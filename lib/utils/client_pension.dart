// Client d'un séjour en pension (pension_entrees) : la demande de séjour, sinon
// le propriétaire de la fiche (animaux_proprietes, profil EXACT — un élevage qui
// met un animal en pension reste l'élevage, jamais is_main). Coordonnées : le
// profil, sinon le compte (users_complet), sinon ce qui est saisi sur le séjour.
// Utilisé par la facture et le contrat d'hébergement. Miroir site :
// website/src/lib/client-pension.ts.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClientPension {
  final String? uid, profileId;
  final bool estPro;
  final String prenom, nom, email, tel, rue, cp, ville;
  const ClientPension({this.uid, this.profileId, this.estPro = false, this.prenom = '', this.nom = '',
      this.email = '', this.tel = '', this.rue = '', this.cp = '', this.ville = ''});

  String get nomComplet => '$prenom $nom'.trim();
  String get adresse => [rue, [cp, ville].where((x) => x.isNotEmpty).join(' ')].where((x) => x.isNotEmpty).join(', ');
}

Future<ClientPension> clientDuSejour(Map<String, dynamic> e) async {
  final supa = Supabase.instance.client;
  final moi = FirebaseAuth.instance.currentUser?.uid;
  String t(dynamic v) => (v?.toString() ?? '').trim();
  String premier(List<dynamic> v) => v.map(t).firstWhere((x) => x.isNotEmpty, orElse: () => '');

  String? uid, pid;
  try {
    final dem = await supa.from('pension_demandes').select('client_uid, client_profile_id')
        .or('entree_id.eq.${e['id']},essai_entree_id.eq.${e['id']}').limit(1).maybeSingle();
    if (t(dem?['client_uid']).isNotEmpty) uid = t(dem?['client_uid']);
    if (t(dem?['client_profile_id']).isNotEmpty) pid = t(dem?['client_profile_id']);
  } catch (_) {}
  final animalId = t(e['animal_id']);
  if (uid == null && animalId.isNotEmpty) {
    try {
      final rows = List<Map<String, dynamic>>.from(await supa.from('animaux_proprietes')
          .select('uid_proprio, profile_id_proprio, role_proprio').eq('animal_id', animalId).isFilter('date_fin', null));
      rows.removeWhere((r) => t(r['uid_proprio']) == moi);
      rows.sort((a, b) => (a['role_proprio'] == 'principal' ? 0 : 1).compareTo(b['role_proprio'] == 'principal' ? 0 : 1));
      if (rows.isNotEmpty) {
        uid = t(rows.first['uid_proprio']);
        pid = t(rows.first['profile_id_proprio']).isEmpty ? null : t(rows.first['profile_id_proprio']);
      }
    } catch (_) {}
  }

  Map<String, dynamic>? prof, compte;
  if (pid != null) {
    try {
      prof = await supa.from('user_profiles_complet')
          .select('profile_type, nom, firstname, lastname, phone_number, phone, telephone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro, adresse, adresse_pro')
          .eq('id', pid).maybeSingle();
    } catch (_) {}
  }
  if (uid != null) {
    try {
      compte = await supa.from('users_complet')
          .select('firstname, lastname, email, phone_number, rue, code_postal, ville, adress').eq('uid', uid).maybeSingle();
    } catch (_) {}
  }

  final type = t(prof?['profile_type']);
  final estPro = type.isNotEmpty && type != 'particulier';
  final contact = t(e['proprietaire_contact']);
  var prenom = estPro ? '' : premier([prof?['firstname'], compte?['firstname']]);
  var nom = estPro ? premier([prof?['nom']]) : premier([prof?['lastname'], compte?['lastname']]);
  if (prenom.isEmpty && nom.isEmpty) nom = premier([e['proprietaire_nom'], prof?['nom']]);
  final rue = estPro ? premier([prof?['rue_pro'], prof?['rue']]) : premier([prof?['rue'], compte?['rue']]);
  final cp = estPro ? premier([prof?['code_postal_pro'], prof?['code_postal']]) : premier([prof?['code_postal'], compte?['code_postal']]);
  final ville = estPro ? premier([prof?['ville_pro'], prof?['ville']]) : premier([prof?['ville'], compte?['ville']]);
  // Téléphone utilisable (pas le « 0000000000 » des anciens profils).
  String telValide(Object? v) => RegExp(r'^0+$').hasMatch(t(v).replaceAll(RegExp(r'\D'), '')) ? '' : t(v);
  // Adresse la plus complète connue : rue avec numéro, code postal, ville
  // (profil, compte, adresse saisie d'un bloc sur le profil ou le séjour).
  int scoreChamps(String r, String c, String v) =>
      (r.isNotEmpty ? 1 : 0) + (RegExp(r'\d').hasMatch(r) ? 1 : 0) + (c.isNotEmpty ? 1 : 0) + (v.isNotEmpty ? 1 : 0);
  int scoreBloc(String b) =>
      (b.isNotEmpty ? 1 : 0) + (RegExp(r'\d').hasMatch(b.replaceFirst(RegExp(r'\b\d{5}\b'), '')) ? 1 : 0) +
      (RegExp(r'\b\d{5}\b').hasMatch(b) ? 1 : 0) + (b.split(RegExp(r'[\s,]+')).where((x) => x.isNotEmpty).length >= 3 ? 1 : 0);
  var aRue = rue, aCp = cp, aVille = ville;
  var score = scoreChamps(rue, cp, ville);
  for (final b in (estPro ? [prof?['adresse_pro'], prof?['adresse'], e['proprietaire_adresse']] : [prof?['adresse'], compte?['adress'], e['proprietaire_adresse']]).map(t)) {
    if (scoreBloc(b) > score) { aRue = b; aCp = ''; aVille = ''; score = scoreBloc(b); }
  }
  return ClientPension(
    uid: uid, profileId: pid, estPro: estPro, prenom: prenom, nom: nom,
    email: premier([prof?['email_contact'], e['proprietaire_email'], contact.contains('@') ? contact : null, compte?['email']]),
    tel: premier([telValide(prof?['phone_number']), telValide(prof?['phone']), telValide(prof?['telephone']),
      contact.contains('@') ? null : telValide(contact), telValide(compte?['phone_number'])]),
    rue: aRue, cp: aCp, ville: aVille,
  );
}
