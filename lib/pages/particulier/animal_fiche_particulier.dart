import 'package:PetsMatch/utils/ages_plausibles.dart';
import 'package:PetsMatch/utils/poids.dart';
import 'package:PetsMatch/utils/exercices_progression.dart';
import 'package:PetsMatch/utils/recuperation_animal.dart' show verifierPuce, showRecuperationAnimal;
import 'package:PetsMatch/widgets/carnet/vermifuge_options.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils/sante_suppression.dart';
import 'package:PetsMatch/utils/controle_dates.dart';
import 'package:PetsMatch/widgets/carnet/prises_traitement.dart';
import 'package:PetsMatch/utils/resume_traitement.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/particulier/balades/choix_animaux_balade.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/data/vaccin_types.dart';
import 'package:PetsMatch/data/genetic_tests.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/particulier/partage_animal_sheet.dart';
import 'package:PetsMatch/pages/particulier/proprietaires_animal_sheet.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_cheval_page.dart';
import 'package:PetsMatch/pages/particulier/social_feed_page.dart' show AnimalTaggedPostsPage;
import 'package:PetsMatch/pages/particulier/balades/mes_balades_page.dart';
import 'package:PetsMatch/services/gamification_service.dart';
import 'package:PetsMatch/pages/pro/pension_journal_page.dart';
import 'package:PetsMatch/widgets/vet_share_dialog.dart';
import 'package:PetsMatch/widgets/alimentation/alimentation_plan_tab.dart';
import 'package:PetsMatch/widgets/rich_text_view.dart';
import 'package:PetsMatch/widgets/document_viewer_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/utils/sante_couleurs.dart';
import 'package:PetsMatch/utils/user_lookup.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/cession_sheet.dart';

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
  final int initialTab; // 0=Identité 1=Carnet 2=Alimentation 3=Documents
  /// Onglet dynamique à ouvrir dès qu'il apparaît (ex. 'Éducation' depuis
  /// une notification d'exercice), prioritaire sur [initialTab].
  final String? initialTabLabel;

  const AnimalFicheParticulierPage({super.key, this.animalId, this.initialData, this.initialTab = 0, this.initialTabLabel});

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
  final _couleurYeuxCtrl = TextEditingController();
  final _identCtrl    = TextEditingController();
  final _sireCtrl       = TextEditingController();
  final _carteImmatCtrl = TextEditingController();
  final _livretCtrl     = TextEditingController();
  final _notesCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _passeportCtrl = TextEditingController();
  final _tailleCtrl   = TextEditingController();
  final _poidsCtrl    = TextEditingController();
  double? _poidsInitial; // poids lu à l'ouverture de la fiche

  String _espece = 'chien';
  final _especeAutreCtrl = TextEditingController();
  String _sexe = 'male';
  bool _sterilise = false;
  bool _steriliseInitial = false;
  // Condition de stérilisation imposée par l'éleveur à la cession
  bool _sterilRequise = false;
  DateTime? _sterilEcheance;
  bool _sterilValidee = false;
  String? _sterilEleveurUid;
  String? _sterilEleveurProfileId;
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

  // Co-propriétaires (animaux_proprietes, statut actif/invite, date_fin NULL)
  List<Map<String, dynamic>> _proprietaires = [];
  Map<String, dynamic>? _monInvitationProprio; // ma ligne si statut='invite'

  // Documents libres attachés par le propriétaire (colonne animaux.documents)
  List<Map<String, dynamic>> _documentsLibres = [];

  // Health records
  bool _loadingHealth = false;
  bool _scanningDocument = false;
  List<Map<String, dynamic>> _vaccinations = [];
  List<Map<String, dynamic>> _traitements = [];
  List<Map<String, dynamic>> _visites = [];
  List<Map<String, dynamic>> _vermifuges = [];
  List<Map<String, dynamic>> _antiparasitaires = [];
  List<Map<String, dynamic>> _allergies = [];
  List<Map<String, dynamic>> _chirurgies = [];
  List<Map<String, dynamic>> _testsGenetiques = [];
  List<Map<String, dynamic>> _poids = [];

  // Gamification Phase 1 — XP / palier d'objet évolutif (par animal)
  int _xp = 0;
  String _objectTier = 'decouverte';
  List<Map<String, dynamic>> _objectTiers = [];

  Map<String, List<String>> _allBreeds = {};

  static const _especes = [
    'chien', 'chat', 'lapin', 'oiseau', 'nac',
    'cheval', 'ovin', 'caprin', 'porcin', 'autre'
  ];

  @override
  void initState() {
    super.initState();
    _animalId = widget.animalId;
    _editing = widget.animalId == null; // nouveau animal → direct en édition
    _fillFromData(widget.initialData);
    // La morphologie n'est plus un onglet : carnet de santé › Comptes rendus.
    const initialLength = 5;
    _tabs = TabController(length: initialLength, vsync: this,
        initialIndex: widget.initialTab.clamp(0, initialLength - 1));
    _loadBreeds();
    if (_animalId != null) { _loadHealthRecords(); _loadActiveAlerte(); _refreshFromSupabase(); }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nomCtrl.dispose();
    _especeAutreCtrl.dispose();
    _raceCtrl.dispose();
    _couleurCtrl.dispose();
    _couleurYeuxCtrl.dispose();
    _identCtrl.dispose();
    _sireCtrl.dispose();
    _carteImmatCtrl.dispose();
    _livretCtrl.dispose();
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
      if (mounted) {
        setState(() { _fillFromData(Map<String, dynamic>.from(data)); _syncTabs(); });
      }
    } catch (_) {}
    _loadPensionAcces();
    _loadProprietaires();
    _loadCessionCedant();
    _loadObjectTiers();
  }

  // ── Cession lancée par ce particulier (don, abandon à une asso, revente)
  Map<String, dynamic>? _cessionCedant;

  bool get _jeSuisPrincipal => _proprietaires.any((r) =>
      r['uid_proprio'] == User_Info.uid && r['statut'] == 'actif' && r['role_proprio'] == 'principal');

  Future<void> _loadCessionCedant() async {
    if (_animalId == null) return;
    try {
      final rows = await _supa.from('cessions')
          .select('id, statut, nom_acquereur')
          .eq('animal_id', _animalId!)
          .eq('uid_eleveur', User_Info.uid)
          .not('statut', 'in', '(revoquee,confirme)')
          .order('created_at', ascending: false)
          .limit(1);
      if (mounted) {
        setState(() => _cessionCedant = (rows as List).isNotEmpty
            ? Map<String, dynamic>.from(rows.first as Map) : null);
      }
    } catch (_) {}
  }

  void _ceder() {
    final nom = '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CessionSheet(
        animal: {
          'id': _animalId,
          'nom': _nomCtrl.text,
          'espece': _espece,
          'race': _raceCtrl.text,
          'sexe': _sexe,
          'identification': _identCtrl.text.trim().isEmpty ? null : _identCtrl.text.trim(),
          'date_naissance': _dateNaissance?.toIso8601String().split('T').first,
        },
        uid: User_Info.uid,
        nomElevage: nom,
        isReCession: true,
        associationSeulement: true,
        onCeded: () { _loadCessionCedant(); _loadProprietaires(); },
      ),
    );
  }

  /// Suivi / confirmation : même écran que pour un éleveur (bandeau
  /// « Confirmer / Révoquer » de la fiche de cession).
  Future<void> _gererCession() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(animalId: _animalId, readOnly: false),
    ));
    _loadCessionCedant();
    _loadProprietaires();
  }

  Widget _cessionCedantBanner() {
    final signe = _cessionCedant!['statut'] == 'signe_acquereur';
    final acq = (_cessionCedant!['nom_acquereur'] as String?)?.trim() ?? '';
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4E0),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        const Text('🤝', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(acq.isEmpty ? 'Cession en cours' : 'Cession en cours — $acq',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
          Text(signe
                  ? "L'acquéreur a signé : confirmez le transfert."
                  : "En attente de la signature de l'acquéreur.",
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.black54)),
        ])),
        TextButton(
          onPressed: _gererCession,
          child: Text(signe ? 'Confirmer' : 'Gérer',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Color(0xFFB26A00))),
        ),
      ]),
    );
  }

  /// Paliers d'objet évolutif pour l'espèce de l'animal (species_object_tiers).
  Future<void> _loadObjectTiers() async {
    try {
      final rows = await _supa
          .from('species_object_tiers')
          .select('tier, xp_threshold')
          .eq('species', _espece)
          .order('xp_threshold');
      if (mounted) setState(() => _objectTiers = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {}
  }

  Future<void> _ouvrirEnregistrerBalade() async {
    if (_animalId == null) return;
    // Cet animal coché d'office ; on peut en ajouter d'autres.
    await demarrerBalade(context, preselectId: _animalId);
    if (!mounted) return;
    await _refreshFromSupabase();
  }

  void _ouvrirMesBalades() {
    if (_animalId == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MesBaladesPage(
        animalId: _animalId,
        animalNom: _nomCtrl.text.trim().isEmpty ? null : _nomCtrl.text.trim(),
      ),
    ));
  }

  /// Carte de progression (flamme/XP Phase 1) : palier actuel + XP restant
  /// avant le prochain palier, avec le raccourci pour enregistrer une balade.
  Widget _evolutionCard() {
    Map<String, dynamic>? nextTier;
    for (final t in _objectTiers) {
      if ((t['xp_threshold'] as num).toInt() > _xp) { nextTier = t; break; }
    }
    double? progress;
    int? xpRestant;
    if (nextTier != null) {
      final currentIdx = _objectTiers.indexOf(nextTier) - 1;
      final prevThreshold = currentIdx >= 0 ? (_objectTiers[currentIdx]['xp_threshold'] as num).toInt() : 0;
      final nextThreshold = (nextTier['xp_threshold'] as num).toInt();
      final span = (nextThreshold - prevThreshold).clamp(1, 1 << 30);
      progress = ((_xp - prevThreshold) / span).clamp(0, 1).toDouble();
      xpRestant = nextThreshold - _xp;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🏅', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Palier ${GamificationService.tierLabel(_objectTier)} · $_xp XP',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        ]),
        if (progress != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress, minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation(_teal),
            ),
          ),
          const SizedBox(height: 6),
          Text('$xpRestant XP avant le prochain palier',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.black54)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _ouvrirEnregistrerBalade,
              icon: const Icon(Icons.directions_walk, size: 16, color: Colors.white),
              label: const Text('Démarrer une balade',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _ouvrirMesBalades,
            style: OutlinedButton.styleFrom(
              foregroundColor: _teal,
              side: const BorderSide(color: _teal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: const Icon(Icons.history, size: 18),
          ),
        ]),
      ]),
    );
  }

  Future<void> _loadProprietaires() async {
    if (_animalId == null) return;
    try {
      final rows = await _supa
          .from('animaux_proprietes')
          .select('uid_proprio, profile_id_proprio, role_proprio, statut, transfert_principal_propose')
          .eq('animal_id', _animalId!)
          .isFilter('date_fin', null)
          .inFilter('statut', ['actif', 'invite']);
      final list = List<Map<String, dynamic>>.from(rows as List);
      final ids = list
          .where((r) => r['statut'] == 'actif' && r['profile_id_proprio'] != null)
          .map((r) => r['profile_id_proprio'] as String)
          .toSet()
          .toList();
      final Map<String, String> nameById = {};
      if (ids.isNotEmpty) {
        final profs = await _supa
            .from('user_profiles_complet')
            .select('id, firstname, lastname, nom')
            .inFilter('id', ids);
        for (final p in (profs as List)) {
          final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          nameById[p['id'] as String] =
              n.isNotEmpty ? n : ((p['nom'] as String?)?.trim() ?? 'Propriétaire');
        }
      }
      for (final r in list) {
        r['_name'] = nameById[r['profile_id_proprio']] ?? '';
      }
      final myUid = User_Info.uid;
      final invit = list.firstWhere(
          (r) => r['uid_proprio'] == myUid && r['statut'] == 'invite',
          orElse: () => {});
      if (mounted) {
        setState(() {
          _proprietaires = list;
          _monInvitationProprio = invit.isEmpty ? null : invit;
        });
      }
    } catch (_) {}
  }

  /// Ligne récap « Propriétaires : X (principal), Y » ; null s'il n'y a qu'un
  /// seul propriétaire (pas de copropriété).
  String? _coproprietairesLabel() {
    final actifs = _proprietaires.where((r) => r['statut'] == 'actif').toList();
    if (actifs.length < 2) return null;
    actifs.sort((a, b) => (a['role_proprio'] == 'principal' ? 0 : 1)
        .compareTo(b['role_proprio'] == 'principal' ? 0 : 1));
    final noms = actifs.map((r) {
      final n = (r['_name'] as String?)?.trim();
      final base = (n == null || n.isEmpty) ? 'Propriétaire' : n;
      return r['role_proprio'] == 'principal' ? '$base (principal)' : base;
    }).join(', ');
    return 'Propriétaires : $noms';
  }

  Future<void> _loadPensionAcces() async {
    if (_animalId == null) return;
    List<Map<String, dynamic>> acces = _pensionAcces;
    bool hasUpd = _hasPensionUpdates, hasRap = _hasEducationRapports, hasDev = _hasDevis;
    try {
      final rows = await _supa
          .from('animal_access')
          .select('id, pro_profile_id, created_at, permissions')
          .eq('animal_id', _animalId!)
          .eq('statut', 'active')
          .contains('permissions', ['write_notes']);
      acces = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}
    try {
      final updates = await _supa.from('pension_updates').select('id').eq('animal_id', _animalId!).limit(1);
      hasUpd = (updates as List).isNotEmpty;
    } catch (_) {}
    try {
      // Brouillons de l'éducateur exclus (jamais visibles par la famille).
      final rapports = await _supa.from('education_progression').select().eq('animal_id', _animalId!).limit(20);
      hasRap = (rapports as List).any((r) => r['statut'] != 'brouillon');
    } catch (_) {}
    if (!hasRap) {
      try {
        final objs = await _supa.from('education_objectifs').select('id').eq('animal_id', _animalId!).limit(1);
        hasRap = (objs as List).isNotEmpty;
      } catch (_) {}
    }
    if (!hasRap) {
      try {
        final exos = await _supa.from('exercices_attribues').select('id').eq('animal_id', _animalId!).limit(1);
        hasRap = (exos as List).isNotEmpty;
      } catch (_) {}
    }
    if (!hasRap) {
      try {
        final att = await _supa.from('education_attestations').select('id').eq('animal_id', _animalId!).limit(1);
        hasRap = (att as List).isNotEmpty;
      } catch (_) {}
    }
    try {
      final devis = await _supa.from('devis').select('id').eq('animal_id', _animalId!).limit(1);
      hasDev = (devis as List).isNotEmpty;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pensionAcces = acces;
      _hasPensionUpdates = hasUpd;
      _hasEducationRapports = hasRap;
      _hasDevis = hasDev;
      _syncTabs();
      final cible = widget.initialTabLabel;
      if (cible != null && !_ongletInitialOuvert) {
        final i = _tabLabelList.indexOf(cible);
        if (i >= 0 && i < _tabs.length) { _tabs.index = i; _ongletInitialOuvert = true; }
      }
    });
  }
  bool _ongletInitialOuvert = false;

  // Onglets dynamiques : Documents toujours présent ; Éducation / Pension &
  // Garde n'apparaissent que si l'animal a un suivi correspondant.
  bool get _showEducationTab => _hasEducationRapports || _hasDevis;
  bool get _showPensionTab => _hasPensionUpdates;

  void _syncTabs() {
    final n = 5 + (_showEducationTab ? 1 : 0) + (_showPensionTab ? 1 : 0);
    if (_tabs.length == n) return;
    final prev = _tabs.index;
    _tabs.dispose();
    _tabs = TabController(
        length: n, vsync: this, initialIndex: prev < n ? prev : n - 1);
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
    _couleurYeuxCtrl.text = d['couleur_yeux'] ?? '';
    _identCtrl.text    = d['identification'] ?? '';
    _sireCtrl.text       = d['num_sire'] ?? '';
    _carteImmatCtrl.text = d['carte_immatriculation'] ?? '';
    _livretCtrl.text     = d['livret_signaletique'] ?? '';
    _notesCtrl.text    = d['notes'] ?? '';
    _descCtrl.text     = d['description'] ?? '';
    _passeportCtrl.text    = d['passeport_europeen'] ?? '';
    _tailleCtrl.text       = d['taille']?.toString() ?? '';
    _poidsCtrl.text        = d['poids']?.toString() ?? '';
    _poidsInitial          = poidsKg(d['poids']);
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
    _xp         = (d['xp'] as num?)?.toInt() ?? 0;
    _objectTier = d['object_tier'] as String? ?? 'decouverte';
    _espece    = d['espece'] ?? 'chien';
    _especeAutreCtrl.text = d['espece_autre'] ?? '';
    _sexe      = d['sexe'] ?? 'male';
    _sterilise = d['sterilise'] ?? false;
    _steriliseInitial = _sterilise;
    _sterilRequise = d['sterilisation_requise'] ?? false;
    _sterilValidee = d['sterilisation_validee'] ?? false;
    _sterilEleveurUid = d['sterilisation_eleveur_uid'] as String?;
    _sterilEleveurProfileId = d['sterilisation_eleveur_profile_id'] as String?;
    _sterilEcheance = d['sterilisation_echeance'] != null
        ? DateTime.tryParse(d['sterilisation_echeance'].toString())
        : null;
    _photoUrl  = d['photo_url'];
    final docs = d['documents'];
    if (docs is List) {
      _documentsLibres = docs
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
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
        _supa.from('chirurgies').select().eq('animal_id', _animalId!).order('date', ascending: false),
        _supa.from('tests_genetiques').select().eq('animal_id', _animalId!).order('date_test', ascending: false),
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
        _chirurgies = List<Map<String, dynamic>>.from(results[7]);
        _testsGenetiques = List<Map<String, dynamic>>.from(results[8]);
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

  String _puceVerifiee = '';

  Future<void> _save() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le nom est requis'), backgroundColor: Colors.red));
      return;
    }
    // Date de naissance plausible pour l'espèce (changée après coup, par ex.).
    final erreurDate = erreurNaissanceAnimal(_dateNaissance, _espece);
    if (erreurDate != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreurDate), backgroundColor: Colors.red));
      return;
    }
    // Poids : « 8,5 » ou « 8.5 », plausible pour l'espèce (il alimente la courbe).
    final erreurP = erreurPoids(_poidsCtrl.text, espece: _espece);
    if (erreurP != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreurP), backgroundColor: Colors.red));
      return;
    }
    // Puce déjà enregistrée (ex. animal acquis auprès d'un élevage) :
    // proposer de récupérer sa fiche plutôt que d'en créer une seconde.
    if (_animalId == null && _identCtrl.text.replaceAll(RegExp(r'\D'), '').length >= 8 && _identCtrl.text != _puceVerifiee) {
      try {
        final v = await verifierPuce(_identCtrl.text);
        _puceVerifiee = _identCtrl.text;
        if (v['etat'] != 'aucun' && mounted) {
          final id = await showRecuperationAnimal(context, v, profileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null);
          if (id != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fiche récupérée : elle est maintenant dans vos animaux.')));
            Navigator.pop(context, true);
          }
          return;
        }
      } catch (_) {}
    }
    setState(() => _saving = true);
    try {
      final photoUrl = await _uploadPhoto();
      final uid = User_Info.uid;
      final data = {
        'nom': nom,
        'espece': _espece,
        'espece_autre': _espece == 'autre' ? _especeAutreCtrl.text.trim() : null,
        'race': _raceCtrl.text.trim().isEmpty ? null : _raceCtrl.text.trim(),
        'sexe': _sexe,
        'sterilise': _sterilise,
        'couleur': _couleurCtrl.text.trim().isEmpty ? null : _couleurCtrl.text.trim(),
        'couleur_yeux': _couleurYeuxCtrl.text.trim().isEmpty ? null : _couleurYeuxCtrl.text.trim(),
        'identification': _identCtrl.text.trim().isEmpty ? null : _identCtrl.text.trim(),
        'passeport_europeen': _passeportCtrl.text.trim().isEmpty ? null : _passeportCtrl.text.trim(),
        'num_sire': _espece == 'cheval' && _sireCtrl.text.trim().isNotEmpty ? _sireCtrl.text.trim() : null,
        'carte_immatriculation': _espece == 'cheval' && _carteImmatCtrl.text.trim().isNotEmpty ? _carteImmatCtrl.text.trim() : null,
        'livret_signaletique': _espece == 'cheval' && _livretCtrl.text.trim().isNotEmpty ? _livretCtrl.text.trim() : null,
        'type_poil': _typePoil,
        'taille': _tailleCtrl.text.trim().isEmpty ? null : double.tryParse(_tailleCtrl.text.trim()),
        // Poids inchangé : non renvoyé, pour ne pas écraser une pesée ajoutée
        // entre-temps à la courbe (la fiche reprend le dernier point, trigger
        // pm_poids_courbe_vers_fiche).
        if (_animalId == null || poidsKg(_poidsCtrl.text) != _poidsInitial)
          'poids': poidsKg(_poidsCtrl.text),
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (_animalId == null) {
        final id = '${DateTime.now().millisecondsSinceEpoch}';
        await _supa.from('animaux').insert({
          'id': id,
          'uid_eleveur': null,
          'uid_proprietaire': uid,
          // profile_id sur l'animal lui-même (cohérent avec les animaux
          // éleveur) — sinon les écrans qui filtrent uniquement
          // animaux.profile_id ne voient jamais l'animal, cf.
          // EducationReservationModal.
          if (User_Info.activeProfileId.isNotEmpty)
            'profile_id': User_Info.activeProfileId,
          ...data,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        // Historique de propriété — SOURCE DE VÉRITÉ pour la visibilité des
        // animaux (mes_animaux.dart / user_feed.dart filtrent dessus). Sans
        // cette ligne, un animal ajouté manuellement par un particulier
        // n'apparaît nulle part.
        try {
          await _supa.from('animaux_proprietes').upsert({
            'animal_id': id,
            'uid_proprio': uid,
            'date_debut': DateTime.now().toIso8601String().substring(0, 10),
            if (User_Info.activeProfileId.isNotEmpty)
              'profile_id_proprio': User_Info.activeProfileId,
          }, onConflict: 'animal_id,uid_proprio');
        } catch (_) {}
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
        // Stérilisation déclarée (false → true) alors que l'éleveur l'exige :
        // horodater et notifier l'éleveur pour qu'il valide.
        final declareSteril = _sterilise && !_steriliseInitial && _sterilRequise && !_sterilValidee;
        if (declareSteril) {
          data['sterilisation_declaree_at'] = DateTime.now().toIso8601String();
        }
        await _supa.from('animaux').update(data).eq('id', _animalId!);
        if (declareSteril && _sterilEleveurUid != null) {
          try {
            await _supa.from('notifications').insert({
              'uid':   _sterilEleveurUid,
              'type':  'sterilisation_declaree',
              'title': '✂️ Stérilisation déclarée — $nom',
              'body':  'Le propriétaire de $nom a déclaré la stérilisation. À valider dans le suivi des cessions.',
              if (_sterilEleveurProfileId != null) 'profile_id': _sterilEleveurProfileId,
              'data':  {'animalId': _animalId, 'tab': 'suivi_cessions'},
              'read':  false,
            });
          } catch (_) {}
        }
        setState(() { _photoFile = null; _photoUrl = photoUrl; _editing = false; _steriliseInitial = _sterilise; });
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
        'created_at': DateTime.now().toUtc().toIso8601String(),
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
          if (_animalId != null && _espece == 'cheval')
            IconButton(
              icon: const Icon(Icons.campaign_outlined, size: 20),
              tooltip: 'Publier une annonce',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => CreateAnnonceChevalPage(preselectedAnimalId: _animalId),
              )),
            ),
          if (_animalId != null) ...[
            if (_jeSuisPrincipal && _cessionCedant == null)
              IconButton(
                icon: const Icon(Icons.handshake_outlined, size: 20),
                tooltip: 'Confier cet animal à une association',
                onPressed: _ceder,
              ),
            IconButton(
              icon: const Icon(Icons.people_alt_outlined, size: 20),
              tooltip: 'Propriétaires',
              onPressed: () async {
                await showProprietairesAnimalSheet(
                    context, _animalId!, _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text);
                _loadProprietaires();
              },
            ),
            IconButton(
              icon: const Icon(Icons.link, size: 20),
              tooltip: 'Partager la fiche',
              onPressed: () => showPartageAnimalSheet(
                  context, _animalId!, _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text),
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
            // « Modifier » n'édite que l'identité : affiché seulement sur
            // l'onglet Identité (le premier), pour ne pas faire croire qu'il
            // modifie la santé ou l'alimentation.
            AnimatedBuilder(
              animation: _tabs,
              builder: (_, __) => _tabs.index != 0 ? const SizedBox.shrink() : TextButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white),
                label: const Text('Modifier',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            const Tab(text: 'Identité'),
            const Tab(text: 'Carnet de santé'),
            const Tab(text: 'Alimentation'),
            const Tab(text: 'Consultations'),
            const Tab(text: 'Administratif'),
            if (_showEducationTab) const Tab(text: 'Éducation'),
            if (_showPensionTab) const Tab(text: 'Pension & Garde'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_monInvitationProprio != null) _invitationCoproprioBanner(),
          if (_cessionCedant != null) _cessionCedantBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildIdentiteTab(),
                _buildSanteTab(),
                _buildAlimentationTab(),
                // Tous les comptes rendus : vétérinaire, ostéo, kiné… (catégories)
                ConsultationsProprietaireTab(animalId: _animalId, espece: _espece),
                _buildDocumentsTab(),
                if (_showEducationTab) _buildEducationTab(),
                if (_showPensionTab) _buildPensionTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _invitationCoproprioBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFEAF2F4),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vous êtes invité·e à co-gérer cette fiche',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 3),
          const Text('En acceptant, vous aurez un accès complet en lecture et écriture.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _repondreInvitationCoproprio(true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white),
                child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _repondreInvitationCoproprio(false),
                child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey')),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  VoidCallback? _repondreInvitationCoproprio(bool accepte) {
    final invit = _monInvitationProprio;
    if (invit == null) return null;
    return () async {
      try {
        await _supa.from('animaux_proprietes').update({
          'statut': accepte ? 'actif' : 'refuse',
          if (accepte) 'accepte_le': DateTime.now().toUtc().toIso8601String(),
        }).eq('animal_id', _animalId!).eq('uid_proprio', User_Info.uid);
        // Notifie l'inviteur
        final inviteurProfileId = invit['invite_par_profile_id'] as String?;
        if (inviteurProfileId != null) {
          final inviteur = await _supa
              .from('user_profiles_complet')
              .select('uid')
              .eq('id', inviteurProfileId)
              .maybeSingle();
          final inviteurUid = inviteur?['uid'] as String?;
          if (inviteurUid != null) {
            await _supa.from('notifications').insert({
              'uid': inviteurUid,
              'type': accepte ? 'coproprio_invitation_acceptee' : 'coproprio_invitation_refusee',
              'title': accepte ? 'Invitation acceptée' : 'Invitation refusée',
              'body': accepte
                  ? '${User_Info.firstname} co-gère désormais la fiche de ${_nomCtrl.text}.'
                  : '${User_Info.firstname} a refusé de co-gérer ${_nomCtrl.text}.',
              'profile_id': inviteurProfileId,
              'recipient_profile_id': inviteurProfileId,
              'data': {'animal_id': _animalId, 'animal_nom': _nomCtrl.text},
              'read': false,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _monInvitationProprio = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accepte
                ? 'Vous êtes maintenant co-propriétaire.'
                : 'Invitation refusée.')));
        if (accepte) _loadProprietaires();
      }
    };
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
        if (_coproprietairesLabel() != null) ...[
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: _animalId == null
                  ? null
                  : () async {
                      await showProprietairesAnimalSheet(context, _animalId!,
                          _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text);
                      _loadProprietaires();
                    },
              child: Text('👥 ${_coproprietairesLabel()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 12.5, color: _teal, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Chips espèce / sexe / stérilisé
        Center(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            _viewChip(
              _espece == 'autre' && _especeAutreCtrl.text.trim().isNotEmpty
                  ? _capitalize(_especeAutreCtrl.text.trim())
                  : _capitalize(_espece),
              _teal,
            ),
            _viewChip(
              _sexe == 'male' ? '♂ Mâle' : _sexe == 'femelle' ? '♀ Femelle' : 'Sexe inconnu',
              Colors.blueGrey,
            ),
            _viewChip(_sterilise ? '✂️ Stérilisé(e)' : 'Non stérilisé(e)',
                _sterilise ? _green : Colors.blueGrey),
          ]),
        ),
        const SizedBox(height: 16),

        if (_sterilRequise && !_sterilise) _sterilisationBanner(),

        if (_animalId != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AnimalTaggedPostsPage(
                  animalId: _animalId!,
                  animalName: _nomCtrl.text.trim().isEmpty ? 'cet animal' : _nomCtrl.text.trim(),
                ),
              )),
              icon: const Icon(Icons.grid_view_rounded, size: 16),
              label: const Text('Publications Pets Social',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),

        if (_animalId != null) _evolutionCard(),

        const SizedBox(height: 8),

        // Toutes les infos du formulaire d'édition — champs vides inclus
        // (affichés « Non renseigné ») pour que la fiche soit toujours complète.
        _infoRow('Espèce', _espece == 'autre'
            ? (_especeAutreCtrl.text.trim().isNotEmpty ? _especeAutreCtrl.text.trim() : 'Autre')
            : _capitalize(_espece)),
        _infoRow('Race', _raceCtrl.text, empty: _raceCtrl.text.trim().isEmpty),
        _infoRow('Date de naissance',
            dob != null ? DateFormat('dd/MM/yyyy').format(dob) : '', empty: dob == null),
        _infoRow('Sexe',
            _sexe == 'male' ? 'Mâle' : _sexe == 'femelle' ? 'Femelle' : 'Inconnu'),
        _infoRow('Couleur / robe', _couleurCtrl.text, empty: _couleurCtrl.text.trim().isEmpty),
        _infoRow('Couleur des yeux', _couleurYeuxCtrl.text, empty: _couleurYeuxCtrl.text.trim().isEmpty),
        if (_espece == 'cheval') ...[
          _infoRow('N° de transpondeur (puce)', _identCtrl.text, empty: _identCtrl.text.trim().isEmpty),
          _infoRow('N° SIRE', _sireCtrl.text, empty: _sireCtrl.text.trim().isEmpty),
          _infoRow('N° carte d\'immatriculation', _carteImmatCtrl.text, empty: _carteImmatCtrl.text.trim().isEmpty),
          _infoRow('N° livret / document d\'identification', _livretCtrl.text, empty: _livretCtrl.text.trim().isEmpty),
        ] else
          _infoRow('Identification (puce / tatouage)', _identCtrl.text,
              empty: _identCtrl.text.trim().isEmpty),
        _infoRow('Stérilisation', _sterilise ? 'Stérilisé(e)' : 'Non stérilisé(e)'),
        if (_espece != 'cheval')
          _infoRow('Passeport européen', _passeportCtrl.text,
              empty: _passeportCtrl.text.trim().isEmpty),
        if (_espece == 'chien' || _espece == 'chat')
          _infoRow('Type de poil', _typePoil ?? '',
              empty: _typePoil == null || _typePoil!.isEmpty),
        _infoRow(_tailleLabelFor(_espece),
            _tailleCtrl.text.trim().isNotEmpty ? '${_tailleCtrl.text} cm' : '',
            empty: _tailleCtrl.text.trim().isEmpty),
        _infoRow('Poids',
            _poidsCtrl.text.trim().isNotEmpty ? '${_poidsCtrl.text} kg' : '',
            empty: _poidsCtrl.text.trim().isEmpty),
        _infoRow(_pediConfig(_espece).sectionLabel, _pedigree
            ? [
                _pediConfig(_espece).yesLabel,
                if (_pedigreeLof != null && _pedigreeLof!.isNotEmpty) _pedigreeLof!,
                if (_clubRegistreCtrl.text.trim().isNotEmpty) _clubRegistreCtrl.text.trim(),
              ].join(' · ')
            : 'Non'),
        _contactsUrgenceView(),
        _infoRow('Description', _descCtrl.text, empty: _descCtrl.text.trim().isEmpty),
        _infoRow('Notes', _notesCtrl.text, empty: _notesCtrl.text.trim().isEmpty),

        // Raccourcis vers les onglets de suivi (les contenus complets sont
        // dans les onglets Documents / Éducation / Pension & Garde).
        if (_showEducationTab)
          _tabShortcut('Suivi éducateur / comportementaliste',
              'Comptes rendus de séance, exercices, devis', Icons.school_outlined,
              const Color(0xFF7B5EA7), () => _goToTab('Éducation')),
        if (_showPensionTab)
          _tabShortcut('Pension & Garde',
              'Photos, vidéos et nouvelles de votre animal', Icons.photo_camera_back_outlined,
              const Color(0xFF6E9E57), () => _goToTab('Pension & Garde')),
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
                    couleurYeux: _couleurYeuxCtrl.text,
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

  Widget _infoRow(String label, String value, {bool empty = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11,
          fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.4)),
      const SizedBox(height: 4),
      Text(empty ? 'Non renseigné' : value,
          style: TextStyle(fontFamily: 'Galey', fontSize: 15,
              color: empty ? Colors.grey.shade400 : const Color(0xFF1F2A2E),
              fontStyle: empty ? FontStyle.italic : FontStyle.normal)),
      const Divider(height: 20, color: Color(0xFFEEEEEE)),
    ]),
  );

  Widget _contactsUrgenceView() {
    final contacts = _contactsUrgence
        .where((c) => c.nom.text.isNotEmpty || c.tel.text.isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Contacts urgence', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
            fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        if (contacts.isEmpty)
          Text('Non renseigné', style: TextStyle(fontFamily: 'Galey', fontSize: 15,
              color: Colors.grey.shade400, fontStyle: FontStyle.italic))
        else
          ...contacts.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.phone_outlined, size: 15, color: Color(0xFF0C5C6C)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    [if (c.nom.text.isNotEmpty) c.nom.text, if (c.tel.text.isNotEmpty) c.tel.text].join(' — '),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
                  )),
                ]),
              )),
        const Divider(height: 20, color: Color(0xFFEEEEEE)),
      ]),
    );
  }

  // ── Navigation entre onglets ──────────────────────────────────────────────
  List<String> get _tabLabelList => [
        'Identité', 'Carnet de santé', 'Alimentation', 'Consultations', 'Documents',
        if (_showEducationTab) 'Éducation',
        if (_showPensionTab) 'Pension & Garde',
      ];

  void _goToTab(String label) {
    final i = _tabLabelList.indexOf(label);
    if (i >= 0 && i < _tabs.length) _tabs.animateTo(i);
  }

  Widget _tabShortcut(String titre, String sous, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                    fontWeight: FontWeight.w700, color: color)),
                Text(sous, style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                    color: Color(0xFF6F767B))),
              ])),
              Icon(Icons.chevron_right, size: 18, color: color.withValues(alpha: 0.6)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Onglets Documents / Éducation / Pension ────────────────────────────────
  Widget _buildDocumentsTab() {
    if (_animalId == null) {
      return const _TabEmptyState(
          icon: Icons.folder_open_outlined,
          text: 'Enregistrez l\'animal pour attacher des documents.');
    }
    return _DocumentsTabP(
      animalId: _animalId!,
      animalNom: _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text,
      documents: _documentsLibres,
      onChanged: (docs) async {
        setState(() => _documentsLibres = docs);
        try {
          await _supa.from('animaux').update({'documents': docs}).eq('id', _animalId!);
        } catch (_) {}
      },
    );
  }

  Widget _buildEducationTab() => _EducationTabP(
        animalId: _animalId,
        animalNom: _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text,
      );

  Widget _buildPensionTab() => _PensionTabP(
        animalId: _animalId,
        animalNom: _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text,
      );

  Widget _sterilisationBanner() {
    final ech = _sterilEcheance;
    final now = DateTime.now();
    final enRetard = ech != null && ech.isBefore(DateTime(now.year, now.month, now.day));
    final echStr = ech != null ? DateFormat('dd/MM/yyyy').format(ech) : null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (enRetard ? Colors.red : Colors.orange).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (enRetard ? Colors.red : Colors.orange).withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(enRetard ? Icons.warning_amber_rounded : Icons.content_cut,
            size: 18, color: enRetard ? Colors.red.shade700 : Colors.orange.shade800),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(enRetard ? 'Stérilisation en retard' : 'Stérilisation à réaliser',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13,
                  color: enRetard ? Colors.red.shade800 : Colors.orange.shade900)),
          const SizedBox(height: 2),
          Text(
            echStr != null
                ? 'L\'éleveur demande la stérilisation avant le $echStr. Activez « Stérilisé(e) » une fois faite pour qu\'il valide.'
                : 'L\'éleveur demande la stérilisation de cet animal. Activez « Stérilisé(e) » une fois faite.',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF5B5B5B)),
          ),
        ])),
      ]),
    );
  }

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
            onChanged: (v) => setState(() { _espece = v; _raceCtrl.clear(); _syncTabs(); }),
          ),
          const SizedBox(height: 18),

          if (_espece == 'autre') ...[
            _FLabel('Préciser l\'espèce'),
            const SizedBox(height: 6),
            _FField(controller: _especeAutreCtrl, hint: 'Ex: Furet, Tortue...'),
            const SizedBox(height: 18),
          ],

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
            premiere: premiereNaissanceAnimal(_espece),
            onPicked: (d) => setState(() => _dateNaissance = d),
          ),
          const SizedBox(height: 18),

          _FLabel('Couleur / robe'),
          const SizedBox(height: 6),
          _FField(controller: _couleurCtrl, hint: 'Ex: Roux, Noir et blanc...'),
          const SizedBox(height: 18),

          _FLabel('Couleur des yeux'),
          const SizedBox(height: 6),
          _FField(controller: _couleurYeuxCtrl, hint: 'Ex: marron, bleu, vairon...'),
          const SizedBox(height: 18),

          if (_espece == 'cheval') ...[
            _FLabel('N° de transpondeur (puce)'),
            const SizedBox(height: 6),
            _FField(controller: _identCtrl, hint: 'Numéro de transpondeur'),
            const SizedBox(height: 18),
            _FLabel('N° SIRE'),
            const SizedBox(height: 6),
            _FField(controller: _sireCtrl, hint: 'Ex: 250 00X XXX XXX XXX'),
            const SizedBox(height: 18),
            _FLabel('N° carte d\'immatriculation'),
            const SizedBox(height: 6),
            _FField(controller: _carteImmatCtrl, hint: 'Numéro de la carte'),
            const SizedBox(height: 18),
            _FLabel('N° livret / document d\'identification'),
            const SizedBox(height: 6),
            _FField(controller: _livretCtrl, hint: 'Numéro du livret signalétique'),
            const SizedBox(height: 18),
          ] else ...[
            _FLabel('Identification (puce / tatouage)'),
            const SizedBox(height: 6),
            _FField(
              controller: _identCtrl,
              hint: _espece == 'chien' || _espece == 'chat'
                  ? 'Numéro I-CAD (15 chiffres)'
                  : 'Numéro de puce ou tatouage',
              keyboardType: _espece == 'chien' || _espece == 'chat'
                  ? TextInputType.number
                  : null,
              inputFormatters: _espece == 'chien' || _espece == 'chat'
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
            ),
            const SizedBox(height: 18),
          ],

          Row(children: [
            _FLabel('Stérilisé(e)'),
            const Spacer(),
            Switch(
              value: _sterilise,
              activeColor: _teal,
              // Décoché : le blanc par défaut sur fond gris clair se voit à
              // peine — piste grise franche + curseur blanc, distincte du
              // teal actif.
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade400,
              onChanged: (v) => setState(() => _sterilise = v),
            ),
          ]),
          if (_sterilRequise && !_sterilValidee) ...[
            const SizedBox(height: 4),
            Text(
              _sterilise
                  ? 'Déclaration transmise à l\'éleveur pour validation.'
                  : 'Stérilisation demandée par l\'éleveur${_sterilEcheance != null ? ' avant le ${DateFormat('dd/MM/yyyy').format(_sterilEcheance!)}' : ''}. Activez ce réglage une fois faite.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.orange.shade800),
            ),
          ],
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
    final options = [
      'Court', 'Mi-long', 'Long', 'Frisé', 'Fil de soie', 'Ras',
      if (_espece == 'chien') 'Dur',
    ];
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
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              onPressed: _searchAndAddContactPetsMatch,
              icon: const Icon(Icons.search, size: 16, color: _teal),
              label: const Text('Rechercher',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => setState(() => _contactsUrgence.add(_ContactUrgenceP())),
              icon: const Icon(Icons.add, size: 16, color: _green),
              label: const Text('Ajouter',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ]),
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

  // Recherche un utilisateur PetsMatch (nom/prénom ou email) à ajouter comme
  // contact urgence — alternative à la saisie manuelle, pas un remplacement :
  // le contact ajouté (nom + téléphone) reste ensuite modifiable comme
  // n'importe quel contact saisi à la main.
  Future<void> _searchAndAddContactPetsMatch() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _ContactPetsMatchSearchSheet(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _contactsUrgence.add(_ContactUrgenceP(
        nomVal: result['nom'] as String? ?? '',
        telVal: result['tel'] as String? ?? '',
      ));
    });
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
          _AiScanCard(onTap: _scanVetDocument, busy: _scanningDocument),
          const SizedBox(height: 16),
          _PanneauSante(children: [
            _HealthSection(
              title: 'Vaccinations',
              icon: Icons.vaccines,
              color: SanteCouleurs.vaccinations,
              records: _vaccinations,
              onAdd: _showVaccinationSheet,
              renderRecord: (r) => _RecordTile(
                title: r['vaccin'] ?? 'Inconnu',
                subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
                trailing: r['date_rappel'] != null ? 'Rappel: ${_fmtDate(r['date_rappel'])}' : null,
                onDelete: () => _deleteRecord('vaccinations', r['id'], _vaccinations),
                  onEdit: r['source'] == 'veterinaire' ? null : () => _showVaccinationSheet(existant: r),
                onTap: () => _showRecordDetail('Vaccination', r, [
                  ('Vaccin', 'vaccin'), ('Date', 'date'), ('Rappel', 'date_rappel'),
                  ('N° de lot', 'lot'), ('Vétérinaire', 'veterinaire'),
                ]),
              ),
            ),
            _HealthSection(
              title: 'Vermifuges',
              icon: Icons.pest_control,
              color: SanteCouleurs.vermifuges,
              records: _vermifuges,
              onAdd: _showVermifugeSheet,
              renderRecord: (r) => _RecordTile(
                title: r['produit'] ?? 'Inconnu',
                subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
                trailing: r['date_rappel'] != null ? 'Rappel: ${_fmtDate(r['date_rappel'])}' : null,
                onDelete: () => _deleteRecord('vermifuges', r['id'], _vermifuges),
                  onEdit: r['source'] == 'veterinaire' ? null : () => _showVermifugeSheet(existant: r),
                onRappel: () => _showVermifugeSheet(prefill: r),
                onTap: () => _showRecordDetail('Vermifuge', r, [
                  ('Produit', 'produit'), ('Dosage', 'dosage'), ('Date', 'date'),
                  ('Rappel', 'date_rappel'), ('Notes', 'notes'),
                ]),
              ),
            ),
            _HealthSection(
              title: 'Antiparasitaires',
              icon: Icons.bug_report,
              color: SanteCouleurs.antiparasitaires,
              records: _antiparasitaires,
              onAdd: _showAntiparasitaireSheet,
              renderRecord: (r) => _RecordTile(
                title: r['produit'] ?? 'Inconnu',
                subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
                trailing: r['date_rappel'] != null ? 'Rappel: ${_fmtDate(r['date_rappel'])}' : null,
                onDelete: () => _deleteRecord('antiparasitaires', r['id'], _antiparasitaires),
                  onEdit: r['source'] == 'veterinaire' ? null : () => _showAntiparasitaireSheet(existant: r),
                onRappel: () => _showAntiparasitaireSheet(prefill: r),
                onTap: () => _showRecordDetail('Antiparasitaire', r, [
                  ('Produit', 'produit'), ('Type', 'type'), ('Fréquence', 'frequence'),
                  ('Date', 'date'), ('Rappel', 'date_rappel'), ('Notes', 'notes'),
                ]),
              ),
            ),
            _HealthSection(
              title: 'Traitements',
              icon: Icons.medication,
              color: SanteCouleurs.traitements,
              records: _traitements,
              onAdd: _showTraitementSheet,
              renderRecord: (r) {
                // Résumé lisible : étape, posologie, période, rappels (miroir site).
                final resume = resumeTraitement(r);
                return _RecordTile(
                  title: r['nom'] ?? r['type'] ?? 'Inconnu',
                  subtitle: resume.isEmpty ? null : resume.join('\n'),
                  onDelete: () => _deleteRecord('traitements', r['id'], _traitements),
                  onEdit: r['source'] == 'veterinaire' ? null : () => _modifierTraitement(r),
                  onEtape: r['source'] == 'veterinaire' ? null : () => _showTraitementSheet(etapeDe: r),
                  onTap: () => _showRecordDetail('Traitement', {
                    ...r,
                    'etape': etapeTraitement(r),
                    'type': kLibellesSante[r['type']] ?? r['type'],
                    'periode': periodeTraitement(r),
                    'rappels': ligneRappelTraitement(r),
                    'notes': notesTraitement(r),
                  }, [
                    ('Nom', 'nom'), ('Étape', 'etape'), ('Type', 'type'), ('Maladie', 'description_maladie'),
                    ('Posologie', 'posologie'), ('Période', 'periode'), ('Rappels', 'rappels'),
                    ('Commentaires', 'notes'),
                  ]),
                );
              },
            ),
            _HealthSection(
              title: 'Chirurgie / Hospitalisation',
              icon: Icons.local_hospital_outlined,
              color: SanteCouleurs.chirurgies,
              records: _chirurgies,
              onAdd: _showChirurgieSheet,
              renderRecord: (r) {
                final st = r['statut']?.toString();
                final label = st == 'realise' ? 'Réalisée' : st == 'annule' ? 'Annulée' : 'Prévue';
                final t = r['type'] == 'hospitalisation' ? 'Hospitalisation' : 'Chirurgie';
                return _RecordTile(
                  title: r['intitule'] ?? t,
                  subtitle: r['date'] != null ? '$label le ${_fmtDate(r['date'])}' : label,
                  trailing: r['clinique'] ?? r['veterinaire'],
                  onDelete: () => _deleteRecord('chirurgies', r['id'], _chirurgies),
                  onEdit: r['source'] == 'veterinaire' ? null : () => _showChirurgieSheet(existant: r),
                  onTap: () => _showRecordDetail('Chirurgie / Hospitalisation', r, [
                    ('Intervention', 'intitule'), ('Type', 'type'), ('Date', 'date'),
                    ('Statut', 'statut'), ('Clinique / vétérinaire', 'clinique'),
                    ('Protocole pré-opératoire', 'protocole_preop'),
                    ('Protocole post-opératoire', 'protocole_postop'),
                    ('Notes', 'notes'),
                  ]),
                );
              },
            ),
            _HealthSection(
              title: 'Allergies',
              icon: Icons.warning_amber,
              color: SanteCouleurs.allergies,
              records: _allergies,
              onAdd: _showAllergieSheet,
              renderRecord: (r) => _RecordTile(
                title: r['description'] ?? 'Allergie',
                subtitle: r['type'],
                trailing: r['severite'],
                onDelete: () => _deleteRecord('allergies', r['id'], _allergies),
                  onEdit: r['source'] == 'veterinaire' ? null : () => _showAllergieSheet(existant: r),
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
              onEdit: (r) => _showPoidsSheet(existant: r),
              onDelete: (r) => _deleteRecord('poids', r['id'], _poids),
              fmtDate: _fmtDate,
            ),
            _HealthSection(
              title: 'Visites vétérinaires',
              icon: Icons.local_hospital,
              color: SanteCouleurs.visites,
              records: _visites,
              onAdd: _showVisiteSheet,
              renderRecord: (r) => _RecordTile(
                title: r['motif'] ?? 'Consultation',
                subtitle: r['date'] != null ? 'Le ${_fmtDate(r['date'])}' : null,
                trailing: r['veterinaire'],
                onDelete: () => _deleteRecord('visites', r['id'], _visites),
                  onEdit: r['source'] == 'veterinaire' ? null : () => _showVisiteSheet(existant: r),
                onTap: () => _showRecordDetail('Visite vétérinaire', r, [
                  ('Motif', 'motif'), ('Date', 'date'), ('Vétérinaire', 'veterinaire'),
                  ('Diagnostic', 'diagnostic'), ('Notes', 'notes'),
                ]),
              ),
            ),
            if (especeHasGenetics(_espece))
              _HealthSection(
                title: 'Génétique & tests',
                icon: Icons.biotech_outlined,
                color: const Color(0xFF7C3AED),
                records: _testsGenetiques,
                onAdd: _showTestGenetiqueSheet,
                renderRecord: (r) => _RecordTile(
                  title: r['nom'] ?? 'Test',
                  subtitle: [r['laboratoire'], _fmtDate(r['date_test']?.toString())]
                      .where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                  trailing: kResultatsGenetiques[r['resultat']] ?? (r['genotype'] as String?),
                  onDelete: () => _deleteRecord('tests_genetiques', r['id'], _testsGenetiques),
                  onEdit: () => _showTestGenetiqueSheet(existant: r),
                  onTap: () => _showRecordDetail('Test génétique', r, const [
                    ('Test', 'nom'), ('Catégorie', 'categorie'), ('Résultat', 'resultat'),
                    ('Génotype', 'genotype'), ('Laboratoire', 'laboratoire'),
                    ('Date', 'date_test'), ('Résultat en ligne', 'lien_resultat'),
                    ('Document joint', 'url'), ('Notes', 'notes'),
                  ]),
                ),
              ),
          ]),
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
    final r = list.firstWhere((x) => x['id']?.toString() == id.toString(), orElse: () => <String, dynamic>{});
    final nom = (r['vaccin'] ?? r['produit'] ?? r['nom'] ?? r['intitule'] ?? r['description'] ?? r['motif']
        ?? (r['valeur'] != null ? '${r['valeur']} kg' : null))?.toString();
    if (!await confirmerSuppressionSante(context, table, nom: nom)) return;
    try {
      await _supa.from(table).delete().eq('id', id);
      setState(() => list.removeWhere((r) => r['id'] == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Import IA (photo/PDF) ────────────────────────────────────────────────────

  static const Map<String, String> _kAiDomaineLabels = {
    'vaccination': 'Vaccination',
    'traitement': 'Traitement',
    'visite': 'Visite vétérinaire',
    'vermifuge': 'Vermifuge',
    'antiparasitaire': 'Antiparasitaire',
    'chirurgie': 'Chirurgie / Hospitalisation',
    'allergie': 'Allergie',
  };

  Future<void> _scanVetDocument() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Ordonnance, compte-rendu, carnet de vaccination, facture...',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: _teal),
            title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: _teal),
            title: const Text('Photo depuis la galerie', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: _teal),
            title: const Text('Fichier / PDF', style: TextStyle(fontFamily: 'Galey')),
            subtitle: const Text(kFormatsDocuments, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    File file;
    if (source == 'file') {
      final res = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: kExtensionsDocuments);
      final path = res?.files.single.path;
      if (path == null) return;
      file = File(path);
    } else {
      final picked = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (picked == null) return;
      file = File(picked.path);
    }
    if (!mounted) return;

    final ext = file.path.split('.').last.toLowerCase();
    final mimeType = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'png'
            ? 'image/png'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/jpeg';

    setState(() => _scanningDocument = true);
    try {
      final bytes = await file.readAsBytes();
      final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('parseCarnetDocument')
          .call({'fileBase64': base64Encode(bytes), 'mimeType': mimeType});
      final data = Map<String, dynamic>.from(result.data as Map);
      final champs = Map<String, dynamic>.from(data['champs'] as Map? ?? {});
      final alerte = data['alerte'] as String?;
      String? domaine = data['domaine'] as String?;
      if (domaine == null || !_kAiDomaineLabels.containsKey(domaine)) domaine = 'visite';

      if (!mounted) return;
      final confirmed = await _confirmAiDomaine(domaine, alerte);
      if (confirmed == null || !mounted) return;
      _routeAiExtraction(confirmed, champs);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Analyse impossible.'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _scanningDocument = false);
    }
  }

  Future<String?> _confirmAiDomaine(String domaine, String? alerte) {
    String selected = domaine;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: const Text('Document analysé', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vérifiez et complétez avant d\'enregistrer.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
          if (alerte != null && alerte.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('⚠️ $alerte', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange)),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              labelText: 'Type d\'entrée',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
            items: _kAiDomaineLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontFamily: 'Galey'))))
                .toList(),
            onChanged: (v) => ss(() => selected = v ?? selected),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, selected),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
            child: const Text('Continuer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ],
      )),
    );
  }

  void _routeAiExtraction(String domaine, Map<String, dynamic> champs) {
    switch (domaine) {
      case 'vaccination': _showVaccinationSheet(prefill: champs); break;
      case 'traitement': _showTraitementSheet(prefill: champs); break;
      case 'vermifuge': _showVermifugeSheet(prefill: champs, prefillDates: true); break;
      case 'antiparasitaire': _showAntiparasitaireSheet(prefill: champs, prefillDates: true); break;
      case 'chirurgie': _showChirurgieSheet(prefill: champs); break;
      case 'allergie': _showAllergieSheet(prefill: champs); break;
      case 'visite': default: _showVisiteSheet(prefill: champs); break;
    }
  }

  // ── Health form sheets ────────────────────────────────────────────────────────

  /// Ajout d'une entrée du carnet, ou modification de [existant] (mêmes
  /// éléments qu'à la création).
  Future<void> _enregistrerSante(String table, Map<String, dynamic>? existant, Map<String, dynamic> ligne) async {
    if (existant == null) {
      await _supa.from(table).insert(ligne);
      return;
    }
    final maj = {...ligne}..remove('id')..remove('animal_id')..remove('created_at');
    await _supa.from(table).update(maj).eq('id', existant['id']);
  }

  void _showVaccinationSheet({Map<String, dynamic>? prefill, Map<String, dynamic>? existant}) {
    prefill ??= existant;
    final vaccin = TextEditingController(text: prefill?['vaccin'] ?? ''),
        lot = TextEditingController(text: prefill?['lot'] ?? ''),
        veto = TextEditingController(text: prefill?['veterinaire'] ?? '');
    DateTime? date = DateTime.tryParse(prefill?['date'] ?? ''),
        dateRappel = DateTime.tryParse(prefill?['date_rappel'] ?? ''),
        dateValidite = DateTime.tryParse(prefill?['date_validite_debut'] ?? '');
    String? categorie = prefill?['categorie'] as String?;

    (int ans, int jours)? defautsPourCategorie() {
      if (categorie == null) return null;
      for (final t in typesVaccinPour(_espece)) {
        if (t.$1 == categorie) return (t.$2, t.$3);
      }
      return null;
    }

    // Le délai légal (ex: rage = 21 jours) ne s'applique qu'à la toute
    // première injection de ce type de vaccin pour cet animal : un rappel
    // d'un vaccin déjà administré est valide dès le jour même.
    Future<bool> estPremiereFois(String cat) async {
      try {
        final rows = await _supa.from('vaccinations').select('id')
            .eq('animal_id', _animalId!).eq('categorie', cat);
        return (rows as List).isEmpty;
      } catch (_) {
        return true;
      }
    }

    Future<void> recomputeSuggestions(StateSetter ss, {bool force = false}) async {
      if (date == null || categorie == null) return;
      final d = defautsPourCategorie();
      if (d == null) return;
      final premiereFois = await estPremiereFois(categorie!);
      if (force || dateValidite == null) {
        ss(() => dateValidite = date!.add(Duration(days: premiereFois ? d.$2 : 0)));
      }
      if (force || dateRappel == null) {
        ss(() => dateRappel = DateTime(date!.year + d.$1, date!.month, date!.day));
      }
    }

    _openSheet(existant != null ? 'Modifier la vaccination' : 'Ajouter une vaccination', (ss) => [
      _SDrop(
        label: 'Type de vaccin',
        value: categorie,
        options: typesVaccinPour(_espece).map((t) => t.$1).toList(),
        onChanged: (v) {
          if (v == null) return;
          ss(() => categorie = v);
          if (vaccin.text.trim().isEmpty) vaccin.text = v;
          recomputeSuggestions(ss, force: true);
        },
      ),
      _SFld(ctrl: vaccin, label: 'Vaccin', hint: 'Ex: Rage, CCHPPI...'),
      _SFld(ctrl: lot, label: 'N° de lot', hint: 'Numéro de lot'),
      _SFld(ctrl: veto, label: 'Vétérinaire', hint: 'Nom du vétérinaire'),
      _SDate(label: 'Date', date: date, onPicked: (d) { ss(() => date = d); recomputeSuggestions(ss, force: true); }),
      _SDate(label: 'Valide à partir de', date: dateValidite, onPicked: (d) => ss(() => dateValidite = d)),
      _SDate(label: 'Date de rappel', date: dateRappel, onPicked: (d) => ss(() => dateRappel = d)),
    ], () async {
      if (vaccin.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le nom du vaccin.');
      controlerDatesSante(date: date, rappel: dateRappel, validite: dateValidite);
      await _enregistrerSante('vaccinations', existant, {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'vaccin': vaccin.text.trim(),
        'lot': lot.text.trim().isEmpty ? null : lot.text.trim(),
        'veterinaire': veto.text.trim().isEmpty ? null : veto.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'date_validite_debut': (dateValidite ?? date)?.toIso8601String().substring(0, 10),
        'date_rappel': dateRappel?.toIso8601String().substring(0, 10),
        'categorie': categorie,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      // Rappel d'agenda : à la création, ou si la date de rappel a changé.
      if (dateRappel != null && (existant == null || existant['date_rappel']?.toString().substring(0, 10) != dateRappel!.toIso8601String().substring(0, 10))) {
        await _scheduleRappelAgenda(
          dateRappel: dateRappel!,
          titre: 'Rappel vaccin — ${vaccin.text.trim()} (${_nomCtrl.text})',
        );
      }
      await _loadHealthRecords();
    });
  }

  /// [etapeDe] : étape suivante d'une posologie progressive (pré-remplie,
  /// même groupe, notes « Phase i/n »).
  /// Modifier un traitement : toutes ses étapes (même groupe), comme à la création.
  Future<void> _modifierTraitement(Map<String, dynamic> r) async {
    var groupe = [r];
    final gid = r['groupe_id']?.toString();
    if (gid != null && gid.isNotEmpty) {
      try {
        final rows = await _supa.from('traitements').select().eq('animal_id', _animalId!).eq('groupe_id', gid);
        groupe = List<Map<String, dynamic>>.from(rows as List)
          ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
      } catch (_) {}
    }
    if (mounted) _showTraitementSheet(groupe: groupe);
  }

  void _showTraitementSheet({Map<String, dynamic>? prefill, Map<String, dynamic>? etapeDe, List<Map<String, dynamic>>? groupe}) {
    if (groupe != null && groupe.isNotEmpty) {
      prefill = {
        ...groupe.first,
        'notes': notesTraitement(groupe.first),
        if (groupe.length > 1) 'posologie': '',
      };
    }
    if (etapeDe != null) {
      prefill = {
        'nom': etapeDe['nom'], 'type': etapeDe['type'], 'description_maladie': etapeDe['description_maladie'],
        'posologie': etapeDe['posologie'], 'date': debutEtapeSuivante(etapeDe).toIso8601String(),
      };
    }
    final nom = TextEditingController(text: prefill?['nom'] ?? ''),
        type = TextEditingController(text: prefill?['type'] ?? ''),
        descriptionMaladie = TextEditingController(text: prefill?['description_maladie'] ?? ''),
        posologie = TextEditingController(text: prefill?['posologie'] ?? ''),
        notes = TextEditingController(text: prefill?['notes'] ?? '');
    DateTime? date = DateTime.tryParse(prefill?['date'] ?? '');

    // ── Posologie en étapes (ex. 4 jours matin et soir, puis 3 jours le
    // matin seulement), chaque prise avec sa quantité ; rappel à chaque prise.
    bool rappelActif = groupe != null
        ? groupe.any((g) => g['rappel_actif'] == true)
        : (etapeDe == null || etapeDe['rappel_actif'] == true);
    int jours(Map g) {
      final d = DateTime.tryParse(g['date']?.toString() ?? ''), f = DateTime.tryParse(g['date_fin']?.toString() ?? '');
      if (d != null && f != null) return f.difference(DateTime(d.year, d.month, d.day)).inDays + 1;
      return int.tryParse('${g['rappel_duree_jours'] ?? ''}') ?? 7;
    }
    final etapes = groupe != null && groupe.isNotEmpty
        ? [for (final g in groupe) EtapeTraitement(dureeJours: jours(g).clamp(1, 3650),
            frequenceJours: int.tryParse('${g['rappel_frequence_jours'] ?? ''}') ?? 1, prises: prisesDepuis(g))]
        : <EtapeTraitement>[
      etapeDe != null
          ? EtapeTraitement(dureeJours: 3,
              frequenceJours: int.tryParse('${etapeDe['rappel_frequence_jours'] ?? ''}') ?? 1,
              prises: prisesDepuis(etapeDe))
          : EtapeTraitement(),
    ];

    _openSheet(groupe != null ? 'Modifier le traitement' : etapeDe != null ? 'Étape suivante' : 'Ajouter un traitement', (ss) => [
      _SFld(ctrl: nom, label: 'Nom du traitement', hint: 'Ex: Amoxicilline...'),
      _SFld(ctrl: type, label: 'Type', hint: 'Ex: Antibiotique, Anti-inflammatoire...'),
      _SFld(ctrl: descriptionMaladie, label: 'Description de la maladie',
          hint: 'Ex: Otite, gastro-entérite...', maxLines: 3),
      _SFld(ctrl: posologie, label: 'Posologie (résumé, facultatif)', hint: 'Ex: dégressif sur 7 jours'),
      _SDate(label: 'Date de début', date: date, onPicked: (d) => ss(() => date = d)),
      Row(children: [
        const Expanded(child: Text('Rappel à chaque prise',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13))),
        Switch(value: rappelActif, activeThumbColor: const Color(0xFF6E9E57),
            onChanged: (v) => ss(() => rappelActif = v)),
      ]),
      EtapesTraitementEditor(etapes: etapes, debut: date, onChanged: () => ss(() {})),
      const SizedBox(height: 12),
      _SFld(ctrl: notes, label: 'Commentaires', maxLines: 3,
          hint: 'Ex: impressions de tolérance au traitement, effets observés...'),
    ], () async {
      if (nom.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le nom du traitement.');
      controlerDatesSante(date: date, fin: finTraitement(date, etapes));
      if (etapes.isEmpty) throw const SaisieInvalide('Ajoutez au moins une étape.');
      final rythme = erreurEtapes(etapes);
      if (rythme != null) throw SaisieInvalide(rythme);
      if (rappelActif && etapes.any((e) => e.prises.isEmpty)) {
        throw const SaisieInvalide('Ajoutez au moins une prise à chaque étape (ou désactivez les rappels).');
      }
      final lignes = lignesEtapes(
        base: {
          'animal_id': _animalId!,
          'nom': nom.text.trim(),
          'type': type.text.trim().isEmpty ? null : type.text.trim(),
          'description_maladie': descriptionMaladie.text.trim().isEmpty ? null : descriptionMaladie.text.trim(),
          if (posologie.text.trim().isNotEmpty) 'posologie': posologie.text.trim(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        debut: date!, etapes: etapes, rappels: rappelActif, notes: notes.text,
      );
      // Étape(s) ajoutée(s) à une posologie existante : même groupe, numérotation suivie.
      if (etapeDe != null) {
        final g = await preparerEtapeSuivante(_animalId!, etapeDe, nouvelles: lignes.length);
        for (var k = 0; k < lignes.length; k++) {
          lignes[k]['groupe_id'] = g.id;
          lignes[k]['notes'] = ['Phase ${g.existantes + k + 1}/${g.total}', if (notes.text.trim().isNotEmpty) notes.text.trim()]
              .join(' — ');
        }
      }
      // Modification : même groupe, les anciennes étapes sont remplacées.
      final gid = groupe?.firstWhere((g) => (g['groupe_id'] ?? '').toString().isNotEmpty, orElse: () => {})['groupe_id'];
      if (gid != null && lignes.length > 1) {
        for (final l in lignes) { l['groupe_id'] = gid; }
      }
      await _supa.from('traitements').insert(lignes);
      for (final g in groupe ?? const <Map<String, dynamic>>[]) {
        await _supa.from('traitements').delete().eq('id', g['id']);
      }
      await _loadHealthRecords();
    });
  }

  void _showVisiteSheet({Map<String, dynamic>? prefill, Map<String, dynamic>? existant}) {
    prefill ??= existant;
    final motif = TextEditingController(text: prefill?['motif'] ?? ''),
        veto = TextEditingController(text: prefill?['veterinaire'] ?? ''),
        diag = TextEditingController(text: prefill?['diagnostic'] ?? ''),
        notes = TextEditingController(text: prefill?['notes'] ?? '');
    DateTime? date = DateTime.tryParse(prefill?['date'] ?? '');
    final isFirstVisit = _visites.isEmpty;
    _openSheet(existant != null ? 'Modifier la visite' : 'Ajouter une visite', (ss) => [
      _SFld(ctrl: motif, label: 'Motif *', hint: 'Ex: Contrôle annuel, Blessure...'),
      _SFld(ctrl: veto, label: 'Vétérinaire', hint: 'Nom du vétérinaire'),
      _SDate(label: 'Date', date: date, onPicked: (d) => ss(() => date = d)),
      _SFld(ctrl: diag, label: 'Diagnostic', hint: 'Diagnostic posé'),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes supplémentaires'),
    ], () async {
      // Une seule phrase pour les champs manquants (« Date et motif sont à remplir. »).
      final vides = [if (date == null) 'Date', if (motif.text.trim().isEmpty) 'Motif'];
      if (vides.isNotEmpty) throw SaisieInvalide(phraseChampsARemplir(vides));
      controlerDatesSante(date: date);
      await _enregistrerSante('visites', existant, {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'motif': motif.text.trim(),
        'veterinaire': veto.text.trim().isEmpty ? null : veto.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'diagnostic': diag.text.trim().isEmpty ? null : diag.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _loadHealthRecords();
      if (isFirstVisit) {
        _showInsuranceCta(reason: '🩺 Première visite vétérinaire — pensez à assurer votre animal !');
      }
    });
  }

  // "1 mois" / "2 semaines" / "10 jours" -> (valeur, unité), best-effort.
  (String, String)? _parseFrequence(String? text) {
    final m = RegExp(r'^(\d+)\s*(jour|semaine|mois)', caseSensitive: false).firstMatch(text ?? '');
    if (m == null) return null;
    return (m.group(1)!, m.group(2)!.toLowerCase());
  }

  void _showVermifugeSheet({Map<String, dynamic>? prefill, bool prefillDates = false, Map<String, dynamic>? existant}) {
    if (existant != null) { prefill = existant; prefillDates = true; }
    final produit = TextEditingController(text: prefill?['produit'] ?? '');
    final dosage = TextEditingController(text: prefill?['dosage'] ?? '');
    final notes = TextEditingController(text: prefill?['notes'] ?? '');
    final parsedFreq = _parseFrequence(prefill?['frequence'] as String?);
    final frequenceValeur = TextEditingController(text: parsedFreq?.$1 ?? '');
    DateTime? date = prefillDates ? DateTime.tryParse(prefill?['date'] ?? '') : null;
    DateTime? dateRappel = prefillDates ? DateTime.tryParse(prefill?['date_rappel'] ?? '') : null;
    String frequenceUnite = parsedFreq?.$2 ?? 'mois';
    // Durée / rappels de prise + autres animaux (widgets/carnet/vermifuge_options.dart).
    final options = OptionsVermifuge();
    if (existant != null) {
      options.dureeJours = int.tryParse('${existant['duree_jours'] ?? existant['rappel_duree_jours'] ?? ''}') ?? 1;
      options.rappel = existant['rappel_actif'] == true;
      options.heures.addAll(((existant['rappel_heures'] as List?) ?? const []).map((h) => h.toString()));
    }

    void recomputeRappel(StateSetter ss) {
      if (date == null) return;
      final n = int.tryParse(frequenceValeur.text.trim());
      if (n == null || n <= 0) return;
      final days = frequenceUnite == 'jour' ? n : frequenceUnite == 'semaine' ? n * 7 : n * 30;
      ss(() => dateRappel = date!.add(Duration(days: days)));
    }

    _openSheet(existant != null ? 'Modifier le vermifuge' : 'Ajouter un vermifuge', (ss) => [
      _SFld(ctrl: produit, label: 'Produit *', hint: 'Ex: Milbemax, Drontal...'),
      _SFld(ctrl: dosage, label: 'Dosage', hint: 'Ex: 1 comprimé'),
      _SDate(label: 'Date', date: date, onPicked: (d) { ss(() => date = d); recomputeRappel(ss); }),
      _SFreq(valeurCtrl: frequenceValeur, unite: frequenceUnite,
        onValeurChanged: () => recomputeRappel(ss),
        onUniteChanged: (v) { ss(() => frequenceUnite = v); recomputeRappel(ss); }),
      PrisesVermifugeSection(options: options),
      const SizedBox(height: 10),
      if (existant == null) ...[
        AutresAnimauxSection(animalId: _animalId!, options: options),
        const SizedBox(height: 10),
      ],
      // Calculée à partir de la date et de la fréquence : non modifiable.
      _SDate(label: 'Date de rappel (calculée)', date: dateRappel, onPicked: null),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes'),
    ], () async {
      final vides = [if (produit.text.trim().isEmpty) 'Produit', if (date == null) 'Date'];
      if (vides.isNotEmpty) throw SaisieInvalide(phraseChampsARemplir(vides));
      if (options.erreur != null) throw Exception(options.erreur);
      controlerDatesSante(date: date, rappel: dateRappel);
      final n = int.tryParse(frequenceValeur.text.trim());
      final freqLabel = (n != null && n > 0)
          ? '$n ${frequenceUnite == 'jour' ? 'jour${n > 1 ? 's' : ''}' : frequenceUnite == 'semaine' ? 'semaine${n > 1 ? 's' : ''}' : 'mois'}'
          : null;
      final cibles = [_animalId!, ...options.autresAnimaux];
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < cibles.length; i++) {
        await _enregistrerSante('vermifuges', existant, {
          'id': '${base + i}',
          'animal_id': cibles[i],
          'produit': produit.text.trim(),
          'dosage': dosage.text.trim().isEmpty ? null : dosage.text.trim(),
          'date': date?.toIso8601String().substring(0, 10),
          'date_rappel': dateRappel?.toIso8601String().substring(0, 10),
          if (freqLabel != null) 'frequence': freqLabel,
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          if (date != null) ...options.colonnes(date!),
        });
      }
      // Prochain rappel : un seul événement pour tous les animaux (à la création,
      // ou si la date de rappel a changé).
      if (dateRappel != null && (existant == null || existant['date_rappel']?.toString().substring(0, 10) != dateRappel!.toIso8601String().substring(0, 10))) {
        var noms = _nomCtrl.text;
        if (options.autresAnimaux.isNotEmpty) {
          try {
            final rows = await _supa.from('animaux').select('nom').inFilter('id', cibles);
            noms = [for (final r in rows as List) r['nom']?.toString() ?? ''].where((x) => x.isNotEmpty).join(', ');
          } catch (_) {}
        }
        await _scheduleRappelAgenda(
          dateRappel: dateRappel!,
          titre: 'Rappel vermifuge — ${produit.text.trim()} ($noms)',
        );
      }
      await _loadHealthRecords();
    });
  }

  void _showAntiparasitaireSheet({Map<String, dynamic>? prefill, bool prefillDates = false, Map<String, dynamic>? existant}) {
    if (existant != null) { prefill = existant; prefillDates = true; }
    final produit = TextEditingController(text: prefill?['produit'] ?? '');
    final type = TextEditingController(text: prefill?['type'] ?? '');
    final notes = TextEditingController(text: prefill?['notes'] ?? '');
    final parsedFreq = _parseFrequence(prefill?['frequence'] as String?);
    final frequenceValeur = TextEditingController(text: parsedFreq?.$1 ?? '1');
    DateTime? date = prefillDates ? DateTime.tryParse(prefill?['date'] ?? '') : null;
    DateTime? dateRappel = prefillDates ? DateTime.tryParse(prefill?['date_rappel'] ?? '') : null;
    String frequenceUnite = parsedFreq?.$2 ?? 'mois';

    void recomputeRappel(StateSetter ss) {
      if (date == null) return;
      final n = int.tryParse(frequenceValeur.text.trim());
      if (n == null || n <= 0) return;
      final days = frequenceUnite == 'jour' ? n : frequenceUnite == 'semaine' ? n * 7 : n * 30;
      ss(() => dateRappel = date!.add(Duration(days: days)));
    }

    _openSheet(existant != null ? 'Modifier l\'antiparasitaire' : 'Ajouter un antiparasitaire', (ss) => [
      _SFld(ctrl: produit, label: 'Produit *', hint: 'Ex: Frontline, Advantix...'),
      _SFld(ctrl: type, label: 'Type', hint: 'Ex: Pipette, Collier, Spray...'),
      _SDate(label: 'Date', date: date, onPicked: (d) { ss(() => date = d); recomputeRappel(ss); }),
      _SFreq(valeurCtrl: frequenceValeur, unite: frequenceUnite,
        onValeurChanged: () => recomputeRappel(ss),
        onUniteChanged: (v) { ss(() => frequenceUnite = v); recomputeRappel(ss); }),
      // Calculée à partir de la date et de la fréquence : non modifiable.
      _SDate(label: 'Date de rappel (calculée)', date: dateRappel, onPicked: null),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes'),
    ], () async {
      final vides = [if (produit.text.trim().isEmpty) 'Produit', if (date == null) 'Date'];
      if (vides.isNotEmpty) throw SaisieInvalide(phraseChampsARemplir(vides));
      controlerDatesSante(date: date, rappel: dateRappel);
      final n = int.tryParse(frequenceValeur.text.trim());
      final freqLabel = (n != null && n > 0)
          ? '$n ${frequenceUnite == 'jour' ? 'jour${n > 1 ? 's' : ''}' : frequenceUnite == 'semaine' ? 'semaine${n > 1 ? 's' : ''}' : 'mois'}'
          : null;
      await _enregistrerSante('antiparasitaires', existant, {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'produit': produit.text.trim(),
        'type': type.text.trim().isEmpty ? null : type.text.trim(),
        'frequence': freqLabel,
        'date': date?.toIso8601String().substring(0, 10),
        'date_rappel': dateRappel?.toIso8601String().substring(0, 10),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
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

  void _showAllergieSheet({Map<String, dynamic>? prefill, Map<String, dynamic>? existant}) {
    prefill ??= existant;
    final desc = TextEditingController(text: prefill?['description'] ?? ''),
        type = TextEditingController(text: prefill?['type'] ?? ''),
        severite = TextEditingController(text: prefill?['severite'] ?? ''),
        notes = TextEditingController(text: prefill?['notes'] ?? '');
    DateTime? date = DateTime.tryParse(prefill?['date'] ?? '');
    _openSheet(existant != null ? 'Modifier l\'allergie' : 'Ajouter une allergie', (ss) => [
      _SFld(ctrl: desc, label: 'Description *', hint: 'Ex: Allergie au pollen...'),
      _SFld(ctrl: type, label: 'Type', hint: 'Ex: Alimentaire, Cutanée...'),
      _SFld(ctrl: severite, label: 'Sévérité', hint: 'Ex: Légère, Modérée, Sévère'),
      // Constatée : jamais dans le futur (même libellé que le site).
      _SDate(label: 'Date constatée', date: date, lastDate: DateTime.now(), onPicked: (d) => ss(() => date = d)),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes supplémentaires'),
    ], () async {
      if (desc.text.trim().isEmpty) throw const SaisieInvalide('Indiquez la description de l\'allergie.');
      if (date != null && date!.isAfter(DateTime.now())) {
        throw const SaisieInvalide('La date constatée ne peut pas être dans le futur.');
      }
      await _enregistrerSante('allergies', existant, {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'description': desc.text.trim(),
        'type': type.text.trim().isEmpty ? null : type.text.trim(),
        'severite': severite.text.trim().isEmpty ? null : severite.text.trim(),
        'date': date?.toIso8601String().substring(0, 10),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _loadHealthRecords();
    });
  }

  void _showChirurgieSheet({Map<String, dynamic>? prefill, Map<String, dynamic>? existant}) {
    prefill ??= existant;
    final intitule = TextEditingController(text: prefill?['intitule'] ?? ''),
        clinique = TextEditingController(text: prefill?['clinique'] ?? ''),
        preop = TextEditingController(text: prefill?['protocole_preop'] ?? ''),
        postop = TextEditingController(text: prefill?['protocole_postop'] ?? ''),
        notes = TextEditingController(text: prefill?['notes'] ?? '');
    DateTime? date = DateTime.tryParse(prefill?['date'] ?? '');
    String type = (prefill?['type'] as String?) ?? 'chirurgie',
        statut = (prefill?['statut'] as String?) ?? 'prevu';
    _openSheet('Chirurgie / Hospitalisation', (ss) => [
      _SDrop(label: 'Type', value: type, options: const ['chirurgie', 'hospitalisation'],
          onChanged: (v) => ss(() => type = v ?? 'chirurgie')),
      _SFld(ctrl: intitule, label: 'Intervention', hint: 'Ex: Stérilisation, Détartrage sous AG...'),
      _SDate(label: 'Date (prévue ou réalisée)', date: date, onPicked: (d) => ss(() {
        date = d;
        statut = d.isBefore(DateTime.now()) ? 'realise' : 'prevu';
      })),
      _SDrop(label: 'Statut', value: statut, options: const ['prevu', 'realise', 'annule'],
          onChanged: (v) => ss(() => statut = v ?? 'prevu')),
      _SFld(ctrl: clinique, label: 'Clinique / vétérinaire', hint: 'Nom de la clinique'),
      _SFld(ctrl: preop, label: 'Protocole pré-opératoire', hint: 'Jeûne, prémédication, anesthésie...', maxLines: 3),
      _SFld(ctrl: postop, label: 'Protocole post-opératoire', hint: 'Analgésie, soins de plaie, repos, contrôle...', maxLines: 3),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes'),
    ], () async {
      if (intitule.text.trim().isEmpty) throw const SaisieInvalide('Indiquez l\'intervention.');
      controlerDatesSante(date: date, statut: statut);
      await _enregistrerSante('chirurgies', existant, {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'type': type,
        'intitule': intitule.text.trim(),
        'date': date!.toIso8601String().substring(0, 10),
        'statut': statut,
        'protocole_preop': preop.text.trim().isEmpty ? null : preop.text.trim(),
        'protocole_postop': postop.text.trim().isEmpty ? null : postop.text.trim(),
        'clinique': clinique.text.trim().isEmpty ? null : clinique.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (statut == 'prevu' && date!.isAfter(DateTime.now())) {
        await _scheduleRappelAgenda(
          dateRappel: date!,
          titre: '${type == 'hospitalisation' ? 'Hospitalisation' : 'Chirurgie'} prévue — ${intitule.text.trim()} (${_nomCtrl.text})',
        );
      }
      await _loadHealthRecords();
    });
  }

  void _showTestGenetiqueSheet({Map<String, dynamic>? existant}) {
    final nomCtrl = TextEditingController(text: existant?['nom']?.toString() ?? ''),
        genoCtrl = TextEditingController(text: existant?['genotype']?.toString() ?? ''),
        laboCtrl = TextEditingController(text: existant?['laboratoire']?.toString() ?? ''),
        notesCtrl = TextEditingController(text: existant?['notes']?.toString() ?? ''),
        lienCtrl = TextEditingController(text: existant?['lien_resultat']?.toString() ?? '');
    DateTime? date = DateTime.tryParse(existant?['date_test']?.toString() ?? '');
    String categorie = (existant?['categorie'] ?? 'maladie').toString();
    String? selectedCode = existant == null ? null : (existant['code']?.toString() ?? '');
    String resultat = (existant?['resultat'] ?? 'clair').toString();
    String? url = existant?['url']?.toString();
    bool uploading = false;

    List<GeneticTest> presetsFor(String cat) =>
        (kGeneticTests[_espece] ?? const []).where((t) => t.categorie == cat).toList();

    void syncPreset(StateSetter ss) {
      final list = presetsFor(categorie);
      if (list.isNotEmpty) {
        selectedCode = list.first.code;
        nomCtrl.text = list.first.nom;
      } else {
        selectedCode = '';
        nomCtrl.text = '';
      }
      if (categorie == 'adn' || categorie == 'complet') resultat = 'etabli';
    }

    Future<void> pickFile(StateSetter ss) async {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Galerie'),
              onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Appareil photo'),
              onTap: () => Navigator.pop(context, 'camera')),
          ListTile(leading: const Icon(Icons.insert_drive_file_outlined), title: const Text('Fichier'),
              subtitle: const Text(kFormatsDocuments, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              onTap: () => Navigator.pop(context, 'file')),
        ])),
      );
      if (choice == null) return;
      File? f;
      if (choice == 'file') {
        final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: kExtensionsDocuments);
        if (r?.files.single.path == null) return;
        f = File(r!.files.single.path!);
      } else {
        final p = await ImagePicker().pickImage(
            source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 85);
        if (p == null) return;
        f = File(p.path);
      }
      ss(() => uploading = true);
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        final name = '${DateTime.now().millisecondsSinceEpoch}_${f.path.split('/').last}';
        url = await uploadRawFile(f, 'documents/$uid/$name');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Envoi impossible ($kFormatsDocuments) : $e'), backgroundColor: Colors.red));
        }
      }
      ss(() => uploading = false);
    }

    _openSheet(existant != null ? 'Modifier le test génétique' : 'Test génétique', (ss) {
      final presets = presetsFor(categorie);
      return [
        _SDrop(label: 'Catégorie', value: categorie, options: kGeneticTestCategories,
            onChanged: (v) => ss(() { categorie = v ?? 'maladie'; syncPreset(ss); })),
        if (presets.isNotEmpty)
          _SDrop(label: 'Test', value: selectedCode == '' ? 'Autre (saisie libre)' : selectedCode,
              options: [...presets.map((t) => t.code), 'Autre (saisie libre)'],
              libelles: {for (final t in presets) t.code: t.nom},
              onChanged: (v) => ss(() {
                if (v == null || v == 'Autre (saisie libre)') {
                  selectedCode = ''; nomCtrl.text = '';
                } else {
                  selectedCode = v;
                  nomCtrl.text = presets.firstWhere((t) => t.code == v).nom;
                }
              })),
        if (presets.isEmpty || selectedCode == '')
          _SFld(ctrl: nomCtrl, label: 'Nom du test', hint: 'Ex : WFFS, MDR1, PKD…'),
        if (categorie != 'robe')
          _SDrop(label: 'Résultat', value: resultat, options: kResultatsGenetiques.keys.toList(),
              onChanged: (v) => ss(() => resultat = v ?? 'clair')),
        _SFld(ctrl: genoCtrl, label: 'Génotype / notation labo', hint: 'N/N, N/WFFS, HD-A/A…'),
        _SFld(ctrl: laboCtrl, label: 'Laboratoire', hint: 'Labéo, Antagene, UC Davis…'),
        _SDate(label: 'Date du test', date: date, firstDate: _dateNaissance, lastDate: DateTime.now(),
            onPicked: (d) => ss(() => date = d)),
        _SFld(ctrl: lienCtrl, label: 'Lien du résultat en ligne', hint: 'https://… (Embark, Wisdom Panel…)'),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: OutlinedButton.icon(
            onPressed: uploading ? null : () => pickFile(ss),
            icon: uploading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(url != null ? Icons.check_circle_outline : Icons.attach_file, size: 16),
            label: Text(url != null ? 'Résultat joint' : 'Joindre le résultat (PDF/photo)',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          ),
        ),
        _SFld(ctrl: notesCtrl, label: 'Notes', hint: 'Notes', maxLines: 2),
      ];
    }, () async {
      final nom = nomCtrl.text.trim();
      if (nom.isEmpty) return;
      controlerDateTestGenetique(date, _dateNaissance);
      if (lienCtrl.text.trim().isNotEmpty && lienWeb(lienCtrl.text).isEmpty) {
        throw const SaisieInvalide('Lien du résultat : adresse web invalide (ex. https://embarkvet.com/…).');
      }
      final hit = presetsFor(categorie).where((t) => t.code == selectedCode).toList();
      final ligne = <String, dynamic>{
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'animal_id': _animalId!,
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'espece': _espece,
        'categorie': categorie,
        'code': hit.isNotEmpty ? hit.first.code : null,
        'nom': nom,
        'resultat': categorie == 'robe' ? null : resultat,
        'genotype': genoCtrl.text.trim().isEmpty ? null : genoCtrl.text.trim(),
        'laboratoire': laboCtrl.text.trim().isEmpty ? null : laboCtrl.text.trim(),
        'date_test': date?.toIso8601String().substring(0, 10),
        'url': url,
        if (lienWeb(lienCtrl.text).isNotEmpty) 'lien_resultat': lienWeb(lienCtrl.text)
        else if (existant?['lien_resultat'] != null) 'lien_resultat': null,
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (existant != null) {
        ligne.remove('id');
        ligne.remove('created_at');
      }
      // Colonne lien_resultat absente en base (migration_tests_genetiques_lien.sql
      // pas passée) : le test est enregistré sans le lien plutôt que refusé.
      Future<void> ecrire() => existant != null
          ? _supa.from('tests_genetiques').update(ligne).eq('id', existant['id'])
          : _supa.from('tests_genetiques').insert(ligne);
      try {
        await ecrire();
      } on PostgrestException catch (e) {
        // 42703 en lecture, PGRST204 en écriture (« Could not find the 'lien_resultat' column »).
        if (!const {'42703', 'PGRST204'}.contains(e.code) || !ligne.containsKey('lien_resultat')) rethrow;
        ligne.remove('lien_resultat');
        await ecrire();
      }
      if (categorie == 'adn' && resultat == 'etabli') {
        try {
          await _supa.from('animaux').update({'profil_adn_etabli': true}).eq('id', _animalId!);
        } catch (_) {}
      }
      await _loadHealthRecords();
    });
  }

  void _showPoidsSheet({Map<String, dynamic>? existant}) {
    final valeur = TextEditingController(text: existant?['valeur']?.toString() ?? ''),
        notes = TextEditingController(text: existant?['notes']?.toString() ?? '');
    DateTime? date = DateTime.tryParse(existant?['date']?.toString() ?? '');
    _openSheet(existant != null ? 'Modifier le poids' : 'Ajouter un poids', (ss) => [
      _SFld(ctrl: valeur, label: 'Poids (kg) *', hint: 'Ex: 4.5', numeric: true),
      // Pesée : ni avant la naissance, ni après aujourd'hui.
      _SDate(label: 'Date *', date: date, onPicked: (d) => ss(() => date = d),
          firstDate: _dateNaissance, lastDate: DateTime.now()),
      _SFld(ctrl: notes, label: 'Notes', hint: 'Notes'),
    ], () async {
      // « 8,5 » ou « 8.5 », date obligatoire et passée (avant : une date vide
      // devenait « aujourd'hui » sans le dire).
      if (valeur.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le poids.');
      final v = poidsKg(valeur.text);
      if (v == null) throw const SaisieInvalide('Poids invalide : chiffres uniquement, avec . ou , pour les décimales (ex. 8,5).');
      if (v <= 0) throw const SaisieInvalide('Le poids doit être supérieur à 0.');
      if (date == null) throw const SaisieInvalide('Indiquez la date de la pesée.');
      final jour = DateTime(date!.year, date!.month, date!.day);
      if (jour.isAfter(DateTime.now())) throw const SaisieInvalide('La date de la pesée ne peut pas être dans le futur.');
      if (_dateNaissance != null && jour.isBefore(DateTime(_dateNaissance!.year, _dateNaissance!.month, _dateNaissance!.day))) {
        throw const SaisieInvalide('La date de la pesée est antérieure à la naissance de l\'animal.');
      }
      // Poids inhabituel pour l'espèce ou variation énorme (1 kg → 100 kg) :
      // à confirmer, pas bloquant (« Oui, c'est correct »).
      (double, DateTime)? proche;
      for (final r in _poids) {
        if (existant != null && r['id']?.toString() == existant['id']?.toString()) continue;
        final kg = poidsKg(r['valeur']);
        final d = DateTime.tryParse(r['date']?.toString() ?? '');
        if (kg == null || d == null) continue;
        if (proche == null || (d.difference(jour).inDays.abs() < proche.$2.difference(jour).inDays.abs())) proche = (kg, d);
      }
      final alerte = alertePoids(v, espece: _espece, precedent: proche);
      if (alerte != null) {
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('Ce poids est-il correct ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          content: Text(alerte, style: const TextStyle(fontFamily: 'Galey')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Corriger', style: TextStyle(fontFamily: 'Galey'))),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: const Text('Oui, c\'est correct', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
          ],
        ));
        if (ok != true) throw const SaisieAnnulee();
      }
      final ligne = {
        'valeur': v,
        'date': jour.toIso8601String().substring(0, 10),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      };
      if (existant != null) {
        await _supa.from('poids').update(ligne).eq('id', existant['id']);
      } else {
        await _supa.from('poids').insert({
          'id': '${DateTime.now().millisecondsSinceEpoch}',
          'animal_id': _animalId!,
          ...ligne,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      await _loadHealthRecords();
      // La fiche reprend le dernier point de la courbe (trigger en base).
      try {
        final r = await _supa.from('animaux').select('poids').eq('id', _animalId!).maybeSingle();
        if (mounted) setState(() { _poidsCtrl.text = r?['poids']?.toString() ?? ''; _poidsInitial = poidsKg(r?['poids']); });
      } catch (_) {}
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
                        // Lien (ex. résultat de test génétique en ligne) : cliquable.
                        child: e.$2.startsWith('http') || e.$1 == 'Document joint' || e.$1 == 'Résultat en ligne'
                            ? GestureDetector(
                                onTap: () => e.$1 == 'Document joint'
                                    ? DocumentViewerPage.open(context, record['url']?.toString() ?? '', title: sectionTitle)
                                    : launchUrl(Uri.parse(lienWeb(e.$2)), mode: LaunchMode.externalApplication),
                                child: Text(e.$1 == 'Document joint' ? nomFichier(e.$2) : e.$2,
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600,
                                        color: Color(0xFF0C5C6C), decoration: TextDecoration.underline)),
                              )
                            : Text(e.$2,
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
                                // Alerte non confirmée : la fenêtre reste ouverte, sans message.
                                if (e is SaisieAnnulee) return;
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                      content: Text(e is SaisieInvalide ? e.message : 'Erreur: $e'),
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
      // 8 h, heure de Paris (heure d'été / d'hiver gérée par toUtc) — avant :
      // minuit UTC, affiché 1 h ou 2 h du matin.
      final at8 = DateTime(dateRappel.year, dateRappel.month, dateRappel.day, 8).toUtc();
      // Profil de l'animal (multi-profil), à défaut le profil actif.
      String? pid;
      try {
        final a = await _supa.from('animaux').select('profile_id').eq('id', _animalId!).maybeSingle();
        pid = (a?['profile_id'] as String?)?.isNotEmpty == true ? a!['profile_id'] as String : null;
      } catch (_) {}
      pid ??= User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;
      await _supa.from('agenda_events').insert({
        'uid':        uid,
        'titre':      titre,
        'type':       'medication',
        'date_debut': at8.toIso8601String(),
        'animal_id':  _animalId,
        if (pid != null) 'pro_profile_id': pid,
        if (pid != null) 'profile_id': pid,
      });
    } catch (_) {}
  }

  // ── Alimentation ──────────────────────────────────────────────────────────────

  Widget _buildAlimentationTab() {
    return AlimentationPlanTab(
      key: ValueKey('alimentation-$_animalId'),
      animalId: _animalId,
      espece: _espece,
      race: _raceCtrl.text,
      sexe: _sexe,
      sterilise: _sterilise,
      dateNaissance: _dateNaissance,
      nom: _nomCtrl.text,
      poidsFiche: double.tryParse(_poidsCtrl.text.trim().replaceAll(',', '.')),
    );
  }
}

// ── Carte d'import IA (photo/PDF) ─────────────────────────────────────────────

class _AiScanCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool busy;
  const _AiScanCard({required this.onTap, required this.busy});

  @override
  Widget build(BuildContext context) {
    // Fonction pas encore finalisée : grisée et inactive, « Bientôt
    // disponible » (prévue en V2). Remettre `teal` / `onTap` pour l'activer.
    const teal = Colors.grey;
    return InkWell(
      onTap: null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [teal.withValues(alpha: 0.08), teal.withValues(alpha: 0.03)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: teal.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: teal, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.document_scanner_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Flexible(
                  child: Text('Remplir depuis une photo',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: teal)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Bientôt disponible',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black54)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                'Ordonnance, compte-rendu, carnet vaccinal… remplis automatiquement (prévu en V2).',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700),
              ),
            ]),
          ),
          Icon(Icons.lock_outline, color: teal.withValues(alpha: 0.6), size: 18),
        ]),
      ),
    );
  }
}

// ── Health section widget ─────────────────────────────────────────────────────

/// Panneau blanc unique du carnet : lignes séparées par des traits gris fins.
class _PanneauSante extends StatelessWidget {
  final List<Widget> children;
  const _PanneauSante({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
          children[i],
        ],
      ]),
    );
  }
}

class _HealthSection extends StatefulWidget {
  final String title;
  final IconData? icon;
  final Color color;
  final List<Map<String, dynamic>> records;
  final VoidCallback onAdd;
  final Widget Function(Map<String, dynamic>)? renderRecord;
  final Widget? body;
  final String vide;

  const _HealthSection({
    required this.title,
    this.icon,
    required this.color,
    required this.records,
    required this.onAdd,
    this.renderRecord,
    this.body,
    this.vide = 'Aucun enregistrement',
  });

  @override
  State<_HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<_HealthSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.records.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Container(width: 12, height: 12,
                      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.title,
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 15, color: Color(0xFF1F2A2E))),
                      const SizedBox(height: 2),
                      Text('$n enregistrement${n > 1 ? 's' : ''}',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
                    ]),
                  ),
                  // Ajouter : ouvre le formulaire sans déplier la ligne
                  TextButton(
                    onPressed: widget.onAdd,
                    style: TextButton.styleFrom(
                      foregroundColor: widget.color,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('+ Ajouter',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                  SizedBox(
                    width: 40, height: 44,
                    child: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: Colors.grey.shade500, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
          if (widget.body != null)
            widget.body!
          else if (widget.records.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(42, 12, 16, 14),
              child: Text(widget.vide,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
            )
          else
            ...widget.records.map(widget.renderRecord!),
        ],
      ],
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
  final VoidCallback? onRappel;
  /// Traitement : ajouter l'étape suivante (posologie progressive).
  final VoidCallback? onEtape;
  /// Modifier l'entrée (même formulaire qu'à la création) ; absent pour un
  /// acte saisi par un vétérinaire (certifié).
  final VoidCallback? onEdit;

  const _RecordTile({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onDelete,
    this.onTap,
    this.onRappel,
    this.onEtape,
    this.onEdit,
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
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: Colors.grey.shade600, size: 18),
              tooltip: 'Modifier',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onEdit,
            ),
          if (onEtape != null)
            IconButton(
              icon: const Icon(Icons.playlist_add_outlined, color: Color(0xFF6E9E57), size: 20),
              tooltip: 'Étape suivante (posologie progressive)',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onEtape,
            ),
          if (onRappel != null)
            IconButton(
              icon: const Icon(Icons.add_alarm_outlined, color: Color(0xFF6E9E57), size: 18),
              tooltip: 'Renouvellement',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onRappel,
            ),
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
  final int maxLines;
  const _SFld({required this.ctrl, required this.label, required this.hint, this.numeric = false, this.maxLines = 1});

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
          maxLines: maxLines,
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

class _SDrop extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  /// Libellés propres à cette liste (ex. code d'un test → son nom).
  final Map<String, String>? libelles;
  const _SDrop({required this.label, required this.value, required this.options, required this.onChanged, this.libelles});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(libelles?[o] ?? kLibellesSante[o] ?? o, overflow: TextOverflow.ellipsis, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))).toList(),
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
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

class _SFreq extends StatelessWidget {
  final TextEditingController valeurCtrl;
  final String unite;
  final VoidCallback onValeurChanged;
  final ValueChanged<String> onUniteChanged;
  const _SFreq({required this.valeurCtrl, required this.unite, required this.onValeurChanged, required this.onUniteChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fréquence',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(flex: 2, child: TextField(
            controller: valeurCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => onValeurChanged(),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              filled: true, fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: DropdownButtonFormField<String>(
            initialValue: unite,
            items: const [
              DropdownMenuItem(value: 'jour', child: Text('Jour(s)', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
              DropdownMenuItem(value: 'semaine', child: Text('Semaine(s)', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
              DropdownMenuItem(value: 'mois', child: Text('Mois', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
            ],
            onChanged: (v) { if (v != null) onUniteChanged(v); },
            decoration: InputDecoration(
              filled: true, fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          )),
        ]),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _SDate extends StatelessWidget {
  final String label;
  final DateTime? date;
  /// null : date calculée, affichée sans pouvoir être modifiée.
  final ValueChanged<DateTime>? onPicked;
  /// Bornes du calendrier (ex. pesée : naissance → aujourd'hui).
  final DateTime? firstDate, lastDate;
  const _SDate({required this.label, required this.date, required this.onPicked, this.firstDate, this.lastDate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onPicked == null ? null : () async {
            final debut = firstDate ?? DateTime(2000);
            final fin = lastDate ?? DateTime(2100);
            var initiale = date ?? DateTime.now();
            if (initiale.isBefore(debut)) initiale = debut;
            if (initiale.isAfter(fin)) initiale = fin;
            final d = await showDatePicker(
              context: context,
              initialDate: initiale,
              firstDate: debut,
              lastDate: fin,
            );
            if (d != null) onPicked?.call(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: onPicked == null ? const Color(0xFFEDEDED) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(onPicked == null ? Icons.lock_outline : Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  date != null ? DateFormat('dd/MM/yyyy').format(date!)
                      : onPicked == null ? 'Selon la date et la fréquence' : 'Sélectionner une date',
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


// ── Recherche d'un contact PetsMatch (Contacts urgence) ────────────────────────
// Alternative à la saisie manuelle : cherche un utilisateur PetsMatch par
// nom/prénom ou email (même logique que reservation_sheet.dart / cession_sheet.dart
// côté éleveur) et retourne {nom, tel} à ajouter comme contact.
class _ContactPetsMatchSearchSheet extends StatefulWidget {
  const _ContactPetsMatchSearchSheet();
  @override
  State<_ContactPetsMatchSearchSheet> createState() => _ContactPetsMatchSearchSheetState();
}

class _ContactPetsMatchSearchSheetState extends State<_ContactPetsMatchSearchSheet> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _searchDone = false;
  List<Map<String, dynamic>> _results = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Suggestions dès la saisie (2 caractères), sans attendre le bouton
  // « Chercher » ou la validation.
  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { _results = []; _searchDone = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _searchDone = false; _results = []; });
    try {
      final isEmail = q.contains('@');
      List<Map<String, dynamic>> rows;
      if (isEmail) {
        final userRow = await trouverUtilisateurParEmail(q.toLowerCase());
        if (userRow == null) {
          rows = [];
        } else {
          final cp = await _supa.from('user_profiles_complet')
              .select('uid, firstname, lastname, phone_number')
              .eq('uid', userRow['uid'] as String).eq('is_main', true).maybeSingle();
          rows = cp != null ? [Map<String, dynamic>.from(cp)] : [];
        }
      } else {
        final cps = await _supa
            .from('user_profiles_complet')
            .select('uid, firstname, lastname, phone_number')
            .or('firstname.ilike.%$q%,lastname.ilike.%$q%')
            .eq('is_main', true)
            .limit(8);
        rows = (cps as List).map((cp) => Map<String, dynamic>.from(cp)).toList();
      }
      final mapped = rows.map((r) {
        final nom = '${r['firstname'] ?? ''} ${r['lastname'] ?? ''}'.trim();
        return {...r, 'nom': nom.isEmpty ? 'Utilisateur PetsMatch' : nom};
      }).toList();
      if (mounted) setState(() => _results = mapped);
    } finally {
      if (mounted) setState(() { _searching = false; _searchDone = true; });
    }
  }

  void _select(Map<String, dynamic> r) {
    Navigator.pop(context, {'nom': r['nom'], 'tel': (r['phone_number'] as String?) ?? ''});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Rechercher un contact PetsMatch',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 4),
        Text('Nom, prénom ou email d\'un utilisateur PetsMatch.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Nom, prénom ou email…',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          )),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _searching ? null : _search,
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _searching
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Chercher'),
          ),
        ]),
        const SizedBox(height: 12),
        if (_results.isNotEmpty)
          ..._results.map((r) => GestureDetector(
            onTap: () => _select(r),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.person_outline, color: _teal, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['nom'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Galey')),
                  if ((r['phone_number'] as String?)?.isNotEmpty == true)
                    Text(r['phone_number'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ])),
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ]),
            ),
          )),
        if (_searchDone && _results.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: const Text('Aucun utilisateur trouvé.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ),
      ]),
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
  final List<TextInputFormatter>? inputFormatters;
  const _FField({required this.controller, required this.hint, this.keyboardType, this.inputFormatters});
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
          inputFormatters: inputFormatters,
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
  /// Date la plus ancienne proposée (âge maximum de l'espèce).
  final DateTime? premiere;
  const _DateField({required this.date, required this.onPicked, this.premiere});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: borner(date ?? DateTime.now().subtract(const Duration(days: 365)), premiere ?? DateTime(1900), DateTime.now()),
            firstDate: premiere ?? DateTime(1900),
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

// ── Poids section avec courbe ─────────────────────────────────────────────────

String _fmtPoidsP(double v) {
  if (v < 1) return v.toStringAsFixed(3);
  if (v < 10) return v.toStringAsFixed(1);
  return v.toStringAsFixed(0);
}

// Libellé lisible d'un poids : sous 1 kg en grammes (bébés / petites espèces),
// au-dessus en kg. Le stockage reste toujours en kg.
String _poidsLabelP(double kg) {
  if (kg < 1) return '${(kg * 1000).round()} g';
  if (kg < 10) {
    final s = kg.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return '${s.replaceAll('.', ',')} kg';
  }
  return '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg';
}

class _PoidsSectionP extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final DateTime? dateNaissance;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onDelete;
  final void Function(Map<String, dynamic>) onEdit;
  final String Function(dynamic) fmtDate;

  const _PoidsSectionP({
    required this.records, required this.dateNaissance,
    required this.onAdd, required this.onDelete, required this.onEdit, required this.fmtDate,
  });

  bool get _isJuvenile {
    if (dateNaissance == null) return false;
    return DateTime.now().difference(dateNaissance!).inDays < 548;
  }

  @override
  Widget build(BuildContext context) {
    const teal = SanteCouleurs.poids;
    final sorted = [...records]..sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return da.compareTo(db);
    });
    final vals = sorted.map((d) => double.tryParse(d['valeur']?.toString() ?? '') ?? 0.0).toList();
    final maxVal = vals.isEmpty ? 1.0 : vals.reduce((a, b) => a > b ? a : b);

    return _HealthSection(
      title: 'Courbe de poids',
      color: teal,
      records: records,
      onAdd: onAdd,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF0C5C6C)),
                tooltip: 'Modifier',
                onPressed: () => onEdit(d),
                padding: const EdgeInsets.only(left: 8),
                constraints: const BoxConstraints(),
              ),
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
      final line1 = _poidsLabelP(vals[i]);
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

// ═══════════════════════════════════════════════════════════════════════════════
// Onglets Documents / Éducation / Pension & Garde (fiche animal — particulier)
// ═══════════════════════════════════════════════════════════════════════════════

const _kTealDoc = Color(0xFF0C5C6C);
const _kPurpleEdu = Color(0xFF7B5EA7);
const _kGreenPension = Color(0xFF6E9E57);

class _TabEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TabEmptyState({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500)),
          ]),
        ),
      );
}

