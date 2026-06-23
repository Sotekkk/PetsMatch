import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart' show speciesIcon, speciesColor, speciesLabel;
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/services/chip_scanner_service.dart';
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
  List<Map<String, dynamic>> _animauxRecus = [];
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
      final results = await Future.wait([
        _supa.from('animaux')
            .select('id,nom,espece,race,sexe,statut,date_naissance,photo_url,date_entree')
            .eq('uid_eleveur', uid)
            .eq('is_association', true)
            .order('nom'),
        _supa.from('animaux')
            .select('id,nom,espece,race,sexe,statut,date_naissance,photo_url,date_sortie,uid_eleveur')
            .eq('uid_acquereur', uid)
            .order('date_sortie', ascending: false),
      ]);
      if (mounted) {
        setState(() {
          _animaux = List<Map<String, dynamic>>.from(results[0] as List);
          _animauxRecus = List<Map<String, dynamic>>.from(results[1] as List);
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
            icon: const Icon(Icons.sensors_rounded),
            tooltip: 'Scanner une puce',
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) ChipScannerService.scanFromAssociation(context, uid);
            },
          ),
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
                : (_filtered.isEmpty && _animauxRecus.isEmpty)
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
                    : CustomScrollView(
                        slivers: [
                          if (_filtered.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.all(12),
                              sliver: SliverGrid(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.68,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => _AnimalCard(
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
                                      builder: (_) => CreateAnnonceAssoPage(
                                        animalId: _filtered[i]['id']?.toString(),
                                        initialAnimal: _filtered[i],
                                      ),
                                    )),
                                  ),
                                  childCount: _filtered.length,
                                ),
                              ),
                            ),
                          if (_filtered.isEmpty && _animauxRecus.isNotEmpty)
                            const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          if (_animauxRecus.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                child: Row(children: [
                                  const Icon(Icons.handshake_outlined, size: 16, color: Color(0xFF0C5C6C)),
                                  const SizedBox(width: 6),
                                  Text('Reçus par cession (${_animauxRecus.length})',
                                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                          fontSize: 13, color: Color(0xFF0C5C6C))),
                                ]),
                              ),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) {
                                  final a = _animauxRecus[i];
                                  final nom = a['nom'] as String? ?? '—';
                                  final espece = a['espece'] as String? ?? '';
                                  final dateStr = a['date_sortie'] as String?;
                                  final dt = dateStr != null ? DateTime.tryParse(dateStr) : null;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF0C5C6C).withOpacity(0.08),
                                      backgroundImage: a['photo_url'] != null
                                          ? NetworkImage(a['photo_url'] as String) : null,
                                      child: a['photo_url'] == null
                                          ? Text(speciesLabel(espece).isNotEmpty
                                              ? speciesLabel(espece)[0].toUpperCase() : '🐾',
                                              style: const TextStyle(fontSize: 16))
                                          : null,
                                    ),
                                    title: Text(nom, style: const TextStyle(
                                        fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                                    subtitle: Text(
                                      '$espece${dt != null ? ' · Reçu le ${dt.day}/${dt.month}/${dt.year}' : ''}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                                    onTap: () async {
                                      await Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => AnimalFichePage(
                                          animalId: a['id'] as String,
                                          readOnly: false,
                                          isAssociation: true,
                                          eleveurUidOverride: a['uid_eleveur'] as String?,
                                        ),
                                      ));
                                      _load();
                                    },
                                  );
                                },
                                childCount: _animauxRecus.length,
                              ),
                            ),
                          ],
                        ],
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

  static const _statutColors = <String, Color>{
    'en_soin':   Colors.orange,
    'disponible': Color(0xFF6E9E57),
    'en_fa':     Colors.purple,
    'adopte':    Color(0xFF0C5C6C),
    'transfere': Colors.blue,
    'decede':    Colors.red,
    'present':   Color(0xFF6E9E57),
  };

  static const _statutLabels = <String, String>{
    'en_soin':   'En soin',
    'disponible': 'Disponible',
    'en_fa':     'En FA',
    'adopte':    'Adopté',
    'transfere': 'Transféré',
    'decede':    'Décédé',
    'present':   'Présent',
  };

  @override
  Widget build(BuildContext context) {
    final photo  = animal['photo_url']?.toString() ?? '';
    final nom    = animal['nom']?.toString()    ?? 'Sans nom';
    final espece = animal['espece']?.toString() ?? '';
    final race   = animal['race']?.toString()   ?? '';
    final sexe   = animal['sexe']?.toString()   ?? '';
    final statut = animal['statut']?.toString() ?? 'en_soin';
    final statutColor = _statutColors[statut] ?? Colors.grey;
    final statutLabel = _statutLabels[statut] ?? statut;
    final specColor   = speciesColor(espece);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo carrée
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    photo.isNotEmpty
                        ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: specColor.withValues(alpha: 0.12),
                              child: Center(child: speciesIcon(espece, 44, specColor))))
                        : Container(
                            color: specColor.withValues(alpha: 0.12),
                            child: Center(child: speciesIcon(espece, 44, specColor))),
                    // Statut badge
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: statutColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(statutLabel,
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 14, color: Color(0xFF1F2A2E)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (race.isNotEmpty)
                  Text(race,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(children: [
                  _Chip(speciesLabel(espece), specColor),
                  if (sexe.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _Chip(sexe == 'male' ? '♂' : '♀', const Color(0xFF5F9EAA)),
                  ],
                  if (statut == 'disponible') ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onAddAnnonce,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6E9E57).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF6E9E57), width: 0.7),
                        ),
                        child: const Text('+ Adopter',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 9,
                                fontWeight: FontWeight.w700, color: Color(0xFF6E9E57))),
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: TextStyle(fontFamily: 'Galey', fontSize: 10,
            fontWeight: FontWeight.w600, color: color)),
  );
}
