import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/particulier/partage_animal_sheet.dart';
import 'package:PetsMatch/pages/pro/pension_journal_page.dart';
import 'package:PetsMatch/pages/pro/education_rapports_page.dart';
import 'package:PetsMatch/pages/pro/animal_devis_page.dart';
import 'package:PetsMatch/widgets/vet_share_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class _ContactUrgenceP {
  final TextEditingController nom;
  final TextEditingController tel;
  _ContactUrgenceP({String nomVal = '', String telVal = ''})
      : nom = TextEditingController(text: nomVal),
        tel = TextEditingController(text: telVal);
  void dispose() { nom.dispose(); tel.dispose(); }
}

class AnimalFicheParticulierPage extends StatefulWidget {
  final String? animalId;
  final Map<String, dynamic>? initialData;

  const AnimalFicheParticulierPage({super.key, this.animalId, this.initialData});

  @override
  State<AnimalFicheParticulierPage> createState() => _AnimalFicheParticulierPageState();
}

class _AnimalFicheParticulierPageState extends State<AnimalFicheParticulierPage>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  final _supa = Supabase.instance.client;
  late TabController _tabs;

  bool _saving = false;
  String? _animalId;

  // Active alert
  String? _activeAlerteId;
  String? _alerteStatut; // 'perdu' or 'retrouve'

  // Identity fields
  final _nomCtrl      = TextEditingController();
  final _raceCtrl     = TextEditingController();
  final _couleurCtrl  = TextEditingController();
  final _identCtrl    = TextEditingController();
  final _notesCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _passeportCtrl = TextEditingController();
  final _tailleCtrl   = TextEditingController();
  final _poidsCtrl    = TextEditingController();

  String _espece = 'chien';
  String _sexe = 'male';
  bool _sterilise = false;
  DateTime? _dateNaissance;
  String? _typePoil;
  bool _pedigree = false;
  String? _pedigreeLof;
  final _clubRegistreCtrl = TextEditingController();
  final List<_ContactUrgenceP> _contactsUrgence = [];

  bool _editing = false;

  String? _photoUrl;
  File? _photoFile;

  // Pension access (read-only accesses granted to pros)
  List<Map<String, dynamic>> _pensionAcces = [];
  bool _hasPensionUpdates = false;
  bool _hasEducationRapports = false;
  bool _hasDevis = false;

  // Health records
  bool _loadingHealth = false;
  List<Map<String, dynamic>> _vaccinations = [];
  List<Map<String, dynamic>> _traitements = [];
  List<Map<String, dynamic>> _visites = [];
  List<Map<String, dynamic>> _vermifuges = [];
  List<Map<String, dynamic>> _antiparasitaires = [];
  List<Map<String, dynamic>> _allergies = [];
  List<Map<String, dynamic>> _poids = [];

  Map<String, List<String>> _allBreeds = {};

  static const _especes = [
    'chien', 'chat', 'lapin', 'oiseau', 'nac',
    'cheval', 'ovin', 'caprin', 'porcin', 'autre'
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _animalId = widget.animalId;
    _editing = widget.animalId == null; // nouveau animal → direct en édition
    _fillFromData(widget.initialData);
    _loadBreeds();
    if (_animalId != null) { _loadHealthRecords(); _loadActiveAlerte(); _refreshFromSupabase(); }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nomCtrl.dispose();
    _raceCtrl.dispose();
    _couleurCtrl.dispose();
    _identCtrl.dispose();
    _notesCtrl.dispose();
    _descCtrl.dispose();
    _passeportCtrl.dispose();
    _tailleCtrl.dispose();
    _poidsCtrl.dispose();
    _clubRegistreCtrl.dispose();
    for (final c in _contactsUrgence) c.dispose();
    super.dispose();
  }

  Future<void> _refreshFromSupabase() async {
    try {
      final data = await _supa.from('animaux').select('*').eq('id', _animalId!).single();
      if (mounted) setState(() => _fillFromData(Map<String, dynamic>.from(data)));
    } catch (_) {}
    _loadPensionAcces();
  }

  Future<void> _loadPensionAcces() async {
    if (_animalId == null) return;
    try {
      final rows = await _supa
          .from('animal_access')
          .select('id, pro_profile_id, created_at, permissions')
          .eq('animal_id', _animalId!)
          .eq('statut', 'active')
          .contains('permissions', ['write_notes']);
      if (mounted) setState(() => _pensionAcces = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
    try {
      final updates = await _supa.from('pension_updates').select('id').eq('animal_id', _animalId!).limit(1);
      if (mounted) setState(() => _hasPensionUpdates = (updates as List).isNotEmpty);
    } catch (_) {}
    try {
      final rapports = await _supa.from('education_progression').select('id').eq('animal_id', _animalId!).limit(1);
      if (mounted) setState(() => _hasEducationRapports = (rapports as List).isNotEmpty);
    } catch (_) {}
    try {
      final devis = await _supa.from('devis').select('id').eq('animal_id', _animalId!).limit(1);
      if (mounted) setState(() => _hasDevis = (devis as List).isNotEmpty);
    } catch (_) {}
  }

  Future<void> _revokePensionAcces(String accesId, String proNom) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Révoquer l\'accès ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text(
          '$proNom n\'aura plus accès à la fiche de ${_nomCtrl.text}.',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Révoquer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _supa.from('animal_access').update({'statut': 'revoked', 'revoked_at': DateTime.now().toUtc().toIso8601String()}).eq('id', accesId);
      _loadPensionAcces();
    }
  }

  void _fillFromData(Map<String, dynamic>? d) {
    if (d == null) return;
    _nomCtrl.text      = d['nom'] ?? '';
    _raceCtrl.text     = d['race'] ?? '';
    _couleurCtrl.text  = d['couleur'] ?? '';
    _identCtrl.text    = d['identification'] ?? '';
    _notesCtrl.text    = d['notes'] ?? '';
    _descCtrl.text     = d['description'] ?? '';
    _passeportCtrl.text    = d['passeport_europeen'] ?? '';
    _tailleCtrl.text       = d['taille']?.toString() ?? '';
    _poidsCtrl.text        = d['poids']?.toString() ?? '';
    _typePoil              = d['type_poil'] as String?;
    _pedigree              = d['pedigree'] ?? false;
    _pedigreeLof           = d['pedigree_lof'] as String?;
    _clubRegistreCtrl.text = d['club_registre'] ?? '';
    for (final c in _contactsUrgence) c.dispose();
    _contactsUrgence.clear();
    final contacts = d['contacts_urgence'];
    for (final raw in (contacts is List ? contacts : [])) {
      _contactsUrgence.add(_ContactUrgenceP(
          nomVal: raw['nom'] ?? '', telVal: raw['tel'] ?? ''));
    }
    _espece    = d['espece'] ?? 'chien';
    _sexe      = d['sexe'] ?? 'male';
    _sterilise = d['sterilise'] ?? false;
    _photoUrl  = d['photo_url'];
    if (d['date_naissance'] != null) {
      try { _dateNaissance = DateTime.parse(d['date_naissance'].toString()); } catch (_) {}
    }
  }

  Future<void> _loadBreeds() async {
    const assets = {
      'chien': 'assets/dog_breeds.json', 'chat': 'assets/cat_breeds.json',
      'cheval': 'assets/horse_breeds.json', 'lapin': 'assets/rabbit_breeds.json',
      'oiseau': 'assets/bird_breeds.json', 'nac': 'assets/nac_breeds.json',
      'ovin': 'assets/sheep_breeds.json', 'caprin': 'assets/goat_breeds.json',
      'porcin': 'assets/pig_breeds.json',
    };
    final loaded = <String, List<String>>{};
    for (final e in assets.entries) {
      try {
        final raw = await rootBundle.loadString(e.value);
        loaded[e.key] = List<String>.from(jsonDecode(raw));
      } catch (_) { loaded[e.key] = []; }
    }
    if (mounted) setState(() => _allBreeds = loaded);
  }

  Future<void> _loadHealthRecords() async {
    if (_animalId == null) return;
    setState(() => _loadingHealth = true);
    try {
      final results = await Future.wait([
        _supa.from('vaccinations').select().eq('animal_id', _animalId!).order('date', ascending: false),
        _supa.from('traitements').select().eq('animal_id', _animalId!).order('date', ascending: false),
        _supa.from('visites').select().eq('animal_id', _animalId!).order('date', ascending: false),
        _supa.from('vermifuges').select().eq('animal_id', _animalId!).order('date', ascending: false),
        _supa.from('antiparasitaires').select().eq('animal_id', _animalId!).order('date', ascending: false),
        _supa.from('allergies').select().eq('animal_id', _animalId!).order('date', ascending: false),
        _supa.from('poids').select().eq('animal_id', _animalId!).order('date', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _vaccinations = List<Map<String, dynamic>>.from(results[0]);
        _traitements = List<Map<String, dynamic>>.from(results[1]);
        _visites = List<Map<String, dynamic>>.from(results[2]);
        _vermifuges = List<Map<String, dynamic>>.from(results[3]);
        _antiparasitaires = List<Map<String, dynamic>>.from(results[4]);
        _allergies = List<Map<String, dynamic>>.from(results[5]);
        _poids = List<Map<String, dynamic>>.from(results[6]);
        _loadingHealth = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHealth = false);
    }
  }

  Future<void> _pickPhoto() async {
    final f = await pickAndCropSquare();
    if (f != null) setState(() => _photoFile = f);
  }

  Future<String?> _uploadPhoto() async {
    if (_photoFile == null) return _photoUrl;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    return uploadPhoto(_photoFile!, 'animaux/$uid/$name');
  }

  Future<void> _save() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le nom est requis'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final photoUrl = await _uploadPhoto();
      final uid = User_Info.uid;
      final data = {
        'nom': nom,
        'espece': _espece,
        'race': _raceCtrl.text.trim().isEmpty ? null : _raceCtrl.text.trim(),
        'sexe': _sexe,
        'sterilise': _sterilise,
        'couleur': _couleurCtrl.text.trim().isEmpty ? null : _couleurCtrl.text.trim(),
        'identification': _identCtrl.text.trim().isEmpty ? null : _identCtrl.text.trim(),
        'passeport_europeen': _passeportCtrl.text.trim().isEmpty ? null : _passeportCtrl.text.trim(),
        'type_poil': _typePoil,
        'taille': _tailleCtrl.text.trim().isEmpty ? null : double.tryParse(_tailleCtrl.text.trim()),
        'poids': _poidsCtrl.text.trim().isEmpty ? null : double.tryParse(_poidsCtrl.text.trim()),
        'pedigree': _pedigree,
        'pedigree_lof': _pedigreeLof,
        'club_registre': _clubRegistreCtrl.text.trim().isEmpty ? null : _clubRegistreCtrl.text.trim(),
        'contacts_urgence': _contactsUrgence
            .map((c) => {'nom': c.nom.text.trim(), 'tel': c.tel.text.trim()})
            .where((c) => c['nom']!.isNotEmpty || c['tel']!.isNotEmpty)
            .toList(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'photo_url': photoUrl,
        'date_naissance': _dateNaissance?.toIso8601String().substring(0, 10),
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_animalId == null) {
        final id = '${DateTime.now().millisecondsSinceEpoch}';
        await _supa.from('animaux').insert({
          'id': id,
          'uid_eleveur': null,
          'uid_proprietaire': uid,
          ...data,
          'created_at': DateTime.now().toIso8601String(),
        });
        setState(() { _animalId = id; _photoFile = null; _photoUrl = photoUrl; _editing = false; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Animal ajouté ✓'), backgroundColor: _green));
          _loadHealthRecords();
          final isYoung = _dateNaissance != null &&
              DateTime.now().difference(_dateNaissance!).inDays < 120;
          _showInsuranceCta(
            reason: isYoung ? '🐾 Animal de moins de 4 mois — c\'est le moment idéal pour assurer !' : null,
          );
        }
      } else {
        await _supa.from('animaux').update(data).eq('id', _animalId!);
        setState(() { _photoFile = null; _photoUrl = photoUrl; _editing = false; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Modifications enregistrées ✓'), backgroundColor: _green));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showInsuranceCta({String? reason}) async {
    try {
      final partners = await _supa
          .from('marketplace_partners')
          .select('id, nom, site_url, description')
          .eq('statut', 'actif')
          .eq('categorie', 'assurance')
          .limit(1);
      if (partners.isEmpty || !mounted) return;
      final partner = (partners as List).first as Map<String, dynamic>;

      await _supa.from('marketplace_events').insert({
        'partner_id': partner['id'],
        'event_type': 'lead',
        'placement': 'animal_creation',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Text('🛡️ ', style: TextStyle(fontSize: 22)),
              Expanded(
                child: Text('Protégez votre animal',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(reason,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600)),
                ),
              Text('${partner['nom']} vous propose une couverture santé adaptée à votre compagnon.',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
              if ((partner['description'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(partner['description'],
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Plus tard',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6E9E57),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final url = partner['site_url'] as String?;
                if (url != null && url.isNotEmpty) {
                  final uri = Uri.tryParse(url);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Obtenir un devis',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final title = _nomCtrl.text.isEmpty ? 'Nouvel animal' : _nomCtrl.text;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        actions: [
          if (_animalId != null) ...[
            IconButton(
              icon: const Icon(Icons.link, size: 20),
              tooltip: 'Partager la fiche',
              onPressed: () => showPartageAnimalSheet(
                  context, _animalId!, _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              tooltip: 'Partager avec mon vétérinaire',
              onPressed: () => showVetShareSheet(context, _animalId!),
            ),
          ],
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else if (_editing)
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (_animalId != null)
                TextButton(
                  onPressed: () => setState(() { _editing = false; _refreshFromSupabase(); }),
                  child: const Text('Annuler',
                      style: TextStyle(fontFamily: 'Galey', color: Colors.white70)),
                ),
              TextButton(
                onPressed: _save,
                child: const Text('Enregistrer',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ])
          else
            TextButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white),
              label: const Text('Modifier',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Identité'), Tab(text: 'Carnet de santé'), Tab(text: 'Alimentation')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildIdentiteTab(), _buildSanteTab(), _buildAlimentationTab()],
      ),
    );
  }

  // ── Identité ──────────────────────────────────────────────────────────────────

  Widget _buildIdentiteTab() => _editing ? _buildIdentiteForm() : _buildIdentiteView();

  // Vue lecture ─────────────────────────────────────────────────────────────────

  Widget _buildIdentiteView() {
    final dob = _dateNaissance;
    String? ageStr;
    if (dob != null) {
      final now = DateTime.now();
      final years = now.year - dob.year -
          ((now.month < dob.month || (now.month == dob.month && now.day < dob.day)) ? 1 : 0);
      ageStr = years == 0
          ? '${((now.difference(dob).inDays) / 30.5).floor()} mois'
          : '$years an${years > 1 ? 's' : ''}';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Photo
        Center(
          child: CircleAvatar(
            radius: 60,
            backgroundColor: const Color(0xFFCCE8EE),
            backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                ? CachedNetworkImageProvider(_photoUrl!) : null,
            child: (_photoUrl == null || _photoUrl!.isEmpty)
                ? const Icon(Icons.pets, size: 48, color: _teal) : null,
          ),
        ),
        const SizedBox(height: 16),

        // Nom centré
        Center(
          child: Text(_nomCtrl.text.isNotEmpty ? _nomCtrl.text : 'Sans nom',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 22,
                  fontWeight: FontWeight.w800, color: Color(0xFF1F2A2E))),
        ),
        if (ageStr != null) ...[
          const SizedBox(height: 4),
          Center(child: Text(ageStr,
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500))),
        ],
        const SizedBox(height: 16),

        // Chips espèce / sexe / stérilisé
        Center(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            _viewChip(_capitalize(_espece), _teal),
            _viewChip(
              _sexe == 'male' ? '♂ Mâle' : _sexe == 'femelle' ? '♀ Femelle' : 'Sexe inconnu',
              Colors.blueGrey,
            ),
            if (_sterilise) _viewChip('✂️ Stérilisé(e)', _green),
          ]),
        ),
        const SizedBox(height: 24),

        // Infos
        if (_raceCtrl.text.isNotEmpty) _infoRow('Race', _raceCtrl.text),
        if (dob != null) _infoRow('Date de naissance', DateFormat('dd/MM/yyyy').format(dob)),
        if (_couleurCtrl.text.isNotEmpty) _infoRow('Couleur / robe', _couleurCtrl.text),
        if (_typePoil != null) _infoRow('Type de poil', _typePoil!),
        if (_tailleCtrl.text.isNotEmpty) _infoRow(_tailleLabelFor(_espece), '${_tailleCtrl.text} cm'),
        if (_poidsCtrl.text.isNotEmpty) _infoRow('Poids', '${_poidsCtrl.text} kg'),
        if (_identCtrl.text.isNotEmpty) _infoRow('Identification', _identCtrl.text),
        if (_passeportCtrl.text.isNotEmpty) _infoRow('Passeport européen', _passeportCtrl.text),
        if (_pedigree) ...[
          _infoRow(_pediConfig(_espece).sectionLabel,
              [if (_pedigreeLof != null) _pedigreeLof!, if (_clubRegistreCtrl.text.isNotEmpty) _clubRegistreCtrl.text].join(' — ')),
        ],
        if (_contactsUrgence.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Contacts urgence', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                  fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.4)),
              const SizedBox(height: 6),
              ..._contactsUrgence.where((c) => c.nom.text.isNotEmpty || c.tel.text.isNotEmpty).map((c) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.phone_outlined, size: 15, color: Color(0xFF0C5C6C)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      [if (c.nom.text.isNotEmpty) c.nom.text, if (c.tel.text.isNotEmpty) c.tel.text].join(' — '),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
                    )),
                  ]),
                ),
              ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
            ]),
          ),
        ],
        if (_descCtrl.text.isNotEmpty) _infoRow('Description', _descCtrl.text),
        if (_notesCtrl.text.isNotEmpty) _infoRow('Notes', _notesCtrl.text),

        if (_hasPensionUpdates) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PensionJournalPage(
                    animalId: _animalId,
                    animalNom: _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text,
                    readOnly: true,
                  ),
                )),
                icon: const Icon(Icons.photo_camera_back_outlined, size: 16),
                label: const Text('📸 Nouvelles de la pension',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6E9E57),
                  side: const BorderSide(color: Color(0xFF6E9E57)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
        if (_hasEducationRapports) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => EducationRapportsPage(
                    animalId: _animalId,
                    animalNom: _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text,
                  ),
                )),
                icon: const Icon(Icons.school_outlined, size: 16),
                label: const Text('🐾 Suivi de progression',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7B5EA7),
                  side: const BorderSide(color: Color(0xFF7B5EA7)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
        if (_hasDevis) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnimalDevisPage(
                    animalId: _animalId,
                    animalNom: _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text,
                  ),
                )),
                icon: const Icon(Icons.request_quote_outlined, size: 16),
                label: const Text('🧾 Devis reçu(s)',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0C5C6C),
                  side: const BorderSide(color: Color(0xFF0C5C6C)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
        // Accès lecture pension actifs
        if (_pensionAcces.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Accès pension actifs',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              for (final a in _pensionAcces)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B5EA7).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7B5EA7).withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.home_work_outlined, size: 18, color: Color(0xFF7B5EA7)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a['pro_nom']?.toString() ?? 'Structure',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                              fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                      if (a['created_at'] != null)
                        Text('Depuis le ${_fmtDate(a['created_at'].toString().substring(0, 10))}',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: Color(0xFF9CA3AF))),
                    ])),
                    TextButton(
                      onPressed: () => _revokePensionAcces(
                          a['id'] as String, a['pro_nom']?.toString() ?? 'Structure'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Révoquer',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              const Divider(height: 20, color: Color(0xFFEEEEEE)),
            ]),
          ),
        ],

        // Actions (alerte perdu + transfert)
        if (_animalId != null) ...[
          const SizedBox(height: 8),
          if (_alerteStatut == 'perdu') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Alerte perdu active',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        fontWeight: FontWeight.w600, color: Colors.orange.shade800))),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _BigActionBtn(
                label: 'Modifier l\'alerte',
                icon: Icons.edit_outlined,
                color: Colors.orange.shade700,
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AlertePerduFormPage(alerteId: _activeAlerteId)));
                  _loadActiveAlerte();
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _BigActionBtn(
                label: 'Retrouvé !',
                icon: Icons.check_circle_outline,
                color: _green,
                onPressed: _marquerRetrouve,
              )),
            ]),
          ] else ...[
            _BigActionBtn(
              label: 'Déclarer perdu',
              icon: Icons.location_searching,
              color: Colors.orange.shade700,
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AlertePerduFormPage(
                    animalId: _animalId,
                    nom: _nomCtrl.text,
                    espece: _espece,
                    race: _raceCtrl.text,
                    sexe: _sexe,
                    couleur: _couleurCtrl.text,
                    photoUrl: _photoUrl,
                  ),
                ));
                _loadActiveAlerte();
              },
            ),
          ],
        ],
      ]),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11,
          fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.4)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Color(0xFF1F2A2E))),
      const Divider(height: 20, color: Color(0xFFEEEEEE)),
    ]),
  );

  Widget _viewChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
        fontWeight: FontWeight.w600, color: color)),
  );

  // Formulaire d'édition ────────────────────────────────────────────────────────

  Widget _buildIdentiteForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: const Color(0xFFCCE8EE),
                    backgroundImage: _photoFile != null
                        ? FileImage(_photoFile!) as ImageProvider
                        : (_photoUrl != null && _photoUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(_photoUrl!)
                            : null),
                    child: (_photoFile == null && (_photoUrl == null || _photoUrl!.isEmpty))
                        ? const Icon(Icons.pets, size: 44, color: _teal)
                        : null,
                  ),
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: _teal,
                    child: Icon(Icons.camera_alt, size: 15, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          _FLabel('Nom *'),
          const SizedBox(height: 6),
          _FField(controller: _nomCtrl, hint: 'Ex: Rex, Luna...'),
          const SizedBox(height: 18),

          _FLabel('Espèce'),
          const SizedBox(height: 6),
          _DropdownCard(
            value: _espece,
            items: _especes,
            display: _capitalize,
            onChanged: (v) => setState(() { _espece = v; _raceCtrl.clear(); }),
          ),
          const SizedBox(height: 18),

          _FLabel('Race'),
          const SizedBox(height: 6),
          _buildRaceField(),
          const SizedBox(height: 18),

          _FLabel('Sexe'),
          const SizedBox(height: 8),
          _SexeRow(value: _sexe, onChanged: (v) => setState(() => _sexe = v)),
          const SizedBox(height: 18),

          _FLabel('Date de naissance'),
          const SizedBox(height: 6),
          _DateField(
            date: _dateNaissance,
            onPicked: (d) => setState(() => _dateNaissance = d),
          ),
          const SizedBox(height: 18),

          _FLabel('Couleur / robe'),
          const SizedBox(height: 6),
          _FField(controller: _couleurCtrl, hint: 'Ex: Roux, Noir et blanc...'),
          const SizedBox(height: 18),

          _FLabel('Identification (puce / tatouage)'),
          const SizedBox(height: 6),
          _FField(controller: _identCtrl, hint: 'Numéro de puce ou tatouage'),
          const SizedBox(height: 18),

          Row(children: [
            _FLabel('Stérilisé(e)'),
            const Spacer(),
            Switch(
              value: _sterilise,
              activeColor: _teal,
              onChanged: (v) => setState(() => _sterilise = v),
            ),
          ]),
          const SizedBox(height: 18),

          _FLabel('Passeport européen n°'),
          const SizedBox(height: 6),
          _FField(controller: _passeportCtrl, hint: 'Numéro de passeport'),
          const SizedBox(height: 18),

          if (_espece == 'chien' || _espece == 'chat') ...[
            _FLabel('Type de poil'),
            const SizedBox(height: 6),
            _buildTypePoilDropdown(),
            const SizedBox(height: 18),
          ],

          _FLabel(_tailleLabelFor(_espece)),
          const SizedBox(height: 6),
          _FField(
            controller: _tailleCtrl,
            hint: 'Ex: 65',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 18),

          _FLabel('Poids (kg)'),
          const SizedBox(height: 6),
          _FField(
            controller: _poidsCtrl,
            hint: 'Ex: 12.5',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 18),

          _buildPedigreeSection(),
          const SizedBox(height: 18),

          _buildContactsUrgenceSection(),
          const SizedBox(height: 18),

          _FLabel('Description'),
          const SizedBox(height: 6),
          _FMultiField(controller: _descCtrl, hint: 'Décrivez votre animal...'),
          const SizedBox(height: 18),

          _FLabel('Notes'),
          const SizedBox(height: 6),
          _FMultiField(controller: _notesCtrl, hint: 'Notes personnelles...'),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildRaceField() {
    final breeds = _allBreeds[_espece] ?? [];
    if (breeds.isEmpty) return _FField(controller: _raceCtrl, hint: 'Race');
    return GestureDetector(
      onTap: () => _openRaceBreedPicker(breeds),
      child: AbsorbPointer(
        child: _FField(controller: _raceCtrl, hint: 'Ex: Labrador, Maine Coon...'),
      ),
    );
  }

  static String _tailleLabelFor(String espece) {
    if (espece == 'cheval') return 'Taille au garrot (cm)';
    if (espece == 'oiseau') return 'Envergure (cm)';
    return 'Taille (cm)';
  }

  Widget _buildTypePoilDropdown() {
    const options = ['Court', 'Mi-long', 'Long', 'Frisé', 'Fil de soie', 'Ras'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: DropdownButtonFormField<String>(
        value: _typePoil,
        hint: const Text('Type de poil', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _teal)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          isDense: true,
        ),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: (v) => setState(() => _typePoil = v),
      ),
    );
  }

  static const _pedigreeConfigs = <String, ({
    String sectionLabel, String yesLabel, String typeLabel,
    List<String> typeOptions, String clubLabel,
  })>{
    'chien': (sectionLabel: 'Pedigree', yesLabel: 'Avec pedigree',
      typeLabel: 'Type LOF', typeOptions: ['LOF', 'Non-LOF'],
      clubLabel: 'Club de race (SCC, etc.)'),
    'chat': (sectionLabel: 'Pedigree', yesLabel: 'Avec pedigree',
      typeLabel: 'Type LOOF', typeOptions: ['LOOF', 'Non-LOOF'],
      clubLabel: 'Club de race (LOOF, etc.)'),
    'cheval': (sectionLabel: 'Stud-book / SIRE', yesLabel: 'Inscrit',
      typeLabel: 'Registre', typeOptions: ['Stud-book', 'Registre d\'élevage', 'Non-inscrit'],
      clubLabel: 'Studbook / Association'),
    'lapin': (sectionLabel: 'Livre de race', yesLabel: 'Inscrit',
      typeLabel: 'Type', typeOptions: ['Livre de race', 'Non-inscrit'],
      clubLabel: 'Club / Association (ASCC, etc.)'),
    'oiseau': (sectionLabel: 'Bague / Origine', yesLabel: 'Bagué',
      typeLabel: 'Type', typeOptions: ['Bagué fermé', 'Bagué ouvert', 'Non-bagué'],
      clubLabel: 'Éleveur / Association'),
    'ovin': (sectionLabel: 'Livre généalogique', yesLabel: 'Inscrit',
      typeLabel: 'Type', typeOptions: ['Livre généalogique', 'Non-inscrit'],
      clubLabel: 'Association de race'),
    'caprin': (sectionLabel: 'Livre généalogique', yesLabel: 'Inscrit',
      typeLabel: 'Type', typeOptions: ['Livre généalogique', 'Non-inscrit'],
      clubLabel: 'Association de race'),
    'porcin': (sectionLabel: 'Livre généalogique', yesLabel: 'Inscrit',
      typeLabel: 'Type', typeOptions: ['Livre généalogique LG', 'Non-inscrit'],
      clubLabel: 'Association de race'),
    'nac': (sectionLabel: 'Registre / Origine', yesLabel: 'Avec registre',
      typeLabel: 'Type', typeOptions: ['Registre d\'élevage', 'Non-inscrit'],
      clubLabel: 'Éleveur / Club'),
  };

  static ({String sectionLabel, String yesLabel, String typeLabel, List<String> typeOptions, String clubLabel})
      _pediConfig(String espece) =>
      _pedigreeConfigs[espece] ?? (
        sectionLabel: 'Registre / Origine', yesLabel: 'Avec registre',
        typeLabel: 'Type', typeOptions: ['Inscrit', 'Non-inscrit'],
        clubLabel: 'Club / Association');

  Widget _buildPedigreeSection() {
    final cfg = _pediConfig(_espece);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FLabel(cfg.sectionLabel),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _pedigree = false),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: !_pedigree ? _green : Colors.transparent,
              border: Border.all(color: !_pedigree ? _green : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Non', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: !_pedigree ? Colors.white : const Color(0xFF1F2A2E))),
          ),
        )),
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _pedigree = true),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _pedigree ? _green : Colors.transparent,
              border: Border.all(color: _pedigree ? _green : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(cfg.yesLabel, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: _pedigree ? Colors.white : const Color(0xFF1F2A2E))),
          ),
        )),
      ]),
      if (_pedigree) ...[
        const SizedBox(height: 12),
        Text(cfg.typeLabel,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6,
          children: cfg.typeOptions.map((opt) {
            final active = _pedigreeLof == opt;
            return GestureDetector(
              onTap: () => setState(() => _pedigreeLof = opt),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _teal : Colors.transparent,
                  border: Border.all(color: active ? _teal : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(opt, textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        color: active ? Colors.white : const Color(0xFF1F2A2E))),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _clubRegistreCtrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
          decoration: InputDecoration(
            labelText: cfg.clubLabel,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    ]);
  }

  Widget _buildContactsUrgenceSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Contacts urgence',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 14, color: Color(0xFF1F2A2E))),
          TextButton.icon(
            onPressed: () => setState(() => _contactsUrgence.add(_ContactUrgenceP())),
            icon: const Icon(Icons.add, size: 16, color: _green),
            label: const Text('Ajouter',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ]),
        if (_contactsUrgence.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Aucun contact',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
          ),
        ..._contactsUrgence.asMap().entries.map((e) {
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
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _teal)),
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
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _teal)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                ),
              ])),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => setState(() {
                  _contactsUrgence[i].dispose();
                  _contactsUrgence.removeAt(i);
                }),
              ),
            ]),
          );
        }),
      ]),
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
      builder: (_) => _BreedPickerSheet(breeds: breeds, label: 'Race', current: _raceCtrl.text),
    );
    if (selected != null) setState(() => _raceCtrl.text = selected);
  }

  Future<void> _loadActiveAlerte() async {
    if (_animalId == null) return;
    try {
      final rows = await _supa.from('alertes_perdus')
          .select('id, statut')
          .eq('animal_id', _animalId!)
          .order('created_at', ascending: false)
          .limit(1);
      if ((rows as List).isNotEmpty && mounted) {
        final d = rows.first as Map<String, dynamic>;
        setState(() {
          _activeAlerteId = d['id'] as String?;
          _alerteStatut   = d['statut'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _marquerRetrouve() async {
    if (_activeAlerteId == null) return;
    try {
      await _supa.from('alertes_perdus').update({
        'statut': 'retrouve',
        'date_retrouve': DateTime.now().toIso8601String().substring(0, 10),
      }).eq('id', _activeAlerteId!);
      setState(() => _alerteStatut = 'retrouve');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Animal marqué retrouvé ✓'), backgroundColor: Color(0xFF6E9E57)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
  }

  // ── Carnet de santé ───────────────────────────────────────────────────────────

  Widget _buildSanteTab() {
    if (_animalId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Enregistrez l\'animal pour accéder au carnet de santé.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loadingHealth) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }
    return RefreshIndicator(
      onRefresh: _loadHealthRecords,
      color: _teal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _HealthSection(
            title: 'Vaccinations',
            icon: Icons.vaccines,
            color: const Color(0xFF2196F3),
            records: _vaccinations,
            onAdd: _showVaccinationSheet,
            renderRecord: (r) => _RecordTile(
              title: r['vaccin'] ?? 'Inconnu',
              subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
              trailing: r['date_rappel'] != null ? 'Rappel: ${_fmtDate(r['date_rappel'])}' : null,
              onDelete: () => _deleteRecord('vaccinations', r['id'], _vaccinations),
              onTap: () => _showRecordDetail('Vaccination', r, [
                ('Vaccin', 'vaccin'), ('Date', 'date'), ('Rappel', 'date_rappel'),
                ('N° de lot', 'lot'), ('Vétérinaire', 'veterinaire'),
              ]),
            ),
          ),
          _HealthSection(
            title: 'Traitements',
            icon: Icons.medication,
            color: const Color(0xFF9C27B0),
            records: _traitements,
            onAdd: _showTraitementSheet,
            renderRecord: (r) => _RecordTile(
              title: r['nom'] ?? r['type'] ?? 'Inconnu',
              subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
              trailing: r['posologie'],
              onDelete: () => _deleteRecord('traitements', r['id'], _traitements),
              onTap: () => _showRecordDetail('Traitement', r, [
                ('Nom', 'nom'), ('Type', 'type'), ('Posologie', 'posologie'),
                ('Date début', 'date'), ('Date fin', 'date_fin'),
              ]),
            ),
          ),
          _HealthSection(
            title: 'Visites vétérinaires',
            icon: Icons.local_hospital,
            color: const Color(0xFFF44336),
            records: _visites,
            onAdd: _showVisiteSheet,
            renderRecord: (r) => _RecordTile(
              title: r['motif'] ?? 'Consultation',
              subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
              trailing: r['veterinaire'],
              onDelete: () => _deleteRecord('visites', r['id'], _visites),
              onTap: () => _showRecordDetail('Visite vétérinaire', r, [
                ('Motif', 'motif'), ('Date', 'date'), ('Vétérinaire', 'veterinaire'),
                ('Diagnostic', 'diagnostic'), ('Notes', 'notes'),
              ]),
            ),
          ),
          _HealthSection(
            title: 'Vermifuges',
            icon: Icons.pest_control,
            color: const Color(0xFF795548),
            records: _vermifuges,
            onAdd: _showVermifugeSheet,
            renderRecord: (r) => _RecordTile(
              title: r['produit'] ?? 'Inconnu',
              subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
              trailing: r['date_rappel'] != null ? 'Rappel: ${_fmtDate(r['date_rappel'])}' : null,
              onDelete: () => _deleteRecord('vermifuges', r['id'], _vermifuges),
              onTap: () => _showRecordDetail('Vermifuge', r, [
                ('Produit', 'produit'), ('Dosage', 'dosage'), ('Date', 'date'),
                ('Rappel', 'date_rappel'), ('Notes', 'notes'),
              ]),
            ),
          ),
          _HealthSection(
            title: 'Antiparasitaires',
            icon: Icons.bug_report,
            color: const Color(0xFF4CAF50),
            records: _antiparasitaires,
            onAdd: _showAntiparasitaireSheet,
            renderRecord: (r) => _RecordTile(
              title: r['produit'] ?? 'Inconnu',
              subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
              trailing: r['date_rappel'] != null ? 'Rappel: ${_fmtDate(r['date_rappel'])}' : null,
              onDelete: () => _deleteRecord('antiparasitaires', r['id'], _antiparasitaires),
              onTap: () => _showRecordDetail('Antiparasitaire', r, [
                ('Produit', 'produit'), ('Type', 'type'), ('Fréquence', 'frequence'),
                ('Date', 'date'), ('Rappel', 'date_rappel'), ('Notes', 'notes'),
              ]),
            ),
          ),
          _HealthSection(
            title: 'Allergies',
            icon: Icons.warning_amber,
            color: const Color(0xFFFF9800),
            records: _allergies,
            onAdd: _showAllergieSheet,
            renderRecord: (r) => _RecordTile(
              title: r['description'] ?? 'Allergie',
              subtitle: r['type'],
              trailing: r['severite'],
              onDelete: () => _deleteRecord('allergies', r['id'], _allergies),
              onTap: () => _showRecordDetail('Allergie', r, [
                ('Description', 'description'), ('Type', 'type'), ('Sévérité', 'severite'),
                ('Date', 'date'), ('Notes', 'notes'),
              ]),
            ),
          ),
          _PoidsSectionP(
            records: _poids,
            dateNaissance: _dateNaissance,
            onAdd: _showPoidsSheet,
            onDelete: (r) => _deleteRecord('poids', r['id'], _poids),
            fmtDate: _fmtDate,
          ),
        ],
      ),
    );
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(d.toString())); }
    catch (_) { return d.toString(); }
  }

  Future<void> _deleteRecord(
      String table, String id, List<Map<String, dynamic>> list) async {
    try {
      await _supa.from(table).delete().eq('id', id);
      setState(() => list.removeWhere((r) => r['id'] == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Health form sheets ────────────────────────────────────────────────────────

  void _showVaccinationSheet() {
    final vaccin = TextEditingController(), lot = TextEditingController(),
        veto = TextEditingController();
    DateTime? date, dateRappel;
    _openSheet('Ajouter une vaccination', (ss) => [
      _SFld(ctrl: vaccin, label: 'Vaccin', hint: 'Ex: Rage, CCHPPI...'),
      _SFld(ctrl: lot, label: 'N° de lot', hint: 'Numéro de lot'),
      _SFld(ctrl: veto, label: 'Vétérinaire', hint: 'Nom du vétérinaire'),
      _SDate(label: 'Date', date: date, onPicked: (d) => ss(() => date = d)),
      _SDate(label: 'Date de rappel', date: dateRappel, onPicked: (d) => ss(() => dateRappel = d)),
    ], () async {
      await _supa.from('vaccinations').insert({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'vaccin': vaccin.text.trim(),
        'lot': lot.text.trim().isEmpty ? null : lot.text.trim(),
        'veterinaire': veto.text.trim().isEmpty ? null : veto.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'date_rappel': dateRappel?.toIso8601String().substring(0, 10),
        'created_at': DateTime.now().toIso8601String(),
      });
      if (dateRappel != null) {
        await _scheduleRappelAgenda(
          dateRappel: dateRappel!,
          titre: 'Rappel vaccin — ${vaccin.text.trim()} (${_nomCtrl.text})',
        );
      }
      await _loadHealthRecords();
    });
  }

  void _showTraitementSheet() {
    final nom = TextEditingController(), type = TextEditingController(),
        posologie = TextEditingController();
    DateTime? date, dateFin;
    _openSheet('Ajouter un traitement', (ss) => [
      _SFld(ctrl: nom, label: 'Nom du traitement', hint: 'Ex: Amoxicilline...'),
      _SFld(ctrl: type, label: 'Type', hint: 'Ex: Antibiotique, Anti-inflammatoire...'),
      _SFld(ctrl: posologie, label: 'Posologie', hint: 'Ex: 1 comprimé 2x/jour'),
      _SDate(label: 'Date de début', date: date, onPicked: (d) => ss(() => date = d)),
      _SDate(label: 'Date de fin', date: dateFin, onPicked: (d) => ss(() => dateFin = d)),
    ], () async {
      await _supa.from('traitements').insert({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'nom': nom.text.trim(),
        'type': type.text.trim().isEmpty ? null : type.text.trim(),
        'posologie': posologie.text.trim().isEmpty ? null : posologie.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'date_fin': dateFin?.toIso8601String().substring(0, 10),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadHealthRecords();
    });
  }

  void _showVisiteSheet() {
    final motif = TextEditingController(), veto = TextEditingController(),
        diag = TextEditingController(), notes = TextEditingController();
    DateTime? date;
    final isFirstVisit = _visites.isEmpty;
    _openSheet('Ajouter une visite', (ss) => [
      _SFld(ctrl: motif, label: 'Motif', hint: 'Ex: Contrôle annuel, Blessure...'),
      _SFld(ctrl: veto, label: 'Vétérinaire', hint: 'Nom du vétérinaire'),
      _SDate(label: 'Date', date: date, onPicked: (d) => ss(() => date = d)),
      _SFld(ctrl: diag, label: 'Diagnostic', hint: 'Diagnostic posé'),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes supplémentaires'),
    ], () async {
      await _supa.from('visites').insert({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'motif': motif.text.trim(),
        'veterinaire': veto.text.trim().isEmpty ? null : veto.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'diagnostic': diag.text.trim().isEmpty ? null : diag.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadHealthRecords();
      if (isFirstVisit) {
        _showInsuranceCta(reason: '🩺 Première visite vétérinaire — pensez à assurer votre animal !');
      }
    });
  }

  void _showVermifugeSheet() {
    final produit = TextEditingController(), dosage = TextEditingController(),
        notes = TextEditingController();
    DateTime? date, dateRappel;
    _openSheet('Ajouter un vermifuge', (ss) => [
      _SFld(ctrl: produit, label: 'Produit', hint: 'Ex: Milbemax, Drontal...'),
      _SFld(ctrl: dosage, label: 'Dosage', hint: 'Ex: 1 comprimé'),
      _SDate(label: 'Date', date: date, onPicked: (d) => ss(() => date = d)),
      _SDate(label: 'Date de rappel', date: dateRappel, onPicked: (d) => ss(() => dateRappel = d)),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes'),
    ], () async {
      await _supa.from('vermifuges').insert({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'produit': produit.text.trim(),
        'dosage': dosage.text.trim().isEmpty ? null : dosage.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'date_rappel': dateRappel?.toIso8601String().substring(0, 10),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      if (dateRappel != null) {
        await _scheduleRappelAgenda(
          dateRappel: dateRappel!,
          titre: 'Rappel vermifuge — ${produit.text.trim()} (${_nomCtrl.text})',
        );
      }
      await _loadHealthRecords();
    });
  }

  void _showAntiparasitaireSheet() {
    final produit = TextEditingController(), type = TextEditingController(),
        frequence = TextEditingController(), notes = TextEditingController();
    DateTime? date, dateRappel;
    _openSheet('Ajouter un antiparasitaire', (ss) => [
      _SFld(ctrl: produit, label: 'Produit', hint: 'Ex: Frontline, Advantix...'),
      _SFld(ctrl: type, label: 'Type', hint: 'Ex: Pipette, Collier, Spray...'),
      _SFld(ctrl: frequence, label: 'Fréquence', hint: 'Ex: Tous les mois'),
      _SDate(label: 'Date', date: date, onPicked: (d) => ss(() => date = d)),
      _SDate(label: 'Date de rappel', date: dateRappel, onPicked: (d) => ss(() => dateRappel = d)),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes'),
    ], () async {
      await _supa.from('antiparasitaires').insert({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'produit': produit.text.trim(),
        'type': type.text.trim().isEmpty ? null : type.text.trim(),
        'frequence': frequence.text.trim().isEmpty ? null : frequence.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'date_rappel': dateRappel?.toIso8601String().substring(0, 10),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      if (dateRappel != null) {
        await _scheduleRappelAgenda(
          dateRappel: dateRappel!,
          titre: 'Rappel antiparasitaire — ${produit.text.trim()} (${_nomCtrl.text})',
        );
      }
      await _loadHealthRecords();
    });
  }

  void _showAllergieSheet() {
    final desc = TextEditingController(), type = TextEditingController(),
        severite = TextEditingController(), notes = TextEditingController();
    DateTime? date;
    _openSheet('Ajouter une allergie', (ss) => [
      _SFld(ctrl: desc, label: 'Description', hint: 'Ex: Allergie au pollen...'),
      _SFld(ctrl: type, label: 'Type', hint: 'Ex: Alimentaire, Cutanée...'),
      _SFld(ctrl: severite, label: 'Sévérité', hint: 'Ex: Légère, Modérée, Sévère'),
      _SDate(label: 'Date de détection', date: date, onPicked: (d) => ss(() => date = d)),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes supplémentaires'),
    ], () async {
      await _supa.from('allergies').insert({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'description': desc.text.trim(),
        'type': type.text.trim().isEmpty ? null : type.text.trim(),
        'severite': severite.text.trim().isEmpty ? null : severite.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadHealthRecords();
    });
  }

  void _showPoidsSheet() {
    final valeur = TextEditingController(), notes = TextEditingController();
    DateTime? date;
    _openSheet('Ajouter un poids', (ss) => [
      _SFld(ctrl: valeur, label: 'Poids (kg)', hint: 'Ex: 4.5', numeric: true),
      _SDate(label: 'Date', date: date, onPicked: (d) => ss(() => date = d)),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes'),
    ], () async {
      final v = double.tryParse(valeur.text.replaceAll(',', '.'));
      await _supa.from('poids').insert({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'valeur': v,
        'date': date?.toIso8601String().substring(0, 10),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadHealthRecords();
    });
  }

  void _showRecordDetail(
    String sectionTitle,
    Map<String, dynamic> record,
    List<(String, String)> fieldDefs,
  ) {
    final entries = <(String, String)>[];
    for (final (label, key) in fieldDefs) {
      final val = record[key];
      if (val == null) continue;
      final s = val.toString().trim();
      if (s.isEmpty) continue;
      final display = key.contains('date') && !key.contains('rappel') && !key.contains('fin')
          ? _fmtDate(s)
          : key == 'date_rappel' || key == 'date_fin'
              ? _fmtDate(s)
              : s;
      entries.add((label, display));
    }

    showModalBottomSheet(
      context: context,
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
              Text(sectionTitle,
                  style: const TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const Divider(),
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(e.$1,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: Text(e.$2,
                            style: const TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _openSheet(
    String title,
    List<Widget> Function(StateSetter) buildFields,
    Future<void> Function() onSave,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, ss) => Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 18)),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...buildFields(ss),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              ss(() => saving = true);
                              try {
                                await onSave();
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                ss(() => saving = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                      content: Text('Erreur: $e'),
                                      backgroundColor: Colors.red));
                                }
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Enregistrer',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _loadHealthRecords();
  }

  // ── Rappels agenda ────────────────────────────────────────────────────────────

  Future<void> _scheduleRappelAgenda({
    required DateTime dateRappel,
    required String titre,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _supa.from('agenda_events').insert({
        'uid':        uid,
        'titre':      titre,
        'type':       'medication',
        'date_debut': dateRappel.toIso8601String(),
        'animal_id':  int.tryParse(_animalId ?? ''),
      });
    } catch (_) {}
  }

  // ── Alimentation ──────────────────────────────────────────────────────────────

  Widget _buildAlimentationTab() {
    return _AlimentationTabParticulier(
      animalId: _animalId,
      espece: _espece,
      sexe: _sexe,
      sterilise: _sterilise,
      dateNaissance: _dateNaissance,
      nom: _nomCtrl.text,
    );
  }
}

// ── Health section widget ─────────────────────────────────────────────────────

class _HealthSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> records;
  final VoidCallback onAdd;
  final Widget Function(Map<String, dynamic>) renderRecord;

  const _HealthSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.records,
    required this.onAdd,
    required this.renderRecord,
  });

  @override
  State<_HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<_HealthSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  if (widget.records.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text('${widget.records.length}',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: widget.color)),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline, color: widget.color, size: 22),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: widget.onAdd,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade400, size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && widget.records.isNotEmpty) ...[
            const Divider(height: 1),
            ...widget.records.map(widget.renderRecord),
          ],
          if (_expanded && widget.records.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text('Aucun enregistrement',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
            ),
        ],
      ),
    );
  }
}

// ── Record tile ───────────────────────────────────────────────────────────────

class _RecordTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const _RecordTile({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      onTap: onTap,
      title: Text(title,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          if (trailing != null)
            Text(trailing!,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onTap != null)
            Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 18),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Sheet field helpers ───────────────────────────────────────────────────────

class _SFld extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final bool numeric;
  const _SFld({required this.ctrl, required this.label, required this.hint, this.numeric = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _SDate extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPicked;
  const _SDate({required this.label, required this.date, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) onPicked(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  date != null ? DateFormat('dd/MM/yyyy').format(date!) : 'Sélectionner une date',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 14,
                      color: date != null ? Colors.black87 : Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ── Form helpers (identity tab) ───────────────────────────────────────────────

class _FLabel extends StatelessWidget {
  final String text;
  const _FLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14));
}

class _FField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  const _FField({required this.controller, required this.hint, this.keyboardType});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
          ),
        ),
      );
}

class _FFocusField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  const _FFocusField({required this.controller, required this.focusNode, required this.hint});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
          ),
        ),
      );
}

class _FMultiField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _FMultiField({required this.controller, required this.hint});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            contentPadding: const EdgeInsets.all(14),
            border: InputBorder.none,
          ),
        ),
      );
}

class _DropdownCard extends StatelessWidget {
  final String value;
  final List<String> items;
  final String Function(String) display;
  final ValueChanged<String> onChanged;
  const _DropdownCard(
      {required this.value, required this.items, required this.display, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: DropdownButtonFormField<String>(
          value: value,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
          ),
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
          items: items
              .map((s) => DropdownMenuItem(
                  value: s, child: Text(display(s), style: const TextStyle(fontFamily: 'Galey'))))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      );
}

class _SexeRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SexeRow({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final opt in [('male', 'Mâle', Icons.male), ('femelle', 'Femelle', Icons.female), ('inconnu', 'Inconnu', Icons.help_outline)])
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opt.$1),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: value == opt.$1 ? const Color(0xFF0C5C6C) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Column(
                  children: [
                    Icon(opt.$3, color: value == opt.$1 ? Colors.white : Colors.grey, size: 20),
                    const SizedBox(height: 4),
                    Text(opt.$2,
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 11,
                            color: value == opt.$1 ? Colors.white : Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final DateTime? date;
  final ValueChanged<DateTime> onPicked;
  const _DateField({required this.date, required this.onPicked});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now().subtract(const Duration(days: 365)),
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (d != null) onPicked(d);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              const SizedBox(width: 10),
              Text(
                date != null ? DateFormat('dd/MM/yyyy').format(date!) : 'Sélectionner une date',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 14,
                    color: date != null ? Colors.black87 : Colors.grey),
              ),
            ],
          ),
        ),
      );
}

class _BigActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _BigActionBtn(
      {required this.label, required this.icon, required this.color, required this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(icon, color: color, size: 20),
          label: Text(label, style: TextStyle(fontFamily: 'Galey', color: color, fontWeight: FontWeight.w600)),
          onPressed: onPressed,
        ),
      );
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Breed picker sheet ────────────────────────────────────────────────────────

class _BreedPickerSheet extends StatefulWidget {
  final List<String> breeds;
  final String label;
  final String current;
  const _BreedPickerSheet({required this.breeds, required this.label, required this.current});
  @override
  State<_BreedPickerSheet> createState() => _BreedPickerSheetState();
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

// ── Onglet Alimentation (particulier) ─────────────────────────────────────────

class _AlimentationTabParticulier extends StatefulWidget {
  final String? animalId;
  final String espece;
  final String sexe;
  final bool sterilise;
  final DateTime? dateNaissance;
  final String nom;

  const _AlimentationTabParticulier({
    required this.animalId,
    required this.espece,
    required this.sexe,
    required this.sterilise,
    required this.dateNaissance,
    this.nom = '',
  });

  @override
  State<_AlimentationTabParticulier> createState() => _AlimentationTabParticulierState();
}

class _AlimentationTabParticulierState extends State<_AlimentationTabParticulier> {
  static final _supa = Supabase.instance.client;
  bool _loading = true;
  bool _saving  = false;
  Map<String, dynamic>? _existing;

  // Dernier poids connu (chargé depuis la table poids)
  String _poidsActuelStr = '';

  String  _type       = 'croquettes';
  String  _activite   = 'modere';
  String  _catEnergie = 'normale';
  String? _phaseManuelle;

  final _densiteCtrl     = TextEditingController();
  final _objectifCtrl    = TextEditingController();
  final _densitePateeCtrl = TextEditingController();
  final _doseManCtrl     = TextEditingController();
  final _doseManCtrl2    = TextEditingController();
  final _densiteGranCtrl = TextEditingController();

  String?       _marqueId;
  String        _marqueNom   = '';
  String        _gammeNom    = '';
  List<dynamic> _dosesMarque = [];

  double _pctMuscles = 70;
  double _pctAbats   = 10;
  double _pctOs      = 10;
  double _pctLegumes = 10;

  double _pctCroquMix   = 70;
  String _typeMixte2    = 'patee';

  int  _nbRepas             = 2;
  bool _modeCalculateur     = true;
  bool _mixteSepareParRepas = false;

  double _pctFoinMix     = 67;
  double _pctGranulesMix = 28;
  double _pctCompMix     =  5;

  // Override manuel de l'état reproducteur (pas d'auto-détection côté particulier)
  String? _etatRepro;

  static const _repasLabels = [
    ['Repas unique'],
    ['Matin 🌅', 'Soir 🌇'],
    ['Matin 🌅', 'Midi ☀️', 'Soir 🌇'],
    ['Matin 🌅', 'Milieu de journée ☀️', 'Après-midi 🌤️', 'Soir 🌇'],
  ];

  static const _actFactors = <String, double>{
    'repos': 0.8, 'leger': 1.4, 'modere': 1.6, 'actif': 1.8, 'tres_actif': 2.0,
  };
  static const _actLabels = <String, String>{
    'repos': 'Repos', 'leger': 'Léger', 'modere': 'Modéré',
    'actif': 'Actif', 'tres_actif': 'Très actif',
  };
  static const _catEnergieFactors = <String, double>{
    'basse': 0.85, 'normale': 1.0, 'elevee': 1.2, 'geant': 0.90,
  };
  static const _catEnergieLabels = <String, String>{
    'basse': 'Faible', 'normale': 'Normale', 'elevee': 'Élevée', 'geant': 'Géante',
  };
  static const _catEnergieExemples = <String, String>{
    'basse':   'Husky, Basset Hound, Bouledogue',
    'normale': 'Labrador, Berger Allemand, Beagle',
    'elevee':  'Border Collie, Jack Russell, Setter',
    'geant':   'Saint-Bernard, Dogue, Terre-Neuve',
  };
  static const _catEnergieExemplesChat = <String, String>{
    'basse':   'Ragdoll, British Shorthair, Persan (races calmes et corpulentes)',
    'normale': 'Européen, Siamois, Sacré de Birmanie',
    'elevee':  'Bengal, Abyssin, Somali, Oriental (races très actives)',
    'geant':   'Maine Coon, Norvégien (grande race, croissance contrôlée)',
  };

  static const _supplements = <String, List<(String, String)>>{
    'cheval': [
      ('🧂', 'Pierre à sel / bloc minéral (accès libre permanent)'),
      ('🔵', 'Complément calcium-phosphore (calcul selon fourrage)'),
      ('🌿', 'Biotine 20 mg/j (santé des sabots)'),
      ('💊', 'Vitamine E + Sélénium (zones carencées, sport)'),
      ('🦠', 'Probiotiques (changement alimentation, stress)'),
      ('🐟', 'Oméga-3 : huile de lin 50 ml/j'),
    ],
    'lapin': [
      ('🌾', 'Foin de qualité en accès libre (priorité absolue)'),
      ('🧂', 'Pierre à sel (accès libre)'),
      ('🥬', 'Légumes frais : chicorée, cresson, romaine (50g/kg/j)'),
      ('💊', 'Vitamine C si santé fragilisée'),
    ],
    'ovin': [
      ('🧂', 'Bloc minéral mouton (Cu < 10 ppm — toxique si trop élevé)'),
      ('💊', 'Sélénium injectable annuel (zones carencées)'),
      ('🌿', 'Vitamine B12 (brebis en gestation)'),
      ('🔵', 'Calcite (prévention hypocalcémie post-agnelage)'),
    ],
    'caprin': [
      ('🧂', 'Bloc minéral chèvre (Cu toléré, différent du mouton)'),
      ('💊', 'Sélénium + Vitamine E'),
      ('🌿', 'Vitamine D (stabulation prolongée)'),
      ('🦠', 'Probiotiques (chevrettes, diarrhées)'),
    ],
    'porcin': [
      ('💊', 'Acides aminés essentiels (lysine, méthionine)'),
      ('🧂', 'Sel 0.5–1% de la ration'),
      ('🔵', 'Vitamines A, D, E, K'),
      ('⚙️', 'Zinc + Fer (porcelets en croissance)'),
    ],
    'oiseau': [
      ('🧂', 'Sépie (calcium, bec)'),
      ('💊', 'Vitamines A, D3, E (si granulés insuffisants)'),
      ('🥬', 'Légumes frais : carottes, épinards, concombre'),
      ('🐟', 'Quelques insectes séchés (perroquets — protéines)'),
    ],
  };

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _densiteCtrl.dispose();
    _objectifCtrl.dispose();
    _densitePateeCtrl.dispose();
    _doseManCtrl.dispose();
    _doseManCtrl2.dispose();
    _densiteGranCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.animalId == null) { setState(() => _loading = false); return; }
    try {
      final res = await _supa
          .from('alimentations')
          .select()
          .eq('animal_id', widget.animalId!)
          .maybeSingle();
      if (mounted && res != null) {
        setState(() {
          _existing          = res;
          _type              = res['type_ration']       ?? 'croquettes';
          _activite          = res['niveau_activite']   ?? 'modere';
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
          final notes = res['notes'] as String?;
          if (notes != null && notes.contains('|')) {
            final parts = notes.split('|');
            if (parts.length >= 3) {
              _pctFoinMix     = double.tryParse(parts[0]) ?? 67;
              _pctGranulesMix = double.tryParse(parts[1]) ?? 28;
              _pctCompMix     = double.tryParse(parts[2]) ?? 5;
              if (parts.length >= 4)  _nbRepas             = int.tryParse(parts[3]) ?? 2;
              if (parts.length >= 5)  _mixteSepareParRepas = parts[4] == '1';
              if (parts.length >= 6)  _doseManCtrl.text    = parts[5];
              if (parts.length >= 7)  _doseManCtrl2.text   = parts[6];
              if (parts.length >= 8 && parts[7].isNotEmpty) _typeMixte2 = parts[7];
              if (parts.length >= 9)  _densitePateeCtrl.text  = parts[8];
              if (parts.length >= 10) _densiteGranCtrl.text   = parts[9];
            }
          }
          _modeCalculateur = false;
        });
        if (_marqueId != null) {
          final brand = await _supa
              .from('marques_aliments')
              .select('doses')
              .eq('id', _marqueId!)
              .maybeSingle();
          if (mounted && brand != null) {
            setState(() => _dosesMarque = brand['doses'] as List<dynamic>? ?? []);
          }
        }
      }
    } catch (_) {}
    // Dernier poids connu depuis la table poids
    try {
      final p = await _supa
          .from('poids')
          .select('valeur')
          .eq('animal_id', widget.animalId!)
          .order('date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted && p != null && p['valeur'] != null) {
        setState(() => _poidsActuelStr = p['valeur'].toString());
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (widget.animalId == null) return;
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'animal_id':           widget.animalId!,
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
                 '|${_mixteSepareParRepas ? 1 : 0}|${_doseManCtrl.text}|${_doseManCtrl2.text}'
                 '|$_typeMixte2|${_densitePateeCtrl.text}|${_densiteGranCtrl.text}',
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (_existing != null) {
        await _supa.from('alimentations').update(payload).eq('id', _existing!['id']);
      } else {
        final r = await _supa.from('alimentations').insert(payload).select().single();
        if (mounted) setState(() => _existing = r);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Alimentation enregistrée'),
            behavior: SnackBarBehavior.floating));
        setState(() => _modeCalculateur = false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Options de ration par espèce ──────────────────────────────────────────

  List<(String, String, String)> get _rationOptions {
    final e = widget.espece;
    if (e == 'cheval')               return [('mixte', '🌿', 'Ration mixte'), ('paturage', '🌿', 'Pâturage'), ('complement', '💊', 'Complément')];
    if (e == 'lapin')                return [('mixte', '🥦', 'Foin + Granulés'), ('granules', '🌾', 'Granulés seuls')];
    if (e == 'oiseau')               return [('graines', '🌰', 'Graines / Mix'), ('granules', '🌾', 'Granulés')];
    if (['ovin', 'caprin'].contains(e)) return [('mixte', '🌿', 'Ration mixte'), ('foin', '🌿', 'Foin seul')];
    if (e == 'porcin')               return [('granules', '🌾', 'Aliment complet'), ('menagere', '🍲', 'Ménagère')];
    return [('croquettes', '🥣', 'Croquettes'), ('barf', '🥩', 'BARF'), ('mixte', '🥣🥩', 'Mixte'), ('menagere', '🍲', 'Ménagère')];
  }

  String get _typeValide {
    final opts = _rationOptions;
    return opts.any((o) => o.$1 == _type) ? _type : opts.first.$1;
  }

  bool get _isDogOrCat => ['chien', 'chat'].contains(widget.espece);

  Map<String, String> get _exemplesEnergie =>
      widget.espece == 'chat' ? _catEnergieExemplesChat : _catEnergieExemples;

  // ── Poids & phase de vie ──────────────────────────────────────────────────

  double? get _poidsActuel {
    final v = _poidsActuelStr.replaceAll(',', '.');
    return v.isEmpty ? null : double.tryParse(v);
  }

  double? get _poidsObjectif {
    final v = _objectifCtrl.text.trim().replaceAll(',', '.');
    return v.isEmpty ? null : double.tryParse(v);
  }

  double get _poidsRef => _poidsObjectif ?? _poidsActuel ?? 0;

  double get _ageMois {
    final dn = widget.dateNaissance;
    if (dn == null) return -1;
    return DateTime.now().difference(dn).inDays / 30.44;
  }

  String get _phaseAutoDetect {
    final am = _ageMois;
    if (am < 0) return 'adulte';
    final p  = _poidsRef;
    final e  = widget.espece;
    final juniorMois = p > 45 ? 24.0 : p > 25 ? 18.0 : p > 10 ? 15.0 : 12.0;
    if (am < juniorMois)             return 'junior';
    if (e == 'chat'  && am >= 96)    return 'senior';
    if (e == 'chien' && am >= 84)    return 'senior';
    if (e == 'lapin' && am >= 48)    return 'senior';
    if (e == 'cheval' && am >= 216)  return 'senior';
    return 'adulte';
  }

  String get _phase => _phaseManuelle ?? _phaseAutoDetect;

  // ── État reproducteur ─────────────────────────────────────────────────────

  String get _etatReproEffectif => _etatRepro ?? 'normal';

  double get _reproFactor {
    switch (_etatReproEffectif) {
      case 'gestation_debut': return 1.1;
      case 'gestation_fin':   return 1.3;
      case 'lactation':       return 1.5;
      default:                return 1.0;
    }
  }

  // ── Formules espèces non-chien/chat ──────────────────────────────────────

  double get _rationPctPoidsvif {
    const chevalPct = <String, double>{'repos': 1.5, 'leger': 1.8, 'modere': 2.0, 'actif': 2.3, 'tres_actif': 2.8};
    const ovinPct   = <String, double>{'repos': 1.5, 'leger': 1.8, 'modere': 2.0, 'actif': 2.2, 'tres_actif': 2.5};
    const porcinPct = <String, double>{'repos': 2.0, 'leger': 2.5, 'modere': 3.0, 'actif': 3.0, 'tres_actif': 3.0};
    final e = widget.espece;
    if (e == 'cheval') return chevalPct[_activite] ?? 2.0;
    if (e == 'ovin' || e == 'caprin') return ovinPct[_activite] ?? 2.0;
    if (e == 'porcin') return porcinPct[_activite] ?? 2.5;
    return 2.0;
  }

  double get _rationTotaleKg =>
      _poidsRef > 0 ? _poidsRef * _rationPctPoidsvif / 100 * _reproFactor : 0;

  Map<String, dynamic>? get _rationEspeceDetail {
    if (_poidsRef <= 0) return null;
    final e = widget.espece;
    if (e == 'cheval' || e == 'ovin' || e == 'caprin') {
      final total           = _rationTotaleKg;
      final foin            = total * _pctFoinMix    / 100;
      final gran            = total * _pctGranulesMix / 100;
      final comp            = total * _pctCompMix    / 100;
      final maxRepasGran    = e == 'cheval' ? 2.5 : 1.5;
      final nbRepasMini     = gran > maxRepasGran ? (gran / maxRepasGran).ceil() : 2;
      return {
        'total_kg': total, 'foin_kg': foin, 'granules_kg': gran, 'complement_kg': comp,
        'max_repas_gran': maxRepasGran, 'nb_repas': nbRepasMini,
        'alerte_gran': gran > maxRepasGran * 2.5,
      };
    }
    if (e == 'lapin') return {
      'granules_g': _poidsRef * 22.5,
      'legumes_g':  _poidsRef * 50.0,
      'eau_ml':     _poidsRef * 100.0,
      'foin': 'illimité',
    };
    if (e == 'oiseau') return {'graines_g': 35.0, 'legumes_g': 30.0};
    if (e == 'porcin') return {'total_kg': _rationTotaleKg};
    return null;
  }

  // ── Calculs DER ───────────────────────────────────────────────────────────

  double? get _rer => _poidsRef > 0 ? 70 * math.pow(_poidsRef, 0.75).toDouble() : null;

  double? get _der {
    final rer = _rer;
    if (rer == null) return null;
    double phaseFactor;
    if (_phase == 'junior') {
      if (_ageMois >= 0 && _ageMois < 4) phaseFactor = 3.0;
      else if (_poidsRef > 25)            phaseFactor = 1.8;
      else                                phaseFactor = 2.0;
    } else if (_phase == 'senior') {
      phaseFactor = 1.2;
    } else {
      phaseFactor = _actFactors[_activite] ?? 1.6;
    }
    final sterilFactor = widget.sterilise
        ? (widget.espece == 'chat' ? 0.7 : 0.8)
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
    final actFactor    = (_catEnergieFactors[_catEnergie] ?? 1.0) * ((_actFactors[_activite] ?? 1.6) / 1.6);
    final sterilFactor = widget.sterilise ? (widget.espece == 'chat' ? 0.7 : 0.8) : 1.0;
    return _poidsRef * 1000 * 0.02 * actFactor * sterilFactor * _reproFactor;
  }

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
    if (_typeMixte2 == 'menagere') return (d * pctSecond / 120.0) * 100;
    final den = double.tryParse(_densitePateeCtrl.text.replaceAll(',', '.'));
    if (den == null || den <= 0) return null;
    return (d * pctSecond / den) * 100;
  }

  double? get _rationMenagere {
    final d = _der;
    return d != null ? (d / 120.0) * 100 : null;
  }

  // Doses effectives (override manuel ou calculé)
  double? get _doseEffCroq      { final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.')); return m ?? _rationCroquettes; }
  double? get _doseEffBarf      { final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.')); return m ?? _rationBarf; }
  double? get _doseEffMenagere  { final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.')); return m ?? _rationMenagere; }
  double? get _doseEffMixteCroq { final m = double.tryParse(_doseManCtrl.text.replaceAll(',','.')); return m ?? _rationMixteCroq; }
  double? get _doseEffMixteSecond { final m = double.tryParse(_doseManCtrl2.text.replaceAll(',','.')); return m ?? _rationMixteSecond; }

  double? get _kcalApportes {
    switch (_typeValide) {
      case 'croquettes':
        final dose = _doseEffCroq;
        final den  = double.tryParse(_densiteCtrl.text.replaceAll(',', '.'));
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
        final den  = double.tryParse(_densiteCtrl.text.replaceAll(',', '.'));
        if (croq != null && den != null && den > 0) total += croq * den / 100;
        final sec = _doseEffMixteSecond;
        if (sec != null) {
          if (_typeMixte2 == 'barf')          total += sec * 1.25;
          else if (_typeMixte2 == 'menagere') total += sec * 120.0 / 100;
          else {
            final denP = double.tryParse(_densitePateeCtrl.text.replaceAll(',', '.'));
            if (denP != null && denP > 0) total += sec * denP / 100;
          }
        }
        return total > 0 ? total : null;
      default: return null;
    }
  }

  double? get _doseBrandInterpolee {
    if (_dosesMarque.isEmpty || _poidsRef <= 0) return null;
    try {
      final sorted = List<dynamic>.from(_dosesMarque)
        ..sort((a, b) => ((a['poids_kg'] as num?) ?? 0).compareTo((b['poids_kg'] as num?) ?? 0));
      for (int i = 0; i < sorted.length - 1; i++) {
        final p1 = (sorted[i]['poids_kg']     as num).toDouble();
        final p2 = (sorted[i + 1]['poids_kg'] as num).toDouble();
        final d1 = (sorted[i]['grammes']      as num).toDouble();
        final d2 = (sorted[i + 1]['grammes']  as num).toDouble();
        if (_poidsRef >= p1 && _poidsRef <= p2) return d1 + (d2 - d1) * (_poidsRef - p1) / (p2 - p1);
      }
      if (_poidsRef < (sorted.first['poids_kg'] as num)) return (sorted.first['grammes'] as num).toDouble();
      return (sorted.last['grammes'] as num).toDouble();
    } catch (_) { return null; }
  }

  // ── Planning repas ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _mealPlan {
    final espece = widget.espece;
    final labels = _repasLabels[_nbRepas - 1];

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
        return List.generate(_nbRepas, (i) => {
          'label': labels[i],
          'items': [
            {'emoji': '🥩', 'nom': 'Viande/muscles', 'qte': '${(par * _pctMuscles / 100).round()} g'},
            {'emoji': '🫀', 'nom': 'Abats',           'qte': '${(par * _pctAbats   / 100).round()} g'},
            {'emoji': '🦴', 'nom': 'Os charnus',       'qte': '${(par * _pctOs       / 100).round()} g'},
            {'emoji': '🥦', 'nom': 'Légumes & fruits', 'qte': '${(par * _pctLegumes  / 100).round()} g'},
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
                ? (rcPar != null ? [{'emoji': '🥜', 'nom': _marqueNom.isNotEmpty ? _marqueNom : 'Croquettes', 'qte': '$rcPar g'}] : <Map<String, String>>[])
                : (rsPar != null ? [{'emoji': secondEmoji, 'nom': secondLabel, 'qte': '$rsPar g'}] : <Map<String, String>>[]),
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

    if (espece == 'cheval') {
      final detail = _rationEspeceDetail;
      if (detail == null) return [];
      final foin    = detail['foin_kg'] as double;
      final gran    = detail['granules_kg'] as double;
      final comp    = (detail['complement_kg'] as double) * 1000;
      final foinPar = foin / _nbRepas;
      final granRepas = List.generate(_nbRepas, (i) {
        if (i == 0) return math.min(gran, 2.5);
        if (i == 1) return math.max(0, math.min(gran - 2.5, 2.5));
        return 0.0;
      });
      return List.generate(_nbRepas, (i) {
        final items = <Map<String, String>>[
          {'emoji': '🌿', 'nom': 'Foin', 'qte': '${foinPar.toStringAsFixed(1)} kg'},
        ];
        if (granRepas[i] > 0) items.add({'emoji': '🌾', 'nom': _marqueNom.isNotEmpty ? _marqueNom : 'Granulés', 'qte': '${granRepas[i].toStringAsFixed(1)} kg'});
        if (i == 0 && comp > 0) items.add({'emoji': '💊', 'nom': 'Compléments', 'qte': '${comp.round()} g'});
        return {'label': labels[i], 'items': items};
      });
    }

    if (espece == 'lapin') {
      final detail = _rationEspeceDetail;
      if (detail == null) return [];
      final gran    = detail['granules_g'] as double;
      final leg     = detail['legumes_g'] as double;
      final granPar = (gran / _nbRepas).round();
      final legPar  = (leg  / _nbRepas).round();
      return List.generate(_nbRepas, (i) => {
        'label': labels[i],
        'items': [
          {'emoji': '🌿', 'nom': 'Foin',          'qte': 'Accès libre'},
          {'emoji': '🌾', 'nom': 'Granulés',       'qte': '$granPar g'},
          {'emoji': '🥬', 'nom': 'Légumes frais',  'qte': '$legPar g'},
        ],
      });
    }

    if (espece == 'ovin' || espece == 'caprin') {
      final detail  = _rationEspeceDetail;
      if (detail == null) return [];
      final foin    = detail['foin_kg'] as double;
      final gran    = detail['granules_kg'] as double;
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

    if (espece == 'porcin') {
      final detail = _rationEspeceDetail;
      if (detail == null) return [];
      final total = detail['total_kg'] as double;
      final par   = total / _nbRepas;
      return List.generate(_nbRepas, (i) => {
        'label': labels[i],
        'items': [{'emoji': '🐷', 'nom': 'Aliment complet', 'qte': '${par.toStringAsFixed(1)} kg'}],
      });
    }

    return [];
  }

  // ── Fiche recette (bottom sheet) ──────────────────────────────────────────

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
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(_typeValide == 'barf' ? 'Ration BARF' : 'Recette ménagère',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
              if (_poidsRef > 0) Text(
                '${widget.nom.isNotEmpty ? widget.nom : "Votre animal"}  ·  ${_poidsRef.toStringAsFixed(1)} kg  ·  ${_der?.round() ?? '—'} kcal/j',
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
      _RecetteItemP('🥩', 'Viande maigre / muscles (${_pctMuscles.round()}%)', '${(rb * _pctMuscles / 100).round()} g', 'Bœuf, poulet, dinde, lapin — haché ou morceaux', const Color(0xFF0C5C6C)),
      _RecetteItemP('🫀', 'Abats (${_pctAbats.round()}%)',                      '${(rb * _pctAbats   / 100).round()} g', 'Foie, rein, cœur — ne pas dépasser 15%', const Color(0xFF8D6E63)),
      _RecetteItemP('🦴', 'Os charnus (${_pctOs.round()}%)',                    '${(rb * _pctOs       / 100).round()} g', 'Carcasse poulet, côtes agneau', const Color(0xFFBCAAA4)),
      _RecetteItemP('🥦', 'Légumes & fruits (${_pctLegumes.round()}%)',         '${(rb * _pctLegumes  / 100).round()} g', 'Courgette, carotte, épinard — mixés', const Color(0xFF6E9E57)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
        child: Text('Total : ${rb.round()} g/j  ·  $_nbRepas repas de ${(rb / _nbRepas).round()} g  ·  ≈${(rb * 1.25).round()} kcal',
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
    final esp   = widget.espece;
    return [
      _RecetteItemP('🥩', 'Protéines animales (40%)', '$protG g',
          esp == 'chat' ? 'Poulet ou dinde hachée cuite — riche en taurine' : 'Poulet, bœuf, agneau — haché cuit (sans os)', const Color(0xFF0C5C6C)),
      _RecetteItemP('🥬', 'Légumes (20%)', '$legG g', 'Carottes, haricots verts, courgette — cuits et mixés', const Color(0xFF6E9E57)),
      _RecetteItemP('🌾', 'Féculents (30%)', '$fecG g',
          esp == 'chat' ? 'Riz blanc cuit (faible quantité) ou patate douce' : 'Riz blanc ou pâtes cuites', const Color(0xFFB8860B)),
      _RecetteItemP('🫒', 'Matières grasses (5%)', '$mgG g', 'Huile de colza ou de saumon (oméga-3)', const Color(0xFF8D6E63)),
      _RecetteItemP('💊', 'Compléments (5%)', '$cmpG g', 'Complément minéral-vitaminé (Seatal, Anibio, BARF Balance…)', Colors.purple.shade300),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
        child: Text('Total : ${rm.round()} g/j  ·  $_nbRepas repas de ${(rm / _nbRepas).round()} g  ·  ≈$kcal kcal',
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

  // ── Vue résumé ────────────────────────────────────────────────────────────

  Widget _buildSummaryView() {
    final rer  = _rer;
    final der  = _der;
    final kcal = _kcalApportes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Profil
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
            if (_phase == 'adulte') _sumRow('Activité', _actLabels[_activite] ?? _activite),
            if (widget.sterilise) _sumRow('Stérilisé(e)', '✂️ Oui'),
            if (_etatReproEffectif != 'normal') _sumRow('État',
                _etatReproEffectif == 'gestation_debut' ? '🤰 Gestation (début)'
                : _etatReproEffectif == 'gestation_fin'  ? '🍼 Gestation (fin)'
                : '🤱 Lactation'),
          ]),
        ),
        const SizedBox(height: 12),

        // Besoins caloriques
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

        // Ration actuelle
        _buildRationCard(der, kcal),
        const SizedBox(height: 12),

        // Plan de repas
        _buildRepasSection(),
        const SizedBox(height: 20),

        // Boutons d'action
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
      case 'croquettes': typeLabel = 'Croquettes';     typeEmoji = '🥜'; break;
      case 'barf':       typeLabel = 'BARF';            typeEmoji = '🥩'; break;
      case 'menagere':   typeLabel = 'Ration ménagère'; typeEmoji = '🍲'; break;
      case 'mixte':      typeLabel = 'Mixte';           typeEmoji = '🥣'; break;
      default:           typeLabel = type;              typeEmoji = '🍽️';
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
        child: Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.refresh_rounded, size: 18, color: Colors.grey.shade400)),
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
          if (_densiteCtrl.text.isEmpty || double.tryParse(_densiteCtrl.text.replaceAll(',', '.')) == null)
            densFld(_densiteCtrl, 'Densité énergétique (sur l\'emballage)'),
        ],

        if (type == 'barf' && isDog) ...[
          Row(children: [
            const Text('Total BARF/jour ', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl, _rationBarf, 'g')),
          ]),
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final base = _doseEffBarf ?? _rationBarf ?? 0;
            return Wrap(spacing: 6, runSpacing: 6, children: [
              _miniChip('🥩', '${(base * _pctMuscles / 100).round()} g muscles'),
              _miniChip('🫀', '${(base * _pctAbats   / 100).round()} g abats'),
              _miniChip('🦴', '${(base * _pctOs       / 100).round()} g os'),
              _miniChip('🥦', '${(base * _pctLegumes  / 100).round()} g légumes'),
            ]);
          }),
        ],

        if (type == 'menagere' && isDog) ...[
          Row(children: [
            const Text('Total/jour ', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl, _rationMenagere, 'g')),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showRecipeSheet(context),
            child: Text('📋 Voir la composition détaillée →',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: const Color(0xFF0C5C6C), decoration: TextDecoration.underline)),
          ),
        ],

        if (type == 'mixte' && isDog) ...[
          Row(children: [
            const Text('🥜  Croquettes', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            Text('  (${_pctCroquMix.round()}%)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl, _rationMixteCroq, 'g')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text('${_typeMixte2 == 'barf' ? '🥩' : _typeMixte2 == 'menagere' ? '🍲' : '🥫'}  ${_typeMixte2 == 'barf' ? 'BARF' : _typeMixte2 == 'menagere' ? 'Ménagère' : 'Pâtée'}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            Text('  (${(100 - _pctCroquMix).round()}%)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
            Expanded(child: doseFld(_doseManCtrl2, _rationMixteSecond, 'g')),
          ]),
          if (_typeMixte2 == 'patee' && (_densitePateeCtrl.text.isEmpty || double.tryParse(_densitePateeCtrl.text.replaceAll(',', '.')) == null))
            densFld(_densitePateeCtrl, 'Densité pâtée (sur l\'emballage)'),
          if (_densiteCtrl.text.isEmpty || double.tryParse(_densiteCtrl.text.replaceAll(',', '.')) == null)
            densFld(_densiteCtrl, 'Densité croquettes (sur l\'emballage)'),
        ],

        if (!isDog) Builder(builder: (_) {
          final detail = _rationEspeceDetail;
          if (detail == null) return Text('Renseignez le poids pour calculer.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (detail.containsKey('total_kg'))    _sumRow('Total/jour',    '${(detail['total_kg'] as double).toStringAsFixed(1)} kg'),
            if (detail.containsKey('foin_kg'))     _sumRow('🌿 Foin',       '${(detail['foin_kg'] as double).toStringAsFixed(1)} kg'),
            if (detail.containsKey('granules_kg') && (detail['granules_kg'] as double) > 0) ...[
              _sumRow('🌾 Granulés', '${(detail['granules_kg'] as double).toStringAsFixed(1)} kg'),
              if (_densiteGranCtrl.text.isEmpty || double.tryParse(_densiteGranCtrl.text.replaceAll(',', '.')) == null)
                densFld(_densiteGranCtrl, 'Densité granulés (sur l\'emballage)'),
            ],
            if (detail.containsKey('complement_kg')) _sumRow('💊 Compléments', '${((detail['complement_kg'] as double) * 1000).round()} g'),
            if (detail.containsKey('granules_g'))    _sumRow('🌾 Granulés',     '${(detail['granules_g'] as double).round()} g'),
            if (detail.containsKey('legumes_g'))     _sumRow('🥬 Légumes',      '${(detail['legumes_g'] as double).round()} g'),
            if (detail.containsKey('graines_g'))     _sumRow('🌰 Graines',      '${(detail['graines_g'] as double).round()} g'),
          ]);
        }),

        if (kcalBadge != null) kcalBadge,

        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C5C6C),
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
        )),
      ]),
    );
  }

  Widget _buildRepasSection() {
    final plan = _mealPlan;
    if (plan.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      const _AlimSectionP('Rations journalières'),
      const SizedBox(height: 10),

      // Sélecteur nombre de repas
      Row(children: [
        Text('Repas par jour :', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(width: 10),
        ...List.generate(4, (i) {
          final n        = i + 1;
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
        if (_etatReproEffectif != 'normal')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Text(
              _etatReproEffectif == 'lactation' ? '🤱 +50%' : _etatReproEffectif == 'gestation_fin' ? '🤰 +30%' : '🤰 +10%',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C), fontWeight: FontWeight.w700)),
          ),
        if (widget.sterilise)
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
        final idx   = entry.key;
        final meal  = entry.value;
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
                        decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
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
            widget.espece == 'cheval' ? 'Eau fraîche : 30–60 L/j minimum'
            : widget.espece == 'lapin' ? 'Eau fraîche : ${(_poidsRef * 100).round()} ml/j minimum'
            : 'Eau fraîche disponible en permanence',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
    ]);
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

  // ── Champ saisie générique ────────────────────────────────────────────────

  Widget _alimField(String label, TextEditingController ctrl, {bool numeric = false, String? hint}) => TextField(
    controller: ctrl,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400),
      labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
      filled: true, fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    ),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)));
    if (widget.animalId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Enregistrez l\'animal pour accéder à l\'alimentation.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
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
        const _AlimSectionP('Type de ration'),
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
                    Text(t.$3, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                        color: _typeValide == t.$1 ? Colors.white : const Color(0xFF1F2A2E))),
                  ]),
                ),
              ),
            )),
        ]),
        const SizedBox(height: 20),

        // ── POIDS DE RÉFÉRENCE ──────────────────────────────────
        const _AlimSectionP('Poids de référence'),
        const SizedBox(height: 10),
        Row(children: [
          if (_poidsActuel != null) Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Actuel', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                Text('${_poidsActuel!.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
              ]),
            ),
          ),
          Expanded(child: TextField(
            controller: _objectifCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Objectif (kg)',
              labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
              filled: true, fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            ),
          )),
        ]),
        const SizedBox(height: 20),

        // ── PHASE DE VIE ────────────────────────────────────────
        Row(children: [
          const _AlimSectionP('Phase de vie'),
          const SizedBox(width: 8),
          if (_phaseManuelle == null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
            child: Text('auto', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
          ),
        ]),
        const SizedBox(height: 8),
        if (phaseAuto == 'junior') Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFDC80))),
          child: const Row(children: [
            Text('🍼 ', style: TextStyle(fontSize: 16)),
            Expanded(child: Text('Alimentation spécifique Junior en croissance recommandée',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF856404)))),
          ]),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in [('junior', 'Junior 🍼'), ('adulte', 'Adulte'), ('senior', 'Senior 🌿')])
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
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(e.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: _phase == e.$1 ? Colors.white : const Color(0xFF1F2A2E),
                      fontWeight: _phase == e.$1 ? FontWeight.w700 : FontWeight.normal)),
                  if (e.$1 == phaseAuto) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: _phase == e.$1 ? Colors.white.withOpacity(0.25) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('auto', style: TextStyle(fontFamily: 'Galey', fontSize: 9,
                          color: _phase == e.$1 ? Colors.white : Colors.grey.shade500)),
                    ),
                  ],
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 20),

        // ── ÉNERGIE DE LA RACE (chien/chat) ─────────────────────
        if (_isDogOrCat) ...[
          const _AlimSectionP('Énergie de la race'),
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
                    color: _catEnergie == e.key ? const Color(0xFF0C5C6C) : Colors.grey.shade200,
                    width: _catEnergie == e.key ? 1.5 : 1),
              ),
              child: Row(children: [
                Radio<String>(value: e.key, groupValue: _catEnergie,
                    onChanged: (v) => setState(() => _catEnergie = v!),
                    activeColor: const Color(0xFF0C5C6C),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.value, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                      color: _catEnergie == e.key ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  Text(_exemplesEnergie[e.key] ?? '', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                ])),
              ]),
            ),
          ))),
          const SizedBox(height: 20),
        ],

        // ── NIVEAU D'ACTIVITÉ (adulte) ──────────────────────────
        if (_phase == 'adulte') ...[
          const _AlimSectionP("Niveau d'activité"),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _actLabels.entries)
              GestureDetector(
                onTap: () => setState(() => _activite = e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _activite == e.key ? const Color(0xFF0C5C6C) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _activite == e.key ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
                  ),
                  child: Text(e.value, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: _activite == e.key ? Colors.white : const Color(0xFF1F2A2E),
                      fontWeight: _activite == e.key ? FontWeight.w700 : FontWeight.normal)),
                ),
              ),
          ]),
          const SizedBox(height: 20),
        ],

        // ── ÉTAT REPRODUCTEUR ───────────────────────────────────
        if (widget.sterilise || widget.sexe == 'femelle') ...[
          const _AlimSectionP('État reproducteur'),
          const SizedBox(height: 8),
          if (widget.sterilise) ...[
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
                  'Réduction stérilisé appliquée : ×${widget.espece == 'chat' ? '0.7' : '0.8'} sur les besoins énergétiques',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF4A7C39)))),
              ]),
            ),
          ] else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in [
                ('normal',          'Normal',             '⚪'),
                ('gestation_debut', 'Gestation (début)',  '🤰'),
                ('gestation_fin',   'Gestation (fin)',    '🍼'),
                ('lactation',       'Lactation',          '🤱'),
              ])
                GestureDetector(
                  onTap: () => setState(() =>
                      _etatRepro = e.$1 == _etatReproEffectif && _etatRepro != null ? null : e.$1),
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
                      Text(e.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: _etatReproEffectif == e.$1 ? Colors.white : const Color(0xFF1F2A2E),
                          fontWeight: _etatReproEffectif == e.$1 ? FontWeight.w700 : FontWeight.normal)),
                    ]),
                  ),
                ),
            ]),
            if (_etatReproEffectif != 'normal') ...[
              const SizedBox(height: 10),
              Container(
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
                      _etatReproEffectif == 'gestation_debut' ? 'Gestation (début) — Apports +10%'
                          : _etatReproEffectif == 'gestation_fin' ? 'Gestation (fin) — Apports +30%'
                          : 'Lactation — Apports +50%',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C)))),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    _etatReproEffectif == 'gestation_debut'
                        ? 'Augmentez progressivement les rations. Préférez une alimentation riche en protéines de qualité.'
                        : _etatReproEffectif == 'gestation_fin'
                            ? 'Dernières semaines : augmentez les apports progressivement. Fractionnez les repas (3–4/j).'
                            : 'Alimentation à volonté recommandée. Eau fraîche disponible en permanence. Besoins pouvant atteindre +75% selon le nombre de petits.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade700)),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 20),
        ],

        // ── PARAMÈTRES SELON TYPE ───────────────────────────────
        if (_typeValide == 'croquettes') ...[
          const _AlimSectionP('Produit'),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
              builder: (_) => _MarquePickerSheetP(
                espece: widget.espece, phase: _phase,
                onSelected: (b) => setState(() {
                  _marqueId         = b['id'] as String?;
                  _marqueNom        = (b['marque'] ?? '') as String;
                  _gammeNom         = (b['gamme']  ?? '') as String;
                  _densiteCtrl.text = (b['densite_kcal_100g'] as num?)?.round().toString() ?? '';
                  _dosesMarque      = (b['doses'] as List<dynamic>?) ?? [];
                }),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _marqueNom.isNotEmpty ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.search, size: 18, color: Color(0xFF0C5C6C)),
                const SizedBox(width: 10),
                Expanded(child: _marqueNom.isEmpty
                    ? Text('Rechercher une marque…', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade400))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_marqueNom, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
                        Text(_gammeNom, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                      ])),
                if (_marqueNom.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() { _marqueId = null; _marqueNom = ''; _gammeNom = ''; _densiteCtrl.clear(); _dosesMarque = []; }),
                    child: const Icon(Icons.close, size: 18, color: Color(0xFF0C5C6C)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          _alimField('Densité énergétique (kcal/100g)', _densiteCtrl, numeric: true, hint: 'Ex : 340 — indiqué sur l\'emballage'),
        ] else if (_typeValide == 'barf') ...[
          const _AlimSectionP('Composition BARF (%)'),
          const SizedBox(height: 10),
          _BarfSliderP(label: 'Muscles / viande maigre', emoji: '🥩', value: _pctMuscles, color: const Color(0xFF0C5C6C), onChanged: (v) => setState(() => _pctMuscles = v)),
          _BarfSliderP(label: 'Abats (foie, rein…)',     emoji: '🫀', value: _pctAbats,   color: const Color(0xFF8D6E63), onChanged: (v) => setState(() => _pctAbats   = v)),
          _BarfSliderP(label: 'Os charnus',               emoji: '🦴', value: _pctOs,      color: const Color(0xFFBCAAA4), onChanged: (v) => setState(() => _pctOs      = v)),
          _BarfSliderP(label: 'Légumes & fruits',         emoji: '🥦', value: _pctLegumes, color: const Color(0xFF6E9E57), onChanged: (v) => setState(() => _pctLegumes = v)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('Total : ', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            Text('${(_pctMuscles + _pctAbats + _pctOs + _pctLegumes).round()}%', style: TextStyle(
                fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700,
                color: (_pctMuscles + _pctAbats + _pctOs + _pctLegumes - 100).abs() < 1
                    ? const Color(0xFF6E9E57) : const Color(0xFFE25C5C))),
          ]),
        ] else if (_typeValide == 'menagere') ...[
          const _AlimSectionP('Ration ménagère'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showRecipeSheet(context),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Voir la recette détaillée', style: TextStyle(fontFamily: 'Galey')),
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0C5C6C), side: const BorderSide(color: Color(0xFF0C5C6C)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          ),
        ] else if (_typeValide == 'mixte' && _isDogOrCat) ...[
          const _AlimSectionP('Composition de la ration mixte'),
          const SizedBox(height: 10),
          _BarfSliderP(
              label: 'Croquettes', emoji: '🥜',
              value: _pctCroquMix, color: const Color(0xFF0C5C6C),
              onChanged: (v) => setState(() => _pctCroquMix = v)),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(children: [
              const SizedBox(width: 22),
              Text('${(100 - _pctCroquMix).round()}% issu de : ',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              GestureDetector(
                onTap: () => setState(() {
                  if (_typeMixte2 == 'patee') _typeMixte2 = 'barf';
                  else if (_typeMixte2 == 'barf') _typeMixte2 = 'menagere';
                  else _typeMixte2 = 'patee';
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0C5C6C).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF0C5C6C).withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_typeMixte2 == 'barf' ? '🥩 BARF' : _typeMixte2 == 'menagere' ? '🍲 Ménagère' : '🥫 Pâtée',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
                    const SizedBox(width: 4),
                    const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF0C5C6C)),
                  ]),
                ),
              ),
            ]),
          ),
          const Text('Croquettes', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
              builder: (_) => _MarquePickerSheetP(
                espece: widget.espece, phase: _phase,
                onSelected: (b) => setState(() {
                  _marqueId         = b['id'] as String?;
                  _marqueNom        = (b['marque'] ?? '') as String;
                  _gammeNom         = (b['gamme']  ?? '') as String;
                  _densiteCtrl.text = (b['densite_kcal_100g'] as num?)?.round().toString() ?? '';
                  _dosesMarque      = (b['doses'] as List<dynamic>?) ?? [];
                }),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _marqueNom.isNotEmpty ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.search, size: 18, color: Color(0xFF0C5C6C)),
                const SizedBox(width: 10),
                Expanded(child: _marqueNom.isEmpty
                    ? Text('Rechercher une marque…', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade400))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_marqueNom, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
                        Text(_gammeNom, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                      ])),
                if (_marqueNom.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() { _marqueId = null; _marqueNom = ''; _gammeNom = ''; _densiteCtrl.clear(); _dosesMarque = []; }),
                    child: const Icon(Icons.close, size: 18, color: Color(0xFF0C5C6C)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          _alimField('Densité croquettes (kcal/100g)', _densiteCtrl, numeric: true, hint: 'Ex : 362 — indiqué sur l\'emballage'),
          const SizedBox(height: 12),
          if (_typeMixte2 == 'patee') ...[
            const Text('Pâtée', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E), fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _alimField('Densité pâtée (kcal/100g)', _densitePateeCtrl, numeric: true, hint: 'Ex : 85 — indiqué sur l\'emballage'),
          ] else if (_typeMixte2 == 'menagere') ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF6E9E57).withOpacity(0.3))),
              child: const Row(children: [
                Text('🍲 ', style: TextStyle(fontSize: 14)),
                Expanded(child: Text('Ration ménagère — viande cuite, légumes, féculents. Densité estimée à 120 kcal/100g.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)))),
              ]),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF5F0E8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBCAAA4).withOpacity(0.3))),
              child: const Row(children: [
                Text('🥩 ', style: TextStyle(fontSize: 14)),
                Expanded(child: Text('BARF — viande crue, os charnus, abats. Ration estimée à 2% du poids vif.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _mixteSepareParRepas = !_mixteSepareParRepas),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _mixteSepareParRepas ? const Color(0xFF0C5C6C).withOpacity(0.07) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _mixteSepareParRepas ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children: [
                Icon(_mixteSepareParRepas ? Icons.restaurant_outlined : Icons.shuffle_rounded,
                    size: 18, color: _mixteSepareParRepas ? const Color(0xFF0C5C6C) : Colors.grey.shade500),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_mixteSepareParRepas ? 'Un type par repas' : 'Mélangé à chaque repas',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                          color: _mixteSepareParRepas ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  Text(_mixteSepareParRepas ? 'Ex: croquettes le matin, pâtée le soir' : 'Les deux composants à chaque repas',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
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
          // Ration mixte (cheval, ovin, caprin, lapin)
          _AlimSectionP(['cheval', 'ovin', 'caprin'].contains(widget.espece)
              ? 'Composition de la ration' : 'Composition (foin + granulés)'),
          const SizedBox(height: 10),
          if (['cheval', 'ovin', 'caprin'].contains(widget.espece)) ...[
            _BarfSliderP(label: 'Foin / Fourrage',    emoji: '🌿', value: _pctFoinMix,     color: const Color(0xFF6E9E57), onChanged: (v) => setState(() => _pctFoinMix     = v)),
            _BarfSliderP(label: 'Granulés / Aliment', emoji: '🌾', value: _pctGranulesMix, color: const Color(0xFFB8860B), onChanged: (v) => setState(() => _pctGranulesMix = v)),
            _BarfSliderP(label: 'Compléments',        emoji: '💊', value: _pctCompMix,     color: const Color(0xFF0C5C6C), onChanged: (v) => setState(() => _pctCompMix     = v)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Total : ', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              Text('${(_pctFoinMix + _pctGranulesMix + _pctCompMix).round()}%', style: TextStyle(
                  fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700,
                  color: (_pctFoinMix + _pctGranulesMix + _pctCompMix - 100).abs() < 1
                      ? const Color(0xFF6E9E57) : const Color(0xFFE25C5C))),
            ]),
            const SizedBox(height: 12),
          ],
          const Text('Marque de granulés', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
              builder: (_) => _MarquePickerSheetP(
                espece: widget.espece, phase: _phase,
                onSelected: (b) => setState(() {
                  _marqueId    = b['id'] as String?;
                  _marqueNom   = (b['marque'] ?? '') as String;
                  _gammeNom    = (b['gamme']  ?? '') as String;
                  _dosesMarque = (b['doses'] as List<dynamic>?) ?? [];
                }),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _marqueNom.isNotEmpty ? const Color(0xFF0C5C6C) : Colors.grey.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.search, size: 18, color: Color(0xFF0C5C6C)),
                const SizedBox(width: 10),
                Expanded(child: _marqueNom.isEmpty
                    ? Text('Rechercher une marque…', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade400))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_marqueNom, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
                        if (_gammeNom.isNotEmpty) Text(_gammeNom, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                      ])),
                if (_marqueNom.isNotEmpty) GestureDetector(
                  onTap: () => setState(() { _marqueId = null; _marqueNom = ''; _gammeNom = ''; _dosesMarque = []; }),
                  child: const Icon(Icons.close, size: 18, color: Color(0xFF0C5C6C)),
                ),
              ]),
            ),
          ),
        ] else if (_typeValide == 'paturage') ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6E9E57).withOpacity(0.3))),
            child: const Row(children: [
              Text('🌿 ', style: TextStyle(fontSize: 16)),
              Expanded(child: Text('Pâturage libre — veillez à la qualité de l\'herbe et à la disponibilité de sel et eau fraîche.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF2E7D32)))),
            ]),
          ),
        ] else ...[
          _alimField('Informations complémentaires', _densiteCtrl, hint: 'Marque, quantité, fréquence…'),
        ],
        const SizedBox(height: 24),

        // ── RÉSULTATS ───────────────────────────────────────────
        if (_isDogOrCat && _poidsRef > 0 && der != null) ...[
          const _AlimSectionP('Besoins calculés'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.07), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _AlimCalcRowP('RER (besoins de repos)', '${rer!.round()} kcal/j'),
              const SizedBox(height: 8),
              _AlimCalcRowP('DER (besoins journaliers)', '${der.round()} kcal/j'),
              if (_phase == 'junior') ...[
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Text(
                    '🍼 Facteur junior : ×${_ageMois >= 0 && _ageMois < 4 ? 3.0 : _poidsRef > 25 ? 1.8 : 2.0}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF856404)))),
              ],
              if (widget.sterilise) ...[
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Text(
                    '✂️ Animal stérilisé : besoins réduits ×${widget.espece == 'chat' ? '0.7' : '0.8'} pris en compte',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C)))),
              ],
              if (_etatReproEffectif != 'normal' && widget.sexe == 'femelle') ...[
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Text(
                    _etatReproEffectif == 'gestation_debut' ? '🤰 Gestation début : +10% inclus'
                        : _etatReproEffectif == 'gestation_fin' ? '🍼 Gestation fin : +30% inclus'
                        : '🤱 Lactation : +50% inclus',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C)))),
              ],
              if (_typeValide == 'croquettes' && _rationCroquettes != null) ...[
                const Divider(height: 20),
                _AlimCalcRowP('Ration calculée', '${_rationCroquettes!.round()} g/j', highlight: true),
                if (_doseBrandInterpolee != null) ...[
                  const SizedBox(height: 6),
                  _AlimCalcRowP('Dose fabricant (${_poidsRef.toStringAsFixed(1)} kg)', '${_doseBrandInterpolee!.round()} g/j', subtle: true),
                ],
              ],
              if (_typeValide == 'barf' && _rationBarf != null) ...[
                const Divider(height: 20),
                _AlimCalcRowP('Ration BARF estimée', '${_rationBarf!.round()} g/j', highlight: true),
                const SizedBox(height: 4),
                Text('Fourchette : ${(_poidsRef * 20).round()}–${(_poidsRef * 30).round()} g/j (2–3% poids vif)',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ],
              if (_typeValide == 'mixte' && _isDogOrCat) ...[
                const Divider(height: 20),
                if (_rationMixteCroq != null)
                  _AlimCalcRowP('🥜 Croquettes (${_pctCroquMix.round()}%)', '${_rationMixteCroq!.round()} g/j', highlight: true)
                else
                  _AlimCalcRowP('🥜 Croquettes (${_pctCroquMix.round()}%)', '— (densité manquante)'),
                const SizedBox(height: 4),
                if (_rationMixteSecond != null)
                  _AlimCalcRowP(
                      _typeMixte2 == 'barf' ? '🥩 BARF (${(100 - _pctCroquMix).round()}%)' : '🥫 Pâtée (${(100 - _pctCroquMix).round()}%)',
                      '${_rationMixteSecond!.round()} g/j', highlight: true)
                else
                  _AlimCalcRowP(
                      _typeMixte2 == 'barf' ? '🥩 BARF (${(100 - _pctCroquMix).round()}%)' : '🥫 Pâtée (${(100 - _pctCroquMix).round()}%)',
                      _typeMixte2 == 'barf' ? '— (poids requis)' : '— (densité manquante)'),
              ],
            ]),
          ),
          const SizedBox(height: 6),
          Text(
            'RER = 70 × poids⁰·⁷⁵  ·  ${_phase == 'adulte' ? 'act.×${_actFactors[_activite]}' : _phase}'
            '  ·  race×${_catEnergieFactors[_catEnergie]}'
            '${widget.sterilise ? '  ·  stérilisé×${widget.espece == 'chat' ? '0.7' : '0.8'}' : ''}'
            '${_etatReproEffectif != 'normal' ? '  ·  repro×${_reproFactor.toStringAsFixed(1)}' : ''}',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
        ] else if (!_isDogOrCat) ...[
          Builder(builder: (_) {
            final detail = _rationEspeceDetail;
            if (detail == null) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Enregistrez un poids dans le carnet de santé pour calculer la ration.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)))),
                ]),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _AlimSectionP('Besoins calculés'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withOpacity(0.07), borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (detail.containsKey('total_kg')) ...[
                    _AlimCalcRowP('Total ration/jour (${_rationPctPoidsvif.toStringAsFixed(1)}% poids vif)', '${(detail['total_kg'] as double).toStringAsFixed(1)} kg/j'),
                    const Divider(height: 16),
                    _AlimCalcRowP('🌿 Foin / Fourrage', '${(detail['foin_kg'] as double).toStringAsFixed(1)} kg/j', highlight: true),
                    const SizedBox(height: 4),
                    _AlimCalcRowP('🌾 Granulés', '${(detail['granules_kg'] as double).toStringAsFixed(1)} kg/j', highlight: true),
                    const SizedBox(height: 4),
                    _AlimCalcRowP('💊 Compléments', '${((detail['complement_kg'] as double) * 1000).round()} g/j', highlight: true),
                    if ((detail['granules_kg'] as double) > 0) ...[
                      const SizedBox(height: 8),
                      Text('↳ Répartir en ${detail['nb_repas']} repas — max ${detail['max_repas_gran']} kg de granulés/repas',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C))),
                    ],
                    if (detail['alerte_gran'] as bool) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                        child: const Text('⚠️ Ration en granulés élevée : risque digestif. Réduisez et augmentez le foin.',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFE65100))),
                      ),
                    ],
                    if (_etatReproEffectif != 'normal' && widget.sexe == 'femelle') ...[
                      const SizedBox(height: 6),
                      Text(_etatReproEffectif == 'gestation_debut' ? '🤰 Gestation début : +10% inclus'
                          : _etatReproEffectif == 'gestation_fin' ? '🍼 Gestation fin : +30% inclus'
                          : '🤱 Lactation : +50% inclus',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF0C5C6C))),
                    ],
                    const SizedBox(height: 8),
                    Text('Eau fraîche : ${widget.espece == 'cheval' ? '30–60 L/j min' : '3–5 L/j'}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                  ],
                  if (detail.containsKey('granules_g') && detail.containsKey('foin')) ...[
                    Row(children: [
                      const Text('🌾 ', style: TextStyle(fontSize: 14)),
                      const Expanded(child: Text('Foin : accès libre permanent (80% minimum de la ration)',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C)))),
                    ]),
                    const SizedBox(height: 8),
                    _AlimCalcRowP('🌿 Granulés',       '${(detail['granules_g'] as double).round()} g/j', highlight: true),
                    const SizedBox(height: 4),
                    _AlimCalcRowP('🥬 Légumes frais',  '${(detail['legumes_g'] as double).round()} g/j', highlight: true),
                    const SizedBox(height: 8),
                    Text('Eau : ${(detail['eau_ml'] as double).round()} ml/j min',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                  ],
                  if (detail.containsKey('graines_g')) ...[
                    _AlimCalcRowP('🌰 Graines / Granulés',     '${(detail['graines_g'] as double).round()} g/j (perroquet moyen)', highlight: true),
                    const SizedBox(height: 4),
                    _AlimCalcRowP('🥬 Légumes / Fruits frais', '${(detail['legumes_g'] as double).round()} g/j', highlight: true),
                  ],
                  if (detail.containsKey('total_kg') && widget.espece == 'porcin') ...[
                    _AlimCalcRowP('Aliment complet/jour', '${(detail['total_kg'] as double).toStringAsFixed(1)} kg/j', highlight: true),
                  ],
                ]),
              ),
              const SizedBox(height: 6),
              Text('Calcul : ${_poidsRef.toStringAsFixed(1)} kg × ${_rationPctPoidsvif.toStringAsFixed(1)}% (poids vif)'
                  '${_etatReproEffectif != 'normal' ? ' × repro' : ''}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
            ]);
          }),
          const SizedBox(height: 20),
          if (_supplements.containsKey(widget.espece)) ...[
            const _AlimSectionP('Compléments recommandés'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final s in _supplements[widget.espece]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.$1, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)))),
                    ]),
                  ),
              ]),
            ),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade100)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.amber.shade700, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('Enregistrez un poids dans le carnet de santé ou renseignez un objectif pour calculer la ration.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)))),
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
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
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
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0C5C6C), disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.white, fontSize: 15)),
        )),
        const SizedBox(height: 32),
      ]),
    );
  }
}