// Catégories de documents attachables par le propriétaire.
const List<(String, String, IconData)> _kDocCategories = [
  ('contrat', 'Contrat d\'achat / adoption', Icons.description_outlined),
  ('pedigree', 'Pédigrée numérique', Icons.workspace_premium_outlined),
  ('identification', 'Carte d\'identification (I-CAD)', Icons.badge_outlined),
  ('passeport', 'Passeport européen', Icons.menu_book_outlined),
  ('assurance', 'Attestation d\'assurance', Icons.shield_outlined),
  ('vaccination', 'Carnet de vaccination', Icons.vaccines_outlined),
  ('facture', 'Facture vétérinaire', Icons.receipt_long_outlined),
  ('autre', 'Autre document administratif', Icons.attach_file),
];

String _docCatLabel(String? v) =>
    _kDocCategories.firstWhere((c) => c.$1 == v, orElse: () => _kDocCategories.last).$2;
IconData _docCatIcon(String? v) =>
    _kDocCategories.firstWhere((c) => c.$1 == v, orElse: () => _kDocCategories.last).$3;

/// Rappel d'agenda 30 jours avant l'expiration d'un document (le jour même si
/// c'est plus proche). Rangé sur le PROFIL DE L'ANIMAL et son propriétaire
/// (multi-profil : pas le profil actif), comme le site. Les notifications et
/// le retrait automatique du document à l'expiration : Cloud Function
/// sendDocumentExpiryReminders.
Future<void> _scheduleDocExpiryReminderP(String animalId, String label, DateTime expiry) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  var d = expiry.subtract(const Duration(days: 30));
  if (d.isBefore(DateTime.now())) d = expiry;
  try {
    final supa = Supabase.instance.client;
    final a = await supa.from('animaux').select('profile_id, uid_proprietaire').eq('id', animalId).maybeSingle();
    final pid = (a?['profile_id'] as String?)?.isNotEmpty == true
        ? a!['profile_id'] as String
        : (User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null);
    final at8 = DateTime(d.year, d.month, d.day, 8).toUtc();
    await supa.from('agenda_events').insert({
      'uid': (a?['uid_proprietaire'] as String?) ?? uid,
      'titre': 'Document à renouveler : $label',
      'type': 'autre',
      'date_debut': at8.toIso8601String(),
      'animal_id': animalId,
      if (pid != null) 'profile_id': pid,
      if (pid != null) 'pro_profile_id': pid,
    });
  } catch (_) {}
}

