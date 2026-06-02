import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Contact urgence ─────────────────────────────────────────────────────────

class _ContactUrgence {
  final TextEditingController nom;
  final TextEditingController tel;
  _ContactUrgence({String nomVal = '', String telVal = ''})
      : nom = TextEditingController(text: nomVal),
        tel = TextEditingController(text: telVal);
  void dispose() { nom.dispose(); tel.dispose(); }
}

// ─── Page principale ──────────────────────────────────────────────────────────

class AnimalFichePage extends StatefulWidget {
  final String? animalId;
  final Map<String, dynamic>? initialData;
  final String? preselectedEspece;
  final bool readOnly;
  final String? eleveurUidOverride;

  const AnimalFichePage({
    super.key,
    this.animalId,
    this.initialData,
    this.preselectedEspece,
    this.readOnly = false,
    this.eleveurUidOverride,
  });

  @override
  State<AnimalFichePage> createState() => _AnimalFichePageState();
}

class _AnimalFichePageState extends State<AnimalFichePage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _saving = false;
  bool _savingRegistre = false;
  final _supa = Supabase.instance.client;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);

  // ── Champs identité
  final _nomCtrl    = TextEditingController();
  final _raceCtrl   = TextEditingController();
  final _couleurCtrl = TextEditingController();
  final _identCtrl  = TextEditingController();
  final _tailleCtrl = TextEditingController();
  final _poidsCtrl  = TextEditingController();
  final _notesCtrl  = TextEditingController();
  // Généalogie structurée
  final _nomPereCtrl  = TextEditingController();
  final _pucePereCtrl = TextEditingController();
  final _nomMereCtrl  = TextEditingController();
  final _puceMereCtrl = TextEditingController();

  String _espece = 'chien';
  String _sexe = 'male';
  bool _sterilise = false;
  String? _typePoil;
  int? _intervalleChaleursCustom;

  // ── Registre Entrée / Sortie
  String    _statut           = 'present'; // 'present' | 'sorti' | 'decede'
  DateTime? _dateEntree;
  final _provenanceNomCtrl     = TextEditingController();
  String    _provenanceQualite = ''; // 'naissance' | 'eleveur' | 'particulier' | 'refuge' | 'importation' | 'autre'
  final _provenanceAdresseCtrl = TextEditingController();
  final _importationRefCtrl    = TextEditingController();
  final _raceMereCtrl          = TextEditingController();
  DateTime? _dateNaissanceMere;
  DateTime? _dateSortie;
  final _destinataireNomCtrl     = TextEditingController();
  String    _destinataireQualite = '';
  final _destinataireAdresseCtrl = TextEditingController();
  String    _causeMort           = ''; // 'maladie' | 'accident' | 'naturelle' | 'inconnue'
  String? _nomElevage;
  String? _adresseElevage;
  bool _pedigree = false;
  final _clubRegistreCtrl = TextEditingController();
  DateTime? _dateNaissance;
  String? _photoUrl;
  File? _photoFile;
  String? _pedigreeUrl;
  String? _pedigreeLof;
  final _passeportCtrl = TextEditingController();
  final List<_ContactUrgence> _contactsUrgence = [];

  final _descriptionCtrl = TextEditingController();
  List<Map<String, String>> _documents = [];
  bool _editing = false;

  String? _activeAlerteId;
  String? _alerteStatut;

  List<Map<String, dynamic>> _mesMales = [];
  List<Map<String, dynamic>> _mesFemelles = [];

  Map<String, List<String>> _allBreeds = {};

  List<String> get _currentBreeds {
    final list = List<String>.from(_allBreeds[_espece] ?? []);
    if (!list.contains('Autre')) list.add('Autre');
    return list;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _editing = widget.animalId == null; // new animal → edit mode directly
    if (widget.preselectedEspece != null) _espece = widget.preselectedEspece!;
    _fillFromData(widget.initialData); // pre-fill instantly from cached data
    _loadBreeds();
    _loadMesAnimaux();
    _loadEleveurProfile();
    if (widget.animalId != null) {
      _loadActiveAlerte();
      _refreshFromSupabase(); // then silently refresh with latest Supabase data
    }
  }

  Future<void> _refreshFromSupabase() async {
    try {
      final data = await _supa
          .from('animaux')
          .select('*')
          .eq('id', widget.animalId!)
          .single();
      if (mounted) setState(() => _fillFromData(Map<String, dynamic>.from(data)));
    } catch (_) {}
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

  Future<void> _loadActiveAlerte() async {
    try {
      final res = await _supa
          .from('alertes_perdus')
          .select('id, statut')
          .eq('animal_id', widget.animalId!)
          .order('created_at', ascending: false)
          .limit(1);
      if (res.isNotEmpty && mounted) {
        setState(() {
          _activeAlerteId = res[0]['id'] as String?;
          _alerteStatut   = res[0]['statut'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadEleveurProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profil = await _supa
          .from('users')
          .select('name_elevage, rue_elevage, ville_elevage, code_postal_elevage')
          .eq('uid', uid)
          .maybeSingle();
      if (profil != null && mounted) {
        final rue   = profil['rue_elevage']          as String? ?? '';
        final cp    = profil['code_postal_elevage']  as String? ?? '';
        final ville = profil['ville_elevage']         as String? ?? '';
        final adresse = [rue, cp, ville].where((s) => s.isNotEmpty).join(', ');
        setState(() {
          _nomElevage     = profil['name_elevage'] as String?;
          _adresseElevage = adresse.isNotEmpty ? adresse : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMesAnimaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final males = await _supa.from('animaux')
          .select('id, nom, identification, race, photo_url')
          .eq('uid_eleveur', uid).eq('sexe', 'male').order('nom');
      final femelles = await _supa.from('animaux')
          .select('id, nom, identification, race, photo_url, date_naissance')
          .eq('uid_eleveur', uid).eq('sexe', 'femelle').order('nom');
      if (mounted) setState(() {
        _mesMales = List<Map<String, dynamic>>.from(males);
        _mesFemelles = List<Map<String, dynamic>>.from(femelles);
      });
    } catch (_) {}
  }

  Future<void> _marquerRetrouve(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Animal retrouvé ?'),
        content: const Text('Confirmer que votre animal a été retrouvé ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || _activeAlerteId == null) return;
    await _supa.from('alertes_perdus').update({
      'statut': 'retrouve',
      'date_retrouve': DateTime.now().toIso8601String(),
    }).eq('id', _activeAlerteId!);
    if (mounted) setState(() => _alerteStatut = 'retrouve');
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  void _fillFromData(Map<String, dynamic>? d) {
    if (d == null) return;
    _espece = d['espece'] ?? _espece;
    _descriptionCtrl.text = d['description'] ?? '';
    _nomCtrl.text   = d['nom'] ?? '';
    _raceCtrl.text  = d['race'] ?? '';
    _couleurCtrl.text = d['couleur'] ?? '';
    _identCtrl.text = d['identification'] ?? '';
    _tailleCtrl.text = d['taille']?.toString() ?? '';
    _poidsCtrl.text  = d['poids']?.toString() ?? '';
    _notesCtrl.text  = d['notes'] ?? '';
    _nomPereCtrl.text  = d['nom_pere'] ?? '';
    _pucePereCtrl.text = d['puce_pere'] ?? '';
    _nomMereCtrl.text  = d['nom_mere'] ?? '';
    _puceMereCtrl.text = d['puce_mere'] ?? '';
    _sexe = d['sexe'] ?? 'male';
    _intervalleChaleursCustom = d['intervalle_chaleurs_jours'] as int?;
    _sterilise = d['sterilise'] ?? false;
    _typePoil = d['type_poil'] as String?;
    _pedigree = d['pedigree'] ?? false;
    _clubRegistreCtrl.text = d['club_registre'] ?? '';
    _pedigreeLof = d['pedigree_lof'] as String?;
    _photoUrl = d['photo_url'] as String?;
    _pedigreeUrl = d['pedigree_url'] as String?;
    _passeportCtrl.text = d['passeport_europeen'] ?? '';
    final docs = d['documents'];
    _documents = (docs is List ? docs : []).map<Map<String, String>>((doc) => <String, String>{
      'nom': (doc['nom'] ?? '') as String,
      'url': (doc['url'] ?? '') as String,
      'type': (doc['type'] ?? 'autre') as String,
    }).toList();
    for (final c in _contactsUrgence) c.dispose();
    _contactsUrgence.clear();
    final contacts = d['contacts_urgence'];
    for (final raw in (contacts is List ? contacts : [])) {
      _contactsUrgence.add(_ContactUrgence(
          nomVal: raw['nom'] ?? '', telVal: raw['tel'] ?? ''));
    }
    _dateNaissance = _parseDate(d['date_naissance']);
    // Registre E/S
    _statut = (d['statut'] as String?) ?? 'present';
    _provenanceNomCtrl.text     = (d['provenance_nom'] as String?) ?? '';
    _provenanceQualite          = (d['provenance_qualite'] as String?) ?? '';
    _provenanceAdresseCtrl.text = (d['provenance_adresse'] as String?) ?? '';
    _importationRefCtrl.text    = (d['importation_ref'] as String?) ?? '';
    _raceMereCtrl.text          = (d['race_mere'] as String?) ?? '';
    _destinataireNomCtrl.text     = (d['destinataire_nom'] as String?) ?? '';
    _destinataireQualite          = (d['destinataire_qualite'] as String?) ?? '';
    _destinataireAdresseCtrl.text = (d['destinataire_adresse'] as String?) ?? '';
    _causeMort = (d['cause_mort'] as String?) ?? '';
    _dateEntree      = _parseDate(d['date_entree']);
    _dateNaissanceMere = _parseDate(d['date_naissance_mere']);
    _dateSortie      = _parseDate(d['date_sortie']);
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_nomCtrl, _raceCtrl, _couleurCtrl, _identCtrl,
      _tailleCtrl, _poidsCtrl, _notesCtrl, _nomPereCtrl, _pucePereCtrl,
      _nomMereCtrl, _puceMereCtrl, _passeportCtrl, _clubRegistreCtrl, _descriptionCtrl,
      _provenanceNomCtrl, _provenanceAdresseCtrl, _importationRefCtrl,
      _raceMereCtrl, _destinataireNomCtrl, _destinataireAdresseCtrl]) { c.dispose(); }
    for (final c in _contactsUrgence) c.dispose();
    super.dispose();
  }

  // ── Sauvegarde ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez saisir un nom')));
      return;
    }
    setState(() => _saving = true);
    try {
      String? uploadedUrl = _photoUrl;
      if (_photoFile != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        uploadedUrl = await uploadPhoto(_photoFile!, 'animaux/$uid/$name');
      }

      final uid = widget.eleveurUidOverride ?? FirebaseAuth.instance.currentUser!.uid;
      final id = widget.animalId ?? DateTime.now().millisecondsSinceEpoch.toString();
      final data = {
        'id':                  id,
        'uid_eleveur':         uid,
        'espece':              _espece,
        'description':         _descriptionCtrl.text.trim(),
        'nom':                 _nomCtrl.text.trim(),
        'race':                _raceCtrl.text.trim(),
        'couleur':             _couleurCtrl.text.trim(),
        'identification':      _identCtrl.text.trim(),
        'taille':              _tailleCtrl.text.trim(),
        'poids':               _poidsCtrl.text.trim(),
        'nom_pere':            _nomPereCtrl.text.trim(),
        'puce_pere':           _pucePereCtrl.text.trim(),
        'nom_mere':            _nomMereCtrl.text.trim(),
        'puce_mere':           _puceMereCtrl.text.trim(),
        'notes':               _notesCtrl.text.trim(),
        'sexe':                _sexe,
        'sterilise':           _sterilise,
        'type_poil':           _typePoil,
        'pedigree':            _pedigree,
        'club_registre':       _clubRegistreCtrl.text.trim(),
        'pedigree_lof':        _pedigreeLof,
        'passeport_europeen':  _passeportCtrl.text.trim(),
        'contacts_urgence':    _contactsUrgence
            .map((c) => {'nom': c.nom.text.trim(), 'tel': c.tel.text.trim()})
            .where((c) => c['nom']!.isNotEmpty || c['tel']!.isNotEmpty)
            .toList(),
        'pedigree_url':        _pedigreeUrl,
        'documents':           _documents,
        'photo_url':           uploadedUrl,
        'date_naissance':      _dateNaissance?.toIso8601String(),
        'statut':              _statut,
        'date_entree':         _dateEntree?.toIso8601String(),
        'provenance_nom':      _provenanceNomCtrl.text.trim(),
        'provenance_qualite':  _provenanceQualite,
        'provenance_adresse':  _provenanceAdresseCtrl.text.trim(),
        'importation_ref':     _importationRefCtrl.text.trim(),
        'race_mere':           _raceMereCtrl.text.trim(),
        'date_naissance_mere': _dateNaissanceMere?.toIso8601String(),
        'date_sortie':         _dateSortie?.toIso8601String(),
        'destinataire_nom':    _destinataireNomCtrl.text.trim(),
        'destinataire_qualite': _destinataireQualite,
        'destinataire_adresse': _destinataireAdresseCtrl.text.trim(),
        'cause_mort':          _causeMort,
        'updated_at':          DateTime.now().toIso8601String(),
      };

      await _supa.from('animaux').upsert(data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRegistre() async {
    if (widget.animalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enregistrez d\'abord la fiche complète', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _savingRegistre = true);
    try {
      await _supa.from('animaux').update({
        'statut':               _statut,
        'date_entree':          _dateEntree?.toIso8601String(),
        'provenance_qualite':   _provenanceQualite,
        'provenance_nom':       _provenanceNomCtrl.text.trim(),
        'provenance_adresse':   _provenanceAdresseCtrl.text.trim(),
        'importation_ref':      _importationRefCtrl.text.trim(),
        'race_mere':            _raceMereCtrl.text.trim(),
        'date_naissance_mere':  _dateNaissanceMere?.toIso8601String(),
        'date_sortie':          _dateSortie?.toIso8601String(),
        'destinataire_nom':     _destinataireNomCtrl.text.trim(),
        'destinataire_qualite': _destinataireQualite,
        'destinataire_adresse': _destinataireAdresseCtrl.text.trim(),
        'cause_mort':           _causeMort,
        'updated_at':           DateTime.now().toIso8601String(),
      }).eq('id', widget.animalId!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registre enregistré ✓', style: TextStyle(fontFamily: 'Galey'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
    } finally {
      if (mounted) setState(() => _savingRegistre = false);
    }
  }

  Future<String> _uploadFile(File file, String folder) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final name = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    return uploadRawFile(file, '$folder/$uid/$name');
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Choisir une photo',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF6E9E57).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF6E9E57).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF6E9E57)),
            ),
            title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Ouvrir la caméra', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF0C5C6C).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.photo_library_outlined, color: Color(0xFF0C5C6C)),
            ),
            title: const Text('Choisir depuis la galerie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Sélectionner une photo existante', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final f = await pickAndCropSquare(source: source);
    if (f != null) setState(() => _photoFile = f);
  }

  Future<void> _pickPedigree() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Ajouter un pedigree',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF6E9E57).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF6E9E57).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF6E9E57)),
            ),
            title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Ouvrir la caméra', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF0C5C6C).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.photo_library_outlined, color: Color(0xFF0C5C6C)),
            ),
            title: const Text('Choisir depuis la galerie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Sélectionner une photo', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFFB07D3A).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFFB07D3A).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFB07D3A)),
            ),
            title: const Text('Document PDF', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Importer un fichier PDF', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
        ]),
      ),
    );
    if (choice == null) return;

    File? file;
    if (choice == 'camera') {
      final xFile = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
      if (xFile != null) file = File(xFile.path);
    } else if (choice == 'gallery') {
      final xFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (xFile != null) file = File(xFile.path);
    } else {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (result?.files.single.path != null) file = File(result!.files.single.path!);
    }

    if (file == null) return;
    setState(() => _saving = true);
    try {
      final url = await _uploadFile(file, 'pedigrees');
      setState(() { _pedigreeUrl = url; _saving = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedigree chargé ✓')));
    } catch (e) {
      setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateNaissance ?? now,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateNaissance = picked);
  }

  Future<void> _pickDocument(String nom, String type) async {
    String docNom = nom;
    if (type == 'autre') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nom du document', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl, autofocus: true,
            decoration: const InputDecoration(hintText: 'Ex: Résultats génétiques', hintStyle: TextStyle(fontFamily: 'Galey')),
            style: const TextStyle(fontFamily: 'Galey'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('OK', style: TextStyle(color: Color(0xFF6E9E57), fontFamily: 'Galey', fontWeight: FontWeight.w600))),
          ],
        ),
      );
      final text = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true || text.isEmpty) return;
      docNom = text;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Ajouter un document',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF6E9E57).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF6E9E57).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF6E9E57)),
            ),
            title: const Text('Photographier le document', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Ouvrir la caméra', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF0C5C6C).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.photo_library_outlined, color: Color(0xFF0C5C6C)),
            ),
            title: const Text('Choisir depuis la galerie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Sélectionner une image', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF5F9EAA).withOpacity(0.07),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF5F9EAA).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF5F9EAA)),
            ),
            title: const Text('Importer un fichier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('PDF, JPG, PNG...', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(context, 'file'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    File? docFile;
    if (choice == 'camera' || choice == 'gallery') {
      final source = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (picked == null || !mounted) return;
      docFile = File(picked.path);
    } else {
      final result = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg']);
      if (result?.files.single.path == null || !mounted) return;
      docFile = File(result!.files.single.path!);
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final url = await _uploadFile(docFile, 'documents');
      if (mounted) setState(() => _documents.add({'nom': docNom, 'url': url, 'type': type}));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        title: Text(widget.animalId != null ? (_nomCtrl.text.isNotEmpty ? _nomCtrl.text : 'Fiche animal') : 'Nouvel animal',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.readOnly)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: Text('Lecture seule',
                  style: TextStyle(color: Colors.white60, fontFamily: 'Galey', fontSize: 12))),
            )
          else if (_saving)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
          else if (_editing)
            TextButton(onPressed: _save,
                child: const Text('Enregistrer', style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w600)))
          else
            TextButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white),
              label: const Text('Modifier', style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: _green,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Identité'), Tab(text: 'Repro'), Tab(text: 'Santé'), Tab(text: 'Alimentation')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _IdentiteTab(this),
          _SuiviReproTab(animalId: widget.animalId, espece: _espece, sexe: _sexe, intervalleChaleursCustom: _intervalleChaleursCustom),
          _CarnetSanteTab(animalId: widget.animalId),
          _AlimentationTab(this),
        ],
      ),
    );
  }
}

// ─── Onglet Identité ──────────────────────────────────────────────────────────

class _IdentiteTab extends StatelessWidget {
  final _AnimalFichePageState s;
  const _IdentiteTab(this.s);

  bool get _hasPoil    => s._espece == 'chien' || s._espece == 'chat';
  bool get _hasPoids   => s._espece != 'oiseau';
  bool get _hasBreeds  => s._allBreeds[s._espece]?.isNotEmpty == true;

  static const _agesRetraite = <String, int>{
    'chien': 7, 'chat': 8, 'lapin': 5,
    'cheval': 18, 'ovin': 8, 'caprin': 8, 'porcin': 5, 'ane': 15,
  };

  // Nombre de jours avant (positif) ou après (négatif) l'âge de retraite.
  // Retourne null si non applicable.
  int? get _joursAvantRetraite {
    if (s._sexe != 'femelle' || s._sterilise || s._dateNaissance == null) return null;
    final ageRetraite = _agesRetraite[s._espece];
    if (ageRetraite == null) return null;
    final dn = s._dateNaissance!;
    final retraite = DateTime(dn.year + ageRetraite, dn.month, dn.day);
    return retraite.difference(DateTime.now()).inDays;
  }

  String get _tailleLabel {
    if (s._espece == 'cheval') return 'Taille au garrot (cm)';
    if (s._espece == 'oiseau') return 'Envergure (cm)';
    return 'Taille (cm)';
  }

  String get _identLabel {
    if (s._espece == 'oiseau') return 'Bague / Puce';
    if (s._espece == 'cheval') return 'SIRE / Puce';
    return 'Puce / Tatouage';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_joursAvantRetraite != null && _joursAvantRetraite! <= 30)
            _RetraiteBanner(jours: _joursAvantRetraite!, espece: s._espece),
          if (_joursAvantRetraite != null && _joursAvantRetraite! <= 30)
            const SizedBox(height: 12),
          IgnorePointer(
            ignoring: !s._editing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _photoSection(),
                const SizedBox(height: 12),
                _card([_field('Description', s._descriptionCtrl, maxLines: 4)]),
                const SizedBox(height: 16),
                _especeDropdown(context),
                const SizedBox(height: 16),
                _card([
                  _field('Nom', s._nomCtrl, required: true),
                  _hasBreeds ? _raceAutocomplete(context) : _field('Race', s._raceCtrl),
                  _field('Couleur / Robe', s._couleurCtrl),
                  _field(_identLabel, s._identCtrl),
                  _field('Passeport européen n°', s._passeportCtrl),
                ]),
                const SizedBox(height: 12),
                _card([
                  _dateField(context),
                  _sexeField(),
                  _steriliseField(),
                  if (_hasPoil) _poilField(),
                  _field(_tailleLabel, s._tailleCtrl, inputType: TextInputType.number),
                  if (_hasPoids) _field('Poids (kg)', s._poidsCtrl, inputType: TextInputType.number),
                ]),
                const SizedBox(height: 12),
                _card([_genealogieSection(context)]),
                const SizedBox(height: 12),
                _contactsUrgenceSection(context),
                const SizedBox(height: 12),
                _card([_field('Notes', s._notesCtrl, maxLines: 3)]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card([_pedigreeSection(context)]),
          const SizedBox(height: 12),
          _registreSection(context),
          const SizedBox(height: 12),
          _documentsSection(context),
          const SizedBox(height: 12),
          _alerteSection(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _alerteSection(BuildContext context) {
    if (s._alerteStatut == 'perdu') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Alerte disparition active',
                    style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text("Modifier l'alerte"),
                  style: OutlinedButton.styleFrom(foregroundColor: _AnimalFichePageState._teal),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlertePerduFormPage(
                        alerteId:       s._activeAlerteId,
                        animalId:       s.widget.animalId,
                        nom:            s._nomCtrl.text,
                        espece:         s._espece,
                        race:           s._raceCtrl.text,
                        sexe:           s._sexe,
                        couleur:        s._couleurCtrl.text,
                        photoUrl:       s._photoUrl,
                        identification: s._identCtrl.text,
                        contactUrgence: s._contactsUrgence.isNotEmpty
                            ? (s._contactsUrgence.first.tel.text.isNotEmpty
                                ? s._contactsUrgence.first.tel.text
                                : s._contactsUrgence.first.nom.text)
                            : null,
                      ),
                    ),
                  ).then((_) => s._loadActiveAlerte()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Retrouvé !'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AnimalFichePageState._green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => s._marquerRetrouve(context),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return ElevatedButton.icon(
      icon: const Icon(Icons.search_off_rounded),
      label: const Text('Déclarer perdu'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlertePerduFormPage(
            animalId:       s.widget.animalId,
            nom:            s._nomCtrl.text,
            espece:         s._espece,
            race:           s._raceCtrl.text,
            sexe:           s._sexe,
            couleur:        s._couleurCtrl.text,
            photoUrl:       s._photoUrl,
            identification: s._identCtrl.text,
            contactUrgence: s._contactsUrgence.isNotEmpty
                ? (s._contactsUrgence.first.tel.text.isNotEmpty
                    ? s._contactsUrgence.first.tel.text
                    : s._contactsUrgence.first.nom.text)
                : null,
          ),
        ),
      ).then((_) => s._loadActiveAlerte()),
    );
  }

  Widget _photoSection() {
    final hasPhoto = s._photoFile != null || s._photoUrl != null;
    return Center(
      child: GestureDetector(
        onTap: s._editing ? s._pickPhoto : null,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 140, height: 140,
                child: hasPhoto
                    ? (s._photoFile != null
                        ? Image.file(s._photoFile!, fit: BoxFit.cover, width: 140, height: 140)
                        : CachedNetworkImage(imageUrl: s._photoUrl!, fit: BoxFit.cover, width: 140, height: 140))
                    : Container(
                        color: const Color(0xFFEEF5EA),
                        child: Center(child: speciesIcon(s._espece, 52, const Color(0xFF6E9E57))),
                      ),
              ),
            ),
            if (s._editing)
              Positioned(bottom: 6, right: 6,
                child: CircleAvatar(radius: 14, backgroundColor: const Color(0xFF6E9E57),
                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Widget _especeDropdown(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: s._espece,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
      decoration: InputDecoration(
        labelText: 'Espèce',
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: kSpeciesData.where((e) => e.value != 'tous').map((e) =>
        DropdownMenuItem(
          value: e.value,
          child: Row(children: [
            speciesIcon(e.value, 16, speciesColor(e.value)),
            const SizedBox(width: 10),
            Text(e.label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
          ]),
        ),
      ).toList(),
      onChanged: (v) { if (v != null) s.setState(() { s._espece = v; s._raceCtrl.clear(); }); },
    );
  }

  Widget _raceAutocomplete(BuildContext context) {
    final breeds = s._currentBreeds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => _openBreedPicker(context, breeds, s._raceCtrl, 'Race'),
        child: AbsorbPointer(
          child: TextFormField(
            controller: s._raceCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Race',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              suffixIcon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF6E9E57)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openBreedPicker(BuildContext context, List<String> breeds, TextEditingController ctrl, String label) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BreedPickerSheet(breeds: breeds, label: label, current: ctrl.text),
    );
    if (selected != null) s.setState(() => ctrl.text = selected);
  }

  Widget _raceMereAutocomplete(BuildContext context) {
    final breeds = s._currentBreeds;
    return GestureDetector(
      onTap: () => _openBreedPicker(context, breeds, s._raceMereCtrl, 'Race de la mère'),
      child: AbsorbPointer(
        child: TextFormField(
          controller: s._raceMereCtrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Race de la mère',
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            suffixIcon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF0C5C6C)),
          ),
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(children: children),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {bool required = false, int maxLines = 1, TextInputType? inputType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: inputType,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: s._pickDate,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Date de naissance',
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF6E9E57)),
          ),
          child: Text(
            s._dateNaissance != null ? DateFormat('dd/MM/yyyy').format(s._dateNaissance!) : 'Sélectionner',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: s._dateNaissance != null ? const Color(0xFF1F2A2E) : Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _sexeField() {
    const options = [('male', '♂ Mâle'), ('femelle', '♀ Femelle')];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Sexe', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
        const SizedBox(height: 6),
        Row(children: options.map((o) {
          final active = s._sexe == o.$1;
          return Expanded(child: GestureDetector(
            onTap: () => s.setState(() => s._sexe = o.$1),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF6E9E57) : Colors.transparent,
                border: Border.all(color: active ? const Color(0xFF6E9E57) : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(o.$2, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: active ? Colors.white : const Color(0xFF1F2A2E))),
            ),
          ));
        }).toList()),
      ]),
    );
  }

