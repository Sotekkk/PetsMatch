import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/services/planning_service.dart';
import 'package:PetsMatch/services/planning_pdf_service.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_list_page.dart';

class PlanningJourPage extends StatefulWidget {
  const PlanningJourPage({super.key});
  @override
  State<PlanningJourPage> createState() => _PlanningJourPageState();
}

class _PlanningJourPageState extends State<PlanningJourPage> {
  static const _green  = Color(0xFF0C5C6C);
  static const _dark   = Color(0xFF1F2A2E);
  static const _orange = Color(0xFFD97706);

  DateTime _selectedDate = DateTime.now();
  int      _weekOffset   = 0;
  List<Map<String, dynamic>> _taches   = [];
  List<Map<String, dynamic>> _employes = [];
  bool     _loading = true;
  String?  _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
    _loadEmployes();
  }

  Future<void> _loadEmployes() async {
    if (_uid == null) return;
    try {
      final supa = Supabase.instance.client;
      final empsRaw = await supa.from('employes').select().eq('uid_eleveur', _uid!).eq('actif', true);
      final List<Map<String, dynamic>> result = [];
      for (final e in empsRaw) {
        final u = await supa.from('users')
            .select('uid, firstname, lastname, name_elevage, is_elevage')
            .eq('uid', e['uid_employe'] as String)
            .maybeSingle();
        if (u != null) {
          final nom = u['is_elevage'] == true
              ? (u['name_elevage'] ?? 'Employé')
              : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          result.add({...e, 'nom': nom});
        }
      }
      if (mounted) setState(() => _employes = result);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_uid == null) return;
    setState(() => _loading = true);
    try {
      final rows = await PlanningService.getTachesJour(_uid!, _selectedDate);
      if (mounted) setState(() { _taches = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _taches = []; _loading = false; });
    }
  }

  // ── Grouper les tâches par etape_id ─────────────────────────────────────────
  List<_TaskGroup> get _groupes {
    final Map<String, List<Map<String, dynamic>>> byKey = {};
    for (final t in _taches) {
      final key = (t['etape_id'] as String?) ?? 'solo_${t['id']}';
      byKey.putIfAbsent(key, () => []).add(t);
    }
    const trancheOrder = {'matin': 0, 'midi': 1, 'apres_midi': 2, 'soir': 3};
    final groups = byKey.entries.map((e) => _TaskGroup(
      etapeId: e.value.first['etape_id'] as String?,
      taches: e.value,
      tranche: e.value.first['tranche_horaire'] as String?,
    )).toList()
      ..sort((a, b) {
        final oA = trancheOrder[a.tranche] ?? 4;
        final oB = trancheOrder[b.tranche] ?? 4;
        if (oA != oB) return oA.compareTo(oB);
        return (a.taches.first['label'] as String? ?? '')
            .compareTo(b.taches.first['label'] as String? ?? '');
      });
    return groups;
  }

  // ── Actions sur un groupe ────────────────────────────────────────────────────
  Future<void> _validerGroupe(List<Map<String, dynamic>> group) async {
    final ctrl = TextEditingController();
    final isSanitaire = (ta) => ['vermifuge','vaccination','antiparasitaire','traitement','visite'].contains(ta);
    final hasSanitaire = group.any((t) =>
        (t['animal_id']?.toString() ?? '').isNotEmpty &&
        isSanitaire(t['type_acte']?.toString() ?? ''));
    bool insertRegistre = false;
    // Sélection individuelle par animal (tous cochés par défaut)
    final selected = {for (final t in group) t['id'] as String: true};

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Valider les tâches', style: TextStyle(fontFamily: 'Galey')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Checklist par animal ──
                if (group.length > 1) ...[
                  Text('Sélectionner les animaux :',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  ...group.map((t) {
                    final id   = t['id'] as String;
                    final nom  = _animalNomFromTache(t);
                    return CheckboxListTile(
                      value: selected[id],
                      onChanged: (v) => setS(() => selected[id] = v ?? false),
                      title: Text(nom.isNotEmpty ? nom : 'Animal', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                      activeColor: _green,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  const Divider(height: 16),
                ],
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(labelText: 'Notes (optionnel)', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                if (hasSanitaire) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => setS(() => insertRegistre = !insertRegistre),
                    child: Row(children: [
                      Checkbox(value: insertRegistre, onChanged: (v) => setS(() => insertRegistre = v ?? false), activeColor: _green),
                      const Expanded(child: Text('Insérer dans le carnet\net registre sanitaire',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child: const Text('Valider', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && mounted) {
      final notes   = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
      final toValid = group.where((t) => selected[t['id'] as String] == true).toList();
      for (final t in toValid) {
        await PlanningService.validerTache(
          t['id'] as String,
          validateurUid: _uid!,
          notes: notes,
          tacheData: t,
          insertRegistre: insertRegistre,
        );
      }
      ctrl.dispose();
      _load();
    }
  }

  // Nom d'animal depuis animal_nom (nouveau) ou extraction label (ancien format)
  static String _animalNomFromTache(Map<String, dynamic> t) {
    final fromField = t['animal_nom'] as String? ?? '';
    if (fromField.isNotEmpty) return fromField;
    // Ancien format : label = "Promenade — Rex — Jour 1/364" → on cherche la partie entre ' — '
    final label = t['label'] as String? ?? '';
    final parts = label.split(' — ');
    if (parts.length >= 2) {
      final candidate = parts[parts.length - 1];
      if (!RegExp(r'^Jour \d+/\d+$').hasMatch(candidate) &&
          !RegExp(r'^\d+e/\d+e$').hasMatch(candidate)) {
        return candidate;
      }
      if (parts.length >= 3) return parts[parts.length - 2];
    }
    return '';
  }

  Future<void> _reporterGroupe(List<Map<String, dynamic>> group) async {
    for (final t in group) {
      final date = DateTime.tryParse(t['date_prevue'] as String) ?? DateTime.now();
      await PlanningService.reporterTache(t['id'] as String, date);
    }
    _load();
  }

  Future<void> _assignerGroupe(List<Map<String, dynamic>> group, String? employeUid) async {
    try {
      for (final t in group) {
        await Supabase.instance.client.from('plan_taches')
            .update({'assigned_to': employeUid}).eq('id', t['id'] as String);
      }
      if (mounted && employeUid != null && group.isNotEmpty) {
        final nomTache = _baseLabel(group.first['label'] as String? ?? '');
        await Supabase.instance.client.from('notifications').insert({
          'uid':   employeUid,
          'type':  'tache',
          'title': 'Tâches de protocole assignées',
          'body':  nomTache,
          'data':  {'eleveurUid': _uid, 'count': group.length},
          'read':  false,
        });
      }
      _load();
    } catch (_) {}
  }

  Future<void> _supprimerGroupe(List<Map<String, dynamic>> group, String? etapeId) async {
    final scope = await _askScope(title: 'Supprimer', isDelete: true);
    if (scope == null || !mounted) return;

    final ids     = group.map((t) => t['id'] as String).toList();
    final dateRef = _selectedDate.toIso8601String().split('T').first;

    await PlanningService.supprimerTaches(
      tacheIds: ids,
      scope:    scope,
      etapeId:  etapeId,
      uid:      _uid,
      dateRef:  dateRef,
    );
    _load();
  }

  Future<void> _modifierTrancheGroupe(List<Map<String, dynamic>> group, String? etapeId) async {
    final currentTranche = group.first['tranche_horaire'] as String?;
    final newTranche = await _askTranche(current: currentTranche);
    if (newTranche == null || !mounted) return; // cancelled

    final scope = await _askScope(title: 'Appliquer à');
    if (scope == null || !mounted) return;

    final ids     = group.map((t) => t['id'] as String).toList();
    final dateRef = _selectedDate.toIso8601String().split('T').first;

    await PlanningService.modifierTranche(
      tacheIds: ids,
      scope:    scope,
      tranche:  newTranche == 'aucune' ? null : newTranche,
      etapeId:  etapeId,
      uid:      _uid,
      dateRef:  dateRef,
    );
    _load();
  }

  // ── Dialogues ────────────────────────────────────────────────────────────────
  Future<String?> _askScope({required String title, bool isDelete = false}) {
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        children: [
          _scopeOption(context, 'cette',    Icons.today,        'Cette occurrence uniquement', null),
          _scopeOption(context, 'suivantes',Icons.arrow_forward,'Aujourd\'hui et les suivantes', null),
          _scopeOption(context, 'toutes',   Icons.all_inclusive,'Toutes les occurrences', isDelete ? Colors.red : null),
        ],
      ),
    );
  }

  Widget _scopeOption(BuildContext ctx, String value, IconData icon, String label, Color? color) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Row(children: [
        Icon(icon, size: 20, color: color ?? _green),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: color)),
      ]),
    );
  }

  Future<String?> _askTranche({String? current}) {
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Moment de la journée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        children: [
          for (final (val, emoji, label) in [
            ('aucune',     '—',    'Non défini'),
            ('matin',      '🌅',   'Matin'),
            ('midi',       '☀️',   'Midi'),
            ('apres_midi', '🌤️', 'Après-midi'),
            ('soir',       '🌙',   'Soir'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, val),
              child: Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(
                  fontFamily: 'Galey', fontSize: 14,
                  fontWeight: current == (val == 'aucune' ? null : val) ? FontWeight.w700 : FontWeight.normal,
                  color: current == (val == 'aucune' ? null : val) ? _green : null,
                )),
                if (current == (val == 'aucune' ? null : val)) ...[
                  const Spacer(),
                  const Icon(Icons.check, size: 16, color: _green),
                ],
              ]),
            ),
        ],
      ),
    );
  }

  // ── Helper: extraire le label sans le nom de l'animal ─────────────────────
  static String _baseLabel(String label) {
    const sep = ' — '; // espace + em-dash + espace
    final idx = label.lastIndexOf(sep);
    return idx >= 0 ? label.substring(0, idx) : label;
  }

  @override
  Widget build(BuildContext context) {
    final fmt     = DateFormat('EEEE d MMMM', 'fr_FR');
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final groupes = _groupes;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Planning', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          if (_taches.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer le planning du jour',
              onPressed: () => PlanningPdfService.printJour(_taches, _selectedDate),
            ),
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'Mes protocoles',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const PlanTemplateListPage(),
            )).then((_) => _load()),
          ),
        ],
      ),
      body: Column(
        children: [
          _DateStrip(
            selected: _selectedDate,
            weekOffset: _weekOffset,
            onSelected: (d) { setState(() { _selectedDate = d; _loading = true; }); _load(); },
            onPrevWeek: () => setState(() => _weekOffset--),
            onNextWeek: () => setState(() => _weekOffset++),
            onToday:    () => setState(() { _weekOffset = 0; _selectedDate = DateTime.now(); _load(); }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  isToday ? 'Aujourd\'hui' : fmt.format(_selectedDate),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 18, fontWeight: FontWeight.w700, color: _dark),
                ),
                const Spacer(),
                if (_taches.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '${groupes.length} tâche${groupes.length > 1 ? 's' : ''}${_taches.length != groupes.length ? ' · ${_taches.length} anim.' : ''}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _taches.isEmpty
                    ? _EmptyState(date: _selectedDate)
                    : _buildGroupedList(groupes),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(List<_TaskGroup> groupes) {
    final items = <Widget>[];
    String? lastTranche = '@@NONE@@';

    for (final group in groupes) {
      if (group.tranche != lastTranche) {
        lastTranche = group.tranche;
        if (group.tranche != null) items.add(_TrancheHeader(group.tranche!));
      }
      items.add(_GroupedTacheCard(
        group:    group,
        employes: _employes,
        uid:      _uid,
        dateRef:  _selectedDate.toIso8601String().split('T').first,
        onValider:       () => _validerGroupe(group.taches),
        onReporter:      () => _reporterGroupe(group.taches),
        onAssigner:      (u) => _assignerGroupe(group.taches, u),
        onSupprimer:     () => _supprimerGroupe(group.taches, group.etapeId),
        onModifierTranche: () => _modifierTrancheGroupe(group.taches, group.etapeId),
      ));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      children: items,
    );
  }
}

// ── Modèle de groupe ─────────────────────────────────────────────────────────

class _TaskGroup {
  final String? etapeId;
  final List<Map<String, dynamic>> taches;
  final String? tranche;
  const _TaskGroup({required this.etapeId, required this.taches, required this.tranche});
}

// ── Section header par tranche ────────────────────────────────────────────────

class _TrancheHeader extends StatelessWidget {
  final String tranche;
  const _TrancheHeader(this.tranche);

  static const _infos = {
    'matin':      ('🌅', 'Matin'),
    'midi':       ('☀️', 'Midi'),
    'apres_midi': ('🌤️', 'Après-midi'),
    'soir':       ('🌙', 'Soir'),
  };

  @override
  Widget build(BuildContext context) {
    final (emoji, label) = _infos[tranche] ?? ('📋', 'Autre');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: const Color(0xFF0C5C6C).withValues(alpha: 0.2))),
      ]),
    );
  }
}