/// Document retiré de la fiche : son rappel d'agenda aussi.
Future<void> _supprimerRappelDocP(String animalId, String label) async {
  try {
    await Supabase.instance.client.from('agenda_events').delete()
        .eq('animal_id', animalId).eq('titre', 'Document à renouveler : $label');
  } catch (_) {}
}

class _DocumentsTabP extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final List<Map<String, dynamic>> documents;
  final Future<void> Function(List<Map<String, dynamic>>) onChanged;
  const _DocumentsTabP({
    required this.animalId,
    required this.animalNom,
    required this.documents,
    required this.onChanged,
  });
  @override
  State<_DocumentsTabP> createState() => _DocumentsTabPState();
}

class _DocumentsTabPState extends State<_DocumentsTabP> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _officiels = [];
  List<Map<String, dynamic>> _certs = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadOfficiels();
  }

  Future<void> _loadOfficiels() async {
    try {
      final results = await Future.wait([
        _supa.from('documents_animaux').select('*')
            .eq('animal_id', widget.animalId).order('created_at', ascending: false),
        _supa.from('certificats_engagement')
            .select('id, statut, date_remise, token_signature, date_signature_acquereur')
            .eq('animal_id', widget.animalId).order('date_remise', ascending: false),
      ]);

      if (mounted) setState(() {
        _officiels = List<Map<String, dynamic>>.from(results[0]);
        _certs = List<Map<String, dynamic>>.from(results[1]);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndAdd() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: _kTealDoc),
            title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: _kTealDoc),
            title: const Text('Photo depuis la galerie', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: _kTealDoc),
            title: const Text('Fichier / PDF', style: TextStyle(fontFamily: 'Galey')),
            subtitle: const Text(kFormatsDocuments, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    File file;
    if (source == 'file') {
      final res = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: kExtensionsDocuments);
      final path = res?.files.single.path;
      if (path == null) return;
      file = File(path);
    } else {
      final picked = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 2400,
      );
      if (picked == null) return;
      file = File(picked.path);
    }

    if (!mounted) return;
    String categorie = 'contrat';
    final nomCtrl = TextEditingController(
        text: source == 'file' ? file.path.split(Platform.pathSeparator).last : '');
    DateTime? expiration;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const Text('Nouveau document', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            TextField(
              controller: nomCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Nom du document',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: categorie,
              isExpanded: true,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
              decoration: InputDecoration(
                labelText: 'Catégorie',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              items: _kDocCategories
                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setSheet(() => categorie = v ?? 'contrat'),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: expiration ?? DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime(2100),
                );
                if (d != null) setSheet(() => expiration = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date d\'expiration (optionnel)',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  suffixIcon: expiration != null
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setSheet(() => expiration = null))
                      : const Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(
                  expiration != null ? DateFormat('dd/MM/yyyy').format(expiration!) : 'Aucune',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                      color: expiration != null ? const Color(0xFF1F2A2E) : Colors.grey),
                ),
              ),
            ),
            if (expiration != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Le document sera retiré automatiquement de la fiche à cette date. '
                    'Vous serez prévenu(e) 30 jours, 7 jours et la veille (rappel aussi dans l\'agenda).',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTealDoc, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        );
      }),
    );
    if (ok != true || !mounted) return;

    setState(() => _uploading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final ext = file.path.split('.').last;
      final storagePath =
          'documents/$uid/${widget.animalId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final url = await uploadDocument(file, storagePath);
      final entry = <String, dynamic>{
        'nom': nomCtrl.text.trim().isEmpty ? _docCatLabel(categorie) : nomCtrl.text.trim(),
        'url': url,
        'categorie': categorie,
        'type': ext.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/$ext',
        'ajoute_le': DateTime.now().toIso8601String().substring(0, 10),
        if (expiration != null) 'date_expiration': expiration!.toIso8601String().substring(0, 10),
      };
      final next = [...widget.documents, entry];
      await widget.onChanged(next);
      if (expiration != null) {
        await _scheduleDocExpiryReminderP(widget.animalId, entry['nom'] as String, expiration!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document ajouté ✓'), backgroundColor: _kGreenPension));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteLibre(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce document ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final doc = widget.documents[index];
    final next = [...widget.documents]..removeAt(index);
    await widget.onChanged(next);
    if (doc['date_expiration'] != null) {
      await _supprimerRappelDocP(widget.animalId, (doc['nom'] ?? '').toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final libres = widget.documents;
    return RefreshIndicator(
      onRefresh: _loadOfficiels,
      color: _kTealDoc,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Bouton d'ajout
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _uploading ? null : _pickAndAdd,
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(_uploading ? 'Envoi…' : 'Ajouter un document',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kTealDoc, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 18),

          if (libres.isNotEmpty) ...[
            _sectionTitle('Mes documents'),
            ...libres.asMap().entries.map((e) => _libreCard(e.key, e.value)),
            const SizedBox(height: 16),
          ],

          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: _kTealDoc)))
          else ...[
            if (_officiels.isNotEmpty) ...[
              _sectionTitle('Contrats & documents officiels'),
              ..._officiels.map(_officielCard),
              const SizedBox(height: 16),
            ],
            if (_certs.isNotEmpty) ...[
              _sectionTitle('Certificats d\'engagement'),
              ..._certs.map(_certCard),
              const SizedBox(height: 16),
            ],
            // Comptes rendus & ordonnances : onglet « Consultations ».
          ],

          if (libres.isEmpty && _officiels.isEmpty && _certs.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: _TabEmptyState(
                  icon: Icons.folder_open_outlined,
                  text: 'Aucun document.\nAttachez le contrat d\'achat, le pédigrée, le passeport…'),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 11, letterSpacing: 0.5, color: Colors.grey.shade500)),
      );

  Widget _libreCard(int index, Map<String, dynamic> doc) {
    final exp = doc['date_expiration'] != null ? DateTime.tryParse(doc['date_expiration'].toString()) : null;
    final expired = exp != null && exp.isBefore(DateTime.now());
    final soon = exp != null && !expired && exp.difference(DateTime.now()).inDays <= 30;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: (doc['type']?.toString().startsWith('image/') ?? false) && (doc['url']?.toString().isNotEmpty ?? false)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ImagePrivee(
                  doc['url'].toString(),
                  width: 40, height: 40, fit: BoxFit.cover,
                  enErreur: (_) => Icon(_docCatIcon(doc['categorie']?.toString()), color: _kTealDoc, size: 20),
                ),
              )
            : CircleAvatar(
                backgroundColor: _kTealDoc.withValues(alpha: 0.1),
                child: Icon(_docCatIcon(doc['categorie']?.toString()), color: _kTealDoc, size: 20),
              ),
        title: Text(doc['nom']?.toString() ?? 'Document',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_docCatLabel(doc['categorie']?.toString()),
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          if (exp != null)
            Text(
              expired
                  ? 'Expiré le ${DateFormat('dd/MM/yyyy').format(exp)}'
                  : 'Expire le ${DateFormat('dd/MM/yyyy').format(exp)}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: expired ? Colors.red.shade600 : soon ? Colors.orange.shade700 : Colors.grey.shade500),
            ),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined, size: 18, color: _kTealDoc),
            onPressed: () => DocumentViewerPage.open(context, doc['url']?.toString() ?? '',
                title: doc['nom']?.toString() ?? 'Document'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _deleteLibre(index),
          ),
        ]),
      ),
    );
  }

  Widget _officielCard(Map<String, dynamic> doc) {
    final type = doc['type']?.toString() ?? '';
    final statut = doc['statut']?.toString() ?? 'brouillon';
    final token = doc['token']?.toString();
    final url = doc['url']?.toString() ?? doc['pdf_signe_url']?.toString();
    final date = doc['created_at'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(doc['created_at'].toString()).toLocal())
        : '';
    const labels = {
      'contrat_vente': 'Contrat de vente', 'contrat_reservation': 'Contrat de réservation',
      'contrat_saillie': 'Contrat de saillie', 'contrat_adoption': 'Contrat d\'adoption',
      'contrat_education': 'Contrat (éducateur)', 'certificat_cession': 'Certificat de cession',
      'contrat_garde': 'Contrat de prestation', 'contrat_pension': 'Contrat de pension',
      'contrat_photographe': 'Contrat (photographe)',
      'contrat_sante': 'Contrat de soins',
      'devis': 'Devis', 'facture': 'Facture',
    };
    final titreDoc = (doc['titre'] as String?)?.trim();
    final titre = labels[type] ?? (titreDoc?.isNotEmpty == true ? titreDoc! : 'Document');
    final isFinal = ['signe', 'refuse', 'annule', 'expire'].contains(statut);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: _kTealDoc.withValues(alpha: 0.1),
          child: const Icon(Icons.description_outlined, color: _kTealDoc, size: 20),
        ),
        title: Text(titre,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Row(children: [
          Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(width: 8),
          _statutBadge(statut),
        ]),
        trailing: (token != null || url != null)
            ? IconButton(
                icon: Icon(
                    url != null
                        ? Icons.open_in_new
                        : isFinal ? Icons.visibility_outlined : Icons.draw_outlined,
                    size: 18, color: _kTealDoc),
                tooltip: url != null
                    ? 'Lire le document'
                    : isFinal ? 'Consulter' : 'Lire et signer',
                onPressed: () {
                  if (url != null) {
                    DocumentViewerPage.open(context, url, title: titre);
                  } else {
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ContratSignaturePage(token: token)));
                  }
                },
              )
            : null,
      ),
    );
  }

  Widget _certCard(Map<String, dynamic> cert) {
    final statut = cert['statut']?.toString() ?? 'en_attente';
    final signe = statut == 'signe';
    final date = cert['date_remise'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(cert['date_remise'].toString()))
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: _kGreenPension.withValues(alpha: 0.12),
          child: const Text('✅', style: TextStyle(fontSize: 16)),
        ),
        title: const Text('Certificat d\'engagement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Row(children: [
          Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(width: 8),
          _statutBadge(signe ? 'signe' : 'en_attente'),
        ]),
      ),
    );
  }

  Widget _statutBadge(String statut) {
    final cfg = {
      'signe': (const Color(0xFF2E7D32), 'Signé', const Color(0xFFE8F5E9)),
      'en_attente': (const Color(0xFF1565C0), 'En attente', const Color(0xFFE3F2FD)),
      'archive': (Colors.grey.shade600, 'Archivé', Colors.grey.shade200),
      'refuse': (const Color(0xFFC62828), 'Refusé', const Color(0xFFFFEBEE)),
    }[statut] ?? (const Color(0xFF8D6E00), 'Brouillon', const Color(0xFFFFF8E1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: cfg.$3, borderRadius: BorderRadius.circular(6)),
      child: Text(cfg.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: cfg.$1)),
    );
  }
}

