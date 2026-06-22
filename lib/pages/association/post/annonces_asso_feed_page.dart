import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  String _searchText = '';

  final _searchCtrl = TextEditingController();

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

  bool _matches(Map<String, dynamic> d) {
    if ((d['profil_source'] as String?) != 'association') return false;
    if ((d['type_vente'] as String?) != 'adoption') return false;
    final s = (d['statut'] as String?) ?? '';
    if (s == 'vendu' || s == 'cede' || s == 'expire') return false;
    if (_espece != 'tous' && d['espece'] != _espece) return false;
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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      body: Column(children: [
        // Filtre espèce
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: _especeOptions.map((e) {
              final active = _espece == e.$1;
              return GestureDetector(
                onTap: () => setState(() => _espece = e.$1),
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

        // Liste
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('annonces')
                .stream(primaryKey: ['id'])
                .eq('statut', 'disponible')
                .order('created_at', ascending: false),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erreur : ${snap.error}',
                    style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)));
              }
              final all = snap.data ?? [];
              final filtered = all.where(_matches).toList();
              if (filtered.isEmpty) {
                return const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.favorite_border, size: 60, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('Aucune annonce d\'adoption pour le moment',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                  ]),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.72,
                ),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _AdoptionCard(
                  annonce: filtered[i],
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AnnonceDetailPage(annonceId: filtered[i]['id']?.toString() ?? ''))),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _AdoptionCard extends StatelessWidget {
  final Map<String, dynamic> annonce;
  final VoidCallback onTap;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  const _AdoptionCard({required this.annonce, required this.onTap});

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
                // Badge adoption
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
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                      child: Icon(
                        sexe == 'male' ? Icons.male : Icons.female,
                        color: sexe == 'male' ? Colors.blue : Colors.pink,
                        size: 14,
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
                Row(children: [
                  const Icon(Icons.favorite_border, size: 11, color: Color(0xFF0C5C6C)),
                  const SizedBox(width: 3),
                  Expanded(child: Text(nomAsso,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
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