// ── Helper widgets alimentation (particulier) ─────────────────────────────────

class _AlimSectionP extends StatelessWidget {
  final String title;
  const _AlimSectionP(this.title);
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E)));
}

class _RecetteItemP extends StatelessWidget {
  final String emoji, label, qte, desc;
  final Color color;
  const _RecetteItemP(this.emoji, this.label, this.qte, this.desc, this.color);
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
        Text(desc,  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
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

class _AlimCalcRowP extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final bool subtle;
  const _AlimCalcRowP(this.label, this.value, {this.highlight = false, this.subtle = false});
  @override
  Widget build(BuildContext context) {
    final color = highlight ? const Color(0xFF0C5C6C) : subtle ? Colors.grey.shade400 : const Color(0xFF1F2A2E);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: color,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.normal)),
      Text(value, style: TextStyle(fontFamily: 'Galey', fontSize: subtle ? 12 : 14,
          fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

class _BarfSliderP extends StatelessWidget {
  final String label;
  final String emoji;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  const _BarfSliderP({required this.label, required this.emoji, required this.value,
      required this.color, required this.onChanged});
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

class _MarquePickerSheetP extends StatefulWidget {
  final String espece;
  final String phase;
  final void Function(Map<String, dynamic>) onSelected;
  const _MarquePickerSheetP({required this.espece, required this.phase, required this.onSelected});
  @override
  State<_MarquePickerSheetP> createState() => _MarquePickerSheetPState();
}

class _MarquePickerSheetPState extends State<_MarquePickerSheetP> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _results = [];
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
      if (mounted) setState(() => _results = (data as List).cast<Map<String, dynamic>>());
    } catch (_) {} finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.of(context).size.height * 0.85,
    decoration: const BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    child: Column(children: [
      Center(child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
      const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('Choisir un aliment',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E)))),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _search, autofocus: true, onChanged: _onSearch,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Ex : Royal Canin, Orijen, Pro Plan…',
            hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true, fillColor: Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none)),
        ),
      ),
      const SizedBox(height: 4),
      if (_searching) const LinearProgressIndicator(color: Color(0xFF0C5C6C), minHeight: 2),
      Expanded(
        child: _results.isEmpty && !_searching
            ? Center(child: Text(
                _search.text.isEmpty ? 'Aucune marque dans la base' : 'Aucun résultat pour « ${_search.text} »',
                style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)))
            : ListView.separated(
                padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.of(context).viewInsets.bottom),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final b = _results[i];
                  final densite = (b['densite_kcal_100g'] as num?)?.round();
                  final isJunior = b['age_categorie'] == 'junior';
                  final taille = b['taille_race'] as String?;
                  return ListTile(
                    dense: true,
                    title: Text('${b['marque']} — ${b['gamme']}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                            fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                    subtitle: Wrap(spacing: 8, children: [
                      if (densite != null) Text('$densite kcal/100g',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                      if (isJunior) Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(6)),
                          child: const Text('Junior', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF856404)))),
                      if (taille != null && taille != 'toutes') Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                          child: Text(taille, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade600))),
                    ]),
                    onTap: () { Navigator.pop(context); widget.onSelected(b); },
                  );
                },
              ),
      ),
    ]),
  );
}

