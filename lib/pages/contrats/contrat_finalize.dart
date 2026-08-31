import 'package:supabase_flutter/supabase_flutter.dart';

/// Effets déclenchés quand un contrat `documents_animaux` vient d'être signé par
/// les deux parties. Réplique `website/src/app/signer-contrat/[token]/page.tsx`
/// `signer()` l.425-494 pour que la finalisation soit identique appli / site.
/// Profil (`user_profiles.id`) qui doit recevoir l'animal cédé :
/// `metadata.acquereur_profile_id` en priorité, sinon résolu via la qualité
/// (particulier / éleveur / association), sinon `is_main`.
Future<String?> _acquereurProfileId(
    dynamic supa, Map<String, dynamic> meta, String? acqUid) async {
  final stored = meta['acquereur_profile_id'] as String?;
  if (stored != null && stored.isNotEmpty) return stored;
  if (acqUid == null || acqUid.isEmpty) return null;
  final qualite = (meta['qualite'] as String?) ?? 'particulier';
  final wanted = qualite == 'eleveur'
      ? 'eleveur'
      : qualite == 'refuge' || qualite == 'association' ? 'association' : 'particulier';
  try {
    final byType = await supa.from('user_profiles')
        .select('id').eq('uid', acqUid).eq('profile_type', wanted).maybeSingle();
    if (byType?['id'] != null) return byType!['id'] as String;
    final main = await supa.from('user_profiles')
        .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
    return main?['id'] as String?;
  } catch (_) {
    return null;
  }
}