  Widget _steriliseField() {
    const options = [(false, 'Non'), (true, 'Oui')];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stérilisé(e)', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
        const SizedBox(height: 6),
        Row(children: options.map((o) {
          final active = s._sterilise == o.$1;
          return Expanded(child: GestureDetector(
            onTap: () => s.setState(() => s._sterilise = o.$1),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF6E9E57) : Colors.transparent,
                border: Border.all(color: active ? const Color(0xFF6E9E57) : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(o.$2, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: active ? Colors.white : const Color(0xFF1F2A2E))),
            ),
          ));
        }).toList()),
      ]),
    );
  }

  Widget _contactsUrgenceSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Contacts urgence',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 14, color: Color(0xFF1F2A2E))),
          TextButton.icon(
            onPressed: () => s.setState(() =>
                s._contactsUrgence.add(_ContactUrgence())),
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF6E9E57)),
            label: const Text('Ajouter',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57))),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ]),
        if (s._contactsUrgence.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun contact',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
          ),
        ...s._contactsUrgence.asMap().entries.map((e) {
          final i = e.key;
          final c = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [
                TextFormField(
                  controller: c.nom,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Nom',
                    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: c.tel,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Téléphone',
                    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                ),
              ])),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => s.setState(() {
                  s._contactsUrgence[i].dispose();
                  s._contactsUrgence.removeAt(i);
                }),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _poilField() {
    const options = ['Court', 'Mi-long', 'Long', 'Frisé', 'Fil de soie', 'Ras'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: s._typePoil,
        hint: const Text('Type de poil', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
        decoration: InputDecoration(
          labelText: 'Type de poil',
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: (v) => s.setState(() => s._typePoil = v),
      ),
    );
  }

  // ── Pedigree/registre adapté par espèce ────────────────────────────────────

  static const _pedigreeConfig = <String, ({
    String sectionLabel,
    String yesLabel,
    String typeLabel,
    List<String> typeOptions,
    String clubLabel,
    String docLabel,
  })>{
    'chien': (
      sectionLabel: 'Pedigree',
      yesLabel: 'Avec pedigree',
      typeLabel: 'Type LOF',
      typeOptions: ['LOF', 'Non-LOF'],
      clubLabel: 'Club de race (SCC, etc.)',
      docLabel: 'Charger le pedigree (PDF/photo)',
    ),
    'chat': (
      sectionLabel: 'Pedigree',
      yesLabel: 'Avec pedigree',
      typeLabel: 'Type LOOF',
      typeOptions: ['LOOF', 'Non-LOOF'],
      clubLabel: 'Club de race (LOOF, etc.)',
      docLabel: 'Charger le pedigree (PDF/photo)',
    ),
    'cheval': (
      sectionLabel: 'Stud-book / SIRE',
      yesLabel: 'Inscrit',
      typeLabel: 'Registre',
      typeOptions: ['Stud-book', 'Registre d\'élevage', 'Non-inscrit'],
      clubLabel: 'Studbook / Association',
      docLabel: 'Charger le document (PDF/photo)',
    ),
    'lapin': (
      sectionLabel: 'Livre de race',
      yesLabel: 'Inscrit',
      typeLabel: 'Type',
      typeOptions: ['Livre de race', 'Non-inscrit'],
      clubLabel: 'Club / Association (ASCC, etc.)',
      docLabel: 'Charger le document (PDF/photo)',
    ),
    'oiseau': (
      sectionLabel: 'Bague / Origine',
      yesLabel: 'Bagué',
      typeLabel: 'Type',
      typeOptions: ['Bagué fermé', 'Bagué ouvert', 'Non-bagué'],
      clubLabel: 'Éleveur / Association',
      docLabel: 'Charger le certificat (PDF/photo)',
    ),
    'ovin': (
      sectionLabel: 'Livre généalogique',
      yesLabel: 'Inscrit',
      typeLabel: 'Type',
      typeOptions: ['Livre généalogique', 'Non-inscrit'],
      clubLabel: 'Association de race',
      docLabel: 'Charger le document (PDF/photo)',
    ),
    'caprin': (
      sectionLabel: 'Livre généalogique',
      yesLabel: 'Inscrit',
      typeLabel: 'Type',
      typeOptions: ['Livre généalogique', 'Non-inscrit'],
      clubLabel: 'Association de race',
      docLabel: 'Charger le document (PDF/photo)',
    ),
    'porcin': (
      sectionLabel: 'Livre généalogique',
      yesLabel: 'Inscrit',
      typeLabel: 'Type',
      typeOptions: ['Livre généalogique LG', 'Non-inscrit'],
      clubLabel: 'Association de race',
      docLabel: 'Charger le document (PDF/photo)',
    ),
    'nac': (
      sectionLabel: 'Registre / Origine',
      yesLabel: 'Avec registre',
      typeLabel: 'Type',
      typeOptions: ['Registre d\'élevage', 'Non-inscrit'],
      clubLabel: 'Éleveur / Club',
      docLabel: 'Charger le document (PDF/photo)',
    ),
  };

  static ({
    String sectionLabel,
    String yesLabel,
    String typeLabel,
    List<String> typeOptions,
    String clubLabel,
    String docLabel,
  }) _pediConfig(String espece) =>
      _pedigreeConfig[espece] ?? (
        sectionLabel: 'Registre / Origine',
        yesLabel: 'Avec registre',
        typeLabel: 'Type',
        typeOptions: ['Inscrit', 'Non-inscrit'],
        clubLabel: 'Club / Association',
        docLabel: 'Charger le document (PDF/photo)',
      );

  Widget _pedigreeSection(BuildContext context) {
    final cfg = _pediConfig(s._espece);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Contrôles d'édition (bloqués hors mode édition) ──────────────────
        IgnorePointer(
          ignoring: !s._editing,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cfg.sectionLabel,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => s.setState(() => s._pedigree = false),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: !s._pedigree ? const Color(0xFF6E9E57) : Colors.transparent,
                    border: Border.all(color: !s._pedigree ? const Color(0xFF6E9E57) : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Non', textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                          color: !s._pedigree ? Colors.white : const Color(0xFF1F2A2E))),
                ),
              )),
              Expanded(child: GestureDetector(
                onTap: () => s.setState(() => s._pedigree = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: s._pedigree ? const Color(0xFF6E9E57) : Colors.transparent,
                    border: Border.all(color: s._pedigree ? const Color(0xFF6E9E57) : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(cfg.yesLabel, textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                          color: s._pedigree ? Colors.white : const Color(0xFF1F2A2E))),
                ),
              )),
            ]),
            if (s._pedigree) ...[
              const SizedBox(height: 12),
              Text(cfg.typeLabel,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6,
                children: cfg.typeOptions.map((opt) {
                  final active = s._pedigreeLof == opt;
                  return GestureDetector(
                    onTap: () => s.setState(() => s._pedigreeLof = opt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF0C5C6C) : Colors.transparent,
                        border: Border.all(color: active ? const Color(0xFF0C5C6C) : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(opt, textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              color: active ? Colors.white : const Color(0xFF1F2A2E))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: s._clubRegistreCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  labelText: cfg.clubLabel,
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF6E9E57))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
              if (s._editing && s._pedigreeUrl == null) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: s._pickPedigree,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E7E2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.upload_file_outlined, size: 18, color: Color(0xFF0C5C6C)),
                      const SizedBox(width: 8),
                      Text(cfg.docLabel,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                    ]),
                  ),
                ),
              ],
            ],
          ]),
        ),
        // ── Prévisualisation (toujours cliquable) ─────────────────────────────
        if (s._pedigree && s._pedigreeUrl != null) ...[
          const SizedBox(height: 8),
          _PedigreePreview(
            url: s._pedigreeUrl!,
            onReplace: s._editing ? s._pickPedigree : null,
          ),
        ],
        const SizedBox(height: 4),
      ]),
    );
  }

  void _showParentPicker(
    BuildContext context,
    List<Map<String, dynamic>> animaux,
    TextEditingController nomCtrl,
    TextEditingController puceCtrl, {
    bool isMere = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text('Choisir la ${isMere ? 'mère' : 'père'}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 8),
            if (animaux.isEmpty)
              const Expanded(child: Center(child: Text('Aucun animal trouvé', style: TextStyle(color: Colors.grey))))
            else
              Expanded(
                child: ListView.separated(
                  controller: sc,
                  itemCount: animaux.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (_, i) {
                    final a = animaux[i];
                    final photoUrl = a['photo_url'] as String?;
                    final subtitle = [a['race'], a['identification'] != null ? '#${a['identification']}' : null]
                        .whereType<String>().join(' · ');
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: photoUrl != null
                            ? CachedNetworkImage(imageUrl: photoUrl, width: 40, height: 40, fit: BoxFit.cover)
                            : Container(width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: isMere ? const Color(0xFFEEF5EA) : const Color(0xFFE8F4F8),
                                  borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.pets, color: isMere ? const Color(0xFF6E9E57) : const Color(0xFF0C5C6C), size: 20)),
                      ),
                      title: Text(a['nom'] ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6F767B))) : null,
                      onTap: () {
                        nomCtrl.text = a['nom'] ?? '';
                        puceCtrl.text = a['identification'] ?? '';
                        if (isMere) {
                          final dn = a['date_naissance'] as String?;
                          final race = a['race'] as String?;
                          s.setState(() {
                            if (dn != null && dn.isNotEmpty) s._dateNaissanceMere = DateTime.tryParse(dn);
                            if (race != null && race.isNotEmpty) s._raceMereCtrl.text = race;
                          });
                        }
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _genealogieSection(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('Généalogie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
            fontSize: 14, color: Color(0xFF1F2A2E))),
      ),
      Row(children: [
        const SizedBox(width: 6),
        FaIcon(FontAwesomeIcons.mars, size: 14, color: Colors.blue.shade300),
        const SizedBox(width: 6),
        const Text('Père', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
        const Spacer(),
        if (s._mesMales.isNotEmpty)
          GestureDetector(
            onTap: () => _showParentPicker(context, s._mesMales, s._nomPereCtrl, s._pucePereCtrl),
            child: const Text('Choisir parmi mes animaux',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C), fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _inlineField('Nom du père', s._nomPereCtrl)),
        const SizedBox(width: 8),
        Expanded(child: _inlineField('N° puce père', s._pucePereCtrl)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const SizedBox(width: 6),
        FaIcon(FontAwesomeIcons.venus, size: 14, color: Colors.pink.shade300),
        const SizedBox(width: 6),
        const Text('Mère', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
        const Spacer(),
        if (s._mesFemelles.isNotEmpty)
          GestureDetector(
            onTap: () => _showParentPicker(context, s._mesFemelles, s._nomMereCtrl, s._puceMereCtrl, isMere: true),
            child: const Text('Choisir parmi mes animaux',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _inlineField('Nom de la mère', s._nomMereCtrl)),
        const SizedBox(width: 8),
        Expanded(child: _inlineField('N° puce mère', s._puceMereCtrl)),
      ]),
    ]);
  }

  // ── Section Registre Entrée / Sortie ────────────────────────────────────────

  Widget _registreSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.swap_horiz_outlined, color: Color(0xFF0C5C6C), size: 20),
          title: const Text('Registre Entrée / Sortie',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 14, color: Color(0xFF0C5C6C))),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            // ── Statut ───────────────────────────────────────────────────
            const Text('Statut de l\'animal', style: TextStyle(
                fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                color: Color(0xFF6F767B))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final e in [('present', 'Présent', Color(0xFF6E9E57)), ('sorti', 'Sorti', Color(0xFF0C5C6C)), ('decede', 'Décédé', Colors.redAccent)])
                GestureDetector(
                  onTap: () => s.setState(() => s._statut = e.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: s._statut == e.$1 ? e.$3 : Colors.transparent,
                      border: Border.all(color: s._statut == e.$1 ? e.$3 : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(e.$2, style: TextStyle(
                        fontFamily: 'Galey', fontSize: 12,
                        fontWeight: s._statut == e.$1 ? FontWeight.w600 : FontWeight.normal,
                        color: s._statut == e.$1 ? Colors.white : Colors.black87)),
                  ),
                ),
            ]),
            const SizedBox(height: 14),

            // ── Entrée ───────────────────────────────────────────────────
            const Text('Entrée', style: TextStyle(
                fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                color: Color(0xFF6F767B))),
            const SizedBox(height: 8),
            _dateRegistreField(context, 'Date d\'entrée *', s._dateEntree,
                (d) => s.setState(() => s._dateEntree = d)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: s._provenanceQualite.isEmpty ? null : s._provenanceQualite,
              isExpanded: true,
              hint: const Text('Qualité du fournisseur', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
              decoration: _dropDeco(),
              items: ['naissance', 'eleveur', 'particulier', 'refuge', 'importation', 'autre'].map((v) =>
                  DropdownMenuItem(value: v, child: Text(_qualiteLabel(v),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13)))).toList(),
              onChanged: (v) {
                s.setState(() => s._provenanceQualite = v ?? '');
                if (v == 'naissance') {
                  if (s._dateEntree == null && s._dateNaissance != null) {
                    s.setState(() => s._dateEntree = s._dateNaissance);
                  }
                  if (s._provenanceNomCtrl.text.isEmpty && (s._nomElevage?.isNotEmpty ?? false)) {
                    s._provenanceNomCtrl.text = s._nomElevage!;
                  }
                  if (s._provenanceAdresseCtrl.text.isEmpty && (s._adresseElevage?.isNotEmpty ?? false)) {
                    s._provenanceAdresseCtrl.text = s._adresseElevage!;
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            _inlineField('Nom du fournisseur / Origine', s._provenanceNomCtrl),
            const SizedBox(height: 8),
            _inlineField('Adresse du fournisseur', s._provenanceAdresseCtrl),
            if (s._provenanceQualite == 'importation') ...[
              const SizedBox(height: 8),
              _inlineField('Référence justificatifs import', s._importationRefCtrl),
            ],
            const SizedBox(height: 8),
            _hasBreeds ? _raceMereAutocomplete(context) : _inlineField('Race de la mère', s._raceMereCtrl),
            const SizedBox(height: 8),
            _dateRegistreField(context, 'Date de naissance de la mère', s._dateNaissanceMere,
                (d) => s.setState(() => s._dateNaissanceMere = d)),
            if (s._nomMereCtrl.text.isNotEmpty || s._puceMereCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F8EE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7C79A)),
                ),
                child: Row(children: [
                  const Icon(Icons.female, size: 16, color: Color(0xFF6E9E57)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Mère : ${s._nomMereCtrl.text.isNotEmpty ? s._nomMereCtrl.text : '—'}'
                    '${s._puceMereCtrl.text.isNotEmpty ? ' · Puce : ${s._puceMereCtrl.text}' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF4A7A3A)),
                  )),
                ]),
              ),
            ],

            const SizedBox(height: 14),

            // ── Sortie / Mort ─────────────────────────────────────────────
            if (s._statut == 'sorti' || s._statut == 'decede') ...[
              Text(s._statut == 'decede' ? 'Décès' : 'Sortie',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.w600, color: Color(0xFF6F767B))),
              const SizedBox(height: 8),
              _dateRegistreField(context,
                  s._statut == 'decede' ? 'Date de mort' : 'Date de sortie',
                  s._dateSortie, (d) => s.setState(() => s._dateSortie = d)),
              if (s._statut == 'sorti') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: s._destinataireQualite.isEmpty ? null : s._destinataireQualite,
                  isExpanded: true,
                  hint: const Text('Qualité du destinataire', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                  decoration: _dropDeco(),
                  items: ['eleveur', 'particulier', 'refuge', 'autre'].map((v) =>
                      DropdownMenuItem(value: v, child: Text(_qualiteLabel(v),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13)))).toList(),
                  onChanged: (v) => s.setState(() => s._destinataireQualite = v ?? ''),
                ),
                const SizedBox(height: 8),
                _inlineField('Nom du destinataire', s._destinataireNomCtrl),
                const SizedBox(height: 8),
                _inlineField('Adresse du destinataire', s._destinataireAdresseCtrl),
              ],
              if (s._statut == 'decede') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: s._causeMort.isEmpty ? null : s._causeMort,
                  isExpanded: true,
                  hint: const Text('Cause de la mort', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                  decoration: _dropDeco(),
                  items: ['maladie', 'accident', 'naturelle', 'inconnue'].map((v) =>
                      DropdownMenuItem(value: v, child: Text(_causeMortLabel(v),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13)))).toList(),
                  onChanged: (v) => s.setState(() => s._causeMort = v ?? ''),
                ),
              ],
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: s._savingRegistre ? null : s._saveRegistre,
                icon: s._savingRegistre
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 16),
                label: const Text('Enregistrer le registre',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _dateRegistreField(BuildContext context, String label, DateTime? value, ValueChanged<DateTime> onPick) {
    final fmt = DateFormat('dd/MM/yyyy');
    return GestureDetector(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1990), lastDate: DateTime(2100),
          builder: (ctx, child) => Theme(
            data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF0C5C6C))),
            child: child!,
          ),
        );
        if (d != null) onPick(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
        child: Text(value != null ? fmt.format(value) : '—',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: value != null ? const Color(0xFF1F2A2E) : Colors.grey.shade400)),
      ),
    );
  }

  static InputDecoration _dropDeco() => InputDecoration(
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
    isDense: true,
  );

  static String _qualiteLabel(String v) => const {
    'naissance': 'Naissance dans l\'élevage', 'eleveur': 'Éleveur', 'particulier': 'Particulier',
    'refuge': 'Refuge / Association', 'importation': 'Importation', 'autre': 'Autre',
    'eleveur_dest': 'Éleveur', 'refuge_dest': 'Refuge',
  }[v] ?? v;

  static String _causeMortLabel(String v) => const {
    'maladie': 'Maladie', 'accident': 'Accident', 'naturelle': 'Mort naturelle', 'inconnue': 'Cause inconnue',
  }[v] ?? v;

  static const _docTypes = [
    ('Test ADN',            'adn',        Icons.science_outlined),
    ('Santé reproducteur',  'sante_repro', Icons.health_and_safety_outlined),
    ('Filiation',           'filiation',  Icons.family_restroom_outlined),
    ('Test hanches',        'hanches',    Icons.accessibility_outlined),
    ('Autre',               'autre',      Icons.description_outlined),
  ];

  Widget _documentsSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Documents',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E))),
          if (s._editing)
            PopupMenuButton<({String nom, String type})>(
              onSelected: (item) => s._pickDocument(item.nom, item.type),
              icon: const Icon(Icons.add, color: Color(0xFF6E9E57)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (_) => _docTypes.map((t) => PopupMenuItem(
                value: (nom: t.$1, type: t.$2),
                child: Row(children: [
                  Icon(t.$3, size: 16, color: const Color(0xFF0C5C6C)),
                  const SizedBox(width: 10),
                  Text(t.$1, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ]),
              )).toList(),
            ),
        ]),
        if (s._documents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun document chargé',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
          ),
        ...s._documents.asMap().entries.map((e) {
          final i = e.key;
          final doc = e.value;
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description_outlined, size: 18, color: Color(0xFF0C5C6C)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doc['nom']!, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
                Text(_docTypeLabel(doc['type']!),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
              ])),
              if ((doc['url'] ?? '').isNotEmpty)
                IconButton(
                  icon: Icon(
                    _isImageUrl(doc['url']!) ? Icons.image_outlined : Icons.open_in_new,
                    size: 18, color: const Color(0xFF0C5C6C)),
                  onPressed: () => _openDoc(context, doc['url']!),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
              if (s._editing)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () => s.setState(() => s._documents.removeAt(i)),
                  padding: const EdgeInsets.only(left: 4), constraints: const BoxConstraints(),
                ),
            ]),
          );
        }),
      ]),
    );
  }

  String _docTypeLabel(String type) {
    switch (type) {
      case 'adn':        return 'Test ADN';
      case 'sante_repro': return 'Santé reproducteur';
      case 'filiation':  return 'Filiation';
      case 'hanches':    return 'Test hanches';
      default:           return 'Autre';
    }
  }

  Widget _inlineField(String label, TextEditingController ctrl) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
      ),
    );
  }
}

// ─── Visualiseur de document ──────────────────────────────────────────────────

bool _isImageUrl(String url) {
  final lower = url.toLowerCase().split('?').first;
  return lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
      lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.gif');
}

void _openDoc(BuildContext context, String url) {
  if (_isImageUrl(url)) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ImageViewerPage(url: url),
    ));
  } else {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

class _PedigreePreview extends StatelessWidget {
  const _PedigreePreview({required this.url, required this.onReplace});
  final String url;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final isImage = _isImageUrl(url);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDoc(context, url),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF6E9E57).withOpacity(0.4)),
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFFEEF5EA),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isImage
                  ? Image.network(url, width: 48, height: 48, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _DocIcon())
                  : const _DocIcon(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Document chargé ✓',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        fontWeight: FontWeight.w600, color: Color(0xFF6E9E57))),
                Text(isImage ? 'Appuyez pour agrandir' : 'Appuyez pour ouvrir le PDF',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
              ]),
            ),
            if (onReplace != null)
              GestureDetector(
                onTap: onReplace,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: const Text('Modifier',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C))),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _DocIcon extends StatelessWidget {
  const _DocIcon();
  @override
  Widget build(BuildContext context) => Container(
    width: 48, height: 48,
    color: const Color(0xFFB07D3A).withOpacity(0.12),
    child: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFB07D3A), size: 26),
  );
}

// ─── Banner mise en retraite ──────────────────────────────────────────────────

class _RetraiteBanner extends StatelessWidget {
  const _RetraiteBanner({required this.jours, required this.espece});
  final int jours;
  final String espece;

  static const _agesRetraite = <String, int>{
    'chien': 7, 'chat': 8, 'lapin': 5,
    'cheval': 18, 'ovin': 8, 'caprin': 8, 'porcin': 5, 'ane': 15,
  };

  @override
  Widget build(BuildContext context) {
    final ageRetraite = _agesRetraite[espece] ?? '?';
    final bool atteint = jours <= 0;
    final color = atteint ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final bg = atteint ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
    final border = atteint ? const Color(0xFFFCA5A5) : const Color(0xFFFDE68A);

    final String label;
    if (atteint) {
      label = 'Âge de retraite reproductive atteint ($ageRetraite ans) — arrêt de la reproduction recommandé.';
    } else if (jours == 1) {
      label = 'Retraite reproductive demain ($ageRetraite ans) — préparez la mise en retraite.';
    } else {
      label = 'Retraite reproductive dans $jours jours ($ageRetraite ans) — préparez la mise en retraite.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Icon(atteint ? Icons.block : Icons.warning_amber_rounded, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Onglet Suivi Repro ───────────────────────────────────────────────────────

class _SuiviReproTab extends StatelessWidget {
  final String? animalId;
  final String espece;
  final String sexe;
  final int? intervalleChaleursCustom;
  const _SuiviReproTab({this.animalId, required this.espece, required this.sexe, this.intervalleChaleursCustom});

  @override
  Widget build(BuildContext context) {
    if (animalId == null) return const _SaveFirstPrompt(message: 'Enregistrez d\'abord la fiche pour accéder au suivi reproducteur.');

    final isMale = sexe == 'male';

    final tabs = isMale
        ? const [Tab(text: 'Saillies')]
        : const [Tab(text: 'Chaleurs'), Tab(text: 'Saillies'), Tab(text: 'Gestations')];

    final views = isMale
        ? [_ReproList(
            animalId: animalId!, collection: 'saillies',
            addBuilder: (ctx) => _AddSaillieDialog(animalId: animalId!, espece: espece, sexeAnimal: sexe),
            editBuilder: (ctx, d) => _AddSaillieDialog(animalId: animalId!, espece: espece, sexeAnimal: sexe, existing: d),
          )]
        : [
            _ChaleursTab(animalId: animalId!, espece: espece, intervalleCustom: intervalleChaleursCustom),
            _ReproList(
              animalId: animalId!, collection: 'saillies',
              addBuilder: (ctx) => _AddSaillieDialog(animalId: animalId!, espece: espece, sexeAnimal: sexe),
              editBuilder: (ctx, d) => _AddSaillieDialog(animalId: animalId!, espece: espece, sexeAnimal: sexe, existing: d),
            ),
            _ReproList(
              animalId: animalId!, collection: 'gestations',
              addBuilder: (ctx) => _AddGestationDialog(animalId: animalId!, espece: espece),
              editBuilder: (ctx, d) => _AddGestationDialog(animalId: animalId!, espece: espece, existing: d),
            ),
          ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        Container(
          color: Colors.white,
          child: TabBar(
            labelColor: const Color(0xFF6E9E57),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF6E9E57),
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600),
            tabs: tabs,
          ),
        ),
        Expanded(child: TabBarView(children: views)),
      ]),
    );
  }
}

class _ReproList extends StatefulWidget {
  final String animalId;
  final String collection;
  final Widget Function(BuildContext) addBuilder;
  final Widget Function(BuildContext, Map<String, dynamic>)? editBuilder;
  const _ReproList({required this.animalId, required this.collection, required this.addBuilder, this.editBuilder});
  @override
  State<_ReproList> createState() => _ReproListState();
}

