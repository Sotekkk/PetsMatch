// Briques communes des tableaux de bord pro (vétérinaire, ostéopathe…) :
// cartes indicateurs, carte / titre de section, badge de statut, photo
// d'animal, anneau de répartition, barres de la semaine, pastille d'alerte.
// Le contenu reste propre à chaque métier (vet_dashboard.dart,
// sante_dashboard.dart). Miroir site : website/src/components/dashboard/kit.tsx.

import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

const kDashTeal = Color(0xFF0C5C6C);
const kDashInk = Color(0xFF1E2025);
const kDashMuted = Color(0xFF6B7280);
const kDashBorder = Color(0xFFE5E8E6);
const kDashFond = Color(0xFFF6F7F5);

/// Ombre discrète commune aux surfaces blanches de l'accueil.
final kDashOmbre = [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 1))];

/// Marge latérale de l'accueil : 16 sur téléphone, contenu centré (≤ 1000)
/// sur tablette / grand écran.
double dashMargeLaterale(BuildContext context) =>
    math.max(16, (MediaQuery.of(context).size.width - 1000) / 2);

/// Bannière PetsMatch d'origine (fichier existant), entière, hauteur plafonnée.
class DashBanniere extends StatelessWidget {
  const DashBanniere({super.key});

  @override
  Widget build(BuildContext context) {
    final l = MediaQuery.of(context).size.width;
    return Container(
      color: Colors.white,
      height: math.min(l * 793 / 1983, 220),
      width: double.infinity,
      child: Image.asset('assets/Banniere_petsmatch.png', fit: BoxFit.contain),
    );
  }
}

/// Bloc professionnel de l'accueil : avatar rond, nom, lignes d'info, lieu,
/// statut et bouton existant.
class DashEnteteAccueil extends StatelessWidget {
  final String nom;
  final String? photoUrl;
  final VoidCallback? onAvatarTap;
  final List<String> lignes;
  final String? lieu;
  final Widget? statut;
  final Widget? action;
  const DashEnteteAccueil({super.key, required this.nom, this.photoUrl, this.onAvatarTap,
      this.lignes = const [], this.lieu, this.statut, this.action});

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 72, height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: kDashBorder)),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl ?? '').isNotEmpty
          ? CachedNetworkImage(imageUrl: photoUrl!, fit: BoxFit.contain,
              errorWidget: (_, __, ___) => _initiale())
          : _initiale(),
    );
    final large = MediaQuery.of(context).size.width >= 600;
    final infos = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      onAvatarTap != null ? GestureDetector(onTap: onAvatarTap, child: avatar) : avatar,
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(nom, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 19, fontWeight: FontWeight.w700, color: kDashInk, height: 1.2)),
        for (final l in lignes) ...[
          const SizedBox(height: 3),
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted)),
        ],
        if ((lieu ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 15, color: kDashTeal),
            const SizedBox(width: 4),
            Flexible(child: Text(lieu!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFF4B5563)))),
          ]),
        ],
        if (statut != null) ...[const SizedBox(height: 8), statut!],
      ])),
      if (large && action != null) ...[const SizedBox(width: 12), action!],
    ]);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kDashBorder), boxShadow: kDashOmbre),
      child: large || action == null
          ? infos
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              infos,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: action!),
            ]),
    );
  }

  Widget _initiale() => Container(
        color: const Color(0xFFE8F4F6), alignment: Alignment.center,
        child: Text(nom.isNotEmpty ? nom[0].toUpperCase() : '?',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 26, fontWeight: FontWeight.w700, color: kDashTeal)),
      );
}

/// Bouton pilule teal (action existante de l'accueil).
class DashBoutonPilule extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const DashBoutonPilule({super.key, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: kDashTeal, borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24), onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ),
      );
}

