class FrenchGeo {
  static const Map<String, _DeptInfo> _departments = {
    '01': _DeptInfo('Ain', 'Auvergne-Rhône-Alpes'),
    '02': _DeptInfo('Aisne', 'Hauts-de-France'),
    '03': _DeptInfo('Allier', 'Auvergne-Rhône-Alpes'),
    '04': _DeptInfo('Alpes-de-Haute-Provence', 'Provence-Alpes-Côte d\'Azur'),
    '05': _DeptInfo('Hautes-Alpes', 'Provence-Alpes-Côte d\'Azur'),
    '06': _DeptInfo('Alpes-Maritimes', 'Provence-Alpes-Côte d\'Azur'),
    '07': _DeptInfo('Ardèche', 'Auvergne-Rhône-Alpes'),
    '08': _DeptInfo('Ardennes', 'Grand Est'),
    '09': _DeptInfo('Ariège', 'Occitanie'),
    '10': _DeptInfo('Aube', 'Grand Est'),
    '11': _DeptInfo('Aude', 'Occitanie'),
    '12': _DeptInfo('Aveyron', 'Occitanie'),
    '13': _DeptInfo('Bouches-du-Rhône', 'Provence-Alpes-Côte d\'Azur'),
    '14': _DeptInfo('Calvados', 'Normandie'),
    '15': _DeptInfo('Cantal', 'Auvergne-Rhône-Alpes'),
    '16': _DeptInfo('Charente', 'Nouvelle-Aquitaine'),
    '17': _DeptInfo('Charente-Maritime', 'Nouvelle-Aquitaine'),
    '18': _DeptInfo('Cher', 'Centre-Val de Loire'),
    '19': _DeptInfo('Corrèze', 'Nouvelle-Aquitaine'),
    '2A': _DeptInfo('Corse-du-Sud', 'Corse'),
    '2B': _DeptInfo('Haute-Corse', 'Corse'),
    '20': _DeptInfo('Corse', 'Corse'),
    '21': _DeptInfo('Côte-d\'Or', 'Bourgogne-Franche-Comté'),
    '22': _DeptInfo('Côtes-d\'Armor', 'Bretagne'),
    '23': _DeptInfo('Creuse', 'Nouvelle-Aquitaine'),
    '24': _DeptInfo('Dordogne', 'Nouvelle-Aquitaine'),
    '25': _DeptInfo('Doubs', 'Bourgogne-Franche-Comté'),
    '26': _DeptInfo('Drôme', 'Auvergne-Rhône-Alpes'),
    '27': _DeptInfo('Eure', 'Normandie'),
    '28': _DeptInfo('Eure-et-Loir', 'Centre-Val de Loire'),
    '29': _DeptInfo('Finistère', 'Bretagne'),
    '30': _DeptInfo('Gard', 'Occitanie'),
    '31': _DeptInfo('Haute-Garonne', 'Occitanie'),
    '32': _DeptInfo('Gers', 'Occitanie'),
    '33': _DeptInfo('Gironde', 'Nouvelle-Aquitaine'),
    '34': _DeptInfo('Hérault', 'Occitanie'),
    '35': _DeptInfo('Ille-et-Vilaine', 'Bretagne'),
    '36': _DeptInfo('Indre', 'Centre-Val de Loire'),
    '37': _DeptInfo('Indre-et-Loire', 'Centre-Val de Loire'),
    '38': _DeptInfo('Isère', 'Auvergne-Rhône-Alpes'),
    '39': _DeptInfo('Jura', 'Bourgogne-Franche-Comté'),
    '40': _DeptInfo('Landes', 'Nouvelle-Aquitaine'),
    '41': _DeptInfo('Loir-et-Cher', 'Centre-Val de Loire'),
    '42': _DeptInfo('Loire', 'Auvergne-Rhône-Alpes'),
    '43': _DeptInfo('Haute-Loire', 'Auvergne-Rhône-Alpes'),
    '44': _DeptInfo('Loire-Atlantique', 'Pays de la Loire'),
    '45': _DeptInfo('Loiret', 'Centre-Val de Loire'),
    '46': _DeptInfo('Lot', 'Occitanie'),
    '47': _DeptInfo('Lot-et-Garonne', 'Nouvelle-Aquitaine'),
    '48': _DeptInfo('Lozère', 'Occitanie'),
    '49': _DeptInfo('Maine-et-Loire', 'Pays de la Loire'),
    '50': _DeptInfo('Manche', 'Normandie'),
    '51': _DeptInfo('Marne', 'Grand Est'),
    '52': _DeptInfo('Haute-Marne', 'Grand Est'),
    '53': _DeptInfo('Mayenne', 'Pays de la Loire'),
    '54': _DeptInfo('Meurthe-et-Moselle', 'Grand Est'),
    '55': _DeptInfo('Meuse', 'Grand Est'),
    '56': _DeptInfo('Morbihan', 'Bretagne'),
    '57': _DeptInfo('Moselle', 'Grand Est'),
    '58': _DeptInfo('Nièvre', 'Bourgogne-Franche-Comté'),
    '59': _DeptInfo('Nord', 'Hauts-de-France'),
    '60': _DeptInfo('Oise', 'Hauts-de-France'),
    '61': _DeptInfo('Orne', 'Normandie'),
    '62': _DeptInfo('Pas-de-Calais', 'Hauts-de-France'),
    '63': _DeptInfo('Puy-de-Dôme', 'Auvergne-Rhône-Alpes'),
    '64': _DeptInfo('Pyrénées-Atlantiques', 'Nouvelle-Aquitaine'),
    '65': _DeptInfo('Hautes-Pyrénées', 'Occitanie'),
    '66': _DeptInfo('Pyrénées-Orientales', 'Occitanie'),
    '67': _DeptInfo('Bas-Rhin', 'Grand Est'),
    '68': _DeptInfo('Haut-Rhin', 'Grand Est'),
    '69': _DeptInfo('Rhône', 'Auvergne-Rhône-Alpes'),
    '70': _DeptInfo('Haute-Saône', 'Bourgogne-Franche-Comté'),
    '71': _DeptInfo('Saône-et-Loire', 'Bourgogne-Franche-Comté'),
    '72': _DeptInfo('Sarthe', 'Pays de la Loire'),
    '73': _DeptInfo('Savoie', 'Auvergne-Rhône-Alpes'),
    '74': _DeptInfo('Haute-Savoie', 'Auvergne-Rhône-Alpes'),
    '75': _DeptInfo('Paris', 'Île-de-France'),
    '76': _DeptInfo('Seine-Maritime', 'Normandie'),
    '77': _DeptInfo('Seine-et-Marne', 'Île-de-France'),
    '78': _DeptInfo('Yvelines', 'Île-de-France'),
    '79': _DeptInfo('Deux-Sèvres', 'Nouvelle-Aquitaine'),
    '80': _DeptInfo('Somme', 'Hauts-de-France'),
    '81': _DeptInfo('Tarn', 'Occitanie'),
    '82': _DeptInfo('Tarn-et-Garonne', 'Occitanie'),
    '83': _DeptInfo('Var', 'Provence-Alpes-Côte d\'Azur'),
    '84': _DeptInfo('Vaucluse', 'Provence-Alpes-Côte d\'Azur'),
    '85': _DeptInfo('Vendée', 'Pays de la Loire'),
    '86': _DeptInfo('Vienne', 'Nouvelle-Aquitaine'),
    '87': _DeptInfo('Haute-Vienne', 'Nouvelle-Aquitaine'),
    '88': _DeptInfo('Vosges', 'Grand Est'),
    '89': _DeptInfo('Yonne', 'Bourgogne-Franche-Comté'),
    '90': _DeptInfo('Territoire de Belfort', 'Bourgogne-Franche-Comté'),
    '91': _DeptInfo('Essonne', 'Île-de-France'),
    '92': _DeptInfo('Hauts-de-Seine', 'Île-de-France'),
    '93': _DeptInfo('Seine-Saint-Denis', 'Île-de-France'),
    '94': _DeptInfo('Val-de-Marne', 'Île-de-France'),
    '95': _DeptInfo('Val-d\'Oise', 'Île-de-France'),
    '971': _DeptInfo('Guadeloupe', 'Guadeloupe'),
    '972': _DeptInfo('Martinique', 'Martinique'),
    '973': _DeptInfo('Guyane', 'Guyane'),
    '974': _DeptInfo('La Réunion', 'La Réunion'),
    '976': _DeptInfo('Mayotte', 'Mayotte'),
  };

