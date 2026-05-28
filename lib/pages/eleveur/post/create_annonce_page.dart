import 'dart:convert';
import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class CreateAnnoncePage extends StatefulWidget {
  final String? annonceId;
  final Map<String, dynamic>? initialData;
  const CreateAnnoncePage({super.key, this.annonceId, this.initialData});

  @override
  State<CreateAnnoncePage> createState() => _CreateAnnoncePageState();
}

class _CreateAnnoncePageState extends State<CreateAnnoncePage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  // ── Type ──────────────────────────────────────────────────────────────────────
  String _type = 'portee';
  String _typeVente = 'vente';

  // ── Espèce & Race ─────────────────────────────────────────────────────────────
  String _espece = 'chien';
  final _raceCtrl      = TextEditingController();
  final _raceFocusNode = FocusNode();

  // ── Photos annonce ────────────────────────────────────────────────────────────
  List<String> _photosUrls  = [];
  List<File>   _photosFiles = [];

  // ── Infos générales ───────────────────────────────────────────────────────────
  final _titreCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _prixCtrl  = TextEditingController();
  bool   _prixNegociable = false;
  String _statut = 'disponible';

  // ── Portée ───────────────────────────────────────────────────────────────────
  DateTime? _dateNaissance;
  int _nombreBebes = 1;
  List<Map<String, dynamic>> _animauxPortee = [];

  // ── Mère ──────────────────────────────────────────────────────────────────────
  String? _mereAnimalId;
  String? _merePhotoUrl;
  File?   _merePhotoFile;
  final _mereNomCtrl    = TextEditingController();
  final _merePuceCtrl   = TextEditingController();
  final _mereRaceCtrl   = TextEditingController();
  final _mereCouleurCtrl = TextEditingController();
  final _mereDescCtrl   = TextEditingController();
  String _mereRegistre = '';

  // ── Père ──────────────────────────────────────────────────────────────────────
  String? _pereAnimalId;
  String? _perePhotoUrl;
  File?   _perePhotoFile;
  final _pereNomCtrl    = TextEditingController();
  final _perePuceCtrl   = TextEditingController();
  final _pereRaceCtrl   = TextEditingController();
  final _pereCouleurCtrl = TextEditingController();
  final _pereDescCtrl   = TextEditingController();
  String _pereRegistre = '';

  // ── Pedigree ──────────────────────────────────────────────────────────────────
  String _registreType = '';
  final _numRegistreCtrl  = TextEditingController();
  final _clubPedigreeCtrl = TextEditingController();
  final _studbookCtrl     = TextEditingController();

  // ── Santé ─────────────────────────────────────────────────────────────────────
  bool _vaccines       = false;
  bool _vermifuge      = false;
  bool _identification = false;
  bool _bilanSante     = false;
  int  _semaines       = 8;

  // ── Portée prix ───────────────────────────────────────────────────────────────
  final _prixMinPorteeCtrl = TextEditingController();
  final _prixMaxPorteeCtrl = TextEditingController();

  // ── Animal individuel / Étalon ────────────────────────────────────────────────
  String?   _etalonAnimalId;
  String    _sexe = 'male';
  final _couleurCtrl = TextEditingController();
  DateTime? _dateNaissanceAnimal;
  bool _sterilise = false;
  final _sailliePrixCtrl = TextEditingController();
  final _saillieCondCtrl = TextEditingController();

  bool _saving = false;
  Map<String, List<String>> _allBreeds = {};

  // ── Espèces de l'éleveur ──────────────────────────────────────────────────────
  List<String> get _breederSpecies {
    final es = User_Info.especesElevees;
    if (es.isEmpty) return kSpeciesData.where((s) => s.value != 'tous').map((s) => s.value).toList();
    return es;
  }

  List<String> get _breederBreeds {
    final list = List<String>.from(_allBreeds[_espece] ?? []);
    if (!list.contains('Autre')) list.add('Autre');
    return list;
  }

  Future<void> _loadBreeds() async {
    const assets = {
      'chien':  'assets/dog_breeds.json',
      'chat':   'assets/cat_breeds.json',
      'cheval': 'assets/horse_breeds.json',
      'lapin':  'assets/rabbit_breeds.json',
      'oiseau': 'assets/bird_breeds.json',
      'nac':    'assets/nac_breeds.json',
      'ovin':   'assets/sheep_breeds.json',
      'caprin': 'assets/goat_breeds.json',
      'porcin': 'assets/pig_breeds.json',
    };
    final loaded = <String, List<String>>{};
    for (final e in assets.entries) {
      try {
        final raw = await rootBundle.loadString(e.value);
        loaded[e.key] = List<String>.from(jsonDecode(raw));
      } catch (_) {
        loaded[e.key] = [];
      }
    }
    if (mounted) setState(() => _allBreeds = loaded);
  }

  @override
  void initState() {
    super.initState();
    _loadBreeds();
    _loadInitialData();
    if (widget.initialData == null) {
      final es = _breederSpecies;
      if (es.isNotEmpty && !es.contains(_espece)) _espece = es.first;
    }
  }

  void _loadInitialData() {
    final d = widget.initialData;
    if (d == null) return;
    _type      = d['type'] ?? 'portee';
    _typeVente = d['type_vente'] ?? d['typeVente'] ?? 'vente';
    _espece    = d['espece'] ?? 'chien';
    _raceCtrl.text = d['race'] ?? '';
    _photosUrls = List<String>.from(d['photos'] ?? []);
    _titreCtrl.text = d['titre'] ?? '';
    _descCtrl.text  = d['description'] ?? '';
    _prixCtrl.text  = (d['prix'] as num?)?.toStringAsFixed(0) ?? '';
    _prixNegociable = d['prix_negociable'] ?? d['prixNegociable'] ?? false;
    _statut = d['statut'] ?? 'disponible';
    // Date naissance portée : Timestamp (Firestore) ou String ISO (Supabase)
    final dnRaw = d['date_naissance'] ?? d['dateNaissance'];
    if (dnRaw is Timestamp) _dateNaissance = dnRaw.toDate();
    else if (dnRaw is String && dnRaw.isNotEmpty) _dateNaissance = DateTime.tryParse(dnRaw);
    _nombreBebes = ((d['nombre_bebes'] ?? d['nombreBebes']) as num?)?.toInt() ?? 1;
    _animauxPortee = List<Map<String, dynamic>>.from(d['animaux_portee'] ?? d['animauxPortee'] ?? []);
    _mereAnimalId  = d['mere_animal_id'] ?? d['mereAnimalId'];
    _merePhotoUrl  = d['mere_photo_url'] ?? d['merePhotoUrl'];
    _mereNomCtrl.text     = d['mere_nom']         ?? d['mereNom']         ?? '';
    _merePuceCtrl.text    = d['mere_puce']         ?? d['merePuce']        ?? '';
    _mereRaceCtrl.text    = d['mere_race']         ?? d['mereRace']        ?? '';
    _mereCouleurCtrl.text = d['mere_couleur']      ?? d['mereCouleur']     ?? '';
    _mereDescCtrl.text    = d['mere_description']  ?? d['mereDescription'] ?? '';
    _mereRegistre = d['mere_registre'] ?? d['mereRegistre'] ?? '';
    _pereAnimalId  = d['pere_animal_id'] ?? d['pereAnimalId'];
    _perePhotoUrl  = d['pere_photo_url'] ?? d['perePhotoUrl'];
    _pereNomCtrl.text     = d['pere_nom']         ?? d['pereNom']         ?? '';
    _perePuceCtrl.text    = d['pere_puce']         ?? d['perePuce']        ?? '';
    _pereRaceCtrl.text    = d['pere_race']         ?? d['pereRace']        ?? '';
    _pereCouleurCtrl.text = d['pere_couleur']      ?? d['pereCouleur']     ?? '';
    _pereDescCtrl.text    = d['pere_description']  ?? d['pereDescription'] ?? '';
    _pereRegistre = d['pere_registre'] ?? d['pereRegistre'] ?? '';
    _registreType = d['registre_type'] ?? d['registreType'] ?? '';
    _numRegistreCtrl.text  = d['numero_registre'] ?? d['numeroRegistre'] ?? '';
    _clubPedigreeCtrl.text = d['club_pedigree']   ?? d['clubPedigree']   ?? '';
    _studbookCtrl.text     = d['studbook'] ?? '';
    _vaccines       = d['vaccines']      ?? false;
    _vermifuge      = d['vermifuge']     ?? false;
    _identification = d['identification'] ?? false;
    _bilanSante     = d['bilan_sante'] ?? d['bilanSante'] ?? false;
    _semaines = (d['semaines'] as num?)?.toInt() ?? 8;
    _prixMinPorteeCtrl.text = ((d['prix_min_portee'] ?? d['prixMinPortee']) as num?)?.toInt().toString() ?? '';
    _prixMaxPorteeCtrl.text = ((d['prix_max_portee'] ?? d['prixMaxPortee']) as num?)?.toInt().toString() ?? '';
    _etalonAnimalId   = d['etalon_animal_id'] ?? d['etalonAnimalId'];
    _sexe = d['sexe'] ?? 'male';
    _couleurCtrl.text     = d['couleur'] ?? '';
    _sailliePrixCtrl.text = (d['saillie_prix'] ?? d['sailliePrix'])?.toString() ?? '';
    _saillieCondCtrl.text = d['saillie_conditions'] ?? d['saillieConditions'] ?? '';
    // Date naissance animal : Timestamp (Firestore) ou String ISO (Supabase)
    final dnaRaw = d['date_naissance_animal'] ?? d['dateNaissanceAnimal'];
    if (dnaRaw is Timestamp) _dateNaissanceAnimal = dnaRaw.toDate();
    else if (dnaRaw is String && dnaRaw.isNotEmpty) _dateNaissanceAnimal = DateTime.tryParse(dnaRaw);
    _sterilise = d['sterilise'] ?? false;
  }

  @override
  void dispose() {
    _raceFocusNode.dispose();
    for (final c in [
      _raceCtrl, _titreCtrl, _descCtrl, _prixCtrl,
      _mereNomCtrl, _merePuceCtrl, _mereRaceCtrl, _mereCouleurCtrl, _mereDescCtrl,
      _pereNomCtrl, _perePuceCtrl, _pereRaceCtrl, _pereCouleurCtrl, _pereDescCtrl,
      _numRegistreCtrl, _clubPedigreeCtrl, _studbookCtrl, _couleurCtrl,
      _sailliePrixCtrl, _saillieCondCtrl, _prixMinPorteeCtrl, _prixMaxPorteeCtrl,
    ]) c.dispose();
    super.dispose();
  }

  // ── Registre adapté espèce ────────────────────────────────────────────────────

  List<String> _registreOptions() => switch (_espece) {
    'chien'  => ['LOF', 'En cours d\'inscription LOF', 'Non LOF', 'LOF étranger'],
    'chat'   => ['LOOF', 'En cours d\'inscription LOOF', 'Non LOOF', 'LOOF étranger'],
    'cheval' => ['SIRE + Studbook', 'SIRE sans studbook', 'Studbook étranger', 'Non inscrit'],
    'lapin'  => ['Livre généalogique ANCG', 'Autre registre', 'Non inscrit'],
    'oiseau' => ['Bagué FOCF/ANRO', 'Bagué autre fédération', 'Non bagué'],
    _        => ['Registre officiel', 'Autre registre', 'Non inscrit'],
  };

  String _registreLabel() => switch (_espece) {
    'chien'  => 'LOF',
    'chat'   => 'LOOF',
    'cheval' => 'SIRE',
    _        => 'Registre',
  };

  // ── Photo helpers ─────────────────────────────────────────────────────────────

  Future<File?> _pickAndCrop() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return null;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recadrer',
          toolbarColor: _teal,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: _green,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Recadrer',
          aspectRatioLockEnabled: true,
          minimumAspectRatio: 1.0,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    return cropped != null ? File(cropped.path) : null;
  }

  Future<void> _pickAnnoncePhoto() async {
    if (_photosUrls.length + _photosFiles.length >= 4) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 4 photos', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    final f = await _pickAndCrop();
    if (f != null) setState(() => _photosFiles.add(f));
  }

  Future<void> _pickMerePhoto() async {
    final f = await _pickAndCrop();
    if (f != null) setState(() { _merePhotoFile = f; _merePhotoUrl = null; });
  }

  Future<void> _pickPerePhoto() async {
    final f = await _pickAndCrop();
    if (f != null) setState(() { _perePhotoFile = f; _perePhotoUrl = null; });
  }

  // ── Animal pickers ────────────────────────────────────────────────────────────

  Future<void> _pickAnimalForMere() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AnimalPickerSheet(espece: _espece, sexeFilter: 'femelle'),
    );
    if (r != null && mounted) setState(() {
      _mereAnimalId         = r['id'];
      _mereNomCtrl.text     = r['nom']            ?? '';
      _merePuceCtrl.text    = r['identification'] ?? '';
      _mereRaceCtrl.text    = r['race']           ?? '';
      _mereCouleurCtrl.text = r['couleur']        ?? '';
      _mereDescCtrl.text    = r['description']    ?? '';
      _merePhotoUrl    = r['photoUrl'];
      _merePhotoFile   = null;
    });
  }

  Future<void> _pickAnimalForPere() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AnimalPickerSheet(espece: _espece, sexeFilter: 'male'),
    );
    if (r != null && mounted) setState(() {
      _pereAnimalId         = r['id'];
      _pereNomCtrl.text     = r['nom']            ?? '';
      _perePuceCtrl.text    = r['identification'] ?? '';
      _pereRaceCtrl.text    = r['race']           ?? '';
      _pereCouleurCtrl.text = r['couleur']        ?? '';
      _pereDescCtrl.text    = r['description']    ?? '';
      _perePhotoUrl    = r['photoUrl'];
      _perePhotoFile   = null;
    });
  }

  Future<void> _pickEtalon() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AnimalPickerSheet(espece: _espece, sexeFilter: 'male'),
    );
    if (r != null && mounted) setState(() {
      _etalonAnimalId = r['id'];
      _sexe = 'male';
      _couleurCtrl.text = r['couleur'] ?? '';
      if (r['photoUrl'] != null) { _photosUrls = [r['photoUrl']]; _photosFiles = []; }
      final dn = r['dateNaissance'] as Timestamp?;
      if (dn != null) _dateNaissanceAnimal = dn.toDate();
      if (_titreCtrl.text.isEmpty && (r['nom'] ?? '').isNotEmpty) {
        _titreCtrl.text = '${r['nom']} — Saillie ${_raceCtrl.text}'.trim();
      }
      if (_descCtrl.text.isEmpty && (r['description'] ?? '').isNotEmpty) {
        _descCtrl.text = r['description'];
      }
    });
  }

  // ── Upload ────────────────────────────────────────────────────────────────────

  Future<String> _uploadFile(File file, String folder) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    return uploadPhoto(file, '$folder/$uid/$name');
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_raceCtrl.text.trim().isEmpty && _titreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez saisir une race ou un titre',
              style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _saving = true);
    try {
      // Photos annonce
      final newUrls = <String>[];
      for (final f in _photosFiles) newUrls.add(await _uploadFile(f, 'annonces'));
      final allPhotos = [..._photosUrls, ...newUrls];

      // Photos parents
      String? merePhotoUrl = _merePhotoUrl;
      if (_merePhotoFile != null) merePhotoUrl = await _uploadFile(_merePhotoFile!, 'annonces/parents');
      String? perePhotoUrl = _perePhotoUrl;
      if (_perePhotoFile != null) perePhotoUrl = await _uploadFile(_perePhotoFile!, 'annonces/parents');

      // Photos bébés inline
      final animauxSaved = <Map<String, dynamic>>[];
      for (final animal in _animauxPortee) {
        if (animal['isLinked'] == true) { animauxSaved.add(animal); continue; }
        final localPaths = List<String>.from(animal['photos'] ?? []);
        final uploaded = <String>[];
        for (final p in localPaths) {
          uploaded.add(p.startsWith('http') ? p : await _uploadFile(File(p), 'annonces/animaux'));
        }
        animauxSaved.add({...animal, 'photos': uploaded});
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userRow = await Supabase.instance.client
          .from('users').select().eq('uid', uid).single();

      final nomEleveur = (userRow['name_elevage'] as String?)?.isNotEmpty == true
          ? userRow['name_elevage'] as String
          : userRow['firstname'] as String? ?? '';
      final villeEleveur =
          (userRow['ville_elevage'] as String?) ?? (userRow['ville'] as String?) ?? '';
      final departementEleveur = () {
        final dep = userRow['departement_elevage'] as String?;
        if (dep != null && dep.isNotEmpty) return dep;
        final cp = (userRow['code_postal_elevage'] as String?) ?? '';
        return FrenchGeo.fromPostalCode(cp)?.departement ?? '';
      }();
      final regionEleveur = () {
        final reg = userRow['region_elevage'] as String?;
        if (reg != null && reg.isNotEmpty) return reg;
        final cp = (userRow['code_postal_elevage'] as String?) ?? '';
        return FrenchGeo.fromPostalCode(cp)?.region ?? '';
      }();

      final now = DateTime.now().toIso8601String();
      final supaData = <String, dynamic>{
        'uid_eleveur':          uid,
        'nom_eleveur':          nomEleveur,
        'ville_eleveur':        villeEleveur,
        'departement_eleveur':  departementEleveur,
        'region_eleveur':       regionEleveur,
        'pays_eleveur':         userRow['pays_elevage'] ?? 'France',
        'type':                 _type,
        'type_vente':           _typeVente,
        'espece':               _espece,
        'race':                 _raceCtrl.text.trim(),
        'titre':                _titreCtrl.text.trim(),
        'description':          _descCtrl.text.trim(),
        'photos':               allPhotos,
        'prix': _typeVente == 'vente' ? double.tryParse(_prixCtrl.text) : null,
        'prix_negociable':      _prixNegociable,
        'statut':               _statut,
        'date_naissance': _type == 'portee' && _dateNaissance != null
            ? _dateNaissance!.toIso8601String().substring(0, 10) : null,
        'nombre_bebes':         _type == 'portee' ? _nombreBebes : null,
        'animaux_portee':       _type == 'portee' ? animauxSaved : null,
        'prix_min_portee':
            _type == 'portee' ? double.tryParse(_prixMinPorteeCtrl.text) : null,
        'prix_max_portee':
            _type == 'portee' ? double.tryParse(_prixMaxPorteeCtrl.text) : null,
        'mere_animal_id':       _mereAnimalId,
        'mere_photo_url':       merePhotoUrl,
        'mere_nom':             _mereNomCtrl.text.trim(),
        'mere_puce':            _merePuceCtrl.text.trim(),
        'mere_identification':  _merePuceCtrl.text.trim(),
        'mere_race':            _mereRaceCtrl.text.trim(),
        'mere_couleur':         _mereCouleurCtrl.text.trim(),
        'mere_description':     _mereDescCtrl.text.trim(),
        'mere_registre':        _mereRegistre,
        'pere_animal_id':       _pereAnimalId,
        'pere_photo_url':       perePhotoUrl,
        'pere_nom':             _pereNomCtrl.text.trim(),
        'pere_puce':            _perePuceCtrl.text.trim(),
        'pere_identification':  _perePuceCtrl.text.trim(),
        'pere_race':            _pereRaceCtrl.text.trim(),
        'pere_couleur':         _pereCouleurCtrl.text.trim(),
        'pere_description':     _pereDescCtrl.text.trim(),
        'pere_registre':        _pereRegistre,
        'registre_type':        _registreType,
        'numero_registre':      _numRegistreCtrl.text.trim(),
        'club_pedigree':        _clubPedigreeCtrl.text.trim(),
        'studbook': _espece == 'cheval' ? _studbookCtrl.text.trim() : null,
        'vaccines':             _vaccines,
        'vermifuge':            _vermifuge,
        'identification':       _identification,
        'bilan_sante':          _bilanSante,
        'semaines':             _typeVente == 'saillie' ? null : _semaines,
        'etalon_animal_id':     _etalonAnimalId,
        'sexe':    _type != 'portee' ? _sexe : null,
        'couleur': _couleurCtrl.text.trim(),
        'date_naissance_animal': _type != 'portee' && _dateNaissanceAnimal != null
            ? _dateNaissanceAnimal!.toIso8601String().substring(0, 10) : null,
        'sterilise': _type != 'portee' ? _sterilise : null,
        'saillie_prix': _typeVente == 'saillie' ? double.tryParse(_sailliePrixCtrl.text) : null,
        'saillie_conditions':
            _typeVente == 'saillie' ? _saillieCondCtrl.text.trim() : null,
        'updated_at': now,
      };

      if (widget.annonceId != null) {
        await Supabase.instance.client
            .from('annonces').update(supaData).eq('id', widget.annonceId!);
      } else {
        supaData['created_at'] = now;
        supaData['expires_at'] =
            DateTime.now().add(const Duration(days: 30)).toIso8601String();
        supaData['vues']     = 0;
        supaData['contacts'] = 0;
        await Supabase.instance.client.from('annonces').insert(supaData);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSaillie = _typeVente == 'saillie';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(widget.annonceId == null ? 'Nouvelle annonce' : 'Modifier l\'annonce',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : TextButton(onPressed: _save,
                  child: const Text('Publier', style: TextStyle(color: Colors.white,
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionType(),         const SizedBox(height: 12),
            _sectionEspece(),       const SizedBox(height: 12),
            _sectionPhotos(),       const SizedBox(height: 12),
            _sectionInfos(),        const SizedBox(height: 12),
            if (_type == 'portee') ...[_sectionPortee(), const SizedBox(height: 12)],
            if (_type == 'animal') ...[_sectionAnimal(), const SizedBox(height: 12)],
            if (isSaillie) ...[_sectionSaillie(), const SizedBox(height: 12)],
            if (!isSaillie) ...[_sectionMere(), const SizedBox(height: 12)],
            if (!isSaillie) ...[_sectionPere(), const SizedBox(height: 12)],
            _sectionPedigree(),     const SizedBox(height: 12),
            _sectionSante(),
            if (_type == 'portee') ...[const SizedBox(height: 12), _sectionAnimauxPortee()],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  widget.annonceId == null ? 'Publier l\'annonce' : 'Enregistrer les modifications',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── Helpers visuels ─────────────────────────────────────────────────────────

  Widget _card(String title, IconData icon, List<Widget> children) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))]),
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: _teal, size: 18), const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
            fontSize: 14, color: _teal)),
      ]),
      const SizedBox(height: 14),
      ...children,
    ]),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
        fontWeight: FontWeight.w600, color: Color(0xFF6F767B))),
  );

  static InputDecoration _inputDeco(String hint, {IconData? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    suffixIcon: suffix != null ? Icon(suffix, size: 18, color: const Color(0xFF6F767B)) : null,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _teal)),
    filled: true, fillColor: const Color(0xFFF8F9FA),
  );

  Widget _textField(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboardType}) =>
    TextFormField(controller: ctrl, maxLines: maxLines, keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
      decoration: _inputDeco(hint));

  Widget _raceField() {
    final breeds = _breederBreeds;
    if (breeds.isEmpty) return _textField(_raceCtrl, 'Ex: Berger Australien, KWPN, Angora...');
    return GestureDetector(
      onTap: () => _openRaceBreedPicker(breeds),
      child: AbsorbPointer(
        child: TextFormField(
          controller: _raceCtrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
          decoration: _inputDeco('Appuyer pour choisir une race...', suffix: Icons.keyboard_arrow_down),
        ),
      ),
    );
  }

  Future<void> _openRaceBreedPicker(List<String> breeds) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AnnonceBreedPickerSheet(breeds: breeds, current: _raceCtrl.text),
    );
    if (selected != null) setState(() => _raceCtrl.text = selected);
  }

  Widget _chips(List<String> options, String selected, ValueChanged<String> onSelect) =>
    Wrap(spacing: 8, runSpacing: 6,
      children: options.map((opt) => GestureDetector(onTap: () => onSelect(opt),
        child: AnimatedContainer(duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected == opt ? _teal : Colors.transparent,
            border: Border.all(color: selected == opt ? _teal : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20)),
          child: Text(opt, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected == opt ? Colors.white : Colors.black87)))
      )).toList(),
    );

  Widget _datePicker(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    final fmt = DateFormat('dd/MM/yyyy');
    return GestureDetector(
      onTap: () async {
        final d = await showDatePicker(context: context,
          initialDate: value ?? DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(primary: _teal)), child: child!));
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFF8F9FA),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6F767B)),
          const SizedBox(width: 8),
          Text(value != null ? fmt.format(value) : label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: value != null ? const Color(0xFF1F2A2E) : const Color(0xFF9CA3AF))),
        ]),
      ),
    );
  }

  Widget _checkRow(IconData icon, String label, bool value, ValueChanged<bool> onChanged) =>
    InkWell(onTap: () => onChanged(!value),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 28, height: 28,
              child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false),
                  activeColor: _teal, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
          const SizedBox(width: 6),
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 7),
          Flexible(child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
              color: Color(0xFF1F2A2E)))),
        ]),
      ),
    );

  // ─── Widget "animal sélectionné" chip ─────────────────────────────────────────

  Widget _parentChip({
    required String nom,
    String? photoUrl,
    File? photoFile,
    required VoidCallback onClear,
    required VoidCallback onPickPhoto,
  }) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: _teal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _teal.withValues(alpha: 0.2))),
    child: Row(children: [
      GestureDetector(
        onTap: onPickPhoto,
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 44, height: 44,
              child: photoFile != null ? Image.file(photoFile, fit: BoxFit.cover)
                  : photoUrl != null ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.contain)
                  : Container(color: const Color(0xFFEEF5EA),
                      child: const Icon(Icons.add_a_photo_outlined, color: _teal, size: 20)),
            ),
          ),
          Positioned(bottom: 0, right: 0,
            child: Container(width: 16, height: 16,
              decoration: BoxDecoration(color: _teal, shape: BoxShape.circle),
              child: const Icon(Icons.edit, color: Colors.white, size: 10))),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(child: Row(children: [
        const Icon(Icons.link, size: 14, color: _teal),
        const SizedBox(width: 4),
        Expanded(child: Text('Lié : $nom',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600, color: _teal),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ])),
      GestureDetector(onTap: onClear,
        child: const Icon(Icons.close, size: 16, color: Color(0xFF6F767B))),
    ]),
  );

  // ─── Widget mini photo parent (sans chip) ─────────────────────────────────────

  Widget _parentPhotoBox(String? url, File? file, VoidCallback onPick, VoidCallback? onRemove) =>
    GestureDetector(
      onTap: onPick,
      child: Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 72, height: 72,
            child: file != null ? Image.file(file, fit: BoxFit.cover)
                : url != null ? CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)
                : Container(color: const Color(0xFFEEF5EA),
                    child: const Icon(Icons.add_a_photo_outlined, color: _teal, size: 26)),
          ),
        ),
        if (file != null || url != null)
          Positioned(top: 2, right: 2,
            child: GestureDetector(onTap: onRemove,
              child: Container(width: 18, height: 18,
                decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 11)))),
        Positioned(bottom: 2, right: 2,
          child: Container(width: 18, height: 18,
            decoration: BoxDecoration(color: _teal.withValues(alpha: 0.8), shape: BoxShape.circle),
            child: const Icon(Icons.edit, color: Colors.white, size: 10))),
      ]),
    );

  // ─── Sections ─────────────────────────────────────────────────────────────────

  Widget _sectionType() => _card('Type d\'annonce', Icons.campaign_outlined, [
    _label('Type de cession'),
    Wrap(spacing: 8, runSpacing: 6, children: [
      for (final v in [('vente', 'Vente €', Icons.sell_outlined),
                       ('adoption', 'Adoption / Don', Icons.favorite_outline),
                       ('saillie', 'Saillie', Icons.diversity_1_outlined)])
        GestureDetector(
          onTap: () => setState(() {
            _typeVente = v.$1;
            if (v.$1 == 'saillie') _type = 'animal';
          }),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _typeVente == v.$1 ? _green : Colors.transparent,
              border: Border.all(color: _typeVente == v.$1 ? _green : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(v.$3, size: 14, color: _typeVente == v.$1 ? Colors.white : Colors.grey),
              const SizedBox(width: 6),
              Text(v.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _typeVente == v.$1 ? Colors.white : Colors.grey)),
            ]),
          ),
        ),
    ]),
    const SizedBox(height: 14),
    if (_typeVente != 'saillie') ...[
      _label('Que souhaitez-vous publier ?'),
      Row(children: [
        for (final t in [('portee', 'Portée', Icons.group_outlined),
                         ('animal', 'Animal individuel', Icons.cruelty_free_outlined)])
          Expanded(child: Padding(
            padding: EdgeInsets.only(right: t.$1 == 'portee' ? 6 : 0, left: t.$1 == 'animal' ? 6 : 0),
            child: GestureDetector(onTap: () => setState(() => _type = t.$1),
              child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _type == t.$1 ? _teal : Colors.transparent,
                  border: Border.all(color: _type == t.$1 ? _teal : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(t.$3, size: 22, color: _type == t.$1 ? Colors.white : Colors.grey),
                  const SizedBox(height: 5),
                  Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _type == t.$1 ? Colors.white : Colors.grey),
                      textAlign: TextAlign.center),
                ]),
              ),
            ),
          )),
      ]),
    ] else Padding(
      padding: const EdgeInsets.only(top: 0),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 13, color: Color(0xFF6F767B)),
        const SizedBox(width: 5),
        Text('La saillie s\'applique à un animal individuel',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
      ]),
    ),
  ]);

  Widget _sectionEspece() {
    final breederSpecies = _breederSpecies;
    return _card('Espèce & Race', Icons.pets_outlined, [
      _label('Espèce'),
      Wrap(spacing: 8, runSpacing: 8,
        children: kSpeciesData
            .where((s) => s.value != 'tous' && breederSpecies.contains(s.value))
            .map((s) => GestureDetector(
          onTap: () => setState(() {
            _espece = s.value; _registreType = ''; _mereRegistre = ''; _pereRegistre = '';
          }),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _espece == s.value ? s.color : Colors.transparent,
              border: Border.all(color: _espece == s.value ? s.color : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              speciesIcon(s.value, 12, _espece == s.value ? Colors.white : s.color),
              const SizedBox(width: 5),
              Text(s.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _espece == s.value ? Colors.white : Colors.black87)),
            ]),
          ),
        )).toList(),
      ),
      const SizedBox(height: 12),
      _label('Race'),
      _raceField(),
    ]);
  }

  Widget _sectionPhotos() {
    final total = _photosUrls.length + _photosFiles.length;
    return _card('Photos', Icons.photo_library_outlined, [
      Row(children: [
        Text('$total / 4  •  Format carré',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
        const Spacer(),
        if (total < 4) TextButton.icon(onPressed: _pickAnnoncePhoto,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 16, color: _teal),
          label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal)),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact)),
      ]),
      const SizedBox(height: 8),
      SizedBox(height: 100, child: ListView(scrollDirection: Axis.horizontal, children: [
        ..._photosUrls.asMap().entries.map((e) => _photoThumb(
            e.key == 0, () => setState(() => _photosUrls.removeAt(e.key)), url: e.value)),
        ..._photosFiles.asMap().entries.map((e) => _photoThumb(
            _photosUrls.isEmpty && e.key == 0,
            () => setState(() => _photosFiles.removeAt(e.key)), file: e.value)),
        if (total < 4) GestureDetector(onTap: _pickAnnoncePhoto,
          child: Container(width: 100, height: 100, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: const Color(0xFFF8F9FA),
                border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate_outlined, color: _teal, size: 28),
              SizedBox(height: 4),
              Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _teal)),
            ]))),
      ])),
    ]);
  }

  Widget _photoThumb(bool isMain, VoidCallback onRemove, {String? url, File? file}) =>
    Stack(children: [
      Container(width: 100, height: 100, margin: const EdgeInsets.only(right: 8),
        child: ClipRRect(borderRadius: BorderRadius.circular(10),
          child: url != null ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
              : Image.file(file!, fit: BoxFit.cover))),
      Positioned(top: 4, right: 12,
        child: GestureDetector(onTap: onRemove,
          child: Container(width: 22, height: 22,
            decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.close, color: Colors.white, size: 13)))),
      if (isMain) Positioned(bottom: 6, left: 4,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: _teal.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(5)),
          child: const Text('Principal', style: TextStyle(fontFamily: 'Galey',
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)))),
    ]);

  Widget _sectionInfos() => _card('Informations', Icons.info_outline, [
    _label('Titre de l\'annonce'),
    _textField(_titreCtrl, 'Ex: Chiots Berger Australien LOF disponibles'),
    const SizedBox(height: 10),
    _label('Description'),
    _textField(_descCtrl, 'Décrivez l\'annonce, la famille, les conditions...', maxLines: 4),
    if (_typeVente == 'vente') ...[
      const SizedBox(height: 10),
      _label('Prix (€)'),
      Row(children: [
        Expanded(child: _textField(_prixCtrl, '0', keyboardType: TextInputType.number)),
        const SizedBox(width: 12),
        GestureDetector(onTap: () => setState(() => _prixNegociable = !_prixNegociable),
          child: Row(children: [
            Checkbox(value: _prixNegociable, onChanged: (v) => setState(() => _prixNegociable = v ?? false),
                activeColor: _teal, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            const Text('Négociable', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
          ])),
      ]),
    ],
    const SizedBox(height: 10),
    _label('Statut'),
    Wrap(spacing: 8, runSpacing: 6, children: [
      for (final s in [('disponible', 'Disponible', _green),
                       ('reserve', 'Réservé', Color(0xFFF59E0B)),
                       ('vendu', _typeVente == 'adoption' ? 'Cédé' : 'Vendu', Colors.blueGrey)])
        GestureDetector(onTap: () => setState(() => _statut = s.$1),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _statut == s.$1 ? s.$3 : Colors.transparent,
              border: Border.all(color: _statut == s.$1 ? s.$3 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20)),
            child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _statut == s.$1 ? Colors.white : Colors.black87)))),
    ]),
  ]);

  Widget _sectionPortee() => _card('Portée', Icons.group_outlined, [
    _label('Date de naissance'),
    _datePicker('Sélectionner une date', _dateNaissance,
        (d) => setState(() => _dateNaissance = d)),
    const SizedBox(height: 12),
    _label('Nombre de bébés dans la portée'),
    Row(children: [
      IconButton(onPressed: () => setState(() { if (_nombreBebes > 1) _nombreBebes--; }),
          icon: const Icon(Icons.remove_circle_outline, color: _teal, size: 28),
          padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      const SizedBox(width: 12),
      Text('$_nombreBebes', style: const TextStyle(fontFamily: 'Galey',
          fontWeight: FontWeight.w700, fontSize: 22, color: Color(0xFF1F2A2E))),
      const SizedBox(width: 12),
      IconButton(onPressed: () => setState(() { if (_nombreBebes < 20) _nombreBebes++; }),
          icon: const Icon(Icons.add_circle_outline, color: _teal, size: 28),
          padding: EdgeInsets.zero, constraints: const BoxConstraints()),
    ]),
    const SizedBox(height: 12),
    _label('Fourchette de prix par bébé (€)'),
    Row(children: [
      Expanded(child: _textField(_prixMinPorteeCtrl, 'Min',
          keyboardType: TextInputType.number)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('—', style: TextStyle(fontFamily: 'Galey', fontSize: 18,
            color: Colors.grey.shade400))),
      Expanded(child: _textField(_prixMaxPorteeCtrl, 'Max',
          keyboardType: TextInputType.number)),
    ]),
  ]);

  Widget _sectionAnimal() => _card(
    _typeVente == 'saillie' ? 'Étalon / Reproducteur' : 'Animal',
    _typeVente == 'saillie' ? Icons.diversity_1_outlined : Icons.cruelty_free_outlined,
    [
      // Saillie : bouton "chercher dans mes animaux"
      if (_typeVente == 'saillie') ...[
        OutlinedButton.icon(
          onPressed: _pickEtalon,
          icon: const Icon(Icons.search, size: 16, color: _teal),
          label: Text(_etalonAnimalId != null ? 'Changer d\'animal' : 'Chercher dans mes animaux',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: _teal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14)),
        ),
        if (_etalonAnimalId != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.check_circle, size: 14, color: _green),
            const SizedBox(width: 4),
            Text('Animal lié — vous pouvez modifier les champs ci-dessous',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ],
        const SizedBox(height: 10),
      ],
      _label('Sexe'),
      Wrap(spacing: 8, children: [
        for (final s in [('male', '♂ Mâle'), ('femelle', '♀ Femelle')])
          GestureDetector(onTap: () => setState(() => _sexe = s.$1),
            child: AnimatedContainer(duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: _sexe == s.$1 ? _teal : Colors.transparent,
                border: Border.all(color: _sexe == s.$1 ? _teal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20)),
              child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _sexe == s.$1 ? Colors.white : Colors.grey)))),
      ]),
      const SizedBox(height: 10),
      _label('Couleur / Robe'),
      _textField(_couleurCtrl, 'Ex: Tricolore, Roux, Noir et blanc...'),
      const SizedBox(height: 10),
      _label('Date de naissance'),
      _datePicker('Sélectionner une date', _dateNaissanceAnimal,
          (d) => setState(() => _dateNaissanceAnimal = d)),
      if (_typeVente != 'saillie') ...[
        const SizedBox(height: 6),
        _checkRow(Icons.cut_outlined, 'Stérilisé(e)', _sterilise,
            (v) => setState(() => _sterilise = v)),
      ],
    ],
  );

  Widget _sectionSaillie() => _card('Conditions de saillie', Icons.handshake_outlined, [
    _label('Prix de la saillie (€) — laisser vide si gratuit'),
    _textField(_sailliePrixCtrl, '0', keyboardType: TextInputType.number),
    const SizedBox(height: 10),
    _label('Conditions & informations complémentaires'),
    _textField(_saillieCondCtrl,
        'Ex: Droit au chiot, contrat de saillie, tests génétiques requis...', maxLines: 3),
  ]);

  Widget _sectionMere() => _card('Mère', Icons.female, [
    // Chip si animal lié
    if (_mereAnimalId != null) ...[
      _parentChip(
        nom: _mereNomCtrl.text,
        photoUrl: _merePhotoUrl,
        photoFile: _merePhotoFile,
        onClear: () => setState(() {
          _mereAnimalId = null; _merePhotoUrl = null; _merePhotoFile = null;
        }),
        onPickPhoto: _pickMerePhoto,
      ),
      const SizedBox(height: 10),
    ],
    // Ligne photo + bouton chercher
    Row(children: [
      if (_mereAnimalId == null)
        _parentPhotoBox(_merePhotoUrl, _merePhotoFile, _pickMerePhoto,
            () => setState(() { _merePhotoUrl = null; _merePhotoFile = null; })),
      if (_mereAnimalId == null) const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _pickAnimalForMere,
          icon: const Icon(Icons.search, size: 16, color: _teal),
          label: Text(_mereAnimalId != null ? 'Changer d\'animal' : 'Chercher dans mes animaux',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: _teal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12)),
        ),
      ),
    ]),
    const SizedBox(height: 10),
    _label('Nom de la mère'),
    _textField(_mereNomCtrl, 'Nom'),
    const SizedBox(height: 10),
    _label('Identification (puce / tatouage)'),
    _textField(_merePuceCtrl, 'Numéro de puce ou tatouage'),
    const SizedBox(height: 10),
    _label('Race'),
    _textField(_mereRaceCtrl, 'Race de la mère'),
    const SizedBox(height: 10),
    _label('Couleur / Robe'),
    _textField(_mereCouleurCtrl, 'Ex: Fauve, Tricolore…'),
    const SizedBox(height: 10),
    _label('Description'),
    _textField(_mereDescCtrl, 'Caractère, morphologie…', maxLines: 3),
    const SizedBox(height: 10),
    _label('${_registreLabel()} de la mère'),
    _chips(_registreOptions(), _mereRegistre, (v) => setState(() => _mereRegistre = v)),
  ]);

  Widget _sectionPere() => _card(
    _typeVente == 'saillie' ? 'Père (optionnel)' : 'Père',
    Icons.male,
    [
      if (_pereAnimalId != null) ...[
        _parentChip(
          nom: _pereNomCtrl.text,
          photoUrl: _perePhotoUrl,
          photoFile: _perePhotoFile,
          onClear: () => setState(() {
            _pereAnimalId = null; _perePhotoUrl = null; _perePhotoFile = null;
          }),
          onPickPhoto: _pickPerePhoto,
        ),
        const SizedBox(height: 10),
      ],
      Row(children: [
        if (_pereAnimalId == null)
          _parentPhotoBox(_perePhotoUrl, _perePhotoFile, _pickPerePhoto,
              () => setState(() { _perePhotoUrl = null; _perePhotoFile = null; })),
        if (_pereAnimalId == null) const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickAnimalForPere,
            icon: const Icon(Icons.search, size: 16, color: _teal),
            label: Text(_pereAnimalId != null ? 'Changer d\'animal' : 'Chercher dans mes animaux',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      _label('Nom du père'),
      _textField(_pereNomCtrl, 'Nom'),
      const SizedBox(height: 10),
      _label('Identification (puce / tatouage)'),
      _textField(_perePuceCtrl, 'Numéro de puce ou tatouage'),
      const SizedBox(height: 10),
      _label('Race'),
      _textField(_pereRaceCtrl, 'Race du père'),
      const SizedBox(height: 10),
      _label('Couleur / Robe'),
      _textField(_pereCouleurCtrl, 'Ex: Fauve, Tricolore…'),
      const SizedBox(height: 10),
      _label('Description'),
      _textField(_pereDescCtrl, 'Caractère, morphologie…', maxLines: 3),
      const SizedBox(height: 10),
      _label('${_registreLabel()} du père'),
      _chips(_registreOptions(), _pereRegistre, (v) => setState(() => _pereRegistre = v)),
    ],
  );

  Widget _sectionPedigree() => _card('Pedigree & Généalogie', Icons.account_tree_outlined, [
    _label('Statut ${_registreLabel()}'),
    _chips(_registreOptions(), _registreType, (v) => setState(() => _registreType = v)),
    const SizedBox(height: 10),
    _label('Numéro d\'inscription au registre'),
    _textField(_numRegistreCtrl, 'Ex: 12345/00, FR•012345•00...'),
    if (_espece == 'cheval') ...[
      const SizedBox(height: 10),
      _label('Studbook / Livre généalogique de la race'),
      _textField(_studbookCtrl, 'Ex: SF, KWPN, AA, PSI, Haflinger...'),
    ],
    const SizedBox(height: 10),
    _label('Club de race / Association pedigree'),
    _textField(_clubPedigreeCtrl, 'Ex: SCC, Club du Berger Australien...'),
  ]);

  Widget _sectionSante() => _card('Santé & Conformité', Icons.health_and_safety_outlined, [
    _label('Informations sanitaires'),
    _checkRow(Icons.vaccines_outlined, 'Vacciné(e)', _vaccines,
        (v) => setState(() => _vaccines = v)),
    _checkRow(Icons.medication_outlined, 'Vermifugé(e)', _vermifuge,
        (v) => setState(() => _vermifuge = v)),
    _checkRow(Icons.qr_code_outlined, 'Pucé(e) / Tatoué(e)', _identification,
        (v) => setState(() => _identification = v)),
    _checkRow(Icons.medical_services_outlined, 'Bilan de santé vétérinaire', _bilanSante,
        (v) => setState(() => _bilanSante = v)),
    // Âge de cession uniquement pour vente/adoption (pas saillie)
    if (_typeVente != 'saillie') ...[
      const SizedBox(height: 12),
      _label('Âge minimum à la cession'),
      Row(children: [
        IconButton(onPressed: () => setState(() { if (_semaines > 4) _semaines--; }),
            icon: const Icon(Icons.remove_circle_outline, color: _teal),
            padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        const SizedBox(width: 10),
        Text('$_semaines semaines', style: const TextStyle(fontFamily: 'Galey',
            fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
        const SizedBox(width: 10),
        IconButton(onPressed: () => setState(() { if (_semaines < 52) _semaines++; }),
            icon: const Icon(Icons.add_circle_outline, color: _teal),
            padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        if (_semaines < 8)
          const Text('  ⚠ min. légal : 8 sem.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.redAccent)),
      ]),
    ],
  ]);

  Widget _sectionAnimauxPortee() => _card('Animaux de la portée', Icons.pets_outlined, [
    if (_animauxPortee.isEmpty)
      Padding(padding: const EdgeInsets.only(bottom: 8),
        child: Text('Aucun animal rattaché pour l\'instant.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500))),
    ..._animauxPortee.asMap().entries.map((e) => _animalPorteeCard(e.key, e.value)),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: _addAnimalInline,
        icon: const Icon(Icons.add, size: 16, color: _teal),
        label: const Text('Créer un bébé', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
        style: OutlinedButton.styleFrom(side: const BorderSide(color: _teal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 12)))),
      const SizedBox(width: 8),
      Expanded(child: OutlinedButton.icon(onPressed: _linkExistingAnimal,
        icon: const Icon(Icons.link, size: 16, color: _green),
        label: const Text('Rattacher existant', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _green)),
        style: OutlinedButton.styleFrom(side: const BorderSide(color: _green),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 12)))),
    ]),
  ]);

  Widget _animalPorteeCard(int index, Map<String, dynamic> animal) {
    final statut = animal['statut'] ?? 'disponible';
    final statusColor = statut == 'disponible' ? _green
        : statut == 'reserve' ? const Color(0xFFF59E0B) : Colors.blueGrey;
    final photos = List<String>.from(animal['photos'] ?? []);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 52, height: 52,
            child: photos.isNotEmpty
                ? (photos.first.startsWith('http')
                    ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.contain)
                    : Image.file(File(photos.first), fit: BoxFit.cover))
                : Container(color: const Color(0xFFEEF5EA),
                    child: const Icon(Icons.pets, size: 24, color: _green)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(animal['nom']?.isNotEmpty == true ? animal['nom'] : 'Sans nom',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
          Text('${animal['sexe'] == 'male' ? '♂ Mâle' : '♀ Femelle'}'
              '${(animal['couleur'] ?? '').isNotEmpty ? ' · ${animal['couleur']}' : ''}'
              '${animal['isLinked'] == true ? ' · lié' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
        ])),
        if (animal['isLinked'] != true)
          IconButton(icon: const Icon(Icons.edit_outlined, color: _teal, size: 18),
              onPressed: () => _editAnimalInline(index, animal),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
        GestureDetector(
          onTap: () {
            const statuts = ['disponible', 'reserve', 'vendu'];
            final next = statuts[(statuts.indexOf(statut) + 1) % statuts.length];
            setState(() => _animauxPortee[index] = {...animal, 'statut': next});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(statut == 'disponible' ? 'Dispo' : statut == 'reserve' ? 'Réservé' : 'Vendu',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                    fontWeight: FontWeight.w600, color: statusColor))),
        ),
        const SizedBox(width: 4),
        GestureDetector(onTap: () => setState(() => _animauxPortee.removeAt(index)),
            child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18)),
      ]),
    );
  }

  Future<void> _addAnimalInline() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context, MaterialPageRoute(builder: (_) => _AddAnimalPage(espece: _espece)));
    if (result != null) setState(() => _animauxPortee.add(result));
  }

  Future<void> _editAnimalInline(int index, Map<String, dynamic> existing) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context, MaterialPageRoute(builder: (_) => _AddAnimalPage(espece: _espece, initial: existing)));
    if (result != null) setState(() => _animauxPortee[index] = result);
  }

  Future<void> _linkExistingAnimal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docs = await Supabase.instance.client
        .from('animaux').select()
        .eq('uid_eleveur', uid).eq('espece', _espece);
    if (!mounted) return;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'Aucun ${speciesLabel(_espece).toLowerCase()} dans vos fiches',
          style: const TextStyle(fontFamily: 'Galey'))));
      return;
    }
    final alreadyLinked = _animauxPortee.map((a) => a['animalId']).whereType<String>().toSet();
    await showModalBottomSheet(context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text('Sélectionner un animal', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 16))),
        Flexible(child: ListView.builder(shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i];
            final photoUrl = d['photo_url'] as String?;
            final isLinked = alreadyLinked.contains(d['id'] as String?);
            return ListTile(
              leading: CircleAvatar(backgroundColor: const Color(0xFFEEF5EA),
                backgroundImage: photoUrl != null
                    ? CachedNetworkImageProvider(photoUrl) : null,
                child: photoUrl == null
                    ? const Icon(Icons.pets, color: _green, size: 18) : null),
              title: Text(d['nom'] ?? 'Sans nom',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              subtitle: Text('${d['race'] ?? ''}${(d['sexe'] ?? '').isNotEmpty ? ' · ${d['sexe']}' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              trailing: isLinked ? const Icon(Icons.check, color: _green) : null,
              enabled: !isLinked,
              onTap: isLinked ? null : () {
                Navigator.pop(ctx);
                setState(() => _animauxPortee.add({
                  'animalId': d['id'], 'nom': d['nom'] ?? '', 'sexe': d['sexe'] ?? 'male',
                  'couleur': d['couleur'] ?? '',
                  'photos': photoUrl != null ? [photoUrl] : [],
                  'statut': 'disponible', 'isLinked': true,
                }));
              });
          })),
      ]));
  }
}

