import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../onboarding_theme.dart';

/// Configuration guidée d'une association : créer un premier hébergement
/// (chenil / enclos) ou une première famille d'accueil, puis y placer un
/// animal du refuge — sans quitter l'onboarding. Facultatif.

const _sorties = ['adopte', 'transfere', 'decede'];

/// Animaux du refuge encore sans hébergement ni famille d'accueil.
Future<List<Map<String, dynamic>>> _animauxAPlacer() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return [];
  final rows = await Supabase.instance.client.from('animaux')
      .select('id, nom, espece, statut, enclos_id, fa_id')
      .eq('uid_eleveur', uid).eq('is_association', true)
      .isFilter('enclos_id', null).isFilter('fa_id', null)
      .order('nom', ascending: true);
  return List<Map<String, dynamic>>.from(rows as List)
      .where((a) => !_sorties.contains(a['statut']?.toString())).toList();
}

InputDecoration _deco(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Choix des animaux à placer (jusqu'à [max]) — retourne leurs identifiants.
Future<List<String>> _choisirAnimaux(BuildContext context, String lieu, int max) async {
  final animaux = await _animauxAPlacer();
  if (!context.mounted || animaux.isEmpty) return [];
  final choisis = <String>{};
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Placer un animal dans « $lieu » ?', style: OnboardingTheme.title.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        Text(max > 1 ? 'Jusqu\'à $max animaux.' : 'Un animal.', style: OnboardingTheme.body.copyWith(fontSize: 13)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
          child: ListView(shrinkWrap: true, children: [
            for (final a in animaux)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: OnboardingTheme.teal,
                value: choisis.contains(a['id'].toString()),
                title: Text(a['nom']?.toString() ?? 'Animal', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                subtitle: Text(a['espece']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                onChanged: (v) => setS(() {
                  final id = a['id'].toString();
                  if (v == true) {
                    if (choisis.length < max) choisis.add(id);
                  } else {
                    choisis.remove(id);
                  }
                }),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: choisis.isEmpty ? null : () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: OnboardingTheme.teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Placer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard', style: OnboardingTheme.skipButtonStyle)),
      ]),
    ))),
  );
  return ok == true ? choisis.toList() : [];
}

/// Chenil : créer un hébergement puis y placer des animaux. true si créé.
Future<bool> guiderChenil(BuildContext context, {required String? profileId}) async {
  final nomCtrl = TextEditingController(text: 'Box 1');
  var type = 'box';
  var capacite = 1;
  final cree = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Votre premier hébergement', style: OnboardingTheme.title.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        Text('Box, enclos, chatterie… vous pourrez en ajouter d\'autres ensuite.', style: OnboardingTheme.body.copyWith(fontSize: 13)),
        const SizedBox(height: 14),
        TextField(controller: nomCtrl, decoration: _deco('Nom (ex : Box 1, Chatterie A, Quarantaine)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: _deco('Type'),
          items: const [
            DropdownMenuItem(value: 'box', child: Text('🏠 Box')),
            DropdownMenuItem(value: 'enclos', child: Text('🌿 Enclos')),
            DropdownMenuItem(value: 'chatterie', child: Text('🐈 Chatterie')),
            DropdownMenuItem(value: 'cage', child: Text('🔲 Cage')),
          ],
          onChanged: (v) => setS(() => type = v ?? 'box'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Capacité', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600))),
          IconButton(onPressed: capacite > 1 ? () => setS(() => capacite--) : null,
              icon: const Icon(Icons.remove_circle_outline, color: OnboardingTheme.teal)),
          Text('$capacite', style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700)),
          IconButton(onPressed: () => setS(() => capacite++),
              icon: const Icon(Icons.add_circle_outline, color: OnboardingTheme.teal)),
        ]),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, nomCtrl.text.trim().isNotEmpty),
          style: ElevatedButton.styleFrom(backgroundColor: OnboardingTheme.teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Créer l\'hébergement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ]),
    ))),
  );
  if (cree != true || !context.mounted) return false;
  final supa = Supabase.instance.client;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  try {
    final enclos = await supa.from('enclos_chenil').insert({
      'uid_eleveur': uid,
      'profile_id': profileId,
      'is_association': true,
      'nom': nomCtrl.text.trim(),
      'type': type,
      'capacite': capacite,
    }).select('id').single();
    if (!context.mounted) return true;
    final ids = await _choisirAnimaux(context, nomCtrl.text.trim(), capacite);
    for (final id in ids) {
      await supa.from('animaux').update({'enclos_id': enclos['id'], 'fa_id': null}).eq('id', id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ids.isEmpty
          ? 'Hébergement créé !' : 'Hébergement créé, ${ids.length} animal(aux) placé(s) !')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
    return false;
  }
}

/// Famille d'accueil : créer une FA puis y placer un animal. true si créée.
Future<bool> guiderFamilleAccueil(BuildContext context, {required String? profileId}) async {
  final prenomCtrl = TextEditingController();
  final nomCtrl = TextEditingController();
  final telCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final cree = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Votre première famille d\'accueil', style: OnboardingTheme.title.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        Text('Vous pourrez la lier à un compte PetsMatch et compléter ses informations ensuite.',
            style: OnboardingTheme.body.copyWith(fontSize: 13)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(controller: prenomCtrl, decoration: _deco('Prénom'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: nomCtrl, decoration: _deco('Nom *'))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: telCtrl, keyboardType: TextInputType.phone, decoration: _deco('Téléphone')),
        const SizedBox(height: 12),
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: _deco('E-mail')),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, nomCtrl.text.trim().isNotEmpty),
          style: ElevatedButton.styleFrom(backgroundColor: OnboardingTheme.teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Créer la famille d\'accueil', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ]),
    )),
  );
  if (cree != true || !context.mounted) return false;
  final supa = Supabase.instance.client;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  String t(TextEditingController c) => c.text.trim();
  try {
    final fa = await supa.from('familles_accueil').insert({
      'association_uid': uid,
      if (profileId != null) 'association_profile_id': profileId,
      'prenom': t(prenomCtrl),
      'nom': t(nomCtrl),
      'telephone': t(telCtrl).isEmpty ? null : t(telCtrl),
      'email': t(emailCtrl).isEmpty ? null : t(emailCtrl),
      'capacite_max': 1,
      'actif': true,
    }).select('id').single();
    if (!context.mounted) return true;
    final lieu = '${t(prenomCtrl)} ${t(nomCtrl)}'.trim();
    final ids = await _choisirAnimaux(context, lieu, 1);
    for (final id in ids) {
      await supa.from('animaux').update({
        'fa_id': fa['id'], 'enclos_id': null,
        'date_entree': DateTime.now().toIso8601String().split('T').first,
      }).eq('id', id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ids.isEmpty
          ? 'Famille d\'accueil créée !' : 'Famille d\'accueil créée et animal placé !')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
    return false;
  }
}
