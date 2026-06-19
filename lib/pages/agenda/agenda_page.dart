import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/widgets/pro_day_timeline.dart';

const _kTeal = Color(0xFF0C5C6C);

// ── Types (catalogue complet — le sous-ensemble affiché dépend du profil) ─────

const _kTypeLabel = {
  'rdv':        'RDV',
  'mise_bas':   'Mise-bas',
  'medication': 'Médicament',
  'visite':     'Visite',
  'formation':  'Formation',
  'reunion':    'Réunion',
  'absence':    'Absence',
  'autre':      'Autre',
};

const _kTypeIcon = {
  'rdv':        '🩺',
  'mise_bas':   '🐣',
  'medication': '💊',
  'visite':     '👀',
  'formation':  '📚',
  'reunion':    '🤝',
  'absence':    '🏖️',
  'autre':      '📅',
};

const _kTypeColor = {
  'rdv':        Color(0xFF2196F3),
  'mise_bas':   Color(0xFFE91E63),
  'medication': Color(0xFFFF9800),
  'visite':     Color(0xFF4CAF50),
  'formation':  Color(0xFF7B1FA2),
  'reunion':    Color(0xFF0288D1),
  'absence':    Color(0xFF78909C),
  'autre':      Color(0xFF9E9E9E),
};

/// Types disponibles selon le profil connecté.
List<String> _typesForProfile() {
  if (User_Info.isPro) {
    return ['rdv', 'formation', 'reunion', 'absence', 'autre'];
  }
  if (User_Info.isElevage) {
    return ['rdv', 'mise_bas', 'medication', 'visite', 'autre'];
  }
  // Particulier
  return ['rdv', 'visite', 'autre'];
}

String _eventSubtitle(String time, String type, dynamic dureeMinutes) {
  final label = _kTypeLabel[type] ?? type;
  if (dureeMinutes == null) return '$time  ·  $label';
  final d = (dureeMinutes as num).toInt();
  final durLabel = d < 60 ? '$d min' : (d % 60 == 0 ? '${d ~/ 60} h' : '${d ~/ 60} h ${d % 60}');
  return '$time  ·  $durLabel  ·  $label';
}

DateTime _parseDate(String s) {
  try {
    final dt = DateTime.parse(s);
    return dt.isUtc ? dt.toLocal() : DateTime.parse('${s}Z').toLocal();
  } catch (_) {
    return DateTime.now();
  }
}

