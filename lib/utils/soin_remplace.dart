// Soin déjà renouvelé : une ligne plus récente existe pour le même produit
// (vaccin : même type, catégorie ou nom si elle est vide / « Autre »). Son
// bouton « + Rappel » et sa relance n'ont plus lieu d'être : on renouvelle
// depuis la dernière ligne. Même règle que trg_sante_rappel_a_jour et
// functions/sante.js. Miroir site : website/src/lib/soin-remplace.ts.

String _norm(Object? v) => (v ?? '').toString().trim().toLowerCase();

String _typeVaccin(Map l) {
  final c = _norm(l['categorie']);
  return c.isNotEmpty && c != 'autre' ? c : _norm(l['vaccin']);
}

bool _memeSoin(String table, Map a, Map b) => table == 'vaccinations'
    ? _typeVaccin(a) == _typeVaccin(b) || (_norm(a['vaccin']).isNotEmpty && _norm(a['vaccin']) == _norm(b['vaccin']))
    : _norm(a['produit']).isNotEmpty && _norm(a['produit']) == _norm(b['produit']);

String _jour(Object? d) {
  final s = (d ?? '').toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

// Date du soin, puis date de rappel, puis identifiant (deux lignes identiques : une seule reste active).
String _cle(Map l) => '${_jour(l['date'])}|${_jour(l['date_rappel'])}|${l['id'] ?? ''}';

bool soinRemplace(String table, Map ligne, Iterable<Map> lignes) => lignes.any((x) =>
    x['id']?.toString() != ligne['id']?.toString() && _memeSoin(table, ligne, x) && _cle(x).compareTo(_cle(ligne)) > 0);
