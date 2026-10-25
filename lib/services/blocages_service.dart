import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Utilisateurs bloqués — source de vérité : table Supabase `bloquages`
/// (messagerie, appli + site). L'ancienne liste Firestore `bloquer/{uid}`
/// (fil d'actualité historique) est encore lue et tenue à jour pour ne perdre
/// aucun blocage passé. Miroir de website/src/lib/blocages.ts.
class Blocages {
  static final _supa = Supabase.instance.client;

  static String? get _moi => FirebaseAuth.instance.currentUser?.uid;

  /// Bloque [autreUid]. Déjà bloqué : rien ne change, aucune erreur.
  static Future<void> bloquer(String autreUid) async {
    final moi = _moi;
    if (moi == null || autreUid.isEmpty || autreUid == moi) return;
    await _supa.from('bloquages').upsert(
      {'uid': moi, 'blocked_uid': autreUid},
      onConflict: 'uid,blocked_uid',
      ignoreDuplicates: true,
    );
    try {
      await FirebaseFirestore.instance.collection('bloquer').doc(moi)
          .set({autreUid: true}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Débloque [autreUid] des deux listes.
  static Future<void> debloquer(String autreUid) async {
    final moi = _moi;
    if (moi == null) return;
    await _supa.from('bloquages').delete().eq('uid', moi).eq('blocked_uid', autreUid);
    try {
      await FirebaseFirestore.instance.collection('bloquer').doc(moi)
          .update({autreUid: FieldValue.delete()});
    } catch (_) {}
  }

  /// Uids que j'ai bloqués (les deux listes réunies).
  static Future<Set<String>> mesBloques() async {
    final moi = _moi;
    if (moi == null) return {};
    final ids = <String>{};
    try {
      final rows = await _supa.from('bloquages').select('blocked_uid').eq('uid', moi);
      ids.addAll((rows as List).map((r) => r['blocked_uid'].toString()));
    } catch (_) {}
    try {
      final snap = await FirebaseFirestore.instance.collection('bloquer').doc(moi).get();
      if (snap.exists) ids.addAll((snap.data() ?? {}).entries.where((e) => e.value == true).map((e) => e.key));
    } catch (_) {}
    ids.remove(moi);
    return ids;
  }
}
