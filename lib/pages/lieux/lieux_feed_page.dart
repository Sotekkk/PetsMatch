import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/lieux/lieu_detail_page.dart';

// ─── Feed plein-écran des lieux pet-friendly ─────────────────────────────────

class LieuxFeedPage extends StatefulWidget {
  const LieuxFeedPage({super.key});

  @override
  State<LieuxFeedPage> createState() => _LieuxFeedPageState();
}

class _LieuxFeedPageState extends State<LieuxFeedPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _pageSize = 15;

  final _supa       = Supabase.instance.client;
  final _pageCtrl   = PageController();
  final _savedKeys  = <String>{};

  List<Map<String, dynamic>> _lieux      = [];
  bool   _loading    = true;
  bool   _loadingMore = false;
  int    _page       = 0;
  bool   _hasMore    = true;
  String _categorie  = 'tous';

  static const _categories = [
    ('tous',            'Tous',             '🗺️'),
    ('restaurant',      'Restaurant',       '🍽️'),
    ('hotel',           'Hébergement',      '🏨'),
    ('cafe',            'Café',             '☕'),
    ('bar',             'Bar',              '🍺'),
    ('gite',            'Gîte',             '🏡'),
    ('camping',         'Camping',          '⛺'),
    ('fast_food',       'Fast food',        '🍔'),
    ('villa_location',  'Location',         '🏖️'),
  ];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _pageCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pageCtrl.removeListener(_onScroll);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_pageCtrl.hasClients) return;
    final page = _pageCtrl.page?.round() ?? 0;
    if (page >= _lieux.length - 4 && _hasMore && !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) setState(() { _loading = true; _page = 0; _hasMore = true; });
    try {
      var q = _supa
          .from('petfriendly_places')
          .select('id, uid_pro, nom, categorie, ville, especes_acceptees, note_moyenne, nb_avis, nb_likes, banniere_url, photo_profil_url, photos, description, statut')
          .eq('statut', 'actif');
      if (_categorie != 'tous') { q = q.eq('categorie', _categorie); }
      final data = await q
          .order('nb_likes', ascending: false)
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(data as List);
      if (mounted) setState(() {
        _lieux   = rows;
        _loading = false;
        _page    = 1;
        _hasMore = rows.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final from = _page * _pageSize;
      var q = _supa
          .from('petfriendly_places')
          .select('id, uid_pro, nom, categorie, ville, especes_acceptees, note_moyenne, nb_avis, nb_likes, banniere_url, photo_profil_url, photos, description, statut')
          .eq('statut', 'actif');
      if (_categorie != 'tous') { q = q.eq('categorie', _categorie); }
      final data = await q
          .order('nb_likes', ascending: false)
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(data as List);
      if (mounted) setState(() {
        _lieux.addAll(rows);
        _page    += 1;
        _hasMore  = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _heroPhoto(Map<String, dynamic> lieu) {
    final banniere = lieu['banniere_url'] as String?;
    if (banniere != null && banniere.isNotEmpty) return banniere;
    final photos = lieu['photos'];
    if (photos is List && photos.isNotEmpty) {
      final first = photos.first?.toString() ?? '';
      if (first.isNotEmpty) return first;
    }
    return (lieu['photo_profil_url'] as String?) ?? '';
  }

  void _toggleSave(String id) {
    setState(() {
      _savedKeys.contains(id) ? _savedKeys.remove(id) : _savedKeys.add(id);
    });
  }

  Future<void> _share(Map<String, dynamic> lieu) async {
    final nom  = lieu['nom'] as String? ?? '';
    final ville = lieu['ville'] as String? ?? '';
    final text = '$nom${ville.isNotEmpty ? ' · $ville' : ''} — Découvrez cet établissement pet-friendly sur PetsMatch !';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Lien copié !', style: TextStyle(fontFamily: 'Galey')),
        duration: Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Feed ────────────────────────────────────────────────────────────
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else if (_lieux.isEmpty)
          Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🏡', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('Aucun établissement pour cette catégorie',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.white)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () { _categorie = 'tous'; _load(reset: true); },
              child: const Text('Voir tous les lieux', style: TextStyle(color: Colors.white54)),
            ),
          ]))
        else
          PageView.builder(
            controller: _pageCtrl,
            scrollDirection: Axis.vertical,
            itemCount: _lieux.length + (_loadingMore ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= _lieux.length) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              final lieu = _lieux[i];
              return _LieuCard(
                lieu:    lieu,
                hero:    _heroPhoto(lieu),
                isSaved: _savedKeys.contains(lieu['id']?.toString() ?? ''),
                onSave:  () => _toggleSave(lieu['id']?.toString() ?? ''),
                onShare: () => _share(lieu),
                onDetail: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => LieuDetailPage(id: lieu['id'] as String))),
                onBack: () => Navigator.pop(context),
              );
            },
          ),

        // ── Filtre catégorie (overlay haut) ─────────────────────────────────
        if (!_loading)
          Positioned(
            top: safe.top + 56,
            left: 0, right: 0,
            child: SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _categories.length,
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final active = _categorie == cat.$1;
                  return GestureDetector(
                    onTap: () {
                      if (_categorie == cat.$1) return;
                      setState(() => _categorie = cat.$1);
                      _load(reset: true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active ? Colors.white : Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(cat.$3, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Text(cat.$2,
                            style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              color: active ? _teal : Colors.white,
                            )),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),

        // ── Bouton retour ────────────────────────────────────────────────────
        Positioned(
          top: safe.top + 8, left: 12,
          child: _CircleBtn(icon: Icons.arrow_back_ios_new, onTap: () => Navigator.pop(context)),
        ),

        // ── Titre ────────────────────────────────────────────────────────────
        Positioned(
          top: safe.top + 12, left: 56,
          child: const Text('Lieux Pet-Friendly',
              style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 17, color: Colors.white,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
        ),
      ]),
    );
  }
}

