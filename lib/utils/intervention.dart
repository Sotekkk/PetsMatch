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

/// Suivi de la journée au propriétaire ('reveille' | 'pret' | 'recuperation') :
/// notification (appli), sinon e-mail, sinon message « appelez-le au … ».
Future<String> messageIntervention(String rdvId, String message) async {
  try {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/rdv/consignes-preop'),
        headers: {...await siteApiHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'rdvId': rdvId, 'message': message}));
    final j = (jsonDecode(r.body) as Map?) ?? const {};
    if (j['notifie'] == true) return 'Client prévenu dans l\u2019appli.';
    if (j['email_envoye'] == true) return 'Client prévenu par e-mail.';
    return (j['error'] ?? 'Envoi impossible.').toString();
  } catch (_) {
    return 'Envoi impossible (connexion).';
  }
}

/// Interventions de l'animal (récentes d'abord) : choisir le CR pré-op à reprendre.
Future<List<Map<String, dynamic>>> chirurgiesAnimal(String animalId) async {
  try {
    return List<Map<String, dynamic>>.from(await Supabase.instance.client.from('chirurgies')
        .select('id, date, intitule, preop, operatoire').eq('animal_id', animalId).order('date', ascending: false).limit(15));
  } catch (_) {
    return [];
  }
}

/// Rattache le RDV à une autre intervention (CR pré-op existant), datée du jour
/// de l'intervention ; l'ancienne, restée vide, est supprimée. null si OK.
Future<String?> rattacherChirurgie({required String rdvId, required DateTime dateHeure, String? ancienneId, required String chirurgieId}) async {
  final supa = Supabase.instance.client;
  final d = dateHeure.toLocal();
  final jour = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  try {
    await supa.from('chirurgies').update({'date': jour}).eq('id', chirurgieId);
    await supa.from('rdv').update({'chirurgie_id': chirurgieId}).eq('id', rdvId);
    if (ancienneId != null && ancienneId != chirurgieId) {
      final a = await supa.from('chirurgies').select('preop, operatoire, consignes').eq('id', ancienneId).maybeSingle();
      if (a != null && a['preop'] == null && a['operatoire'] == null && a['consignes'] == null) {
        await supa.from('chirurgies').delete().eq('id', ancienneId);
      }
    }
    return null;
  } catch (e) {
    return e.toString();
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
    // Sinon : CR préopératoire récent de l'animal (consultation des jours
    // précédents), pas encore opéré — repris et daté du jour de l'intervention.
    if (id == null) {
      final depuis = d.subtract(const Duration(days: 60));
      final recents = await supa.from('chirurgies').select('id, preop, operatoire').eq('animal_id', animalId)
          .gte('date', '${depuis.year}-${depuis.month.toString().padLeft(2, '0')}-${depuis.day.toString().padLeft(2, '0')}')
          .order('date', ascending: false).limit(10);
      final c = (recents as List).where((x) => x['preop'] != null && x['operatoire'] == null).firstOrNull;
      if (c != null) {
        id = c['id'].toString();
        await supa.from('chirurgies').update({'date': jour}).eq('id', id);
      }
    }
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
