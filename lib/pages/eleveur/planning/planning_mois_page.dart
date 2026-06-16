import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/planning/planning_jour_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_list_page.dart';

// ── Couleurs par type d'acte ──────────────────────────────────────────────────

const _dotColors = <String, Color>{
  'vaccination':     Color(0xFF4CAF50),
  'visite':          Color(0xFF2196F3),
  'traitement':      Color(0xFF0C5C6C),
  'vermifuge':       Color(0xFFFFC107),
  'antiparasitaire': Color(0xFFFF9800),
  'osteopathie':     Color(0xFF9C27B0),
  'ferrage':         Color(0xFF795548),
  'radiographie':    Color(0xFF607D8B),
  'chirurgie':       Color(0xFFF44336),
  'nettoyage':       Color(0xFF00BCD4),
  'promenade':       Color(0xFF673AB7),
  'socialisation':   Color(0xFFFF5722),
};

Color _typeColor(String? type) =>
    _dotColors[type ?? ''] ?? const Color(0xFF9CA3AF);

// ── Page calendrier mensuel ───────────────────────────────────────────────────

class PlanningMoisPage extends StatefulWidget {
  const PlanningMoisPage({super.key});

  @override
  State<PlanningMoisPage> createState() => _PlanningMoisPageState();
}

class _PlanningMoisPageState extends State<PlanningMoisPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg    = Color(0xFFF8F8F6);

  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  // date → list of type_acte for tasks not done
  final Map<String, List<String?>> _tasksByDate = {};
  // dates in the past that have undone tasks (overdue)
  final Set<String> _overdue = {};
  bool _loading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _loadMonth();
  }

  DateTime get _today => DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadMonth() async {
    if (_uid == null) return;
    setState(() => _loading = true);
    try {
      final first = _focusedMonth;
      final last  = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
      final firstStr = _key(first);
      final lastStr  = _key(last);

      final rows = await Supabase.instance.client
          .from('plan_taches')
          .select('date_prevue, type_acte, statut')
          .eq('uid_eleveur', _uid!)
          .gte('date_prevue', firstStr)
          .lte('date_prevue', lastStr)
          .not('statut', 'eq', 'fait');

      final Map<String, List<String?>> byDate = {};
      final Set<String> overdue = {};
      for (final r in rows as List) {
        final ds = (r['date_prevue'] as String? ?? '').split('T').first;
        if (ds.isEmpty) continue;
        byDate.putIfAbsent(ds, () => []).add(r['type_acte'] as String?);
        final d = DateTime.tryParse(ds);
        if (d != null && d.isBefore(_today)) overdue.add(ds);
      }

      if (mounted) {
        setState(() {
          _tasksByDate.clear();
          _tasksByDate.addAll(byDate);
          _overdue.clear();
          _overdue.addAll(overdue);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      _tasksByDate.clear();
    });
    _loadMonth();
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      _tasksByDate.clear();
    });
    _loadMonth();
  }

  void _goToDay(DateTime date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlanningJourPage(initialDate: date),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'fr_FR').format(_focusedMonth);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Planning',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_day_outlined),
            tooltip: 'Vue journalière',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PlanningJourPage())),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_check_outlined),
            tooltip: 'Mes routines',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PlanTemplateListPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Navigateur mois ───────────────────────────────────────────────
          Container(
            color: _teal,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: _prevMonth,
              ),
              Expanded(
                child: Text(
                  monthLabel[0].toUpperCase() + monthLabel.substring(1),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: _nextMonth,
              ),
            ]),
          ),

          // ── Jours de la semaine ───────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: const ['L', 'M', 'M', 'J', 'V', 'S', 'D'].map((d) {
                return Expanded(
                  child: Text(d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6F767B))),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1),

          // ── Grille du mois ────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _teal))
                : _CalendarGrid(
                    focusedMonth: _focusedMonth,
                    today: _today,
                    tasksByDate: _tasksByDate,
                    overdue: _overdue,
                    onDayTap: _goToDay,
                  ),
          ),

          // ── Légende ───────────────────────────────────────────────────────
          _Legend(),
        ],
      ),
    );
  }
}

