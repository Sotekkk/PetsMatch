import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/services/profile_service.dart';

// ── Types de profil ────────────────────────────────────────────────────────────

class _ProfileTypeInfo {
  final String type;
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  const _ProfileTypeInfo({required this.type, required this.icon,
      required this.label, required this.description, required this.color});
}

const _profileTypes = [
  _ProfileTypeInfo(type: 'particulier', icon: Icons.person_outline, label: 'Particulier',
      description: 'Propriétaire d\'animaux de compagnie', color: Color(0xFF5B9EAA)),
  _ProfileTypeInfo(type: 'eleveur', icon: Icons.pets, label: 'Éleveur',
      description: 'Élevage professionnel, reproduction', color: Color(0xFF6E9E57)),
  _ProfileTypeInfo(type: 'association', icon: Icons.favorite_outline, label: 'Association',
      description: 'Refuge, SPA, association de protection animale', color: Color(0xFF0C5C6C)),
  _ProfileTypeInfo(type: 'restauration', icon: Icons.restaurant_outlined, label: 'Hébergement / Restauration',
      description: 'Hôtel, restaurant, café, gîte ou camping pet-friendly', color: Color(0xFFFFA726)),
  _ProfileTypeInfo(type: 'veterinaire', icon: Icons.local_hospital_outlined, label: 'Vétérinaire',
      description: 'Clinique vétérinaire, soins médicaux', color: Color(0xFFE57373)),
  _ProfileTypeInfo(type: 'sante', icon: Icons.self_improvement_outlined, label: 'Santé',
      description: 'Ostéo, kiné, acupuncteur, naturopathe…', color: Color(0xFFBA68C8)),
  _ProfileTypeInfo(type: 'education', icon: Icons.psychology_outlined, label: 'Éducation',
      description: 'Éducateur, comportementaliste, dresseur', color: Color(0xFFFF8A65)),
  _ProfileTypeInfo(type: 'garde', icon: Icons.home_outlined, label: 'Garde',
      description: 'Pet sitter à domicile, promeneur', color: Color(0xFF4DB6AC)),
  _ProfileTypeInfo(type: 'pension', icon: Icons.hotel_outlined, label: 'Pension',
      description: 'Hébergement temporaire, pensionnat', color: Color(0xFF64B5F6)),
  _ProfileTypeInfo(type: 'toilettage', icon: Icons.content_cut, label: 'Toilettage',
      description: 'Salon de toilettage, bain-brush', color: Color(0xFFFFB74D)),
  _ProfileTypeInfo(type: 'photographe', icon: Icons.camera_alt_outlined, label: 'Photographe',
      description: 'Photographe animalier spécialisé', color: Color(0xFF90A4AE)),
  _ProfileTypeInfo(type: 'marechal_ferrant', icon: Icons.handyman_outlined, label: 'Maréchal-ferrant',
      description: 'Soins des sabots, ferrure équine', color: Color(0xFF8D6E63)),
];

const _subProfessions = <String, List<String>>{
  'sante':          ['Ostéopathe', 'Chiropracteur', 'Kinésithérapeute', 'Naturopathe', 'Acupuncteur', 'Maréchal-ferrant'],
  'education':      ['Éducateur canin', 'Comportementaliste', 'Dresseur'],
  'garde':          ['Pet sitter', 'Promeneur de chiens'],
  'photographe':    ['Photographe animalier', 'Photographe équin', 'Photographe de studio'],
  'marechal_ferrant': ['Maréchal-ferrant traditionnel', 'Parage naturel'],
};

const _especes = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'NAC'];

// ── Page principale ─────────────────────────────────────────────────────────────

class AddProfilePage extends StatefulWidget {
  const AddProfilePage({super.key});
  @override
  State<AddProfilePage> createState() => _AddProfilePageState();
}

