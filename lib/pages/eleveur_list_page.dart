import 'dart:convert';
import 'package:PetsMatch/pages/eleveur_map_view.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EleveurListPage extends StatefulWidget {
  const EleveurListPage({super.key});

  @override
  State<EleveurListPage> createState() => _EleveurListPageState();
}

class _EleveurListPageState extends State<EleveurListPage> {
  String _search = '';
  String _locationSearch = '';
  String _speciesFilter = 'tous';
  bool _mapView = false;
  List<String> _selectedBreeds = [];
  List<String> _allDogBreeds = [];
  List<String> _allCatBreeds = [];

  static const _speciesFilters = [
    ('tous', 'Tous'),
    ('chien', 'Chiens'),
    ('chat', 'Chats'),
  ];

  @override
  void initState() {
    super.initState();
    _loadBreeds();
  }

  Future<void> _loadBreeds() async {
    final dogJson = await rootBundle.loadString('assets/dog_breeds.json');
    final catJson = await rootBundle.loadString('assets/cat_breeds.json');
    setState(() {
      _allDogBreeds = List<String>.from(jsonDecode(dogJson));
      _allCatBreeds = List<String>.from(jsonDecode(catJson));
    });
  }

  List<String> get _breedsForFilter {
    if (_speciesFilter == 'chien') return _allDogBreeds;
    if (_speciesFilter == 'chat') return _allCatBreeds;
    return [..._allDogBreeds, ..._allCatBreeds];
  }

