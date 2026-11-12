// Tableau de bord éleveur (accueil de l'appli, pages/eleveur/eleveur_dashboard.dart) :
// LECTURE SEULE des modules existants, rien n'est créé. Chaque élément
// n'apparaît que dans un bloc :
//   • À faire  : tâches manuelles (taches_elevage) + tâches de protocole qui
//                ne sont pas des soins ;
//   • Soins    : rappels du CARNET (vaccinations / vermifuges / antiparasitaires,
//                dernière ligne de chaque soin, règle de functions/sante.js), soins des
//                protocoles (plan_taches, type_acte sanitaire) et tâches
//                « Vaccin — … » des rappels (masquées si le rappel du carnet du
//                même jour est listé). Les copies d'agenda « Rappel vaccin — … »
//                ne sont pas reprises ;
//   • Agenda   : autres événements + RDV vétérinaires à venir ;
//   • Activité : contrats à envoyer / à signer, demandes de récupération.
// Filtres de profil : ceux de l'agenda (agenda_page.dart _loadTasks).
// Miroir site : website/src/lib/tableau-bord-eleveur.ts.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/cloisonnement_profils.dart';

typedef _Filtre = PostgrestFilterBuilder<List<Map<String, dynamic>>>;
typedef _Transf = PostgrestTransformBuilder<List<Map<String, dynamic>>>;

const kHorizonJours = 7;
const kActesCarnet = ['vermifuge', 'antiparasitaire', 'vaccination', 'traitement'];

/// Où mène une ligne : le jour de l'agenda, le planning du jour des
/// protocoles (validation d'un soin avec inscription au carnet), ou l'onglet
/// Santé de la fiche de l'animal (rappel du carnet).
/// tacheSoin : tâche « rappel du carnet » (brut = la tâche) — carnet vérifié,
/// puis formulaire de soin (lib/utils/soin_depuis_tache.dart).
enum CibleTB { jour, planning, fiche, animaux, soin, protocole, tacheSoin }

/// Rappel du carnet : de quoi ouvrir le formulaire de soin prérempli (PorteeSoinSheet).
class SoinTB {
  final String typeActe; // vaccination | vermifuge | antiparasitaire
  final String produit;
  final List<String> animalIds;
  final int? ecartJours; // intervalle habituel soin → rappel
  const SoinTB(this.typeActe, this.produit, this.animalIds, this.ecartJours);
}

class LigneTB {
  final String cle;
  final String titre;
  final DateTime date; // jour local, minuit
  final String? heure;
  final String? animal;
  final String? responsable;
  bool fait;
  final bool retard;
  final Color? couleur;
  final String? sousTitre;
  final CibleTB cible;
  /// Coche directe (tâches simples) : 'taches_elevage' ou 'plan_taches'.
  final String? tableCochable;
  final Map<String, dynamic>? brut;
  /// Rappel du carnet : animal (fiche) et clé jour|acte|animal.
  final String? animalId;
  final String? cleSoin;
  /// Rappel du carnet : jour|soin|produit — même clé = une ligne, animaux regroupés.
  final String? groupe;
  final SoinTB? soin;
  /// Soins d'un protocole le même jour (une ligne) : tâches non faites à valider ensemble.
  final List<Map<String, dynamic>>? protocole;
  LigneTB({
    required this.cle, required this.titre, required this.date, this.heure, this.animal,
    this.responsable, this.fait = false, this.retard = false, this.couleur, this.sousTitre,
    this.cible = CibleTB.jour, this.tableCochable, this.brut, this.animalId, this.cleSoin, this.groupe, this.soin, this.protocole,
  });
}

class ContratTB {
  final String id, titre, statut;
  final String? animalNom;
  ContratTB(this.id, this.titre, this.statut, this.animalNom);
}

class DonneesTB {
  final List<LigneTB> aFaire, soins, agenda;
  final List<ContratTB> contrats;
  final List<String> recuperations; // noms des animaux
  DonneesTB(this.aFaire, this.soins, this.agenda, this.contrats, this.recuperations);
}

