import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart';

/// Helpers partagés pour facturer une prestation de garde depuis un `rdv`
/// (registre des visites ET agenda pro). La facture elle-même passe par le
/// moteur commun conforme (`CreerFacturePage` / table `factures`).

/// Clé de prestation garde (`tarifs_garde` / `tarifs_clients_garde.prestation_type`)
/// déduite du motif du RDV.
String gardePrestationKey(String? motif) {
  final m = (motif ?? '').toLowerCase();
  if (m.contains('visite')) return 'visite';
  if (m.contains('promenade') && m.contains('30')) return 'promenade_30min';
  if (m.contains('promenade') && m.contains('2')) return 'promenade_2h';
  if (m.contains('promenade')) return 'promenade_1h';
  if (m.contains('garde') || m.contains('journ')) return 'garde_journee';
  return 'autre';
}

/// Désignation de la ligne de facture (« motif — Animal »).
String gardeDesignation(Map<String, dynamic> rdv) {
  final motif = (rdv['motif'] ?? '').toString().trim();
  final animal = (rdv['_animal_nom'] ?? rdv['animal_nom'] ?? rdv['_animal_name'] ?? '').toString().trim();
  final base = motif.isNotEmpty ? motif : 'Prestation de garde';
  return animal.isNotEmpty ? '$base — $animal' : base;
}

/// Libellé d'affichage d'un motif de garde, adapté à l'espèce : pour un équidé,
/// « Promenade … » devient « Sortie au paddock … ». **Affichage uniquement** —
/// la clé (`promenade_*`) et la valeur stockée dans `rdv.motif` ne changent pas,
/// donc la facturation (`gardePrestationKey`) et les rapports restent intacts.
String gardeMotifLabel(String keyOrLabel, String? espece) {
  final e = (espece ?? '').toLowerCase().trim();
  final isEquide = e == 'cheval' || e == 'poney' || e == 'ane' || e == 'âne';
  const fallback = <String, String>{
    'promenade_30min': 'Promenade 30 min', 'promenade_1h': 'Promenade 1h',
    'promenade_2h': 'Promenade 2h', 'visite_domicile': 'Visite à domicile',
    'garde_journee': 'Garde journée',
  };
  final base = fallback[keyOrLabel] ?? keyOrLabel;
  if (!isEquide) return base;
  final s = base.toLowerCase();
  if (!s.contains('promenade') && !s.contains('balade')) return base;
  if (s.contains('30')) return 'Sortie au paddock (30 min)';
  if (s.contains('2')) return 'Sortie au paddock (2 h)';
  return 'Sortie au paddock (1 h)';
}

/// Nom du client tel que stocké selon la page appelante (`_client_nom` côté
/// registre, `_client_name` côté agenda).
String? gardeClientNom(Map<String, dynamic> rdv) =>
    (rdv['_client_nom'] ?? rdv['_client_name'] ?? rdv['client_nom_manuel'])?.toString();

/// true si le RDV est une garde-journée (facturable « à la journée »,
/// candidate au regroupement multi-jours).
bool estGardeJournee(Map<String, dynamic> rdv) {
  final m = (rdv['motif'] ?? '').toString().toLowerCase();
  return m.contains('garde') && (m.contains('journ') || m.contains('journée'));
}

/// Jours d'une même garde encore non facturés (mêmes client + animal, motif
/// garde-journée, statut confirmé/terminé, `facture_id` nul), triés par date.
/// Inclut [rdv] lui-même. Retourne `[rdv]` si ce n'est pas une garde-journée.
Future<List<Map<String, dynamic>>> gardeJoursAFacturer(Map<String, dynamic> rdv) async {
  if (!estGardeJournee(rdv)) return [rdv];
  final supa = Supabase.instance.client;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final pid = User_Info.activeProfileId;
  final clientUid = rdv['client_uid']?.toString();
  final animalId = rdv['animal_id']?.toString();
  if (uid == null || clientUid == null || clientUid.isEmpty) return [rdv];
  try {
    var q = supa.from('rdv').select().eq('pro_uid', uid).eq('client_uid', clientUid);
    if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
    if (animalId != null && animalId.isNotEmpty) q = q.eq('animal_id', animalId);
    final rows = await q
        .inFilter('statut', ['confirme', 'termine'])
        .isFilter('facture_id', null)
        .order('date_heure', ascending: true);
    final jours = [
      for (final r in rows as List)
        if (estGardeJournee(Map<String, dynamic>.from(r as Map)))
          Map<String, dynamic>.from(r),
    ];
    // Garde le nom d'animal résolu par l'appelant.
    for (final j in jours) {
      if ((j['_animal_nom'] ?? '').toString().isEmpty) {
        j['_animal_nom'] = rdv['_animal_nom'] ?? rdv['animal_nom'] ?? '';
      }
    }
    return jours.isEmpty ? [rdv] : jours;
  } catch (_) {
    return [rdv];
  }
}

