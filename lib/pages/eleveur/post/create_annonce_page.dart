import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/utils/reproducteurs.dart';
import 'package:PetsMatch/widgets/inline_video.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class CreateAnnoncePage extends StatefulWidget {
  final String? annonceId;
  final Map<String, dynamic>? initialData;
  const CreateAnnoncePage({super.key, this.annonceId, this.initialData});

  @override
  State<CreateAnnoncePage> createState() => _CreateAnnoncePageState();
}

num? _toNum(dynamic v) => v is num ? v : v is String ? num.tryParse(v) : null;

class _CreateAnnoncePageState extends State<CreateAnnoncePage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  // ── Type ──────────────────────────────────────────────────────────────────────
  String _type = 'portee';
  String _typeVente = 'vente';
  // Vente / Adoption / Don (ou formule équine) retenu quand l'objet est une saillie / un retraité
  String _cessionMemo = 'vente';

  // ── Étapes : 1 Annonce et animal · 2 Santé et origines · 3 Publication
  int _etape = 1;
  static const _etapes = ['Annonce et animal', 'Santé et origines', 'Publication'];
  int? _dureePlan;
  // Père : mes animaux / réseau PetsMatch / saisie manuelle
  String _pereSource = 'mien';
  String? _pereEleveurReseau;
  // Sauvegarde automatique (nouvelle annonce) sur cet appareil
  Timer? _autoSaveTimer;
  String? _dernierJson;
  String? _autoSaveA;
  Map<String, dynamic>? _brouillonLocal;
  static const _dark = Color(0xFF1F2A2E);
  bool get _estBrouillon => widget.initialData?['statut'] == 'brouillon';

  // ── Espèce & Race ─────────────────────────────────────────────────────────────
  String _espece = 'chien';
  final _especeAutreCtrl = TextEditingController();
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
  String _prixUnite = 'total'; // 'total' | 'mois' | 'semaine' | 'convenir'
  String _statut = 'disponible';
  int _dureeAnnonce = 30;

  // ── Cheval (annonce équine) ──────────────────────────────────────────────────
  static const _kNiveauxEquide = [
    'Débutant', 'Galops 1-4', 'Galops 5-7', 'Club', 'Amateur', 'Pro', 'Tous niveaux',
  ];
  String _niveauEquide = '';
  final _palmaresCtrl = TextEditingController();
  final _isoCtrl = TextEditingController();
  final _idrCtrl = TextEditingController();
  final _iccCtrl = TextEditingController();
  String? _videoMonteUrl;
  String? _videoLibreUrl;
  bool _uploadingVideo = false;

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
  final _mereCouleurYeuxCtrl = TextEditingController();
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
  final _pereCouleurYeuxCtrl = TextEditingController();
  final _pereDescCtrl   = TextEditingController();
  String _pereRegistre = '';

  // ── Pedigree ──────────────────────────────────────────────────────────────────
  String _registreType = '';
  final _numRegistreCtrl  = TextEditingController();
  final _clubPedigreeCtrl = TextEditingController();
  final _studbookCtrl     = TextEditingController();

  // ── Identification légale (champs obligatoires Code rural) ────────────────────
  final _numIdentCtrl    = TextEditingController(); // animal compagnon chien/chat
  final _numSIRECtrl     = TextEditingController(); // équidé — SIRE
  final _numPasseportCtrl = TextEditingController(); // équidé — passeport

  // ── Santé ─────────────────────────────────────────────────────────────────────
  bool _vaccines       = false;
  bool _vermifuge      = false;
  bool _identification = false;
  bool _bilanSante     = false;
  int  _semaines       = 8;

  // ── Portée prix ───────────────────────────────────────────────────────────────
  final _prixMinPorteeCtrl = TextEditingController();
  final _prixMaxPorteeCtrl = TextEditingController();

  // ── Animal individuel / Étalon / Retraité ────────────────────────────────────
  String?   _etalonAnimalId;
  String?   _retraiteAnimalNom; // nom affiché dans le bouton picker retraite
  String    _sexe = 'male';
  final _couleurCtrl = TextEditingController();
  final _couleurYeuxCtrl = TextEditingController();
  DateTime? _dateNaissanceAnimal;
  bool _sterilise = false;
  final _sailliePrixCtrl = TextEditingController();
  final _saillieCondCtrl = TextEditingController();
  final _saillieGenetiqueCtrl = TextEditingController();

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
    if (!const {'saillie', 'retraite'}.contains(_typeVente)) _cessionMemo = _typeVente;
    _chargerDureePlan();
    if (widget.annonceId == null) {
      _lireBrouillonLocal();
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 4), (_) => _sauvegardeAuto());
    }
  }

  Future<void> _chargerDureePlan() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final cfg = await PlanService.getConfig(await PlanService.getPlanCode(uid));
      if (mounted) setState(() => _dureePlan = cfg.dureeDays);
    } catch (_) {}
  }

  String get _cleBrouillon => 'pm_annonce_brouillon_${FirebaseAuth.instance.currentUser?.uid ?? ''}';

  /// Champs sérialisables (sauvegarde automatique sur l'appareil).
  Map<String, dynamic> _versMap() => {
    'type': _type, 'type_vente': _typeVente, 'espece': _espece, 'espece_autre': _especeAutreCtrl.text,
    'race': _raceCtrl.text, 'titre': _titreCtrl.text, 'description': _descCtrl.text, 'prix': _prixCtrl.text,
    'prix_negociable': _prixNegociable, 'prix_unite': _prixUnite,
    'date_naissance': _dateNaissance?.toIso8601String(), 'nombre_bebes': _nombreBebes, 'animaux_portee': _animauxPortee,
    'mere_animal_id': _mereAnimalId, 'mere_photo_url': _merePhotoUrl, 'mere_nom': _mereNomCtrl.text, 'mere_puce': _merePuceCtrl.text,
    'mere_race': _mereRaceCtrl.text, 'mere_couleur': _mereCouleurCtrl.text, 'mere_couleur_yeux': _mereCouleurYeuxCtrl.text,
    'mere_description': _mereDescCtrl.text, 'mere_registre': _mereRegistre,
    'pere_animal_id': _pereAnimalId, 'pere_photo_url': _perePhotoUrl, 'pere_nom': _pereNomCtrl.text, 'pere_puce': _perePuceCtrl.text,
    'pere_race': _pereRaceCtrl.text, 'pere_couleur': _pereCouleurCtrl.text, 'pere_couleur_yeux': _pereCouleurYeuxCtrl.text,
    'pere_description': _pereDescCtrl.text, 'pere_registre': _pereRegistre, 'pere_source': _pereSource, 'pere_eleveur_reseau': _pereEleveurReseau,
    'registre_type': _registreType, 'numero_registre': _numRegistreCtrl.text, 'club_pedigree': _clubPedigreeCtrl.text, 'studbook': _studbookCtrl.text,
    'vaccines': _vaccines, 'vermifuge': _vermifuge, 'identification': _identification, 'bilan_sante': _bilanSante, 'semaines': _semaines,
    'prix_min_portee': _prixMinPorteeCtrl.text, 'prix_max_portee': _prixMaxPorteeCtrl.text,
    'etalon_animal_id': _etalonAnimalId, 'retraite_nom': _retraiteAnimalNom, 'sexe': _sexe, 'couleur': _couleurCtrl.text,
    'couleur_yeux': _couleurYeuxCtrl.text, 'date_naissance_animal': _dateNaissanceAnimal?.toIso8601String(), 'sterilise': _sterilise,
    'saillie_prix': _sailliePrixCtrl.text, 'saillie_conditions': _saillieCondCtrl.text, 'saillie_genetique': _saillieGenetiqueCtrl.text,
    'num_identification': _numIdentCtrl.text, 'num_sire': _numSIRECtrl.text, 'num_passeport_equin': _numPasseportCtrl.text,
    'niveau_recommande': _niveauEquide, 'palmares': _palmaresCtrl.text, 'indice_iso': _isoCtrl.text, 'indice_idr': _idrCtrl.text,
    'indice_icc': _iccCtrl.text, 'video_monte_url': _videoMonteUrl, 'video_libre_url': _videoLibreUrl,
    'photos': _photosUrls, 'photos_locales': _photosFiles.map((f) => f.path).toList(), 'etape': _etape,
  };

  void _depuisMap(Map<String, dynamic> d) {
    String t(String k) => (d[k] ?? '').toString();
    _type = t('type').isEmpty ? 'portee' : t('type');
    _typeVente = t('type_vente').isEmpty ? 'vente' : t('type_vente');
    if (!const {'saillie', 'retraite'}.contains(_typeVente)) _cessionMemo = _typeVente;
    _espece = t('espece').isEmpty ? _espece : t('espece');
    _especeAutreCtrl.text = t('espece_autre'); _raceCtrl.text = t('race'); _titreCtrl.text = t('titre');
    _descCtrl.text = t('description'); _prixCtrl.text = t('prix');
    _prixNegociable = d['prix_negociable'] == true; _prixUnite = t('prix_unite').isEmpty ? 'total' : t('prix_unite');
    _dateNaissance = DateTime.tryParse(t('date_naissance'));
    _nombreBebes = (d['nombre_bebes'] as num?)?.toInt() ?? 1;
    _animauxPortee = List<Map<String, dynamic>>.from((d['animaux_portee'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []);
    _mereAnimalId = d['mere_animal_id'] as String?; _merePhotoUrl = d['mere_photo_url'] as String?;
    _mereNomCtrl.text = t('mere_nom'); _merePuceCtrl.text = t('mere_puce'); _mereRaceCtrl.text = t('mere_race');
    _mereCouleurCtrl.text = t('mere_couleur'); _mereCouleurYeuxCtrl.text = t('mere_couleur_yeux');
    _mereDescCtrl.text = t('mere_description'); _mereRegistre = t('mere_registre');
    _pereAnimalId = d['pere_animal_id'] as String?; _perePhotoUrl = d['pere_photo_url'] as String?;
    _pereNomCtrl.text = t('pere_nom'); _perePuceCtrl.text = t('pere_puce'); _pereRaceCtrl.text = t('pere_race');
    _pereCouleurCtrl.text = t('pere_couleur'); _pereCouleurYeuxCtrl.text = t('pere_couleur_yeux');
    _pereDescCtrl.text = t('pere_description'); _pereRegistre = t('pere_registre');
    _pereSource = t('pere_source').isEmpty ? 'mien' : t('pere_source'); _pereEleveurReseau = d['pere_eleveur_reseau'] as String?;
    _registreType = t('registre_type'); _numRegistreCtrl.text = t('numero_registre'); _clubPedigreeCtrl.text = t('club_pedigree');
    _studbookCtrl.text = t('studbook');
    _vaccines = d['vaccines'] == true; _vermifuge = d['vermifuge'] == true; _identification = d['identification'] == true;
    _bilanSante = d['bilan_sante'] == true; _semaines = (d['semaines'] as num?)?.toInt() ?? 8;
    _prixMinPorteeCtrl.text = t('prix_min_portee'); _prixMaxPorteeCtrl.text = t('prix_max_portee');
    _etalonAnimalId = d['etalon_animal_id'] as String?; _retraiteAnimalNom = d['retraite_nom'] as String?;
    _sexe = t('sexe').isEmpty ? 'male' : t('sexe'); _couleurCtrl.text = t('couleur'); _couleurYeuxCtrl.text = t('couleur_yeux');
    _dateNaissanceAnimal = DateTime.tryParse(t('date_naissance_animal')); _sterilise = d['sterilise'] == true;
    _sailliePrixCtrl.text = t('saillie_prix'); _saillieCondCtrl.text = t('saillie_conditions'); _saillieGenetiqueCtrl.text = t('saillie_genetique');
    _numIdentCtrl.text = t('num_identification'); _numSIRECtrl.text = t('num_sire'); _numPasseportCtrl.text = t('num_passeport_equin');
    _niveauEquide = t('niveau_recommande'); _palmaresCtrl.text = t('palmares');
    _isoCtrl.text = t('indice_iso'); _idrCtrl.text = t('indice_idr'); _iccCtrl.text = t('indice_icc');
    _videoMonteUrl = d['video_monte_url'] as String?; _videoLibreUrl = d['video_libre_url'] as String?;
    _photosUrls = List<String>.from((d['photos'] as List?) ?? []);
    // Photos prises sur l'appareil : seulement celles encore présentes
    _photosFiles = ((d['photos_locales'] as List?) ?? []).map((p) => File(p.toString())).where((f) => f.existsSync()).toList();
    _etape = (d['etape'] as num?)?.toInt() ?? 1;
  }

  Future<void> _lireBrouillonLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cleBrouillon);
      if (raw != null && mounted) setState(() => _brouillonLocal = Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}
  }

  Future<void> _sauvegardeAuto() async {
    if (!mounted || _brouillonLocal != null || _saving) return;
    final json = jsonEncode(_versMap());
    if (_dernierJson == null) { _dernierJson = json; return; } // état initial : rien à sauvegarder
    if (json == _dernierJson) return;
    _dernierJson = json;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cleBrouillon, jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'data': jsonDecode(json)}));
      if (mounted) setState(() => _autoSaveA = DateFormat('HH:mm').format(DateTime.now()));
    } catch (_) {}
  }

  Future<void> _oublierBrouillonLocal() async {
    try { (await SharedPreferences.getInstance()).remove(_cleBrouillon); } catch (_) {}
  }

  void _loadInitialData() {
    final d = widget.initialData;
    if (d == null) return;
    _type      = d['type'] ?? 'portee';
    _typeVente = d['type_vente'] ?? d['typeVente'] ?? 'vente';
    _espece    = d['espece'] ?? 'chien';
    _especeAutreCtrl.text = d['espece_autre'] ?? '';
    _raceCtrl.text = d['race'] ?? '';
    _photosUrls = List<String>.from(d['photos'] ?? []);
    _titreCtrl.text = d['titre'] ?? '';
    _descCtrl.text  = d['description'] ?? '';
    _prixCtrl.text  = _toNum(d['prix'])?.toStringAsFixed(0) ?? '';
    _prixNegociable = d['prix_negociable'] ?? d['prixNegociable'] ?? false;
    _statut = d['statut'] ?? 'disponible';
    // Date naissance portée : Timestamp (Firestore) ou String ISO (Supabase)
    final dnRaw = d['date_naissance'] ?? d['dateNaissance'];
    if (dnRaw is Timestamp) _dateNaissance = dnRaw.toDate();
    else if (dnRaw is String && dnRaw.isNotEmpty) _dateNaissance = DateTime.tryParse(dnRaw);
    _nombreBebes = _toNum(d['nombre_bebes'] ?? d['nombreBebes'])?.toInt() ?? 1;
    _animauxPortee = List<Map<String, dynamic>>.from(d['animaux_portee'] ?? d['animauxPortee'] ?? []);
    _mereAnimalId  = d['mere_animal_id'] ?? d['mereAnimalId'];
    _merePhotoUrl  = d['mere_photo_url'] ?? d['merePhotoUrl'];
    _mereNomCtrl.text     = d['mere_nom']         ?? d['mereNom']         ?? '';
    _merePuceCtrl.text    = d['mere_puce']         ?? d['merePuce']        ?? '';
    _mereRaceCtrl.text    = d['mere_race']         ?? d['mereRace']        ?? '';
    _mereCouleurCtrl.text = d['mere_couleur']      ?? d['mereCouleur']     ?? '';
    _mereCouleurYeuxCtrl.text = d['mere_couleur_yeux'] ?? '';
    _mereDescCtrl.text    = d['mere_description']  ?? d['mereDescription'] ?? '';
    _mereRegistre = d['mere_registre'] ?? d['mereRegistre'] ?? '';
    _pereAnimalId  = d['pere_animal_id'] ?? d['pereAnimalId'];
    _perePhotoUrl  = d['pere_photo_url'] ?? d['perePhotoUrl'];
    _pereNomCtrl.text     = d['pere_nom']         ?? d['pereNom']         ?? '';
    _perePuceCtrl.text    = d['pere_puce']         ?? d['perePuce']        ?? '';
    _pereRaceCtrl.text    = d['pere_race']         ?? d['pereRace']        ?? '';
    _pereCouleurCtrl.text = d['pere_couleur']      ?? d['pereCouleur']     ?? '';
    _pereCouleurYeuxCtrl.text = d['pere_couleur_yeux'] ?? '';
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
    _semaines = _toNum(d['semaines'])?.toInt() ?? 8;
    _prixMinPorteeCtrl.text = _toNum(d['prix_min_portee'] ?? d['prixMinPortee'])?.toInt().toString() ?? '';
    _prixMaxPorteeCtrl.text = _toNum(d['prix_max_portee'] ?? d['prixMaxPortee'])?.toInt().toString() ?? '';
    _etalonAnimalId   = d['etalon_animal_id'] ?? d['etalonAnimalId'];
    _sexe = d['sexe'] ?? 'male';
    _couleurCtrl.text     = d['couleur'] ?? '';
    _couleurYeuxCtrl.text = d['couleur_yeux'] ?? '';
    _sailliePrixCtrl.text = (d['saillie_prix'] ?? d['sailliePrix'])?.toString() ?? '';
    _saillieCondCtrl.text = d['saillie_conditions'] ?? d['saillieConditions'] ?? '';
    _saillieGenetiqueCtrl.text = d['saillie_genetique'] ?? d['saillieGenetique'] ?? '';
    // Date naissance animal : Timestamp (Firestore) ou String ISO (Supabase)
    final dnaRaw = d['date_naissance_animal'] ?? d['dateNaissanceAnimal'];
    if (dnaRaw is Timestamp) _dateNaissanceAnimal = dnaRaw.toDate();
    else if (dnaRaw is String && dnaRaw.isNotEmpty) _dateNaissanceAnimal = DateTime.tryParse(dnaRaw);
    _sterilise = d['sterilise'] ?? false;
    _numIdentCtrl.text    = d['num_identification'] ?? '';
    _numSIRECtrl.text     = d['num_sire'] ?? '';
    _numPasseportCtrl.text = d['num_passeport_equin'] ?? '';
    _prixUnite     = d['prix_unite'] ?? d['prixUnite'] ?? 'total';
    _niveauEquide  = d['niveau_recommande'] ?? d['niveauRecommande'] ?? '';
    _palmaresCtrl.text = d['palmares'] ?? '';
    _isoCtrl.text  = _toNum(d['indice_iso'])?.toInt().toString() ?? '';
    _idrCtrl.text  = _toNum(d['indice_idr'])?.toInt().toString() ?? '';
    _iccCtrl.text  = _toNum(d['indice_icc'])?.toInt().toString() ?? '';
    _videoMonteUrl = (d['video_monte_url'] as String?)?.isNotEmpty == true ? d['video_monte_url'] : null;
    _videoLibreUrl = (d['video_libre_url'] as String?)?.isNotEmpty == true ? d['video_libre_url'] : null;
    // Brouillon repris : le statut de publication part de « Disponible »
    if (_statut == 'brouillon') _statut = 'disponible';
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _scroll.dispose();
    _raceFocusNode.dispose();
    for (final c in [
      _especeAutreCtrl,
      _raceCtrl, _titreCtrl, _descCtrl, _prixCtrl,
      _mereNomCtrl, _merePuceCtrl, _mereRaceCtrl, _mereCouleurCtrl, _mereCouleurYeuxCtrl, _mereDescCtrl,
      _pereNomCtrl, _perePuceCtrl, _pereRaceCtrl, _pereCouleurCtrl, _pereCouleurYeuxCtrl, _pereDescCtrl,
      _numRegistreCtrl, _clubPedigreeCtrl, _studbookCtrl, _couleurCtrl, _couleurYeuxCtrl,
      _sailliePrixCtrl, _saillieCondCtrl, _saillieGenetiqueCtrl, _prixMinPorteeCtrl, _prixMaxPorteeCtrl,
      _numIdentCtrl, _numSIRECtrl, _numPasseportCtrl,
      _palmaresCtrl, _isoCtrl, _idrCtrl, _iccCtrl,
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

  Future<ImageSource?> _showPhotoSourceSheet() => showModalBottomSheet<ImageSource>(
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
        const Text('Ajouter une photo',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 16),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: const Color(0xFF6E9E57).withValues(alpha: 0.07),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFF6E9E57).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF6E9E57)),
          ),
          title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          subtitle: const Text('Ouvrir la caméra', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        const SizedBox(height: 10),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: const Color(0xFF0C5C6C).withValues(alpha: 0.07),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.photo_library_outlined, color: Color(0xFF0C5C6C)),
          ),
          title: const Text('Choisir depuis la galerie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          subtitle: const Text('Sélectionner une photo existante', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
      ]),
    ),
  );

  Future<File?> _pickAndCrop({ImageSource source = ImageSource.gallery}) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
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
    if (_photosUrls.length + _photosFiles.length >= 5) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 5 photos', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    final source = await _showPhotoSourceSheet();
    if (source == null) return;
    final f = await _pickAndCrop(source: source);
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
      _mereCouleurYeuxCtrl.text = r['couleurYeux'] ?? '';
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
      _pereCouleurYeuxCtrl.text = r['couleurYeux'] ?? '';
      _pereDescCtrl.text    = r['description']    ?? '';
      _perePhotoUrl    = r['photoUrl'];
      _perePhotoFile   = null;
    });
  }

  Future<void> _pickEtalon() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AnimalPickerSheet(espece: _espece, sexeFilter: 'male', reproducteursSeulement: true),
    );
    if (r != null && mounted) setState(() {
      _etalonAnimalId = r['id'];
      _sexe = 'male';
      _couleurCtrl.text = r['couleur'] ?? '';
      _couleurYeuxCtrl.text = r['couleurYeux'] ?? '';
      _numIdentCtrl.text = r['identification'] ?? '';
      if (r['photoUrl'] != null) { _photosUrls = [r['photoUrl']]; _photosFiles = []; }
      final dn = r['dateNaissance'] as Timestamp?;
      if (dn != null) _dateNaissanceAnimal = dn.toDate();
      if (_titreCtrl.text.isEmpty && (r['nom'] ?? '').isNotEmpty) {
        _titreCtrl.text = '${r['nom']} — Saillie ${_raceCtrl.text}'.trim();
      }
      if (_descCtrl.text.isEmpty && (r['description'] ?? '').isNotEmpty) {
        _descCtrl.text = r['description'];
      }
      // Pré-remplir section Père avec les infos de l'étalon
      _pereAnimalId         = r['id'];
      _pereNomCtrl.text     = r['nom']            ?? '';
      _perePuceCtrl.text    = r['identification'] ?? '';
      _pereRaceCtrl.text    = r['race']           ?? '';
      _perePhotoUrl         = r['photoUrl'] as String?;
      // Pedigree étalon → section Père
      final lof     = (r['pedigree_lof']  ?? '').toString();
      final club    = (r['club_registre'] ?? '').toString();
      if (lof.isNotEmpty)  _pereRegistre = lof;
      if (club.isNotEmpty) _clubPedigreeCtrl.text = club;
    });
  }

  Future<void> _pickRetraite() async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AnimalPickerSheet(espece: _espece),
    );
    if (r != null && mounted) setState(() {
      _etalonAnimalId       = r['id'];
      _retraiteAnimalNom    = r['nom'] as String?;
      _sexe                 = (r['sexe'] as String?)?.isNotEmpty == true ? r['sexe'] : 'male';
      _couleurCtrl.text     = r['couleur']  ?? '';
      _couleurYeuxCtrl.text = r['couleurYeux'] ?? '';
      _numIdentCtrl.text    = r['identification'] ?? '';
      // Auto-remplir espèce et race depuis l'animal
      if ((r['espece'] as String?)?.isNotEmpty == true) _espece = r['espece'];
      _raceCtrl.text = r['race'] ?? '';
      if (r['photoUrl'] != null) { _photosUrls = [r['photoUrl']]; _photosFiles = []; }
      final dn = r['dateNaissance'] as Timestamp?;
      if (dn != null) _dateNaissanceAnimal = dn.toDate();
      if (_titreCtrl.text.isEmpty && (r['nom'] ?? '').isNotEmpty) {
        _titreCtrl.text = '${r['nom']} — Retraité d\'élevage';
      }
      if (_descCtrl.text.isEmpty && (r['description'] ?? '').isNotEmpty) {
        _descCtrl.text = r['description'];
      }
      // Pré-remplir pedigree depuis l'animal
      final lof  = (r['pedigree_lof']  ?? '').toString();
      final club = (r['club_registre'] ?? '').toString();
      if (lof.isNotEmpty)  _registreType = lof;
      if (club.isNotEmpty) _clubPedigreeCtrl.text = club;
    });
  }

  // ── Upload ────────────────────────────────────────────────────────────────────

  Future<String> _uploadFile(File file, String folder) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    return uploadPhoto(file, '$folder/$uid/$name');
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  void _showQuotaGate(String planCode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuotaGateSheet(
        // Palier au-dessus du plan actuel — null si déjà Premium (le plus
        // élevé), auquel cas il n'y a pas d'upgrade à proposer.
        nextPlanLabel: planCode == 'premium' ? null : planCode == 'pro' ? 'Premium' : 'Pro',
        onBuyExtra: () async {
          Navigator.pop(context);
          final uri = Uri.parse('${PlanService.kWebsiteUrl}/abonnement?buy=annonce_sup');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        onUpgradePro: () {
          Navigator.pop(context);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AbonnementPage()));
        },
      ),
    );
  }

  /// Contrôles par étape (mêmes règles légales qu'à la publication).
  String? _erreurEtape(int n) {
    final chienChat = _espece == 'chien' || _espece == 'chat';
    if (n == 1) {
      if (_raceCtrl.text.trim().isEmpty && _titreCtrl.text.trim().isEmpty) return 'Veuillez saisir une race.';
      if (chienChat && _type == 'portee' && _dateNaissance == null) return 'Obligatoire : date de naissance de la portée.';
    }
    if (n == 2) {
      if (_espece == 'cheval' && _numSIRECtrl.text.trim().isEmpty) return 'Obligatoire : numéro SIRE pour tout équidé (Décret n°2013-879).';
      if (chienChat && _type != 'portee' && _numIdentCtrl.text.trim().isEmpty) return 'Obligatoire : numéro d’identification de l’animal (puce ou tatouage) — art. L212-10.';
      if (chienChat && _type == 'portee' && _merePuceCtrl.text.trim().isEmpty) return 'Obligatoire : identification (puce ICAD ou tatouage) de la mère — art. L214-8.';
    }
    return null;
  }

  void _allerA(int n) {
    for (var k = _etape; k < n; k++) {
      final err = _erreurEtape(k);
      if (err != null) {
        setState(() => _etape = k);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red.shade700));
        return;
      }
    }
    setState(() => _etape = n);
  }

  Future<void> _save({bool brouillon = false}) async {
    if (brouillon) return _enregistrer(brouillon: true);
    return _enregistrer();
  }

  Future<void> _enregistrer({bool brouillon = false}) async {
    if (brouillon) {
      if (_raceCtrl.text.trim().isEmpty && _titreCtrl.text.trim().isEmpty && _descCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Renseignez au moins la race pour enregistrer un brouillon.', style: TextStyle(fontFamily: 'Galey'))));
        return;
      }
    } else if (_raceCtrl.text.trim().isEmpty && _titreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez saisir une race ou un titre',
              style: TextStyle(fontFamily: 'Galey'))));
      return;
    }

    // ── Champs légaux obligatoires (Code rural français) ──────────────────
    if (!brouillon && _photosFiles.isEmpty && _photosUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Au moins une photo est obligatoire',
            style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    if (!brouillon && (_espece == 'chien' || _espece == 'chat') && _type == 'portee') {
      if (_merePuceCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Obligatoire : identification (puce ICAD ou tatouage) de la mère',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red.shade700));
        return;
      }
      if (_dateNaissance == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Obligatoire : date de naissance de la portée',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red.shade700));
        return;
      }
    }
    if (!brouillon && _espece == 'cheval' && _numSIRECtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Obligatoire : numéro SIRE pour tout équidé (Décret n°2013-879)',
            style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.red.shade700));
      return;
    }
    if (!brouillon && (_espece == 'chien' || _espece == 'chat') && _type != 'portee' &&
        _numIdentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Obligatoire : numéro d\'identification de l\'animal (puce/tatouage) — art. L212-10',
            style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.red.shade700));
      return;
    }

    // ── Seuls les éleveurs validés peuvent publier (anti-opportunistes) ──────
    // Requête directe (pas de champ statut_pro mis en cache dans User_Info)
    // pour avoir la donnée la plus fraîche au moment de la publication.
    final activeProfId = User_Info.activeProfileId;
    if (!brouillon && activeProfId.isNotEmpty) {
      final prof = await Supabase.instance.client
          .from('user_profiles_complet')
          .select('statut_pro')
          .eq('id', activeProfId)
          .maybeSingle();
      final statutPro = (prof?['statut_pro'] ?? '').toString().toLowerCase();
      if (statutPro != 'actif' && statutPro != 'validated') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                '⏳ Votre dossier éleveur est en cours de validation. Vous pourrez publier des annonces dès qu\'il sera approuvé.',
                style: TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.orange.shade700));
        }
        return;
      }
    }

    setState(() => _saving = true);

    // ── Quota check (nouvelle annonce ou brouillon publié) ───────────────────
    if (!brouillon && (widget.annonceId == null || _estBrouillon)) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final planCode = await PlanService.getPlanCode(uid);
        final config = await PlanService.getConfig(planCode);
        if (config.maxAnnonces != -1) {
          final count = await PlanService.countActiveAnnonces(uid);
          if (count >= config.maxAnnonces) {
            if (mounted) {
              setState(() => _saving = false);
              _showQuotaGate(planCode);
            }
            return;
          }
        }
        // ── Limite portées actives (plan-aware) ─────────────────────────────
        if (_type == 'portee') {
          final maxPortees = planCode == 'premium' ? -1 : planCode == 'pro' ? 5 : 2;
          if (maxPortees != -1) {
            final rows = await Supabase.instance.client
                .from('annonces')
                .select('id')
                .eq('uid_eleveur', uid)
                .eq('type', 'portee')
                .neq('statut', 'archivée');
            if ((rows as List).length >= maxPortees) {
              if (mounted) {
                setState(() => _saving = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                    'Limite atteinte : $maxPortees portée${maxPortees > 1 ? 's' : ''} active${maxPortees > 1 ? 's' : ''} sur votre plan. '
                    'Archivez une portée ou passez à Premium pour des portées illimitées.',
                    style: const TextStyle(fontFamily: 'Galey'),
                  ),
                  backgroundColor: Colors.red.shade700,
                  duration: const Duration(seconds: 5),
                ));
              }
              return;
            }
          }
        }
      } catch (_) {}
    }

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

      // Photos bébés inline — pour tous les animaux (liés ou non), upload les chemins locaux
      final animauxSaved = <Map<String, dynamic>>[];
      for (final animal in _animauxPortee) {
        final localPaths = List<String>.from(animal['photos'] ?? []);
        final uploaded = <String>[];
        for (final p in localPaths) {
          uploaded.add(p.startsWith('http') ? p : await _uploadFile(File(p), 'annonces/animaux'));
        }
        animauxSaved.add({...animal, 'photos': uploaded});
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      // Le profil actif directement, plutôt que "mon profil principal" par
      // uid : pour un cogérant (elevage_cogerants), l'un et l'autre diffèrent
      // — sans ça l'annonce se serait publiée avec le nom/ville du cogérant
      // au lieu de ceux de l'élevage. userRow['uid'] redonne ensuite le vrai
      // uid du gérant pour uid_eleveur plus bas.
      final activeProfileId = User_Info.activeProfileId;
      final userRow = activeProfileId.isNotEmpty
          ? await Supabase.instance.client.from('user_profiles_complet').select().eq('id', activeProfileId).single()
          : await Supabase.instance.client.from('user_profiles_complet').select().eq('uid', uid).eq('is_main', true).single();
      final ownerUid = (userRow['uid'] as String?) ?? uid;

      final nomEleveur = (userRow['nom'] as String?)?.isNotEmpty == true
          ? userRow['nom'] as String
          : userRow['firstname'] as String? ?? '';
      final villeEleveur =
          (userRow['ville_pro'] as String?) ?? (userRow['ville'] as String?) ?? '';
      final departementEleveur = () {
        final dep = userRow['departement_pro'] as String?;
        if (dep != null && dep.isNotEmpty) return dep;
        final cp = (userRow['code_postal_pro'] as String?) ?? '';
        return FrenchGeo.fromPostalCode(cp)?.departement ?? '';
      }();
      final regionEleveur = () {
        final reg = userRow['region_pro'] as String?;
        if (reg != null && reg.isNotEmpty) return reg;
        final cp = (userRow['code_postal_pro'] as String?) ?? '';
        return FrenchGeo.fromPostalCode(cp)?.region ?? '';
      }();

      final now = DateTime.now().toIso8601String();
      final supaData = <String, dynamic>{
        'uid_eleveur':          ownerUid,
        if (activeProfileId.isNotEmpty) 'profile_id': activeProfileId,
        'nom_eleveur':          nomEleveur,
        'ville_eleveur':        villeEleveur,
        'departement_eleveur':  departementEleveur,
        'region_eleveur':       regionEleveur,
        'pays_eleveur':         userRow['pays_pro'] ?? 'France',
        'type':                 _type,
        'type_vente':           _typeVente,
        'espece':               _espece,
        'espece_autre':         _espece == 'autre' ? _especeAutreCtrl.text.trim() : null,
        'race':                 _raceCtrl.text.trim(),
        'titre':                _titreCtrl.text.trim(),
        'description':          _descCtrl.text.trim(),
        'photos':               allPhotos,
        'prix': const {'vente', 'adoption', 'retraite', 'location', 'demi_pension', 'pension_complete', 'valorisation'}
                .contains(_typeVente)
            ? double.tryParse(_prixCtrl.text)
            : null,
        'prix_unite': const {'location', 'demi_pension', 'pension_complete', 'valorisation'}.contains(_typeVente)
            ? _prixUnite
            : null,
        'prix_negociable':      _prixNegociable,
        'statut':               brouillon ? 'brouillon' : _statut,
        'date_naissance': _type == 'portee' && _dateNaissance != null
            ? _dateNaissance!.toIso8601String().substring(0, 10) : null,
        'nombre_bebes':         _type == 'portee' ? _nombreBebes : null,
        'animaux_portee':       _type == 'portee' ? animauxSaved : null,
        'prix_min_portee':
            _type == 'portee' && _typeVente != 'don' ? double.tryParse(_prixMinPorteeCtrl.text) : null,
        'prix_max_portee':
            _type == 'portee' && _typeVente != 'don' ? double.tryParse(_prixMaxPorteeCtrl.text) : null,
        'mere_animal_id':       _mereAnimalId,
        'mere_photo_url':       merePhotoUrl,
        'mere_nom':             _mereNomCtrl.text.trim(),
        'mere_puce':            _merePuceCtrl.text.trim(),
        'mere_identification':  _merePuceCtrl.text.trim(),
        'mere_race':            _mereRaceCtrl.text.trim(),
        'mere_couleur':         _mereCouleurCtrl.text.trim(),
        'mere_couleur_yeux':    _mereCouleurYeuxCtrl.text.trim(),
        'mere_description':     _mereDescCtrl.text.trim(),
        'mere_registre':        _mereRegistre,
        'pere_animal_id':       _pereAnimalId,
        'pere_photo_url':       perePhotoUrl,
        'pere_nom':             _pereNomCtrl.text.trim(),
        'pere_puce':            _perePuceCtrl.text.trim(),
        'pere_identification':  _perePuceCtrl.text.trim(),
        'pere_race':            _pereRaceCtrl.text.trim(),
        'pere_couleur':         _pereCouleurCtrl.text.trim(),
        'pere_couleur_yeux':    _pereCouleurYeuxCtrl.text.trim(),
        'pere_description':     _pereDescCtrl.text.trim(),
        'pere_registre':        _pereRegistre,
        'registre_type':        _registreType,
        'numero_registre':      _numRegistreCtrl.text.trim(),
        'club_pedigree':        _clubPedigreeCtrl.text.trim(),
        'studbook': _espece == 'cheval' ? _studbookCtrl.text.trim() : null,
        // ── Cheval : sport & vidéos ──
        'niveau_recommande': _espece == 'cheval' && _niveauEquide.isNotEmpty ? _niveauEquide : null,
        'palmares': _espece == 'cheval' && _palmaresCtrl.text.trim().isNotEmpty
            ? _palmaresCtrl.text.trim()
            : null,
        'indice_iso': _espece == 'cheval' ? int.tryParse(_isoCtrl.text.trim()) : null,
        'indice_idr': _espece == 'cheval' ? int.tryParse(_idrCtrl.text.trim()) : null,
        'indice_icc': _espece == 'cheval' ? int.tryParse(_iccCtrl.text.trim()) : null,
        'video_monte_url': _espece == 'cheval' ? _videoMonteUrl : null,
        'video_libre_url': _espece == 'cheval' ? _videoLibreUrl : null,
        'vaccines':             _vaccines,
        'vermifuge':            _vermifuge,
        'identification':       _identification,
        'bilan_sante':          _bilanSante,
        'semaines':             _typeVente == 'saillie' ? null : _semaines,
        'etalon_animal_id':     _etalonAnimalId,
        'sexe':    _type != 'portee' ? _sexe : null,
        'couleur': _couleurCtrl.text.trim(),
        'couleur_yeux': _couleurYeuxCtrl.text.trim(),
        'date_naissance_animal': _type != 'portee' && _dateNaissanceAnimal != null
            ? _dateNaissanceAnimal!.toIso8601String().substring(0, 10) : null,
        'sterilise': _type != 'portee' ? _sterilise : null,
        'saillie_prix': _typeVente == 'saillie' ? double.tryParse(_sailliePrixCtrl.text) : null,
        'saillie_genetique': _typeVente == 'saillie' && _saillieGenetiqueCtrl.text.trim().isNotEmpty
            ? _saillieGenetiqueCtrl.text.trim()
            : null,
        'saillie_conditions':
            _typeVente == 'saillie' ? _saillieCondCtrl.text.trim() : null,
        // Champs légaux obligatoires
        'num_identification': (_espece == 'chien' || _espece == 'chat') && _type != 'portee'
            ? _numIdentCtrl.text.trim() : null,
        'num_sire': _espece == 'cheval' ? _numSIRECtrl.text.trim() : null,
        'num_passeport_equin': _espece == 'cheval' ? _numPasseportCtrl.text.trim() : null,
        'updated_at': now,
      };

      // ── Auto-check annonce suspect ─────────────────────────────────────────
      final _suspectReasons = <String>[];
      // Les bornes de prix ne valent que pour une vente ferme : une location /
      // demi-pension / valo de cheval a des montants (mensuels) hors barème.
      final _checkPriceBand = _typeVente == 'vente' || _typeVente == 'retraite' || _type == 'portee';
      final _prixCheck = _checkPriceBand ? supaData['prix'] as double? : null;
      final _prixPorteeCheck = supaData['prix_min_portee'] as double?;
      final _maxPrix = <String, double>{
        'chien': 20000, 'chat': 6000, 'cheval': 150000,
        'lapin': 1000, 'oiseau': 5000, 'nac': 3000,
      }[_espece] ?? 50000;
      final _minPrix = <String, double>{
        'chien': 150, 'chat': 100, 'cheval': 800,
        'lapin': 20, 'oiseau': 30,
      }[_espece] ?? 20;
      if (_prixCheck != null && _prixCheck > 0 && _prixCheck < _minPrix) {
        _suspectReasons.add('prix_tres_bas');
      }
      if (_prixCheck != null && _prixCheck > _maxPrix) {
        _suspectReasons.add('prix_tres_eleve');
      }
      if (_prixPorteeCheck != null && _prixPorteeCheck > 0 && _prixPorteeCheck < _minPrix) {
        _suspectReasons.add('prix_portee_bas');
      }
      final _fullText =
          '${supaData['titre'] ?? ''} ${supaData['description'] ?? ''}'.toLowerCase();
      const _blacklistWords = [
        'bitcoin', 'crypto', 'western union', 'mandat cash',
        'arnaque', 'don gratuit', 'livraison longue distance',
        'visa gift', 'paypal friends',
      ];
      for (final w in _blacklistWords) {
        if (_fullText.contains(w)) _suspectReasons.add('mot_suspect:$w');
      }
      supaData['is_suspect'] = _suspectReasons.isNotEmpty;
      supaData['suspect_reasons'] = _suspectReasons;

      if (widget.annonceId != null) {
        // Brouillon publié : la durée de publication démarre maintenant
        if (_estBrouillon && !brouillon) {
          supaData['expires_at'] = DateTime.now().add(Duration(days: _dureePlan ?? _dureeAnnonce)).toIso8601String();
        }
        await Supabase.instance.client
            .from('annonces').update(supaData).eq('id', widget.annonceId!);
      } else {
        supaData['created_at'] = now;
        supaData['expires_at'] =
            DateTime.now().add(Duration(days: _dureePlan ?? _dureeAnnonce)).toIso8601String();
        supaData['vues']     = 0;
        supaData['contacts'] = 0;
        await Supabase.instance.client.from('annonces').insert(supaData);
      }
      await _oublierBrouillonLocal();
      _autoSaveTimer?.cancel();
      if (mounted && brouillon) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Brouillon enregistré dans Mes annonces.', style: TextStyle(fontFamily: 'Galey'))));
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

  // Une fois l'annonce publiée, on verrouille les champs qui identifient
  // l'animal/la portée (date de naissance, parents) : les laisser modifiables
  // permettrait de faire passer une annonce pour une AUTRE portée/animal sans
  // repayer/reconsommer le quota — seuls photos, texte et prix restent
  // éditables après publication.
  bool get _isEditLocked => widget.annonceId != null && !_estBrouillon;

  final _scroll = ScrollController();

  void _suivant() {
    final err = _erreurEtape(_etape);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red.shade700));
      return;
    }
    setState(() => _etape = (_etape + 1).clamp(1, 3));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final isSaillie  = _typeVente == 'saillie';
    final isRetraite = _typeVente == 'retraite';
    final chienChat  = _espece == 'chien' || _espece == 'chat';
    const gap = SizedBox(height: 12);
    final etape1 = <Widget>[
      _sectionType(), gap,
      _sectionEspece(), gap,
      if (_type == 'portee') ...[_sectionPortee(), gap],
      if (_type == 'animal') ...[_sectionAnimal(), gap],
      if (_type == 'portee') ...[_sectionAnimauxPortee(), gap],
      _sectionDescription(),
    ];
    final etape2 = <Widget>[
      if (_espece == 'cheval') ...[_sectionIdentificationEquin(), gap],
      if (chienChat && _type != 'portee') ...[_sectionIdentificationAnimal(), gap],
      _sectionSante(), gap,
      if (!isSaillie && !isRetraite) ...[_lockable(_sectionMere()), gap],
      if (!isSaillie && !isRetraite) ...[_lockable(_sectionPere()), gap],
      _sectionPedigree(),
    ];
    final etape3 = <Widget>[
      _sectionPhotos(), gap,
      _sectionPublication(), gap,
      if (isSaillie) ...[_sectionSaillie(), gap],
      if (_espece == 'cheval' && !isSaillie) ...[_sectionEquide(), gap],
      _recap(),
    ];
    final peutBrouillon = widget.annonceId == null || _estBrouillon;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(widget.annonceId == null ? 'Nouvelle annonce' : _estBrouillon ? 'Reprendre le brouillon' : 'Modifier l\'annonce',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: Column(children: [
        // Étapes
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
          child: Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(child: InkWell(
                onTap: () => _allerA(i + 1),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(
                      color: _etape == i + 1 ? _teal : Colors.transparent, width: 2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 22, height: 22, alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _etape == i + 1 ? _teal : _etape > i + 1 ? _teal.withValues(alpha: 0.12) : Colors.white,
                        border: Border.all(color: _etape >= i + 1 ? _teal : Colors.grey.shade400),
                      ),
                      child: Text('${i + 1}', style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700,
                          color: _etape == i + 1 ? Colors.white : _etape > i + 1 ? _teal : Colors.grey.shade600)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: Text(_etapes[i], maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700,
                            color: _etape == i + 1 ? _teal : Colors.grey.shade600))),
                  ]),
                ),
              )),
          ]),
        ),
        if (_brouillonLocal != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Expanded(child: Text('Une annonce non terminée a été retrouvée sur cet appareil.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _dark))),
              TextButton(
                onPressed: () { _oublierBrouillonLocal(); setState(() => _brouillonLocal = null); },
                child: const Text('Ignorer', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              ),
              TextButton(
                onPressed: () {
                  final data = Map<String, dynamic>.from((_brouillonLocal!['data'] as Map?) ?? {});
                  setState(() { _depuisMap(data); _brouillonLocal = null; });
                },
                child: const Text('Reprendre', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
              ),
            ]),
          ),
        Expanded(child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_autoSaveA != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Enregistré automatiquement à $_autoSaveA',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
              ),
            ...(_etape == 1 ? etape1 : _etape == 2 ? etape2 : etape3),
          ]),
        )),
        // Actions
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade300))),
          child: Row(children: [
            OutlinedButton(
              onPressed: _saving ? null : () {
                if (_etape > 1) { setState(() => _etape--); if (_scroll.hasClients) _scroll.jumpTo(0); }
                else { Navigator.pop(context); }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _dark, side: BorderSide(color: Colors.grey.shade400),
                minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(_etape > 1 ? 'Précédent' : 'Annuler', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            if (peutBrouillon) ...[
              TextButton(
                onPressed: _saving ? null : () => _save(brouillon: true),
                style: TextButton.styleFrom(foregroundColor: _teal, minimumSize: const Size(0, 44)),
                child: const Text('Brouillon', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
            ],
            ElevatedButton(
              onPressed: _saving ? null : (_etape < 3 ? _suivant : _save),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_etape < 3 ? 'Suivant'
                        : (widget.annonceId == null || _estBrouillon) ? 'Publier l\'annonce' : 'Enregistrer',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ),
          ]),
        )),
      ]),
    );
  }

  /// Récapitulatif avant publication.
  Widget _recap() {
    final prix = _typeVente == 'saillie'
        ? (_sailliePrixCtrl.text.isNotEmpty ? '${_sailliePrixCtrl.text} €' : 'Gratuite')
        : _typeVente == 'don' ? 'Don'
        : _type == 'portee'
            ? ([_prixMinPorteeCtrl.text, _prixMaxPorteeCtrl.text].where((v) => v.isNotEmpty).join(' – ') + (_prixMinPorteeCtrl.text.isNotEmpty || _prixMaxPorteeCtrl.text.isNotEmpty ? ' €' : '—'))
            : (_prixCtrl.text.isNotEmpty ? '${_prixCtrl.text} €' : '—');
    final lignes = <(String, String)>[
      ('Annonce', '${_libelleCession()} · ${_libelleObjet()}'),
      ('Animal', [_espece == 'autre' ? _especeAutreCtrl.text : _espece, _raceCtrl.text].where((v) => v.isNotEmpty).join(' · ')),
      ('Identification', _espece == 'cheval' ? _numSIRECtrl.text : _type == 'portee' ? _merePuceCtrl.text : _numIdentCtrl.text),
      ('Prix', prix),
      ('Photos', '${_photosUrls.length + _photosFiles.length} / 5'),
      ('Durée de publication', '${_dureePlan ?? _dureeAnnonce} jours (selon votre abonnement)'),
      ('Mise en avant', 'Depuis Mes annonces, après publication'),
    ];
    return _card('Récapitulatif', Icons.fact_check_outlined, [
      for (final l in lignes)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(l.$1, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600))),
            const SizedBox(width: 12),
            Flexible(child: Text(l.$2.isEmpty ? '—' : l.$2, textAlign: TextAlign.right,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _dark))),
          ]),
        ),
    ]);
  }

  String _libelleCession() => switch (_typeVente) {
    'vente' => 'Vente', 'adoption' => 'Adoption', 'don' => 'Don', 'saillie' => 'Saillie', 'retraite' => 'Retraité',
    'location' => 'Location', 'demi_pension' => 'Demi-pension', 'pension_complete' => 'Pension complète', 'valorisation' => 'Valorisation',
    _ => _typeVente,
  };
  String _libelleObjet() => _typeVente == 'saillie' ? 'Saillie' : _typeVente == 'retraite' ? 'Retraité d\'élevage'
      : _type == 'portee' ? 'Portée complète' : 'Animal individuel';

  Future<void> _chercherReseau() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final choisi = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ReseauEtalonSheet(espece: _espece, uid: uid),
    );
    if (choisi == null || !mounted) return;
    final photos = List<String>.from(choisi['photos'] ?? []);
    setState(() {
      _pereAnimalId = choisi['etalon_animal_id'] as String?;
      _pereNomCtrl.text = ((choisi['pere_nom'] as String?)?.isNotEmpty == true ? choisi['pere_nom'] : choisi['titre'] ?? '').toString();
      _perePuceCtrl.text = (choisi['pere_puce'] ?? '').toString();
      _pereRaceCtrl.text = (choisi['pere_race'] ?? choisi['race'] ?? '').toString();
      _pereCouleurCtrl.text = (choisi['pere_couleur'] ?? '').toString();
      _pereCouleurYeuxCtrl.text = (choisi['pere_couleur_yeux'] ?? '').toString();
      _pereRegistre = (choisi['pere_registre'] ?? '').toString();
      _perePhotoFile = null;
      _perePhotoUrl = (choisi['pere_photo_url'] as String?) ?? (photos.isNotEmpty ? photos.first : null);
      _pereEleveurReseau = (choisi['nom_eleveur'] as String?) ?? 'Éleveur PetsMatch';
    });
  }

  // ─── Helpers visuels ─────────────────────────────────────────────────────────

  // Grise + verrouille une section entière (Mère/Père) une fois l'annonce
  // publiée — cf. _isEditLocked.
  Widget _lockable(Widget child) {
    if (!_isEditLocked) return child;
    return Stack(children: [
      AbsorbPointer(child: Opacity(opacity: 0.5, child: child)),
      Positioned(
        top: 16, right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 12, color: Colors.white),
            SizedBox(width: 4),
            Text('Non modifiable après publication', style: TextStyle(
                fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      ),
    ]);
  }

  // Bloc sobre : fond blanc, bordure fine, titre texte (l'icône n'est plus affichée).
  Widget _card(String title, IconData icon, List<Widget> children) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300)),
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 15, color: _dark)),
      const SizedBox(height: 12),
      ...children,
    ]),
  );

  /// Sélecteur segmenté compact.
  Widget _segmente(List<(String, String)> options, String valeur, ValueChanged<String> onTap, {Set<String> desactives = const {}}) =>
    Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < options.length; i++)
          Expanded(child: InkWell(
            onTap: desactives.contains(options[i].$1) ? null : () => onTap(options[i].$1),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: valeur == options[i].$1 ? _teal : Colors.white,
                border: i > 0 ? Border(left: BorderSide(color: Colors.grey.shade300)) : null,
              ),
              child: Text(options[i].$2, textAlign: TextAlign.center, maxLines: 2,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: desactives.contains(options[i].$1) ? Colors.grey.shade400
                          : valeur == options[i].$1 ? Colors.white : _dark)),
            ),
          )),
      ])),
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
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _teal, width: 1.5)),
    filled: true, fillColor: Colors.white,
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
            borderRadius: BorderRadius.circular(8)),
          child: Text(opt, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected == opt ? Colors.white : Colors.black87)))
      )).toList(),
    );

  Widget _datePicker(String label, DateTime? value, ValueChanged<DateTime> onPick, {bool enabled = true}) {
    final fmt = DateFormat('dd/MM/yyyy');
    return GestureDetector(
      onTap: !enabled ? null : () async {
        final d = await showDatePicker(context: context,
          initialDate: value ?? DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(primary: _teal)), child: child!));
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: !enabled ? const Color(0xFFEFEFEF) : Colors.white,
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(!enabled ? Icons.lock_outline : Icons.calendar_today_outlined,
              size: 16, color: const Color(0xFF6F767B)),
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

  void _choisirCession(String v) => setState(() {
    _typeVente = v; _cessionMemo = v;
    const forceAnimal = {'location', 'demi_pension', 'pension_complete', 'valorisation'};
    if (forceAnimal.contains(v)) _type = 'animal';
    _prixUnite = switch (v) {
      'location' || 'demi_pension' || 'pension_complete' => 'mois',
      'valorisation' => 'convenir',
      _ => 'total',
    };
  });

  String get _objet => _typeVente == 'saillie' ? 'saillie' : _typeVente == 'retraite' ? 'retraite'
      : _type == 'portee' ? 'portee' : 'individuel';

  void _choisirObjet(String o) => setState(() {
    switch (o) {
      case 'saillie':  _typeVente = 'saillie';  _type = 'animal'; _prixUnite = 'total';
      case 'retraite': _typeVente = 'retraite'; _type = 'animal'; _prixUnite = 'total';
      default:
        if (const {'saillie', 'retraite'}.contains(_typeVente)) _typeVente = _cessionMemo;
        _type = o == 'portee' ? 'portee' : 'animal';
        if (o == 'portee' && !const {'vente', 'adoption', 'don'}.contains(_typeVente)) { _typeVente = 'vente'; _cessionMemo = 'vente'; }
    }
  });

  Widget _optionCession(String v, String titre, String detail, IconData icone) {
    final actif = _typeVente == v;
    return InkWell(
      onTap: () => _choisirCession(v),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: actif ? _teal.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: actif ? _teal : Colors.grey.shade300, width: actif ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icone, size: 18, color: actif ? _teal : Colors.grey.shade600),
          const SizedBox(height: 6),
          Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700, color: _dark)),
          const SizedBox(height: 2),
          Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _sectionType() {
    final objet = _objet;
    final equin = const {'location', 'demi_pension', 'pension_complete', 'valorisation'}.contains(_typeVente);
    return _card('Type d\'annonce', Icons.campaign_outlined, [
      if (objet != 'saillie' && objet != 'retraite') ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _optionCession('vente', 'Vente', 'Proposer à la vente', Icons.sell_outlined)),
          const SizedBox(width: 8),
          Expanded(child: _optionCession('adoption', 'Adoption', 'Frais d\'adoption', Icons.favorite_border)),
          const SizedBox(width: 8),
          Expanded(child: _optionCession('don', 'Don', 'Céder gratuitement', Icons.card_giftcard_outlined)),
        ]),
        if (_espece == 'cheval') ...[
          const SizedBox(height: 10),
          _label('Autres formules (cheval)'),
          _chips(const ['Location', 'Demi-pension', 'Pension complète', 'Valorisation'],
              const {'location': 'Location', 'demi_pension': 'Demi-pension', 'pension_complete': 'Pension complète', 'valorisation': 'Valorisation'}[_typeVente] ?? '',
              (v) => _choisirCession(const {'Location': 'location', 'Demi-pension': 'demi_pension', 'Pension complète': 'pension_complete', 'Valorisation': 'valorisation'}[v]!)),
        ],
        const SizedBox(height: 14),
      ],
      _label('Objet de l\'annonce'),
      _segmente(const [('individuel', 'Animal individuel'), ('portee', 'Portée complète'), ('saillie', 'Saillie'), ('retraite', 'Retraité d\'élevage')],
          objet, _choisirObjet, desactives: equin ? const {'portee', 'saillie', 'retraite'} : const {}),
      if (objet == 'saillie' || objet == 'retraite') ...[
        const SizedBox(height: 8),
        Text(objet == 'saillie'
            ? 'Une saillie n\'est ni une vente, ni une adoption : son prix se règle à l\'étape Publication.'
            : 'Choisissez l\'animal : l\'espèce et la race seront préremplies.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
      // Saillie : picker étalon (avant espèce) pour auto-remplissage
      if (_typeVente == 'saillie') ...[
        OutlinedButton.icon(
          onPressed: _pickEtalon,
          icon: const Icon(Icons.diversity_1_outlined, size: 16, color: _teal),
          label: Text(
            _etalonAnimalId != null
                ? '${_pereNomCtrl.text.isNotEmpty ? _pereNomCtrl.text : 'Étalon sélectionné'} — changer'
                : 'Sélectionner l\'étalon / reproducteur',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal),
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _teal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          ),
        ),
        if (_etalonAnimalId != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.check_circle, size: 14, color: _green),
            const SizedBox(width: 4),
            Expanded(child: Text('Espèce, race et pedigree pré-remplis',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500))),
          ]),
        ],
      ],
      // Retraité : picker placé ICI (avant espèce) pour auto-remplissage
      if (_typeVente == 'retraite') ...[
        OutlinedButton.icon(
          onPressed: _pickRetraite,
          icon: const Icon(Icons.pets_outlined, size: 16, color: _teal),
          label: Text(
            _retraiteAnimalNom != null
                ? '$_retraiteAnimalNom — changer'
                : 'Sélectionner l\'animal retraité',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal),
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _teal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          ),
        ),
      ],
      ],
    ]);
  }

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
            // Le vocabulaire de sexe diffère pour les équidés (jument/hongre/
            // entier) : on remet une valeur valide au changement d'espèce.
            if (_espece == 'cheval' && !const ['jument', 'hongre', 'entier'].contains(_sexe)) {
              _sexe = 'jument';
            } else if (_espece != 'cheval' && !const ['male', 'femelle'].contains(_sexe)) {
              _sexe = 'male';
            }
          }),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _espece == s.value ? _teal : Colors.white,
              border: Border.all(color: _espece == s.value ? _teal : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              speciesIcon(s.value, 12, _espece == s.value ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 5),
              Text(s.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _espece == s.value ? Colors.white : Colors.black87)),
            ]),
          ),
        )).toList(),
      ),
      if (_espece == 'autre') ...[
        const SizedBox(height: 12),
        _label('Préciser l\'espèce'),
        _textField(_especeAutreCtrl, 'Ex: Furet, Tortue...'),
      ],
      const SizedBox(height: 12),
      _label('Race'),
      _raceField(),
    ]);
  }

  Widget _sectionPhotos() {
    final total = _photosUrls.length + _photosFiles.length;
    return _card('Photos', Icons.photo_library_outlined, [
      Row(children: [
        Text('$total / 5  ·  format carré  ·  la première est la photo principale',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
        const Spacer(),
        if (total < 5) TextButton.icon(onPressed: _pickAnnoncePhoto,
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
        if (total < 5) GestureDetector(onTap: _pickAnnoncePhoto,
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

  Widget _sectionDescription() => _card('Description', Icons.notes_outlined, [
    _textField(_descCtrl, 'Décrivez l\'animal ou la portée, la famille, les conditions...', maxLines: 5),
  ]);

  Widget _sectionPublication() => _card('Prix et conditions', Icons.sell_outlined, [
    _label('Titre de l\'annonce'),
    _textField(_titreCtrl, 'Ex: Chiots Berger Australien LOF disponibles'),
    if (_typeVente == 'don') ...[
      const SizedBox(height: 10),
      Text('Don : aucun prix n\'est demandé.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
    ],
    if (_type != 'portee' && const {'vente', 'adoption', 'retraite', 'location', 'demi_pension', 'pension_complete', 'valorisation'}.contains(_typeVente)) ...[
      const SizedBox(height: 10),
      _label(_typeVente == 'valorisation' ? 'Rémunération (€, optionnel)' : _typeVente == 'adoption' ? 'Frais d\'adoption (€)' : 'Prix (€)'),
      Row(children: [
        Expanded(child: _textField(_prixCtrl, '0', keyboardType: TextInputType.number)),
        if (const {'location', 'demi_pension', 'pension_complete'}.contains(_typeVente)) ...[
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _prixUnite == 'total' || _prixUnite == 'convenir' ? 'mois' : _prixUnite,
            items: const [
              DropdownMenuItem(value: 'mois', child: Text('/ mois', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
              DropdownMenuItem(value: 'semaine', child: Text('/ semaine', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _prixUnite = v ?? 'mois'),
          ),
        ],
        const SizedBox(width: 12),
        GestureDetector(onTap: () => setState(() => _prixNegociable = !_prixNegociable),
          child: Row(children: [
            Checkbox(value: _prixNegociable, onChanged: (v) => setState(() => _prixNegociable = v ?? false),
                activeColor: _teal, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            const Text('Négociable', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
          ])),
      ]),
    ],
    if (_type == 'portee' && _typeVente != 'don') ...[
      const SizedBox(height: 10),
      _label(_typeVente == 'adoption' ? 'Frais d\'adoption par bébé (€)' : 'Fourchette de prix par bébé (€)'),
      Row(children: [
        Expanded(child: _textField(_prixMinPorteeCtrl, 'Min', keyboardType: TextInputType.number)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('—', style: TextStyle(fontFamily: 'Galey', fontSize: 18, color: Colors.grey.shade400))),
        Expanded(child: _textField(_prixMaxPorteeCtrl, 'Max', keyboardType: TextInputType.number)),
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
              color: _statut == s.$1 ? s.$3 : Colors.white,
              border: Border.all(color: _statut == s.$1 ? s.$3 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8)),
            child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _statut == s.$1 ? Colors.white : Colors.black87)))),
    ]),
    const SizedBox(height: 14),
    Text('Durée de publication : ${_dureePlan ?? _dureeAnnonce} jours, selon votre abonnement. '
        'La mise en avant se propose depuis Mes annonces après publication.',
        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
  ]);

  Widget _sectionPortee() => _card('Portée', Icons.group_outlined, [
    Row(children: [
      Text(
        (_espece == 'chien' || _espece == 'chat') ? 'Date de naissance ' : 'Date de naissance (optionnel) ',
        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6F767B)),
      ),
      if (_espece == 'chien' || _espece == 'chat')
        const Text('*', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
    ]),
    const SizedBox(height: 6),
    _datePicker('Sélectionner une date', _dateNaissance,
        (d) => setState(() => _dateNaissance = d), enabled: !_isEditLocked),
    if (_isEditLocked) ...[
      const SizedBox(height: 4),
      Text('Non modifiable après publication.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
    ],
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
  ]);

  Widget _sectionAnimal() => _card(
    _typeVente == 'saillie' ? 'Étalon / Reproducteur'
        : _typeVente == 'retraite' ? 'Animal retraité'
        : 'Animal',
    _typeVente == 'saillie' ? Icons.diversity_1_outlined
        : _typeVente == 'retraite' ? Icons.elderly_outlined
        : Icons.cruelty_free_outlined,
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
      // Retraité : l'animal est déjà sélectionné dans _sectionType — indiquer seulement si sélectionné
      if (_typeVente == 'retraite' && _retraiteAnimalNom != null) ...[
        Row(children: [
          const Icon(Icons.check_circle, size: 14, color: _green),
          const SizedBox(width: 4),
          Expanded(child: Text(
            '$_retraiteAnimalNom — modifiez les champs si besoin',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
          )),
        ]),
        const SizedBox(height: 10),
      ],
      _label('Sexe'),
      Wrap(spacing: 8, children: [
        for (final s in (_espece == 'cheval'
            ? const [('jument', 'Jument'), ('hongre', 'Hongre'), ('entier', 'Entier')]
            : const [('male', 'Mâle'), ('femelle', 'Femelle')]))
          GestureDetector(onTap: () => setState(() => _sexe = s.$1),
            child: AnimatedContainer(duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: _sexe == s.$1 ? _teal : Colors.white,
                border: Border.all(color: _sexe == s.$1 ? _teal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8)),
              child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _sexe == s.$1 ? Colors.white : Colors.grey)))),
      ]),
      const SizedBox(height: 10),
      _label('Couleur / Robe'),
      _textField(_couleurCtrl, 'Ex: Tricolore, Roux, Noir et blanc...'),
      const SizedBox(height: 10),
      _label('Couleur des yeux'),
      _textField(_couleurYeuxCtrl, 'Ex: marron, bleu...'),
      const SizedBox(height: 10),
      _label('Date de naissance'),
      _datePicker('Sélectionner une date', _dateNaissanceAnimal,
          (d) => setState(() => _dateNaissanceAnimal = d), enabled: !_isEditLocked),
      if (_isEditLocked) ...[
        const SizedBox(height: 4),
        Text('Non modifiable après publication.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
      ],
      if (_typeVente != 'saillie') ...[
        const SizedBox(height: 6),
        _checkRow(Icons.cut_outlined, 'Stérilisé(e)', _sterilise,
            (v) => setState(() => _sterilise = v)),
      ],
    ],
  );

  // ── Bloc équin (niveau, palmarès, indices, vidéos) ───────────────────────────
  Future<void> _pickAnnonceVideo({required bool monte}) async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    if (await file.length() > 60 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Vidéo trop lourde (max 60 Mo).', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _uploadingVideo = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'x';
      final ext = picked.path.split('.').last.toLowerCase();
      final url = await uploadRawFile(file,
          'annonces/$uid/video_${monte ? 'monte' : 'libre'}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      if (mounted) setState(() {
        if (monte) { _videoMonteUrl = url; } else { _videoLibreUrl = url; }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Widget _videoSlot(String label, String? url, {required bool monte}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      if (url != null) ...[
        ClipRRect(borderRadius: BorderRadius.circular(10), child: InlineVideo(url: url, placeholderHeight: 140)),
        TextButton.icon(
          onPressed: () => setState(() { if (monte) { _videoMonteUrl = null; } else { _videoLibreUrl = null; } }),
          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
          label: const Text('Retirer', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.red)),
        ),
      ] else
        OutlinedButton.icon(
          onPressed: _uploadingVideo ? null : () => _pickAnnonceVideo(monte: monte),
          icon: _uploadingVideo
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.video_call_outlined, size: 18),
          label: Text(_uploadingVideo ? 'Envoi…' : 'Ajouter une vidéo', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
        ),
      const SizedBox(height: 10),
    ]);

  Widget _sectionEquide() => _card('Cheval — sport & vidéos', Icons.sports_score_outlined, [
    _label('Niveau recommandé'),
    Wrap(spacing: 8, runSpacing: 6, children: [
      for (final n in _kNiveauxEquide)
        GestureDetector(
          onTap: () => setState(() => _niveauEquide = _niveauEquide == n ? '' : n),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _niveauEquide == n ? _teal : Colors.transparent,
              border: Border.all(color: _niveauEquide == n ? _teal : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8)),
            child: Text(n, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600, color: _niveauEquide == n ? Colors.white : Colors.grey.shade700)),
          ),
        ),
    ]),
    const SizedBox(height: 12),
    _label('Palmarès / résultats (optionnel)'),
    _textField(_palmaresCtrl, 'Ex: 2e Amateur Elite GP Fontainebleau 2025…', maxLines: 3),
    const SizedBox(height: 12),
    _label('Indices (optionnel)'),
    Row(children: [
      Expanded(child: _textField(_isoCtrl, 'ISO', keyboardType: TextInputType.number)),
      const SizedBox(width: 8),
      Expanded(child: _textField(_idrCtrl, 'IDR', keyboardType: TextInputType.number)),
      const SizedBox(width: 8),
      Expanded(child: _textField(_iccCtrl, 'ICC', keyboardType: TextInputType.number)),
    ]),
    const SizedBox(height: 14),
    _videoSlot('Vidéo sous selle', _videoMonteUrl, monte: true),
    _videoSlot('Vidéo en liberté', _videoLibreUrl, monte: false),
  ]);

  Widget _sectionSaillie() => _card('Conditions de saillie', Icons.handshake_outlined, [
    _label('Prix de la saillie (€) — laisser vide si gratuit'),
    _textField(_sailliePrixCtrl, '0', keyboardType: TextInputType.number),
    const SizedBox(height: 10),
    _label('Conditions & informations complémentaires'),
    _textField(_saillieCondCtrl,
        'Ex: Droit au chiot, contrat de saillie, tests génétiques requis...', maxLines: 3),
    if (_espece == 'cheval') ...[
      const SizedBox(height: 10),
      _label('Statut génétique de l\'étalon (optionnel)'),
      _textField(_saillieGenetiqueCtrl,
          'Ex: WFFS N/N, PSSM1 N/N, profil ADN établi — si l\'étalon n\'est pas fiché dans PetsMatch',
          maxLines: 3),
      if (_etalonAnimalId != null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Les tests génétiques fichés sur cet étalon s\'afficheront automatiquement.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
        ),
    ],
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
    Row(children: [
      Text(
        'Identification (puce / tatouage)',
        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6F767B)),
      ),
      if (_espece == 'chien' || _espece == 'chat')
        const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
    ]),
    const SizedBox(height: 6),
    _textField(_merePuceCtrl, 'Numéro de puce ICAD ou tatouage'),
    if ((_espece == 'chien' || _espece == 'chat') && _type == 'portee') ...[
      const SizedBox(height: 4),
      const Text('Obligatoire (art. L214-8 Code rural)',
          style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF9B6800))),
    ],
    const SizedBox(height: 10),
    _label('Race'),
    _textField(_mereRaceCtrl, 'Race de la mère'),
    const SizedBox(height: 10),
    _label('Couleur / Robe'),
    _textField(_mereCouleurCtrl, 'Ex: Fauve, Tricolore…'),
    const SizedBox(height: 10),
    _label('Couleur des yeux'),
    _textField(_mereCouleurYeuxCtrl, 'Ex: marron, bleu...'),
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
      _segmente(const [('mien', 'Mes animaux'), ('reseau', 'Réseau PetsMatch'), ('manuel', 'Saisie manuelle')],
          _pereSource, (v) => setState(() {
            _pereSource = v;
            if (v == 'manuel') { _pereAnimalId = null; _pereEleveurReseau = null; }
          })),
      const SizedBox(height: 10),
      if (_pereSource == 'reseau') ...[
        if (_pereEleveurReseau != null && _pereNomCtrl.text.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 44,
                  child: _perePhotoUrl != null ? CachedNetworkImage(imageUrl: _perePhotoUrl!, fit: BoxFit.cover)
                      : Container(color: Colors.grey.shade100))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_pereNomCtrl.text, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700, color: _dark)),
                Text('Fiche liée — $_pereEleveurReseau', style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _teal)),
              ])),
              IconButton(
                onPressed: () => setState(() { _pereAnimalId = null; _pereEleveurReseau = null; _perePhotoUrl = null; }),
                icon: const Icon(Icons.close, size: 18, color: Color(0xFF6F767B)),
              ),
            ]),
          ),
        OutlinedButton.icon(
          onPressed: _chercherReseau,
          icon: const Icon(Icons.search, size: 16, color: _teal),
          label: const Text('Rechercher sur le réseau PetsMatch', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: _teal), minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
        const SizedBox(height: 6),
        Text('Seuls les reproducteurs proposés publiquement en saillie apparaissent. Aucun transfert de propriété.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
      ],
      if (_pereSource == 'manuel') ...[
        Text('Reproducteur extérieur : il n\'est pas ajouté à votre cheptel.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
      ],
      if (_pereSource == 'mien' && _pereAnimalId != null) ...[
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
      if (_pereSource != 'reseau') Row(children: [
        if (_pereAnimalId == null)
          _parentPhotoBox(_perePhotoUrl, _perePhotoFile, _pickPerePhoto,
              () => setState(() { _perePhotoUrl = null; _perePhotoFile = null; })),
        if (_pereAnimalId == null) const SizedBox(width: 10),
        if (_pereSource == 'mien') Expanded(
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
      _label('Couleur des yeux'),
      _textField(_pereCouleurYeuxCtrl, 'Ex: marron, bleu...'),
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
          const Text('  minimum légal : 8 semaines',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.redAccent)),
      ]),
    ],
  ]);

  Widget _sectionIdentificationEquin() => _card(
    'Identification équidé', Icons.badge_outlined,
    [
      Text('Obligatoire pour tout équidé mis en vente (Décret n°2013-879).',
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 12),
      Row(children: [
        _label('Numéro SIRE'),
        const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ]),
      _textField(_numSIRECtrl, 'Ex: 008FR12345678901 (15 chiffres)'),
      const SizedBox(height: 10),
      _label('Numéro de passeport équin (optionnel)'),
      _textField(_numPasseportCtrl, 'Ex: FR123456789'),
    ],
  );

  Widget _sectionIdentificationAnimal() => _card('Identification de l\'animal', Icons.qr_code_2_outlined, [
    Text('Obligatoire pour chien et chat (art. L212-10 Code rural).',
        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
    const SizedBox(height: 10),
    Row(children: [
      _label('Numéro de puce électronique ou tatouage'),
      const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
    ]),
    _textField(_numIdentCtrl, 'Ex: 250269811234567 ou tatouage AA123'),
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
          Text('${animal['sexe'] == 'male' ? 'Mâle' : 'Femelle'}'
              '${(animal['couleur'] ?? '').isNotEmpty ? ' · ${animal['couleur']}' : ''}'
              '${animal['isLinked'] == true ? ' · lié' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
        ])),
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

// ─── Réseau PetsMatch : reproducteurs proposés publiquement en saillie ───────
// (annonces de saillie actives d'autres éleveurs — jamais une fiche privée).

class _ReseauEtalonSheet extends StatefulWidget {
  final String espece;
  final String uid;
  const _ReseauEtalonSheet({required this.espece, required this.uid});
  @override
  State<_ReseauEtalonSheet> createState() => _ReseauEtalonSheetState();
}

class _ReseauEtalonSheetState extends State<_ReseauEtalonSheet> {
  List<Map<String, dynamic>> _tous = [];
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final rows = await Supabase.instance.client.from('annonces')
          .select('id, titre, race, nom_eleveur, pere_nom, pere_puce, pere_race, pere_couleur, pere_couleur_yeux, pere_registre, pere_photo_url, photos, etalon_animal_id')
          .eq('type_vente', 'saillie').eq('statut', 'disponible').eq('espece', widget.espece)
          .neq('uid_eleveur', widget.uid)
          .order('created_at', ascending: false).limit(60);
      if (mounted) setState(() { _tous = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _q.trim().toLowerCase();
    final liste = _tous.where((a) => t.isEmpty ||
        ['pere_nom', 'titre', 'nom_eleveur', 'pere_puce', 'pere_race', 'race']
            .any((k) => (a[k] ?? '').toString().toLowerCase().contains(t))).toList();
    return SafeArea(child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Réseau PetsMatch', style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 10),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Nom de l\'animal, n° d\'identification ou élevage',
                  hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
                  prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade500),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
                ),
              ),
            ]),
          ),
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)))
              : liste.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Aucun reproducteur trouvé. Seuls les reproducteurs proposés publiquement en saillie sur PetsMatch apparaissent.',
                          textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)))
                  : ListView.separated(
                      itemCount: liste.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (_, i) {
                        final a = liste[i];
                        final photos = List<String>.from(a['photos'] ?? []);
                        final ph = (a['pere_photo_url'] as String?) ?? (photos.isNotEmpty ? photos.first : null);
                        final nom = ((a['pere_nom'] as String?)?.isNotEmpty == true ? a['pere_nom'] : a['titre'] ?? '').toString();
                        final sous = [a['pere_race'] ?? a['race'], a['pere_registre'], a['nom_eleveur']]
                            .where((v) => v != null && v.toString().isNotEmpty).join(' · ');
                        return ListTile(
                          leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 44,
                              child: ph != null ? CachedNetworkImage(imageUrl: ph, fit: BoxFit.cover) : Container(color: Colors.grey.shade100))),
                          title: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
                          subtitle: Text(sous, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                          trailing: const Text('Sélectionner', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
                          onTap: () => Navigator.pop(context, a),
                        );
                      },
                    )),
        ]),
      ),
    ));
  }
}