class _ReproListState extends State<_ReproList> {
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final rows = await Supabase.instance.client
          .from(widget.collection)
          .select()
          .eq('animal_id', widget.animalId)
          .order('date', ascending: false);
      if (mounted) setState(() { _data = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await Supabase.instance.client.from(widget.collection).delete().eq('id', id);
      if (mounted) setState(() => _data.removeWhere((d) => d['id']?.toString() == id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmGestation(String id) async {
    try {
      final supa = Supabase.instance.client;
      await supa.from('gestations').update({'gestation_confirmee': true}).eq('id', id);

      // Sync agenda mise-bas
      final idx   = _data.indexWhere((d) => d['id']?.toString() == id);
      final gest  = idx >= 0 ? _data[idx] : null;
      final datePrevue = gest?['date_prevue'] as String?;
      final uid   = FirebaseAuth.instance.currentUser?.uid;

      if (datePrevue != null && uid != null) {
        String animalNom = 'animal';
        try {
          final a = await supa.from('animaux').select('nom').eq('id', widget.animalId).maybeSingle();
          if (a != null) animalNom = (a['nom'] as String?)?.isNotEmpty == true ? a['nom'] as String : 'animal';
        } catch (_) {}

        final existing = await supa.from('agenda_events')
            .select('id').eq('gestation_id', id).maybeSingle();
        final eventData = {
          'uid':          uid,
          'titre':        'Mise-bas prévue — $animalNom',
          'type':         'mise_bas',
          'date_debut':   datePrevue,
          'animal_id':    int.tryParse(widget.animalId),
          'notes':        'Gestation confirmée',
          'gestation_id': id,
        };
        if (existing != null) {
          await supa.from('agenda_events').update(eventData).eq('id', existing['id']);
        } else {
          await supa.from('agenda_events').insert(eventData);
        }
      }

      if (mounted) setState(() {
        if (idx >= 0) _data[idx] = {..._data[idx], 'gestation_confirmee': true};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Gestation confirmée ✓  ·  Agenda mis à jour'),
            backgroundColor: Color(0xFF6E9E57)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () async {
          await showDialog(context: context, builder: widget.addBuilder);
          _refresh();
        },
        backgroundColor: const Color(0xFF6E9E57),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
          : _data.isEmpty
              ? Center(child: Text('Aucun enregistrement',
                  style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey')))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _data.length,
                  itemBuilder: (_, i) {
                    final d = _data[i];
                    final id = d['id']?.toString() ?? '';
                    final isGestation = widget.collection == 'gestations';
                    final alreadyConfirmed = d['gestation_confirmee'] as bool? ?? false;
                    return _SimpleCard(
                      data: d,
                      collection: widget.collection,
                      onDelete: () => _delete(id),
                      onEdit: widget.editBuilder != null ? () async {
                        await showDialog(context: context, builder: (ctx) => widget.editBuilder!(ctx, d));
                        _refresh();
                      } : null,
                      onConfirmGestation: (isGestation && !alreadyConfirmed)
                          ? () => _confirmGestation(id)
                          : null,
                    );
                  },
                ),
    );
  }
}

// ─── Onglet Carnet Santé ──────────────────────────────────────────────────────

class _CarnetSanteTab extends StatelessWidget {
  final String? animalId;
  const _CarnetSanteTab({this.animalId});

  static const _cats = [
    (key: 'vaccinations',     label: 'Vaccins',              icon: Icons.vaccines_outlined,             color: Color(0xFF0C5C6C)),
    (key: 'vermifuges',       label: 'Vermifuges',            icon: Icons.bug_report_outlined,           color: Color(0xFF6E9E57)),
    (key: 'antiparasitaires', label: 'Antiparasitaires',      icon: Icons.pest_control_outlined,         color: Color(0xFF5B8648)),
    (key: 'traitements',      label: 'Traitements',           icon: Icons.medication_outlined,           color: Color(0xFF8D6E63)),
    (key: 'allergies',        label: 'Allergies',             icon: Icons.warning_amber_outlined,        color: Color(0xFFE25C5C)),
    (key: 'poids',            label: 'Courbe de poids',       icon: Icons.monitor_weight_outlined,       color: Color(0xFF5F9EAA)),
    (key: 'visites',          label: 'Visites vétérinaires',  icon: Icons.medical_services_outlined,     color: Color(0xFF26A69A)),
  ];

  @override
  Widget build(BuildContext context) {
    if (animalId == null) return const _SaveFirstPrompt(message: 'Enregistrez d\'abord la fiche pour accéder au carnet de santé.');
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _cats.length,
      itemBuilder: (_, i) {
        final cat = _cats[i];
        return _SanteTile(
          animalId: animalId!,
          collection: cat.key,
          label: cat.label,
          icon: cat.icon,
          color: cat.color,
        );
      },
    );
  }
}

class _SanteTile extends StatelessWidget {
  final String animalId;
  final String collection;
  final String label;
  final IconData icon;
  final Color color;
  const _SanteTile({required this.animalId, required this.collection,
      required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from(collection).stream(primaryKey: ['id']).eq('animal_id', animalId),
      builder: (ctx, snap) {
        final count = snap.data?.length ?? 0;
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => _SanteDetailPage(
              animalId: animalId, collection: collection,
              label: label, icon: icon, color: color,
            ),
          )),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(label,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
                    textAlign: TextAlign.center, maxLines: 2),
              ),
              const SizedBox(height: 3),
              Text(
                count == 0 ? 'Aucune entrée' : '$count entrée${count > 1 ? 's' : ''}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                    color: count > 0 ? color : Colors.grey.shade400),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _SanteDetailPage extends StatelessWidget {
  final String animalId;
  final String collection;
  final String label;
  final IconData icon;
  final Color color;
  const _SanteDetailPage({required this.animalId, required this.collection,
      required this.label, required this.icon, required this.color});

  Widget _dialogFor(BuildContext ctx) {
    switch (collection) {
      case 'vaccinations':     return _AddVaccinDialog(animalId: animalId);
      case 'vermifuges':       return _AddVermifugeDialog(animalId: animalId);
      case 'antiparasitaires': return _AddAntiparasitaireDialog(animalId: animalId);
      case 'traitements':      return _AddTraitementDialog(animalId: animalId);
      case 'allergies':        return _AddAllergieDialog(animalId: animalId);
      case 'visites':          return _AddVisiteDialog(animalId: animalId);
      default:                 return _AddVaccinDialog(animalId: animalId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        title: Text(label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: collection == 'poids'
          ? _PoidsTab(animalId: animalId)
          : _SanteList(animalId: animalId, collection: collection, icon: icon, addBuilder: _dialogFor),
    );
  }
}

class _SanteList extends StatefulWidget {
  final String animalId;
  final String collection;
  final IconData icon;
  final Widget Function(BuildContext) addBuilder;
  const _SanteList({required this.animalId, required this.collection, required this.icon, required this.addBuilder});
  @override
  State<_SanteList> createState() => _SanteListState();
}

class _SanteListState extends State<_SanteList> {
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final rows = await Supabase.instance.client
          .from(widget.collection)
          .select()
          .eq('animal_id', widget.animalId)
          .order('date', ascending: false);
      if (mounted) setState(() { _data = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _title(Map<String, dynamic> data) {
    if (widget.collection == 'vaccinations')     return data['vaccin'] ?? 'Vaccin';
    if (widget.collection == 'traitements')      return data['nom'] ?? data['type'] ?? 'Traitement';
    if (widget.collection == 'vermifuges')       return data['produit'] ?? 'Vermifuge';
    if (widget.collection == 'antiparasitaires') return data['produit'] ?? data['type'] ?? 'Antiparasitaire';
    if (widget.collection == 'allergies')        return data['description'] ?? data['type'] ?? 'Allergie';
    return data['motif'] ?? 'Visite';
  }

  Future<void> _delete(String id) async {
    try {
      await Supabase.instance.client.from(widget.collection).delete().eq('id', id);
      if (mounted) setState(() => _data.removeWhere((d) => d['id']?.toString() == id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () async {
          await showDialog(context: context, builder: widget.addBuilder);
          _refresh();
        },
        backgroundColor: const Color(0xFF6E9E57),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
          : _data.isEmpty
              ? Center(child: Text('Aucun enregistrement',
                  style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey')))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _data.length,
                  itemBuilder: (_, i) {
                    final d = _data[i];
                    return _SanteCard(
                      title: _title(d), data: d, icon: widget.icon,
                      onDelete: () => _delete(d['id']?.toString() ?? ''),
                    );
                  },
                ),
    );
  }
}

// ─── Cards communes ───────────────────────────────────────────────────────────

class _SimpleCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final String? collection;
  final VoidCallback? onConfirmGestation;
  const _SimpleCard({required this.data, required this.onDelete, this.onEdit,
      this.collection, this.onConfirmGestation});

  static const _labels = {
    'nom_partenaire':   'Partenaire',
    'ident_partenaire': 'Identification',
    'methode':          'Méthode',
    'notes':            'Notes',
    'extra_date':       'Date complémentaire',
    'nb_attendu':       'Petits attendus',
    'nb_nes':           'Petits nés',
    'date_conception':  'Date de conception',
    'date_prevue':      'Mise-bas prévue',
    'date_naissance':   'Date de mise-bas réelle',
  };

  static const _excludedKeys = {
    'date', 'id', 'animal_id', 'created_at', 'partenaire_animal_id', 'gestation_confirmee',
  };

  static String _fmt(String key, dynamic val) {
    if (val == null) return '';
    if (val is bool) return val ? 'Oui' : 'Non';
    if (val.toString().isEmpty) return '';
    if (val is String && key.contains('date') && val.isNotEmpty) {
      final dt = DateTime.tryParse(val);
      if (dt != null) return DateFormat('dd/MM/yyyy').format(dt);
    }
    return val.toString();
  }

  void _showDetail(BuildContext context) {
    final rawDate = data['date'];
    final date = rawDate is String && rawDate.isNotEmpty
        ? (DateTime.tryParse(rawDate) != null
            ? DateFormat('dd/MM/yyyy').format(DateTime.parse(rawDate))
            : rawDate)
        : '';
    final isGestation = collection == 'gestations';
    final confirmee   = data['gestation_confirmee'] as bool? ?? false;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(
            isGestation ? 'Détail gestation'
                : collection == 'saillies' ? 'Détail saillie'
                : 'Détail chaleurs',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          if (date.isNotEmpty)
            _DetailRow(label: 'Date', value: date),
          ...data.entries
              .where((e) => !_excludedKeys.contains(e.key)
                  && e.value != null && e.value.toString().isNotEmpty)
              .map((e) {
                final v = _fmt(e.key, e.value);
                if (v.isEmpty) return const SizedBox.shrink();
                final label = _labels[e.key] ?? e.key.replaceAll('_', ' ');
                return _DetailRow(label: label, value: v);
              }),
          if (isGestation) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: confirmee ? const Color(0xFFEEF5EA) : const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: confirmee ? const Color(0xFF6E9E57) : const Color(0xFFFFCC02)),
              ),
              child: Text(
                confirmee ? '✓ Gestation confirmée' : '⏳ Gestation à confirmer',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                    color: confirmee ? const Color(0xFF4A7A3A) : const Color(0xFF9E7000)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (isGestation && !confirmee && onConfirmGestation != null)
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6E9E57),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                label: const Text('Confirmer la gestation',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700)),
                onPressed: () {
                  Navigator.pop(context);
                  onConfirmGestation!();
                },
              ),
            ),
          if (onEdit != null)
            TextButton.icon(
              onPressed: () { Navigator.pop(context); onEdit!(); },
              icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF6E9E57)),
              label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawDate = data['date'];
    final date = rawDate is String && rawDate.isNotEmpty
        ? (DateTime.tryParse(rawDate) != null
            ? DateFormat('dd/MM/yyyy').format(DateTime.parse(rawDate))
            : rawDate)
        : '';
    final hasConfirmee = data.containsKey('gestation_confirmee');
    final confirmee = data['gestation_confirmee'] as bool? ?? false;
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Text(date, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
              if (hasConfirmee) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: confirmee ? const Color(0xFFEEF5EA) : const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: confirmee ? const Color(0xFF6E9E57) : const Color(0xFFFFCC02)),
                  ),
                  child: Text(
                    confirmee ? '✓ Confirmée' : 'À confirmer',
                    style: TextStyle(
                      fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600,
                      color: confirmee ? const Color(0xFF4A7A3A) : const Color(0xFF9E7000),
                    ),
                  ),
                ),
              ],
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),
          ]),
          ...data.entries
              .where((e) => !_excludedKeys.contains(e.key)
                  && e.value != null && e.value.toString().isNotEmpty)
              .map((e) {
            final v = _fmt(e.key, e.value);
            if (v.isEmpty) return const SizedBox.shrink();
            final label = _labels[e.key] ?? e.key.replaceAll('_', ' ');
            return Padding(padding: const EdgeInsets.only(top: 3),
              child: Text('$label : $v', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))));
          }),
        ]),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 150,
        child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
            fontWeight: FontWeight.w600, color: Color(0xFF6F767B)))),
      Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
    ]),
  );
}

class _SanteCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  final IconData icon;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  const _SanteCard({required this.title, required this.data, required this.icon,
      required this.onDelete, this.onTap});

  static const _labels = {
    'vaccin': 'Vaccin', 'lot': 'N° de lot', 'veterinaire': 'Vétérinaire',
    'date': 'Date', 'date_rappel': 'Rappel', 'date_fin': 'Date de fin',
    'produit': 'Produit', 'dosage': 'Dosage', 'frequence': 'Fréquence',
    'type': 'Type', 'nom': 'Nom', 'posologie': 'Posologie',
    'description': 'Description', 'severite': 'Sévérité',
    'motif': 'Motif', 'diagnostic': 'Diagnostic', 'notes': 'Notes',
    'valeur': 'Poids (kg)',
  };

  static String _fmtVal(String key, dynamic val) {
    if (val == null || val.toString().isEmpty) return '';
    if (val is String && key.contains('date') && val.isNotEmpty) {
      final dt = DateTime.tryParse(val);
      if (dt != null) return DateFormat('dd/MM/yyyy').format(dt);
    }
    return val.toString();
  }

  void _showDetail(BuildContext context) {
    const _skip = {'id', 'animal_id', 'created_at'};
    final entries = data.entries.where((e) =>
        !_skip.contains(e.key) && e.value != null && e.value.toString().isNotEmpty).toList();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 17)),
              ),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const Divider(),
            ...entries.map((e) {
              final label = _labels[e.key] ?? e.key;
              final val   = _fmtVal(e.key, e.value);
              if (val.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(label,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 13,
                              color: Color(0xFF6F767B),
                              fontWeight: FontWeight.w500)),
                    ),
                    Expanded(
                      child: Text(val,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawDate = data['date'] as String?;
    final date = rawDate != null && rawDate.isNotEmpty
        ? (DateTime.tryParse(rawDate) != null
            ? DateFormat('dd/MM/yyyy').format(DateTime.parse(rawDate))
            : rawDate)
        : '';
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: const Color(0xFF6E9E57), size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
            if (date.isNotEmpty) Text(date, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
          ])),
          const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 18),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
      ),
    );
  }
}

// ─── Onglet Poids ─────────────────────────────────────────────────────────────

String _fmtPoids(double v) {
  if (v < 1) return v.toStringAsFixed(3);
  if (v < 10) return v.toStringAsFixed(1);
  return v.toStringAsFixed(0);
}

class _PoidsTab extends StatefulWidget {
  final String animalId;
  const _PoidsTab({required this.animalId});
  @override State<_PoidsTab> createState() => _PoidsTabState();
}
class _PoidsTabState extends State<_PoidsTab> {
  int _refreshKey = 0;
  DateTime? _dateNaissance;

  @override
  void initState() {
    super.initState();
    _fetchBirthDate();
  }

  Future<void> _fetchBirthDate() async {
    final res = await Supabase.instance.client
        .from('animaux').select('date_naissance').eq('id', widget.animalId).maybeSingle();
    if (!mounted || res == null) return;
    final raw = res['date_naissance'] as String?;
    if (raw != null && raw.isNotEmpty) setState(() => _dateNaissance = DateTime.tryParse(raw));
  }

  bool get _isJuvenile {
    if (_dateNaissance == null) return false;
    return DateTime.now().difference(_dateNaissance!).inDays < 548;
  }

  void _refresh() { if (mounted) setState(() => _refreshKey++); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => showDialog(context: context,
            builder: (_) => _AddPoidsDialog(animalId: widget.animalId))
            .then((_) => _refresh()),
        backgroundColor: const Color(0xFF6E9E57),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(_refreshKey),
        stream: Supabase.instance.client
            .from('poids')
            .stream(primaryKey: ['id'])
            .eq('animal_id', widget.animalId)
            .order('date', ascending: true),
        builder: (ctx, snap) {
          if (!snap.hasData || snap.data!.isEmpty) {
            return Center(child: Text('Aucune pesée enregistrée',
                style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey')));
          }
          final docs = snap.data!;
          final vals = docs.map((d) =>
              double.tryParse(d['valeur']?.toString() ?? '') ?? 0.0).toList();
          final maxPoids = vals.isEmpty ? 1.0 : vals.reduce((a, b) => a > b ? a : b);
          final showChart = docs.length >= 2;

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: docs.length + (showChart ? 1 : 0),
            itemBuilder: (_, rawIdx) {
              if (showChart && rawIdx == 0) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: _WeightChart(docs: docs, isJuvenile: _isJuvenile, dateNaissance: _dateNaissance),
                );
              }
              final i = rawIdx - (showChart ? 1 : 0);
              final d   = docs[i];
              final raw = d['date'] as String?;
              final date = raw != null && raw.isNotEmpty
                  ? (DateTime.tryParse(raw) != null
                      ? DateFormat('dd/MM/yyyy').format(DateTime.parse(raw))
                      : raw)
                  : '';
              final val = vals[i];
              final pct = maxPoids > 0 ? val / maxPoids : 0.0;
              return Container(
                margin: EdgeInsets.only(bottom: 10, top: i == 0 && !showChart ? 16 : 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5)]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(date, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                    Row(children: [
                      Text('${_fmtPoids(val)} kg',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 16, color: Color(0xFF1F2A2E))),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF0C5C6C)),
                        onPressed: () => showDialog(context: context,
                            builder: (_) => _AddPoidsDialog(animalId: widget.animalId, existing: d))
                            .then((_) => _refresh()),
                        padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        onPressed: () => Supabase.instance.client
                            .from('poids').delete().eq('id', d['id'])
                            .then((_) => _refresh()),
                        padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFEEF5EA),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF6E9E57)),
                    ),
                  ),
                  if ((d['notes'] ?? '').toString().isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4),
                        child: Text(d['notes'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)))),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Weight line chart ─────────────────────────────────────────────────────────

class _WeightChart extends StatefulWidget {
  final List<Map<String, dynamic>> docs;
  final bool isJuvenile;
  final DateTime? dateNaissance;
  const _WeightChart({required this.docs, required this.isJuvenile, this.dateNaissance});
  @override State<_WeightChart> createState() => _WeightChartState();
}
class _WeightChartState extends State<_WeightChart> {
  int? _hoverIdx;

  String _xLabel(int i) {
    final raw = widget.docs[i]['date'] as String? ?? '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    if (widget.isJuvenile && widget.dateNaissance != null) {
      final days = dt.difference(widget.dateNaissance!).inDays.abs();
      if (days < 14) return '${days}j';
      if (days < 90) return '${(days / 7).round()}sem';
      return '${(days / 30).round()}m';
    }
    return DateFormat('dd/MM').format(dt);
  }

  List<Offset> _calcPoints(Size size) {
    const l = 44.0, t = 20.0, r = 12.0, b = 30.0;
    final w = size.width - l - r;
    final h = size.height - t - b;
    final vals = widget.docs.map((d) => double.tryParse(d['valeur']?.toString() ?? '') ?? 0.0).toList();
    final minY = vals.reduce((a, b) => a < b ? a : b);
    final maxY = vals.reduce((a, b) => a > b ? a : b);
    final rangeY = (maxY - minY) < 0.01 ? 1.0 : (maxY - minY) * 1.2;
    final baseY = minY - rangeY * 0.1;
    return List.generate(vals.length, (i) {
      final x = l + (vals.length < 2 ? w / 2 : i * w / (vals.length - 1));
      final y = t + h - ((vals[i] - baseY) / rangeY) * h;
      return Offset(x, y);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 195,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(builder: (_, c) {
          return GestureDetector(
            onTapDown: (d) {
              final pts = _calcPoints(Size(c.maxWidth, c.maxHeight));
              int? best;
              double bestDist = 32;
              for (int i = 0; i < pts.length; i++) {
                final dist = (pts[i] - d.localPosition).distance;
                if (dist < bestDist) { bestDist = dist; best = i; }
              }
              setState(() => _hoverIdx = best == _hoverIdx ? null : best);
            },
            child: CustomPaint(
              painter: _ChartPainter(
                docs: widget.docs,
                isJuvenile: widget.isJuvenile,
                hoverIdx: _hoverIdx,
                xLabelFn: _xLabel,
              ),
              child: const SizedBox.expand(),
            ),
          );
        }),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> docs;
  final bool isJuvenile;
  final int? hoverIdx;
  final String Function(int) xLabelFn;

  static const _l = 44.0, _t = 20.0, _r = 12.0, _b = 30.0;
  static const _accent = Color(0xFF5F9EAA);

  const _ChartPainter({required this.docs, required this.isJuvenile, this.hoverIdx, required this.xLabelFn});

  @override
  bool shouldRepaint(_ChartPainter o) => o.hoverIdx != hoverIdx;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _l - _r;
    final h = size.height - _t - _b;
    final vals = docs.map((d) => double.tryParse(d['valeur']?.toString() ?? '') ?? 0.0).toList();
    if (vals.isEmpty) return;

    final minY = vals.reduce((a, b) => a < b ? a : b);
    final maxY = vals.reduce((a, b) => a > b ? a : b);
    final rangeY = (maxY - minY) < 0.01 ? 1.0 : (maxY - minY) * 1.2;
    final baseY = minY - rangeY * 0.1;

    Offset pt(int i) {
      final x = _l + (vals.length < 2 ? w / 2 : i * w / (vals.length - 1));
      final y = _t + h - ((vals[i] - baseY) / rangeY) * h;
      return Offset(x, y);
    }

    // Title
    final title = isJuvenile ? 'Courbe de croissance' : 'Évolution du poids';
    final titleTp = TextPainter(
      text: TextSpan(text: title, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: _accent)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    titleTp.paint(canvas, Offset(_l, (_t - titleTp.height) / 2));

    // Grid lines
    final gridPaint = Paint()..color = const Color(0xFFF0F0F0)..strokeWidth = 1;
    for (int g = 0; g <= 4; g++) {
      final yVal = baseY + g * rangeY / 4;
      final yPx = _t + h - g * h / 4;
      canvas.drawLine(Offset(_l, yPx), Offset(size.width - _r, yPx), gridPaint);
      final lbl = _fmtPoids(yVal < 0 ? 0 : yVal);
      final tp = TextPainter(
        text: TextSpan(text: lbl, style: const TextStyle(fontFamily: 'Galey', fontSize: 9, color: Color(0xFFBBBBBB))),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_l - tp.width - 4, yPx - tp.height / 2));
    }

    // Area fill + line
    if (vals.length >= 2) {
      final areaPath = Path()..moveTo(pt(0).dx, _t + h);
      for (int i = 0; i < vals.length; i++) areaPath.lineTo(pt(i).dx, pt(i).dy);
      areaPath..lineTo(pt(vals.length - 1).dx, _t + h)..close();
      canvas.drawPath(areaPath, Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x285F9EAA), Color(0x005F9EAA)],
        ).createShader(Rect.fromLTWH(_l, _t, w, h))
        ..style = PaintingStyle.fill);

      final linePath = Path()..moveTo(pt(0).dx, pt(0).dy);
      for (int i = 1; i < vals.length; i++) linePath.lineTo(pt(i).dx, pt(i).dy);
      canvas.drawPath(linePath, Paint()
        ..color = _accent..strokeWidth = 2.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    }

    // Dots + X labels
    final step = ((vals.length - 1) / 4).ceil().clamp(1, vals.length);
    for (int i = 0; i < vals.length; i++) {
      final p = pt(i);
      final isH = hoverIdx == i;
      canvas.drawCircle(p, isH ? 5.5 : 3.5, Paint()..color = _accent);
      canvas.drawCircle(p, isH ? 3.5 : 2.0, Paint()..color = Colors.white);
      if (i == 0 || i == vals.length - 1 || i % step == 0) {
        final tp = TextPainter(
          text: TextSpan(text: xLabelFn(i), style: const TextStyle(fontFamily: 'Galey', fontSize: 9, color: Color(0xFFBBBBBB))),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset((p.dx - tp.width / 2).clamp(_l, size.width - _r - tp.width), _t + h + 6));
      }
    }

    // Tooltip on hover
    if (hoverIdx != null && hoverIdx! < vals.length) {
      final i = hoverIdx!;
      final p = pt(i);
      const pad = 7.0;
      final line1 = '${_fmtPoids(vals[i])} kg';
      final line2 = xLabelFn(i);
      final tp1 = TextPainter(text: TextSpan(text: line1, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)), textDirection: ui.TextDirection.ltr)..layout();
      final tp2 = TextPainter(text: TextSpan(text: line2, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xCCFFFFFF))), textDirection: ui.TextDirection.ltr)..layout();
      final tooltipW = (tp1.width > tp2.width ? tp1.width : tp2.width) + pad * 2;
      final tooltipH = tp1.height + tp2.height + pad * 2 + 2;
      var tx = p.dx - tooltipW / 2;
      var ty = p.dy - tooltipH - 10;
      if (tx < _l) tx = _l;
      if (tx + tooltipW > size.width - _r) tx = size.width - _r - tooltipW;
      if (ty < _t) ty = p.dy + 10;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx, ty, tooltipW, tooltipH), const Radius.circular(8)),
        Paint()..color = _accent,
      );
      tp1.paint(canvas, Offset(tx + pad, ty + pad));
      tp2.paint(canvas, Offset(tx + pad, ty + pad + tp1.height + 2));
    }
  }
}

// ─── Dialogs d'ajout ──────────────────────────────────────────────────────────

class _AddVaccinDialog extends StatefulWidget {
  final String animalId;
  const _AddVaccinDialog({required this.animalId});
  @override State<_AddVaccinDialog> createState() => _AddVaccinDialogState();
}
class _AddVaccinDialogState extends State<_AddVaccinDialog> {
  final _vaccin = TextEditingController();
  final _lot = TextEditingController();
  final _veto = TextEditingController();
  DateTime? _date;
  DateTime? _rappel;
  @override
  Widget build(BuildContext context) => _BaseDialog(title: 'Ajouter un vaccin', fields: [
    _DF('Vaccin *', _vaccin), _DF('N° de lot', _lot), _DF('Vétérinaire', _veto),
    _DD('Date *', _date, (d) => setState(() => _date = d)),
    _DD('Date de rappel', _rappel, (d) => setState(() => _rappel = d)),
  ], onSave: () async {
    if (_vaccin.text.isEmpty || _date == null) return false;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await Supabase.instance.client.from('vaccinations').insert({
      'id': id, 'animal_id': widget.animalId,
      'vaccin': _vaccin.text.trim(), 'lot': _lot.text.trim(), 'veterinaire': _veto.text.trim(),
      'date': _date!.toIso8601String(),
      'date_rappel': _rappel?.toIso8601String(),
    });
    if (_rappel != null) {
      await _scheduleRappelAgenda(
        animalId: widget.animalId,
        dateRappel: _rappel!,
        titre: 'Rappel vaccin — ${_vaccin.text.trim()}',
      );
    }
    RegistreHelper.writeActe(
      animalId: widget.animalId, typeActe: 'vaccination', dateActe: _date!,
      intervenant: _veto.text.trim(),
      description: 'Vaccin : ${_vaccin.text.trim()}${_lot.text.trim().isNotEmpty ? ' (lot ${_lot.text.trim()})' : ''}',
    );
    return true;
  });
}

