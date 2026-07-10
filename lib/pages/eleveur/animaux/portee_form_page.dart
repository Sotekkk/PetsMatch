import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/services/planning_service.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';

// ─── Modèle d'un animal dans la portée ───────────────────────────────────────

class _AnimalRow {
  final TextEditingController nom      = TextEditingController();
  final TextEditingController ident    = TextEditingController();
  final TextEditingController couleur  = TextEditingController();
  final TextEditingController taille   = TextEditingController();
  final TextEditingController poids    = TextEditingController();
  final TextEditingController passeport = TextEditingController();
  final TextEditingController notes    = TextEditingController();
  String sexe       = 'male';
  String typePoil   = '';
  bool   sterilise  = false;
  File?  photoFile;

  void dispose() {
    nom.dispose(); ident.dispose(); couleur.dispose();
    taille.dispose(); poids.dispose(); passeport.dispose(); notes.dispose();
  }
}

const _kTypesPoil = ['Court', 'Mi-long', 'Long', 'Frisé', 'Fil de soie', 'Ras'];

// ─── Page formulaire portée ───────────────────────────────────────────────────

class PorteeFormPage extends StatefulWidget {
  const PorteeFormPage({super.key});
  @override
  State<PorteeFormPage> createState() => _PorteeFormPageState();
}

class _PorteeFormPageState extends State<PorteeFormPage> {
  final _supa = Supabase.instance.client;
  final _fmt  = DateFormat('dd/MM/yyyy');

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  // ── Champs communs
  String    _espece        = 'chien';
  final _raceCtrl          = TextEditingController();
  final _descriptionCtrl   = TextEditingController();
  DateTime? _dateNaissance;

  // ── Pedigree
  bool   _pedigree     = false;
  final  _clubRegistreCtrl = TextEditingController();
  final  _pedigreeLofCtrl  = TextEditingController();

  // ── Père
  Map<String, dynamic>? _pereSelected;
  final _nomPereCtrl  = TextEditingController();
  final _pucePereCtrl = TextEditingController();

  // ── Mère
  Map<String, dynamic>? _mereSelected;
  final _nomMereCtrl     = TextEditingController();
  final _puceMereCtrl    = TextEditingController();
  final _raceMereCtrl    = TextEditingController();
  DateTime? _dateNaissanceMere;

  // ── Liste animaux de la portée
  final List<_AnimalRow> _animaux = [];

  // ── Données chargées
  List<Map<String, dynamic>> _animauxExistants = [];
  Map<String, List<String>>  _allBreeds        = {};
  String? _nomElevage;
  String? _adresseElevage;
  bool _loading = true;
  bool _saving  = false;
  int? _uploadingPhotoIdx;

  List<String> get _currentBreeds {
    final list = List<String>.from(_allBreeds[_espece] ?? []);
    if (!list.contains('Autre')) list.add('Autre');
    return list;
  }

