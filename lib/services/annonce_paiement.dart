// Modification / renouvellement d'une annonce publiée : la route du site
// /api/annonces/modifier applique les changements gratuits (photos,
// disponibilité) et renvoie l'URL de paiement Stripe pour le reste
// (4,99 € ; 1 modification = 1 paiement) ou le renouvellement (+30 jours).
// Paiement sur le site (commission Apple / Google) ; le webhook applique.
// Miroir site : website/src/lib/annonce-paiement.ts.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/utils/site_api.dart';

String _prix(num? p) => '${(p ?? 4.99).toStringAsFixed(2).replaceAll('.', ',')} €';

Future<Map<String, dynamic>> _appeler(Map<String, dynamic> body) async {
  final res = await http.post(Uri.parse('$kSiteBaseUrl/api/annonces/modifier'),
      headers: {...await siteApiHeaders(), 'Content-Type': 'application/json'}, body: jsonEncode(body));
  Map<String, dynamic> data;
  try {
    data = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {
    // Page HTML (route absente / site pas à jour) au lieu d'une réponse JSON.
    throw Exception('Le paiement en ligne est momentanément indisponible. Réessayez plus tard.');
  }
  if (data['error'] != null) throw Exception(data['error']);
  return data;
}

// ── Tri des changements (même règle que le serveur :
// website/src/lib/annonce-modification.ts) ─────────────────────────────────
const _techniques = {
  'id', 'uid', 'uid_eleveur', 'profile_id', 'profil_source', 'created_at', 'updated_at', 'vues', 'contacts',
  'is_suspect', 'suspect_reasons', 'boost_until', 'paiement_statut', 'expires_at', 'lat', 'lng', 'latitude', 'longitude',
};
const _verrouilles = {
  'espece', 'espece_autre', 'race', 'sexe', 'type', 'type_vente', 'date_naissance',
  'mere_animal_id', 'mere_nom', 'mere_puce', 'mere_photo_url', 'mere_race', 'mere_lof',
  'pere_animal_id', 'pere_nom', 'pere_puce', 'pere_photo_url', 'pere_race', 'pere_lof', 'etalon_animal_id',
};

/// Valeur comparable : '' = null, nombre en texte = nombre (pas de paiement
/// pour « 350 » vs 350).
dynamic _norm(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t.replaceAll(',', '.'))?.toDouble() ?? t;
  }
  if (v is num) return v.toDouble();
  if (v is List) return v.map(_norm).toList();
  if (v is Map) {
    final m = <String, dynamic>{};
    for (final k in (v.keys.map((e) => e.toString()).toList()..sort())) {
      final x = _norm(v[k]);
      if (x != null) m[k] = x;
    }
    return m;
  }
  return v;
}
bool _egal(dynamic a, dynamic b) => jsonEncode(_norm(a)) == jsonEncode(_norm(b));
List<dynamic> _sansLibres(dynamic p) => p is List
    ? p.map((e) => e is Map ? (Map<String, dynamic>.from(e)..remove('statut')..remove('photos')) : e).toList()
    : const [];

({Map<String, dynamic> libres, Map<String, dynamic> payants}) _trier(
    String table, Map<String, dynamic> actuel, Map<String, dynamic> demande) {
  final libres = <String, dynamic>{}, payants = <String, dynamic>{};
  final expiree = DateTime.tryParse(actuel['expires_at']?.toString() ?? '')?.isBefore(DateTime.now()) ?? false;
  demande.forEach((k, v) {
    if (_techniques.contains(k) || k.endsWith('_eleveur')) return;
    if (table == 'annonces' && _verrouilles.contains(k)) return;
    if (_egal(v, actuel[k])) return;
    if (k == 'statut' && expiree && (v == 'disponible' || v == 'reserve')) return;
    if (k == 'statut' || k == 'photos' || (k == 'animaux_portee' && _egal(_sansLibres(v), _sansLibres(actuel[k])))) {
      libres[k] = v;
    } else {
      payants[k] = v;
    }
  });
  return (libres: libres, payants: payants);
}

Future<void> _ouvrirPaiement(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Issue d'une modification : appliquée tout de suite, en attente de
/// paiement (page de paiement ouverte), ou abandonnée par l'utilisateur.
enum IssueModification { appliquee, paiement, annulee }

Future<IssueModification> enregistrerModificationAnnonce(BuildContext context,
    {required String table, required String id, required Map<String, dynamic> changements}) async {
  final supa = Supabase.instance.client;
  final propres = jsonDecode(jsonEncode(changements)) as Map<String, dynamic>;
  final actuel = await supa.from(table).select().eq('id', id).maybeSingle();
  if (actuel == null) throw Exception('Annonce introuvable.');
  final tri = _trier(table, Map<String, dynamic>.from(actuel), propres);
  // Gratuits (photos, disponibilité, statut des chiots) : enregistrés
  // directement, sans passer par le site.
  if (tri.libres.isNotEmpty) await supa.from(table).update(tri.libres).eq('id', id);
  if (tri.payants.isEmpty) return IssueModification.appliquee;
  final r = await _appeler({'table': table, 'id': id, 'action': 'modification', 'changements': tri.payants});
  if (r['applique'] == true) return IssueModification.appliquee;
  final url = r['url'] as String?;
  if (url == null || !context.mounted) return IssueModification.annulee;
  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('Modification payante', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
    content: Text('Cette modification coûte ${_prix(r['prix'] as num?)}. Les photos et la disponibilité restent gratuites.\n\n'
        'Le paiement s\'effectue sur le site ; vos changements seront appliqués dès le paiement.',
        style: const TextStyle(fontFamily: 'Galey')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0C5C6C)),
        onPressed: () => Navigator.pop(ctx, true),
        child: const Text('Payer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
    ],
  ));
  if (ok != true) return IssueModification.annulee;
  await _ouvrirPaiement(url);
  return IssueModification.paiement;
}

/// Renouvellement payant (+30 jours). true = page de paiement ouverte.
Future<bool> renouvelerAnnoncePayant(BuildContext context, {required String table, required String id}) async {
  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('Renouveler l\'annonce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
    content: Text('Remettre l\'annonce en ligne pour 30 jours (${_prix(null)}).\n\n'
        'Le paiement s\'effectue sur le site ; l\'annonce est prolongée dès le paiement.',
        style: const TextStyle(fontFamily: 'Galey')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0C5C6C)),
        onPressed: () => Navigator.pop(ctx, true),
        child: const Text('Payer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
    ],
  ));
  if (ok != true) return false;
  final r = await _appeler({'table': table, 'id': id, 'action': 'renouvellement'});
  final url = r['url'] as String?;
  if (url == null) return false;
  await _ouvrirPaiement(url);
  return true;
}
