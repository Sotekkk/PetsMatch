import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kTeal = Color(0xFF0C5C6C);

// ── Types ─────────────────────────────────────────────────────────────────────

const _kTypes = ['rdv', 'mise_bas', 'medication', 'visite', 'autre'];

const _kTypeLabel = {
  'rdv':       'RDV',
  'mise_bas':  'Mise-bas',
  'medication':'Médicament',
  'visite':    'Visite',
  'autre':     'Autre',
};

const _kTypeIcon = {
  'rdv':       '🩺',
  'mise_bas':  '🐣',
  'medication':'💊',
  'visite':    '👀',
  'autre':     '📅',
};

const _kTypeColor = {
  'rdv':       Color(0xFF2196F3),
  'mise_bas':  Color(0xFFE91E63),
  'medication':Color(0xFFFF9800),
  'visite':    Color(0xFF4CAF50),
  'autre':     Color(0xFF9E9E9E),
};

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
  const AgendaPage({super.key});
  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _showCalendar = true;
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _load();
  }

  Future<void> _load() async {
    if (_events.isEmpty) setState(() => _loading = true);
    try {
      final from = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1).toUtc();
      final to   = DateTime(_focusedMonth.year, _focusedMonth.month + 2, 0, 23, 59, 59).toUtc();
      final data = await _supa
          .from('agenda_events')
          .select()
          .eq('uid', _uid)
          .gte('date_debut', from.toIso8601String())
          .lte('date_debut', to.toIso8601String())
          .order('date_debut');
      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) => _events.where((e) {
    final d = _parseDate(e['date_debut'] as String);
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }).toList();

  List<Map<String, dynamic>> get _upcoming => _events.where((e) {
    return _parseDate(e['date_debut'] as String).isAfter(DateTime.now().subtract(const Duration(days: 1)));
  }).toList();

  void _prevMonth() { _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1); _load(); }
  void _nextMonth() { _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1); _load(); }

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
        title: const Text('Mon Agenda',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: _showCalendar ? 'Vue liste' : 'Vue calendrier',
            icon: Icon(_showCalendar ? Icons.list_rounded : Icons.calendar_month_rounded),
            onPressed: () => setState(() => _showCalendar = !_showCalendar),
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
          : _showCalendar ? _calendarView() : _listView(),
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
          final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
          final isSelected = _selectedDay != null &&
              day.year == _selectedDay!.year && day.month == _selectedDay!.month && day.day == _selectedDay!.day;

          return GestureDetector(
            onTap: () { setState(() => _selectedDay = day); _showDaySheet(day); },
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
                  if (evts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 2,
                      children: evts.take(3).map((e) => Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white.withValues(alpha: 0.8) : _colorFor(e),
                          shape: BoxShape.circle,
                        ),
                      )).toList(),
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

  @override
  Widget build(BuildContext context) {
    final color  = _colorFor(event);
    final time   = DateFormat('HH:mm').format(_parseDate(event['date_debut'] as String));
    final type   = event['type'] as String? ?? 'autre';

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
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
          onPressed: () async {
            final supa = Supabase.instance.client;
            await supa.from('agenda_events').delete().eq('id', event['id']);
            onRefresh();
          },
        ),
      ),
    );
  }
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
  String _type = 'autre';
  late DateTime _dateDebut;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateDebut = widget.initialDate;
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
        'uid':        widget.uid,
        'titre':      _titreCtrl.text.trim(),
        'type':       _type,
        'date_debut': _dateDebut.toUtc().toIso8601String(),
        'notes':      _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
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
        Wrap(spacing: 6, runSpacing: 6, children: _kTypes.map((t) {
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
