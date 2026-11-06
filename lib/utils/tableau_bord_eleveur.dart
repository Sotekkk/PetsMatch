// Tableau de bord éleveur (accueil de l'appli, pages/eleveur/eleveur_dashboard.dart) :
// LECTURE SEULE des modules existants, rien n'est créé. Chaque élément
// n'apparaît que dans un bloc :
//   • À faire  : tâches manuelles (taches_elevage) + tâches de protocole qui
//                ne sont pas des soins ;
//   • Soins    : soins des protocoles (plan_taches, type_acte sanitaire),
//                tâches « Vaccin — … » des rappels du carnet, rappels du
//                carnet dans l'agenda (agenda_events « Rappel vaccin — … ») ;
//                le rappel d'agenda est masqué s'il double une tâche du jour ;
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

/// Où mène une ligne : le jour de l'agenda, ou le planning du jour des
/// protocoles (validation d'un soin avec inscription au carnet).
enum CibleTB { jour, planning }

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
  LigneTB({
    required this.cle, required this.titre, required this.date, this.heure, this.animal,
    this.responsable, this.fait = false, this.retard = false, this.couleur, this.sousTitre,
    this.cible = CibleTB.jour, this.tableCochable, this.brut,
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

Future<DonneesTB> chargerTableauBord({
  required String userUid, required String ownerUid, required String activeProfileId,
}) async {
  final supa = Supabase.instance.client;
  final pid = activeProfileId;
  final maintenant = DateTime.now();
  final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
  final today = _ymd(aujourdhui);
  final end = _ymd(aujourdhui.add(const Duration(days: kHorizonJours)));
  final debutRetard = aujourdhui.subtract(const Duration(days: 90));

  const colsR = 'id,label,date_prevue,statut,type_acte,animal_nom,assigned_to';
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
    return await fin(supa.from(table).select(cols).eq('uid_eleveur', ownerUid)
        .or('profil_source.is.null,profil_source.eq.eleveur'));
  }

  _Filtre routinesAMoi() => pid.isNotEmpty
      ? supa.from('plan_taches').select(colsR).eq('assigned_profile_id', pid)
      : supa.from('plan_taches').select(colsR).eq('assigned_to', userUid);
  _Filtre tachesAMoi() => pid.isNotEmpty
      ? supa.from('taches_elevage').select(colsT).eq('assigne_profile_id', pid)
      : supa.from('taches_elevage').select(colsT).eq('assigne_a', userUid);
  final evQ = pid.isNotEmpty
      ? supa.from('agenda_events').select('id,titre,date_debut,type,animal_id,lieu').eq('pro_profile_id', pid)
      : supa.from('agenda_events').select('id,titre,date_debut,type,animal_id,lieu').eq('uid', userUid)
          .or('pro_profile_id.is.null,pro_profile_id.eq.');

  final r = await Future.wait<dynamic>([
    avecProfil('plan_taches', (q) => q.gte('date_prevue', today).lte('date_prevue', end), cols: colsR),
    avecProfil('plan_taches', (q) => q.neq('statut', 'fait').lt('date_prevue', today), cols: colsR, ordre: 'date_prevue', limite: 200),
    routinesAMoi().gte('date_prevue', today).lte('date_prevue', end).limit(300),
    routinesAMoi().neq('statut', 'fait').lt('date_prevue', today).limit(200),
    avecProfil('taches_elevage', (q) => q.gte('date', today).lte('date', end), cols: colsT),
    avecProfil('taches_elevage', (q) => q.neq('statut', 'fait').lt('date', today), cols: colsT, ordre: 'date', limite: 200),
    tachesAMoi().gte('date', today).lte('date', end).limit(300),
    tachesAMoi().neq('statut', 'fait').lt('date', today).limit(200),
    evQ.gte('date_debut', debutRetard.toUtc().toIso8601String())
        .lte('date_debut', DateTime.parse('${end}T23:59:59').toUtc().toIso8601String())
        .order('date_debut').limit(300),
    _membres(ownerUid, userUid),
    // Contrats de l'élevage (contrat_reservation.dart) qui attendent une action.
    supa.from('documents_animaux').select('id,titre,statut,animal_id,created_at')
        .eq('uid_eleveur', ownerUid)
        .inFilter('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession', 'contrat_saillie'])
        .inFilter('statut', ['brouillon', 'en_attente', 'partiellement_signe'])
        .order('created_at', ascending: false).limit(50),
    // Demandes de récupération (recuperations_page.dart).
    supa.from('animal_recuperations').select('id,animal_id,created_at')
        .eq('eleveur_uid', ownerUid).eq('statut', 'en_attente')
        .order('created_at', ascending: false).limit(50),
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

  for (final x in routines) {
    final date = _jour(x['date_prevue'].toString());
    final fait = x['statut'] == 'fait';
    final titre = sansPictos((x['label'] ?? 'Tâche').toString());
    if (kActesCarnet.contains(x['type_acte']?.toString() ?? '')) {
      soins.add(LigneTB(cle: 'r_${x['id']}', titre: titre, date: date, animal: x['animal_nom']?.toString(),
          responsable: resp(x['assigned_to']), fait: fait, retard: !fait && date.isBefore(aujourdhui),
          sousTitre: 'Protocole', cible: CibleTB.planning));
    } else {
      aFaire.add(LigneTB(cle: 'r_${x['id']}', titre: titre, date: date, animal: x['animal_nom']?.toString(),
          responsable: resp(x['assigned_to']), fait: fait, retard: !fait && date.isBefore(aujourdhui),
          tableCochable: 'plan_taches', brut: x));
    }
  }

  final soinsDuJour = <String>{};
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
        tableCochable: acte.isNotEmpty ? null : 'taches_elevage', brut: acte.isNotEmpty ? null : t);
    if (acte.isNotEmpty) {
      if ((t['animal_id']?.toString() ?? '').isNotEmpty) soinsDuJour.add('${_ymd(date)}|$acte|${t['animal_id']}');
      soins.add(ligne);
    } else {
      aFaire.add(ligne);
    }
  }

  for (final e in evenements) {
    final debut = DateTime.parse(e['date_debut'].toString()).toLocal();
    final date = DateTime(debut.year, debut.month, debut.day);
    final acte = e['type'] == 'medication' ? _acte(e['titre']?.toString() ?? '', _acteRappel) : '';
    if (acte.isNotEmpty) {
      // Rappel du carnet : retiré par le serveur au renouvellement du soin.
      if (e['animal_id'] != null && soinsDuJour.contains('${_ymd(date)}|$acte|${e['animal_id']}')) continue;
      soins.add(LigneTB(cle: 'e_${e['id']}', titre: sansPictos(e['titre'].toString()), date: date,
          retard: date.isBefore(aujourdhui), sousTitre: 'Rappel du carnet'));
      continue;
    }
    if (date.isBefore(aujourdhui)) continue;
    final heure = debut.hour != 0 || debut.minute != 0
        ? '${debut.hour.toString().padLeft(2, '0')}:${debut.minute.toString().padLeft(2, '0')}' : null;
    agenda.add(LigneTB(cle: 'e_${e['id']}', titre: sansPictos(e['titre'].toString()), date: date, heure: heure,
        couleur: _couleurType[e['type']?.toString() ?? ''] ?? _couleurType['autre'],
        sousTitre: (e['lieu']?.toString() ?? '').isEmpty ? null : e['lieu'].toString()));
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
    final rows = await supa.from('animaux').select('id, nom').inFilter('id', ids.toList());
    for (final a in rows as List) { noms[a['id'].toString()] = (a['nom'] ?? '').toString(); }
  }

  return DonneesTB(aFaire, soins, agenda, [
    for (final c in contrats)
      ContratTB(c['id'].toString(), sansPictos((c['titre'] ?? 'Contrat').toString()), c['statut'].toString(),
          noms[c['animal_id']?.toString()]),
  ], [for (final x in recups) noms[x['animal_id']?.toString()] ?? 'Animal']);
}

/// Noms de l'équipe (moi + employés avec compte) — miroir site loadMembres.
Future<Map<String, String>> _membres(String ownerUid, String moiUid) async {
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
          .eq('uid_eleveur', ownerUid).eq('actif', true).eq('profil_source', 'eleveur'),
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