// ─── Carte plein-écran ────────────────────────────────────────────────────────

class _LieuCard extends StatelessWidget {
  final Map<String, dynamic> lieu;
  final String hero;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onDetail;
  final VoidCallback onBack;

  const _LieuCard({
    required this.lieu, required this.hero,
    required this.isSaved, required this.onSave,
    required this.onShare, required this.onDetail,
    required this.onBack,
  });

  static const _teal = Color(0xFF0C5C6C);

  String _catLabel(String cat) {
    const m = {
      'restaurant': '🍽️ Restaurant',
      'hotel':      '🏨 Hébergement',
      'cafe':       '☕ Café',
      'bar':        '🍺 Bar',
      'gite':       '🏡 Gîte',
      'camping':    '⛺ Camping',
      'fast_food':  '🍔 Fast food',
      'boulangerie':'🥐 Boulangerie',
      'villa_location': '🏖️ Location',
      'hebergement_insolite': '✨ Insolite',
    };
    return m[cat] ?? '🏠 Établissement';
  }

  String _especeEmoji(String e) {
    const m = {
      'chien': '🐕', 'chat': '🐈', 'cheval': '🐴',
      'lapin': '🐇', 'oiseau': '🦜', 'nac': '🦎',
      'ovin': '🐑', 'caprin': '🐐', 'porcin': '🐷',
    };
    return m[e] ?? '🐾';
  }

  @override
  Widget build(BuildContext context) {
    final safe    = MediaQuery.of(context).padding;
    final nom     = lieu['nom'] as String? ?? '';
    final ville   = lieu['ville'] as String? ?? '';
    final cat     = lieu['categorie'] as String? ?? '';
    final note    = (lieu['note_moyenne'] as num?)?.toDouble() ?? 0;
    final nbAvis  = (lieu['nb_avis'] as int?) ?? 0;
    final especes = List<String>.from(lieu['especes_acceptees'] as List? ?? []);
    final desc    = lieu['description'] as String? ?? '';

    return GestureDetector(
      onTap: onDetail,
      child: Stack(children: [

        // ── Image plein écran ──────────────────────────────────────────────
        Positioned.fill(
          child: hero.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: hero,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: const Color(0xFF1A1A2E)),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF0C3040),
                    child: const Center(child: Icon(Icons.storefront, color: Colors.white24, size: 80)),
                  ),
                )
              : Container(
                  color: const Color(0xFF0C3040),
                  child: const Center(child: Icon(Icons.storefront, color: Colors.white24, size: 80)),
                ),
        ),