Color _colorFor(Map<String, dynamic> e) {
  if (e['couleur'] != null) {
    try { return Color(int.parse('FF${(e['couleur'] as String).replaceAll('#', '')}', radix: 16)); } catch (_) {}
  }
  return _kTypeColor[e['type']] ?? const Color(0xFF9E9E9E);
}

// ── Page ─────────────────────────────────────────────────────────────────────

class AgendaPage extends StatefulWidget {
  final VoidCallback? onBack;
  const AgendaPage({super.key, this.onBack});
  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _tasks  = [];
  bool _loading = true;
  // 0 = mois, 1 = jour, 2 = liste
  int _viewMode = 0;
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _load();
    _loadTasks();
  }

  Future<void> _load() async {
    if (_events.isEmpty) setState(() => _loading = true);
    final from = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1).toUtc();
    final to   = DateTime(_focusedMonth.year, _focusedMonth.month + 2, 0, 23, 59, 59).toUtc();
    final pid  = User_Info.activeProfileId;
    // Try with pro_profile_id filter first; fall back if column not yet migrated.
    List<dynamic>? data;
    try {
      data = await _supa
          .from('agenda_events')
          .select()
          .eq('uid', _uid)
          .eq('pro_profile_id', pid)
          .gte('date_debut', from.toIso8601String())
          .lte('date_debut', to.toIso8601String())
          .order('date_debut');
    } catch (_) {
      try {
        data = await _supa
            .from('agenda_events')
            .select()
            .eq('uid', _uid)
            .gte('date_debut', from.toIso8601String())
            .lte('date_debut', to.toIso8601String())
            .order('date_debut');
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        if (data != null) _events = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) => _events.where((e) {
    final d = _parseDate(e['date_debut'] as String);
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }).toList();

  List<Map<String, dynamic>> get _upcoming => _events.where((e) {
    return _parseDate(e['date_debut'] as String).isAfter(DateTime.now().subtract(const Duration(days: 1)));
  }).toList();

  Future<void> _loadTasks() async {
    final from = '${_focusedMonth.year}-${(_focusedMonth.month - 1).clamp(1, 12).toString().padLeft(2, '0')}-01';
    final toDate = DateTime(_focusedMonth.year, _focusedMonth.month + 2, 0);
    final to   = '${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}';
    try {
      // ── Tâches manuelles ─────────────────────────────────────────────────
      final d1 = await _supa.from('taches_elevage')
          .select('id,titre,date,statut,assigne_a,uid_eleveur')
          .eq('uid_eleveur', _uid).gte('date', from).lte('date', to);
      final d2 = await _supa.from('taches_elevage')
          .select('id,titre,date,statut,assigne_a,uid_eleveur')
          .eq('assigne_a', _uid).gte('date', from).lte('date', to);
      final seen = <dynamic>{};
      final all  = <Map<String, dynamic>>[];
      for (final t in [...(d1 as List), ...(d2 as List)]) {
        final m = Map<String, dynamic>.from(t);
        if (seen.add(m['id'])) all.add({...m, '_source': 'manuel'});
      }

      // ── Tâches protocole (plan_taches) ───────────────────────────────────
      try {
        final p1 = await _supa.from('plan_taches')
            .select('id,label,date_prevue,statut,assigned_to,uid_eleveur,type_acte,animal_nom,etape_id')
            .eq('uid_eleveur', _uid)
            .gte('date_prevue', from).lte('date_prevue', to);
        final p2 = await _supa.from('plan_taches')
            .select('id,label,date_prevue,statut,assigned_to,uid_eleveur,type_acte,animal_nom,etape_id')
            .eq('assigned_to', _uid)
            .gte('date_prevue', from).lte('date_prevue', to);
        final seenPlan = <dynamic>{};
        for (final t in [...(p1 as List), ...(p2 as List)]) {
          final m = Map<String, dynamic>.from(t);
          if (seenPlan.add(m['id'])) {
            all.add({
              ...m,
              '_source': 'protocole',
              // Normalise les champs pour la vue agenda
              'titre': m['label'],
              'date': (m['date_prevue'] as String? ?? '').split('T').first,
            });
          }
        }
      } catch (_) {}

      // ── Résoudre les noms ─────────────────────────────────────────────────
      final uids = <String>{};
      for (final t in all) {
        final assignee = (t['assigne_a'] ?? t['assigned_to']) as String?;
        if (assignee != null) uids.add(assignee);
        if (t['uid_eleveur'] != null) uids.add(t['uid_eleveur'] as String);
      }
      if (uids.isNotEmpty) {
        try {
          final users = await _supa.from('users')
              .select('uid,firstname,lastname,name_elevage,is_elevage')
              .inFilter('uid', uids.toList());
          final nomMap = <String, String>{};
          for (final u in (users as List)) {
            final uid = u['uid'] as String;
            final nom = (u['is_elevage'] == true && u['name_elevage'] != null)
                ? u['name_elevage'] as String
                : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
            if (nom.isNotEmpty) nomMap[uid] = nom;
          }
          for (final t in all) {
            final assignee = (t['assigne_a'] ?? t['assigned_to']) as String?;
            final resp = assignee ?? (t['uid_eleveur'] as String?);
            t['responsable_nom'] = resp != null ? nomMap[resp] : null;
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _tasks = all);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _tasksForDay(DateTime day) {
    final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _tasks.where((t) => (t['date'] ?? '').toString().startsWith(key)).toList();
  }

  // ── Section tâches du jour (agenda) — groupée par etape_id ─────────────────

  static String _protoEmoji(String? typeActe) => switch (typeActe ?? '') {
    'vermifuge'       => '💊',
    'vaccination'     => '💉',
    'antiparasitaire' => '🛡️',
    'traitement'      => '🩺',
    'visite'          => '🏥',
    'alimentaire'     => '🍽️',
    'toilettage'      => '✂️',
    'peignage'        => '🪮',
    'nettoyage'       => '🧴',
    'promenade'       => '🦮',
    'socialisation'   => '🦮',
    _                 => '📋',
  };

  Widget _buildDayTasksSection(List<Map<String, dynamic>> tasks) {
    final manuel = tasks.where((t) => t['_source'] != 'protocole').toList();

    final protoMap = <String, List<Map<String, dynamic>>>{};
    for (final t in tasks.where((t) => t['_source'] == 'protocole')) {
      final key = (t['etape_id'] as String?) ?? 'solo_${t['id']}';
      protoMap.putIfAbsent(key, () => []).add(t);
    }
    final protoGroups = protoMap.values.toList();

    final protoEnCours    = protoGroups.where((g) => !g.every((t) => t['statut'] == 'fait')).toList();
    final protoEffectuees = protoGroups.where((g) =>  g.every((t) => t['statut'] == 'fait')).toList();
    final manuelEnCours    = manuel.where((t) => t['statut'] != 'fait').toList();
    final manuelEffectuees = manuel.where((t) => t['statut'] == 'fait').toList();

    final totalItems = manuel.length + protoGroups.length;
    final doneItems  = manuelEffectuees.length + protoEffectuees.length;

    // ── Carte d'un groupe protocole ─────────────────────────────────────────
    Widget protoCard(List<Map<String, dynamic>> groupe, {bool effectuee = false}) {
      final total   = groupe.length;
      final done    = groupe.where((t) => t['statut'] == 'fait').length;
      final pct     = total > 0 ? done / total : 0.0;
      final first   = groupe.first;
      final label   = (first['titre'] ?? first['label'] ?? '') as String;
      final emoji   = _protoEmoji(first['type_acte']?.toString());
      final allDone = done == total;

      return GestureDetector(
        onTap: effectuee
            ? null
            : () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _AgendaProtoSheet(
                    groupe: groupe, label: label, emoji: emoji,
                    onDone: _loadTasks,
                    onDelete: (ids) async {
                      final dayDate = (groupe.first['date_prevue'] as String? ??
                          groupe.first['date'] as String? ?? '').split('T').first;
                      await _supa.from('plan_taches').delete()
                          .inFilter('id', ids)
                          .gte('date_prevue', '${dayDate}T00:00:00')
                          .lte('date_prevue', '${dayDate}T23:59:59');
                      _loadTasks();
                    },
                  ),
                );
              },
        onLongPress: () => _deleteProtoGroup(groupe),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: allDone ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kTeal.withValues(alpha: allDone ? 0.1 : 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(label,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                    color: allDone ? Colors.grey.shade400 : const Color(0xFF1E2025),
                    decoration: allDone ? TextDecoration.lineThrough : null),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (effectuee)
                GestureDetector(
                  onTap: () => _deleteProtoGroup(groupe),
                  child: Icon(Icons.delete_outline, size: 16, color: Colors.grey.shade400),
                )
              else ...[
                Text('$done/$total',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: allDone ? Colors.grey : _kTeal, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                GestureDetector(
                  onTap: () => _showReporterDialog(groupe.first, isProtocole: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.schedule_outlined, size: 15, color: Colors.grey.shade400),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16,
                    color: allDone ? Colors.grey.shade300 : Colors.grey.shade400),
              ],
            ]),
            if (total > 1 && !effectuee) ...[
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: pct,
                backgroundColor: _kTeal.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(allDone ? Colors.grey.shade300 : _kTeal),
                minHeight: 3,
              ),
            ],
          ]),
        ),
      );
    }

    // ── Ligne d'une tâche manuelle ──────────────────────────────────────────
    Widget manuelRow(Map<String, dynamic> t) {
      final isDone = t['statut'] == 'fait';
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          GestureDetector(
            onTap: () async {
              final newStatut = isDone ? 'a_faire' : 'fait';
              await _supa.from('taches_elevage').update({'statut': newStatut}).eq('id', t['id']);
              _loadTasks();
            },
            child: Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: isDone ? const Color(0xFF6E9E57) : Colors.grey.shade300, width: 2),
                color: isDone ? const Color(0xFF6E9E57) : Colors.transparent,
              ),
              child: isDone ? const Icon(Icons.check, size: 11, color: Colors.white) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t['titre'] ?? '',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: isDone ? Colors.grey.shade400 : const Color(0xFF1E2025),
                    decoration: isDone ? TextDecoration.lineThrough : null),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              if (t['responsable_nom'] != null)
                Text(isDone ? 'Fait par : ${t['responsable_nom']}' : '👤 ${t['responsable_nom']}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10.5,
                        color: isDone ? Colors.grey.shade400 : Colors.grey.shade500)),
            ],
          )),
          if (!isDone) ...[
            GestureDetector(
              onTap: () => _showReporterDialog(t, isProtocole: false),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.schedule_outlined, size: 16, color: Colors.grey.shade400),
              ),
            ),
          ],
          GestureDetector(
            onTap: () => _deleteManualTask(t),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.delete_outline, size: 16, color: Colors.grey.shade400),
            ),
          ),
        ]),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFEDF6F7),
        border: Border(bottom: BorderSide(color: Color(0xFFD0E8EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── En-tête ────────────────────────────────────────────────────
          Row(children: [
            const Text('✅', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            const Text('Tâches du jour',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: _kTeal)),
            const Spacer(),
            Text('$doneItems/$totalItems',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
          ]),
          const SizedBox(height: 8),

          // ── À faire : protocoles ──────────────────────────────────────
          ...protoEnCours.map((g) => protoCard(g)),

          // ── À faire : manuelles ──────────────────────────────────────
          ...manuelEnCours.map((t) => manuelRow(t)),

          // ── Effectuées ────────────────────────────────────────────────
          if (doneItems > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Effectuées ($doneItems)',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
            ]),
            const SizedBox(height: 6),
            ...protoEffectuees.map((g) => protoCard(g, effectuee: true)),
            ...manuelEffectuees.map((t) => manuelRow(t)),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteManualTask(Map<String, dynamic> t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la tâche ?',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text(t['titre'] ?? '', style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _supa.from('taches_elevage').delete().eq('id', t['id']);
      _loadTasks();
    }
  }

  Future<void> _deleteProtoGroup(List<Map<String, dynamic>> groupe) async {
    final label = (groupe.first['titre'] ?? groupe.first['label'] ?? '') as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le protocole du jour ?',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text(label, style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final ids = groupe.map((t) => t['id']).toList();
      // On scope explicitement sur la date du jour pour ne pas toucher les récurrences futures
      final dayDate = (groupe.first['date_prevue'] as String? ??
          groupe.first['date'] as String? ?? '').split('T').first;
      await _supa.from('plan_taches').delete()
          .inFilter('id', ids)
          .gte('date_prevue', '${dayDate}T00:00:00')
          .lte('date_prevue', '${dayDate}T23:59:59');
      _loadTasks();
    }
  }

  Future<void> _showReporterDialog(Map<String, dynamic> t, {required bool isProtocole}) async {
    final currentDateStr = isProtocole
        ? (t['date_prevue'] as String? ?? t['date'] as String? ?? '')
        : (t['date'] as String? ?? '');
    final currentDate = DateTime.tryParse(currentDateStr) ?? DateTime.now();
    final minDate = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate.isAfter(minDate) ? currentDate : minDate.add(const Duration(days: 1)),
      firstDate: minDate,
      lastDate: DateTime(2030),
      locale: const Locale('fr'),
    );
    if (picked == null || !mounted) return;
    final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

    if (isProtocole) {
      await _supa.from('plan_taches').update({'date_prevue': '${dateStr}T00:00:00'}).eq('id', t['id']);
    } else {
      await _supa.from('taches_elevage').update({'date': dateStr}).eq('id', t['id']);
    }
    _loadTasks();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Tâche reportée au ${DateFormat('d MMMM yyyy', 'fr').format(picked)}',
            style: const TextStyle(fontFamily: 'Galey')),
        backgroundColor: _kTeal,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _prevMonth() { _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1); _load(); _loadTasks(); }
  void _nextMonth() { _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1); _load(); _loadTasks(); }

  // ── Add event ──────────────────────────────────────────────────────────────

  void _showAddSheet({DateTime? initialDate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddEventSheet(
        initialDate: initialDate ?? _selectedDay ?? DateTime.now(),
        uid: _uid,
        onSaved: _load,
      ),
    );
  }

  void _showDaySheet(DateTime day) {
    final evts = _eventsForDay(day);
    if (evts.isEmpty) { _showAddSheet(initialDate: day); return; }
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DaySheet(day: day, events: evts, onAdd: () { Navigator.pop(context); _showAddSheet(initialDate: day); }, onRefresh: _load),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                tooltip: 'Retour',
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('Mon Agenda',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: _viewMode == 0 ? 'Vue jour' : _viewMode == 1 ? 'Vue liste' : 'Vue calendrier',
            icon: Icon(_viewMode == 0 ? Icons.view_day_outlined : _viewMode == 1 ? Icons.list_rounded : Icons.calendar_month_rounded),
            onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 3),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        onPressed: () => _showAddSheet(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kTeal))
          : _viewMode == 0 ? _calendarView()
          : _viewMode == 1 ? _dayView()
          : _listView(),
    );
  }

  // ── Calendar view ──────────────────────────────────────────────────────────

  Widget _calendarView() {
    return Column(children: [
      _monthHeader(),
      _weekdayRow(),
      Expanded(child: _calendarGrid()),
    ]);
  }

  Widget _monthHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left, color: _kTeal), onPressed: _prevMonth),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy', 'fr').format(_focusedMonth),
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 16, color: Color(0xFF1E2025)),
          ),
        ),
        IconButton(icon: const Icon(Icons.chevron_right, color: _kTeal), onPressed: _nextMonth),
      ]),
    );
  }

  Widget _weekdayRow() {
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: days.map((d) => Expanded(
          child: Text(d, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600, color: Colors.grey)),
        )).toList(),
      ),
    );
  }

  Widget _calendarGrid() {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final last  = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    // Monday = 1, so offset = weekday - 1
    final startOffset = (first.weekday - 1) % 7;
    final totalCells  = startOffset + last.day;
    final rows        = (totalCells / 7).ceil();
    final today       = DateTime.now();

    return RefreshIndicator(
      onRefresh: _load,
      color: _kTeal,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: 0.85, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: rows * 7,
        itemBuilder: (_, index) {
          final dayNum = index - startOffset + 1;
          if (dayNum < 1 || dayNum > last.day) return const SizedBox();
          final day = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
          final evts = _eventsForDay(day);
          final tasks = _tasksForDay(day);
          final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
          final isSelected = _selectedDay != null &&
              day.year == _selectedDay!.year && day.month == _selectedDay!.month && day.day == _selectedDay!.day;

          return GestureDetector(
            onTap: () { setState(() { _selectedDay = day; _viewMode = 1; }); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isSelected ? _kTeal : isToday ? _kTeal.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: isToday && !isSelected ? Border.all(color: _kTeal, width: 1.5) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$dayNum',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isSelected ? Colors.white : const Color(0xFF1E2025),
                    )),
                  if (evts.isNotEmpty || tasks.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 2,
                      children: [
                        ...evts.take(2).map((e) => Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withValues(alpha: 0.8) : _colorFor(e),
                            shape: BoxShape.circle,
                          ),
                        )),
                        if (tasks.isNotEmpty) Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.8)
                                : const Color(0xFF6E9E57),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Day view ───────────────────────────────────────────────────────────────

  Widget _dayView() {
    final day = _selectedDay ?? DateTime.now();
    final evts = _eventsForDay(day);
    final dayTasks = _tasksForDay(day);

    return Column(children: [
      // Navigation jour
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: _kTeal),
            onPressed: () => setState(() => _selectedDay = day.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: day,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  locale: const Locale('fr'),
                );
                if (picked != null && mounted) setState(() => _selectedDay = picked);
              },
              child: Text(
                DateFormat('EEEE d MMMM', 'fr').format(day),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 15, color: Color(0xFF1E2025)),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: _kTeal),
            onPressed: () => setState(() => _selectedDay = day.add(const Duration(days: 1))),
          ),
        ]),
      ),
      const Divider(height: 1),
      if (dayTasks.isNotEmpty) _buildDayTasksSection(dayTasks),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async { await _load(); await _loadTasks(); },
          color: _kTeal,
          child: evts.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 80, left: 32, right: 32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.event_available_outlined, size: 64, color: Colors.grey.shade200),
                      const SizedBox(height: 12),
                      Text('Aucun événement ce jour',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 15,
                              color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Appuyez sur + pour en ajouter un',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              color: Colors.grey.shade300)),
                    ]),
                  ),
                ])
              : ProDayTimeline(
                  rdvs: evts,
                  date: day,
                  heureDebut: 7,
                  heureFin: 22,
                  onRdvTap: (e) {
                    if (e['type'] == 'rdv' && e['rdv_id'] != null) {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                        builder: (_) => _RdvDetailSheet(event: e, onRefresh: _load),
                      );
                    } else {
                      showModalBottomSheet(
                        context: context,
                        useSafeArea: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => _DaySheet(
                          day: day,
                          events: [e],
                          onAdd: () { Navigator.pop(context); _showAddSheet(initialDate: day); },
                          onRefresh: _load,
                        ),
                      );
                    }
                  },
                  showCurrentTimeLine: true,
                ),
        ),
      ),
    ]);
  }

  // ── List view ──────────────────────────────────────────────────────────────

  Widget _listView() {
    if (_upcoming.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Aucun événement à venir',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey)),
          const SizedBox(height: 16),
          TextButton(onPressed: () => _showAddSheet(),
              child: const Text('Ajouter un événement',
                  style: TextStyle(fontFamily: 'Galey', color: _kTeal))),
        ]),
      );
    }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in _upcoming) {
      final key = DateFormat('yyyy-MM-dd').format(_parseDate(e['date_debut'] as String));
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final keys = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      color: _kTeal,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final key  = keys[i];
          final day  = DateTime.parse(key);
          final evts = grouped[key]!;
          final today = DateTime.now();
          final isToday = day.year == today.year && day.month == today.month && day.day == today.day;

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6, top: 12),
              child: Row(children: [
                Text(
                  isToday ? "Aujourd'hui" : DateFormat('EEEE d MMMM', 'fr').format(day),
                  style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13,
                    color: isToday ? _kTeal : const Color(0xFF555555),
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _kTeal, borderRadius: BorderRadius.circular(10)),
                    child: const Text('Aujourd\'hui',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                          fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ]
              ]),
            ),
            ...evts.map((e) => _EventTile(event: e, onRefresh: _load)),
          ]);
        },
      ),
    );
  }
}

