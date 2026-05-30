import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/pro/pro_zone_page.dart';

class ProProfileEditPage extends StatefulWidget {
  const ProProfileEditPage({super.key});

  @override
  State<ProProfileEditPage> createState() => _ProProfileEditPageState();
}

class _ProProfileEditPageState extends State<ProProfileEditPage> {
  final _supa   = Supabase.instance.client;
  late final GoogleMapsPlaces _places;
  bool _saving  = false;
  bool _loading = true;
  bool _locating = false;
  bool _loadingPredictions = false;
  Timer? _searchDebounce;
  List<Prediction> _predictions = [];

  // Controllers
  final _nomStructureCtrl    = TextEditingController();
  final _professionCtrl      = TextEditingController();
  final _descCtrl            = TextEditingController();
  final _tarifsCtrl          = TextEditingController();
  final _siteWebCtrl         = TextEditingController();
  final _instagramCtrl       = TextEditingController();
  final _facebookCtrl        = TextEditingController();
  int _rayonKm               = 20;
  final _addressSearchCtrl   = TextEditingController();
  final _rueCtrl             = TextEditingController();
  final _villeCtrl           = TextEditingController();
  final _cpCtrl              = TextEditingController();
  final _paysCtrl            = TextEditingController(text: 'France');

  double? _lat;
  double? _lng;

  bool _acceptNewClients = true;
  String _catPro = '';

