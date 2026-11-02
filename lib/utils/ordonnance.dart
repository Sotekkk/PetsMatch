// Ordonnance structurée (migration_ordonnances_v2.sql) : contenu jsonb des
// lignes, contrôles avant validation, statuts. Le PDF est produit à partir de
// ce contenu (ordonnance_pdf.dart). Miroir site : website/src/lib/ordonnance.ts.
//
// Règle : rien n'est déduit ni inventé — un champ vide reste vide et bloque
// (médicament, posologie, durée) ou est signalé (voie, quantité, mentions).

class LigneOrdo {
  String medicament, principeActif, presentation, posologie, voie, duree, quantite, renouvellement, instructions, mentions;
  LigneOrdo({this.medicament = '', this.principeActif = '', this.presentation = '', this.posologie = '', this.voie = '',
      this.duree = '', this.quantite = '', this.renouvellement = '', this.instructions = '', this.mentions = ''});

  factory LigneOrdo.fromJson(Map j) {
    String v(String k) => (j[k] ?? '').toString();
    return LigneOrdo(medicament: v('medicament'), principeActif: v('principeActif'), presentation: v('presentation'),
        posologie: v('posologie'), voie: v('voie'), duree: v('duree'), quantite: v('quantite'),
        renouvellement: v('renouvellement'), instructions: v('instructions'), mentions: v('mentions'));
  }

  Map<String, String> toJson() => {
        'medicament': medicament.trim(), 'principeActif': principeActif.trim(), 'presentation': presentation.trim(),
        'posologie': posologie.trim(), 'voie': voie.trim(), 'duree': duree.trim(), 'quantite': quantite.trim(),
        'renouvellement': renouvellement.trim(), 'instructions': instructions.trim(), 'mentions': mentions.trim(),
      };

  bool get vide => toJson().values.every((x) => x.isEmpty);
}

class ContenuOrdo {
  final List<LigneOrdo> lignes;
  final String poids, remarques;
  ContenuOrdo({required this.lignes, this.poids = '', this.remarques = ''});

  factory ContenuOrdo.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    return ContenuOrdo(
      lignes: [for (final l in (m['lignes'] as List? ?? const [])) if (l is Map) LigneOrdo.fromJson(l)],
      poids: (m['poids'] ?? '').toString(),
      remarques: (m['remarques'] ?? '').toString(),
    );
  }

  /// Contenu nettoyé (lignes vides retirées).
  Map<String, dynamic> toJson() => {
        'lignes': [for (final l in lignes) if (!l.vide) l.toJson()],
        if (poids.trim().isNotEmpty) 'poids': poids.trim(),
        if (remarques.trim().isNotEmpty) 'remarques': remarques.trim(),
      };

  String get resume => lignes.map((l) => l.medicament.trim()).where((x) => x.isNotEmpty).join(', ');
}

const voiesOrdonnance = ['Orale', 'Cutanée', 'Auriculaire', 'Oculaire', 'Sous-cutanée', 'Intramusculaire',
  'Intraveineuse', 'Rectale', 'Nasale'];

const libelleStatutOrdo = {
  'brouillon': 'Brouillon', 'validee': 'Validée', 'signee': 'Signée', 'remplacee': 'Remplacée',
};

/// Espèces pouvant être destinées à la consommation humaine : le vétérinaire
/// doit indiquer le temps d'attente ou l'exclusion. Les règles exactes
/// (catégories, délais) restent à faire valider par un vétérinaire.
const _rente = ['bovin', 'vache', 'veau', 'taureau', 'ovin', 'mouton', 'brebis', 'agneau', 'caprin', 'chèvre', 'chevre',
  'porc', 'porcin', 'cochon', 'volaille', 'poule', 'coq', 'canard', 'oie', 'dinde', 'caille', 'pintade', 'lapin',
  'cheval', 'jument', 'poney', 'âne', 'ane', 'équidé', 'equide', 'mule', 'abeille', 'poisson'];
bool especeDeRente(String? espece) {
  final e = (espece ?? '').toLowerCase();
  return e.isNotEmpty && _rente.any(e.contains);
}

/// Contrôles avant validation : (bloquants, à vérifier).
({List<String> bloquants, List<String> avertissements}) controlerOrdo(ContenuOrdo c, String? espece) {
  final bloquants = <String>[], avertissements = <String>[];
  final lignes = c.lignes.where((l) => !l.vide).toList();
  if (lignes.isEmpty) bloquants.add('Au moins un médicament');
  final rente = especeDeRente(espece);
  for (var i = 0; i < lignes.length; i++) {
    final l = lignes[i];
    final n = 'Ligne ${i + 1}${l.medicament.trim().isNotEmpty ? ' (${l.medicament.trim()})' : ''}';
    if (l.medicament.trim().isEmpty) bloquants.add('$n : médicament');
    if (l.posologie.trim().isEmpty) bloquants.add('$n : posologie (dose, prises, fréquence)');
    if (l.duree.trim().isEmpty) bloquants.add('$n : durée du traitement');
    if (l.voie.trim().isEmpty) avertissements.add("$n : voie d'administration non précisée");
    if (l.quantite.trim().isEmpty) avertissements.add('$n : quantité à délivrer non précisée');
    if (rente && l.mentions.trim().isEmpty) {
      avertissements.add("$n : espèce pouvant être destinée à la consommation — indiquez le temps d'attente ou l'exclusion dans les mentions réglementaires");
    }
  }
  return (bloquants: bloquants, avertissements: avertissements);
}