// ── EventTile ─────────────────────────────────────────────────────────────────

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onRefresh;
  const _EventTile({required this.event, required this.onRefresh});

  bool get _isRdv => event['type'] == 'rdv';
  String? get _rdvId => event['rdv_id']?.toString().let((v) => v.isNotEmpty ? v : null);
  bool get _canCancelRdv {
    if (_rdvId == null) return false;
    final d = _parseDate(event['date_debut'] as String);
    return d.isAfter(DateTime.now().add(const Duration(hours: 24)));
  }

  Future<void> _showCancelOrModify(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const Text('Que souhaitez-vous faire ?',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined, color: _kTeal),
            title: const Text('Modifier le rendez-vous',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Choisir un autre créneau disponible',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200)),
            onTap: () => Navigator.pop(ctx, 'modifier'),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.cancel_outlined, color: Colors.red),
            title: const Text('Annuler définitivement',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.red)),
            subtitle: const Text('Le professionnel sera notifié',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200)),
            onTap: () => Navigator.pop(ctx, 'annuler'),
          ),
        ]),
      ),
    );
    if (choice == 'modifier' && context.mounted) {
      await _proposeNewSlot(context);
    } else if (choice == 'annuler' && context.mounted) {
      await _cancelRdv(context);
    }
  }

  Future<void> _proposeNewSlot(BuildContext context) async {
    final supa = Supabase.instance.client;
    final rdvId = _rdvId!;

    // Charger les infos du RDV (pro_uid, durée)
    final rdvRow = await supa.from('rdv')
        .select('pro_uid, duree_minutes, motif')
        .eq('id', rdvId).maybeSingle();
    if (rdvRow == null || !context.mounted) return;
    final proUid     = rdvRow['pro_uid'] as String;
    final duration   = (rdvRow['duree_minutes'] as num?)?.toInt() ?? 30;

    final now        = DateTime.now();
    final todayStr   = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    final maxDate    = DateTime(now.year, now.month + 3, now.day);
    final maxDateStr = '${maxDate.year}-${maxDate.month.toString().padLeft(2,'0')}-${maxDate.day.toString().padLeft(2,'0')}';

    // Charger créneaux + RDVs existants (hors le RDV modifié)
    final results = await Future.wait([
      supa.from('creneaux_pro')
          .select('date, heure_debut, heure_fin')
          .eq('pro_uid', proUid).eq('statut', 'disponible')
          .gte('date', todayStr).lte('date', maxDateStr)
          .order('date', ascending: true).order('heure_debut', ascending: true),
      supa.from('rdv')
          .select('date_heure, duree_minutes')
          .eq('pro_uid', proUid)
          .inFilter('statut', ['confirme', 'demande', 'contre_proposition'])
          .neq('id', rdvId)
          .gte('date_heure', now.toUtc().toIso8601String()),
    ]);

    if (!context.mounted) return;

    final creneaux   = List<Map<String, dynamic>>.from(results[0]);
    final rdvsExist  = List<Map<String, dynamic>>.from(results[1]);
    final smartSlots = _SmartSlotCalc.compute(
        creneaux: creneaux, existingRdvs: rdvsExist,
        duration: duration, now: now);

    if (smartSlots.isEmpty) {
      // Fallback: sélecteur libre si aucun créneau configuré
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(days: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
        locale: const Locale('fr'),
      );
      if (pickedDate == null || !context.mounted) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 10, minute: 0),
      );
      if (pickedTime == null || !context.mounted) return;
      final chosen = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
          pickedTime.hour, pickedTime.minute);
      await _applyModification(context, supa, rdvId, proUid, chosen, duration);
      return;
    }

    final dates = smartSlots.keys.toList()..sort();
    String selDate = dates.first;
    String? selTime;

    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const Text('Modifier le rendez-vous',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Durée estimée : ${_fmtDuration(duration)}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            // Date chips
            SizedBox(
              height: 68,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: dates.length,
                itemBuilder: (_, i) {
                  final d = dates[i];
                  final dt = DateTime.parse(d);
                  final sel = d == selDate;
                  final count = smartSlots[d]?.length ?? 0;
                  return GestureDetector(
                    onTap: () => setModal(() { selDate = d; selTime = null; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? _kTeal : Colors.white,
                        border: Border.all(color: sel ? _kTeal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(DateFormat('EEE', 'fr').format(dt),
                            style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                color: sel ? Colors.white70 : Colors.grey.shade500)),
                        Text('${dt.day}/${dt.month}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : const Color(0xFF1E2025))),
                        Text('$count crén.',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                                color: sel ? Colors.white60 : Colors.grey.shade400)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(DateFormat('EEEE d MMMM', 'fr').format(DateTime.parse(selDate)),
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: (smartSlots[selDate] ?? []).map((time) {
                final sel = time == selTime;
                return GestureDetector(
                  onTap: () => setModal(() => selTime = time),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: sel ? _kTeal : Colors.white,
                      border: Border.all(color: sel ? _kTeal : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(time,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : const Color(0xFF1E2025))),
                  ),
                );
              }).toList(),
            ),
            if (selTime != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final dt  = DateTime.parse(selDate);
                    final tParts = selTime!.split(':');
                    Navigator.pop(ctx, DateTime(dt.year, dt.month, dt.day,
                        int.parse(tParts[0]), int.parse(tParts[1])));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Confirmer la modification',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );

    if (chosen == null || !context.mounted) return;
    await _applyModification(context, supa, rdvId, proUid, chosen, duration);
  }

  Future<void> _applyModification(BuildContext context, dynamic supa,
      String rdvId, String proUid, DateTime chosen, int duration) async {
    try {
      await supa.from('rdv').update({
        'statut':              'contre_proposition',
        'date_heure':          chosen.toUtc().toIso8601String(),
        'reminder_1h_sent':    false,  // reset reminders pour le nouveau créneau
        'reminder_15min_sent': false,
      }).eq('id', rdvId);

      final clientName = FirebaseAuth.instance.currentUser?.displayName ?? 'Le client';
      final dateStr = DateFormat('d MMM à HH:mm', 'fr').format(chosen);
      await supa.from('notifications').insert({
        'uid':   proUid,
        'type':  'rdv_contre_proposition',
        'title': 'Modification demandée par $clientName',
        'body':  '$clientName souhaite déplacer le RDV au $dateStr',
        'data':  {'rdv_id': rdvId},
        'read':  false,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Proposition envoyée au professionnel',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _kTeal,
          behavior: SnackBarBehavior.floating,
        ));
      }
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _cancelRdv(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const Text('Annuler définitivement',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Le professionnel sera notifié de votre annulation.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Motif de l\'annulation (optionnel)…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Confirmer l\'annulation',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
    ctrl.dispose();
    if (ok != true) return;

    try {
      final supa = Supabase.instance.client;
      final rdvId = _rdvId!;
      final motif = ctrl.text.trim();

      // Load rdv to get pro_uid
      final rdvRows = await supa.from('rdv').select('pro_uid').eq('id', rdvId);
      final proUid = rdvRows.isNotEmpty ? rdvRows[0]['pro_uid'] as String? : null;

      // Cancel the RDV
      await supa.from('rdv').update({
        'statut': 'annule',
        if (motif.isNotEmpty) 'notes_annulation': motif,
      }).eq('id', rdvId);

      // Remove from agenda
      await supa.from('agenda_events').delete().eq('id', event['id']);

      // Notify pro
      if (proUid != null) {
        final clientName = FirebaseAuth.instance.currentUser?.displayName ?? 'Le client';
        final motifPart = motif.isNotEmpty ? ' — Motif : $motif' : '';
        await supa.from('notifications').insert({
          'uid':   proUid,
          'type':  'rdv_annule_client',
          'title': 'RDV annulé par $clientName',
          'body':  '$clientName a annulé son rendez-vous$motifPart',
          'data':  {'rdv_id': rdvId},
          'read':  false,
        });
      }

      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(event);
    final time  = DateFormat('HH:mm').format(_parseDate(event['date_debut'] as String));
    final type  = event['type'] as String? ?? 'autre';

    Widget trailing;
    if (_isRdv && _rdvId != null) {
      if (_canCancelRdv) {
        trailing = IconButton(
          icon: const Icon(Icons.edit_calendar_outlined, size: 20, color: _kTeal),
          tooltip: 'Annuler ou modifier',
          onPressed: () => _showCancelOrModify(context),
        );
      } else {
        trailing = const Tooltip(
          message: 'Annulation impossible (< 24h)',
          child: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
        );
      }
    } else {
      trailing = IconButton(
        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
        onPressed: () async {
          final supa = Supabase.instance.client;
          await supa.from('agenda_events').delete().eq('id', event['id']);
          onRefresh();
        },
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(_kTypeIcon[type] ?? '📅', style: const TextStyle(fontSize: 18))),
        ),
        title: Text(event['titre'] ?? '',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 14, color: Color(0xFF1E2025))),
        subtitle: Text(_eventSubtitle(time, type, event['duree_minutes']),
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        trailing: trailing,
        onTap: _isRdv && _rdvId != null
            ? () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (_) => _RdvDetailSheet(event: event, onRefresh: onRefresh),
              )
            : null,
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}

// ── Algorithme créneaux intelligents (partagé avec rdv_booking_page) ──────────

String _fmtDuration(int min) {
  if (min < 60) return '$min min';
  final h = min ~/ 60; final m = min % 60;
  return m > 0 ? '${h}h$m' : '${h}h';
}

class _SmartSlotCalc {
  /// Calcule les créneaux disponibles (pas 15 min) en tenant compte
  /// des RDVs existants et de la durée de la prestation.
  static Map<String, List<String>> compute({
    required List<Map<String, dynamic>> creneaux,
    required List<Map<String, dynamic>> existingRdvs,
    required int duration,
    required DateTime now,
  }) {
    final todayKey   = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    final nowMinutes = now.hour * 60 + now.minute + 30; // marge 30 min

    // 1. Regrouper les créneaux par date
    final creneauxByDate = <String, List<({int startMin, int endMin})>>{};
    for (final slot in creneaux) {
      final date = slot['date'] as String;
      final sp = (slot['heure_debut'] as String).split(':');
      final ep = (slot['heure_fin']   as String).split(':');
      final s  = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final e  = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      creneauxByDate.putIfAbsent(date, () => []).add((startMin: s, endMin: e));
    }

    final result = <String, List<String>>{};
    for (final entry in creneauxByDate.entries) {
      final date  = entry.key;
      final slots = entry.value..sort((a, b) => a.startMin.compareTo(b.startMin));

      // 2. Fusionner les créneaux consécutifs
      final windows = <({int startMin, int endMin})>[];
      for (final s in slots) {
        if (windows.isNotEmpty && s.startMin <= windows.last.endMin) {
          windows[windows.length - 1] = (
            startMin: windows.last.startMin,
            endMin: s.endMin > windows.last.endMin ? s.endMin : windows.last.endMin,
          );
        } else {
          windows.add(s);
        }
      }

      // 3. Intervalles bloqués
      final blocked = <({int startMin, int endMin})>[];
      for (final rdv in existingRdvs) {
        final dh = DateTime.tryParse(rdv['date_heure'] as String? ?? '')?.toLocal();
        if (dh == null) continue;
        final rdvDate = '${dh.year}-${dh.month.toString().padLeft(2,'0')}-${dh.day.toString().padLeft(2,'0')}';
        if (rdvDate != date) continue;
        final d     = (rdv['duree_minutes'] as num?)?.toInt() ?? duration;
        final start = dh.hour * 60 + dh.minute;
        blocked.add((startMin: start, endMin: start + d));
      }

      // 4. Générer les créneaux (pas 15 min)
      final available = <String>[];
      for (final window in windows) {
        for (int t = window.startMin; t + duration <= window.endMin; t += 15) {
          if (date == todayKey && t < nowMinutes) continue;
          final overlaps = blocked.any((b) => t < b.endMin && t + duration > b.startMin);
          if (!overlaps) {
            final h = t ~/ 60; final m = t % 60;
            available.add('${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}');
          }
        }
      }
      if (available.isNotEmpty) result[date] = available;
    }
    return result;
  }
}

// ── Vue détail RDV (client) ───────────────────────────────────────────────────

class _RdvDetailSheet extends StatefulWidget {
  final Map<String, dynamic> event; // agenda_event row
  final VoidCallback onRefresh;
  const _RdvDetailSheet({required this.event, required this.onRefresh});

  @override
  State<_RdvDetailSheet> createState() => _RdvDetailSheetState();
}

class _RdvDetailSheetState extends State<_RdvDetailSheet> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _rdv;
  Map<String, dynamic>? _pro;
  Map<String, dynamic>? _animal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rdvId = widget.event['rdv_id']?.toString();
    if (rdvId == null) { setState(() => _loading = false); return; }
    try {
      final rdvRows = await _supa.from('rdv')
          .select('id, pro_uid, client_uid, animal_id, date_heure, motif, statut, duree_minutes, notes_client')
          .eq('id', rdvId).maybeSingle();
      if (rdvRows == null) { setState(() => _loading = false); return; }
      _rdv = Map<String, dynamic>.from(rdvRows);

      // Pro profile (adresse, GPS)
      try {
        final proRows = await _supa.from('users')
            .select('uid, firstname, lastname, name_elevage, profession_pro, adress_elevage, lat, lng, profile_picture_url_elevage')
            .eq('uid', _rdv!['pro_uid']).maybeSingle();
        if (proRows != null) _pro = Map<String, dynamic>.from(proRows);
      } catch (_) {}

      // Animal info
      final animalId = _rdv!['animal_id']?.toString();
      if (animalId != null && animalId.isNotEmpty) {
        try {
          final aRows = await _supa.from('animaux')
              .select('id, nom, espece, race, photo_url').eq('id', animalId).maybeSingle();
          if (aRows != null) _animal = Map<String, dynamic>.from(aRows);
        } catch (_) {}
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canModify {
    final d = _parseDate(widget.event['date_debut'] as String);
    return d.isAfter(DateTime.now().add(const Duration(hours: 24)));
  }

  String _proName() {
    if (_pro == null) return widget.event['titre']?.toString() ?? 'Professionnel';
    final elevage = _pro!['name_elevage']?.toString() ?? '';
    if (elevage.isNotEmpty) return elevage;
    final fn = _pro!['firstname']?.toString() ?? '';
    final ln = _pro!['lastname']?.toString() ?? '';
    final prof = _pro!['profession_pro']?.toString() ?? '';
    final name = '$fn $ln'.trim();
    if (name.isNotEmpty) return prof.isNotEmpty ? '$prof — $name' : name;
    return prof.isNotEmpty ? prof : 'Professionnel';
  }

  Future<void> _openNav() async {
    final lat = (_pro?['lat'] as num?)?.toDouble();
    final lng = (_pro?['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const Text('Ouvrir l\'itinéraire dans',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFF00CFFD),
                child: Text('W', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            title: const Text('Waze', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else {
                await launchUrl(Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes'),
                    mode: LaunchMode.externalApplication);
              }
            },
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFF4285F4),
                child: Icon(Icons.map_outlined, color: Colors.white, size: 20)),
            title: const Text('Google Maps', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(ctx);
              await launchUrl(
                Uri.parse('https://maps.google.com/?q=$lat,$lng'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventTile = _EventTile(event: widget.event, onRefresh: () {
      Navigator.pop(context);
      widget.onRefresh();
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scroll) => _loading
          ? const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: _teal)))
          : SingleChildScrollView(
              controller: scroll,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Handle
                  Center(child: Container(width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),

                  // ── Animal ────────────────────────────────────────────────
                  if (_animal != null) ...[
                    Row(children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: _teal.withValues(alpha: 0.10),
                        backgroundImage: (_animal!['photo_url']?.toString() ?? '').isNotEmpty
                            ? CachedNetworkImageProvider(_animal!['photo_url'].toString()) as ImageProvider
                            : null,
                        child: (_animal!['photo_url']?.toString() ?? '').isEmpty
                            ? const Icon(Icons.pets, color: _teal, size: 24) : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_animal!['nom']?.toString() ?? '',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800,
                                fontSize: 18, color: Color(0xFF1F2A2E))),
                        if ((_animal!['espece']?.toString() ?? '').isNotEmpty)
                          Text(
                            [_animal!['espece'], _animal!['race']].where((s) => s?.toString().isNotEmpty == true).join(' · '),
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal, fontWeight: FontWeight.w600),
                          ),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                  ],

                  // ── Date + heure + motif ──────────────────────────────────
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat("EEEE d MMMM 'à' HH'h'mm", 'fr').format(
                        _parseDate(widget.event['date_debut'] as String)),
                  ),
                  if (_rdv?['motif']?.toString().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    _InfoRow(icon: Icons.medical_services_outlined,
                        text: _rdv!['motif'].toString()),
                  ],
                  if (_rdv?['duree_minutes'] != null) ...[
                    const SizedBox(height: 8),
                    _InfoRow(icon: Icons.timer_outlined,
                        text: _durationLabel((_rdv!['duree_minutes'] as num).toInt())),
                  ],
                  const SizedBox(height: 12),

                  // ── Professionnel ─────────────────────────────────────────
                  const Divider(),
                  const SizedBox(height: 12),
                  _InfoRow(icon: Icons.person_outlined, text: _proName(), bold: true),
                  if ((_pro?['adress_elevage']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InfoRow(icon: Icons.location_on_outlined,
                        text: _pro!['adress_elevage'].toString()),
                  ],

                  // ── Bouton GPS ────────────────────────────────────────────
                  if (_pro?['lat'] != null && _pro?['lng'] != null) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openNav,
                        icon: const Icon(Icons.navigation_outlined),
                        label: const Text('Calculer l\'itinéraire',
                            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _teal,
                          side: const BorderSide(color: _teal),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Actions (modifier / annuler) ──────────────────────────
                  if (_canModify) ...[
                    const Divider(),
                    const SizedBox(height: 12),
                    eventTile,
                  ] else ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text('Modification impossible — RDV dans moins de 24h.',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Contactez directement le cabinet pour annuler.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                            color: Colors.grey.shade400)),
                  ],
                ]),
              ),
            ),
    );
  }

  String _durationLabel(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60; final m = min % 60;
    return m > 0 ? '${h}h$m' : '${h}h';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool bold;
  const _InfoRow({required this.icon, required this.text, this.bold = false});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: Colors.grey.shade500),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(
          fontFamily: 'Galey',
          fontSize: 14,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          color: const Color(0xFF1E2025),
          height: 1.4))),
    ],
  );
}

