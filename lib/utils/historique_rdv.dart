// Historique des RDV d'un pro : plus récents en haut, filtre par client / animal,
// par jour et par hospitalisation (RDV « Intervention »).
// Miroir site : website/src/lib/historique-rdv.ts.

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
};

String _norm(Object? v) => (v ?? '').toString().toLowerCase().split('').map((c) => _accents[c] ?? c).join().trim();

DateTime? _date(Object? iso) => DateTime.tryParse(iso?.toString() ?? '')?.toLocal();

/// Plus récents en haut.
List<Map<String, dynamic>> historiqueTrie(Iterable<Map<String, dynamic>> rdvs) =>
    rdvs.toList()..sort((a, b) => (b['date_heure']?.toString() ?? '').compareTo(a['date_heure']?.toString() ?? ''));

/// Tous les mots de [recherche] dans le client, l'animal ou le motif ; [jour] : RDV
/// ce jour-là, ou hospitalisation en cours ce jour-là (du dépôt à la récupération).
List<Map<String, dynamic>> historiqueFiltre(List<Map<String, dynamic>> rdvs,
    {String recherche = '', DateTime? jour, bool hospitalisations = false}) {
  final mots = _norm(recherche).split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
  final j = jour == null ? null : DateTime(jour.year, jour.month, jour.day);
  return rdvs.where((r) {
    if (hospitalisations && r['intervention_type'] == null) return false;
    if (mots.isNotEmpty) {
      final texte = _norm([r['_client_name'], r['client_nom_manuel'], r['_animal_nom'], r['animal_nom_manuel'], r['motif']].join(' '));
      if (!mots.every(texte.contains)) return false;
    }
    if (j != null) {
      final debut = _date(r['date_heure']);
      if (debut == null) return false;
      final d0 = DateTime(debut.year, debut.month, debut.day);
      final sortie = r['intervention_type'] != null ? _date(r['sortie_le']) : null;
      final d1 = sortie == null ? d0 : DateTime(sortie.year, sortie.month, sortie.day);
      if (j.isBefore(d0) || j.isAfter(d1)) return false;
    }
    return true;
  }).toList();
}

String _jourHeure(DateTime d) => 'le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    'à ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

/// « Déposé le 04/11 à 10h15 · récupéré le 05/11 à 15h28 » (null si pas d'intervention commencée).
String? ligneHospitalisation(Map<String, dynamic> r) {
  if (r['intervention_type'] == null) return null;
  final admis = _date(r['admis_le']), sortie = _date(r['sortie_le']);
  if (admis == null && sortie == null) return null;
  return [if (admis != null) 'Déposé ${_jourHeure(admis)}', if (sortie != null) 'récupéré ${_jourHeure(sortie)}'].join(' · ');
}
