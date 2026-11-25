// Tâche « rappel du carnet » (functions/sante.js : « Antiparasitaire — 5 animaux »,
// « Vaccin — Tokyo »…) cochée ou ouverte : on retrouve le soin, le produit et
// les animaux, on vérifie le carnet ; soin déjà fait pour tous → la tâche est
// simplement cochée ; sinon le formulaire de soin (PorteeSoinSheet) s'ouvre
// prérempli avec les animaux restants, et la tâche est validée à l'enregistrement.
// Miroir site : lib/soin-depuis-tache.ts + components/animaux/SoinDepuisTache.tsx.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/portee_soin_sheet.dart';
import 'package:PetsMatch/utils/valider_tache.dart';

typedef _Acte = ({String acte, String table, String col, String label});
const _kActes = <String, _Acte>{
  'vaccin': (acte: 'vaccination', table: 'vaccinations', col: 'vaccin', label: 'Vaccin'),
  'vermifuge': (acte: 'vermifuge', table: 'vermifuges', col: 'produit', label: 'Vermifuge'),
  'antiparasitaire': (acte: 'antiparasitaire', table: 'antiparasitaires', col: 'produit', label: 'Antiparasitaire'),
};
// Titre posé par functions/sante.js (pictogramme éventuel devant) : jour J
// « Antiparasitaire — Luna » ou relance « Antiparasitaire en retard — Luna ».
final _reTitre = RegExp(r'^[^A-Za-zÀ-ÿ]*(Vaccin|Vermifuge|Antiparasitaire)( en retard)? — ');

bool estTacheRappelSoin(String? titre) => _reTitre.hasMatch(titre ?? '');

const _partis = {'sorti', 'decede', 'adopte', 'transfere', 'vendu'};

/// Soin d'une tâche « rappel du carnet » : acte, produit, animaux, et ceux
/// pour qui le soin est déjà au carnet. null : pas une tâche de rappel.
Future<({Map<String, dynamic> t, _Acte a, String produit, List<String> ids, Set<String> faits})?> _etatTache(String tacheId) async {
    final supa = Supabase.instance.client;
    // select() complet : soin_rappel n'existe qu'après migration_taches_soin_rappel.sql.
    final t = await supa.from('taches_elevage').select().eq('id', tacheId).maybeSingle();
    final m = _reTitre.firstMatch(t?['titre']?.toString() ?? '');
    if (t == null || m == null) return null;
    final a = _kActes[m.group(1)!.toLowerCase()]!;
    var produit = '';
    var ids = <String>[];
    final sr = t['soin_rappel'];
    if (sr is Map && sr['animal_ids'] is List && (sr['animal_ids'] as List).isNotEmpty) {
      produit = (sr['produit'] ?? '').toString().trim();
      ids = [for (final x in sr['animal_ids'] as List) x.toString()];
    } else if (m.group(2) != null) {
      // Relance « en retard » : notes = « Produit pour Luna devait être fait… ».
      final notes = (t['notes'] ?? '').toString();
      final i = notes.indexOf(' pour ');
      produit = i > 0 ? notes.substring(0, i).trim() : '';
      if (produit.toLowerCase() == a.label.toLowerCase()) produit = '';
      if ((t['animal_id']?.toString() ?? '').isNotEmpty) ids = [t['animal_id'].toString()];
    } else {
      // Tâches créées avant la colonne : notes = « Produit — Animaux : A, B, C ».
      final parts = (t['notes'] ?? '').toString().trim().split(' — ');
      produit = parts.first.startsWith('Animaux :') ? '' : parts.first.trim();
      if ((t['animal_id']?.toString() ?? '').isNotEmpty) {
        ids = [t['animal_id'].toString()];
      } else {
        final liste = parts.firstWhere((x) => x.startsWith('Animaux :'), orElse: () => '');
        final noms = [for (final n in liste.replaceFirst('Animaux :', '').split(',')) if (n.trim().isNotEmpty) n.trim()];
        if (noms.isEmpty) return null;
        final rows = await supa.from('animaux').select('id, nom, statut')
            .eq('uid_eleveur', t['uid_eleveur'].toString()).inFilter('nom', noms);
        final parNom = <String, String>{};
        for (final r in rows) {
          // Homonymes : l'animal encore présent l'emporte.
          if (!parNom.containsKey(r['nom']) || !_partis.contains(r['statut'])) parNom[r['nom'].toString()] = r['id'].toString();
        }
        ids = [for (final n in noms) if (parNom[n] != null) parNom[n]!];
      }
    }
    if (ids.isEmpty) return null;

    // Déjà au carnet : même produit (ou n'importe lequel si inconnu), donné le
    // jour du rappel ou après, ou renouvelé avec un rappel plus lointain.
    final jour = t['date'].toString().substring(0, 10);
    var q = supa.from(a.table).select('animal_id, date, date_rappel').inFilter('animal_id', ids);
    if (produit.isNotEmpty) q = q.ilike(a.col, produit);
    final faits = <String>{};
    for (final r in await q) {
      final d = (r['date'] ?? '').toString(), dr = (r['date_rappel'] ?? '').toString();
      final d10 = d.length >= 10 ? d.substring(0, 10) : '', dr10 = dr.length >= 10 ? dr.substring(0, 10) : '';
      if ((d10.isNotEmpty && d10.compareTo(jour) >= 0) || (dr10.isNotEmpty && dr10.compareTo(jour) > 0)) faits.add(r['animal_id'].toString());
    }
    return (t: t, a: a, produit: produit, ids: ids, faits: faits);
}

