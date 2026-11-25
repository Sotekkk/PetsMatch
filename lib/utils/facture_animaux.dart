// Animaux d'une facture (tous ceux de ses lignes, avec leur identification),
// rappelés sous « Désignation : ».
// Miroir site : website/src/lib/facture-animaux.ts.
String _t(Object? v) => v == null ? '' : v.toString().trim();

typedef AnimalFacture = ({String nom, String identification});

/// Animaux des lignes, sans doublon, dans l'ordre d'apparition. Une ligne
/// portant sur plusieurs animaux (acompte groupé) les liste dans `animaux`.
List<AnimalFacture> animauxDeLaFacture(Iterable<Map<String, dynamic>> lignes) {
  final vus = <String, AnimalFacture>{};
  void ajouter(Object? id, Object? nom, Object? ident) {
    final cle = _t(id).isNotEmpty ? _t(id) : _t(nom);
    if (cle.isEmpty) return;
    final deja = vus[cle];
    if (deja != null && deja.identification.isNotEmpty) return;
    vus[cle] = (nom: _t(nom).isEmpty ? 'Animal' : _t(nom), identification: _t(ident));
  }
  for (final l in lignes) {
    for (final a in (l['animaux'] as List?) ?? const []) {
      if (a is Map) ajouter(a['id'], a['nom'], a['identification']);
    }
    if (l['commune'] != true) ajouter(l['animalId'], l['animalNom'], l['animalIdentification']);
  }
  return vus.values.toList();
}

String titreAnimaux(int n) => n > 1 ? 'Animaux :' : 'Animal :';

String libelleAnimalFacture(AnimalFacture a) =>
    a.identification.isEmpty ? a.nom : '${a.nom} — Identification : ${a.identification}';
