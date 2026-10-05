import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'balade_live_page.dart';

/// Démarrer une balade avec UN OU PLUSIEURS animaux — point d'entrée unique
/// (accueil, Mes balades, fiche animal). [preselectId] : animal coché
/// d'office (fiche). S'il n'y a qu'un animal, la balade démarre directement.
Future<void> demarrerBalade(BuildContext context, {String? preselectId}) async {
  final animaux = await _mesAnimaux();
  if (!context.mounted) return;
  if (animaux.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Ajoutez un animal avant de démarrer une balade.', style: TextStyle(fontFamily: 'Galey')),
    ));
    return;
  }
  final choisis = animaux.length == 1
      ? animaux
      : await _choisir(context, animaux, preselectId);
  if (choisis == null || choisis.isEmpty || !context.mounted) return;
  final principal = choisis.first;
  await Navigator.push(context, MaterialPageRoute(
    builder: (_) => BaladeLivePage(
      animalId: principal['id'].toString(),
      animalNom: nomsAnimaux(choisis),
      espece: principal['espece']?.toString() ?? '',
      autresAnimaux: choisis.skip(1).toList(),
    ),
  ));
}

/// « Luna », « Luna et Rocky », « Luna, Rocky et Max ».
String nomsAnimaux(List<Map<String, dynamic>> animaux) {
  final noms = animaux.map((a) => a['nom']?.toString() ?? 'Animal').toList();
  if (noms.isEmpty) return 'cet animal';
  if (noms.length == 1) return noms.first;
  return '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}';
}

/// Animaux du profil actif (propriétés en cours), décédés exclus.
Future<List<Map<String, dynamic>>> _mesAnimaux() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return [];
  final supa = Supabase.instance.client;
  try {
    var q = supa.from('animaux_proprietes').select('animal_id')
        .eq('uid_proprio', uid).isFilter('date_fin', null);
    if (User_Info.activeProfileId.isNotEmpty) q = q.eq('profile_id_proprio', User_Info.activeProfileId);
    final ids = (await q as List).map((r) => r['animal_id'].toString()).toSet().toList();
    if (ids.isEmpty) return [];
    final rows = await supa.from('animaux').select('id, nom, espece, photo_url, statut').inFilter('id', ids).order('nom', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List).where((a) => a['statut'] != 'decede').toList();
  } catch (_) {
    return [];
  }
}

Future<List<Map<String, dynamic>>?> _choisir(
    BuildContext context, List<Map<String, dynamic>> animaux, String? preselectId) {
  const teal = Color(0xFF0C5C6C);
  final coches = <String>{if (preselectId != null) preselectId};
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Avec qui balade-t-on ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text('Cochez un ou plusieurs compagnons.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
          child: ListView(shrinkWrap: true, children: [
            for (final a in animaux)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: teal,
                value: coches.contains(a['id'].toString()),
                onChanged: (v) => setS(() => v == true ? coches.add(a['id'].toString()) : coches.remove(a['id'].toString())),
                secondary: CircleAvatar(
                  backgroundColor: teal.withValues(alpha: 0.12),
                  backgroundImage: (a['photo_url'] as String?)?.isNotEmpty == true
                      ? CachedNetworkImageProvider(a['photo_url']) : null,
                  child: (a['photo_url'] as String?)?.isNotEmpty != true ? const Icon(Icons.pets, color: teal) : null,
                ),
                title: Text(a['nom']?.toString() ?? 'Animal', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: coches.isEmpty ? null : () {
            // Ordre : l'animal présélectionné (fiche) en premier = principal.
            final sel = animaux.where((a) => coches.contains(a['id'].toString())).toList()
              ..sort((x, y) => x['id'].toString() == preselectId ? -1 : (y['id'].toString() == preselectId ? 1 : 0));
            Navigator.pop(ctx, sel);
          },
          icon: const Icon(Icons.directions_walk),
          label: Text(coches.length > 1 ? 'Démarrer avec ${coches.length} animaux' : 'Démarrer la balade',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(backgroundColor: teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
      ]),
    ))),
  );
}