/// Soin enregistré depuis le rappel du carnet (accueil) : les tâches de
/// l'agenda du même soin dont tous les animaux sont maintenant au carnet sont
/// cochées. Rend le nombre de tâches cochées.
Future<int> cocherTachesSoinFaites(List<Map<String, dynamic>> taches) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 0;
  var n = 0;
  for (final tache in taches) {
    try {
      final e = await _etatTache(tache['id'].toString());
      if (e == null || e.t['statut'] == 'fait' || e.ids.any((i) => !e.faits.contains(i))) continue;
      await basculerTacheManuelle({...e.t, 'statut': 'a_faire'}, uid: uid, profileId: User_Info.activeProfileId);
      n++;
    } catch (err) {
      debugPrint('Tâche de soin ${tache['id']} non cochée : $err');
    }
  }
  return n;
}

/// true : la tâche est prise en charge ici (cochée, ou formulaire ouvert).
Future<bool> traiterTacheSoin(BuildContext context, Map<String, dynamic> tache, {VoidCallback? apres}) async {
  if (tache['statut'] == 'fait' || !estTacheRappelSoin(tache['titre']?.toString())) return false;
  final supa = Supabase.instance.client;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  try {
    final e = await _etatTache(tache['id'].toString());
    if (e == null) return false;
    final t = e.t, a = e.a, produit = e.produit, ids = e.ids, faits = e.faits;
    final restants = ids.where((i) => !faits.contains(i)).toSet();
    final pid = User_Info.activeProfileId;
    Future<void> valider() async {
      await basculerTacheManuelle({...t, 'statut': 'a_faire'}, uid: uid, profileId: pid);
    }
    if (restants.isEmpty) {
      await valider();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating,
            content: Text('Soin déjà inscrit au carnet : tâche cochée.', style: TextStyle(fontFamily: 'Galey'))));
      }
      apres?.call();
      return true;
    }
    final animaux = List<Map<String, dynamic>>.from(await supa.from('animaux')
        .select('id, nom, espece, sexe, date_naissance, identification').inFilter('id', ids));
    animaux.sort((x, y) {
      final r = (restants.contains(y['id'].toString()) ? 1 : 0) - (restants.contains(x['id'].toString()) ? 1 : 0);
      return r != 0 ? r : (x['nom'] ?? '').toString().compareTo((y['nom'] ?? '').toString());
    });
    final deja = [for (final x in animaux) if (faits.contains(x['id'].toString())) (x['nom'] ?? '').toString()];
    if (!context.mounted) return true;
    final owner = t['uid_eleveur']?.toString();
    final ok = await PorteeSoinSheet.show(context, animaux,
        eleveurUid: owner != null && owner != uid ? owner : null,
        titre: '${a.label}${produit.isNotEmpty ? ' — $produit' : ''}',
        acteInitial: a.acte, produitInitial: produit, selectionInitiale: restants,
        info: deja.isNotEmpty ? 'Déjà inscrit au carnet : ${deja.join(', ')}.' : null);
    if (ok) {
      await valider();
      apres?.call();
    }
    return true;
  } catch (_) {
    return false;
  }
}