Future<void> finalizeContratSigne({
  required Map<String, dynamic> doc,
  required Map<String, dynamic>? animal,
}) async {
  final supa = Supabase.instance.client;
  final type = doc['type'] as String? ?? '';
  final animalId = doc['animal_id'] as String?;
  final meta = (doc['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
  final now = DateTime.now().toIso8601String();
  final today = now.split('T').first;

  // ── Transfert de propriété (contrat de vente / certificat de cession) ──
  if ((type == 'contrat_vente' || type == 'certificat_cession') && animalId != null) {
    try {
      // L'appli pose 'cession_en_cours', le site 'en_attente_cession' — accepter
      // les deux, sinon le contrat signé n'entraînait aucun transfert (appli).
      final ceded = await supa.from('animaux')
          .update({'statut': 'sorti'})
          .eq('id', animalId)
          .inFilter('statut', ['en_attente_cession', 'cession_en_cours'])
          .select('uid_eleveur, uid_acquereur, date_sortie')
          .maybeSingle();
      // Marquer la cession correspondante comme confirmée
      try {
        await supa.from('cessions')
            .update({'statut': 'confirme', 'confirmed_at': now})
            .eq('animal_id', animalId)
            .inFilter('statut', ['en_attente_acquereur', 'signe_acquereur']);
      } catch (_) {}
      if (ceded != null) {
        final dateCession = (ceded['date_sortie'] as String?) ?? today;
        final cedantUid = ceded['uid_eleveur'] as String?;
        final acqUid = ceded['uid_acquereur'] as String?;
        if (cedantUid != null) {
          await supa.from('animaux_proprietes')
              .update({'date_fin': dateCession})
              .eq('animal_id', animalId)
              .eq('uid_proprio', cedantUid)
              .isFilter('date_fin', null);
        }
        if (acqUid != null) {
          final acqProfileId = await _acquereurProfileId(supa, meta, acqUid);
          await supa.from('animaux_proprietes').upsert({
            'animal_id': animalId,
            'uid_proprio': acqUid,
            'date_debut': dateCession,
            'date_fin': null,
            'profile_id_proprio': acqProfileId,
          }, onConflict: 'animal_id,uid_proprio');
          // Garder animaux.profile_id_acquereur cohérent
          if (acqProfileId != null) {
            try {
              await supa.from('animaux')
                  .update({'profile_id_acquereur': acqProfileId}).eq('id', animalId);
            } catch (_) {}
          }
          // Prévenir l'acquéreur que l'animal est désormais dans son compte
          try {
            await supa.from('notifications').insert({
              'uid': acqUid,
              'type': 'cession_confirmee',
              'title': '🐾 Animal transféré',
              'body': 'Le contrat est signé — l\'animal apparaît maintenant dans votre compte.',
              if (acqProfileId != null) 'profile_id': acqProfileId,
              'data': {'animalId': animalId},
              'read': false,
            });
          } catch (_) {}
        }
      }
    } catch (_) {/* pas bloquant */}
  }

  // ── Adoption association → animal adopté ──
  if (type == 'contrat_adoption' && animalId != null) {
    try {
      await supa.from('animaux').update({'statut': 'adopte'}).eq('id', animalId);
    } catch (_) {}
  }
}

/// Notifie l'autre partie après une signature (partielle ou complète).
/// [role] = 'eleveur' | 'acquereur' (celui qui vient de signer).
Future<void> notifierContratSignature({
  required Map<String, dynamic> doc,
  required String role,
  required bool bothSigned,
}) async {
  final supa = Supabase.instance.client;
  final meta = (doc['metadata'] as Map?) ?? {};
  final type = doc['type'] as String? ?? '';
  final isAdoption = type == 'contrat_adoption';
  final titre = (doc['titre'] as String?) ?? 'le contrat';
  final acqNom = (meta['acquereur_nom'] as String?) ??
      (isAdoption ? 'L\'adoptant(e)' : 'L\'acquéreur');
  final partieVendeur = isAdoption ? 'L\'association' : 'L\'éleveur';
  final eleveurUid = doc['uid_eleveur'] as String?;
  var acqUid = meta['acquereur_uid'] as String? ?? doc['uid_acquereur'] as String?;
  // Repli : retrouver l'acquéreur PetsMatch via son email si l'uid manque
  // (contrats créés avant l'ajout de uid_acquereur).
  if (acqUid == null || acqUid.isEmpty) {
    final email = (meta['acquereur_email'] as String?)?.trim();
    if (email != null && email.isNotEmpty) {
      try {
        final u = await supa.from('users').select('uid').eq('email', email).maybeSingle();
        acqUid = u?['uid'] as String?;
      } catch (_) {}
    }
  }
  final token = doc['token'] as String?;
  final signingUrl = token != null ? 'https://petsmatchapp.com/signer-contrat/$token' : null;
  final data = {
    if (token != null) 'token': token,
    'documentId': doc['id'],
    // `url` : lu par le routeur de notifs du site (Header.getNotifUrl).
    if (signingUrl != null) 'url': signingUrl,
    if (signingUrl != null) 'signingUrl': signingUrl,
  };

  // Profil de l'acquéreur (celui qui recevra l'animal) pour cibler la notif.
  final acqProfileId = await _acquereurProfileId(supa, meta.cast<String, dynamic>(), acqUid);

  Future<void> notif(String? uid, String type, String title, String body) async {
    if (uid == null || uid.isEmpty) return;
    try {
      String? profId = (uid == acqUid) ? acqProfileId : null;
      if (profId == null) {
        final prof = await supa.from('user_profiles')
            .select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
        profId = prof?['id'] as String?;
      }
      await supa.from('notifications').insert({
        'uid': uid,
        'type': type,
        'title': title,
        'body': body,
        if (profId != null) 'profile_id': profId,
        'data': data,
        'read': false,
      });
    } catch (_) {}
  }

  if (bothSigned) {
    const complet = 'est désormais signé par les deux parties.';
    await notif(eleveurUid, 'contrat_signe_complet', '✅ Contrat signé !', '$titre $complet');
    if (acqUid != eleveurUid) {
      await notif(acqUid, 'contrat_signe_complet', '✅ Contrat signé !', '$titre $complet');
    }
  } else if (role == 'acquereur') {
    await notif(eleveurUid, 'contrat_signe_acquereur', '✍️ Signature reçue',
        '$acqNom a signé $titre — à vous de signer pour finaliser.');
  } else {
    await notif(acqUid, 'contrat_signe_eleveur', '✍️ $partieVendeur a signé',
        '$partieVendeur a signé $titre — à vous de signer pour finaliser.');
  }
}
