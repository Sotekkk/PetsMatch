import 'package:PetsMatch/pages/association/association_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AnnoncesAssoFeedPage extends StatefulWidget {
  const AnnoncesAssoFeedPage({super.key});

  @override
  State<AnnoncesAssoFeedPage> createState() => _AnnoncesAssoFeedPageState();
}

class _AnnoncesAssoFeedPageState extends State<AnnoncesAssoFeedPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  String _espece     = 'tous';
  String _race       = 'toutes';
  String _searchText = '';

  final _searchCtrl = TextEditingController();

  // Likes
  final _likedKeys  = <String>{};
  final _likeCounts = <String, int>{};
  bool _likesLoaded = false;

  static const _especeOptions = [
    ('tous',   'Tous'),
    ('chien',  'Chiens'),
    ('chat',   'Chats'),
    ('lapin',  'Lapins'),
    ('nac',    'NAC'),
    ('oiseau', 'Oiseaux'),
    ('cheval', 'Chevaux'),
    ('autre',  'Autres'),
  ];

  @override
  void initState() {
    super.initState();
    _loadLikes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLikes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _likesLoaded = true); return; }
    try {
      final liked = await Supabase.instance.client
          .from('likes')
          .select('annonce_id')
          .eq('user_uid', uid);
      final counts = await Supabase.instance.client
          .from('likes')
          .select('annonce_id');
      final countMap = <String, int>{};
      for (final row in counts as List) {
        final id = row['annonce_id']?.toString() ?? '';
        if (id.isNotEmpty) countMap[id] = (countMap[id] ?? 0) + 1;
      }
      if (mounted) {
        setState(() {
          _likedKeys.addAll((liked as List).map((r) => r['annonce_id']?.toString() ?? ''));
          _likeCounts.addAll(countMap);
          _likesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _likesLoaded = true);
    }
  }

  Future<void> _toggleLike(String annonceId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final wasLiked = _likedKeys.contains(annonceId);
    setState(() {
      if (wasLiked) {
        _likedKeys.remove(annonceId);
        _likeCounts[annonceId] = (_likeCounts[annonceId] ?? 1) - 1;
      } else {
        _likedKeys.add(annonceId);
        _likeCounts[annonceId] = (_likeCounts[annonceId] ?? 0) + 1;
      }
    });
    try {
      if (wasLiked) {
        await Supabase.instance.client
            .from('likes')
            .delete()
            .eq('annonce_id', annonceId)
            .eq('user_uid', uid);
      } else {
        await Supabase.instance.client
            .from('likes')
            .insert({'annonce_id': annonceId, 'user_uid': uid, 'bebe_index': -1});
      }
    } catch (_) {
      // rollback
      setState(() {
        if (wasLiked) { _likedKeys.add(annonceId); _likeCounts[annonceId] = (_likeCounts[annonceId] ?? 0) + 1; }
        else { _likedKeys.remove(annonceId); _likeCounts[annonceId] = (_likeCounts[annonceId] ?? 1) - 1; }
      });
    }
  }

  bool _matches(Map<String, dynamic> d) {
    if ((d['profil_source'] as String?) != 'association') return false;
    final s = (d['statut'] as String?) ?? '';
    if (s == 'vendu' || s == 'cede' || s == 'expire') return false;
    if (_espece != 'tous' && d['espece'] != _espece) return false;
    if (_race != 'toutes' && (d['race'] as String?) != _race) return false;
    if (_searchText.isNotEmpty) {
      final q     = _searchText.toLowerCase();
      final race  = ((d['race'] as String?) ?? '').toLowerCase();
      final titre = ((d['titre'] as String?) ?? '').toLowerCase();
      final nom   = ((d['nom_eleveur'] as String?) ?? '').toLowerCase();
      if (!race.contains(q) && !titre.contains(q) && !nom.contains(q)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Adoptions associations',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchText = v),
              style: const TextStyle(color: Colors.white, fontFamily: 'Galey'),
              decoration: InputDecoration(
                hintText: 'Rechercher…',
                hintStyle: const TextStyle(color: Colors.white70, fontFamily: 'Galey'),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () { _searchCtrl.clear(); setState(() => _searchText = ''); })
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('annonces')
            .stream(primaryKey: ['id'])
            .eq('statut', 'disponible')
            .order('created_at', ascending: false),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? [];
          final assoc = all.where((d) => d['profil_source'] == 'association').toList();

          // Races disponibles pour filtre dynamique
          final races = {'toutes', ...assoc.map((d) => (d['race'] as String?) ?? '').where((r) => r.isNotEmpty)};

          final filtered = assoc.where(_matches).toList();

          return Column(children: [
            // Filtre espèce
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: _especeOptions.map((e) {
                  final active = _espece == e.$1;
                  return GestureDetector(
                    onTap: () => setState(() { _espece = e.$1; _race = 'toutes'; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active ? _teal : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: active ? _teal : Colors.grey.shade300),
                      ),
                      child: Center(child: Text(e.$2,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                              color: active ? Colors.white : Colors.grey.shade700))),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Filtre race (si espèce sélectionnée avec des races)
            if (races.length > 1)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  children: races.toList().map((r) {
                    final active = _race == r;
                    final label = r == 'toutes' ? 'Toutes races' : r;
                    return GestureDetector(
                      onTap: () => setState(() => _race = r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: active ? _green.withValues(alpha: 0.12) : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: active ? _green : Colors.grey.shade200),
                        ),
                        child: Center(child: Text(label,
                            style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                color: active ? _green : Colors.grey.shade600,
                                fontWeight: active ? FontWeight.w700 : FontWeight.normal))),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Grille
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.favorite_border, size: 60, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Aucune annonce d\'adoption pour le moment',
                            style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                      ]),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.68,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final a = filtered[i];
                        final id = a['id']?.toString() ?? '';
                        return _AdoptionCard(
                          annonce: a,
                          isLiked: _likedKeys.contains(id),
                          likeCount: _likeCounts[id] ?? 0,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => AnnonceDetailPage(annonceId: id))),
                          onLike: () => _toggleLike(id),
                          onAssoProfil: () {
                            final assoUid = a['uid_eleveur']?.toString() ?? '';
                            final assoNom = a['nom_eleveur']?.toString() ?? '';
                            final assoVille = a['ville_eleveur']?.toString() ?? '';
                            if (assoUid.isNotEmpty) {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => AssociationDetailPage(
                                  uid: assoUid, name: assoNom, avatar: '', ville: assoVille,
                                ),
                              ));
                            }
                          },
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _AdoptionCard extends StatelessWidget {
  final Map<String, dynamic> annonce;
  final bool isLiked;
  final int likeCount;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onAssoProfil;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  const _AdoptionCard({
    required this.annonce,
    required this.isLiked,
    required this.likeCount,
    required this.onTap,
    required this.onLike,
    required this.onAssoProfil,
  });

  @override
  Widget build(BuildContext context) {
    final photos  = List<String>.from(annonce['photos'] ?? []);
    final photo   = photos.isNotEmpty ? photos.first : '';
    final titre   = annonce['titre']?.toString() ?? '';
    final race    = annonce['race']?.toString() ?? '';
    final espece  = annonce['espece']?.toString() ?? '';
    final ville   = annonce['ville_eleveur']?.toString() ?? '';
    final nomAsso = annonce['nom_eleveur']?.toString() ?? '';
    final sexe    = annonce['sexe']?.toString() ?? '';
    final createdAt = annonce['created_at']?.toString();
    String age = '';
    if (createdAt != null) {
      try {
        final d = DateTime.parse(createdAt);
        final diff = DateTime.now().difference(d).inDays;
        age = diff == 0 ? 'Aujourd\'hui' : 'Il y a ${diff}j';
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Photo
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(fit: StackFit.expand, children: [
                photo.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder())
                    : _placeholder(),
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(10)),
                    child: const Text('Adoption', style: TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
                if (sexe == 'male' || sexe == 'femelle')
                  Positioned(
                    top: 8, right: 36,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                      child: Icon(
                        sexe == 'male' ? Icons.male : Icons.female,
                        color: sexe == 'male' ? Colors.blue : Colors.pink, size: 14,
                      ),
                    ),
                  ),
                // Bouton like
                Positioned(
                  top: 6, right: 6,
                  child: GestureDetector(
                    onTap: onLike,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? Colors.red : Colors.white, size: 11),
                        if (likeCount > 0) ...[
                          const SizedBox(width: 3),
                          Text('$likeCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Galey')),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          // Infos
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (race.isNotEmpty || espece.isNotEmpty)
                Text(race.isNotEmpty ? race : espece,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              if (nomAsso.isNotEmpty)
                GestureDetector(
                  onTap: onAssoProfil,
                  child: Row(children: [
                    const Icon(Icons.favorite_border, size: 11, color: Color(0xFF0C5C6C)),
                    const SizedBox(width: 3),
                    Expanded(child: Text(nomAsso,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C), decoration: TextDecoration.underline),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              if (ville.isNotEmpty)
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 11, color: Colors.grey),
                  const SizedBox(width: 3),
                  Expanded(child: Text(ville,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFF0F0EC),
    child: const Icon(Icons.favorite_border, color: Color(0xFF0C5C6C), size: 40),
  );
}
