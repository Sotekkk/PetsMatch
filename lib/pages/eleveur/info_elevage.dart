import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/document_elevage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_webservice/places.dart';

// ── Données espèces (pour l'inscription) ────────────────────────────────────
const _kInscriptionEspeces = [
  (value: 'chien',  label: 'Chien'),
  (value: 'chat',   label: 'Chat'),
  (value: 'cheval', label: 'Cheval'),
  (value: 'lapin',  label: 'Lapin'),
  (value: 'ovin',   label: 'Ovin'),
  (value: 'caprin', label: 'Caprin'),
  (value: 'porcin', label: 'Porcin'),
  (value: 'nac',    label: 'NAC'),
  (value: 'oiseau', label: 'Oiseau'),
  (value: 'autre',  label: 'Autre'),
];


// ── Page ────────────────────────────────────────────────────────────────────

class RegisterElevageInformation extends StatefulWidget {
  const RegisterElevageInformation({super.key});
  @override
  State<RegisterElevageInformation> createState() => _RegisterElevageInformationState();
}

class _RegisterElevageInformationState extends State<RegisterElevageInformation> {
  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  // Identité
  final _nomCtrl   = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Adresse
  final _adresseSearchCtrl = TextEditingController();
  final _rueCtrl   = TextEditingController();
  final _cpCtrl    = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _paysCtrl  = TextEditingController(text: 'France');

  // Races chargées depuis les assets
  List<String> _dogBreeds = [];
  List<String> _catBreeds = [];

  // Espèces / races
  final List<String> _selectedEspeces = [];
  final Map<String, List<String>> _selectedRaces = {};
  final Map<String, String?> _pendingBreed = {};       // dropdown value en cours
  final Map<String, TextEditingController> _breedTextCtrl = {}; // saisie libre
  final Map<String, TextEditingController> _breedSearchCtrl = {}; // recherche races chien/chat

  File? _imageFile;
  bool _uploading = false;
  String _countryCode = '+33';

