// Pension — protocoles du séjour (reference_event = 'sejour',
// migration_pension_protocoles_sejour.sql). Appliqués AUTOMATIQUEMENT à
// l'enregistrement de l'arrivée ; tâches rattachées au séjour
// (pension_entree_id), retirées si le séjour se termine plus tôt ou est
// annulé. Miroir site : lib/pension-protocoles.ts (même logique).
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/protocoles.dart' show acteLabel;
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart' show cleEspecePension, pensionGroupe, kPensionEspeces;

const kMomentsSejour = <(String, String)>[
  ('chaque_jour', 'Chaque jour du séjour'),
  ('arrivee', "Jour de l'arrivée (+ jours)"),
  ('depart', 'Avant le départ (jours)'),
];

String momentSejourLabel(String? m, [int offset = 0]) {
  if (m == 'arrivee') return offset > 0 ? "$offset j après l'arrivée" : "Jour de l'arrivée";
  if (m == 'depart') return offset > 0 ? '$offset j avant le départ' : 'Jour du départ';
  return 'Chaque jour du séjour';
}

/// Résumé du ciblage d'un protocole de séjour.
String cibleSejourLabel(Object? brut) {
  if (brut is! Map) return 'Tous les pensionnaires';
  final p = <String>[];
  final races = (brut['races'] as List?) ?? const [];
  final types = (brut['logement_types'] as List?) ?? const [];
  final ids = (brut['logement_ids'] as List?) ?? const [];
  final esp = (brut['especes'] as List?) ?? const [];
  if (esp.isNotEmpty) {
    p.add('espèces : ${esp.map((k) => kPensionEspeces.firstWhere((x) => x['key'] == k, orElse: () => {'label': k.toString()})['label']).join(', ')}');
  }
  if (races.isNotEmpty) p.add('races : ${races.join(', ')}');
  if (types.isNotEmpty) p.add('logements : ${types.join(', ')}');
  if (ids.isNotEmpty) p.add('${ids.length} logement(s) choisi(s)');
  if (brut['places'] == 'individuel') p.add('logements individuels');
  if (brut['places'] == 'partage') p.add('logements partagés');
  if (brut['sejour'] == 'essai') p.add('essais seulement');
  if (brut['sejour'] == 'sejour') p.add('séjours (hors essai)');
  if (brut['nouveau'] == 'nouveau') p.add('nouveaux pensionnaires');
  if (brut['nouveau'] == 'habitue') p.add('habitués');
  return p.isEmpty ? 'Tous les pensionnaires' : p.join(' · ');
}

String _t(Object? v) => v == null ? '' : v.toString().trim();
final _f = DateFormat('yyyy-MM-dd');
String _decaler(String iso, int n) => _f.format(DateTime.parse(iso).add(Duration(days: n)));

List<String> _joursSejour(String arrivee, String? depart) {
  final fin = depart != null && depart.compareTo(arrivee) >= 0 ? depart : arrivee;
  final out = <String>[];
  for (var d = arrivee; d.compareTo(fin) <= 0 && out.length < 400; d = _decaler(d, 1)) { out.add(d); }
  return out;
}

bool _especeOk(Object? tpl, Object? esp) {
  final a = cleEspecePension(_t(tpl)), b = cleEspecePension(_t(esp));
  return a.isEmpty || b.isEmpty || a == b || pensionGroupe(a) == pensionGroupe(b);
}

/// Ciblage par espèce : espèce du pensionnaire, ou à défaut espèces du logement.
bool especeCibleOk(List? cibles, Object? espece, Object? especesLogement) {
  final cs = [for (final c in cibles ?? const []) cleEspecePension(c.toString())];
  if (cs.isEmpty) return true;
  bool proche(String a, String b) => a == b || pensionGroupe(a) == pensionGroupe(b);
  final k = cleEspecePension(_t(espece));
  if (k.isNotEmpty) return cs.any((c) => proche(c, k));
  final liste = [for (final x in especesLogement is List ? especesLogement : const []) cleEspecePension(x.toString())]..removeWhere((x) => x.isEmpty);
  return liste.isEmpty || liste.any((l) => cs.any((c) => proche(c, l)));
}