class _AddTraitementDialog extends StatefulWidget {
  final String animalId;
  const _AddTraitementDialog({required this.animalId});
  @override State<_AddTraitementDialog> createState() => _AddTraitementDialogState();
}
class _AddTraitementDialogState extends State<_AddTraitementDialog> {
  final _nom = TextEditingController();
  final _posologie = TextEditingController();
  String _type = 'antiparasitaire';
  DateTime? _date;
  DateTime? _dateFin;
  @override
  Widget build(BuildContext context) => _BaseDialog(title: 'Ajouter un traitement', fields: [
    _DDrop('Type', _type, ['antiparasitaire', 'medicament', 'autre'], (v) => setState(() => _type = v!)),
    _DF('Nom du produit *', _nom), _DF('Posologie', _posologie),
    _DD('Date début *', _date, (d) => setState(() => _date = d)),
    _DD('Date fin', _dateFin, (d) => setState(() => _dateFin = d)),
  ], onSave: () async {
    if (_nom.text.isEmpty || _date == null) return false;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await Supabase.instance.client.from('traitements').insert({
      'id': id, 'animal_id': widget.animalId,
      'type': _type, 'nom': _nom.text.trim(), 'posologie': _posologie.text.trim(),
      'date': _date!.toIso8601String(),
      'date_fin': _dateFin?.toIso8601String(),
    });
    RegistreHelper.writeActe(
      animalId: widget.animalId, typeActe: 'traitement', dateActe: _date!,
      intervenant: '',
      description: '${_nom.text.trim()}${_posologie.text.trim().isNotEmpty ? ' — ${_posologie.text.trim()}' : ''}',
    );
    return true;
  });
}

class _AddVisiteDialog extends StatefulWidget {
  final String animalId;
  const _AddVisiteDialog({required this.animalId});
  @override State<_AddVisiteDialog> createState() => _AddVisiteDialogState();
}
class _AddVisiteDialogState extends State<_AddVisiteDialog> {
  static const _motifs = ['Consultation', 'Rappel de vaccin', 'Urgence', 'Suivi', 'Autre'];
  String _motif = 'Consultation';
  final _veto   = TextEditingController();
  final _diag   = TextEditingController();
  final _notes  = TextEditingController();
  final _vaccin = TextEditingController();
  final _lot    = TextEditingController();
  DateTime? _date;
  DateTime? _dateRappel;

  bool get _isVaccin => _motif == 'Rappel de vaccin';

  @override
  Widget build(BuildContext context) => _BaseDialog(title: 'Ajouter une visite', fields: [
    _DDrop('Motif *', _motif, _motifs, (v) => setState(() => _motif = v!)),
    _DF('Vétérinaire', _veto),
    _DD('Date *', _date, (d) => setState(() => _date = d)),
    if (_isVaccin) ...[
      _DF('Vaccin *', _vaccin),
      _DF('N° de lot', _lot),
      _DD('Date de rappel', _dateRappel, (d) => setState(() => _dateRappel = d)),
    ],
    _DF('Diagnostic / Observations', _diag),
    _DF('Notes', _notes, maxLines: 3),
  ], onSave: () async {
    if (_date == null) return false;
    if (_isVaccin && _vaccin.text.trim().isEmpty) return false;
    final supa = Supabase.instance.client;
    final visiteId = DateTime.now().microsecondsSinceEpoch.toString();
    await supa.from('visites').insert({
      'id': visiteId, 'animal_id': widget.animalId,
      'motif': _motif, 'veterinaire': _veto.text.trim(),
      'date': _date!.toIso8601String(),
      'diagnostic': _diag.text.trim(), 'notes': _notes.text.trim(),
    });
    if (_isVaccin) {
      final vacId = (DateTime.now().microsecondsSinceEpoch + 1).toString();
      await supa.from('vaccinations').insert({
        'id': vacId, 'animal_id': widget.animalId,
        'vaccin': _vaccin.text.trim(), 'lot': _lot.text.trim(),
        'veterinaire': _veto.text.trim(),
        'date': _date!.toIso8601String(),
        'date_rappel': _dateRappel?.toIso8601String(),
      });
      if (_dateRappel != null) {
        await _scheduleRappelAgenda(
          animalId: widget.animalId,
          dateRappel: _dateRappel!,
          titre: 'Rappel vaccin — ${_vaccin.text.trim()}',
        );
      }
    }
    RegistreHelper.writeActe(
      animalId: widget.animalId,
      typeActe: _isVaccin ? 'vaccination' : 'visite',
      dateActe: _date!,
      intervenant: _veto.text.trim(),
      description: [
        _motif,
        if (_isVaccin && _vaccin.text.trim().isNotEmpty) 'Vaccin : ${_vaccin.text.trim()}',
        if (_diag.text.trim().isNotEmpty) _diag.text.trim(),
      ].join(' — '),
    );
    return true;
  });
}

class _AddVermifugeDialog extends StatefulWidget {
  final String animalId;
  const _AddVermifugeDialog({required this.animalId});
  @override State<_AddVermifugeDialog> createState() => _AddVermifugeDialogState();
}
class _AddVermifugeDialogState extends State<_AddVermifugeDialog> {
  final _produit = TextEditingController();
  final _dosage  = TextEditingController();
  final _notes   = TextEditingController();
  DateTime? _date, _dateRappel;
  @override
  Widget build(BuildContext context) => _BaseDialog(title: 'Ajouter un vermifuge', fields: [
    _DF('Produit *', _produit),
    _DF('Dosage', _dosage),
    _DD('Date *', _date, (d) => setState(() => _date = d)),
    _DD('Prochain rappel', _dateRappel, (d) => setState(() => _dateRappel = d)),
    _DF('Notes', _notes, maxLines: 2),
  ], onSave: () async {
    if (_produit.text.isEmpty || _date == null) return false;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await Supabase.instance.client.from('vermifuges').insert({
      'id': id, 'animal_id': widget.animalId,
      'produit': _produit.text.trim(), 'dosage': _dosage.text.trim(),
      'date': _date!.toIso8601String(),
      'date_rappel': _dateRappel?.toIso8601String(),
      'notes': _notes.text.trim(),
    });
    RegistreHelper.writeActe(
      animalId: widget.animalId, typeActe: 'vermifuge', dateActe: _date!,
      intervenant: '',
      description: '${_produit.text.trim()}${_dosage.text.trim().isNotEmpty ? ' — ${_dosage.text.trim()}' : ''}',
    );
    return true;
  });
}

class _AddAntiparasitaireDialog extends StatefulWidget {
  final String animalId;
  const _AddAntiparasitaireDialog({required this.animalId});
  @override State<_AddAntiparasitaireDialog> createState() => _AddAntiparasitaireDialogState();
}
class _AddAntiparasitaireDialogState extends State<_AddAntiparasitaireDialog> {
  final _produit   = TextEditingController();
  final _frequence = TextEditingController();
  final _notes     = TextEditingController();
  String _type = 'pipette';
  DateTime? _date, _dateRappel;
  @override
  Widget build(BuildContext context) => _BaseDialog(title: 'Ajouter un antiparasitaire', fields: [
    _DDrop('Type', _type, ['pipette', 'collier', 'comprimé', 'spray', 'autre'], (v) => setState(() => _type = v!)),
    _DF('Produit *', _produit),
    _DD('Date application *', _date, (d) => setState(() => _date = d)),
    _DD('Prochain rappel', _dateRappel, (d) => setState(() => _dateRappel = d)),
    _DF('Fréquence (ex : 1 mois)', _frequence),
    _DF('Notes', _notes, maxLines: 2),
  ], onSave: () async {
    if (_produit.text.isEmpty || _date == null) return false;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await Supabase.instance.client.from('antiparasitaires').insert({
      'id': id, 'animal_id': widget.animalId,
      'type': _type, 'produit': _produit.text.trim(),
      'date': _date!.toIso8601String(),
      'date_rappel': _dateRappel?.toIso8601String(),
      'frequence': _frequence.text.trim(), 'notes': _notes.text.trim(),
    });
    if (_dateRappel != null) {
      await _scheduleRappelAgenda(
        animalId: widget.animalId,
        dateRappel: _dateRappel!,
        titre: 'Rappel antiparasitaire — ${_produit.text.trim()}',
      );
    }
    RegistreHelper.writeActe(
      animalId: widget.animalId, typeActe: 'antiparasitaire', dateActe: _date!,
      intervenant: '',
      description: '${_produit.text.trim()} ($_type)',
    );
    return true;
  });
}

class _AddAllergieDialog extends StatefulWidget {
  final String animalId;
  const _AddAllergieDialog({required this.animalId});
  @override State<_AddAllergieDialog> createState() => _AddAllergieDialogState();
}
class _AddAllergieDialogState extends State<_AddAllergieDialog> {
  final _description = TextEditingController();
  final _notes       = TextEditingController();
  String _type     = 'alimentaire';
  String _severite = 'modérée';
  @override
  Widget build(BuildContext context) => _BaseDialog(title: 'Ajouter une allergie / pathologie', fields: [
    _DDrop('Type', _type, ['alimentaire', 'médicamenteuse', 'environnementale', 'maladie chronique', 'autre'],
        (v) => setState(() => _type = v!)),
    _DF('Description *', _description),
    _DDrop('Sévérité', _severite, ['légère', 'modérée', 'sévère'], (v) => setState(() => _severite = v!)),
    _DF('Notes / antécédents', _notes, maxLines: 3),
  ], onSave: () async {
    if (_description.text.isEmpty) return false;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await Supabase.instance.client.from('allergies').insert({
      'id': id, 'animal_id': widget.animalId,
      'type': _type, 'description': _description.text.trim(),
      'severite': _severite, 'notes': _notes.text.trim(),
    });
    return true;
  });
}

class _AddPoidsDialog extends StatefulWidget {
  final String animalId;
  final Map<String, dynamic>? existing;
  const _AddPoidsDialog({required this.animalId, this.existing});
  @override State<_AddPoidsDialog> createState() => _AddPoidsDialogState();
}
class _AddPoidsDialogState extends State<_AddPoidsDialog> {
  final _valeur = TextEditingController();
  final _notes  = TextEditingController();
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _date       = e['date'] != null ? DateTime.tryParse(e['date'] as String) : null;
      _valeur.text = e['valeur']?.toString() ?? '';
      _notes.text  = (e['notes'] as String?) ?? '';
    }
  }

  @override
  void dispose() { _valeur.dispose(); _notes.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _BaseDialog(
    title: widget.existing != null ? 'Modifier la pesée' : 'Ajouter une pesée',
    fields: [
      _DD('Date *', _date, (d) => setState(() => _date = d)),
      _DF('Poids (kg) *', _valeur, inputType: TextInputType.numberWithOptions(decimal: true)),
      _DF('Notes', _notes),
    ],
    onSave: () async {
      if (_valeur.text.isEmpty || _date == null) return false;
      final payload = {
        'valeur': double.tryParse(_valeur.text.replaceAll(',', '.')) ?? 0,
        'date':   _date!.toIso8601String(),
        'notes':  _notes.text.trim(),
      };
      if (widget.existing != null) {
        await Supabase.instance.client.from('poids').update(payload).eq('id', widget.existing!['id']);
      } else {
        await Supabase.instance.client.from('poids').insert({
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'animal_id': widget.animalId,
          ...payload,
        });
      }
      return true;
    },
  );
}

// ─── Helpers calcul chaleurs ──────────────────────────────────────────────────

int _intervalChaleursJours(String espece) {
  switch (espece.toLowerCase()) {
    case 'chien':  return 182; // ~6 mois
    case 'chat':   return 21;  // ~21 jours (si non stérilisée)
    case 'lapin':  return 14;  // quasi-permanente
    case 'ovin':   return 17;  // cycle ~17j (saisonnière automne-hiver)
    case 'caprin': return 21;  // cycle ~21j (saisonnière automne-hiver)
    case 'porcin': return 21;  // ~21 jours
    case 'cheval': return 21;  // cycle ~21j dans la saison (printemps-été)
    default:       return 0;
  }
}

int _dureeChaleursJours(String espece) {
  switch (espece.toLowerCase()) {
    case 'chien':  return 21; // 9-21j
    case 'chat':   return 7;  // 5-10j
    case 'cheval': return 6;  // 4-8j
    case 'ovin':   return 2;  // 1-3j
    case 'caprin': return 2;  // 1-3j
    case 'porcin': return 3;  // 2-4j
    case 'lapin':  return 7;
    default:       return 7;
  }
}

DateTime? _nextHeatDate(List<Map<String, dynamic>> data, String espece) {
  final interval = _intervalChaleursJours(espece);
  if (interval == 0 || data.isEmpty) return null;
  final sorted = [...data]..sort((a, b) {
    final da = DateTime.tryParse(a['date'] ?? '') ?? DateTime(2000);
    final db = DateTime.tryParse(b['date'] ?? '') ?? DateTime(2000);
    return db.compareTo(da);
  });
  final last = DateTime.tryParse(sorted.first['date'] ?? '');
  if (last == null) return null;
  return last.add(Duration(days: interval));
}

// ─── Bannière prochaine chaleur ───────────────────────────────────────────────

class _NextHeatBanner extends StatelessWidget {
  final DateTime nextHeat;
  final String espece;
  const _NextHeatBanner({required this.nextHeat, required this.espece});

  String _intervalInfo() {
    switch (espece.toLowerCase()) {
      case 'chien':  return 'Intervalle moyen : 6 mois';
      case 'chat':   return 'Intervalle moyen : 21 jours (si non stérilisée)';
      case 'cheval': return 'Saisonnière printemps-été · cycle ~21j';
      case 'ovin':   return 'Saisonnière automne-hiver · cycle ~17j';
      case 'caprin': return 'Saisonnière automne-hiver · cycle ~21j';
      case 'porcin': return 'Intervalle moyen : 21 jours';
      case 'lapin':  return 'Réceptive quasi-permanente';
      default:       return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = nextHeat.difference(DateTime.now()).inDays;
    final Color bg, fg, border;
    final IconData icon;
    final String label;

    if (diff < 0) {
      bg = const Color(0xFFFFEBEE); fg = Colors.red.shade700; border = Colors.red.shade300;
      icon = Icons.warning_amber_rounded;
      label = 'Chaleurs probables (${-diff}j de retard)';
    } else if (diff == 0) {
      bg = const Color(0xFFFFEBEE); fg = Colors.red.shade700; border = Colors.red.shade300;
      icon = Icons.warning_amber_rounded;
      label = 'Chaleurs attendues aujourd\'hui !';
    } else if (diff == 1) {
      bg = const Color(0xFFFFEBEE); fg = Colors.red.shade700; border = Colors.red.shade300;
      icon = Icons.warning_amber_rounded;
      label = 'Chaleurs attendues demain !';
    } else if (diff <= 7) {
      bg = const Color(0xFFFFF3CD); fg = const Color(0xFF9E7000); border = const Color(0xFFFFCC02);
      icon = Icons.access_time_rounded;
      label = 'Chaleurs prochaines dans $diff jours';
    } else {
      bg = const Color(0xFFEEF5EA); fg = const Color(0xFF4A7A3A); border = const Color(0xFF6E9E57);
      icon = Icons.calendar_today_outlined;
      label = 'Prochaines chaleurs : ${DateFormat('dd/MM/yyyy').format(nextHeat)}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Icon(icon, color: fg, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: fg)),
          if (_intervalInfo().isNotEmpty)
            Text(_intervalInfo(), style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: fg.withValues(alpha: 0.8))),
        ])),
      ]),
    );
  }
}

// ─── Onglet Chaleurs (avec calcul prochaine date) ─────────────────────────────

class _ChaleursTab extends StatefulWidget {
  final String animalId;
  final String espece;
  final int? intervalleCustom;
  const _ChaleursTab({required this.animalId, required this.espece, this.intervalleCustom});
  @override State<_ChaleursTab> createState() => _ChaleursTabState();
}

class _ChaleursTabState extends State<_ChaleursTab> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;
  int? _intervalleCustom; // local copy, editable

  @override
  void initState() {
    super.initState();
    _intervalleCustom = widget.intervalleCustom;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa.from('chaleurs')
          .select()
          .eq('animal_id', widget.animalId)
          .order('date', ascending: false);
      if (mounted) setState(() { _data = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    await _supa.from('chaleurs').delete().eq('id', id);
    if (mounted) setState(() => _data.removeWhere((d) => d['id']?.toString() == id));
  }

  Future<void> _editIntervalle() async {
    final ctrl = TextEditingController(text: _intervalleCustom?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Intervalle personnalisé', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Intervalle par défaut pour ${widget.espece} : ${_intervalChaleursJours(widget.espece)} jours',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Intervalle en jours',
              hintText: 'Laisser vide pour utiliser la valeur par défaut',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixText: 'j',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, -1), // -1 = reset to default
            child: const Text('Réinitialiser', style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              Navigator.pop(context, v ?? 0);
            },
            child: const Text('Enregistrer', style: TextStyle(color: Color(0xFF6E9E57), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result == null) return;
    final newVal = result == -1 ? null : (result == 0 ? null : result);
    await _supa.from('animaux').update({'intervalle_chaleurs_jours': newVal}).eq('id', widget.animalId);
    if (mounted) setState(() => _intervalleCustom = newVal);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)));
    final effectiveInterval = _intervalleCustom ?? _intervalChaleursJours(widget.espece);
    final nextHeat = _data.isNotEmpty && effectiveInterval > 0
        ? (() {
            final sorted = [..._data]..sort((a, b) {
                final da = DateTime.tryParse(a['date'] ?? '') ?? DateTime(2000);
                final db = DateTime.tryParse(b['date'] ?? '') ?? DateTime(2000);
                return db.compareTo(da);
              });
            final last = DateTime.tryParse(sorted.first['date'] ?? '');
            return last?.add(Duration(days: effectiveInterval));
          })()
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: const Color(0xFF6E9E57),
        onPressed: () async {
          await showDialog(context: context, builder: (_) =>
              _AddChaleursDialog(animalId: widget.animalId, espece: widget.espece, intervalleCustom: _intervalleCustom));
          _load();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (nextHeat != null)
            _NextHeatBanner(nextHeat: nextHeat, espece: widget.espece),
          // Intervalle row
          GestureDetector(
            onTap: _editIntervalle,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                Icon(Icons.tune_rounded, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  _intervalleCustom != null
                      ? 'Intervalle personnalisé : $_intervalleCustom jours'
                      : 'Intervalle par défaut (${widget.espece}) : ${_intervalChaleursJours(widget.espece)} jours',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600),
                )),
                Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade400),
              ]),
            ),
          ),
          if (_data.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Text('Aucune chaleur enregistrée',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
            ))
          else
            ..._data.map((d) => _SimpleCard(
              data: d,
              collection: 'chaleurs',
              onDelete: () => _delete(d['id']?.toString() ?? ''),
              onEdit: () async {
                await showDialog(context: context, builder: (_) =>
                    _AddChaleursDialog(animalId: widget.animalId, espece: widget.espece, intervalleCustom: _intervalleCustom, existing: d));
                _load();
              },
            )),
        ],
      ),
    );
  }
}

// ─── Dialog Chaleurs ──────────────────────────────────────────────────────────

class _AddChaleursDialog extends StatefulWidget {
  final String animalId;
  final String espece;
  final int? intervalleCustom;
  final Map<String, dynamic>? existing;
  const _AddChaleursDialog({required this.animalId, required this.espece, this.intervalleCustom, this.existing});
  @override State<_AddChaleursDialog> createState() => _AddChaleursDialogState();
}
class _AddChaleursDialogState extends State<_AddChaleursDialog> {
  final _duree = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date;
  DateTime? _dateFin;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _date    = e['date']     != null ? DateTime.tryParse(e['date'])     : null;
      _dateFin = e['date_fin'] != null ? DateTime.tryParse(e['date_fin']) : null;
      _duree.text = e['duree']?.toString() ?? '';
      _notes.text = e['notes'] ?? '';
    }
  }

  @override
  void dispose() { _duree.dispose(); _notes.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _BaseDialog(
    title: widget.existing != null ? 'Modifier les chaleurs' : 'Ajouter des chaleurs',
    fields: [
      _DD('Date début *', _date, (d) {
        setState(() {
          _date = d;
          // Auto-fill date_fin si non encore saisie
          if (_dateFin == null && widget.existing == null) {
            final duree = _dureeChaleursJours(widget.espece);
            _dateFin = d.add(Duration(days: duree));
            _duree.text = duree.toString();
          }
        });
      }),
      _DD('Date de fin', _dateFin, (d) => setState(() => _dateFin = d)),
      _DF('Durée (jours)', _duree, inputType: TextInputType.number),
      _DF('Notes', _notes, maxLines: 2),
    ],
    onSave: () async {
      if (_date == null) return false;
      final payload = {
        'animal_id': widget.animalId,
        'date': _date!.toIso8601String(),
        'date_fin': _dateFin?.toIso8601String(),
        'duree': _duree.text.trim().isEmpty ? null : _duree.text.trim(),
        'notes': _notes.text.trim(),
      };
      if (widget.existing != null) {
        await Supabase.instance.client.from('chaleurs').update(payload).eq('id', widget.existing!['id']);
      } else {
        await Supabase.instance.client.from('chaleurs').insert({
          'id': DateTime.now().microsecondsSinceEpoch.toString(), ...payload,
        });
        // Sync agenda J-7 et J-1 pour la prochaine chaleur
        final interval = widget.intervalleCustom ?? _intervalChaleursJours(widget.espece);
        if (interval > 0) {
          final nextHeat = _date!.add(Duration(days: interval));
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            String nomAnimal = 'animal';
            try {
              final a = await Supabase.instance.client.from('animaux').select('nom').eq('id', widget.animalId).maybeSingle();
              if (a != null) nomAnimal = (a['nom'] as String?)?.isNotEmpty == true ? a['nom'] as String : 'animal';
            } catch (_) {}
            for (final offset in [7, 1]) {
              final rappel = nextHeat.subtract(Duration(days: offset));
              if (rappel.isAfter(DateTime.now())) {
                await _scheduleRappelAgenda(
                  animalId: widget.animalId,
                  dateRappel: rappel,
                  titre: 'Chaleurs prévues J-$offset — $nomAnimal',
                );
              }
            }
          }
        }
      }
      return true;
    },
  );
}

// ─── Helper rappels agenda ────────────────────────────────────────────────────

Future<void> _scheduleRappelAgenda({
  required String animalId,
  required DateTime dateRappel,
  required String titre,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await Supabase.instance.client.from('agenda_events').insert({
      'uid':        uid,
      'titre':      titre,
      'type':       'medication',
      'date_debut': dateRappel.toIso8601String(),
      'animal_id':  int.tryParse(animalId),
    });
  } catch (_) {}
}

// ─── Durée de gestation par espèce ───────────────────────────────────────────

int _gestationJours(String espece) {
  switch (espece) {
    case 'chien':  return 63;
    case 'chat':   return 65;
    case 'cheval': return 340;
    case 'ovin':   return 150;
    case 'caprin': return 150;
    case 'porcin': return 114;
    case 'lapin':  return 31;
    default:       return 0;
  }
}

String _confirmationInfo(String espece) {
  switch (espece) {
    case 'chien':
    case 'chat':   return 'Confirmation recommandée par écho vers J+21 à J+28';
    case 'cheval': return 'Premier contrôle écho vers J+14-16, puis confirmation vers J+42';
    case 'lapin':  return 'Confirmation par palpation possible vers J+10-14';
    case 'ovin':
    case 'caprin': return 'Confirmation par écho ou palpation vers J+40-70';
    case 'porcin': return 'Retour en chaleur vers J+21 si gestation non confirmée';
    default:       return 'À confirmer par un professionnel de santé';
  }
}

// ─── Dialog Saillie ───────────────────────────────────────────────────────────

class _AddSaillieDialog extends StatefulWidget {
  final String animalId;
  final String espece;
  final String sexeAnimal;
  final Map<String, dynamic>? existing;
  const _AddSaillieDialog({required this.animalId, required this.espece, required this.sexeAnimal, this.existing});
  @override State<_AddSaillieDialog> createState() => _AddSaillieDialogState();
}

class _AddSaillieDialogState extends State<_AddSaillieDialog> {
  final _nomPartenaire   = TextEditingController();
  final _identPartenaire = TextEditingController();
  final _notes           = TextEditingController();
  String _methode = 'naturelle';
  DateTime? _date;
  String? _selectedPartenaireId;
  List<Map<String, String>> _partenaires = [];
  bool _loadingPartenaires = true;