// Couleurs de l'agenda (agenda_page.dart / site TYPE_COLOR).
const _couleurType = <String, Color>{
  'rdv': Color(0xFF2196F3), 'mise_bas': Color(0xFFE91E63), 'medication': Color(0xFFFF9800),
  'visite': Color(0xFF4CAF50), 'formation': Color(0xFF7B1FA2), 'reunion': Color(0xFF0288D1),
  'absence': Color(0xFF78909C), 'autre': Color(0xFF9E9E9E),
};

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime _jour(String s) {
  final d = DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s) ?? DateTime.now();
  return DateTime(d.year, d.month, d.day);
}

/// Titres posés par les fonctions (« 💉 Vaccin — Luna ») : sans pictogramme à l'écran.
String sansPictos(String t) => t
    .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{2300}-\u{23FF}\u{2190}-\u{21FF}\u{2700}-\u{27BF}]', unicode: true), '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

final _acteTitre = RegExp(r'^(vaccin|vermifuge|antiparasitaire|traitement)s?\s+—\s+', caseSensitive: false);
final _acteRappel = RegExp(r'^rappel\s+(vaccin|vermifuge|antiparasitaire)\s+—\s+', caseSensitive: false);
String _acte(String titre, RegExp re) => (re.firstMatch(sansPictos(titre))?.group(1) ?? '').toLowerCase();