/// Pastille de statut (contour fin), avec point optionnel.
class DashPuce extends StatelessWidget {
  final String texte;
  final Color fg, bg;
  final bool point;
  final IconData? icon;
  const DashPuce(this.texte, {super.key, required this.fg, required this.bg, this.point = false, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: fg.withValues(alpha: 0.15))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (point) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(texte, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );
}

/// Carte de synthèse (3 par ligne) : icône dans un cercle teinté, valeur
/// lisible, libellé. Dimensions identiques d'une carte à l'autre.
class DashStat extends StatelessWidget {
  final String valeur;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color teinte;
  const DashStat({super.key, required this.valeur, required this.label, required this.icon, this.onTap, this.teinte = kDashTeal});

  @override
  Widget build(BuildContext context) {
    final nombre = int.tryParse(valeur) != null;
    return Material(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16), onTap: onTap,
        child: Container(
          height: 118,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kDashBorder), boxShadow: kDashOmbre),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: teinte.withValues(alpha: 0.09), shape: BoxShape.circle),
              child: Icon(icon, size: 19, color: teinte),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              child: Center(child: Text(valeur, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Galey', fontSize: nombre ? 22 : 15, fontWeight: FontWeight.w700,
                      color: kDashInk, fontFeatures: const [FontFeature.tabularFigures()]))),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF4B5563))),
          ]),
        ),
      ),
    );
  }
}

/// Palette catégorielle validée daltonisme (ordre fixe, jamais cyclée).
const kDashPalette = <Color>[
  Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A),
  Color(0xFFEDA100), Color(0xFFE87BA4), Color(0xFF008300),
];

class DashCarte extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const DashCarte({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kDashBorder), boxShadow: kDashOmbre),
        child: child,
      );
}

class DashTitre extends StatelessWidget {
  final String texte;
  final IconData? icone;
  final Widget? trailing;
  final int? compteur;
  const DashTitre(this.texte, {super.key, this.icone, this.trailing, this.compteur});

  @override
  Widget build(BuildContext context) => Row(children: [
        if (icone != null) ...[Icon(icone, size: 19, color: kDashTeal), const SizedBox(width: 8)],
        Flexible(child: Text(texte, style: const TextStyle(fontFamily: 'Galey', fontSize: 16,
            fontWeight: FontWeight.w700, color: kDashInk))),
        if (compteur != null && compteur! > 0) ...[
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(minWidth: 18), height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5), alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(9)),
            child: Text('$compteur', style: const TextStyle(color: Colors.white, fontSize: 10.5,
                fontWeight: FontWeight.w700, fontFamily: 'Galey')),
          ),
        ],
        const Spacer(),
        if (trailing != null) trailing!,
      ]);
}

/// Lien texte de fin de titre (« Voir tout », « Voir l'agenda complet »).
class DashLien extends StatelessWidget {
  final String texte;
  final VoidCallback? onTap;
  const DashLien(this.texte, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
        child: Text(texte, style: const TextStyle(fontFamily: 'Galey', color: kDashTeal,
            fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

/// Carte indicateur cliquable ; [teinte] colore la pastille d'icône.
class DashKpi extends StatelessWidget {
  final int valeur;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color teinte;
  final bool actif;
  const DashKpi({super.key, required this.valeur, required this.label, required this.icon,
      required this.onTap, this.teinte = kDashTeal, this.actif = false});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: kDashOmbre,
                border: Border.all(color: actif ? teinte : kDashBorder, width: actif ? 1.5 : 1)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: teinte.withValues(alpha: 0.09), shape: BoxShape.circle),
                child: Icon(icon, size: 19, color: teinte),
              ),
              Text('$valeur', style: const TextStyle(fontFamily: 'Galey', fontSize: 26,
                  fontWeight: FontWeight.w700, color: kDashInk, height: 1.1, fontFeatures: [FontFeature.tabularFigures()])),
              Text(label, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                  fontWeight: FontWeight.w500, color: Color(0xFF4B5563), height: 1.2)),
            ]),
          ),
        ),
      );
}