// ── Carte groupée ─────────────────────────────────────────────────────────────

class _GroupedTacheCard extends StatelessWidget {
  final _TaskGroup  group;
  final List<Map<String, dynamic>> employes;
  final String? uid;
  final String  dateRef;
  final VoidCallback onValider;
  final VoidCallback onReporter;
  final void Function(String?) onAssigner;
  final VoidCallback onSupprimer;
  final VoidCallback onModifierTranche;

  const _GroupedTacheCard({
    required this.group,
    required this.employes,
    required this.uid,
    required this.dateRef,
    required this.onValider,
    required this.onReporter,
    required this.onAssigner,
    required this.onSupprimer,
    required this.onModifierTranche,
  });

  static const _green  = Color(0xFF0C5C6C);
  static const _dark   = Color(0xFF1F2A2E);
  static const _orange = Color(0xFFD97706);

  List<Map<String, dynamic>> get taches => group.taches;

  String get _baseLabel {
    final label = taches.first['label'] as String? ?? '';
    // Nouveau format : label ne contient plus le nom d'animal → retourner tel quel
    // Ancien format : "Promenade — Rex — Jour 1/364" → extraire "Promenade"
    final parts = label.split(' — ');
    if (parts.length <= 1) return label;
    // Si la 2e partie ressemble à "Jour N/M" = ancien format sans animal
    if (parts.length == 2 && RegExp(r'^Jour \d+/\d+$').hasMatch(parts[1])) {
      return parts[0];
    }
    // Si la 2e partie est un nom d'animal (3+ parties ou nom seul)
    if (parts.length >= 2) {
      final lastPart = parts.last;
      if (RegExp(r'^Jour \d+/\d+$').hasMatch(lastPart)) {
        // "Promenade — Rex — Jour 1/N" → base = "Promenade"
        return parts.first;
      }
      // "Promenade — Rex" → base = "Promenade"
      return parts.first;
    }
    return label;
  }

