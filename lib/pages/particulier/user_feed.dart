import 'dart:io';

import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/mes_animaux_page.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserParticulierFeed extends StatefulWidget {
  const UserParticulierFeed({super.key});

  @override
  State<UserParticulierFeed> createState() => _UserParticulierFeedState();
}

class _UserParticulierFeedState extends State<UserParticulierFeed>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController _descriptionController =
      TextEditingController(text: '');
  final TextEditingController _adoptionProjectController =
      TextEditingController(text: '');

  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isImagePickerActive = false;
  String profilePictureUrl =
      'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
  bool isDescriptionModified = false;
  bool isAdoptionProjectModified = false;
  String initialDescription = '';
  String initialAdoptionProject = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUserData();

    _descriptionController.addListener(() {
      setState(() {
        isDescriptionModified = _descriptionController.text != initialDescription;
      });
    });
    _adoptionProjectController.addListener(() {
      setState(() {
        isAdoptionProjectModified =
            _adoptionProjectController.text != initialAdoptionProject;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _descriptionController.dispose();
    _adoptionProjectController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(User_Info.uid)
          .get();
      setState(() {
        profilePictureUrl = doc['profilePictureUrl'] ??
            'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
        initialDescription = doc['desc'] ?? '';
        initialAdoptionProject = doc['adoptProject'] ?? '';
        _descriptionController.text = initialDescription;
        _adoptionProjectController.text = initialAdoptionProject;
      });
    } catch (_) {}
  }

  Future<void> _pickImage() async {
    if (_isImagePickerActive) return;
    try {
      setState(() => _isImagePickerActive = true);
      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);
      setState(() {
        _imageFile = pickedFile != null ? File(pickedFile.path) : _imageFile;
        _isImagePickerActive = false;
      });
      if (_imageFile != null) await _uploadFile();
    } catch (_) {
      setState(() => _isImagePickerActive = false);
    }
  }

  Future<void> _uploadFile() async {
    final name = _imageFile!.path.split('/').last;
    final ref = FirebaseStorage.instance.ref().child('files/$name');
    final snapshot = await ref.putFile(_imageFile!);
    final url = await snapshot.ref.getDownloadURL();
    setState(() => profilePictureUrl = url);
    User_Info.profilePictureUrl = url;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(User_Info.uid)
        .update({'profilePictureUrl': url});
  }

  Future<void> _updateDescription() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(User_Info.uid)
        .update({'desc': _descriptionController.text});
    setState(() {
      isDescriptionModified = false;
      initialDescription = _descriptionController.text;
    });
    User_Info.desc = _descriptionController.text;
  }

  Future<void> _updateAdoptionProject() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(User_Info.uid)
        .update({'adoptProject': _adoptionProjectController.text});
    setState(() {
      isAdoptionProjectModified = false;
      initialAdoptionProject = _adoptionProjectController.text;
    });
    User_Info.adoptProject = _adoptionProjectController.text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            backgroundColor: const Color(0xFF1E2025),
            automaticallyImplyLeading: false,
            expandedHeight: 100,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 4, 50),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Mon Profil',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: Colors.white),
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => InfoUserSettings())),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert,
                            size: 18, color: Colors.white),
                        onSelected: (value) {
                          if (value == 'settings') {
                            Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => SettingsMainPage()));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'settings',
                            child: Row(children: [
                              Icon(Icons.settings, size: 18),
                              SizedBox(width: 8),
                              Text('Paramètres',
                                  style: TextStyle(fontFamily: 'Galey')),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFF8484),
              labelColor: const Color(0xFFFF8484),
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
              tabs: const [
                Tab(text: 'Mon Profil'),
                Tab(text: 'Mes Animaux'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildProfilTab(context),
            _buildAnimauxTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        children: [
          // Photo
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.black,
                    backgroundImage: _imageFile != null
                        ? FileImage(_imageFile!) as ImageProvider
                        : CachedNetworkImageProvider(profilePictureUrl),
                  ),
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFFFB2AD),
                    child:
                        const Icon(Icons.edit, size: 16, color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${User_Info.firstname} ${User_Info.lastname}',
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 28),

          // Description
          _SectionTitle('Mes informations'),
          const SizedBox(height: 10),
          _TextBox(controller: _descriptionController, hint: 'Parlez-nous un peu de vous'),
          const SizedBox(height: 8),
          if (isDescriptionModified)
            _SaveButton(label: 'Enregistrer', onPressed: _updateDescription),

          const SizedBox(height: 24),

          // Projet d'adoption
          _SectionTitle("Projet d'adoption"),
          const SizedBox(height: 10),
          _TextBox(
              controller: _adoptionProjectController,
              hint: "Parlez-nous de votre projet d'adoption"),
          const SizedBox(height: 8),
          if (isAdoptionProjectModified)
            _SaveButton(
                label: 'Enregistrer', onPressed: _updateAdoptionProject),
        ],
      ),
    );
  }

  Widget _buildAnimauxTab() {
    final uid = User_Info.uid;
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('pets')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final pets = snapshot.data?.docs ?? [];

            if (pets.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pets, size: 72, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('Aucun animal enregistré',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 16,
                            color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Text('Appuyez sur + pour ajouter votre premier animal',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            color: Colors.grey.shade400)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: pets.length,
              itemBuilder: (context, index) {
                final data = pets[index].data() as Map<String, dynamic>;
                final petId = pets[index].id;
                return _AnimalCard(petId: petId, data: data, uid: uid ?? '');
              },
            );
          },
        ),
        // FAB
        Positioned(
          right: 16,
          bottom: 90,
          child: FloatingActionButton(
            backgroundColor: const Color(0xFFFF8484),
            child: const Icon(Icons.add, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnimalFormPage()),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text,
          style: const TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Colors.black)),
    );
  }
}

class _TextBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _TextBox({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color.fromARGB(176, 250, 192, 187),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextFormField(
        controller: controller,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _SaveButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF8484),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final String petId;
  final Map<String, dynamic> data;
  final String uid;

  const _AnimalCard(
      {required this.petId, required this.data, required this.uid});

  String _speciesEmoji(String? species) {
    switch (species) {
      case 'Chien': return '🐕';
      case 'Chat': return '🐈';
      case 'Oiseau': return '🐦';
      case 'Lapin': return '🐇';
      default: return '🐾';
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['photoUrl'] as String?;
    final name = data['name'] as String? ?? 'Sans nom';
    final species = data['species'] as String?;
    final breed = data['breed'] as String?;
    final description = data['description'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AnimalFormPage(petId: petId, existing: data)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: const Color(0xFFFFF0EE),
                        child: Center(
                          child: Text(_speciesEmoji(species),
                              style: const TextStyle(fontSize: 30)),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    if (species != null || breed != null)
                      Text(
                        [if (species != null) species, if (breed != null) breed]
                            .join(' · '),
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            color: Colors.grey.shade600),
                      ),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 12,
                                color: Colors.grey.shade500)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    color: Colors.grey.shade400, size: 20),
                onSelected: (value) async {
                  if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Supprimer cet animal ?'),
                        content: Text('$name sera supprimé définitivement.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annuler')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Supprimer',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('pets')
                          .doc(petId)
                          .delete();
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Supprimer',
                          style: TextStyle(
                              fontFamily: 'Galey', color: Colors.red)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
