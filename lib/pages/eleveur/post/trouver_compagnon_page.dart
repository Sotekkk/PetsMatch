import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart' show speciesIcon, speciesLabel;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_map_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrouverCompagnonPage extends StatefulWidget {
  const TrouverCompagnonPage({super.key});

  @override
  State<TrouverCompagnonPage> createState() => _TrouverCompagnonPageState();
}

class _TrouverCompagnonPageState extends State<TrouverCompagnonPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  List<Map<String, dynamic>> _annonces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('annonces')
          .select('id, titre, espece, race, photos, prix, saillie_prix, prix_min_portee, prix_max_portee, type, type_vente, ville_eleveur')
          .eq('statut', 'disponible')
          .or('profil_source.is.null,profil_source.neq.association')
          .order('created_at', ascending: false)
          .limit(8);
      if (mounted) {
        setState(() {
          _annonces = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: const Text('Trouver un compagnon',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Colors.white)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0C5C6C), Color(0xFF5F9EAA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Mode de découverte ───────────────────────────────────
                const _SectionTitle('Mode de découverte'),
                const SizedBox(height: 12),
                _ModeCard(
                  icon: Icons.play_circle_filled_rounded,
                  color: _green,
                  title: 'Fil d\'actualité',
                  subtitle: 'Swipez et découvrez les annonces en plein écran',
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const AnnoncesFeedPage())),
                ),
                const SizedBox(height: 10),
                _ModeCard(
                  icon: Icons.search_rounded,
                  color: _teal,
                  title: 'Recherche',
                  subtitle: 'Filtrez par espèce, race, région…',
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const AnnoncesPublicPage())),
                ),

                const SizedBox(height: 20),
                _MapPreviewCard(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const AnnoncesMapPage())),
                ),

                const SizedBox(height: 28),

                // ── Dernières annonces ───────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionTitle('Dernières annonces'),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnnoncesPublicPage())),
                      child: Text('Voir tout',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_loading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
                  ))
                else if (_annonces.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(child: Text('Aucune annonce disponible',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                            color: Colors.grey.shade500))),
                  )
                else
                  SizedBox(
                    height: 230,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _annonces.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => _AnnonceMiniCard(
                        annonce: _annonces[i],
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AnnonceDetailPage(
                            annonceId: _annonces[i]['id'] as String,
                            initialData: _annonces[i],
                          ),
                        )),
                      ),
                    ),
                  ),

                // ── Saillies ─────────────────────────────────────────────
                const SizedBox(height: 28),
                if (User_Info.isElevage) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _SectionTitle('Saillies disponibles'),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const AnnoncesPublicPage(typeFilter: 'saillie'))),
                        child: Text('Voir tout',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                color: const Color(0xFF8B5CF6))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SaillieShortcut(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const AnnoncesPublicPage(typeFilter: 'saillie'))),
                  ),
                ] else ...[
                  const _SectionTitle('Saillies'),
                  const SizedBox(height: 10),
                  _SaillieLocked(),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte mode principale (pleine largeur) ────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ModeCard({
    required this.icon, required this.color, required this.title,
    required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 16,
                    color: Color(0xFF1F2A2E))),
            const SizedBox(height: 3),
            Text(subtitle,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: Color(0xFF6F767B))),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 22),
        ]),
      ),
    );
  }
}


// ── Aperçu carte ──────────────────────────────────────────────────────────────

