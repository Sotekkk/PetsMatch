// Prix d'un acte depuis « Autres actes » du vétérinaire (tarifs_veto_extra) :
// libellé rapproché sans accents ni casse, tranche de poids choisie d'après le
// poids de l'animal (« - de 10 kg », « + de 10 kg », « < 10 kg », « moins de /
// plus de 10 kg »). Strict (consultation) : libellé identique, tranche de poids
// mise à part ; souple (intervention) : l'un contient l'autre.
// Miroir site : website/src/lib/tarif-acte.ts.

typedef TarifExtra = ({String label, double prix});

String _norm(String s) {
  const a = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ', b = 'aaaaaaceeeeiiiinooooouuuuyy';
  final l = s.toLowerCase().trim();
  final out = StringBuffer();
  for (final c in l.split('')) {
    final i = a.indexOf(c);
    out.write(i >= 0 ? b[i] : c);
  }
  return out.toString();
}

final _rePoids = RegExp(r'([-+<>≤≥]|moins de|plus de)\s*(?:de\s*)?(\d+(?:[.,]\d+)?)\s*kg');

String _sansPoids(String s) => _norm(s)
    .replaceAll(RegExp(r'\(?\s*(?:[-+<>≤≥]|moins de|plus de)\s*(?:de\s*)?\d+(?:[.,]\d+)?\s*kg\s*\)?'), '')
    .replaceAll(RegExp(r'[\s\-–—:]+$'), '')
    .trim();

bool? _conditionPoids(String label, double? kg) {
  final m = _rePoids.firstMatch(_norm(label));
  if (m == null) return null;
  if (kg == null) return false;
  final n = double.parse(m.group(2)!.replaceAll(',', '.'));
  return const ['-', '<', '≤', 'moins de'].contains(m.group(1)) ? kg < n : kg >= n;
}

double? prixActeExtra(String libelle, List<TarifExtra> extras, double? kg, {bool souple = false}) {
  final cible = _sansPoids(libelle);
  if (cible.isEmpty) return null;
  final candidats = extras.where((e) {
    final base = _sansPoids(e.label);
    return base.isNotEmpty && (cible == base || (souple && (cible.contains(base) || base.contains(cible))));
  }).toList();
  if (candidats.isEmpty) return null;
  final avecPoids = candidats.where((e) => _conditionPoids(e.label, kg) == true);
  final choisi = avecPoids.isNotEmpty ? avecPoids.first
      : candidats.where((e) => _conditionPoids(e.label, kg) == null).firstOrNull ?? (kg == null ? candidats.first : null);
  return choisi != null && choisi.prix > 0 ? choisi.prix : null;
}

List<TarifExtra> extrasDepuis(dynamic v) => v is List
    ? [for (final e in v) if (e is Map && (e['label']?.toString().trim() ?? '').isNotEmpty)
        (label: e['label'].toString(), prix: double.tryParse('${e['prix'] ?? 0}'.replaceAll(',', '.')) ?? 0)]
    : const [];

/// Jours d'hospitalisation : du jour du dépôt au jour de la récupération (0 le même jour).
int joursHospitalisation(dynamic depotIso, dynamic recupIso) {
  final d = DateTime.tryParse(depotIso?.toString() ?? '')?.toLocal(), r = DateTime.tryParse(recupIso?.toString() ?? '')?.toLocal();
  if (d == null || r == null) return 0;
  final n = DateTime(r.year, r.month, r.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  return n > 0 ? n : 0;
}
