import 'package:flutter/material.dart';

/// Grille semaine (7 colonnes jour × heures) pour visualiser les événements
/// d'un agenda — pendant Google Agenda de la vue Jour existante
/// (ProDayTimeline), jusqu'ici réservée aux plages de disponibilité pro
/// (CreneauxWeekGrid). Widget purement présentationnel, réutilisable par
/// tout agenda (agenda_page.dart, pro_agenda.dart…) : ne connaît rien de
/// Supabase, reçoit les événements déjà résolus par jour.
class WeekEventsGrid extends StatelessWidget {
  final List<DateTime> days; // 7 jours, lundi → dimanche
  final DateTime? selectedDay;
  final List<Map<String, dynamic>> Function(DateTime day) eventsForDay;
  final Color Function(Map<String, dynamic> event) colorFor;
  final void Function(DateTime day) onDayHeaderTap;
  final void Function(Map<String, dynamic> event) onEventTap;
  final int heureDebut;
  final int heureFin;
  final double pixelsParMinute;
  static const double dayColWidth = 108;
  static const double headerHeight = 44;
  static const _dayAbbr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  const WeekEventsGrid({
    super.key,
    required this.days,
    required this.eventsForDay,
    required this.colorFor,
    required this.onDayHeaderTap,
    required this.onEventTap,
    this.selectedDay,
    this.heureDebut = 7,
    this.heureFin = 21,
    this.pixelsParMinute = 1.1,
  });

  double get _totalHeight => (heureFin - heureDebut) * 60 * pixelsParMinute;
  double _topFor(int hour, int minute) =>
      ((hour - heureDebut) * 60 + minute) * pixelsParMinute;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Ruler des heures — fixe horizontalement, partagée par tous les jours.
          SizedBox(
            width: 36,
            child: Column(children: [
              const SizedBox(height: headerHeight),
              SizedBox(
                height: _totalHeight,
                child: Stack(clipBehavior: Clip.none, children: [
                  for (int h = heureDebut; h <= heureFin; h++)
                    Positioned(
                      top: _topFor(h, 0) - 7,
                      right: 4,
                      child: Text('${h.toString().padLeft(2, '0')}h',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (int i = 0; i < days.length; i++)
                  _dayColumn(days[i], _dayAbbr[days[i].weekday - 1], now),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dayColumn(DateTime day, String abbr, DateTime now) {
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    final isSelected = selectedDay != null &&
        day.year == selectedDay!.year && day.month == selectedDay!.month && day.day == selectedDay!.day;
    final evts = eventsForDay(day)
      ..sort((a, b) {
        final da = _dateOf(a) ?? DateTime(0);
        final db = _dateOf(b) ?? DateTime(0);
        return da.compareTo(db);
      });

    return SizedBox(
      width: dayColWidth,
      child: Column(children: [
        GestureDetector(
          onTap: () => onDayHeaderTap(day),
          child: Container(
            height: headerHeight - 6,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF0C5C6C) : isToday ? const Color(0xFF0C5C6C).withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(abbr, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white70 : Colors.grey)),
              Text('${day.day}', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF1E2025))),
            ]),
          ),
        ),
        Container(
          width: dayColWidth - 4,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade100),
            borderRadius: BorderRadius.circular(6),
          ),
          height: _totalHeight,
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            for (int h = heureDebut; h <= heureFin; h++)
              Positioned(top: _topFor(h, 0), left: 0, right: 0,
                  child: Container(height: 1, color: Colors.grey.shade100)),
            if (isToday && now.hour >= heureDebut && now.hour < heureFin)
              Positioned(
                top: _topFor(now.hour, now.minute),
                left: 0, right: 0,
                child: Container(height: 1.5, color: Colors.red),
              ),
            for (final e in evts)
              _WeekEventBlock(
                event: e,
                heureDebut: heureDebut,
                heureFin: heureFin,
                pixelsParMinute: pixelsParMinute,
                totalHeight: _totalHeight,
                color: colorFor(e),
                onTap: () => onEventTap(e),
              ),
          ]),
        ),
      ]),
    );
  }

  static DateTime? _dateOf(Map<String, dynamic> e) {
    final raw = e['date_heure']?.toString() ?? e['date_debut']?.toString() ?? '';
    try { return DateTime.parse(raw).toLocal(); } catch (_) { return null; }
  }
}

class _WeekEventBlock extends StatelessWidget {
  final Map<String, dynamic> event;
  final int heureDebut;
  final int heureFin;
  final double pixelsParMinute;
  final double totalHeight;
  final Color color;
  final VoidCallback onTap;

  const _WeekEventBlock({
    required this.event,
    required this.heureDebut,
    required this.heureFin,
    required this.pixelsParMinute,
    required this.totalHeight,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dt = WeekEventsGrid._dateOf(event);
    if (dt == null) return const SizedBox.shrink();

    final duree = (event['duree_minutes'] as num?)?.toDouble() ?? 30.0;
    final rawTop = ((dt.hour - heureDebut) * 60 + dt.minute) * pixelsParMinute;
    final top = rawTop.clamp(0.0, totalHeight - 16.0);
    final height = (duree * pixelsParMinute).clamp(16.0, totalHeight - top);
    final statut = event['statut']?.toString() ?? 'confirme';
    final isTermine = statut == 'termine' || statut == 'annule';

    final titre = (event['titre'] ?? event['motif'] ?? event['animal_nom'] ?? '').toString();
    final heure = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Positioned(
      top: top + 1,
      left: 2,
      right: 2,
      height: height - 2,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isTermine ? Colors.grey.shade200 : color,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: height < 28
              ? Text(heure, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 8.5, fontWeight: FontWeight.w700,
                      color: isTermine ? Colors.grey.shade500 : Colors.white))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(titre, maxLines: height >= 42 ? 2 : 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700,
                          color: isTermine ? Colors.grey.shade500 : Colors.white)),
                  Text(heure, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 8,
                          color: isTermine ? Colors.grey.shade400 : Colors.white70)),
                ]),
        ),
      ),
    );
  }
}