        // ── Gradient haut ──────────────────────────────────────────────────
        Positioned(top: 0, left: 0, right: 0,
          child: IgnorePointer(child: Container(
            height: 200,
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Colors.transparent],
            )),
          )),
        ),

        // ── Gradient bas ───────────────────────────────────────────────────
        Positioned(bottom: 0, left: 0, right: 0,
          child: IgnorePointer(child: Container(
            height: 380,
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Color(0xEE000000), Colors.transparent],
            )),
          )),
        ),

        // ── Bouton retour (haut gauche) ───────────────────────────────────
        Positioned(
          top: safe.top + 8, left: 12,
          child: _CircleBtn(icon: Icons.arrow_back_ios_new, onTap: onBack),
        ),

        // ── Titre + catégorie filtre (haut centre) ────────────────────────
        Positioned(
          top: safe.top + 12, left: 56,
          child: const Text('Lieux Pet-Friendly',
              style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 17, color: Colors.white,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
        ),

        // ── Actions droite ─────────────────────────────────────────────────
        Positioned(
          right: 12,
          bottom: safe.bottom + 220,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _ActionBtn(
              icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: isSaved ? Colors.amber : Colors.white,
              label: 'Sauvegarder',
              onTap: onSave,
            ),
            const SizedBox(height: 18),
            _ActionBtn(
              icon: Icons.share_outlined,
              color: Colors.white,
              label: 'Partager',
              onTap: onShare,
            ),
            const SizedBox(height: 18),
            _ActionBtn(
              icon: Icons.map_outlined,
              color: Colors.white,
              label: 'Carte',
              onTap: () async {
                final lat = lieu['lat'] as num?;
                final lng = lieu['lng'] as num?;
                if (lat != null && lng != null) {
                  final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ]),
        ),

        // ── Infos bas (glassmorphism) ──────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: GestureDetector(
            onTap: onDetail,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: EdgeInsets.fromLTRB(20, 18, 70, safe.bottom + 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12), width: 0.5)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // Nom
                    Text(nom,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontWeight: FontWeight.w800,
                            fontSize: 22, color: Colors.white),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),

                    // Badges : catégorie + espèces
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (cat.isNotEmpty)
                        _Badge(label: _catLabel(cat),
                            color: _teal.withValues(alpha: 0.85)),
                      ...especes.take(3).map((e) =>
                          _Badge(label: _especeEmoji(e),
                              color: Colors.white.withValues(alpha: 0.16))),
                    ]),
                    const SizedBox(height: 10),

                    // Ville + note
                    Row(children: [
                      if (ville.isNotEmpty) ...[
                        const Icon(Icons.location_on_outlined,
                            color: Colors.white54, size: 14),
                        const SizedBox(width: 4),
                        Text(ville, style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 13, color: Colors.white54)),
                        const SizedBox(width: 12),
                      ],
                      if (nbAvis > 0) ...[
                        const Icon(Icons.star_rounded,
                            color: Colors.amber, size: 14),
                        const SizedBox(width: 3),
                        Text('${note.toStringAsFixed(1)} ($nbAvis avis)',
                            style: const TextStyle(
                                fontFamily: 'Galey', fontSize: 13, color: Colors.white70)),
                      ],
                    ]),

                    // Description
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(desc,
                          style: const TextStyle(
                              fontFamily: 'Galey', fontSize: 13, color: Colors.white60, height: 1.4),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 14),

                    // Bouton
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: onDetail,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: _teal,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Center(child: Text('Voir l\'établissement',
                              style: TextStyle(
                                  fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                  fontSize: 15, color: Colors.white))),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20)),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color,
      required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(
          fontFamily: 'Galey', fontSize: 10, color: Colors.white,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
    ]),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    ),
    child: Text(label, style: const TextStyle(
        fontFamily: 'Galey', fontSize: 12,
        fontWeight: FontWeight.w600, color: Colors.white)),
  );
}