  @override
  void initState() {
    super.initState();
    _addAnimal();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    // Races
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
        loaded[e.key] = List<String>.from(jsonDecode(raw) as List);
      } catch (_) { loaded[e.key] = []; }
    }
    if (mounted) setState(() => _allBreeds = loaded);

    // Profil éleveur (nom + adresse)
    try {
      final profil = await _supa
          .from('user_profiles')
          .select('nom, rue_pro, ville_pro')
          .eq('uid', uid)
          .eq('is_main', true)
          .maybeSingle();
      if (profil != null && mounted) {
        final rue    = profil['rue_pro']    as String? ?? '';
        final ville  = profil['ville_pro']  as String? ?? '';
        setState(() {
          _nomElevage     = profil['nom'] as String?;
          _adresseElevage = [rue, ville].where((s) => s.isNotEmpty).join(', ').isEmpty
              ? null
              : [rue, ville].where((s) => s.isNotEmpty).join(', ');
        });
      }
    } catch (_) {}

    // Animaux existants de l'éleveur
    try {
      final pid = User_Info.activeProfileId;
      var q = _supa
          .from('animaux')
          .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
          .eq('uid_eleveur', uid)
          .or('statut.is.null,statut.eq.present');
      if (pid.isNotEmpty) q = q.eq('profile_id', pid);
      final rows = await q;
      if (mounted) setState(() {
        _animauxExistants = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _peres() => _animauxExistants
      .where((a) => a['espece'] == _espece && (a['sexe'] as String? ?? '').startsWith('m'))
      .toList();

  List<Map<String, dynamic>> _meres() => _animauxExistants
      .where((a) => a['espece'] == _espece && (a['sexe'] as String? ?? '').startsWith('f'))
      .toList();

  void _addAnimal() => setState(() => _animaux.add(_AnimalRow()));

  void _removeAnimal(int i) {
    _animaux[i].dispose();
    setState(() => _animaux.removeAt(i));
  }

  Future<void> _pickPhoto(int idx) async {
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
    if (f != null) setState(() => _animaux[idx].photoFile = f);
  }

  void _onEspeceChanged(String e) {
    setState(() {
      _espece = e;
      _pereSelected = null; _nomPereCtrl.clear(); _pucePereCtrl.clear();
      _mereSelected = null; _nomMereCtrl.clear(); _puceMereCtrl.clear();
      _raceMereCtrl.clear(); _dateNaissanceMere = null;
    });
  }

  void _pickPere() async {
    final peres = _peres();
    if (peres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun mâle enregistré pour cette espèce')));
      return;
    }
    final sel = await _showAnimalPickerSheet(peres, 'Sélectionner le père');
    if (sel != null) {
      setState(() {
        _pereSelected  = sel;
        _nomPereCtrl.text  = sel['nom']            as String? ?? '';
        _pucePereCtrl.text = sel['identification'] as String? ?? '';
      });
    }
  }

  void _pickMere() async {
    final meres = _meres();
    if (meres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucune femelle enregistrée pour cette espèce')));
      return;
    }
    final sel = await _showAnimalPickerSheet(meres, 'Sélectionner la mère');
    if (sel != null) {
      setState(() {
        _mereSelected  = sel;
        _nomMereCtrl.text  = sel['nom']            as String? ?? '';
        _puceMereCtrl.text = sel['identification'] as String? ?? '';
        _raceMereCtrl.text = sel['race']           as String? ?? '';
        final dn = sel['date_naissance'] as String?;
        _dateNaissanceMere = dn != null ? DateTime.tryParse(dn) : null;
        if (_raceCtrl.text.isEmpty && (sel['race'] as String? ?? '').isNotEmpty) {
          _raceCtrl.text = sel['race'] as String;
        }
      });
    }
  }

  Future<Map<String, dynamic>?> _showAnimalPickerSheet(
      List<Map<String, dynamic>> list, String title) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AnimalPickerSheet(animals: list, title: title),
    );
  }

  Future<void> _save() async {
    if (_dateNaissance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La date de naissance est obligatoire')));
      return;
    }
    if (_animaux.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoutez au moins un animal')));
      return;
    }
    setState(() => _saving = true);
    try {
      final uid      = FirebaseAuth.instance.currentUser!.uid;
      final porteeId = 'portee_${DateTime.now().millisecondsSinceEpoch}';
      final dnIso    = _dateNaissance!.toIso8601String();

      // Upload photos
      final photoUrls = <String?>[];
      for (int i = 0; i < _animaux.length; i++) {
        if (_animaux[i].photoFile != null) {
          if (mounted) setState(() => _uploadingPhotoIdx = i);
          final url = await uploadPhoto(
            _animaux[i].photoFile!,
            'animaux/$uid/${porteeId}_$i.jpg',
          );
          photoUrls.add(url);
        } else {
          photoUrls.add(null);
        }
      }
      if (mounted) setState(() => _uploadingPhotoIdx = null);

      final activeProfileId = User_Info.activeProfileId;
      final rows = _animaux.asMap().entries.map((e) => {
        'id':                  '${porteeId}_${e.key}',
        'uid_eleveur':         uid,
        if (activeProfileId.isNotEmpty) 'profile_id': activeProfileId,
        'portee_id':           porteeId,
        'espece':              _espece,
        'race':                _raceCtrl.text.trim(),
        'sexe':                e.value.sexe,
        'nom':                 e.value.nom.text.trim(),
        'identification':      e.value.ident.text.trim(),
        'couleur':             e.value.couleur.text.trim(),
        'type_poil':           e.value.typePoil.isEmpty ? null : e.value.typePoil,
        'taille':              e.value.taille.text.trim().isEmpty ? null : e.value.taille.text.trim(),
        'poids':               e.value.poids.text.trim().isEmpty ? null : e.value.poids.text.trim(),
        'sterilise':           e.value.sterilise,
        'passeport_europeen':  e.value.passeport.text.trim().isEmpty ? null : e.value.passeport.text.trim(),
        'notes':               e.value.notes.text.trim().isEmpty ? null : e.value.notes.text.trim(),
        'photo_url':           photoUrls[e.key],
        'date_naissance':      dnIso,
        'date_entree':         dnIso,
        'provenance_qualite':  'naissance',
        'provenance_nom':      _nomElevage,
        'provenance_adresse':  _adresseElevage,
        'statut':              'present',
        'description':         _descriptionCtrl.text.trim(),
        'pedigree':            _pedigree,
        'club_registre':       _clubRegistreCtrl.text.trim(),
        'pedigree_lof':        _pedigreeLofCtrl.text.trim(),
        'nom_pere':            _nomPereCtrl.text.trim(),
        'puce_pere':           _pucePereCtrl.text.trim(),
        'nom_mere':            _nomMereCtrl.text.trim(),
        'puce_mere':           _puceMereCtrl.text.trim(),
        'race_mere':           _raceMereCtrl.text.trim(),
        'date_naissance_mere': _dateNaissanceMere?.toIso8601String(),
        'updated_at':          DateTime.now().toIso8601String(),
      }).toList();

      await _supa.from('animaux').upsert(rows);

      // Initialise animaux_proprietes pour chaque nouveau-né (même logique
      // que animal_fiche.dart) — sans quoi les animaux restent invisibles
      // dans "Mes animaux" (filtré par profile_id_proprio).
      try {
        final dateStr = _dateNaissance!.toIso8601String().split('T').first;
        await _supa.from('animaux_proprietes').upsert(
          _animaux.asMap().entries.map((e) => {
            'animal_id':   '${porteeId}_${e.key}',
            'uid_proprio': uid,
            'date_debut':  dateStr,
            if (activeProfileId.isNotEmpty) 'profile_id_proprio': activeProfileId,
          }).toList(),
          onConflict: 'animal_id,uid_proprio',
        );
      } catch (_) {}

      // Protocoles automatiques pour chaque nouveau-né
      try {
        for (final entry in _animaux.asMap().entries) {
          await PlanningService.triggerAutoProtocoles(
            uid: uid,
            declencheur: 'naissance',
            animalId: '${porteeId}_${entry.key}',
            dateEvenement: _dateNaissance!,
            espece: _espece,
          );
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_animaux.length} animal(s) créé(s) avec succès'),
          backgroundColor: _green,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _raceCtrl.dispose(); _descriptionCtrl.dispose();
    _clubRegistreCtrl.dispose(); _pedigreeLofCtrl.dispose();
    _nomPereCtrl.dispose(); _pucePereCtrl.dispose();
    _nomMereCtrl.dispose(); _puceMereCtrl.dispose(); _raceMereCtrl.dispose();
    for (final a in _animaux) a.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text('Nouvelle portée',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      color: Colors.white, fontSize: 15)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionInfosCommunes(),
                const SizedBox(height: 12),
                _sectionPedigree(),
                const SizedBox(height: 12),
                _sectionPere(),
                const SizedBox(height: 12),
                _sectionMere(),
                const SizedBox(height: 12),
                _sectionAnimaux(),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  // ─── Sections ─────────────────────────────────────────────────────────────────

  Widget _sectionInfosCommunes() => _card('Informations communes', Icons.info_outline, [
    _label('Espèce'),
    _especeChips(),
    const SizedBox(height: 12),
    _label('Race'),
    _raceField(),
    const SizedBox(height: 12),
    _label('Date de naissance *'),
    _datePicker('Sélectionner une date', _dateNaissance,
        (d) => setState(() => _dateNaissance = d)),
    const SizedBox(height: 12),
    _label('Description (optionnel)'),
    TextFormField(
      controller: _descriptionCtrl,
      maxLines: 3,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
      decoration: _inputDeco('Caractère, particularités de la portée…'),
    ),
  ]);

  Widget _sectionPedigree() => _card('Pedigree & Registre', Icons.workspace_premium_outlined, [
    Row(children: [
      Expanded(child: Text('Inscrit au registre (LOF / LOOF…)',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
      Switch(
        value: _pedigree,
        onChanged: (v) => setState(() => _pedigree = v),
        activeColor: _green,
      ),
    ]),
    const SizedBox(height: 10),
    _label('Club de race / Association pedigree (optionnel)'),
    _textField(_clubRegistreCtrl, 'Ex: SCC, Club du Berger Australien…'),
    const SizedBox(height: 10),
    _label("N° d'inscription au registre (optionnel)"),
    _textField(_pedigreeLofCtrl, 'Ex: LOF 12345/00, LOOF 67890…'),
  ]);

  Widget _sectionPere() => _card('Père', Icons.male, [
    if (_pereSelected != null) ...[
      _parentChip(
        label: _nomPereCtrl.text.isNotEmpty ? _nomPereCtrl.text : 'Père lié',
        onClear: () => setState(() {
          _pereSelected = null;
          _nomPereCtrl.clear(); _pucePereCtrl.clear();
        }),
      ),
      const SizedBox(height: 10),
    ],
    OutlinedButton.icon(
      onPressed: _pickPere,
      icon: const Icon(Icons.search, size: 16, color: _teal),
      label: Text(_pereSelected != null ? 'Changer d\'animal' : 'Chercher dans mes animaux',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
      style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _teal),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14)),
    ),
    const SizedBox(height: 12),
    _label('Nom du père'),
    _textField(_nomPereCtrl, 'Nom', enabled: _pereSelected == null),
    const SizedBox(height: 10),
    _label('Identification (puce / tatouage)'),
    _textField(_pucePereCtrl, 'Numéro de puce ou tatouage', enabled: _pereSelected == null),
  ]);

  Widget _sectionMere() => _card('Mère', Icons.female, [
    if (_mereSelected != null) ...[
      _parentChip(
        label: _nomMereCtrl.text.isNotEmpty ? _nomMereCtrl.text : 'Mère liée',
        onClear: () => setState(() {
          _mereSelected = null;
          _nomMereCtrl.clear(); _puceMereCtrl.clear();
          _raceMereCtrl.clear(); _dateNaissanceMere = null;
        }),
      ),
      const SizedBox(height: 10),
    ],
    OutlinedButton.icon(
      onPressed: _pickMere,
      icon: const Icon(Icons.search, size: 16, color: _teal),
      label: Text(_mereSelected != null ? 'Changer d\'animal' : 'Chercher dans mes animaux',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
      style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _teal),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14)),
    ),
    const SizedBox(height: 12),
    _label('Nom de la mère'),
    _textField(_nomMereCtrl, 'Nom', enabled: _mereSelected == null),
    const SizedBox(height: 10),
    _label('Identification (puce / tatouage)'),
    _textField(_puceMereCtrl, 'Numéro de puce ou tatouage', enabled: _mereSelected == null),
    const SizedBox(height: 10),
    _label('Race de la mère'),
    _raceMereField(enabled: _mereSelected == null),
    const SizedBox(height: 10),
    _label('Date de naissance de la mère'),
    _datePicker(
      'Sélectionner une date',
      _dateNaissanceMere,
      _mereSelected == null ? (d) => setState(() => _dateNaissanceMere = d) : null,
    ),
  ]);

  Widget _sectionAnimaux() => _card(
    'Animaux de la portée',
    Icons.pets,
    [
      Row(children: [
        Expanded(child: Text('${_animaux.length} animal${_animaux.length > 1 ? 'aux' : ''}',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: Colors.grey.shade500))),
      ]),
      const SizedBox(height: 12),
      ..._animaux.asMap().entries.map((e) => _animalRow(e.key, e.value)),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _addAnimal,
        icon: const Icon(Icons.add, color: _teal, size: 16),
        label: const Text('Ajouter un animal',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
        style: OutlinedButton.styleFrom(
            side: BorderSide(color: _teal.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14)),
      ),
    ],
  );

  Widget _animalRow(int index, _AnimalRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Photo
          GestureDetector(
            onTap: () => _pickPhoto(index),
            child: Stack(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF5EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: row.photoFile != null
                    ? Image.file(row.photoFile!, fit: BoxFit.cover)
                    : const Icon(Icons.camera_alt_outlined, color: Color(0xFF6E9E57), size: 26),
              ),
              if (_uploadingPhotoIdx == index)
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(child: Row(children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Center(child: Text('${index + 1}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 11, color: _teal))),
            ),
            const SizedBox(width: 8),
            const Text('Animal', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                fontSize: 13, color: Color(0xFF1F2A2E))),
            const Spacer(),
            if (_animaux.length > 1)
              GestureDetector(
                onTap: () => _removeAnimal(index),
                child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
              ),
          ])),
        ]),
        const SizedBox(height: 10),
        // Nom + identification
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Nom (optionnel)'),
            _textField(row.nom, 'Nom'),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('N° identification'),
            _textField(row.ident, 'Puce / tatouage'),
          ])),
        ]),
        const SizedBox(height: 10),
        // Sexe
        _label('Sexe'),
        Wrap(spacing: 8, children: [
          for (final s in [('male', '♂ Mâle'), ('femelle', '♀ Femelle')])
            GestureDetector(
              onTap: () => setState(() => row.sexe = s.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: row.sexe == s.$1 ? _teal : Colors.transparent,
                  border: Border.all(color: row.sexe == s.$1 ? _teal : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: row.sexe == s.$1 ? Colors.white : Colors.grey)),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        // Couleur + Passeport
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Couleur / Robe'),
            _textField(row.couleur, 'Ex: Fauve, Tricolore…'),
          ])),
          if (_espece != 'oiseau') ...[
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Passeport européen'),
              _textField(row.passeport, 'N° passeport'),
            ])),
          ],
        ]),
        // Type de poil (chien/chat)
        if (_espece == 'chien' || _espece == 'chat') ...[
          const SizedBox(height: 10),
          _label('Type de poil'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in _kTypesPoil)
              GestureDetector(
                onTap: () => setState(() => row.typePoil = row.typePoil == t ? '' : t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: row.typePoil == t ? _teal : Colors.transparent,
                    border: Border.all(color: row.typePoil == t ? _teal : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: row.typePoil == t ? Colors.white : Colors.grey.shade600)),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        // Taille + Poids
        Row(children: [
          if (_espece != 'oiseau') ...[
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(_espece == 'cheval' ? 'Taille au garrot (cm)' : 'Taille (cm)'),
              _textField(row.taille, 'cm'),
            ])),
            const SizedBox(width: 10),
          ],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Poids (kg)'),
            _textField(row.poids, 'kg'),
          ])),
        ]),
        const SizedBox(height: 10),
        // Stérilisé
        Row(children: [
          Expanded(child: Text('Stérilisé(e)',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
          Switch(
            value: row.sterilise,
            onChanged: (v) => setState(() => row.sterilise = v),
            activeColor: _green,
          ),
        ]),
        const SizedBox(height: 6),
        // Notes
        _label('Notes (optionnel)'),
        TextFormField(
          controller: row.notes,
          maxLines: 2,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
          decoration: _inputDeco('Particularités, remarques…'),
        ),
      ]),
    );
  }

  // ─── Helpers visuels (même style que create_annonce_page) ─────────────────────

  Widget _card(String title, IconData icon, List<Widget> children) => Container(
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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

  static InputDecoration _inputDeco(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    suffixIcon: suffix,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _teal)),
    filled: true, fillColor: const Color(0xFFF8F9FA),
  );

  Widget _textField(TextEditingController ctrl, String hint, {bool enabled = true}) =>
      TextFormField(
        controller: ctrl,
        enabled: enabled,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
        decoration: _inputDeco(hint),
      );

  Widget _raceField() {
    final breeds = _currentBreeds;
    if (breeds.isEmpty) return _textField(_raceCtrl, 'Ex: Berger Australien, Angora…');
    return GestureDetector(
      onTap: () async {
        final sel = await _openBreedPicker(breeds, 'Race de la portée', _raceCtrl.text);
        if (sel != null) setState(() => _raceCtrl.text = sel);
      },
      child: AbsorbPointer(
        child: TextFormField(
          controller: _raceCtrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
          decoration: _inputDeco('Appuyer pour choisir une race…',
              suffix: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF6F767B))),
        ),
      ),
    );
  }

  Widget _raceMereField({required bool enabled}) {
    final breeds = _currentBreeds;
    if (breeds.isEmpty || !enabled) return _textField(_raceMereCtrl, 'Race', enabled: enabled);
    return GestureDetector(
      onTap: () async {
        final sel = await _openBreedPicker(breeds, 'Race de la mère', _raceMereCtrl.text);
        if (sel != null) setState(() => _raceMereCtrl.text = sel);
      },
      child: AbsorbPointer(
        child: TextFormField(
          controller: _raceMereCtrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
          decoration: _inputDeco('Appuyer pour choisir une race…',
              suffix: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF6F767B))),
        ),
      ),
    );
  }

  Future<String?> _openBreedPicker(List<String> breeds, String label, String current) {
    return showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BreedPickerSheet(breeds: breeds, label: label, current: current),
    );
  }

  Widget _datePicker(String label, DateTime? value, ValueChanged<DateTime>? onPick) {
    final enabled = onPick != null;
    return GestureDetector(
      onTap: enabled ? () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(
              data: ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(primary: _teal)),
              child: child!),
        );
        if (d != null) onPick(d);
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6F767B)),
          const SizedBox(width: 8),
          Text(
            value != null ? _fmt.format(value) : label,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: value != null ? const Color(0xFF1F2A2E) : const Color(0xFF9CA3AF)),
          ),
        ]),
      ),
    );
  }

  Widget _especeChips() {
    final species = kSpeciesData.where((s) => s.value != 'tous').toList();
    return Wrap(spacing: 8, runSpacing: 6,
      children: species.map((sp) => GestureDetector(
        onTap: () => _onEspeceChanged(sp.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _espece == sp.value ? sp.color : Colors.transparent,
            border: Border.all(color: _espece == sp.value ? sp.color : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            speciesIcon(sp.value, 13, _espece == sp.value ? Colors.white : sp.color),
            const SizedBox(width: 5),
            Text(sp.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _espece == sp.value ? Colors.white : Colors.black87)),
          ]),
        ),
      )).toList(),
    );
  }

  Widget _parentChip({required String label, required VoidCallback onClear}) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _teal.withValues(alpha: 0.2))),
        child: Row(children: [
          const Icon(Icons.link, size: 14, color: _teal),
          const SizedBox(width: 8),
          Expanded(child: Text('Lié : $label',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600, color: _teal),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          GestureDetector(onTap: onClear,
              child: const Icon(Icons.close, size: 16, color: Color(0xFF6F767B))),
        ]),
      );
}

