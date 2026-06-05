import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';

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
  const AgendaPage({super.key});
  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _events = [];
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

  // ── Day view ───────────────────────────────────────────────────────────────

  Widget _dayView() {
    final day = _selectedDay ?? DateTime.now();
    final evts = _eventsForDay(day);

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
            child: Text(
              DateFormat('EEEE d MMMM', 'fr').format(day),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 15, color: Color(0xFF1E2025)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: _kTeal),
            onPressed: () => setState(() => _selectedDay = day.add(const Duration(days: 1))),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _kTeal,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: 16, // 7h → 22h
            itemBuilder: (_, i) {
              final hour = 7 + i;
              final hLabel = '${hour.toString().padLeft(2, "0")}:00';
              // Événements qui démarrent dans cette heure
              final startingHere = evts.where((e) {
                final s = _parseDate(e['date_debut'] as String);
                return s.hour == hour;
              }).toList();

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Colonne heure
                  SizedBox(
                    width: 56,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8, top: 10),
                      child: Text(hLabel,
                          textAlign: TextAlign.right,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  // Ligne verticale
                  Container(width: 1, color: const Color(0xFFEEEEEE)),
                  const SizedBox(width: 8),
                  // Événements ou slot vide
                  Expanded(
                    child: startingHere.isEmpty
                        ? GestureDetector(
                            onTap: () => _showAddSheet(
                                initialDate: DateTime(day.year, day.month, day.day, hour)),
                            child: Container(
                              height: 52,
                              margin: const EdgeInsets.only(right: 12, bottom: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                        : Column(
                            children: startingHere.map((e) => Padding(
                              padding: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
                              child: _EventTile(event: e, onRefresh: _load),
                            )).toList(),
                          ),
                  ),
                ],
              );
            },
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

    // Charger le pro_uid depuis le rdv
    final rdvRows = await supa.from('rdv').select('pro_uid').eq('id', rdvId);
    if (rdvRows.isEmpty || !context.mounted) return;
    final proUid = rdvRows[0]['pro_uid'] as String;

    // Charger les créneaux disponibles de la pension
    final today  = DateTime.now().toIso8601String().substring(0, 10);
    final future = DateTime.now().add(const Duration(days: 90)).toIso8601String().substring(0, 10);
    final slotsData = await supa
        .from('creneaux_pro')
        .select('date, heure_debut')
        .eq('pro_uid', proUid)
        .eq('statut', 'disponible')
        .gte('date', today)
        .lte('date', future)
        .order('date', ascending: true)
        .order('heure_debut', ascending: true);

    if (!context.mounted) return;

    // Grouper par date
    final Map<String, List<int>> slotsByDate = {};
    for (final s in slotsData) {
      final date = s['date'] as String;
      final hour = int.tryParse((s['heure_debut'] as String).split(':').first) ?? 0;
      slotsByDate.putIfAbsent(date, () => []).add(hour);
    }

    DateTime? chosen;

    if (slotsByDate.isEmpty) {
      // Fallback: free date+time picker when pension has no creneaux configured
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        locale: const Locale('fr'),
      );
      if (pickedDate == null || !context.mounted) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 10, minute: 0),
      );
      if (pickedTime == null || !context.mounted) return;
      chosen = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
          pickedTime.hour, pickedTime.minute);
    } else {
    final dates = slotsByDate.keys.toList()..sort((a, b) => a.compareTo(b));
    String selDate = dates.first;
    int? selHour;

    chosen = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const Text('Modifier le rendez-vous',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Choisissez parmi les créneaux disponibles.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            const Text('Date', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: dates.map((d) {
                  final dt = DateTime.parse(d);
                  final label = DateFormat('EEE d MMM', 'fr').format(dt);
                  final sel = d == selDate;
                  return GestureDetector(
                    onTap: () => setModal(() { selDate = d; selHour = null; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? _kTeal : Colors.white,
                        border: Border.all(color: sel ? _kTeal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(label, style: TextStyle(
                          fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : const Color(0xFF1E2025))),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Heure', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: (slotsByDate[selDate] ?? []).map((h) {
                final sel = h == selHour;
                return GestureDetector(
                  onTap: () => setModal(() => selHour = h),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? _kTeal : Colors.white,
                      border: Border.all(color: sel ? _kTeal : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${h.toString().padLeft(2, "0")}h00',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : const Color(0xFF1E2025))),
                  ),
                );
              }).toList(),
            ),
            if (selHour != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final dt = DateTime.parse(selDate);
                    Navigator.pop(ctx, DateTime(dt.year, dt.month, dt.day, selHour!));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Proposer ce créneau',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
    } // end else (slots available)

    if (chosen == null || !context.mounted) return;

    try {
      await supa.from('rdv').update({
        'statut': 'contre_proposition',
        'date_heure': chosen.toUtc().toIso8601String(),
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
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
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