  String get _sexePartenaire => widget.sexeAnimal == 'male' ? 'femelle' : 'male';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _date = e['date'] != null ? DateTime.tryParse(e['date']) : null;
      _nomPartenaire.text   = e['nom_partenaire'] ?? '';
      _identPartenaire.text = e['ident_partenaire'] ?? '';
      _methode = e['methode'] ?? 'naturelle';
      _notes.text = e['notes'] ?? '';
      _selectedPartenaireId = e['partenaire_animal_id'] as String?;
    }
    _loadPartenaires();
  }

  Future<void> _loadPartenaires() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { if (mounted) setState(() => _loadingPartenaires = false); return; }
    final rows = await Supabase.instance.client
        .from('animaux')
        .select('id, nom, identification, espece, sexe')
        .eq('uid_eleveur', uid)
        .eq('espece', widget.espece)
        .eq('sexe', _sexePartenaire);
    if (!mounted) return;
    setState(() {
      _partenaires = (rows as List).map((d) => <String, String>{
        'id': (d['id'] ?? '') as String,
        'nom': (d['nom'] ?? '') as String,
        'identification': (d['identification'] ?? '') as String,
      }).toList();
      _loadingPartenaires = false;
    });
  }

  @override
  void dispose() {
    _nomPartenaire.dispose(); _identPartenaire.dispose(); _notes.dispose();
    super.dispose();
  }

  Widget _dateRow(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () async {
          final p = await showDatePicker(context: context,
            initialDate: value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
              child: child!));
          if (p != null) onPick(p);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57))),
          child: Text(value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Sélectionner',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: value != null ? const Color(0xFF1F2A2E) : Colors.grey)),
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(controller: ctrl, maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.existing != null ? 'Modifier la saillie' : 'Ajouter une saillie',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _dateRow('Date *', _date, (d) => setState(() => _date = d)),
                if (_loadingPartenaires)
                  const Center(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6E9E57))),
                  )),
                if (!_loadingPartenaires && _partenaires.isNotEmpty) ...[
                  Text(
                    widget.sexeAnimal == 'male' ? 'Femelles de votre élevage' : 'Mâles de votre élevage',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: _partenaires.map((m) => ActionChip(
                      label: Text(m['nom']!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                      backgroundColor: _selectedPartenaireId == m['id']
                          ? const Color(0xFF6E9E57)
                          : const Color(0xFFEEF5EA),
                      labelStyle: TextStyle(
                        fontFamily: 'Galey', fontSize: 12,
                        color: _selectedPartenaireId == m['id'] ? Colors.white : const Color(0xFF1F2A2E),
                      ),
                      side: const BorderSide(color: Color(0xFF6E9E57), width: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onPressed: () => setState(() {
                        _nomPartenaire.text   = m['nom']!;
                        _identPartenaire.text = m['identification']!;
                        _selectedPartenaireId = m['id']!;
                      }),
                    )).toList(),
                  ),
                  const SizedBox(height: 10),
                ],
                _textField('Nom du partenaire', _nomPartenaire),
                _textField('N° identification partenaire', _identPartenaire),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(
                    value: _methode,
                    decoration: InputDecoration(labelText: 'Méthode',
                      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                    items: const [
                      DropdownMenuItem(value: 'naturelle', child: Text('Naturelle')),
                      DropdownMenuItem(value: 'ia', child: Text('IA (insémination artificielle)')),
                      DropdownMenuItem(value: 'iaf', child: Text('IAF (semence fraîche)')),
                    ],
                    onChanged: (v) => setState(() => _methode = v!),
                  ),
                ),
                _textField('Notes', _notes, maxLines: 2),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'))),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                if (_date == null) return;
                final supa = Supabase.instance.client;
                final payload = {
                  'animal_id': widget.animalId,
                  'date': _date!.toIso8601String(),
                  'nom_partenaire': _nomPartenaire.text.trim(),
                  'ident_partenaire': _identPartenaire.text.trim(),
                  'methode': _methode,
                  'notes': _notes.text.trim(),
                  'partenaire_animal_id': _selectedPartenaireId,
                };
                if (widget.existing != null) {
                  await supa.from('saillies').update(payload).eq('id', widget.existing!['id']);
                } else {
                  final id = DateTime.now().microsecondsSinceEpoch.toString();
                  await supa.from('saillies').insert({'id': id, ...payload});
                  // Mise à jour bilatérale si le partenaire est dans mon élevage
                  if (_selectedPartenaireId != null) {
                    final animalData = await supa.from('animaux')
                        .select('nom, identification').eq('id', widget.animalId).maybeSingle();
                    if (animalData != null) {
                      await supa.from('saillies').insert({
                        'id': '${id}_mirror',
                        'animal_id': _selectedPartenaireId,
                        'date': _date!.toIso8601String(),
                        'nom_partenaire': (animalData['nom'] ?? '') as String,
                        'ident_partenaire': (animalData['identification'] ?? '') as String,
                        'methode': _methode,
                        'notes': _notes.text.trim(),
                        'partenaire_animal_id': widget.animalId,
                      });
                    }
                  }
                  // A07 — Gestation automatique pour la femelle
                  if (widget.sexeAnimal == 'femelle') {
                    try {
                      final jours = _gestationJours(widget.espece);
                      await supa.from('gestations').insert({
                        'id': '${id}_gest',
                        'animal_id': widget.animalId,
                        'date': _date!.toIso8601String(),
                        if (jours > 0) 'date_prevue': _date!.add(Duration(days: jours)).toIso8601String(),
                        'gestation_confirmee': false,
                      });
                    } catch (_) {}
                  }
                }
                if (context.mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57), foregroundColor: Colors.white),
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey'))),
          ]),
        ]),
      ),
    );
  }
}

// ─── Dialog Gestation ─────────────────────────────────────────────────────────

class _AddGestationDialog extends StatefulWidget {
  final String animalId;
  final String espece;
  final Map<String, dynamic>? existing;
  const _AddGestationDialog({required this.animalId, required this.espece, this.existing});
  @override State<_AddGestationDialog> createState() => _AddGestationDialogState();
}

class _AddGestationDialogState extends State<_AddGestationDialog> {
  final _nbAttendu = TextEditingController();
  final _nbNes     = TextEditingController();
  final _notes     = TextEditingController();
  DateTime? _dateConception;
  DateTime? _datePrevue;
  DateTime? _dateNaissance;
  bool _dateOverride = false;
  bool _gestationConfirmee = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _dateConception = e['date']           != null ? DateTime.tryParse(e['date'])           : null;
      _datePrevue     = e['date_prevue']    != null ? DateTime.tryParse(e['date_prevue'])    : null;
      _dateNaissance  = e['date_naissance'] != null ? DateTime.tryParse(e['date_naissance']) : null;
      _nbAttendu.text = e['nb_attendu']?.toString() ?? '';
      _nbNes.text     = e['nb_nes']?.toString() ?? '';
      _notes.text     = e['notes'] ?? '';
      _gestationConfirmee = (e['gestation_confirmee'] as bool?) ?? false;
      if (_datePrevue != null) _dateOverride = true;
    }
  }

  @override
  void dispose() {
    _nbAttendu.dispose(); _nbNes.dispose(); _notes.dispose();
    super.dispose();
  }

  void _onConceptionPicked(DateTime d) {
    setState(() {
      _dateConception = d;
      final jours = _gestationJours(widget.espece);
      if (jours > 0 && !_dateOverride) {
        _datePrevue = d.add(Duration(days: jours));
      }
    });
  }

  Widget _dateRow(String label, DateTime? value, ValueChanged<DateTime> onPick,
      {bool calculated = false, String? helper}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () async {
          final p = await showDatePicker(context: context,
            initialDate: value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
              child: child!));
          if (p != null) onPick(p);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: calculated ? const Color(0xFF6E9E57).withOpacity(0.4) : const Color(0xFFE4E7E2))),
            fillColor: calculated ? const Color(0xFFEEF5EA) : null,
            filled: calculated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
            suffixIcon: Icon(calculated ? Icons.calculate_outlined : Icons.calendar_today_outlined,
                size: 16, color: const Color(0xFF6E9E57)),
            helperText: helper,
            helperStyle: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6E9E57))),
          child: Text(value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Sélectionner',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: value != null ? const Color(0xFF1F2A2E) : Colors.grey)),
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl, {TextInputType? inputType, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(controller: ctrl, maxLines: maxLines, keyboardType: inputType,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jours = _gestationJours(widget.espece);
    final hasCalcul = jours > 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.existing != null ? 'Modifier la gestation' : 'Ajouter une gestation',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: Column(children: [
                _dateRow('Date de conception *', _dateConception, _onConceptionPicked),
                _dateRow(
                  hasCalcul ? 'Mise-bas estimée' : 'Mise-bas prévue',
                  _datePrevue,
                  (d) => setState(() { _datePrevue = d; _dateOverride = true; }),
                  calculated: hasCalcul && !_dateOverride && _datePrevue != null,
                  helper: hasCalcul
                      ? (_datePrevue == null
                          ? 'calculée auto. dès la date de conception saisie'
                          : (_dateOverride ? 'modifiée manuellement' : 'calculée — $jours j de gestation'))
                      : null,
                ),
                _textField('Nb attendus', _nbAttendu, inputType: TextInputType.number),
                _dateRow('Mise-bas réelle', _dateNaissance,
                    (d) => setState(() => _dateNaissance = d)),
                _textField('Nb nés', _nbNes, inputType: TextInputType.number),
                _textField('Notes', _notes, maxLines: 2),
                const Divider(height: 20),
                Row(children: [
                  Icon(Icons.check_circle_outline, size: 18,
                      color: _gestationConfirmee ? const Color(0xFF6E9E57) : Colors.grey.shade400),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Gestation confirmée',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
                  Switch.adaptive(
                    value: _gestationConfirmee,
                    activeColor: const Color(0xFF6E9E57),
                    onChanged: (v) => setState(() => _gestationConfirmee = v),
                  ),
                ]),
                if (!_gestationConfirmee)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFCC02)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 14, color: Color(0xFFE6A817)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        _confirmationInfo(widget.espece),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFB37A1A)),
                      )),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'))),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                if (_dateConception == null) return;
                try {
                  final basePayload = {
                    'animal_id': widget.animalId,
                    'date': _dateConception!.toIso8601String(),
                    'date_prevue': _datePrevue?.toIso8601String(),
                    'date_naissance': _dateNaissance?.toIso8601String(),
                    'nb_attendu': int.tryParse(_nbAttendu.text),
                    'nb_nes': int.tryParse(_nbNes.text),
                    'notes': _notes.text.trim(),
                  };
                  final String savedId;
                  if (widget.existing != null) {
                    savedId = widget.existing!['id'].toString();
                    await Supabase.instance.client.from('gestations').update(basePayload).eq('id', savedId);
                  } else {
                    savedId = DateTime.now().microsecondsSinceEpoch.toString();
                    await Supabase.instance.client.from('gestations').insert({'id': savedId, ...basePayload});
                  }
                  // gestation_confirmee — colonne optionnelle (à créer via ALTER TABLE si besoin)
                  try {
                    await Supabase.instance.client.from('gestations')
                        .update({'gestation_confirmee': _gestationConfirmee}).eq('id', savedId);
                  } catch (_) {}
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
                        backgroundColor: Colors.redAccent));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57), foregroundColor: Colors.white),
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey'))),
          ]),
        ]),
      ),
    );
  }
}

// ─── Types data pour les dialogs ─────────────────────────────────────────────

class _DF { final String label; final TextEditingController ctrl; final int maxLines; final TextInputType? inputType;
  const _DF(this.label, this.ctrl, {this.maxLines = 1, this.inputType}); }
class _DD { final String label; final DateTime? value; final ValueChanged<DateTime> onChanged;
  const _DD(this.label, this.value, this.onChanged); }
class _DDrop { final String label; final String value; final List<String> options; final ValueChanged<String?> onChanged;
  const _DDrop(this.label, this.value, this.options, this.onChanged); }

// ─── Dialog de base générique ─────────────────────────────────────────────────

class _BaseDialog extends StatelessWidget {
  final String title;
  final List<dynamic> fields;
  final Future<bool> Function() onSave;
  const _BaseDialog({required this.title, required this.fields, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
              fontSize: 16, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.of(context).size.height * 0.55 -
                      MediaQuery.of(context).viewInsets.bottom)
                  .clamp(150.0, double.infinity),
            ),
            child: SingleChildScrollView(
              child: Column(children: fields.map((f) {
                if (f is _DF) return Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(controller: f.ctrl, maxLines: f.maxLines, keyboardType: f.inputType,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                    decoration: InputDecoration(labelText: f.label,
                      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)));

                if (f is _DD) return Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(onTap: () async {
                      final p = await showDatePicker(context: context,
                        initialDate: f.value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060),
                        builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))), child: child!));
                      if (p != null) f.onChanged(p);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: f.label,
                        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
                        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57))),
                      child: Text(f.value != null ? DateFormat('dd/MM/yyyy').format(f.value!) : 'Sélectionner',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: f.value != null ? const Color(0xFF1F2A2E) : Colors.grey)))));

                if (f is _DDrop) return Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(value: f.value,
                    decoration: InputDecoration(labelText: f.label,
                      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                    items: f.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                    onChanged: f.onChanged));

                return const SizedBox.shrink();
              }).toList()),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'))),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                try {
                  final ok = await onSave();
                  if (ok && context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
                        backgroundColor: Colors.redAccent));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57), foregroundColor: Colors.white),
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey'))),
          ]),
        ]),
      ),
    );
  }
}

class _SaveFirstPrompt extends StatelessWidget {
  final String message;
  const _SaveFirstPrompt({required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.save_outlined, size: 52, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500, fontSize: 15)),
      ])));
}

// ─── Onglet Alimentation ─────────────────────────────────────────────────────

class _AlimentationTab extends StatefulWidget {
  final _AnimalFichePageState s;
  const _AlimentationTab(this.s);
  @override
  State<_AlimentationTab> createState() => _AlimentationTabState();
}

class _AlimentationTabState extends State<_AlimentationTab> {
  static final _supa = Supabase.instance.client;
  bool _loading = true;
  bool _saving  = false;
  Map<String,dynamic>? _existing;

  String  _type          = 'croquettes';
  String  _activite      = 'modere';
  String  _catEnergie    = 'normale'; // 'basse'|'normale'|'elevee'|'geant'
  String? _phaseManuelle; // null = auto-détectée

  final _densiteCtrl  = TextEditingController();
  final _objectifCtrl = TextEditingController();

  // Marque sélectionnée (depuis marques_aliments)
  String?       _marqueId;
  String        _marqueNom   = '';
  String        _gammeNom    = '';
  List<dynamic> _dosesMarque = [];

  double _pctMuscles = 70;
  double _pctAbats   = 10;
  double _pctOs      = 10;
  double _pctLegumes = 10;

  // Ration mixte chien/chat (croquettes + pâtée ou croquettes + BARF)
  double _pctCroquMix    = 70;  // % DER en croquettes
  String _typeMixte2     = 'patee'; // 'patee' ou 'barf'
  final  _densitePateeCtrl = TextEditingController(); // kcal/100g pâtée

  // Planning des repas
  int _nbRepas = 2;
  bool _modeCalculateur    = true;       // false = summary, true = calculator
  bool _mixteSepareParRepas = false;     // one food type per meal in mixte
  final _doseManCtrl   = TextEditingController(); // manual dose override g/j (component 1)
  final _doseManCtrl2  = TextEditingController(); // manual dose override g/j (component 2 mixte)
  final _densiteGranCtrl = TextEditingController(); // density for non-dog/cat granulés

  static const _repasLabels = [
    ['Repas unique'],
    ['Matin 🌅', 'Soir 🌇'],
    ['Matin 🌅', 'Midi ☀️', 'Soir 🌇'],
    ['Matin 🌅', 'Milieu de journée ☀️', 'Après-midi 🌤️', 'Soir 🌇'],
  ];

  // Ration mixte (espèces herbivores / non chien/chat)
  double _pctFoinMix     = 67;
  double _pctGranulesMix = 28;
  double _pctCompMix     =  5;

  // État reproducteur (femelles)
  String?              _etatRepro;        // null = auto-détecté
  Map<String,dynamic>? _gestationActive;  // gestation en cours (sans date_mise_bas)
  bool                 _lactationRecente = false; // mise-bas < 8 semaines

  static const _actFactors = <String,double>{
    'repos': 0.8, 'leger': 1.4, 'modere': 1.6, 'actif': 1.8, 'tres_actif': 2.0,
  };
  static const _actLabels = <String,String>{
    'repos':'Repos','leger':'Léger','modere':'Modéré','actif':'Actif','tres_actif':'Très actif',
  };
  static const _catEnergieFactors = <String,double>{
    'basse': 0.85, 'normale': 1.0, 'elevee': 1.2, 'geant': 0.90,
  };
  static const _catEnergieLabels = <String,String>{
    'basse':'Faible','normale':'Normale','elevee':'Élevée','geant':'Géante',
  };
  static const _catEnergieExemples = <String,String>{
    'basse':   'Husky, Basset Hound, Bouledogue',
    'normale': 'Labrador, Berger Allemand, Beagle',
    'elevee':  'Border Collie, Jack Russell, Setter',
    'geant':   'Saint-Bernard, Dogue, Terre-Neuve',
  };
  static const _catEnergieExemplesChat = <String,String>{
    'basse':   'Ragdoll, British Shorthair, Persan (races calmes et corpulentes)',
    'normale': 'Européen, Siamois, Sacré de Birmanie',
    'elevee':  'Bengal, Abyssin, Somali, Oriental (races très actives)',
    'geant':   'Maine Coon, Norvégien (grande race, croissance contrôlée)',
  };

  // Types de ration adaptés à l'espèce
  List<(String, String, String)> get _rationOptions {
    final e = widget.s._espece;
    if (e == 'cheval')           return [('mixte','🌿','Ration mixte'), ('paturage','🌿','Pâturage'), ('complement','💊','Complément')];
    if (e == 'lapin')            return [('mixte','🥦','Foin + Granulés'), ('granules','🌾','Granulés seuls')];
    if (e == 'oiseau')           return [('graines','🌰','Graines / Mix'), ('granules','🌾','Granulés')];
    if (['ovin','caprin'].contains(e)) return [('mixte','🌿','Ration mixte'), ('foin','🌿','Foin seul')];
    if (e == 'porcin')           return [('granules','🌾','Aliment complet'), ('menagere','🍲','Ménagère')];
    return [('croquettes','🥣','Croquettes'), ('barf','🥩','BARF'), ('mixte','🥣🥩','Mixte'), ('menagere','🍲','Ménagère')];
  }

  // Le type sauvegardé peut être invalide si l'espèce a changé
  String get _typeValide {
    final opts = _rationOptions;
    return opts.any((o) => o.$1 == _type) ? _type : opts.first.$1;
  }

  bool get _isDogOrCat => ['chien', 'chat'].contains(widget.s._espece);

  Map<String,String> get _exemplesEnergie =>
      widget.s._espece == 'chat' ? _catEnergieExemplesChat : _catEnergieExemples;

  // ── Formules espèces non-chien/chat ──────────────────────────────────────

  // % poids vif en MS totale/jour selon espèce + activité
  double get _rationPctPoidsvif {
    const chevalPct = <String,double>{'repos':1.5,'leger':1.8,'modere':2.0,'actif':2.3,'tres_actif':2.8};
    const ovinPct   = <String,double>{'repos':1.5,'leger':1.8,'modere':2.0,'actif':2.2,'tres_actif':2.5};
    const porcinPct = <String,double>{'repos':2.0,'leger':2.5,'modere':3.0,'actif':3.0,'tres_actif':3.0};
    final e = widget.s._espece;
    if (e == 'cheval') return chevalPct[_activite] ?? 2.0;
    if (e == 'ovin' || e == 'caprin') return ovinPct[_activite] ?? 2.0;
    if (e == 'porcin') return porcinPct[_activite] ?? 2.5;
    return 2.0;
  }

  double get _rationTotaleKg =>
      _poidsRef > 0 ? _poidsRef * _rationPctPoidsvif / 100 * _reproFactor : 0;

  // Détail ration mixte calculée par espèce
  Map<String,dynamic>? get _rationEspeceDetail {
    if (_poidsRef <= 0) return null;
    final e = widget.s._espece;
    if (e == 'cheval' || e == 'ovin' || e == 'caprin') {
      final total = _rationTotaleKg;
      final foin  = total * _pctFoinMix    / 100;
      final gran  = total * _pctGranulesMix / 100;
      final comp  = total * _pctCompMix    / 100;
      final maxRepasGran = e == 'cheval' ? 2.5 : 1.5;
      final nbRepasMini  = gran > maxRepasGran ? (gran / maxRepasGran).ceil() : 2;
      return {
        'total_kg': total, 'foin_kg': foin, 'granules_kg': gran, 'complement_kg': comp,
        'max_repas_gran': maxRepasGran, 'nb_repas': nbRepasMini,
        'alerte_gran': gran > maxRepasGran * 2.5, // trop de granulés
      };
    }
    if (e == 'lapin') {
      return {
        'granules_g': _poidsRef * 22.5,      // 22.5g/kg/j
        'legumes_g':  _poidsRef * 50.0,       // 50g/kg/j
        'eau_ml':     _poidsRef * 100.0,      // 100ml/kg/j
        'foin': 'illimité',
      };
    }
    if (e == 'oiseau') {
      return {'graines_g': 35.0, 'legumes_g': 30.0}; // perroquet moyen
    }
    if (e == 'porcin') {
      return {'total_kg': _rationTotaleKg};
    }
    return null;
  }