// ─── Onglet Éducation ────────────────────────────────────────────────────────

class _EducationTabP extends StatefulWidget {
  final String? animalId;
  final String animalNom;
  const _EducationTabP({required this.animalId, required this.animalNom});
  @override
  State<_EducationTabP> createState() => _EducationTabPState();
}

class _EducationTabPState extends State<_EducationTabP> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _rapports = [];
  List<Map<String, dynamic>> _devis = [];
  List<Map<String, dynamic>> _objectifs = [];
  List<Map<String, dynamic>> _exercices = [];
  List<Map<String, dynamic>> _forfaits = [];
  List<Map<String, dynamic>> _attestations = [];
  final Map<String, List<Map<String, dynamic>>> _retours = {}; // attribution_id -> retours
  bool _loading = true;

  static const _kEduCategories = <String, String>{
    'rappel': 'Rappel', 'laisse': 'Marche en laisse', 'proprete': 'Propreté',
    'aboiements': 'Aboiements', 'destruction': 'Destruction',
    'socialisation_chien': 'Socialisation chiens', 'socialisation_humain': 'Socialisation humains',
    'manipulation': 'Manipulation / soins', 'solitude': 'Solitude',
    'agressivite': 'Agressivité', 'peurs': 'Peurs', 'autre': 'Autre',
  };
  static const _kEduStatutLabels = {
    'a_travailler': 'À travailler', 'en_cours': 'En cours', 'en_progression': 'En progression',
    'acquis': 'Acquis selon évaluation', 'a_reevaluer': 'À réévaluer',
  };
  Color _eduStatutColor(String s) => switch (s) {
        'acquis' => const Color(0xFF6E9E57),
        'en_progression' => const Color(0xFF2E7D8C),
        'a_reevaluer' => const Color(0xFF7B5EA7),
        'en_cours' => const Color(0xFFEFA100),
        _ => const Color(0xFFD5573B),
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.animalId == null) { setState(() => _loading = false); return; }
    try {
      final r = await _supa.from('education_progression').select()
          .eq('animal_id', widget.animalId!).order('date_seance', ascending: false);
      final d = await _supa.from('devis').select()
          .eq('animal_id', widget.animalId!).order('created_at', ascending: false);
      List objectifs = const [];
      List exercices = const [];
      try {
        objectifs = await _supa.from('education_objectifs').select()
            .eq('animal_id', widget.animalId!).order('ordre', ascending: true).order('created_at', ascending: true);
      } catch (_) {}
      try {
        exercices = await _supa.from('exercices_attribues').select()
            .eq('animal_id', widget.animalId!).order('assigned_at', ascending: false);
      } catch (_) {}
      List forfaits = const [];
      try {
        forfaits = await _supa.from('forfaits_souscrits').select()
            .eq('animal_id', widget.animalId!).order('souscrit_le', ascending: false);
      } catch (_) {}
      _forfaits = List<Map<String, dynamic>>.from(forfaits);
      List attestations = const [];
      try {
        attestations = await _supa.from('education_attestations').select()
            .eq('animal_id', widget.animalId!).order('emise_le', ascending: false);
      } catch (_) {}
      _attestations = List<Map<String, dynamic>>.from(attestations);
      _retours.clear();
      final exoIds = exercices.map((e) => e['id']?.toString()).whereType<String>().toList();
      if (exoIds.isNotEmpty) {
        try {
          final rr = await _supa.from('exercices_retours').select()
              .inFilter('attribution_id', exoIds).order('created_at');
          for (final row in (rr as List)) {
            final aid = row['attribution_id']?.toString() ?? '';
            (_retours[aid] ??= []).add(Map<String, dynamic>.from(row));
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _rapports = List<Map<String, dynamic>>.from((r as List).where((x) => x['statut'] != 'brouillon'));
          _devis = List<Map<String, dynamic>>.from(d as List);
          _objectifs = List<Map<String, dynamic>>.from(objectifs);
          _exercices = List<Map<String, dynamic>>.from(exercices);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _exerciceLignes(String? raw) => (raw ?? '')
      .split(RegExp(r'[\n;]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _toggleExercice(Map<String, dynamic> rapport, int index, int total) async {
    final current = (rapport['exercices_coches'] as List?)?.map((e) => e as bool).toList() ??
        List<bool>.filled(total, false);
    while (current.length < total) current.add(false);
    current[index] = !current[index];
    setState(() => rapport['exercices_coches'] = current);
    try {
      await _supa.from('education_progression')
          .update({'exercices_coches': current}).eq('id', rapport['id']);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kPurpleEdu));
    if (_rapports.isEmpty && _devis.isEmpty && _objectifs.isEmpty && _exercices.isEmpty) {
      return const _TabEmptyState(
          icon: Icons.school_outlined,
          text: 'Aucun suivi éducatif pour l\'instant.\nLe plan de travail et les comptes rendus de votre éducateur apparaîtront ici.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        ..._attestations.map(_attestationBanner),
        ..._forfaits.where((f) => f['statut'] != 'annule').map(_forfaitBanner),
        if (_objectifs.isNotEmpty || _rapports.isNotEmpty) ...[
          _progressionSection(),
          const SizedBox(height: 18),
        ],
        if (_objectifs.isNotEmpty) ...[
          _title('Plan de travail'),
          ..._objectifs.map(_objectifCard),
          const SizedBox(height: 18),
        ],
        if (_exercices.isNotEmpty) ...[
          _title('Exercices à faire'),
          ..._exercices.map(_exerciceCard),
          const SizedBox(height: 18),
        ],
        if (_devis.isNotEmpty) ...[
          _title('Devis reçus'),
          ..._devis.map(_devisCard),
          const SizedBox(height: 18),
        ],
        if (_rapports.isNotEmpty) ...[
          _title('Comptes rendus de séance'),
          ..._rapports.map(_rapportCard),
        ],
      ],
    );
  }

  Widget _progressionSection() {
    // Frise : bilan + séances (par date_seance) + objectifs atteints (acquis_le).
    final events = <({DateTime date, String label, IconData icon, Color color})>[];
    for (final r in _rapports) {
      final d = DateTime.tryParse(r['date_seance']?.toString() ?? '');
      if (d == null) continue;
      final bilan = r['type'] == 'bilan';
      events.add((
        date: d,
        label: bilan ? 'Bilan comportemental' : 'Séance',
        icon: bilan ? Icons.assignment_outlined : Icons.school_outlined,
        color: bilan ? const Color(0xFFEF6C00) : _kPurpleEdu,
      ));
    }
    for (final o in _objectifs) {
      final d = DateTime.tryParse(o['acquis_le']?.toString() ?? '');
      if (o['statut'] == 'acquis' && d != null) {
        events.add((
          date: d,
          label: 'Objectif atteint : ${o['libelle']}',
          icon: Icons.flag_outlined,
          color: const Color(0xFF6E9E57),
        ));
      }
    }
    events.sort((a, b) => b.date.compareTo(a.date));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECECEC)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PROGRESSION',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11,
                letterSpacing: 0.5, color: Colors.grey)),
        if (_objectifs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: _objectifs.map((o) {
            final st = o['statut']?.toString() ?? 'a_travailler';
            final c = _eduStatutColor(st);
            final emoji = st == 'acquis' ? '✅' : (st == 'en_cours' || st == 'en_progression') ? '🟡' : st == 'a_reevaluer' ? '🔁' : '🔴';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('$emoji ${o['libelle']}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: c, fontWeight: FontWeight.w600)),
            );
          }).toList()),
        ],
        if (events.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (int i = 0; i < events.length; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  Icon(events[i].icon, size: 16, color: events[i].color),
                  if (i < events.length - 1)
                    Expanded(child: Container(width: 1.5, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(vertical: 2))),
                ]),
                const SizedBox(width: 10),
                Expanded(child: Padding(
                  padding: EdgeInsets.only(bottom: i < events.length - 1 ? 12 : 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(events[i].label,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('${events[i].date.day}/${events[i].date.month}/${events[i].date.year}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
                  ]),
                )),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _attestationBanner(Map<String, dynamic> a) {
    final url = a['pdf_url']?.toString() ?? '';
    final d = DateTime.tryParse(a['emise_le']?.toString() ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF5EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6E9E57).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Text('🎓 ', style: TextStyle(fontSize: 16)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Attestation de fin de programme',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
          if (d != null)
            Text('Émise le ${d.day}/${d.month}/${d.year}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        ])),
        TextButton(
          onPressed: url.isEmpty ? null : () => ouvrirDocument(context, url),
          child: const Text('Ouvrir', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Color(0xFF4A7A32))),
        ),
      ]),
    );
  }

  Widget _forfaitBanner(Map<String, dynamic> f) {
    final total = (f['nb_seances_total'] as num?)?.toInt() ?? 1;
    final used = (f['nb_seances_utilisees'] as num?)?.toInt() ?? 0;
    final actif = f['statut'] == 'actif';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF6C00).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🎫 ', style: TextStyle(fontSize: 14)),
          Expanded(child: Text(f['nom_snapshot']?.toString() ?? 'Forfait',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13))),
          Text(actif ? '$used / $total séances' : 'Terminé',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFEF6C00))),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (used / total).clamp(0, 1),
            minHeight: 5,
            backgroundColor: const Color(0xFFEF6C00).withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation(Color(0xFFEF6C00)),
          ),
        ),
      ]),
    );
  }

  Widget _objectifCard(Map<String, dynamic> o) {
    final statut = o['statut']?.toString() ?? 'a_travailler';
    final cat = o['categorie']?.toString();
    final color = _eduStatutColor(statut);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(o['libelle']?.toString() ?? '',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13))),
          Text(_kEduStatutLabels[statut] ?? statut,
              style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ]),
        if (cat != null && _kEduCategories[cat] != null) ...[
          const SizedBox(height: 4),
          Text(_kEduCategories[cat]!,
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        ],
        if ((o['note']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          RichTextView(o['note'].toString(),
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ],
      ]),
    );
  }

  /// Valide l'étape suivante / la réussite du jour, ou annule la dernière.
  Future<void> _validerExercice(Map<String, dynamic> ex, {required bool valider}) async {
    final maj = majValidationExercice(ex, valider: valider);
    final avant = Map<String, dynamic>.from(ex);
    setState(() => ex.addAll(maj));
    try {
      await _supa.from('exercices_attribues').update(maj).eq('id', ex['id']);
    } catch (_) {
      if (mounted) setState(() => ex..clear()..addAll(avant));
    }
  }

  Future<void> _toggleRappelMute(Map<String, dynamic> ex) async {
    final next = ex['rappels_mutes'] != true;
    setState(() => ex['rappels_mutes'] = next);
    try {
      await _supa.from('exercices_attribues').update({'rappels_mutes': next}).eq('id', ex['id']);
    } catch (_) {}
  }

  Widget _exerciceCard(Map<String, dynamic> ex) {
    final media = (ex['media_snapshot'] is List)
        ? (ex['media_snapshot'] as List).whereType<Map>().toList() : const [];
    final done = ex['statut']?.toString() == 'fait';
    final prog = progressionExercice(ex);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done ? const Color(0xFF6E9E57) : Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(ex['titre_snapshot']?.toString() ?? '',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13,
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? Colors.grey.shade500 : const Color(0xFF1F2A2E)))),
          if (ex['rappels_actifs'] == true)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(ex['rappels_mutes'] == true ? Icons.notifications_off : Icons.notifications_active,
                  size: 17, color: ex['rappels_mutes'] == true ? Colors.grey : _kPurpleEdu),
              tooltip: ex['rappels_mutes'] == true ? 'Réactiver les rappels' : 'Mettre les rappels en pause',
              onPressed: () => _toggleRappelMute(ex),
            ),
          if (done)
            TextButton(
              onPressed: () => _validerExercice(ex, valider: false),
              child: const Text('✓ Terminé', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
            )
          else if (prog.etapes.isEmpty && prog.total == 1)
            TextButton(
              onPressed: () => _validerExercice(ex, valider: true),
              child: const Text('Marquer fait', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: _kPurpleEdu, fontWeight: FontWeight.w600)),
            ),
        ]),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if ((ex['cadence']?.toString() ?? '').isNotEmpty)
            _exoPill(ex['cadence'].toString(), Colors.grey.shade500),
          if (prog.total > 1)
            _exoPill(prog.etapes.isNotEmpty ? 'Étape ${prog.faites}/${prog.total}' : '${prog.faites}/${prog.total} réussites', _kPurpleEdu),
          if (libelleDureeExercice(ex) != null)
            _exoPill(libelleDureeExercice(ex)!, prog.echue ? Colors.grey.shade500 : const Color(0xFFD5573B)),
        ]),
        // Étapes : validées une à une, dans l'ordre.
        if (prog.etapes.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (int i = 0; i < prog.etapes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(i < prog.faites ? Icons.check_circle : Icons.radio_button_unchecked, size: 18,
                    color: i < prog.faites ? const Color(0xFF6E9E57) : (i == prog.faites ? _kPurpleEdu : Colors.grey.shade400)),
                const SizedBox(width: 8),
                Expanded(child: Text('${i + 1}. ${prog.etapes[i]}', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                    fontWeight: i == prog.faites ? FontWeight.w700 : FontWeight.w400,
                    color: i < prog.faites ? Colors.grey.shade500 : const Color(0xFF1F2A2E)))),
              ]),
            ),
        ],
        if (!done && (prog.etapes.isNotEmpty || prog.total > 1))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              FilledButton(
                onPressed: prog.peutValider ? () => _validerExercice(ex, valider: true) : null,
                style: FilledButton.styleFrom(backgroundColor: _kPurpleEdu, visualDensity: VisualDensity.compact),
                child: Text(prog.etapes.isNotEmpty ? "Valider l'étape ${prog.faites + 1}"
                    : prog.dejaAujourdhui ? 'Réussite notée aujourd\'hui' : 'Réussi aujourd\'hui',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              if (prog.faites > 0)
                TextButton(
                  onPressed: () => _validerExercice(ex, valider: false),
                  child: Text('Annuler la dernière', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                ),
            ]),
          ),
        if ((ex['description_snapshot']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          RichTextView(ex['description_snapshot'].toString(),
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, height: 1.4, color: Colors.grey.shade700)),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: media.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final m = media[i];
                final url = m['url']?.toString() ?? '';
                final isVideo = m['type'] == 'video';
                return GestureDetector(
                  onTap: () => isVideo
                      ? launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
                      : _openImage(url),
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    clipBehavior: Clip.antiAlias,
                    child: isVideo
                        ? const Icon(Icons.play_circle_outline, color: Colors.grey)
                        : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
        ],
        // ── Fil de retours ──
        ..._retoursOf(ex['id']?.toString() ?? '').map(_retourBubble),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _donnerRetour(ex),
            icon: const Icon(Icons.add_comment_outlined, size: 15),
            label: const Text('Donner un retour', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: _kPurpleEdu, padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
          ),
        ),
      ]),
    );
  }

  List<Map<String, dynamic>> _retoursOf(String attributionId) => _retours[attributionId] ?? const [];

  static const _kRessenti = {
    'facile': ('😊', 'Facile'), 'moyen': ('😐', 'Moyen'),
    'difficile': ('😓', 'Difficile'), 'bloque': ('🚫', 'Bloqué'),
  };

  Widget _retourBubble(Map<String, dynamic> r) {
    final fromPro = r['from_pro'] == true;
    final media = (r['media'] is List) ? (r['media'] as List).whereType<Map>().toList() : const [];
    final ressenti = r['ressenti']?.toString();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: fromPro ? const Color(0xFFF3EEFA) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(fromPro ? '🎓 Éducateur' : '👪 Famille',
              style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                  color: fromPro ? _kPurpleEdu : Colors.grey.shade600)),
          if (ressenti != null && _kRessenti[ressenti] != null) ...[
            const SizedBox(width: 6),
            Text('${_kRessenti[ressenti]!.$1} ${_kRessenti[ressenti]!.$2}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade600)),
          ],
        ]),
        if ((r['note']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(r['note'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal, itemCount: media.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final url = media[i]['url']?.toString() ?? '';
                final isVideo = media[i]['type'] == 'video';
                return GestureDetector(
                  onTap: () => isVideo
                      ? launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
                      : _openImage(url),
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                    clipBehavior: Clip.antiAlias,
                    child: isVideo
                        ? const Icon(Icons.play_circle_outline, size: 18, color: Colors.grey)
                        : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _donnerRetour(Map<String, dynamic> ex) async {
    final noteCtrl = TextEditingController();
    String? ressenti;
    final images = <String>[]; // urls déjà uploadées
    bool busy = false;

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Text('Retour — ${ex['titre_snapshot'] ?? 'exercice'}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: _kRessenti.entries.map((e) {
              final sel = ressenti == e.key;
              return ChoiceChip(
                label: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                selected: sel,
                onSelected: (_) => setSheet(() => ressenti = sel ? null : e.key),
                selectedColor: _kPurpleEdu.withValues(alpha: 0.18),
                showCheckmark: false,
              );
            }).toList()),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Comment ça s\'est passé ? Ce qui bloque…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final u in images)
                Container(width: 56, height: 56, decoration: BoxDecoration(
                    color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(imageUrl: u, fit: BoxFit.cover)),
              GestureDetector(
                onTap: busy ? null : () async {
                  final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
                  if (f == null) return;
                  setSheet(() => busy = true);
                  try {
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'x';
                    final url = await uploadPhoto(File(f.path),
                        'exercices_retours/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg', quality: 78);
                    setSheet(() { images.add(url); busy = false; });
                  } catch (_) { setSheet(() => busy = false); }
                },
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8)),
                  child: busy
                      ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : Icon(Icons.add_a_photo_outlined, size: 18, color: Colors.grey.shade500),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurpleEdu, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Envoyer à l\'éducateur',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );

    if (sent != true || !mounted) return;
    if (noteCtrl.text.trim().isEmpty && ressenti == null && images.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      await _supa.from('exercices_retours').insert({
        'attribution_id': ex['id'],
        'author_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'author_profile_id': User_Info.activeProfileId,
        if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
        'media': images.map((u) => {'type': 'image', 'url': u}).toList(),
        if (ressenti != null) 'ressenti': ressenti,
        'from_pro': false,
      });
      final proUid = ex['pro_uid']?.toString();
      if (proUid != null && proUid.isNotEmpty) {
        try {
          await _supa.from('notifications').insert({
            'uid': proUid,
            'type': 'education_retour_exercice',
            'title': 'Retour famille — ${widget.animalNom}',
            'body': 'La famille a répondu sur « ${ex['titre_snapshot']} ».',
            if (ex['pro_profile_id'] != null) 'profile_id': ex['pro_profile_id'],
            'data': {'animalId': widget.animalId, 'url': '/mes-patients/${widget.animalId}'},
            'read': false,
          });
        } catch (_) {}
      }
      await _load();
    } catch (_) {}
  }

  Widget _exoPill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: InteractiveViewer(
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 11, letterSpacing: 0.5, color: Colors.grey.shade500)),
      );

  Widget _rapportCard(Map<String, dynamic> r) {
    final date = r['date_seance']?.toString() ?? '';
    final dt = DateTime.tryParse(date);
    final exos = _exerciceLignes(r['exercices_conseilles']?.toString());
    final coches = (r['exercices_coches'] as List?)?.map((e) => e == true).toList() ?? const [];
    final isBilan = r['type'] == 'bilan';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isBilan ? const Color(0xFFEF6C00) : const Color(0xFFECECEC)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (isBilan) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFEF6C00), borderRadius: BorderRadius.circular(4)),
              child: const Text('BILAN', style: TextStyle(fontFamily: 'Galey', fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
          ],
          Text(dt != null ? DateFormat('dd/MM/yyyy').format(dt) : date,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _kPurpleEdu)),
        ]),
        if (isBilan && (r['bilan_motif']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Motif : ${r['bilan_motif']}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 6),
        if ((r['contenu']?.toString() ?? '').isNotEmpty)
          RichTextView(r['contenu'].toString(),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: Color(0xFF1F2A2E))),
        if (isBilan && (r['bilan_recommandation']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF3E9), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('📋 Recommandation',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFFEF6C00))),
              const SizedBox(height: 3),
              RichTextView(r['bilan_recommandation'].toString(),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, height: 1.4, color: Color(0xFF1F2A2E))),
              if (r['bilan_nb_seances_estime'] != null)
                Text('Estimation : ${r['bilan_nb_seances_estime']} séances',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
        ],
        if (exos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF3EEFA), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🏋️ Exercices à faire à la maison',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: _kPurpleEdu)),
              const SizedBox(height: 4),
              ...exos.asMap().entries.map((e) {
                final done = e.key < coches.length && coches[e.key];
                return InkWell(
                  onTap: () => _toggleExercice(r, e.key, exos.length),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(done ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18, color: done ? _kGreenPension : Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.value,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                              decoration: done ? TextDecoration.lineThrough : null,
                              color: done ? Colors.grey.shade500 : const Color(0xFF1F2A2E)))),
                    ]),
                  ),
                );
              }),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _devisCard(Map<String, dynamic> d) {
    final statut = d['statut']?.toString() ?? 'envoye';
    final token = d['token_acceptation']?.toString();
    final montant = (d['total_ttc'] as num?)?.toDouble();
    final labels = {'brouillon': 'Brouillon', 'envoye': 'À signer', 'accepte': 'Accepté', 'refuse': 'Refusé', 'expire': 'Expiré'};
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: const CircleAvatar(backgroundColor: Color(0x1A0C5C6C), child: Text('🧾', style: TextStyle(fontSize: 16))),
        title: Text(montant != null ? '${montant.toStringAsFixed(2)} €' : 'Devis',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(labels[statut] ?? statut,
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        trailing: (token != null && statut != 'brouillon')
            ? IconButton(
                icon: const Icon(Icons.open_in_new, size: 18, color: _kTealDoc),
                tooltip: statut == 'envoye' ? 'Voir et répondre' : 'Voir le devis',
                onPressed: () {
                  final uri = Uri.tryParse('$kSiteBaseUrl/devis/$token');
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              )
            : null,
      ),
    );
  }
}

