import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';

class InscriptionLieuPage extends StatefulWidget {
  const InscriptionLieuPage({super.key});

  @override
  State<InscriptionLieuPage> createState() => _InscriptionLieuPageState();
}

class _InscriptionLieuPageState extends State<InscriptionLieuPage> {
  static const _teal = Color(0xFF0C5C6C);

  int _step = 0;
  bool _saving = false;

  // ── Étape 1 — Identité ──
  final _nomCtrl     = TextEditingController();
  final _siretCtrl   = TextEditingController();
  String _categorie  = 'hebergement';
  String _sousCategorie = 'hotel';
  final _adresseSearchCtrl = TextEditingController();
  final _rueCtrl  = TextEditingController();
  final _cpCtrl   = TextEditingController();
  final _villeCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  Timer? _debounce;
  late final GoogleMapsPlaces _places;

  // ── Étape 2 — Profil ──
  final _descCtrl = TextEditingController();
  File? _logoPick;
  File? _bannierePick;
  final List<File> _photosPick = [];

  // Horaires : 3 maps distinctes
  final Map<String, bool> _horairesFerme = {
    'lundi': false, 'mardi': false, 'mercredi': false, 'jeudi': false,
    'vendredi': false, 'samedi': false, 'dimanche': false,
  };
  final Map<String, String> _horairesDebut = {
    'lundi': '08:00', 'mardi': '08:00', 'mercredi': '08:00', 'jeudi': '08:00',
    'vendredi': '08:00', 'samedi': '09:00', 'dimanche': '09:00',
  };
  final Map<String, String> _horairesFin = {
    'lundi': '20:00', 'mardi': '20:00', 'mercredi': '20:00', 'jeudi': '20:00',
    'vendredi': '20:00', 'samedi': '18:00', 'dimanche': '18:00',
  };