/// [animauxAssociation] : accueil de l'association — mêmes blocs, tâches de
/// l'association (profil_source), rappels du carnet de ces animaux (présents),
/// sans contrats ni récupérations. Miroir site chargerTableauBord({ association }).
Future<DonneesTB> chargerTableauBord({
  required String userUid, required String ownerUid, required String activeProfileId,
  List<String>? animauxAssociation,
}) async {
  final asso = animauxAssociation != null;
  final supa = Supabase.instance.client;
  final pid = activeProfileId;
  final maintenant = DateTime.now();
  final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
  final today = _ymd(aujourdhui);
  final end = _ymd(aujourdhui.add(const Duration(days: kHorizonJours)));

  const colsR = 'id,label,date_prevue,statut,type_acte,animal_nom,assigned_to,animal_id,etape_id,jour_traitement,total_jours,uid_eleveur';
  const colsT = 'id,titre,date,statut,heure,uid_eleveur,eleveur_profile_id,animal_id,animal_nom,assignes_a,assigne_a,rdv_veto_cabinet,rdv_veto_motif,notes';

  // Même règle que l'agenda : profile_id strict, sinon repli uid_eleveur + profil_source.
  Future<List> avecProfil(String table, _Filtre Function(_Filtre q) filtre,
      {required String cols, String? ordre, int limite = 300}) async {
    _Transf fin(_Filtre q) {
      final f = filtre(q);
      return ordre != null ? f.order(ordre, ascending: false).limit(limite) : f.limit(limite);
    }
    if (pid.isNotEmpty) {
      final List strict = await fin(supa.from(table).select(cols).eq('profile_id', pid));
      if (strict.isNotEmpty) return strict;
    }
    final repli = supa.from(table).select(cols).eq('uid_eleveur', ownerUid);
    return await fin(asso ? repli.eq('profil_source', 'association')
        : repli.or('profil_source.is.null,profil_source.eq.eleveur'));
  }

  _Filtre routinesAMoi() => pid.isNotEmpty
      ? supa.from('plan_taches').select(colsR).eq('assigned_profile_id', pid)
      : supa.from('plan_taches').select(colsR).eq('assigned_to', userUid);
  _Filtre tachesAMoi() => pid.isNotEmpty
      ? supa.from('taches_elevage').select(colsT).eq('assigne_profile_id', pid)
      : supa.from('taches_elevage').select(colsT).eq('assigne_a', userUid);
  final evQ = pid.isNotEmpty
      ? supa.from('agenda_events').select('id,titre,date_debut,type,animal_id').eq('pro_profile_id', pid)
      : supa.from('agenda_events').select('id,titre,date_debut,type,animal_id').eq('uid', userUid)
          .or('pro_profile_id.is.null,pro_profile_id.eq.');

  // Une requête en erreur ne bloque pas tout l'accueil : liste vide + journal.
  Future<dynamic> sur(Future<dynamic> f, String quoi) => f.catchError((Object e) {
        debugPrint('Tableau de bord éleveur, $quoi : $e');
        return quoi == 'equipe' ? <String, String>{} : <dynamic>[];
      });
  final carnetF = _rappelsCarnet(ownerUid, pid, aujourdhui, end, ids: animauxAssociation)
      .catchError((Object e) { debugPrint('Tableau de bord éleveur, carnet : $e'); return <LigneTB>[]; });

  final r = await Future.wait<dynamic>([
    sur(avecProfil('plan_taches', (q) => q.gte('date_prevue', today).lte('date_prevue', end), cols: colsR), 'protocoles'),
    sur(avecProfil('plan_taches', (q) => q.neq('statut', 'fait').lt('date_prevue', today), cols: colsR, ordre: 'date_prevue', limite: 200), 'protocoles en retard'),
    sur(routinesAMoi().gte('date_prevue', today).lte('date_prevue', end).limit(300), 'protocoles assignés'),
    sur(routinesAMoi().neq('statut', 'fait').lt('date_prevue', today).limit(200), 'protocoles assignés en retard'),
    sur(avecProfil('taches_elevage', (q) => q.gte('date', today).lte('date', end), cols: colsT), 'tâches'),
    sur(avecProfil('taches_elevage', (q) => q.neq('statut', 'fait').lt('date', today), cols: colsT, ordre: 'date', limite: 200), 'tâches en retard'),
    sur(tachesAMoi().gte('date', today).lte('date', end).limit(300), 'tâches assignées'),
    sur(tachesAMoi().neq('statut', 'fait').lt('date', today).limit(200), 'tâches assignées en retard'),
    sur(evQ.gte('date_debut', aujourdhui.toUtc().toIso8601String())
        .lte('date_debut', DateTime.parse('${end}T23:59:59').toUtc().toIso8601String())
        .order('date_debut').limit(300), 'agenda'),
    sur(_membres(ownerUid, userUid, source: asso ? 'association' : 'eleveur'), 'equipe'),
    // Contrats de l'élevage (contrat_reservation.dart) qui attendent une action.
    asso ? Future.value(<dynamic>[]) : sur(supa.from('documents_animaux').select('id,titre,statut,animal_id,created_at')
        .eq('uid_eleveur', ownerUid)
        .inFilter('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession', 'contrat_saillie'])
        .inFilter('statut', ['brouillon', 'en_attente', 'partiellement_signe'])
        .order('created_at', ascending: false).limit(50), 'contrats'),
    // Demandes de récupération (recuperations_page.dart).
    asso ? Future.value(<dynamic>[]) : sur(supa.from('animal_recuperations').select('id,animal_id,created_at')
        .eq('eleveur_uid', ownerUid).eq('statut', 'en_attente')
        .order('created_at', ascending: false).limit(50), 'récupérations'),
  ]);

  List<Map<String, dynamic>> maps(dynamic l) => [for (final x in l as List) Map<String, dynamic>.from(x as Map)];
  final membres = r[9] as Map<String, String>;
  String? resp(dynamic uid) => uid == null ? null : membres[uid.toString()];

  final vusR = <String>{};
  final routines = [
    for (final x in [...maps(r[0]), ...maps(r[1]), ...maps(r[2]), ...maps(r[3])])
      if (vusR.add(x['id'].toString())) x
  ];
  // Cloisonnement : rien d'un autre profil du compte (eleveur_profile_id, animal).
  final vusT = <String>{};
  final taches = await sansAnimauxAutresProfils([
    for (final t in [...maps(r[4]), ...maps(r[5]), ...maps(r[6]), ...maps(r[7])])
      if (pid.isEmpty || (t['eleveur_profile_id']?.toString() ?? '').isEmpty || t['eleveur_profile_id'].toString() == pid)
        if (vusT.add(t['id'].toString())) t
  ], pid);
  final evenements = await sansAnimauxAutresProfils(maps(r[8]), pid);

  final aFaire = <LigneTB>[], soins = <LigneTB>[], agenda = <LigneTB>[];

  // Soins d'un protocole : une ligne par étape et par jour (tous les animaux),
  // validée en une fois depuis l'accueil (carnet + registre). Miroir site.
  final groupesProto = <String, List<Map<String, dynamic>>>{};
  for (final x in routines) {
    final date = _jour(x['date_prevue'].toString());
    final fait = x['statut'] == 'fait';
    final titre = sansPictos((x['label'] ?? 'Tâche').toString());
    if (kActesCarnet.contains(x['type_acte']?.toString() ?? '')) {
      groupesProto.putIfAbsent('${_ymd(date)}|${x['etape_id'] ?? titre}', () => []).add(x);
    } else {
      aFaire.add(LigneTB(cle: 'r_${x['id']}', titre: titre, date: date, animal: x['animal_nom']?.toString(),
          responsable: resp(x['assigned_to']), fait: fait, retard: !fait && date.isBefore(aujourdhui),
          tableCochable: 'plan_taches', brut: x));
    }
  }
  for (final e in groupesProto.entries) {
    final g = e.value;
    final date = _jour(g.first['date_prevue'].toString());
    final restantes = [for (final r in g) if (r['statut'] != 'fait') r];
    final fait = restantes.isEmpty;
    soins.add(LigneTB(cle: 'p_${e.key}', titre: sansPictos((g.first['label'] ?? 'Soin').toString()), date: date,
        animal: g.map((r) => r['animal_nom']?.toString() ?? '').where((n) => n.isNotEmpty).join(', '),
        responsable: resp(g.first['assigned_to']), fait: fait, retard: !fait && date.isBefore(aujourdhui),
        sousTitre: fait ? 'Protocole — fait' : 'Protocole${g.length > 1 ? ' — ${restantes.length}/${g.length} à faire' : ''}',
        cible: fait ? CibleTB.planning : CibleTB.protocole, protocole: restantes));
  }

  final carnet = await carnetF;
  soins.addAll(_grouperRappels(carnet));
  final soinsDuJour = {for (final l in carnet) l.cleSoin!};
  for (final t in taches) {
    final date = _jour(t['date'].toString());
    final fait = t['statut'] == 'fait';
    final assignes = t['assignes_a'] is List ? t['assignes_a'] as List : const [];
    final responsable = resp(t['assigne_a'] ?? (assignes.isNotEmpty ? assignes.first : null));
    final titre = sansPictos((t['titre'] ?? '').toString());
    final heure = t['heure']?.toString();
    if (t['rdv_veto_cabinet'] != null) {
      if (date.isBefore(aujourdhui) && fait) continue;
      agenda.add(LigneTB(cle: 't_${t['id']}', titre: titre, date: date, heure: heure,
          animal: t['animal_nom']?.toString(), responsable: responsable, fait: fait,
          retard: !fait && date.isBefore(aujourdhui), couleur: _couleurType['visite'],
          sousTitre: [t['rdv_veto_cabinet'], t['rdv_veto_motif']].where((v) => (v ?? '').toString().isNotEmpty).join(' · ')));
      continue;
    }
    final acte = _acte(t['titre']?.toString() ?? '', _acteTitre);
    final ligne = LigneTB(cle: 't_${t['id']}', titre: titre, date: date, heure: heure,
        animal: t['animal_nom']?.toString(), responsable: responsable, fait: fait,
        retard: !fait && date.isBefore(aujourdhui),
        sousTitre: acte.isNotEmpty ? 'Rappel du carnet' : null,
        cible: acte.isNotEmpty && !fait ? CibleTB.tacheSoin : CibleTB.jour,
        tableCochable: acte.isNotEmpty ? null : 'taches_elevage', brut: t);
    if (acte.isNotEmpty) {
      // Même rappel déjà listé depuis le carnet : la tâche du jour n'est pas répétée.
      if ((t['animal_id']?.toString() ?? '').isNotEmpty && soinsDuJour.contains('${_ymd(date)}|$acte|${t['animal_id']}')) continue;
      soins.add(ligne);
    } else {
      aFaire.add(ligne);
    }
  }

  for (final e in evenements) {
    final debut = DateTime.parse(e['date_debut'].toString()).toLocal();
    final date = DateTime(debut.year, debut.month, debut.day);
    // Copie d'agenda d'un rappel du carnet : déjà listée depuis le carnet.
    if (e['type'] == 'medication' && _acte(e['titre']?.toString() ?? '', _acteRappel).isNotEmpty) continue;
    if (date.isBefore(aujourdhui)) continue;
    final heure = debut.hour != 0 || debut.minute != 0
        ? '${debut.hour.toString().padLeft(2, '0')}:${debut.minute.toString().padLeft(2, '0')}' : null;
    agenda.add(LigneTB(cle: 'e_${e['id']}', titre: sansPictos(e['titre'].toString()), date: date, heure: heure,
        couleur: _couleurType[e['type']?.toString() ?? ''] ?? _couleurType['autre']));
  }

  // En retard d'abord, puis par jour et heure ; faites en dernier dans la journée.
  int tri(LigneTB a, LigneTB b) {
    if (a.retard != b.retard) return a.retard ? -1 : 1;
    final d = a.date.compareTo(b.date);
    if (d != 0) return d;
    if (a.fait != b.fait) return a.fait ? 1 : -1;
    final h = (a.heure ?? '99').compareTo(b.heure ?? '99');
    return h != 0 ? h : a.titre.compareTo(b.titre);
  }
  aFaire.sort(tri); soins.sort(tri); agenda.sort(tri);

  // Contrats et récupérations : seulement les animaux de CE profil.
  final contrats = await sansAnimauxAutresProfils(maps(r[10]), pid);
  final recups = await sansAnimauxAutresProfils(maps(r[11]), pid);
  final ids = {
    for (final x in [...contrats, ...recups])
      if ((x['animal_id']?.toString() ?? '').isNotEmpty) x['animal_id'].toString()
  };
  final noms = <String, String>{};
  if (ids.isNotEmpty) {
    try {
      final rows = await supa.from('animaux').select('id, nom').inFilter('id', ids.toList());
      for (final a in rows as List) { noms[a['id'].toString()] = (a['nom'] ?? '').toString(); }
    } catch (e) {
      debugPrint('Tableau de bord éleveur, noms des animaux : $e');
    }
  }

  return DonneesTB(aFaire, soins, agenda, [
    for (final c in contrats)
      ContratTB(c['id'].toString(), sansPictos((c['titre'] ?? 'Contrat').toString()), c['statut'].toString(),
          noms[c['animal_id']?.toString()]),
  ], [for (final x in recups) noms[x['animal_id']?.toString()] ?? 'Animal']);
}