class _MapPreviewCard extends StatelessWidget {
  final VoidCallback onTap;
  const _MapPreviewCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            // Fond carte stylisé
            Container(color: const Color(0xFFE8F4F0)),
            CustomPaint(painter: _MapGridPainter()),
            // Overlay gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF0C5C6C).withValues(alpha: 0.85),
                    const Color(0xFF16A34A).withValues(alpha: 0.60),
                  ],
                ),
              ),
            ),
            // Contenu
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Explorer la carte',
                          style: TextStyle(fontFamily: 'Galey',
                              fontWeight: FontWeight.w700, fontSize: 17,
                              color: Colors.white)),
                      const SizedBox(height: 5),
                      Text('Éleveurs et annonces géolocalisés',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.map_rounded, size: 14, color: Color(0xFF0C5C6C)),
                          SizedBox(width: 5),
                          Text('Ouvrir la carte',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                  fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
                        ]),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.location_on_rounded,
                    color: Colors.white, size: 52),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF16A34A).withValues(alpha: 0.12)
      ..strokeWidth = 1;
    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Quelques "routes" stylisées
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height * 0.4),
        Offset(size.width, size.height * 0.55), roadPaint);
    canvas.drawLine(Offset(size.width * 0.3, 0),
        Offset(size.width * 0.45, size.height), roadPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Mini card annonce horizontale ─────────────────────────────────────────────

class _AnnonceMiniCard extends StatelessWidget {
  final Map<String, dynamic> annonce;
  final VoidCallback onTap;
  const _AnnonceMiniCard({required this.annonce, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final photos   = List<String>.from(annonce['photos'] ?? []);
    final espece   = (annonce['espece'] as String?) ?? '';
    final race     = (annonce['race'] as String?) ?? '';
    final titre    = (annonce['titre'] as String?) ?? '';
    final typeVente   = (annonce['type_vente'] as String?) ?? 'vente';
    final type        = (annonce['type'] as String?) ?? 'animal';
    final prix        = (annonce['prix'] as num?)?.toDouble();
    final sailliePrix = (annonce['saillie_prix'] as num?)?.toDouble();
    final prixMin     = (annonce['prix_min_portee'] as num?)?.toDouble();
    final ville       = (annonce['ville_eleveur'] as String?) ?? '';
    final isSaillie   = typeVente == 'saillie';
    final isRetraite  = typeVente == 'retraite';
    final display     = titre.isNotEmpty ? titre : (race.isNotEmpty ? race : speciesLabel(espece));

    String prixLabel = '';
    Color  prixColor = const Color(0xFF0C5C6C);
    if (type == 'portee' && prixMin != null) {
      prixLabel = 'dès ${prixMin.toInt()} €';
    } else if (isSaillie) {
      prixLabel = sailliePrix != null && sailliePrix > 0
          ? '💜 ${sailliePrix.toInt()} €' : '💜 Saillie';
      prixColor = const Color(0xFF7C3AED);
    } else if (isRetraite) {
      prixLabel = prix != null && prix > 0 ? '${prix.toInt()} €' : '🏅 Retraité';
    } else if (prix != null && prix > 0) {
      prixLabel = '${prix.toInt()} €';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                photos.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover,
                        placeholder: (_, __) => _placeholder(espece),
                        errorWidget: (_, __, ___) => _placeholder(espece))
                    : _placeholder(espece),
                Positioned(
                  top: 5, left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSaillie ? const Color(0xFF8B5CF6)
                          : isRetraite ? const Color(0xFFB45309)
                          : const Color(0xFF6E9E57),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(isSaillie ? 'Saillie' : isRetraite ? 'Retraité' : 'Compagnon',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 9,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(display,
                  style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, fontSize: 12,
                      color: Color(0xFF1F2A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (prixLabel.isNotEmpty)
                Text(prixLabel,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        fontWeight: FontWeight.w800, color: prixColor)),
              if (ville.isNotEmpty)
                Text('📍 $ville',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 10,
                        color: Color(0xFF9CA3AF)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(String espece) => Container(
    color: const Color(0xFFEEF5EA),
    child: Center(child: speciesIcon(espece, 32, const Color(0xFF6E9E57).withValues(alpha: 0.35))),
  );
}

// ── Raccourci saillies ────────────────────────────────────────────────────────

class _SaillieShortcut extends StatelessWidget {
  final VoidCallback onTap;
  const _SaillieShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF3E8FF), Color(0xFFEDE9FE)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDDD6FE)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.diversity_1_outlined,
                color: Color(0xFF8B5CF6), size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Trouver une saillie',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 14, color: Color(0xFF6D28D9))),
            SizedBox(height: 2),
            Text('Accouplement pour votre animal',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: Color(0xFF7C3AED))),
          ])),
          const Icon(Icons.chevron_right, color: Color(0xFF8B5CF6)),
        ]),
      ),
    );
  }
}

// ── Saillie réservée aux éleveurs ────────────────────────────────────────────
class _SaillieLocked extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.lock_outline, color: Colors.grey, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Réservé aux éleveurs professionnels',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 3),
          Text('La reproduction par des particuliers n\'est pas conforme à notre règlement.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        ])),
      ]),
    );
  }
}

// ── Titre de section ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: Color(0xFF1F2A2E)));
}
