import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/rdv/salles_clinique_widgets.dart' show kTypePoste;

/// Planning de l'équipe (toiletteur, Premium) — vue jour, RDV colorés par
/// employé, filtrable. Vue « Postes » : postes du salon (table, baignoire…)
/// = lignes salles_clinique de type « poste », gérées ici ; le poste d'un RDV
/// (rdv.salle_id) se choisit à l'acceptation / la modification
/// (pro_agenda.dart). Conflits signalés : même employé ou même poste.
/// Pas de glisser-déposer (décision validée : confort d'usage, pas un besoin
/// fonctionnel pour la V1). Miroir site : components/rdv/PlanningEmployes.tsx.
class ToilettagePlanningEmployesPage extends StatefulWidget {
  const ToilettagePlanningEmployesPage({super.key});

  @override
  State<ToilettagePlanningEmployesPage> createState() => _ToilettagePlanningEmployesPageState();
}

class _ToilettagePlanningEmployesPageState extends State<ToilettagePlanningEmployesPage> {
  static const _orange = Color(0xFFFFB74D);
  static const _bg = Color(0xFFF8F8F6);
  static const _teal = Color(0xFF0C5C6C);
  static const _rouge = Color(0xFFB42318);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _employes = [];
  List<Map<String, dynamic>> _postes = [];
  List<Map<String, dynamic>> _rdvs = [];
  bool _parPoste = false;
  /// null = tous ; '' = non assigné / sans poste ; sinon id (employé ou poste) en texte.
  String? _filtre;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final start = DateTime(_date.year, _date.month, _date.day).toUtc();
      final end = DateTime(_date.year, _date.month, _date.day, 23, 59, 59).toUtc();
      final results = await Future.wait([
        pid.isNotEmpty
            // .neq('type', 'benevole') excluait TOUT le monde : ce champ
            // n'est jamais renseigné pour un employé normal (seuls les
            // bénévoles association l'ont), et NULL != 'benevole' n'est
            // jamais vrai en SQL — donc les lignes NULL étaient exclues.
            ? _supa.from('employes').select('id, prenom, nom, couleur_planning')
                .eq('eleveur_profile_id', pid).eq('actif', true).or('type.is.null,type.neq.benevole')
            : Future.value(<Map<String, dynamic>>[]),
        _supa.from('rdv').select('id, date_heure, duree_minutes, motif, employe_id, salle_id, client_uid, statut')
            .eq('pro_uid', uid).eq('pro_profile_id', pid)
            .inFilter('statut', ['confirme', 'demande', 'termine'])
            .gte('date_heure', start.toIso8601String()).lte('date_heure', end.toIso8601String())
            .order('date_heure'),
        pid.isNotEmpty
            ? _supa.from('salles_clinique').select('id, nom, ordre').eq('clinique_profile_id', pid)
                .eq('type_salle', kTypePoste).eq('actif', true).order('ordre').order('created_at')
            : Future.value(<Map<String, dynamic>>[]),
      ]);
      final employes = List<Map<String, dynamic>>.from(results[0] as List);
      final rdvs = List<Map<String, dynamic>>.from(results[1] as List);
      final postes = List<Map<String, dynamic>>.from(results[2] as List);

      final clientUids = rdvs.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      if (clientUids.isNotEmpty) {
        final profiles = await _supa.from('user_profiles_complet')
            .select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true);
        final names = <String, String>{};
        for (final c in profiles as List) {
          final n = (c['nom'] as String?)?.trim();
          final full = n?.isNotEmpty == true ? n! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
          names[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
        }
        for (final r in rdvs) { r['_client_nom'] = names[r['client_uid']] ?? 'Client'; }
      }