  List<String> get _animaux {
    // Nouveau format : lire 'animal_nom'
    final fromField = taches
        .map((t) => t['animal_nom'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    if (fromField.isNotEmpty) return fromField;

    // Ancien format : extraire depuis le label
    final names = <String>[];
    for (final t in taches) {
      final nom = _PlanningJourPageState._animalNomFromTache(t);
      if (nom.isNotEmpty && !names.contains(nom)) names.add(nom);
    }
    return names;
  }

  String get _typeEmoji => switch (taches.first['type_acte']?.toString() ?? '') {
    'vermifuge'       => '💊',
    'vaccination'     => '💉',
    'antiparasitaire' => '🛡️',
    'traitement'      => '🩺',
    'visite'          => '🏥',
    'toilettage'      => '🛁',
    'peignage'        => '🪮',
    'nettoyage'       => '🧹',
    'promenade'       => '🦮',
    'socialisation'   => '🐾',
    _                 => '📋',
  };

  String? get _assigneNom {
    final assignedTo = taches.first['assigned_to'] as String?;
    if (assignedTo == null) return null;
    if (!taches.every((t) => t['assigned_to'] == assignedTo)) return null; // assignations mixtes
    return employes.firstWhere(
      (e) => e['uid_employe'] == assignedTo,
      orElse: () => {},
    )['nom'] as String?;
  }

  void _showAssignSheet(BuildContext context) {
    final assignedTo = taches.every((t) => t['assigned_to'] == taches.first['assigned_to'])
        ? taches.first['assigned_to'] as String?
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Assigner ${taches.length > 1 ? '${taches.length} tâches' : 'la tâche'}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            if (assignedTo != null)
              ListTile(
                leading: const Icon(Icons.person_off_outlined, color: Colors.red),
                title: const Text('Retirer l\'assignation', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.red)),
                onTap: () { Navigator.pop(context); onAssigner(null); },
                contentPadding: EdgeInsets.zero,
              ),
            ...employes.map((e) => ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: _green.withValues(alpha: 0.12),
                child: Text((e['nom'] as String? ?? '?')[0].toUpperCase(),
                    style: const TextStyle(fontFamily: 'Galey', color: _green, fontWeight: FontWeight.w700)),
              ),
              title: Text(e['nom'] as String? ?? '—', style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
              trailing: e['uid_employe'] == assignedTo
                  ? const Icon(Icons.check_circle, color: _green, size: 20) : null,
              onTap: () { Navigator.pop(context); onAssigner(e['uid_employe'] as String); },
              contentPadding: EdgeInsets.zero,
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref         = (taches.first['plans_actifs'] as Map<String, dynamic>?)?['reference_label'] as String?;
    final isMultiJours = (taches.first['total_jours'] as num? ?? 1).toInt() > 1;
    final reporte     = taches.first['statut']?.toString() == 'reporte';
    final assigneNom  = _assigneNom;
    final animaux     = _animaux;
    final count       = taches.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        border: reporte ? Border.all(color: _orange.withValues(alpha: 0.4)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Ligne principale ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: _green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text(_typeEmoji, style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_baseLabel,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: _dark)),
                      if (ref != null) ...[
                        const SizedBox(height: 2),
                        Text(ref, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                      ],
                      if (reporte)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: _orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Reporté', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _orange)),
                          ),
                        ),
                    ],
                  ),
                ),
                // ── Menu ···  ──
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                  onSelected: (v) {
                    if (v == 'tranche') onModifierTranche();
                    if (v == 'supprimer') onSupprimer();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'tranche', child: Row(children: [
                      Icon(Icons.access_time_outlined, size: 18, color: Color(0xFF0C5C6C)),
                      SizedBox(width: 8),
                      Text('Modifier le moment', style: TextStyle(fontFamily: 'Galey')),
                    ])),
                    const PopupMenuItem(value: 'supprimer', child: Row(children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
                    ])),
                  ],
                ),
              ],
            ),
          ),

          // ── Animaux concernés ──
          if (animaux.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Wrap(
                spacing: 5, runSpacing: 4,
                children: animaux.map((nom) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _green.withValues(alpha: 0.2)),
                  ),
                  child: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _dark)),
                )).toList(),
              ),
            ),
          ],

          // ── Progressbar multi-jours ──
          if (isMultiJours)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: _ProgressBar(
                current: (taches.first['jour_traitement'] as num? ?? 1).toInt(),
                total:   (taches.first['total_jours']    as num? ?? 1).toInt(),
              ),
            ),

          // ── Employé assigné ──
          if (assigneNom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('👤 $assigneNom', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
              ),
            ),

          // ── Boutons d'action ──
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Row(
              children: [
                Expanded(child: _ActionBtn(
                  icon: Icons.check_circle_outline,
                  label: count > 1 ? 'Valider tous ($count)' : 'Valider',
                  color: _green,
                  onTap: onValider,
                )),
                const SizedBox(width: 8),
                Expanded(child: _ActionBtn(
                  icon: Icons.schedule_outlined,
                  label: 'Reporter',
                  color: _orange,
                  onTap: onReporter,
                )),
                if (employes.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _IconBtn(
                    icon: assigneNom != null ? Icons.person : Icons.person_add_outlined,
                    color: assigneNom != null ? _green : Colors.grey.shade400,
                    tooltip: 'Assigner',
                    onTap: () => _showAssignSheet(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets communs ─────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      ]),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Icon(icon, color: color, size: 20),
      ),
    ),
  );
}