// ── DaySheet ─────────────────────────────────────────────────────────────────

class _DaySheet extends StatelessWidget {
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;
  const _DaySheet({required this.day, required this.events, required this.onAdd, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(DateFormat('EEEE d MMMM', 'fr').format(day),
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E2025))),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 8),
        ...events.map((e) => _EventTile(event: e, onRefresh: () { Navigator.pop(context); onRefresh(); })),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Ajouter un événement',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kTeal,
              side: const BorderSide(color: _kTeal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── AddEventSheet ─────────────────────────────────────────────────────────────

class _AddEventSheet extends StatefulWidget {
  final DateTime initialDate;
  final String uid;
  final VoidCallback onSaved;
  const _AddEventSheet({required this.initialDate, required this.uid, required this.onSaved});
  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final _supa   = Supabase.instance.client;
  final _titreCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late String _type;
  late DateTime _dateDebut;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateDebut = widget.initialDate;
    final types = _typesForProfile();
    _type = types.contains('autre') ? 'autre' : types.last;
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateDebut,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('fr'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dateDebut));
    if (time == null || !mounted) return;
    setState(() => _dateDebut = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_titreCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await _supa.from('agenda_events').insert({
        'uid':            widget.uid,
        'titre':          _titreCtrl.text.trim(),
        'type':           _type,
        'date_debut':     _dateDebut.toUtc().toIso8601String(),
        'notes':          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'pro_profile_id': User_Info.activeProfileId,
      });
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Nouvel événement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1E2025))),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 14),

        // Titre
        TextField(
          controller: _titreCtrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Titre *',
            labelStyle: const TextStyle(fontFamily: 'Galey'),
            filled: true, fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),

        // Type chips
        const Text('Type', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _typesForProfile().map((t) {
          final sel = _type == t;
          final col = _kTypeColor[t]!;
          return GestureDetector(
            onTap: () => setState(() => _type = t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? col : col.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${_kTypeIcon[t]} ', style: const TextStyle(fontSize: 13)),
                Text(_kTypeLabel[t]!,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: FontWeight.w600, color: sel ? Colors.white : col)),
              ]),
            ),
          );
        }).toList()),
        const SizedBox(height: 12),

        // Date
        GestureDetector(
          onTap: _pickDateTime,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.event_rounded, color: _kTeal, size: 20),
              const SizedBox(width: 10),
              Text(DateFormat('EEE d MMM yyyy  ·  HH:mm', 'fr').format(_dateDebut),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1E2025))),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Notes
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Notes (optionnel)',
            labelStyle: const TextStyle(fontFamily: 'Galey'),
            filled: true, fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _kTeal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ── Bottom sheet protocole agenda ─────────────────────────────────────────────