  // Compléments recommandés par espèce
  static const _supplements = <String, List<(String,String)>>{
    'cheval': [
      ('🧂','Pierre à sel / bloc minéral (accès libre permanent)'),
      ('🔵','Complément calcium-phosphore (calcul selon fourrage)'),
      ('🌿','Biotine 20 mg/j (santé des sabots)'),
      ('💊','Vitamine E + Sélénium (zones carencées, sport)'),
      ('🦠','Probiotiques (changement alimentation, stress)'),
      ('🐟','Oméga-3 : huile de lin 50 ml/j'),
    ],
    'lapin': [
      ('🌾','Foin de qualité en accès libre (priorité absolue)'),
      ('🧂','Pierre à sel (accès libre)'),
      ('🥬','Légumes frais : chicorée, cresson, romaine (50g/kg/j)'),
      ('💊','Vitamine C si santé fragilisée'),
    ],
    'ovin': [
      ('🧂','Bloc minéral mouton (Cu < 10 ppm — toxique si trop élevé)'),
      ('💊','Sélénium injectable annuel (zones carencées)'),
      ('🌿','Vitamine B12 (brebis en gestation)'),
      ('🔵','Calcite (prévention hypocalcémie post-agnelage)'),
    ],
    'caprin': [
      ('🧂','Bloc minéral chèvre (Cu toléré, différent du mouton)'),
      ('💊','Sélénium + Vitamine E'),
      ('🌿','Vitamine D (stabulation prolongée)'),
      ('🦠','Probiotiques (chevrettes, diarrhées)'),
    ],
    'porcin': [
      ('💊','Acides aminés essentiels (lysine, méthionine)'),
      ('🧂','Sel 0.5–1% de la ration'),
      ('🔵','Vitamines A, D, E, K'),
      ('⚙️','Zinc + Fer (porcelets en croissance)'),
    ],
    'oiseau': [
      ('🧂','Sépie (calcium, bec)'),
      ('💊','Vitamines A, D3, E (si granulés insuffisants)'),
      ('🥬','Légumes frais : carottes, épinards, concombre'),
      ('🐟','Quelques insectes séchés (perroquets — protéines)'),
    ],
  };

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _densiteCtrl.dispose(); _objectifCtrl.dispose(); _densitePateeCtrl.dispose(); _doseManCtrl.dispose(); _doseManCtrl2.dispose(); _densiteGranCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (widget.s.widget.animalId == null) { setState(() => _loading = false); return; }
    try {
      final res = await _supa
          .from('alimentations').select()
          .eq('animal_id', widget.s.widget.animalId!)
          .maybeSingle();
      if (mounted && res != null) {
        setState(() {
          _existing          = res;
          _type              = res['type_ration']      ?? 'croquettes';
          _activite          = res['niveau_activite']  ?? 'modere';
          _catEnergie        = res['categorie_energie'] ?? 'normale';
          final pv           = res['phase_vie'] as String?;
          _phaseManuelle     = (pv == null || pv == 'auto') ? null : pv;
          _densiteCtrl.text  = res['densite_calorique']?.toString() ?? '';
          _objectifCtrl.text = res['poids_objectif']?.toString()    ?? '';
          _marqueId          = res['marque_id'] as String?;
          _marqueNom         = res['marque'] ?? '';
          _gammeNom          = res['gamme']  ?? '';
          _pctMuscles = (res['pourcentage_muscles'] as num?)?.toDouble() ?? 70;
          _pctAbats   = (res['pourcentage_abats']   as num?)?.toDouble() ?? 10;
          _pctOs      = (res['pourcentage_os']       as num?)?.toDouble() ?? 10;
          _pctLegumes = (res['pourcentage_legumes']  as num?)?.toDouble() ?? 10;
          // Restore mix percentages from notes field (encoded as "foin|gran|comp")
          final notes = res['notes'] as String?;
          if (notes != null && notes.contains('|')) {
            final parts = notes.split('|');
            if (parts.length >= 3) {
              _pctFoinMix     = double.tryParse(parts[0]) ?? 67;
              _pctGranulesMix = double.tryParse(parts[1]) ?? 28;
              _pctCompMix     = double.tryParse(parts[2]) ?? 5;
              if (parts.length >= 4) _nbRepas = int.tryParse(parts[3]) ?? 2;
              if (parts.length >= 5) _mixteSepareParRepas = parts[4] == '1';
              if (parts.length >= 6) _doseManCtrl.text   = parts[5];
              if (parts.length >= 7) _doseManCtrl2.text  = parts[6];
              if (parts.length >= 8 && parts[7].isNotEmpty) _typeMixte2 = parts[7];
              if (parts.length >= 9) _densitePateeCtrl.text   = parts[8];
              if (parts.length >= 10) _densiteGranCtrl.text   = parts[9];
            }
          }
          _modeCalculateur = false;
        });
        // Re-fetch brand doses if a brand is saved
        if (_marqueId != null) {
          final brand = await _supa.from('marques_aliments').select('doses').eq('id', _marqueId!).maybeSingle();
          if (mounted && brand != null) setState(() => _dosesMarque = brand['doses'] as List<dynamic>? ?? []);
        }
      }
    } catch (_) {
      // Table may not exist yet — show empty state
    }
    // Auto-détection gestation/lactation pour les femelles
    if (widget.s._sexe == 'femelle') {
      try {
        final gesta = await _supa
            .from('gestations')
            .select('id, date_saillie, date_mise_bas')
            .eq('animal_id', widget.s.widget.animalId!)
            .order('date_saillie', ascending: false)
            .limit(1)
            .maybeSingle();
        if (mounted && gesta != null) {
          final dateMiseBas = gesta['date_mise_bas'] as String?;
          if (dateMiseBas == null) {
            setState(() => _gestationActive = gesta);
          } else {
            final birth = DateTime.tryParse(dateMiseBas);
            if (birth != null && DateTime.now().difference(birth).inDays < 56) {
              setState(() => _lactationRecente = true);
            }
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Calculs ───────────────────────────────────────────────────────────────

  double? get _poidsActuel {
    final v = widget.s._poidsCtrl.text.trim().replaceAll(',', '.');
    return v.isEmpty ? null : double.tryParse(v);
  }
  double? get _poidsObjectif {
    final v = _objectifCtrl.text.trim().replaceAll(',', '.');
    return v.isEmpty ? null : double.tryParse(v);
  }
  double get _poidsRef => _poidsObjectif ?? _poidsActuel ?? 0;

  double get _ageMois {
    final dn = widget.s._dateNaissance;
    if (dn == null) return -1;
    return DateTime.now().difference(dn).inDays / 30.44;
  }

  // Auto-détection de la phase de vie (junior/adulte/senior) selon âge + poids
  String get _phaseAutoDetect {
    final am = _ageMois;
    if (am < 0) return 'adulte';
    final p      = _poidsRef;
    final espece = widget.s._espece;
    final juniorMois = p > 45 ? 24.0 : p > 25 ? 18.0 : p > 10 ? 15.0 : 12.0;
    if (am < juniorMois) return 'junior';
    if (espece == 'chat'  && am >= 96)  return 'senior'; // 8 ans
    if (espece == 'chien' && am >= 84)  return 'senior'; // 7 ans
    if (espece == 'lapin' && am >= 48)  return 'senior'; // 4 ans
    if (espece == 'cheval' && am >= 216) return 'senior'; // 18 ans
    return 'adulte';
  }

  String get _phase => _phaseManuelle ?? _phaseAutoDetect;

  // ── État reproducteur (femelles) ─────────────────────────────────────────

  String get _etatReproAuto {
    if (widget.s._sexe != 'femelle') return 'normal';
    if (_lactationRecente) return 'lactation';
    final g = _gestationActive;
    if (g == null) return 'normal';
    final saillie = DateTime.tryParse(g['date_saillie'] as String? ?? '');
    if (saillie == null) return 'normal';
    final joursG = DateTime.now().difference(saillie).inDays;
    const durees = <String,int>{'chien':63,'chat':65,'cheval':340,'ovin':150,'caprin':150,'porcin':114,'lapin':31};
    final total = durees[widget.s._espece] ?? 63;
    return joursG >= (total - 21) ? 'gestation_fin' : 'gestation_debut';
  }

  String get _etatReproEffectif => _etatRepro ?? _etatReproAuto;

  double get _reproFactor {
    switch (_etatReproEffectif) {
      case 'gestation_debut': return 1.1;
      case 'gestation_fin':   return 1.3;
      case 'lactation':       return 1.5;
      default:                return 1.0;
    }
  }

  // ── Calculs DER ──────────────────────────────────────────────────────────

  double? get _rer => _poidsRef > 0 ? 70 * math.pow(_poidsRef, 0.75).toDouble() : null;

  double? get _der {
    final rer = _rer;
    if (rer == null) return null;
    double phaseFactor;
    if (_phase == 'junior') {
      if (_ageMois >= 0 && _ageMois < 4) phaseFactor = 3.0;
      else if (_poidsRef > 25)           phaseFactor = 1.8;
      else                                phaseFactor = 2.0;
    } else if (_phase == 'senior') {
      phaseFactor = 1.2;
    } else {
      phaseFactor = _actFactors[_activite] ?? 1.6;
    }
    final sterilFactor = widget.s._sterilise
        ? (widget.s._espece == 'chat' ? 0.7 : 0.8)
        : 1.0;
    return rer * phaseFactor * (_catEnergieFactors[_catEnergie] ?? 1.0) * sterilFactor * _reproFactor;
  }

  double? get _rationCroquettes {
    final d = _der;
    if (d == null) return null;
    final den = double.tryParse(_densiteCtrl.text.replaceAll(',', '.'));
    if (den == null || den <= 0) return null;
    return (d / den) * 100;
  }

  double? get _rationBarf {
    if (_poidsRef <= 0) return null;
    final actFactor = (_catEnergieFactors[_catEnergie] ?? 1.0) * ((_actFactors[_activite] ?? 1.6) / 1.6);
    final sterilFactor = widget.s._sterilise ? (widget.s._espece == 'chat' ? 0.7 : 0.8) : 1.0;
    return _poidsRef * 1000 * 0.02 * actFactor * sterilFactor * _reproFactor;
  }

  // Ration mixte chien/chat
  double? get _rationMixteCroq {
    final d = _der;
    if (d == null) return null;
    final den = double.tryParse(_densiteCtrl.text.replaceAll(',', '.'));
    if (den == null || den <= 0) return null;
    return (d * _pctCroquMix / 100.0 / den) * 100;
  }

  double? get _rationMixteSecond {
    final d = _der;
    if (d == null) return null;
    final pctSecond = 1.0 - _pctCroquMix / 100.0;
    if (_typeMixte2 == 'barf') {
      final rb = _rationBarf;
      return rb != null ? rb * pctSecond : null;
    }
    if (_typeMixte2 == 'menagere') {
      return (d * pctSecond / 120.0) * 100;
    }
    final den = double.tryParse(_densitePateeCtrl.text.replaceAll(',', '.'));
    if (den == null || den <= 0) return null;
    return (d * pctSecond / den) * 100;
  }

  // Ration ménagère chien/chat — densité ~120 kcal/100g
  double? get _rationMenagere {
    final d = _der;
    return d != null ? (d / 120.0) * 100 : null;
  }

  // Doses effectives — override manuel ou calculé
  double? get _doseEffCroq {
    final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.'));
    return m ?? _rationCroquettes;
  }
  double? get _doseEffBarf {
    final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.'));
    return m ?? _rationBarf;
  }
  double? get _doseEffMenagere {
    final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.'));
    return m ?? _rationMenagere;
  }
  double? get _doseEffMixteCroq {
    final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.'));
    return m ?? _rationMixteCroq;
  }
  double? get _doseEffMixteSecond {
    final m = double.tryParse(_doseManCtrl2.text.replaceAll(',','.'));
    return m ?? _rationMixteSecond;
  }

  // Calories apportées par la ration effective
  double? get _kcalApportes {
    switch (_typeValide) {
      case 'croquettes':
        final dose = _doseEffCroq;
        final den = double.tryParse(_densiteCtrl.text.replaceAll(',','.'));
        return (dose != null && den != null && den > 0) ? dose * den / 100 : null;
      case 'barf':
        final dose = _doseEffBarf;
        return dose != null ? dose * 1.25 : null;
      case 'menagere':
        final dose = _doseEffMenagere;
        return dose != null ? dose * 120.0 / 100 : null;
      case 'mixte':
        double total = 0;
        final croq = _doseEffMixteCroq;
        final den = double.tryParse(_densiteCtrl.text.replaceAll(',','.'));
        if (croq != null && den != null && den > 0) total += croq * den / 100;
        final sec = _doseEffMixteSecond;
        if (sec != null) {
          if (_typeMixte2 == 'barf')         total += sec * 1.25;
          else if (_typeMixte2 == 'menagere') total += sec * 120.0 / 100;
          else {
            final denP = double.tryParse(_densitePateeCtrl.text.replaceAll(',','.'));
            if (denP != null && denP > 0) total += sec * denP / 100;
          }
        }
        return total > 0 ? total : null;
      default: return null;
    }
  }

  // Interpolation linéaire depuis les doses fabricant (clés : poids_kg / grammes)
  double? get _doseBrandInterpolee {
    if (_dosesMarque.isEmpty || _poidsRef <= 0) return null;
    try {
      final sorted = List<dynamic>.from(_dosesMarque)
        ..sort((a, b) => ((a['poids_kg'] as num?)??0).compareTo((b['poids_kg'] as num?)??0));
      for (int i = 0; i < sorted.length - 1; i++) {
        final p1 = (sorted[i]['poids_kg']   as num).toDouble();
        final p2 = (sorted[i+1]['poids_kg'] as num).toDouble();
        final d1 = (sorted[i]['grammes']    as num).toDouble();
        final d2 = (sorted[i+1]['grammes']  as num).toDouble();
        if (_poidsRef >= p1 && _poidsRef <= p2) return d1 + (d2-d1)*(_poidsRef-p1)/(p2-p1);
      }
      if (_poidsRef < (sorted.first['poids_kg'] as num)) return (sorted.first['grammes'] as num).toDouble();
      return (sorted.last['grammes'] as num).toDouble();
    } catch (_) { return null; }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (widget.s.widget.animalId == null) return;
    setState(() => _saving = true);
    try {
      final payload = <String,dynamic>{
        'animal_id':           widget.s.widget.animalId!,
        'uid_eleveur':         FirebaseAuth.instance.currentUser?.uid,
        'type_ration':         _typeValide,
        'niveau_activite':     _activite,
        'categorie_energie':   _catEnergie,
        'phase_vie':           _phaseManuelle ?? 'auto',
        'poids_objectif':      _poidsObjectif,
        'marque_id':           _marqueId,
        'marque':              _marqueNom.isEmpty ? null : _marqueNom,
        'gamme':               _gammeNom.isEmpty  ? null : _gammeNom,
        'densite_calorique':   double.tryParse(_densiteCtrl.text.replaceAll(',', '.')),
        'pourcentage_muscles': _pctMuscles,
        'pourcentage_abats':   _pctAbats,
        'pourcentage_os':      _pctOs,
        'pourcentage_legumes': _pctLegumes,
        'notes': '${_pctFoinMix.round()}|${_pctGranulesMix.round()}|${_pctCompMix.round()}|$_nbRepas'
                 '|${_mixteSepareParRepas?1:0}|${_doseManCtrl.text}|${_doseManCtrl2.text}'
                 '|$_typeMixte2|${_densitePateeCtrl.text}|${_densiteGranCtrl.text}',
        'updated_at':          DateTime.now().toIso8601String(),
      };
      if (_existing != null) {
        await _supa.from('alimentations').update(payload).eq('id', _existing!['id']);
      } else {
        final r = await _supa.from('alimentations').insert(payload).select().single();
        if (mounted) setState(() => _existing = r);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alimentation enregistrée'), behavior: SnackBarBehavior.floating));
      if (mounted) setState(() => _modeCalculateur = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Planning repas ────────────────────────────────────────────────────────

  // Retourne [{label, items: [{emoji, nom, quantite}]}]
  List<Map<String, dynamic>> get _mealPlan {
    final espece = widget.s._espece;
    final labels = _repasLabels[_nbRepas - 1];

    // ── CHIEN / CHAT ──────────────────────────────────────────────
    if (_isDogOrCat) {
      if (_typeValide == 'croquettes') {
        final rc = _doseEffCroq;
        if (rc == null) return [];
        final par = (rc / _nbRepas).roundToDouble();
        return List.generate(_nbRepas, (i) => {
          'label': labels[i],
          'items': [{'emoji': '🥜', 'nom': _marqueNom.isNotEmpty ? '$_marqueNom — $_gammeNom' : 'Croquettes', 'qte': '${par.round()} g'}],
        });
      }
      if (_typeValide == 'barf') {
        final rb = _doseEffBarf;
        if (rb == null) return [];
        final par = (rb / _nbRepas).roundToDouble();
        final pMuscles = (par * _pctMuscles / 100).round();
        final pAbats   = (par * _pctAbats   / 100).round();
        final pOs      = (par * _pctOs       / 100).round();
        final pLeg     = (par * _pctLegumes  / 100).round();
        return List.generate(_nbRepas, (i) => {
          'label': labels[i],
          'items': [
            {'emoji': '🥩', 'nom': 'Viande/muscles', 'qte': '$pMuscles g'},
            {'emoji': '🫀', 'nom': 'Abats', 'qte': '$pAbats g'},
            {'emoji': '🦴', 'nom': 'Os charnus', 'qte': '$pOs g'},
            {'emoji': '🥦', 'nom': 'Légumes & fruits', 'qte': '$pLeg g'},
          ],
        });
      }
      if (_typeValide == 'mixte') {
        final rc = _doseEffMixteCroq;
        final rs = _doseEffMixteSecond;
        if (rc == null && rs == null) return [];
        final secondLabel = _typeMixte2 == 'barf' ? 'BARF' : _typeMixte2 == 'menagere' ? 'Ration ménagère' : 'Pâtée';
        final secondEmoji = _typeMixte2 == 'barf' ? '🥩' : _typeMixte2 == 'menagere' ? '🍲' : '🥫';

        if (_mixteSepareParRepas && _nbRepas >= 2) {
          final nCroq = ((_nbRepas * _pctCroquMix / 100).round()).clamp(1, _nbRepas - 1);
          final nSec  = _nbRepas - nCroq;
          final rcPar = rc != null ? (rc / nCroq).round() : null;
          final rsPar = rs != null ? (rs / nSec).round() : null;
          return List.generate(_nbRepas, (i) => {
            'label': labels[i],
            'items': i < nCroq
              ? (rcPar != null ? [{'emoji':'🥜','nom':_marqueNom.isNotEmpty?_marqueNom:'Croquettes','qte':'$rcPar g'}] : <Map<String,String>>[])
              : (rsPar != null ? [{'emoji':secondEmoji,'nom':secondLabel,'qte':'$rsPar g'}] : <Map<String,String>>[]),
          });
        }

        final rcPar = rc != null ? (rc / _nbRepas).round() : null;
        final rsPar = rs != null ? (rs / _nbRepas).round() : null;
        return List.generate(_nbRepas, (i) => {
          'label': labels[i],
          'items': [
            if (rcPar != null) {'emoji': '🥜', 'nom': _marqueNom.isNotEmpty ? _marqueNom : 'Croquettes', 'qte': '$rcPar g'},
            if (rsPar != null) {'emoji': secondEmoji, 'nom': secondLabel, 'qte': '$rsPar g'},
          ],
        });
      }
      if (_typeValide == 'menagere') {
        final rm = _doseEffMenagere;
        if (rm == null) return [];
        final par = (rm / _nbRepas).round();
        return List.generate(_nbRepas, (i) => {
          'label': labels[i],
          'items': [{'emoji': '🍲', 'nom': 'Ration ménagère', 'qte': '$par g'}],
        });
      }
      return [];
    }

    // ── CHEVAL ─────────────────────────────────────────────────────
    if (espece == 'cheval') {
      final detail = _rationEspeceDetail;
      if (detail == null) return [];
      final foin = detail['foin_kg'] as double;
      final gran = detail['granules_kg'] as double;
      final comp = (detail['complement_kg'] as double) * 1000; // en grammes
      final foinPar = foin / _nbRepas;
      // Granulés le matin uniquement (max 2.5 kg/repas)
      final granRepas = List.generate(_nbRepas, (i) {
        if (i == 0) return math.min(gran, 2.5);
        if (i == 1) return math.max(0, math.min(gran - 2.5, 2.5));
        return 0.0;
      });
      return List.generate(_nbRepas, (i) {
        final items = <Map<String,String>>[
          {'emoji': '🌿', 'nom': 'Foin', 'qte': '${foinPar.toStringAsFixed(1)} kg'},
        ];
        if (granRepas[i] > 0) items.add({'emoji': '🌾', 'nom': _marqueNom.isNotEmpty ? '$_marqueNom' : 'Granulés', 'qte': '${granRepas[i].toStringAsFixed(1)} kg'});
        if (i == 0 && comp > 0) items.add({'emoji': '💊', 'nom': 'Compléments', 'qte': '${comp.round()} g'});
        return {'label': labels[i], 'items': items};
      });
    }

    // ── LAPIN ──────────────────────────────────────────────────────
    if (espece == 'lapin') {
      final detail = _rationEspeceDetail;
      if (detail == null) return [];
      final gran = detail['granules_g'] as double;
      final leg  = detail['legumes_g'] as double;
      final granPar = (gran / _nbRepas).round();
      final legPar  = (leg  / _nbRepas).round();
      return List.generate(_nbRepas, (i) => {
        'label': labels[i],
        'items': [
          {'emoji': '🌿', 'nom': 'Foin', 'qte': 'Accès libre'},
          {'emoji': '🌾', 'nom': 'Granulés', 'qte': '$granPar g'},
          {'emoji': '🥬', 'nom': 'Légumes frais', 'qte': '$legPar g'},
        ],
      });
    }

    // ── OVIN / CAPRIN ──────────────────────────────────────────────
    if (espece == 'ovin' || espece == 'caprin') {
      final detail = _rationEspeceDetail;
      if (detail == null) return [];
      final foin = detail['foin_kg'] as double;
      final gran = detail['granules_kg'] as double;
      final foinPar = foin / _nbRepas;
      final granPar = gran / _nbRepas;
      return List.generate(_nbRepas, (i) => {
        'label': labels[i],
        'items': [
          {'emoji': '🌿', 'nom': 'Foin / Fourrage', 'qte': '${foinPar.toStringAsFixed(1)} kg'},
          if (granPar > 0) {'emoji': '🌾', 'nom': 'Granulés', 'qte': '${granPar.toStringAsFixed(1)} kg'},
        ],
      });
    }

    // ── PORCIN ─────────────────────────────────────────────────────
    if (espece == 'porcin') {
      final detail = _rationEspeceDetail;
      if (detail == null) return [];
      final total = detail['total_kg'] as double;
      final par = total / _nbRepas;
      return List.generate(_nbRepas, (i) => {
        'label': labels[i],
        'items': [{'emoji': '🐷', 'nom': 'Aliment complet', 'qte': '${par.toStringAsFixed(1)} kg'}],
      });
    }

    return [];
  }

  // ── Recipe bottom sheet ───────────────────────────────────────────────────

  void _showRecipeSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(_typeValide == 'barf' ? 'Ration BARF' : 'Recette ménagère',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
              if (_poidsRef > 0) Text(
                '${widget.s._nomCtrl.text.isNotEmpty ? widget.s._nomCtrl.text : "Votre animal"}  ·  ${_poidsRef.toStringAsFixed(1)} kg  ·  ${_der?.round() ?? '—'} kcal/j',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 20),
              ...(_typeValide == 'barf' ? _recetteBarf() : _recetteMenagere()),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _recetteBarf() {
    final rb = _doseEffBarf;
    if (rb == null) return [Text('Renseignez le poids de votre animal.', style: TextStyle(color: Colors.grey.shade500))];
    return [
      _RecetteItem('🥩', 'Viande maigre / muscles (${_pctMuscles.round()}%)', '${(rb * _pctMuscles / 100).round()} g', 'Bœuf, poulet, dinde, lapin — haché ou morceaux', const Color(0xFF0C5C6C)),
      _RecetteItem('🫀', 'Abats (${_pctAbats.round()}%)', '${(rb * _pctAbats / 100).round()} g', 'Foie, rein, cœur — ne pas dépasser 15%', const Color(0xFF8D6E63)),
      _RecetteItem('🦴', 'Os charnus (${_pctOs.round()}%)', '${(rb * _pctOs / 100).round()} g', 'Carcasse poulet, côtes agneau', const Color(0xFFBCAAA4)),
      _RecetteItem('🥦', 'Légumes & fruits (${_pctLegumes.round()}%)', '${(rb * _pctLegumes / 100).round()} g', 'Courgette, carotte, épinard — mixés', const Color(0xFF6E9E57)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
        child: Text('Total : ${rb.round()} g/j  ·  $_nbRepas repas de ${(rb/_nbRepas).round()} g  ·  ≈${(rb*1.25).round()} kcal',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
      ),
      const SizedBox(height: 10),
      Text('💡 Supplémenter avec 5 ml d\'huile de saumon/colza + levure de bière ou complément minéral.',
        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
    ];
  }

  List<Widget> _recetteMenagere() {
    final rm = _doseEffMenagere;
    if (rm == null) return [Text('Renseignez le poids de votre animal.', style: TextStyle(color: Colors.grey.shade500))];
    final protG = (rm * 0.40).round();
    final legG  = (rm * 0.20).round();
    final fecG  = (rm * 0.30).round();
    final mgG   = (rm * 0.05).round();
    final cmpG  = (rm * 0.05).round();
    final kcal  = (rm * 120.0 / 100).round();
    final esp   = widget.s._espece;
    return [
      _RecetteItem('🥩', 'Protéines animales (40%)', '$protG g',
        esp == 'chat' ? 'Poulet ou dinde hachée cuite — riche en taurine' : 'Poulet, bœuf, agneau — haché cuit (sans os)', const Color(0xFF0C5C6C)),
      _RecetteItem('🥬', 'Légumes (20%)', '$legG g',
        'Carottes, haricots verts, courgette — cuits et mixés', const Color(0xFF6E9E57)),
      _RecetteItem('🌾', 'Féculents (30%)', '$fecG g',
        esp == 'chat' ? 'Riz blanc cuit (faible quantité) ou patate douce' : 'Riz blanc ou pâtes cuites', const Color(0xFFB8860B)),
      _RecetteItem('🫒', 'Matières grasses (5%)', '$mgG g',
        'Huile de colza ou de saumon (oméga-3)', const Color(0xFF8D6E63)),
      _RecetteItem('💊', 'Compléments (5%)', '$cmpG g',
        'Complément minéral-vitaminé (Seatal, Anibio, BARF Balance…)', Colors.purple.shade300),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
        child: Text('Total : ${rm.round()} g/j  ·  $_nbRepas repas de ${(rm/_nbRepas).round()} g  ·  ≈$kcal kcal',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
        child: const Text('⚠️ Consultez votre vétérinaire pour valider cette recette selon les besoins spécifiques de votre animal.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF856404))),
      ),
    ];
  }

  // ── Summary / Dashboard View ──────────────────────────────────────────────

  Widget _buildSummaryView() {
    final rer  = _rer;
    final der  = _der;
    final kcal = _kcalApportes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── PROFIL DE L'ANIMAL ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🐾', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text("Profil de l'animal", style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _modeCalculateur = true),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF0C5C6C), minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
              ),
            ]),
            const Divider(height: 14),
            _sumRow('Poids', _poidsActuel != null ? '${_poidsActuel!.toStringAsFixed(1)} kg' : '—'),
            _sumRow('Phase', _phase == 'junior' ? '🍼 Junior' : _phase == 'senior' ? '🌿 Senior' : 'Adulte'),
            if (_phase == 'adulte') _sumRow("Activité", _actLabels[_activite] ?? _activite),
            if (widget.s._sterilise) _sumRow('Stérilisé(e)', '✂️ Oui'),
            if (_etatReproEffectif != 'normal') _sumRow('État', _etatReproEffectif == 'gestation_debut' ? '🤰 Gestation (début)' : _etatReproEffectif == 'gestation_fin' ? '🍼 Gestation (fin)' : '🤱 Lactation'),
          ]),
        ),
        const SizedBox(height: 12),

        // ── BESOINS CALORIQUES ──────────────────────────────────
        if (rer != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0C5C6C).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF0C5C6C).withOpacity(0.12)),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Besoins caloriques', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(der != null ? '${der.round()} kcal/jour' : '${rer.round()} kcal (RER)',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0C5C6C))),
                if (der != null) Text('RER ${rer.round()} × facteurs (phase, activité, état)',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
              ])),
              const Text('⚡', style: TextStyle(fontSize: 28)),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // ── RATION ACTUELLE ──────────────────────────────────────
        _buildRationCard(der, kcal),
        const SizedBox(height: 12),

        // ── PLAN DE REPAS ────────────────────────────────────────
        _buildRepasSection(),
        const SizedBox(height: 20),

        // ── ACTIONS ──────────────────────────────────────────────
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => setState(() => _modeCalculateur = true),
            icon: const Icon(Icons.calculate_outlined, size: 16),
            label: const Text('Recalculer la ration', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0C5C6C),
              side: const BorderSide(color: Color(0xFF0C5C6C)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          )),
          if (_typeValide == 'menagere' || _typeValide == 'barf') ...[
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _showRecipeSheet(context),
              icon: const Icon(Icons.menu_book_outlined, size: 16, color: Colors.white),
              label: const Text('Voir la recette', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5C6C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )),
          ],
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _buildRationCard(double? der, double? kcalApportes) {
    final type  = _typeValide;
    final isDog = _isDogOrCat;

    String typeLabel, typeEmoji;
    switch (type) {
      case 'croquettes': typeLabel = 'Croquettes';      typeEmoji = '🥜'; break;
      case 'barf':       typeLabel = 'BARF';             typeEmoji = '🥩'; break;
      case 'menagere':   typeLabel = 'Ration ménagère';  typeEmoji = '🍲'; break;
      case 'mixte':      typeLabel = 'Mixte';            typeEmoji = '🥣'; break;
      default:           typeLabel = type;               typeEmoji = '🍽️';
    }

    Widget doseFld(TextEditingController ctrl, double? computed, String unit) => Row(children: [
      Expanded(child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C)),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: computed != null ? computed.round().toString() : 'Quantité',
          hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400, fontWeight: FontWeight.normal),
          suffixText: unit,
          suffixStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF0C5C6C)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: const Color(0xFF0C5C6C).withOpacity(0.04),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: const Color(0xFF0C5C6C).withOpacity(0.25))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: const Color(0xFF0C5C6C).withOpacity(0.25))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
        ),
      )),
      if (ctrl.text.isNotEmpty) GestureDetector(
        onTap: () => setState(ctrl.clear),
        child: Padding(padding: const EdgeInsets.only(left:6), child: Icon(Icons.refresh_rounded, size:18, color:Colors.grey.shade400)),
      ),
    ]);

    Widget densFld(TextEditingController ctrl, String hint) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: hint,
          labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
          suffixText: 'kcal/100g',
          suffixStyle: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true, fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
        ),
      ),
    );

    Widget? kcalBadge;
    if (kcalApportes != null && der != null) {
      final diff  = kcalApportes - der;
      final pct   = ((diff / der) * 100).round();
      final ok    = diff.abs() / der < 0.15;
      final over  = diff > 0;
      final color = ok ? const Color(0xFF6E9E57) : over ? const Color(0xFFE65100) : const Color(0xFF0C5C6C);
      kcalBadge = Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))),
        child: Row(children: [
          Text(ok ? '✅' : over ? '⚠️' : 'ℹ️', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            '${kcalApportes.round()} kcal apportés  (${pct >= 0 ? '+' : ''}$pct% vs besoins)',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: color),
          )),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(typeEmoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(typeLabel, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _modeCalculateur = true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF0C5C6C), minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
          ),
        ]),
        const Divider(height: 14),

        // ── Croquettes
        if (type == 'croquettes' && isDog) ...[
          if (_marqueNom.isNotEmpty) ...[
            Text('$_marqueNom — $_gammeNom', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 8),
          ],
          Row(children: [
            const Text('🥜  Quantité/jour ', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl, _rationCroquettes, 'g')),
          ]),
          if (_densiteCtrl.text.isEmpty || double.tryParse(_densiteCtrl.text.replaceAll(',','.')) == null)
            densFld(_densiteCtrl, 'Densité énergetique (sur l\'emballage)'),
        ],

        // ── BARF
        if (type == 'barf' && isDog) ...[
          Row(children: [
            const Text('Total BARF/jour ', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl, _rationBarf, 'g')),
          ]),
          const SizedBox(height: 10),
          Builder(builder:(_) {
            final base = _doseEffBarf ?? _rationBarf ?? 0;
            return Wrap(spacing: 6, runSpacing: 6, children: [
              _miniChip('🥩', '${(base * _pctMuscles / 100).round()} g muscles'),
              _miniChip('🫀', '${(base * _pctAbats   / 100).round()} g abats'),
              _miniChip('🦴', '${(base * _pctOs       / 100).round()} g os'),
              _miniChip('🥦', '${(base * _pctLegumes  / 100).round()} g légumes'),
            ]);
          }),
        ],

        // ── Ménagère
        if (type == 'menagere' && isDog) ...[
          Row(children: [
            const Text('Total/jour ', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl, _rationMenagere, 'g')),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showRecipeSheet(context),
            child: Text('📋 Voir la composition détaillée →', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: const Color(0xFF0C5C6C), decoration: TextDecoration.underline)),
          ),
        ],

        // ── Mixte chien/chat
        if (type == 'mixte' && isDog) ...[
          Row(children: [
            const Text('🥜  Croquettes', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            Text('  (${_pctCroquMix.round()}%)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl, _rationMixteCroq, 'g')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text('${_typeMixte2=='barf'?'🥩':_typeMixte2=='menagere'?'🍲':'🥫'}  ${_typeMixte2=='barf'?'BARF':_typeMixte2=='menagere'?'Ménagère':'Pâtée'}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            Text('  (${(100-_pctCroquMix).round()}%)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl2, _rationMixteSecond, 'g')),
          ]),
          if (_typeMixte2 == 'patee' && (_densitePateeCtrl.text.isEmpty || double.tryParse(_densitePateeCtrl.text.replaceAll(',','.')) == null))
            densFld(_densitePateeCtrl, 'Densité pâtée (sur l\'emballage)'),
          if (_densiteCtrl.text.isEmpty || double.tryParse(_densiteCtrl.text.replaceAll(',','.')) == null)
            densFld(_densiteCtrl, 'Densité croquettes (sur l\'emballage)'),
        ],

        // ── Autres espèces
        if (!isDog) Builder(builder: (_) {
          final detail = _rationEspeceDetail;
          if (detail == null) return Text('Renseignez le poids pour calculer.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (detail.containsKey('total_kg'))  _sumRow('Total/jour', '${(detail['total_kg'] as double).toStringAsFixed(1)} kg'),
            if (detail.containsKey('foin_kg'))   _sumRow('🌿 Foin', '${(detail['foin_kg'] as double).toStringAsFixed(1)} kg'),
            if (detail.containsKey('granules_kg') && (detail['granules_kg'] as double) > 0) ...[
              _sumRow('🌾 Granulés', '${(detail['granules_kg'] as double).toStringAsFixed(1)} kg'),
              if (_densiteGranCtrl.text.isEmpty || double.tryParse(_densiteGranCtrl.text.replaceAll(',','.')) == null)
                densFld(_densiteGranCtrl, 'Densité granulés (sur l\'emballage)'),
            ],
            if (detail.containsKey('complement_kg')) _sumRow('💊 Compléments', '${((detail['complement_kg'] as double)*1000).round()} g'),
            if (detail.containsKey('granules_g'))    _sumRow('🌾 Granulés', '${(detail['granules_g'] as double).round()} g'),
            if (detail.containsKey('legumes_g'))     _sumRow('🥬 Légumes', '${(detail['legumes_g'] as double).round()} g'),
            if (detail.containsKey('graines_g'))     _sumRow('🌰 Graines', '${(detail['graines_g'] as double).round()} g'),
          ]);
        }),

        if (kcalBadge != null) kcalBadge,

        // Save button
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C5C6C), disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 12)),
          child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
        )),
      ]),
    );
  }

  Widget _miniChip(String emoji, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
    child: Text('$emoji $label', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF1F2A2E))),
  );

  Widget _sumRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
      const Spacer(),
      Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
    ]),
  );

  Widget _buildRepasSection() {
    final plan = _mealPlan;
    if (plan.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      const _AlimSection('Rations journalières'),
      const SizedBox(height: 10),

      // Sélecteur nombre de repas
      Row(children: [
        Text('Repas par jour :', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(width: 10),
        ...List.generate(4, (i) {
          final n = i + 1;
          final selected = _nbRepas == n;
          return GestureDetector(
            onTap: () => setState(() => _nbRepas = n),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF0C5C6C) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              alignment: Alignment.center,
              child: Text('$n', style: TextStyle(
                fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.grey.shade600)),
            ),
          );
        }),
        const Spacer(),
        // Note état
        if (_etatReproEffectif != 'normal')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Text(
              _etatReproEffectif == 'lactation' ? '🤱 +50%' : _etatReproEffectif == 'gestation_fin' ? '🤰 +30%' : '🤰 +10%',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C), fontWeight: FontWeight.w700)),
          ),
        if (widget.s._sterilise)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text('✂️ Stérilisé', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.purple.shade600, fontWeight: FontWeight.w700)),
          ),
      ]),
      const SizedBox(height: 12),

      // Cartes repas
      ...plan.asMap().entries.map((entry) {
        final idx  = entry.key;
        final meal = entry.value;
        final label = meal['label'] as String;
        final items = meal['items'] as List;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // En-tête repas
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: [
                  const Color(0xFF0C5C6C), const Color(0xFF6E9E57),
                  const Color(0xFFB8860B), const Color(0xFF8D6E63),
                ][idx % 4].withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                Text(label, style: TextStyle(
                  fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700,
                  color: [
                    const Color(0xFF0C5C6C), const Color(0xFF4A7A38),
                    const Color(0xFF8B6914), const Color(0xFF5D4037),
                  ][idx % 4])),
              ]),
            ),
            // Items
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.map<Widget>((item) {
                  final m = item as Map;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Text(m['emoji'] as String, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(m['nom'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C5C6C).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(m['qte'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
                      ),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ]),
        );
      }),

      // Note eau
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Row(children: [
          const Text('💧', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            widget.s._espece == 'cheval' ? 'Eau fraîche : 30–60 L/j minimum'
            : widget.s._espece == 'lapin' ? 'Eau fraîche : ${(_poidsRef * 100).round()} ml/j minimum'
            : 'Eau fraîche disponible en permanence',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)));
    if (widget.s.widget.animalId == null) {
      return const _SaveFirstPrompt(message: 'Enregistrez la fiche pour accéder à l\'alimentation.');
    }
    if (!_modeCalculateur) return _buildSummaryView();

    final rer       = _rer;
    final der       = _der;
    final phaseAuto = _phaseAutoDetect;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        if (_existing != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _modeCalculateur = false),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF0C5C6C)),
              label: const Text('← Retour au résumé', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF0C5C6C))),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
            ),
          ),
          const SizedBox(height: 4),
        ],

        // ── TYPE DE RATION ──────────────────────────────────────
        const _AlimSection('Type de ration'),
        const SizedBox(height: 10),
        Row(children: [
          for (final t in _rationOptions)
            Expanded(child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _type = t.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _typeValide == t.$1 ? const Color(0xFF0C5C6C) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _typeValide == t.$1 ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
                  ),
                  child: Column(children: [
                    Text(t.$2, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(t.$3, style: TextStyle(fontFamily:'Galey',fontSize:11,fontWeight:FontWeight.w600,
                      color: _typeValide==t.$1 ? Colors.white : const Color(0xFF1F2A2E))),
                  ]),
                ),
              ),
            )),
        ]),
        const SizedBox(height: 20),

        // ── POIDS DE RÉFÉRENCE ──────────────────────────────────
        const _AlimSection('Poids de référence'),
        const SizedBox(height: 10),
        Row(children: [
          if (_poidsActuel != null) Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color:Colors.grey.shade50, borderRadius:BorderRadius.circular(12), border:Border.all(color:Colors.grey.shade100)),
              child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                Text('Actuel', style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade500)),
                Text('${_poidsActuel!.toStringAsFixed(1)} kg',
                  style: const TextStyle(fontFamily:'Galey',fontWeight:FontWeight.w700,fontSize:16,color:Color(0xFF1F2A2E))),
              ]),
            ),
          ),
          Expanded(child: TextField(
            controller: _objectifCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily:'Galey',fontSize:14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText:'Objectif (kg)',
              labelStyle:TextStyle(fontFamily:'Galey',fontSize:13,color:Colors.grey.shade500),
              filled:true, fillColor:Colors.grey.shade50,
              contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
              border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide(color:Colors.grey.shade200)),
              enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide(color:Colors.grey.shade200)),
            ),
          )),
        ]),
        const SizedBox(height: 20),

        // ── PHASE DE VIE (auto-détectée + override) ─────────────
        Row(children: [
          const _AlimSection('Phase de vie'),
          const SizedBox(width: 8),
          if (_phaseManuelle == null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color:Colors.grey.shade100, borderRadius:BorderRadius.circular(10)),
            child: Text('auto', style:TextStyle(fontFamily:'Galey',fontSize:10,color:Colors.grey.shade500)),
          ),
        ]),
        const SizedBox(height: 8),
        if (phaseAuto == 'junior') Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color:const Color(0xFFFFF3CD), borderRadius:BorderRadius.circular(12), border:Border.all(color:const Color(0xFFFFDC80))),
          child: const Row(children: [
            Text('🍼 ', style: TextStyle(fontSize: 16)),
            Expanded(child: Text('Alimentation spécifique Junior en croissance recommandée',
              style: TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF856404)))),
          ]),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in [('junior','Junior 🍼'),('adulte','Adulte'),('senior','Senior 🌿')])
            GestureDetector(
              onTap: () => setState(() => _phaseManuelle = e.$1 == phaseAuto ? null : e.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _phase == e.$1 ? const Color(0xFF0C5C6C) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _phase == e.$1 ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
                ),
                child: Row(mainAxisSize:MainAxisSize.min, children:[
                  Text(e.$2, style:TextStyle(fontFamily:'Galey',fontSize:13,
                    color: _phase==e.$1 ? Colors.white : const Color(0xFF1F2A2E),
                    fontWeight: _phase==e.$1 ? FontWeight.w700 : FontWeight.normal)),
                  if (e.$1 == phaseAuto) ...[
                    const SizedBox(width:4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal:5,vertical:1),
                      decoration: BoxDecoration(
                        color: _phase==e.$1 ? Colors.white.withOpacity(0.25) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('auto', style:TextStyle(fontFamily:'Galey',fontSize:9,
                        color: _phase==e.$1 ? Colors.white : Colors.grey.shade500)),
                    ),
                  ],
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 20),

        // ── ÉNERGIE DE LA RACE (chien/chat uniquement) ──────────
        if (_isDogOrCat) ...[
        const _AlimSection('Énergie de la race'),
        const SizedBox(height: 10),
        ...(_catEnergieLabels.entries.map((e) => GestureDetector(
          onTap: () => setState(() => _catEnergie = e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _catEnergie == e.key ? const Color(0xFF0C5C6C).withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _catEnergie==e.key ? const Color(0xFF0C5C6C) : Colors.grey.shade200,
                width: _catEnergie==e.key ? 1.5 : 1),
            ),
            child: Row(children: [
              Radio<String>(value:e.key, groupValue:_catEnergie,
                onChanged:(v) => setState(() => _catEnergie=v!),
                activeColor:const Color(0xFF0C5C6C),
                materialTapTargetSize:MaterialTapTargetSize.shrinkWrap,
                visualDensity:VisualDensity.compact),
              const SizedBox(width:6),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                Text(e.value, style:TextStyle(fontFamily:'Galey',fontSize:13,fontWeight:FontWeight.w600,
                  color: _catEnergie==e.key ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                Text(_exemplesEnergie[e.key] ?? '', style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade500)),
              ])),
            ]),
          ),
        ))),
        const SizedBox(height: 20),
        ], // end if (_isDogOrCat) énergie race

        // ── NIVEAU D'ACTIVITÉ (adulte) ──────────────────────────
        if (_phase == 'adulte') ...[
          const _AlimSection("Niveau d'activité"),
          const SizedBox(height: 10),
          Wrap(spacing:8, runSpacing:8, children:[
            for (final e in _actLabels.entries)
              GestureDetector(
                onTap: () => setState(() => _activite = e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal:14,vertical:8),
                  decoration: BoxDecoration(
                    color: _activite==e.key ? const Color(0xFF0C5C6C) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _activite==e.key ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
                  ),
                  child: Text(e.value, style:TextStyle(fontFamily:'Galey',fontSize:13,
                    color: _activite==e.key ? Colors.white : const Color(0xFF1F2A2E),
                    fontWeight: _activite==e.key ? FontWeight.w700 : FontWeight.normal)),
                ),
              ),
          ]),
          const SizedBox(height: 20),
        ],

        // ── ÉTAT REPRODUCTEUR ───────────────────────────────────
        if (widget.s._sterilise || widget.s._sexe == 'femelle') ...[
          Row(children: [
            const _AlimSection('État reproducteur'),
            const SizedBox(width: 8),
            if (!widget.s._sterilise && _etatRepro == null) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color:Colors.grey.shade100, borderRadius:BorderRadius.circular(10)),
              child: Text('auto', style:TextStyle(fontFamily:'Galey',fontSize:10,color:Colors.grey.shade500)),
            ),
          ]),
          const SizedBox(height: 8),
          if (widget.s._sterilise) ...[
            // Chip stérilisé pré-sélectionné (non modifiable — vient de la fiche identité)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6E9E57),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('✂️', style: TextStyle(fontSize: 13)),
                SizedBox(width: 4),
                Text('Stérilisé(e)', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6E9E57).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6E9E57).withOpacity(0.25)),
              ),
              child: Row(children: [
                const Text('✂️', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Réduction stérilisé appliquée : ×${widget.s._espece == 'chat' ? '0.7' : '0.8'} sur les besoins énergétiques',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF4A7C39)))),
              ]),
            ),
          ] else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in [
                ('normal',          'Normal', '⚪'),
                ('gestation_debut', 'Gestation (début)', '🤰'),
                ('gestation_fin',   'Gestation (fin)', '🍼'),
                ('lactation',       'Lactation', '🤱'),
              ])
                GestureDetector(
                  onTap: () => setState(() => _etatRepro = e.$1 == _etatReproEffectif && _etatRepro != null ? null : e.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _etatReproEffectif == e.$1 ? const Color(0xFF0C5C6C) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _etatReproEffectif == e.$1 ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.$3, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(e.$2, style: TextStyle(fontFamily:'Galey', fontSize: 12,
                        color: _etatReproEffectif == e.$1 ? Colors.white : const Color(0xFF1F2A2E),
                        fontWeight: _etatReproEffectif == e.$1 ? FontWeight.w700 : FontWeight.normal)),
                      if (e.$1 == _etatReproAuto && _etatRepro == null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _etatReproEffectif == e.$1 ? Colors.white.withOpacity(0.25) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6)),
                          child: Text('auto', style: TextStyle(fontFamily:'Galey', fontSize: 9,
                            color: _etatReproEffectif == e.$1 ? Colors.white : Colors.grey.shade500)),
                        ),
                      ],
                    ]),
                  ),
                ),
            ]),
            // Recommandations spécifiques selon l'état
            if (_etatReproEffectif != 'normal') ...[
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0C5C6C).withOpacity(0.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('🥗 ', style: TextStyle(fontSize: 14)),
                    Expanded(child: Text(
                      _etatReproEffectif == 'gestation_debut'
                        ? 'Gestation (début) — Apports +10%'
                        : _etatReproEffectif == 'gestation_fin'
                          ? 'Gestation (fin) — Apports +30%'
                          : 'Lactation — Apports +50%',
                      style: const TextStyle(fontFamily:'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C)))),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    _etatReproEffectif == 'gestation_debut'
                      ? 'Augmentez progressivement les rations. Préférez une alimentation riche en protéines de qualité. Ne modifiez pas l\'alimentation brutalement.'
                      : _etatReproEffectif == 'gestation_fin'
                        ? 'Dernières semaines : augmentez les apports progressivement. Fractionnez les repas (3–4/j pour les chiens/chats). Alimentation gestante ou aliment jeune recommandé.'
                        : 'Alimentation à volonté recommandée (chiens/chats). Eau fraîche disponible en permanence. Besoins pouvant atteindre +75% selon le nombre de petits.',
                    style: TextStyle(fontFamily:'Galey', fontSize: 11, color: Colors.grey.shade700)),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 20),
        ],

        // ── PARAMÈTRES SELON TYPE ───────────────────────────────
        if (_typeValide == 'croquettes') ...[
          const _AlimSection('Produit'),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
              builder: (_) => _MarquePickerSheet(
                espece: widget.s._espece, phase: _phase,
                onSelected: (b) => setState(() {
                  _marqueId     = b['id'] as String?;
                  _marqueNom    = (b['marque'] ?? '') as String;
                  _gammeNom     = (b['gamme']  ?? '') as String;
                  _densiteCtrl.text = (b['densite_kcal_100g'] as num?)?.round().toString() ?? '';
                  _dosesMarque  = (b['doses'] as List<dynamic>?) ?? [];
                }),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal:14, vertical:12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _marqueNom.isNotEmpty ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children:[
                const Icon(Icons.search, size:18, color:Color(0xFF0C5C6C)),
                const SizedBox(width:10),
                Expanded(child: _marqueNom.isEmpty
                  ? Text('Rechercher une marque…', style:TextStyle(fontFamily:'Galey',fontSize:14,color:Colors.grey.shade400))
                  : Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                      Text(_marqueNom, style:const TextStyle(fontFamily:'Galey',fontSize:14,fontWeight:FontWeight.w700,color:Color(0xFF1F2A2E))),
                      Text(_gammeNom, style:TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade500)),
                    ]),
                ),
                if (_marqueNom.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() { _marqueId=null; _marqueNom=''; _gammeNom=''; _densiteCtrl.clear(); _dosesMarque=[]; }),
                    child: const Icon(Icons.close, size:18, color:Color(0xFF0C5C6C)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          _alimField('Densité énergétique (kcal/100g)', _densiteCtrl, numeric:true, hint:'Ex : 340 — indiqué sur l\'emballage'),
        ] else if (_typeValide == 'barf') ...[
          const _AlimSection('Composition BARF (%)'),
          const SizedBox(height: 10),
          _BarfSlider(label:'Muscles / viande maigre', emoji:'🥩', value:_pctMuscles, color:const Color(0xFF0C5C6C), onChanged:(v)=>setState(()=>_pctMuscles=v)),
          _BarfSlider(label:'Abats (foie, rein…)',     emoji:'🫀', value:_pctAbats,   color:const Color(0xFF8D6E63), onChanged:(v)=>setState(()=>_pctAbats=v)),
          _BarfSlider(label:'Os charnus',               emoji:'🦴', value:_pctOs,      color:const Color(0xFFBCAAA4), onChanged:(v)=>setState(()=>_pctOs=v)),
          _BarfSlider(label:'Légumes & fruits',         emoji:'🥦', value:_pctLegumes, color:const Color(0xFF6E9E57), onChanged:(v)=>setState(()=>_pctLegumes=v)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment:MainAxisAlignment.end, children:[
            Text('Total : ', style:TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade500)),
            Text('${(_pctMuscles+_pctAbats+_pctOs+_pctLegumes).round()}%', style:TextStyle(
              fontFamily:'Galey',fontSize:13,fontWeight:FontWeight.w700,
              color:(_pctMuscles+_pctAbats+_pctOs+_pctLegumes-100).abs()<1 ? const Color(0xFF6E9E57) : const Color(0xFFE25C5C))),
          ]),
        ] else if (_typeValide == 'menagere') ...[
          const _AlimSection('Ration ménagère'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder:(_)=>_RecetteLibraryPage(espece:widget.s._espece, sterilise:widget.s._sterilise))),
            icon: const Icon(Icons.menu_book_outlined, size:18),
            label: const Text('Bibliothèque de recettes', style:TextStyle(fontFamily:'Galey')),
            style: OutlinedButton.styleFrom(
              foregroundColor:const Color(0xFF0C5C6C), side:const BorderSide(color:Color(0xFF0C5C6C)),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),
              padding:const EdgeInsets.symmetric(horizontal:20,vertical:12)),
          ),
        ] else if (_typeValide == 'mixte' && _isDogOrCat) ...[
          // ── RATION MIXTE CHIEN/CHAT (croquettes + pâtée ou BARF) ──
          const _AlimSection('Composition de la ration mixte'),
          const SizedBox(height: 10),
          // Slider croquettes %
          _BarfSlider(
            label: 'Croquettes', emoji: '🥜',
            value: _pctCroquMix, color: const Color(0xFF0C5C6C),
            onChanged: (v) => setState(() => _pctCroquMix = v)),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(children: [
              const SizedBox(width: 22),
              Text(
                '${(100 - _pctCroquMix).round()}% issu de : ',
                style: TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade600)),
              // Toggle pâtée / BARF
              GestureDetector(
                onTap: () => setState(() {
                  if (_typeMixte2 == 'patee') _typeMixte2 = 'barf';
                  else if (_typeMixte2 == 'barf') _typeMixte2 = 'menagere';
                  else _typeMixte2 = 'patee';
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal:10, vertical:4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C5C6C).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF0C5C6C).withOpacity(0.3))),
                  child: Row(mainAxisSize:MainAxisSize.min, children:[
                    Text(_typeMixte2 == 'barf' ? '🥩 BARF' : _typeMixte2 == 'menagere' ? '🍲 Ménagère' : '🥫 Pâtée',
                      style: const TextStyle(fontFamily:'Galey',fontSize:12,fontWeight:FontWeight.w700,color:Color(0xFF0C5C6C))),
                    const SizedBox(width:4),
                    const Icon(Icons.swap_horiz, size:14, color:Color(0xFF0C5C6C)),
                  ]),
                ),
              ),
            ]),
          ),
          // Croquettes : brand + density
          const Text('Croquettes', style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E),fontWeight:FontWeight.w600)),
          const SizedBox(height:6),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
              builder: (_) => _MarquePickerSheet(
                espece: widget.s._espece, phase: _phase,
                onSelected: (b) => setState(() {
                  _marqueId    = b['id'] as String?;
                  _marqueNom   = (b['marque'] ?? '') as String;
                  _gammeNom    = (b['gamme']  ?? '') as String;
                  _densiteCtrl.text = (b['densite_kcal_100g'] as num?)?.round().toString() ?? '';
                  _dosesMarque = (b['doses'] as List<dynamic>?) ?? [];
                }),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal:14, vertical:12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _marqueNom.isNotEmpty ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children:[
                const Icon(Icons.search, size:18, color:Color(0xFF0C5C6C)),
                const SizedBox(width:10),
                Expanded(child: _marqueNom.isEmpty
                  ? Text('Rechercher une marque…', style:TextStyle(fontFamily:'Galey',fontSize:14,color:Colors.grey.shade400))
                  : Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                      Text(_marqueNom, style:const TextStyle(fontFamily:'Galey',fontSize:14,fontWeight:FontWeight.w700,color:Color(0xFF1F2A2E))),
                      Text(_gammeNom, style:TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade500)),
                    ]),
                ),
                if (_marqueNom.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() { _marqueId=null; _marqueNom=''; _gammeNom=''; _densiteCtrl.clear(); _dosesMarque=[]; }),
                    child: const Icon(Icons.close, size:18, color:Color(0xFF0C5C6C)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height:8),
          _alimField('Densité croquettes (kcal/100g)', _densiteCtrl, numeric:true, hint:'Ex : 362 — indiqué sur l\'emballage'),
          const SizedBox(height:12),
          // Second composant
          if (_typeMixte2 == 'patee') ...[
            const Text('Pâtée', style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E),fontWeight:FontWeight.w600)),
            const SizedBox(height:6),
            _alimField('Densité pâtée (kcal/100g)', _densitePateeCtrl, numeric:true, hint:'Ex : 85 — indiqué sur l\'emballage'),
          ] else if (_typeMixte2 == 'menagere') ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color:const Color(0xFFE8F5E9), borderRadius:BorderRadius.circular(10), border:Border.all(color:const Color(0xFF6E9E57).withOpacity(0.3))),
              child: const Row(children:[
                Text('🍲 ', style:TextStyle(fontSize:14)),
                Expanded(child:Text('Ration ménagère — viande cuite, légumes, féculents. Densité estimée à 120 kcal/100g.',
                  style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E)))),
              ]),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color:const Color(0xFFF5F0E8), borderRadius:BorderRadius.circular(10), border:Border.all(color:const Color(0xFFBCAAA4).withOpacity(0.3))),
              child: const Row(children:[
                Text('🥩 ', style:TextStyle(fontSize:14)),
                Expanded(child:Text('BARF — viande crue, os charnus, abats. Ration estimée à 2% du poids vif.',
                  style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E)))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _mixteSepareParRepas = !_mixteSepareParRepas),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal:14, vertical:10),
              decoration: BoxDecoration(
                color: _mixteSepareParRepas ? const Color(0xFF0C5C6C).withOpacity(0.07) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _mixteSepareParRepas ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children:[
                Icon(_mixteSepareParRepas ? Icons.restaurant_outlined : Icons.shuffle_rounded,
                  size:18, color:_mixteSepareParRepas ? const Color(0xFF0C5C6C) : Colors.grey.shade500),
                const SizedBox(width:10),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                  Text(_mixteSepareParRepas ? 'Un type par repas' : 'Mélangé à chaque repas',
                    style:TextStyle(fontFamily:'Galey',fontSize:13,fontWeight:FontWeight.w600,
                      color: _mixteSepareParRepas ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  Text(_mixteSepareParRepas ? 'Ex: croquettes le matin, pâtée le soir' : 'Les deux composants à chaque repas',
                    style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade500)),
                ])),
                Switch.adaptive(
                  value: _mixteSepareParRepas,
                  onChanged: (v) => setState(() => _mixteSepareParRepas = v),
                  activeColor: const Color(0xFF0C5C6C),
                ),
              ]),
            ),
          ),
        ] else if (_typeValide == 'mixte') ...[
          // ── RATION MIXTE (cheval, ovin, caprin, lapin) ──────────
          _AlimSection(widget.s._espece == 'lapin' ? 'Composition (foin + granulés)' : 'Composition de la ration'),
          const SizedBox(height: 10),
          if (['cheval','ovin','caprin'].contains(widget.s._espece)) ...[
            _BarfSlider(label:'Foin / Fourrage',   emoji:'🌿', value:_pctFoinMix,     color:const Color(0xFF6E9E57), onChanged:(v)=>setState(()=>_pctFoinMix=v)),
            _BarfSlider(label:'Granulés / Aliment', emoji:'🌾', value:_pctGranulesMix, color:const Color(0xFFB8860B), onChanged:(v)=>setState(()=>_pctGranulesMix=v)),
            _BarfSlider(label:'Compléments',        emoji:'💊', value:_pctCompMix,     color:const Color(0xFF0C5C6C), onChanged:(v)=>setState(()=>_pctCompMix=v)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment:MainAxisAlignment.end, children:[
              Text('Total : ', style:TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade500)),
              Text('${(_pctFoinMix+_pctGranulesMix+_pctCompMix).round()}%', style:TextStyle(
                fontFamily:'Galey',fontSize:13,fontWeight:FontWeight.w700,
                color:(_pctFoinMix+_pctGranulesMix+_pctCompMix-100).abs()<1 ? const Color(0xFF6E9E57) : const Color(0xFFE25C5C))),
            ]),
            const SizedBox(height: 12),
          ],
          // Recherche marque granulés
          const Text('Marque de granulés', style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
              builder: (_) => _MarquePickerSheet(
                espece: widget.s._espece, phase: _phase,
                onSelected: (b) => setState(() {
                  _marqueId   = b['id'] as String?;
                  _marqueNom  = (b['marque'] ?? '') as String;
                  _gammeNom   = (b['gamme']  ?? '') as String;
                  _dosesMarque = (b['doses'] as List<dynamic>?) ?? [];
                }),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal:14, vertical:12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _marqueNom.isNotEmpty ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children:[
                const Icon(Icons.search, size:18, color:Color(0xFF0C5C6C)),
                const SizedBox(width:10),
                Expanded(child: _marqueNom.isEmpty
                  ? Text('Rechercher une marque…', style:TextStyle(fontFamily:'Galey',fontSize:14,color:Colors.grey.shade400))
                  : Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                      Text(_marqueNom, style:const TextStyle(fontFamily:'Galey',fontSize:14,fontWeight:FontWeight.w700,color:Color(0xFF1F2A2E))),
                      if (_gammeNom.isNotEmpty) Text(_gammeNom, style:TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade500)),
                    ]),
                ),
                if (_marqueNom.isNotEmpty) GestureDetector(
                  onTap: () => setState(() { _marqueId=null; _marqueNom=''; _gammeNom=''; _dosesMarque=[]; }),
                  child: const Icon(Icons.close, size:18, color:Color(0xFF0C5C6C)),
                ),
              ]),
            ),
          ),
        ] else if (_typeValide == 'paturage') ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color:const Color(0xFFE8F5E9), borderRadius:BorderRadius.circular(12), border:Border.all(color:const Color(0xFF6E9E57).withOpacity(0.3))),
            child: const Row(children:[
              Text('🌿 ', style:TextStyle(fontSize:16)),
              Expanded(child:Text('Pâturage libre — veillez à la qualité de l\'herbe et à la disponibilité de sel et eau fraîche.',
                style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF2E7D32)))),
            ]),
          ),
        ] else ...[
          // Complément / graines / granulés seuls
          _alimField('Informations complémentaires', _densiteCtrl, hint: 'Marque, quantité, fréquence…'),
        ],
        const SizedBox(height: 24),

        // ── RÉSULTATS ───────────────────────────────────────────
        if (_isDogOrCat && _poidsRef > 0 && der != null) ...[
          const _AlimSection('Besoins calculés'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color:const Color(0xFF0C5C6C).withOpacity(0.07), borderRadius:BorderRadius.circular(16)),
            child: Column(children:[
              _AlimCalcRow('RER (besoins de repos)', '${rer!.round()} kcal/j'),
              const SizedBox(height:8),
              _AlimCalcRow('DER (besoins journaliers)', '${der.round()} kcal/j'),
              if (_phase == 'junior') ...[
                const SizedBox(height:4),
                Align(alignment:Alignment.centerLeft, child:Text(
                  '🍼 Facteur junior : ×${_ageMois>=0&&_ageMois<4 ? 3.0 : _poidsRef>25 ? 1.8 : 2.0} (grande race = croissance lente)',
                  style:const TextStyle(fontFamily:'Galey',fontSize:11,color:Color(0xFF856404)))),
              ],
              if (widget.s._sterilise) ...[
                const SizedBox(height:4),
                Align(alignment:Alignment.centerLeft, child:Text(
                  '✂️ Animal stérilisé : besoins réduits ×${widget.s._espece == 'chat' ? '0.7' : '0.8'} pris en compte',
                  style:const TextStyle(fontFamily:'Galey',fontSize:11,color:Color(0xFF0C5C6C)))),
              ],
              if (_etatReproEffectif != 'normal' && widget.s._sexe == 'femelle') ...[
                const SizedBox(height:4),
                Align(alignment:Alignment.centerLeft, child:Text(
                  _etatReproEffectif == 'gestation_debut'
                    ? '🤰 Gestation début : +10% inclus dans le calcul'
                    : _etatReproEffectif == 'gestation_fin'
                      ? '🍼 Gestation fin : +30% inclus dans le calcul'
                      : '🤱 Lactation : +50% inclus (jusqu\'à +75% selon la portée)',
                  style:const TextStyle(fontFamily:'Galey',fontSize:11,color:Color(0xFF0C5C6C)))),
              ],
              if (_typeValide=='croquettes' && _rationCroquettes!=null) ...[
                const Divider(height:20),
                _AlimCalcRow('Ration calculée', '${_rationCroquettes!.round()} g/j', highlight:true),
                if (_doseBrandInterpolee != null) ...[
                  const SizedBox(height:6),
                  _AlimCalcRow('Dose fabricant (${_poidsRef.toStringAsFixed(1)} kg)', '${_doseBrandInterpolee!.round()} g/j', subtle:true),
                ],
              ],
              if (_typeValide=='barf' && _rationBarf!=null) ...[
                const Divider(height:20),
                _AlimCalcRow('Ration BARF estimée', '${_rationBarf!.round()} g/j', highlight:true),
                const SizedBox(height:4),
                Text('Fourchette : ${(_poidsRef*20).round()}–${(_poidsRef*30).round()} g/j (2–3% poids vif)',
                  style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade500)),
              ],
              if (_typeValide=='mixte' && _isDogOrCat) ...[
                const Divider(height:20),
                if (_rationMixteCroq != null)
                  _AlimCalcRow('🥜 Croquettes (${_pctCroquMix.round()}%)', '${_rationMixteCroq!.round()} g/j', highlight:true)
                else
                  _AlimCalcRow('🥜 Croquettes (${_pctCroquMix.round()}%)', '— (densité manquante)', highlight:false),
                const SizedBox(height:4),
                if (_rationMixteSecond != null)
                  _AlimCalcRow(
                    _typeMixte2 == 'barf' ? '🥩 BARF (${(100-_pctCroquMix).round()}%)' : '🥫 Pâtée (${(100-_pctCroquMix).round()}%)',
                    '${_rationMixteSecond!.round()} g/j', highlight:true)
                else
                  _AlimCalcRow(
                    _typeMixte2 == 'barf' ? '🥩 BARF (${(100-_pctCroquMix).round()}%)' : '🥫 Pâtée (${(100-_pctCroquMix).round()}%)',
                    _typeMixte2 == 'barf' ? '— (poids requis)' : '— (densité manquante)', highlight:false),
              ],
            ]),
          ),
          const SizedBox(height:6),
          Text(
            'RER = 70 × poids⁰·⁷⁵  ·  ${_phase=="adulte" ? "act.×${_actFactors[_activite]}" : _phase}  ·  race×${_catEnergieFactors[_catEnergie]}'
            '${widget.s._sterilise ? "  ·  stérilisé×${widget.s._espece == 'chat' ? '0.7' : '0.8'}" : ""}'
            '${_etatReproEffectif != 'normal' ? "  ·  repro×${_reproFactor.toStringAsFixed(1)}" : ""}',
            style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade400)),
        ] else if (!_isDogOrCat) ...[
          // ── BESOINS CALCULÉS (espèces non chien/chat) ───────────
          Builder(builder: (_) {
            final detail = _rationEspeceDetail;
            if (detail == null) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color:Colors.blue.shade50, borderRadius:BorderRadius.circular(12), border:Border.all(color:Colors.blue.shade100)),
                child: Row(children:[
                  Icon(Icons.info_outline, color:Colors.blue.shade700, size:18),
                  const SizedBox(width:10),
                  const Expanded(child:Text('Renseignez le poids (onglet Identité) pour calculer la ration.',
                    style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E)))),
                ]),
              );
            }
            return Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
              const _AlimSection('Besoins calculés'),
              const SizedBox(height:10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color:const Color(0xFF0C5C6C).withOpacity(0.07), borderRadius:BorderRadius.circular(16)),
                child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                  // Cheval / ovin / caprin — ration mixte
                  if (detail.containsKey('total_kg')) ...[
                    _AlimCalcRow('Total ration/jour (${_rationPctPoidsvif.toStringAsFixed(1)}% poids vif)', '${(detail['total_kg'] as double).toStringAsFixed(1)} kg/j'),
                    const Divider(height:16),
                    _AlimCalcRow('🌿 Foin / Fourrage', '${(detail['foin_kg'] as double).toStringAsFixed(1)} kg/j', highlight:true),
                    const SizedBox(height:4),
                    _AlimCalcRow('🌾 Granulés', '${(detail['granules_kg'] as double).toStringAsFixed(1)} kg/j', highlight:true),
                    const SizedBox(height:4),
                    _AlimCalcRow('💊 Compléments', '${((detail['complement_kg'] as double)*1000).round()} g/j', highlight:true),
                    if (detail['granules_kg'] as double > 0) ...[
                      const SizedBox(height:8),
                      Text(
                        '↳ Répartir en ${detail['nb_repas']} repas — max ${detail['max_repas_gran']} kg de granulés/repas',
                        style:const TextStyle(fontFamily:'Galey',fontSize:11,color:Color(0xFF0C5C6C))),
                    ],
                    if (detail['alerte_gran'] as bool) ...[
                      const SizedBox(height:6),
                      Container(
                        padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
                        decoration:BoxDecoration(color:Colors.orange.shade50, borderRadius:BorderRadius.circular(8), border:Border.all(color:Colors.orange.shade200)),
                        child:const Text('⚠️ Ration en granulés élevée : risque digestif. Réduisez et augmentez le foin.',
                          style:TextStyle(fontFamily:'Galey',fontSize:11,color:Color(0xFFE65100))),
                      ),
                    ],
                    if (_etatReproEffectif != 'normal' && widget.s._sexe == 'femelle') ...[
                      const SizedBox(height:6),
                      Text(_etatReproEffectif=='gestation_debut'?'🤰 Gestation début : +10% inclus':_etatReproEffectif=='gestation_fin'?'🍼 Gestation fin : +30% inclus':'🤱 Lactation : +50% inclus',
                        style:const TextStyle(fontFamily:'Galey',fontSize:11,color:Color(0xFF0C5C6C))),
                    ],
                    const SizedBox(height:8),
                    Text('Eau fraîche : ${widget.s._espece=='cheval' ? '30–60 L/j min' : '3–5 L/j'}',
                      style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade500)),
                  ],
                  // Lapin
                  if (detail.containsKey('granules_g') && detail.containsKey('foin')) ...[
                    Row(children:[
                      const Text('🌾 ', style:TextStyle(fontSize:14)),
                      Expanded(child:Text('Foin : accès libre permanent (80% minimum de la ration)',
                        style:const TextStyle(fontFamily:'Galey',fontSize:12,fontWeight:FontWeight.w700,color:Color(0xFF0C5C6C)))),
                    ]),
                    const SizedBox(height:8),
                    _AlimCalcRow('🌿 Granulés',  '${(detail['granules_g'] as double).round()} g/j', highlight:true),
                    const SizedBox(height:4),
                    _AlimCalcRow('🥬 Légumes frais', '${(detail['legumes_g'] as double).round()} g/j', highlight:true),
                    const SizedBox(height:8),
                    Text('Eau : ${(detail['eau_ml'] as double).round()} ml/j min',
                      style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade500)),
                  ],
                  // Oiseau
                  if (detail.containsKey('graines_g')) ...[
                    _AlimCalcRow('🌰 Graines / Granulés',    '${(detail['graines_g'] as double).round()} g/j (perroquet moyen)', highlight:true),
                    const SizedBox(height:4),
                    _AlimCalcRow('🥬 Légumes / Fruits frais', '${(detail['legumes_g'] as double).round()} g/j', highlight:true),
                  ],
                  // Porc
                  if (detail.containsKey('total_kg') && widget.s._espece == 'porcin') ...[
                    _AlimCalcRow('Aliment complet/jour', '${(detail['total_kg'] as double).toStringAsFixed(1)} kg/j', highlight:true),
                  ],
                ]),
              ),
              const SizedBox(height:6),
              Text('Calcul : ${_poidsRef.toStringAsFixed(1)} kg × ${_rationPctPoidsvif.toStringAsFixed(1)}% (poids vif)${_etatReproEffectif!='normal'?' × repro':''}',
                style:TextStyle(fontFamily:'Galey',fontSize:11,color:Colors.grey.shade400)),
            ]);
          }),
          const SizedBox(height:20),
          // ── COMPLÉMENTS RECOMMANDÉS ─────────────────────────────
          if (_supplements.containsKey(widget.s._espece)) ...[
            const _AlimSection('Compléments recommandés'),
            const SizedBox(height:8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(14),
                border:Border.all(color:Colors.grey.shade200),
                boxShadow:[BoxShadow(color:Colors.black.withOpacity(0.03),blurRadius:6)]),
              child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                for (final s in _supplements[widget.s._espece]!) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment:CrossAxisAlignment.start, children:[
                      Text(s.$1, style:const TextStyle(fontSize:16)),
                      const SizedBox(width:8),
                      Expanded(child:Text(s.$2, style:const TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E)))),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color:Colors.amber.shade50, borderRadius:BorderRadius.circular(12), border:Border.all(color:Colors.amber.shade100)),
            child: Row(children:[
              Icon(Icons.info_outline, color:Colors.amber.shade700, size:18),
              const SizedBox(width:10),
              const Expanded(child:Text('Renseignez le poids (onglet Identité) ou un objectif pour calculer la ration.',
                style:TextStyle(fontFamily:'Galey',fontSize:12,color:Color(0xFF1F2A2E)))),
            ]),
          ),
        ],
        const SizedBox(height: 16),

        // ── PLAN DE REPAS ────────────────────────────────────────
        _buildRepasSection(),
        const SizedBox(height: 16),

        // ── AVERTISSEMENT ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            const Expanded(child: Text(
              'Ces informations sont fournies à titre indicatif. En cas de problème de santé spécifique ou de régime particulier, consultez votre vétérinaire.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6B7280)),
            )),
          ]),
        ),
        const SizedBox(height: 16),

        // ── ENREGISTRER ─────────────────────────────────────────
        SizedBox(width:double.infinity, child:ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor:const Color(0xFF0C5C6C), disabledBackgroundColor:Colors.grey.shade300,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),
            padding:const EdgeInsets.symmetric(vertical:14)),
          child: _saving
            ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2))
            : const Text('Enregistrer', style:TextStyle(fontFamily:'Galey',fontWeight:FontWeight.w600,color:Colors.white,fontSize:15)),
        )),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _alimField(String label, TextEditingController ctrl, {bool numeric = false, String? hint}) => TextField(
    controller: ctrl,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    style: const TextStyle(fontFamily:'Galey',fontSize:14),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText:label, hintText:hint,
      hintStyle:TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade400),
      labelStyle:TextStyle(fontFamily:'Galey',fontSize:13,color:Colors.grey.shade500),
      filled:true, fillColor:Colors.grey.shade50,
      contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide(color:Colors.grey.shade200)),
      enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide(color:Colors.grey.shade200))),
  );
}