  Future<void> _openBreedFilter() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BreedFilterSheet(
        allBreeds: _breedsForFilter,
        selected: List<String>.from(_selectedBreeds),
      ),
    );
    if (result != null) setState(() => _selectedBreeds = result);
  }

  bool _matchesSpecies(Map<String, dynamic> data) {
    if (_speciesFilter == 'tous') return true;
    if (_speciesFilter == 'chien') return data['isDog'] == true;
    if (_speciesFilter == 'chat') return data['isCat'] == true;
    return true;
  }

  bool _matchesBreeds(Map<String, dynamic> data) {
    if (_selectedBreeds.isEmpty) return true;
    final all = [
      ...List<String>.from(data['dogBreeds'] ?? []),
      ...List<String>.from(data['catBreeds'] ?? []),
    ];
    return _selectedBreeds.any((b) => all.contains(b));
  }

  bool _matchesLocation(Map<String, dynamic> data) {
    if (_locationSearch.isEmpty) return true;
    final q = _locationSearch.toLowerCase();
    final ville = (data['villeElevage'] ?? '').toString().toLowerCase();
    final cp = (data['codePostalElevage'] ?? '').toString().toLowerCase();
    final pays = (data['paysElevage'] ?? '').toString().toLowerCase();
    final adresse = (data['adressElevage'] ?? '').toString().toLowerCase();
    return ville.contains(q) || cp.contains(q) || pays.contains(q) || adresse.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: Column(
        children: [
          // Header
          SizedBox(
            width: UTILS.widthReference(context),
            height: UTILS.calculHeight(104, UTILS.heightReference(context)),
            child: Stack(
              children: [
                Image.asset(
                  'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                  fit: BoxFit.cover,
                  width: UTILS.calculWidth(211, UTILS.widthReference(context)),
                  height:
                      UTILS.calculHeight(104, UTILS.heightReference(context)),
                ),
                Positioned(
                  top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      'ÉLEVAGES',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: UTILS.calculHeight(48, UTILS.heightReference(context)),
                  right: 12,
                  child: GestureDetector(
                    onTap: () => setState(() => _mapView = !_mapView),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _mapView ? Icons.list : Icons.map_outlined,
                            size: 16,
                            color: Colors.black87,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _mapView ? 'Liste' : 'Carte',
                            style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Barre de recherche nom/élevage
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Rechercher un élevage...',
                hintStyle:
                    const TextStyle(fontFamily: 'Galey', fontSize: 14),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Barre de recherche localisation
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: (v) =>
                  setState(() => _locationSearch = v),
              decoration: InputDecoration(
                hintText: 'Ville, département, région...',
                hintStyle:
                    const TextStyle(fontFamily: 'Galey', fontSize: 14),
                prefixIcon: const Icon(Icons.location_on_outlined),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Filtres espèces + races
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ..._speciesFilters.map((f) {
                  final selected = _speciesFilter == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        f.$2,
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _speciesFilter = f.$1;
                        _selectedBreeds = [];
                      }),
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFA7C79A),
                      checkmarkColor: Colors.black,
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFFA7C79A)
                            : Colors.grey.shade300,
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: _openBreedFilter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _selectedBreeds.isEmpty
                          ? Colors.white
                          : const Color(0xFFA7C79A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _selectedBreeds.isEmpty
                            ? Colors.grey.shade300
                            : const Color(0xFFA7C79A),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tune, size: 14, color: Colors.black87),
                        const SizedBox(width: 5),
                        Text(
                          _selectedBreeds.isEmpty
                              ? 'Races'
                              : '${_selectedBreeds.length} race(s)',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _selectedBreeds.isEmpty
                                ? Colors.black87
                                : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Contenu : liste ou carte
          Expanded(
            child: _mapView
                ? EleveurMapView(
                    speciesFilter: _speciesFilter,
                    nameSearch: _search,
                    locationSearch: _locationSearch,
                  )
                : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('isElevage', isEqualTo: true)
                  .where('isValidate', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const _EmptyState();
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  if (!_matchesSpecies(data)) return false;
                  if (!_matchesBreeds(data)) return false;
                  if (!_matchesLocation(data)) return false;

                  if (_search.isNotEmpty) {
                    final name =
                        (data['nameElevage'] ?? '').toString().toLowerCase();
                    final address = (data['adressElevage'] ?? '')
                        .toString()
                        .toLowerCase();
                    final desc = (data['descEntreprise'] ?? '')
                        .toString()
                        .toLowerCase();
                    if (!name.contains(_search) &&
                        !address.contains(_search) &&
                        !desc.contains(_search)) {
                      return false;
                    }
                  }
                  return true;
                }).toList();

                if (docs.isEmpty) {
                  return const _EmptyState(message: 'Aucun résultat.');
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data =
                        docs[index].data() as Map<String, dynamic>;
                    final uid = docs[index].id;
                    return _EleveurCard(data: data, uid: uid);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EleveurCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;

  const _EleveurCard({required this.data, required this.uid});

  @override
  Widget build(BuildContext context) {
    final nameElevage = data['nameElevage'] ?? 'Élevage';
    final adress = FrenchGeo.formatLocation(data).isNotEmpty
        ? FrenchGeo.formatLocation(data)
        : (data['adressElevage'] ?? '').toString().trim();
    final desc = data['descEntreprise'] ?? '';
    final ppUrl = data['profilePictureUrlElevage'] ?? '';
    final isDog = data['isDog'] == true;
    final isCat = data['isCat'] == true;
    final dogBreeds = List<String>.from(data['dogBreeds'] ?? []);
    final catBreeds = List<String>.from(data['catBreeds'] ?? []);

    return GestureDetector(
      onTap: () {
        final user = UserSelected.fromMap(data, uid);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserDetailPageFeed(user: user),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo bannière
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20)),
              child: ppUrl.isNotEmpty
                  ? Image.network(
                      ppUrl,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _PlaceholderBanner(),
                    )
                  : const _PlaceholderBanner(),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nom + badge vérifié
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nameElevage,
                          style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF2E7D32).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                color: Color(0xFF2E7D32), size: 13),
                            SizedBox(width: 4),
                            Text(
                              'PRO Vérifié',
                              style: TextStyle(
                                color: Color(0xFF2E7D32),
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Tags espèces + races
                  if (isDog || isCat) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (isDog) _SpeciesChip(label: 'Chien', icon: '🐶'),
                        if (isCat) _SpeciesChip(label: 'Chat', icon: '🐱'),
                        ...dogBreeds.take(3).map(
                              (r) => _BreedChip(label: r),
                            ),
                        ...catBreeds.take(3).map(
                              (r) => _BreedChip(label: r),
                            ),
                        if (dogBreeds.length + catBreeds.length > 3)
                          _BreedChip(
                              label:
                                  '+${dogBreeds.length + catBreeds.length - 3}'),
                      ],
                    ),
                  ],

                  if (adress.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            adress,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontFamily: 'Galey'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeciesChip extends StatelessWidget {
  final String label;
  final String icon;

  const _SpeciesChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFA7C79A).withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFA7C79A),
          width: 1,
        ),
      ),
      child: Text(
        '$icon $label',
        style: const TextStyle(
          fontFamily: 'Galey',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _BreedChip extends StatelessWidget {
  final String label;

  const _BreedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Galey',
          fontSize: 10,
          color: Colors.black54,
        ),
      ),
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  const _PlaceholderBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      width: double.infinity,
      color:
          const Color(0xFFA7C79A).withOpacity(0.3),
      child: const Icon(Icons.pets,
          size: 48, color: Color(0xFFA7C79A)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(
      {this.message = 'Aucun élevage vérifié pour le moment.'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            message,
            style:
                const TextStyle(color: Colors.grey, fontFamily: 'Galey'),
          ),
        ],
      ),
    );
  }
}

class _BreedFilterSheet extends StatefulWidget {
  final List<String> allBreeds;
  final List<String> selected;
  const _BreedFilterSheet({required this.allBreeds, required this.selected});

  @override
  State<_BreedFilterSheet> createState() => _BreedFilterSheetState();
}

class _BreedFilterSheetState extends State<_BreedFilterSheet> {
  late List<String> _selected;
  late List<String> _filtered;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
    _filtered = List<String>.from(widget.allBreeds);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Filtrer par race',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 18)),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text('Effacer',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Appliquer',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6E9E57),
                            fontSize: 15)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _search,
                onChanged: (q) => setState(() {
                  _filtered = widget.allBreeds
                      .where((b) => b.toLowerCase().contains(q.toLowerCase()))
                      .toList();
                }),
                decoration: InputDecoration(
                  hintText: 'Rechercher une race...',
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 6, runSpacing: 4,
                  children: _selected
                      .map((b) => Chip(
                            label: Text(b,
                                style: const TextStyle(
                                    fontFamily: 'Galey', fontSize: 12)),
                            backgroundColor:
                                const Color(0xFFA7C79A),
                            deleteIconColor: Colors.black54,
                            onDeleted: () =>
                                setState(() => _selected.remove(b)),
                          ))
                      .toList(),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final breed = _filtered[i];
                  final sel = _selected.contains(breed);
                  return ListTile(
                    dense: true,
                    title: Text(breed,
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 14,
                            fontWeight:
                                sel ? FontWeight.w500 : FontWeight.normal)),
                    trailing: Icon(
                        sel ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: sel
                            ? const Color(0xFF6E9E57)
                            : Colors.grey,
                        size: 20),
                    onTap: () => setState(() {
                      sel ? _selected.remove(breed) : _selected.add(breed);
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
