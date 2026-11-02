// Remises d'une facture (lot 4 de la refonte) : une remise en % par ligne,
// motif affiché sur la facture (« Remise globale », « Tarif dégressif —
// 2e animal »…). Une ligne n'a qu'une remise : appliquer une remise par
// animal, globale ou dégressive remplace celle de la ligne (pas de cumul).
// Miroir site : website/src/lib/facture-remise.ts.

double _arrondi(num v) => (v * 100).roundToDouble() / 100;

/// Montant HT de la ligne, remise déduite (arrondi au centime).
double htLigneRemisee(num quantite, num prixUnitaireHT, num? remisePct) {
  final brut = _arrondi(quantite * prixUnitaireHT);
  final pct = (remisePct ?? 0).clamp(0, 100);
  return pct > 0 ? _arrondi(brut * (1 - pct / 100)) : brut;
}

/// Montant de la remise (HT, positif).
double montantRemise(num quantite, num prixUnitaireHT, num? remisePct) =>
    _arrondi(_arrondi(quantite * prixUnitaireHT) - htLigneRemisee(quantite, prixUnitaireHT, remisePct));

String _pctTxt(num p) => '${p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString().replaceAll('.', ',')} %';

/// « Remise 10 % (…) : -6,00 € HT »
String libelleRemise(num remisePct, String? motif, num montant) =>
    '${(motif ?? '').trim().isEmpty ? 'Remise' : motif!.trim()} ${_pctTxt(remisePct)} : -${montant.toStringAsFixed(2).replaceAll('.', ',')} € HT';

/// Tarif dégressif : rang de chaque animal dans l'ordre d'apparition des
/// lignes (0 = 1er animal, plein tarif) ; -1 pour une prestation commune.
List<String> animauxDesLignes(Iterable<({String? animalId, String? animalNom, bool commune})> lignes) {
  final ids = <String>[];
  for (final l in lignes) {
    final cle = l.commune ? '' : (l.animalId ?? l.animalNom ?? '');
    if (cle.isNotEmpty && !ids.contains(cle)) ids.add(cle);
  }
  return ids;
}