class DashBadge extends StatelessWidget {
  final String texte;
  final Color fg, bg;
  const DashBadge(this.texte, {super.key, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(texte, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}

class DashPhotoAnimal extends StatelessWidget {
  final String? url;
  final double taille;
  const DashPhotoAnimal({super.key, this.url, this.taille = 38});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(taille / 2),
        child: Container(
          width: taille, height: taille, color: const Color(0xFFE6F2F3),
          child: (url ?? '').isNotEmpty
              ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const Icon(Icons.pets, size: 18, color: kDashTeal))
              : const Icon(Icons.pets, size: 18, color: kDashTeal),
        ),
      );
}

class DashPastille extends StatelessWidget {
  final IconData icon;
  final String texte;
  final Color fg, bg;
  final VoidCallback onTap;
  const DashPastille({super.key, required this.icon, required this.texte, required this.fg, required this.bg, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: bg, borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20), onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(texte, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            ]),
          ),
        ),
      );
}

/// Segment d'anneau : identité = libellé (jamais la couleur seule).
typedef DashSegment = ({String key, String label, Color color, int n});

/// Anneau + légende (libellé, nombre, %). Toucher une ligne met son segment
/// en avant. Écart de 2 px entre segments.
class DashDonut extends StatefulWidget {
  final List<DashSegment> segments;
  final String libelleCentre;
  const DashDonut({super.key, required this.segments, this.libelleCentre = 'RDV'});

  @override
  State<DashDonut> createState() => _DashDonutState();
}

class _DashDonutState extends State<DashDonut> {
  String? _actif;

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments.where((s) => s.n > 0).toList();
    final total = segments.fold<int>(0, (a, s) => a + s.n);
    final actif = segments.where((s) => s.key == _actif).firstOrNull;
    final anneau = SizedBox(
      width: 150, height: 150,
      child: CustomPaint(
        painter: _DonutPainter(segments: segments, total: total, actif: _actif),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${actif?.n ?? total}', style: const TextStyle(fontFamily: 'Galey', fontSize: 24,
                fontWeight: FontWeight.w800, color: kDashInk)),
            Text(actif?.label ?? widget.libelleCentre, textAlign: TextAlign.center, maxLines: 2,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: kDashMuted)),
          ]),
        ),
      ),
    );
    final legende = Column(children: [
      for (final s in segments)
        InkWell(
          onTap: () => setState(() => _actif = _actif == s.key ? null : s.key),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(s.label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashInk,
                  fontWeight: _actif == s.key ? FontWeight.w800 : FontWeight.w500))),
              Text('${s.n}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: kDashInk)),
              SizedBox(width: 48, child: Text('${(s.n * 100 / total).round()} %', textAlign: TextAlign.right,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: kDashMuted))),
            ]),
          ),
        ),
    ]);
    return LayoutBuilder(builder: (context, c) => c.maxWidth >= 420
        ? Row(children: [anneau, const SizedBox(width: 20), Expanded(child: legende)])
        : Column(children: [anneau, const SizedBox(height: 12), legende]));
  }
}

class _DonutPainter extends CustomPainter {
  final List<DashSegment> segments;
  final int total;
  final String? actif;
  _DonutPainter({required this.segments, required this.total, this.actif});

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;
    const epaisseur = 20.0;
    final rect = Rect.fromLTWH(epaisseur / 2 + 3, epaisseur / 2 + 3,
        size.width - epaisseur - 6, size.height - epaisseur - 6);
    final rayon = rect.width / 2;
    final ecart = segments.length > 1 ? 2 / rayon : 0.0;
    var angle = -math.pi / 2;
    for (final s in segments) {
      final balayage = 2 * math.pi * s.n / total;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.key == actif ? epaisseur + 6 : epaisseur
        ..color = actif == null || s.key == actif ? s.color : s.color.withValues(alpha: 0.35);
      canvas.drawArc(rect, angle + ecart / 2, math.max(0.001, balayage - ecart), false, p);
      angle += balayage;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.actif != actif || old.total != total || old.segments != segments;
}

/// Barres par jour (lundi → dimanche), empilées si plusieurs séries
/// ([series][jour]) avec 2 px d'écart. Valeur affichée sur aujourd'hui et
/// sur la barre touchée, jamais sur toutes. Légende si plusieurs séries.
class DashBarresSemaine extends StatefulWidget {
  final List<List<int>> series;
  final List<Color> couleurs;
  final List<String> libelles;
  final int aujourdhui;
  const DashBarresSemaine({super.key, required this.series, required this.couleurs,
      this.libelles = const [], required this.aujourdhui});