class _AgendaProtoSheet extends StatefulWidget {
  final List<Map<String, dynamic>> groupe;
  final String label;
  final String emoji;
  final VoidCallback onDone;
  final Future<void> Function(List<dynamic> ids)? onDelete;
  const _AgendaProtoSheet({
    required this.groupe, required this.label, required this.emoji, required this.onDone,
    this.onDelete,
  });
  @override
  State<_AgendaProtoSheet> createState() => _AgendaProtoSheetState();
}

class _AgendaProtoSheetState extends State<_AgendaProtoSheet> {
  final _supa = Supabase.instance.client;
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.groupe);
  }

  Future<void> _toggle(int idx) async {
    final t         = _items[idx];
    final isDone    = t['statut'] == 'fait';
    final newStatut = isDone ? 'en_attente' : 'fait';
    await _supa.from('plan_taches').update({'statut': newStatut}).eq('id', t['id']);
    setState(() => _items[idx] = {...t, 'statut': newStatut});
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.length;
    final done  = _items.where((t) => t['statut'] == 'fait').length;
    final pct   = total > 0 ? done / total : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(controller: ctrl, padding: EdgeInsets.zero, children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.label,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _kTeal),
                maxLines: 2)),
              Text('$done/$total',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _kTeal)),
              if (widget.onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  tooltip: 'Supprimer ce protocole',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Supprimer le protocole ?',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                        content: Text(widget.label,
                          style: const TextStyle(fontFamily: 'Galey')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler')),
                          TextButton(onPressed: () => Navigator.pop(context, true),
                            child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      final ids = _items.map((t) => t['id']).toList();
                      await widget.onDelete!(ids);
                      if (mounted) Navigator.pop(context); // ignore: use_build_context_synchronously
                    }
                  },
                ),
            ]),
          ),

          // Barre de progression
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              LinearProgressIndicator(
                value: pct,
                backgroundColor: _kTeal.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(done == total ? Colors.grey.shade300 : _kTeal),
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 2),
              Text('${(pct * 100).round()} %',
                style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
            ]),
          ),

          const Divider(height: 24),

          // Liste animaux
          ..._items.asMap().entries.map((e) {
            final idx    = e.key;
            final t      = e.value;
            final isDone = t['statut'] == 'fait';
            final nom    = (t['animal_nom'] as String?)?.isNotEmpty == true
                ? t['animal_nom'] as String
                : 'Animal #${idx + 1}';
            return Dismissible(
              key: Key('pt_${t['id']}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.red.shade50,
                child: Icon(Icons.delete_outline, color: Colors.red.shade400),
              ),
              confirmDismiss: (_) => showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Supprimer ?',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  content: Text(nom, style: const TextStyle(fontFamily: 'Galey')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler')),
                    TextButton(onPressed: () => Navigator.pop(context, true),
                      child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
              onDismissed: (_) async {
                await _supa.from('plan_taches').delete().eq('id', t['id']);
                setState(() => _items.removeAt(idx));
                widget.onDone();
              },
              child: CheckboxListTile(
                value: isDone,
                onChanged: (_) => _toggle(idx),
                activeColor: _kTeal,
                title: Text(nom,
                  style: TextStyle(
                    fontFamily: 'Galey', fontSize: 14,
                    color: isDone ? Colors.grey.shade400 : const Color(0xFF1E2025),
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  )),
                secondary: const Icon(Icons.pets, size: 18, color: _kTeal),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            );
          }),

          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