/// Libellé « du JJ/MM au JJ/MM » (ou « le JJ/MM » si un seul jour).
String gardePeriodeLabel(List<Map<String, dynamic>> jours) {
  final dates = jours
      .map((j) => DateTime.tryParse(j['date_heure']?.toString() ?? ''))
      .whereType<DateTime>()
      .toList()
    ..sort();
  if (dates.isEmpty) return '';
  final f = DateFormat('dd/MM', 'fr_FR');
  if (dates.length == 1) return 'le ${f.format(dates.first)}';
  return 'du ${f.format(dates.first)} au ${f.format(dates.last)}';
}

/// Prix HT (€) : surcharge client (`tarifs_clients_garde`) sinon tarif standard
/// (`user_profiles.tarifs_garde`) sinon 0.
Future<double> gardeTarif(Map<String, dynamic> rdv) async {
  final supa = Supabase.instance.client;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final pid = User_Info.activeProfileId;
  if (uid == null || pid.isEmpty) return 0;
  final key = gardePrestationKey(rdv['motif']?.toString());
  final ownerPid = rdv['client_profile_id']?.toString();
  try {
    if (ownerPid != null && ownerPid.isNotEmpty) {
      final o = await supa.from('tarifs_clients_garde')
          .select('prix')
          .eq('pro_uid', uid)
          .eq('pro_profile_id', pid)
          .eq('owner_profile_id', ownerPid)
          .eq('prestation_type', key)
          .maybeSingle();
      final p = (o?['prix'] as num?)?.toDouble();
      if (p != null && p > 0) return p;
    }
    final prof = await supa.from('user_profiles')
        .select('tarifs_garde').eq('id', pid).maybeSingle();
    final tg = prof?['tarifs_garde'];
    if (tg is Map) {
      final p = (tg[key] as num?)?.toDouble();
      if (p != null) return p;
    }
  } catch (_) {}
  return 0;
}

/// Ouvre la facturation d'une prestation de garde depuis un `rdv`.
/// Une garde-journée étalée sur plusieurs jours non facturés propose de
/// facturer toute la période en une seule facture (une ligne, quantité = N).
Future<void> facturerGardeDepuisRdv(BuildContext context, Map<String, dynamic> rdv) async {
  final jours = await gardeJoursAFacturer(rdv);
  if (!context.mounted) return;

  var rdvsAFacturer = <Map<String, dynamic>>[rdv];
  if (jours.length > 1) {
    final periode = gardePeriodeLabel(jours);
    final choix = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text(
                'Cette garde couvre ${jours.length} jours ($periode).',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined, color: Color(0xFF0C5C6C)),
            title: Text('Facturer les ${jours.length} jours', style: const TextStyle(fontFamily: 'Galey')),
            subtitle: const Text('Une seule facture pour toute la période', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            onTap: () => Navigator.pop(ctx, 'tous'),
          ),
          ListTile(
            leading: const Icon(Icons.today_outlined, color: Color(0xFF0C5C6C)),
            title: const Text('Facturer ce jour seulement', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, 'un'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choix == null || !context.mounted) return;
    if (choix == 'tous') rdvsAFacturer = jours;
  }

  final n = rdvsAFacturer.length;
  final prixJour = await gardeTarif(rdv);
  if (!context.mounted) return;

  final designation = n > 1
      ? 'Garde à domicile — $n jours (${gardePeriodeLabel(rdvsAFacturer)})'
      : gardeDesignation(rdv);

  await Navigator.push(context, MaterialPageRoute(
    builder: (_) => CreerFacturePage(
      clientNom: gardeClientNom(rdv),
      clientEmail: (rdv['_client_email'] ?? rdv['client_email_manuel'])?.toString(),
      lignesPrefill: [
        FacturePrefillLigne(designation: designation, prixHT: prixJour, quantite: n.toDouble(), tauxTVA: 20),
      ],
      sourceRdvId: rdv['id']?.toString(),
      sourceRdvIds: rdvsAFacturer.map((r) => r['id']?.toString() ?? '').where((s) => s.isNotEmpty).toList(),
      sourceAnimalId: rdv['animal_id']?.toString(),
      clientUid: rdv['client_uid']?.toString(),
      clientProfileId: rdv['client_profile_id']?.toString(),
    ),
  ));
}