// ── Grille calendrier ─────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime today;
  final Map<String, List<String?>> tasksByDate;
  final Set<String> overdue;
  final ValueChanged<DateTime> onDayTap;

  const _CalendarGrid({
    required this.focusedMonth,
    required this.today,
    required this.tasksByDate,
    required this.overdue,
    required this.onDayTap,
  });

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    // weekday: 1=Mon … 7=Sun → offset = weekday - 1
    final startOffset = (firstOfMonth.weekday - 1) % 7;
    final daysInMonth =
        DateUtils.getDaysInMonth(focusedMonth.year, focusedMonth.month);
    final totalCells = (startOffset + daysInMonth + 6) ~/ 7 * 7;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 0.85,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: totalCells,
        itemBuilder: (_, i) {
          final dayNum = i - startOffset + 1;
          if (dayNum < 1 || dayNum > daysInMonth) {
            return const SizedBox.shrink();
          }
          final date  = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
          final key   = _key(date);
          final types = tasksByDate[key] ?? [];
          final isOverdue = overdue.contains(key);
          final isToday   = DateUtils.isSameDay(date, today);

          return _DayCell(
            day: dayNum,
            types: types,
            isToday: isToday,
            isOverdue: isOverdue,
            onTap: () => onDayTap(date),
          );
        },
      ),
    );
  }
}

// ── Cellule jour ──────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final int day;
  final List<String?> types;
  final bool isToday;
  final bool isOverdue;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.types,
    required this.isToday,
    required this.isOverdue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Déduplique et garde max 3 types distincts pour les points
    final unique = <String?, bool>{};
    for (final t in types) {
      if (unique.length >= 3) break;
      unique[t] = true;
    }
    final dotTypes = unique.keys.toList();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: isToday
              ? const Color(0xFF0C5C6C)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: isOverdue && !isToday
              ? Border.all(color: Colors.red.shade300, width: 1.5)
              : isToday
                  ? null
                  : Border.all(color: const Color(0xFFE8E8E4), width: 0.8),
          boxShadow: isToday
              ? [const BoxShadow(
                  color: Color(0x330C5C6C), blurRadius: 6, offset: Offset(0, 2))]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Numéro du jour
            Text(
              '$day',
              style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 14,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: isToday
                    ? Colors.white
                    : const Color(0xFF1F2A2E),
              ),
            ),
            // Points de couleur
            if (types.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isOverdue && !isToday)
                    _dot(Colors.red)
                  else
                    ...dotTypes.map((t) => _dot(_typeColor(t))),
                  // Badge "+" si plus de 3 types
                  if (types.length > 3 && !isOverdue)
                    _plusBadge(types.length - 3, isToday),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.symmetric(horizontal: 1.5),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _plusBadge(int extra, bool onTeal) => Container(
    margin: const EdgeInsets.only(left: 2),
    child: Text('+$extra',
        style: TextStyle(
            fontFamily: 'Galey',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: onTeal ? Colors.white70 : const Color(0xFF9CA3AF))),
  );
}

// ── Légende ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          _legendItem(Colors.red, 'En retard'),
          _legendItem(const Color(0xFF0C5C6C), 'Aujourd\'hui'),
          ..._dotColors.entries.take(6).map((e) =>
              _legendItem(e.value, _labelFor(e.key))),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(
              fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B))),
    ],
  );

  String _labelFor(String type) => switch (type) {
    'vaccination'     => 'Vaccination',
    'visite'          => 'Visite vét.',
    'traitement'      => 'Traitement',
    'vermifuge'       => 'Vermifuge',
    'antiparasitaire' => 'Antiparasit.',
    'osteopathie'     => 'Ostéo.',
    'ferrage'         => 'Ferrage',
    'radiographie'    => 'Radio.',
    'chirurgie'       => 'Chirurgie',
    'nettoyage'       => 'Nettoyage',
    'promenade'       => 'Promenade',
    'socialisation'   => 'Socialisation',
    _                 => type,
  };
}
