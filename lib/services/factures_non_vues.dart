// Bulle rouge « nouvelle facture » côté client (Administratif → Mes Factures).
// Non vue = facture reçue après la dernière ouverture de « Mes Factures »
// (table factures_vues, partagée avec le site — migration_factures_vues.sql).
// Même filtre que MesFacturesParticulierPage : client_profile_id du profil
// actif, sinon client_uid. Miroir site : website/src/lib/factures-non-vues.ts.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

class FacturesNonVues {
  static final compteur = ValueNotifier<int>(0);

  /// Sans ouverture enregistrée : seules les factures des 30 derniers jours.
  static const _fenetre = Duration(days: 30);

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static String _cle(String uid) =>
      User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : uid;

  /// Date de la dernière ouverture de « Mes Factures » (UTC ISO), sinon la
  /// limite des 30 jours.
  static Future<String> derniereVue() async {
    final uid = _uid;
    final defaut = DateTime.now().toUtc().subtract(_fenetre).toIso8601String();
    if (uid == null) return defaut;
    try {
      final r = await Supabase.instance.client.from('factures_vues')
          .select('vu_le').eq('cle', _cle(uid)).maybeSingle();
      return r?['vu_le']?.toString() ?? defaut;
    } catch (_) {
      return defaut;
    }
  }

  static Future<void> rafraichir() async {
    final uid = _uid;
    if (uid == null) { compteur.value = 0; return; }
    try {
      final depuis = await derniereVue();
      final supa = Supabase.instance.client;
      var q = supa.from('factures').select('id').gt('created_at', depuis).neq('statut', 'annulee');
      q = User_Info.activeProfileId.isNotEmpty
          ? q.eq('client_profile_id', User_Info.activeProfileId)
          : q.eq('client_uid', uid);
      final rows = await q;
      compteur.value = (rows as List).length;
    } catch (_) {}
  }

  static Future<void> marquerVues() async {
    final uid = _uid;
    if (uid == null) return;
    compteur.value = 0;
    try {
      await Supabase.instance.client.from('factures_vues').upsert({
        'cle': _cle(uid), 'uid': uid, 'vu_le': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }
}
