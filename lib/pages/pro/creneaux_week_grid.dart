import 'package:flutter/material.dart';

/// Une plage groupée (créneaux_pro fusionnés) — même forme que le record
/// retourné par `_ProAgendaPageState._groupedRanges` (pro_agenda.dart),
/// compatible par structure (records Dart).
typedef CreneauRange = ({TimeOfDay start, TimeOfDay end, String statut, String? type, bool domicile});

const _kJoursCourts = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Grille semaine (7 jours × heures) pour "Mes créneaux" — remplace le
/// sélecteur "un jour à la fois" par une vraie vue agenda. Widget purement
/// présentationnel : ne connaît rien de Supabase, reçoit les plages déjà
/// groupées par jour et remonte les intentions (créer/ouvrir une plage) au
/// parent via callbacks — pro_agenda.dart garde toute la logique de données
/// (_applyRange/_deleteRange/_groupedRanges/_loadCreneaux) inchangée.
class CreneauxWeekGrid extends StatelessWidget {
  final List<DateTime> days;
  final Map<String, List<CreneauRange>> rangesByDay; // clé 'yyyy-MM-dd'
  final Map<String, List<Map<String, dynamic>>> rdvsByDay; // clé 'yyyy-MM-dd'
  final void Function(DateTime day, TimeOfDay start, TimeOfDay end) onCreateRange;
  final void Function(DateTime day, CreneauRange range) onTapRange;
  final int startHour;
  final int endHour;
  static const double hourHeight = 56;
  static const double dayColWidth = 104;
  static const double headerHeight = 30;

  const CreneauxWeekGrid({
    super.key,
    required this.days,
    required this.rangesByDay,
    required this.rdvsByDay,
    required this.onCreateRange,
    required this.onTapRange,
    this.startHour = 6,
    this.endHour = 22,
  });

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final totalHeight = (endHour - startHour) * hourHeight;
    final today = DateTime.now();

