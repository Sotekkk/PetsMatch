import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/services/profile_service.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilAssociationEditPage extends StatefulWidget {
  const ProfilAssociationEditPage({super.key});

  @override
  State<ProfilAssociationEditPage> createState() => _ProfilAssociationEditPageState();
}

class _ProfilAssociationEditPageState extends State<ProfilAssociationEditPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  final _supa = Supabase.instance.client;

  final _nomCtrl   = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  bool   _loading = true;
  bool   _saving  = false;
  File?  _photoFile;
  String? _photoUrl;
  String? _secondaryProfileId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _villeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final d = doc.data() ?? {};

      // Try to find secondary association profile
      final profiles = await ProfileService.loadProfiles(uid);
      final assoProfile = profiles.where((p) => p['profile_type'] == 'association').firstOrNull;

      setState(() {
        _nomCtrl.text   = d['nameElevage']  ?? User_Info.nameElevage;
        _villeCtrl.text = d['villeElevage'] ?? User_Info.villeElevage;
        _descCtrl.text  = d['desc']         ?? User_Info.desc;
        _photoUrl = assoProfile?['avatar_url'] as String?
            ?? d['profilePictureUrlElevage'] as String?
            ?? User_Info.profilePictureUrlElevage;
        _secondaryProfileId = assoProfile?['id']?.toString();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final f = await pickAndCropSquare();
    if (f != null) setState(() => _photoFile = f);
  }

  Future<void> _save() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le nom de l\'association est requis')));
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      String? photoUrl = _photoUrl;
      if (_photoFile != null) {
        photoUrl = await uploadPhoto(_photoFile!, 'profiles/$uid/photo.jpg');
      }

      final ville = _villeCtrl.text.trim();
      final desc  = _descCtrl.text.trim();

      // Save to Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'nameElevage':  nom,
        'villeElevage': ville,
        'desc':         desc,
        if (photoUrl != null) 'profilePictureUrlElevage': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Sync User_Info
      User_Info.nameElevage  = nom;
      User_Info.villeElevage = ville;
      if (photoUrl != null) User_Info.profilePictureUrlElevage = photoUrl;

      // Save to Supabase users
      await _supa.from('users').upsert({
        'uid':          uid,
        'name_elevage': nom,
        'ville_elevage': ville,
        'description_elevage': desc,
        if (photoUrl != null) 'profile_picture_url_elevage': photoUrl,
      }, onConflict: 'uid');

      // Update secondary profile if it exists
      if (_secondaryProfileId != null) {
        await _supa.from('user_profiles').update({
          'profile_label': nom,
          if (photoUrl != null) 'avatar_url': photoUrl,
        }).eq('id', _secondaryProfileId!);
      } else {
        // Upsert secondary profile
        await ProfileService.upsertProfile({
          'uid':           uid,
          'profile_type':  'association',
          'profile_label': nom,
          if (photoUrl != null) 'avatar_url': photoUrl,
        });
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mon Association',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer',
                      style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo
                  Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: _teal.withValues(alpha: 0.12),
                            backgroundImage: _photoFile != null
                                ? FileImage(_photoFile!) as ImageProvider
                                : (_photoUrl?.isNotEmpty == true
                                    ? CachedNetworkImageProvider(_photoUrl!) as ImageProvider
                                    : null),
                            child: (_photoFile == null && (_photoUrl == null || _photoUrl!.isEmpty))
                                ? const Icon(Icons.favorite, color: Color(0xFF0C5C6C), size: 48)
                                : null,
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: _green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Nom
                  _label('Nom de l\'association *'),
                  const SizedBox(height: 6),
                  _field(controller: _nomCtrl, hint: 'Ex : SPA de Lyon, Refuge du Soleil…'),
                  const SizedBox(height: 18),

                  // Ville
                  _label('Ville'),
                  const SizedBox(height: 6),
                  _field(controller: _villeCtrl, hint: 'Ville ou commune'),
                  const SizedBox(height: 18),

                  // Description
                  _label('Présentation'),
                  const SizedBox(height: 6),
                  _field(
                    controller: _descCtrl,
                    hint: 'Décrivez votre association, vos missions…',
                    maxLines: 5,
                  ),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Enregistrer',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
          fontSize: 14, color: Color(0xFF333333)));

  Widget _field({required TextEditingController controller, String? hint, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _teal),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
