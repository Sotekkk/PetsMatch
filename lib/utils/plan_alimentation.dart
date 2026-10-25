// Plan d'alimentation par repas — modèle, calculs et contrôles partagés par
// l'onglet Alimentation (propriétaire) et la vue lecture seule (pension,
// pet-sitter, vétérinaire, partage). Miroir exact de
// website/src/lib/plan-alimentation.ts : toute règle changée ici doit l'être
// là-bas (mêmes libellés, mêmes seuils, mêmes messages).
//
// Méthodes de calcul selon l'espèce :
//  - chien / chat : énergie (kcal). Adulte : besoin au repos 70 × P^0,75 ×
//    coefficient (activité, stérilisation). Croissance : formules NRC 2006
//    (poids adulte estimé obligatoire). Chaque repas reçoit la même part
//    d'énergie, partagée entre ses aliments selon leur densité (kcal/100 g).
//  - cheval, ovin, caprin, porcin : % du poids vif selon l'activité (comme
//    l'ancien onglet), réparti par type d'aliment (foin 67 / concentrés 28 /
//    compléments 5).
//  - lapin : foin à volonté, granulés 22,5 g/kg, légumes 50 g/kg par jour.
//  - oiseau, NAC, autres : pas de recommandation, quantités saisies.
import 'dart:math' as math;

// ── Espèces ────────────────────────────────────────────────────────────────

class ProfilEspece {
  /// 'energie' | 'poids_vif' | 'lapin' | 'aucune'
  final String methode;
  final List<String> types;
  /// Quantités saisies et affichées en kg (grands animaux).
  final bool uniteKg;
  /// Types pouvant être servis « à volonté » (sans quantité).
  final List<String> typesLibres;
  const ProfilEspece(this.methode, this.types, {this.uniteKg = false, this.typesLibres = const []});
}

const _herbivore = ProfilEspece('poids_vif', ['foin', 'concentre', 'paturage', 'complement', 'autre'],
    uniteKg: true, typesLibres: ['foin', 'paturage']);

ProfilEspece profilEspece(String espece) {
  switch (espece.toLowerCase()) {
    case 'chien':
    case 'chat':
      return const ProfilEspece('energie', ['croquettes', 'patee', 'barf', 'menagere', 'autre']);
    case 'cheval':
    case 'ane':
    case 'ovin':
    case 'caprin':
      return _herbivore;
    case 'porcin':
      return const ProfilEspece('poids_vif', ['granules', 'menagere', 'legumes', 'autre'], uniteKg: true);
    case 'lapin':
      return const ProfilEspece('lapin', ['foin', 'granules', 'legumes', 'autre'], typesLibres: ['foin']);
    case 'oiseau':
      return const ProfilEspece('aucune', ['graines', 'granules', 'legumes', 'autre']);
    default:
      return const ProfilEspece('aucune', ['granules', 'foin', 'legumes', 'graines', 'autre'], typesLibres: ['foin']);
  }
}

const kLibellesTypeAliment = <String, String>{
  'croquettes': 'Croquettes',
  'patee': 'Pâtée / humide',
  'barf': 'BARF / cru',
  'menagere': 'Ration ménagère',
  'autre': 'Autre',
  'foin': 'Foin / fourrage',
  'concentre': 'Granulés / concentrés',
  'paturage': 'Pâturage',
  'complement': 'Complément',
  'granules': 'Granulés',
  'legumes': 'Légumes frais',
  'graines': 'Graines / mélange',
};

/// Type du catalogue marques_aliments → type du plan (« pâtée » historique ;
/// les granulés du catalogue sont enregistrés « croquettes » pour les autres
/// espèces).
String typeDepuisCatalogue(String? t, String espece) {
  final p = profilEspece(espece);
  if (t == 'pâtée') return 'patee';
  if (t == 'croquettes' && p.methode != 'energie') {
    return p.types.contains('concentre') ? 'concentre' : 'granules';
  }
  if (t != null && p.types.contains(t)) return t;
  return p.types.first;
}

String typeVersCatalogue(String t) => t == 'patee' ? 'pâtée' : t;

/// Servi à volonté par défaut : pâturage, foin du lapin.
bool libreParDefaut(String type, ProfilEspece p) =>
    type == 'paturage' || (type == 'foin' && p.methode == 'lapin');

const kActivites = ['sedentaire', 'normal', 'sportif'];
const kLibellesActivite = <String, String>{
  'sedentaire': 'Sédentaire', 'normal': 'Normal', 'sportif': 'Sportif',
};

/// Ancien codage de l'activité (appli : repos…très actif ; site : actif…).
String activiteDepuisAncienne(String? a) {
  switch (a) {
    case 'repos': case 'leger': case 'sedentaire': return 'sedentaire';
    case 'actif': case 'tres_actif': case 'sportif': return 'sportif';
    default: return 'normal';
  }
}

List<String> libellesRepas(int n) {
  switch (n) {
    case 1: return ['Repas unique'];
    case 2: return ['Matin', 'Soir'];
    case 3: return ['Matin', 'Midi', 'Soir'];
    case 4: return ['Matin', 'Midi', 'Après-midi', 'Soir'];
    case 5: return ['Matin', 'Milieu de matinée', 'Midi', 'Après-midi', 'Soir'];
    default: return List.generate(n, (i) => 'Repas ${i + 1}');
  }
}

/// Plages habituelles de densité énergétique (kcal/100 g) par type.
const kPlagesKcal = <String, (double, double)>{
  'croquettes': (250, 500), 'patee': (50, 150), 'barf': (100, 300),
  'menagere': (80, 250), 'autre': (20, 600),
};

/// Poids plausibles par espèce (kg) — hors plage : avertissement.
const _poidsPlausibles = <String, (double, double)>{
  'chien': (0.5, 110), 'chat': (0.3, 15), 'cheval': (50, 1200), 'ane': (50, 500),
  'lapin': (0.3, 10), 'ovin': (5, 200), 'caprin': (5, 150), 'porcin': (5, 350), 'oiseau': (0.005, 20),
};

// ── Saisie des nombres ─────────────────────────────────────────────────────

class LectureNombre {
  final double? v;
  final String? err;
  const LectureNombre({this.v, this.err});
  bool get vide => v == null && err == null;
}

final _reNombre = RegExp(r'^\d+(?:[.,]\d+)?$');

/// Nombre positif, virgule française acceptée, sans unité ni signe.
LectureNombre lireNombre(String? s, {bool zeroAutorise = false}) {
  final t = (s ?? '').trim();
  if (t.isEmpty) return const LectureNombre();
  if (!_reNombre.hasMatch(t)) {
    return const LectureNombre(err: 'Saisissez un nombre positif, sans unité (ex. 135).');
  }
  final v = double.parse(t.replaceAll(',', '.'));
  if (v == 0 && !zeroAutorise) return const LectureNombre(err: 'La valeur doit être supérieure à 0.');
  return LectureNombre(v: v);
}

String _fr1(double n) => ((n * 10).round() / 10).toStringAsFixed(1).replaceAll('.', ',');
String _frCoef(double n) => n.toString().replaceAll('.', ',');

/// Quantité lisible avec son unité : « 135 g » ou « 3,5 kg ».
String formatQuantite(double g, {bool kg = false}) =>
    (kg || g >= 1000) ? '${_fr1(g / 1000)} kg' : '${g.round()} g';

