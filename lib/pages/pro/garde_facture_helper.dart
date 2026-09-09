import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Helpers partagés pour facturer une prestation de garde depuis un `rdv`
/// (registre des visites ET agenda pro). La facture elle-même passe par le
/// moteur commun conforme (`CreerFacturePage` / table `factures`).

/// Clé de prestation garde (`tarifs_garde` / `tarifs_clients_garde.prestation_type`)
/// déduite du motif du RDV.
String gardePrestationKey(String? motif) {
  final m = (motif ?? '').toLowerCase();
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

/// Nom du client tel que stocké selon la page appelante (`_client_nom` côté
/// registre, `_client_name` côté agenda).
String? gardeClientNom(Map<String, dynamic> rdv) =>
    (rdv['_client_nom'] ?? rdv['_client_name'] ?? rdv['client_nom_manuel'])?.toString();

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
