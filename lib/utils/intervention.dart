// RDV « Intervention » (vétérinaire) : détartrage, stérilisation… sous
// anesthésie — dépôt le matin, récupération plus tard, consignes avant
// l'intervention, dossier propre. Pas de réservation en ligne.
// Miroir site : website/src/lib/intervention.ts.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/utils/site_api.dart';

const kSousTypesIntervention = <({String key, String label, int duree})>[
  (key: 'detartrage', label: 'Détartrage', duree: 60),
  (key: 'sterilisation', label: 'Stérilisation', duree: 60),
  (key: 'castration', label: 'Castration', duree: 45),
  (key: 'extraction', label: 'Extraction dentaire', duree: 60),
  (key: 'chirurgie', label: 'Chirurgie', duree: 90),
  (key: 'autre', label: 'Autre intervention', duree: 60),
];

String libelleIntervention(String? k) =>
    kSousTypesIntervention.where((t) => t.key == k).firstOrNull?.label ?? 'Intervention';

const _jeun = 'Animal à jeun : dernier repas la veille avant 20 h. L’eau reste à disposition jusqu’au matin.';
/// Textes proposés tant que la clinique n'a pas écrit les siens (profil).
const kConsignesPreopDefaut = <String, String>{
  'detartrage': '$_jeun\nPrévoir la journée : l’animal repart en fin de journée, une fois bien réveillé.',
  'sterilisation': '$_jeun\nPromenade / passage dehors avant de venir.\nApporter une couverture ; prévoir une collerette ou un body pour le retour.',
  'castration': '$_jeun\nPromenade / passage dehors avant de venir.\nPrévoir une collerette pour le retour.',
  'extraction': '$_jeun\nPrévoir la journée : alimentation molle quelques jours après.',
  'chirurgie': '$_jeun\nApporter les traitements en cours et les derniers examens.',
  'autre': _jeun,
};

/// Consignes par défaut de la clinique (sinon les textes ci-dessus).
Future<Map<String, String>> consignesPreopDefaut(String? proProfileId) async {
  final out = Map<String, String>.from(kConsignesPreopDefaut);
  if (proProfileId == null || proProfileId.isEmpty) return out;
  try {
    final r = await Supabase.instance.client.from('consignes_preop_veto').select('consignes')
        .eq('pro_profile_id', proProfileId).maybeSingle();
    final c = (r?['consignes'] as Map?) ?? const {};
    for (final t in kSousTypesIntervention) {
      final v = (c[t.key]?.toString() ?? '').trim();
      if (v.isNotEmpty) out[t.key] = v;
    }
  } catch (_) {}
  return out;
}

Future<bool> enregistrerConsignesPreop(String proProfileId, Map<String, String> consignes) async {
  try {
    await Supabase.instance.client.from('consignes_preop_veto').upsert({
      'pro_profile_id': proProfileId, 'consignes': consignes, 'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'pro_profile_id');
    return true;
  } catch (_) {
    return false;
  }
}

/// Envoie les consignes au propriétaire (notification + e-mail) ; renvoie le message à afficher.
Future<String> envoyerConsignesPreop(String rdvId) async {
  try {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/rdv/consignes-preop'),
        headers: {...await siteApiHeaders(), 'Content-Type': 'application/json'}, body: jsonEncode({'rdvId': rdvId}));
    final j = (jsonDecode(r.body) as Map?) ?? const {};
    if (r.statusCode != 200) return (j['error'] ?? 'Envoi impossible').toString();
    final mail = j['email_envoye'] == true, notif = j['notifie'] == true;
    return 'Consignes envoyées${mail ? ' par e-mail' : ''}${notif ? '${mail ? ' et' : ''} dans l’appli du client' : ''}.';
  } catch (_) {
    return 'Envoi impossible (connexion).';
  }
}

/// Intervention (chirurgies) du RDV : celle de l'animal ce jour-là (CR pré-op
/// fait en consultation avec la date prévue), sinon une nouvelle. Renvoie son id.
Future<String?> lierChirurgieRdv({required String rdvId, required String? animalId, required DateTime dateHeure,
    required String motif, required String proUid, String? proProfileId}) async {
  if (animalId == null || animalId.isEmpty) return null;
  final supa = Supabase.instance.client;
  final d = dateHeure.toLocal();
  final jour = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  try {
    final ex = await supa.from('chirurgies').select('id').eq('animal_id', animalId).eq('date', jour).limit(1).maybeSingle();
    var id = ex?['id']?.toString();
    if (id == null) {
      id = '${DateTime.now().microsecondsSinceEpoch}';
      await supa.from('chirurgies').insert({
        'id': id, 'animal_id': animalId, 'date': jour, 'type': 'chirurgie', 'intitule': motif, 'statut': 'prevu',
        'source': 'veterinaire', 'vet_id': proUid, 'pro_uid': proUid,
        if ((proProfileId ?? '').isNotEmpty) 'pro_profile_id': proProfileId,
      });
    }
    await supa.from('rdv').update({'chirurgie_id': id}).eq('id', rdvId);
    return id;
  } catch (_) {
    return null;
  }
}