class _ProgressBar extends StatelessWidget {
  final int current, total;
  const _ProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: current / total,
        backgroundColor: const Color(0xFF0C5C6C).withValues(alpha: 0.15),
        valueColor: const AlwaysStoppedAnimation(Color(0xFF0C5C6C)),
        minHeight: 5,
      ),
    )),
    const SizedBox(width: 8),
    Text('J$current/$total', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C), fontWeight: FontWeight.w600)),
  ]);
}

// ─── Sélecteur de semaine ─────────────────────────────────────────────────────

class _DateStrip extends StatelessWidget {
  final DateTime selected;
  final int weekOffset;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onPrevWeek, onNextWeek, onToday;

  const _DateStrip({
    required this.selected, required this.weekOffset,
    required this.onSelected, required this.onPrevWeek,
    required this.onNextWeek, required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final today  = DateTime.now();
    final anchor = today.add(Duration(days: weekOffset * 7));
    final days   = List.generate(7, (i) => anchor.subtract(const Duration(days: 3)).add(Duration(days: i)));
    final isCurrentWeek = weekOffset == 0;

    return Container(
      color: const Color(0xFF0C5C6C),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavBtn(icon: Icons.chevron_left,  onTap: onPrevWeek),
                GestureDetector(
                  onTap: isCurrentWeek ? null : onToday,
                  child: Text(
                    isCurrentWeek ? 'Cette semaine'
                        : weekOffset > 0 ? 'Semaine +$weekOffset' : 'Semaine $weekOffset',
                    style: TextStyle(
                      fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                      color: isCurrentWeek ? Colors.white70 : Colors.white,
                      decoration: isCurrentWeek ? null : TextDecoration.underline,
                    ),
                  ),
                ),
                _NavBtn(icon: Icons.chevron_right, onTap: onNextWeek),
              ],
            ),
          ),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              itemCount: days.length,
              itemBuilder: (_, i) {
                final d       = days[i];
                final active  = DateUtils.isSameDay(d, selected);
                final isToday = DateUtils.isSameDay(d, today);
                return GestureDetector(
                  onTap: () => onSelected(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: active ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isToday && !active ? Border.all(color: Colors.white60, width: 1.5) : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('EEE', 'fr_FR').format(d).substring(0, 2).toUpperCase(),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 9, color: active ? Colors.white : Colors.white60),
                        ),
                        const SizedBox(height: 2),
                        Text('${d.day}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700,
                                color: active ? Colors.white : Colors.white70)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: Colors.white, size: 20)),
  );
}

// ─── État vide ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final DateTime date;
  const _EmptyState({required this.date});

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            isToday ? 'Aucune tâche aujourd\'hui' : 'Aucune tâche ce jour',
            style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez des protocoles pour générer\ndes tâches automatiquement',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanTemplateListPage())),
            icon: const Icon(Icons.add, size: 18, color: Color(0xFF0C5C6C)),
            label: const Text('Créer un protocole', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C))),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF0C5C6C))),
          ),
        ],
      ),
    );
  }
}
