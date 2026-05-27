import 'dart:convert';
import 'dart:io';
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
  final _nomCtrl = TextEditingController();
  final _raceCtrl = TextEditingController();
  final _couleurCtrl = TextEditingController();
  final _identCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _espece = 'chien';
  String _sexe = 'male';
  bool _sterilise = false;
  DateTime? _dateNaissance;

  String? _photoUrl;
  File? _photoFile;

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
    _tabs = TabController(length: 2, vsync: this);
    _animalId = widget.animalId;
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
    super.dispose();
  }

  Future<void> _refreshFromSupabase() async {
    try {
      final data = await _supa.from('animaux').select('*').eq('id', _animalId!).single();
      if (mounted) setState(() => _fillFromData(Map<String, dynamic>.from(data)));
    } catch (_) {}
  }

  void _fillFromData(Map<String, dynamic>? d) {
    if (d == null) return;
    _nomCtrl.text = d['nom'] ?? '';
    _raceCtrl.text = d['race'] ?? '';
    _couleurCtrl.text = d['couleur'] ?? '';
    _identCtrl.text = d['identification'] ?? '';
    _notesCtrl.text = d['notes'] ?? '';
    _descCtrl.text = d['description'] ?? '';
    _espece = d['espece'] ?? 'chien';
    _sexe = d['sexe'] ?? 'male';
    _sterilise = d['sterilise'] ?? false;
    _photoUrl = d['photo_url'];
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
        setState(() { _animalId = id; _photoFile = null; _photoUrl = photoUrl; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Animal ajouté ✓'), backgroundColor: _green));
          _loadHealthRecords();
        }
      } else {
        await _supa.from('animaux').update(data).eq('id', _animalId!);
        setState(() { _photoFile = null; _photoUrl = photoUrl; });
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
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer',
                  style: TextStyle(
                      fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Identité'), Tab(text: 'Carnet de santé')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildIdentiteTab(), _buildSanteTab()],
      ),
    );
  }

  // ── Identité ──────────────────────────────────────────────────────────────────

  Widget _buildIdentiteTab() {
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

          Row(
            children: [
              _FLabel('Stérilisé(e)'),
              const Spacer(),
              Switch(
                value: _sterilise,
                activeColor: _teal,
                onChanged: (v) => setState(() => _sterilise = v),
              ),
            ],
          ),
          const SizedBox(height: 18),

          _FLabel('Description'),
          const SizedBox(height: 6),
          _FMultiField(controller: _descCtrl, hint: 'Décrivez votre animal...'),
          const SizedBox(height: 18),

          _FLabel('Notes'),
          const SizedBox(height: 6),
          _FMultiField(controller: _notesCtrl, hint: 'Notes personnelles...'),
          const SizedBox(height: 32),

          if (_animalId != null) ...[
            // ── Alerte perdu section ──
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
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade800))),
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
                  color: const Color(0xFF6E9E57),
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
            const SizedBox(height: 12),
            _BigActionBtn(
              label: 'Transférer la propriété',
              icon: Icons.swap_horiz,
              color: _teal,
              onPressed: _showTransfertDialog,
            ),
          ],
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

  void _showTransfertDialog() {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transférer la propriété',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Entrez l'email de l'acheteur. Il recevra un lien pour confirmer le transfert.",
                style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(fontFamily: 'Galey'),
              decoration: InputDecoration(
                hintText: 'email@exemple.com',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty || !email.contains('@')) return;
              Navigator.pop(ctx);
              await _initiateTransfert(email);
            },
            child: const Text('Envoyer',
                style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _initiateTransfert(String email) async {
    try {
      final token =
          '${DateTime.now().millisecondsSinceEpoch}${User_Info.uid.hashCode.abs()}';
      await _supa.from('transferts_propriete').insert({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'uid_eleveur': User_Info.uid,
        'animal_id': _animalId,
        'email_acheteur': email,
        'token': token,
        'statut': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Transfert initié vers $email'),
                backgroundColor: _green));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
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
          _HealthSection(
            title: 'Poids',
            icon: Icons.monitor_weight,
            color: _teal,
            records: _poids,
            onAdd: _showPoidsSheet,
            renderRecord: (r) => _RecordTile(
              title: r['valeur'] != null ? '${r['valeur']} kg' : '—',
              subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
              trailing: r['notes'],
              onDelete: () => _deleteRecord('poids', r['id'], _poids),
              onTap: () => _showRecordDetail('Pesée', r, [
                ('Poids (kg)', 'valeur'), ('Date', 'date'), ('Notes', 'notes'),
              ]),
            ),
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
  const _FField({required this.controller, required this.hint});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: controller,
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
