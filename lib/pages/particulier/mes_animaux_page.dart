import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';

class MesAnimauxPage extends StatelessWidget {
  const MesAnimauxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = User_Info.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2025),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mes animaux',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_animal_page_fab',
        backgroundColor: const Color(0xFF6E9E57),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AnimalFormPage()),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
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
              return _AnimalCard(
                petId: petId,
                data: data,
                uid: uid ?? '',
              );
            },
          );
        },
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final String petId;
  final Map<String, dynamic> data;
  final String uid;

  const _AnimalCard({required this.petId, required this.data, required this.uid});

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
            builder: (_) => AnimalFormPage(petId: petId, existing: data),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Photo or emoji
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const CircularProgressIndicator(),
                        errorWidget: (_, __, ___) => _EmojiAvatar(
                            emoji: _speciesEmoji(species)),
                      )
                    : _EmojiAvatar(emoji: _speciesEmoji(species)),
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
                icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
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
                          style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
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

class _EmojiAvatar extends StatelessWidget {
  final String emoji;
  const _EmojiAvatar({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF5EA),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 30))),
    );
  }
}

// ── Add / Edit form ──────────────────────────────────────────────────────────

class AnimalFormPage extends StatefulWidget {
  final String? petId;
  final Map<String, dynamic>? existing;

  const AnimalFormPage({this.petId, this.existing});

  @override
  State<AnimalFormPage> createState() => AnimalFormPageState();
}

class AnimalFormPageState extends State<AnimalFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _breedController = TextEditingController();
  final _descController = TextEditingController();

  String? _selectedSpecies;
  File? _imageFile;
  String? _existingPhotoUrl;
  bool _saving = false;

  static const _species = ['Chien', 'Chat', 'Oiseau', 'Lapin', 'Autre'];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!['name'] ?? '';
      _breedController.text = widget.existing!['breed'] ?? '';
      _descController.text = widget.existing!['description'] ?? '';
      _selectedSpecies = widget.existing!['species'];
      _existingPhotoUrl = widget.existing!['photoUrl'];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) setState(() => _imageFile = File(file.path));
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return _existingPhotoUrl;
    final name = _imageFile!.path.split('/').last;
    final ref = FirebaseStorage.instance.ref().child('pets/$name');
    final snapshot = await ref.putFile(_imageFile!);
    return await snapshot.ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final photoUrl = await _uploadImage();
      final uid = User_Info.uid ?? '';
      final data = {
        'name': _nameController.text.trim(),
        'species': _selectedSpecies,
        'breed': _breedController.text.trim(),
        'description': _descController.text.trim(),
        'photoUrl': photoUrl ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pets');

      if (widget.petId != null) {
        await col.doc(widget.petId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await col.add(data);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.petId != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2025),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(isEdit ? 'Modifier l\'animal' : 'Ajouter un animal',
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      color: const Color(0xFF6E9E57),
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: const Color(0xFFEEF5EA),
                        backgroundImage: _imageFile != null
                            ? FileImage(_imageFile!) as ImageProvider
                            : (_existingPhotoUrl != null &&
                                    _existingPhotoUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(_existingPhotoUrl!)
                                : null),
                        child: (_imageFile == null &&
                                (_existingPhotoUrl == null ||
                                    _existingPhotoUrl!.isEmpty))
                            ? const Icon(Icons.pets, size: 40, color: const Color(0xFF6E9E57))
                            : null,
                      ),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFF6E9E57),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              _SectionLabel('Nom *'),
              const SizedBox(height: 8),
              _FormField(
                controller: _nameController,
                hint: 'Ex: Rex, Luna...',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 20),

              _SectionLabel('Espèce'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: DropdownButtonFormField<String>(
                  value: _selectedSpecies,
                  decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                  hint: const Text('Sélectionner',
                      style: TextStyle(fontFamily: 'Galey')),
                  style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
                  items: _species
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s,
                              style: const TextStyle(fontFamily: 'Galey'))))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSpecies = v),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel('Race'),
              const SizedBox(height: 8),
              _FormField(
                controller: _breedController,
                hint: 'Ex: Berger Allemand, Maine Coon...',
              ),
              const SizedBox(height: 20),

              _SectionLabel('Description'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(16),
                    hintText: 'Décrivez votre animal...',
                    hintStyle:
                        TextStyle(fontFamily: 'Galey', color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14));
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;

  const _FormField({required this.controller, required this.hint, this.validator});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: TextFormField(
        controller: controller,
        validator: validator,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
