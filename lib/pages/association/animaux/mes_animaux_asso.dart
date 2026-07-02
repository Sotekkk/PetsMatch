import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart' show speciesIcon, speciesColor, speciesLabel;
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/services/chip_scanner_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MesAnimauxAssoPage extends StatefulWidget {
  final String initialFilterStatut;
  const MesAnimauxAssoPage({super.key, this.initialFilterStatut = 'tous'});
  @override
  State<MesAnimauxAssoPage> createState() => _MesAnimauxAssoPageState();
}

class _MesAnimauxAssoPageState extends State<MesAnimauxAssoPage> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;

  static const _teal = Color(0xFF0C5C6C);

  late final TabController _tabController;
  List<Map<String, dynamic>> _animaux = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  late String _filterStatut = widget.initialFilterStatut;
  String _search = '';
  String? _myUid;

  // "Ancien" = l'animal a un nouveau propriétaire (adopté/transféré) ou est décédé.
  // "Détenus" = tout le reste (en_soin, disponible — et en_fa n'est plus un statut,
  // c'est un état indépendant porté par fa_id, un animal en FA reste "détenu").
  static const _anciensValues = {'adopte', 'transfere', 'decede'};

  static const _detenusStatuts = [
    ('tous', 'Tous', Colors.grey),
    ('en_soin', 'En soin', Colors.orange),
    ('disponible', 'Disponible', Color(0xFF6E9E57)),
    ('en_fa', 'En FA', Colors.purple),
  ];

  static const _anciensStatuts = [
    ('tous', 'Tous', Colors.grey),
    ('adopte', 'Adopté', Color(0xFF0C5C6C)),
    ('transfere', 'Transféré', Colors.blue),
    ('decede', 'Décédé', Colors.red),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (_anciensValues.contains(widget.initialFilterStatut)) _tabController.index = 1;
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      setState(() { _filterStatut = 'tous'; _applyFilters(); });
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _myUid = uid;
    try {
      const cols = 'id,nom,espece,race,sexe,statut,fa_id,date_naissance,photo_url,date_entree,date_sortie,uid_eleveur';
      final results = await Future.wait([
        _supa.from('animaux').select(cols)
            .eq('uid_eleveur', uid).eq('is_association', true).order('nom'),
        _supa.from('animaux').select(cols)
            .eq('uid_acquereur', uid).order('date_sortie', ascending: false),
      ]);
      final owned = List<Map<String, dynamic>>.from(results[0] as List);
      final receivedIds = owned.map((a) => a['id']).toSet();
      final received = List<Map<String, dynamic>>.from(results[1] as List)
          .where((a) => !receivedIds.contains(a['id']))
          .toList();
      if (mounted) {
        setState(() {
          _animaux = [...owned, ...received];
          _applyFilters();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final isDetenus = _tabController.index == 0;
    _filtered = _animaux.where((a) {
      final statut = a['statut']?.toString() ?? 'en_soin';
      final matchTab = isDetenus ? !_anciensValues.contains(statut) : _anciensValues.contains(statut);
      if (!matchTab) return false;
      final matchStatut = _filterStatut == 'tous'
          || (_filterStatut == 'en_fa' ? a['fa_id'] != null : statut == _filterStatut);
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
    final statuts = _tabController.index == 0 ? _detenusStatuts : _anciensStatuts;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Mes Animaux',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Détenus'), Tab(text: 'Ancien')],
        ),
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
          // Filtres statut (dépendent de l'onglet actif)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: statuts.map((s) {
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
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.68,
                        ),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final a = _filtered[i];
                          final isCession = _myUid != null && a['uid_eleveur'] != _myUid;
                          return _AnimalCard(
                            animal: a,
                            age: _age(a['date_naissance']),
                            isCession: isCession,
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => AnimalFichePage(
                                  animalId: a['id'],
                                  initialData: a,
                                  isAssociation: true,
                                  eleveurUidOverride: isCession ? a['uid_eleveur'] as String? : null,
                                ),
                              ));
                              _load();
                            },
                            onAddAnnonce: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => CreateAnnonceAssoPage(
                                animalId: a['id']?.toString(),
                                initialAnimal: a,
                              ),
                            )),
                          );
                        },
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
  final bool isCession;
  final VoidCallback onTap;
  final VoidCallback onAddAnnonce;

  const _AnimalCard({
    required this.animal,
    required this.age,
    required this.onTap,
    required this.onAddAnnonce,
    this.isCession = false,
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
    final enFa   = animal['fa_id'] != null;
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
                    // Badge En FA — indépendant du statut, un animal peut être
                    // à la fois "Disponible" et "En FA" en même temps.
                    if (enFa)
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('🏡 FA',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 9,
                                  fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    if (isCession)
                      Positioned(
                        bottom: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('🤝 Cession',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 9,
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
