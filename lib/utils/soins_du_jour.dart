// Soins inscrits au carnet d'un animal un jour donné (intervention) : repris
// dans le CR opératoire — « Soins administrés » et « Traitements prescrits »
// (à poursuivre : date de fin après le jour, ou rappels de prise), qui servent
// aussi à préparer l'ordonnance et les consignes postopératoires.
// Miroir site : website/src/lib/soins-du-jour.ts.
import 'package:supabase_flutter/supabase_flutter.dart';

typedef TraitementPrescrit = ({String nom, String posologie, String duree});

Future<({List<String> administres, List<TraitementPrescrit> prescrits})> soinsDuJour(String animalId, String jour) async {
  final supa = Supabase.instance.client;
  final j = jour.length >= 10 ? jour.substring(0, 10) : jour;
  final administres = <String>[];
  final prescrits = <TraitementPrescrit>[];
  String fr(String d) {
    final x = DateTime.tryParse(d.substring(0, 10));
    const mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return x == null ? d : '${x.day} ${mois[x.month - 1]}';
  }
  try {
    final r = await Future.wait([
      supa.from('traitements').select('nom, posologie, date, date_fin, rappel_actif, rappel_fin').eq('animal_id', animalId).eq('date', j),
      supa.from('vaccinations').select('vaccin, lot').eq('animal_id', animalId).eq('date', j),
      supa.from('vermifuges').select('produit, dosage').eq('animal_id', animalId).eq('date', j),
      supa.from('antiparasitaires').select('produit').eq('animal_id', animalId).eq('date', j),
    ]);
    for (final t in r[0] as List) {
      final nom = (t['nom'] ?? '').toString().trim();
      if (nom.isEmpty) continue;
      final poso = (t['posologie'] ?? '').toString().trim();
      final fin = (t['date_fin'] ?? t['rappel_fin'])?.toString();
      final aPoursuivre = (fin != null && fin.substring(0, 10).compareTo(j) > 0) || t['rappel_actif'] == true;
      if (aPoursuivre) {
        final jours = fin == null ? 0 : DateTime.parse(fin.substring(0, 10)).difference(DateTime.parse(j)).inDays + 1;
        prescrits.add((nom: nom, posologie: poso, duree: fin == null ? '' : '$jours jours (jusqu’au ${fr(fin)})'));
      } else {
        administres.add('$nom${poso.isNotEmpty ? ' — $poso' : ''}');
      }
    }
    for (final v in r[1] as List) {
      final n = (v['vaccin'] ?? '').toString().trim(), lot = (v['lot'] ?? '').toString().trim();
      if (n.isNotEmpty) administres.add('Vaccin $n${lot.isNotEmpty ? ' (lot $lot)' : ''}');
    }
    for (final v in r[2] as List) {
      final n = (v['produit'] ?? '').toString().trim(), d = (v['dosage'] ?? '').toString().trim();
      if (n.isNotEmpty) administres.add('Vermifuge $n${d.isNotEmpty ? ' — $d' : ''}');
    }
    for (final a in r[3] as List) {
      final n = (a['produit'] ?? '').toString().trim();
      if (n.isNotEmpty) administres.add('Antiparasitaire $n');
    }
  } catch (_) {}
  return (administres: administres, prescrits: prescrits);
}

String lignePrescrit(TraitementPrescrit t) => [t.nom, t.posologie, t.duree].where((x) => x.isNotEmpty).join(' — ');

/// Ajoute des lignes à un texte sans doublon.
String ajouterLignes(String texte, List<String> lignes) {
  final existantes = {for (final l in texte.split('\n')) if (l.trim().isNotEmpty) l.trim().toLowerCase()};
  final nouvelles = lignes.where((l) => !existantes.contains(l.trim().toLowerCase()));
  return [if (texte.trim().isNotEmpty) texte.trim(), ...nouvelles].join('\n');
}