/// Applique les protocoles de séjour aux séjours donnés (arrivée enregistrée).
/// Renvoie le nombre de tâches créées et les protocoles appliqués.
Future<({int taches, List<String> protocoles})> appliquerProtocolesSejour(List<String> entreeIds,
    {List<String>? templateIds, String? depuis}) async {
  final supa = Supabase.instance.client;
  var total = 0;
  final noms = <String>[];
  if (entreeIds.isEmpty) return (taches: 0, protocoles: noms);
  try {
    final entrees = [for (final e in await supa.from('pension_entrees').select().inFilter('id', entreeIds))
      if (_t(e['statut']) == 'en_pension') Map<String, dynamic>.from(e)];
    if (entrees.isEmpty) return (taches: 0, protocoles: noms);
    final proUid = _t(entrees.first['pro_uid']), pid = _t(entrees.first['pro_profile_id']);
    var q = supa.from('plan_templates').select('*, plan_template_etapes(*)').eq('uid_eleveur', proUid)
        .eq('profil_source', 'pension').eq('reference_event', 'sejour');
    if (templateIds != null && templateIds.isNotEmpty) q = q.inFilter('id', templateIds);
    final templates = [for (final tp in await q)
      if (pid.isEmpty || _t(tp['eleveur_profile_id']).isEmpty || _t(tp['eleveur_profile_id']) == pid) Map<String, dynamic>.from(tp)];
    if (templates.isEmpty) return (taches: 0, protocoles: noms);
    final logements = {for (final l in await supa.from('enclos_chenil').select('id, nom, type, especes, capacite').eq('uid_eleveur', proUid)) _t(l['id']): l};
    final dms = await supa.from('pension_demandes').select('entree_id, essai_entree_id, nouveau_pensionnaire')
        .or(entreeIds.map((id) => 'entree_id.eq.$id,essai_entree_id.eq.$id').join(','));
    bool? nouveauDe(String id) {
      for (final d in dms) {
        if (_t(d['entree_id']) == id || _t(d['essai_entree_id']) == id) return d['nouveau_pensionnaire'] == true;
      }
      return null;
    }

    for (final tp in templates) {
      final cible = tp['pension_cible'] is Map ? tp['pension_cible'] as Map : const {};
      final etapes = [for (final x in (tp['plan_template_etapes'] as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
      if (etapes.isEmpty) continue;
      final locaux = _t(tp['cible_type']) == 'locaux';
      var applique = false;
      for (final e in entrees) {
        final races = [for (final r in (cible['races'] as List?) ?? const []) r.toString().trim().toLowerCase()];
        final lIds = [for (final x in (cible['logement_ids'] as List?) ?? const []) x.toString()];
        final lTypes = [for (final x in (cible['logement_types'] as List?) ?? const []) x.toString()];
        final lg = logements[_t(e['logement_id'])];
        if (!locaux && !_especeOk(tp['espece'], e['espece'])) continue;
        if (races.isNotEmpty && !races.contains(_t(e['race']).toLowerCase())) continue;
        if (lIds.isNotEmpty && !lIds.contains(_t(e['logement_id']))) continue;
        if (lTypes.isNotEmpty && !lTypes.contains(_t(lg?['type']))) continue;
        if (!especeCibleOk(cible['especes'] as List?, e['espece'], lg?['especes'])) continue;
        final places = (lg?['capacite'] as num?)?.toInt() ?? 1;
        if (cible['places'] == 'individuel' && (lg == null || places > 1)) continue;
        if (cible['places'] == 'partage' && (lg == null || places <= 1)) continue;
        if (cible['sejour'] == 'essai' && e['essai'] != true) continue;
        if (cible['sejour'] == 'sejour' && e['essai'] == true) continue;
        final nv = nouveauDe(_t(e['id']));
        if (cible['nouveau'] == 'nouveau' && nv != true) continue;
        if (cible['nouveau'] == 'habitue' && nv == true) continue;
        if (locaux && lg == null) continue;

        final debut = _t(e['date_entree']).substring(0, 10);
        final finTxt = _t(e['date_sortie_prevue']);
        final jours = _joursSejour(debut, finTxt.length >= 10 ? finTxt.substring(0, 10) : null);
        final etapeIds = [for (final x in etapes) _t(x['id'])];
        final deja = locaux
            ? await supa.from('plan_taches').select('etape_id, date_prevue').eq('box_id', _t(e['logement_id'])).inFilter('etape_id', etapeIds)
                .gte('date_prevue', jours.first).lte('date_prevue', jours.last)
            : await supa.from('plan_taches').select('etape_id, date_prevue').eq('pension_entree_id', _t(e['id'])).inFilter('etape_id', etapeIds);
        final existe = {for (final x in deja) '${_t(x['etape_id'])}|${_t(x['date_prevue'])}'};

        final taches = <Map<String, dynamic>>[];
        for (final et in etapes) {
          final m = _t(et['sejour_moment']).isEmpty ? 'chaque_jour' : _t(et['sejour_moment']);
          final off = (et['jour_offset'] as num?)?.toInt() ?? 0;
          final dates = m == 'arrivee' ? [_decaler(jours.first, off)] : m == 'depart' ? [_decaler(jours.last, -off)] : jours;
          final base = [acteLabel(_t(et['type_acte'])).isNotEmpty ? acteLabel(_t(et['type_acte'])) : _t(et['description']), _t(et['produit']),
            if (_t(et['dosage']).isNotEmpty) '(${_t(et['dosage'])})'].where((x) => x.isNotEmpty).join(' ');
          final dansSejour = [for (final d in dates)
            if (d.compareTo(jours.first) >= 0 && d.compareTo(jours.last) <= 0 && (depuis == null || d.compareTo(depuis) >= 0)) d];
          for (var i = 0; i < dansSejour.length; i++) {
            final d = dansSejour[i];
            if (existe.contains('${_t(et['id'])}|$d')) continue;
            taches.add({
              'etape_id': _t(et['id']), 'uid_eleveur': proUid, 'profile_id': pid.isEmpty ? null : pid,
              if (pid.isNotEmpty) 'eleveur_profile_id': pid,
              'animal_id': locaux || _t(e['animal_id']).isEmpty ? null : _t(e['animal_id']),
              'animal_nom': locaux || _t(e['animal_nom']).isEmpty ? null : _t(e['animal_nom']),
              'type_acte': _t(et['type_acte']).isEmpty ? null : _t(et['type_acte']),
              'lieu': _t(lg?['nom']).isNotEmpty ? _t(lg?['nom']) : (_t(et['lieu']).isEmpty ? null : _t(et['lieu'])),
              'tranche_horaire': _t(et['tranche_horaire']).isEmpty ? null : _t(et['tranche_horaire']),
              'profil_source': 'pension', 'pension_entree_id': _t(e['id']),
              'box_id': _t(e['logement_id']).isEmpty ? null : _t(e['logement_id']),
              'label': locaux ? '$base — ${_t(lg?['nom']).isEmpty ? 'logement' : _t(lg?['nom'])}'
                  : (dansSejour.length > 1 ? '$base — Jour ${i + 1}/${dansSejour.length}' : base),
              'date_prevue': d, 'jour_traitement': i + 1, 'total_jours': dansSejour.length,
            });
          }
        }
        if (taches.isEmpty) continue;
        final plan = await supa.from('plans_actifs').insert({
          'template_id': _t(tp['id']), 'uid_eleveur': proUid, if (pid.isNotEmpty) 'eleveur_profile_id': pid,
          'type_declencheur': 'sejour', 'date_reference': jours.first, 'reference_id': _t(e['id']),
          'reference_label': locaux ? (_t(lg?['nom']).isEmpty ? 'Logement' : _t(lg?['nom'])) : (_t(e['animal_nom']).isEmpty ? 'Pensionnaire' : _t(e['animal_nom'])),
          'profil_source': 'pension',
        }).select('id').single();
        try {
          await supa.from('plan_taches').insert([for (final x in taches) {...x, 'plan_id': plan['id']}]);
          total += taches.length;
          applique = true;
        } catch (_) {}
      }
      if (applique) noms.add(_t(tp['nom']));
    }
  } catch (_) {}
  return (taches: total, protocoles: noms);
}

/// Départ enregistré : les tâches « au départ » se recalent sur le vrai jour du
/// départ ; une tâche de logement dont le logement reste occupé par un autre
/// pensionnaire passe au départ de celui-ci ; les autres tâches non faites
/// après le départ sont retirées. Miroir site : terminerTachesSejour.
Future<void> terminerTachesSejour(List<String> entreeIds, String dateDepart) async {
  if (entreeIds.isEmpty) return;
  final supa = Supabase.instance.client;
  try {
    final tts = await supa.from('plan_taches')
        .select('id, etape_id, date_prevue, box_id, plan_template_etapes(sejour_moment, jour_offset), plans_actifs(plan_templates(cible_type))')
        .inFilter('pension_entree_id', entreeIds).neq('statut', 'fait');
    bool estLocaux(Map x) => _t(((x['plans_actifs'] as Map?)?['plan_templates'] as Map?)?['cible_type']) == 'locaux';
    bool estDepart(Map x) => _t((x['plan_template_etapes'] as Map?)?['sejour_moment']) == 'depart';
    final taches = [for (final x in tts) if (estDepart(x)) x];
    // Tâches quotidiennes d'un logement encore occupé : elles continuent pour l'autre pensionnaire.
    final quotidiennes = [for (final x in tts) if (!estDepart(x) && estLocaux(x) && _t(x['date_prevue']).compareTo(dateDepart) > 0) x];
    final boxes = {for (final x in [...taches, ...quotidiennes]) if (_t(x['box_id']).isNotEmpty) _t(x['box_id'])}.toList();
    final autres = boxes.isEmpty ? const [] : await supa.from('pension_entrees').select('id, logement_id, date_sortie_prevue')
        .eq('statut', 'en_pension').inFilter('logement_id', boxes);
    final restants = [for (final o in autres) if (!entreeIds.contains(_t(o['id']))) o];
    for (final x in quotidiennes) {
      final d = _t(x['date_prevue']);
      for (final o in restants) {
        final fin = _t(o['date_sortie_prevue']);
        if (_t(o['logement_id']) == _t(x['box_id']) && (fin.length < 10 || d.compareTo(fin.substring(0, 10)) <= 0)) {
          await supa.from('plan_taches').update({'pension_entree_id': _t(o['id'])}).eq('id', _t(x['id']));
          break;
        }
      }
    }
    for (final x in taches) {
      final off = ((x['plan_template_etapes'] as Map)['jour_offset'] as num?)?.toInt() ?? 0;
      final locaux = estLocaux(x);
      final memeBox = locaux ? ([for (final o in restants) if (_t(o['logement_id']) == _t(x['box_id'])) o]
        ..sort((a, b) => _t(b['date_sortie_prevue']).compareTo(_t(a['date_sortie_prevue'])))) : const [];
      if (memeBox.isNotEmpty) {
        final reste = memeBox.first;
        final finTxt = _t(reste['date_sortie_prevue']);
        final date = _decaler(finTxt.length >= 10 ? finTxt.substring(0, 10) : dateDepart, -off);
        final dbl = await supa.from('plan_taches').select('id').eq('box_id', _t(x['box_id'])).eq('etape_id', _t(x['etape_id']))
            .eq('date_prevue', date).neq('id', _t(x['id'])).limit(1);
        if (dbl.isNotEmpty) {
          await supa.from('plan_taches').delete().eq('id', _t(x['id']));
        } else {
          await supa.from('plan_taches').update({'pension_entree_id': _t(reste['id']), 'date_prevue': date}).eq('id', _t(x['id']));
        }
      } else {
        final date = _decaler(dateDepart, -off);
        if (_t(x['date_prevue']) != date) await supa.from('plan_taches').update({'date_prevue': date}).eq('id', _t(x['id']));
      }
    }
  } catch (_) {}
  await retirerTachesSejour(entreeIds, dateDepart);
}

/// Séjour terminé plus tôt / annulé : tâches non faites après [apres] retirées.
Future<void> retirerTachesSejour(List<String> entreeIds, String apres) async {
  if (entreeIds.isEmpty) return;
  try {
    await Supabase.instance.client.from('plan_taches').delete()
        .inFilter('pension_entree_id', entreeIds).neq('statut', 'fait').gt('date_prevue', apres);
  } catch (_) {}
}