  @override
  State<DashBarresSemaine> createState() => _DashBarresSemaineState();
}

class _DashBarresSemaineState extends State<DashBarresSemaine> {
  int? _touche;
  static const _jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  int _total(int jour) => widget.series.fold<int>(0, (a, s) => a + s[jour]);

  @override
  Widget build(BuildContext context) {
    final max = [for (var i = 0; i < 7; i++) _total(i)].fold<int>(0, math.max);
    const hauteur = 110.0;
    final unique = widget.series.length == 1;
    final barres = SizedBox(
      height: hauteur + 40,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _touche = _touche == i ? null : i),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (i == widget.aujourdhui || i == _touche)
                  Text('${_total(i)}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.w700, color: kDashInk)),
                const SizedBox(height: 3),
                if (_total(i) == 0)
                  Container(width: 22, height: 2, color: kDashBorder)
                else
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (var s = widget.series.length - 1; s >= 0; s--)
                        if (widget.series[s][i] > 0) ...[
                          Container(
                            width: 22,
                            height: math.max(2, hauteur * widget.series[s][i] / max),
                            color: unique && !(i == widget.aujourdhui || i == _touche)
                                ? widget.couleurs[s].withValues(alpha: 0.45) : widget.couleurs[s],
                          ),
                          if (s > 0 && widget.series.sublist(0, s).any((x) => x[i] > 0))
                            const SizedBox(height: 2),
                        ],
                    ]),
                  ),
                const SizedBox(height: 6),
                Text(_jours[i], style: TextStyle(fontFamily: 'Galey', fontSize: 11.5,
                    color: i == widget.aujourdhui ? kDashInk : kDashMuted,
                    fontWeight: i == widget.aujourdhui ? FontWeight.w800 : FontWeight.w500)),
              ]),
            ),
          ),
      ]),
    );
    if (unique || widget.libelles.isEmpty) return barres;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      barres,
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (var s = 0; s < widget.series.length; s++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.couleurs[s], borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(widget.libelles[s], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashInk)),
          ]),
      ]),
    ]);
  }
}

/// Liste déroulante sobre (filtres et formulaires), style validé éleveur :
/// fond blanc, bordure fine, libellé au-dessus du champ.
class DashListeDeroulante<T> extends StatelessWidget {
  final String? libelle;
  final T valeur;
  final List<(T, String)> options;
  final ValueChanged<T?>? onChanged;
  const DashListeDeroulante({super.key, this.libelle, required this.valeur, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final existe = options.any((o) => o.$1 == valeur);
    OutlineInputBorder bord(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
    return DropdownButtonFormField<T>(
      key: ValueKey('${libelle}_${options.length}_$valeur'),
      initialValue: existe ? valeur : options.first.$1,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kDashMuted),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14.5, color: kDashInk),
      decoration: InputDecoration(
        labelText: libelle,
        labelStyle: const TextStyle(fontFamily: 'Galey', color: kDashMuted),
        isDense: true, filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: bord(kDashBorder), enabledBorder: bord(kDashBorder), disabledBorder: bord(kDashBorder),
        focusedBorder: bord(kDashTeal, 1.5),
      ),
      items: [for (final o in options) DropdownMenuItem<T>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }
}