// ─── Onglet Pension & Garde ──────────────────────────────────────────────────

class _PensionTabP extends StatefulWidget {
  final String? animalId;
  final String animalNom;
  const _PensionTabP({required this.animalId, required this.animalNom});
  @override
  State<_PensionTabP> createState() => _PensionTabPState();
}

class _PensionTabPState extends State<_PensionTabP> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _updates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.animalId == null) { setState(() => _loading = false); return; }
    try {
      final rows = await _supa.from('pension_updates').select()
          .eq('animal_id', widget.animalId!).order('created_at', ascending: false);
      if (mounted) setState(() {
        _updates = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kGreenPension));
    if (_updates.isEmpty) {
      return const _TabEmptyState(
          icon: Icons.photo_camera_back_outlined,
          text: 'Aucune nouvelle pour l\'instant.\nLes photos et messages de la pension ou du pet-sitter apparaîtront ici.');
    }
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _kGreenPension,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: _updates.length,
            itemBuilder: (_, i) => _updateCard(_updates[i]),
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PensionJournalPage(
                  animalId: widget.animalId,
                  animalNom: widget.animalNom,
                  readOnly: true,
                ),
              )),
              icon: const Icon(Icons.open_in_full, size: 16),
              label: const Text('Ouvrir le journal complet (vidéos, réactions…)',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kGreenPension,
                side: const BorderSide(color: _kGreenPension),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _updateCard(Map<String, dynamic> u) {
    final dt = DateTime.tryParse(u['created_at']?.toString() ?? '');
    final photo = u['photo_url']?.toString();
    final video = u['video_url']?.toString();
    final note = u['note']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECECEC)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (photo != null)
          ImagePrivee(
            photo, width: double.infinity, height: 200, fit: BoxFit.cover,
            enErreur: (_) => Container(height: 200, color: const Color(0xFFEFEFEF),
                child: const Icon(Icons.broken_image_outlined, color: Colors.grey)),
          )
        else if (video != null)
          Container(
            height: 120, width: double.infinity, color: const Color(0xFF1F2A2E),
            child: const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 40)),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (note != null && note.isNotEmpty)
              Text(note, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.35)),
            if (note != null && note.isNotEmpty) const SizedBox(height: 4),
            Text(dt != null ? DateFormat('dd/MM/yyyy · HH:mm').format(dt.toLocal()) : '',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ),
      ]),
    );
  }
}