    return SingleChildScrollView(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Colonne des heures — fixe horizontalement (hors du scroll horizontal
        // des colonnes jour), défile verticalement avec la grille.
        SizedBox(
          width: 34,
          child: Column(children: [
            const SizedBox(height: headerHeight),
            SizedBox(
              height: totalHeight,
              child: Stack(children: [
                for (int h = startHour; h < endHour; h++)
                  Positioned(
                    top: (h - startHour) * hourHeight - 6,
                    right: 4,
                    child: Text('${h}h', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final day in days)
                SizedBox(
                  width: dayColWidth,
                  child: Column(children: [
                    SizedBox(
                      height: headerHeight,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _sameDay(day, today) ? const Color(0xFF0C5C6C) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${_kJoursCourts[day.weekday - 1]} ${day.day}',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700,
                                  color: _sameDay(day, today) ? Colors.white : Colors.black87)),
                        ),
                      ),
                    ),
                    _DayColumn(
                      day: day,
                      hourHeight: hourHeight,
                      startHour: startHour,
                      endHour: endHour,
                      ranges: rangesByDay[dateKey(day)] ?? const [],
                      rdvs: rdvsByDay[dateKey(day)] ?? const [],
                      onCreateRange: (s, e) => onCreateRange(day, s, e),
                      onTapRange: (r) => onTapRange(day, r),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _DayColumn extends StatefulWidget {
  final DateTime day;
  final double hourHeight;
  final int startHour;
  final int endHour;
  final List<CreneauRange> ranges;
  final List<Map<String, dynamic>> rdvs;
  final void Function(TimeOfDay start, TimeOfDay end) onCreateRange;
  final void Function(CreneauRange range) onTapRange;

  const _DayColumn({
    required this.day,
    required this.hourHeight,
    required this.startHour,
    required this.endHour,
    required this.ranges,
    required this.rdvs,
    required this.onCreateRange,
    required this.onTapRange,
  });

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  double? _dragStartY;
  double? _dragCurrentY;

  double get _totalHeight => (widget.endHour - widget.startHour) * widget.hourHeight;

  int _yToMinutes(double y) {
    final minutesFromStart = (y / widget.hourHeight * 60);
    final snapped = (minutesFromStart / 15).round() * 15;
    final total = widget.startHour * 60 + snapped;
    return total.clamp(widget.startHour * 60, widget.endHour * 60);
  }

  ({int start, int end}) get _dragRangeMinutes {
    final a = _yToMinutes(_dragStartY!);
    final b = _yToMinutes(_dragCurrentY!);
    final start = a < b ? a : b;
    final end = (a < b ? b : a);
    return (start: start, end: end <= start ? start + 15 : end);
  }

  bool _overlaps(int startMin, int endMin) {
    for (final r in widget.ranges) {
      final rs = r.start.hour * 60 + r.start.minute;
      final re = r.end.hour * 60 + r.end.minute;
      if (startMin < re && endMin > rs) return true;
    }
    for (final rdv in widget.rdvs) {
      final dh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
      if (dh == null) continue;
      final rs = dh.hour * 60 + dh.minute;
      final re = rs + ((rdv['duree_minutes'] as num?)?.toInt() ?? 60);
      if (startMin < re && endMin > rs) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (d) => setState(() {
        _dragStartY = d.localPosition.dy.clamp(0, _totalHeight);
        _dragCurrentY = _dragStartY;
      }),
      onVerticalDragUpdate: (d) => setState(() {
        _dragCurrentY = d.localPosition.dy.clamp(0, _totalHeight);
      }),
      onVerticalDragEnd: (_) {
        if (_dragStartY != null && _dragCurrentY != null) {
          final range = _dragRangeMinutes;
          if (!_overlaps(range.start, range.end)) {
            widget.onCreateRange(
              TimeOfDay(hour: range.start ~/ 60, minute: range.start % 60),
              TimeOfDay(hour: range.end ~/ 60, minute: range.end % 60),
            );
          }
        }
        setState(() { _dragStartY = null; _dragCurrentY = null; });
      },
      child: Container(
        width: double.infinity,
        height: _totalHeight,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(6)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(children: [
            for (int h = 1; h < widget.endHour - widget.startHour; h++)
              Positioned(top: h * widget.hourHeight, left: 0, right: 0,
                  child: Container(height: 1, color: Colors.grey.shade100)),
            for (final r in widget.ranges) _rangeBlock(r),
            for (final rdv in widget.rdvs) _rdvBlock(rdv),
            if (_dragStartY != null && _dragCurrentY != null) _dragOverlay(),
          ]),
        ),
      ),
    );
  }

  double _minutesToY(int hour, int minute) =>
      ((hour - widget.startHour) * 60 + minute) / 60 * widget.hourHeight;

  Widget _rangeBlock(CreneauRange r) {
    final top = _minutesToY(r.start.hour, r.start.minute);
    final bottom = _minutesToY(r.end.hour, r.end.minute);
    final isDisp = r.statut == 'disponible';
    final color = isDisp ? const Color(0xFF6E9E57) : const Color(0xFFFF9800);
    return Positioned(
      top: top, left: 1, right: 1, height: (bottom - top).clamp(10, double.infinity),
      child: GestureDetector(
        onTap: () => widget.onTapRange(r),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Text(
            '${r.start.hour.toString().padLeft(2, '0')}:${r.start.minute.toString().padLeft(2, '0')}'
            '${r.domicile ? ' 🏠' : ''}${r.type == 'collectif' ? ' 👥' : r.type == 'individuel' ? ' 🎓' : ''}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700,
                color: isDisp ? const Color(0xFF4A7A32) : const Color(0xFFE65100)),
          ),
        ),
      ),
    );
  }

  Widget _rdvBlock(Map<String, dynamic> rdv) {
    final dh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    if (dh == null) return const SizedBox.shrink();
    final duree = (rdv['duree_minutes'] as num?)?.toInt() ?? 60;
    final top = _minutesToY(dh.hour, dh.minute);
    final endDh = dh.add(Duration(minutes: duree));
    final bottom = _minutesToY(endDh.hour, endDh.minute);
    return Positioned(
      top: top, left: 1, right: 1, height: (bottom - top).clamp(10, double.infinity),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: const BoxDecoration(
            color: Color(0x330C5C6C),
            border: Border(left: BorderSide(color: Color(0xFF0C5C6C), width: 3)),
          ),
          child: Text(rdv['motif']?.toString() ?? 'RDV', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
        ),
      ),
    );
  }

  Widget _dragOverlay() {
    final range = _dragRangeMinutes;
    final top = ((range.start - widget.startHour * 60) / 60) * widget.hourHeight;
    final bottom = ((range.end - widget.startHour * 60) / 60) * widget.hourHeight;
    final h1 = range.start ~/ 60, m1 = range.start % 60, h2 = range.end ~/ 60, m2 = range.end % 60;
    return Positioned(
      top: top, left: 1, right: 1, height: (bottom - top).clamp(10, double.infinity),
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C5C6C).withValues(alpha: 0.25),
            border: Border.all(color: const Color(0xFF0C5C6C), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            '${h1.toString().padLeft(2, '0')}:${m1.toString().padLeft(2, '0')}–${h2.toString().padLeft(2, '0')}:${m2.toString().padLeft(2, '0')}',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C)),
          ),
        ),
      ),
    );
  }
}
