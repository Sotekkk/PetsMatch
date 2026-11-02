// Ordonnance structurée (migration_ordonnances_v2.sql) : contenu jsonb des
// lignes, contrôles avant validation, statuts. Le PDF est produit à partir de
// ce contenu (ordonnance_pdf.dart). Miroir site : website/src/lib/ordonnance.ts.
//
// Règle : rien n'est déduit ni inventé — un champ vide reste vide et bloque
// (médicament, posologie, durée) ou est signalé (voie, quantité, mentions).

class LigneOrdo {
  String medicament, principeActif, presentation, posologie, voie, duree, quantite, renouvellement, instructions, mentions;
  /// Quantité suggérée par le calcul : tant que [quantite] lui est égale, elle est « à vérifier ».
  String quantiteCalculee;
  /// Médicament de la pharmacie marqué stupéfiant.
  bool stupefiant;
  LigneOrdo({this.medicament = '', this.principeActif = '', this.presentation = '', this.posologie = '', this.voie = '',
      this.duree = '', this.quantite = '', this.renouvellement = '', this.instructions = '', this.mentions = '',
      this.quantiteCalculee = '', this.stupefiant = false});

  factory LigneOrdo.fromJson(Map j) {
    String v(String k) => (j[k] ?? '').toString();
    return LigneOrdo(medicament: v('medicament'), principeActif: v('principeActif'), presentation: v('presentation'),
        posologie: v('posologie'), voie: v('voie'), duree: v('duree'), quantite: v('quantite'),
        renouvellement: v('renouvellement'), instructions: v('instructions'), mentions: v('mentions'),
        quantiteCalculee: v('quantiteCalculee'), stupefiant: j['stupefiant'] == true);
  }

  Map<String, dynamic> toJson() => {
        'medicament': medicament.trim(), 'principeActif': principeActif.trim(), 'presentation': presentation.trim(),
        'posologie': posologie.trim(), 'voie': voie.trim(), 'duree': duree.trim(), 'quantite': quantite.trim(),
        'renouvellement': renouvellement.trim(), 'instructions': instructions.trim(), 'mentions': mentions.trim(),
        if (quantiteCalculee.isNotEmpty) 'quantiteCalculee': quantiteCalculee,
        if (stupefiant) 'stupefiant': true,
      };

  bool get vide => [medicament, principeActif, presentation, posologie, voie, duree, quantite, renouvellement,
      instructions, mentions].every((x) => x.trim().isEmpty);
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
    if (l.quantite.trim().isEmpty) {
      avertissements.add('$n : quantité à délivrer non précisée');
    } else if (l.quantiteCalculee.isNotEmpty && l.quantite.trim() == l.quantiteCalculee) {
      avertissements.add("$n : quantité calculée d'après la posologie et le conditionnement — à vérifier");
    }
    if (l.stupefiant) avertissements.add('$n : médicament classé stupéfiant — vérifiez les règles de prescription particulières');
    if (rente && l.mentions.trim().isEmpty) {
      avertissements.add("$n : espèce pouvant être destinée à la consommation — indiquez le temps d'attente ou l'exclusion dans les mentions réglementaires");
    }
  }
  return (bloquants: bloquants, avertissements: avertissements);
}

// ── Pharmacie de la clinique (migration_pharmacie_ordonnance.sql) ────────

const colonnesArticleOrdo = 'nom, presentation, principe_actif, contenance, contenance_unite, voie, instructions, mentions, stupefiant';

String _sansAccent(String x) {
  const a = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ', b = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buf = StringBuffer();
  for (final c in x.trim().toLowerCase().split('')) {
    final i = a.indexOf(c);
    buf.write(i >= 0 ? b[i] : c);
  }
  return buf.toString();
}

/// Article de même nom (sans tenir compte de la casse ni des accents).
Map<String, dynamic>? articleDe(String nom, List<Map<String, dynamic>> articles) {
  final n = _sansAccent(nom);
  if (n.isEmpty) return null;
  for (final a in articles) {
    if (_sansAccent((a['nom'] ?? '').toString()) == n) return a;
  }
  return null;
}

/// Champs vides de la ligne complétés par l'article (rien n'est écrasé ; jamais la dose).
LigneOrdo completerDepuisArticle(LigneOrdo l, Map<String, dynamic>? a) {
  if (a == null) return l;
  String garde(String actuel, dynamic val) => actuel.trim().isNotEmpty ? actuel : (val ?? '').toString().trim();
  l.presentation = garde(l.presentation, a['presentation']);
  l.principeActif = garde(l.principeActif, a['principe_actif']);
  l.voie = garde(l.voie, a['voie']);
  l.instructions = garde(l.instructions, a['instructions']);
  l.mentions = garde(l.mentions, a['mentions']);
  if (a['stupefiant'] == true) l.stupefiant = true;
  return l;
}

String _uniteCommune(String u) {
  final x = _sansAccent(u).replaceAll(RegExp(r'\.$'), '');
  if (RegExp(r'^(cp|cps|comp|comprime|comprimes)$').hasMatch(x)) return 'comprime';
  if (RegExp(r'^(gel|gelule|gelules)$').hasMatch(x)) return 'gelule';
  if (RegExp(r'^(ml|millilitre|millilitres)$').hasMatch(x)) return 'ml';
  return x.replaceAll(RegExp(r's$'), '');
}

/// « 1 cp », « ½ cp », « 1,5 mL », « 1/2 comprimé » → (n, unité) ; null si incertain.
({double n, String unite})? _doseNumerique(String d) {
  final m = RegExp(r'^\s*(\d+(?:[.,]\d+)?)?\s*(½|¼|¾|1/2|1/4|3/4)?\s*([a-zA-ZÀ-ÿ.]+)\s*$').firstMatch(d);
  if (m == null || (m.group(1) == null && m.group(2) == null)) return null;
  const frac = {'½': 0.5, '¼': 0.25, '¾': 0.75, '1/2': 0.5, '1/4': 0.25, '3/4': 0.75};
  final double n = (m.group(1) != null ? double.parse(m.group(1)!.replaceAll(',', '.')) : 0.0) + (frac[m.group(2)] ?? 0.0);
  return n > 0 ? (n: n, unite: _uniteCommune(m.group(3)!)) : null;
}

/// Quantité à délivrer SUGGÉRÉE : seulement si toutes les doses sont des
/// nombres dans l'unité du conditionnement et que la durée est connue ; sinon ''.
String quantiteSuggeree(List<({List<String> doses, int frequenceJours, int? dureeJours})> phases, Map<String, dynamic>? a) {
  final contenance = (a?['contenance'] as num?)?.toDouble();
  final uniteBoite = (a?['contenance_unite'] ?? '').toString().trim();
  if (contenance == null || contenance <= 0 || uniteBoite.isEmpty || phases.isEmpty) return '';
  final unite = _uniteCommune(uniteBoite);
  var total = 0.0;
  for (final p in phases) {
    if (p.dureeJours == null || p.dureeJours! <= 0 || p.doses.isEmpty) return '';
    final jours = (p.dureeJours! / (p.frequenceJours < 1 ? 1 : p.frequenceJours)).ceil();
    for (final d in p.doses) {
      final x = _doseNumerique(d);
      if (x == null || x.unite != unite) return '';
      total += x.n * jours;
    }
  }
  final boites = (total / contenance).ceil();
  String fmt(double n) => ((n * 100).round() / 100).toString().replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',');
  return '$boites conditionnement${boites > 1 ? 's' : ''} de ${fmt(contenance)} $uniteBoite (${fmt(total)} $uniteBoite pour le traitement)';
}