  final GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: getApiKey());
  List<Prediction> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _adresseSearchCtrl.addListener(_onAddressChanged);
    _cpCtrl.addListener(_onCpChanged);
    _loadBreeds();
  }

  Future<void> _loadBreeds() async {
    final dogJson = await rootBundle.loadString('assets/dog_breeds.json');
    final catJson = await rootBundle.loadString('assets/cat_breeds.json');
    if (!mounted) return;
    setState(() {
      _dogBreeds = List<String>.from(json.decode(dogJson) as List);
      _catBreeds = List<String>.from(json.decode(catJson) as List);
    });
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _phoneCtrl.dispose();
    _adresseSearchCtrl.dispose();
    _rueCtrl.dispose();
    _cpCtrl.dispose();
    _villeCtrl.dispose();
    _paysCtrl.dispose();
    for (final c in _breedTextCtrl.values) c.dispose();
    for (final c in _breedSearchCtrl.values) c.dispose();
    _debounce?.cancel();
    _places.dispose();
    super.dispose();
  }

  // ── Google Places ─────────────────────────────────────────────────────────

  void _onAddressChanged() {
    final text = _adresseSearchCtrl.text;
    _debounce?.cancel();
    if (text.length < 3) { setState(() { _suggestions = []; _showSuggestions = false; }); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final response = await _places.autocomplete(text, language: 'fr');
      if (!mounted) return;
      setState(() {
        _suggestions = response.isOkay ? response.predictions : [];
        _showSuggestions = _suggestions.isNotEmpty;
      });
    });
  }

  void _onCpChanged() {
    final cp = _cpCtrl.text.trim();
    if (cp.length != 5) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final response = await _places.autocomplete(cp, language: 'fr',
          types: ['(cities)'], components: [Component(Component.country, 'fr')]);
      if (!mounted || !response.isOkay || response.predictions.isEmpty) return;
      final det = await _places.getDetailsByPlaceId(response.predictions.first.placeId!);
      if (!mounted || !det.isOkay) return;
      for (final comp in det.result!.addressComponents) {
        if (comp.types.contains('locality')) {
          if (mounted) setState(() => _villeCtrl.text = comp.longName);
          break;
        }
      }
    });
  }

  Future<void> _selectPrediction(Prediction p) async {
    if (p.placeId == null) return;
    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;
    String streetNum = '', route = '', cp = '', ville = '', pays = '';
    for (final comp in det.result!.addressComponents) {
      if (comp.types.contains('street_number')) streetNum = comp.longName;
      if (comp.types.contains('route'))         route = comp.longName;
      if (comp.types.contains('postal_code'))   cp = comp.longName;
      if (comp.types.contains('locality'))      ville = comp.longName;
      if (comp.types.contains('country'))       pays = comp.longName;
    }
    setState(() {
      _rueCtrl.text    = [streetNum, route].where((s) => s.isNotEmpty).join(' ');
      _cpCtrl.text     = cp;
      _villeCtrl.text  = ville;
      _paysCtrl.text   = pays.isNotEmpty ? pays : 'France';
      _adresseSearchCtrl.text = det.result!.formattedAddress ?? '';
      _suggestions = [];
      _showSuggestions = false;
    });
  }

  // ── Photo ─────────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final f = await pickAndCropSquare();
    if (f != null) setState(() => _imageFile = f);
  }

  // ── Espèces ───────────────────────────────────────────────────────────────

  void _toggleEspece(String esp) {
    setState(() {
      if (_selectedEspeces.contains(esp)) {
        _selectedEspeces.remove(esp);
        _selectedRaces.remove(esp);
        _pendingBreed.remove(esp);
        _breedTextCtrl.remove(esp)?.dispose();
        _breedSearchCtrl.remove(esp)?.dispose();
      } else {
        _selectedEspeces.add(esp);
        _selectedRaces[esp] = [];
        _pendingBreed[esp] = null;
        if (esp == 'chien' || esp == 'chat') {
          _breedSearchCtrl[esp] = TextEditingController();
        } else {
          _breedTextCtrl[esp] = TextEditingController();
        }
      }
    });
  }

  void _addBreedDropdown(String esp) {
    final breed = _pendingBreed[esp];
    if (breed == null || breed.isEmpty) return;
    setState(() {
      if (!(_selectedRaces[esp] ?? []).contains(breed)) {
        _selectedRaces[esp]!.add(breed);
      }
      _pendingBreed[esp] = null;
    });
  }

  void _addBreedText(String esp) {
    final ctrl = _breedTextCtrl[esp];
    if (ctrl == null) return;
    final val = ctrl.text.trim();
    if (val.isEmpty) return;
    setState(() {
      if (!(_selectedRaces[esp] ?? []).contains(val)) {
        _selectedRaces[esp]!.add(val);
      }
      ctrl.clear();
    });
  }

  void _removeBreed(String esp, String breed) {
    setState(() => _selectedRaces[esp]?.remove(breed));
  }

  // ── Validation ────────────────────────────────────────────────────────────

  Future<void> _validateAndContinue() async {
    final nom   = _nomCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final rue   = _rueCtrl.text.trim();
    final ville = _villeCtrl.text.trim();

    if (nom.isEmpty || phone.isEmpty || rue.isEmpty || ville.isEmpty) {
      _snack('Veuillez remplir tous les champs obligatoires.');
      return;
    }
    if (_selectedEspeces.isEmpty) {
      _snack('Sélectionnez au moins une espèce élevée.');
      return;
    }

    setState(() => _uploading = true);
    try {
      if (_imageFile != null) {
        final name = _imageFile!.path.split('/').last;
        final ref  = FirebaseStorage.instance.ref().child('files/$name');
        final snap = await ref.putFile(_imageFile!);
        User_Info.profilePictureUrlElevage = await snap.ref.getDownloadURL();
      }

      User_Info.nameElevage        = nom;
      User_Info.codeISOElevage     = _countryCode;
      User_Info.numeroElevage      = phone;
      User_Info.rueElevage         = rue;
      User_Info.codePostalElevage  = _cpCtrl.text.trim();
      User_Info.villeElevage       = ville;
      User_Info.paysElevage        = _paysCtrl.text.trim();
      User_Info.adressElevage      = [rue, _cpCtrl.text.trim(), ville].where((s) => s.isNotEmpty).join(', ');

      // Espèces et races
      User_Info.especesElevees = List.from(_selectedEspeces);
      User_Info.isDog          = _selectedEspeces.contains('chien');
      User_Info.isCat          = _selectedEspeces.contains('chat');
      User_Info.dogBreeds      = List.from(_selectedRaces['chien'] ?? []);
      User_Info.catBreeds      = List.from(_selectedRaces['chat'] ?? []);

      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterDocumentElevage()));
    } catch (e) {
      if (mounted) _snack('Erreur: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Galey'))));

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(
          User_Info.isPro ? 'Informations société' : 'Informations élevage',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: _StepBar(current: 2, total: 4),
        ),
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Photo ───────────────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFFEEF5EA),
                    backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                    child: _imageFile == null
                        ? const Icon(Icons.pets, size: 40, color: Color(0xFF6E9E57))
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: _green,
                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text("Photo de l'élevage (optionnel)",
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ),
            const SizedBox(height: 24),

            // ── Nom ─────────────────────────────────────────────────────────
            _sectionTitle(User_Info.isPro ? 'Nom de la société *' : "Nom de l'élevage *"),
            const SizedBox(height: 8),
            _card([
              _textField(
                User_Info.isPro ? 'Nom société' : 'Nom élevage',
                _nomCtrl,
                icon: Icons.business_outlined,
              ),
            ]),
            const SizedBox(height: 20),

            // ── Téléphone ────────────────────────────────────────────────────
            _sectionTitle('Téléphone *'),
            const SizedBox(height: 8),
            _card([
              Row(children: [
                GestureDetector(
                  onTap: _pickCountryCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E7E2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_countryCode, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF6F767B)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: _inputDeco('Numéro de téléphone'),
                  ),
                ),
              ]),
            ]),
            const SizedBox(height: 20),

            // ── Adresse ──────────────────────────────────────────────────────
            _sectionTitle('Adresse *'),
            const SizedBox(height: 8),
            _card([
              TextFormField(
                controller: _adresseSearchCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: _inputDeco('Rechercher une adresse').copyWith(
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF6F767B)),
                  suffixIcon: _adresseSearchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () { _adresseSearchCtrl.clear(); setState(() { _suggestions = []; _showSuggestions = false; }); },
                          child: const Icon(Icons.close, size: 16, color: Color(0xFF6F767B)),
                        )
                      : null,
                ),
              ),
              if (_showSuggestions) ...[
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE4E7E2)),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                  ),
                  child: Column(
                    children: _suggestions.take(4).map((p) => InkWell(
                      onTap: () => _selectPrediction(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.place_outlined, size: 16, color: Color(0xFF0C5C6C)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                        ]),
                      ),
                    )).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _textField('Rue', _rueCtrl),
              Row(children: [
                Expanded(flex: 2, child: _textField('Code postal', _cpCtrl, inputType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: _textField('Ville', _villeCtrl)),
              ]),
              _textField('Pays', _paysCtrl),
            ]),
            const SizedBox(height: 20),

            // ── Espèces élevées ──────────────────────────────────────────────
            _sectionTitle('Espèces élevées *'),
            const SizedBox(height: 4),
            Text('Sélectionnez toutes les espèces que vous élevez.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 10),
            _card([
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kInscriptionEspeces.map((sp) {
                  final active = _selectedEspeces.contains(sp.value);
                  return GestureDetector(
                    onTap: () => _toggleEspece(sp.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? _green : Colors.transparent,
                        border: Border.all(color: active ? _green : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(sp.label,
                          style: TextStyle(
                              fontFamily: 'Galey', fontSize: 13,
                              color: active ? Colors.white : Colors.black87,
                              fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ),
                  );
                }).toList(),
              ),
            ]),

            // ── Races (dynamique) ────────────────────────────────────────────
            if (_selectedEspeces.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle('Races élevées'),
              const SizedBox(height: 4),
              Text('Pour chaque espèce, précisez les races (optionnel).',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 10),
              ..._selectedEspeces.map((esp) => _breedSection(esp)),
            ],
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _uploading ? null : _validateAndContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _uploading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('CONTINUER',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Section race ──────────────────────────────────────────────────────────

  Widget _breedSection(String esp) {
    final label = _kInscriptionEspeces.firstWhere((e) => e.value == esp).label;
    final isDropdown = esp == 'chien' || esp == 'chat';
    final breedList  = esp == 'chien' ? _dogBreeds : _catBreeds;
    final selected   = _selectedRaces[esp] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF5EA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: FontWeight.w700, color: _green)),
          ),
        ]),
        const SizedBox(height: 10),

        if (isDropdown) ...[
          // Recherche typable races chien/chat
          TextFormField(
            controller: _breedSearchCtrl[esp],
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            decoration: _inputDeco('Tapez pour chercher une race').copyWith(
              prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF6F767B)),
              suffixIcon: (_breedSearchCtrl[esp]?.text.isNotEmpty ?? false)
                  ? GestureDetector(
                      onTap: () => setState(() => _breedSearchCtrl[esp]!.clear()),
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF6F767B)),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          Builder(builder: (context) {
            final query = (_breedSearchCtrl[esp]?.text.trim().toLowerCase()) ?? '';
            if (query.isEmpty) return const SizedBox.shrink();
            final suggestions = breedList
                .where((b) => !selected.contains(b) && b.toLowerCase().contains(query))
                .take(6)
                .toList();
            if (suggestions.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Aucune race trouvée',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
              );
            }
            return Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE4E7E2)),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
              ),
              child: Column(
                children: suggestions.asMap().entries.map((entry) {
                  final b = entry.value;
                  final isLast = entry.key == suggestions.length - 1;
                  return Column(children: [
                    InkWell(
                      onTap: () => setState(() {
                        _selectedRaces[esp]!.add(b);
                        _breedSearchCtrl[esp]?.clear();
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.pets, size: 14, color: _green),
                          const SizedBox(width: 8),
                          Expanded(child: Text(b,
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                          const Icon(Icons.add, size: 14, color: Color(0xFF6F767B)),
                        ]),
                      ),
                    ),
                    if (!isLast) const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  ]);
                }).toList(),
              ),
            );
          }),
        ] else ...[
          // Saisie libre pour les autres espèces
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: TextFormField(
                controller: _breedTextCtrl[esp],
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: _inputDeco('Race ou variété'),
                onFieldSubmitted: (_) => _addBreedText(esp),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _addBreedText(esp),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: Size.zero,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
          ]),
        ],

        if (selected.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: selected.map((b) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF5EA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _green.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(b, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeBreed(esp, b),
                  child: const Icon(Icons.close, size: 13, color: _green),
                ),
              ]),
            )).toList(),
          ),
        ],
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _pickCountryCode() async {
    const codes = ['+33', '+32', '+41', '+1', '+44', '+34', '+39', '+49'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: codes.map((c) => ListTile(
          title: Text(c, style: const TextStyle(fontFamily: 'Galey', fontSize: 15)),
          onTap: () => Navigator.pop(context, c),
        )).toList(),
      ),
    );
    if (picked != null) setState(() => _countryCode = picked);
  }

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 16, color: Color(0xFF1F2A2E)));

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  InputDecoration _inputDeco(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    isDense: true,
  );

  Widget _textField(String label, TextEditingController ctrl, {IconData? icon, TextInputType? inputType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: ctrl,
          keyboardType: inputType,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: _inputDeco(label).copyWith(
            prefixIcon: icon != null ? Icon(icon, size: 18, color: const Color(0xFF6F767B)) : null,
          ),
        ),
      );
}

// ── Step bar ─────────────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  final int current;
  final int total;
  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Row(
      children: List.generate(total, (i) => Expanded(
        child: Container(
          height: 3,
          margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
          decoration: BoxDecoration(
            color: i < current ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    ),
  );
}
