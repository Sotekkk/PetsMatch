// Pension — gestion des demandes de séjour (comme la gestion des RDV) :
//  À traiter : demandes reçues (regroupées par client et dates) → Accepter
//    (logement + heures) / Refuser.
//  À venir : séjours acceptés pas encore arrivés → arrhes (à facturer /
//    facturées / payées, « Facturer les arrhes »), essai (« Essai concluant »
//    / « Non concluant » = séjour annulé, client prévenu), contrat.
//  Historique : refusées, annulées, arrivées.
// Écritures via la route /api/pension/sejour. Les fonctions d'acceptation /
// de refus servent aussi à l'accueil pension. Miroir site : /pension/sejours.
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/pro/toilettage_dossier_seance.dart' show signerContratAvecSignaturePro;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/site_api.dart';
import 'package:PetsMatch/utils/pension_horaires.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart' show logementAccepteEspece;
import 'package:PetsMatch/pages/pro/registre_pension_page.dart' show PensionFacturationSheet;

const _teal = kDashTeal;
const _muted = kDashMuted;
const _vert = Color(0xFF2E7D5E);
const _orange = Color(0xFFB45309);
const _rouge = Color(0xFFB3261E);

List<Map<String, dynamic>> _listeP(dynamic r) =>
    List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
String _jmP(dynamic v) { final d = DateTime.tryParse(v?.toString() ?? ''); return d == null ? '' : DateFormat('dd/MM').format(d); }

/// Acceptation : logement par animal, heures ajustables, puis décision.
  /// Accepter une demande (un ou plusieurs animaux) en attribuant un logement