class _AddProfilePageState extends State<AddProfilePage> {
  static const _teal = Color(0xFF0C5C6C);
  int _step = 0;
  _ProfileTypeInfo? _selectedType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(
          _step == 0 ? 'Ajouter un profil' : _selectedType!.label,
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
        ),
        leading: BackButton(onPressed: () {
          if (_step == 1) setState(() => _step = 0);
          else Navigator.pop(context);
        }),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _step == 0
            ? _TypePickerStep(key: const ValueKey('step0'),
                onSelect: (t) => setState(() { _selectedType = t; _step = 1; }))
            : _ProfileFormStep(key: ValueKey('step1_${_selectedType!.type}'),
                typeInfo: _selectedType!,
                onSaved: () => Navigator.pop(context, true)),
      ),
    );
  }
}

// ── Étape 1 : Choix du type ─────────────────────────────────────────────────────

class _TypePickerStep extends StatelessWidget {
  final void Function(_ProfileTypeInfo) onSelect;
  const _TypePickerStep({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quel type de profil souhaitez-vous ajouter ?',
              style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Chaque profil a sa propre adresse, ses coordonnées et ses informations professionnelles.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.95),
            itemCount: _profileTypes.length,
            itemBuilder: (_, i) {
              final t = _profileTypes[i];
              return GestureDetector(
                onTap: () => onSelect(t),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: t.color.withOpacity(0.12), shape: BoxShape.circle),
                      child: Icon(t.icon, color: t.color, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text(t.label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(t.description, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Étape 2 : Formulaire avec Maps ─────────────────────────────────────────────

class _ProfileFormStep extends StatefulWidget {
  final _ProfileTypeInfo typeInfo;
  final VoidCallback onSaved;
  const _ProfileFormStep({super.key, required this.typeInfo, required this.onSaved});
  @override
  State<_ProfileFormStep> createState() => _ProfileFormStepState();
}

class _ProfileFormStepState extends State<_ProfileFormStep> {
  static const _green = Color(0xFF6E9E57);
  static const _teal  = Color(0xFF0C5C6C);

  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // Champs communs
  final _labelCtrl      = TextEditingController();
  final _nomCtrl        = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _descCtrl       = TextEditingController();
  final _siretCtrl      = TextEditingController();
  final _siteCtrl       = TextEditingController();

  // Adresse (remplis par Maps ou manuellement)
  final _addressSearchCtrl = TextEditingController();
  final _rueCtrl           = TextEditingController();
  final _villeCtrl         = TextEditingController();
  final _cpCtrl            = TextEditingController();
  final _paysCtrl          = TextEditingController(text: 'France');
  double? _lat;
  double? _lng;

  // Maps
  late final GoogleMapsPlaces _places;
  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  bool _locating = false;
  Timer? _searchDebounce;

  // Éleveur
  final _numElevageCtrl = TextEditingController();
  final _acacedCtrl     = TextEditingController();

  // Pro
  String? _subProfession;
  int _rayon = 20;
  final Set<String> _especesAcceptees = {};
  final Set<String> _especesElevees   = {};

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _phoneCtrl.text = User_Info.phone_number == '0000000000' ? '' : User_Info.phone_number;
    if (widget.typeInfo.type == 'particulier') {
      _nomCtrl.text = '${User_Info.firstname} ${User_Info.lastname}'.trim();
    }
    _labelCtrl.text = switch (widget.typeInfo.type) {
      'particulier'      => '${User_Info.firstname} ${User_Info.lastname}'.trim(),
      'eleveur'          => 'Mon élevage',
      'association'      => 'Mon association',
      'restauration'     => 'Mon établissement',
      'veterinaire'      => 'Mon cabinet vétérinaire',
      'sante'            => 'Mon cabinet',
      'education'        => 'Mon activité éducation',
      'garde'            => 'Mon activité garde',
      'pension'          => 'Ma pension',
      'toilettage'       => 'Mon salon',
      'photographe'      => 'Mon activité photo',
      'marechal_ferrant' => 'Mon activité maréchalerie',
      _                  => 'Mon profil',
    };
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _places.dispose();
    for (final c in [_labelCtrl, _nomCtrl, _phoneCtrl, _descCtrl, _siretCtrl, _siteCtrl,
        _addressSearchCtrl, _rueCtrl, _villeCtrl, _cpCtrl, _paysCtrl,
        _numElevageCtrl, _acacedCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Maps autocomplete ────────────────────────────────────────────────────────

  void _onAddressChanged(String val) {
    _searchDebounce?.cancel();
    if (val.length < 3) {
      setState(() { _predictions = []; _loadingPredictions = false; });
      return;
    }
    setState(() => _loadingPredictions = true);
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _fetchPredictions(val));
  }

  Future<void> _fetchPredictions(String input) async {
    final res = await _places.autocomplete(
      input,
      components: [Component(Component.country, 'fr')],
      language: 'fr',
    );
    if (!mounted) return;
    setState(() {
      _predictions = res.isOkay ? res.predictions : [];
      _loadingPredictions = false;
    });
  }

  Future<void> _selectPrediction(Prediction p) async {
    _searchDebounce?.cancel();
    setState(() { _predictions = []; _addressSearchCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;
    String num = '', route = '', cp = '', ville = '', pays = 'France';
    for (final c in det.result.addressComponents) {
      if (c.types.contains('street_number')) num = c.longName;
      if (c.types.contains('route')) route = c.longName;
      if (c.types.contains('postal_code')) cp = c.longName;
      if (c.types.contains('locality')) { ville = c.longName; }
      else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) { ville = c.longName; }
      if (c.types.contains('country')) pays = c.longName;
    }
    final loc = det.result.geometry?.location;
    setState(() {
      _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
      _cpCtrl.text    = cp;
      _villeCtrl.text = ville;
      _paysCtrl.text  = pays;
      if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
    });
  }

  Future<void> _geolocate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return;
      final m = marks.first;
      setState(() {
        _rueCtrl.text   = m.street ?? '';
        _cpCtrl.text    = m.postalCode ?? '';
        _villeCtrl.text = m.locality ?? m.subLocality ?? '';
        _paysCtrl.text  = m.country ?? 'France';
        _lat = pos.latitude;
        _lng = pos.longitude;
        _addressSearchCtrl.text = [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text]
            .where((s) => s.isNotEmpty).join(', ');
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Sauvegarde ────────────────────────────────────────────────────────────────

  bool get _isProType => const {
    'veterinaire', 'sante', 'education', 'garde', 'pension', 'toilettage',
    'photographe', 'marechal_ferrant', 'restauration',
  }.contains(widget.typeInfo.type);
  bool get _isEleveurType => widget.typeInfo.type == 'eleveur';
  bool get _isAssociationType => widget.typeInfo.type == 'association';
  bool get _isParticulierType => widget.typeInfo.type == 'particulier';
  bool get _isRestauration => widget.typeInfo.type == 'restauration';
  bool get _hasSiret => const {
    'veterinaire', 'sante', 'education', 'pension', 'toilettage',
    'photographe', 'marechal_ferrant', 'restauration',
  }.contains(widget.typeInfo.type);
  bool get _hasRayon => const {
    'veterinaire', 'sante', 'education', 'garde', 'toilettage',
    'photographe', 'marechal_ferrant',
  }.contains(widget.typeInfo.type); // restauration = lieu fixe, pas de rayon
  bool get _hasSubProfession => _subProfessions.containsKey(widget.typeInfo.type);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final type = widget.typeInfo.type;
    final data = <String, dynamic>{
      'uid': uid,
      'profile_type': type,
      'profile_label': _labelCtrl.text.trim().isNotEmpty ? _labelCtrl.text.trim() : widget.typeInfo.label,
      'phone':       _phoneCtrl.text.trim(),
      'adresse':     _addressSearchCtrl.text.trim(),
      'rue':         _rueCtrl.text.trim(),
      'ville':       _villeCtrl.text.trim(),
      'code_postal': _cpCtrl.text.trim(),
      'pays':        _paysCtrl.text.trim().isNotEmpty ? _paysCtrl.text.trim() : 'France',
      'description': _descCtrl.text.trim(),
      'site_web':    _siteCtrl.text.trim(),
    };
    // Filet de sécurité : si l'utilisateur a tapé une adresse sans jamais
    // sélectionner une suggestion (ou géolocalisé), _lat/_lng restent nuls
    // et le profil pro devient invisible sur la carte des professionnels.
    if ((_lat == null || _lng == null) && _addressSearchCtrl.text.trim().isNotEmpty) {
      try {
        final locs = await geo.locationFromAddress(_addressSearchCtrl.text.trim());
        if (locs.isNotEmpty) { _lat = locs.first.latitude; _lng = locs.first.longitude; }
      } catch (_) {}
    }
    if (_lat != null) data['latitude']  = _lat;
    if (_lng != null) data['longitude'] = _lng;
    if (_lat != null) data['lat']       = _lat;
    if (_lng != null) data['lng']       = _lng;

    if (_isParticulierType) {
      data['firstname'] = User_Info.firstname;
      data['lastname']  = User_Info.lastname;
    }
    if (_isAssociationType) {
      data['nom'] = _nomCtrl.text.trim();
    }
    if (_isEleveurType) {
      data['nom']             = _nomCtrl.text.trim();
      data['numero_elevage']  = _numElevageCtrl.text.trim();
      data['is_elevage']      = true;
      data['acaced_numero']   = _acacedCtrl.text.trim();
      data['especes_elevees'] = _especesElevees.toList();
    }
    if (_isProType) {
      data['cat_pro']            = type;
      data['nom']                = _nomCtrl.text.trim();
      data['profession_pro']     = _subProfession ?? widget.typeInfo.label;
      data['siret']              = _siretCtrl.text.trim();
      data['rayon_intervention'] = _rayon;
      data['especes_acceptees']  = _especesAcceptees.toList();
      if (type == 'education' || type == 'garde') {
        data['acaced_numero'] = _acacedCtrl.text.trim();
      }
    }
    if (_isRestauration) {
      // Champs spécifiques attendus par RestaurationHomePage
      data['adresse_pro'] = _addressSearchCtrl.text.trim();
      data['rue_pro']     = _rueCtrl.text.trim();
      data['cp_pro']      = _cpCtrl.text.trim();
      data['ville_pro']   = _villeCtrl.text.trim();
      if (_lat != null) data['lat_pro'] = _lat;
      if (_lng != null) data['lng_pro'] = _lng;
      data['verification_status'] = 'pending';
      data['statut_pro']          = 'en_attente';
    }

    try {
      await ProfileService.upsertProfile(data);
      if (!mounted) return;
      if (type == 'restauration') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profil créé ! En attente de validation par notre équipe.',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
          duration: Duration(seconds: 4),
        ));
        Navigator.pop(context, true);
      } else {
        final rows = await ProfileService.loadProfiles(uid);
        final created = rows.firstWhere((r) => r['profile_type'] == type, orElse: () => data);
        User_Info.applyProfile(created);
        if (mounted) {
          widget.onSaved();
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => BottomNav()), (_) => false);
        }
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('Nom du profil'),
          _field(_labelCtrl, 'Libellé affiché dans le sélecteur', required: true),

          if (!_isParticulierType) ...[
            const SizedBox(height: 12),
            _section(_isEleveurType
                ? 'Nom de l\'élevage'
                : _isAssociationType
                    ? 'Nom de l\'association'
                    : _isRestauration
                        ? 'Nom de l\'établissement'
                        : 'Nom du cabinet / établissement'),
            _field(_nomCtrl,
                _isEleveurType
                    ? 'Ex : Élevage du Moulin'
                    : _isAssociationType
                        ? 'Ex : SPA de Lyon, Refuge du Soleil…'
                        : _isRestauration
                            ? 'Ex : Hôtel Le Charme, Café des Animaux…'
                            : 'Ex : Cabinet Dupont',
                required: _isEleveurType || _isProType || _isAssociationType),
          ],

          if (_hasSubProfession) ...[
            const SizedBox(height: 12),
            _section('Profession'),
            _dropdownProfession(),
          ],

          const SizedBox(height: 16),
          _section('Adresse professionnelle'),
          _addressBlock(),

          const SizedBox(height: 16),
          _section(_isParticulierType ? 'Téléphone' : 'Téléphone professionnel'),
          _field(_phoneCtrl, 'Ex : 06 12 34 56 78',
              required: _isParticulierType),

          if (_isEleveurType) ...[
            const SizedBox(height: 16),
            _section('Numéro d\'élevage'),
            _field(_numElevageCtrl, 'Numéro SIREN/DDPP', required: true),
            const SizedBox(height: 8),
            _section('Numéro ACACED (facultatif)'),
            _field(_acacedCtrl, 'Ex : ACE-2023-XXXX'),
            const SizedBox(height: 16),
            _section('Espèces élevées'),
            _especesChips(_especesElevees),
          ],

          if (_isProType) ...[
            if (_hasSiret) ...[
              const SizedBox(height: 16),
              _section('SIRET'),
              _field(_siretCtrl, '14 chiffres'),
            ],
            if (widget.typeInfo.type == 'education' || widget.typeInfo.type == 'garde') ...[
              const SizedBox(height: 16),
              _section('Numéro ACACED *'),
              _field(_acacedCtrl, 'Ex : 2022/9fd5-fd12', required: true),
            ],
            if (_hasRayon) ...[
              const SizedBox(height: 16),
              _section('Rayon d\'intervention : $_rayon km'),
              Slider(value: _rayon.toDouble(), min: 5, max: 100, divisions: 19,
                  activeColor: _green,
                  onChanged: (v) => setState(() => _rayon = v.round())),
            ],
            const SizedBox(height: 8),
            _section('Espèces acceptées'),
            _especesChips(_especesAcceptees),
          ],

          const SizedBox(height: 16),
          _section('Description (facultatif)'),
          _field(_descCtrl, 'Présentation, spécialités…', maxLines: 4),

          const SizedBox(height: 16),
          _section('Site web (facultatif)'),
          _field(_siteCtrl, 'https://…'),

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _green, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Créer le profil',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Bloc adresse avec Maps ────────────────────────────────────────────────────

  Widget _addressBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _addressSearchCtrl,
              onChanged: _onAddressChanged,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher une adresse…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                prefixIcon: _loadingPredictions
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6E9E57))))
                    : const Icon(Icons.search, color: Colors.grey),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 48, height: 48,
            child: Material(
              color: const Color(0xFFEEF5EA),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _locating ? null : _geolocate,
                child: _locating
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6E9E57)))
                    : const Icon(Icons.my_location, color: _teal, size: 22),
              ),
            ),
          ),
        ]),

        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _predictions.length > 4 ? 4 : _predictions.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (_, i) => ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined, color: _teal, size: 18),
                title: Text(_predictions[i].description ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                onTap: () => _selectPrediction(_predictions[i]),
              ),
            ),
          ),

        const SizedBox(height: 10),
        _field(_rueCtrl, 'Rue / numéro'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 2, child: _field(_villeCtrl, 'Ville', required: true)),
          const SizedBox(width: 8),
          Expanded(child: _field(_cpCtrl, 'Code postal',
              required: _isProType || _isEleveurType)),
        ]),
        const SizedBox(height: 8),
        _field(_paysCtrl, 'Pays'),
      ],
    );
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────────

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(label, style: const TextStyle(
      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
  );

  Widget _field(TextEditingController ctrl, String hint,
      {bool required = false, int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _green, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null : null,
    );
  }

  Widget _dropdownProfession() {
    final options = _subProfessions[widget.typeInfo.type] ?? [];
    return DropdownButtonFormField<String>(
      value: _subProfession,
      hint: const Text('Choisir…', style: TextStyle(fontFamily: 'Galey')),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
      decoration: InputDecoration(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _green, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: options.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: (v) => setState(() => _subProfession = v),
    );
  }

  Widget _especesChips(Set<String> selected) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _especes.map((e) {
        final isSelected = selected.contains(e);
        return FilterChip(
          label: Text(e, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          selected: isSelected,
          selectedColor: const Color(0xFFDCEDD5),
          checkmarkColor: _green,
          backgroundColor: Colors.white,
          side: BorderSide(color: isSelected ? _green : Colors.grey.shade300),
          onSelected: (_) => setState(() {
            if (isSelected) selected.remove(e); else selected.add(e);
          }),
        );
      }).toList(),
    );
  }
}
