import 'package:flutter/material.dart';
import 'morpho_constants.dart';

/// Point posé sur la silhouette (pointage libre, comme
/// anatomie_points_page.dart) — soit déjà enregistré (id renseigné), soit un
/// point en cours de saisie (id vide, avant validation dans la fiche).
class MorphoPoint {
  final String? id;
  final double xPct;
  final double yPct;
  final String categorie;
  final String? note;
  final String? photoUrl;
  const MorphoPoint({this.id, required this.xPct, required this.yPct, required this.categorie, this.note, this.photoUrl});
}

/// Silhouette de profil par espèce, reprise des illustrations dédiées
/// (assets/anatomie/*.png) — pointage libre au tap, avec catégorie par
/// couleur (légende kCategoriesOsteo). Intégrée dans le compte-rendu
/// structuré "Suivi morphologique". Un bouton d'agrandissement (si
/// [enableFullscreen]) ouvre une vue plein écran zoomable pour pointer plus
/// précisément — [refreshPoints] permet à la vue plein écran de relire
/// l'état à jour après chaque ajout/édition (le parent gère la persistance
/// réelle, cette lecture est purement synchrone).
class MorphoSilhouette extends StatelessWidget {
  final String espece; // 'chien' | 'chat' | 'cheval'
  final String vue; // 'profil_g' | 'profil_d'
  final List<MorphoPoint> points;
  final Future<void> Function(double xPct, double yPct)? onTapEmpty;
  final Future<void> Function(MorphoPoint point)? onTapPoint;
  final bool enableFullscreen;
  final List<MorphoPoint> Function()? refreshPoints;
  final ValueChanged<String>? onVueChanged;

  const MorphoSilhouette({
    super.key,
    required this.espece,
    required this.vue,
    this.points = const [],
    this.onTapEmpty,
    this.onTapPoint,
    this.enableFullscreen = true,
    this.refreshPoints,
    this.onVueChanged,
  });

  void _openFullscreen(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MorphoSilhouetteFullscreenPage(
        espece: espece, initialVue: vue, initialPoints: points,
        onTapEmpty: onTapEmpty, onTapPoint: onTapPoint,
        refreshPoints: refreshPoints, onVueChanged: onVueChanged,
      ),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final asset = kMorphoSilhouetteAssets[espece]?[vue] ?? kMorphoSilhouetteAssets['chien']![vue]!;
    return AspectRatio(
      aspectRatio: asset.ratio,
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(children: [
            Positioned.fill(child: Image.asset(asset.path, fit: BoxFit.cover)),
            if (onTapEmpty != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    final box = context.findRenderObject() as RenderBox;
                    final local = box.globalToLocal(details.globalPosition);
                    onTapEmpty!((local.dx / w).clamp(0.0, 1.0), (local.dy / h).clamp(0.0, 1.0));
                  },
                ),
              ),
            for (final p in points)
              Positioned(
                left: p.xPct * w - 11,
                top: p.yPct * h - 11,
                child: GestureDetector(
                  onTap: onTapPoint == null ? null : () => onTapPoint!(p),
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorCategoriePoint(p.categorie),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
                    ),
                  ),
                ),
              ),
            if (enableFullscreen)
              Positioned(
                right: 8, bottom: 8,
                child: GestureDetector(
                  onTap: () => _openFullscreen(context),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

/// Vue plein écran zoomable (pinch-to-zoom / pan) de la silhouette, pour
/// pointer précisément sur de petites zones. Les taps déclenchent les mêmes
/// callbacks que la vue compacte (qui persistent réellement côté parent) ;
/// [refreshPoints], si fourni, permet de relire l'état à jour après chaque
/// interaction pour rafraîchir l'affichage local.
class MorphoSilhouetteFullscreenPage extends StatefulWidget {
  final String espece;
  final String initialVue;
  final List<MorphoPoint> initialPoints;
  final Future<void> Function(double xPct, double yPct)? onTapEmpty;
  final Future<void> Function(MorphoPoint point)? onTapPoint;
  final List<MorphoPoint> Function()? refreshPoints;
  final ValueChanged<String>? onVueChanged;

  const MorphoSilhouetteFullscreenPage({
    super.key,
    required this.espece,
    required this.initialVue,
    required this.initialPoints,
    this.onTapEmpty,
    this.onTapPoint,
    this.refreshPoints,
    this.onVueChanged,
  });

  @override
  State<MorphoSilhouetteFullscreenPage> createState() => _MorphoSilhouetteFullscreenPageState();
}

class _MorphoSilhouetteFullscreenPageState extends State<MorphoSilhouetteFullscreenPage> {
  late String _vue = widget.initialVue;
  late List<MorphoPoint> _points = widget.initialPoints;

  void _refresh() {
    if (widget.refreshPoints != null) setState(() => _points = widget.refreshPoints!());
  }

  void _changeVue(String v) {
    setState(() => _vue = v);
    widget.onVueChanged?.call(v);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final asset = kMorphoSilhouetteAssets[widget.espece]?[_vue] ?? kMorphoSilhouetteAssets['chien']![_vue]!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final v in vuesDisponibles(widget.espece))
              _segButton(v.$2, _vue == v.$1, () => _changeVue(v.$1)),
          ]),
        ),
        Expanded(
          child: InteractiveViewer(
            minScale: 1, maxScale: 5,
            child: Center(
              child: AspectRatio(
                aspectRatio: asset.ratio,
                child: LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(children: [
                    Positioned.fill(child: Image.asset(asset.path, fit: BoxFit.contain)),
                    if (widget.onTapEmpty != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (details) async {
                            final box = context.findRenderObject() as RenderBox;
                            final local = box.globalToLocal(details.globalPosition);
                            await widget.onTapEmpty!((local.dx / w).clamp(0.0, 1.0), (local.dy / h).clamp(0.0, 1.0));
                            _refresh();
                          },
                        ),
                      ),
                    for (final p in _points)
                      Positioned(
                        left: p.xPct * w - 14,
                        top: p.yPct * h - 14,
                        child: GestureDetector(
                          onTap: widget.onTapPoint == null ? null : () async {
                            await widget.onTapPoint!(p);
                            _refresh();
                          },
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorCategoriePoint(p.categorie),
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1))],
                            ),
                          ),
                        ),
                      ),
                  ]);
                }),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: MorphoLegende(dark: true),
        ),
      ]),
    );
  }

  Widget _segButton(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: selected ? kMorphoTeal : Colors.white12, borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      );
}

/// Légende des catégories, sous la silhouette.
class MorphoLegende extends StatelessWidget {
  final bool dark;
  const MorphoLegende({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final labelColor = dark ? Colors.white70 : Colors.grey.shade600;
    return Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, children: [
      for (final c in kCategoriesOsteo)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: c.$3)),
          const SizedBox(width: 4),
          Text(c.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: labelColor)),
        ]),
    ]);
  }
}
