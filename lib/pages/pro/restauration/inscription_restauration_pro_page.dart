import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/utils.dart';

// ── Types d'établissement ───────────────────────────────────────────────────

const _kTypes = [
  ('restaurant',           '🍽️', 'Restaurant'),
  ('hotel',                '🏨', 'Hôtel pet-friendly'),
  ('cafe',                 '☕', 'Café / Salon de thé'),
  ('bar',                  '🍺', 'Bar / Brasserie'),
  ('fast_food',            '🍔', 'Restauration rapide'),
  ('boulangerie',          '🥐', 'Boulangerie / Pâtisserie'),
  ('gite',                 '🏡', 'Gîte / Chambre d\'hôtes'),
  ('hebergement_insolite', '🏕️', 'Hébergement insolite'),
  ('camping',              '⛺', 'Camping'),
  ('villa_location',       '🏖️', 'Location saisonnière'),
];

const _kEspeces = ['Chien', 'Chat', 'Lapin', 'Cheval', 'Oiseau', 'NAC', 'Tous'];

// ── Page principale ─────────────────────────────────────────────────────────

class InscriptionRestaurationProPage extends StatefulWidget {
  const InscriptionRestaurationProPage({super.key});

  @override
  State<InscriptionRestaurationProPage> createState() =>
      _InscriptionRestaurationProPageState();
}