// Tables du carnet avec date de rappel (functions/sante.js, TABLES).
const _carnet = [
  (table: 'vaccinations', acte: 'vaccin', libelle: 'Rappel vaccin', nom: 'vaccin', cols: 'id,animal_id,date,date_rappel,vaccin,categorie'),
  (table: 'vermifuges', acte: 'vermifuge', libelle: 'Rappel vermifuge', nom: 'produit', cols: 'id,animal_id,date,date_rappel,produit'),
  (table: 'antiparasitaires', acte: 'antiparasitaire', libelle: 'Rappel antiparasitaire', nom: 'produit', cols: 'id,animal_id,date,date_rappel,produit'),
];

// Rappel déjà renouvelé : un soin SAISI PLUS TARD pour le même animal (ou le
// même jour avec un rappel plus lointain) — vermifuge / antiparasitaire : quel
// que soit le nom saisi, comme functions/sante.js ; vaccin : même type
// (catégorie, sinon nom du vaccin). Un soin plus ANCIEN à rappel lointain ne
// masque pas le rappel d'un soin plus récent. Miroir site.
String _normTB(Object? v) => (v ?? '').toString().trim().toLowerCase();
String _typeVaccinTB(Map r) {
  final c = _normTB(r['categorie']);
  return c.isNotEmpty && c != 'autre' ? c : _normTB(r['vaccin']);
}
String _j10(Object? v) { final t = (v ?? '').toString(); return t.length >= 10 ? t.substring(0, 10) : t; }
bool _rappelRemplace(String table, Map r, List<Map> lignes) => lignes.any((x) {
      if (x['id']?.toString() == r['id']?.toString()) return false;
      if (table == 'vaccinations' && _typeVaccinTB(x) != _typeVaccinTB(r)
          && !(_normTB(r['vaccin']).isNotEmpty && _normTB(x['vaccin']) == _normTB(r['vaccin']))) { return false; }
      final dx = _j10(x['date']), dr = _j10(r['date']), rx = _j10(x['date_rappel']), rr = _j10(r['date_rappel']);
      if (dx.isEmpty || dr.isEmpty) return false;
      return dx.compareTo(dr) > 0 || (dx == dr && rx.isNotEmpty && rr.isNotEmpty && rx.compareTo(rr) > 0);
    });