// ── Modèle ────────────────────────────────────────────────────────────────

class AlimentPlan {
  String? id; // marques_aliments.id (null : préparation maison / ancien plan)
  String marque;
  String gamme;
  String type;
  double? kcal; // kcal/100 g, null = non renseignée
  String? source; // 'fabricant' | 'composition' (estimation)
  /// Repère de composition d'une préparation maison, en % : BARF (muscles,
  /// abats, os, légumes) ou ration ménagère (protéines, légumes, féculents,
  /// matières grasses, compléments) — détaillé en grammes à chaque repas.
  Map<String, double>? repartition;
  // Non stockés dans le plan : relus du catalogue.
  List<dynamic> doses = const [];
  List<dynamic> tableauCroissance = const [];

  AlimentPlan({this.id, required this.marque, this.gamme = '', required this.type, this.kcal, this.source, this.repartition});

  String get nom => gamme.trim().isEmpty ? marque : '$marque — $gamme';

  Map<String, dynamic> toJson() => {
        'id': id, 'marque': marque, 'gamme': gamme, 'type': type, 'kcal': kcal, 'source': source,
        if (repartition != null) 'repartition': repartition,
      };

  factory AlimentPlan.fromJson(Map<String, dynamic> j) => AlimentPlan(
        id: j['id']?.toString(),
        marque: (j['marque'] ?? '').toString(),
        gamme: (j['gamme'] ?? '').toString(),
        type: (j['type'] ?? 'autre').toString(),
        kcal: (j['kcal'] as num?)?.toDouble(),
        source: j['source']?.toString(),
        repartition: j['repartition'] is Map
            ? (j['repartition'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble()))
            : null,
      );
}

class ItemRepas {
  int a;
  /// Quantité choisie par le propriétaire (g) ; null = recommandation.
  double? g;
  /// À volonté (foin, pâturage) : pas de quantité.
  bool libre;
  /// Quantité enregistrée (lecture seule : pension, partage…).
  double? gEnregistre;
  ItemRepas(this.a, {this.g, this.libre = false, this.gEnregistre});
}

class RepasPlan {
  String? heure; // « 07:30 »
  List<ItemRepas> items;
  RepasPlan({this.heure, List<ItemRepas>? items}) : items = items ?? [];
}

class PlanAlimentation {
  String mode; // 'unique' | 'mixte'
  List<String> categories;
  String activite;
  double? poidsAdulte;
  /// Nombre de petits allaités (lactation), repris de la portée, modifiable.
  int? nbPetits;
  /// Mise bas (« yyyy-MM-dd ») à laquelle se rapporte [nbPetits] : une
  /// nouvelle portée remplace la saisie précédente.
  String? nbPetitsMiseBas;
  List<AlimentPlan> aliments;
  List<RepasPlan> repas;
  /// Plan reconstitué depuis l'ancien format (pas encore réenregistré).
  bool repris;

  PlanAlimentation({
    this.mode = 'unique', List<String>? categories, this.activite = 'normal', this.poidsAdulte, this.nbPetits, this.nbPetitsMiseBas,
    List<AlimentPlan>? aliments, List<RepasPlan>? repas, this.repris = false,
  })  : categories = categories ?? [],
        aliments = aliments ?? [],
        repas = repas ?? [RepasPlan(heure: null), RepasPlan(heure: null)];

  int get nbRepas => repas.length;

  /// Change le nombre de repas : les repas ajoutés reçoivent tous les aliments.
  void changerNbRepas(int n, ProfilEspece profil) {
    while (repas.length > n) { repas.removeLast(); }
    while (repas.length < n) {
      repas.add(RepasPlan(items: [
        for (var i = 0; i < aliments.length; i++)
          ItemRepas(i, libre: libreParDefaut(aliments[i].type, profil)),
      ]));
    }
  }

  /// Ajoute un aliment ; il est proposé à tous les repas (décochable ensuite).
  void ajouterAliment(AlimentPlan a, ProfilEspece profil) {
    if (mode == 'unique') {
      aliments = [a];
      for (final r in repas) { r.items = [ItemRepas(0, libre: libreParDefaut(a.type, profil))]; }
      return;
    }
    aliments.add(a);
    final idx = aliments.length - 1;
    for (final r in repas) { r.items.add(ItemRepas(idx, libre: libreParDefaut(a.type, profil))); }
  }

  void retirerAliment(int idx) {
    aliments.removeAt(idx);
    for (final r in repas) {
      r.items.removeWhere((it) => it.a == idx);
      for (final it in r.items) { if (it.a > idx) it.a--; }
    }
  }

  /// Coche / décoche un aliment pour un repas.
  void basculer(int repasIdx, int a, ProfilEspece profil) {
    final r = repas[repasIdx];
    final i = r.items.indexWhere((it) => it.a == a);
    if (i >= 0) {
      r.items.removeAt(i);
    } else {
      r.items.add(ItemRepas(a, libre: libreParDefaut(aliments[a].type, profil)));
      r.items.sort((x, y) => x.a.compareTo(y.a));
    }
  }

  /// Revenir à la ration recommandée : efface les quantités choisies, garde
  /// aliments, repas et horaires.
  void revenirRecommandation() {
    for (final r in repas) { for (final it in r.items) { it.g = null; } }
  }

  bool get estPersonnalise => repas.any((r) => r.items.any((it) => it.g != null));

  Map<String, dynamic> toJson(CalculRation c) => {
        'v': 1,
        'mode': mode,
        'categories': categories,
        'activite': activite,
        'poids_adulte': poidsAdulte,
        'nb_petits': nbPetits,
        'nb_petits_mise_bas': nbPetitsMiseBas,
        'enregistre_le': DateTime.now().toUtc().toIso8601String(),
        'aliments': aliments.map((a) => a.toJson()).toList(),
        'repas': [
          for (var i = 0; i < repas.length; i++)
            {
              'heure': repas[i].heure,
              'items': [
                for (var j = 0; j < repas[i].items.length; j++)
                  {
                    'a': repas[i].items[j].a,
                    'g': c.lignes[i][j].eff?.roundToDouble(),
                    'perso': repas[i].items[j].g != null,
                    if (repas[i].items[j].libre) 'libre': true,
                  },
              ],
            },
        ],
      };