// ─── Sheet picker animaux (mère / père / étalon) ──────────────────────────────

class _AnimalPickerSheet extends StatelessWidget {
  final String espece;
  final String? sexeFilter;
  // Saillie : seuls les reproducteurs actifs (utils/reproducteurs.dart)
  final bool reproducteursSeulement;
  const _AnimalPickerSheet({required this.espece, this.sexeFilter, this.reproducteursSeulement = false});

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
                      .then((rows) => rows.where((d) =>
                          (sexeFilter == null || d['sexe'] == sexeFilter) &&
                          (!reproducteursSeulement || estReproducteurEligible(d))).toList()),
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
                        Text(reproducteursSeulement ? 'Aucun reproducteur actif : cochez « Reproducteur » sur sa fiche'
                            : sexeFilter == 'femelle' ? 'Aucune femelle de cette espèce'
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
                            Text('${d['race'] ?? ''} · ${d['sexe'] == 'male' ? 'Mâle' : 'Femelle'}',
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
                            'couleurYeux':    d['couleur_yeux'] ?? '',
                            'sexe':           d['sexe'] ?? '',
                            'espece':         d['espece'] ?? '',  // pour auto-fill espèce
                            'race':           d['race'] ?? '',
                            'identification': d['identification'] ?? '',
                            'dateNaissance':  dateNaiss != null
                                ? Timestamp.fromDate(dateNaiss) : null,
                            'description':    d['description'] ?? '',
                            // Pedigree — pour pré-remplissage étalon et retraité
                            'pedigree_lof':  d['pedigree_lof']  ?? '',
                            'club_registre': d['club_registre'] ?? '',
                            'pedigree_url':  d['pedigree_url']  ?? '',
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
  final _couleurYeuxCtrl = TextEditingController();
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
      _couleurYeuxCtrl.text = r['couleurYeux'] ?? '';
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
      _couleurYeuxCtrl.text = d['couleur_yeux'] ?? '';
      _prixCtrl.text    = _toNum(d['prix'])?.toInt().toString() ?? '';
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
    _nomCtrl.dispose(); _couleurCtrl.dispose(); _couleurYeuxCtrl.dispose();
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
    'couleur_yeux': _couleurYeuxCtrl.text.trim(),
    'prix': double.tryParse(_prixCtrl.text.trim()),
    'description': _descCtrl.text.trim(),
    'statut': _statut,
    // Préserve isLinked + animalId si l'animal était lié (portée)
    if (widget.initial?['isLinked'] == true) 'isLinked': true,
    if (widget.initial?['animalId'] != null) 'animalId': widget.initial!['animalId'],
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
            for (final s in [('male', 'Mâle'), ('femelle', 'Femelle')])
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
          _label('Couleur des yeux'), _field(_couleurYeuxCtrl, 'Ex: marron, bleu...'),
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

// ── Bottom sheet quota gate ──────────────────────────────────────────────────

class _QuotaGateSheet extends StatelessWidget {
  final Future<void> Function() onBuyExtra;
  final VoidCallback onUpgradePro;
  // Palier au-dessus du plan actuel à proposer — null si déjà au plan le
  // plus élevé (Premium), auquel cas il n'y a rien à upsell.
  final String? nextPlanLabel;

  const _QuotaGateSheet({
    required this.onBuyExtra,
    required this.onUpgradePro,
    required this.nextPlanLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isTopPlan = nextPlanLabel == null;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Quota atteint',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 20, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 8),
          Text(
            isTopPlan
                ? 'Vous êtes déjà sur notre plan le plus élevé (Premium). Achetez une annonce supplémentaire ou archivez-en une pour en publier une nouvelle.'
                : 'Vous avez atteint la limite d\'annonces de votre plan actuel.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF6F767B)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onBuyExtra,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Annonce supplémentaire — 2,99 €',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6E9E57),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (!isTopPlan) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpgradePro,
                icon: const Icon(Icons.upgrade, size: 18),
                label: Text('Passer au plan $nextPlanLabel',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF9CA3AF))),
          ),
        ],
      ),
    );
  }
}
