import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/eleveur/cat_fiche.dart';
import 'package:PetsMatch/pages/eleveur/cat_fiche_edit.dart';
import 'package:PetsMatch/pages/eleveur/dog_fiche.dart';
import 'package:PetsMatch/pages/eleveur/dofficheedit.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RaceSelectionPage extends StatefulWidget {
  const RaceSelectionPage({super.key});

  @override
  State<RaceSelectionPage> createState() => _RaceSelectionPageState();
}

class _RaceSelectionPageState extends State<RaceSelectionPage> {
  List<_RaceGroup> _races = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRaces();
  }

  Future<void> _fetchRaces() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final dogSnap = await FirebaseFirestore.instance
        .collection('dogfiche')
        .doc(uid)
        .collection('entries')
        .get();
    final catSnap = await FirebaseFirestore.instance
        .collection('catfiche')
        .doc(uid)
        .collection('entries')
        .get();

    final Map<String, _RaceGroup> groups = {};

    for (final doc in dogSnap.docs) {
      final data = doc.data();
      final race = (data['race'] as String?) ?? 'Sans race';
      groups.putIfAbsent(race, () => _RaceGroup(race: race, isDog: true));
      groups[race]!.count++;
      groups[race]!.photos.add(data['profilePicture'] as String? ?? '');
    }
    for (final doc in catSnap.docs) {
      final data = doc.data();
      final race = (data['race'] as String?) ?? 'Sans race';
      final key = '$race|cat';
      groups.putIfAbsent(key, () => _RaceGroup(race: race, isDog: false));
      groups[key]!.count++;
      groups[key]!.photos.add(data['profilePicture'] as String? ?? '');
    }

    setState(() {
      _races = groups.values.toList()
        ..sort((a, b) => a.race.compareTo(b.race));
      _loading = false;
    });
  }

  void _addAnimal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ajouter un animal',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
            const SizedBox(height: 20),
            _AddTypeRow(
              icon: Icons.pets,
              label: 'Chien',
              color: const Color(0xFF43A047),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DogFiche()));
              },
            ),
            const SizedBox(height: 12),
            _AddTypeRow(
              icon: Icons.catching_pokemon,
              label: 'Chat',
              color: const Color(0xFF1E88E5),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CatFiche()));
              },
            ),
          ],
        ),
      ),
    ).then((_) => _fetchRaces());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2025),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mes races',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Colors.white)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_race_fab',
        backgroundColor: const Color(0xFFFF8484),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Ajouter',
            style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        onPressed: _addAnimal,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _races.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  itemCount: _races.length,
                  itemBuilder: (_, i) => _RaceCard(
                    group: _races[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              AnimalByRacePage(group: _races[i])),
                    ).then((_) => _fetchRaces()),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Aucun animal enregistré',
              style: TextStyle(
                  fontFamily: 'Galey',
                  color: Colors.grey.shade500,
                  fontSize: 16)),
          const SizedBox(height: 8),
          Text('Appuyez sur Ajouter pour créer une fiche',
              style: TextStyle(
                  fontFamily: 'Galey',
                  color: Colors.grey.shade400,
                  fontSize: 13)),
        ],
      ),
    );
  }
}

class _RaceGroup {
  final String race;
  final bool isDog;
  int count = 0;
  final List<String> photos = [];

  _RaceGroup({required this.race, required this.isDog});
}

class _RaceCard extends StatelessWidget {
  final _RaceGroup group;
  final VoidCallback onTap;

  const _RaceCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = group.isDog
        ? const Color(0xFF43A047)
        : const Color(0xFF1E88E5);
    final bgColor = group.isDog
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFE3F2FD);
    final photo = group.photos.firstWhere(
        (p) => p.isNotEmpty && p.startsWith('http'),
        orElse: () => '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: photo.isNotEmpty
              ? CircleAvatar(
                  radius: 26,
                  backgroundImage: CachedNetworkImageProvider(photo),
                )
              : CircleAvatar(
                  radius: 26,
                  backgroundColor: bgColor,
                  child: Icon(Icons.pets, color: color, size: 24),
                ),
          title: Text(group.race,
              style: const TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          subtitle: Text(
            '${group.count} animal${group.count > 1 ? 'x' : ''} · ${group.isDog ? 'Chien' : 'Chat'}',
            style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 12,
                color: Colors.grey.shade600),
          ),
          trailing: Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}

class _AddTypeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AddTypeRow(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Page liste animaux par race ──────────────────────────────────────────────

class AnimalByRacePage extends StatefulWidget {
  final _RaceGroup group;

  const AnimalByRacePage({super.key, required this.group});

  @override
  State<AnimalByRacePage> createState() => _AnimalByRacePageState();
}

class _AnimalByRacePageState extends State<AnimalByRacePage> {
  List<Map<String, dynamic>> _animals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAnimals();
  }

  Future<void> _fetchAnimals() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);

    final collection = widget.group.isDog ? 'dogfiche' : 'catfiche';
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .doc(uid)
        .collection('entries')
        .where('race', isEqualTo: widget.group.race)
        .get();

    setState(() {
      _animals =
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _loading = false;
    });
  }

  Future<void> _delete(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final col = widget.group.isDog ? 'dogfiche' : 'catfiche';
    await FirebaseFirestore.instance
        .collection(col)
        .doc(uid)
        .collection('entries')
        .doc(id)
        .delete();
    _fetchAnimals();
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer',
            style: TextStyle(fontFamily: 'Galey')),
        content: Text('Supprimer la fiche de $name ?',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Non')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _delete(id);
              },
              child: const Text('Oui',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _addAnimal() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              widget.group.isDog ? const DogFiche() : const CatFiche()),
    ).then((_) => _fetchAnimals());
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.group.isDog
        ? const Color(0xFF43A047)
        : const Color(0xFF1E88E5);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2025),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.group.race,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Colors.white)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_animal_race_fab',
        backgroundColor: const Color(0xFFFF8484),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Ajouter',
            style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        onPressed: _addAnimal,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _animals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pets, size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Aucun animal pour cette race',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              color: Colors.grey.shade500,
                              fontSize: 15)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  itemCount: _animals.length,
                  itemBuilder: (_, i) {
                    final animal = _animals[i];
                    final photo =
                        animal['profilePicture'] as String? ?? '';
                    final name = animal['name'] as String? ?? '—';

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => widget.group.isDog
                              ? DogFicheEdit(dogData: animal)
                              : CatFicheEdit(catData: animal),
                        ),
                      ).then((_) => _fetchAnimals()),
                      onLongPress: () => _confirmDelete(animal['id'], name),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          leading: photo.isNotEmpty &&
                                  photo.startsWith('http')
                              ? CircleAvatar(
                                  radius: 28,
                                  backgroundImage:
                                      CachedNetworkImageProvider(photo),
                                )
                              : CircleAvatar(
                                  radius: 28,
                                  backgroundColor:
                                      color.withOpacity(0.1),
                                  child: Icon(Icons.pets,
                                      color: color, size: 24),
                                ),
                          title: Text(name,
                              style: const TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          subtitle: Text(
                            animal['sexe'] as String? ??
                                animal['sex'] as String? ??
                                '',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 12,
                                color: Colors.grey.shade600),
                          ),
                          trailing: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: Colors.grey.shade400),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