  factory PlanAlimentation.fromJson(Map<String, dynamic> j) {
    final aliments = ((j['aliments'] as List?) ?? [])
        .whereType<Map>()
        .map((m) => AlimentPlan.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final repas = ((j['repas'] as List?) ?? []).whereType<Map>().map((r) {
      final items = ((r['items'] as List?) ?? []).whereType<Map>().map((it) {
        final g = (it['g'] as num?)?.toDouble();
        return ItemRepas((it['a'] as num).toInt(),
            g: it['perso'] == true ? g : null, libre: it['libre'] == true, gEnregistre: g);
      }).where((it) => it.a >= 0 && it.a < aliments.length).toList();
      final h = r['heure']?.toString();
      return RepasPlan(heure: (h == null || h.isEmpty) ? null : h, items: items);
    }).toList();
    return PlanAlimentation(
      mode: (j['mode'] ?? (aliments.length > 1 ? 'mixte' : 'unique')).toString(),
      categories: ((j['categories'] as List?) ?? []).map((e) => e.toString()).toList(),
      activite: kActivites.contains(j['activite']) ? j['activite'] as String : 'normal',
      poidsAdulte: (j['poids_adulte'] as num?)?.toDouble(),
      nbPetits: (j['nb_petits'] as num?)?.toInt(),
      nbPetitsMiseBas: j['nb_petits_mise_bas']?.toString(),
      aliments: aliments,
      repas: repas.isEmpty ? [RepasPlan()] : repas,
    );
  }
}

/// Repères de composition des préparations maison (ancien onglet).
const kRepartitionBarf = <String, double>{'muscles': 70, 'abats': 10, 'os': 10, 'legumes': 10};
const kRepartitionMenagere = <String, double>{
  'proteines': 40, 'legumes': 20, 'feculents': 30, 'matieres_grasses': 5, 'complements': 5,
};
const kLibellesRepartition = <String, String>{
  'muscles': 'Muscles', 'abats': 'Abats', 'os': 'Os charnus', 'legumes': 'Légumes',
  'proteines': 'Protéines animales', 'feculents': 'Féculents', 'matieres_grasses': 'Matières grasses',
  'complements': 'Complément minéral',
};

// ── Profil animal et besoin ───────────────────────────────────────────────

class ProfilAnimal {
  final String espece;
  final String nom;
  final String sexe;
  final bool sterilise;
  final DateTime? dateNaissance;
  final double? poidsKg;
  /// 'normal' | 'gestation_debut' | 'gestation_fin' | 'lactation'
  final String etatRepro;
  /// Semaine de lactation (1 = première semaine après la mise bas).
  final int? semaineLactation;
  const ProfilAnimal({
    required this.espece, this.nom = '', this.sexe = '', this.sterilise = false,
    this.dateNaissance, this.poidsKg, this.etatRepro = 'normal', this.semaineLactation,
  });

  double? get ageMois {
    final d = dateNaissance;
    if (d == null) return null;
    return DateTime.now().difference(d).inDays / 30.44;
  }

