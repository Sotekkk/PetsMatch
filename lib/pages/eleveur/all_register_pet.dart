import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/eleveur/cat_fiche_edit.dart';
import 'package:PetsMatch/pages/eleveur/dofficheedit.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AllPetRegister extends StatefulWidget {
  const AllPetRegister({super.key});

  @override
  State<AllPetRegister> createState() => _AllPetRegisterState();
}

class _AllPetRegisterState extends State<AllPetRegister> {
  List<Map<String, dynamic>> _dogs = [];
  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _filteredDogs = [];
  List<Map<String, dynamic>> _filteredCats = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchPets();
  }

  Future<void> _fetchPets() async {
    setState(() {
      _loading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      final uid = user.uid;
      final dogSnapshot = await FirebaseFirestore.instance
          .collection('dogfiche')
          .doc(uid)
          .collection('entries')
          .get();

      final catSnapshot = await FirebaseFirestore.instance
          .collection('catfiche')
          .doc(uid)
          .collection('entries')
          .get();

      setState(() {
        _dogs = dogSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        _cats = catSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        _filteredDogs = _dogs;
        _filteredCats = _cats;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _filterPets(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _filteredDogs = _dogs
          .where((dog) =>
              dog['name']?.toLowerCase().contains(_searchQuery) ?? false)
          .toList();
      _filteredCats = _cats
          .where((cat) =>
              cat['name']?.toLowerCase().contains(_searchQuery) ?? false)
          .toList();
    });
  }

  Future<void> _navigateToDetailsPage(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    // Rafraîchit les données après le retour à cette page
    _fetchPets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF6E9E57),
        onRefresh: _fetchPets,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      width: UTILS.widthReference(context),
                      height: UTILS.calculHeight(
                          105, UTILS.heightReference(context)),
                      child: Stack(
                        children: [
                          Image.asset(
                            'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                            fit: BoxFit.cover,
                            width: UTILS.calculWidth(
                                211, UTILS.widthReference(context)),
                            height: UTILS.calculHeight(
                                104, UTILS.heightReference(context)),
                          ),
                          Positioned(
                            top: UTILS.calculHeight(
                                42, UTILS.heightReference(context)),
                            left: UTILS.calculWidth(
                                10, UTILS.widthReference(context)),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.black),
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                          Positioned(
                            top: UTILS.calculHeight(
                                53, UTILS.heightReference(context)),
                            left: 0,
                            right: 0,
                            child: Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Listes de vos animaux',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w500,
                                  fontSize: UTILS.calculWidth(
                                      20, UTILS.widthReference(context)),
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Filtrer les animaux',
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 5.0, horizontal: 15.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: const Color(0x33A7C79A),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13.0),
                            borderSide: const BorderSide(
                              color: Color(0xFFA7C79A),
                              width: 2.0,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13.0),
                            borderSide: const BorderSide(
                              color: Color(0xFFA7C79A),
                              width: 2.0,
                            ),
                          ),
                        ),
                        onChanged: _filterPets,
                      ),
                    ),
                    if (_filteredDogs.isNotEmpty)
                      _buildCategorySection('Chiens', _filteredDogs, true),
                    if (_filteredCats.isNotEmpty)
                      _buildCategorySection('Chats', _filteredCats, false),
                  ],
                ),
              ),
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> pet, bool isDog) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer"),
        content: const Text("Voulez-vous vraiment supprimer cet animal ?"),
        actions: [
          TextButton(
            child: const Text("Annuler"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text("Supprimer"),
            onPressed: () async {
              Navigator.of(context).pop(); // Fermer le dialog
              await _deletePet(pet['id'], isDog);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deletePet(String petId, bool isDog) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final collection = isDog ? 'dogfiche' : 'catfiche';

      await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .collection('entries')
          .doc(petId)
          .delete();

      // Mise à jour des listes
      _fetchPets();
    } catch (e) {
      // Tu peux ajouter un message d'erreur ici si besoin
    }
  }

  Widget _buildCategorySection(
      String category, List<Map<String, dynamic>> pets, bool isDog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            category,
            style: TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.bold,
              fontSize: UTILS.calculWidth(24, UTILS.widthReference(context)),
            ),
          ),
        ),
        Center(
          child: ListView.builder(
            padding: const EdgeInsets.all(8.0),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pets.length,
            itemBuilder: (context, index) {
              final pet = pets[index];
              return GestureDetector(
                onTap: () {
                  _navigateToDetailsPage(
                    isDog
                        ? DogFicheEdit(dogData: pet)
                        : CatFicheEdit(catData: pet),
                  );
                },
                onLongPress: () => _showDeleteDialog(pet, isDog),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.black,
                        backgroundImage: CachedNetworkImageProvider(
                          pet['profilePicture'] != 'Aucune photo de profil'
                              ? pet['profilePicture']
                              : (isDog
                                  ? 'assets/logo/defaultdog.png'
                                  : 'assets/logo/defaultcat.png'),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      Text(
                        pet['name'] ?? 'Aucun nom',
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          fontSize: UTILS.calculWidth(
                              23, UTILS.widthReference(context)),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