class _AlimSection extends StatelessWidget {
  final String title;
  const _AlimSection(this.title);
  @override
  Widget build(BuildContext context) => Text(title,
    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13,
      color: Color(0xFF1F2A2E), letterSpacing: 0.3));
}

class _AlimCalcRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final bool subtle;
  const _AlimCalcRow(this.label, this.value, {this.highlight = false, this.subtle = false});
  @override
  Widget build(BuildContext context) {
    final color = highlight ? const Color(0xFF0C5C6C) : subtle ? Colors.grey.shade400 : const Color(0xFF1F2A2E);
    return Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[
      Text(label, style:TextStyle(fontFamily:'Galey',fontSize:13,color:color,
        fontWeight:highlight ? FontWeight.w700 : FontWeight.normal)),
      Text(value, style:TextStyle(fontFamily:'Galey',fontSize:subtle?12:14,fontWeight:FontWeight.w700,color:color)),
    ]);
  }
}

class _BarfSlider extends StatelessWidget {
  final String label;
  final String emoji;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  const _BarfSlider({required this.label, required this.emoji, required this.value, required this.color, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('$emoji ', style: const TextStyle(fontSize: 14)),
        Expanded(child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)))),
        Text('${value.round()}%', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: color, thumbColor: color, overlayColor: color.withOpacity(0.15),
          trackHeight: 4, inactiveTrackColor: Colors.grey.shade200),
        child: Slider(value: value, min: 0, max: 100, divisions: 100, onChanged: onChanged),
      ),
    ]),
  );
}