  String get nomOuAnimal => nom.trim().isEmpty ? 'L’animal' : nom.trim();
}

class Besoin {
  /// Énergie (kcal/jour) — chien / chat.
  final double? kcal;
  /// Ration totale (g/jour) — méthode % du poids vif.
  final double? totalG;
  /// Donnée indispensable manquante (message à afficher), sinon null.
  final String? manque;
  final String detail;
  final bool croissance;
  final String? avertissement;
  const Besoin({this.kcal, this.totalG, this.manque, this.detail = '', this.croissance = false, this.avertissement});
}

/// Coefficient multiplicateur du besoin au repos (chien / chat adultes).
double coefficientAdulte(String espece, bool sterilise, String activite) {
  const chienSt = {'sedentaire': 1.4, 'normal': 1.6, 'sportif': 2.0};
  const chienEn = {'sedentaire': 1.6, 'normal': 1.8, 'sportif': 2.2};
  const chatSt = {'sedentaire': 1.0, 'normal': 1.2, 'sportif': 1.4};
  const chatEn = {'sedentaire': 1.2, 'normal': 1.4, 'sportif': 1.6};
  final t = espece == 'chat' ? (sterilise ? chatSt : chatEn) : (sterilise ? chienSt : chienEn);
  return t[activite] ?? t['normal']!;
}

/// Gestation / lactation chien et chat (NRC 2006), en kcal/jour, sur le poids
/// réel. Lactation : selon le nombre de petits et la semaine. null : état
/// normal. [manque] renseigné si le nombre de petits est inconnu.
({double? kcal, String detail, String? manque})? _besoinRepro(ProfilAnimal p, double poids, int? nbPetits) {
  final chat = p.espece == 'chat';
  switch (p.etatRepro) {
    case 'gestation_debut':
      if (chat) {
        final k = 140 * math.pow(poids, 0.67).toDouble();
        return (kcal: k, detail: 'Gestation : 140 × P^0,67 (NRC 2006, chatte, toute la gestation).', manque: null);
      }
      return null; // chienne : entretien jusqu'aux 4 dernières semaines
    case 'gestation_fin':
      if (chat) {
        final k = 140 * math.pow(poids, 0.67).toDouble();
        return (kcal: k, detail: 'Gestation : 140 × P^0,67 (NRC 2006, chatte, toute la gestation).', manque: null);
      }
      final k = 132 * math.pow(poids, 0.75).toDouble() + 26 * poids;
      return (kcal: k, detail: 'Fin de gestation : 132 × P^0,75 + 26 × P (NRC 2006, dernières semaines).', manque: null);
    case 'lactation':
      final n = nbPetits;
      if (n == null || n <= 0) {
        return (kcal: null, detail: '',
            manque: '${p.nomOuAnimal} allaite : indiquez le nombre de petits pour calculer sa ration de lactation.');
      }
      final sem = (p.semaineLactation ?? 1).clamp(1, 8);
      if (chat) {
        const lChat = [0.9, 0.9, 1.2, 1.2, 1.1, 1.0, 0.8];
        final l = lChat[math.min(sem, 7) - 1];
        final coef = n <= 2 ? 18.0 : n <= 4 ? 60.0 : 70.0;
        final k = 100 * math.pow(poids, 0.67).toDouble() + coef * poids * l;
        return (kcal: k, manque: null,
            detail: 'Lactation, $n chaton${n > 1 ? 's' : ''}, semaine $sem : 100 × P^0,67 + ${coef.round()} × P × ${_frCoef(l)} (NRC 2006).');
      }
      const lChien = [0.75, 0.95, 1.1, 1.2];
      final l = lChien[math.min(sem, 4) - 1];
      final premiers = math.min(n, 4), suivants = math.max(n - 4, 0);
      final k = 145 * math.pow(poids, 0.75).toDouble() + poids * (24 * premiers + 12 * suivants) * l;
      return (kcal: k, manque: null,
          detail: 'Lactation, $n chiot${n > 1 ? 's' : ''}, semaine $sem : 145 × P^0,75 + P × (24 × $premiers${suivants > 0 ? ' + 12 × $suivants' : ''}) × ${_frCoef(l)} (NRC 2006).');
  }
  return null;
}

double _facteurRepro(String etat) => switch (etat) {
      'gestation_debut' => 1.1, 'gestation_fin' => 1.3, 'lactation' => 1.5, _ => 1.0,
    };

String _libRepro(String etat) => switch (etat) {
      'gestation_debut' => 'début de gestation ×1,1',
      'gestation_fin' => 'fin de gestation ×1,3',
      'lactation' => 'lactation ×1,5',
      _ => '',
    };

/// Âge (mois) jusqu'auquel l'animal est considéré en croissance.
double _finCroissanceMois(String espece, double? poidsAdulte) {
  switch (espece) {
    case 'chien': return (poidsAdulte ?? 0) >= 25 ? 18 : 12;
    case 'chat': return 12;
    case 'cheval': case 'ane': return 24;
    case 'lapin': return 4;
    default: return 6;
  }
}

Besoin calculerBesoin(ProfilAnimal p, {required String activite, double? poidsObjectif, double? poidsAdulte, int? nbPetits}) {
  final profil = profilEspece(p.espece);
  final nom = p.nomOuAnimal;
  if (profil.methode == 'aucune') {
    return const Besoin(detail: 'Pas de calcul automatique pour cette espèce : indiquez les quantités servies.');
  }
  final poids = p.poidsKg;
  if (poids == null || poids <= 0) {
    return Besoin(manque: 'Le poids de $nom n’est pas renseigné : ajoutez une pesée dans la fiche pour calculer la ration.');
  }
  String? avert;
  final plage = _poidsPlausibles[p.espece];
  if (plage != null && (poids < plage.$1 || poids > plage.$2)) {
    avert = 'Le poids enregistré (${_fr1(poids)} kg) est inhabituel pour cette espèce : vérifiez la fiche avant de suivre la ration.';
  }
  final age = p.ageMois;
  final enCroissance = age != null && age < _finCroissanceMois(p.espece, poidsAdulte);

  if (profil.methode == 'energie') {
    if (age != null && age < 2) {
      return Besoin(manque: 'Avant 8 semaines, la ration de $nom est fixée par l’éleveur ou le vétérinaire : PetsMatch ne la calcule pas.');
    }
    if (enCroissance) {
      if (poidsAdulte == null || poidsAdulte <= 0) {
        return Besoin(croissance: true,
            manque: '$nom est en croissance : indiquez son poids adulte estimé (demandez à l’éleveur ou au vétérinaire) pour calculer sa ration.');
      }
      final ratio = poids / poidsAdulte;
      if (ratio < 1) {
        final kcal = p.espece == 'chat'
            ? 100 * math.pow(poids, 0.67) * 6.7 * (math.exp(-0.189 * ratio) - 0.66)
            : 130 * math.pow(poids, 0.75) * 3.2 * (math.exp(-0.87 * ratio) - 0.1);
        return Besoin(kcal: kcal.toDouble(), croissance: true, avertissement: avert,
            detail: 'Croissance : formule NRC 2006 (poids actuel ${_fr1(poids)} kg, poids adulte estimé ${_fr1(poidsAdulte)} kg). Estimation à ajuster selon la courbe de poids.');
      }
    }
    final repro = p.sterilise ? null : _besoinRepro(p, poids, nbPetits);
    if (repro != null) {
      if (repro.manque != null) return Besoin(manque: repro.manque);
      return Besoin(kcal: repro.kcal, avertissement: avert,
          detail: '${repro.detail} Poids ${_fr1(poids)} kg. Estimation : à ajuster selon l’état de la femelle.');
    }
    final pCalc = poidsObjectif ?? poids;
    final rer = 70 * math.pow(pCalc, 0.75).toDouble();
    final coef = coefficientAdulte(p.espece, p.sterilise, activite);
    final parts = [
      p.sterilise ? 'adulte stérilisé' : 'adulte non stérilisé',
      'activité ${kLibellesActivite[activite]!.toLowerCase()}',
      if (poidsObjectif != null) 'objectif ${_fr1(poidsObjectif)} kg',
    ];
    return Besoin(kcal: rer * coef, avertissement: avert,
        detail: 'Besoin au repos ${rer.round()} kcal × ${_frCoef(coef)} (${parts.join(', ')})${p.etatRepro == 'gestation_debut' ? ', début de gestation : besoins d’entretien' : ''}. '
            'Estimation : à ajuster selon l’évolution du poids.');
  }

  if (enCroissance) {
    return Besoin(croissance: true,
        manque: '$nom est encore jeune : pour un animal en croissance de cette espèce, demandez la ration au vétérinaire. Indiquez les quantités servies.');
  }
  final pCalc = poidsObjectif ?? poids;
  if (profil.methode == 'lapin') {
    return Besoin(avertissement: avert,
        detail: 'Foin à volonté, granulés 22,5 g et légumes frais 50 g par kg de poids et par jour (poids ${_fr1(pCalc)} kg).');
  }
  const pct = <String, Map<String, double>>{
    'cheval': {'sedentaire': 1.5, 'normal': 2.0, 'sportif': 2.5},
    'ovin': {'sedentaire': 1.5, 'normal': 2.0, 'sportif': 2.2},
    'porcin': {'sedentaire': 2.0, 'normal': 3.0, 'sportif': 3.0},
  };
  final table = pct[p.espece == 'ane' ? 'cheval' : p.espece == 'caprin' ? 'ovin' : p.espece] ?? pct['cheval']!;
  final taux = table[activite] ?? table['normal']!;
  final repro = p.sterilise ? 1.0 : _facteurRepro(p.etatRepro);
  final total = pCalc * 1000 * taux / 100 * repro;
  return Besoin(totalG: total, avertissement: avert,
      detail: 'Ration totale ${formatQuantite(total, kg: true)}/jour : ${_frCoef(taux)} % du poids (${_fr1(pCalc)} kg), activité ${kLibellesActivite[activite]!.toLowerCase()}'
          '${repro != 1.0 ? ', ${_libRepro(p.etatRepro)}' : ''}.');
}

// ── Recommandation fabricant ──────────────────────────────────────────────

/// Quantité (g/jour) indiquée par le fabricant pour ce profil, sinon null.
double? recommandationFabricant(AlimentPlan a, ProfilAnimal p, {required bool croissance, double? poidsAdulte}) {
  final poids = p.poidsKg;
  if (croissance) {
    final age = p.ageMois;
    final rows = a.tableauCroissance.whereType<Map>()
        .where((r) => r['g_jour'] is num && r['age_mois'] is num).toList();
    if (rows.isEmpty || age == null) return null;
    var cand = rows;
    if (poidsAdulte != null && rows.any((r) => r['poids_adulte_kg'] is num)) {
      final avecPoids = rows.where((r) => r['poids_adulte_kg'] is num).toList();
      double ecart(Map r) => ((r['poids_adulte_kg'] as num).toDouble() - poidsAdulte).abs();
      final best = avecPoids.map(ecart).reduce(math.min);
      cand = avecPoids.where((r) => ecart(r) == best).toList();
    }
    cand.sort((x, y) => (x['age_mois'] as num).compareTo(y['age_mois'] as num));
    final avant = cand.where((r) => (r['age_mois'] as num) <= age).toList();
    return ((avant.isNotEmpty ? avant.last : cand.first)['g_jour'] as num).toDouble();
  }
  if (poids == null || poids <= 0) return null;
  final pts = a.doses.whereType<Map>()
      .where((d) => d['poids_kg'] is num && d['grammes'] is num)
      .map((d) => ((d['poids_kg'] as num).toDouble(), (d['grammes'] as num).toDouble()))
      .toList()
    ..sort((x, y) => x.$1.compareTo(y.$1));
  if (pts.isEmpty) return null;
  if (poids <= pts.first.$1) return pts.first.$2;
  for (var i = 0; i < pts.length - 1; i++) {
    final (p1, g1) = pts[i];
    final (p2, g2) = pts[i + 1];
    if (poids >= p1 && poids <= p2) return g1 + (g2 - g1) * (poids - p1) / (p2 - p1);
  }
  return pts.last.$2;
}

// ── Calcul de la ration ───────────────────────────────────────────────────

class LigneRation {
  final int a;
  final double? reco; // g/repas recommandés par PetsMatch
  final double? eff; // g/repas servis (choisis, sinon recommandés)
  final bool libre;
  final bool perso;
  const LigneRation({required this.a, this.reco, this.eff, this.libre = false, this.perso = false});
}

class CalculRation {
  final Besoin besoin;
  final List<List<LigneRation>> lignes;
  final List<double> totalParAliment; // g/jour
  final List<bool> alimentLibre; // servi à volonté partout
  final double totalG;
  final double? kcalServies; // null si non calculable
  final List<String> sansKcal; // aliments sans valeur énergétique
  final bool recoDisponible;
  final double? ecartPct;
  final List<double?> fabricant; // g/jour par aliment
  final List<String> avertissements;
  const CalculRation({
    required this.besoin, required this.lignes, required this.totalParAliment, required this.alimentLibre,
    required this.totalG, this.kcalServies, this.sansKcal = const [], this.recoDisponible = false,
    this.ecartPct, this.fabricant = const [], this.avertissements = const [],
  });
  bool get ecartImportant => ecartPct != null && ecartPct!.abs() > 15;
}

const _poidsTypes = <String, double>{
  'foin': 67, 'concentre': 28, 'complement': 5, 'granules': 90, 'menagere': 90, 'legumes': 10,
};

CalculRation calculerRation(PlanAlimentation plan, ProfilAnimal animal, {double? poidsObjectif}) {
  final profil = profilEspece(animal.espece);
  final besoin = calculerBesoin(animal,
      activite: plan.activite, poidsObjectif: poidsObjectif, poidsAdulte: plan.poidsAdulte, nbPetits: plan.nbPetits);
  final n = plan.repas.length;
  final nAlim = plan.aliments.length;
  // Nombre de repas où chaque aliment est servi avec une quantité.
  final repasParAliment = List<int>.filled(nAlim, 0);
  for (final r in plan.repas) {
    for (final it in r.items) { if (!it.libre) repasParAliment[it.a]++; }
  }

  // Recommandation journalière par aliment (méthodes poids vif / lapin).
  final recoJour = List<double?>.filled(nAlim, null);
  if (besoin.manque == null) {
    if (profil.methode == 'poids_vif' && besoin.totalG != null) {
      final types = <String>{for (var i = 0; i < nAlim; i++) if (repasParAliment[i] > 0) plan.aliments[i].type};
      final somme = types.fold<double>(0, (s, t) => s + (_poidsTypes[t] ?? 0));
      if (somme > 0) {
        for (final t in types) {
          final idx = [for (var i = 0; i < nAlim; i++) if (plan.aliments[i].type == t && repasParAliment[i] > 0) i];
          final part = besoin.totalG! * (_poidsTypes[t] ?? 0) / somme / idx.length;
          if ((_poidsTypes[t] ?? 0) > 0) { for (final i in idx) { recoJour[i] = part; } }
        }
      }
    } else if (profil.methode == 'lapin' && (animal.poidsKg ?? 0) > 0) {
      final pk = poidsObjectif ?? animal.poidsKg!;
      for (final t in ['granules', 'legumes']) {
        final idx = [for (var i = 0; i < nAlim; i++) if (plan.aliments[i].type == t && repasParAliment[i] > 0) i];
        for (final i in idx) { recoJour[i] = pk * (t == 'granules' ? 22.5 : 50) / idx.length; }
      }
    }
  }

  final lignes = <List<LigneRation>>[];
  for (var i = 0; i < n; i++) {
    final r = plan.repas[i];
    final aQuantite = r.items.where((it) => !it.libre).toList();
    final energieOk = profil.methode == 'energie' && besoin.kcal != null &&
        aQuantite.isNotEmpty && aQuantite.every((it) => (plan.aliments[it.a].kcal ?? 0) > 0);
    lignes.add([
      for (final it in r.items)
        () {
          if (it.libre) return LigneRation(a: it.a, libre: true);
          double? reco;
          if (profil.methode == 'energie') {
            if (energieOk) reco = besoin.kcal! / n / aQuantite.length * 100 / plan.aliments[it.a].kcal!;
          } else if (recoJour[it.a] != null && repasParAliment[it.a] > 0) {
            reco = recoJour[it.a]! / repasParAliment[it.a];
          }
          return LigneRation(a: it.a, reco: reco, eff: it.g ?? reco, perso: it.g != null);
        }(),
    ]);
  }

  final total = List<double>.filled(nAlim, 0);
  final servi = List<bool>.filled(nAlim, false);
  final libreSeul = List<bool>.filled(nAlim, true);
  for (final l in lignes) {
    for (final x in l) {
      servi[x.a] = true;
      if (!x.libre) { libreSeul[x.a] = false; total[x.a] += x.eff ?? 0; }
    }
  }
  final sansKcal = <String>[];
  double kcal = 0;
  for (var i = 0; i < nAlim; i++) {
    if (!servi[i] || libreSeul[i]) continue;
    final k = plan.aliments[i].kcal;
    if (k == null || k <= 0) { sansKcal.add(plan.aliments[i].nom); } else { kcal += total[i] * k / 100; }
  }
  final toutesLignes = lignes.expand((l) => l).where((x) => !x.libre).toList();
  final recoDispo = besoin.manque == null && toutesLignes.isNotEmpty && toutesLignes.every((x) => x.reco != null);
  final calcEnergie = profil.methode == 'energie';
  final kcalServies = calcEnergie && sansKcal.isEmpty && toutesLignes.every((x) => x.eff != null) ? kcal : null;

  double? ecart;
  if (calcEnergie && kcalServies != null && besoin.kcal != null && besoin.kcal! > 0) {
    ecart = (kcalServies - besoin.kcal!) / besoin.kcal! * 100;
  } else if (!calcEnergie && recoDispo) {
    final reco = toutesLignes.fold<double>(0, (s, x) => s + x.reco!);
    final eff = toutesLignes.fold<double>(0, (s, x) => s + (x.eff ?? 0));
    if (reco > 0) ecart = (eff - reco) / reco * 100;
  }

  final avert = <String>[if (besoin.avertissement != null) besoin.avertissement!];
  final maxConcentre = animal.espece == 'cheval' || animal.espece == 'ane' ? 2500.0
      : (animal.espece == 'ovin' || animal.espece == 'caprin') ? 1500.0 : null;
  if (maxConcentre != null) {
    for (var i = 0; i < n; i++) {
      final g = lignes[i].where((x) => plan.aliments[x.a].type == 'concentre').fold<double>(0, (s, x) => s + (x.eff ?? 0));
      if (g > maxConcentre) {
        avert.add('${libellesRepas(n)[i]} : ${formatQuantite(g, kg: true)} de concentrés en un repas, au-delà de ${formatQuantite(maxConcentre, kg: true)} le risque digestif augmente. Ajoutez un repas ou réduisez la quantité.');
      }
    }
  }

  return CalculRation(
    besoin: besoin,
    lignes: lignes,
    totalParAliment: total,
    alimentLibre: [for (var i = 0; i < nAlim; i++) servi[i] && libreSeul[i]],
    totalG: total.fold(0, (s, x) => s + x),
    kcalServies: kcalServies,
    sansKcal: sansKcal,
    recoDisponible: recoDispo,
    ecartPct: ecart,
    fabricant: [
      for (final a in plan.aliments)
        recommandationFabricant(a, animal, croissance: besoin.croissance, poidsAdulte: plan.poidsAdulte),
    ],
    avertissements: avert,
  );
}

// ── Contrôles d'étape ─────────────────────────────────────────────────────

/// Message bloquant de l'étape (1 à 6), sinon null. [saisiesInvalides] :
/// erreurs de saisie des quantités (« repas-item » → message).
String? erreurEtape(int etape, PlanAlimentation plan, CalculRation c,
    {String objectifTexte = '', String poidsAdulteTexte = '', bool ecartConfirme = false,
    Map<String, String> saisiesInvalides = const {}}) {
  switch (etape) {
    case 1:
      if (plan.categories.isEmpty) return 'Choisissez au moins un type d’alimentation.';
      return null;
    case 2:
      final o = lireNombre(objectifTexte);
      if (o.err != null) return 'Objectif de poids : ${o.err}';
      final pa = lireNombre(poidsAdulteTexte);
      if (pa.err != null) return 'Poids adulte estimé : ${pa.err}';
      return null;
    case 3:
      if (plan.mode == 'unique' && plan.aliments.length != 1) return 'Sélectionnez un aliment.';
      if (plan.mode == 'mixte' && plan.aliments.length < 2) return 'Une alimentation mixte comporte au moins deux aliments.';
      return null;
    case 4:
      final labels = libellesRepas(plan.repas.length);
      for (var i = 0; i < plan.repas.length; i++) {
        if (plan.repas[i].items.isEmpty) {
          return 'Vous avez renseigné ${plan.repas.length} repas, mais aucun aliment pour le repas « ${labels[i]} ».';
        }
      }
      for (var a = 0; a < plan.aliments.length; a++) {
        if (!plan.repas.any((r) => r.items.any((it) => it.a == a))) {
          return '« ${plan.aliments[a].nom} » n’est servi à aucun repas : cochez-le ou retirez-le à l’étape 3.';
        }
      }
      return null;
    case 5:
      if (saisiesInvalides.isNotEmpty) return 'Corrigez les quantités signalées en rouge.';
      final labels = libellesRepas(plan.repas.length);
      for (var i = 0; i < c.lignes.length; i++) {
        for (final x in c.lignes[i]) {
          if (!x.libre && x.eff == null) {
            return '${labels[i]} : indiquez la quantité de « ${plan.aliments[x.a].nom} » (pas de recommandation possible).';
          }
        }
      }
      if (c.ecartImportant && !ecartConfirme) {
        return 'Cette ration est très différente de l’estimation PetsMatch. Vérifiez les quantités avant de confirmer.';
      }
      return null;
  }
  return null;
}

// ── Énergie d'un aliment ajouté ───────────────────────────────────────────

class EvaluationEnergie {
  String? err;
  String? warn;
  String? info;
  double? kcal;
  bool ok = false;
  bool estime = false;
  Map<String, String> erreursChamps = {};
  Map<String, double> composition = {};
}

const kChampsComposition = <(String, String)>[
  ('proteines', 'Protéines'), ('matieres_grasses', 'Matières grasses'), ('fibres', 'Fibres brutes'),
  ('cendres', 'Cendres brutes'), ('humidite', 'Humidité'), ('glucides', 'Glucides (si indiqués)'),
];

const _typesDe = <String, String>{
  'croquettes': 'des croquettes', 'patee': 'une pâtée', 'barf': 'du BARF',
  'menagere': 'une ration ménagère', 'autre': 'cet aliment',
};

/// [methode] : 'A' (kcal connues), 'B' (composition), 'C' (aucune info).
EvaluationEnergie evaluerEnergie({
  required String methode, required String type, String kcalTexte = '', String unite = '100g',
  Map<String, String> compo = const {},
}) {
  final out = EvaluationEnergie();
  final plage = kPlagesKcal[type] ?? kPlagesKcal['autre']!;
  void plausible(double v) {
    if (v < plage.$1 || v > plage.$2) {
      out.warn = 'La valeur énergétique semble inhabituelle pour ${_typesDe[type] ?? 'cet aliment'} '
          '(habituellement ${plage.$1.round()} à ${plage.$2.round()} kcal/100 g). Vérifiez si elle est indiquée pour 100 g ou pour 1 kg.';
    }
  }

  if (methode == 'A') {
    final p = lireNombre(kcalTexte);
    if (p.err != null) { out.err = p.err; return out; }
    if (p.v == null) return out;
    final v = unite == 'kg' ? p.v! / 10 : p.v!;
    if (v >= 1000) {
      out.err = unite == 'kg'
          ? 'Valeur trop élevée, même pour 1 kg : vérifiez le chiffre recopié.'
          : 'Valeur trop élevée pour 100 g : elle est sans doute indiquée pour 1 kg. Sélectionnez alors « kcal/kg ».';
      return out;
    }
    if (unite == 'kg') out.info = '${p.v!.round()} kcal/kg = ${_fr1(v)} kcal/100 g';
    plausible(v);
    out.kcal = (v * 10).round() / 10;
    out.ok = true;
    return out;
  }
  if (methode == 'B') {
    final vals = <String, double>{};
    for (final (k, _) in kChampsComposition) {
      final q = lireNombre(compo[k], zeroAutorise: true);
      if (q.err != null) {
        out.erreursChamps[k] = q.err!;
      } else if (q.v != null && q.v! > 100) {
        out.erreursChamps[k] = 'Un pourcentage est compris entre 0 et 100.';
      } else if (q.v != null) {
        vals[k] = q.v!;
      }
    }
    if (out.erreursChamps.isNotEmpty) return out;
    out.composition = vals;
    final somme = vals.values.fold<double>(0, (s, x) => s + x);
    if (somme > 100.5) {
      out.err = 'La somme des pourcentages dépasse 100 %. Vérifiez les valeurs recopiées sur l’emballage.';
      return out;
    }
    if (vals['proteines'] == null || vals['matieres_grasses'] == null) {
      if (vals.isNotEmpty) out.info = 'Protéines et matières grasses sont nécessaires à l’estimation.';
      return out;
    }
    double gluc;
    if (vals['glucides'] != null) {
      gluc = vals['glucides']!;
    } else {
      final manquants = ['fibres', 'cendres', 'humidite'].where((k) => vals[k] == null).toList();
      if (manquants.isNotEmpty) {
        final lib = {for (final (k, l) in kChampsComposition) k: l.toLowerCase()};
        out.info = 'Encore à remplir pour estimer les glucides : ${manquants.map((k) => lib[k]).join(', ')} (ou indiquez directement les glucides).';
        return out;
      }
      gluc = 100 - (vals['proteines']! + vals['matieres_grasses']! + vals['fibres']! + vals['cendres']! + vals['humidite']!);
      if (gluc < -0.5) {
        out.err = 'Les glucides calculés par différence seraient négatifs : vérifiez les valeurs recopiées.';
        return out;
      }
      gluc = math.max(0, gluc);
    }
    final industriel = type == 'croquettes' || type == 'patee';
    final v = industriel
        ? 3.5 * vals['proteines']! + 8.5 * vals['matieres_grasses']! + 3.5 * gluc
        : 4 * vals['proteines']! + 9 * vals['matieres_grasses']! + 4 * gluc;
    if (v <= 0) { out.err = 'Estimation impossible avec ces valeurs.'; return out; }
    out.info = 'Estimation : ${v.round()} kcal/100 g'
        '${vals['glucides'] == null ? ' (glucides estimés par différence : ${_fr1(gluc)} %)' : ''}. '
        '${industriel ? 'Méthode Atwater modifiée (NRC 2006), adaptée aux aliments industriels.' : 'Méthode Atwater (4-9-4) : estimation moins précise pour un aliment cru ou maison.'} '
        'Ce n’est pas une valeur certifiée par le fabricant.';
    plausible(v);
    out.kcal = v.roundToDouble();
    out.ok = true;
    out.estime = true;
    return out;
  }
  if (methode == 'C') out.ok = true;
  return out;
}

// ── Gestation / lactation détectées ───────────────────────────────────────

class EtatRepro {
  /// 'normal' | 'gestation_debut' | 'gestation_fin' | 'lactation'
  final String etat;
  final int? semaine;
  final int? nbPetits;
  /// Date de mise bas retenue (« yyyy-MM-dd »).
  final String? miseBas;
  /// D'où vient le nombre de petits, à afficher.
  final String? source;
  const EtatRepro(this.etat, {this.semaine, this.nbPetits, this.miseBas, this.source});
}

const _dureesGestation = {'chien': 63, 'chat': 65, 'cheval': 340, 'ane': 365, 'ovin': 150, 'caprin': 150, 'porcin': 114, 'lapin': 31};
/// Petits qui ne tètent plus : décédés ou déjà partis.
const _statutsHorsPortee = {'decede', 'sorti', 'adopte'};

String _jourIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _jourFr(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// État reproducteur d'une femelle à partir de sa dernière gestation (onglet
/// Repro : `date` = saillie, `date_naissance` = mise bas, `nb_nes`) et des
/// portées dont elle est la mère (fiches des petits : `portee_id`,
/// `date_naissance`, `statut`). La portée la plus récente fait foi pour la
/// mise bas et le nombre de petits encore présents, même si la gestation
/// n'a pas été mise à jour. Lactation jusqu'à 8 semaines.
EtatRepro detecterReproduction({required String espece, Map? gestation, List portees = const [], DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  DateTime? jour(Object? v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }
  final saillie = jour(gestation?['date']);
  final miseBasG = jour(gestation?['date_naissance']);
  final nbNes = (gestation?['nb_nes'] as num?)?.toInt();

  // Portée la plus récente (regroupée par portee_id).
  final parPortee = <String, ({DateTime date, int presents, int total})>{};
  for (final r in portees.whereType<Map>()) {
    final d = jour(r['date_naissance']);
    final id = r['portee_id']?.toString();
    if (d == null || id == null || id.isEmpty) continue;
    final prev = parPortee[id];
    final present = !_statutsHorsPortee.contains(r['statut']?.toString());
    parPortee[id] = (date: prev?.date ?? d, presents: (prev?.presents ?? 0) + (present ? 1 : 0), total: (prev?.total ?? 0) + 1);
  }
  final derniere = parPortee.values.fold<({DateTime date, int presents, int total})?>(
      null, (m, p) => m == null || p.date.isAfter(m.date) ? p : m);

  DateTime? miseBas = miseBasG;
  int? nb = nbNes;
  String? source = nbNes != null ? 'Repris de la gestation ($nbNes nés)' : null;
  if (derniere != null && (miseBas == null || !derniere.date.isBefore(miseBas))) {
    miseBas = derniere.date;
    nb = derniere.presents;
    source = 'Repris de la portée née le ${_jourFr(derniere.date)} (${derniere.presents} petit${derniere.presents > 1 ? 's' : ''}'
        '${derniere.total > derniere.presents ? ' sur ${derniere.total} nés' : ''})';
  }

  if (saillie != null && (miseBas == null || miseBas.isBefore(saillie))) {
    final jours = now.difference(saillie).inDays;
    final total = _dureesGestation[espece] ?? 63;
    if (jours >= 0 && jours <= total + 7) return EtatRepro(jours >= total - 21 ? 'gestation_fin' : 'gestation_debut');
    return const EtatRepro('normal');
  }
  if (miseBas != null) {
    final jours = now.difference(miseBas).inDays;
    if (jours >= 0 && jours < 56) {
      return EtatRepro('lactation', semaine: jours ~/ 7 + 1, nbPetits: nb, miseBas: _jourIso(miseBas), source: source);
    }
  }
  return const EtatRepro('normal');
}

// ── Lecture d'une ligne `alimentations` ───────────────────────────────────

/// Plan de la ligne : colonne `plan` si elle est à jour, sinon reconstitué
/// depuis l'ancien format (type_ration, marque, notes « …|nbRepas|… »).
/// null : rien d'exploitable.
PlanAlimentation? planDepuisLigne(Map<String, dynamic>? row, String espece) {
  if (row == null) return null;
  final brut = row['plan'];
  if (brut is Map) {
    final plan = PlanAlimentation.fromJson(Map<String, dynamic>.from(brut));
    // Réenregistré depuis une ancienne version de l'appli après le plan ?
    final enr = DateTime.tryParse(brut['enregistre_le']?.toString() ?? '');
    final maj = DateTime.tryParse(row['updated_at']?.toString() ?? '');
    final perime = enr != null && maj != null && maj.difference(enr).inSeconds > 30;
    if (plan.aliments.isNotEmpty && !perime) return plan;
  }
  return _planAncien(row, espece);
}

PlanAlimentation? _planAncien(Map<String, dynamic> row, String espece) {
  final profil = profilEspece(espece);
  final type = (row['type_ration'] ?? '').toString();
  final notes = (row['notes'] ?? '').toString();
  final parts = notes.contains('|') ? notes.split('|') : <String>[];
  String part(int i) => i < parts.length ? parts[i].trim() : '';
  double? nombre(Object? v) {
    final d = double.tryParse(v?.toString().replaceAll(',', '.') ?? '');
    return d != null && d > 0 ? d : null;
  }

  final nb = ((row['nb_repas'] as num?)?.toInt() ?? int.tryParse(part(3)) ?? 2).clamp(1, 4);
  final marque = (row['marque'] ?? '').toString().trim();
  final gamme = (row['gamme'] ?? '').toString().trim();
  final densite = nombre(row['densite_calorique']) ?? nombre(part(11));
  final marqueId = row['marque_id']?.toString();
  final plan = PlanAlimentation(activite: activiteDepuisAncienne(row['niveau_activite']?.toString()), repris: true,
      repas: List.generate(nb, (_) => RepasPlan()));
  AlimentPlan produit(String typeDefaut, String libelle, {double? kcal}) => AlimentPlan(
      id: marqueId, marque: marque.isNotEmpty ? marque : libelle, gamme: marque.isNotEmpty ? gamme : '',
      type: typeDefaut, kcal: kcal, source: kcal != null ? 'fabricant' : null);
  final ration1 = nombre(row['ration_grammes']) ?? nombre(part(5));
  final ration2 = nombre(row['ration2_grammes']) ?? nombre(part(6));

  void servirPartout(int a, double? jour, {bool libre = false}) {
    for (final r in plan.repas) { r.items.add(ItemRepas(a, libre: libre, g: jour != null ? jour / nb : null)); }
  }

  if (profil.methode == 'energie') {
    switch (type) {
      case 'barf':
        plan.aliments.add(AlimentPlan(marque: 'BARF', gamme: 'préparation', type: 'barf', repartition: {
          'muscles': (row['pourcentage_muscles'] as num?)?.toDouble() ?? 70,
          'abats': (row['pourcentage_abats'] as num?)?.toDouble() ?? 10,
          'os': (row['pourcentage_os'] as num?)?.toDouble() ?? 10,
          'legumes': (row['pourcentage_legumes'] as num?)?.toDouble() ?? 10,
        }));
        servirPartout(0, ration1);
      case 'menagere':
        plan.aliments.add(AlimentPlan(marque: 'Ration ménagère', type: 'menagere', repartition: Map.of(kRepartitionMenagere)));
        servirPartout(0, ration1);
      case 'mixte':
        plan.mode = 'mixte';
        plan.aliments.add(produit('croquettes', 'Croquettes', kcal: densite));
        final t2 = part(7).isEmpty ? 'patee' : part(7);
        final kcal2 = t2 == 'patee' ? nombre(part(8)) : null;
        plan.aliments.add(AlimentPlan(
            marque: t2 == 'barf' ? 'BARF' : t2 == 'menagere' ? 'Ration ménagère' : 'Pâtée',
            type: t2 == 'barf' ? 'barf' : t2 == 'menagere' ? 'menagere' : 'patee',
            kcal: kcal2, source: kcal2 != null ? 'fabricant' : null));
        final separe = part(4) == '1' && nb >= 2;
        if (separe) {
          final pct = (row['mixte_ratio_croq'] as num?)?.toDouble() ?? nombre(part(10)) ?? 50;
          final nCroq = (nb * pct / 100).round().clamp(1, nb - 1);
          for (var i = 0; i < nb; i++) {
            final a = i < nCroq ? 0 : 1;
            final jour = a == 0 ? ration1 : ration2;
            final nRepas = a == 0 ? nCroq : nb - nCroq;
            plan.repas[i].items.add(ItemRepas(a, g: jour != null ? jour / nRepas : null));
          }
        } else {
          servirPartout(0, ration1);
          servirPartout(1, ration2);
        }
      default:
        if (type.isEmpty && marque.isEmpty) return null;
        plan.aliments.add(produit('croquettes', 'Croquettes', kcal: densite));
        servirPartout(0, ration1);
    }
  } else {
    // Autres espèces : mêmes compositions que l'ancien onglet.
    final total = ration1;
    final pctFoin = nombre(part(0)) ?? 67, pctGran = nombre(part(1)) ?? 28, pctComp = nombre(part(2)) ?? 0;
    final sommePct = pctFoin + pctGran + pctComp;
    double? partDe(double pct) => total != null ? total * pct / sommePct : null;
    switch (espece) {
      case 'lapin':
        plan.aliments.add(AlimentPlan(marque: 'Foin', type: 'foin'));
        servirPartout(0, null, libre: true);
        plan.aliments.add(produit('granules', 'Granulés', kcal: densite));
        servirPartout(1, null);
        if (type != 'granules') {
          plan.mode = 'mixte';
          plan.aliments.add(AlimentPlan(marque: 'Légumes frais', type: 'legumes'));
          servirPartout(2, null);
        }
      case 'oiseau':
        plan.aliments.add(produit(type == 'granules' ? 'granules' : 'graines', type == 'granules' ? 'Granulés' : 'Graines / mélange'));
        servirPartout(0, total);
      case 'porcin':
        plan.aliments.add(type == 'menagere'
            ? AlimentPlan(marque: 'Ration ménagère', type: 'menagere')
            : produit('granules', 'Aliment complet'));
        servirPartout(0, total);
      default:
        if (type == 'paturage') {
          plan.aliments.add(AlimentPlan(marque: 'Pâturage', type: 'paturage'));
          servirPartout(0, null, libre: true);
        } else if (type == 'complement') {
          plan.aliments.add(produit('complement', 'Complément'));
          servirPartout(0, total);
        } else if (type == 'foin') {
          plan.aliments.add(AlimentPlan(marque: 'Foin / fourrage', type: 'foin'));
          servirPartout(0, total);
        } else if (profil.types.contains('concentre')) {
          plan.mode = 'mixte';
          plan.aliments.add(AlimentPlan(marque: 'Foin / fourrage', type: 'foin'));
          servirPartout(0, partDe(pctFoin));
          plan.aliments.add(produit('concentre', 'Granulés / concentrés'));
          servirPartout(1, partDe(pctGran));
          if (pctComp > 0) {
            plan.aliments.add(AlimentPlan(marque: 'Complément', type: 'complement'));
            servirPartout(2, partDe(pctComp));
          }
        } else {
          if (type.isEmpty && marque.isEmpty) return null;
          plan.aliments.add(produit(profil.types.first, kLibellesTypeAliment[profil.types.first]!));
          servirPartout(0, total);
        }
    }
  }
  plan.categories = {for (final a in plan.aliments) a.type}.toList();
  if (plan.aliments.length > 1) plan.mode = 'mixte';
  return plan;
}

/// Colonnes historiques, encore lues par d'anciens écrans.
Map<String, dynamic> colonnesHistoriques(PlanAlimentation plan, CalculRation c) {
  final a0 = plan.aliments.isNotEmpty ? plan.aliments.first : null;
  return {
    'type_ration': plan.aliments.length > 1 ? 'mixte' : (a0?.type ?? 'croquettes'),
    'niveau_activite': plan.activite,
    'phase_vie': 'auto',
    'marque_id': a0?.id,
    'marque': a0?.marque,
    'gamme': (a0?.gamme ?? '').isEmpty ? null : a0!.gamme,
    'densite_calorique': a0?.kcal,
    'nb_repas': plan.repas.length,
    'ration_grammes': c.totalParAliment.isNotEmpty && c.totalParAliment[0] > 0 ? c.totalParAliment[0].round() : null,
    'ration2_grammes': c.totalParAliment.length > 1 && c.totalParAliment[1] > 0 ? c.totalParAliment[1].round() : null,
    'ration_kcal': c.kcalServies?.round(),
  };
}

/// Pour la vue lecture seule (pros) : quantités enregistrées, sans recalcul.
CalculRation calculEnregistre(PlanAlimentation plan) {
  final lignes = [
    for (final r in plan.repas)
      [for (final it in r.items) LigneRation(a: it.a, libre: it.libre, eff: it.gEnregistre ?? it.g, perso: it.g != null)],
  ];
  final total = List<double>.filled(plan.aliments.length, 0);
  final libreSeul = List<bool>.filled(plan.aliments.length, true);
  final servi = List<bool>.filled(plan.aliments.length, false);
  for (final l in lignes) {
    for (final x in l) {
      servi[x.a] = true;
      if (!x.libre) { libreSeul[x.a] = false; total[x.a] += x.eff ?? 0; }
    }
  }
  return CalculRation(
    besoin: const Besoin(),
    lignes: lignes,
    totalParAliment: total,
    alimentLibre: [for (var i = 0; i < total.length; i++) servi[i] && libreSeul[i]],
    totalG: total.fold(0, (s, x) => s + x),
  );
}
