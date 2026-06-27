import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/utils.dart';

// ── Page de complétion / édition du profil restauration ─────────────────────
// Accessible depuis le dashboard quand verification_status == 'none'
// ou depuis le menu "Mon profil"

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

class InscriptionRestaurationDetailPage extends StatefulWidget {
  const InscriptionRestaurationDetailPage({super.key});

  @override
  State<InscriptionRestaurationDetailPage> createState() =>
      _InscriptionRestaurationDetailPageState();
}

class _InscriptionRestaurationDetailPageState
    extends State<InscriptionRestaurationDetailPage> {
  static const _teal = Color(0xFF0C5C6C);

  bool _loading = true;
  bool _saving  = false;
  int  _step    = 0;

  String? _existingProfileId;
  String  _existingVerifStatus = 'none';

  // Infos établissement
  final _nomCtrl    = TextEditingController();
  final _siretCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _condCtrl   = TextEditingController();
  String _typeEtabl = 'restaurant';
  final List<String> _especesAcceptees = [];

  // Adresse
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

  // Photos
  File?   _newPhotoProfil;
  File?   _newBanner;
  final List<File>   _newFeedPhotos  = [];
  String? _existingProfil;
  String? _existingBanner;
  List<String> _existingFeed = [];

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _loadProfile();
  }

  @override
  void dispose() {
    for (final c in [_nomCtrl, _siretCtrl, _descCtrl, _condCtrl,
        _adresseSearchCtrl, _rueCtrl, _cpCtrl, _villeCtrl]) {
      c.dispose();
    }
    _debounce?.cancel();
    _places.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .eq('uid', uid)
          .eq('cat_pro', 'restauration')
          .maybeSingle();
      if (res != null) {
        _existingProfileId    = res['id']?.toString();
        _existingVerifStatus  = res['verification_status']?.toString() ?? 'none';
        _nomCtrl.text         = res['nom']?.toString() ?? '';
        _siretCtrl.text       = res['siret']?.toString() ?? '';
        _descCtrl.text        = res['description']?.toString() ?? '';
        _condCtrl.text        = res['conditions_animaux']?.toString() ?? '';
        _typeEtabl            = res['type_restauration']?.toString() ?? 'restaurant';
        final esp = res['especes_acceptees'];
        if (esp is List) _especesAcceptees.addAll(esp.cast<String>());
        _adresseSearchCtrl.text = res['adresse_pro']?.toString() ?? '';
        _rueCtrl.text           = res['rue_pro']?.toString() ?? '';
        _cpCtrl.text            = res['cp_pro']?.toString() ?? '';
        _villeCtrl.text         = res['ville_pro']?.toString() ?? '';
        _lat                    = (res['lat_pro'] as num?)?.toDouble();
        _lng                    = (res['lng_pro'] as num?)?.toDouble();
        _existingProfil         = res['avatar_url']?.toString();
        _existingBanner         = res['banner_url']?.toString();
        final feed = res['photos_galerie'];
        if (feed is List) _existingFeed = feed.cast<String>();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Places API ────────────────────────────────────────────────────────────

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
    setState(() { _predictions = []; _adresseSearchCtrl.text = p.description ?? ''; });
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

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<String> _upload(File f, String path) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseStorage.instance.ref('restauration_pros/$uid/$path');
    await ref.putFile(f);
    return await ref.getDownloadURL();
  }

  Future<File?> _pickImg() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    return f == null ? null : File(f.path);
  }

  // ── Sauvegarde ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) { _err('Nom requis'); return; }
    if (_lat == null && _rueCtrl.text.trim().isEmpty) { _err('Adresse requise'); return; }
    if (_descCtrl.text.trim().length < 20) { _err('Description trop courte (min 20 caractères)'); return; }
    setState(() => _saving = true);

    try {
      // Upload nouvelles photos
      String? profilUrl = _existingProfil;
      if (_newPhotoProfil != null) profilUrl = await _upload(_newPhotoProfil!, 'profil.jpg');

      String? bannerUrl = _existingBanner;
      if (_newBanner != null) bannerUrl = await _upload(_newBanner!, 'banniere.jpg');

      final feedUrls = List<String>.from(_existingFeed);
      for (int i = 0; i < _newFeedPhotos.length; i++) {
        feedUrls.add(await _upload(_newFeedPhotos[i], 'feed_${feedUrls.length}_$i.jpg'));
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final alreadyPending = _existingVerifStatus == 'pending' || _existingVerifStatus == 'approved';

      final payload = <String, dynamic>{
        'uid': uid,
        'profile_type': 'restauration',
        'cat_pro': 'restauration',
        'is_main': true,
        'profile_label': _nomCtrl.text.trim(),
        'nom': _nomCtrl.text.trim(),
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
        if (profilUrl != null) 'avatar_url': profilUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
        'photos_galerie': feedUrls,
        // Si c'est la 1ère soumission → pending, sinon on ne change pas le statut
        if (!alreadyPending) 'verification_status': 'pending',
        if (!alreadyPending) 'statut_pro': 'en_attente',
        'plan_code': 'free',
      };

      if (_existingProfileId != null) {
        await Supabase.instance.client
            .from('user_profiles')
            .update(payload)
            .eq('id', _existingProfileId!);
      } else {
        payload['plan_code'] = 'free';
        await Supabase.instance.client.from('user_profiles').insert(payload);
      }

      // Mise à jour User_Info en mémoire
      if (profilUrl != null) User_Info.profilePictureUrl = profilUrl;
      if (bannerUrl != null) User_Info.bannerUrl = bannerUrl;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profil enregistré ✅ — En attente de validation'),
        backgroundColor: Color(0xFF0C5C6C),
      ));
      Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      _err('Erreur : $e');
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F8F6),
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mon profil établissement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 4,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      ),
      body: [_buildStep0, _buildStep1, _buildStep2, _buildStep3][_step](),
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
                  if (_step < 3) { setState(() { _step++; _predictions = []; }); }
                  else { _save(); }
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
                    : Text(_step < 3 ? 'Suivant →' : 'Enregistrer',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Étape 0 : Infos établissement ─────────────────────────────────────────

  Widget _buildStep0() => ListView(padding: const EdgeInsets.all(16), children: [
    _title('Informations', 'Décrivez votre établissement.'),
    const SizedBox(height: 20),
    _field(_nomCtrl, 'Nom de l\'établissement *', maxLength: 80),
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
    _sectionLabel('Espèces acceptées'),
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
    const SizedBox(height: 20),
    _sectionLabel('Description *'),
    const SizedBox(height: 8),
    TextField(
      controller: _descCtrl,
      maxLines: 4,
      maxLength: 600,
      decoration: _dec('Décrivez votre établissement, vos engagements pet-friendly...'),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _condCtrl,
      maxLines: 3,
      decoration: _dec('Conditions animaux (laisse obligatoire, races acceptées, taille...)'),
    ),
  ]);

  // ── Étape 1 : Adresse ────────────────────────────────────────────────────

  Widget _buildStep1() => ListView(padding: const EdgeInsets.all(16), children: [
    _title('Localisation', 'Adresse de votre établissement.'),
    const SizedBox(height: 20),
    TextField(
      controller: _adresseSearchCtrl,
      onChanged: _onAddressChanged,
      decoration: _dec('Rechercher votre adresse...', icon: Icons.search),
    ),
    if (_loadingPredictions)
      const Padding(padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: SizedBox(height: 16, width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _teal)))),
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
    if (_lat != null)
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _teal.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle, color: _teal, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_rueCtrl.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('${_cpCtrl.text} ${_villeCtrl.text}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            Text('GPS : ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ])),
        ]),
      )
    else ...[
      _field(_rueCtrl, 'Rue'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(flex: 2, child: _field(_cpCtrl, 'Code postal')),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _field(_villeCtrl, 'Ville')),
      ]),
    ],
  ]);

  // ── Étape 2 : Photos ──────────────────────────────────────────────────────

  Widget _buildStep2() => ListView(padding: const EdgeInsets.all(16), children: [
    _title('Photos', 'Ajoutez une photo de profil, une bannière et des photos pour le feed.'),
    const SizedBox(height: 20),
    _sectionLabel('Photo de profil'),
    const SizedBox(height: 8),
    GestureDetector(
      onTap: () async {
        final f = await _pickImg();
        if (f != null) setState(() => _newPhotoProfil = f);
      },
      child: Center(
        child: CircleAvatar(
          radius: 50,
          backgroundColor: const Color(0xFFE0F2F1),
          backgroundImage: _newPhotoProfil != null
              ? FileImage(_newPhotoProfil!)
              : _existingProfil != null
                  ? CachedNetworkImageProvider(_existingProfil!) as ImageProvider
                  : null,
          child: (_newPhotoProfil == null && _existingProfil == null)
              ? const Icon(Icons.camera_alt_outlined, size: 32, color: _teal)
              : null,
        ),
      ),
    ),
    const SizedBox(height: 20),
    _sectionLabel('Bannière'),
    const SizedBox(height: 8),
    GestureDetector(
      onTap: () async {
        final f = await _pickImg();
        if (f != null) setState(() => _newBanner = f);
      },
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2F1),
          borderRadius: BorderRadius.circular(14),
          image: _newBanner != null
              ? DecorationImage(image: FileImage(_newBanner!), fit: BoxFit.cover)
              : _existingBanner != null
                  ? DecorationImage(image: CachedNetworkImageProvider(_existingBanner!), fit: BoxFit.cover)
                  : null,
        ),
        child: (_newBanner == null && _existingBanner == null)
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 36, color: _teal),
                  SizedBox(height: 4),
                  Text('Ajouter une bannière', style: TextStyle(fontSize: 13, color: _teal)),
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
        ..._existingFeed.asMap().entries.map((e) => Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(imageUrl: e.value,
                    width: double.infinity, height: double.infinity, fit: BoxFit.cover)),
            Positioned(top: 4, right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _existingFeed.removeAt(e.key)),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              )),
          ],
        )),
        ..._newFeedPhotos.asMap().entries.map((e) => Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10),
                child: Image.file(e.value, width: double.infinity, height: double.infinity, fit: BoxFit.cover)),
            Positioned(top: 4, right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _newFeedPhotos.removeAt(e.key)),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              )),
          ],
        )),
        if (_existingFeed.length + _newFeedPhotos.length < 10)
          GestureDetector(
            onTap: () async {
              final f = await _pickImg();
              if (f != null) setState(() => _newFeedPhotos.add(f));
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _teal.withValues(alpha: 0.3)),
              ),
              child: const Center(child: Icon(Icons.add, color: _teal, size: 28)),
            ),
          ),
      ],
    ),
  ]);

  // ── Étape 3 : Récap & validation ─────────────────────────────────────────

  Widget _buildStep3() => ListView(padding: const EdgeInsets.all(16), children: [
    _title('Récapitulatif', 'Vérifiez vos informations avant de soumettre.'),
    const SizedBox(height: 20),
    _recapRow(Icons.storefront_outlined, 'Nom', _nomCtrl.text.isNotEmpty ? _nomCtrl.text : '—'),
    _recapRow(Icons.business_outlined, 'SIRET', _siretCtrl.text.isNotEmpty ? _siretCtrl.text : '—'),
    _recapRow(Icons.restaurant_menu_outlined, 'Type', _typeEtabl),
    _recapRow(Icons.place_outlined, 'Ville', _villeCtrl.text.isNotEmpty ? _villeCtrl.text : '—'),
    _recapRow(Icons.pets, 'Espèces', _especesAcceptees.isNotEmpty ? _especesAcceptees.join(', ') : '—'),
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
        Text('Votre dossier sera examiné par l\'équipe PetsMatch.\n'
            'Un algorithme vérifie automatiquement votre SIRET via l\'annuaire des entreprises.\n'
            'Vous recevrez un email sous 48h.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4)),
      ]),
    ),
  ]);

  Widget _recapRow(IconData icon, String label, String val) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      Icon(icon, color: _teal, size: 18),
      const SizedBox(width: 10),
      Text('$label : ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
    ]),
  );

  // ── Helpers UI ────────────────────────────────────────────────────────────

  Widget _title(String t, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 4),
      Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
    ],
  );

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E)));

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
    filled: true,
    fillColor: Colors.white,
    prefixIcon: icon != null ? Icon(icon, color: _teal, size: 20) : null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
  );

  Widget _field(TextEditingController c, String hint, {
    TextInputType keyboard = TextInputType.text, int? maxLength,
  }) => TextField(
    controller: c,
    keyboardType: keyboard,
    maxLength: maxLength,
    decoration: _dec(hint),
  );
}
