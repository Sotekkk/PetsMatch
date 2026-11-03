// Propriétaire / client porté sur les documents médicaux (compte rendu,
// ordonnance, comptes rendus d'intervention) : nom ET coordonnées (adresse,
// téléphone, e-mail), avec la même cascade que la facture — coordonnées de
// facturation PetsMatch (pm_client_facturation), sinon fichier clients de la
// clinique, sinon client saisi sur le RDV. Miroir site :
// website/src/lib/client-document.ts.

import 'package:supabase_flutter/supabase_flutter.dart';

typedef ClientDocument = ({String nom, List<String> coord, String? email});

String _v(dynamic x) => x?.toString().trim() ?? '';

List<String> _lignes(dynamic rue, dynamic cp, dynamic ville, dynamic tel, dynamic email) {
  final villeTxt = '${_v(cp)} ${_v(ville)}'.trim();
  return [
    [_v(rue), villeTxt].where((x) => x.isNotEmpty).join(', '),
    if (_v(tel).isNotEmpty) 'Tél. ${_v(tel)}',
    _v(email),
  ].where((x) => x.isNotEmpty).toList();
}

Future<ClientDocument> clientDocument(String animalId, {String? rdvId, String? clientProfileId}) async {
  final supa = Supabase.instance.client;
  Map<String, dynamic>? rdv;
  if (rdvId != null && rdvId.isNotEmpty) {
    try {
      rdv = await supa.from('rdv').select('client_profile_id, client_nom_manuel, client_email_manuel, client_telephone_manuel')
          .eq('id', rdvId).maybeSingle();
    } catch (_) {}
  }
  final profil = clientProfileId ?? (_v(rdv?['client_profile_id']).isEmpty ? null : _v(rdv?['client_profile_id']));

  // 1. Client PetsMatch : coordonnées de facturation.
  try {
    final j = await supa.rpc('pm_client_facturation', params: {
      'p_animal_id': animalId, if (profil != null) 'p_client_profile_id': profil,
    });
    // « societe » est un indicateur (vrai / faux) : le nom de la structure est dans « nom ».
    if (j is Map && (_v(j['nom']).isNotEmpty || _v(j['prenom']).isNotEmpty)) {
      final nom = j['societe'] == true ? _v(j['nom']) : '${_v(j['prenom'])} ${_v(j['nom'])}'.trim();
      return (nom: nom, coord: _lignes(j['rue'], j['code_postal'], j['ville'], j['telephone'], j['email']),
          email: _v(j['email']).isEmpty ? null : _v(j['email']));
    }
  } catch (_) {}
  // 2. Client du fichier de la clinique (sans compte PetsMatch).
  Map<String, dynamic>? a;
  try {
    a = await supa.from('animaux').select('client_clinique_id, uid_proprietaire').eq('id', animalId).maybeSingle();
    if (_v(a?['client_clinique_id']).isNotEmpty) {
      final cc = await supa.from('clients_clinique').select('nom, prenom, email, telephone, adresse, code_postal, ville')
          .eq('id', a!['client_clinique_id']).maybeSingle();
      if (cc != null) {
        return (nom: '${_v(cc['prenom'])} ${_v(cc['nom'])}'.trim(),
            coord: _lignes(cc['adresse'], cc['code_postal'], cc['ville'], cc['telephone'], cc['email']),
            email: _v(cc['email']).isEmpty ? null : _v(cc['email']));
      }
    }
  } catch (_) {}
  // 3. Client saisi sur le RDV.
  if (_v(rdv?['client_nom_manuel']).isNotEmpty) {
    return (nom: _v(rdv!['client_nom_manuel']), coord: _lignes('', '', '', rdv['client_telephone_manuel'], rdv['client_email_manuel']),
        email: _v(rdv['client_email_manuel']).isEmpty ? null : _v(rdv['client_email_manuel']));
  }
  // 4. Nom du compte propriétaire.
  if (_v(a?['uid_proprietaire']).isNotEmpty) {
    try {
      final u = await supa.from('users_complet').select('firstname, lastname').eq('uid', a!['uid_proprietaire']).maybeSingle();
      return (nom: '${_v(u?['firstname'])} ${_v(u?['lastname'])}'.trim(), coord: <String>[], email: null);
    } catch (_) {}
  }
  return (nom: '', coord: <String>[], email: null);
}