/// Même rappel le même jour pour plusieurs animaux : une ligne (comme les notifications groupées).
List<LigneTB> _grouperRappels(List<LigneTB> lignes) {
  final groupes = <String, List<LigneTB>>{};
  for (final l in lignes) { groupes.putIfAbsent(l.groupe ?? l.cle, () => []).add(l); }
  return [
    for (final g in groupes.values)
      if (g.length == 1) g.first
      else LigneTB(cle: g.map((x) => x.cle).join('+'), titre: g.first.titre, date: g.first.date,
          animal: g.map((x) => x.animal).whereType<String>().join(', '), retard: g.first.retard,
          sousTitre: g.first.sousTitre, cible: CibleTB.soin, groupe: g.first.groupe,
          soin: g.first.soin == null ? null
              : SoinTB(g.first.soin!.typeActe, g.first.soin!.produit, [for (final x in g) ...?x.soin?.animalIds], g.first.soin!.ecartJours)),
  ];
}

/// Rappels du carnet à faire (en retard ou dans l'horizon) pour les animaux
/// présents du profil — mêmes animaux que le compteur « Animaux » de l'accueil.
/// Animaux présents du profil actif — même calcul que le compteur « Animaux » de l'accueil.
Future<List<String>> animauxDuProfil(String ownerUid, String pid) async {
  final supa = Supabase.instance.client;
  var q = supa.from('animaux_proprietes').select('animal_id').eq('uid_proprio', ownerUid).isFilter('date_fin', null);
  if (pid.isNotEmpty) {
    final check = await supa.from('animaux_proprietes').select('animal_id')
        .eq('uid_proprio', ownerUid).not('profile_id_proprio', 'is', null).limit(1);
    if ((check as List).isNotEmpty) q = q.eq('profile_id_proprio', pid);
  }
  return {for (final r in await q.limit(2000) as List) if (r['animal_id'] != null) r['animal_id'].toString()}.toList();
}