// ─── Sheet picker animaux (mère / père / étalon) ──────────────────────────────

class _AnimalPickerSheet extends StatelessWidget {
  final String espece;
  final String? sexeFilter;
  const _AnimalPickerSheet({required this.espece, this.sexeFilter});

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
          child: Row(children: [
            speciesIcon(espece, 18, _teal), const SizedBox(width: 8),
            Text(sexeFilter == 'femelle' ? 'Choisir la mère'
                : sexeFilter == 'male' ? 'Choisir le père / étalon' : 'Choisir un animal',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
          ])),
        const Divider(height: 1),
        Expanded(
          child: uid == null
              ? const Center(child: Text('Non connecté'))
              : FutureBuilder<List<Map<String, dynamic>>>(
                  future: Supabase.instance.client
                      .from('animaux').select()
                      .eq('uid_eleveur', uid).eq('espece', espece)
                      .then((rows) => sexeFilter == null
                          ? rows
                          : rows.where((d) => d['sexe'] == sexeFilter).toList()),
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(
                        child: CircularProgressIndicator(color: _teal));
                    final docs = snap.data!;
                    if (docs.isEmpty) return Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        speciesIcon(espece, 48, Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Aucun animal disponible',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 15,
                                color: Colors.grey.shade500)),
                        const SizedBox(height: 4),
                        Text(sexeFilter == 'femelle' ? 'Aucune femelle de cette espèce'
                            : sexeFilter == 'male' ? 'Aucun mâle de cette espèce'
                            : '',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: Colors.grey.shade400)),
                      ]),
                    );
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final photoUrl = d['photo_url'] as String?;
                        final dateNaissStr = d['date_naissance'] as String?;
                        DateTime? dateNaiss;
                        if (dateNaissStr != null) {
                          try { dateNaiss = DateTime.parse(dateNaissStr); } catch (_) {}
                        }
                        String ageStr = '';
                        if (dateNaiss != null) {
                          final age = DateTime.now().difference(dateNaiss);
                          final years = (age.inDays / 365).floor();
                          final months = ((age.inDays % 365) / 30).floor();
                          ageStr = years > 0 ? '$years ans'
                              : months > 0 ? '$months mois' : '${age.inDays} j';
                        }
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(width: 54, height: 54,
                              child: photoUrl != null
                                  ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.contain)
                                  : Container(color: const Color(0xFFEEF5EA),
                                      child: Center(child: speciesIcon(espece, 24, _green)))),
                          ),
                          title: Text(d['nom'] ?? 'Sans nom', style: const TextStyle(
                              fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${d['race'] ?? ''} · ${d['sexe'] == 'male' ? '♂' : '♀'}',
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                                    color: Color(0xFF6F767B))),
                            if (ageStr.isNotEmpty || (d['identification'] ?? '').isNotEmpty)
                              Text('${ageStr.isNotEmpty ? ageStr : ''}'
                                  '${ageStr.isNotEmpty && (d['identification'] ?? '').isNotEmpty ? ' · ' : ''}'
                                  '${d['identification'] ?? ''}',
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                      color: Colors.grey.shade500)),
                          ]),
                          trailing: const Icon(Icons.chevron_right, color: _teal),
                          onTap: () => Navigator.pop(context, {
                            'id':             d['id'],
                            'nom':            d['nom'] ?? '',
                            'photoUrl':       photoUrl,
                            'couleur':        d['couleur'] ?? '',
                            'sexe':           d['sexe'] ?? '',
                            'race':           d['race'] ?? '',
                            'identification': d['identification'] ?? '',
                            'dateNaissance':  dateNaiss != null
                                ? Timestamp.fromDate(dateNaiss) : null,
                            'description':    d['description'] ?? '',
                          }),
                        );
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ─── Page ajout / édition bébé ───────────────────────────────────────────────

