import 'dart:convert';
import 'dart:io';
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

  const AnimalFichePage({super.key, this.animalId, this.initialData, this.preselectedEspece});

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
    _tabs = TabController(length: 3, vsync: this);
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

      final uid = FirebaseAuth.instance.currentUser!.uid;
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
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg']);
    if (result?.files.single.path != null) {
      setState(() => _saving = true);
      try {
        final url = await _uploadFile(File(result!.files.single.path!), 'pedigrees');
        setState(() { _pedigreeUrl = url; _saving = false; });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedigree chargé ✓')));
      } catch (e) {
        setState(() => _saving = false);
      }
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
          if (_saving)
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
          indicatorColor: _green,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Identité'), Tab(text: 'Suivi Repro'), Tab(text: 'Carnet Santé')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _IdentiteTab(this),
          _SuiviReproTab(animalId: widget.animalId, espece: _espece, sexe: _sexe),
          _CarnetSanteTab(animalId: widget.animalId),
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
                _card([
                  _pedigreeSection(context),
                  _genealogieSection(context),
                ]),
                const SizedBox(height: 12),
                _contactsUrgenceSection(context),
                const SizedBox(height: 12),
                _card([_field('Notes', s._notesCtrl, maxLines: 3)]),
              ],
            ),
          ),
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
                Icon(s._pedigreeUrl != null ? Icons.check_circle_outline : Icons.upload_file_outlined,
                    size: 18, color: s._pedigreeUrl != null ? const Color(0xFF6E9E57) : const Color(0xFF0C5C6C)),
                const SizedBox(width: 8),
                Text(s._pedigreeUrl != null ? 'Document chargé ✓' : cfg.docLabel,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        color: s._pedigreeUrl != null ? const Color(0xFF6E9E57) : const Color(0xFF6F767B))),
              ]),
            ),
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
                  icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFF0C5C6C)),
                  onPressed: () => launchUrl(Uri.parse(doc['url']!), mode: LaunchMode.externalApplication),
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

// ─── Onglet Suivi Repro ───────────────────────────────────────────────────────

class _SuiviReproTab extends StatelessWidget {
  final String? animalId;
  final String espece;
  final String sexe;
  const _SuiviReproTab({this.animalId, required this.espece, required this.sexe});

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
            _ChaleursTab(animalId: animalId!, espece: espece),
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

        await supa.from('agenda_events').upsert({
          'uid':          uid,
          'titre':        'Mise-bas prévue — $animalNom',
          'type':         'mise_bas',
          'date_debut':   datePrevue,
          'animal_id':    int.tryParse(widget.animalId),
          'notes':        'Gestation confirmée',
          'gestation_id': id,
        }, onConflict: 'gestation_id');
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

class _PoidsTab extends StatefulWidget {
  final String animalId;
  const _PoidsTab({required this.animalId});
  @override State<_PoidsTab> createState() => _PoidsTabState();
}
class _PoidsTabState extends State<_PoidsTab> {
  int _refreshKey = 0;

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

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d    = docs[i];
              final raw  = d['date'] as String?;
              final date = raw != null && raw.isNotEmpty
                  ? (DateTime.tryParse(raw) != null
                      ? DateFormat('dd/MM/yyyy').format(DateTime.parse(raw))
                      : raw)
                  : '';
              final val = vals[i];
              final pct = maxPoids > 0 ? val / maxPoids : 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(date, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                    Row(children: [
                      Text('${val.toStringAsFixed(1)} kg',
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
  const _ChaleursTab({required this.animalId, required this.espece});
  @override State<_ChaleursTab> createState() => _ChaleursTabState();
}

class _ChaleursTabState extends State<_ChaleursTab> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)));
    final nextHeat = _nextHeatDate(_data, widget.espece);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: const Color(0xFF6E9E57),
        onPressed: () async {
          await showDialog(context: context, builder: (_) =>
              _AddChaleursDialog(animalId: widget.animalId, espece: widget.espece));
          _load();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (nextHeat != null)
            _NextHeatBanner(nextHeat: nextHeat, espece: widget.espece),
          if (_data.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.only(top: 40),
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
                    _AddChaleursDialog(animalId: widget.animalId, espece: widget.espece, existing: d));
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
  final Map<String, dynamic>? existing;
  const _AddChaleursDialog({required this.animalId, required this.espece, this.existing});
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
      _DD('Date début *', _date, (d) => setState(() => _date = d)),
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
        final interval = _intervalChaleursJours(widget.espece);
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