  /// Retourne (departement, region) depuis un code postal français.
  /// Retourne null si le code postal ne correspond pas à un département français.
  static ({String departement, String region})? fromPostalCode(String codePostal) {
    final cp = codePostal.trim();
    if (cp.length < 2) return null;

    // DOM-TOM : codes commençant par 97x
    if (cp.startsWith('97') && cp.length >= 3) {
      final domKey = cp.substring(0, 3);
      final info = _departments[domKey];
      if (info != null) return (departement: info.name, region: info.region);
    }

    // Corse : 20xxx → préfixe 20, mais départements 2A/2B
    // On se base sur les 2 premiers chiffres
    final key = cp.substring(0, 2).toUpperCase();
    final info = _departments[key];
    if (info != null) return (departement: info.name, region: info.region);

    return null;
  }

  /// Formate l'adresse complète d'un élevage pour l'affichage.
  /// Retourne les parties non vides : ville, département, région, pays.
  static String formatLocation(Map<String, dynamic> data) {
    final ville = (data['villeElevage'] ?? '').toString().trim();
    final cp = (data['codePostalElevage'] ?? '').toString().trim();
    final pays = (data['paysElevage'] ?? '').toString().trim();

    final isFrance = pays.isEmpty ||
        pays.toLowerCase() == 'france' ||
        pays.toLowerCase() == 'fr';

    final parts = <String>[];
    if (ville.isNotEmpty) parts.add(ville);

    if (isFrance && cp.isNotEmpty) {
      final geo = fromPostalCode(cp);
      if (geo != null) {
        parts.add(geo.departement);
        parts.add(geo.region);
      }
    }

    if (pays.isNotEmpty && !isFrance) parts.add(pays);
    if (isFrance && parts.isNotEmpty) parts.add('France');

    return parts.join(', ');
  }
}

class _DeptInfo {
  final String name;
  final String region;
  const _DeptInfo(this.name, this.region);
}
