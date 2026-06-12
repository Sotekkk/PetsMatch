import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MesAnimauxAssoPage extends StatefulWidget {
  const MesAnimauxAssoPage({super.key});
  @override
  State<MesAnimauxAssoPage> createState() => _MesAnimauxAssoPageState();
}

class _MesAnimauxAssoPageState extends State<MesAnimauxAssoPage> {
  final _supa = Supabase.instance.client;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _animaux = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _filterStatut = 'tous';
  String _search = '';

  static const _statuts = [
    ('tous', 'Tous', Colors.grey),
    ('en_soin', 'En soin', Colors.orange),
    ('disponible', 'Disponible', Color(0xFF6E9E57)),
    ('en_fa', 'En FA', Colors.purple),
    ('adopte', 'Adopté', Color(0xFF0C5C6C)),
    ('transfere', 'Transféré', Colors.blue),
    ('decede', 'Décédé', Colors.red),
  ];

  static Map<String, Color> get statutColors => {
    for (final s in _statuts) s.$1: s.$3,
  };

  static Map<String, String> get statutLabels => {
    for (final s in _statuts) s.$1: s.$2,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final data = await _supa
          .from('animaux')
          .select('id,nom,espece,race,sexe,statut,date_naissance,photo_url,date_entree')
          .eq('uid_eleveur', uid)
          .order('nom');
      if (mounted) {
        setState(() {
          _animaux = List<Map<String, dynamic>>.from(data as List);
          _applyFilters();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    _filtered = _animaux.where((a) {
      final matchStatut = _filterStatut == 'tous' || a['statut'] == _filterStatut;
      final matchSearch = _search.isEmpty ||
          (a['nom']?.toString().toLowerCase().contains(_search.toLowerCase()) ?? false) ||
          (a['espece']?.toString().toLowerCase().contains(_search.toLowerCase()) ?? false) ||
          (a['race']?.toString().toLowerCase().contains(_search.toLowerCase()) ?? false);
      return matchStatut && matchSearch;
    }).toList();
  }

  String _age(dynamic dateNaissance) {
    if (dateNaissance == null) return '';
    try {
      final dn = DateTime.parse(dateNaissance.toString());
      final diff = DateTime.now().difference(dn);
      final mois = (diff.inDays / 30).floor();
      if (mois < 12) return '${mois}m';
      return '${(mois / 12).floor()}a';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Mes Animaux',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => const AnimalFichePage(isAssociation: true),
              ));
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() { _search = v; _applyFilters(); }),
              decoration: InputDecoration(
                hintText: 'Rechercher un animal…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Filtres statut
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _statuts.map((s) {
                final active = _filterStatut == s.$1;
                return GestureDetector(
                  onTap: () => setState(() { _filterStatut = s.$1; _applyFilters(); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: active ? s.$3 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? s.$3 : Colors.grey.shade300),
                    ),
                    child: Center(
                      child: Text(s.$2,
                          style: TextStyle(
                              fontFamily: 'Galey', fontSize: 12,
                              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                              color: active ? Colors.white : Colors.grey.shade600)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Liste
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pets, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Aucun animal',
                                style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _AnimalCard(
                          animal: _filtered[i],
                          age: _age(_filtered[i]['date_naissance']),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => AnimalFichePage(
                                animalId: _filtered[i]['id'],
                                initialData: _filtered[i],
                                isAssociation: true,
                              ),
                            ));
                            _load();
                          },
                          onAddAnnonce: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const CreateAnnoncePage(),
                          )),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final String age;
  final VoidCallback onTap;
  final VoidCallback onAddAnnonce;

  const _AnimalCard({
    required this.animal,
    required this.age,
    required this.onTap,
    required this.onAddAnnonce,
  });

  static const _statutColors = {
    'en_soin': Colors.orange,
    'disponible': Color(0xFF6E9E57),
    'en_fa': Colors.purple,
    'adopte': Color(0xFF0C5C6C),
    'transfere': Colors.blue,
    'decede': Colors.red,
    'present': Color(0xFF6E9E57),
  };

  static const _statutLabels = {
    'en_soin': 'En soin',
    'disponible': 'Disponible',
    'en_fa': 'En FA',
    'adopte': 'Adopté',
    'transfere': 'Transféré',
    'decede': 'Décédé',
    'present': 'Présent',
  };

  @override
  Widget build(BuildContext context) {
    final photo = animal['photo_url']?.toString() ?? '';
    final nom = animal['nom']?.toString() ?? 'Sans nom';
    final espece = animal['espece']?.toString() ?? '';
    final race = animal['race']?.toString() ?? '';
    final statut = animal['statut']?.toString() ?? 'en_soin';
    final color = _statutColors[statut] ?? Colors.grey;
    final label = _statutLabels[statut] ?? statut;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    photo.isNotEmpty
                        ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _placeholder())
                        : _placeholder(),
                    // Statut badge
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(label,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 9,
                                fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Infos
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(nom,
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 13, color: Color(0xFF1F2A2E)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (age.isNotEmpty)
                        Text(age,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  if (race.isNotEmpty || espece.isNotEmpty)
                    Text(race.isNotEmpty ? race : espece,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Actions
            if (statut == 'disponible')
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 28,
                  child: OutlinedButton.icon(
                    onPressed: onAddAnnonce,
                    icon: const Icon(Icons.campaign_outlined, size: 12),
                    label: const Text('Mettre en adoption', style: TextStyle(fontSize: 10)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6E9E57),
                      side: const BorderSide(color: Color(0xFF6E9E57)),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFF0F0EC),
    child: const Icon(Icons.pets, color: Color(0xFFCCCCCC), size: 40),
  );
}