class _InscriptionRestaurationProPageState
    extends State<InscriptionRestaurationProPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg   = Color(0xFFF8F8F6);

  int  _step   = 0;
  bool _saving = false;

  // Étape 0 — Identité personnelle
  final _prenomCtrl = TextEditingController();
  final _nomCtrl    = TextEditingController();
  final _dobCtrl    = TextEditingController();
  File? _photoProfil;

  // Étape 1 — Sécurité
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  bool _showPass = false;

  // Étape 2 — Info établissement
  final _nomEtablCtrl  = TextEditingController();
  final _siretCtrl     = TextEditingController();
  String _typeEtabl    = 'restaurant';
  final List<String> _especesAcceptees = [];

  // Étape 3 — Adresse avec map
  final _adresseSearchCtrl = TextEditingController();
  final _rueCtrl   = TextEditingController();
  final _cpCtrl    = TextEditingController();
  final _villeCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  Timer? _debounce;
  late final GoogleMapsPlaces _places;

  // Étape 4 — Photos
  File? _banner;
  final List<File> _feedPhotos = [];

  // Étape 5 — Description & conditions
  final _descCtrl     = TextEditingController();
  final _condCtrl     = TextEditingController();
  bool _cguAccepted   = false;

  static const _steps = [
    'Identité',
    'Sécurité',
    'Établissement',
    'Adresse',
    'Photos',
    'Finalisation',
  ];

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    for (final c in [
      _prenomCtrl, _nomCtrl, _dobCtrl,
      _emailCtrl, _passCtrl, _phoneCtrl,
      _nomEtablCtrl, _siretCtrl,
      _adresseSearchCtrl, _rueCtrl, _cpCtrl, _villeCtrl,
      _descCtrl, _condCtrl,
    ]) { c.dispose(); }
    _debounce?.cancel();
    _places.dispose();
    super.dispose();
  }

  // ── Google Places ─────────────────────────────────────────────────────────

  void _onAddressChanged(String v) {
    _debounce?.cancel();
    if (v.length < 3) { setState(() => _predictions = []); return; }
    setState(() => _loadingPredictions = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await _places.autocomplete(v,
          components: [Component(Component.country, 'fr')], language: 'fr');
      if (!mounted) return;
      setState(() {
        _predictions = res.isOkay ? res.predictions : [];
        _loadingPredictions = false;
      });
    });
  }

  Future<void> _selectPrediction(Prediction p) async {
    _debounce?.cancel();
    setState(() {
      _predictions = [];
      _adresseSearchCtrl.text = p.description ?? '';
    });
    if (p.placeId == null) return;
    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;
    String num = '', route = '', cp = '', ville = '';
    for (final c in det.result.addressComponents) {
      if (c.types.contains('street_number')) num = c.longName;
      if (c.types.contains('route')) route = c.longName;
      if (c.types.contains('postal_code')) cp = c.longName;
      if (c.types.contains('locality')) ville = c.longName;
      else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) ville = c.longName;
    }
    final loc = det.result.geometry?.location;
    setState(() {
      _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
      _cpCtrl.text    = cp;
      _villeCtrl.text = ville;
      if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
    });
  }

  // ── Sélection image ───────────────────────────────────────────────────────

  Future<File?> _pickImg({int quality = 80}) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: quality);
    return f == null ? null : File(f.path);
  }

  Future<void> _pickDOB() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(1930),
      lastDate: DateTime(now.year - 16),
      locale: const Locale('fr'),
    );
    if (picked != null && mounted) {
      setState(() => _dobCtrl.text =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}');
    }
  }

  // ── Upload Firebase Storage ────────────────────────────────────────────────

  Future<String> _upload(File file, String path) async {
    final ref = FirebaseStorage.instance.ref('restauration_pros/$path');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  // ── Validation par étape ──────────────────────────────────────────────────

  bool _validate(int step) {
    switch (step) {
      case 0:
        if (_prenomCtrl.text.trim().isEmpty || _nomCtrl.text.trim().isEmpty) {
          _err('Prénom et nom requis'); return false;
        }
        if (_dobCtrl.text.trim().isEmpty) { _err('Date de naissance requise'); return false; }
        return true;
      case 1:
        if (!_emailCtrl.text.contains('@')) { _err('Email invalide'); return false; }
        if (_passCtrl.text.length < 6) { _err('Mot de passe : min 6 caractères'); return false; }
        return true;
      case 2:
        if (_nomEtablCtrl.text.trim().isEmpty) { _err('Nom de l\'établissement requis'); return false; }
        if (_siretCtrl.text.trim().length != 14) { _err('SIRET : 14 chiffres'); return false; }
        if (_especesAcceptees.isEmpty) { _err('Sélectionne au moins une espèce acceptée'); return false; }
        return true;
      case 3:
        if (_lat == null) { _err('Sélectionne une adresse dans la liste'); return false; }
        return true;
      case 4:
        return true;
      case 5:
        if (_descCtrl.text.trim().length < 30) { _err('Description : min 30 caractères'); return false; }
        if (!_cguAccepted) { _err('Vous devez accepter les CGU'); return false; }
        return true;
      default:
        return true;
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── Soumission finale ─────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_validate(5)) return;
    setState(() => _saving = true);
    try {
      // 1 — Création compte Firebase
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      final uid = cred.user!.uid;

      // 2 — Upload photos
      String? photoUrl;
      if (_photoProfil != null) {
        photoUrl = await _upload(_photoProfil!, '$uid/profil.jpg');
      }
      String? bannerUrl;
      if (_banner != null) {
        bannerUrl = await _upload(_banner!, '$uid/banniere.jpg');
      }
      final feedUrls = <String>[];
      for (int i = 0; i < _feedPhotos.length; i++) {
        feedUrls.add(await _upload(_feedPhotos[i], '$uid/feed_$i.jpg'));
      }

      // 3 — Firestore users
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'role': 'user',
        'isAdmin': false,
        'verificationStatus': 'pending',
        'firstname': _prenomCtrl.text.trim(),
        'lastname': _nomCtrl.text.trim(),
        'dateofbirth': _dobCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'isElevage': false,
        'isPro': true,
        'catPro': 'restauration',
        'isAssociation': false,
        'isValidate': false,
        'isDev': false,
        'CGU': true,
        'mentionlegal': true,
        if (photoUrl != null) 'profilePictureUrl': photoUrl,
        if (bannerUrl != null) 'bannerUrl': bannerUrl,
      });

      // 4 — Supabase users
      await Supabase.instance.client.from('users').upsert({
        'uid': uid,
        'firstname': _prenomCtrl.text.trim(),
        'lastname': _nomCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'is_elevage': false,
        'is_pro': true,
        'is_association': false,
        'is_validate': false,
        'cat_pro': 'restauration',
        'statut_pro': 'en_attente',
        if (photoUrl != null) 'profile_picture_url': photoUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
        'cgu_accepted_at': DateTime.now().toIso8601String(),
      });

      // 5 — Supabase user_profiles
      await Supabase.instance.client.from('user_profiles').upsert({
        'uid': uid,
        'profile_type': 'restauration',
        'cat_pro': 'restauration',
        'is_main': true,
        'profile_label': _nomEtablCtrl.text.trim(),
        'nom': _nomEtablCtrl.text.trim(),
        'firstname': _prenomCtrl.text.trim(),
        'lastname': _nomCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'siret': _siretCtrl.text.trim(),
        'type_restauration': _typeEtabl,
        'description': _descCtrl.text.trim(),
        'conditions_animaux': _condCtrl.text.trim(),
        'especes_acceptees': _especesAcceptees,
        'adresse_pro': _adresseSearchCtrl.text.trim(),
        'rue_pro': _rueCtrl.text.trim(),
        'cp_pro': _cpCtrl.text.trim(),
        'ville_pro': _villeCtrl.text.trim(),
        if (_lat != null) 'lat_pro': _lat,
        if (_lng != null) 'lng_pro': _lng,
        if (photoUrl != null) 'avatar_url': photoUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
        if (feedUrls.isNotEmpty) 'photos_galerie': feedUrls,
        'verification_status': 'pending',
        'statut_pro': 'en_attente',
        'plan_code': 'free',
      });

      // 6 — Email de vérification
      await cred.user!.sendEmailVerification();

      // 7 — Navigation
      User_Info.uid = uid;
      User_Info.firstname = _prenomCtrl.text.trim();
      User_Info.lastname = _nomCtrl.text.trim();
      User_Info.email = _emailCtrl.text.trim();
      User_Info.isPro = true;
      User_Info.catPro = 'restauration';
      if (photoUrl != null) User_Info.profilePictureUrl = photoUrl;

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VerificationRegistrationPage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _saving = false);
      _err(e.code == 'email-already-in-use'
          ? 'Cet email est déjà utilisé'
          : e.code == 'weak-password'
              ? 'Mot de passe trop faible'
              : 'Erreur : ${e.message}');
    } catch (e) {
      setState(() => _saving = false);
      _err('Erreur : $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(_steps[_step],
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _steps.length,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      ),
      body: [
        _buildStep0,
        _buildStep1,
        _buildStep2,
        _buildStep3,
        _buildStep4,
        _buildStep5,
      ][_step](),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            if (_step > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal,
                    side: const BorderSide(color: _teal),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Précédent'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ElevatedButton(
                onPressed: _saving ? null : () {
                  if (!_validate(_step)) return;
                  if (_step < _steps.length - 1) {
                    setState(() { _step++; _predictions = []; });
                  } else {
                    _submit();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_step < _steps.length - 1 ? 'Suivant →' : 'Créer mon compte',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Étape 0 : Identité ────────────────────────────────────────────────────

  Widget _buildStep0() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title('Informations personnelles',
          'Ces informations concernent le responsable du compte.'),
      const SizedBox(height: 20),
      Center(
        child: GestureDetector(
          onTap: () async {
            final f = await _pickImg();
            if (f != null) setState(() => _photoProfil = f);
          },
          child: CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFFE0F2F1),
            backgroundImage: _photoProfil != null ? FileImage(_photoProfil!) : null,
            child: _photoProfil == null
                ? const Icon(Icons.camera_alt_outlined, size: 32, color: Color(0xFF0C5C6C))
                : null,
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Center(
        child: Text('Photo de profil (optionnel)',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      const SizedBox(height: 20),
      _field(_prenomCtrl, 'Prénom'),
      const SizedBox(height: 12),
      _field(_nomCtrl, 'Nom'),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: _pickDOB,
        child: AbsorbPointer(
          child: _field(_dobCtrl, 'Date de naissance (jj/mm/aaaa)',
              icon: Icons.calendar_today_outlined),
        ),
      ),
    ]);
  }

  // ── Étape 1 : Sécurité ────────────────────────────────────────────────────

  Widget _buildStep1() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title('Sécurité du compte', 'Email et mot de passe pour vous connecter.'),
      const SizedBox(height: 20),
      _field(_emailCtrl, 'Email', keyboard: TextInputType.emailAddress, icon: Icons.email_outlined),
      const SizedBox(height: 12),
      TextField(
        controller: _passCtrl,
        obscureText: !_showPass,
        decoration: _dec('Mot de passe (min 6 caractères)', icon: Icons.lock_outline,
            suffix: IconButton(
              icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
              onPressed: () => setState(() => _showPass = !_showPass),
            )),
      ),
      const SizedBox(height: 12),
      _field(_phoneCtrl, 'Téléphone (optionnel)', keyboard: TextInputType.phone, icon: Icons.phone_outlined),
    ]);
  }

  // ── Étape 2 : Info établissement ──────────────────────────────────────────

  Widget _buildStep2() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title('Votre établissement', 'Informations sur votre activité professionnelle.'),
      const SizedBox(height: 20),
      _field(_nomEtablCtrl, 'Nom de l\'établissement', maxLength: 80),
      const SizedBox(height: 12),
      _field(_siretCtrl, 'SIRET (14 chiffres)', keyboard: TextInputType.number, maxLength: 14),
      const SizedBox(height: 20),
      _sectionLabel('Type d\'établissement'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: _kTypes.map((t) {
          final sel = _typeEtabl == t.$1;
          return FilterChip(
            label: Text('${t.$2} ${t.$3}',
                style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.grey.shade700)),
            selected: sel,
            selectedColor: _teal,
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            showCheckmark: false,
            side: BorderSide(color: sel ? _teal : Colors.grey.shade300),
            onSelected: (_) => setState(() => _typeEtabl = t.$1),
          );
        }).toList(),
      ),
      const SizedBox(height: 20),
      _sectionLabel('Espèces acceptées *'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: _kEspeces.map((e) {
          final sel = _especesAcceptees.contains(e);
          return FilterChip(
            label: Text(e, style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.grey.shade700)),
            selected: sel,
            selectedColor: const Color(0xFF6E9E57),
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            showCheckmark: false,
            side: BorderSide(color: sel ? const Color(0xFF6E9E57) : Colors.grey.shade300),
            onSelected: (_) => setState(() {
              if (sel) _especesAcceptees.remove(e); else _especesAcceptees.add(e);
            }),
          );
        }).toList(),
      ),
    ]);
  }

  // ── Étape 3 : Adresse ────────────────────────────────────────────────────

  Widget _buildStep3() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title('Localisation', 'Adresse exacte de votre établissement.'),
      const SizedBox(height: 20),
      TextField(
        controller: _adresseSearchCtrl,
        onChanged: _onAddressChanged,
        decoration: _dec('Rechercher une adresse...', icon: Icons.search),
      ),
      if (_loadingPredictions)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: SizedBox(height: 16, width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _teal))),
        ),
      if (_predictions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
          ),
          child: Column(
            children: _predictions.map((p) => ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, color: _teal, size: 18),
              title: Text(p.description ?? '', style: const TextStyle(fontSize: 13)),
              onTap: () => _selectPrediction(p),
            )).toList(),
          ),
        ),
      const SizedBox(height: 16),
      if (_lat != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F4F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0C5C6C).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFF0C5C6C), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_rueCtrl.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${_cpCtrl.text} ${_villeCtrl.text}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text('GPS : ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
          ]),
        ),
      ] else ...[
        _field(_rueCtrl, 'Rue'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 2, child: _field(_cpCtrl, 'Code postal')),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _field(_villeCtrl, 'Ville')),
        ]),
      ],
    ]);
  }

  // ── Étape 4 : Photos ──────────────────────────────────────────────────────

  Widget _buildStep4() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title('Photos', 'Bannière et photos pour votre feed (optionnel).'),
      const SizedBox(height: 20),
      _sectionLabel('Bannière'),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () async {
          final f = await _pickImg();
          if (f != null) setState(() => _banner = f);
        },
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(14),
            image: _banner != null
                ? DecorationImage(image: FileImage(_banner!), fit: BoxFit.cover)
                : null,
          ),
          child: _banner == null
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 36, color: Color(0xFF0C5C6C)),
                    SizedBox(height: 4),
                    Text('Ajouter une bannière',
                        style: TextStyle(fontSize: 13, color: Color(0xFF0C5C6C))),
                  ]),
                )
              : null,
        ),
      ),
      const SizedBox(height: 20),
      _sectionLabel('Photos du feed (max 10)'),
      const SizedBox(height: 8),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: [
          ..._feedPhotos.asMap().entries.map((e) => Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(e.value, width: double.infinity, height: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4, right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _feedPhotos.removeAt(e.key)),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          )),
          if (_feedPhotos.length < 10)
            GestureDetector(
              onTap: () async {
                final f = await _pickImg();
                if (f != null) setState(() => _feedPhotos.add(f));
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0C5C6C).withValues(alpha: 0.3)),
                ),
                child: const Center(
                  child: Icon(Icons.add, color: Color(0xFF0C5C6C), size: 28),
                ),
              ),
            ),
        ],
      ),
    ]);
  }

  // ── Étape 5 : Description & CGU ──────────────────────────────────────────

  Widget _buildStep5() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title('Description & Finalisation',
          'Décrivez votre établissement et acceptez nos conditions.'),
      const SizedBox(height: 20),
      TextField(
        controller: _descCtrl,
        maxLines: 4,
        maxLength: 600,
        decoration: _dec('Description de votre établissement (min 30 caractères)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _condCtrl,
        maxLines: 3,
        decoration: _dec('Conditions pour les animaux (ex: laisse obligatoire, taille max...)'),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Validation admin requise',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Votre profil sera examiné par notre équipe sous 48h. '
              'Vous recevrez un email de confirmation.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Checkbox(
          value: _cguAccepted,
          onChanged: (v) => setState(() => _cguAccepted = v ?? false),
          activeColor: _teal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        const Expanded(
          child: Text('J\'accepte les Conditions Générales d\'Utilisation de PetsMatch',
              style: TextStyle(fontSize: 13)),
        ),
      ]),
    ]);
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────

  Widget _title(String t, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 4),
      Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontFamily: 'Galey')),
    ],
  );

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E)));

  InputDecoration _dec(String hint, {IconData? icon, Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
    filled: true,
    fillColor: Colors.white,
    prefixIcon: icon != null ? Icon(icon, color: _teal, size: 20) : null,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
  );

  Widget _field(TextEditingController c, String hint, {
    TextInputType keyboard = TextInputType.text,
    IconData? icon,
    int? maxLength,
  }) => TextField(
    controller: c,
    keyboardType: keyboard,
    maxLength: maxLength,
    decoration: _dec(hint, icon: icon),
  );
}