/// Articles d'inventaire du profil sous leur seuil d'alerte ou en rupture
/// (même règle que la page Inventaire et la notification « Stock bas »).
Future<int> stockBas({required String ownerUid, required String pid}) async {
  final supa = Supabase.instance.client;
  final rows = pid.isNotEmpty
      ? await supa.from('inventaire_items').select('quantite, quantite_alerte, alerte_active').eq('eleveur_profile_id', pid)
      : await supa.from('inventaire_items').select('quantite, quantite_alerte, alerte_active').eq('uid_eleveur', ownerUid);
  var n = 0;
  for (final i in rows as List) {
    final q = (i['quantite'] as num?)?.toDouble() ?? 0;
    final seuil = (i['quantite_alerte'] as num?)?.toDouble();
    if (q <= 0 || (i['alerte_active'] == true && seuil != null && q <= seuil)) n++;
  }
  return n;
}

const _typeSoin = {'vaccinations': 'vaccination', 'vermifuges': 'vermifuge', 'antiparasitaires': 'antiparasitaire'};

Future<List<LigneTB>> _rappelsCarnet(String ownerUid, String pid, DateTime aujourdhui, String end, {List<String>? ids}) async {
  final supa = Supabase.instance.client;
  ids ??= await animauxDuProfil(ownerUid, pid);
  if (ids.isEmpty) return [];
  final morceaux = [for (var i = 0; i < ids.length; i += 100) ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100)];
  final noms = <String, String>{};
  for (final m in morceaux) {
    final rows = await supa.from('animaux').select('id, nom').inFilter('id', m);
    for (final a in rows as List) { noms[a['id'].toString()] = (a['nom'] ?? '').toString(); }
  }
  final lignes = <LigneTB>[];
  for (final c in _carnet) {
    final rows = <Map<String, dynamic>>[];
    for (final m in morceaux) {
      try {
        final res = await supa.from(c.table).select(c.cols).inFilter('animal_id', m).limit(5000);
        rows.addAll([for (final x in res as List) Map<String, dynamic>.from(x as Map)]);
      } catch (e) {
        debugPrint('Tableau de bord éleveur, ${c.table} : $e');
      }
    }
    final parAnimal = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) { parAnimal.putIfAbsent(r['animal_id'].toString(), () => []).add(r); }
    for (final r in rows) {
      final rappel = (r['date_rappel']?.toString() ?? '');
      if (rappel.length < 10 || rappel.substring(0, 10).compareTo(end) > 0) continue;
      // Soin déjà renouvelé : plus rien à faire.
      if (_rappelRemplace(c.table, r, parAnimal[r['animal_id'].toString()] ?? const [])) continue;
      final date = _jour(rappel);
      final produit = (r[c.nom] ?? '').toString().trim();
      final animalId = r['animal_id'].toString();
      // Intervalle habituel (soin → rappel) : proposé pour le prochain rappel.
      final dSoin = DateTime.tryParse((r['date']?.toString() ?? '').length >= 10 ? r['date'].toString().substring(0, 10) : '');
      final ecart = dSoin == null ? null : date.difference(DateTime(dSoin.year, dSoin.month, dSoin.day)).inDays;
      lignes.add(LigneTB(cle: 'c_${c.table}_${r['id']}', titre: produit.isEmpty ? c.libelle : '${c.libelle} — $produit',
          date: date, animal: (noms[animalId] ?? '').isEmpty ? null : noms[animalId],
          retard: date.isBefore(aujourdhui), sousTitre: 'Carnet de santé', cible: CibleTB.soin,
          soin: SoinTB(_typeSoin[c.table]!, produit, [animalId], ecart != null && ecart > 0 ? ecart : null),
          animalId: animalId, cleSoin: '${_ymd(date)}|${c.acte}|$animalId',
          // Mots du produit triés : « Effitix Virbac » = « Virbac Effitix ».
          groupe: '${_ymd(date)}|${c.table}|${(produit.toLowerCase().split(RegExp(r'\s+'))..removeWhere((m) => m.isEmpty)..sort()).join(' ')}'));
    }
  }
  return lignes;
}

