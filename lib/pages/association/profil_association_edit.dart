import 'dart:io';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/utils/image_pick.dart' show pickAndCropSquare, pickAndCropBanner;
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  final _telCtrl   = TextEditingController();
  final _siteCtrl  = TextEditingController();

  bool   _loading = true;
  bool   _saving  = false;
  File?  _photoFile;
  String? _photoUrl;
  File?  _bannerFile;
  String? _bannerUrl;
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
    _telCtrl.dispose();
    _siteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      // Charge le profil secondaire association depuis user_profiles
      final profiles = await _supa
          .from('user_profiles')
          .select('id, profile_label, name_elevage, avatar_url, ville, description, telephone, site_web')
          .eq('uid', uid)
          .eq('profile_type', 'association');

      final list = profiles as List;
      final assoProfile = list.isNotEmpty ? list.first as Map<String, dynamic> : null;

      if (assoProfile != null) {
        // Profil secondaire existant → utilise ses données
        // Priorité : name_elevage (nom réel de l'asso) > profile_label (label générique)
        final nomElevage = (assoProfile['name_elevage'] as String?)?.trim() ?? '';
        final label      = (assoProfile['profile_label'] as String?)?.trim() ?? '';
        final nom = nomElevage.isNotEmpty ? nomElevage : label;
        setState(() {
          _secondaryProfileId = assoProfile['id']?.toString();
          _nomCtrl.text   = nom;
          _villeCtrl.text = assoProfile['ville']?.toString() ?? '';
          _descCtrl.text  = assoProfile['description']?.toString() ?? '';
          _telCtrl.text   = assoProfile['telephone']?.toString() ?? '';
          _siteCtrl.text  = assoProfile['site_web']?.toString() ?? '';
          _photoUrl       = assoProfile['avatar_url']?.toString();
          _bannerUrl      = assoProfile['banner_url']?.toString();
          _loading = false;
        });
      } else {
        // Pas encore de profil secondaire → cherche dans users (profil principal association)
        final userRow = await _supa
            .from('users')
            .select('name_elevage, ville_elevage, description_elevage, phone, profile_picture_url_elevage')
            .eq('uid', uid)
            .maybeSingle();
        setState(() {
          _nomCtrl.text   = userRow?['name_elevage']?.toString() ?? '';
          _villeCtrl.text = userRow?['ville_elevage']?.toString() ?? '';
          _descCtrl.text  = userRow?['description_elevage']?.toString() ?? '';
          _telCtrl.text   = userRow?['phone']?.toString() ?? '';
          _photoUrl       = userRow?['profile_picture_url_elevage']?.toString();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final f = await pickAndCropSquare();
    if (f != null) setState(() => _photoFile = f);
  }

  Future<void> _pickBanner() async {
    final f = await pickAndCropBanner();
    if (f != null) setState(() => _bannerFile = f);
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
        photoUrl = await uploadPhoto(_photoFile!, 'profiles/$uid/asso_photo.jpg');
      }

      String? bannerUrl = _bannerUrl;
      if (_bannerFile != null) {
        bannerUrl = await uploadPhoto(_bannerFile!, 'profiles/$uid/asso_banner.jpg');
      }

      final data = <String, dynamic>{
        'uid':           uid,
        'profile_type':  'association',
        'name_elevage':  nom,
        'profile_label': nom,
        'ville':         _villeCtrl.text.trim().isEmpty ? null : _villeCtrl.text.trim(),
        'description':   _descCtrl.text.trim().isEmpty  ? null : _descCtrl.text.trim(),
        'telephone':     _telCtrl.text.trim().isEmpty   ? null : _telCtrl.text.trim(),
        'site_web':      _siteCtrl.text.trim().isEmpty  ? null : _siteCtrl.text.trim(),
        if (photoUrl != null) 'avatar_url': photoUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
      };

      if (_secondaryProfileId != null) {
        await _supa.from('user_profiles').update(data).eq('id', _secondaryProfileId!);
      } else {
        // Crée le profil secondaire
        final inserted = await _supa.from('user_profiles').insert(data).select().single();
        if (mounted) setState(() => _secondaryProfileId = inserted['id']?.toString());
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
                  // Bannière
                  GestureDetector(
                    onTap: _pickBanner,
                    child: Stack(clipBehavior: Clip.none, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 130, width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0C5C6C), Color(0xFF6E9E57)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _bannerFile != null
                              ? Image.file(_bannerFile!, fit: BoxFit.cover, width: double.infinity, height: 130)
                              : (_bannerUrl?.isNotEmpty == true
                                  ? CachedNetworkImage(imageUrl: _bannerUrl!, fit: BoxFit.cover,
                                      width: double.infinity, height: 130,
                                      errorWidget: (_, __, ___) => const SizedBox())
                                  : const Center(child: Icon(Icons.add_photo_alternate_outlined,
                                      color: Colors.white54, size: 36))),
                        ),
                      ),
                      Positioned(
                        bottom: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                          child: const Text('Bannière (16:9)',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white)),
                        ),
                      ),
                      // Photo de profil chevauchant la bannière
                      Positioned(
                        bottom: -28, left: 16,
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: Stack(children: [
                            Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                color: const Color(0xFFEEF5EA),
                              ),
                              child: ClipOval(
                                child: _photoFile != null
                                    ? Image.file(_photoFile!, fit: BoxFit.cover)
                                    : (_photoUrl?.isNotEmpty == true
                                        ? CachedNetworkImage(imageUrl: _photoUrl!, fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) => const Icon(Icons.favorite, size: 28, color: Color(0xFF0C5C6C)))
                                        : const Icon(Icons.favorite, size: 28, color: Color(0xFF0C5C6C))),
                              ),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 40),

                  _label('Nom de l\'association *'),
                  const SizedBox(height: 6),
                  _field(controller: _nomCtrl, hint: 'Ex : SPA de Lyon, Refuge du Soleil…'),
                  const SizedBox(height: 18),

                  _label('Ville'),
                  const SizedBox(height: 6),
                  _field(controller: _villeCtrl, hint: 'Ville ou commune'),
                  const SizedBox(height: 18),

                  _label('Téléphone'),
                  const SizedBox(height: 6),
                  _field(controller: _telCtrl, hint: '+33 6 12 34 56 78', keyboard: TextInputType.phone),
                  const SizedBox(height: 18),

                  _label('Site web'),
                  const SizedBox(height: 6),
                  _field(controller: _siteCtrl, hint: 'https://…', keyboard: TextInputType.url),
                  const SizedBox(height: 18),

                  _label('Présentation'),
                  const SizedBox(height: 6),
                  _field(
                    controller: _descCtrl,
                    hint: 'Décrivez votre association, vos missions…',
                    maxLines: 5,
                  ),

                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const EmployesPage(isAssociation: true))),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: const Color(0xFFE8F4F6), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.group_outlined, color: _teal, size: 20),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Gestion des bénévoles / employés',
                              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                                  fontSize: 14, color: Color(0xFF1F2A2E))),
                          SizedBox(height: 2),
                          Text('Ajouter, révoquer, gérer les accès',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                        ])),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF9CA3AF)),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 32),
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

  Widget _field({required TextEditingController controller, String? hint,
      int maxLines = 1, TextInputType? keyboard}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboard,
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