// ─── Sheet sélection animal existant ─────────────────────────────────────────

class _AnimalPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final String title;
  const _AnimalPickerSheet({required this.animals, required this.title});
  @override State<_AnimalPickerSheet> createState() => _AnimalPickerSheetState();
}

class _AnimalPickerSheetState extends State<_AnimalPickerSheet> {
  late List<Map<String, dynamic>> _filtered;
  final _searchCtrl = TextEditingController();
  static const _teal = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _filtered = widget.animals;
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? widget.animals
          : widget.animals.where((a) {
              final nom   = (a['nom'] as String? ?? '').toLowerCase();
              final race  = (a['race'] as String? ?? '').toLowerCase();
              return nom.contains(q.toLowerCase()) || race.contains(q.toLowerCase());
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scroll) => Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(child: Text(widget.title,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 17))),
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuler',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _filter,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Rechercher…',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true, fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final a        = _filtered[i];
              final nom      = a['nom']  as String? ?? 'Sans nom';
              final race     = a['race'] as String? ?? '';
              final photoUrl = a['photo_url'] as String? ?? '';
              return ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            width: 44, height: 44, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Center(child: Text('🐾', style: TextStyle(fontSize: 18))),
                          )
                        : const Center(child: Text('🐾', style: TextStyle(fontSize: 18))),
                  ),
                ),
                title: Text(nom, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: race.isNotEmpty ? Text(race, style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))) : null,
                onTap: () => Navigator.pop(context, a),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── Sélecteur de race ────────────────────────────────────────────────────────

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
  static const _teal = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _filtered = widget.breeds;
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? widget.breeds
          : widget.breeds.where((b) => b.toLowerCase().contains(q.toLowerCase())).toList();
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
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: Text(widget.label,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 17))),
              TextButton(onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler',
                      style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final b        = _filtered[i];
                final selected = b == widget.current;
                return ListTile(
                  title: Text(b, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      color: selected ? _teal : const Color(0xFF1F2A2E))),
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: _teal, size: 18)
                      : null,
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