  static const _especesList = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'Autre'];
  List<String> _especesAcceptees = [];

  final _jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
  late final Map<String, TextEditingController> _horairesCtrl;

  List<Map<String, String>> _certifications = [];

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _horairesCtrl = {for (var j in _jours) j: TextEditingController()};
    _loadProProfile();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _places.dispose();
    for (final c in [
      _nomStructureCtrl, _professionCtrl, _descCtrl, _tarifsCtrl,
      _siteWebCtrl, _instagramCtrl, _facebookCtrl,
      _addressSearchCtrl, _rueCtrl, _villeCtrl, _cpCtrl, _paysCtrl,
    ]) { c.dispose(); }
    for (final c in _horairesCtrl.values) { c.dispose(); }
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────────

  Future<void> _loadProProfile() async {
    try {
      final row = await _supa
          .from('users')
          .select()
          .eq('uid', User_Info.uid)
          .maybeSingle();

      if (row != null) {
        _nomStructureCtrl.text = row['name_elevage']    ?? User_Info.nameElevage;
        _professionCtrl.text   = row['profession_pro']  ?? User_Info.professionPro;
        _descCtrl.text         = row['desc_entreprise'] ?? User_Info.descEntreprise;
        _tarifsCtrl.text       = row['tarifs']          ?? '';
        _siteWebCtrl.text      = row['site_web']        ?? '';
        _instagramCtrl.text    = row['instagram']       ?? '';
        _facebookCtrl.text     = row['facebook']        ?? '';
        _rayonKm               = (row['rayon_intervention'] as num?)?.toInt() ?? 20;
        _acceptNewClients      = row['accept_new_clients'] ?? true;
        _lat                   = (row['lat'] as num?)?.toDouble();
        _lng                   = (row['lng'] as num?)?.toDouble();

        // Adresse
        _catPro         = row['cat_pro']               ?? '';
        _rueCtrl.text   = row['rue_elevage']          ?? '';
        _villeCtrl.text = row['ville_elevage']         ?? '';
        _cpCtrl.text    = row['code_postal_elevage']   ?? '';
        _paysCtrl.text  = row['pays_elevage']?.isNotEmpty == true
            ? row['pays_elevage'] : 'France';
        _addressSearchCtrl.text = [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text]
            .where((s) => s.isNotEmpty).join(', ');

        if (row['especes_acceptees'] is List) {
          _especesAcceptees = List<String>.from(row['especes_acceptees']);
        }
        if (row['horaires'] is Map) {
          for (final j in _jours) {
            _horairesCtrl[j]!.text = row['horaires'][j] ?? '';
          }
        }
        if (row['certifications'] is List) {
          _certifications = List<Map<String, String>>.from(
            (row['certifications'] as List).map((e) => Map<String, String>.from(
              (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
            )),
          );
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Geocoding ─────────────────────────────────────────────────────────────────

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
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('Permission refusée');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) throw Exception('Adresse introuvable');
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Géolocalisation impossible : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez saisir une adresse pour géolocaliser votre cabinet.',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final horairesMap = {
        for (final j in _jours)
          if (_horairesCtrl[j]!.text.trim().isNotEmpty) j: _horairesCtrl[j]!.text.trim()
      };

      final adresse = [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
          .where((s) => s.isNotEmpty).join(', ');

      _catPro = _inferCatPro(_professionCtrl.text.trim());

      await _supa.from('users').upsert({
        'uid':                  User_Info.uid,
        'name_elevage':         _nomStructureCtrl.text.trim(),
        'profession_pro':       _professionCtrl.text.trim(),
        'desc_entreprise':      _descCtrl.text.trim(),
        'tarifs':               _tarifsCtrl.text.trim(),
        'site_web':             _siteWebCtrl.text.trim(),
        'instagram':            _instagramCtrl.text.trim(),
        'facebook':             _facebookCtrl.text.trim(),
        'rayon_intervention':   _rayonKm,
        'especes_acceptees':    _especesAcceptees,
        'horaires':             horairesMap,
        'certifications':       _certifications,
        'accept_new_clients':   _acceptNewClients,
        'cat_pro':              _catPro,
        'is_pro':               true,
        // Adresse + géolocalisation
        'rue_elevage':          _rueCtrl.text.trim(),
        'ville_elevage':        _villeCtrl.text.trim(),
        'code_postal_elevage':  _cpCtrl.text.trim(),
        'pays_elevage':         _paysCtrl.text.trim(),
        'adress_elevage':       adresse,
        'lat':                  _lat,
        'lng':                  _lng,
      }, onConflict: 'uid');

      // Mettre à jour User_Info en mémoire
      User_Info.nameElevage       = _nomStructureCtrl.text.trim();
      User_Info.professionPro     = _professionCtrl.text.trim();
      User_Info.descEntreprise    = _descCtrl.text.trim();
      User_Info.tarifs            = _tarifsCtrl.text.trim();
      User_Info.siteWeb           = _siteWebCtrl.text.trim();
      User_Info.instagram         = _instagramCtrl.text.trim();
      User_Info.facebook          = _facebookCtrl.text.trim();
      User_Info.rayonIntervention = _rayonKm;
      User_Info.especesAcceptees  = List.from(_especesAcceptees);
      User_Info.certifications    = List.from(_certifications);
      User_Info.acceptNewClients  = _acceptNewClients;
      User_Info.rueElevage        = _rueCtrl.text.trim();
      User_Info.villeElevage      = _villeCtrl.text.trim();
      User_Info.codePostalElevage = _cpCtrl.text.trim();
      User_Info.paysElevage       = _paysCtrl.text.trim();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil pro mis à jour', style: TextStyle(fontFamily: 'Galey')),
            backgroundColor: Color(0xFF6E9E57),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: const Color(0xFF1E2025),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 20, 16),
              title: const Text('Mon profil pro',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6E9E57), Color(0xFF1E2025)],
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Informations générales ────────────────────────────────
                  _sectionTitle('Informations générales'),
                  const SizedBox(height: 12),
                  _field(_nomStructureCtrl, 'Nom de la structure', Icons.business_outlined),
                  const SizedBox(height: 12),
                  _field(_professionCtrl, 'Profession', Icons.work_outline),
                  const SizedBox(height: 12),
                  _field(_descCtrl, 'Description de l\'activité', Icons.description_outlined, maxLines: 4),
                  const SizedBox(height: 12),
                  _field(_tarifsCtrl, 'Tarifs (description libre)', Icons.euro_outlined, maxLines: 3),

                  // ── Adresse & géolocalisation ─────────────────────────────
                  const SizedBox(height: 24),
                  _sectionTitle('Adresse & localisation'),
                  const SizedBox(height: 4),
                  Text(
                    'L\'adresse sert à vous référencer sur la carte de l\'annuaire.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  _addressBlock(),

                  if (_lat != null && _lng != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'Coordonnées GPS : ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.green.shade700),
                      ),
                    ]),
                  ],

                  // ── Disponibilité & intervention ──────────────────────────
                  const SizedBox(height: 24),
                  _sectionTitle('Disponibilité & intervention'),
                  const SizedBox(height: 12),
                  _zoneTile(),
                  const SizedBox(height: 16),
                  _acceptClientsToggle(),

                  // ── Espèces ───────────────────────────────────────────────
                  const SizedBox(height: 24),
                  _sectionTitle('Espèces acceptées'),
                  const SizedBox(height: 12),
                  _especesSelector(),

                  // ── Horaires ──────────────────────────────────────────────
                  const SizedBox(height: 24),
                  _sectionTitle('Horaires d\'ouverture'),
                  const SizedBox(height: 12),
                  ..._jours.map((j) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _field(_horairesCtrl[j]!, j, Icons.schedule_outlined, hint: 'ex: 9h-18h ou Fermé'),
                  )),

                  // ── Réseaux & site web ────────────────────────────────────
                  const SizedBox(height: 24),
                  _sectionTitle('Réseaux & site web'),
                  const SizedBox(height: 12),
                  _field(_siteWebCtrl, 'Site web', Icons.language_outlined),
                  const SizedBox(height: 12),
                  _field(_instagramCtrl, 'Instagram (@...)', Icons.camera_alt_outlined),
                  const SizedBox(height: 12),
                  _field(_facebookCtrl, 'Facebook (URL ou nom de page)', Icons.facebook_outlined),

                  // ── Certifications ────────────────────────────────────────
                  const SizedBox(height: 24),
                  _sectionTitle('Certifications / Diplômes'),
                  const SizedBox(height: 12),
                  _certificationsEditor(),

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6E9E57),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _saving
                          ? const SizedBox(height: 22, width: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Enregistrer',
                              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // ── Address block ─────────────────────────────────────────────────────────────

  Widget _addressBlock() {
    return Column(
      children: [
        // Champ recherche d'adresse
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _addressSearchCtrl,
                  onChanged: _onAddressChanged,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Rechercher une adresse',
                    prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF6E9E57)),
                    suffixIcon: _loadingPredictions
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6E9E57))))
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    filled: true, fillColor: Colors.white,
                    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              // Bouton GPS
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  onPressed: _locating ? null : _geolocate,
                  tooltip: 'Ma position actuelle',
                  icon: _locating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6E9E57)))
                      : const Icon(Icons.my_location, color: Color(0xFF6E9E57)),
                ),
              ),
            ],
          ),
        ),

        // Suggestions Google Places
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final p = _predictions[i];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF6E9E57)),
                  title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  dense: true,
                  onTap: () => _selectPrediction(p),
                );
              },
            ),
          ),

        const SizedBox(height: 12),

        // Champs adresse détaillés (remplis automatiquement)
        _field(_rueCtrl, 'Rue', Icons.home_outlined),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 2, child: _field(_villeCtrl, 'Ville', Icons.location_city_outlined)),
          const SizedBox(width: 10),
          Expanded(flex: 1, child: _field(_cpCtrl, 'Code postal', Icons.markunread_mailbox_outlined,
              inputType: TextInputType.number)),
        ]),
        const SizedBox(height: 10),
        _field(_paysCtrl, 'Pays', Icons.flag_outlined),
      ],
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────────

  Widget _zoneTile() {
    return InkWell(
      onTap: () async {
        final result = await Navigator.push<int>(
          context,
          MaterialPageRoute(builder: (_) => const ProZonePage()),
        );
        if (result != null && mounted) {
          setState(() => _rayonKm = result);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(children: [
          const Icon(Icons.social_distance_outlined, color: Color(0xFF0C5C6C), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Zone d\'intervention',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF888888))),
              Text('$_rayonKm km',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                      fontSize: 15, color: Color(0xFF1E2025))),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFBBBBBB)),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E2025)));
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? inputType,
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: inputType,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20, color: const Color(0xFF6E9E57)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          filled: true, fillColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _acceptClientsToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        const Icon(Icons.person_add_alt_1_outlined, color: Color(0xFF6E9E57), size: 20),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Accepter de nouveaux clients',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
            Text('Visible sur votre fiche publique',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          ]),
        ),
        Switch(
          value: _acceptNewClients,
          onChanged: (v) => setState(() => _acceptNewClients = v),
          activeThumbColor: const Color(0xFF6E9E57),
        ),
      ]),
    );
  }

  Widget _especesSelector() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _especesList.map((e) {
        final selected = _especesAcceptees.contains(e);
        return FilterChip(
          label: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
            color: selected ? Colors.white : const Color(0xFF1E2025))),
          selected: selected,
          onSelected: (v) => setState(() {
            if (v) { _especesAcceptees.add(e); } else { _especesAcceptees.remove(e); }
          }),
          selectedColor: const Color(0xFF6E9E57),
          checkmarkColor: Colors.white,
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDDDDDD)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );
  }

  Widget _certificationsEditor() {
    return Column(children: [
      ..._certifications.asMap().entries.map((e) {
        final i = e.key;
        final cert = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            const Icon(Icons.verified_outlined, color: Color(0xFF6E9E57), size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cert['nom'] ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
              if ((cert['numero'] ?? '').isNotEmpty)
                Text('N° ${cert['numero']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ])),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => setState(() => _certifications.removeAt(i)),
            ),
          ]),
        );
      }),
      OutlinedButton.icon(
        onPressed: _addCertification,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Ajouter une certification', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6E9E57),
          side: const BorderSide(color: Color(0xFF6E9E57)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    ]);
  }

  void _addCertification() {
    final nomCtrl    = TextEditingController();
    final numeroCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ajouter une certification',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nomCtrl,
            decoration: const InputDecoration(labelText: 'Nom de la certification',
              labelStyle: TextStyle(fontFamily: 'Galey')),
            style: const TextStyle(fontFamily: 'Galey')),
          const SizedBox(height: 10),
          TextField(controller: numeroCtrl,
            decoration: const InputDecoration(labelText: 'Numéro (optionnel)',
              labelStyle: TextStyle(fontFamily: 'Galey')),
            style: const TextStyle(fontFamily: 'Galey')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          ElevatedButton(
            onPressed: () {
              if (nomCtrl.text.trim().isNotEmpty) {
                setState(() => _certifications.add({
                  'nom': nomCtrl.text.trim(),
                  'numero': numeroCtrl.text.trim(),
                }));
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57)),
            child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Auto-inférence cat_pro ────────────────────────────────────────────────────

String _inferCatPro(String profession) {
  final p = profession.toLowerCase()
      .replaceAll('é', 'e').replaceAll('è', 'e').replaceAll('ê', 'e')
      .replaceAll('à', 'a').replaceAll('â', 'a').replaceAll('î', 'i');
  if (p.contains('veterinaire') || p.contains('veto') || p.contains('clinique veterinaire')) {
    return 'veterinaire';
  }
  if (p.contains('auxiliaire') || p.contains('infirmier') || p.contains('sante') ||
      p.contains('osteo') || p.contains('kine') || p.contains('naturo') ||
      p.contains('acupunct') || p.contains('homeo') || p.contains('therapeute') ||
      p.contains('soin')) {
    return 'sante';
  }
  if (p.contains('educateur') || p.contains('education') || p.contains('comportement') ||
      p.contains('dresseur') || p.contains('maitre-chien') || p.contains('maitre chien')) {
    return 'education';
  }
  if (p.contains('sitter') || p.contains('pension') || p.contains('promeneur') ||
      p.contains('garde') || p.contains('dog walker')) {
    return 'garde';
  }
  if (p.contains('toiletteur') || p.contains('toilettage') || p.contains('grooming')) {
    return 'toilettage';
  }
  if (p.contains('boutique') || p.contains('commerce') || p.contains('pharmacie') ||
      p.contains('animalerie') || p.contains('magasin')) {
    return 'referencement';
  }
  return 'sante';
}
