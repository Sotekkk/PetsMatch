import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/app_nav_drawer.dart';

import 'lieu_detail_page.dart';
import 'inscription_lieu_page.dart';

class LieuxPetFriendlyPage extends StatefulWidget {
  final String? filterCategorie; // 'hebergement' | 'restauration' | null = tous
  const LieuxPetFriendlyPage({super.key, this.filterCategorie});

  @override
  State<LieuxPetFriendlyPage> createState() => _LieuxPetFriendlyPageState();
}

class _LieuxPetFriendlyPageState extends State<LieuxPetFriendlyPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _pageSize = 12;

  final _supabase = Supabase.instance.client;
  final _scroll = ScrollController();

  String _categorie = 'tous'; // 'tous' | 'hebergement' | 'restauration'
  String _espece = 'tous';
  String _sortBy = 'recent'; // 'recent' | 'note' | 'misEnAvant'

  List<Map<String, dynamic>> _lieux = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    if (widget.filterCategorie != null) {
      _categorie = widget.filterCategorie!;
    }
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 0;
        _lieux = [];
        _hasMore = true;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final from = _page * _pageSize;

      // Build base filter
      var base = _supabase
          .from('petfriendly_places')
          .select(
              'id, uid_pro, nom, categorie, sous_categorie, ville, lat, lng, especes_acceptees, horaires, photo_profil_url, banniere_url, photos, note_moyenne, nb_avis, nb_likes, plan, statut')
          .eq('statut', 'actif');

      if (_categorie != 'tous') base = base.eq('categorie', _categorie);
      if (_espece != 'tous')
        base = base.contains('especes_acceptees', [_espece]);

      // Apply sort + pagination (returns PostgrestTransformBuilder — no reassign)
      final data = await (_sortBy == 'note'
              ? base.order('note_moyenne', ascending: false)
              : _sortBy == 'misEnAvant'
                  ? base
                      .order('plan', ascending: false)
                      .order('created_at', ascending: false)
                  : base.order('created_at', ascending: false))
          .range(from, from + _pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(data as List);

      setState(() {
        if (reset) {
          _lieux = rows;
        } else {
          _lieux.addAll(rows);
        }
        _page++;
        _hasMore = rows.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  String _photoUrl(Map<String, dynamic> lieu) {
    final banniere = lieu['banniere_url'] as String?;
    if (banniere != null && banniere.isNotEmpty) return banniere;
    final photos = lieu['photos'] as List?;
    if (photos != null && photos.isNotEmpty) return photos.first as String;
    return lieu['photo_profil_url'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      endDrawer: const AppNavDrawer(),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Lieux Pet-Friendly',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            onSelected: (v) {
              _sortBy = v;
              _load(reset: true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recent', child: Text('Les plus récents')),
              PopupMenuItem(value: 'note', child: Text('Mieux notés')),
              PopupMenuItem(value: 'misEnAvant', child: Text('Mis en avant')),
            ],
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InscriptionLieuPage()),
        ),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Référencer mon établissement',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          _Filters(
            categorie: _categorie,
            espece: _espece,
            onCategorie: (v) {
              _categorie = v;
              _load(reset: true);
            },
            onEspece: (v) {
              _espece = v;
              _load(reset: true);
            },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _teal))
                : _lieux.isEmpty
                    ? _Empty(categorie: _categorie)
                    : RefreshIndicator(
                        color: _teal,
                        onRefresh: () => _load(reset: true),
                        child: GridView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.62,
                          ),
                          itemCount: _lieux.length + (_loadingMore ? 2 : 0),
                          itemBuilder: (ctx, i) {
                            if (i >= _lieux.length) return _SkeletonCard();
                            final lieu = _lieux[i];
                            final id = lieu['id'] as String;
                            return _LieuCard(
                              lieu: lieu,
                              photoUrl: _photoUrl(lieu),
                              isLiked: false,
                              likeCount: 0,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => LieuDetailPage(id: id)),
                              ).then((_) => _load(reset: true)),
                              onLike: () {},
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Filtres chips ───────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  final String categorie;
  final String espece;
  final ValueChanged<String> onCategorie;
  final ValueChanged<String> onEspece;

  const _Filters({
    required this.categorie,
    required this.espece,
    required this.onCategorie,
    required this.onEspece,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _Chip('Tout', 'tous', categorie, onCategorie,
                  Icons.explore_outlined),
              const SizedBox(width: 8),
              _Chip('Hébergements', 'hebergement', categorie, onCategorie,
                  Icons.hotel_outlined),
              const SizedBox(width: 8),
              _Chip('Cafés & Restos', 'restauration', categorie, onCategorie,
                  Icons.restaurant_outlined),
            ]),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _Chip('Toutes espèces', 'tous', espece, onEspece,
                  Icons.pets_outlined),
              const SizedBox(width: 8),
              _Chip('🐶 Chien', 'chien', espece, onEspece, null),
              const SizedBox(width: 8),
              _Chip('🐱 Chat', 'chat', espece, onEspece, null),
              const SizedBox(width: 8),
              _Chip('🐴 Cheval', 'cheval', espece, onEspece, null),
              const SizedBox(width: 8),
              _Chip('🐰 Lapin', 'lapin', espece, onEspece, null),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  final IconData? icon;

  const _Chip(this.label, this.value, this.selected, this.onTap, this.icon);

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    final active = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? teal : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? teal : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: active ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? Colors.white : Colors.grey.shade700,
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Card lieu ───────────────────────────────────────────────────────────────

class _LieuCard extends StatelessWidget {
  final Map<String, dynamic> lieu;
  final String photoUrl;
  final bool isLiked;
  final int likeCount;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _LieuCard({
    required this.lieu,
    required this.photoUrl,
    required this.isLiked,
    required this.likeCount,
    required this.onTap,
    required this.onLike,
  });

  String get _logoUrl => lieu['photo_profil_url'] as String? ?? '';

  String _ouvertLabel(Map<String, dynamic> lieu) {
    final horaires = lieu['horaires'] as Map<String, dynamic>?;
    if (horaires == null || horaires.isEmpty) return '';
    final days = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche'
    ];
    final now = DateTime.now();
    final dayKey = days[now.weekday - 1];
    final val = horaires[dayKey] as String?;
    if (val == null ||
        val.toLowerCase() == 'fermé' ||
        val.toLowerCase() == 'ferme') return '🔴 Fermé';
    final parts = val.split('-');
    if (parts.length < 2) return '';
    try {
      final open = _parseTime(parts[0].trim());
      final close = _parseTime(parts[1].trim());
      final t = now.hour * 60 + now.minute;
      if (t >= open && t < close) return '🟢 Ouvert';
      if (t < open) return '🔴 Fermé';
      return '🔴 Fermé';
    } catch (_) {
      return '';
    }
  }

  int _parseTime(String s) {
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  List<String> _especes(Map<String, dynamic> lieu) {
    final raw = lieu['especes_acceptees'];
    if (raw == null) return [];
    return List<String>.from(raw as List);
  }

  String _especeEmoji(String e) {
    const map = {
      'chien': '🐶',
      'chat': '🐱',
      'cheval': '🐴',
      'lapin': '🐰',
      'oiseau': '🦜',
      'nac': '🐾'
    };
    return map[e.toLowerCase()] ?? '🐾';
  }

  @override
  Widget build(BuildContext context) {
    final note = (lieu['note_moyenne'] as num?)?.toDouble() ?? 0.0;
    final nbAvis = lieu['nb_avis'] as int? ?? 0;
    final ville = lieu['ville'] as String? ?? '';
    final nom = lieu['nom'] as String? ?? '';
    final ouvert = _ouvertLabel(lieu);
    final especes = _especes(lieu);
    final isPremium = lieu['plan'] == 'premium';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo 4:5
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _PlaceholderPhoto(lieu['categorie']),
                        )
                      : _PlaceholderPhoto(lieu['categorie']),
                  // Badge ouvert
                  if (ouvert.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(ouvert,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ),
                    ),
                  // Badge Recommandé
                  if (isPremium)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFA000),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('⭐ Recommandé',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  // Logo circle
                  if (_logoUrl.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4)
                          ],
                        ),
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: _logoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF0C5C6C),
                              child: const Icon(Icons.store_outlined,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Infos
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom,
                        style: const TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF1E2025),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 11, color: Color(0xFF0C5C6C)),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(ville,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (note > 0)
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: Color(0xFFFFA000)),
                          const SizedBox(width: 2),
                          Text(note.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 3),
                          Text('($nbAvis)',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
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

class _PlaceholderPhoto extends StatelessWidget {
  final String? categorie;
  const _PlaceholderPhoto(this.categorie);

  @override
  Widget build(BuildContext context) {
    final isHeb = categorie == 'hebergement';
    return Container(
      color: isHeb ? const Color(0xFFE3F2FD) : const Color(0xFFFFF3E0),
      child: Center(
        child: Icon(
          isHeb ? Icons.hotel_outlined : Icons.restaurant_outlined,
          size: 48,
          color: isHeb ? const Color(0xFF1E88E5) : const Color(0xFFEF6C00),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(color: Colors.grey.shade200),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 12,
                      color: Colors.grey.shade200,
                      width: double.infinity),
                  const SizedBox(height: 6),
                  Container(height: 10, color: Colors.grey.shade100, width: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String categorie;
  const _Empty({required this.categorie});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore_off_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            categorie == 'hebergement'
                ? 'Aucun hébergement pet-friendly\npour le moment'
                : categorie == 'restauration'
                    ? 'Aucun café/restaurant pet-friendly\npour le moment'
                    : 'Aucun lieu pet-friendly\npour le moment',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Galey',
              fontSize: 16,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