class _AddAnimalPage extends StatefulWidget {
  final String espece;
  final Map<String, dynamic>? initial;
  const _AddAnimalPage({required this.espece, this.initial});
  @override
  State<_AddAnimalPage> createState() => _AddAnimalPageState();
}

class _AddAnimalPageState extends State<_AddAnimalPage> {
  final _nomCtrl     = TextEditingController();
  final _couleurCtrl = TextEditingController();
  final _prixCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  String _sexe   = 'male';
  String _statut = 'disponible';
  List<String> _existingPhotos = [];
  List<File>   _newPhotos = [];

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  Future<void> _pickAnimalInfo() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AnimalPickerSheet(espece: widget.espece),
    );
    if (r != null && mounted) setState(() {
      _nomCtrl.text     = r['nom']         ?? '';
      _couleurCtrl.text = r['couleur']     ?? '';
      _descCtrl.text    = r['description'] ?? '';
      _sexe = (r['sexe'] ?? _sexe) as String;
      // intentionally not importing photos
    });
  }

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    if (d != null) {
      _nomCtrl.text     = d['nom'] ?? '';
      _couleurCtrl.text = d['couleur'] ?? '';
      _prixCtrl.text    = (d['prix'] as num?)?.toInt().toString() ?? '';
      _descCtrl.text    = d['description'] ?? '';
      _sexe   = d['sexe'] ?? 'male';
      _statut = d['statut'] ?? 'disponible';
      for (final p in List<String>.from(d['photos'] ?? [])) {
        if (p.startsWith('http')) _existingPhotos.add(p);
        else _newPhotos.add(File(p));
      }
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose(); _couleurCtrl.dispose();
    _prixCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_existingPhotos.length + _newPhotos.length >= 4) return;
    final f = await pickAndCropSquare();
    if (f != null) setState(() => _newPhotos.add(f));
  }

  Map<String, dynamic> _buildResult() => {
    'nom': _nomCtrl.text.trim(), 'sexe': _sexe, 'couleur': _couleurCtrl.text.trim(),
    'prix': double.tryParse(_prixCtrl.text.trim()),
    'description': _descCtrl.text.trim(),
    'statut': _statut, 'isLinked': false,
    'photos': [..._existingPhotos, ..._newPhotos.map((f) => f.path)],
  };

  @override
  Widget build(BuildContext context) {
    final total = _existingPhotos.length + _newPhotos.length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(widget.initial != null ? 'Modifier le bébé' : 'Ajouter un bébé',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _buildResult()),
            child: Text(widget.initial != null ? 'Mettre à jour' : 'Ajouter',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Photos (max. 4)  •  Format carré',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          SizedBox(height: 84, child: ListView(scrollDirection: Axis.horizontal, children: [
            ..._existingPhotos.asMap().entries.map((e) => _thumb(
                () => setState(() => _existingPhotos.removeAt(e.key)), url: e.value)),
            ..._newPhotos.asMap().entries.map((e) => _thumb(
                () => setState(() => _newPhotos.removeAt(e.key)), file: e.value)),
            if (total < 4) GestureDetector(onTap: _pickPhoto,
              child: Container(width: 84, height: 84,
                decoration: BoxDecoration(color: const Color(0xFFF8F9FA),
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add_photo_alternate_outlined, color: _teal, size: 26))),
          ])),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickAnimalInfo,
            icon: const Icon(Icons.search, size: 16, color: _green),
            label: const Text('Récupérer les infos d\'un animal',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _green)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _green),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              minimumSize: const Size(double.infinity, 0),
            ),
          ),
          const SizedBox(height: 8),
          Text('Remplit nom, sexe, couleur et description. Les photos sont à ajouter séparément.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
          const SizedBox(height: 20),
          _label('Nom (optionnel)'), _field(_nomCtrl, 'Nom du bébé'),
          const SizedBox(height: 16),
          _label('Sexe'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final s in [('male', '♂ Mâle'), ('femelle', '♀ Femelle')])
              GestureDetector(onTap: () => setState(() => _sexe = s.$1),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: _sexe == s.$1 ? _teal : Colors.transparent,
                    border: Border.all(color: _sexe == s.$1 ? _teal : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _sexe == s.$1 ? Colors.white : Colors.grey)))),
          ]),
          const SizedBox(height: 16),
          _label('Couleur / Robe'), _field(_couleurCtrl, 'Ex: Tricolore, Roux, Noir...'),
          const SizedBox(height: 16),
          _label('Prix (€)'), _field(_prixCtrl, 'Ex: 1200', keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          _label('Description'), _field(_descCtrl, 'Caractère, particularités...', maxLines: 4),
          const SizedBox(height: 16),
          _label('Disponibilité'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final s in [('disponible', 'Disponible', _green),
                             ('reserve', 'Réservé', Color(0xFFF59E0B)),
                             ('vendu', 'Vendu / Cédé', Colors.blueGrey)])
              GestureDetector(onTap: () => setState(() => _statut = s.$1),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _statut == s.$1 ? s.$3 : Colors.transparent,
                    border: Border.all(color: _statut == s.$1 ? s.$3 : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statut == s.$1 ? Colors.white : Colors.black87)))),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
        fontWeight: FontWeight.w600, color: Color(0xFF6F767B))),
  );

  Widget _thumb(VoidCallback onRemove, {String? url, File? file}) =>
    Stack(children: [
      Container(width: 84, height: 84, margin: const EdgeInsets.only(right: 8),
        child: ClipRRect(borderRadius: BorderRadius.circular(8),
          child: url != null ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
              : Image.file(file!, fit: BoxFit.cover))),
      Positioned(top: 2, right: 10,
        child: GestureDetector(onTap: onRemove,
          child: Container(width: 20, height: 20,
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 12)))),
    ]);

  Widget _field(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboardType}) => TextFormField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    scrollPadding: const EdgeInsets.only(bottom: 120),
    style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
    decoration: InputDecoration(hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _teal)),
      filled: true, fillColor: const Color(0xFFF8F9FA)),
  );
}