      if (mounted) setState(() { _employes = employes; _postes = postes; _rdvs = rdvs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _couleurEmploye(Object? employeId) {
    if (employeId == null) return Colors.grey;
    final e = _employes.firstWhere((e) => e['id'] == employeId, orElse: () => {});
    final hex = e['couleur_planning'] as String? ?? '#FFB74D';
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  String _nomEmploye(Object? employeId) {
    if (employeId == null) return 'Non assigné';
    final e = _employes.firstWhere((e) => e['id'] == employeId, orElse: () => {});
    return '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim();
  }

  String? _nomPoste(Object? salleId) {
    if (salleId == null) return null;
    final p = _postes.firstWhere((p) => p['id'].toString() == salleId.toString(), orElse: () => {});
    return p['nom'] as String?;
  }

  /// Conflits : même employé (ou même poste), deux RDV qui se chevauchent.
  Map<String, String> get _conflits {
    final out = <String, String>{};
    DateTime? debut(Map r) => DateTime.tryParse(r['date_heure']?.toString() ?? '');
    final actifs = _rdvs.where((r) => r['statut'] != 'termine' && debut(r) != null).toList();
    for (var i = 0; i < actifs.length; i++) {
      for (var j = i + 1; j < actifs.length; j++) {
        final a = actifs[i], b = actifs[j];
        final da = debut(a)!, db = debut(b)!;
        final fa = da.add(Duration(minutes: (a['duree_minutes'] as num?)?.toInt() ?? 30));
        final fb = db.add(Duration(minutes: (b['duree_minutes'] as num?)?.toInt() ?? 30));
        if (!(da.isBefore(fb) && db.isBefore(fa))) continue;
        if (a['employe_id'] != null && a['employe_id'] == b['employe_id']) {
          out[a['id'].toString()] = 'employe'; out[b['id'].toString()] = 'employe';
        } else if (a['salle_id'] != null && a['salle_id'] == b['salle_id']) {
          out[a['id'].toString()] = 'poste'; out[b['id'].toString()] = 'poste';
        }
      }
    }
    return out;
  }

  Widget _puce(String libelle, String? valeur, {Color? couleur}) => ChoiceChip(
        avatar: couleur == null ? null : CircleAvatar(backgroundColor: couleur, radius: 6),
        label: Text(libelle, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
        selected: _filtre == valeur,
        onSelected: (_) => setState(() => _filtre = valeur),
      );

  @override
  Widget build(BuildContext context) {
    final displayed = _filtre == null
        ? _rdvs
        : _parPoste
            ? _rdvs.where((r) => _filtre!.isEmpty ? _nomPoste(r['salle_id']) == null : r['salle_id']?.toString() == _filtre).toList()
            : _rdvs.where((r) => _filtre!.isEmpty ? r['employe_id'] == null : r['employe_id']?.toString() == _filtre).toList();
    final conflits = _conflits;
    final avecPuces = _parPoste ? _postes.isNotEmpty : _employes.length > 1;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        title: Text(DateFormat('EEEE d MMMM', 'fr_FR').format(_date), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { setState(() => _date = _date.subtract(const Duration(days: 1))); _load(); }),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () { setState(() => _date = _date.add(const Duration(days: 1))); _load(); }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : Column(children: [
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(children: [
                  Expanded(child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Employés', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                      ButtonSegment(value: true, label: Text('Postes', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                    ],
                    selected: {_parPoste},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() { _parPoste = s.first; _filtre = null; }),
                  )),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _gererPostes,
                    child: const Text('Gérer les postes', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
                  ),
                ]),
              ),
              if (avecPuces)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.white,
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    _puce('Tous', null),
                    if (_parPoste) ...[
                      for (final p in _postes) _puce('${p['nom'] ?? 'Poste'}', p['id'].toString()),
                      if (_rdvs.any((r) => _nomPoste(r['salle_id']) == null)) _puce('Sans poste', ''),
                    ] else ...[
                      for (final e in _employes) _puce('${e['prenom'] ?? ''}'.trim(), e['id'].toString(), couleur: _couleurEmploye(e['id'])),
                      if (_rdvs.any((r) => r['employe_id'] == null)) _puce('Non assigné', '', couleur: Colors.grey),
                    ],
                  ]),
                ),
              if (_parPoste && _postes.isEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      "Aucun poste déclaré. Créez vos postes (table 1, baignoire…) avec « Gérer les postes », "
                      "puis choisissez le poste de chaque rendez-vous en l'acceptant ou en le modifiant.",
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                ),
              Expanded(
                child: displayed.isEmpty
                    ? const Center(child: Text('Aucun RDV ce jour.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: displayed.length,
                        itemBuilder: (_, i) {
                          final r = displayed[i];
                          final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal();
                          final heure = dh != null ? DateFormat('HH:mm').format(dh) : '';
                          final couleur = _couleurEmploye(r['employe_id']);
                          final conflit = conflits[r['id'].toString()];
                          final poste = _nomPoste(r['salle_id']);
                          final sousTitre = [
                            _nomEmploye(r['employe_id']),
                            if (poste != null) poste else if (_postes.isNotEmpty) 'sans poste',
                            if (r['statut'] == 'demande') 'demande' else if (r['statut'] == 'termine') 'terminé',
                            if (conflit == 'employe') 'conflit : deux rendez-vous en même temps'
                            else if (conflit == 'poste') 'conflit : poste déjà occupé',
                          ].join(' · ');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border(left: BorderSide(color: couleur, width: 4)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(children: [
                              Text(heure, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${r['motif'] ?? ''} — ${r['_client_nom'] ?? ''}',
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(sousTitre,
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: conflit != null ? _rouge : Colors.grey.shade500)),
                              ])),
                              Text('${r['duree_minutes'] ?? 0} min', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
    );
  }

  /// Postes du salon : ajouter, renommer, ordonner, retirer (actif = false :
  /// les RDV déjà placés gardent leur poste).
  Future<void> _gererPostes() async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) return;
    final nouveauCtrl = TextEditingController();
    var postes = [for (final p in _postes) Map<String, dynamic>.from(p)];
    String? erreur;
    var enCours = false;

    Future<void> recharger(StateSetter setM) async {
      final rows = await _supa.from('salles_clinique').select('id, nom, ordre').eq('clinique_profile_id', pid)
          .eq('type_salle', kTypePoste).eq('actif', true).order('ordre').order('created_at');
      setM(() => postes = [for (final r in rows as List) Map<String, dynamic>.from(r as Map)]);
    }

    Future<void> executer(StateSetter setM, Future<void> Function() f) async {
      setM(() { enCours = true; erreur = null; });
      try {
        await f();
      } catch (e) {
        setM(() => erreur = 'Action impossible : $e');
      }
      await recharger(setM);
      setM(() => enCours = false);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Postes du salon', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text("Table de toilettage, baignoire, poste de séchage… Le poste d'un rendez-vous se choisit en l'acceptant "
                'ou en le modifiant ; un poste déjà occupé sur le créneau est grisé.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            if (postes.isEmpty)
              Text("Aucun poste pour l'instant.", style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
            for (var i = 0; i < postes.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: TextFormField(
                    key: ValueKey('poste_${postes[i]['id']}'),
                    initialValue: '${postes[i]['nom'] ?? ''}',
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    onFieldSubmitted: (v) {
                      final nom = v.trim();
                      if (nom.isEmpty || nom == postes[i]['nom']) return;
                      final id = postes[i]['id'];
                      executer(setM, () => _supa.from('salles_clinique').update({'nom': nom}).eq('id', id));
                    },
                  )),
                  IconButton(
                    tooltip: 'Monter', icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: enCours || i == 0 ? null : () => executer(setM, () => _reordonner(postes, i, i - 1)),
                  ),
                  IconButton(
                    tooltip: 'Descendre', icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: enCours || i == postes.length - 1 ? null : () => executer(setM, () => _reordonner(postes, i, i + 1)),
                  ),
                  IconButton(
                    tooltip: 'Retirer', icon: const Icon(Icons.delete_outline, size: 20, color: _rouge),
                    onPressed: enCours ? null : () async {
                      final ok = await showDialog<bool>(context: ctx, builder: (d) => AlertDialog(
                        title: Text('Retirer le poste « ${postes[i]['nom']} » ?', style: const TextStyle(fontFamily: 'Galey', fontSize: 16)),
                        content: const Text('Les rendez-vous déjà placés sur ce poste le gardent.', style: TextStyle(fontFamily: 'Galey')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
                          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Retirer')),
                        ],
                      ));
                      if (ok != true) return;
                      final id = postes[i]['id'];
                      await executer(setM, () => _supa.from('salles_clinique').update({'actif': false}).eq('id', id));
                    },
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(
                controller: nouveauCtrl,
                decoration: const InputDecoration(hintText: 'Ex. Table 1, Baignoire', isDense: true, border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              )),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _teal),
                onPressed: enCours ? null : () {
                  final nom = nouveauCtrl.text.trim();
                  if (nom.isEmpty) return;
                  nouveauCtrl.clear();
                  executer(setM, () => _supa.from('salles_clinique').insert({
                    'clinique_profile_id': pid, 'nom': nom, 'type_salle': kTypePoste, 'ordre': postes.length,
                  }));
                },
                child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ]),
            if (erreur != null) ...[
              const SizedBox(height: 8),
              Text(erreur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _rouge)),
            ],
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey'))),
          ]),
        )),
      )),
    );
    nouveauCtrl.dispose();
    if (mounted) _load();
  }

  /// Échange de deux postes : l'ordre est renuméroté (0, 1, 2…) pour rester stable.
  Future<void> _reordonner(List<Map<String, dynamic>> postes, int i, int j) async {
    final liste = [...postes];
    final t = liste[i]; liste[i] = liste[j]; liste[j] = t;
    for (var k = 0; k < liste.length; k++) {
      await _supa.from('salles_clinique').update({'ordre': k}).eq('id', liste[k]['id']);
    }
  }
}