// ── Poids section avec courbe ─────────────────────────────────────────────────

String _fmtPoidsP(double v) {
  if (v < 1) return v.toStringAsFixed(3);
  if (v < 10) return v.toStringAsFixed(1);
  return v.toStringAsFixed(0);
}

class _PoidsSectionP extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final DateTime? dateNaissance;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onDelete;
  final String Function(dynamic) fmtDate;

  const _PoidsSectionP({
    required this.records, required this.dateNaissance,
    required this.onAdd, required this.onDelete, required this.fmtDate,
  });

  bool get _isJuvenile {
    if (dateNaissance == null) return false;
    return DateTime.now().difference(dateNaissance!).inDays < 548;
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    final sorted = [...records]..sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return da.compareTo(db);
    });
    final vals = sorted.map((d) => double.tryParse(d['valeur']?.toString() ?? '') ?? 0.0).toList();
    final maxVal = vals.isEmpty ? 1.0 : vals.reduce((a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
          child: Row(children: [
            const Icon(Icons.monitor_weight, color: teal, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Poids & Courbe de croissance',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 14, color: Color(0xFF1F2A2E)))),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16, color: teal),
              label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: teal)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
            ),
          ]),
        ),
        if (sorted.length >= 2) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _WeightChartP(docs: sorted, isJuvenile: _isJuvenile, dateNaissance: dateNaissance),
          ),
        ],
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Text('Aucune pesée enregistrée',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
          ),
        ...sorted.asMap().entries.map((e) {
          final i = e.key;
          final d = e.value;
          final val = vals[i];
          final pct = maxVal > 0 ? val / maxVal : 0.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(14, i == 0 ? 10 : 4, 14, i == sorted.length - 1 ? 14 : 0),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(fmtDate(d['date']),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                  Text('${_fmtPoidsP(val)} kg',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 15, color: Color(0xFF1F2A2E))),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct, minHeight: 5,
                    backgroundColor: const Color(0xFFEEF5EA),
                    valueColor: const AlwaysStoppedAnimation(teal),
                  ),
                ),
              ])),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                onPressed: () => onDelete(d),
                padding: const EdgeInsets.only(left: 8),
                constraints: const BoxConstraints(),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