// ─── Breed picker sheet (annonce) ─────────────────────────────────────────────

class _AnnonceBreedPickerSheet extends StatefulWidget {
  final List<String> breeds;
  final String current;
  const _AnnonceBreedPickerSheet({required this.breeds, required this.current});
  @override
  State<_AnnonceBreedPickerSheet> createState() => _AnnonceBreedPickerSheetState();
}

class _AnnonceBreedPickerSheetState extends State<_AnnonceBreedPickerSheet> {
  late List<String> _filtered;
  final _searchCtrl = TextEditingController();

  static const _teal = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    final list = List<String>.from(widget.breeds);
    if (!list.contains('Autre')) list.add('Autre');
    _filtered = list;
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _filter(String q) {
    final list = List<String>.from(widget.breeds);
    if (!list.contains('Autre')) list.add('Autre');
    setState(() {
      _filtered = q.isEmpty
          ? list
          : list.where((b) => b.toLowerCase().contains(q.toLowerCase())).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Expanded(child: Text('Race',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17))),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher une race...',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final b = _filtered[i];
                final selected = b == widget.current;
                return ListTile(
                  dense: true,
                  title: Text(b, style: TextStyle(
                      fontFamily: 'Galey', fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      color: selected ? _teal : const Color(0xFF1F2A2E))),
                  trailing: selected ? const Icon(Icons.check, color: _teal, size: 18) : null,
                  onTap: () => Navigator.pop(context, b),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
