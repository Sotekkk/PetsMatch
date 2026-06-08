import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Widget timeline journalier réutilisable pour tous les agendas pro.
/// Affiche les RDVs comme des blocs proportionnels à leur durée.
class ProDayTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> rdvs;
  final DateTime date;
  final int heureDebut;
  final int heureFin;
  final double pixelsParMinute;
  final Function(Map<String, dynamic>)? onRdvTap;
  final bool showCurrentTimeLine;

  const ProDayTimeline({
    super.key,
    required this.rdvs,
    required this.date,
    this.heureDebut = 8,
    this.heureFin = 19,
    this.pixelsParMinute = 1.5,
    this.onRdvTap,
    this.showCurrentTimeLine = true,
  });

  double get _totalHeight => (heureFin - heureDebut) * 60 * pixelsParMinute;

  double _topFor(int hour, int minute) =>
      ((hour - heureDebut) * 60 + minute) * pixelsParMinute;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final showNowLine = showCurrentTimeLine &&
        isToday &&
        now.hour >= heureDebut &&
        now.hour < heureFin;
    final nowTop = showNowLine ? _topFor(now.hour, now.minute) : 0.0;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Ruler gauche ──────────────────────────────────────────
            SizedBox(
              width: 44,
              height: _totalHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int h = heureDebut; h <= heureFin; h++)
                    Positioned(
                      top: _topFor(h, 0) - 7,
                      right: 4,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            // ── Zone principale ──────────────────────────────────────
            Expanded(
              child: SizedBox(
                height: _totalHeight,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Lignes horaires
                    for (int h = heureDebut; h <= heureFin; h++)
                      Positioned(
                        top: _topFor(h, 0),
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 1,
                          color: Colors.grey.shade200,
                        ),
                      ),
                    // Lignes demi-heure (plus légères)
                    for (int h = heureDebut; h < heureFin; h++)
                      Positioned(
                        top: _topFor(h, 30),
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 0.5,
                          color: Colors.grey.shade100,
                        ),
                      ),
                    // Ligne "maintenant"
                    if (showNowLine) ...[
                      Positioned(
                        top: nowTop,
                        left: 0,
                        right: 0,
                        child: Row(children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red,
                            ),
                          ),
                          Expanded(
                            child: Container(height: 1.5, color: Colors.red),
                          ),
                        ]),
                      ),
                    ],
                    // Blocs RDV
                    ...rdvs.map((rdv) => _RdvBlock(
                      rdv: rdv,
                      heureDebut: heureDebut,
                      heureFin: heureFin,
                      pixelsParMinute: pixelsParMinute,
                      onTap: onRdvTap,
                    )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bloc RDV individuel ──────────────────────────────────────────────────────

class _RdvBlock extends StatelessWidget {
  final Map<String, dynamic> rdv;
  final int heureDebut;
  final int heureFin;
  final double pixelsParMinute;
  final Function(Map<String, dynamic>)? onTap;

  const _RdvBlock({
    required this.rdv,
    required this.heureDebut,
    required this.heureFin,
    required this.pixelsParMinute,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Supporte date_heure (rdv) ET date_debut (agenda_events)
    final dhRaw = rdv['date_heure']?.toString() ?? rdv['date_debut']?.toString() ?? '';
    DateTime? dt;
    try { dt = DateTime.parse(dhRaw).toLocal(); } catch (_) {}
    if (dt == null || dt.hour < heureDebut || dt.hour >= heureFin) {
      return const SizedBox.shrink();
    }

    final duree = (rdv['duree_minutes'] as num?)?.toDouble() ?? 30.0;
    final top = ((dt.hour - heureDebut) * 60 + dt.minute) * pixelsParMinute;
    final maxHeight = (heureFin - heureDebut) * 60 * pixelsParMinute - top;
    final height = (duree * pixelsParMinute).clamp(20.0, maxHeight);
    final statut = rdv['statut']?.toString() ?? 'confirme';
    final isDemande = statut == 'demande';
    final isTermine = statut == 'termine' || statut == 'annule';

    // Couleur : custom hex (agenda_events.couleur) > statut > défaut teal
    Color blockColor;
    Color textColor;
    final customHex = rdv['couleur']?.toString();
    if (isTermine) {
      blockColor = Colors.grey.shade200;
      textColor = Colors.grey.shade500;
    } else if (isDemande) {
      blockColor = Colors.amber.shade50;
      textColor = Colors.amber.shade900;
    } else if (customHex != null && customHex.isNotEmpty) {
      try {
        blockColor = Color(int.parse('FF${customHex.replaceAll('#', '')}', radix: 16));
      } catch (_) { blockColor = const Color(0xFF26A69A); }
      textColor = Colors.white;
    } else {
      blockColor = const Color(0xFF26A69A);
      textColor = Colors.white;
    }

    final animal = rdv['animal'] as Map<String, dynamic>?;
    final client = rdv['client'] as Map<String, dynamic>?;
    final animalNom = animal?['nom']?.toString() ?? rdv['animal_nom']?.toString() ?? '';
    final photo = animal?['photo_url']?.toString() ?? '';
    // Supporte motif (rdv) et titre (agenda_events)
    final motif = rdv['motif']?.toString() ?? rdv['titre']?.toString() ?? '';
    final heure = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final clientNom = _clientName(client);

    return Positioned(
      top: top + 1,
      left: 2,
      right: 2,
      height: height - 2,
      child: GestureDetector(
        onTap: onTap != null ? () => onTap!(rdv) : null,
        child: Container(
          decoration: BoxDecoration(
            color: blockColor,
            borderRadius: BorderRadius.circular(6),
            border: isDemande
                ? Border.all(color: Colors.amber.shade400, width: 1.5)
                : null,
            boxShadow: !isTermine
                ? [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: height < 26
              ? Text(heure,
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (photo.isNotEmpty && height >= 48) ...[
                        CircleAvatar(
                          radius: 9,
                          backgroundImage: CachedNetworkImageProvider(photo),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          animalNom.isNotEmpty ? animalNom : motif,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ),
                      Text(heure,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 10,
                            color: textColor.withValues(alpha: 0.75),
                          )),
                    ]),
                    if (height >= 44 &&
                        (clientNom.isNotEmpty || motif.isNotEmpty))
                      Text(
                        clientNom.isNotEmpty ? clientNom : motif,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 10,
                          color: textColor.withValues(alpha: 0.75),
                        ),
                      ),
                    if (height >= 60 && clientNom.isNotEmpty && motif.isNotEmpty)
                      Text(
                        motif,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  String _clientName(Map<String, dynamic>? c) {
    if (c == null) return '';
    final isElevage = c['isElevage'] == true || c['isPro'] == true;
    final nameElevage = c['name_elevage']?.toString() ?? '';
    final fn = c['firstname']?.toString() ?? '';
    final ln = c['lastname']?.toString() ?? '';
    if (isElevage && nameElevage.isNotEmpty) return nameElevage;
    return '$fn $ln'.trim();
  }
}