/// à chaque animal : logements acceptant son espèce, places libres sur la
/// période (pleins grisés). Sans logement configuré : acceptation directe.
/// Miroir site : AccepterSejourModal.
Future<bool> accepterDemandesPension(BuildContext context, List<Map<String, dynamic>> g) async {
  final supa = Supabase.instance.client;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  final d0 = g.first;
  final arrivee = d0['date_arrivee'].toString().substring(0, 10);
  final depart = d0['date_depart'].toString().substring(0, 10);
  List<Map<String, dynamic>> logements = [], occupations = [];
  try {
    logements = _listeP(await supa.from('enclos_chenil').select('id, nom, type, capacite, especes').eq('uid_eleveur', uid).order('nom'));
    occupations = _listeP(await supa.from('pension_entrees').select('date_entree, date_sortie_prevue, logement_id')
        .eq('pro_uid', uid).eq('statut', 'en_pension').not('logement_id', 'is', null).lte('date_entree', depart));
  } catch (_) {}
  // Heures prévues : celles demandées par le client, ajustables (nombre
  // d'animaux, premier séjour…), avec la durée de l'arrivée / du départ.
  Map<String, dynamic>? horaires;
  final pid = User_Info.activeProfileId;
  if (pid.isNotEmpty) {
    try {
      final r = await supa.from('user_profiles').select('pension_horaires').eq('id', pid).maybeSingle();
      horaires = lireHorairesPension(r?['pension_horaires']);
    } catch (_) {}
  }
  final nouveau = g.any((d) => d['nouveau_pensionnaire'] == true);
  String? hA = d0['heure_arrivee']?.toString(), hD = d0['heure_depart']?.toString();
  int? dA = horaires == null ? null : dureePassagePension(horaires, depart: false, nbAnimaux: g.length, nouveau: nouveau);
  int? dD = horaires == null ? null : dureePassagePension(horaires, depart: true, nbAnimaux: g.length, nouveau: false);
  final avecHeures = horaires != null || hA != null || hD != null;
  if (!context.mounted) return false;
  if (logements.isEmpty && !avecHeures) { return deciderDemandesPension(context, g, true); }
  // Nuits du séjour (jour du départ exclu ; séjour d'un jour = ce jour).
  final nuits = <String>[];
  for (var d = DateTime.parse(arrivee); d.isBefore(DateTime.parse(depart)) && nuits.length < 400; d = d.add(const Duration(days: 1))) {
    nuits.add(DateFormat('yyyy-MM-dd').format(d));
  }
  if (nuits.isEmpty) nuits.add(arrivee);
  bool occupe(Map<String, dynamic> e, String j) {
    final de = e['date_entree'].toString().substring(0, 10);
    final ds = e['date_sortie_prevue']?.toString();
    final fin = ds?.substring(0, 10);
    return de.compareTo(j) <= 0 && (fin == null || fin.compareTo(j) > 0 || (fin == de && j == de));
  }
  final choix = <String, String>{};
  int pris(Map<String, dynamic> l, String sauf) {
    final autres = choix.entries.where((e) => e.value == l['id'].toString() && e.key != sauf).length;
    var max = 0;
    for (final j in nuits) {
      final n = occupations.where((o) => o['logement_id'].toString() == l['id'].toString() && occupe(o, j)).length;
      if (n > max) max = n;
    }
    return max + autres;
  }
  /// Logement proposé : places libres au pire jour, grisé s'il est plein.
  DropdownMenuItem<String> item(Map<String, dynamic> l, int n) {
    final cap = (l['capacite'] as num?)?.toInt() ?? 1;
    final plein = n >= cap;
    return DropdownMenuItem<String>(
      value: l['id'].toString(), enabled: !plein,
      child: Text('${l['nom']}${(l['type'] ?? '').toString().isNotEmpty ? ' (${l['type']})' : ''} — '
          '${plein ? 'complet' : '${cap - n} place${cap - n > 1 ? 's' : ''} libre${cap - n > 1 ? 's' : ''}'}',
          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: plein ? Colors.grey : null)),
    );
  }
  final ok = await showModalBottomSheet<bool>(
    context: context, isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(g.length > 1 ? 'Accepter les ${g.length} séjours' : 'Accepter le séjour',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17)),
        Text('Du ${_jmP(arrivee)} au ${_jmP(depart)} · attribuez un logement à chaque animal',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
        const SizedBox(height: 12),
        if (avecHeures) ...[
          for (final (lib, depart) in [('Arrivée prévue', false), ('Départ prévu', true)])
            Builder(builder: (_) {
              final h = depart ? hD : hA;
              final duree = depart ? dD : dA;
              final demande = depart ? d0['heure_depart'] : d0['heure_arrivee'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: Text('$lib${demande != null ? ' (demandé ${demande.toString().replaceAll(':', 'h')})' : ''}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                  OutlinedButton(
                    onPressed: () async {
                      final m = heureValidePension(h) ? int.parse(h!.substring(0, 2)) * 60 + int.parse(h.substring(3)) : 9 * 60;
                      final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
                      if (t == null) return;
                      final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                      setM(() { if (depart) { hD = v; } else { hA = v; } });
                    },
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(h == null ? '--h--' : h.replaceAll(':', 'h'), style: const TextStyle(fontFamily: 'Galey')),
                  ),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: (duree ?? 15) <= 5 ? null : () => setM(() { if (depart) { dD = (dD ?? 15) - 5; } else { dA = (dA ?? 15) - 5; } })),
                  Text('${duree ?? 15} min', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700)),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () => setM(() { if (depart) { dD = (dD ?? 15) + 5; } else { dA = (dA ?? 15) + 5; } })),
                ]),
              );
            }),
          Text("${g.length} animal${g.length > 1 ? 'aux' : ''}${nouveau ? ' · premier séjour' : ''} : ajustez l'heure et la durée si besoin.",
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
          const Divider(height: 20),
        ],
        if (logements.isNotEmpty) for (final d in g) Builder(builder: (_) {
          final id = d['id'].toString();
          final proposes = [for (final l in logements) if (logementAccepteEspece(l['especes'] as List?, d['espece']?.toString())) l];
          final titre = 'Logement pour ${d['animal_nom'] ?? "l'animal"}${(d['espece']?.toString() ?? '').isNotEmpty ? ' (${d['espece']})' : ''}'
              '${d['hebergement'] == 'pre' ? ' · pré souhaité' : d['hebergement'] == 'box' ? ' · box souhaité' : ''}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: proposes.isEmpty
                ? Text("$titre : aucun logement n'accepte cette espèce (cochez-la dans Chenil / logements).",
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFB45309)))
                : DropdownButtonFormField<String>(
                    initialValue: choix[id], isExpanded: true,
                    decoration: InputDecoration(labelText: titre, border: const OutlineInputBorder(), isDense: true),
                    items: [for (final l in proposes) item(l, pris(l, id))],
                    onChanged: (v) => setM(() { if (v != null) choix[id] = v; }),
                  ),
          );
        }),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _vert, padding: const EdgeInsets.symmetric(vertical: 13)),
          onPressed: () {
            final manque = logements.isNotEmpty && g.any((d) => !choix.containsKey(d['id'].toString()));
            if (manque) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Attribuez un logement à chaque animal.')));
              return;
            }
            Navigator.pop(ctx, true);
          },
          child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ]),
    ))),
  );
  if (ok == true && context.mounted) {
    return deciderDemandesPension(context, g, true, logements: choix, heures: avecHeures
        ? {'arrivee': hA, 'depart': hD, 'dureeArrivee': dA, 'dureeDepart': dD} : null);
  }
  return false;
}