class _RecetteItem extends StatelessWidget {
  final String emoji, label, qte, desc;
  final Color color;
  const _RecetteItem(this.emoji, this.label, this.qte, this.desc, this.color);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        Text(desc, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
      ])),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(qte, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ),
    ]),
  );
}

// ─── Bibliothèque de recettes ménagères ──────────────────────────────────────

class _RecetteLibraryPage extends StatelessWidget {
  final String espece;
  final bool sterilise;
  const _RecetteLibraryPage({required this.espece, this.sterilise = false});

  static const _recettes = <String, List<Map<String,dynamic>>>{
    'chien': [
      {
        'nom': 'Riz – Poulet – Légumes',
        'description': 'Recette équilibrée de base, facile à digérer',
        'poids_ref': 10.0,
        'ingredients': [
          {'nom': 'Poulet cuit (sans os)', 'quantite': 150, 'unite': 'g'},
          {'nom': 'Riz blanc cuit',        'quantite': 100, 'unite': 'g'},
          {'nom': 'Carottes cuites',       'quantite': 50,  'unite': 'g'},
          {'nom': 'Courgette cuite',       'quantite': 30,  'unite': 'g'},
          {'nom': 'Huile de colza',        'quantite': 5,   'unite': 'ml'},
        ],
      },
      {
        'nom': 'Bœuf – Patate douce – Épinards',
        'description': 'Riche en protéines et en fer',
        'poids_ref': 10.0,
        'ingredients': [
          {'nom': 'Bœuf haché cuit',    'quantite': 140, 'unite': 'g'},
          {'nom': 'Patate douce cuite', 'quantite': 120, 'unite': 'g'},
          {'nom': 'Épinards cuits',     'quantite': 40,  'unite': 'g'},
          {'nom': 'Huile de lin',       'quantite': 5,   'unite': 'ml'},
        ],
      },
      {
        'nom': 'Poisson – Quinoa – Brocoli',
        'description': 'Riche en oméga-3, idéal pour les chiens sensibles',
        'poids_ref': 10.0,
        'ingredients': [
          {'nom': 'Saumon cuit',      'quantite': 130, 'unite': 'g'},
          {'nom': 'Quinoa cuit',      'quantite': 100, 'unite': 'g'},
          {'nom': 'Brocoli cuit',     'quantite': 60,  'unite': 'g'},
          {'nom': 'Huile de poisson', 'quantite': 3,   'unite': 'ml'},
        ],
      },
    ],
    'chat': [
      {
        'nom': 'Poulet – Foie – Riz',
        'description': 'Recette complète riche en protéines animales',
        'poids_ref': 4.0,
        'ingredients': [
          {'nom': 'Poulet cuit (sans os)',   'quantite': 80, 'unite': 'g'},
          {'nom': 'Foie de poulet cuit',     'quantite': 20, 'unite': 'g'},
          {'nom': 'Riz blanc cuit',          'quantite': 20, 'unite': 'g'},
          {'nom': 'Huile de poisson',        'quantite': 2,  'unite': 'ml'},
        ],
      },
      {
        'nom': 'Thon – Œuf – Courgette',
        'description': 'Riche en taurine naturelle, essentielle pour les chats',
        'poids_ref': 4.0,
        'ingredients': [
          {'nom': 'Thon au naturel égoutté', 'quantite': 70, 'unite': 'g'},
          {'nom': 'Œuf entier cuit',         'quantite': 25, 'unite': 'g'},
          {'nom': 'Courgette cuite',         'quantite': 15, 'unite': 'g'},
          {'nom': 'Huile de saumon',         'quantite': 2,  'unite': 'ml'},
        ],
      },
    ],
  };

  @override
  Widget build(BuildContext context) {
    final recettes = _recettes[espece] ?? _recettes['chien']!;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        title: const Text('Bibliothèque de recettes',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: recettes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _RecetteCard(recette: recettes[i], sterilise: sterilise),
      ),
    );
  }
}

class _RecetteCard extends StatefulWidget {
  final Map<String,dynamic> recette;
  final bool sterilise;
  const _RecetteCard({required this.recette, this.sterilise = false});
  @override
  State<_RecetteCard> createState() => _RecetteCardState();
}

class _RecetteCardState extends State<_RecetteCard> {
  final _poidsCtrl = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() { _poidsCtrl.dispose(); super.dispose(); }

  double get _poidsRef => (widget.recette['poids_ref'] as num).toDouble();

  // Sterilized animals need ~20% fewer calories
  double get _sterilFactor => widget.sterilise ? 0.8 : 1.0;

  double _adapt(double q, double poids) =>
      poids > 0 ? q * (poids / _poidsRef) * _sterilFactor : q * _sterilFactor;

  @override
  Widget build(BuildContext context) {
    final ingredients = (widget.recette['ingredients'] as List<dynamic>).cast<Map<String,dynamic>>();
    final poids = double.tryParse(_poidsCtrl.text.replaceAll(',', '.')) ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.recette['nom'] as String,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A2E))),
                const SizedBox(height: 2),
                Text(widget.recette['description'] as String,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              ])),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF0C5C6C)),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Poids de l\'animal :', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E))),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: TextField(
                  controller: _poidsCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '${_poidsRef.round()} kg',
                    hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400),
                    isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                    filled: true, fillColor: Colors.grey.shade50,
                  ),
                )),
                const SizedBox(width: 6),
                Text('kg  (réf. ${_poidsRef.round()} kg)', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 14),
              const Text('Ingrédients', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
              const SizedBox(height: 8),
              ...ingredients.map((ing) {
                final q = (ing['quantite'] as num).toDouble();
                final adapted = (poids > 0 || widget.sterilise);
                final display = adapted ? _adapt(q, poids).round() : q.round();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Text('• ', style: TextStyle(color: Color(0xFF0C5C6C), fontSize: 16)),
                    Expanded(child: Text(ing['nom'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
                    Text('$display ${ing['unite']}', style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700,
                      color: adapted ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  ]),
                );
              }),
              if (poids > 0 || widget.sterilise) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.07), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    poids > 0
                      ? (widget.sterilise
                          ? 'Quantités adaptées pour ${poids.toStringAsFixed(1)} kg · stérilisé (−20%)'
                          : 'Quantités adaptées pour ${poids.toStringAsFixed(1)} kg')
                      : 'Animal stérilisé : quantités réduites de 20%',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C))),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─── Sélecteur de marque d'aliment ───────────────────────────────────────────

class _MarquePickerSheet extends StatefulWidget {
  final String espece;
  final String phase;
  final void Function(Map<String,dynamic>) onSelected;
  const _MarquePickerSheet({required this.espece, required this.phase, required this.onSelected});
  @override
  State<_MarquePickerSheet> createState() => _MarquePickerSheetState();
}

class _MarquePickerSheetState extends State<_MarquePickerSheet> {
  final _search = TextEditingController();
  List<Map<String,dynamic>> _results = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() { super.initState(); _fetch(''); }
  @override
  void dispose() { _search.dispose(); _debounce?.cancel(); super.dispose(); }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      var query = Supabase.instance.client
          .from('marques_aliments')
          .select('id, marque, gamme, densite_kcal_100g, doses, age_categorie, taille_race, type_aliment')
          .eq('espece', widget.espece);
      if (widget.phase != 'junior') query = query.eq('age_categorie', 'adulte');
      if (q.isNotEmpty) query = query.or('marque.ilike.%$q%,gamme.ilike.%$q%');
      final data = await query.order('marque').limit(50);
      if (mounted) setState(() => _results = (data as List).cast<Map<String,dynamic>>());
    } catch (_) {} finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.of(context).size.height * 0.85,
    decoration: const BoxDecoration(color:Colors.white, borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
    child: Column(children: [
      Center(child:Container(margin:const EdgeInsets.symmetric(vertical:12),width:40,height:4,
        decoration:BoxDecoration(color:Colors.grey.shade300, borderRadius:BorderRadius.circular(2)))),
      const Padding(padding:EdgeInsets.symmetric(horizontal:16,vertical:4),
        child:Text('Choisir un aliment', style:TextStyle(fontFamily:'Galey',fontWeight:FontWeight.w700,fontSize:17,color:Color(0xFF1F2A2E)))),
      const SizedBox(height:8),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),
        child:TextField(
          controller:_search, autofocus:true, onChanged:_onSearch,
          style:const TextStyle(fontFamily:'Galey',fontSize:14),
          decoration:InputDecoration(
            hintText:'Ex : Royal Canin, Orijen, Pro Plan…',
            hintStyle:TextStyle(fontFamily:'Galey',fontSize:13,color:Colors.grey.shade400),
            prefixIcon:const Icon(Icons.search,size:20),
            filled:true, fillColor:Colors.grey.shade100,
            contentPadding:const EdgeInsets.symmetric(vertical:0),
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(30),borderSide:BorderSide.none)),
        )),
      const SizedBox(height:4),
      if (_searching) const LinearProgressIndicator(color:Color(0xFF0C5C6C), minHeight:2),
      Expanded(
        child: _results.isEmpty && !_searching
          ? Center(child:Text(
              _search.text.isEmpty ? 'Aucune marque dans la base' : 'Aucun résultat pour « ${_search.text} »',
              style:const TextStyle(fontFamily:'Galey',color:Colors.grey)))
          : ListView.separated(
              padding: EdgeInsets.only(
                top: 8, bottom: 8 + MediaQuery.of(context).viewInsets.bottom),
              separatorBuilder:(_,__) => const Divider(height:1),
              itemCount:_results.length,
              itemBuilder:(ctx,i) {
                final b = _results[i];
                final densite = (b['densite_kcal_100g'] as num?)?.round();
                final isJunior = b['age_categorie'] == 'junior';
                final taille = b['taille_race'] as String?;
                return ListTile(
                  dense:true,
                  title:Text('${b['marque']} — ${b['gamme']}',
                    style:const TextStyle(fontFamily:'Galey',fontSize:14,fontWeight:FontWeight.w600,color:Color(0xFF1F2A2E))),
                  subtitle:Wrap(spacing:8, children:[
                    if (densite != null) Text('$densite kcal/100g',
                      style:TextStyle(fontFamily:'Galey',fontSize:12,color:Colors.grey.shade500)),
                    if (isJunior) Container(
                      padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                      decoration:BoxDecoration(color:const Color(0xFFFFF3CD),borderRadius:BorderRadius.circular(6)),
                      child:const Text('Junior',style:TextStyle(fontFamily:'Galey',fontSize:10,color:Color(0xFF856404)))),
                    if (taille != null && taille != 'toutes') Container(
                      padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                      decoration:BoxDecoration(color:Colors.grey.shade100,borderRadius:BorderRadius.circular(6)),
                      child:Text(taille,style:TextStyle(fontFamily:'Galey',fontSize:10,color:Colors.grey.shade600))),
                  ]),
                  onTap:() { Navigator.pop(context); widget.onSelected(b); },
                );
              },
            ),
      ),
    ]),
  );
}

// ─── Breed picker sheet (modal bottom sheet) ──────────────────────────────────

class _BreedPickerSheet extends StatefulWidget {
  final List<String> breeds;
  final String label;
  final String current;
  const _BreedPickerSheet({required this.breeds, required this.label, required this.current});
  @override State<_BreedPickerSheet> createState() => _BreedPickerSheetState();
}

class _BreedPickerSheetState extends State<_BreedPickerSheet> {
  late List<String> _filtered;
  final _searchCtrl = TextEditingController();

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
              Expanded(child: Text(widget.label,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17))),
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
                      color: selected ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  trailing: selected ? const Icon(Icons.check, color: Color(0xFF0C5C6C), size: 18) : null,
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