/// Noms de l'équipe (moi + employés avec compte) — miroir site loadMembres.
Future<Map<String, String>> _membres(String ownerUid, String moiUid, {String source = 'eleveur'}) async {
  final supa = Supabase.instance.client;
  String nom(Map? p, String repli) => p == null ? repli
      : (p['profile_type'] == 'eleveur' ? (p['nom'] ?? repli).toString()
          : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim().isEmpty ? repli
              : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim());
  try {
    final res = await Future.wait<dynamic>([
      supa.from('user_profiles_complet').select('firstname, lastname, nom, profile_type')
          .eq('uid', moiUid).eq('is_main', true).maybeSingle(),
      supa.from('employes').select('uid_employe, prenom, nom')
          .eq('uid_eleveur', ownerUid).eq('actif', true).eq('profil_source', source),
    ]);
    final m = <String, String>{moiUid: nom(res[0] as Map?, 'Moi')};
    final emp = [for (final e in res[1] as List) if (e['uid_employe'] != null) e];
    if (emp.isNotEmpty) {
      final profils = await supa.from('user_profiles_complet').select('uid, firstname, lastname, nom, profile_type')
          .inFilter('uid', [for (final e in emp) e['uid_employe'].toString()]).eq('is_main', true);
      final parUid = {for (final p in profils as List) p['uid'].toString(): p as Map};
      for (final e in emp) {
        final u = e['uid_employe'].toString();
        m[u] = nom(parUid[u], '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim().isEmpty ? 'Sans nom' : '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim());
      }
    }
    return m;
  } catch (_) {
    return {};
  }
}