Future<bool> deciderDemandesPension(BuildContext context, List<Map<String, dynamic>> g, bool accepter, {bool forcer = false, Map<String, String>? logements, Map<String, dynamic>? heures}) async {
  final d = g.first;
  String? motif;
  if (!accepter) {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Refuser la demande', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(
          hintText: 'Motif pour le client (facultatif) : complet à ces dates…', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Refuser')),
      ],
    ));
    if (ok != true) return false;
    motif = ctrl.text.trim();
  }
  try {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/pension/sejour'), headers: await siteApiHeaders(),
        body: jsonEncode({'action': 'decider', 'demandeId': d['id'], 'demandeIds': [for (final x in g) x['id']],
            'accepter': accepter, if (motif != null) 'motif': motif, if (forcer) 'forcer': true,
            if (logements != null && logements.isNotEmpty) 'logements': logements,
            if (heures != null) 'heures': heures}));
    if (!context.mounted) return false;
    // Hébergements pleins sur une partie du séjour : accepter quand même ?
    if (r.statusCode == 409 && accepter && !forcer) {
      Map j = {};
      try { j = jsonDecode(r.body) as Map; } catch (_) {}
      if (j['complet'] == true) {
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Pension complète', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Text('${j['error']}\nAccepter quand même ${g.length > 1 ? 'ces séjours' : 'ce séjour'} ?', style: const TextStyle(fontFamily: 'Galey')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accepter quand même')),
          ],
        ));
        if (ok == true && context.mounted) return deciderDemandesPension(context, g, true, forcer: true, logements: logements, heures: heures);
        return false;
      }
    }
    if (r.statusCode != 200) {
      String m = 'Action impossible';
      try { m = (jsonDecode(r.body) as Map)['error']?.toString() ?? m; } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accepter
        ? '${g.length > 1 ? 'Séjours acceptés : ils sont' : 'Séjour accepté : il est'} au planning et le client est prévenu' : 'Demande refusée, le client est prévenu')));
    if (accepter && context.mounted) await proposerArrhesPension(context, g);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
    return false;
  }
}


/// Après acceptation : la place est bloquée au planning (séjour créé, sans
/// arrivée) ; si le règlement prévoit des arrhes, facture d'acompte proposée.
Future<void> proposerArrhesPension(BuildContext context, List<Map<String, dynamic>> g) async {
  final supa = Supabase.instance.client;
  // Avec essai : arrhes demandées après un essai concluant (page Demandes de séjour).
  if (g.any((d) => d['essai_date'] != null)) return;
  final pid = User_Info.activeProfileId;
  int? pct;
  try {
    final p = await supa.from('user_profiles').select('tarifs_pension').eq('id', pid).maybeSingle();
    final a = (((p?['tarifs_pension'] as Map?)?['reglement'] as Map?)?['arrhes_pct'] as num?)?.round();
    pct = a != null && a > 0 ? a : null;
  } catch (_) {}
  if (pct == null || !context.mounted) return;
  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text("Facture d'arrhes", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
    content: Text("La place est bloquée au planning. Envoyer maintenant la facture d'arrhes ($pct %)${g.length > 1 ? ' pour les ${g.length} animaux' : ''} ?",
        style: const TextStyle(fontFamily: 'Galey')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Facturer les arrhes')),
    ],
  ));
  if (ok != true || !context.mounted) return;
  try {
    final dm = await supa.from('pension_demandes').select('entree_id').eq('id', g.first['id'].toString()).maybeSingle();
    final eid = dm?['entree_id']?.toString();
    if (eid == null) return;
    final en = await supa.from('pension_entrees').select().eq('id', eid).maybeSingle();
    if (en == null || !context.mounted) return;
    await showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
        builder: (_) => PensionFacturationSheet(entree: Map<String, dynamic>.from(en), acompte: pct));
  } catch (_) {}
}



// ══════════════════════════════════════════════════════════════════════════
// Page « Demandes de séjour »
// ══════════════════════════════════════════════════════════════════════════