  // ── Étape 3 — Détails & Contact ──
  final List<String> _especesChoisies = [];
  final _telCtrl   = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _siteCtrl  = TextEditingController();
  // Hébergement
  bool _animauxChambre  = true;
  int  _fraisNuit       = 0;
  int  _nbAnimauxMax    = 2;
  bool _espaceDetente   = false;
  int  _prixNuitDefaut  = 0;
  // Restauration
  bool _terrasse        = true;
  bool _animauxSalle    = false;
  bool _eauFournie      = false;
  bool _friandises      = false;
  bool _petMenu         = false;

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    _places.dispose();
    _debounce?.cancel();
    for (final c in [_nomCtrl, _siretCtrl, _adresseSearchCtrl, _rueCtrl,
        _cpCtrl, _villeCtrl, _descCtrl, _telCtrl, _emailCtrl, _siteCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Google Places ────────────────────────────────────────────────────────

  void _onAddressChanged(String v) {
    _debounce?.cancel();
    if (v.length < 3) { setState(() => _predictions = []); return; }
    setState(() => _loadingPredictions = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await _places.autocomplete(v,
          components: [Component(Component.country, 'fr')], language: 'fr');
      if (!mounted) return;
      setState(() { _predictions = res.isOkay ? res.predictions : []; _loadingPredictions = false; });
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

  // ─── Upload photos ─────────────────────────────────────────────────────────

  Future<File?> _pickImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    return f == null ? null : File(f.path);
  }

  Future<void> _pickTime(String day, bool isStart) async {
    final str = isStart ? (_horairesDebut[day] ?? '08:00') : (_horairesFin[day] ?? '20:00');
    final parts = str.split(':');
    final h = int.tryParse(parts[0]) ?? 8;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      final s = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) _horairesDebut[day] = s;
        else _horairesFin[day] = s;
      });
    }
  }

  Future<String> _upload(File file, String path) async {
    final ref = FirebaseStorage.instance.ref('lieux/$path');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  // ─── Validation étape ─────────────────────────────────────────────────────

  bool _validateStep(int step) {
    if (step == 0) {
      if (_nomCtrl.text.trim().isEmpty) { _err('Nom requis'); return false; }
      if (_siretCtrl.text.trim().length != 14) { _err('SIRET : 14 chiffres'); return false; }
      if (_lat == null) { _err('Sélectionne une adresse dans la liste'); return false; }
    }
    if (step == 1) {
      if (_descCtrl.text.trim().length < 50) { _err('Description : min 50 caractères'); return false; }
    }
    if (step == 2) {
      if (_especesChoisies.isEmpty) { _err('Sélectionne au moins une espèce'); return false; }
    }
    return true;
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ─── Soumission finale ────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_validateStep(2)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final profileRow = await Supabase.instance.client
          .from('user_profiles').select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
      final profileId = profileRow?['id'] as String?;

      final id = DateTime.now().millisecondsSinceEpoch.toString();

      String? logoUrl;
      if (_logoPick != null) logoUrl = await _upload(_logoPick!, '$id/logo.jpg');

      String? banniereUrl;
      if (_bannierePick != null) banniereUrl = await _upload(_bannierePick!, '$id/banniere.jpg');

      final photosUrls = <String>[];
      for (int i = 0; i < _photosPick.length; i++) {
        photosUrls.add(await _upload(_photosPick[i], '$id/photo_$i.jpg'));
      }

      final horairesClean = <String, String>{
        for (final j in _horairesFerme.keys)
          j: _horairesFerme[j]! ? 'fermé' : '${_horairesDebut[j]}-${_horairesFin[j]}',
      };

      final payload = <String, dynamic>{
        'uid_pro':         uid,
        if (profileId != null) 'pro_profile_id': profileId,
        'nom':             _nomCtrl.text.trim(),
        'categorie':       _categorie,
        'sous_categorie':  _sousCategorie,
        'description':     _descCtrl.text.trim(),
        'siret':           _siretCtrl.text.trim(),
        'adresse':         _rueCtrl.text.trim(),
        'code_postal':     _cpCtrl.text.trim(),
        'ville':           _villeCtrl.text.trim(),
        'lat':             _lat,
        'lng':             _lng,
        'telephone':       _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'email_contact':   _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'site_web':        _siteCtrl.text.trim().isEmpty ? null : _siteCtrl.text.trim(),
        'especes_acceptees': _especesChoisies,
        'horaires':        horairesClean,
        'photo_profil_url': logoUrl,
        'banniere_url':    banniereUrl,
        'photos':          photosUrls,
        'statut':          'en_attente_validation',
        'plan':            'decouverte',
      };

      if (_categorie == 'hebergement') {
        payload.addAll({
          'animaux_dans_chambre': _animauxChambre,
          'frais_animal_nuit':    _fraisNuit > 0 ? _fraisNuit : null,
          'nb_animaux_max':       _nbAnimauxMax,
          'espace_detente':       _espaceDetente,
          'prix_nuit_defaut':     _prixNuitDefaut,
        });
      } else {
        payload.addAll({
          'terrasse':        _terrasse,
          'animaux_en_salle': _animauxSalle,
          'eau_fournie':     _eauFournie,
          'friandises':      _friandises,
          'pet_menu':        _petMenu,
        });
      }

      await Supabase.instance.client.from('petfriendly_places').insert(payload);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Établissement soumis ✅ — En attente de validation (48h)'),
          backgroundColor: Color(0xFF0C5C6C),
        ));
      }
    } catch (e) {
      setState(() => _saving = false);
      _err('Erreur : $e');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(
          ['Identité', 'Profil', 'Détails & Contact'][_step],
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      ),
      body: [_buildStep1, _buildStep2, _buildStep3][_step](),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              if (_step > 0)
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
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : () {
                    if (!_validateStep(_step)) return;
                    if (_step < 2) {
                      setState(() => _step++);
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
                      : Text(_step < 2 ? 'Suivant →' : 'Soumettre',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Étape 1 — Identité ──────────────────────────────────────────────────

  Widget _buildStep1() {
    const allTypes = [
      ('hotel',                '🏨', 'Hôtel'),
      ('hebergement_insolite', '🏕️', 'Hébergement insolite'),
      ('gite',                 '🏡', 'Gîte / Chambre d\'hôtes'),
      ('camping',              '⛺', 'Camping'),
      ('villa_location',       '🏖️', 'Location saisonnière'),
      ('cafe',                 '☕', 'Café / Salon de thé'),
      ('restaurant',           '🍽️', 'Restaurant'),
      ('bar',                  '🍺', 'Bar / Brasserie'),
      ('fast_food',            '🍔', 'Restauration rapide'),
      ('boulangerie',          '🥐', 'Boulangerie / Pâtisserie'),
    ];
    const hebergementTypes = {'hotel','hebergement_insolite','gite','camping','villa_location'};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Informations générales'),
        _Field(_nomCtrl, 'Nom de l\'établissement', maxLength: 80),
        const SizedBox(height: 12),
        _Field(_siretCtrl, 'SIRET (14 chiffres)', keyboardType: TextInputType.number, maxLength: 14),
        const SizedBox(height: 20),
        _SectionTitle('Type d\'établissement'),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: allTypes.map((t) {
            final sel = _sousCategorie == t.$1;
            return FilterChip(
              label: Text('${t.$2} ${t.$3}', style: TextStyle(
                  fontSize: 12, color: sel ? Colors.white : Colors.grey.shade700)),
              selected: sel,
              selectedColor: _teal,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              showCheckmark: false,
              side: BorderSide(color: sel ? _teal : Colors.grey.shade300),
              onSelected: (_) => setState(() {
                _sousCategorie = t.$1;
                _categorie = hebergementTypes.contains(t.$1) ? 'hebergement' : 'restauration';
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Adresse'),
        TextFormField(
          controller: _adresseSearchCtrl,
          decoration: _inputDeco('Rechercher une adresse…'),
          onChanged: _onAddressChanged,
        ),
        if (_loadingPredictions)
          const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        if (_predictions.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)],
            ),
            child: Column(
              children: _predictions.map((p) => ListTile(
                leading: const Icon(Icons.location_on_outlined, size: 18),
                title: Text(p.description ?? '', style: const TextStyle(fontSize: 13)),
                onTap: () => _selectPrediction(p),
              )).toList(),
            ),
          ),
        const SizedBox(height: 12),
        if (_lat != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${_rueCtrl.text}, ${_cpCtrl.text} ${_villeCtrl.text}',
                style: const TextStyle(fontSize: 12),
              )),
            ]),
          ),
      ],
    );
  }

  // ─── Étape 2 — Profil ────────────────────────────────────────────────────

  Widget _buildStep2() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Description'),
        TextFormField(
          controller: _descCtrl,
          maxLines: 5,
          maxLength: 1000,
          decoration: _inputDeco('Décrivez votre établissement (min 50 caractères)…'),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Photos'),
        _PhotoPicker(
          label: 'Logo (400×400 min)',
          file: _logoPick,
          onPick: () async { final f = await _pickImage(); if (f != null) setState(() => _logoPick = f); },
        ),
        const SizedBox(height: 12),
        _PhotoPicker(
          label: 'Bannière (1200×400 min)',
          file: _bannierePick,
          wide: true,
          onPick: () async { final f = await _pickImage(); if (f != null) setState(() => _bannierePick = f); },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Photos du lieu (max 5)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            Text('${_photosPick.length}/5',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ..._photosPick.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(e.value, width: 90, height: 100, fit: BoxFit.cover),
                  ),
                  Positioned(top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _photosPick.removeAt(e.key)),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ]),
              )),
              if (_photosPick.length < 5)
                GestureDetector(
                  onTap: () async {
                    final picks = await ImagePicker().pickMultiImage(imageQuality: 80);
                    if (picks.isNotEmpty && mounted) {
                      setState(() {
                        for (final f in picks) {
                          if (_photosPick.length < 5) _photosPick.add(File(f.path));
                        }
                      });
                    }
                  },
                  child: Container(
                    width: 90, height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined, color: Colors.grey, size: 30),
                        const SizedBox(height: 4),
                        Text('${5 - _photosPick.length} dispo.',
                            style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Horaires d\'ouverture'),
        ..._horairesFerme.keys.map((j) {
          final ferme = _horairesFerme[j]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(
                width: 82,
                child: Text(_capitalize(j),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              Transform.scale(
                scale: 0.75,
                alignment: Alignment.centerLeft,
                child: Switch(
                  value: !ferme,
                  onChanged: (v) => setState(() => _horairesFerme[j] = !v),
                  activeColor: _teal,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (!ferme) ...[
                const SizedBox(width: 2),
                GestureDetector(
                  onTap: () => _pickTime(j, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: Text(_horairesDebut[j]!,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('–', style: TextStyle(fontSize: 14)),
                ),
                GestureDetector(
                  onTap: () => _pickTime(j, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: Text(_horairesFin[j]!,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 4),
                Text('Fermé', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ],
            ]),
          );
        }),
      ],
    );
  }

  // ─── Étape 3 — Détails & Contact ─────────────────────────────────────────

  Widget _buildStep3() {
    const especes = [
      ('chien', '🐶 Chien'), ('chat', '🐱 Chat'), ('cheval', '🐴 Cheval'),
      ('lapin', '🐰 Lapin'), ('oiseau', '🦜 Oiseau'), ('nac', '🐾 NAC'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Espèces acceptées'),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: especes.map((e) {
            final selected = _especesChoisies.contains(e.$1);
            return FilterChip(
              label: Text(e.$2, style: TextStyle(fontSize: 12,
                  color: selected ? Colors.white : Colors.grey.shade700)),
              selected: selected,
              selectedColor: _teal,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              side: BorderSide(color: selected ? _teal : Colors.grey.shade300),
              onSelected: (v) => setState(() {
                if (v) _especesChoisies.add(e.$1); else _especesChoisies.remove(e.$1);
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        if (_categorie == 'hebergement') ...[
          _SectionTitle('Conditions pour les animaux'),
          _BoolRow('Animaux autorisés dans la chambre', _animauxChambre,
              (v) => setState(() => _animauxChambre = v)),
          _BoolRow('Espace détente / jardin clôturé', _espaceDetente,
              (v) => setState(() => _espaceDetente = v)),
          const SizedBox(height: 12),
          _FieldInt('Supplément/nuit (€)', _fraisNuit,
              (v) => setState(() => _fraisNuit = v)),
          const SizedBox(height: 8),
          _FieldInt('Nb animaux max / séjour', _nbAnimauxMax,
              (v) => setState(() => _nbAnimauxMax = v)),
          const SizedBox(height: 8),
          _FieldInt('Prix par nuit par défaut (€)', _prixNuitDefaut,
              (v) => setState(() => _prixNuitDefaut = v)),
        ] else ...[
          _SectionTitle('Conditions pour les animaux'),
          _BoolRow('Terrasse disponible', _terrasse, (v) => setState(() => _terrasse = v)),
          _BoolRow('Animaux acceptés en salle', _animauxSalle, (v) => setState(() => _animauxSalle = v)),
          _BoolRow('Gamelle d\'eau fournie', _eauFournie, (v) => setState(() => _eauFournie = v)),
          _BoolRow('Friandises proposées', _friandises, (v) => setState(() => _friandises = v)),
          _BoolRow('Menu dédié aux animaux', _petMenu, (v) => setState(() => _petMenu = v)),
        ],
        const SizedBox(height: 20),
        _SectionTitle('Contact'),
        _Field(_telCtrl, 'Téléphone professionnel', keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _Field(_emailCtrl, 'Email de contact', keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _Field(_siteCtrl, 'Site web (optionnel)', keyboardType: TextInputType.url),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFB74D)),
          ),
          child: const Text(
            '⏳ Votre établissement sera examiné sous 48h par notre équipe avant publication.',
            style: TextStyle(fontSize: 12, color: Color(0xFFE65100)),
          ),
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0C5C6C))),
  );
}

// ─── Widgets utilitaires ─────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title,
        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
  );
}

Widget _Field(TextEditingController ctrl, String hint,
    {TextInputType keyboardType = TextInputType.text, int? maxLength}) {
  return TextFormField(
    controller: ctrl,
    keyboardType: keyboardType,
    maxLength: maxLength,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      counterText: '',
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0C5C6C))),
    ),
  );
}

Widget _FieldInt(String label, int value, ValueChanged<int> onChanged) {
  final ctrl = TextEditingController(text: value == 0 ? '' : '$value');
  return TextFormField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(fontSize: 12),
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0C5C6C))),
    ),
    onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
  );
}

Widget _BoolRow(String label, bool value, ValueChanged<bool> onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF0C5C6C),
        ),
      ],
    ),
  );
}


class _PhotoPicker extends StatelessWidget {
  final String label;
  final File? file;
  final bool wide;
  final VoidCallback onPick;
  const _PhotoPicker({required this.label, required this.file, required this.onPick, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        width: double.infinity,
        height: wide ? 100 : 80,
        decoration: BoxDecoration(
          color: file != null ? null : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: file != null ? Colors.transparent : Colors.grey.shade300,
          ),
          image: file != null
              ? DecorationImage(image: FileImage(file!), fit: BoxFit.cover)
              : null,
        ),
        child: file != null
            ? const Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined, color: Colors.grey),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
      ),
    );
  }
}