class _WeightChartP extends StatefulWidget {
  final List<Map<String, dynamic>> docs;
  final bool isJuvenile;
  final DateTime? dateNaissance;
  const _WeightChartP({required this.docs, required this.isJuvenile, this.dateNaissance});
  @override State<_WeightChartP> createState() => _WeightChartPState();
}
class _WeightChartPState extends State<_WeightChartP> {
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
      height: 185,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
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
              painter: _ChartPainterP(
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

class _ChartPainterP extends CustomPainter {
  final List<Map<String, dynamic>> docs;
  final bool isJuvenile;
  final int? hoverIdx;
  final String Function(int) xLabelFn;

  static const _l = 44.0, _t = 20.0, _r = 12.0, _b = 30.0;
  static const _accent = Color(0xFF0C5C6C);

  const _ChartPainterP({required this.docs, required this.isJuvenile, this.hoverIdx, required this.xLabelFn});

  @override
  bool shouldRepaint(_ChartPainterP o) => o.hoverIdx != hoverIdx;

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

    final title = isJuvenile ? 'Courbe de croissance' : 'Évolution du poids';
    final titleTp = TextPainter(
      text: TextSpan(text: title, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: _accent)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    titleTp.paint(canvas, Offset(_l, (_t - titleTp.height) / 2));

    final gridPaint = Paint()..color = const Color(0xFFEEEEEE)..strokeWidth = 1;
    for (int g = 0; g <= 4; g++) {
      final yVal = baseY + g * rangeY / 4;
      final yPx = _t + h - g * h / 4;
      canvas.drawLine(Offset(_l, yPx), Offset(size.width - _r, yPx), gridPaint);
      final lbl = _fmtPoidsP(yVal < 0 ? 0 : yVal);
      final tp = TextPainter(
        text: TextSpan(text: lbl, style: const TextStyle(fontFamily: 'Galey', fontSize: 9, color: Color(0xFFBBBBBB))),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_l - tp.width - 4, yPx - tp.height / 2));
    }

    if (vals.length >= 2) {
      final areaPath = Path()..moveTo(pt(0).dx, _t + h);
      for (int i = 0; i < vals.length; i++) areaPath.lineTo(pt(i).dx, pt(i).dy);
      areaPath..lineTo(pt(vals.length - 1).dx, _t + h)..close();
      canvas.drawPath(areaPath, Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x280C5C6C), Color(0x000C5C6C)],
        ).createShader(Rect.fromLTWH(_l, _t, w, h))
        ..style = PaintingStyle.fill);

      final linePath = Path()..moveTo(pt(0).dx, pt(0).dy);
      for (int i = 1; i < vals.length; i++) linePath.lineTo(pt(i).dx, pt(i).dy);
      canvas.drawPath(linePath, Paint()
        ..color = _accent..strokeWidth = 2.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    }

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

    if (hoverIdx != null && hoverIdx! < vals.length) {
      final i = hoverIdx!;
      final p = pt(i);
      const pad = 7.0;
      final line1 = '${_fmtPoidsP(vals[i])} kg';
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