class PensionDemandesPage extends StatefulWidget {
  const PensionDemandesPage({super.key});
  @override
  State<PensionDemandesPage> createState() => _PensionDemandesPageState();
}

class _PensionDemandesPageState extends State<PensionDemandesPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _demandes = [];
  Map<String, Map<String, dynamic>> _sejours = {};
  Map<String, String> _clients = {}, _arrhesFacts = {};
  /// Contrat par séjour : statut, id du document, signé par la pension ?
  Map<String, ({String statut, String id, bool signePro})> _contrats = {};
  int? _arrhesPct;
  bool _loading = true;
  String? _enCours;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null) return;
    try {
      var q = _supa.from('pension_demandes').select().eq('pro_uid', uid);
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      _demandes = _listeP(await q.order('date_arrivee'));
      final ids = {for (final d in _demandes) ...[d['entree_id'], d['essai_entree_id']]}.whereType<Object>().map((x) => x.toString()).toList();
      final pids = {for (final d in _demandes) d['client_profile_id']}.whereType<Object>().map((x) => x.toString()).toList();
      _sejours = {};
      _clients = {};
      _arrhesFacts = {};
      _contrats = {};
      if (ids.isNotEmpty) {
        for (final s in await _supa.from('pension_entrees').select('id, statut, arrivee_reelle_le').inFilter('id', ids)) {
          _sejours[s['id'].toString()] = Map<String, dynamic>.from(s);
        }
        if (pid.isNotEmpty) {
          for (final f in await _supa.from('factures').select('source_pension_entree_id, statut, type_facture').eq('profile_id', pid).inFilter('source_pension_entree_id', ids)) {
            if (f['statut'] == 'annulee') continue;
            final k = f['source_pension_entree_id'].toString();
            if (f['type_facture'] == 'acompte' || !_arrhesFacts.containsKey(k)) {
              _arrhesFacts[k] = '${f['type_facture'] == 'acompte' ? 'acompte' : 'complete'}:${f['statut'] ?? 'envoyee'}';
            }
          }
        }
        for (final d in await _supa.from('documents_animaux').select('id, pension_entree_id, statut, metadata')
            .inFilter('type', ['contrat_hebergement', 'contrat_document_pro']).inFilter('pension_entree_id', ids)) {
          final v = (statut: (d['statut'] ?? 'brouillon').toString(), id: d['id'].toString(),
              signePro: ((d['metadata'] as Map?)?['signature_eleveur']?.toString() ?? '').isNotEmpty);
          for (final id in [d['pension_entree_id'], ...(((d['metadata'] as Map?)?['entree_ids'] as List?) ?? const [])]) {
            _contrats[id.toString()] = v;
          }
        }
      }
      if (pids.isNotEmpty) {
        for (final c in await _supa.from('user_profiles_complet').select('id, firstname, lastname, nom').inFilter('id', pids)) {
          final n = '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
          _clients[c['id'].toString()] = n.isNotEmpty ? n : (c['nom']?.toString() ?? 'Client');
        }
      }
      if (pid.isNotEmpty) {
        final p = await _supa.from('user_profiles').select('tarifs_pension').eq('id', pid).maybeSingle();
        final a = (((p?['tarifs_pension'] as Map?)?['reglement'] as Map?)?['arrhes_pct'] as num?)?.round();
        _arrhesPct = a != null && a > 0 ? a : null;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<List<Map<String, dynamic>>> get _groupes {
    final m = <String, List<Map<String, dynamic>>>{};
    for (final d in _demandes) {
      m.putIfAbsent('${d['statut']}|${d['client_uid'] ?? d['id']}|${d['client_profile_id'] ?? ''}|${d['date_arrivee']}|${d['date_depart']}', () => []).add(d);
    }
    return m.values.toList();
  }

  bool _arrive(List<Map<String, dynamic>> g) => g.any((d) {
        final s = _sejours[d['entree_id']?.toString()];
        return s != null && (s['arrivee_reelle_le'] != null || s['statut'] == 'sorti');
      });

  Future<void> _essai(List<Map<String, dynamic>> g, bool concluant) async {
    String? motif;
    if (!concluant) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Essai non concluant', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Le séjour sera annulé (place libérée) et le client prévenu.', style: TextStyle(fontFamily: 'Galey')),
          const SizedBox(height: 8),
          TextField(controller: ctrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Motif pour le client (facultatif)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler le séjour', style: TextStyle(color: _rouge))),
        ],
      ));
      if (ok != true) return;
      motif = ctrl.text.trim();
    }
    setState(() => _enCours = g.first['id'].toString());
    try {
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/pension/sejour'), headers: await siteApiHeaders(),
          body: jsonEncode({'action': 'essai', 'demandeIds': [for (final d in g) d['id']], 'concluant': concluant,
              if ((motif ?? '').isNotEmpty) 'motif': motif}));
      if (r.statusCode != 200 && mounted) {
        String m = 'Action impossible';
        try { m = (jsonDecode(r.body) as Map)['error']?.toString() ?? m; } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
    if (!mounted) return;
    setState(() => _enCours = null);
    await _charger();
    // Essai concluant : place aux arrhes (si le règlement en prévoit).
    if (concluant && _arrhesPct != null && mounted) {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Essai concluant', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text("Le client est prévenu. Envoyer maintenant la facture d'arrhes ($_arrhesPct %) ?", style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Facturer les arrhes')),
        ],
      ));
      if (ok == true && mounted) await _facturerArrhes(g);
    }
  }

  Future<void> _facturerArrhes(List<Map<String, dynamic>> g) async {
    final eid = g.map((d) => d['entree_id']).firstWhere((x) => x != null, orElse: () => null)?.toString();
    if (eid == null) return;
    final en = await _supa.from('pension_entrees').select().eq('id', eid).maybeSingle();
    if (en == null || !mounted) return;
    await showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
        builder: (_) => PensionFacturationSheet(entree: Map<String, dynamic>.from(en), acompte: _arrhesPct));
    await _charger();
  }

  Widget _txt(String t, Color c, {bool gras = true}) =>
      Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: gras ? FontWeight.w700 : FontWeight.w400, color: c));

  Widget _carte(List<Map<String, dynamic>> g) {
    final d = g.first;
    final statut = d['statut']?.toString();
    String h(Object? x) => x == null ? '' : ' (${x.toString().replaceAll(':', 'h')})';
    final essaiD = g.where((x) => x['essai_date'] != null).firstOrNull;
    final resultat = g.map((x) => x['essai_resultat']).whereType<Object>().firstOrNull?.toString();
    final ids = [for (final x in g) if (x['entree_id'] != null) x['entree_id'].toString()];
    final fact = ids.map((i) => _arrhesFacts[i]).whereType<String>().firstOrNull;
    // Contrat du séjour, ou de l'essai (fait à l'arrivée de l'essai).
    final contrat = [...ids, for (final x in g) if (x['essai_entree_id'] != null) x['essai_entree_id'].toString()]
        .map((i) => _contrats[i]).nonNulls.firstOrNull;
    final occupe = _enCours == d['id'].toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE5E8E6))),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${g.map((x) => x['animal_nom'] ?? 'Animal').join(', ')}${g.any((x) => x['nouveau_pensionnaire'] == true) ? ' · nouveau pensionnaire' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          Text(_clients[d['client_profile_id']?.toString()] ?? 'Client', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
          Text('Du ${_jmP(d['date_arrivee'])}${h(d['heure_arrivee'])} au ${_jmP(d['date_depart'])}${h(d['heure_depart'])}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
          if (g.any((x) => x['hebergement'] != null))
            Text(g.where((x) => x['hebergement'] != null).map((x) => '${x['animal_nom']} : ${x['hebergement'] == 'pre' ? 'pré' : 'box'} souhaité').join(' · '),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
          if ((d['message']?.toString() ?? '').isNotEmpty)
            Text('« ${d['message']} »', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontStyle: FontStyle.italic, color: _muted)),
          if (statut == 'refusee' || statut == 'annulee')
            _txt('${statut == 'refusee' ? 'Refusée' : 'Annulée'}${(d['motif_refus']?.toString() ?? '').isNotEmpty ? ' : ${d['motif_refus']}' : ''}', _rouge, gras: false),
          if (statut == 'demande')
            Row(children: [
              FilledButton(
                onPressed: occupe ? null : () async { if (await accepterDemandesPension(context, g)) _charger(); },
                style: FilledButton.styleFrom(backgroundColor: _vert, visualDensity: VisualDensity.compact),
                child: Text(g.length > 1 ? 'Accepter les ${g.length}' : 'Accepter', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: occupe ? null : () async { if (await deciderDemandesPension(context, g, false)) _charger(); },
                child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey')),
              ),
            ]),
          if (essaiD != null) ...[
            const Divider(height: 18),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Essai le ${_jmP(essaiD['essai_date'])}${h(essaiD['heure_essai'])}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              if (resultat == 'concluant') _txt('Essai concluant', _vert)
              else if (resultat == 'non_concluant') _txt('Essai non concluant', _rouge)
              else if (statut == 'acceptee') ...[
                _txt("À valider après l'essai", _orange),
                FilledButton(onPressed: occupe ? null : () => _essai(g, true),
                    style: FilledButton.styleFrom(backgroundColor: _vert, visualDensity: VisualDensity.compact),
                    child: const Text('Essai concluant', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5))),
                OutlinedButton(onPressed: occupe ? null : () => _essai(g, false),
                    style: OutlinedButton.styleFrom(foregroundColor: _rouge, visualDensity: VisualDensity.compact),
                    child: const Text('Non concluant', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5))),
              ],
            ]),
          ],
          if (statut == 'acceptee' && !_arrive(g)) ...[
            const Divider(height: 18),
            Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (essaiD != null && resultat != 'concluant' && fact == null)
                _txt('Arrhes demandées après un essai concluant', _muted, gras: false)
              else if (fact != null)
                _txt(fact.endsWith(':payee') ? (fact.startsWith('acompte') ? 'Arrhes payées' : 'Séjour payé')
                    : (fact.startsWith('acompte') ? 'Arrhes facturées, en attente de paiement' : 'Séjour facturé'), fact.endsWith(':payee') ? _vert : _orange)
              else if (_arrhesPct != null) ...[
                _txt('Arrhes à facturer ($_arrhesPct %)', _orange),
                FilledButton(onPressed: () => _facturerArrhes(g), style: FilledButton.styleFrom(backgroundColor: _teal, visualDensity: VisualDensity.compact),
                    child: const Text('Facturer les arrhes', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5))),
              ] else
                _txt("Pas d'arrhes prévues", _muted, gras: false),
              if (contrat?.statut == 'signe')
                _txt('Contrat signé', _vert, gras: false)
              else if (contrat?.statut == 'partiellement_signe' && !contrat!.signePro) ...[
                _txt('Contrat signé par le client — à signer par vous', _orange),
                FilledButton(
                  onPressed: () async {
                    // Signature enregistrée reprise d'office, sinon signer une fois (enregistrée).
                    await signerContratAvecSignaturePro(context, contrat.id);
                    await _charger();
                  },
                  style: FilledButton.styleFrom(backgroundColor: _teal, visualDensity: VisualDensity.compact),
                  child: const Text('Signer', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                ),
              ] else
                _txt(contrat != null ? 'Contrat envoyé' : "Contrat à faire à l'arrivée", _muted, gras: false),
            ]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupes = _groupes;
    final attente = [for (final g in groupes) if (g.first['statut'] == 'demande') g];
    final avenir = [for (final g in groupes) if (g.first['statut'] == 'acceptee' && !_arrive(g)) g];
    final historique = [for (final g in groupes.reversed)
      if (g.first['statut'] == 'refusee' || g.first['statut'] == 'annulee' || (g.first['statut'] == 'acceptee' && _arrive(g))) g];
    Widget liste(List<List<Map<String, dynamic>>> l, String vide) => _loading
        ? const Center(child: CircularProgressIndicator(color: _teal))
        : RefreshIndicator(
            onRefresh: _charger,
            child: l.isEmpty
                ? ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(vide, textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Galey', color: _muted)))])
                : ListView(padding: const EdgeInsets.all(14), children: [for (final g in l) _carte(g)]),
          );
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F5),
        appBar: AppBar(
          backgroundColor: _teal, foregroundColor: Colors.white,
          title: const Text('Demandes de séjour', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          bottom: TabBar(
            labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Colors.white,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'À traiter${attente.isNotEmpty ? ' (${attente.length})' : ''}'),
              Tab(text: 'À venir${avenir.isNotEmpty ? ' (${avenir.length})' : ''}'),
              const Tab(text: 'Historique'),
            ],
          ),
        ),
        body: TabBarView(children: [
          liste(attente, 'Aucune demande à traiter.'),
          liste(avenir, 'Aucun séjour accepté à venir.'),
          liste(historique, 'Aucun historique.'),
        ]),
      ),
    );
  }
}
