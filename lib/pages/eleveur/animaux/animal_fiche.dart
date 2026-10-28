import 'package:PetsMatch/utils/ages_plausibles.dart';
import 'package:share_plus/share_plus.dart';
import 'package:PetsMatch/utils/cloisonnement_profils.dart';
import 'package:PetsMatch/utils/poids.dart';
import 'package:PetsMatch/utils/recuperation_animal.dart' show verifierPuce, showRecuperationAnimal, inviterAcquereur;
import 'package:PetsMatch/pages/pro/toilettage_constantes.dart' show labelTravailToilettage;
import 'package:PetsMatch/pages/animaux/morpho/morpho_detail_page.dart';
import 'package:PetsMatch/pages/animaux/morpho/morpho_constants.dart';
import 'package:PetsMatch/pages/animaux/morpho/morpho_form_page.dart';
import 'package:PetsMatch/utils/chaleurs_etat.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:PetsMatch/utils/sante_suppression.dart';
import 'package:PetsMatch/utils/controle_dates.dart';
import 'package:PetsMatch/widgets/carnet/prises_traitement.dart';
import 'package:PetsMatch/utils/resume_traitement.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/animaux/cession_sheet.dart';
import 'package:PetsMatch/pages/eleveur/animaux/reservation_sheet.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/pro/pension_journal_page.dart';
import 'package:PetsMatch/pages/pro/animal_devis_page.dart';
import 'package:PetsMatch/pages/pro/education_rapports_page.dart';
import 'package:PetsMatch/services/planning_service.dart';
import 'package:PetsMatch/services/chaleur_interval_service.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/particulier/social_feed_page.dart' show AnimalTaggedPostsPage;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/widgets/carnet/vermifuge_options.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/widgets/vet/consultation_widgets.dart';
import 'package:PetsMatch/pages/pro/historique_patient_page.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';
import 'package:PetsMatch/pages/pro/anatomie_points_page.dart';
import 'package:PetsMatch/pages/animaux/morpho/morpho_timeline_tab.dart';
import 'package:PetsMatch/pages/pro/rdv_booking_page.dart';
import 'package:PetsMatch/pages/particulier/partage_animal_sheet.dart';
import 'package:PetsMatch/widgets/vet_share_dialog.dart';
import 'package:PetsMatch/widgets/alimentation/alimentation_plan_tab.dart';
import 'package:PetsMatch/widgets/rich_text_view.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/animal/pro_animal_entete.dart';
import 'package:PetsMatch/widgets/animal/sante_pro_tabs.dart';
import 'package:PetsMatch/data/vaccin_types.dart';
import 'package:PetsMatch/data/genetic_tests.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:PetsMatch/utils/user_lookup.dart';
import 'package:PetsMatch/pages/eleveur/animaux/edit_cession_sheet.dart';
import 'package:PetsMatch/utils/sante_couleurs.dart';
import 'package:PetsMatch/utils/reproducteurs.dart';

// ─── Contact urgence ─────────────────────────────────────────────────────────


/// Statuts d'un contrat pas encore signé des deux côtés (supprimé quand la
/// cession est révoquée). Même liste côté site : mes-animaux/[id]/page.tsx.
const kStatutsContratNonFinalises = [
  'brouillon', 'en_attente', 'genere', 'partiellement_signe', 'signe_acquereur', 'signe_vendeur',
];

class _ContactUrgence {
  final TextEditingController nom;
  final TextEditingController tel;
  /// Lien avec le propriétaire (personnes autorisées uniquement).
  final TextEditingController lien;
  _ContactUrgence({String nomVal = '', String telVal = '', String lienVal = ''})
      : nom = TextEditingController(text: nomVal),
        tel = TextEditingController(text: telVal),
        lien = TextEditingController(text: lienVal);
  void dispose() { nom.dispose(); tel.dispose(); lien.dispose(); }
}

// ─── Bouton d'action rapide de l'en-tête (Partager / Réserver / Céder…) ───────
// Un vrai bouton libellé (icône + texte, fond blanc translucide sur l'AppBar
// teal), comme sur le site, plutôt qu'une icône seule pas toujours claire.

class _QuickAction {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;
  /// Bouton icône seule (pas de texte) — réservé au partage, dont le
  /// pictogramme est reconnu universellement et n'a pas besoin de libellé.
  final bool iconOnly;
  _QuickAction({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
    this.tooltip,
    this.iconOnly = false,
  });

  Widget build() {
    if (iconOnly) {
      return Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, size: 20, color: color),
          tooltip: tooltip ?? label,
          onPressed: onTap,
        ),
      );
    }
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(label ?? '', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              fontWeight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }
}

// ─── Page principale ──────────────────────────────────────────────────────────

class AnimalFichePage extends StatefulWidget {
  final String? animalId;
  final Map<String, dynamic>? initialData;
  final String? preselectedEspece;
  final bool readOnly;
  final bool vetMode;
  final bool educationMode;
  final bool isAssociation;
  final bool showReproTab;
  final int? initialTabIndex;
  final String? eleveurUidOverride;
  final String? rdvId;
  final Set<String>? employePerms;
  /// Profil (user_profiles.id) propriétaire à utiliser à la création — vue
  /// employé : l'animal appartient à l'élevage de l'employeur, pas au profil
  /// actif de l'employé.
  final String? proprioProfileIdOverride;

  const AnimalFichePage({
    super.key,
    this.animalId,
    this.initialData,
    this.preselectedEspece,
    this.readOnly = false,
    this.vetMode = false,
    this.educationMode = false,
    this.isAssociation = false,
    this.showReproTab = false,
    this.initialTabIndex,
    this.eleveurUidOverride,
    this.rdvId,
    this.employePerms,
    this.proprioProfileIdOverride,
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

  // Pension access
  List<Map<String, dynamic>> _pensionAcces = [];
  bool _hasPensionUpdates = false;
  bool _hasEducationRapports = false;
  bool _hasDevis = false;
  // Registre mouvements (plusieurs E/S par animal)
  List<Map<String, dynamic>> _mouvements = [];
  // Garde/pet-sitting access (visible au propriétaire)
  List<Map<String, dynamic>> _gardeAcces = [];
  // Statut de l'accès animal_access du viewer vetMode courant (pro non-santé
  // uniquement — health pros ont toujours l'écriture) : null/'active' = lecture
  // seule, 'write_requested' = demande envoyée, 'active_write' = autorisé.
  String? _healthAccessStatut;
  String? _healthAccessGrantId;
  bool get _canWriteHealth => _isHealthPro || _healthAccessStatut == 'active_write';
  /// Fiche créée par un autre pro : identité et documents de ce pro seulement,
  /// le carnet reste privé tant que le propriétaire ne l'a pas partagé.
  bool get _carnetPrive => _healthAccessStatut == 'identite';
  // Vet access (visible au propriétaire)
  List<Map<String, dynamic>> _vetAcces = [];
  // Owner uid (utilisé dans le mode vétérinaire)
  String? _ownerUid;
  // Cogérant actif de _ownerUid : a les mêmes droits que le gérant
  // principal (dont céder/décéder), même quand la fiche est ouverte avec
  // eleveurUidOverride (résolution multi-profil, cf. mes_animaux.dart).
  bool _isCogerantActif = false;

  // ── Champs identité
  final _nomCtrl    = TextEditingController();
  final _nomPedigreeCtrl = TextEditingController();
  final _raceCtrl   = TextEditingController();
  final _couleurCtrl = TextEditingController();
  final _couleurYeuxCtrl = TextEditingController();
  final _identCtrl  = TextEditingController();
  // Identification équidé (cheval)
  final _sireCtrl        = TextEditingController();
  final _carteImmatCtrl  = TextEditingController();
  final _livretCtrl      = TextEditingController();
  final _tailleCtrl = TextEditingController();
  final _poidsCtrl  = TextEditingController();
  double? _poidsInitial; // poids lu à l'ouverture de la fiche
  final _notesCtrl  = TextEditingController();
  // Généalogie structurée
  final _nomPereCtrl  = TextEditingController();
  final _pucePereCtrl = TextEditingController();
  final _racePereCtrl = TextEditingController();
  // Généalogie : nom de pedigree (affixe) et date de naissance des parents.
  final _nomPedigreePereCtrl = TextEditingController();
  final _nomPedigreeMereCtrl = TextEditingController();
  DateTime? _dateNaissancePere;
  final _nomMereCtrl  = TextEditingController();
  final _puceMereCtrl = TextEditingController();
  // Rattachement par puce : recherche l'animal (tous propriétaires confondus,
  // ex. saillie extérieure) correspondant au numéro de puce saisi, pour
  // permettre plus tard une vraie généalogie inter-éleveurs.
  Map<String, dynamic>? _perePuceMatch;
  Map<String, dynamic>? _merePuceMatch;
  Timer? _pucePereDebounce;
  Timer? _puceMereDebounce;

  String _espece = 'chien';
  final _especeAutreCtrl = TextEditingController();
  String _sexe = 'male';
  bool _sterilise = false;
  String? _typePoil;
  int? _intervalleChaleursCustom;

  // ── Registre Entrée / Sortie
  String    _statut           = 'present'; // éleveur: present|sorti|decede  asso: en_soin|disponible|adopte|transfere|decede (en_fa = fa_id renseigné, indépendant du statut)
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
  // ── Cession
  String? _uidAcquereur;
  String? _cessionContratUrl;
  String? _cessionCertificatUrl;
  double? _cessionPrix;
  String? _cessionNotes;
  // Cession en cours
  Map<String, dynamic>? _cessionEnCours;
  bool _cessionContratSigne = false;
  Map<String, dynamic>? _reservation;
  bool _confirmingCession = false;
  bool _revokingCession   = false;

  bool _pedigree = false;
  bool _isRetraite = false;
  final _clubRegistreCtrl   = TextEditingController();
  final _pedigreeNumeroCtrl = TextEditingController();
  DateTime? _dateNaissance;
  bool _ageEstime = false;
  final _ageEstimeAnneesCtrl = TextEditingController();
  String? _photoUrl;
  File? _photoFile;
  String? _pedigreeUrl;
  String? _pedigreeLof;
  final _passeportCtrl = TextEditingController();
  final List<_ContactUrgence> _contactsUrgence = [];
  /// Personnes autorisées à déposer / récupérer l'animal (pension, pet-sitter) —
  /// animaux.personnes_autorisees (migration_personnes_autorisees.sql).
  final List<_ContactUrgence> _personnesAutorisees = [];

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

  bool get _isNewOwner =>
      _uidAcquereur != null &&
      _uidAcquereur == FirebaseAuth.instance.currentUser?.uid;

  /// Fiche cédée verrouillée pour le cédant : seulement quand l'acquéreur a
  /// un compte PetsMatch (il gère la fiche). Cédé à un particulier sans
  /// compte : l'élevage garde la fiche complète en écriture jusqu'à ce que
  /// l'acquéreur la récupère.
  bool get _cedeVerrouille => _statut == 'sorti' && !_isNewOwner && (_uidAcquereur ?? '').isNotEmpty;

  // Condition de stérilisation (suivi des animaux cédés).
  bool _sterilRequise = false;
  DateTime? _sterilEcheance;
  bool _sterilValidee = false;

  bool _tabReadOnly(String perm) {
    if (widget.readOnly) return true;
    if (widget.employePerms == null) return false;
    return !widget.employePerms!.contains(perm);
  }

  /// Vue employé (Mes employeurs) : droits pilotés par employePerms.
  bool get _estEmploye => widget.employePerms != null;
  /// Identité / alimentation / registre : « Modifier les animaux ».
  bool get _identiteLectureSeule => _tabReadOnly('write_animaux');

  /// Onglet Alimentation (toutes espèces) — lecture seule pour un pet-sitter
  /// ou un employé sans droit d'écriture sur les animaux.
  Widget _alimentationTab({bool lectureSeule = false}) => AlimentationPlanTab(
        key: ValueKey('alimentation-${widget.animalId}'),
        animalId: widget.animalId,
        espece: _espece,
        race: _raceCtrl.text,
        sexe: _sexe,
        sterilise: _sterilise,
        dateNaissance: _dateNaissance,
        nom: _nomCtrl.text,
        poidsFiche: double.tryParse(_poidsCtrl.text.trim().replaceAll(',', '.')),
        lectureSeule: lectureSeule || _identiteLectureSeule,
      );

  // Consultations (CR/ordonnances/radios/actes) est réservé aux professions de
  // santé — un pet-sitter, toiletteur, éducateur… n'y a pas accès du tout
  // (masqué, pas juste lecture seule).
  static bool get _isHealthPro =>
      User_Info.catPro == 'veterinaire' || User_Info.catPro == 'sante' || User_Info.catPro == 'marechal_ferrant';

  // Suivi morphologique & bien-être : réservé aux pros ostéo/kiné et véto
  // (pas maréchal-ferrant — équidés hors périmètre V1, chien/chat
  // uniquement). Le gating par espèce se fait DANS l'onglet
  // (MorphoTimelineTab affiche un message si non supporté), pas dans le
  // compte d'onglets — même principe que l'onglet Anatomie existant, qui
  // ne varie pas non plus avec l'espèce.
  static bool get _isMorphoPro =>
      User_Info.catPro == 'veterinaire' || User_Info.catPro == 'sante';

  int get _tabCount {
    if (widget.vetMode) {
      // Propriétaire : dans l'en-tête commun (ProAnimalEntete), plus un onglet.
      // Véto : Synthèse · Consultations · Santé · Documents ;
      // ostéo : Synthèse · Séances · Bilans · Documents.
      if (User_Info.catPro == 'sante') return 4;
      if (User_Info.catPro == 'marechal_ferrant') return 5;
      if (User_Info.catPro == 'veterinaire') return 4;
      if (User_Info.catPro == 'garde') return 3; // Identité · Santé · Alimentation (pas de Repro)
      return 2; // toilettage / photographe / taxi animalier… : Identité · Santé
    }
    if (widget.isAssociation) return 5; // + Administratif (contrats, certificats)
    if (_cedeVerrouille) return 2; // ancien proprio (acquéreur sur PetsMatch) : Identité + Documents
    if (!User_Info.isElevage && !User_Info.isAssociation && !widget.showReproTab) return 5; // particulier : sans Repro
    return 6; // éleveur / employé élevage (morphologie : carnet de santé › Comptes rendus)
  }

  /// Reconstitue le TabController si le nombre d'onglets a changé (statut /
  /// acquéreur connus seulement après chargement). Sans ça, un animal cédé
  /// ouvert en lecture seule affichait 2 onglets avec un contrôleur à 7 →
  /// « BOTTOM OVERFLOWED BY 99896 PIXELS » et onglets cassés.
  void _syncTabs() {
    final needed = _tabCount;
    if (_tabs.length == needed) return;
    final index = _tabs.index.clamp(0, needed - 1);
    _tabs.dispose();
    _tabs = TabController(length: needed, vsync: this, initialIndex: index);
  }

  void _onPucePereChanged() {
    _pucePereDebounce?.cancel();
    final puce = _pucePereCtrl.text.trim();
    if (puce.length < 4) {
      if (_perePuceMatch != null) setState(() => _perePuceMatch = null);
      return;
    }
    _pucePereDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final rows = await _supa.from('animaux').select('id,nom,race')
            .eq('identification', puce).neq('id', widget.animalId ?? '').limit(1);
        if (!mounted) return;
        setState(() => _perePuceMatch = (rows as List).isNotEmpty ? Map<String, dynamic>.from(rows.first) : null);
      } catch (_) {}
    });
  }

  void _onPuceMereChanged() {
    _puceMereDebounce?.cancel();
    final puce = _puceMereCtrl.text.trim();
    if (puce.length < 4) {
      if (_merePuceMatch != null) setState(() => _merePuceMatch = null);
      return;
    }
    _puceMereDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final rows = await _supa.from('animaux').select('id,nom,race')
            .eq('identification', puce).neq('id', widget.animalId ?? '').limit(1);
        if (!mounted) return;
        setState(() => _merePuceMatch = (rows as List).isNotEmpty ? Map<String, dynamic>.from(rows.first) : null);
      } catch (_) {}
    });
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this); // réajusté après chargement via _refreshFromSupabase si _tabCount change
    if (widget.isAssociation && widget.animalId == null) {
      _statut = 'en_soin';
      // Registre : un animal recueilli entre au refuge le jour de sa saisie
      // (modifiable dans « Registre Entrée / Sortie »).
      final now = DateTime.now();
      _dateEntree = DateTime(now.year, now.month, now.day);
    }
    if (widget.initialTabIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.initialTabIndex! < _tabs.length) _tabs.animateTo(widget.initialTabIndex!);
      });
    }
    _editing = widget.animalId == null; // new animal → edit mode directly
    if (widget.preselectedEspece != null) _espece = widget.preselectedEspece!;
    unawaited(_fillFromData(widget.initialData)); // pre-fill instantly from cached data
    _loadBreeds();
    _loadMesAnimaux();
    _loadEleveurProfile();
    _pucePereCtrl.addListener(_onPucePereChanged);
    _puceMereCtrl.addListener(_onPuceMereChanged);
    if (widget.animalId != null) {
      _loadActiveAlerte();
      _refreshFromSupabase();
      if (!widget.vetMode) {
        _loadVetAcces();
        _loadGardeAcces();
      } else if (!_isHealthPro) {
        _loadHealthAccessStatut();
      }
    }
  }

  // Statut de l'accès du viewer pro courant (non-santé) sur cet animal — pilote
  // _canWriteHealth (lecture seule par défaut, écriture seulement si le
  // propriétaire a explicitement autorisé via _gardeAccesSection/'active_write').
  Future<void> _loadHealthAccessStatut() async {
    if (widget.animalId == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      // Profil pro ACTIF (pas le profil principal : un compte peut être
      // éleveur et vétérinaire), sinon le profil principal.
      String? pid = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;
      if (pid == null) {
        final proProfile = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
        pid = proProfile?['id'] as String?;
      }
      if (pid == null) return;
      final row = await _supa.from('animal_access')
          .select('id, statut').eq('animal_id', widget.animalId!)
          .eq('pro_profile_id', pid).maybeSingle();
      if (mounted) setState(() {
        _healthAccessGrantId = row?['id']?.toString();
        _healthAccessStatut = row?['statut']?.toString();
      });
    } catch (_) {}
  }

  Future<void> _requestHealthWriteAccess() async {
    if (_healthAccessGrantId == null) return;
    try {
      await _supa.from('animal_access').update({'statut': 'write_requested'}).eq('id', _healthAccessGrantId!);
      if (mounted) setState(() => _healthAccessStatut = 'write_requested');
    } catch (_) {}
  }

  Future<void> _loadVetAcces() async {
    if (widget.animalId == null) return;
    try {
      final grants = await _supa
          .from('animal_access')
          .select('id, pro_profile_id, statut, granted_at')
          .eq('animal_id', widget.animalId!)
          .neq('statut', 'revoked');
      final profileIds = (grants as List).map((g) => g['pro_profile_id']?.toString()).whereType<String>().toList();
      final proNames = <String, String>{};
      final vetProfileIds = <String>{};
      if (profileIds.isNotEmpty) {
        final profiles = await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, profile_type')
            .inFilter('id', profileIds);
        for (final u in profiles as List) {
          final pid = u['id']?.toString() ?? '';
          if (u['profile_type'] != 'veterinaire') continue; // exclut pension/autres, gérés dans leur propre section
          vetProfileIds.add(pid);
          final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          proNames[pid] = nom.isNotEmpty ? nom : 'Vétérinaire';
        }
      }
      final list = (grants as List)
          .where((g) => vetProfileIds.contains(g['pro_profile_id']?.toString()))
          .map((g) {
            final m = Map<String, dynamic>.from(g as Map);
            m['vet_nom'] = proNames[g['pro_profile_id']?.toString()] ?? 'Professionnel';
            return m;
          }).toList();
      if (mounted) setState(() => _vetAcces = list);
    } catch (_) {}
  }

  Future<void> _approveVetAcces(String grantId) async {
    try {
      await _supa.from('animal_access').update({
        'statut': 'active',
        'granted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', grantId);
      _loadVetAcces();
    } catch (_) {}
  }

  Future<void> _revokeVetAcces(String grantId) async {
    try {
      await _supa.from('animal_access').update({
        'statut': 'revoked',
        'revoked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', grantId);
      _loadVetAcces();
    } catch (_) {}
  }

  Future<void> _refreshFromSupabase() async {
    try {
      final data = await _supa
          .from('animaux')
          .select('*')
          .eq('id', widget.animalId!)
          .single();
      if (mounted) {
        await _fillFromData(Map<String, dynamic>.from(data));
        setState(_syncTabs);
      }
    } catch (_) {}
    _loadPensionAcces();
    _loadMouvements();
  }

  Future<void> _loadPensionAcces() async {
    if (widget.animalId == null) return;
    try {
      final rows = await _supa
          .from('animal_access')
          .select('id, pro_profile_id, created_at, permissions, user_profiles!inner(profile_type, name_elevage, firstname, lastname)')
          .eq('animal_id', widget.animalId!)
          .eq('statut', 'active')
          .eq('user_profiles.profile_type', 'pension');
      final list = (rows as List).map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        final profile = m['user_profiles'] as Map?;
        final nom = (profile?['name_elevage'] as String?)?.isNotEmpty == true
            ? profile!['name_elevage'] as String
            : '${profile?['firstname'] ?? ''} ${profile?['lastname'] ?? ''}'.trim();
        m['pro_nom'] = nom.isNotEmpty ? nom : 'Pension';
        return m;
      }).toList();
      if (mounted) setState(() => _pensionAcces = list);
    } catch (_) {}
    try {
      final updates = await _supa.from('pension_updates').select('id').eq('animal_id', widget.animalId!).limit(1);
      if (mounted) setState(() => _hasPensionUpdates = (updates as List).isNotEmpty);
    } catch (_) {}
    try {
      final rapports = await _supa.from('education_progression').select('id').eq('animal_id', widget.animalId!).limit(1);
      if (mounted) setState(() => _hasEducationRapports = (rapports as List).isNotEmpty);
    } catch (_) {}
    try {
      final devis = await _supa.from('devis').select('id').eq('animal_id', widget.animalId!).limit(1);
      if (mounted) setState(() => _hasDevis = (devis as List).isNotEmpty);
    } catch (_) {}
  }

  // Accès pet-sitting (visible au propriétaire) — lecture seule par défaut
  // (statut 'active'), écriture santé seulement si 'active_write' (approuvée
  // via _approveGardeAcces), demande en attente si 'write_requested'.
  Future<void> _loadGardeAcces() async {
    if (widget.animalId == null) return;
    try {
      final rows = await _supa
          .from('animal_access')
          .select('id, pro_profile_id, statut, created_at, user_profiles!inner(profile_type, name_elevage, firstname, lastname)')
          .eq('animal_id', widget.animalId!)
          .neq('statut', 'revoked')
          .eq('user_profiles.profile_type', 'garde');
      final list = (rows as List).map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        final profile = m['user_profiles'] as Map?;
        final nom = (profile?['name_elevage'] as String?)?.isNotEmpty == true
            ? profile!['name_elevage'] as String
            : '${profile?['firstname'] ?? ''} ${profile?['lastname'] ?? ''}'.trim();
        m['pro_nom'] = nom.isNotEmpty ? nom : 'Pet-sitter';
        return m;
      }).toList();
      if (mounted) setState(() => _gardeAcces = list);
    } catch (_) {}
  }

  Future<void> _loadMouvements() async {
    if (widget.animalId == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final res = await _supa
          .from('registre_mouvements')
          .select('*')
          .eq('animal_id', widget.animalId!)
          .eq('uid_eleveur', uid)
          .order('date_mouvement', ascending: false);
      if (mounted) setState(() => _mouvements = List<Map<String, dynamic>>.from(res));
    } catch (_) {}
  }

  Future<void> _showAddMouvementSheet(BuildContext context) async {
    if (widget.animalId == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    const qualiteLabels = <String, String>{
      'naissance': 'Naissance dans l\'élevage', 'eleveur': 'Éleveur',
      'particulier': 'Particulier', 'refuge': 'Refuge / Association',
      'importation': 'Importation', 'association': 'Association', 'autre': 'Autre',
    };
    String type = 'entree';
    DateTime date = DateTime.now();
    String motif = '';
    String provQualite = '';
    String provNom = '';
    String provAdresse = '';
    String destQualite = '';
    String destNom = '';
    String destAdresse = '';
    final notesCtrl = TextEditingController();
    bool saving = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        const deco = InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
          isDense: true,
        );
        return Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Ajouter un mouvement', style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 16),
            // Type
            Row(children: [
              for (final t in <(String, String, IconData)>[
                ('entree', 'Entrée', Icons.arrow_downward),
                ('sortie', 'Sortie', Icons.arrow_upward),
              ])
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setSheet(() { type = t.$1; motif = ''; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: type == t.$1 ? const Color(0xFF0C5C6C) : Colors.transparent,
                        border: Border.all(
                            color: type == t.$1 ? const Color(0xFF0C5C6C) : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(t.$3, size: 14,
                            color: type == t.$1 ? Colors.white : const Color(0xFF0C5C6C)),
                        const SizedBox(width: 6),
                        Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: type == t.$1 ? Colors.white : const Color(0xFF1F2A2E))),
                      ]),
                    ),
                  ),
                )),
            ]),
            const SizedBox(height: 12),
            // Date
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: date,
                  firstDate: DateTime(1990), lastDate: DateTime(2100),
                  builder: (c, child) => Theme(
                      data: ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(primary: Color(0xFF0C5C6C))),
                      child: child!),
                );
                if (d != null) setSheet(() => date = d);
              },
              child: InputDecorator(
                decoration: deco.copyWith(
                  labelText: 'Date *',
                  labelStyle: const TextStyle(
                      fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  suffixIcon: const Icon(Icons.calendar_today_outlined,
                      size: 14, color: Color(0xFF6F767B)),
                ),
                child: Text(DateFormat('dd/MM/yyyy').format(date),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
            ),
            const SizedBox(height: 10),
            // Motif
            DropdownButtonFormField<String>(
              value: motif.isEmpty ? null : motif,
              isExpanded: true,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
              decoration: deco.copyWith(
                  labelText: 'Motif',
                  labelStyle: const TextStyle(
                      fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              items: (type == 'entree'
                  ? <(String, String)>[('naissance', 'Naissance'), ('achat', 'Achat / Acquisition'),
                      ('cession', 'Cession'), ('retour_saillie', 'Retour de saillie'),
                      ('retour_pension', 'Retour de pension'), ('autre', 'Autre')]
                  : <(String, String)>[('cession', 'Cession'), ('saillie', 'Saillie'),
                      ('pension', 'Pension / Garde'), ('retraite', 'Retraite'),
                      ('adoption', 'Adoption'), ('vente', 'Vente'), ('autre', 'Autre')])
                  .map((t) => DropdownMenuItem(value: t.$1,
                      child: Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13))))
                  .toList(),
              onChanged: (v) => setSheet(() => motif = v ?? ''),
            ),
            const SizedBox(height: 10),
            if (type == 'entree') ...[
              DropdownButtonFormField<String>(
                value: provQualite.isEmpty ? null : provQualite,
                isExpanded: true,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                decoration: deco.copyWith(
                    labelText: 'Qualité fournisseur',
                    labelStyle: const TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                items: ['naissance', 'eleveur', 'particulier', 'refuge', 'importation', 'autre']
                    .map((v) => DropdownMenuItem(value: v,
                        child: Text(qualiteLabels[v] ?? v,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13))))
                    .toList(),
                onChanged: (v) => setSheet(() => provQualite = v ?? ''),
              ),
              const SizedBox(height: 8),
              TextFormField(
                onChanged: (v) => provNom = v,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: deco.copyWith(labelText: 'Nom / Élevage',
                    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              ),
              const SizedBox(height: 8),
              TextFormField(
                onChanged: (v) => provAdresse = v,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: deco.copyWith(labelText: 'Adresse',
                    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                value: destQualite.isEmpty ? null : destQualite,
                isExpanded: true,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                decoration: deco.copyWith(
                    labelText: 'Qualité destinataire',
                    labelStyle: const TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                items: ['eleveur', 'particulier', 'refuge', 'association', 'autre']
                    .map((v) => DropdownMenuItem(value: v,
                        child: Text(qualiteLabels[v] ?? v,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13))))
                    .toList(),
                onChanged: (v) => setSheet(() => destQualite = v ?? ''),
              ),
              const SizedBox(height: 8),
              TextFormField(
                onChanged: (v) => destNom = v,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: deco.copyWith(labelText: 'Nom / Élevage',
                    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              ),
              const SizedBox(height: 8),
              TextFormField(
                onChanged: (v) => destAdresse = v,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: deco.copyWith(labelText: 'Adresse',
                    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: notesCtrl,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: deco.copyWith(labelText: 'Notes (optionnel)',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: saving ? null : () async {
                setSheet(() => saving = true);
                try {
                  await _supa.from('registre_mouvements').insert({
                    'animal_id':    widget.animalId,
                    'uid_eleveur':  uid,
                    if (User_Info.activeProfileId != null) 'eleveur_profile_id': User_Info.activeProfileId,
                    'type':         type,
                    'date_mouvement': date.toIso8601String().split('T').first,
                    if (motif.isNotEmpty) 'motif': motif,
                    if (type == 'entree') ...{
                      if (provQualite.isNotEmpty) 'provenance_qualite': provQualite,
                      if (provNom.isNotEmpty)     'provenance_nom':     provNom,
                      if (provAdresse.isNotEmpty) 'provenance_adresse': provAdresse,
                    } else ...{
                      if (destQualite.isNotEmpty) 'destinataire_qualite': destQualite,
                      if (destNom.isNotEmpty)     'destinataire_nom':     destNom,
                      if (destAdresse.isNotEmpty) 'destinataire_adresse': destAdresse,
                    },
                    if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadMouvements();
                } catch (e) {
                  setSheet(() => saving = false);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5C6C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            )),
          ])),
        );
      }),
    );
    notesCtrl.dispose();
  }

  Future<void> _revokePensionAcces(BuildContext context, String accesId, String proNom) async {
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

  Future<void> _revokeGardeAcces(BuildContext context, String accesId, String proNom) async {
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
      _loadGardeAcces();
    }
  }

  // Le propriétaire autorise explicitement l'écriture santé (ajout/suppression
  // de vaccins…) à un pet-sitter qui en a fait la demande (_requestHealthWriteAccess).
  Future<void> _approveGardeAcces(String accesId) async {
    try {
      await _supa.from('animal_access').update({'statut': 'active_write'}).eq('id', accesId);
      _loadGardeAcces();
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
          .from('users_complet')
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

  // Crée un doc dans documents_animaux et ouvre /signer-contrat/[token] dans le navigateur
  Future<void> _ouvrirContratWeb(String type) async {
    final uid  = FirebaseAuth.instance.currentUser?.uid;
    final anId = widget.animalId;
    if (uid == null || anId == null) return;
    try {
      final pid = User_Info.activeProfileId;
      final res = await _supa.from('documents_animaux').insert({
        'animal_id':    anId,
        'uid_eleveur':  uid,
        if (pid.isNotEmpty) 'pro_profile_id': pid,
        'type':         type,
        'titre':        '${type == 'contrat_vente' ? 'Contrat de vente' : 'Contrat de réservation'} — ${_nomCtrl.text.trim()}',
        'statut':       'brouillon',
        'metadata':     <String, dynamic>{},
      }).select('token').single();
      final token = res['token'] as String;
      const baseUrl = kSiteBaseUrl;
      final url = Uri.parse('$baseUrl/signer-contrat/$token');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        await Clipboard.setData(ClipboardData(text: url.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lien copié — ouvrez-le dans votre navigateur')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  Future<void> _loadMesAnimaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final pid = User_Info.activeProfileId;
      var maleQ = _supa.from('animaux')
          .select('id, nom, nom_pedigree, identification, race, photo_url, date_naissance')
          .eq('uid_eleveur', uid).eq('sexe', 'male');
      if (pid.isNotEmpty) maleQ = maleQ.eq('profile_id', pid);
      final males = await maleQ.order('nom');
      var femelleQ = _supa.from('animaux')
          .select('id, nom, nom_pedigree, identification, race, photo_url, date_naissance')
          .eq('uid_eleveur', uid).eq('sexe', 'femelle');
      if (pid.isNotEmpty) femelleQ = femelleQ.eq('profile_id', pid);
      final femelles = await femelleQ.order('nom');
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

  Future<void> _checkCogerantActif() async {
    // mes_animaux.dart passe TOUJOURS eleveurUidOverride = uid de l'élevage
    // actif (même quand ce n'est pas une cogérance), donc eleveurUidOverride
    // != null ne veut pas dire "viewer non autorisé" — seul un vrai
    // décalage entre le uid Firebase courant et _ownerUid, sans lien de
    // cogérance actif, signale un viewer tiers (employé, etc.).
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || _ownerUid == null || me == _ownerUid) return;
    try {
      final row = await _supa.from('elevage_cogerants')
          .select('id')
          .eq('uid_gerant', _ownerUid!)
          .eq('uid_cogerant', me)
          .eq('statut', 'actif')
          .isFilter('date_fin', null)
          .maybeSingle();
      if (mounted && row != null) setState(() => _isCogerantActif = true);
    } catch (_) {}
  }

  Future<void> _fillFromData(Map<String, dynamic>? d) async {
    if (d == null) return;
    _ownerUid = (d['uid_eleveur'] ?? d['uid_proprietaire'])?.toString();
    unawaited(_checkCogerantActif());
    _espece = d['espece'] ?? _espece;
    _especeAutreCtrl.text = (d['espece_autre'] as String?) ?? '';
    _descriptionCtrl.text = d['description'] ?? '';
    _nomCtrl.text   = d['nom'] ?? '';
    _nomPedigreeCtrl.text = d['nom_pedigree'] ?? '';
    _raceCtrl.text  = d['race'] ?? '';
    _couleurCtrl.text = d['couleur'] ?? '';
    _couleurYeuxCtrl.text = d['couleur_yeux'] ?? '';
    _identCtrl.text = d['identification'] ?? '';
    _sireCtrl.text       = d['num_sire'] ?? '';
    _carteImmatCtrl.text = d['carte_immatriculation'] ?? '';
    _livretCtrl.text     = d['livret_signaletique'] ?? '';
    _tailleCtrl.text = d['taille']?.toString() ?? '';
    _poidsCtrl.text  = d['poids']?.toString() ?? '';
    _poidsInitial    = poidsKg(d['poids']);
    _notesCtrl.text  = d['notes'] ?? '';
    _nomPereCtrl.text  = d['nom_pere'] ?? '';
    _pucePereCtrl.text = d['puce_pere'] ?? '';
    _racePereCtrl.text = (d['race_pere'] as String?) ?? '';
    _nomPedigreePereCtrl.text = (d['nom_pedigree_pere'] as String?) ?? '';
    _nomPedigreeMereCtrl.text = (d['nom_pedigree_mere'] as String?) ?? '';
    _dateNaissancePere = _parseDate(d['date_naissance_pere']);
    _nomMereCtrl.text  = d['nom_mere'] ?? '';
    _puceMereCtrl.text = d['puce_mere'] ?? '';
    _sexe = d['sexe'] ?? 'male';
    _intervalleChaleursCustom = d['intervalle_chaleurs_jours'] as int?;
    _sterilise = d['sterilise'] ?? false;
    _isRetraite = d['is_retraite'] ?? false;
    _typePoil = d['type_poil'] as String?;
    _pedigree = d['pedigree'] ?? false;
    _clubRegistreCtrl.text    = d['club_registre']    ?? '';
    _pedigreeNumeroCtrl.text  = d['pedigree_numero']  ?? '';
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
    for (final c in _personnesAutorisees) c.dispose();
    _personnesAutorisees.clear();
    final autorises = d['personnes_autorisees'];
    for (final raw in (autorises is List ? autorises : [])) {
      _personnesAutorisees.add(_ContactUrgence(
          nomVal: raw['nom'] ?? '', telVal: raw['tel'] ?? '', lienVal: raw['lien'] ?? ''));
    }
    _dateNaissance = _parseDate(d['date_naissance']);
    _ageEstime = d['age_estime'] as bool? ?? false;
    if (_ageEstime && _dateNaissance != null) {
      _ageEstimeAnneesCtrl.text =
          ((DateTime.now().difference(_dateNaissance!).inDays) / 365).round().toString();
    }
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
    // Cession
    _uidAcquereur          = d['uid_acquereur'] as String?;
    _sterilRequise         = d['sterilisation_requise'] == true;
    _sterilEcheance        = _parseDate(d['sterilisation_echeance']);
    _sterilValidee         = d['sterilisation_validee'] == true;
    // Statut + acquéreur connus → nombre d'onglets définitif, rebuild
    // immédiat (la suite du chargement attend le réseau).
    if (mounted) { setState(_syncTabs); } else { _syncTabs(); }
    _cessionContratUrl     = d['cession_contrat_url'] as String?;
    _cessionCertificatUrl  = d['cession_certificat_url'] as String?;
    _cessionPrix           = (d['cession_prix'] as num?)?.toDouble();
    _cessionNotes          = d['cession_notes'] as String?;
    // Charger la cession active si en cours
    // 'cession_en_cours' = cession lancée depuis l'app (ligne `cessions`),
    // 'en_attente_cession' = cession du site (pas toujours de ligne `cessions`).
    if (_cessionEnAttente && widget.animalId != null) {
      final cessions = await _supa
          .from('cessions')
          .select()
          .eq('animal_id', widget.animalId!)
          // Pas une cession déjà confirmée d'un précédent passage de main
          .not('statut', 'in', '(revoquee,confirme)')
          .order('created_at', ascending: false)
          .limit(1);
      _cessionEnCours = cessions.isNotEmpty ? cessions.first : null;
      // Un contrat de vente / certificat entièrement signé vaut accord de
      // l'acquéreur → l'éleveur peut confirmer même si le récap n'est pas signé.
      try {
        final signedDocs = await _supa.from('documents_animaux')
            .select('id').eq('animal_id', widget.animalId!)
            .inFilter('type', ['contrat_vente', 'certificat_cession'])
            .eq('statut', 'signe').limit(1);
        _cessionContratSigne = signedDocs.isNotEmpty;
      } catch (_) {
        _cessionContratSigne = false;
      }
    } else {
      _cessionEnCours = null;
      _cessionContratSigne = false;
    }
    // Charger la réservation active si l'animal est réservé
    if (_statut == 'reserve' && widget.animalId != null) {
      final reservations = await _supa
          .from('reservations_animaux')
          .select()
          .eq('animal_id', widget.animalId!)
          .eq('statut', 'active')
          .order('created_at', ascending: false)
          .limit(1);
      _reservation = reservations.isNotEmpty ? reservations.first : null;
    } else {
      _reservation = null;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _pucePereDebounce?.cancel();
    _puceMereDebounce?.cancel();
    _pucePereCtrl.removeListener(_onPucePereChanged);
    _puceMereCtrl.removeListener(_onPuceMereChanged);
    for (final c in [_nomCtrl, _nomPedigreeCtrl, _raceCtrl, _couleurCtrl, _couleurYeuxCtrl, _identCtrl,
      _sireCtrl, _carteImmatCtrl, _livretCtrl,
      _tailleCtrl, _poidsCtrl, _notesCtrl, _nomPereCtrl, _pucePereCtrl, _racePereCtrl,
      _nomPedigreePereCtrl, _nomPedigreeMereCtrl,
      _nomMereCtrl, _puceMereCtrl, _passeportCtrl, _clubRegistreCtrl, _pedigreeNumeroCtrl, _descriptionCtrl,
      _provenanceNomCtrl, _provenanceAdresseCtrl, _importationRefCtrl,
      _raceMereCtrl, _destinataireNomCtrl, _destinataireAdresseCtrl]) { c.dispose(); }
    for (final c in _contactsUrgence) c.dispose();
    for (final c in _personnesAutorisees) c.dispose();
    _ageEstimeAnneesCtrl.dispose();
    _especeAutreCtrl.dispose();
    super.dispose();
  }

  // ── Sauvegarde ───────────────────────────────────────────────────────────────

  String _puceVerifiee = '';

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez saisir un nom')));
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
    if (widget.animalId == null && _identCtrl.text.replaceAll(RegExp(r'\D'), '').length >= 8 && _identCtrl.text != _puceVerifiee) {
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
      String? uploadedUrl = _photoUrl;
      if (_photoFile != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        uploadedUrl = await uploadPhoto(_photoFile!, 'animaux/$uid/$name');
      }

      final uid = widget.eleveurUidOverride ?? FirebaseAuth.instance.currentUser!.uid;
      final id = widget.animalId ?? DateTime.now().millisecondsSinceEpoch.toString();
      final activeProfileId = widget.proprioProfileIdOverride ?? User_Info.activeProfileId;
      final data = {
        'id':                  id,
        'uid_eleveur':         uid,
        if (activeProfileId.isNotEmpty && widget.animalId == null)
          'profile_id': activeProfileId,
        'espece':              _espece,
        'espece_autre':        _espece == 'autre' ? _especeAutreCtrl.text.trim() : null,
        'description':         _descriptionCtrl.text.trim(),
        'nom':                 _nomCtrl.text.trim(),
        'nom_pedigree':        _nomPedigreeCtrl.text.trim(),
        'race':                _raceCtrl.text.trim(),
        'couleur':             _couleurCtrl.text.trim(),
        'couleur_yeux':        _couleurYeuxCtrl.text.trim(),
        'identification':      _identCtrl.text.trim(),
        'num_sire':              _espece == 'cheval' ? _sireCtrl.text.trim() : null,
        'carte_immatriculation': _espece == 'cheval' ? _carteImmatCtrl.text.trim() : null,
        'livret_signaletique':   _espece == 'cheval' ? _livretCtrl.text.trim() : null,
        'taille':              _tailleCtrl.text.trim(),
        // Poids inchangé : non renvoyé, pour ne pas écraser une pesée ajoutée
        // entre-temps à la courbe (la fiche reprend le dernier point, trigger
        // pm_poids_courbe_vers_fiche).
        if (widget.animalId == null || poidsKg(_poidsCtrl.text) != _poidsInitial)
          'poids':             poidsKg(_poidsCtrl.text),
        'nom_pere':            _nomPereCtrl.text.trim(),
        'puce_pere':           _pucePereCtrl.text.trim(),
        'race_pere':           _racePereCtrl.text.trim(),
        'nom_pedigree_pere':   _nomPedigreePereCtrl.text.trim().isEmpty ? null : _nomPedigreePereCtrl.text.trim(),
        'nom_pedigree_mere':   _nomPedigreeMereCtrl.text.trim().isEmpty ? null : _nomPedigreeMereCtrl.text.trim(),
        'date_naissance_pere': _dateNaissancePere?.toIso8601String(),
        'nom_mere':            _nomMereCtrl.text.trim(),
        'puce_mere':           _puceMereCtrl.text.trim(),
        'notes':               _notesCtrl.text.trim(),
        'sexe':                _sexe,
        'sterilise':           _sterilise,
        'type_poil':           _typePoil,
        'pedigree':            _pedigree,
        'club_registre':       _clubRegistreCtrl.text.trim(),
        'pedigree_numero':     _pedigreeNumeroCtrl.text.trim().isEmpty ? null : _pedigreeNumeroCtrl.text.trim(),
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
        'age_estime':          widget.isAssociation ? _ageEstime : false,
        'statut':              _statut,
        'is_retraite':         _isRetraite,
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
        'updated_at':          DateTime.now().toUtc().toIso8601String(),
        'is_association':      widget.isAssociation,
      };

      await _supa.from('animaux').upsert(data);
      // Personnes autorisées : écrit à part — la colonne n'existe qu'une fois
      // migration_personnes_autorisees.sql passée (ne bloque pas l'enregistrement).
      try {
        await _supa.from('animaux').update({
          'personnes_autorisees': _personnesAutorisees
              .map((c) => {'nom': c.nom.text.trim(), 'tel': c.tel.text.trim(), 'lien': c.lien.text.trim()})
              .where((c) => c['nom']!.isNotEmpty || c['tel']!.isNotEmpty)
              .toList(),
        }).eq('id', id);
      } catch (_) {}

      // Création : initialiser animaux_proprietes avec le profil actif
      if (widget.animalId == null) {
        try {
          final dateStr = (_dateEntree ?? DateTime.now()).toIso8601String().split('T').first;
          await _supa.from('animaux_proprietes').upsert({
            'animal_id':          id,
            'uid_proprio':        uid,
            'date_debut':         dateStr,
            if (activeProfileId.isNotEmpty) 'profile_id_proprio': activeProfileId,
          }, onConflict: 'animal_id,uid_proprio');
        } catch (_) {}
      }

      // Protocoles auto pour un nouvel animal entrant
      if (widget.animalId == null) {
        try {
          await PlanningService.triggerAutoProtocoles(
            uid: uid,
            declencheur: 'entree',
            animalId: id,
            dateEvenement: _dateEntree ?? DateTime.now(),
            espece: _espece,
          );
        } catch (_) {}
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Confirmer la cession (après signature acquéreur) ─────────────────────
  Future<void> _confirmerCession() async {
    if (_cessionEnCours == null) return;
    setState(() => _confirmingCession = true);
    try {
      final cessionId = _cessionEnCours!['id'];
      final uidAcq    = _cessionEnCours!['uid_acquereur'] as String?;
      final qualiteAcq = (_cessionEnCours!['qualite'] as String?) ?? 'particulier';
      // Profil de l'acquéreur qui recevra l'animal (jamais un profil pro)
      String? acqProfileId = _cessionEnCours!['acquereur_profile_id'] as String?;
      if ((acqProfileId == null || acqProfileId.isEmpty) && uidAcq != null) {
        final wanted = qualiteAcq == 'eleveur'
            ? 'eleveur'
            : qualiteAcq == 'refuge' || qualiteAcq == 'association' ? 'association' : 'particulier';
        final byType = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', uidAcq).eq('profile_type', wanted).maybeSingle();
        acqProfileId = byType?['id'] as String?;
        acqProfileId ??= (await _supa.from('user_profiles_complet')
            .select('id').eq('uid', uidAcq).eq('is_main', true).maybeSingle())?['id'] as String?;
      }
      // Transférer la fiche
      final dateCession = (_cessionEnCours!['date_cession'] as String?)
          ?? DateTime.now().toIso8601String().split('T').first;
      await _supa.from('animaux').update({
        'statut':        'sorti',
        'uid_acquereur': uidAcq,
        if (acqProfileId != null) 'profile_id_acquereur': acqProfileId,
        'date_sortie':   dateCession,
      }).eq('id', widget.animalId!);
      // Historique de propriété (animaux_proprietes) — clôture la ligne du
      // cédant et ouvre celle de l'acquéreur sur son profil principal
      // (is_main), pas forcément 'particulier' : cette étape manquait, ce qui
      // rendait l'animal invisible pour l'acquéreur (filtré par profile_id_proprio).
      //
      // IMPORTANT — ordre des opérations : la policy RLS d'INSERT sur
      // animaux_proprietes n'autorise le cédant à créer la ligne de
      // l'acquéreur que via is_principal_owner_or_cogerant(), qui exige que
      // SA PROPRE ligne soit encore active (date_fin IS NULL) au moment de
      // l'insert — la clôturer avant fait donc échouer l'insert
      // silencieusement. Ouvrir la ligne acquéreur D'ABORD, clôturer celle
      // du cédant ENSUITE.
      // Le CÉDANT réel de la cession est toujours le propriétaire de la
      // fiche (_ownerUid) — PAS forcément la session en cours : un cogérant
      // actif peut cliquer ce bouton pour le compte de l'élevage, mais son
      // propre uid n'est jamais titulaire de la ligne animaux_proprietes à
      // clôturer, ni « uid_eleveur » du mouvement de sortie. Utiliser
      // FirebaseAuth.currentUser ici faisait échouer silencieusement la
      // clôture (0 ligne mise à jour) et mal-attribuait l'entrée du registre
      // au cogérant au lieu du véritable élevage cédant.
      // Re-cession par un particulier acquéreur : le cédant est celui qui a
      // lancé la cession (cessions.uid_eleveur), pas l'éleveur d'origine.
      final cedantUid = (_cessionEnCours!['uid_eleveur'] as String?)
          ?? _ownerUid ?? FirebaseAuth.instance.currentUser?.uid;
      // Transfert atomique côté base (migration_cession_transfert_propriete) :
      // l'index « un seul principal actif » faisait échouer en silence
      // l'insert de la ligne acquéreur → animal absent de ses « Mes animaux ».
      if (uidAcq != null) {
        await _supa.rpc('ceder_propriete_animal', params: {
          'p_animal_id':         widget.animalId,
          'p_uid_acquereur':     uidAcq,
          'p_profile_acquereur': acqProfileId,
          'p_date':              dateCession,
        });
      }
      // Insérer mouvements dans registre_mouvements (historique de vie de l'animal)
      if (uidAcq != null && cedantUid != null) {
        final profilAcq = await _supa.from('users_complet')
            .select('firstname, lastname, name_elevage, is_elevage, is_association')
            .eq('uid', uidAcq).maybeSingle();
        final nomAcqRaw = (profilAcq?['name_elevage'] as String? ?? '').isNotEmpty
            ? profilAcq!['name_elevage'] as String
            : '${profilAcq?['firstname'] ?? ''} ${profilAcq?['lastname'] ?? ''}'.trim();
        final isAcqEleveur = profilAcq?['is_elevage'] == true;
        final isAcqAsso    = profilAcq?['is_association'] == true;
        final cedantProfileId = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', cedantUid).eq('is_main', true).maybeSingle();
        // Sortie pour le cédant
        await _supa.from('registre_mouvements').insert({
          'animal_id':             widget.animalId,
          'uid_eleveur':           cedantUid,
          if (cedantProfileId?['id'] != null) 'eleveur_profile_id': cedantProfileId!['id'],
          'type':                  'sortie',
          'date_mouvement':        dateCession,
          'motif':                 'cession',
          'destinataire_qualite':  isAcqEleveur ? 'eleveur' : (isAcqAsso ? 'association' : 'particulier'),
          'destinataire_nom':      nomAcqRaw,
          'cession_id':            cessionId,
        });
        // Entrée pour l'acquéreur (éleveur ou association uniquement)
        if (isAcqEleveur || isAcqAsso) {
          final acqProfRow = await _supa.from('user_profiles_complet')
              .select('id').eq('uid', uidAcq!).eq('is_main', true).maybeSingle();
          final acqProfileId = acqProfRow?['id'] as String?;
          await _supa.from('registre_mouvements').insert({
            'animal_id':           widget.animalId,
            'uid_eleveur':         uidAcq,
            if (acqProfileId != null) 'eleveur_profile_id': acqProfileId,
            'type':                'entree',
            'date_mouvement':      dateCession,
            'motif':               'cession',
            'provenance_qualite':  'eleveur',
            'provenance_nom':      _nomElevage ?? '',
            'provenance_adresse':  _adresseElevage ?? '',
            'cession_id':          cessionId,
          });
        }
      }
      // Marquer la cession confirmée
      await _supa.from('cessions').update({
        'statut':       'confirme',
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', cessionId);
      // Notifier l'acquéreur (sur le profil qui reçoit l'animal)
      if (uidAcq != null) {
        await _supa.from('notifications').insert({
          'uid':   uidAcq,
          'type':  'cession_confirmee',
          'title': '🐾 Animal transféré : ${_nomCtrl.text}',
          'body':  '${_nomElevage ?? 'L\'éleveur'} a confirmé la cession. L\'animal apparaît maintenant dans votre compte.',
          if (acqProfileId != null) 'profile_id': acqProfileId,
          'data':  {'animalId': widget.animalId},
          'read':  false,
        });
      }
      await _refreshFromSupabase();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Cession confirmée — fiche transférée'), backgroundColor: Color(0xFF6E9E57)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _confirmingCession = false);
    }
  }

  // ── Révoquer la cession ────────────────────────────────────────────────────
  bool get _cessionEnAttente => _statut == 'cession_en_cours' || _statut == 'en_attente_cession';

  /// Modifier la cession en attente sans la refaire (tant que les deux
  /// parties n'ont pas signé).
  Future<void> _modifierCession() async {
    if (widget.animalId == null) return;
    final cedantUid = _ownerUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final ok = await showEditCessionSheet(
      context,
      animal: {
        'id': widget.animalId,
        'nom': _nomCtrl.text,
        'statut': _statut,
        'uid_acquereur': _uidAcquereur,
        'destinataire_qualite': _destinataireQualite,
        'destinataire_nom': _destinataireNomCtrl.text,
        'destinataire_adresse': _destinataireAdresseCtrl.text,
        'cession_prix': _cessionPrix,
        'cession_notes': _cessionNotes,
        'date_sortie': _dateSortie?.toIso8601String().split('T').first,
      },
      cession: _cessionEnCours,
      cedantUid: cedantUid,
    );
    if (!ok || !mounted) return;
    await _refreshFromSupabase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cession modifiée'), backgroundColor: Color(0xFF6E9E57)));
    }
  }

  /// Cession faite hors PetsMatch (contrat papier) : finalise le transfert
  /// sans signature électronique — avec ou sans ligne `cessions` (cession
  /// créée sur le site). Contrats encore à signer annulés (trace conservée).
  Future<void> _validerCessionSansSignature() async {
    if (widget.animalId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Valider sans signature ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text('La cession de ${_nomCtrl.text.isNotEmpty ? _nomCtrl.text : 'cet animal'} a été faite hors PetsMatch '
            '(contrat papier). Le transfert est finalisé sans contrat signé dans l\'application ; les documents encore à signer sont annulés.',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Valider la cession')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _confirmingCession = true);
    try {
      final id = widget.animalId!;
      final cedant = _ownerUid ?? FirebaseAuth.instance.currentUser!.uid;
      final row = _cessionEnCours;
      final uidAcq = (row?['uid_acquereur'] as String?) ?? _uidAcquereur;
      final dateCession = (row?['date_cession'] as String?)
          ?? _dateSortie?.toIso8601String().split('T').first
          ?? DateTime.now().toIso8601String().split('T').first;
      if (row != null) {
        await _supa.from('cessions').update({'statut': 'confirme', 'confirmed_at': DateTime.now().toUtc().toIso8601String()}).eq('id', row['id']);
      }
      String? acqProfileId = row?['acquereur_profile_id'] as String?;
      if ((acqProfileId == null || acqProfileId.isEmpty) && uidAcq != null) {
        acqProfileId = (await _supa.from('user_profiles_complet').select('id').eq('uid', uidAcq).eq('profile_type', 'particulier').maybeSingle())?['id'] as String?;
        acqProfileId ??= (await _supa.from('user_profiles_complet').select('id').eq('uid', uidAcq).eq('is_main', true).maybeSingle())?['id'] as String?;
      }
      await _supa.from('animaux').update({
        'statut': 'sorti',
        'date_sortie': dateCession,
        if (row != null) ...{
          'destinataire_nom': row['nom_acquereur'],
          'destinataire_adresse': row['adresse_acquereur'],
          'destinataire_qualite': row['qualite'] ?? 'particulier',
        },
        if (uidAcq != null) 'uid_acquereur': uidAcq,
        if (acqProfileId != null) 'profile_id_acquereur': acqProfileId,
      }).eq('id', id);
      if (uidAcq != null) {
        await _supa.rpc('ceder_propriete_animal', params: {
          'p_animal_id': id, 'p_uid_acquereur': uidAcq, 'p_profile_acquereur': acqProfileId, 'p_date': dateCession,
        });
      } else {
        await _supa.from('animaux_proprietes').update({'date_fin': dateCession})
            .eq('animal_id', id).eq('uid_proprio', cedant).isFilter('date_fin', null);
      }
      // Registre : sortie du cédant (déjà inscrite pour une cession du site).
      try {
        final deja = await _supa.from('registre_mouvements').select('id')
            .eq('animal_id', id).eq('uid_eleveur', cedant).eq('type', 'sortie').limit(1);
        if ((deja as List).isEmpty) {
          await _supa.from('registre_mouvements').insert({
            'animal_id': id, 'uid_eleveur': cedant,
            if (User_Info.activeProfileId.isNotEmpty) 'eleveur_profile_id': User_Info.activeProfileId,
            'type': 'sortie', 'date_mouvement': dateCession, 'motif': 'cession',
            'destinataire_qualite': row?['qualite'] ?? 'particulier',
            'destinataire_nom': row?['nom_acquereur'] ?? _destinataireNomCtrl.text,
          });
        }
      } catch (_) {}
      // Contrats de cession encore à signer : annulés (cession faite sur papier).
      try {
        await _supa.from('documents_animaux').update({'statut': 'annule'})
            .eq('animal_id', id).inFilter('type', ['contrat_vente', 'certificat_cession'])
            .inFilter('statut', kStatutsContratNonFinalises);
      } catch (_) {}
      if (!mounted) return;
      setState(() { _statut = 'sorti'; _cessionEnCours = null; _syncTabs(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cession validée.'), backgroundColor: Color(0xFF6E9E57)));
      await _refreshFromSupabase();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _confirmingCession = false);
    }
  }

  Future<void> _revoquerCession() async {
    if (_cessionEnCours == null && _statut != 'en_attente_cession') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Révoquer la cession ?'),
        content: const Text('L\'animal reviendra dans votre compte. L\'acquéreur sera notifié de l\'annulation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Révoquer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _revokingCession = true);
    try {
      final uidAcq = (_cessionEnCours?['uid_acquereur'] as String?) ?? _uidAcquereur;
      if (_cessionEnCours != null) {
        await _supa.from('cessions').update({'statut': 'revoquee'}).eq('id', _cessionEnCours!['id']);
      }
      // Cession annulée : plus d'acquéreur ni de condition de stérilisation
      // (sinon les rappels « stérilisation en retard » continuaient chaque jour).
      const annulation = {
        'uid_acquereur': null, 'profile_id_acquereur': null,
        'sterilisation_requise': false, 'sterilisation_echeance': null,
        'sterilisation_eleveur_uid': null, 'sterilisation_eleveur_profile_id': null,
      };
      if (_statut == 'en_attente_cession') {
        // Cession du site : la sortie avait déjà été inscrite au registre et
        // la date de sortie posée — l'animal n'est finalement pas parti.
        await _supa.from('animaux').update({'statut': 'present', 'date_sortie': null, ...annulation}).eq('id', widget.animalId!);
        try {
          await _supa.from('registre_mouvements').delete()
              .eq('animal_id', widget.animalId!)
              .eq('uid_eleveur', _ownerUid ?? FirebaseAuth.instance.currentUser?.uid ?? '')
              .eq('type', 'sortie').eq('motif', 'cession');
        } catch (_) {}
      } else {
        await _supa.from('animaux').update({'statut': 'present', ...annulation}).eq('id', widget.animalId!);
      }
      // Contrats de cette cession avortée : tout ce qui n'est pas signé des
      // deux côtés est supprimé (brouillon, généré, en attente, signé par une
      // seule partie) ; un contrat de vente / certificat déjà signé passe en
      // « Annulé » (trace conservée). Un contrat de réservation signé reste
      // valable (la réservation peut tenir).
      try {
        await _supa.from('documents_animaux')
            .delete()
            .eq('animal_id', widget.animalId!)
            .inFilter('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession'])
            .inFilter('statut', kStatutsContratNonFinalises);
        await _supa.from('documents_animaux')
            .update({'statut': 'annule'})
            .eq('animal_id', widget.animalId!)
            .inFilter('type', ['contrat_vente', 'certificat_cession'])
            .eq('statut', 'signe');
      } catch (e) {
        debugPrint('Révocation cession — contrats : $e');
      }
      if (uidAcq != null) {
        final acqProfileNotif = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', uidAcq).eq('is_main', true).maybeSingle();
        await _supa.from('notifications').insert({
          'uid':   uidAcq,
          'type':  'cession_revoquee',
          'title': '❌ Cession annulée — ${_nomCtrl.text}',
          'body':  'L\'éleveur a révoqué la cession de ${_nomCtrl.text}.',
          if (acqProfileNotif?['id'] != null) 'profile_id': acqProfileNotif!['id'],
          'data':  {'animalId': widget.animalId},
          'read':  false,
        });
      }
      await _refreshFromSupabase();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cession révoquée'), backgroundColor: Colors.orange));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _revokingCession = false);
    }
  }

  /// Condition de stérilisation d'un animal cédé : alimente l'onglet
  /// « Suivi » des cessions et ses rappels (J-30, J-7, J-48 h, J-0).
  Future<void> _editerSterilisation() async {
    var requise = _sterilRequise;
    var echeance = _sterilEcheance ?? (_dateNaissance != null
        ? DateTime(_dateNaissance!.year + 1, _dateNaissance!.month, _dateNaissance!.day)
        : DateTime.now().add(const Duration(days: 180)));
    var validee = _sterilValidee;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Condition de stérilisation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: requise, onChanged: (v) => setM(() => requise = v),
              title: const Text('Stérilisation exigée', style: TextStyle(fontFamily: 'Galey'))),
          if (requise) ...[
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: echeance, firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 3650)));
                if (d != null) setM(() => echeance = d);
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('Échéance : ${DateFormat('dd/MM/yyyy').format(echeance)}', style: const TextStyle(fontFamily: 'Galey')),
            ),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: validee, onChanged: (v) => setM(() => validee = v == true),
                title: const Text('Stérilisation confirmée', style: TextStyle(fontFamily: 'Galey'))),
          ],
          const SizedBox(height: 8),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey'))),
        ]),
      ))),
    );
    if (ok != true || widget.animalId == null) return;
    try {
      await _supa.from('animaux').update({
        'sterilisation_requise': requise,
        'sterilisation_echeance': requise ? DateFormat('yyyy-MM-dd').format(echeance) : null,
        'sterilisation_validee': requise && validee,
        'sterilisation_eleveur_uid': requise ? (widget.eleveurUidOverride ?? FirebaseAuth.instance.currentUser?.uid) : null,
        if (requise && User_Info.activeProfileId.isNotEmpty) 'sterilisation_eleveur_profile_id': User_Info.activeProfileId,
      }).eq('id', widget.animalId!);
      setState(() { _sterilRequise = requise; _sterilEcheance = requise ? echeance : null; _sterilValidee = requise && validee; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  static bool _statutSorti(String s) =>
      s == 'sorti' || s == 'decede' || s == 'adopte' || s == 'transfere';

  Future<void> _saveRegistre() async {
    if (widget.animalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enregistrez d\'abord la fiche complète', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _savingRegistre = true);
    try {
      final animalId = widget.animalId!;
      // Statut avant modification — pour détecter un passage « présent → sorti »
      // et le répercuter sur animaux_proprietes + registre_mouvements, que
      // cet éditeur laissait jusqu'ici désynchronisés (l'animal restait
      // « présent » dans Mes Animaux malgré un statut « sorti »).
      final before = await _supa.from('animaux')
          .select('statut, uid_eleveur, uid_proprietaire').eq('id', animalId).maybeSingle();
      final oldStatut = (before?['statut'] as String?) ?? 'present';
      final ownerUid = (before?['uid_eleveur'] ?? before?['uid_proprietaire'])?.toString() ?? _ownerUid;

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
        'is_retraite':          _isRetraite,
        'updated_at':           DateTime.now().toUtc().toIso8601String(),
      }).eq('id', animalId);

      // Sortie/décès déclarés directement dans le registre (sans passer par
      // la fiche de cession) : clôturer/rouvrir aussi la ligne
      // animaux_proprietes du propriétaire actuel (sinon l'animal reste
      // compté comme « présent » dans Mes Animaux malgré un statut
      // sorti/décédé) et journaliser la sortie dans registre_mouvements
      // (sinon le registre légal ne voit jamais ce mouvement).
      final devientSorti = _statutSorti(_statut) && !_statutSorti(oldStatut);
      final redevientPresent = !_statutSorti(_statut) && _statutSorti(oldStatut);
      final dateMvt = (_dateSortie ?? DateTime.now()).toIso8601String().split('T').first;

      if (devientSorti && ownerUid != null) {
        try {
          await _supa.from('animaux_proprietes')
              .update({'date_fin': dateMvt})
              .eq('animal_id', animalId).eq('uid_proprio', ownerUid)
              .isFilter('date_fin', null);
        } catch (_) {}
        try {
          final dejaSorti = await _supa.from('registre_mouvements')
              .select('id').eq('animal_id', animalId).eq('type', 'sortie').limit(1);
          if ((dejaSorti as List).isEmpty) {
            await _supa.from('registre_mouvements').insert({
              'animal_id':            animalId,
              'uid_eleveur':          ownerUid,
              'type':                 'sortie',
              'date_mouvement':       dateMvt,
              'motif':                _statut == 'decede' ? 'autre' : 'cession',
              if (User_Info.activeProfileId.isNotEmpty) 'eleveur_profile_id': User_Info.activeProfileId,
              if (_destinataireQualite.isNotEmpty) 'destinataire_qualite': _destinataireQualite,
              if (_destinataireNomCtrl.text.trim().isNotEmpty) 'destinataire_nom': _destinataireNomCtrl.text.trim(),
              if (_destinataireAdresseCtrl.text.trim().isNotEmpty) 'destinataire_adresse': _destinataireAdresseCtrl.text.trim(),
              if (_statut == 'decede' && _causeMort.isNotEmpty) 'cause_mort': _causeMort,
            });
            await _loadMouvements();
          }
        } catch (_) {}
      } else if (redevientPresent && ownerUid != null) {
        try {
          await _supa.from('animaux_proprietes')
              .update({'date_fin': null})
              .eq('animal_id', animalId).eq('uid_proprio', ownerUid)
              .not('date_fin', 'is', null);
        } catch (_) {}
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registre enregistré ✓', style: TextStyle(fontFamily: 'Galey'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
    } finally {
      if (mounted) setState(() => _savingRegistre = false);
    }
  }

  /// Raccourci depuis l'en-tête de la fiche (à côté de « Céder ») pour
  /// déclarer un décès sans passer par la section « Registre Entrée / Sortie ».
  Future<void> _declarerDeces() async {
    DateTime date = DateTime.now();
    String cause = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Déclarer le décès',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('L\'animal passera dans l\'onglet « Décédés » de Mes Animaux.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            const SizedBox(height: 14),
            const Text('Date du décès', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600, color: Color(0xFF6F767B))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
                if (picked != null) setSheet(() => date = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd/MM/yyyy').format(date),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Cause (optionnel)', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600, color: Color(0xFF6F767B))),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: cause.isEmpty ? null : cause,
              isExpanded: true,
              hint: const Text('Cause de la mort',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: ['maladie', 'accident', 'naturelle', 'inconnue']
                  .map((v) => DropdownMenuItem(value: v, child: Text(_IdentiteTab._causeMortLabel(v),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13))))
                  .toList(),
              onChanged: (v) => setSheet(() => cause = v ?? ''),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer le décès', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (widget.animalId == null) return;
    final animalId = widget.animalId!;
    final dateStr = date.toIso8601String().split('T').first;
    try {
      // Écriture directe et minimale (statut + date + cause) : on ne passe
      // pas par _saveRegistre pour éviter toute dépendance à l'état des
      // autres champs du registre — la seule chose qui doit se produire ici
      // est « cet animal est décédé », de façon fiable.
      await _supa.from('animaux').update({
        'statut':      'decede',
        'date_sortie': dateStr,
        'cause_mort':  cause,
        'updated_at':  DateTime.now().toUtc().toIso8601String(),
      }).eq('id', animalId);
      // Clôture (best-effort) de la ligne de propriété en cours, pour que
      // l'animal ne reste pas compté comme « présent » dans Mes Animaux.
      try {
        final ownerUid = _ownerUid ?? FirebaseAuth.instance.currentUser?.uid;
        if (ownerUid != null) {
          await _supa.from('animaux_proprietes')
              .update({'date_fin': dateStr})
              .eq('animal_id', animalId).eq('uid_proprio', ownerUid)
              .isFilter('date_fin', null);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _statut = 'decede';
        _dateSortie = date;
        _causeMort = cause;
      });
      await _refreshFromSupabase();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('☠️ Décès enregistré — l\'animal est dans l\'onglet Décédés',
            style: TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'enregistrement du décès : $e',
            style: const TextStyle(fontFamily: 'Galey'))),
      );
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
      initialDate: borner(_dateNaissance ?? now, premiereNaissanceAnimal(_espece), now),
      // Âge maximum plausible selon l'espèce, jamais dans le futur.
      firstDate: premiereNaissanceAnimal(_espece),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateNaissance = picked);
  }

  void _toggleAgeEstime(bool value) {
    setState(() {
      _ageEstime = value;
      if (!value) {
        _ageEstimeAnneesCtrl.clear();
      }
    });
  }

  void _applyAgeEstimeAnnees(String value) {
    final annees = int.tryParse(value.trim());
    if (annees == null || annees < 0) {
      setState(() => _dateNaissance = null);
      return;
    }
    final now = DateTime.now();
    setState(() => _dateNaissance = DateTime(now.year - annees, now.month, now.day));
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
            subtitle: const Text(kFormatsDocuments, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
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
          type: FileType.custom, allowedExtensions: kExtensionsDocuments);
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

  /// Actions rapides de la fiche (Partager / Réserver / Céder / Décéder…) —
  /// de vrais boutons libellés (icône + texte), comme sur le site, plutôt
  /// que des icônes seules pas toujours claires.
  List<_QuickAction> _ficheQuickActions() {
    if (widget.animalId == null || widget.readOnly) return [];
    final actions = <_QuickAction>[];
    if (!widget.vetMode) {
      // Lien + QR code en lecture seule, onglets au choix (carnet de santé
      // pour le vétérinaire, etc.) — remplace le lien « vétérinaire ».
      actions.add(_QuickAction(
        icon: Icons.ios_share,
        tooltip: 'Partager la fiche',
        iconOnly: true,
        color: const Color(0xFF5F9EAA),
        onTap: () => showPartageAnimalSheet(context, widget.animalId!,
            _nomCtrl.text.isEmpty ? 'Animal' : _nomCtrl.text),
      ));
    }
    // mes_animaux.dart passe TOUJOURS eleveurUidOverride (= _ownerUid de
    // l'élevage actif), y compris quand le viewer EST le gérant lui-même
    // (pas seulement en cogérance) — un `eleveurUidOverride == null` strict
    // masquait donc Céder/Décéder/Réserver pour tout le monde. On autorise
    // désormais le vrai gérant (son uid Firebase == _ownerUid) et un
    // cogérant actif ; seul un viewer tiers (employé...) reste exclu.
    final me = FirebaseAuth.instance.currentUser?.uid;
    final isOwnerOrCogerant = widget.eleveurUidOverride == null
        || me == _ownerUid
        || _isCogerantActif;
    if (!widget.vetMode && isOwnerOrCogerant) {
      // Auparavant `_statut == 'present'` : un animal dont le statut n'était
      // pas exactement « present » en base (vide/legacy) faisait disparaître
      // ce bouton alors que Céder/Décéder, eux, restaient visibles
      // (conditions par exclusion) — mêmes règles ici pour rester cohérent.
      // Association : publier l'annonce d'adoption depuis la fiche (animal
      // pré-rempli), sans repasser par Annonces.
      if (widget.isAssociation && (_statut == 'disponible' || _statut == 'en_soin')) {
        actions.add(_QuickAction(
          icon: Icons.campaign_outlined,
          label: "Annonce d'adoption",
          color: const Color(0xFF6E9E57),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => CreateAnnonceAssoPage(
              animalId: widget.animalId,
              initialAnimal: {
                'id': widget.animalId,
                'nom': _nomCtrl.text,
                'espece': _espece,
                'race': _raceCtrl.text,
                'sexe': _sexe,
                'date_naissance': _dateNaissance?.toIso8601String(),
                'age_estime': _ageEstime,
                'photo_url': _photoUrl,
              },
            ),
          )),
        ));
      }
      if (_statut != 'reserve' && _statut != 'sorti'
          && _statut != 'decede' && _statut != 'cession_en_cours') {
        actions.add(_QuickAction(
          icon: Icons.bookmark_add_outlined,
          label: 'Réserver',
          color: const Color(0xFFD97706),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ReservationSheet(
              animal: {
                'id': widget.animalId,
                // Profil émetteur des documents (certificat, contrat) :
                // association vs élevage — absent jusqu'ici, le certificat
                // d'un animal du refuge était rangé côté élevage.
                'is_association': widget.isAssociation,
                'nom': _nomCtrl.text.isNotEmpty ? _nomCtrl.text : null,
                'espece': _espece,
                'race': _raceCtrl.text.isNotEmpty ? _raceCtrl.text : null,
                'identification': _identCtrl.text.isNotEmpty ? _identCtrl.text : null,
                'date_naissance': _dateNaissance?.toIso8601String(),
              },
              uid: FirebaseAuth.instance.currentUser!.uid,
              onReserved: () {
                _refreshFromSupabase();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔖 Réservation enregistrée'), backgroundColor: Color(0xFFD97706)),
                );
              },
            ),
          ),
        ));
      }
      if (_statut == 'reserve') {
        actions.add(_QuickAction(
          icon: Icons.bookmark_remove_outlined,
          label: 'Annuler la réservation',
          color: const Color(0xFF6F767B),
          onTap: () async {
            if (_reservation == null) return;
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Annuler la réservation ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui, annuler')),
                ],
              ),
            );
            if (confirm != true) return;
            await _supa.from('reservations_animaux')
                .update({'statut': 'annulee', 'updated_at': DateTime.now().toUtc().toIso8601String()})
                .eq('id', _reservation!['id']);
            // Association : l'animal redevient « disponible » à l'adoption
            // (« present » est un statut d'élevage, inconnu côté refuge).
            await _supa.from('animaux').update({'statut': widget.isAssociation ? 'disponible' : 'present'})
                .eq('id', widget.animalId!);
            if (mounted) _refreshFromSupabase();
          },
        ));
      }
      if (_statut != 'decede' && _statut != 'cession_en_cours'
          && (_statut != 'sorti' || _uidAcquereur == FirebaseAuth.instance.currentUser?.uid)) {
        actions.add(_QuickAction(
          icon: Icons.handshake_outlined,
          label: widget.isAssociation ? 'Proposer à l\'adoption' : 'Céder',
          color: const Color(0xFFB45309),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CessionSheet(
              animal: {
                'id': widget.animalId,
                'is_association': widget.isAssociation,
                'nom': _nomCtrl.text.isNotEmpty ? _nomCtrl.text : null,
                'espece': _espece,
                'race': _raceCtrl.text.isNotEmpty ? _raceCtrl.text : null,
                'sexe': _sexe,
                'identification': _identCtrl.text.isNotEmpty ? _identCtrl.text : null,
                'date_naissance': _dateNaissance?.toIso8601String(),
              },
              uid: _ownerUid ?? FirebaseAuth.instance.currentUser!.uid,
              nomElevage: _nomElevage ?? '',
              isReCession: _isNewOwner && !User_Info.isElevage && !User_Info.isAssociation,
              reservation: _statut == 'reserve' ? _reservation : null,
              onCeded: () {
                _refreshFromSupabase();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✓ Cession enregistrée'), backgroundColor: Color(0xFF6E9E57)),
                );
              },
            ),
          ),
        ));
      }
      if (_statut != 'decede' && _statut != 'cession_en_cours' && _statut != 'sorti') {
        actions.add(_QuickAction(
          icon: Icons.sentiment_very_dissatisfied_outlined,
          label: 'Décéder',
          color: Colors.redAccent,
          onTap: _declarerDeces,
        ));
      }
    }
    return actions;
  }

  Widget _ficheQuickActionsRow(List<_QuickAction> actions) {
    return Container(
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              actions[i].build(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Fiches métier vétérinaire / ostéopathe (étape 5) ─────────────────────

  bool get _ficheSanteMetier =>
      widget.animalId != null && (User_Info.catPro == 'veterinaire' || User_Info.catPro == 'sante');

  /// Vue de l'onglet Santé du vétérinaire : carnet / reproduction / ostéo-kiné.
  String _santeVue = 'carnet';

  Widget _carnetVet() => _carnetPrive ? const _CarnetPriveTab() : _CarnetSanteTab(
        animalId: widget.animalId, vetMode: true, espece: _espece,
        canWrite: _canWriteHealth,
        writeRequested: _healthAccessStatut == 'write_requested',
        onRequestWrite: (!_canWriteHealth && _healthAccessGrantId != null && _healthAccessStatut != 'write_requested')
            ? _requestHealthWriteAccess : null,
      );

  /// Synthèse vétérinaire : rappel fait aujourd'hui — même vaccin, même
  /// intervalle, vétérinaire = moi.
  Future<void> _faireRappelVet(Map<String, dynamic> v) => showDialog(context: context, builder: (_) => _AddVaccinDialog(
        animalId: widget.animalId!, espece: _espece, source: 'veterinaire',
        vetId: FirebaseAuth.instance.currentUser?.uid, vetName: _nomVeterinaire(),
        prefillVaccin: v['vaccin']?.toString(), prefillCategorie: v['categorie']?.toString(), rappelDe: v));

  /// Identité complète + carnet de santé (lecture), ouverts depuis la Synthèse.
  void _ouvrirIdentite() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F6),
        appBar: AppBar(
          backgroundColor: _teal, foregroundColor: Colors.white,
          title: Text(_nomCtrl.text.isNotEmpty ? _nomCtrl.text : 'Animal', style: const TextStyle(fontFamily: 'Galey')),
          bottom: const TabBar(indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white60,
              tabs: [Tab(text: 'Identité'), Tab(text: 'Carnet de santé')]),
        ),
        body: TabBarView(children: [_IdentiteTab(this), _carnetVet()]),
      ),
    )));
  }

  List<Widget> _ongletsSanteMetier() {
    final morpho = MorphoTimelineTab(
      animalId: widget.animalId ?? '', espece: _espece,
      canWrite: _canWriteHealth,
      proProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
    );
    if (User_Info.catPro == 'sante') {
      return [
        SyntheseOsteoTab(animalId: widget.animalId!, onIdentite: _ouvrirIdentite, onSeances: () => _tabs.animateTo(1)),
        MorphoTimelineTab(
          animalId: widget.animalId ?? '', espece: _espece,
          canWrite: _canWriteHealth,
          proProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
          sansBilans: true,
        ),
        MorphoTimelineTab(
          animalId: widget.animalId ?? '', espece: _espece,
          canWrite: _canWriteHealth,
          proProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
          bilansSeulement: true,
        ),
        DocumentsSanteProTab(animalId: widget.animalId!, espece: _espece, osteo: true),
      ];
    }
    Widget seg(String v, String label) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600,
                color: _santeVue == v ? Colors.white : const Color(0xFF1F2A2E))),
            selected: _santeVue == v, showCheckmark: false,
            selectedColor: _teal, backgroundColor: const Color(0xFFF1F4F3), side: BorderSide.none,
            onSelected: (_) => setState(() => _santeVue = v),
          ),
        );
    return [
      SyntheseVetTab(animalId: widget.animalId!, onIdentite: _ouvrirIdentite,
          onFaireRappel: _canWriteHealth && !_carnetPrive ? _faireRappelVet : null,
          peutEcrire: _canWriteHealth && !_carnetPrive),
      _ConsultationsVetTab(animalId: widget.animalId, ownerUid: _ownerUid, animalNom: _nomCtrl.text, rdvId: widget.rdvId, espece: _espece),
      Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
            seg('carnet', 'Carnet de santé'), seg('repro', 'Reproduction'), seg('morpho', 'Ostéo / Kiné'),
          ]),
        ),
        Expanded(child: switch (_santeVue) {
          'repro' => _SuiviReproTab(animalId: widget.animalId, espece: _espece, sexe: _sexe, race: _raceCtrl.text, uidEleveur: _ownerUid, intervalleChaleursCustom: _intervalleChaleursCustom, readOnly: true, sterilise: _sterilise, dateNaissance: _dateNaissance),
          'morpho' => morpho,
          _ => _carnetVet(),
        }),
      ]),
      DocumentsSanteProTab(animalId: widget.animalId!, espece: _espece),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final quickActions = _ficheQuickActions();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        title: Text(widget.animalId != null ? (_nomCtrl.text.isNotEmpty ? _nomCtrl.text : 'Fiche animal') : 'Nouvel animal',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_identiteLectureSeule)
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
            // « Modifier » n'édite que l'identité : affiché seulement sur
            // l'onglet Identité (le premier), pour ne pas faire croire qu'il
            // modifie la santé ou l'alimentation.
            AnimatedBuilder(
              animation: _tabs,
              builder: (_, __) => _tabs.index != 0 ? const SizedBox.shrink() : TextButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white),
                label: const Text('Modifier', style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(quickActions.isEmpty ? 48 : 96),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (quickActions.isNotEmpty) _ficheQuickActionsRow(quickActions),
            TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: _green,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: (widget.vetMode && _ficheSanteMetier)
              ? (User_Info.catPro == 'veterinaire'
                  ? const [Tab(text: 'Synthèse'), Tab(text: 'Consultations'), Tab(text: 'Santé'), Tab(text: 'Documents')]
                  : const [Tab(text: 'Synthèse'), Tab(text: 'Séances'), Tab(text: 'Bilans'), Tab(text: 'Documents')])
              : widget.vetMode
              ? (User_Info.catPro == 'sante'
                  // Anatomie a fusionné dans Morphologie pour santé (pointage
                  // libre + compte-rendu structuré) — maréchal-ferrant garde
                  // l'ancien onglet Anatomie séparé, hors périmètre ici.
                  ? const [Tab(text: 'Identité'), Tab(text: 'Santé'), Tab(text: 'Repro'), Tab(text: 'Consultations')]
                  : User_Info.catPro == 'marechal_ferrant'
                  ? const [Tab(text: 'Identité'), Tab(text: 'Santé'), Tab(text: 'Repro'), Tab(text: 'Consultations'), Tab(text: 'Anatomie')]
                  : User_Info.catPro == 'veterinaire'
                      ? const [Tab(text: 'Identité'), Tab(text: 'Santé'), Tab(text: 'Repro'), Tab(text: 'Consultations'), Tab(text: 'Ostéo / Kiné')]
                      // Pet-sitter : pas de Consultations (domaine santé réservé
                      // aux pros de santé) mais Alimentation (essentiel pour
                      // nourrir l'animal pendant la garde).
                      : User_Info.catPro == 'garde'
                          ? const [Tab(text: 'Identité'), Tab(text: 'Santé'), Tab(text: 'Alimentation')]
                          // toilettage / photographe / taxi animalier…
                          : const [Tab(text: 'Identité'), Tab(text: 'Santé')])
              : widget.educationMode
                  ? const [Tab(text: 'Identité'), Tab(text: 'Santé'), Tab(text: 'Éducation')]
                  : widget.isAssociation
                      ? const [Tab(text: 'Identité'), Tab(text: 'Carnet de santé'), Tab(text: 'Alimentation'), Tab(text: 'Consultations'), Tab(text: 'Administratif')]
                      : (_cedeVerrouille
                          ? const [Tab(text: 'Identité'), Tab(text: 'Administratif')]
                          : (!User_Info.isElevage && !User_Info.isAssociation && !widget.showReproTab
                              ? const [Tab(text: 'Identité'), Tab(text: 'Carnet de santé'), Tab(text: 'Alimentation'), Tab(text: 'Consultations'), Tab(text: 'Administratif')]
                              // Repro reste à l'index 2 (liens directs : agenda chaleurs, notifications)
                              : const [Tab(text: 'Identité'), Tab(text: 'Carnet de santé'), Tab(text: 'Suivi repro'), Tab(text: 'Alimentation'), Tab(text: 'Consultations'), Tab(text: 'Administratif')])),
            ),
          ]),
        ),
      ),
      body: Column(children: [
        // Vues professionnelles : identité + propriétaire (appeler, message,
        // urgence, personnes autorisées) — widgets/animal/pro_animal_entete.dart.
        if ((widget.vetMode || widget.educationMode) && widget.animalId != null)
          ProAnimalEntete(animalId: widget.animalId!, catPro: User_Info.catPro),
        Expanded(child: TabBarView(
        controller: _tabs,
        children: (widget.vetMode && _ficheSanteMetier)
            ? _ongletsSanteMetier()
            : widget.vetMode
            ? [
                _IdentiteTab(this),
                _carnetVet(),
                // Le régime alimentaire n'a pas de mode lecture seule intégré
                // (_AlimentationTab n'a jamais été pensé pour un viewer externe) —
                // AbsorbPointer (posé DANS son ScrollView, cf. sa méthode
                // build()) bloque l'interaction sans bloquer le scroll, pour
                // qu'un pet-sitter puisse consulter sans pouvoir modifier le
                // plan du propriétaire.
                if (User_Info.catPro == 'garde')
                  _alimentationTab(lectureSeule: true),
                // Pros de santé : consultation seule — déclarer chaleurs,
                // saillies et gestations est réservé à l'éleveur. Pas de Repro
                // pour le pet-sitter, le toiletteur… (hors de leur métier).
                if (_isHealthPro)
                  _SuiviReproTab(animalId: widget.animalId, espece: _espece, sexe: _sexe, race: _raceCtrl.text, uidEleveur: _ownerUid, intervalleChaleursCustom: _intervalleChaleursCustom, readOnly: true, sterilise: _sterilise, dateNaissance: _dateNaissance),
                // Ostéo / kiné : leurs comptes rendus de séance (onglet unique
                // « Consultations » ci-dessous), pas le circuit vétérinaire.
                if (_isHealthPro && User_Info.catPro != 'sante')
                  _ConsultationsVetTab(animalId: widget.animalId, ownerUid: _ownerUid, animalNom: _nomCtrl.text, rdvId: widget.rdvId, espece: _espece),
                // Maréchal-ferrant garde l'ancien onglet Anatomie séparé
                // (pointage libre, hors périmètre de la fusion Morphologie) ;
                // santé a fusionné dans Morphologie ci-dessous.
                if (User_Info.catPro == 'marechal_ferrant')
                  AnatomieSeancesTab(animalId: widget.animalId ?? '', espece: _espece),
                if (_isMorphoPro)
                  MorphoTimelineTab(
                    animalId: widget.animalId ?? '', espece: _espece,
                    canWrite: _canWriteHealth,
                    proProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
                  ),
              ]
            : widget.educationMode
                ? [
                    _IdentiteTab(this),
                    // Un éducateur n'est pas un pro de santé — lecture seule du
                    // carnet, jamais d'écriture (vaccins, etc.), contrairement
                    // au défaut `canWrite = true` de _CarnetSanteTab.
                    _CarnetSanteTab(animalId: widget.animalId, espece: _espece, canWrite: false),
                    _EducationTab(animalId: widget.animalId, ownerUid: _ownerUid, animalNom: _nomCtrl.text),
                  ]
                : widget.isAssociation
                ? [
                    _IdentiteTab(this),
                    _CarnetSanteTab(animalId: widget.animalId, espece: _espece),
                    _alimentationTab(),
                    ConsultationsProprietaireTab(animalId: widget.animalId, espece: _espece),
                    // Contrats (réservation, adoption, cession) + certificats
                    // d'engagement.
                    _DocumentsTab(animalId: widget.animalId ?? ''),
                  ]
                : (_cedeVerrouille
                    ? [
                        _IdentiteTab(this),
                        _DocumentsTab(animalId: widget.animalId ?? ''),
                      ]
                    : (!User_Info.isElevage && !User_Info.isAssociation && !widget.showReproTab
                        ? [
                            _IdentiteTab(this),
                            _CarnetSanteTab(animalId: widget.animalId, espece: _espece),
                            _alimentationTab(),
                            ConsultationsProprietaireTab(animalId: widget.animalId, espece: _espece),
                            _DocumentsTab(animalId: widget.animalId ?? ''),
                          ]
                        : [
                            _IdentiteTab(this),
                            _CarnetSanteTab(animalId: widget.animalId, espece: _espece, canWrite: !_tabReadOnly('write_sante')),
                            _SuiviReproTab(animalId: widget.animalId, espece: _espece, sexe: _sexe, race: _raceCtrl.text, uidEleveur: _ownerUid, intervalleChaleursCustom: _intervalleChaleursCustom, readOnly: _tabReadOnly("write_repro"), sterilise: _sterilise, dateNaissance: _dateNaissance),
                            _alimentationTab(),
                            ConsultationsProprietaireTab(animalId: widget.animalId, espece: _espece, canWrite: !_tabReadOnly('write_sante')),
                            _DocumentsTab(animalId: widget.animalId ?? ''),
                          ])),
        )),
      ]),
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
    // AbsorbPointer DANS le ScrollView (pas autour) : posé à l'extérieur, il
    // bloquait aussi le geste de scroll lui-même — un animal cédé (lecture
    // seule) ne pouvait plus glisser sa fiche Identité, seuls les taps sur
    // les champs devaient être bloqués.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AbsorbPointer(
        absorbing: s._identiteLectureSeule,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s._cessionEnAttente && s._uidAcquereur == FirebaseAuth.instance.currentUser?.uid)
            ...[if (s._cessionEnCours != null) _CessionAcquereurBanner(cession: s._cessionEnCours!)]
          else if (s._cessionEnAttente)
            _CessionEnCoursBanner(
              cession: s._cessionEnCours,
              nomAcquereurFiche: s._destinataireNomCtrl.text,
              dateFiche: s._dateSortie,
              prixFiche: s._cessionPrix,
              contratSigne: s._cessionContratSigne,
              confirming: s._confirmingCession,
              revoking: s._revokingCession,
              onConfirm: s._confirmerCession,
              onSansSignature: s._validerCessionSansSignature,
              onRevoke: s._revoquerCession,
              onEdit: s._modifierCession,
            ),
          if (s._cessionEnAttente) const SizedBox(height: 12),
          if (s._statut == 'sorti') _CessionBanner(
            dateDepart: s._dateSortie,
            nomDestinataire: s._destinataireNomCtrl.text,
            prix: s._cessionPrix,
            notes: s._cessionNotes,
            contratUrl: s._cessionContratUrl,
            certificatUrl: s._cessionCertificatUrl,
            // Acquéreur sans compte : l'élevage peut l'inviter à récupérer la fiche.
            animalIdInvitation: !s._isNewOwner && (s._uidAcquereur ?? '').isEmpty ? s.widget.animalId : null,
            modifiable: !s._cedeVerrouille && !s._isNewOwner,
            sterilisation: s._isNewOwner ? null
                : !s._sterilRequise ? 'Aucune condition de stérilisation'
                : s._sterilValidee ? 'Stérilisation confirmée'
                : 'Stérilisation exigée${s._sterilEcheance != null ? ' avant le ${DateFormat('dd/MM/yyyy').format(s._sterilEcheance!)}' : ''}',
            onSterilisation: s._isNewOwner || s.widget.readOnly ? null : s._editerSterilisation,
          ),
          if (s._statut == 'sorti') const SizedBox(height: 12),
          // Association : statut visible et modifiable en un geste (avant :
          // caché dans « Registre Entrée / Sortie », replié, en mode édition).
          if (s.widget.isAssociation && s.widget.animalId != null && !s.widget.readOnly) ...[
            _StatutAssoBar(
              statut: s._statut,
              onChange: (v) async {
                s.setState(() {
                  s._statut = v;
                  // Sortie (adopté / transféré / décédé) : date du jour par
                  // défaut, modifiable ensuite dans « Registre Entrée / Sortie ».
                  if (_AnimalFichePageState._statutSorti(v)) s._dateSortie ??= DateTime.now();
                });
                // _saveRegistre (et non _save) : c'est lui qui inscrit la
                // sortie au registre et clôture la propriété — avec _save,
                // Loup était passé « adopté » sans sortie au registre.
                await s._saveRegistre();
              },
            ),
            const SizedBox(height: 12),
          ],
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
                Center(child: _photoAide()),
                const SizedBox(height: 12),
                _card([_field('Description', s._descriptionCtrl, maxLines: 4)]),
                const SizedBox(height: 16),
                _especeDropdown(context),
                if (s._espece == 'autre') ...[
                  const SizedBox(height: 10),
                  _field('Préciser l\'espèce', s._especeAutreCtrl),
                ],
                const SizedBox(height: 16),
                _card([
                  _field('Nom', s._nomCtrl, required: true),
                  _field('Nom de pedigree / affixe', s._nomPedigreeCtrl),
                  _hasBreeds ? _raceAutocomplete(context) : _field('Race', s._raceCtrl),
                  _field('Couleur / Robe', s._couleurCtrl),
                  _field('Couleur des yeux', s._couleurYeuxCtrl),
                  if (s._espece == 'cheval') ...[
                    _field('N° de transpondeur (puce)', s._identCtrl),
                  ] else ...[
                    _field(
                      _identLabel,
                      s._identCtrl,
                      inputType: s._espece == 'chien' || s._espece == 'chat'
                          ? TextInputType.number
                          : null,
                      inputFormatters: s._espece == 'chien' || s._espece == 'chat'
                          ? [FilteringTextInputFormatter.digitsOnly]
                          : null,
                    ),
                    _field('Passeport européen n°', s._passeportCtrl),
                  ],
                ]),
                if (s._espece == 'cheval') ...[
                  const SizedBox(height: 12),
                  _card([
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('Identification équidé (SIRE)',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                              fontSize: 14, color: Color(0xFF1F2A2E))),
                    ),
                    _field('N° SIRE', s._sireCtrl),
                    _field('N° carte d\'immatriculation', s._carteImmatCtrl),
                    _field('N° livret / document d\'identification', s._livretCtrl),
                  ]),
                ],
                const SizedBox(height: 12),
                _card([
                  _dateField(context),
                  _sexeField(),
                  _steriliseField(),
                  _retraiteField(),
                  if (_hasPoil) _poilField(),
                  _field(_tailleLabel, s._tailleCtrl, inputType: const TextInputType.numberWithOptions(decimal: true)),
                  if (_hasPoids) _field('Poids (kg)', s._poidsCtrl, inputType: const TextInputType.numberWithOptions(decimal: true)),
                ]),
                const SizedBox(height: 12),
                if (!s.widget.isAssociation) ...[
                  _card([_genealogieSection(context)]),
                  const SizedBox(height: 12),
                ],
                _contactsUrgenceSection(context),
                const SizedBox(height: 12),
                _personnesAutoriseesSection(context),
                const SizedBox(height: 12),
                _card([_field('Notes', s._notesCtrl, maxLines: 3)]),
              ],
            ),
          ),
          if (!s.widget.vetMode) ...[
            if (!s.widget.isAssociation) ...[
              const SizedBox(height: 12),
              _card([_pedigreeSection(context)]),
            ],
            const SizedBox(height: 12),
            _registreSection(context),
            const SizedBox(height: 12),
            _documentsSection(context),
            const SizedBox(height: 12),
            _alerteSection(context),
            if (s.widget.animalId != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AnimalTaggedPostsPage(
                      animalId: s.widget.animalId!,
                      animalName: s._nomCtrl.text.trim().isEmpty ? 'cet animal' : s._nomCtrl.text.trim(),
                    ),
                  )),
                  icon: const Icon(Icons.grid_view_rounded, size: 16),
                  label: const Text('Publications Pets Social',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0C5C6C),
                    side: const BorderSide(color: Color(0xFF0C5C6C)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
          if (s._hasPensionUpdates && !s.widget.vetMode) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PensionJournalPage(
                    animalId: s.widget.animalId,
                    animalNom: s._nomCtrl.text.isEmpty ? 'Animal' : s._nomCtrl.text,
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
          ],
          if (s._hasEducationRapports && !s.widget.vetMode) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => EducationRapportsPage(
                    animalId: s.widget.animalId,
                    animalNom: s._nomCtrl.text.isEmpty ? 'Animal' : s._nomCtrl.text,
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
          ],
          if (s._hasDevis && !s.widget.vetMode) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnimalDevisPage(
                    animalId: s.widget.animalId,
                    animalNom: s._nomCtrl.text.isEmpty ? 'Animal' : s._nomCtrl.text,
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
          ],
          if (s._pensionAcces.isNotEmpty && !s.widget.vetMode) ...[
            const SizedBox(height: 12),
            _pensionAccesSection(context),
          ],
          if (s._vetAcces.isNotEmpty && !s.widget.vetMode) ...[
            const SizedBox(height: 12),
            _vetAccesSection(context),
          ],
          if (s._gardeAcces.isNotEmpty && !s.widget.vetMode) ...[
            const SizedBox(height: 12),
            _gardeAccesSection(context),
          ],
          const SizedBox(height: 80),
        ],
      ),
      ),
    );
  }

  Widget _pensionAccesSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF7B5EA7).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7B5EA7).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.home_work_outlined, size: 16, color: Color(0xFF7B5EA7)),
          SizedBox(width: 6),
          Text('Accès pension actifs',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w700, color: Color(0xFF7B5EA7))),
        ]),
        const SizedBox(height: 10),
        for (final a in s._pensionAcces)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['pro_nom']?.toString() ?? 'Structure',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                        fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                if (a['created_at'] != null)
                  Text(() {
                    try {
                      return 'Depuis le ${DateFormat('dd/MM/yyyy').format(DateTime.parse(a['created_at'].toString()).toLocal())}';
                    } catch (_) { return ''; }
                  }(),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                        color: Color(0xFF9CA3AF))),
              ])),
              TextButton(
                onPressed: () => s._revokePensionAcces(
                    context, a['id'] as String, a['pro_nom']?.toString() ?? 'Structure'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Révoquer',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _vetAccesSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF26A69A).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26A69A).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.medical_services_outlined, size: 16, color: Color(0xFF26A69A)),
          SizedBox(width: 6),
          Text('Accès vétérinaires',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w700, color: Color(0xFF26A69A))),
        ]),
        const SizedBox(height: 10),
        for (final g in s._vetAcces)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dr. ${g['vet_nom'] ?? 'Vétérinaire'}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                        fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: g['status'] == 'demande' ? Colors.amber.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    g['status'] == 'demande' ? 'En attente' : 'Accès accordé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600,
                        color: g['status'] == 'demande' ? Colors.amber.shade800 : Colors.green.shade800),
                  ),
                ),
              ])),
              if (g['status'] == 'active')
                IconButton(
                  icon: const Icon(Icons.calendar_month_outlined, color: Color(0xFF26A69A), size: 22),
                  tooltip: 'Prendre RDV',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => RdvBookingPage(
                      proUid: g['vet_id']?.toString() ?? '',
                      proName: 'Dr. ${g['vet_nom'] ?? 'Vétérinaire'}',
                      categoryColor: const Color(0xFF26A69A),
                      isVet: true,
                      preselectedAnimalId: s.widget.animalId,
                    ),
                  )),
                ),
              if (g['status'] == 'demande')
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: Color(0xFF26A69A), size: 22),
                  tooltip: 'Approuver',
                  onPressed: () => s._approveVetAcces(g['id']?.toString() ?? ''),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _gardeAccesSection(BuildContext context) {
    const orange = Color(0xFFE08000);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: orange.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.pets_outlined, size: 16, color: orange),
          SizedBox(width: 6),
          Text('Accès pet-sitting',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w700, color: orange)),
        ]),
        const SizedBox(height: 10),
        for (final a in s._gardeAcces)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['pro_nom']?.toString() ?? 'Pet-sitter',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                        fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: a['statut'] == 'active_write' ? Colors.green.shade100
                        : a['statut'] == 'write_requested' ? Colors.amber.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    a['statut'] == 'active_write' ? 'Écriture autorisée'
                        : a['statut'] == 'write_requested' ? 'Demande d\'accès écriture'
                        : 'Lecture seule',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600,
                        color: a['statut'] == 'active_write' ? Colors.green.shade800
                            : a['statut'] == 'write_requested' ? Colors.amber.shade800
                            : Colors.grey.shade700),
                  ),
                ),
              ])),
              if (a['statut'] == 'write_requested')
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: orange, size: 22),
                  tooltip: 'Autoriser l\'écriture',
                  onPressed: () => s._approveGardeAcces(a['id']?.toString() ?? ''),
                ),
              TextButton(
                onPressed: () => s._revokeGardeAcces(
                    context, a['id'] as String, a['pro_nom']?.toString() ?? 'Pet-sitter'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Révoquer',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
      ]),
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
                        couleurYeux:    s._couleurYeuxCtrl.text,
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
            couleurYeux:    s._couleurYeuxCtrl.text,
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
                        color: const Color(0xFFEDF2F2),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.photo_camera_outlined, size: 32, color: Color(0xFF8B9FA1)),
                          if (s._editing) ...[
                            const SizedBox(height: 6),
                            const Text('Ajouter une photo', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
                          ],
                        ]),
                      ),
              ),
            ),
            if (s._editing && hasPhoto)
              Positioned(bottom: 6, right: 6,
                child: CircleAvatar(radius: 14, backgroundColor: const Color(0xFF0C5C6C),
                    child: const Icon(Icons.photo_camera_outlined, size: 14, color: Colors.white))),
          ],
        ),
      ),
    );
  }

  /// Formats réellement pris en charge par le sélecteur (recadrage + compression).
  Widget _photoAide() => s._editing
      ? Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('JPG, PNG ou HEIC. La photo est recadrée puis compressée automatiquement.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
        )
      : const SizedBox.shrink();

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

  Widget _racePereAutocomplete(BuildContext context) {
    final breeds = s._currentBreeds;
    return GestureDetector(
      onTap: () => _openBreedPicker(context, breeds, s._racePereCtrl, 'Race du père'),
      child: AbsorbPointer(
        child: TextFormField(
          controller: s._racePereCtrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Race du père',
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

  Widget _puceMatchBanner(BuildContext context, {
    required Map<String, dynamic>? match,
    required TextEditingController nomCtrl,
    required TextEditingController raceCtrl,
    required VoidCallback onClear,
    required Color color,
  }) {
    if (match == null || nomCtrl.text == (match['nom'] as String? ?? '')) return const SizedBox.shrink();
    final race = match['race'] as String?;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              '🔗 Puce trouvée en base : ${match['nom']}${race != null && race.isNotEmpty ? ' ($race)' : ''}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () {
              s.setState(() {
                nomCtrl.text = match['nom'] ?? '';
                raceCtrl.text = race ?? '';
              });
              onClear();
            },
            child: Text('Rattacher',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: color, fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline)),
          ),
        ]),
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

  Widget _field(String label, TextEditingController ctrl, {bool required = false, int maxLines = 1, TextInputType? inputType, List<TextInputFormatter>? inputFormatters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: inputType,
        inputFormatters: inputFormatters,
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
    // Option "Âge estimé" réservée aux associations : pour les chiens recueillis
    // dont la date de naissance exacte est inconnue.
    if (!s.widget.isAssociation) {
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!s._ageEstime)
            GestureDetector(
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
            )
          else
            TextFormField(
              controller: s._ageEstimeAnneesCtrl,
              keyboardType: TextInputType.number,
              onChanged: s._applyAgeEstimeAnnees,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Âge approximatif (années)',
                hintText: 'Ex : 3',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
          if (s._ageEstime && s._dateNaissance != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Estimation : né(e) vers ${s._dateNaissance!.year}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFB45309), fontStyle: FontStyle.italic),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Switch(
                  value: s._ageEstime,
                  activeColor: const Color(0xFF6E9E57),
                  // Désactivé : piste grise visible (blanc sur blanc avant).
                  inactiveThumbColor: Colors.grey.shade500,
                  inactiveTrackColor: Colors.grey.shade300,
                  onChanged: s._toggleAgeEstime,
                ),
                const Expanded(
                  child: Text(
                    'Date de naissance inconnue — indiquer un âge estimé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  ),
                ),
              ],
            ),
          ),
        ],
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

  Widget _retraiteField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('En retraite reproductive',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
            if (s._isRetraite)
              const Text('Arrêt de la reproduction',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFFB45309))),
          ]),
          Switch(
            value: s._isRetraite,
            activeColor: const Color(0xFFB45309),
            onChanged: (v) => s.setState(() => s._isRetraite = v),
          ),
        ],
      ),
    );
  }

  // Personnes autorisées à déposer / récupérer l'animal (pension, pet-sitter).
  // Visibles par les pros qui gardent l'animal (en-tête de leur fiche).
  Widget _personnesAutoriseesSection(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Expanded(child: Text('Personnes autorisées à déposer / récupérer',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 14, color: Color(0xFF1F2A2E)))),
          TextButton.icon(
            onPressed: () => s.setState(() => s._personnesAutorisees.add(_ContactUrgence())),
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF6E9E57)),
            label: const Text('Ajouter',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57))),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ]),
        const Text('Pour la pension ou le pet-sitter (en plus de vous-même).',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
        if (s._personnesAutorisees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucune personne', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
          ),
        const SizedBox(height: 8),
        ...s._personnesAutorisees.asMap().entries.map((e) {
          final i = e.key;
          final c = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [
                TextFormField(controller: c.nom, style: const TextStyle(fontFamily: 'Galey', fontSize: 13), decoration: deco('Nom')),
                const SizedBox(height: 6),
                TextFormField(controller: c.lien, style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                    decoration: deco('Lien (ex. conjoint, voisin)')),
                const SizedBox(height: 6),
                TextFormField(controller: c.tel, keyboardType: TextInputType.phone,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13), decoration: deco('Téléphone')),
              ])),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => s.setState(() {
                  s._personnesAutorisees[i].dispose();
                  s._personnesAutorisees.removeAt(i);
                }),
              ),
            ]),
          );
        }),
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
    final options = [
      'Court', 'Mi-long', 'Long', 'Frisé', 'Fil de soie', 'Ras',
      if (s._espece == 'chien') 'Dur',
    ];
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
      typeLabel: 'Inscription',
      // « Club de race (hors LOF) » : pedigree d'un club de race (races non
      // reconnues FCI, ex. Pomsky).
      typeOptions: ['LOF', 'Club de race (hors LOF)', 'Non-LOF'],
      clubLabel: 'Club de race (SCC, club de race…)',
      docLabel: 'Charger le pedigree (PDF/photo)',
    ),
    'chat': (
      sectionLabel: 'Pedigree',
      yesLabel: 'Avec pedigree',
      typeLabel: 'Inscription',
      typeOptions: ['LOOF', 'Club de race (hors LOOF)', 'Non-LOOF'],
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
                      // « Non-LOF » / « Non-LOOF » = sans pedigree.
                      child: Text(RegExp(r'^Non-LO').hasMatch(opt) ? 'Sans pedigree' : opt, textAlign: TextAlign.center,
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
              TextFormField(
                controller: s._pedigreeNumeroCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'N° de pedigree',
                  hintText: 'LOF n°123456, LOOF, SIRE…',
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
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final q = searchCtrl.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? animaux
                  : animaux.where((a) {
                      final nom  = (a['nom'] as String? ?? '').toLowerCase();
                      final race = (a['race'] as String? ?? '').toLowerCase();
                      return nom.contains(q) || race.contains(q);
                    }).toList();
              return Column(children: [
                const SizedBox(height: 10),
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 14),
                Text('Choisir la ${isMere ? 'mère' : 'père'}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Rechercher par nom…',
                      hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true, fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  const Expanded(child: Center(child: Text('Aucun animal trouvé', style: TextStyle(color: Colors.grey))))
                else
                  Expanded(
                    child: ListView.separated(
                      controller: sc,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (_, i) {
                        final a = filtered[i];
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
                            final race = a['race'] as String?;
                            final dn = a['date_naissance'] as String?;
                            final ped = (a['nom_pedigree'] as String?) ?? '';
                            s.setState(() {
                              if (isMere) {
                                if (dn != null && dn.isNotEmpty) s._dateNaissanceMere = DateTime.tryParse(dn);
                                if (race != null && race.isNotEmpty) s._raceMereCtrl.text = race;
                                if (ped.isNotEmpty) s._nomPedigreeMereCtrl.text = ped;
                              } else {
                                if (dn != null && dn.isNotEmpty) s._dateNaissancePere = DateTime.tryParse(dn);
                                if (race != null && race.isNotEmpty) s._racePereCtrl.text = race;
                                if (ped.isNotEmpty) s._nomPedigreePereCtrl.text = ped;
                              }
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
              ]);
            },
          ),
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
      _inlineField('Nom de pedigree du père (affixe)', s._nomPedigreePereCtrl),
      _puceMatchBanner(context,
        match: s._perePuceMatch, nomCtrl: s._nomPereCtrl, raceCtrl: s._racePereCtrl,
        onClear: () => s.setState(() => s._perePuceMatch = null), color: const Color(0xFF0C5C6C)),
      const SizedBox(height: 8),
      _hasBreeds ? _racePereAutocomplete(context) : _inlineField('Race du père', s._racePereCtrl),
      const SizedBox(height: 8),
      _dateRegistreField(context, 'Date de naissance du père', s._dateNaissancePere,
          (d) => s.setState(() => s._dateNaissancePere = d)),
      const SizedBox(height: 12),
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
      const SizedBox(height: 8),
      _inlineField('Nom de pedigree de la mère (affixe)', s._nomPedigreeMereCtrl),
      _puceMatchBanner(context,
        match: s._merePuceMatch, nomCtrl: s._nomMereCtrl, raceCtrl: s._raceMereCtrl,
        onClear: () => s.setState(() => s._merePuceMatch = null), color: const Color(0xFF6E9E57)),
      const SizedBox(height: 8),
      _hasBreeds ? _raceMereAutocomplete(context) : _inlineField('Race de la mère', s._raceMereCtrl),
      const SizedBox(height: 8),
      _dateRegistreField(context, 'Date de naissance de la mère', s._dateNaissanceMere,
          (d) => s.setState(() => s._dateNaissanceMere = d)),
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
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in s.widget.isAssociation
                  ? [
                      ('en_soin',    'En soin',   Colors.orange),
                      ('disponible', 'Disponible',Color(0xFF6E9E57)),
                      ('adopte',     'Adopté',    Color(0xFF0C5C6C)),
                      ('transfere',  'Transféré', Colors.blue),
                      ('decede',     'Décédé',    Colors.redAccent),
                    ]
                  : [
                      ('present', 'Présent', Color(0xFF6E9E57)),
                      ('sorti',   'Sorti',   Color(0xFF0C5C6C)),
                      ('decede',  'Décédé',  Colors.redAccent),
                    ])
                GestureDetector(
                  onTap: s._estEmploye ? null : () => s.setState(() => s._statut = e.$1),
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
              hint: Text(
                s.widget.isAssociation ? 'Origine de l\'animal' : 'Qualité du fournisseur',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
              decoration: _dropDeco(),
              items: (s.widget.isAssociation
                  ? ['abandon', 'confiscation', 'saisie', 'refuge', 'particulier', 'autre']
                  : ['naissance', 'eleveur', 'particulier', 'refuge', 'importation', 'autre'])
                .map((v) => DropdownMenuItem(value: v, child: Text(_qualiteLabel(v),
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
            _inlineField(s.widget.isAssociation ? 'Nom / Origine' : 'Nom du fournisseur / Origine', s._provenanceNomCtrl),
            const SizedBox(height: 8),
            _inlineField(s.widget.isAssociation ? 'Adresse / Localité' : 'Adresse du fournisseur', s._provenanceAdresseCtrl),
            if (!s.widget.isAssociation) ...[
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
            ],

            const SizedBox(height: 14),

            // ── Sortie / Mort ─────────────────────────────────────────────
            if (s.widget.isAssociation
                ? (s._statut == 'adopte' || s._statut == 'transfere' || s._statut == 'decede')
                : (s._statut == 'sorti' || s._statut == 'decede')) ...[
              Text(
                s._statut == 'decede' ? 'Décès'
                    : s._statut == 'adopte' ? 'Adoption'
                    : s._statut == 'transfere' ? 'Transfert'
                    : 'Sortie',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: FontWeight.w600, color: Color(0xFF6F767B))),
              const SizedBox(height: 8),
              _dateRegistreField(context,
                  s._statut == 'decede' ? 'Date de mort'
                  : s._statut == 'adopte' ? 'Date d\'adoption'
                  : s._statut == 'transfere' ? 'Date de transfert'
                  : 'Date de sortie',
                  s._dateSortie, (d) => s.setState(() => s._dateSortie = d)),
              if (s._statut == 'sorti' || s._statut == 'adopte' || s._statut == 'transfere') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: s._destinataireQualite.isEmpty ? null : s._destinataireQualite,
                  isExpanded: true,
                  hint: const Text('Qualité du destinataire', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                  decoration: _dropDeco(),
                  items: (s.widget.isAssociation
                      ? ['particulier', 'famille_accueil', 'association', 'autre']
                      : ['eleveur', 'particulier', 'refuge', 'autre'])
                    .map((v) => DropdownMenuItem(value: v, child: Text(_qualiteLabel(v),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13)))).toList(),
                  onChanged: (v) => s.setState(() => s._destinataireQualite = v ?? ''),
                ),
                const SizedBox(height: 8),
                _inlineField(s._statut == 'adopte' ? 'Nom de l\'adoptant' : 'Nom du destinataire', s._destinataireNomCtrl),
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

            // ── Historique des mouvements (plusieurs E/S par animal) ──────────
            const SizedBox(height: 20),
            Row(children: [
              const Text('Historique des mouvements',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.w600, color: Color(0xFF6F767B))),
              const Spacer(),
              GestureDetector(
                onTap: () => s._showAddMouvementSheet(context),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF6E9E57)),
                  SizedBox(width: 4),
                  Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            if (s._mouvements.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  s._isNewOwner
                      ? 'Votre entrée par cession sera ici une fois la migration appliquée'
                      : 'Aucun mouvement enregistré · utilisez "Ajouter" pour saillies, pensions…',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                ),
              )
            else
              for (final m in s._mouvements) _buildMouvementCard(m),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMouvementCard(Map<String, dynamic> m) {
    final isEntree = m['type'] == 'entree';
    final fmt = DateFormat('dd/MM/yyyy');
    final rawDate = m['date_mouvement'] as String?;
    final date = rawDate != null ? fmt.format(DateTime.parse(rawDate)) : '—';
    final motif = m['motif'] as String? ?? '';
    const motifLabels = <String, String>{
      'cession': 'Cession', 'saillie': 'Saillie', 'pension': 'Pension / Garde',
      'retraite': 'Retraite', 'adoption': 'Adoption', 'vente': 'Vente',
      'naissance': 'Naissance', 'achat': 'Achat / Acquisition',
      'retour_saillie': 'Retour de saillie', 'retour_pension': 'Retour de pension',
      'autre': 'Autre',
    };
    final motifLabel = motifLabels[motif] ?? motif;
    final tiersNom = isEntree
        ? (m['provenance_nom'] as String? ?? '')
        : (m['destinataire_nom'] as String? ?? '');
    final tiersQualite = isEntree
        ? _qualiteLabel(m['provenance_qualite'] as String? ?? '')
        : _qualiteLabel(m['destinataire_qualite'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isEntree ? const Color(0xFFF0F8EE) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isEntree ? const Color(0xFFA7C79A) : const Color(0xFFFFCC80)),
      ),
      child: Row(children: [
        Icon(isEntree ? Icons.arrow_downward : Icons.arrow_upward,
            size: 15,
            color: isEntree ? const Color(0xFF6E9E57) : Colors.orange.shade700),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(isEntree ? 'Entrée' : 'Sortie',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isEntree ? const Color(0xFF4A7A3A) : Colors.orange.shade800)),
            if (motifLabel.isNotEmpty) ...[
              const Text(' · ', style: TextStyle(
                  fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              Text(motifLabel, style: const TextStyle(
                  fontFamily: 'Galey', fontSize: 12, color: Colors.black87)),
            ],
            const Spacer(),
            Text(date, style: const TextStyle(
                fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
          ]),
          if (tiersQualite.isNotEmpty || tiersNom.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(
                [tiersQualite, tiersNom].where((v) => v.isNotEmpty).join(' — '),
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B)))),
        ])),
      ]),
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
    // Association
    'abandon': 'Abandon', 'confiscation': 'Confiscation judiciaire', 'saisie': 'Saisie par autorité',
    'famille_accueil': 'Famille d\'accueil', 'association': 'Association / Transfert',
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

Future<void> _openDoc(BuildContext context, String url) async {
  if (_isImageUrl(url)) {
    final String lien;
    try {
      lien = await lienDocument(url); // document privé → lien temporaire
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le document.")));
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ImageViewerPage(url: lien),
    ));
  } else {
    await ouvrirDocument(context, url);
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
                  ? ImagePrivee(url, width: 48, height: 48, fit: BoxFit.cover,
                      enErreur: (_) => const _DocIcon())
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

// ─── Banner cession ───────────────────────────────────────────────────────────

// ── Bannière acquéreur — cession en attente de finalisation ────────────────

class _CessionAcquereurBanner extends StatelessWidget {
  final Map<String, dynamic> cession;
  const _CessionAcquereurBanner({required this.cession});

  @override
  Widget build(BuildContext context) {
    final prix        = (cession['prix'] as num?)?.toDouble();
    final contratUrl  = cession['contrat_url']     as String?;
    final certifUrl   = cession['certificat_url']  as String?;
    final token       = cession['token']            as String?;
    final dateC       = cession['date_cession']     as String?;
    final statut      = cession['statut']           as String? ?? '';
    final hasSigned   = statut == 'signe_acquereur' || statut == 'confirme';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.transfer_within_a_station_outlined, color: Color(0xFF1D4ED8), size: 18),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Animal en cours de transfert vers vous',
                style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Galey',
                    fontSize: 13, color: Color(0xFF1D4ED8))),
          ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Vous êtes désigné acquéreur. Signez les documents et validez le paiement pour finaliser la cession.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF1E40AF)),
        ),
        if (dateC != null || (prix != null && prix > 0)) ...[
          const SizedBox(height: 6),
          if (dateC != null) _infoLine('Date prévue', dateC),
          if (prix != null && prix > 0) _infoLine('Prix', '${prix.toStringAsFixed(0)} €'),
        ],
        const SizedBox(height: 8),
        _docLine('Contrat', contratUrl),
        _docLine('Certificat de cession', certifUrl),
        const SizedBox(height: 10),
        if (!hasSigned && token != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ContratSignaturePage(cessionToken: token),
              )),
              icon: const Icon(Icons.draw_outlined, size: 16),
              label: const Text('Lire et signer',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        if (hasSigned) ...[
          Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFF6E9E57), size: 14),
            const SizedBox(width: 4),
            const Expanded(
              child: Text('Documents signés — en attente de confirmation du vendeur.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF065F46))),
            ),
          ]),
        ],
        const SizedBox(height: 4),
        const Text('La fiche est en lecture seule jusqu\'à confirmation.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
      ]),
    );
  }

  Widget _infoLine(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      Text('$label : ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _docLine(String label, String? url) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      Icon(url != null ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 13, color: url != null ? const Color(0xFF6E9E57) : Colors.orange),
      const SizedBox(width: 4),
      Text('$label : ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(url != null ? 'Fourni ✓' : 'Non fourni',
          style: TextStyle(fontSize: 11,
              color: url != null ? const Color(0xFF6E9E57) : Colors.orange,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Bannière cession en cours (côté cédant) ────────────────────────────────

class _CessionEnCoursBanner extends StatelessWidget {
  /// Ligne `cessions` (circuit app) ; null pour une cession lancée depuis le
  /// site, dont les infos sont alors celles de la fiche (`*Fiche`).
  final Map<String, dynamic>? cession;
  final String nomAcquereurFiche;
  final DateTime? dateFiche;
  final double? prixFiche;
  final bool contratSigne;
  final bool confirming;
  final bool revoking;
  final VoidCallback onConfirm;
  final VoidCallback onRevoke;
  /// Cession faite sur papier : finaliser sans signature électronique.
  final VoidCallback? onSansSignature;
  final VoidCallback onEdit;

  const _CessionEnCoursBanner({
    required this.cession, required this.nomAcquereurFiche,
    required this.dateFiche, required this.prixFiche,
    required this.contratSigne,
    required this.confirming, required this.revoking,
    required this.onConfirm, required this.onRevoke, required this.onEdit, this.onSansSignature,
  });

  @override
  Widget build(BuildContext context) {
    final c = cession ?? const <String, dynamic>{};
    final nomAcq  = (c['nom_acquereur'] as String?) ?? (nomAcquereurFiche.isNotEmpty ? nomAcquereurFiche : '…');
    final statut  = (c['statut'] as String?) ?? '';
    // Récap signé OU contrat de vente/certificat entièrement signé → l'éleveur
    // peut confirmer le transfert.
    final signedByAcq = statut == 'signe_acquereur' || statut == 'confirme' || contratSigne;
    final dateC   = (c['date_cession'] as String?)
        ?? (dateFiche == null ? null : '${dateFiche!.day.toString().padLeft(2, '0')}/${dateFiche!.month.toString().padLeft(2, '0')}/${dateFiche!.year}');
    final prix    = (c['prix'] as num?)?.toDouble() ?? prixFiche;
    final contratUrl = c['contrat_url'] as String?;
    final token   = c['token'] as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.pending_outlined, color: Color(0xFFFF8F00), size: 18),
          const SizedBox(width: 6),
          const Text('Cession en cours', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Galey', fontSize: 14, color: Color(0xFFFF8F00))),
        ]),
        const SizedBox(height: 8),
        _line('Acquéreur', nomAcq),
        if (dateC != null) _line('Date prévue', dateC),
        if (prix != null && prix > 0) _line('Prix', '${prix.toStringAsFixed(0)} €'),
        const SizedBox(height: 8),
        // Statut signatures
        _sigBadge(contratSigne ? 'Acquéreur' : 'Acquéreur (signature)', signedByAcq),
        _sigBadge(
          signedByAcq ? 'Éleveur — à confirmer' : 'Éleveur (en attente)',
          false, pending: true,
        ),
        if (token != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ContratSignaturePage(cessionToken: token),
            )),
            child: const Text('📄 Voir le récap / signer', style: TextStyle(fontSize: 11, color: Color(0xFF0C5C6C), decoration: TextDecoration.underline)),
          ),
        ] else if (contratUrl != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => ouvrirDocument(context, contratUrl),
            child: const Text('📄 Voir le contrat', style: TextStyle(fontSize: 11, color: Color(0xFF0C5C6C), decoration: TextDecoration.underline)),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: confirming || revoking ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Modifier la cession', style: TextStyle(fontSize: 12, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0C5C6C),
              side: const BorderSide(color: Color(0xFF0C5C6C)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Boutons
        Row(children: [
          if (cession != null) Expanded(
            child: ElevatedButton(
              onPressed: (confirming || !signedByAcq) ? null : onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: signedByAcq ? const Color(0xFF6E9E57) : Colors.grey.shade300,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: confirming
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(signedByAcq ? '✅ Confirmer la cession' : '⏳ En attente de signature',
                      style: const TextStyle(fontSize: 12, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ),
          if (cession != null) const SizedBox(width: 8),
          OutlinedButton(
            onPressed: revoking ? null : onRevoke,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            ),
            child: revoking
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2))
                : const Text('Annuler la cession', style: TextStyle(fontSize: 12, fontFamily: 'Galey')),
          ),
        ]),
        if (cession != null && !signedByAcq)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('La confirmation sera possible une fois l\'acquéreur signé.',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        if (onSansSignature != null && !(cession != null && signedByAcq))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: confirming || revoking ? null : onSansSignature,
              icon: const Icon(Icons.task_alt, size: 16),
              label: const Text('Valider sans signature (cession faite sur papier)',
                  style: TextStyle(fontSize: 12, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF6E9E57), padding: EdgeInsets.zero),
            ),
          ),
      ]),
    );
  }

  Widget _line(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      Text('$label : ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _sigBadge(String label, bool signed, {bool pending = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      Icon(signed ? Icons.check_circle : (pending ? Icons.radio_button_unchecked : Icons.schedule),
          size: 14, color: signed ? const Color(0xFF6E9E57) : Colors.grey),
      const SizedBox(width: 4),
      Text('$label : ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(signed ? 'Signé' : 'En attente', style: TextStyle(fontSize: 11, color: signed ? const Color(0xFF6E9E57) : Colors.orange, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _CessionBanner extends StatelessWidget {
  final DateTime? dateDepart;
  final String nomDestinataire;
  final double? prix;
  final String? notes;
  final String? contratUrl;
  final String? certificatUrl;
  /// Renseigné quand l'acquéreur n'a pas de compte : bouton d'invitation.
  final String? animalIdInvitation;
  /// Fiche encore modifiable par l'élevage (acquéreur sans compte).
  final bool modifiable;
  /// Condition de stérilisation (libellé) et son édition.
  final String? sterilisation;
  final VoidCallback? onSterilisation;

  const _CessionBanner({
    this.dateDepart, required this.nomDestinataire, this.prix,
    this.notes, this.contratUrl, this.certificatUrl, this.animalIdInvitation,
    this.modifiable = false, this.sterilisation, this.onSterilisation,
  });

  /// Invitation de l'acquéreur : WhatsApp, SMS, e-mail, partage ou copie.
  Future<void> _inviter(BuildContext context) async {
    try {
      final inv = await inviterAcquereur(animalIdInvitation!);
      if (!context.mounted) return;
      final msg = inv.message;
      await showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          Widget canal(IconData ic, String t, Future<void> Function() f) => ListTile(
                leading: Icon(ic, color: const Color(0xFF1565C0)),
                title: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                onTap: () async { Navigator.pop(ctx); await f(); },
              );
          return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text("Inviter ${'${inv.prenom} ${inv.nom}'.trim().isNotEmpty ? '${inv.prenom} ${inv.nom}'.trim() : "l'acquéreur"} à récupérer la fiche",
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            canal(Icons.chat_outlined, 'WhatsApp', () async {
              final t = inv.telInternational;
              await launchUrl(Uri.parse(t != null ? 'https://wa.me/$t?text=${Uri.encodeComponent(msg)}' : 'https://wa.me/?text=${Uri.encodeComponent(msg)}'),
                  mode: LaunchMode.externalApplication);
            }),
            canal(Icons.sms_outlined, 'SMS', () async {
              await launchUrl(Uri.parse('sms:${(inv.tel ?? '').replaceAll(' ', '')}?body=${Uri.encodeComponent(msg)}'));
            }),
            canal(Icons.email_outlined, (inv.email ?? '').isNotEmpty ? 'E-mail (${inv.email})' : 'E-mail', () async {
              if ((inv.email ?? '').isNotEmpty) {
                final ok = await inv.envoyerEmail();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'E-mail envoyé à ${inv.email}.' : "L'e-mail n'a pas pu être envoyé.")));
                }
              } else {
                await launchUrl(Uri.parse('mailto:?subject=${Uri.encodeComponent('${inv.animalNom} vous attend sur PetsMatch')}&body=${Uri.encodeComponent(msg)}'));
              }
            }),
            canal(Icons.ios_share_rounded, 'Partager…', () async => Share.share(msg)),
            canal(Icons.copy_outlined, 'Copier le message', () async {
              await Clipboard.setData(ClipboardData(text: msg));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copié.')));
            }),
          ]));
        },
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = dateDepart != null
        ? '${dateDepart!.day.toString().padLeft(2, '0')}/${dateDepart!.month.toString().padLeft(2, '0')}/${dateDepart!.year}'
        : '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.handshake_outlined, color: Color(0xFF1565C0), size: 18),
          SizedBox(width: 6),
          Text('Animal cédé',
              style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1565C0), fontFamily: 'Galey', fontSize: 13)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(modifiable
              ? "Acquéreur sans compte PetsMatch : vous gardez la fiche en écriture jusqu'à ce qu'il la récupère."
              : 'Fiche gérée par son nouveau propriétaire : lecture seule.',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Color(0xFF1565C0))),
        ),
        const SizedBox(height: 8),
        if (nomDestinataire.isNotEmpty)
          _CessionLine(Icons.person_outline, 'Acquéreur', nomDestinataire),
        _CessionLine(Icons.calendar_today_outlined, 'Date de départ', dateStr),
        if (prix != null)
          _CessionLine(Icons.euro_outlined, 'Prix', '${prix!.toStringAsFixed(prix! % 1 == 0 ? 0 : 2)} €'),
        if (notes != null && notes!.isNotEmpty)
          _CessionLine(Icons.notes_outlined, 'Notes', notes!),
        if (contratUrl != null || certificatUrl != null) ...[
          const Divider(height: 14),
          const Text('Documents', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (certificatUrl != null)
            _DocLink('📜 Certificat de cession', certificatUrl!),
          if (contratUrl != null)
            _DocLink('🤝 Contrat de vente', contratUrl!),
        ],
        if (sterilisation != null) ...[
          const Divider(height: 14),
          Row(children: [
            const Icon(Icons.health_and_safety_outlined, size: 14, color: Color(0xFF1565C0)),
            const SizedBox(width: 6),
            Expanded(child: Text(sterilisation!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)))),
            if (onSterilisation != null)
              TextButton(onPressed: onSterilisation, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
          ]),
        ],
        if (animalIdInvitation != null) ...[
          const Divider(height: 14),
          TextButton.icon(
            onPressed: () => _inviter(context),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: const Color(0xFF1565C0)),
            icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
            label: const Text("Inviter l'acquéreur à récupérer la fiche", style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

class _CessionLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _CessionLine(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(icon, size: 14, color: const Color(0xFF1565C0)),
      const SizedBox(width: 6),
      Text('$label : ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Flexible(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)))),
    ]),
  );
}

class _DocLink extends StatelessWidget {
  final String label;
  final String url;
  const _DocLink(this.label, this.url);
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      // Ouverture du document via url_launcher
      final uri = Uri.tryParse(url);
      if (uri != null) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ouverture : $label'), backgroundColor: const Color(0xFF0C5C6C)));
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        const Icon(Icons.open_in_new, size: 13, color: Color(0xFF1565C0)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0), decoration: TextDecoration.underline)),
      ]),
    ),
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
  final String? race;
  final String? uidEleveur;
  final int? intervalleChaleursCustom;
  final bool readOnly;
  final bool sterilise;
  final DateTime? dateNaissance;
  const _SuiviReproTab({this.animalId, required this.espece, required this.sexe, this.race, this.uidEleveur, this.intervalleChaleursCustom, this.readOnly = false, this.sterilise = false, this.dateNaissance});

  @override
  Widget build(BuildContext context) {
    if (animalId == null) return const _SaveFirstPrompt(message: 'Enregistrez d\'abord la fiche pour accéder au suivi reproducteur.');

    final isMale = sexe == 'male';
    final hasGen = especeHasGenetics(espece);

    final tabs = <Tab>[
      if (!isMale) const Tab(text: 'Chaleurs'),
      const Tab(text: 'Saillies'),
      if (!isMale) const Tab(text: 'Gestations'),
      if (hasGen) const Tab(text: 'Génétique'),
    ];

    final views = <Widget>[
      if (!isMale)
        _ChaleursTab(animalId: animalId!, espece: espece, race: race, uidEleveur: uidEleveur,
            intervalleCustom: intervalleChaleursCustom, readOnly: readOnly,
            sterilise: sterilise, dateNaissance: dateNaissance),
      _ReproList(
        animalId: animalId!, collection: 'saillies', readOnly: readOnly,
        addBuilder: (ctx) => _AddSaillieDialog(animalId: animalId!, espece: espece, sexeAnimal: sexe),
        editBuilder: (ctx, d) => _AddSaillieDialog(animalId: animalId!, espece: espece, sexeAnimal: sexe, existing: d),
      ),
      if (!isMale)
        _ReproList(
          animalId: animalId!, collection: 'gestations', readOnly: readOnly,
          addBuilder: (ctx) => _AddGestationDialog(animalId: animalId!, espece: espece),
          editBuilder: (ctx, d) => _AddGestationDialog(animalId: animalId!, espece: espece, existing: d),
        ),
      if (hasGen)
        ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          _GenetiqueSection(animalId: animalId!, espece: espece, readOnly: readOnly, dateNaissance: dateNaissance),
          _BilanReproCard(animalId: animalId!, espece: espece, readOnly: readOnly),
        ]),
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
  final bool readOnly;
  const _ReproList({required this.animalId, required this.collection, required this.addBuilder, this.editBuilder, this.readOnly = false});
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
      final supa = Supabase.instance.client;
      await supa.from(widget.collection).delete().eq('id', id);
      // La gestation supprimée peut avoir un événement "Mise-bas prévue" lié
      // dans l'agenda (agenda_events.gestation_id) : sans ce nettoyage, il
      // reste orphelin et continue de s'afficher indéfiniment.
      if (widget.collection == 'gestations') {
        try {
          await supa.from('agenda_events').delete().eq('gestation_id', id);
        } catch (_) {}
      }
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
      // Événement agenda = date de mise-bas la plus probable : milieu de la
      // fenêtre [date_prevue → date_prevue_fin] si elle existe, sinon date_prevue.
      final dp  = DateTime.tryParse(gest?['date_prevue']?.toString() ?? '');
      final dpf = DateTime.tryParse(gest?['date_prevue_fin']?.toString() ?? '');
      final datePrevue = dp == null
          ? null
          : (dpf != null && !dpf.isAtSameMomentAs(dp)
                ? DateTime.fromMillisecondsSinceEpoch(
                    (dp.millisecondsSinceEpoch + dpf.millisecondsSinceEpoch) ~/ 2)
                  .toIso8601String()
                : (gest?['date_prevue'] as String?));
      final uid   = FirebaseAuth.instance.currentUser?.uid;

      if (datePrevue != null && uid != null) {
        String animalNom = 'animal';
        String? animalEspece;
        try {
          final a = await supa.from('animaux').select('nom, espece').eq('id', widget.animalId).maybeSingle();
          if (a != null) {
            animalNom    = (a['nom']    as String?)?.isNotEmpty == true ? a['nom']    as String : 'animal';
            animalEspece = a['espece'] as String?;
          }
        } catch (_) {}

        // Protocoles automatiques gestation
        try {
          await PlanningService.triggerAutoProtocoles(
            uid: uid,
            declencheur: 'gestation',
            animalId: widget.animalId,
            dateEvenement: DateTime.tryParse(datePrevue) ?? DateTime.now(),
            espece: animalEspece,
          );
        } catch (_) {}

        final existing = await supa.from('agenda_events')
            .select('id').eq('gestation_id', id).maybeSingle();
        // Stocke à 08h00 UTC pour affichage correct en France (évite minuit UTC = 02h00 local)
        final datePrevueAt8 = datePrevue != null
            ? DateTime(DateTime.parse(datePrevue).year, DateTime.parse(datePrevue).month,
                       DateTime.parse(datePrevue).day, 8, 0).toUtc().toIso8601String()
            : null;
        final eventData = {
          'uid':            uid,
          'titre':          'Mise-bas prévue — $animalNom',
          'type':           'mise_bas',
          'date_debut':     datePrevueAt8 ?? datePrevue,
          'animal_id':      widget.animalId,
          'notes':          'Gestation confirmée',
          'gestation_id':   id,
          'pro_profile_id': await profilPourAnimal(widget.animalId),
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
            content: Text('Gestation confirmée · agenda mis à jour'),
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
      floatingActionButton: widget.readOnly ? null : FloatingActionButton.small(
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
                      readOnly: widget.readOnly,
                      onDelete: () => _delete(id),
                      onEdit: widget.readOnly || widget.editBuilder == null ? null : () async {
                        await showDialog(context: context, builder: (ctx) => widget.editBuilder!(ctx, d));
                        _refresh();
                      },
                      onConfirmGestation: (isGestation && !alreadyConfirmed && !widget.readOnly)
                          ? () => _confirmGestation(id)
                          : null,
                    );
                  },
                ),
    );
  }
}

// ─── Onglet Carnet Santé ──────────────────────────────────────────────────────

/// Carnet d'un animal dont la fiche a été créée par un autre professionnel :
/// privé tant que le propriétaire ne l'a pas partagé (secret professionnel).
class _CarnetPriveTab extends StatelessWidget {
  const _CarnetPriveTab();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Carnet de santé privé', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 6),
            Text('La fiche de cet animal a été créée par un autre professionnel. Vous voyez son identité et vos '
                'propres documents ; son carnet et les documents de l’autre professionnel restent privés tant que '
                'le propriétaire ne les a pas partagés.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Colors.grey.shade600, height: 1.4)),
          ]),
        ),
      );
}

class _CarnetSanteTab extends StatelessWidget {
  final String? animalId;
  final bool vetMode;
  final String espece;
  // Lecture seule par défaut pour un viewer vetMode sans droit d'écriture
  // santé (ex. pet-sitter) — cf. AnimalFichePage._canWriteHealth.
  final bool canWrite;
  final bool writeRequested;
  final VoidCallback? onRequestWrite;
  const _CarnetSanteTab({this.animalId, this.vetMode = false, required this.espece,
      this.canWrite = true, this.writeRequested = false, this.onRequestWrite});

  static const _cats = [
    // Couleurs fonctionnelles (rubrique + « Ajouter » + rappels agenda) :
    // référence unique, utils/sante_couleurs.dart.
    (key: 'vaccinations',     label: 'Vaccinations',          icon: Icons.vaccines_outlined,             color: SanteCouleurs.vaccinations),
    (key: 'vermifuges',       label: 'Vermifuges',            icon: Icons.bug_report_outlined,           color: SanteCouleurs.vermifuges),
    (key: 'antiparasitaires', label: 'Antiparasitaires',      icon: Icons.pest_control_outlined,         color: SanteCouleurs.antiparasitaires),
    (key: 'traitements',      label: 'Traitements',           icon: Icons.medication_outlined,           color: SanteCouleurs.traitements),
    (key: 'chirurgies',       label: 'Chirurgie / Hospitalisation', icon: Icons.local_hospital_outlined, color: SanteCouleurs.chirurgies),
    (key: 'allergies',        label: 'Allergies',             icon: Icons.warning_amber_outlined,        color: SanteCouleurs.allergies),
    (key: 'poids',            label: 'Courbe de poids',       icon: Icons.monitor_weight_outlined,       color: SanteCouleurs.poids),
    (key: 'visites',          label: 'Visites vétérinaires',  icon: Icons.medical_services_outlined,     color: SanteCouleurs.visites),
    (key: 'radios',           label: 'Radios / Examens',       icon: Icons.image_search_outlined,          color: Color(0xFF0284C7)),
  ];
  // Les 7 rubriques du carnet, puis le suivi vétérinaire.
  @override
  Widget build(BuildContext context) {
    if (animalId == null) return const _SaveFirstPrompt(message: 'Enregistrez d\'abord la fiche pour accéder au carnet de santé.');
    Widget panneau(List<Widget> lignes) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < lignes.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              lignes[i],
            ],
          ]),
        );
    // Radios / examens : onglet Consultations côté propriétaire (actes du
    // vétérinaire, miroir du site) ; le vétérinaire les garde dans le carnet.
    // Visites : doublon des consultations (comptes rendus) pour le vétérinaire.
    // Visites vétérinaires : plus dans le carnet — les consultations (comptes
    // rendus) sont dans l'onglet Consultations.
    final cats = [for (final c in _cats) if (c.key != 'visites' && (vetMode || c.key != 'radios')) c];
    Widget ligne(int i) {
        final cat = cats[i];
        return _SanteTile(
          animalId: animalId!,
          collection: cat.key,
          label: cat.label,
          icon: cat.icon,
          color: cat.color,
          vetMode: vetMode,
          espece: espece,
          canWrite: canWrite,
          writeRequested: writeRequested,
          onRequestWrite: onRequestWrite,
        );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        panneau([
          for (var i = 0; i < cats.length; i++) ligne(i),
        ]),
      ],
    );
  }
}

class _SanteTile extends StatelessWidget {
  final String animalId;
  final String collection;
  final String label;
  final IconData icon;
  final Color color;
  final bool vetMode;
  final String? espece;
  final bool canWrite;
  final bool writeRequested;
  final VoidCallback? onRequestWrite;
  const _SanteTile({required this.animalId, required this.collection,
      required this.label, required this.icon, required this.color, this.vetMode = false, this.espece,
      this.canWrite = true, this.writeRequested = false, this.onRequestWrite});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from(collection).stream(primaryKey: ['id']).eq('animal_id', animalId),
      builder: (ctx, snap) {
        final count = snap.data?.length ?? 0;
        final page = SanteDetailPage(
          animalId: animalId, collection: collection,
          label: label, icon: icon, color: color, vetMode: vetMode, espece: espece,
          canWrite: canWrite, writeRequested: writeRequested, onRequestWrite: onRequestWrite,
        );
        void ouvrir() => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
        return InkWell(
          onTap: ouvrir,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 14),
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A2E))),
                    const SizedBox(height: 2),
                    Text('$count enregistrement${count > 1 ? 's' : ''}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
                  ]),
                )),
                // « + Ajouter » : ouvre le formulaire, sans ouvrir la liste
                if (canWrite)
                  TextButton(
                    onPressed: () async {
                      if (collection == 'poids') { ouvrir(); return; }
                      await showDialog(context: context, builder: page._dialogFor);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('+ Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                SizedBox(width: 40, height: 44,
                    child: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class SanteDetailPage extends StatelessWidget {
  final String animalId;
  final String collection;
  final String label;
  final IconData icon;
  final Color color;
  final bool vetMode;
  final String? espece;
  final bool canWrite;
  final bool writeRequested;
  final VoidCallback? onRequestWrite;
  const SanteDetailPage({super.key, required this.animalId, required this.collection,
      required this.label, required this.icon, required this.color, this.vetMode = false, this.espece,
      this.canWrite = true, this.writeRequested = false, this.onRequestWrite});

  Widget _dialogFor(BuildContext ctx) {
    final src   = vetMode ? 'veterinaire' : 'owner';
    final vid   = vetMode ? FirebaseAuth.instance.currentUser?.uid : null;
    final vname = vetMode ? _nomVeterinaire() : null;
    switch (collection) {
      case 'vaccinations':     return _AddVaccinDialog(animalId: animalId, espece: espece, source: src, vetId: vid, vetName: vname);
      case 'vermifuges':       return AddVermifugeDialog(animalId: animalId, source: src, vetId: vid, vetName: vname);
      case 'antiparasitaires': return AddAntiparasitaireDialog(animalId: animalId, source: src, vetId: vid, vetName: vname);
      case 'traitements':      return _AddTraitementDialog(animalId: animalId, source: src, vetId: vid, vetName: vname);
      case 'chirurgies':       return AddChirurgieDialog(animalId: animalId, source: src, vetId: vid, vetName: vname);
      case 'allergies':        return _AddAllergieDialog(animalId: animalId, source: src, vetId: vid, vetName: vname);
      case 'visites':          return _AddVisiteDialog(animalId: animalId, source: src, vetId: vid, vetName: vname);
      case 'radios':           return _AddRadioDialog(animalId: animalId, vetId: vid, vetName: vname);
      default:                 return _AddVaccinDialog(animalId: animalId, espece: espece, source: src, vetId: vid, vetName: vname);
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
          : _SanteList(animalId: animalId, collection: collection, icon: icon, addBuilder: _dialogFor, vetMode: vetMode, espece: espece,
              canWrite: canWrite, writeRequested: writeRequested, onRequestWrite: onRequestWrite),
    );
  }
}

class _SanteList extends StatefulWidget {
  final String animalId;
  final String collection;
  final IconData icon;
  final Widget Function(BuildContext) addBuilder;
  final bool vetMode;
  final String? espece;
  final bool canWrite;
  final bool writeRequested;
  final VoidCallback? onRequestWrite;
  const _SanteList({required this.animalId, required this.collection, required this.icon, required this.addBuilder, this.vetMode = false, this.espece,
      this.canWrite = true, this.writeRequested = false, this.onRequestWrite});
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
    if (widget.collection == 'chirurgies')       return data['intitule'] ?? (data['type'] == 'hospitalisation' ? 'Hospitalisation' : 'Chirurgie');
    if (widget.collection == 'allergies')        return data['description'] ?? data['type'] ?? 'Allergie';
    if (widget.collection == 'radios')           return data['titre'] ?? 'Radio / Examen';
    return data['motif'] ?? 'Visite';
  }

  Future<void> _delete(String id) async {
    final d = _data.firstWhere((x) => x['id']?.toString() == id, orElse: () => <String, dynamic>{});
    if (!await confirmerSuppressionSante(context, widget.collection, nom: d.isEmpty ? null : _title(d))) return;
    try {
      await Supabase.instance.client.from(widget.collection).delete().eq('id', id);
      // Sans ça, la ligne du registre sanitaire liee a cet acte restait
      // orpheline indefiniment apres suppression.
      await RegistreHelper.deleteActe(sourceTable: widget.collection, sourceId: id);
      if (mounted) setState(() => _data.removeWhere((d) => d['id']?.toString() == id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  void _edit(Map<String, dynamic> data) async {
    // Vaccins, vermifuges, antiparasitaires, traitements : même formulaire
    // qu'à la création (dates, fréquence, prises, étapes…).
    Widget? dialogue;
    switch (widget.collection) {
      case 'vaccinations':
        dialogue = _AddVaccinDialog(animalId: widget.animalId, espece: widget.espece, existant: data);
      case 'vermifuges':
        dialogue = AddVermifugeDialog(animalId: widget.animalId, existant: data);
      case 'antiparasitaires':
        dialogue = AddAntiparasitaireDialog(animalId: widget.animalId, existant: data);
      case 'traitements':
        var groupe = [data];
        final gid = data['groupe_id']?.toString();
        if (gid != null && gid.isNotEmpty) {
          try {
            final rows = await Supabase.instance.client.from('traitements').select()
                .eq('animal_id', widget.animalId).eq('groupe_id', gid);
            groupe = List<Map<String, dynamic>>.from(rows as List)
              ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
          } catch (_) {}
        }
        dialogue = _AddTraitementDialog(animalId: widget.animalId, groupe: groupe);
    }
    if (dialogue != null) {
      if (!mounted) return;
      final d = dialogue;
      await showDialog(context: context, builder: (_) => d);
      _refresh();
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _QuickEditSheet(data: data, collection: widget.collection, espece: widget.espece, onSaved: _refresh),
    );
  }

  // Pré-remplit le dialog d'ajout avec les mêmes infos que l'enregistrement
  // existant (vaccin/produit/type/fréquence...) — pour saisir un
  // renouvellement il ne reste alors qu'à changer la date.
  void _addRappel(Map<String, dynamic> data) async {
    // "1 mois" / "2 semaines" / "10 jours" -> (valeur, unité), best-effort.
    final freqMatch = RegExp(r'^(\d+)\s*(jour|semaine|mois)', caseSensitive: false)
        .firstMatch((data['frequence'] as String?) ?? '');
    final freqValeur = freqMatch?.group(1);
    final freqUnite = freqMatch?.group(2)?.toLowerCase();
    final src = widget.vetMode ? 'veterinaire' : 'owner';
    final vid = widget.vetMode ? FirebaseAuth.instance.currentUser?.uid : null;
    final vname = widget.vetMode ? _nomVeterinaire() : null;

    await showDialog(
      context: context,
      builder: (_) {
        switch (widget.collection) {
          case 'vermifuges':
            return AddVermifugeDialog(
              animalId: widget.animalId, source: src, vetId: vid, vetName: vname,
              prefillProduit: data['produit'] as String?,
              prefillDosage: data['dosage'] as String?,
              prefillFrequenceValeur: freqValeur,
              prefillFrequenceUnite: freqUnite,
            );
          case 'antiparasitaires':
            return AddAntiparasitaireDialog(
              animalId: widget.animalId, source: src, vetId: vid, vetName: vname,
              prefillProduit: data['produit'] as String?,
              prefillType: data['type'] as String?,
              prefillFrequenceValeur: freqValeur,
              prefillFrequenceUnite: freqUnite,
            );
          default:
            return _AddVaccinDialog(
              animalId: widget.animalId,
              espece: widget.espece,
              source: src, vetId: vid, vetName: vname,
              prefillVaccin: data['vaccin'] as String?,
              prefillVeto: widget.vetMode ? null : data['veterinaire'] as String?,
              prefillCategorie: data['categorie'] as String?,
              rappelDe: widget.vetMode ? data : null,
            );
        }
      },
    );
    _refresh();
  }

  /// Traitement : étape suivante d'une posologie progressive.
  Future<void> _addEtape(Map<String, dynamic> data) async {
    await showDialog(context: context,
        builder: (_) => _AddTraitementDialog(animalId: widget.animalId, etapeDe: data));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: widget.canWrite
          ? FloatingActionButton.small(
              onPressed: () async {
                await showDialog(context: context, builder: widget.addBuilder);
                _refresh();
              },
              backgroundColor: const Color(0xFF6E9E57),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : (widget.onRequestWrite != null
              ? FloatingActionButton.extended(
                  onPressed: widget.onRequestWrite,
                  backgroundColor: Colors.grey.shade500,
                  icon: const Icon(Icons.lock_outline, size: 18, color: Colors.white),
                  label: const Text('Demander l\'accès', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white)),
                )
              : null),
      body: Column(children: [
        if (widget.vetMode && !widget.canWrite)
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              widget.writeRequested
                  ? 'Lecture seule — demande d\'accès en écriture envoyée, en attente d\'autorisation du propriétaire.'
                  : 'Lecture seule — le propriétaire n\'a pas autorisé l\'ajout/la suppression d\'entrées ici.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.amber.shade900),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
              : _data.isEmpty
                  ? Center(child: Text('Aucun enregistrement',
                      style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _data.length,
                      itemBuilder: (_, i) {
                        final d = _data[i];
                        final isVetEntry = d['source'] == 'veterinaire';
                        final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                        final canDelete = widget.canWrite && (isVetEntry
                            ? (widget.vetMode && d['vet_id']?.toString() == myUid)
                            : !widget.vetMode);
                        final canEdit = !isVetEntry && !widget.vetMode;
                        return _SanteCard(
                          title: _title(d), data: d, icon: widget.icon,
                          onDelete: () => _delete(d['id']?.toString() ?? ''),
                          onEdit: canEdit ? () => _edit(d) : null,
                          onRappel: ((!widget.vetMode || widget.canWrite) && ['vaccinations', 'vermifuges', 'antiparasitaires'].contains(widget.collection))
                              ? () => _addRappel(d) : null,
                          // Couper les relances : réservé au propriétaire.
                          canMute: !widget.vetMode,
                          onEtape: (canEdit && widget.canWrite && widget.collection == 'traitements')
                              ? () => _addEtape(d) : null,
                          collection: widget.collection,
                          canDelete: canDelete,
                        );
                      },
                    ),
        ),
      ]),
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
  final bool readOnly;
  const _SimpleCard({required this.data, required this.onDelete, this.onEdit,
      this.collection, this.onConfirmGestation, this.readOnly = false});

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
    'date_prevue_fin':  'Mise-bas — fin de fenêtre',
    'date_naissance':   'Date de mise-bas réelle',
  };

  static const _excludedKeys = {
    'date', 'id', 'animal_id', 'created_at', 'partenaire_animal_id', 'gestation_confirmee',
    'reminder_j7_sent', 'reminder_j3_sent', 'reminder_j1_sent',
    'dates', 'date_prevue', 'date_prevue_fin',
  };

  // Résumé « saillies » : liste des dates numérotées (Saillie 1, 2, 3…).
  String? _saillieDatesLabel() {
    if (collection != 'saillies') return null;
    final ds = _parseSaillieDates(data['dates'], fallbackDate: data['date']?.toString());
    if (ds.length <= 1) return null;
    final df = DateFormat('dd/MM/yyyy');
    return [for (var i = 0; i < ds.length; i++) 'Saillie ${i + 1} : ${df.format(ds[i])}'].join('  ·  ');
  }

  // Résumé « gestation » : fenêtre de mise-bas + date la plus probable.
  String? _gestationFenetreLabel() {
    if (collection != 'gestations') return null;
    final debut = DateTime.tryParse(data['date_prevue']?.toString() ?? '');
    final fin   = DateTime.tryParse(data['date_prevue_fin']?.toString() ?? '');
    if (debut == null) return null;
    final df = DateFormat('dd/MM/yyyy');
    if (fin == null || fin.isAtSameMomentAs(debut)) {
      return 'Mise-bas prévue : ${df.format(debut)}';
    }
    final probable = DateTime.fromMillisecondsSinceEpoch(
        (debut.millisecondsSinceEpoch + fin.millisecondsSinceEpoch) ~/ 2);
    return 'Fenêtre mise-bas : ${df.format(debut)} → ${df.format(fin)}\nDate la plus probable : ${df.format(probable)}';
  }

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
          if (date.isNotEmpty && collection != 'saillies')
            _DetailRow(label: 'Date', value: date),
          if (collection == 'saillies' && _saillieDatesLabel() == null && date.isNotEmpty)
            _DetailRow(label: 'Date', value: date),
          if (_saillieDatesLabel() != null)
            _DetailRow(label: 'Saillies', value: _saillieDatesLabel()!.replaceAll('  ·  ', '\n')),
          if (_gestationFenetreLabel() != null)
            _DetailRow(label: 'Mise-bas', value: _gestationFenetreLabel()!),
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
                confirmee ? 'Gestation confirmée' : 'Gestation à confirmer',
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
          if (!readOnly && onEdit != null)
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
                    confirmee ? 'Confirmée' : 'À confirmer',
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
              if (!readOnly) ...[
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ],
            ]),
          ]),
          if (_saillieDatesLabel() != null)
            Padding(padding: const EdgeInsets.only(top: 3),
              child: Text(_saillieDatesLabel()!,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF4A7A3A), fontWeight: FontWeight.w600))),
          if (_gestationFenetreLabel() != null)
            Padding(padding: const EdgeInsets.only(top: 3),
              child: Text(_gestationFenetreLabel()!,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF4A7A3A), fontWeight: FontWeight.w600))),
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
  final VoidCallback? onEdit;
  final VoidCallback? onRappel;
  /// Traitement : ajouter l'étape suivante (posologie progressive).
  final VoidCallback? onEtape;
  final String? collection;
  final bool canDelete;
  final bool canMute;
  const _SanteCard({required this.title, required this.data, required this.icon,
      required this.onDelete, this.onTap, this.onEdit, this.onRappel, this.onEtape, this.collection, this.canDelete = true,
      this.canMute = true});

  static const _overdueTables = {'vaccinations', 'vermifuges', 'antiparasitaires'};

  bool get _isOverdue {
    if (!_overdueTables.contains(collection)) return false;
    final rappel = data['date_rappel'] as String?;
    if (rappel == null || rappel.isEmpty) return false;
    final dt = DateTime.tryParse(rappel);
    if (dt == null) return false;
    final today = DateTime.now();
    return dt.isBefore(DateTime(today.year, today.month, today.day));
  }

  Future<void> _muteReminder(BuildContext context) async {
    try {
      // Insert simple : notifs_sent n'a pas de lecture (RLS), un upsert était
      // refusé. Déjà coupé (clé existante) = même résultat.
      try {
        await Supabase.instance.client.from('notifs_sent').insert({
          'key': 'sante_${collection}_muted_${data['id']}',
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        });
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rappel arrêté — vous ne serez plus relancé pour ce soin')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  static const _labels = {
    'vaccin': 'Vaccin', 'lot': 'N° de lot', 'veterinaire': 'Vétérinaire',
    'date': 'Date', 'date_validite_debut': 'Valide à partir de', 'date_rappel': 'Rappel', 'date_fin': 'Date de fin',
    'produit': 'Produit', 'dosage': 'Dosage', 'frequence': 'Fréquence',
    'type': 'Type', 'nom': 'Nom', 'posologie': 'Posologie',
    'description': 'Description', 'severite': 'Sévérité',
    'motif': 'Motif', 'diagnostic': 'Diagnostic', 'notes': 'Notes',
    'valeur': 'Poids (kg)', 'titre': 'Titre',
    'image_url': 'Pièce jointe', 'doc_url': 'Document',
    'intitule': 'Intervention', 'statut': 'Statut', 'clinique': 'Clinique',
    'protocole_preop': 'Protocole pré-opératoire', 'protocole_postop': 'Protocole post-opératoire',
    'etape': 'Étape', 'description_maladie': 'Maladie',
  };

  static String _fmtVal(String key, dynamic val) {
    if (val == null || val.toString().isEmpty) return '';
    if (key == 'statut' || key == 'type') return kLibellesSante[val.toString()] ?? val.toString();
    if (val is String && key.contains('date') && val.isNotEmpty) {
      final dt = DateTime.tryParse(val);
      if (dt != null) return DateFormat('dd/MM/yyyy').format(dt);
    }
    return val.toString();
  }

  String? _subtitle() {
    String? v(String key) {
      final s = data[key]?.toString() ?? '';
      return s.isNotEmpty ? s : null;
    }
    switch (collection) {
      case 'vermifuges':       return v('dosage') ?? v('notes');
      case 'vaccinations':     return v('veterinaire');
      case 'antiparasitaires': return v('frequence') ?? v('notes');
      // Étape, posologie, période, rappels — sur plusieurs lignes (miroir site).
      case 'traitements':      return resumeTraitement(data).join('\n');
      case 'visites':          return v('diagnostic') ?? v('notes');
      case 'radios':           return v('notes');
      case 'chirurgies': {
        final st = data['statut']?.toString();
        final label = st == 'realise' ? 'Réalisée' : st == 'annule' ? 'Annulée' : 'Prévue';
        final t = data['type'] == 'hospitalisation' ? 'Hospitalisation' : 'Chirurgie';
        return '$t · $label${v('clinique') != null ? ' — ${v('clinique')}' : ''}';
      }
      default:                 return null;
    }
  }

  void _showDetail(BuildContext context) {
    const _skip = {'id', 'animal_id', 'created_at', 'vet_id', 'visite_ref',
                   'source', 'pro_uid', 'owner_uid', 'rdv_id', 'extra_data',
                   'rappel_actif', 'rappel_frequence_jours', 'rappel_duree_jours',
                   'rappel_fin', 'rappel_heures'};
    final entries = data.entries.where((e) =>
        !_skip.contains(e.key) && e.value != null && e.value.toString().isNotEmpty).toList();
    // Traitement : ordre de lecture (nom → posologie → période → notes), type en
    // clair, étape « 2 sur 3 » au lieu du préfixe technique « Phase 2/3 ».
    if (collection == 'traitements') {
      const ordre = ['nom', 'type', 'description_maladie', 'posologie', 'date', 'date_fin', 'notes'];
      int rang(String k) => ordre.contains(k) ? ordre.indexOf(k) : ordre.length;
      entries.sort((a, b) => rang(a.key).compareTo(rang(b.key)));
      final etape = etapeTraitement(data);
      for (var i = 0; i < entries.length; i++) {
        final k = entries[i].key;
        if (k == 'type') entries[i] = MapEntry(k, kLibellesSante[entries[i].value] ?? entries[i].value);
        if (k == 'notes') entries[i] = MapEntry(k, notesTraitement(data));
      }
      if (etape != null) entries.insert(0, MapEntry('etape', etape));
    }
    final visiteRef = data['visite_ref'] as String?;
    final rdvId = data['rdv_id'] as String?;
    // Résumé lisible des rappels récurrents (traitements) — les colonnes
    // brutes (rappel_frequence_jours, rappel_fin...) sont exclues ci-dessus
    // et remplacées par cette seule ligne formatée.
    String? rappelSummary;
    if (collection == 'traitements') {
      final r = ligneRappelTraitement(data);
      rappelSummary = r.isEmpty ? null : r;
    } else if (data['rappel_actif'] == true) {
      final freq = data['rappel_frequence_jours'];
      final fin  = data['rappel_fin'] as String?;
      final heuresRaw = data['rappel_heures'];
      final heures = heuresRaw is List ? heuresRaw.join(', ') : '';
      final finFmt = fin != null ? (DateTime.tryParse(fin) != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(fin)) : fin) : null;
      rappelSummary = [
        'Tous les $freq jour${freq == 1 ? '' : 's'}',
        if (heures.isNotEmpty) 'à $heures',
        if (finFmt != null) 'jusqu\'au $finFmt',
      ].join(' ');
    }
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
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
            if (rappelSummary != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 130,
                        child: Text('Rappels', style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                            color: Color(0xFF6F767B), fontWeight: FontWeight.w500))),
                    Expanded(child: Text(rappelSummary,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ...entries.map((e) {
              final label  = _labels[e.key] ?? e.key;
              final val    = _fmtVal(e.key, e.value);
              if (val.isEmpty) return const SizedBox.shrink();
              final isUrl  = e.key.endsWith('_url') && val.startsWith('http');
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
                      child: isUrl
                          ? GestureDetector(
                              onTap: () async {
                                final uri = Uri.tryParse(val);
                                if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                              },
                              child: Text('Ouvrir le fichier',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                                      fontWeight: FontWeight.w600, color: Color(0xFF0284C7),
                                      decoration: TextDecoration.underline)),
                            )
                          : Text(val,
                              style: const TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            }),
          if (collection == 'traitements' && (visiteRef ?? '').isNotEmpty)
            _OrdonnanceLinkSection(visiteRef: visiteRef!),
          if ((rdvId ?? '').isNotEmpty)
            _RdvLinkSection(rdvId: rdvId!),
          if (onEdit != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () { Navigator.pop(context); onEdit!(); },
                icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF6E9E57)),
                label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          ],
        ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawDate  = data['date'] as String?;
    final date = rawDate != null && rawDate.isNotEmpty
        ? (DateTime.tryParse(rawDate) != null
            ? DateFormat('dd/MM/yyyy').format(DateTime.parse(rawDate))
            : rawDate)
        : '';
    final isVet   = data['source'] == 'veterinaire';
    final vetName = data['veterinaire'] as String?;
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isVet
                  ? const Color(0xFF0C5C6C).withValues(alpha: 0.10)
                  : const Color(0xFFEEF5EA),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(icon,
                color: isVet ? const Color(0xFF0C5C6C) : const Color(0xFF6E9E57), size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
            if (date.isNotEmpty) Text(date, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
            Builder(builder: (_) {
              final sub = _subtitle();
              if (sub == null || sub.isEmpty) return const SizedBox.shrink();
              return Text(sub,
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                maxLines: collection == 'traitements' ? 4 : 1, overflow: TextOverflow.ellipsis);
            }),
            if (isVet) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C5C6C).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  vetName != null && vetName.isNotEmpty ? vetName : 'Vétérinaire',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 10,
                      fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C)),
                ),
              ),
            ],
          ])),
          const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 18),
          if (onEtape != null)
            IconButton(icon: const Icon(Icons.playlist_add_outlined, size: 20, color: Color(0xFF0C5C6C)),
                tooltip: 'Étape suivante (posologie progressive)',
                onPressed: onEtape, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          if (onRappel != null)
            IconButton(icon: const Icon(Icons.add_alarm_outlined, size: 18, color: Color(0xFF0C5C6C)),
                tooltip: 'Ajouter un rappel (même vaccin)',
                onPressed: onRappel, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          if (_isOverdue && canMute)
            IconButton(icon: const Icon(Icons.notifications_off_outlined, size: 18, color: Color(0xFF9CA3AF)),
                tooltip: 'Arrêter les rappels pour ce soin',
                onPressed: () => _muteReminder(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          if (canDelete)
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
      ),
    );
  }
}

// ─── Sheet édition rapide santé ──────────────────────────────────────────────

class _QuickEditSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final String collection;
  final String? espece;
  final VoidCallback onSaved;
  const _QuickEditSheet({required this.data, required this.collection, this.espece, required this.onSaved});
  @override State<_QuickEditSheet> createState() => _QuickEditSheetState();
}

class _QuickEditSheetState extends State<_QuickEditSheet> {
  static const _teal = Color(0xFF0C5C6C);

  // (key, label, required, multiLine)
  static const _config = {
    'vermifuges':       [('produit','Produit *',true,false),('dosage','Dosage',false,false),('notes','Notes',false,true)],
    'vaccinations':     [('vaccin','Vaccin *',true,false),('lot','N° de lot',false,false),('veterinaire','Vétérinaire',false,false)],
    'antiparasitaires': [('produit','Produit *',true,false),('frequence','Fréquence',false,false),('notes','Notes',false,true)],
    'traitements':      [('nom','Nom *',true,false),('posologie','Posologie',false,false)],
    'visites':          [('veterinaire','Vétérinaire',false,false),('diagnostic','Diagnostic',false,true),('notes','Notes',false,true)],
    'radios':           [('titre','Titre *',true,false),('notes','Notes',false,true)],
    'allergies':        [('description','Description *',true,true)],
    'chirurgies':       [('intitule','Intervention *',true,false),('clinique','Clinique / vétérinaire',false,false),('protocole_preop','Protocole pré-opératoire',false,true),('protocole_postop','Protocole post-opératoire',false,true),('notes','Notes',false,true)],
  };

  late final Map<String, TextEditingController> _ctrls;
  late DateTime _date;
  // Vaccinations uniquement : rappel et début de validité, absents du
  // formulaire jusqu'ici (seuls vaccin/lot/vétérinaire/date étaient
  // modifiables), ce qui bloquait toute correction après coup.
  DateTime? _dateRappel;
  DateTime? _dateValidite;
  // Vaccinations uniquement : type de vaccin — permet de corriger une
  // catégorie après coup (les délais par défaut affichés lors de l'ajout
  // ne sont pas re-suggérés ici, seule la valeur est éditable).
  String? _categorie;
  bool _saving = false;
  String? _error;

  // ── Rappels récurrents (traitements uniquement) ──────────────────────────
  bool _rappelActif = false;
  late final TextEditingController _rappelFrequenceCtrl;
  late final TextEditingController _rappelDureeCtrl;
  List<PriseTraitement> _prises = []; // heure + quantité de chaque prise

  bool get _isTraitement => widget.collection == 'traitements';

  @override
  void initState() {
    super.initState();
    final fields = _config[widget.collection] ?? [];
    _ctrls = { for (final f in fields) f.$1: TextEditingController(text: (widget.data[f.$1] ?? '').toString()) };
    for (final c in _ctrls.values) {
      c.addListener(() { if (_error != null && mounted) setState(() => _error = null); });
    }
    final raw = widget.data['date'] as String?;
    _date = raw != null ? (DateTime.tryParse(raw) ?? DateTime.now()) : DateTime.now();
    _dateRappel = DateTime.tryParse((widget.data['date_rappel'] ?? '').toString());
    _dateValidite = DateTime.tryParse((widget.data['date_validite_debut'] ?? '').toString());
    _categorie = widget.data['categorie'] as String?;

    _rappelActif = widget.data['rappel_actif'] == true;
    _rappelFrequenceCtrl = TextEditingController(text: (widget.data['rappel_frequence_jours'] ?? 1).toString());
    _rappelDureeCtrl = TextEditingController(text: (widget.data['rappel_duree_jours'] ?? 7).toString());
    _prises = prisesDepuis(widget.data);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    _rappelFrequenceCtrl.dispose();
    _rappelDureeCtrl.dispose();
    super.dispose();
  }

  Widget _buildRappelSection() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F8F6),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE4E7E2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Rappels récurrents',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800))),
        Switch(value: _rappelActif, activeThumbColor: const Color(0xFF6E9E57),
            onChanged: (v) => setState(() => _rappelActif = v)),
      ]),
      if (_rappelActif) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Text('Répéter tous les', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(width: 50, child: TextFormField(controller: _rappelFrequenceCtrl,
              keyboardType: TextInputType.number, textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          const Text('jour(s)', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Text('Pendant', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(width: 50, child: TextFormField(controller: _rappelDureeCtrl,
              keyboardType: TextInputType.number, textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          const Text('jours', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        PrisesTraitementEditor(prises: _prises, onChanged: (l) => setState(() => _prises = l)),
      ],
    ]),
  );

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now(),
      locale: const Locale('fr'),
      builder: (ctx, child) => Theme(data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: _teal)), child: child!),
    );
    if (p != null) setState(() => _date = p);
  }

  Widget _optionalDateRow(String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    final fmt = DateFormat('dd/MM/yyyy');
    return GestureDetector(
      onTap: () async {
        final p = await showDatePicker(
          context: context, initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000), lastDate: DateTime(2100),
          locale: const Locale('fr'),
          builder: (ctx, child) => Theme(data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(primary: _teal)), child: child!),
        );
        if (p != null) onChanged(p);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F6), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _teal.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(Icons.event_outlined, size: 16, color: value != null ? _teal : Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600))),
          Text(value != null ? fmt.format(value) : '—',
              style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                  fontWeight: FontWeight.w600, color: value != null ? const Color(0xFF1F2A2E) : Colors.grey.shade400)),
          if (value != null)
            GestureDetector(
              onTap: () => onChanged(null),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    final fields = _config[widget.collection] ?? [];
    for (final f in fields) {
      if (f.$3 && (_ctrls[f.$1]?.text.trim().isEmpty ?? true)) {
        setState(() => _error = '${f.$2.replaceAll('*', '').trim()} est obligatoire.');
        return;
      }
    }
    if (_isTraitement && _rappelActif) {
      final freq = int.tryParse(_rappelFrequenceCtrl.text.trim()) ?? 1;
      final duree = int.tryParse(_rappelDureeCtrl.text.trim()) ?? 0;
      if (duree > 0 && freq > duree) {
        setState(() => _error = 'Une prise tous les $freq jours ne tient pas dans $duree jours de traitement — '
            'le rythme doit être inférieur ou égal à la durée.');
        return;
      }
    }
    if (_isTraitement && _rappelActif && _prises.isEmpty) {
      setState(() => _error = 'Ajoute au moins une heure de rappel.');
      return;
    }
    try {
      controlerDatesSante(date: _date,
          rappel: widget.collection == 'vaccinations' ? _dateRappel : null,
          validite: widget.collection == 'vaccinations' ? _dateValidite : null,
          statut: widget.collection == 'chirurgies' ? widget.data['statut'] as String? : null);
    } on SaisieInvalide catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final updates = <String, dynamic>{ 'date': _date.toIso8601String() };
      if (widget.collection == 'vaccinations') {
        updates['date_rappel'] = _dateRappel?.toIso8601String();
        updates['date_validite_debut'] = _dateValidite?.toIso8601String();
        updates['categorie'] = _categorie;
      }
      for (final f in fields) {
        final v = _ctrls[f.$1]?.text.trim() ?? '';
        updates[f.$1] = v;
      }
      if (_isTraitement) {
        updates['rappel_actif'] = _rappelActif;
        if (_rappelActif) {
          final frequenceJours = int.tryParse(_rappelFrequenceCtrl.text) ?? 1;
          final dureeJours = int.tryParse(_rappelDureeCtrl.text) ?? 7;
          updates['rappel_frequence_jours'] = frequenceJours;
          updates['rappel_duree_jours'] = dureeJours;
          // Fin = dernier jour inclus (début + durée − 1), identique pour la
          // fiche et les rappels : le total des jours correspond aux dates.
          final fin = DateTime(_date.year, _date.month, _date.day).add(Duration(days: dureeJours - 1));
          updates['rappel_fin'] = fin.toIso8601String();
          updates['date_fin'] = fin.toIso8601String();
          updates.addAll(colonnesPrises(_prises));
        } else {
          updates['rappel_frequence_jours'] = null;
          updates['rappel_duree_jours'] = null;
          updates['rappel_fin'] = null;
          updates['rappel_heures'] = null;
          updates['rappel_quantites'] = null;
        }
      }
      final id = widget.data['id'].toString();
      await Supabase.instance.client
          .from(widget.collection).update(updates).eq('id', id);
      await _syncRegistre(id, updates);
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Erreur: $e'; });
    }
  }

  // Répercute la modification sur la ligne du registre sanitaire liée
  // (source_table/source_id) — sans quoi une correction ici n'apparaissait
  // jamais dans le registre.
  static const _typeActeParCollection = {
    'vaccinations': 'vaccination', 'vermifuges': 'vermifuge',
    'antiparasitaires': 'antiparasitaire', 'traitements': 'traitement',
    'visites': 'visite',
  };

  Future<void> _syncRegistre(String id, Map<String, dynamic> updates) async {
    final typeActe = _typeActeParCollection[widget.collection];
    if (typeActe == null) return;
    String description;
    switch (widget.collection) {
      case 'vaccinations':
        final lot = (updates['lot'] as String? ?? '').trim();
        description = 'Vaccin : ${updates['vaccin']}${lot.isNotEmpty ? ' (lot $lot)' : ''}';
        break;
      case 'vermifuges':
        final dosage = (updates['dosage'] as String? ?? '').trim();
        description = '${updates['produit']}${dosage.isNotEmpty ? ' — $dosage' : ''}';
        break;
      case 'antiparasitaires':
        description = '${updates['produit']}';
        break;
      case 'traitements':
        final posologie = (updates['posologie'] as String? ?? '').trim();
        description = '${updates['nom']}${posologie.isNotEmpty ? ' — $posologie' : ''}';
        break;
      case 'visites':
        final diag = (updates['diagnostic'] as String? ?? '').trim();
        description = diag.isNotEmpty ? diag : 'Visite vétérinaire';
        break;
      default:
        return;
    }
    await RegistreHelper.writeActe(
      animalId: widget.data['animal_id'] as String? ?? '',
      typeActe: typeActe, dateActe: _date,
      intervenant: (updates['veterinaire'] as String?) ?? (widget.data['veterinaire'] as String? ?? ''),
      description: description,
      sourceTable: widget.collection, sourceId: id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = _config[widget.collection] ?? [];
    final fmt = DateFormat('dd/MM/yyyy');
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          if (widget.collection == 'vaccinations') ...[
            DropdownButtonFormField<String>(
              initialValue: _categorie,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Type de vaccin',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
                filled: true, fillColor: const Color(0xFFF8F8F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
              items: typesVaccinPour(widget.espece).map((t) => t.$1)
                  .toList().map((l) => DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _categorie = v),
            ),
            const SizedBox(height: 10),
          ],
          // Date
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F6), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _teal.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: _teal),
                const SizedBox(width: 8),
                Text(fmt.format(_date), style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9E9E9E)),
              ]),
            ),
          ),
          if (widget.collection == 'vaccinations') ...[
            const SizedBox(height: 10),
            _optionalDateRow('Valide à partir de', _dateValidite,
                (d) => setState(() => _dateValidite = d)),
            const SizedBox(height: 10),
            _optionalDateRow('Date de rappel', _dateRappel,
                (d) => setState(() => _dateRappel = d)),
          ],
          const SizedBox(height: 12),
          for (final f in fields) ...[
            TextField(
              controller: _ctrls[f.$1],
              maxLines: f.$4 ? 2 : 1,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                labelText: f.$2,
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
                filled: true, fillColor: const Color(0xFFF8F8F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _teal.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _teal.withOpacity(0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _teal, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_isTraitement) ...[
            _buildRappelSection(),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFB71C1C))),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(_saving ? 'Enregistrement…' : 'Enregistrer',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Onglet Propriétaire (vue vétérinaire) ───────────────────────────────────

// ─── Onglet Poids ─────────────────────────────────────────────────────────────

// Libellé lisible : sous 1 kg on affiche en grammes (utile pour les bébés
// de petites espèces), au-dessus en kg. Le stockage reste toujours en kg.
String _poidsLabel(double kg) {
  if (kg < 1) return '${(kg * 1000).round()} g';
  if (kg < 10) {
    final s = kg.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return '${s.replaceAll('.', ',')} kg';
  }
  return '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg';
}

// Version compacte pour les axes de graphe (pas d'espace, k au lieu de kg).
String _poidsAxis(double kg) {
  if (kg < 1) return '${(kg * 1000).round()}g';
  if (kg < 10) return '${kg.toStringAsFixed(1)}k';
  return '${kg.toStringAsFixed(0)}k';
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
                      Text(_poidsLabel(val),
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
                        onPressed: () async {
                          if (!await confirmerSuppressionSante(context, 'poids',
                              nom: d['valeur'] != null ? '${d['valeur']} kg' : null)) return;
                          await Supabase.instance.client.from('poids').delete().eq('id', d['id']);
                          _refresh();
                        },
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
      final lbl = _poidsAxis(yVal < 0 ? 0 : yVal);
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
      final line1 = _poidsLabel(vals[i]);
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

// Types de vaccins par espèce, avec délais par défaut (indicatifs, toujours
// modifiables) : intervalle de rappel en années, et délai avant mise en
// validité légale en jours (ex: rage = 21 jours pour les déplacements UE —
// ne s'applique qu'à la toute première injection de ce type pour l'animal,
// un rappel étant valide dès le jour même). Utilisé pour l'ajout ET la
// modification d'un vaccin.
// Types de vaccins par espèce : voir lib/data/vaccin_types.dart (partagé
// avec animal_fiche_particulier.dart pour ne jamais diverger entre profils).

class _AddVaccinDialog extends StatefulWidget {
  final String animalId;
  final String? espece;
  final String source;
  final String? vetId;
  final String? vetName;
  // Pré-remplissage pour "Ajouter un rappel" depuis un vaccin existant :
  // même vaccin/type/vétérinaire, seuls date et lot changent.
  final String? prefillVaccin;
  final String? prefillVeto;
  final String? prefillCategorie;
  /// Modification : entrée existante (même formulaire qu'à la création).
  final Map<String, dynamic>? existant;
  /// Rappel fait aujourd'hui (vétérinaire) : date du jour, prochain rappel au
  /// même intervalle que l'injection précédente.
  final Map<String, dynamic>? rappelDe;
  const _AddVaccinDialog({required this.animalId, this.espece, this.source = 'owner', this.vetId, this.vetName,
      this.prefillVaccin, this.prefillVeto, this.prefillCategorie, this.existant, this.rappelDe});
  @override State<_AddVaccinDialog> createState() => _AddVaccinDialogState();
}
class _AddVaccinDialogState extends State<_AddVaccinDialog> {
  final _vaccin = TextEditingController();
  final _lot = TextEditingController();
  final _veto = TextEditingController();
  DateTime? _date;
  DateTime? _rappel;
  DateTime? _validite;
  String? _categorie;

  List<(String label, int rappelAns, int validiteJours)> get _typesDisponibles =>
      typesVaccinPour(widget.espece);

  (int ans, int jours)? get _defautsPourCategorie {
    if (_categorie == null) return null;
    for (final t in _typesDisponibles) {
      if (t.$1 == _categorie) return (t.$2, t.$3);
    }
    return null;
  }

  // Le délai légal (ex: rage = 21 jours) ne s'applique qu'à la toute
  // première injection de ce type de vaccin pour cet animal : un rappel
  // d'un vaccin déjà administré est valide dès le jour même.
  Future<bool> _estPremiereFois(String categorie) async {
    try {
      final rows = await Supabase.instance.client
          .from('vaccinations').select('id').eq('animal_id', widget.animalId).eq('categorie', categorie);
      return (rows as List).isEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<void> _recomputeSuggestions({bool force = false}) async {
    if (_date == null || _categorie == null) return;
    final d = _defautsPourCategorie;
    if (d == null) return;
    final premiereFois = await _estPremiereFois(_categorie!);
    if (!mounted) return;
    if (force || _validite == null) {
      setState(() => _validite = _date!.add(Duration(days: premiereFois ? d.$2 : 0)));
    }
    if (force || _rappel == null) {
      setState(() => _rappel = DateTime(_date!.year + d.$1, _date!.month, _date!.day));
    }
  }

  void _onCategorieChanged(String? label) {
    if (label == null) return;
    setState(() => _categorie = label);
    if (_vaccin.text.trim().isEmpty) _vaccin.text = label;
    _recomputeSuggestions(force: true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.vetName != null) _veto.text = widget.vetName!;
    if (widget.prefillVaccin != null) _vaccin.text = widget.prefillVaccin!;
    if (widget.prefillVeto != null) _veto.text = widget.prefillVeto!;
    _categorie = widget.prefillCategorie;
    final e = widget.existant;
    if (e != null) {
      _vaccin.text = (e['vaccin'] ?? '').toString();
      _lot.text = (e['lot'] ?? '').toString();
      _veto.text = (e['veterinaire'] ?? '').toString();
      _date = DateTime.tryParse(e['date']?.toString() ?? '');
      _validite = DateTime.tryParse(e['date_validite_debut']?.toString() ?? '');
      _rappel = DateTime.tryParse(e['date_rappel']?.toString() ?? '');
      final c = e['categorie']?.toString();
      _categorie = _typesDisponibles.any((t) => t.$1 == c) ? c : null;
    }
    final r0 = widget.rappelDe;
    if (r0 != null && e == null) {
      final now = DateTime.now();
      _date = DateTime(now.year, now.month, now.day);
      _validite = _date; // rappel : valide le jour même
      if (!_typesDisponibles.any((t) => t.$1 == _categorie)) _categorie = null;
      final d0 = DateTime.tryParse(r0['date']?.toString() ?? '');
      final dr = DateTime.tryParse(r0['date_rappel']?.toString() ?? '');
      if (d0 != null && dr != null && dr.isAfter(d0)) {
        _rappel = _date!.add(dr.difference(d0));
      } else {
        _recomputeSuggestions();
      }
    }
  }

  @override
  Widget build(BuildContext context) => _BaseDialog(
      title: widget.existant != null ? 'Modifier le vaccin' : 'Ajouter un vaccin', fields: [
    _DDrop('Type de vaccin', _categorie, _typesDisponibles.map((t) => t.$1).toList(), _onCategorieChanged),
    _DF('Vaccin *', _vaccin), _DF('N° de lot', _lot),
    _DF('Vétérinaire', _veto, readOnly: widget.source == 'veterinaire'),
    _DD('Date *', _date, (d) { setState(() => _date = d); _recomputeSuggestions(force: true); }),
    _DD('Valide à partir de', _validite, (d) => setState(() => _validite = d)),
    _DD('Date de rappel', _rappel, (d) => setState(() => _rappel = d)),
  ], onSave: () async {
    if (_vaccin.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le nom du vaccin.');
    controlerDatesSante(date: _date, rappel: _rappel, validite: _validite);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final ligne = <String, dynamic>{
      'id': id, 'animal_id': widget.animalId,
      'vaccin': _vaccin.text.trim(), 'lot': _lot.text.trim(), 'veterinaire': _veto.text.trim(),
      'date': _date!.toIso8601String(),
      'date_validite_debut': (_validite ?? _date)!.toIso8601String(),
      'date_rappel': _rappel?.toIso8601String(),
      'categorie': _categorie,
      'source': widget.source,
      if (widget.vetId != null) 'vet_id': widget.vetId,
    };
    final e = widget.existant;
    if (e != null) {
      await _majSante('vaccinations', e, ligne);
      final avant = DateTime.tryParse(e['date_rappel']?.toString() ?? '');
      if (_rappel != null && (avant == null || !DateUtils.isSameDay(avant, _rappel))) {
        await _scheduleRappelAgenda(animalId: widget.animalId, dateRappel: _rappel!, titre: 'Rappel vaccin — ${_vaccin.text.trim()}');
      }
      return true;
    }
    await Supabase.instance.client.from('vaccinations').insert(ligne);
    // Saisi par le vétérinaire : pas d'événement dans SON agenda — le
    // propriétaire et ses co-propriétaires sont relancés par le serveur
    // (sendSanteReminders sur date_rappel) et le voient dans « Mon quotidien ».
    if (_rappel != null && widget.source != 'veterinaire') {
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
      sourceTable: 'vaccinations', sourceId: id,
    );
    if (widget.vetId != null) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyOwnerVetEntry')
            .call({'animalId': widget.animalId, 'vetName': _veto.text.trim(), 'typeActe': 'vaccin'});
      } catch (_) {}
    }
    return true;
  });
}

/// Modification d'une entrée du carnet : mêmes colonnes que l'ajout, sans
/// identifiant / animal / source (inchangés).
Future<void> _majSante(String table, Map existant, Map<String, dynamic> ligne) async {
  final maj = {...ligne}..remove('id')..remove('animal_id')..remove('source')..remove('vet_id');
  await Supabase.instance.client.from(table).update(maj).eq('id', existant['id']);
}

/// « 3 mois » / « 2 semaines » / « 10 jours » → (valeur, unité du formulaire).
(String, String)? _frequenceDe(Object? f) {
  final m = RegExp(r'^(\d+)\s*(jour|semaine|mois)', caseSensitive: false).firstMatch((f ?? '').toString());
  return m == null ? null : (m.group(1)!, m.group(2)!.toLowerCase());
}

class _AddTraitementDialog extends StatefulWidget {
  final String animalId;
  final String source;
  final String? vetId;
  final String? vetName;
  /// Étape suivante d'une posologie progressive : pré-remplie depuis cette
  /// étape, enregistrée dans le même groupe (notes « Phase i/n »).
  final Map<String, dynamic>? etapeDe;
  /// Modification : toutes les étapes du traitement (même groupe).
  final List<Map<String, dynamic>>? groupe;
  const _AddTraitementDialog({required this.animalId, this.source = 'owner', this.vetId, this.vetName, this.etapeDe, this.groupe});
  @override State<_AddTraitementDialog> createState() => _AddTraitementDialogState();
}
class _AddTraitementDialogState extends State<_AddTraitementDialog> {
  final _nom = TextEditingController();
  final _posologie = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'antiparasitaire';
  DateTime? _date;
  DateTime? _dateFin;

  // ── Posologie en étapes + rappels à chaque prise ──
  bool _rappelActif = true;
  List<EtapeTraitement> _etapes = [EtapeTraitement()];

  @override
  void initState() {
    super.initState();
    final g = widget.groupe;
    if (g != null && g.isNotEmpty) {
      final p0 = g.first;
      _nom.text = (p0['nom'] ?? '').toString();
      if (g.length == 1) _posologie.text = (p0['posologie'] ?? '').toString();
      _notes.text = notesTraitement(p0);
      if (['antiparasitaire', 'medicament', 'autre'].contains(p0['type'])) _type = p0['type'] as String;
      _date = DateTime.tryParse(p0['date']?.toString() ?? '');
      _rappelActif = g.any((x) => x['rappel_actif'] == true);
      int jours(Map x) {
        final d = DateTime.tryParse(x['date']?.toString() ?? ''), f = DateTime.tryParse(x['date_fin']?.toString() ?? '');
        if (d != null && f != null) return DateTime(f.year, f.month, f.day).difference(DateTime(d.year, d.month, d.day)).inDays + 1;
        return int.tryParse('${x['rappel_duree_jours'] ?? ''}') ?? 7;
      }
      _etapes = [for (final x in g) EtapeTraitement(dureeJours: jours(x).clamp(1, 3650),
          frequenceJours: int.tryParse('${x['rappel_frequence_jours'] ?? ''}') ?? 1, prises: prisesDepuis(x))];
    }
    final e = widget.etapeDe;
    if (e != null) {
      _nom.text = (e['nom'] ?? '').toString();
      if (['antiparasitaire', 'medicament', 'autre'].contains(e['type'])) _type = e['type'] as String;
      _date = debutEtapeSuivante(e);
      _rappelActif = e['rappel_actif'] == true;
      _etapes = [EtapeTraitement(dureeJours: 3,
          frequenceJours: int.tryParse('${e['rappel_frequence_jours'] ?? ''}') ?? 1, prises: prisesDepuis(e))];
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Widget _buildEtapesSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: Text('Rappel à chaque prise',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800))),
      Switch(value: _rappelActif, activeThumbColor: const Color(0xFF6E9E57),
          onChanged: (v) => setState(() => _rappelActif = v)),
    ]),
    EtapesTraitementEditor(etapes: _etapes, debut: _date, onChanged: () => setState(() {})),
  ]);

  @override
  Widget build(BuildContext context) => _BaseDialog(
      title: widget.groupe != null ? 'Modifier le traitement' : widget.etapeDe != null ? 'Étape suivante' : 'Ajouter un traitement', fields: [
    _DDrop('Type', _type, ['antiparasitaire', 'medicament', 'autre'], (v) => setState(() => _type = v!)),
    _DF('Nom du produit *', _nom), _DF('Posologie (résumé, facultatif)', _posologie),
    _DD('Date début *', _date, (d) => setState(() => _date = d)),
    _DCustom(_buildEtapesSection()),
    _DF('Commentaires', _notes, maxLines: 3),
  ], onSave: () async {
    if (_nom.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le nom du produit.');
    controlerDatesSante(date: _date, fin: finTraitement(_date, _etapes));
    if (_etapes.isEmpty) throw const SaisieInvalide('Ajoutez au moins une étape.');
    final rythme = erreurEtapes(_etapes);
    if (rythme != null) throw SaisieInvalide(rythme);
    if (_rappelActif && _etapes.any((e) => e.prises.isEmpty)) {
      throw const SaisieInvalide('Ajoutez au moins une prise à chaque étape (ou désactivez les rappels).');
    }
    final lignes = lignesEtapes(
      base: {
        'animal_id': widget.animalId, 'type': _type, 'nom': _nom.text.trim(),
        if (_posologie.text.trim().isNotEmpty) 'posologie': _posologie.text.trim(),
        'source': widget.source,
        if (widget.vetId != null) 'vet_id': widget.vetId,
      },
      debut: _date!, etapes: _etapes, rappels: _rappelActif, notes: _notes.text,
    );
    // Étape(s) ajoutée(s) à une posologie existante : même groupe, numérotation suivie.
    if (widget.etapeDe != null) {
      final g = await preparerEtapeSuivante(widget.animalId, widget.etapeDe!, nouvelles: lignes.length);
      for (var k = 0; k < lignes.length; k++) {
        lignes[k]['groupe_id'] = g.id;
        lignes[k]['notes'] = ['Phase ${g.existantes + k + 1}/${g.total}', if (_notes.text.trim().isNotEmpty) _notes.text.trim()]
            .join(' — ');
      }
    }
    // Modification : même groupe, les anciennes étapes sont remplacées.
    final ancien = widget.groupe;
    if (ancien != null) {
      final gid = ancien.map((x) => (x['groupe_id'] ?? '').toString()).firstWhere((x) => x.isNotEmpty, orElse: () => '');
      if (gid.isNotEmpty && lignes.length > 1) {
        for (final l in lignes) { l['groupe_id'] = gid; }
      }
      await Supabase.instance.client.from('traitements').insert(lignes);
      for (final x in ancien) {
        await Supabase.instance.client.from('traitements').delete().eq('id', x['id']);
      }
      return true;
    }
    await Supabase.instance.client.from('traitements').insert(lignes);
    RegistreHelper.writeActe(
      animalId: widget.animalId, typeActe: 'traitement', dateActe: _date!,
      intervenant: widget.vetName ?? '',
      description: '${_nom.text.trim()} — ${_etapes.map((e) => e.libelle()).join(', puis ')}',
      sourceTable: 'traitements', sourceId: lignes.first['id'] as String,
    );
    if (widget.vetId != null) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyOwnerVetEntry')
            .call({'animalId': widget.animalId, 'vetName': widget.vetName ?? '', 'typeActe': 'traitement'});
      } catch (_) {}
    }
    return true;
  });
}

class _AddVisiteDialog extends StatefulWidget {
  final String animalId;
  final String source;
  final String? vetId;
  final String? vetName;
  const _AddVisiteDialog({required this.animalId, this.source = 'owner', this.vetId, this.vetName});
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
  void initState() {
    super.initState();
    if (widget.vetName != null) _veto.text = widget.vetName!;
  }

  @override
  Widget build(BuildContext context) => _BaseDialog(title: 'Ajouter une visite', fields: [
    _DDrop('Motif *', _motif, _motifs, (v) => setState(() => _motif = v!)),
    _DF('Vétérinaire', _veto, readOnly: widget.source == 'veterinaire'),
    _DD('Date *', _date, (d) => setState(() => _date = d)),
    if (_isVaccin) ...[
      _DF('Vaccin *', _vaccin),
      _DF('N° de lot', _lot),
      _DD('Date de rappel', _dateRappel, (d) => setState(() => _dateRappel = d)),
    ],
    _DF('Diagnostic / Observations', _diag),
    _DF('Notes', _notes, maxLines: 3),
  ], onSave: () async {
    controlerDatesSante(date: _date, rappel: _isVaccin ? _dateRappel : null);
    if (_isVaccin && _vaccin.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le nom du vaccin.');
    final supa = Supabase.instance.client;
    final visiteId = DateTime.now().microsecondsSinceEpoch.toString();
    String? vetProfileId;
    if (widget.vetId != null) {
      final profRow = await supa.from('user_profiles_complet')
          .select('id').eq('uid', widget.vetId!).eq('is_main', true).maybeSingle();
      vetProfileId = profRow?['id'] as String?;
    }
    await supa.from('visites').insert({
      'id': visiteId, 'animal_id': widget.animalId,
      'motif': _motif, 'veterinaire': _veto.text.trim(),
      'date': _date!.toIso8601String(),
      'diagnostic': _diag.text.trim(), 'notes': _notes.text.trim(),
      'source': widget.source,
      if (widget.vetId != null) 'vet_id': widget.vetId,
      if (vetProfileId != null) 'vet_profile_id': vetProfileId,
    });
    String? vacId;
    if (_isVaccin) {
      vacId = (DateTime.now().microsecondsSinceEpoch + 1).toString();
      await supa.from('vaccinations').insert({
        'id': vacId, 'animal_id': widget.animalId,
        'vaccin': _vaccin.text.trim(), 'lot': _lot.text.trim(),
        'veterinaire': _veto.text.trim(),
        'date': _date!.toIso8601String(),
        'date_rappel': _dateRappel?.toIso8601String(),
        'source': widget.source,
        if (widget.vetId != null) 'vet_id': widget.vetId,
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
      sourceTable: _isVaccin ? 'vaccinations' : 'visites',
      sourceId: _isVaccin ? vacId : visiteId,
    );
    if (widget.vetId != null) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyOwnerVetEntry')
            .call({'animalId': widget.animalId, 'vetName': _veto.text.trim(), 'typeActe': 'visite'});
      } catch (_) {}
    }
    return true;
  });
}

class AddVermifugeDialog extends StatefulWidget {
  final String animalId;
  final String source;
  final String? vetId;
  final String? vetName;
  // Pré-remplissage pour "+ Renouvellement" depuis un traitement existant :
  // même produit/dosage/fréquence, seule la date change.
  final String? prefillProduit;
  final String? prefillDosage;
  final String? prefillFrequenceValeur;
  final String? prefillFrequenceUnite;
  /// Modification : entrée existante (même formulaire qu'à la création).
  final Map<String, dynamic>? existant;
  const AddVermifugeDialog({required this.animalId, this.source = 'owner', this.vetId, this.vetName,
      this.prefillProduit, this.prefillDosage, this.prefillFrequenceValeur, this.prefillFrequenceUnite, this.existant});
  @override State<AddVermifugeDialog> createState() => AddVermifugeDialogState();
}
class AddVermifugeDialogState extends State<AddVermifugeDialog> {
  late final _produit         = TextEditingController(text: widget.prefillProduit ?? '');
  late final _dosage          = TextEditingController(text: widget.prefillDosage ?? '');
  late final _frequenceValeur = TextEditingController(text: widget.prefillFrequenceValeur ?? '');
  final _notes   = TextEditingController();
  late String _frequenceUnite = widget.prefillFrequenceUnite ?? 'mois';
  DateTime? _date, _dateRappel;
  /// Durée / rappels de prise + autres animaux (widgets/carnet/vermifuge_options.dart).
  final _options = OptionsVermifuge();

  @override
  void initState() {
    super.initState();
    final e = widget.existant;
    if (e != null) {
      _produit.text = (e['produit'] ?? '').toString();
      _dosage.text = (e['dosage'] ?? '').toString();
      _notes.text = (e['notes'] ?? '').toString();
      final f = _frequenceDe(e['frequence']);
      if (f != null) { _frequenceValeur.text = f.$1; _frequenceUnite = f.$2; }
      _date = DateTime.tryParse(e['date']?.toString() ?? '');
      _dateRappel = DateTime.tryParse(e['date_rappel']?.toString() ?? '');
      _options.dureeJours = int.tryParse('${e['duree_jours'] ?? e['rappel_duree_jours'] ?? ''}') ?? 1;
      _options.rappel = e['rappel_actif'] == true;
      _options.heures.addAll(((e['rappel_heures'] as List?) ?? const []).map((h) => h.toString()));
    }
  }

  String? get _frequenceLabel {
    final n = int.tryParse(_frequenceValeur.text.trim());
    if (n == null || n <= 0) return null;
    final unite = _frequenceUnite == 'jour' ? 'jour${n > 1 ? 's' : ''}'
        : _frequenceUnite == 'semaine' ? 'semaine${n > 1 ? 's' : ''}' : 'mois';
    return '$n $unite';
  }

  void _recomputeRappel() {
    if (_date == null) return;
    final n = int.tryParse(_frequenceValeur.text.trim());
    if (n == null || n <= 0) return;
    final days = _frequenceUnite == 'jour' ? n : _frequenceUnite == 'semaine' ? n * 7 : n * 30;
    setState(() => _dateRappel = _date!.add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) => _BaseDialog(
      title: widget.existant != null ? 'Modifier le vermifuge' : 'Ajouter un vermifuge', fields: [
    _DF('Produit *', _produit),
    _DF('Dosage', _dosage),
    _DD('Date *', _date, (d) { setState(() => _date = d); _recomputeRappel(); }),
    _DCustom(Row(children: [
      Expanded(flex: 2, child: TextFormField(
        controller: _frequenceValeur, keyboardType: TextInputType.number,
        onChanged: (_) => _recomputeRappel(),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(labelText: 'Fréquence',
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true))),
      const SizedBox(width: 8),
      Expanded(flex: 3, child: DropdownButtonFormField<String>(
        initialValue: _frequenceUnite,
        items: const [
          DropdownMenuItem(value: 'jour', child: Text('Jour(s)')),
          DropdownMenuItem(value: 'semaine', child: Text('Semaine(s)')),
          DropdownMenuItem(value: 'mois', child: Text('Mois')),
        ],
        onChanged: (v) { setState(() => _frequenceUnite = v!); _recomputeRappel(); },
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true))),
    ])),
    _DCustom(PrisesVermifugeSection(options: _options)),
    // Saisie groupée : réservée au propriétaire (pas au vétérinaire).
    if (widget.vetId == null && widget.existant == null) _DCustom(AutresAnimauxSection(animalId: widget.animalId, options: _options)),
    // Calculé à partir de la date et de la fréquence : non modifiable.
    _DLecture('Prochain rappel (calculé)',
        _dateRappel != null ? DateFormat('dd/MM/yyyy').format(_dateRappel!) : 'Selon la date et la fréquence'),
    _DF('Notes', _notes, maxLines: 2),
  ], onSave: () async {
    if (_produit.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le produit.');
    controlerDatesSante(date: _date, rappel: _dateRappel);
    if (_options.erreur != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_options.erreur!)));
      return false;
    }
    final e = widget.existant;
    if (e != null) {
      await _majSante('vermifuges', e, {
        'produit': _produit.text.trim(), 'dosage': _dosage.text.trim(),
        'date': _date!.toIso8601String(), 'date_rappel': _dateRappel?.toIso8601String(),
        'frequence': _frequenceLabel, 'notes': _notes.text.trim(),
        ..._options.colonnes(_date!),
        if (!_options.rappel) ...{'rappel_heures': null, 'rappel_fin': null},
      });
      final avant = DateTime.tryParse(e['date_rappel']?.toString() ?? '');
      if (_dateRappel != null && (avant == null || !DateUtils.isSameDay(avant, _dateRappel))) {
        await _scheduleRappelAgenda(animalId: widget.animalId, dateRappel: _dateRappel!, titre: 'Rappel vermifuge — ${_produit.text.trim()}');
      }
      return true;
    }
    final cibles = [widget.animalId, ..._options.autresAnimaux];
    final base = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < cibles.length; i++) {
      final id = '${base + i}';
      await Supabase.instance.client.from('vermifuges').insert({
        'id': id, 'animal_id': cibles[i],
        'produit': _produit.text.trim(), 'dosage': _dosage.text.trim(),
        'date': _date!.toIso8601String(),
        'date_rappel': _dateRappel?.toIso8601String(),
        if (_frequenceLabel != null) 'frequence': _frequenceLabel,
        'notes': _notes.text.trim(),
        'source': widget.source,
        if (widget.vetId != null) 'vet_id': widget.vetId,
        ..._options.colonnes(_date!),
      });
      RegistreHelper.writeActe(
        animalId: cibles[i], typeActe: 'vermifuge', dateActe: _date!,
        intervenant: widget.vetName ?? '',
        description: '${_produit.text.trim()}${_dosage.text.trim().isNotEmpty ? ' — ${_dosage.text.trim()}' : ''}',
        sourceTable: 'vermifuges', sourceId: id,
      );
    }
    // Prochain rappel : un seul événement d'agenda pour tous les animaux.
    if (_dateRappel != null) {
      await _scheduleRappelAgenda(
        animalId: widget.animalId,
        dateRappel: _dateRappel!,
        titre: 'Rappel vermifuge — ${_produit.text.trim()}',
        autres: _options.autresAnimaux.toList(),
      );
    }
    if (widget.vetId != null) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyOwnerVetEntry')
            .call({'animalId': widget.animalId, 'vetName': widget.vetName ?? '', 'typeActe': 'traitement'});
      } catch (_) {}
    }
    return true;
  });
}

class AddAntiparasitaireDialog extends StatefulWidget {
  final String animalId;
  final String source;
  final String? vetId;
  final String? vetName;
  // Pré-remplissage pour "+ Renouvellement" depuis un traitement existant :
  // même produit/type/fréquence, seule la date change.
  final String? prefillProduit;
  final String? prefillType;
  final String? prefillFrequenceValeur;
  final String? prefillFrequenceUnite;
  /// Modification : entrée existante (même formulaire qu'à la création).
  final Map<String, dynamic>? existant;
  const AddAntiparasitaireDialog({required this.animalId, this.source = 'owner', this.vetId, this.vetName,
      this.prefillProduit, this.prefillType, this.prefillFrequenceValeur, this.prefillFrequenceUnite, this.existant});
  @override State<AddAntiparasitaireDialog> createState() => AddAntiparasitaireDialogState();
}
class AddAntiparasitaireDialogState extends State<AddAntiparasitaireDialog> {
  late final _produit         = TextEditingController(text: widget.prefillProduit ?? '');
  late final _frequenceValeur = TextEditingController(text: widget.prefillFrequenceValeur ?? '1');
  final _notes     = TextEditingController();
  late String _type = widget.prefillType ?? 'pipette';
  late String _frequenceUnite = widget.prefillFrequenceUnite ?? 'mois';
  DateTime? _date, _dateRappel;
  /// Saisie groupée « autres animaux » — même bloc que le vermifuge.
  final _options = OptionsVermifuge();

  @override
  void initState() {
    super.initState();
    final e = widget.existant;
    if (e != null) {
      _produit.text = (e['produit'] ?? '').toString();
      _notes.text = (e['notes'] ?? '').toString();
      if (['pipette', 'collier', 'comprimé', 'spray', 'autre'].contains(e['type'])) _type = e['type'] as String;
      final f = _frequenceDe(e['frequence']);
      if (f != null) { _frequenceValeur.text = f.$1; _frequenceUnite = f.$2; }
      _date = DateTime.tryParse(e['date']?.toString() ?? '');
      _dateRappel = DateTime.tryParse(e['date_rappel']?.toString() ?? '');
    }
  }

  String get _frequenceLabel {
    final n = int.tryParse(_frequenceValeur.text.trim()) ?? 1;
    final unite = _frequenceUnite == 'jour' ? 'jour${n > 1 ? 's' : ''}'
        : _frequenceUnite == 'semaine' ? 'semaine${n > 1 ? 's' : ''}' : 'mois';
    return '$n $unite';
  }

  void _recomputeRappel() {
    if (_date == null) return;
    final n = int.tryParse(_frequenceValeur.text.trim()) ?? 1;
    if (n <= 0) return;
    final days = _frequenceUnite == 'jour' ? n : _frequenceUnite == 'semaine' ? n * 7 : n * 30;
    setState(() => _dateRappel = _date!.add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) => _BaseDialog(
      title: widget.existant != null ? 'Modifier l\'antiparasitaire' : 'Ajouter un antiparasitaire', fields: [
    _DDrop('Type', _type, ['pipette', 'collier', 'comprimé', 'spray', 'autre'], (v) => setState(() => _type = v!)),
    _DF('Produit *', _produit),
    _DD('Date application *', _date, (d) { setState(() => _date = d); _recomputeRappel(); }),
    _DCustom(Row(children: [
      Expanded(flex: 2, child: TextFormField(
        controller: _frequenceValeur, keyboardType: TextInputType.number,
        onChanged: (_) => _recomputeRappel(),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(labelText: 'Fréquence',
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true))),
      const SizedBox(width: 8),
      Expanded(flex: 3, child: DropdownButtonFormField<String>(
        initialValue: _frequenceUnite,
        items: const [
          DropdownMenuItem(value: 'jour', child: Text('Jour(s)')),
          DropdownMenuItem(value: 'semaine', child: Text('Semaine(s)')),
          DropdownMenuItem(value: 'mois', child: Text('Mois')),
        ],
        onChanged: (v) { setState(() => _frequenceUnite = v!); _recomputeRappel(); },
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true))),
    ])),
    // Saisie groupée : réservée au propriétaire (pas au vétérinaire).
    if (widget.vetId == null && widget.existant == null) _DCustom(AutresAnimauxSection(animalId: widget.animalId, options: _options)),
    // Calculé à partir de la date et de la fréquence : non modifiable.
    _DLecture('Prochain rappel (calculé)',
        _dateRappel != null ? DateFormat('dd/MM/yyyy').format(_dateRappel!) : 'Selon la date et la fréquence'),
    _DF('Notes', _notes, maxLines: 2),
  ], onSave: () async {
    if (_produit.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le produit.');
    controlerDatesSante(date: _date, rappel: _dateRappel);
    final e = widget.existant;
    if (e != null) {
      await _majSante('antiparasitaires', e, {
        'produit': _produit.text.trim(), 'type': _type,
        'date': _date!.toIso8601String(), 'date_rappel': _dateRappel?.toIso8601String(),
        'frequence': _frequenceLabel, 'notes': _notes.text.trim(),
      });
      final avant = DateTime.tryParse(e['date_rappel']?.toString() ?? '');
      if (_dateRappel != null && (avant == null || !DateUtils.isSameDay(avant, _dateRappel))) {
        await _scheduleRappelAgenda(animalId: widget.animalId, dateRappel: _dateRappel!, titre: 'Rappel antiparasitaire — ${_produit.text.trim()}');
      }
      return true;
    }
    final cibles = [widget.animalId, ..._options.autresAnimaux];
    final base = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < cibles.length; i++) {
      final id = '${base + i}';
      await Supabase.instance.client.from('antiparasitaires').insert({
        'id': id, 'animal_id': cibles[i],
        'type': _type, 'produit': _produit.text.trim(),
        'date': _date!.toIso8601String(),
        'date_rappel': _dateRappel?.toIso8601String(),
        'frequence': _frequenceLabel, 'notes': _notes.text.trim(),
        'source': widget.source,
        if (widget.vetId != null) 'vet_id': widget.vetId,
      });
      RegistreHelper.writeActe(
        animalId: cibles[i], typeActe: 'antiparasitaire', dateActe: _date!,
        intervenant: widget.vetName ?? '',
        description: '${_produit.text.trim()} ($_type)',
        sourceTable: 'antiparasitaires', sourceId: id,
      );
    }
    // Prochain rappel : un seul événement d'agenda pour tous les animaux.
    if (_dateRappel != null) {
      await _scheduleRappelAgenda(
        animalId: widget.animalId,
        dateRappel: _dateRappel!,
        titre: 'Rappel antiparasitaire — ${_produit.text.trim()}',
        autres: _options.autresAnimaux.toList(),
      );
    }
    if (widget.vetId != null) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyOwnerVetEntry')
            .call({'animalId': widget.animalId, 'vetName': widget.vetName ?? '', 'typeActe': 'traitement'});
      } catch (_) {}
    }
    return true;
  });
}

// ── Chirurgie / Hospitalisation ─────────────────────────────────────────────
// Sert surtout à PLANIFIER : date prévue + protocole pré-op (jeûne,
// prémédication, anesthésie…) et post-op (analgésie, soins, contrôle…).
class AddChirurgieDialog extends StatefulWidget {
  final String animalId;
  final String source;
  final String? vetId;
  final String? vetName;
  const AddChirurgieDialog({super.key, required this.animalId,
      this.source = 'owner', this.vetId, this.vetName});
  @override
  State<AddChirurgieDialog> createState() => _AddChirurgieDialogState();
}

class _AddChirurgieDialogState extends State<AddChirurgieDialog> {
  final _intitule = TextEditingController();
  final _clinique = TextEditingController();
  final _preop    = TextEditingController();
  final _postop   = TextEditingController();
  final _notes    = TextEditingController();
  String _type   = 'chirurgie';
  String _statut = 'prevu';
  DateTime? _date;

  @override
  void dispose() {
    _intitule.dispose(); _clinique.dispose(); _preop.dispose();
    _postop.dispose(); _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BaseDialog(
    title: 'Chirurgie / Hospitalisation',
    fields: [
      _DDrop('Type', _type, const ['chirurgie', 'hospitalisation'],
          (v) => setState(() => _type = v ?? 'chirurgie')),
      _DF('Intervention *', _intitule),
      _DD('Date (prévue ou réalisée) *', _date, (d) {
        setState(() {
          _date = d;
          _statut = d.isBefore(DateTime.now()) ? 'realise' : 'prevu';
        });
      }),
      _DDrop('Statut', _statut, const ['prevu', 'realise', 'annule'],
          (v) => setState(() => _statut = v ?? 'prevu')),
      _DF('Clinique / vétérinaire', _clinique),
      _DF('Protocole pré-opératoire\n(jeûne, prémédication, anesthésie…)', _preop, maxLines: 3),
      _DF('Protocole post-opératoire\n(analgésie, soins de plaie, repos, contrôle…)', _postop, maxLines: 3),
      _DF('Notes', _notes, maxLines: 2),
    ],
    onSave: () async {
      if (_intitule.text.trim().isEmpty) throw const SaisieInvalide('Indiquez l\'intitulé.');
      controlerDatesSante(date: _date, statut: _statut);
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await Supabase.instance.client.from('chirurgies').insert({
        'id': id, 'animal_id': widget.animalId,
        'type': _type,
        'intitule': _intitule.text.trim(),
        'date': _date!.toIso8601String(),
        'statut': _statut,
        'protocole_preop': _preop.text.trim(),
        'protocole_postop': _postop.text.trim(),
        'clinique': _clinique.text.trim(),
        'veterinaire': widget.vetName ?? _clinique.text.trim(),
        'notes': _notes.text.trim(),
        'source': widget.source,
        if (widget.vetId != null) 'vet_id': widget.vetId,
      });
      if (_statut == 'prevu' && _date!.isAfter(DateTime.now())) {
        await _scheduleRappelAgenda(
          animalId: widget.animalId,
          dateRappel: _date!,
          titre: '${_type == 'hospitalisation' ? 'Hospitalisation' : 'Chirurgie'} prévue — ${_intitule.text.trim()}',
        );
      }
      if (widget.vetId != null) {
        try {
          await FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('notifyOwnerVetEntry')
              .call({'animalId': widget.animalId, 'vetName': widget.vetName ?? '',
                  'typeActe': _type == 'hospitalisation' ? 'hospitalisation' : 'chirurgie'});
        } catch (_) {}
      }
      return true;
    },
  );
}

// ─── Génétique & bilan reproduction (onglet Repro) ───────────────────────────

class _GenetiqueSection extends StatefulWidget {
  final String animalId;
  final String espece;
  final bool readOnly;
  final DateTime? dateNaissance;
  const _GenetiqueSection({required this.animalId, required this.espece, this.readOnly = false, this.dateNaissance});
  @override
  State<_GenetiqueSection> createState() => _GenetiqueSectionState();
}

class _GenetiqueSectionState extends State<_GenetiqueSection> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _tests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _supa
          .from('tests_genetiques')
          .select()
          .eq('animal_id', widget.animalId)
          .order('date_test', ascending: false);
      if (mounted) {
        setState(() {
          _tests = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncAdnFlag() async {
    final etabli = _tests.any((t) => t['categorie'] == 'adn' && t['resultat'] == 'etabli');
    try {
      await _supa.from('animaux').update({'profil_adn_etabli': etabli}).eq('id', widget.animalId);
    } catch (_) {}
  }

  Future<void> _add({Map<String, dynamic>? existing}) async {
    // _BaseDialog se ferme sans valeur : on recharge toujours (avant : le test
    // enregistré n'apparaissait qu'après être revenu sur la fiche → doublons).
    await showDialog<void>(
      context: context,
      builder: (_) => _AddTestGenetiqueDialog(animalId: widget.animalId, espece: widget.espece,
          dateNaissance: widget.dateNaissance, existing: existing),
    );
    if (!mounted) return;
    await _load();
    await _syncAdnFlag();
  }

  /// Fiche complète d'un test (appui sur la ligne).
  void _detail(Map<String, dynamic> t) {
    final lien = lienWeb(t['lien_resultat']?.toString());
    final url = (t['url'] ?? '').toString().trim();
    final lignes = <(String, String)>[
      ('Catégorie', kGeneticTestCategorieLabels[t['categorie']] ?? (t['categorie'] ?? '').toString()),
      ('Résultat', kResultatsGenetiques[t['resultat']] ?? (t['resultat'] ?? '').toString()),
      ('Génotype', (t['genotype'] ?? '').toString()),
      ('Laboratoire', (t['laboratoire'] ?? '').toString()),
      ('Date du test', _fmtTgDate(t['date_test'])),
      ('Notes', (t['notes'] ?? '').toString()),
    ].where((l) => l.$2.trim().isNotEmpty).toList();
    const lab = TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B));
    const val = TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600);
    const lienSt = TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600,
        color: Color(0xFF0C5C6C), decoration: TextDecoration.underline);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((t['nom'] ?? 'Test').toString(),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 12),
          for (final l in lignes)
            Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 120, child: Text(l.$1, style: lab)),
              Expanded(child: Text(l.$2, style: val)),
            ])),
          if (lien.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 120, child: Text('Résultat en ligne', style: lab)),
              Expanded(child: GestureDetector(
                onTap: () => launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication),
                child: Text(lien, style: lienSt))),
            ])),
          if (url.startsWith('http'))
            Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 120, child: Text('Document joint', style: lab)),
              Expanded(child: GestureDetector(onTap: () => _openDoc(context, url), child: Text(nomFichier(url), style: lienSt))),
            ])),
          if (!widget.readOnly) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey')),
                onPressed: () { Navigator.pop(ctx); _add(existing: t); })),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey')),
                onPressed: () { Navigator.pop(ctx); _delete(t['id'].toString()); })),
            ]),
          ],
        ]),
      )),
    );
  }

  Future<void> _delete(String id) async {
    final t = _tests.firstWhere((x) => x['id']?.toString() == id, orElse: () => <String, dynamic>{});
    if (!await confirmerSuppressionSante(context, 'tests_genetiques', nom: t['nom']?.toString())) return;
    try {
      await _supa.from('tests_genetiques').delete().eq('id', id);
      await _load();
      await _syncAdnFlag();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.biotech_outlined, size: 18, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Génétique & tests',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E)))),
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.add, color: Color(0xFF6E9E57)),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              onPressed: _add,
            ),
        ]),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
        else if (_tests.isEmpty)
          Text('Aucun test renseigné', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400))
        else
          ..._tests.map((t) {
            final res = t['resultat'] as String?;
            final geno = (t['genotype'] as String?)?.trim() ?? '';
            final sub = [t['laboratoire'], _fmtTgDate(t['date_test'])]
                .where((e) => e != null && '$e'.isNotEmpty).join(' · ');
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: InkWell(onTap: () => _detail(t), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['nom'] ?? 'Test',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
                  if (sub.isNotEmpty)
                    Text(sub, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
                ]))),
                if (res != null || geno.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: resultatBg(res), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      res != null ? (kResultatsGenetiques[res] ?? res) : geno,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, fontWeight: FontWeight.w600, color: resultatColor(res)),
                    ),
                  ),
                if (lienWeb(t['lien_resultat']?.toString()).isNotEmpty)
                  IconButton(
                    tooltip: 'Résultat en ligne',
                    icon: const Icon(Icons.link, size: 16, color: Color(0xFF0C5C6C)),
                    padding: const EdgeInsets.only(left: 4), constraints: const BoxConstraints(),
                    onPressed: () => launchUrl(Uri.parse(lienWeb(t['lien_resultat']?.toString())), mode: LaunchMode.externalApplication),
                  ),
                if ((t['url'] as String?)?.isNotEmpty == true)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF0C5C6C)),
                    padding: const EdgeInsets.only(left: 4), constraints: const BoxConstraints(),
                    onPressed: () => _openDoc(context, t['url'] as String),
                  ),
                if (!widget.readOnly)
                  IconButton(
                    tooltip: 'Modifier',
                    icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF0C5C6C)),
                    padding: const EdgeInsets.only(left: 4), constraints: const BoxConstraints(),
                    onPressed: () => _add(existing: t),
                  ),
                if (!widget.readOnly)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    padding: const EdgeInsets.only(left: 4), constraints: const BoxConstraints(),
                    onPressed: () => _delete(t['id'] as String),
                  ),
              ]),
            );
          }),
      ]),
    );
  }
}

String _fmtTgDate(dynamic v) {
  if (v == null) return '';
  final d = DateTime.tryParse(v.toString());
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
}

class _AddTestGenetiqueDialog extends StatefulWidget {
  final String animalId;
  final String espece;
  final DateTime? dateNaissance;
  /// Test à modifier (mêmes champs qu'à la création).
  final Map<String, dynamic>? existing;
  const _AddTestGenetiqueDialog({required this.animalId, required this.espece, this.dateNaissance, this.existing});
  @override
  State<_AddTestGenetiqueDialog> createState() => _AddTestGenetiqueDialogState();
}

class _AddTestGenetiqueDialogState extends State<_AddTestGenetiqueDialog> {
  final _nomCtrl   = TextEditingController();
  final _genoCtrl  = TextEditingController();
  final _laboCtrl  = TextEditingController();
  final _notesCtrl = TextEditingController();
  // Lien du résultat en ligne (Embark, Wisdom Panel…) — en plus du fichier.
  final _lienCtrl  = TextEditingController();
  String _categorie = 'maladie';
  String? _selectedCode; // '' = saisie libre
  String _resultat = 'clair';
  DateTime? _date;
  String? _url;
  bool _uploading = false;

  List<GeneticTest> get _presets =>
      (kGeneticTests[widget.espece] ?? const []).where((t) => t.categorie == _categorie).toList();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) { _syncPreset(); return; }
    _categorie = (e['categorie'] ?? 'maladie').toString();
    final code = e['code']?.toString() ?? '';
    _selectedCode = _presets.any((t) => t.code == code) ? code : '';
    _nomCtrl.text = e['nom']?.toString() ?? '';
    _resultat = (e['resultat'] ?? 'clair').toString();
    _genoCtrl.text = e['genotype']?.toString() ?? '';
    _laboCtrl.text = e['laboratoire']?.toString() ?? '';
    _notesCtrl.text = e['notes']?.toString() ?? '';
    _lienCtrl.text = e['lien_resultat']?.toString() ?? '';
    _date = DateTime.tryParse(e['date_test']?.toString() ?? '');
    _url = e['url']?.toString();
  }

  void _syncPreset() {
    final list = _presets;
    if (list.isNotEmpty) {
      _selectedCode = list.first.code;
      _nomCtrl.text = list.first.nom;
    } else {
      _selectedCode = '';
      _nomCtrl.text = '';
    }
    if (_categorie == 'adn' || _categorie == 'complet') _resultat = 'etabli';
  }

  @override
  void dispose() {
    _nomCtrl.dispose(); _genoCtrl.dispose(); _laboCtrl.dispose(); _notesCtrl.dispose(); _lienCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
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
    if (choice == null || !mounted) return;
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
    setState(() => _uploading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final name = '${DateTime.now().millisecondsSinceEpoch}_${f.path.split('/').last}';
      final url = await uploadRawFile(f, 'documents/$uid/$name');
      if (mounted) setState(() => _url = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur upload : $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _BaseDialog(
    title: widget.existing != null ? 'Modifier le test génétique' : 'Test génétique',
    fields: [
      _DDrop('Catégorie', _categorie, kGeneticTestCategories,
          (v) => setState(() { _categorie = v ?? 'maladie'; _syncPreset(); })),
      if (_presets.isNotEmpty)
        _DDrop('Test', _selectedCode == '' ? '' : _selectedCode,
            ['', ..._presets.map((t) => t.code)],
            libelles: {'': 'Autre (saisie libre)', for (final t in _presets) t.code: t.nom},
            (v) => setState(() {
              _selectedCode = v;
              if (v != null && v.isNotEmpty) {
                _nomCtrl.text = _presets.firstWhere((t) => t.code == v).nom;
              } else {
                _nomCtrl.text = '';
              }
            })),
      if (_presets.isEmpty || _selectedCode == '')
        _DF('Nom du test *', _nomCtrl),
      if (_categorie != 'robe')
        _DDrop('Résultat', _resultat, kResultatsGenetiques.keys.toList(),
            (v) => setState(() => _resultat = v ?? 'clair')),
      _DF('Génotype / notation labo', _genoCtrl),
      _DF('Laboratoire', _laboCtrl),
      _DF('Lien du résultat en ligne (Embark, Wisdom Panel…)', _lienCtrl),
      _DD('Date du test', _date, (d) => setState(() => _date = d)),
      _DCustom(Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _uploading ? null : _pickFile,
          icon: _uploading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_url != null ? Icons.check_circle_outline : Icons.attach_file, size: 16),
          label: Text(_url != null ? 'Résultat joint' : 'Joindre le résultat (PDF/photo)',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
        ),
      )),
      _DF('Notes', _notesCtrl, maxLines: 2),
    ],
    onSave: () async {
      final nom = _nomCtrl.text.trim();
      if (nom.isEmpty) throw const SaisieInvalide('Indiquez le nom du test.');
      controlerDateTestGenetique(_date, widget.dateNaissance);
      if (_lienCtrl.text.trim().isNotEmpty && lienWeb(_lienCtrl.text).isEmpty) {
        throw const SaisieInvalide('Lien du résultat : adresse web invalide (ex. https://embarkvet.com/…).');
      }
      final presetHit = _presets.where((t) => t.code == _selectedCode).toList();
      final ligne = <String, dynamic>{
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'animal_id': widget.animalId,
        'uid': FirebaseAuth.instance.currentUser?.uid,
        if (User_Info.activeProfileId.isNotEmpty) 'profile_id': User_Info.activeProfileId,
        'espece': widget.espece,
        'categorie': _categorie,
        'code': presetHit.isNotEmpty ? presetHit.first.code : null,
        'nom': nom,
        'resultat': _categorie == 'robe' ? null : _resultat,
        'genotype': _genoCtrl.text.trim().isEmpty ? null : _genoCtrl.text.trim(),
        'laboratoire': _laboCtrl.text.trim().isEmpty ? null : _laboCtrl.text.trim(),
        'date_test': _date?.toIso8601String().substring(0, 10),
        'url': _url,
        if (lienWeb(_lienCtrl.text).isNotEmpty) 'lien_resultat': lienWeb(_lienCtrl.text)
        else if (widget.existing?['lien_resultat'] != null) 'lien_resultat': null,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };
      if (widget.existing != null) ligne.remove('id');
      // Colonne lien_resultat absente en base (migration_tests_genetiques_lien.sql
      // pas passée) : le test est enregistré sans le lien plutôt que refusé.
      Future<void> ecrire() => widget.existing != null
          ? Supabase.instance.client.from('tests_genetiques').update(ligne).eq('id', widget.existing!['id'])
          : Supabase.instance.client.from('tests_genetiques').insert(ligne);
      try {
        await ecrire();
      } on PostgrestException catch (e) {
        // 42703 en lecture, PGRST204 en écriture (« Could not find the 'lien_resultat' column »).
        if (!const {'42703', 'PGRST204'}.contains(e.code) || !ligne.containsKey('lien_resultat')) rethrow;
        ligne.remove('lien_resultat');
        await ecrire();
      }
      return true;
    },
  );
}

class _BilanReproCard extends StatefulWidget {
  final String animalId;
  final String espece;
  final bool readOnly;
  const _BilanReproCard({required this.animalId, required this.espece, this.readOnly = false});
  @override
  State<_BilanReproCard> createState() => _BilanReproCardState();
}

class _BilanReproCardState extends State<_BilanReproCard> {
  final _supa = Supabase.instance.client;
  final _nbCtrl = TextEditingController();
  final _histCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int _gestConfirmees = 0;
  int _petitsNes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nbCtrl.dispose(); _histCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final animal = await _supa.from('animaux')
          .select('nb_petits_produits, historique_fertilite')
          .eq('id', widget.animalId).maybeSingle();
      final gests = await _supa.from('gestations')
          .select('nb_nes, gestation_confirmee')
          .eq('animal_id', widget.animalId);
      var conf = 0, nes = 0;
      for (final g in (gests as List)) {
        if (g['gestation_confirmee'] == true) conf++;
        final n = g['nb_nes'];
        if (n is num) nes += n.toInt();
      }
      if (mounted) {
        setState(() {
          _nbCtrl.text = animal?['nb_petits_produits']?.toString() ?? '';
          _histCtrl.text = (animal?['historique_fertilite'] as String?) ?? '';
          _gestConfirmees = conf;
          _petitsNes = nes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _supa.from('animaux').update({
        'nb_petits_produits': int.tryParse(_nbCtrl.text.trim()),
        'historique_fertilite': _histCtrl.text.trim().isEmpty ? null : _histCtrl.text.trim(),
      }).eq('id', widget.animalId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bilan enregistré', style: TextStyle(fontFamily: 'Galey'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final word = offspringWord(widget.espece);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.insights_outlined, size: 18, color: Color(0xFF6E9E57)),
                SizedBox(width: 8),
                Text('Bilan reproduction',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _nbCtrl,
                readOnly: widget.readOnly,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Nombre de $word produits',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _histCtrl,
                readOnly: widget.readOnly,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Historique de fertilité',
                  hintText: 'Ex : 12 saillies 2024, 9 poulains vivants, jument facile à suivre…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF9CA3AF)),
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              if (_gestConfirmees > 0 || _petitsNes > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(
                    'Suggéré d\'après le suivi : $_gestConfirmees gestation(s) confirmée(s) · $_petitsNes $word nés',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B)))),
                  if (!widget.readOnly)
                    TextButton(
                      onPressed: () => setState(() {
                        if (_petitsNes > 0) _nbCtrl.text = _petitsNes.toString();
                      }),
                      child: const Text('Utiliser', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    ),
                ]),
              ],
              if (!widget.readOnly) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6E9E57), foregroundColor: Colors.white),
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey')),
                  ),
                ),
              ],
            ]),
    );
  }
}

class _AddAllergieDialog extends StatefulWidget {
  final String animalId;
  final String source;
  final String? vetId;
  final String? vetName;
  const _AddAllergieDialog({required this.animalId, this.source = 'owner', this.vetId, this.vetName});
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
    if (_description.text.trim().isEmpty) throw const SaisieInvalide('Indiquez la description de l\'allergie.');
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await Supabase.instance.client.from('allergies').insert({
      'id': id, 'animal_id': widget.animalId,
      'type': _type, 'description': _description.text.trim(),
      'severite': _severite, 'notes': _notes.text.trim(),
      'source': widget.source,
      if (widget.vetId != null) 'vet_id': widget.vetId,
    });
    if (widget.vetId != null) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyOwnerVetEntry')
            .call({'animalId': widget.animalId, 'vetName': widget.vetName ?? '', 'typeActe': 'allergie'});
      } catch (_) {}
    }
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
  final _dateCtrl = TextEditingController();
  DateTime? _date;
  DateTime? _naissance; // borne basse du calendrier de la pesée
  String _unite = 'kg'; // 'g' ou 'kg' — stockage toujours en kg

  DateTime? _parseFrDate(String s) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    final dt = DateTime(y, mo, d);
    if (dt.day != d || dt.month != mo) return null;
    return dt;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _date = e['date'] != null ? DateTime.tryParse(e['date'] as String) : null;
      final kg = double.tryParse(e['valeur']?.toString().replaceAll(',', '.') ?? '');
      if (kg != null) {
        if (kg < 1) { _unite = 'g'; _valeur.text = _fmtInput(kg * 1000); }
        else        { _unite = 'kg'; _valeur.text = _fmtInput(kg); }
      }
      _notes.text = (e['notes'] as String?) ?? '';
    } else {
      _prefillUnite();
    }
    _chargerNaissance();
    if (_date != null) _dateCtrl.text = DateFormat('dd/MM/yyyy').format(_date!);
  }

  // Nouvelle pesée : on reprend l'unité de la dernière pesée de l'animal
  // (un bébé pesé en g reste en g par défaut).
  Future<void> _chargerNaissance() async {
    try {
      final a = await Supabase.instance.client.from('animaux').select('date_naissance')
          .eq('id', widget.animalId).maybeSingle();
      final n = DateTime.tryParse(a?['date_naissance']?.toString() ?? '');
      if (n != null && mounted) setState(() => _naissance = DateTime(n.year, n.month, n.day));
    } catch (_) {}
  }

  Future<void> _prefillUnite() async {
    try {
      final last = await Supabase.instance.client
          .from('poids').select('valeur').eq('animal_id', widget.animalId)
          .order('date', ascending: false).limit(1).maybeSingle();
      final kg = double.tryParse(last?['valeur']?.toString() ?? '');
      if (kg != null && kg < 1 && mounted) setState(() => _unite = 'g');
    } catch (_) {}
  }

  String _fmtInput(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  void _switchUnite(String u) {
    if (u == _unite) return;
    final v = double.tryParse(_valeur.text.replaceAll(',', '.'));
    setState(() {
      _unite = u;
      if (v != null) _valeur.text = _fmtInput(u == 'g' ? v * 1000 : v / 1000);
    });
  }

  double? get _valeurKg {
    final v = double.tryParse(_valeur.text.replaceAll(',', '.'));
    if (v == null) return null;
    return _unite == 'g' ? v / 1000 : v;
  }

  @override
  void dispose() { _valeur.dispose(); _notes.dispose(); _dateCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _BaseDialog(
    title: widget.existing != null ? 'Modifier la pesée' : 'Ajouter une pesée',
    fields: [
      _DCustom(TextField(
        controller: _dateCtrl,
        keyboardType: TextInputType.datetime,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
          LengthLimitingTextInputFormatter(10),
        ],
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
        onChanged: (s) {
          final d = _parseFrDate(s);
          if (d != null) setState(() => _date = d);
        },
        decoration: InputDecoration(
          labelText: 'Date *',
          hintText: 'jj/mm/aaaa',
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF6E9E57))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          isDense: true,
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF6E9E57)),
            onPressed: () async {
              // Pesée : ni avant la naissance, ni après aujourd'hui.
              final debut = _naissance ?? DateTime(2000);
              final fin = DateTime.now();
              var initiale = _date ?? fin;
              if (initiale.isBefore(debut)) initiale = debut;
              if (initiale.isAfter(fin)) initiale = fin;
              final p = await showDatePicker(
                context: context, initialDate: initiale,
                firstDate: debut, lastDate: fin,
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
                  child: child!),
              );
              if (p != null) {
                setState(() => _date = p);
                _dateCtrl.text = DateFormat('dd/MM/yyyy').format(p);
              }
            },
          ),
        ),
      )),
      _DCustom(Row(children: [
        Expanded(
          child: TextField(
            controller: _valeur,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Poids *',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF6E9E57))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _UniteSeg(value: _unite, onChanged: _switchUnite),
      ])),
      _DF('Notes', _notes),
    ],
    onSave: () async {
      // Pesée : « 8,5 » ou « 8.5 », plausible pour l'espèce, datée entre la
      // naissance et aujourd'hui (messages affichés par la feuille).
      Map<String, dynamic>? a;
      try {
        a = await Supabase.instance.client.from('animaux').select('espece, date_naissance')
            .eq('id', widget.animalId).maybeSingle();
      } catch (_) {}
      final err = erreurPoids(_valeur.text, espece: a?['espece']?.toString(), unite: _unite);
      if (err != null) throw SaisieInvalide(err);
      if (_valeur.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le poids.');
      final kg = _valeurKg;
      final d = _parseFrDate(_dateCtrl.text) ?? _date;
      if (d == null) throw const SaisieInvalide('Indiquez la date de la pesée (jj/mm/aaaa).');
      if (d.isAfter(DateTime.now())) throw const SaisieInvalide('La date de la pesée ne peut pas être dans le futur.');
      final naissance = DateTime.tryParse(a?['date_naissance']?.toString() ?? '');
      if (naissance != null && d.isBefore(DateTime(naissance.year, naissance.month, naissance.day))) {
        throw const SaisieInvalide('La date de la pesée est antérieure à la naissance de l\'animal.');
      }
      if (kg == null) return false;
      final payload = {
        'valeur': kg,
        'date':   d.toIso8601String(),
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

class _UniteSeg extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _UniteSeg({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String u) {
      final active = value == u;
      return GestureDetector(
        onTap: () => onChanged(u),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          color: active ? const Color(0xFF6E9E57) : Colors.transparent,
          child: Text(u, style: TextStyle(
              fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700,
              color: active ? Colors.white : const Color(0xFF6F767B))),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE4E7E2)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('g'),
        Container(width: 1, height: 34, color: const Color(0xFFE4E7E2)),
        seg('kg'),
      ]),
    );
  }
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

// ─── Bannière cycle suspendu (stérilisée / retraite / lactation) ─────────────

class _CycleSuspenduBanner extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CycleSuspenduBanner({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF5EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6E9E57)),
      ),
      child: Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12.5, color: Color(0xFF4A7A3A)))),
      ]),
    );
  }
}

// ─── Bannière prochaine chaleur ───────────────────────────────────────────────

class _NextHeatBanner extends StatelessWidget {
  final DateTime nextHeat;
  final String espece;
  final String? race;
  final int? raceIntervalDays;
  final int? animalOverrideDays;
  const _NextHeatBanner({required this.nextHeat, required this.espece, this.race, this.raceIntervalDays, this.animalOverrideDays});

  String _intervalInfo() {
    if (animalOverrideDays != null && animalOverrideDays! > 0) {
      return 'Intervalle personnalisé (cet animal) : $animalOverrideDays j';
    }
    if (raceIntervalDays != null && raceIntervalDays! > 0) {
      return 'Protocole ${race ?? ''} : $raceIntervalDays j';
    }
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
  final String? race;
  final String? uidEleveur;
  final int? intervalleCustom;
  final bool readOnly;
  final bool sterilise;
  final DateTime? dateNaissance;
  const _ChaleursTab({required this.animalId, required this.espece, this.race, this.uidEleveur,
      this.intervalleCustom, this.readOnly = false, this.sterilise = false, this.dateNaissance});
  @override State<_ChaleursTab> createState() => _ChaleursTabState();
}

class _ChaleursTabState extends State<_ChaleursTab> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;
  int? _intervalleCustom; // local copy, editable
  DateTime? _lastMiseBas;
  List<RaceIntervalEntry> _raceIntervals = [];

  // Même convention que le rappel de chaleurs (chaleurs_notif_service.dart) :
  // âge de retraite par espèce + fenêtre de lactation suspendant le cycle.
  static const _agesRetraite = <String, int>{
    'chien': 7, 'chat': 8, 'lapin': 5,
    'cheval': 18, 'ovin': 8, 'caprin': 8, 'porcin': 5, 'ane': 15,
  };
  static const _joursLactation = 56;

  bool get _enRetraite {
    final naissance = widget.dateNaissance;
    final age = _agesRetraite[widget.espece.toLowerCase()];
    if (naissance == null || age == null) return false;
    final dateRetraite = DateTime(naissance.year + age, naissance.month, naissance.day);
    return !DateTime.now().isBefore(dateRetraite);
  }

  bool get _enLactation {
    final miseBas = _lastMiseBas;
    if (miseBas == null) return false;
    return DateTime.now().difference(miseBas).inDays < _joursLactation;
  }

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
      DateTime? lastMiseBas;
      try {
        // Mise bas saisie, sinon date estimée d'une gestation confirmée.
        final gests = await _supa.from('gestations')
            .select(colonnesGestationsMiseBas)
            .eq('animal_id', widget.animalId)
            .or(filtreGestationsMiseBas);
        lastMiseBas = dernieresMisesBas(gests as List)[widget.animalId];
      } catch (_) {}
      final raceIntervals = await ChaleurIntervalService.loadRaceIntervals(widget.uidEleveur ?? '');
      if (mounted) setState(() {
        _data = List<Map<String, dynamic>>.from(rows);
        _lastMiseBas = lastMiseBas;
        _raceIntervals = raceIntervals;
        _loading = false;
      });
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
    final effectiveInterval = ChaleurIntervalService.resolve(
      raceIntervals: _raceIntervals, espece: widget.espece, race: widget.race, animalOverride: _intervalleCustom,
    );
    // Stérilisée / en retraite / mise-bas récente (< 8 sem., allaitement) :
    // le cycle est suspendu ou terminé — pas d'alerte « chaleurs » trompeuse.
    final cycleSuspendu = widget.sterilise || _enRetraite || _enLactation;
    final nextHeat = !cycleSuspendu && effectiveInterval > 0
        ? (() {
            DateTime? last;
            if (_data.isNotEmpty) {
              final sorted = [..._data]..sort((a, b) {
                  final da = DateTime.tryParse(a['date'] ?? '') ?? DateTime(2000);
                  final db = DateTime.tryParse(b['date'] ?? '') ?? DateTime(2000);
                  return db.compareTo(da);
                });
              last = DateTime.tryParse(sorted.first['date'] ?? '');
            }
            // Une mise-bas postérieure à la dernière chaleur enregistrée
            // redémarre le cycle : sans ça, une femelle qui vient de mettre
            // bas retombe, une fois la lactation passée, sur sa dernière
            // chaleur d'AVANT la gestation, largement dépassée.
            final miseBas = _lastMiseBas;
            final effectiveLast = (miseBas != null && (last == null || miseBas.isAfter(last)))
                ? miseBas : last;
            return effectiveLast?.add(Duration(days: effectiveInterval));
          })()
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: widget.readOnly ? null : FloatingActionButton.small(
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
          if (widget.sterilise)
            _CycleSuspenduBanner(
                icon: Icons.block, label: 'Stérilisée — plus de cycle de chaleurs à suivre.')
          else if (_enRetraite)
            _CycleSuspenduBanner(
                icon: Icons.eco_outlined, label: 'En retraite reproductive — plus de cycle à suivre.')
          else if (_enLactation)
            _CycleSuspenduBanner(
                icon: Icons.child_friendly_outlined,
                label: _lastMiseBas!.isAfter(DateTime.now())
                    ? 'Gestation confirmée — cycle suspendu jusqu\'à la mise-bas puis pendant l\'allaitement.'
                    : 'Mise-bas récente — cycle suspendu pendant l\'allaitement.')
          else if (nextHeat != null)
            _NextHeatBanner(
              nextHeat: nextHeat, espece: widget.espece, race: widget.race,
              raceIntervalDays: ChaleurIntervalService.raceIntervalFor(
                raceIntervals: _raceIntervals, espece: widget.espece, race: widget.race,
              ),
              animalOverrideDays: _intervalleCustom,
            ),
          // Intervalle row
          GestureDetector(
            onTap: widget.readOnly ? null : _editIntervalle,
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
                  (() {
                    if (_intervalleCustom != null) return 'Intervalle personnalisé : $_intervalleCustom jours';
                    final raceInterval = ChaleurIntervalService.raceIntervalFor(
                      raceIntervals: _raceIntervals, espece: widget.espece, race: widget.race,
                    );
                    if (raceInterval != null) return 'Protocole ${widget.race} : $raceInterval jours';
                    return 'Intervalle par défaut (${widget.espece}) : ${_intervalChaleursJours(widget.espece)} jours';
                  })(),
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
              readOnly: widget.readOnly,
              onDelete: () => _delete(d['id']?.toString() ?? ''),
              onEdit: widget.readOnly ? null : () async {
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
        // Protocoles automatiques chaleurs
        try {
          final uidAuto = FirebaseAuth.instance.currentUser?.uid;
          if (uidAuto != null) {
            await PlanningService.triggerAutoProtocoles(
              uid: uidAuto,
              declencheur: 'chaleurs',
              animalId: widget.animalId,
              dateEvenement: _date!,
              espece: widget.espece,
            );
          }
        } catch (_) {}
      }
      return true;
    },
  );
}

// ─── Helper rappels agenda ────────────────────────────────────────────────────

/// Nom du vétérinaire connecté, inscrit sur ses saisies du carnet.
String _nomVeterinaire() => '${User_Info.firstname} ${User_Info.lastname}'.trim();

/// Saisie au carnet avec le formulaire complet de la rubrique (le même que
/// dans le carnet), au nom du vétérinaire connecté — utilisée par le compte
/// rendu de consultation. Enregistrée tout de suite dans la bonne rubrique.
Future<void> saisirAuCarnet(BuildContext context, {required String animalId, required String collection, String? espece}) {
  final vid = FirebaseAuth.instance.currentUser?.uid;
  final vname = _nomVeterinaire();
  final Widget dialogue = switch (collection) {
    'vermifuges' => AddVermifugeDialog(animalId: animalId, source: 'veterinaire', vetId: vid, vetName: vname),
    'antiparasitaires' => AddAntiparasitaireDialog(animalId: animalId, source: 'veterinaire', vetId: vid, vetName: vname),
    'allergies' => _AddAllergieDialog(animalId: animalId, source: 'veterinaire', vetId: vid, vetName: vname),
    'chirurgies' => AddChirurgieDialog(animalId: animalId, source: 'veterinaire', vetId: vid, vetName: vname),
    'radios' => _AddRadioDialog(animalId: animalId, vetId: vid, vetName: vname),
    _ => _AddVaccinDialog(animalId: animalId, espece: espece, source: 'veterinaire', vetId: vid, vetName: vname),
  };
  return showDialog(context: context, builder: (_) => dialogue);
}

Future<void> _scheduleRappelAgenda({
  required String animalId,
  required DateTime dateRappel,
  required String titre,
  /// Autres animaux traités en même temps : un seul rappel pour le groupe.
  List<String> autres = const [],
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    String finalTitre = titre;
    try {
      final rows = await Supabase.instance.client
          .from('animaux').select('nom').inFilter('id', [animalId, ...autres]);
      final noms = [for (final a in rows as List) if ((a['nom'] as String?)?.isNotEmpty == true) a['nom'] as String];
      if (noms.isNotEmpty) {
        finalTitre = noms.length > 4 ? '$titre (${noms.take(4).join(', ')} +${noms.length - 4})' : '$titre (${noms.join(', ')})';
      }
    } catch (_) {}
    // Stocke à 08h00 UTC pour affichage correct en France (évite minuit UTC = 02h00 local)
    final dateAt8 = DateTime(dateRappel.year, dateRappel.month, dateRappel.day, 8, 0).toUtc();
    // Ne jamais écrire une chaîne vide : les vues agenda filtrent par
    // pro_profile_id = activeProfileId, une chaîne vide ne matche jamais
    // rien et rend le rappel invisible partout.
    // Profil propriétaire de l'animal (un rappel de l'élevage reste dans
    // l'agenda de l'élevage, même créé depuis l'association).
    var proProfileId = await profilPourAnimal(animalId);
    if (proProfileId.isEmpty) {
      try {
        final row = await Supabase.instance.client.from('user_profiles_complet')
            .select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
        proProfileId = row?['id']?.toString() ?? '';
      } catch (_) {}
    }
    await Supabase.instance.client.from('agenda_events').insert({
      'uid':            uid,
      'titre':          finalTitre,
      'type':           'medication',
      'date_debut':     dateAt8.toIso8601String(),
      'animal_id':      animalId,
      'pro_profile_id': proProfileId.isNotEmpty ? proProfileId : null,
      if (proProfileId.isNotEmpty) 'profile_id': proProfileId,
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

/// Fenêtre de mise-bas estimée à partir des dates de saillie d'un même
/// épisode (une chaleur). Début = 1re saillie + durée gestation ;
/// fin = dernière saillie + durée gestation ; probable = milieu des deux.
/// Retourne null si l'espèce n'a pas de durée connue ou si aucune date.
({DateTime debut, DateTime fin, DateTime probable})? _fenetreMiseBas(
    List<DateTime> saillies, String espece) {
  final n = _gestationJours(espece);
  if (n <= 0 || saillies.isEmpty) return null;
  final sorted = [...saillies]..sort();
  final debut = DateTime(sorted.first.year, sorted.first.month, sorted.first.day)
      .add(Duration(days: n));
  final fin = DateTime(sorted.last.year, sorted.last.month, sorted.last.day)
      .add(Duration(days: n));
  final probable = DateTime.fromMillisecondsSinceEpoch(
      (debut.millisecondsSinceEpoch + fin.millisecondsSinceEpoch) ~/ 2);
  return (debut: debut, fin: fin, probable: probable);
}

/// Parse une valeur `dates` (jsonb) en liste de DateTime triée.
/// Accepte une List, ou retombe sur [fallbackDate] si absente/vide.
List<DateTime> _parseSaillieDates(dynamic raw, {String? fallbackDate}) {
  final out = <DateTime>[];
  if (raw is List) {
    for (final v in raw) {
      final d = DateTime.tryParse(v.toString());
      if (d != null) out.add(d);
    }
  }
  if (out.isEmpty && fallbackDate != null && fallbackDate.isNotEmpty) {
    final d = DateTime.tryParse(fallbackDate);
    if (d != null) out.add(d);
  }
  out.sort();
  return out;
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
  // Dates de saillie de l'épisode (une chaleur) : saillie 1, 2, 3…
  final List<DateTime> _dates = [];
  String? _selectedPartenaireId;
  // Reproducteurs éligibles (utils/reproducteurs.dart) : mon élevage / extérieurs
  List<Reproducteur> _partenaires = [];
  List<Reproducteur> _exterieurs = [];
  bool _loadingPartenaires = true;
  String _provenance = 'elevage'; // 'elevage' | 'exterieur'
  String? _raisonAnimalNonEligible; // l'animal de la fiche lui-même (nouvelle saillie)
  String? _erreur;

  String get _sexePartenaire => widget.sexeAnimal == 'male' ? 'femelle' : 'male';
  String get _libellePartenaire => _sexePartenaire == 'male' ? 'un étalon' : 'une reproductrice';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _dates.addAll(_parseSaillieDates(e['dates'],
          fallbackDate: e['date']?.toString()));
      _nomPartenaire.text   = e['nom_partenaire'] ?? '';
      _identPartenaire.text = e['ident_partenaire'] ?? '';
      _methode = e['methode'] ?? 'naturelle';
      _notes.text = e['notes'] ?? '';
      _selectedPartenaireId = e['partenaire_animal_id'] as String?;
      if ((_selectedPartenaireId ?? '').isEmpty && _nomPartenaire.text.isNotEmpty) _provenance = 'exterieur';
    }
    _loadPartenaires();
  }

  Future<void> _loadPartenaires() async {
    try {
      // Élevage propriétaire de la fiche (pas forcément l'utilisateur connecté :
      // cogérant, salarié)
      final animal = await Supabase.instance.client.from('animaux')
          .select('uid_eleveur, reproducteur, is_retraite, sterilise, statut')
          .eq('id', widget.animalId).maybeSingle();
      final uid = (animal?['uid_eleveur'] as String?) ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      final results = await Future.wait([
        chargerReproducteurs(uidEleveur: uid, sexe: _sexePartenaire, espece: widget.espece, exclureId: widget.animalId),
        chargerReproducteursExterieurs(uidEleveur: uid, sexe: _sexePartenaire, espece: widget.espece),
      ]);
      if (!mounted) return;
      setState(() {
        _partenaires = results[0];
        _exterieurs = results[1];
        _raisonAnimalNonEligible = animal == null ? null : raisonNonEligible(animal);
        _loadingPartenaires = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPartenaires = false);
    }
  }

  Future<void> _choisirInterne() async {
    final r = await choisirReproducteur(context,
        titre: _sexePartenaire == 'male' ? 'Sélectionner un étalon' : 'Sélectionner une reproductrice',
        options: _partenaires,
        vide: _sexePartenaire == 'male'
            ? 'Aucun mâle reproducteur actif. Cochez « Reproducteur » sur la fiche de vos mâles (ni retraités, ni stérilisés, ni cédés).'
            : 'Aucune femelle reproductrice active. Cochez « Reproducteur » sur la fiche de vos femelles (ni retraitées, ni stérilisées, ni cédées).');
    if (r == null || !mounted) return;
    setState(() {
      _selectedPartenaireId = r.id;
      _nomPartenaire.text = r.nom;
      _identPartenaire.text = r.identification ?? '';
      _erreur = null;
    });
  }

  Future<void> _choisirExterieur() async {
    final r = await choisirReproducteur(context,
        titre: _sexePartenaire == 'male' ? 'Étalon extérieur' : 'Reproductrice extérieure',
        options: _exterieurs,
        vide: 'Aucun reproducteur extérieur enregistré. Saisissez-le ci-dessous.');
    if (r == null || !mounted) return;
    setState(() {
      _selectedPartenaireId = null; // jamais rattaché au cheptel
      _nomPartenaire.text = r.nom;
      _identPartenaire.text = r.identification ?? '';
      _erreur = null;
    });
  }

  /// Bloc « partenaire » : sélecteur compact (mon élevage) ou extérieur.
  List<Widget> _partenaireSection() {
    final interne = _provenance == 'elevage';
    final selectionInterne = interne && (_selectedPartenaireId ?? '').isNotEmpty;
    final dansListe = _partenaires.any((r) => r.id == _selectedPartenaireId);
    return [
      Container(
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD1D5DB)), borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          for (final o in const ['elevage', 'exterieur'])
            Expanded(child: InkWell(
              onTap: () => setState(() {
                if (_provenance == o) return;
                _provenance = o;
                _selectedPartenaireId = null;
                _nomPartenaire.clear(); _identPartenaire.clear();
              }),
              child: Container(
                height: 40, alignment: Alignment.center,
                color: _provenance == o ? const Color(0xFF0C5C6C) : Colors.white,
                child: Text(o == 'exterieur' ? (_sexePartenaire == 'male' ? 'Étalon extérieur' : 'Femelle extérieure') : 'Mon élevage',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600,
                        color: _provenance == o ? Colors.white : const Color(0xFF1F2A2E))),
              ),
            )),
        ]),
      ),
      const SizedBox(height: 10),
      if (_loadingPartenaires)
        const Padding(padding: EdgeInsets.symmetric(vertical: 6),
            child: Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6E9E57)))))
      else if (interne) ...[
        ChampReproducteur(
          label: 'Sélectionner $_libellePartenaire',
          valeur: selectionInterne ? _nomPartenaire.text : null,
          detail: selectionInterne
              ? (dansListe ? _partenaires.firstWhere((r) => r.id == _selectedPartenaireId).detail
                  : 'N\'est plus proposé pour une nouvelle saillie (saillie existante conservée)')
              : null,
          onTap: _choisirInterne,
        ),
        if (_partenaires.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(_sexePartenaire == 'male'
                ? 'Aucun mâle reproducteur actif dans votre élevage.'
                : 'Aucune femelle reproductrice active dans votre élevage.',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Color(0xFF6F767B)))),
        const SizedBox(height: 10),
      ] else ...[
        OutlinedButton.icon(
          onPressed: _choisirExterieur,
          icon: const Icon(Icons.search, size: 16, color: Color(0xFF0C5C6C)),
          label: const Text('Choisir un reproducteur extérieur enregistré',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF0C5C6C))),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF0C5C6C)),
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
        const SizedBox(height: 4),
        const Text('Ou saisissez-le : il est enregistré dans le dossier de reproduction, sans être ajouté à votre cheptel.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
        const SizedBox(height: 10),
        _textField(_sexePartenaire == 'male' ? 'Nom de l\'étalon' : 'Nom de la reproductrice', _nomPartenaire),
        _textField('N° d\'identification', _identPartenaire),
      ],
    ];
  }

  @override
  void dispose() {
    _nomPartenaire.dispose(); _identPartenaire.dispose(); _notes.dispose();
    super.dispose();
  }

  Future<void> _pickSaillieDate({DateTime? initial, required ValueChanged<DateTime> onPick}) async {
    final p = await showDatePicker(context: context,
      initialDate: initial ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))),
        child: child!));
    if (p != null) onPick(DateTime(p.year, p.month, p.day));
  }

  // Section « dates de saillie » : 1re saillie + saillies suivantes de la
  // même chaleur, avec fenêtre de mise-bas estimée (1re → dernière + gestation).
  List<Widget> _datesSection() {
    final df = DateFormat('dd/MM/yyyy');
    final rows = <Widget>[
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text('Dates de saillie',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
      ),
    ];
    for (var i = 0; i < _dates.length; i++) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _pickSaillieDate(
                initial: _dates[i],
                onPick: (d) => setState(() { _dates[i] = d; _dates.sort(); }),
              ),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Saillie ${i + 1}${i == 0 ? ' *' : ''}',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
                  suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57)),
                ),
                child: Text(df.format(_dates[i]),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E))),
              ),
            ),
          ),
          if (_dates.length > 1)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => setState(() => _dates.removeAt(i)),
            ),
        ]),
      ));
    }
    rows.add(Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _pickSaillieDate(
          initial: _dates.isNotEmpty ? _dates.last : null,
          onPick: (d) => setState(() { _dates.add(d); _dates.sort(); }),
        ),
        icon: const Icon(Icons.add, size: 16, color: Color(0xFF6E9E57)),
        label: Text(_dates.isEmpty ? 'Choisir la date de la 1re saillie *' : 'Ajouter une date de saillie',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ),
    ));

    if (widget.sexeAnimal == 'femelle' && _dates.isNotEmpty) {
      final f = _fenetreMiseBas(_dates, widget.espece);
      if (f != null) {
        rows.add(Container(
          margin: const EdgeInsets.only(top: 4, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF5EA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6E9E57), width: 0.6),
          ),
          child: Row(children: [
            Expanded(child: Text(
              f.debut == f.fin
                  ? 'Mise-bas estimée : ${df.format(f.probable)}'
                  : 'Fenêtre mise-bas : ${df.format(f.debut)} → ${df.format(f.fin)}\nDate la plus probable : ${df.format(f.probable)}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Color(0xFF4A7A3A), height: 1.35),
            )),
          ]),
        ));
      }
    }
    rows.add(const SizedBox(height: 4));
    return rows;
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
    // Le dialogue entier (titre + champs + boutons) défile en un seul bloc, avec
    // une hauteur qui tient compte du clavier ouvert (viewInsets.bottom) : le
    // bouton « Enregistrer » reste toujours atteignable en faisant défiler, pas
    // besoin de fermer le clavier numérique pour l'atteindre.
    final mq = MediaQuery.of(context);
    final dialogMaxHeight = (mq.size.height - mq.viewInsets.bottom - mq.padding.vertical - 48)
        .clamp(200.0, mq.size.height);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.existing != null ? 'Modifier la saillie' : 'Ajouter une saillie',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._datesSection(),
                if (widget.existing == null && _raisonAnimalNonEligible != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                    child: Text('Nouvelle saillie impossible : $_raisonAnimalNonEligible.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.red.shade700)),
                  ),
                ..._partenaireSection(),
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
          if (_erreur != null)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(_erreur!, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.red.shade700))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'))),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                if (_dates.isEmpty) return;
                if (_nomPartenaire.text.trim().isEmpty) {
                  setState(() => _erreur = 'Sélectionnez $_libellePartenaire ou saisissez un reproducteur extérieur.');
                  return;
                }
                // Nouvelle saillie : animal de la fiche et partenaire interne éligibles
                // (contrôle aussi fait côté serveur à l'enregistrement)
                if (widget.existing == null) {
                  if (_raisonAnimalNonEligible != null) {
                    setState(() => _erreur = 'Nouvelle saillie impossible : $_raisonAnimalNonEligible.');
                    return;
                  }
                  if (_provenance == 'elevage' && !_partenaires.any((r) => r.id == _selectedPartenaireId)) {
                    setState(() => _erreur = 'Sélectionnez $_libellePartenaire parmi vos reproducteurs actifs.');
                    return;
                  }
                }
                final supa = Supabase.instance.client;
                final sorted = [..._dates]..sort();
                final isoDates = sorted.map((d) => d.toIso8601String()).toList();
                final premiere = sorted.first;
                final f = _fenetreMiseBas(sorted, widget.espece);
                final payload = {
                  'animal_id': widget.animalId,
                  'date': premiere.toIso8601String(),
                  'dates': isoDates,
                  'nom_partenaire': _nomPartenaire.text.trim(),
                  'ident_partenaire': _identPartenaire.text.trim(),
                  'methode': _methode,
                  'notes': _notes.text.trim(),
                  'partenaire_animal_id': _provenance == 'elevage' && (_selectedPartenaireId ?? '').isNotEmpty
                      ? _selectedPartenaireId : null,
                };
                try {
                if (widget.existing != null) {
                  await supa.from('saillies').update(payload).eq('id', widget.existing!['id']);
                  // Répercute la fenêtre sur la gestation auto liée, si elle
                  // existe encore et n'a pas de mise-bas réelle.
                  if (widget.sexeAnimal == 'femelle' && f != null) {
                    try {
                      await supa.from('gestations').update({
                        'date': premiere.toIso8601String(),
                        'date_prevue': f.debut.toIso8601String(),
                        'date_prevue_fin': f.fin.toIso8601String(),
                      }).eq('id', '${widget.existing!['id']}_gest').isFilter('date_naissance', null);
                    } catch (_) {}
                  }
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
                        'date': premiere.toIso8601String(),
                        'dates': isoDates,
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
                      await supa.from('gestations').insert({
                        'id': '${id}_gest',
                        'animal_id': widget.animalId,
                        'date': premiere.toIso8601String(),
                        if (f != null) 'date_prevue': f.debut.toIso8601String(),
                        if (f != null) 'date_prevue_fin': f.fin.toIso8601String(),
                        'gestation_confirmee': false,
                      });
                    } catch (_) {}
                  }
                }
                } on PostgrestException catch (e) {
                  setState(() => _erreur = e.message.contains('REPRO_NON_ELIGIBLE')
                      ? 'Enregistrement refusé : reproducteur non éligible (retraité, stérilisé, cédé ou non coché « Reproducteur »).'
                      : 'Erreur : ${e.message}');
                  return;
                }
                if (context.mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57), foregroundColor: Colors.white),
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey'))),
          ]),
            ]),
          ),
        ),
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
  DateTime? _datePrevueFin;
  DateTime? _dateNaissance;
  bool _dateOverride = false;
  bool _gestationConfirmee = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _dateConception = e['date']            != null ? DateTime.tryParse(e['date'])            : null;
      _datePrevue     = e['date_prevue']     != null ? DateTime.tryParse(e['date_prevue'])     : null;
      _datePrevueFin  = e['date_prevue_fin'] != null ? DateTime.tryParse(e['date_prevue_fin']) : null;
      _dateNaissance  = e['date_naissance']  != null ? DateTime.tryParse(e['date_naissance'])  : null;
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
        // Saisie manuelle d'une date de conception unique : pas de fenêtre.
        _datePrevueFin = null;
      }
    });
  }

  // Date de mise-bas la plus probable = milieu de la fenêtre si elle existe,
  // sinon la date prévue simple.
  DateTime? get _dateProbable {
    if (_datePrevue != null && _datePrevueFin != null) {
      return DateTime.fromMillisecondsSinceEpoch(
          (_datePrevue!.millisecondsSinceEpoch + _datePrevueFin!.millisecondsSinceEpoch) ~/ 2);
    }
    return _datePrevue;
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

    // Le dialogue entier (titre + champs + boutons) défile en un seul bloc, avec
    // une hauteur qui tient compte du clavier ouvert (viewInsets.bottom) : le
    // bouton « Enregistrer » reste toujours atteignable en faisant défiler, pas
    // besoin de fermer le clavier numérique pour l'atteindre.
    final mq = MediaQuery.of(context);
    final dialogMaxHeight = (mq.size.height - mq.viewInsets.bottom - mq.padding.vertical - 48)
        .clamp(200.0, mq.size.height);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.existing != null ? 'Modifier la gestation' : 'Ajouter une gestation',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 16),
          Column(children: [
                _dateRow('Date de conception / 1re saillie *', _dateConception, _onConceptionPicked),
                _dateRow(
                  _datePrevueFin != null
                      ? 'Mise-bas — début de fenêtre'
                      : (hasCalcul ? 'Mise-bas estimée' : 'Mise-bas prévue'),
                  _datePrevue,
                  (d) => setState(() { _datePrevue = d; _dateOverride = true; }),
                  calculated: hasCalcul && !_dateOverride && _datePrevue != null,
                  helper: hasCalcul
                      ? (_datePrevue == null
                          ? 'calculée auto. dès la date de conception saisie'
                          : (_dateOverride ? 'modifiée manuellement' : 'calculée — $jours j de gestation'))
                      : null,
                ),
                _dateRow(
                  'Mise-bas — fin de fenêtre (optionnel)',
                  _datePrevueFin,
                  (d) => setState(() => _datePrevueFin = d),
                  helper: 'renseignée si plusieurs saillies (dernière saillie + $jours j)',
                ),
                if (_datePrevue != null && _datePrevueFin != null && _dateProbable != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF5EA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF6E9E57), width: 0.6),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(
                        'Fenêtre : ${DateFormat('dd/MM/yyyy').format(_datePrevue!)} → ${DateFormat('dd/MM/yyyy').format(_datePrevueFin!)}\nDate la plus probable : ${DateFormat('dd/MM/yyyy').format(_dateProbable!)}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Color(0xFF4A7A3A), height: 1.35),
                      )),
                    ]),
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
                    'date_prevue_fin': _datePrevueFin?.toIso8601String(),
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
        ),
      ),
    );
  }
}

// ─── Types data pour les dialogs ─────────────────────────────────────────────

class _DF { final String label; final TextEditingController ctrl; final int maxLines; final TextInputType? inputType; final bool readOnly;
  const _DF(this.label, this.ctrl, {this.maxLines = 1, this.inputType, this.readOnly = false}); }
class _DD { final String label; final DateTime? value; final ValueChanged<DateTime> onChanged;
  const _DD(this.label, this.value, this.onChanged); }
class _DDrop { final String label; final String? value; final List<String> options; final ValueChanged<String?> onChanged;
  /// Libellés propres à cette liste (ex. code d'un test → son nom).
  final Map<String, String>? libelles;
  const _DDrop(this.label, this.value, this.options, this.onChanged, {this.libelles}); }
class _DCustom { final Widget child; const _DCustom(this.child); }
/// Valeur calculée, affichée sans pouvoir être modifiée.
class _DLecture { final String label; final String valeur; const _DLecture(this.label, this.valeur); }

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
                    readOnly: f.readOnly,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: f.readOnly ? Colors.grey.shade600 : null),
                    decoration: InputDecoration(labelText: f.label,
                      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)));

                if (f is _DLecture) return Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: f.label,
                      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                      filled: true, fillColor: const Color(0xFFF1F1EF),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
                      suffixIcon: const Icon(Icons.lock_outline, size: 16, color: Color(0xFF9AA3A6))),
                    child: Text(f.valeur, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700))));
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
                    isExpanded: true,
                    decoration: InputDecoration(labelText: f.label,
                      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
                    items: f.options.map((o) => DropdownMenuItem(value: o,
                        child: Text(f.libelles?[o] ?? kLibellesSante[o] ?? o, overflow: TextOverflow.ellipsis, maxLines: 2))).toList(),
                    onChanged: f.onChanged));

                if (f is _DCustom) return Padding(padding: const EdgeInsets.only(bottom: 10), child: f.child);

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
                    SnackBar(content: Text(e is SaisieInvalide ? e.message : 'Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
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

  // ─── _BreedSearchSheet.build ─────────────────────────────────────────────
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

// ─── Onglet Consultations (vue vétérinaire) ──────────────────────────────────

class _ConsultationsVetTab extends StatefulWidget {
  final String? animalId;
  final String? ownerUid;
  final String animalNom;
  final String? rdvId;
  final String espece;
  const _ConsultationsVetTab({required this.animalId, required this.ownerUid, required this.animalNom, this.rdvId, this.espece = 'chien'});

  @override
  State<_ConsultationsVetTab> createState() => _ConsultationsVetTabState();
}

class _ConsultationsVetTabState extends State<_ConsultationsVetTab> {
  static const _teal  = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _crs        = [];
  List<Map<String, dynamic>> _ordos      = [];
  /// Intervenants (profil / uid → nom) des CR et ordonnances.
  Map<String, String> _noms = {};
  // Droits (titulaire : tous ; employé : selon ses permissions). La RLS
  // reste la garantie côté serveur.
  bool _peutCr = false;
  bool _peutCarnet = false;
  bool _peutOrdonnance = false;
  String? _vetProfileId;
  // ID de session — lie toutes les entrées ajoutées pendant cette visite
  late final String _sessionVisiteRef;

  @override
  void initState() {
    super.initState();
    _sessionVisiteRef = DateTime.now().microsecondsSinceEpoch.toString();
    _load();
    _chargerDroits();
  }

  /// Compte rendu saisi par erreur (droits contrôlés en base : un CR validé
  /// n'est supprimable que par qui peut valider).
  Future<void> _supprimerCr(Map<String, dynamic> cr) async {
    try {
      final r = await Supabase.instance.client.from('comptes_rendus').delete().eq('id', cr['id']).select('id');
      if ((r as List).isEmpty) throw 'seul un vétérinaire qui peut valider supprime un compte rendu validé';
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Compte rendu supprimé.', style: TextStyle(fontFamily: 'Galey')), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Suppression impossible : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _chargerDroits() async {
    final cr = await AgendaContexte.peut('vet_cr_rediger') || await AgendaContexte.peut('vet_cr_valider');
    final carnet = await AgendaContexte.peut('vet_patients') || cr;
    final ordo = await AgendaContexte.peut('vet_ordonnances');
    if (mounted) setState(() { _peutCr = cr; _peutCarnet = carnet; _peutOrdonnance = ordo; });
  }

  Future<void> _load() async {
    if (widget.animalId == null) { setState(() => _loading = false); return; }
    final vetUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Profil pro ACTIF (cabinet souvent en profil secondaire) — is_main en
    // dernier recours seulement (sinon CR / ordonnances introuvables).
    if (_vetProfileId == null && User_Info.activeProfileId.isNotEmpty) _vetProfileId = User_Info.activeProfileId;
    if (_vetProfileId == null && vetUid.isNotEmpty) {
      final row = await _supa.from('user_profiles_complet').select('id').eq('uid', vetUid).eq('is_main', true).maybeSingle();
      _vetProfileId = row?['id'] as String?;
    }
    final proFilter = _vetProfileId != null ? 'pro_profile_id' : 'pro_uid';
    final proValue  = _vetProfileId ?? vetUid;
    try {
      final results = await Future.wait([
        _supa.from('comptes_rendus').select()
            .eq('animal_id', widget.animalId!).eq(proFilter, proValue)
            .order('created_at', ascending: false),
        _supa.from('ordonnances').select()
            .eq('animal_id', widget.animalId!).eq(proFilter, proValue)
            .order('created_at', ascending: false),
      ]);
      final crs = List<Map<String, dynamic>>.from(results[0]);
      final ordos = List<Map<String, dynamic>>.from(results[1]);
      final cites = intervenantsCites(crs, ordos);
      final noms = await chargerNomsIntervenants(profils: cites.profils, uids: cites.uids);
      if (mounted) setState(() {
        _crs     = crs;
        _ordos   = ordos;
        _noms    = noms;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCrPage() {
    // Ostéo / physio : compte rendu de séance (Soins & Rééducation), pas le
    // compte rendu vétérinaire.
    if (User_Info.catPro == 'sante') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MorphoFormPage(
          animalId: widget.animalId,
          espece: widget.espece,
          proProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
          rdvId: widget.rdvId,
        ),
      )).then((_) => _load());
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CompteRenduPage(
        animalId: widget.animalId,
        ownerUid: widget.ownerUid,
        clientName: widget.animalNom,
        categoryColor: _teal,
      ),
    )).then((_) => _load());
  }

  void _showAddCarnetSheet() {
    showModalBottomSheet(
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
          const Text('Ajouter au carnet de santé',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 20),
          for (final opt in [
            (Icons.vaccines_outlined,         const Color(0xFF0C5C6C),  '💉 Vaccin',              'vaccin'),
            (Icons.medication_outlined,        const Color(0xFF8D6E63),  '💊 Traitement',           'traitement'),
            (Icons.medical_services_outlined,  const Color(0xFF26A69A),  '🩺 Visite vétérinaire',   'visite'),
            if (_peutOrdonnance)
              (Icons.description_outlined,     const Color(0xFF6D28D9),  '📄 Ordonnance PDF',       'ordo'),
            (Icons.image_search_outlined,      const Color(0xFF0284C7),  '🩻 Radio / Examen',       'radio'),
          ]) ...[
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: (opt.$2).withValues(alpha: 0.07),
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: (opt.$2).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(opt.$1, color: opt.$2),
              ),
              title: Text(opt.$3,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _openVetEntryDialog(opt.$4);
              },
            ),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    );
  }

  Future<void> _openVetEntryDialog(String type) async {
    if (widget.animalId == null) return;
    final vetUid  = FirebaseAuth.instance.currentUser?.uid ?? '';
    final vetName = 'Dr. ${User_Info.firstname} ${User_Info.lastname}'.trim();
    Widget dialog;
    switch (type) {
      case 'vaccin':
        dialog = _VetAddVaccinDialog(
            animalId: widget.animalId!, vetUid: vetUid, vetName: vetName,
            visiteRef: _sessionVisiteRef, rdvId: widget.rdvId);
        break;
      case 'traitement':
        dialog = _VetAddTraitementDialog(
            animalId: widget.animalId!, vetUid: vetUid, vetName: vetName,
            visiteRef: _sessionVisiteRef, rdvId: widget.rdvId);
        break;
      case 'ordo':
        dialog = _VetAddOrdoDialog(
            animalId: widget.animalId!, vetUid: vetUid, vetName: vetName,
            vetProfileId: _vetProfileId,
            ownerUid: widget.ownerUid, rdvId: widget.rdvId);
        break;
      case 'radio':
        dialog = _VetAddRadioDialog(
            animalId: widget.animalId!, vetUid: vetUid, vetName: vetName,
            visiteRef: _sessionVisiteRef);
        break;
      default:
        dialog = _VetAddVisiteDialog(
            animalId: widget.animalId!, vetUid: vetUid, vetName: vetName,
            visiteRef: _sessionVisiteRef, rdvId: widget.rdvId);
    }
    final saved = await showDialog<bool>(context: context, builder: (_) => dialog);
    if (saved == true) {
      _load();
      _notifyOwner(type);
    }
  }

  void _notifyOwner(String type) async {
    if (widget.ownerUid == null || widget.ownerUid!.isEmpty) return;
    final vetName = 'Dr. ${User_Info.firstname} ${User_Info.lastname}'.trim();
    final label   = type == 'vaccin' ? 'une vaccination'
        : type == 'traitement' ? 'un traitement'
        : 'une visite';
    final propRow = await _supa.from('animaux_proprietes')
        .select('profile_id_proprio').eq('animal_id', widget.animalId!)
        .filter('date_fin', 'is', null).order('date_debut', ascending: false)
        .limit(1).maybeSingle();
    final ownerProfileId = propRow?['profile_id_proprio'] as String?;
    _supa.from('notifications').insert({
      'uid':   widget.ownerUid,
      'type':  'sante_vet',
      'title': '🩺 Entrée vétérinaire ajoutée',
      'body':  '$vetName a enregistré $label pour ${widget.animalNom}',
      if (ownerProfileId != null) 'profile_id': ownerProfileId,
      'data':  {'animalId': widget.animalId},
      'read':  false,
    }).catchError((_) {});
  }

  void _ouvrirHistorique() => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoriquePatientPage(
      animalId: widget.animalId!, animalNom: widget.animalNom.isNotEmpty ? widget.animalNom : 'Patient')));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));
    final consultations = regrouperConsultations(_crs, _ordos);
    const texteBouton = TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13);
    final forme = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return RefreshIndicator(
      onRefresh: _load,
      color: _teal,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          // En-tête : actions compactes, dans le flux (jamais par-dessus le contenu).
          Row(children: [
            Expanded(child: Text('Consultations (${consultations.length})',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2025)))),
            if (_crs.isNotEmpty)
              TextButton(
                onPressed: _ouvrirHistorique,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Historique complet', style: TextStyle(fontFamily: 'Galey',
                    fontSize: 12.5, color: _teal, fontWeight: FontWeight.w600)),
              ),
          ]),
          if (_peutCr || _peutCarnet) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_peutCr)
                FilledButton.icon(
                  onPressed: _openCrPage,
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Nouveau compte rendu', style: texteBouton),
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal, minimumSize: const Size(0, 36), shape: forme,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (_peutCarnet)
                OutlinedButton.icon(
                  onPressed: _showAddCarnetSheet,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter au carnet', style: texteBouton),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal, side: const BorderSide(color: Color(0xFFCFDCDD)),
                    minimumSize: const Size(0, 36), shape: forme,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          if (consultations.isEmpty)
            _VetConsultEmptyCard(message: 'Aucune consultation enregistrée pour cet animal.')
          else
            for (final c in consultations) ...[
              ConsultationCard(
                c: c, noms: _noms,
                onOuvrir: () => showConsultationDetail(context, c: c, noms: _noms,
                    onGererCr: _peutCr || _peutOrdonnance ? _openCrPage : null,
                    onSupprimerCr: _peutCr ? _supprimerCr : null),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 6),
          Text('Vaccins, traitements et autres soins : onglet Santé.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ─── Onglet Consultations (vue propriétaire) ─────────────────────────────────

// ── Éducateur/comportementaliste : suivi de progression + exercices ─────────

class _EducationTab extends StatefulWidget {
  final String? animalId;
  final String? ownerUid;
  final String animalNom;
  const _EducationTab({required this.animalId, required this.ownerUid, required this.animalNom});

  @override
  State<_EducationTab> createState() => _EducationTabState();
}

class _EducationTabState extends State<_EducationTab> {
  static const _purple = Color(0xFF7B5EA7);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _showAdd = false;
  List<Map<String, dynamic>> _rapports = [];
  final _contenuCtrl = TextEditingController();
  final _exercicesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contenuCtrl.dispose();
    _exercicesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.animalId == null) { setState(() => _loading = false); return; }
    try {
      final rows = await _supa.from('education_progression').select()
          .eq('animal_id', widget.animalId!).order('date_seance', ascending: false);
      if (mounted) setState(() { _rapports = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _soumettre() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.animalId == null || _contenuCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await _supa.from('education_progression').insert({
        'pro_uid': uid,
        'animal_id': widget.animalId,
        'owner_uid': widget.ownerUid,
        'date_seance': DateTime.now().toIso8601String().substring(0, 10),
        'contenu': _contenuCtrl.text.trim(),
        if (_exercicesCtrl.text.trim().isNotEmpty) 'exercices_conseilles': _exercicesCtrl.text.trim(),
      });
      if (widget.ownerUid != null) {
        final proNom = User_Info.nameElevage.isNotEmpty
            ? User_Info.nameElevage
            : '${User_Info.firstname} ${User_Info.lastname}'.trim();
        try {
          final propRow = await _supa.from('animaux_proprietes')
              .select('profile_id_proprio').eq('animal_id', widget.animalId!)
              .filter('date_fin', 'is', null).order('date_debut', ascending: false)
              .limit(1).maybeSingle();
          final ownerProfileId = propRow?['profile_id_proprio'] as String?;
          await _supa.from('notifications').insert({
            'uid': widget.ownerUid,
            'type': 'education_rapport',
            'title': 'Rapport de séance — ${widget.animalNom}',
            'body': '${proNom.isNotEmpty ? proNom : 'Votre éducateur'} a envoyé un rapport de séance pour ${widget.animalNom}.',
            if (ownerProfileId != null) 'profile_id': ownerProfileId,
            'data': <String, dynamic>{'animalId': widget.animalId, 'animalNom': widget.animalNom},
            'read': false,
          });
        } catch (_) {}
      }
      _contenuCtrl.clear();
      _exercicesCtrl.clear();
      setState(() => _showAdd = false);
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editRapport(Map<String, dynamic> r) async {
    // Édition brute : texte sans balises ; inchangé → on garde le HTML du site.
    final contenuOriginal = r['contenu']?.toString() ?? '';
    final contenuPlain = richTextToPlain(contenuOriginal);
    final contenuCtrl = TextEditingController(text: contenuPlain);
    final exercicesCtrl = TextEditingController(text: r['exercices_conseilles']?.toString() ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const Text('Modifier le rapport', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          TextField(controller: contenuCtrl, minLines: 6, maxLines: 16, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.all(12))),
          const SizedBox(height: 12),
          TextField(controller: exercicesCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(labelText: 'Exercices conseillés',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.all(12))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          )),
        ]),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final contenuOut = contenuCtrl.text.trim() == contenuPlain.trim()
          ? contenuOriginal
          : contenuCtrl.text.trim();
      await _supa.from('education_progression').update({
        'contenu': contenuOut,
        'exercices_conseilles': exercicesCtrl.text.trim().isEmpty ? null : exercicesCtrl.text.trim(),
      }).eq('id', r['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  Future<void> _deleteRapport(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce rapport ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('education_progression').delete().eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _purple));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _showAdd = !_showAdd),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter un rapport de séance', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(foregroundColor: _purple, side: const BorderSide(color: _purple)),
          ),
        ),
        if (_showAdd) ...[
          const SizedBox(height: 12),
          TextField(controller: _contenuCtrl, minLines: 6, maxLines: 16, decoration: const InputDecoration(
              labelText: 'Compte rendu', hintText: 'Déroulé de la séance, observations, progrès…', border: OutlineInputBorder())),
          const SizedBox(height: 4),
          const Text('Mise en forme (gras, couleurs, listes…) disponible sur le site.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(controller: _exercicesCtrl, maxLines: 2, decoration: const InputDecoration(
              labelText: 'Exercices conseillés', hintText: 'Exercices à faire à la maison…', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _soumettre,
              style: ElevatedButton.styleFrom(backgroundColor: _purple, padding: const EdgeInsets.symmetric(vertical: 12)),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Envoyer au propriétaire', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_rapports.isEmpty)
          Text('Aucun rapport de séance pour l\'instant.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500))
        else
          ..._rapports.map((r) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r['date_seance']?.toString() ?? '',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500))),
                GestureDetector(
                  onTap: () => _editRapport(r),
                  child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade400),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _deleteRapport(r['id'].toString()),
                  child: Icon(Icons.delete_outline, size: 16, color: Colors.grey.shade400),
                ),
              ]),
              const SizedBox(height: 6),
              RichTextView(r['contenu']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: Color(0xFF1F2A2E))),
              if ((r['exercices_conseilles']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('🏋️ Exercices conseillés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF4A7A32))),
                    const SizedBox(height: 2),
                    Text(r['exercices_conseilles'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF4A7A32))),
                  ]),
                ),
              ],
            ]),
          )),
      ]),
    );
  }
}

/// Onglet « Consultations » du propriétaire : TOUS les comptes rendus de
/// l'animal, rangés par catégorie — vétérinaire (comptes rendus, ordonnances)
/// et séances partagées par les ostéopathes, kinés… (suivis_morpho envoyés).
/// Utilisé aussi par la fiche particulier (animal_fiche_particulier.dart).
class ConsultationsProprietaireTab extends StatefulWidget {
  final String? animalId;
  final String espece;
  /// Ajout / suppression des radios (employé sans write_sante : lecture seule).
  final bool canWrite;
  /// Compte rendu à mettre en avant (lien de la notification).
  final String? crCible;
  const ConsultationsProprietaireTab({super.key, required this.animalId, required this.espece, this.canWrite = true, this.crCible});

  @override
  State<ConsultationsProprietaireTab> createState() => _ConsultationsProprietaireTabState();
}

class _ConsultationsProprietaireTabState extends State<ConsultationsProprietaireTab> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _crs   = [];
  List<Map<String, dynamic>> _ordos = [];
  /// Radios / imagerie : déposées par le vétérinaire ou par le propriétaire.
  List<Map<String, dynamic>> _radios = [];
  int _seancesOsteoCount = 0;
  Map<String, String> _vetNames = {};
  /// Comptes rendus de séance partagés (ostéo, kiné, rééducation, bilans).
  List<Map<String, dynamic>> _seances = [];
  /// Comptes rendus de toilettage que le salon a choisi de partager.
  List<Map<String, dynamic>> _toilettages = [];
  /// tous | osteopathie | kine | veterinaire | toilettage | autre — d'après le métier de
  /// l'auteur (categorieConsultation), pas le type de séance.
  String _categorie = 'tous';
  final _crCibleKey = GlobalKey();
  bool _crCibleVu = false;

  @override
  void initState() {
    super.initState();
    _load().whenComplete(() {
      if (widget.crCible == null || _crCibleVu) return;
      _crCibleVu = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _crCibleKey.currentContext;
        if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 400), alignment: 0.1);
      });
    });
  }

  Future<void> _load() async {
    if (widget.animalId == null) { setState(() => _loading = false); return; }
    try {
      final crs   = await _supa.from('comptes_rendus').select()
          .eq('animal_id', widget.animalId!).order('created_at', ascending: false);
      final ordos = await _supa.from('ordonnances').select()
          .eq('animal_id', widget.animalId!).order('created_at', ascending: false);
      var radios = <Map<String, dynamic>>[];
      try {
        radios = List<Map<String, dynamic>>.from(await _supa.from('radios').select()
            .eq('animal_id', widget.animalId!).order('date', ascending: false));
      } catch (_) {}
      int seancesOsteoCount = 0;
      try {
        final seances = await _supa.from('seances_osteo').select('id').eq('animal_id', widget.animalId!);
        seancesOsteoCount = (seances as List).length;
      } catch (_) {}

      final allCrs   = List<Map<String, dynamic>>.from(crs);
      final allOrdos = List<Map<String, dynamic>>.from(ordos);

      final proUids = {
        ...allCrs.map((r)  => r['pro_uid']?.toString()).whereType<String>(),
        ...allOrdos.map((r) => r['pro_uid']?.toString()).whereType<String>(),
      }.toList();

      final vetNames = <String, String>{};
      if (proUids.isNotEmpty) {
        try {
          // Pro émetteur (clinique, pension…) : nom de structure du profil
          // pro, sinon prénom + nom.
          final profs = await _supa.from('user_profiles_complet')
              .select('uid, nom, firstname, lastname, profile_type').inFilter('uid', proUids);
          for (final p in profs as List) {
            final uid = p['uid']?.toString() ?? '';
            final nom = (p['nom'] as String?)?.trim() ?? '';
            final full = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
            final isPro = (p['profile_type'] as String?)?.isNotEmpty == true && p['profile_type'] != 'particulier';
            final label = isPro && nom.isNotEmpty ? nom : (full.isNotEmpty ? full : nom);
            if (label.isNotEmpty && (isPro || !vetNames.containsKey(uid))) vetNames[uid] = label;
          }
        } catch (_) {}
      }

      // Séances des pros (bilan d'un pro visible une fois envoyé — RLS +
      // filtre pour un même compte propriétaire / pro).
      var seances = <Map<String, dynamic>>[];
      try {
        final rows = await _supa.from('suivis_morpho').select()
            .eq('animal_id', widget.animalId!).order('date', ascending: false);
        seances = List<Map<String, dynamic>>.from(rows as List)
            .where((x) => x['source'] != 'professionnel' || x['notifie_a'] != null).toList();
        final pids = seances.map((x) => x['pro_profile_id']?.toString()).whereType<String>().toSet().toList();
        if (pids.isNotEmpty) {
          final pros = await _supa.from('user_profiles_complet')
              .select('id, nom, firstname, lastname, profession_pro, cat_pro').inFilter('id', pids);
          final noms = <String, String>{};
          final metiers = <String, (String?, String?)>{};
          for (final r in pros as List) {
            final nom = (r['nom'] ?? '').toString().trim().isNotEmpty
                ? r['nom'].toString().trim() : '${r['firstname'] ?? ''} ${r['lastname'] ?? ''}'.trim();
            noms[r['id'].toString()] = [nom, (r['profession_pro'] ?? '').toString().trim()].where((x) => x.isNotEmpty).join(' — ');
            metiers[r['id'].toString()] = (r['profession_pro']?.toString(), r['cat_pro']?.toString());
          }
          for (final x in seances) {
            x['_pro'] = noms[x['pro_profile_id']?.toString()] ?? x['professionnel_nom'];
            final m = metiers[x['pro_profile_id']?.toString()];
            x['_categorie'] = categorieConsultation(type: x['type_suivi']?.toString(), profession: m?.$1, catPro: m?.$2);
          }
        }
        for (final x in seances) {
          x['_categorie'] ??= categorieConsultation(type: x['type_suivi']?.toString());
        }
      } catch (_) {}

      var toilettages = <Map<String, dynamic>>[];
      try {
        toilettages = List<Map<String, dynamic>>.from(await _supa.from('seances_toilettage').select()
            .eq('animal_id', widget.animalId!).eq('partage_proprietaire', true).order('date_seance', ascending: false));
        final pids = toilettages.map((x) => x['pro_profile_id']?.toString()).whereType<String>().toSet().toList();
        if (pids.isNotEmpty) {
          final salons = await _supa.from('user_profiles_complet').select('id, nom, firstname, lastname').inFilter('id', pids);
          final noms = {
            for (final r in salons as List)
              r['id'].toString(): (r['nom'] ?? '').toString().trim().isNotEmpty ? r['nom'].toString().trim() : '${r['firstname'] ?? ''} ${r['lastname'] ?? ''}'.trim(),
          };
          for (final x in toilettages) { x['_pro'] = noms[x['pro_profile_id']?.toString()]; }
        }
      } catch (_) {}

      if (mounted) setState(() {
        _toilettages = toilettages;
        _crs      = allCrs;
        _ordos    = allOrdos;
        _radios   = radios;
        _vetNames = vetNames;
        _seancesOsteoCount = seancesOsteoCount;
        _seances  = seances;
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));
    final isEmpty = _crs.isEmpty && _ordos.isEmpty && _radios.isEmpty && _seancesOsteoCount == 0 && _seances.isEmpty && _toilettages.isEmpty;
    final Widget? ajouterRadio = !widget.canWrite || widget.animalId == null ? null : Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () async {
          await showDialog(context: context, builder: (_) => _AddRadioDialog(animalId: widget.animalId!));
          _load();
        },
        icon: const Icon(Icons.add, size: 18, color: _teal),
        label: const Text('Ajouter une radio / imagerie',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
      ),
    );
    // Catégories présentes seulement (pas de filtre vide).
    // Ordre : Ostéopathie, Kiné, Vétérinaire, Autres — catégories présentes seulement.
    final presentes = <String>[
      for (final c in kCategoriesConsultation)
        if (_seances.any((x) => x['_categorie'] == c.$1)
            || (c.$1 == 'veterinaire' && (_crs.isNotEmpty || _ordos.isNotEmpty || _radios.isNotEmpty))
            || (c.$1 == 'toilettage' && _toilettages.isNotEmpty)
            || (c.$1 == 'osteopathie' && _seancesOsteoCount > 0)) c.$1,
    ];
    bool voir(String c) => _categorie == 'tous' || _categorie == c;
    final seancesVues = _seances.where((x) => voir(x['_categorie']?.toString() ?? 'autre')).toList();
    return RefreshIndicator(
      onRefresh: _load,
      color: _teal,
      child: isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
              if (ajouterRadio != null) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ajouterRadio),
              Padding(
                padding: const EdgeInsets.only(top: 80, left: 32, right: 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade200),
                  const SizedBox(height: 16),
                  const Text('Aucune consultation enregistrée',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 16, color: Color(0xFF1F2A2E))),
                  const SizedBox(height: 8),
                  Text('Les comptes rendus de vos vétérinaires,\nostéopathes, kinés… apparaîtront ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                          color: Colors.grey.shade500, height: 1.5)),
                ]),
              ),
            ])
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (ajouterRadio != null) ajouterRadio,
                // Filtres dès qu'il y a un compte rendu : le métier se lit
                // d'un coup d'œil (catégories vides jamais affichées).
                if (presentes.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final c in ['tous', ...presentes])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c == 'tous' ? 'Tous' : kCategoriesConsultation.firstWhere((k) => k.$1 == c).$2, style: TextStyle(
                                fontFamily: 'Galey', fontSize: 12.5, color: _categorie == c ? Colors.white : const Color(0xFF1F2A2E))),
                            selected: _categorie == c,
                            showCheckmark: false,
                            selectedColor: _teal,
                            backgroundColor: Colors.white,
                            side: BorderSide(color: _categorie == c ? _teal : Colors.grey.shade300),
                            onSelected: (_) => setState(() => _categorie = c),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                ],
                if (voir('veterinaire') && _crs.isNotEmpty) ...[
                  _VetConsultSectionHeader(label: 'Comptes rendus', count: _crs.length,
                      icon: Icons.assignment_outlined, color: _teal),
                  const SizedBox(height: 10),
                  ..._crs.map((cr) {
                    final carte = _OwnerConsultCrCard(cr: cr, color: _teal,
                        vetName: _vetNames[cr['pro_uid']?.toString()] ?? 'Professionnel',
                        fmtDate: _fmtDate);
                    // Compte rendu de la notification : mis en avant.
                    if (widget.crCible == null || cr['id']?.toString() != widget.crCible) return carte;
                    return Container(
                      key: _crCibleKey,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _teal, width: 2)),
                      child: carte,
                    );
                  }),
                  const SizedBox(height: 20),
                ],
                if (voir('veterinaire') && _ordos.isNotEmpty) ...[
                  _VetConsultSectionHeader(label: 'Ordonnances', count: _ordos.length,
                      icon: Icons.description_outlined, color: _teal),
                  const SizedBox(height: 10),
                  ..._ordos.map((o) => _OwnerConsultOrdoCard(ordo: o, color: _teal,
                      vetName: _vetNames[o['pro_uid']?.toString()] ?? 'Professionnel',
                      fmtDate: _fmtDate)),
                  const SizedBox(height: 20),
                ],
                if (voir('veterinaire') && _radios.isNotEmpty) ...[
                  _VetConsultSectionHeader(label: 'Radios / Imagerie', count: _radios.length,
                      icon: Icons.image_search_outlined, color: _teal),
                  const SizedBox(height: 10),
                  for (final r in _radios)
                    _OwnerRadioCard(radio: r, color: _teal, fmtDate: _fmtDate,
                        // Seules les radios déposées par le propriétaire se suppriment.
                        onDelete: widget.canWrite && r['source'] != 'veterinaire' ? () async {
                          final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                            title: const Text('Supprimer cette radio ?', style: TextStyle(fontFamily: 'Galey')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
                            ],
                          ));
                          if (ok != true) return;
                          await _supa.from('radios').delete().eq('id', r['id']);
                          _load();
                        } : null),
                  const SizedBox(height: 20),
                ],
                if (seancesVues.isNotEmpty) ...[
                  _VetConsultSectionHeader(label: 'Comptes rendus de séance', count: seancesVues.length,
                      icon: Icons.description_outlined, color: _teal),
                  const SizedBox(height: 10),
                  for (final x in seancesVues) _SeanceProprietaireCard(seance: x, espece: widget.espece),
                  const SizedBox(height: 20),
                ],
                if (voir('toilettage') && _toilettages.isNotEmpty) ...[
                  _VetConsultSectionHeader(label: 'Toilettage', count: _toilettages.length,
                      icon: Icons.content_cut, color: _teal),
                  const SizedBox(height: 10),
                  for (final x in _toilettages) _ToilettageProprietaireCard(seance: x),
                  const SizedBox(height: 20),
                ],
                if (voir('osteopathie') && _seancesOsteoCount > 0)
                  AnatomieOwnerSection(animalId: widget.animalId ?? '', espece: widget.espece),
              ]),
            ),
    );
  }
}

// ─── Widgets helpers consultations ───────────────────────────────────────────

/// Compte rendu de toilettage partagé par le salon (lecture seule) : date,
/// salon, travaux réalisés, compte rendu. Les observations internes et les
/// photos restent côté salon.
class _ToilettageProprietaireCard extends StatelessWidget {
  final Map<String, dynamic> seance;
  const _ToilettageProprietaireCard({required this.seance});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(seance['date_seance']?.toString() ?? '');
    final travaux = ((seance['travaux'] as List?) ?? []).map((e) => labelTravailToilettage(e.toString())).join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Toilettage', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 2),
        Text([
          if (date != null) DateFormat('d MMMM yyyy', 'fr_FR').format(date),
          if ((seance['_pro'] as String?)?.trim().isNotEmpty == true) seance['_pro'] as String,
        ].join(' — '), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        if (travaux.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(travaux, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E))),
        ],
        for (final (k, label) in const [('finition', 'Finition'), ('produits', 'Produits utilisés')])
          if ((seance[k]?.toString() ?? '').trim().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('$label : ${seance[k].toString().trim()}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700))),
        if ((seance['compte_rendu']?.toString() ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(seance['compte_rendu'].toString().trim(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: Color(0xFF1F2A2E))),
        ],
        if ((seance['conseils_pelage']?.toString() ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF1F7F8), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Conseils de soin du pelage', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF0C5C6C))),
              const SizedBox(height: 2),
              Text(seance['conseils_pelage'].toString().trim(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: Color(0xFF1F2A2E))),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Carte compacte d'un compte rendu de séance (ostéo, kiné…) côté
/// propriétaire : type, date, professionnel et spécialité ; ouvre le compte
/// rendu (lecture seule, PDF).
class _SeanceProprietaireCard extends StatelessWidget {
  final Map<String, dynamic> seance;
  final String espece;
  const _SeanceProprietaireCard({required this.seance, required this.espece});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(seance['date']?.toString() ?? '');
    final pro = seance['source'] == 'professionnel';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(pro ? titreCompteRendu(seance['type_suivi']?.toString()) : labelTypeSuivi(seance['type_suivi']?.toString()),
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
        subtitle: Text([
          if (date != null) DateFormat('d MMMM yyyy', 'fr_FR').format(date),
          if ((seance['_pro'] as String?)?.trim().isNotEmpty == true) seance['_pro'] as String,
          if ((seance['intitule'] as String?)?.trim().isNotEmpty == true) seance['intitule'].toString().trim(),
        ].join(' — '), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => MorphoDetailPage(suivi: seance, espece: espece, readOnly: true),
        )),
      ),
    );
  }
}

class _VetConsultSectionHeader extends StatelessWidget {
  final String label; final int count; final IconData icon; final Color color;
  const _VetConsultSectionHeader({required this.label, required this.count,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: color),
    const SizedBox(width: 8),
    Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
        fontSize: 15, color: color)),
    if (count > 0) ...[
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text('$count', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
            fontWeight: FontWeight.w700, color: color)),
      ),
    ],
  ]);
}

class _VetConsultEmptyCard extends StatelessWidget {
  final String message;
  const _VetConsultEmptyCard({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200)),
    child: Text(message, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
        color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
  );
}

/// Historique du patient en lignes : date · motif · poids, actes réalisés,
/// prescription (comptes_rendus structurés — migration_cr_structure.sql).
class _OwnerConsultCrCard extends StatelessWidget {
  final Map<String, dynamic> cr; final Color color; final String vetName;
  final String Function(String?) fmtDate;
  const _OwnerConsultCrCard({required this.cr, required this.color,
      required this.vetName, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    final date    = fmtDate(cr['created_at']?.toString());
    final contenu = cr['contenu']?.toString() ?? '';
    final docUrl  = cr['doc_url']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20)),
            child: Text(vetName, style: TextStyle(fontFamily: 'Galey',
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
          const Spacer(),
          if (date.isNotEmpty) Text(date, style: TextStyle(fontFamily: 'Galey',
              fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        Text(contenu, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
        if (docUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              await ouvrirDocument(context, docUrl);
            },
            child: Row(children: [
              Icon(Icons.attach_file, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(child: Text('Document joint', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: color, decoration: TextDecoration.underline))),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Radio / imagerie (vétérinaire ou propriétaire) : titre, date, auteur, fichier.
class _OwnerRadioCard extends StatelessWidget {
  final Map<String, dynamic> radio; final Color color;
  final String Function(String?) fmtDate;
  final VoidCallback? onDelete;
  const _OwnerRadioCard({required this.radio, required this.color, required this.fmtDate, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final url = radio['image_url']?.toString() ?? '';
    final notes = radio['notes']?.toString().trim() ?? '';
    final veto = radio['veterinaire']?.toString().trim() ?? '';
    final auteur = radio['source'] == 'veterinaire' ? (veto.isNotEmpty ? veto : 'Vétérinaire') : 'Ajoutée par le propriétaire';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
            child: Text(auteur, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
          const Spacer(),
          Text(fmtDate(radio['date']?.toString()), style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          if (onDelete != null)
            IconButton(onPressed: onDelete, icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade500),
                visualDensity: VisualDensity.compact, tooltip: 'Supprimer'),
        ]),
        const SizedBox(height: 8),
        Text(radio['titre']?.toString() ?? 'Radio / Examen',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: color)),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
        ],
        if (url.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => ouvrirDocument(context, url),
            child: Row(children: [
              Icon(Icons.attach_file, size: 14, color: color),
              const SizedBox(width: 4),
              Text("Voir l'image / le fichier", style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: color, decoration: TextDecoration.underline)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _OwnerConsultOrdoCard extends StatelessWidget {
  final Map<String, dynamic> ordo; final Color color; final String vetName;
  final String Function(String?) fmtDate;
  const _OwnerConsultOrdoCard({required this.ordo, required this.color,
      required this.vetName, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    final dateEmit = fmtDate(ordo['date_emit']?.toString());
    final docUrl   = ordo['doc_url']?.toString() ?? '';
    final notes    = ordo['notes']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20)),
            child: Text(vetName, style: TextStyle(fontFamily: 'Galey',
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
          const Spacer(),
          if (dateEmit.isNotEmpty) Text(dateEmit, style: TextStyle(fontFamily: 'Galey',
              fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.description_outlined, size: 15, color: color),
          const SizedBox(width: 6),
          Text('Ordonnance', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w600, fontSize: 13, color: color)),
        ]),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
        ],
        if (docUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              await ouvrirDocument(context, docUrl);
            },
            child: Row(children: [
              Icon(Icons.attach_file, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(child: Text('Voir l\'ordonnance', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: color, decoration: TextDecoration.underline))),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─── VET06 : carte entrée santé vétérinaire ───────────────────────────────────

// ─── VET06 : dialog ajout vaccin vétérinaire ─────────────────────────────────

class _VetAddVaccinDialog extends StatefulWidget {
  final String animalId, vetUid, vetName, visiteRef;
  final String? rdvId;
  const _VetAddVaccinDialog({required this.animalId, required this.vetUid,
      required this.vetName, required this.visiteRef, this.rdvId});
  @override State<_VetAddVaccinDialog> createState() => _VetAddVaccinDialogState();
}
class _VetAddVaccinDialogState extends State<_VetAddVaccinDialog> {
  final _vaccin = TextEditingController();
  final _lot    = TextEditingController();
  DateTime? _date;
  DateTime? _rappel;
  bool _saving = false;

  @override
  void dispose() { _vaccin.dispose(); _lot.dispose(); super.dispose(); }

  Future<void> _save() async {
    try {
      if (_vaccin.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le nom du vaccin.');
      controlerDatesSante(date: _date, rappel: _rappel);
    } on SaisieInvalide catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await Supabase.instance.client.from('vaccinations').insert({
        'id': id, 'animal_id': widget.animalId,
        'vaccin': _vaccin.text.trim(), 'lot': _lot.text.trim(),
        'veterinaire': widget.vetName,
        'date': _date!.toIso8601String().substring(0, 10),
        'date_rappel': _rappel?.toIso8601String().substring(0, 10),
        'source': 'veterinaire', 'vet_id': widget.vetUid,
        'visite_ref': widget.visiteRef,
        if (widget.rdvId != null) 'rdv_id': widget.rdvId!,
      });
      if (mounted) Navigator.pop(context, true);
      RegistreHelper.writeActe(
        animalId: widget.animalId, typeActe: 'vaccination', dateActe: _date!,
        intervenant: widget.vetName,
        description: 'Vaccin : ${_vaccin.text.trim()}${_lot.text.trim().isNotEmpty ? " (lot ${_lot.text.trim()})" : ""}',
      );
      _notifyOwnerVetEntry(animalId: widget.animalId, vetName: widget.vetName, typeActe: 'vaccin').catchError((_) {});
      // fire-and-forget – ne bloque pas si l'agenda échoue
      if (_rappel != null) {
        _scheduleRappelAgenda(
          animalId: widget.animalId, dateRappel: _rappel!,
          titre: 'Rappel vaccin — ${_vaccin.text.trim()}',
        ).catchError((_) {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tf(String label, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(controller: ctrl,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      decoration: InputDecoration(labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)));

  Widget _dp(BuildContext ctx, String label, DateTime? val, ValueChanged<DateTime> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(onTap: () async {
      final p = await showDatePicker(context: ctx, initialDate: val ?? DateTime.now(),
        firstDate: DateTime(2000), lastDate: DateTime(2060),
        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))), child: child!));
      if (p != null) onChanged(p);
    }, child: InputDecorator(
      decoration: InputDecoration(labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57))),
      child: Text(val != null ? DateFormat('dd/MM/yyyy').format(val) : 'Sélectionner',
        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: val != null ? const Color(0xFF1F2A2E) : Colors.grey)))));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Vaccin (vétérinaire)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _tf('Vaccin *', _vaccin),
        _tf('N° de lot', _lot),
        _dp(context, 'Date *', _date, (d) => setState(() => _date = d)),
        _dp(context, 'Date de rappel', _rappel, (d) => setState(() => _rappel = d)),
      ])),
      actions: _saving
          ? [const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())]
          : [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
              TextButton(onPressed: _save,
                  child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
            ],
    );
  }
}

// ─── VET06 : dialog ajout traitement vétérinaire ─────────────────────────────

class _VetAddTraitementDialog extends StatefulWidget {
  final String animalId, vetUid, vetName, visiteRef;
  final String? rdvId;
  const _VetAddTraitementDialog({required this.animalId, required this.vetUid,
      required this.vetName, required this.visiteRef, this.rdvId});
  @override State<_VetAddTraitementDialog> createState() => _VetAddTraitementDialogState();
}
class _VetAddTraitementDialogState extends State<_VetAddTraitementDialog> {
  final _nom       = TextEditingController();
  final _posologie = TextEditingController();
  String _type = 'medicament';
  DateTime? _date, _dateFin;
  bool _saving = false;
  bool _posologieDansOrdo = false; // true = "voir ordonnance"

  @override
  void dispose() { _nom.dispose(); _posologie.dispose(); super.dispose(); }

  Future<void> _save() async {
    try {
      if (_nom.text.trim().isEmpty) throw const SaisieInvalide('Indiquez le nom du traitement.');
      controlerDatesSante(date: _date, fin: _dateFin);
    } on SaisieInvalide catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('traitements').insert({
        'animal_id': widget.animalId,
        'type': _type, 'nom': _nom.text.trim(),
        'posologie': _posologieDansOrdo ? 'Voir ordonnance jointe' : _posologie.text.trim(),
        'date': _date!.toIso8601String().substring(0, 10),
        'date_fin': _dateFin?.toIso8601String().substring(0, 10),
        'source': 'veterinaire', 'vet_id': widget.vetUid,
        'veterinaire': widget.vetName, 'visite_ref': widget.visiteRef,
        if (widget.rdvId != null) 'rdv_id': widget.rdvId!,
      });
      if (mounted) Navigator.pop(context, true);
      RegistreHelper.writeActe(
        animalId: widget.animalId, typeActe: 'traitement', dateActe: _date!,
        intervenant: widget.vetName,
        description: _nom.text.trim(),
      );
      _notifyOwnerVetEntry(animalId: widget.animalId, vetName: widget.vetName, typeActe: 'traitement').catchError((_) {});
      if (_dateFin != null) {
        _scheduleTraitementDailyReminders(
          animalId: widget.animalId,
          nom: _nom.text.trim(),
          dateDebut: _date!,
          dateFin: _dateFin!,
        ).catchError((_) {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _types = ['medicament', 'antibiotique', 'anti-inflammatoire', 'autre'];

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(controller: ctrl, maxLines: maxLines,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      decoration: InputDecoration(labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)));

  Widget _dp(BuildContext ctx, String label, DateTime? val, ValueChanged<DateTime> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(onTap: () async {
      final p = await showDatePicker(context: ctx, initialDate: val ?? DateTime.now(),
        firstDate: DateTime(2000), lastDate: DateTime(2060),
        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))), child: child!));
      if (p != null) onChanged(p);
    }, child: InputDecorator(
      decoration: InputDecoration(labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57))),
      child: Text(val != null ? DateFormat('dd/MM/yyyy').format(val) : 'Sélectionner',
        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: val != null ? const Color(0xFF1F2A2E) : Colors.grey)))));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Traitement (vétérinaire)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(value: _type,
            decoration: InputDecoration(labelText: 'Type',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
            items: _types.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) { if (v != null) setState(() => _type = v); })),
        _tf('Nom du produit *', _nom),
        // Posologie : saisie libre OU renvoi vers ordonnance
        InkWell(
          onTap: () => setState(() => _posologieDansOrdo = !_posologieDansOrdo),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border.all(color: _posologieDansOrdo ? const Color(0xFF8D6E63) : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(_posologieDansOrdo ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18, color: const Color(0xFF8D6E63)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Posologie dans l\'ordonnance jointe',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
            ]),
          ),
        ),
        if (!_posologieDansOrdo) _tf('Posologie (ex: 1 cp matin + soir)', _posologie),
        _dp(context, 'Date début *', _date, (d) => setState(() => _date = d)),
        _dp(context, 'Date fin', _dateFin, (d) => setState(() => _dateFin = d)),
      ])),
      actions: _saving
          ? [const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())]
          : [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
              TextButton(onPressed: _save,
                  child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
            ],
    );
  }
}

// ─── VET06 : dialog ajout visite vétérinaire ─────────────────────────────────

class _VetAddVisiteDialog extends StatefulWidget {
  final String animalId, vetUid, vetName, visiteRef;
  final String? rdvId;
  const _VetAddVisiteDialog({required this.animalId, required this.vetUid,
      required this.vetName, required this.visiteRef, this.rdvId});
  @override State<_VetAddVisiteDialog> createState() => _VetAddVisiteDialogState();
}
class _VetAddVisiteDialogState extends State<_VetAddVisiteDialog> {
  static const _motifs = ['Consultation', 'Rappel de vaccin', 'Urgence', 'Suivi post-opératoire', 'Contrôle', 'Autre'];
  String _motif = 'Consultation';
  final _diag  = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date;
  bool _saving = false;

  @override
  void dispose() { _diag.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_date == null) return;
    setState(() => _saving = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final profRow = await Supabase.instance.client.from('user_profiles_complet')
          .select('id').eq('uid', widget.vetUid).eq('is_main', true).maybeSingle();
      final vetProfileId = profRow?['id'] as String?;
      await Supabase.instance.client.from('visites').insert({
        'id': id, 'animal_id': widget.animalId,
        'motif': _motif, 'veterinaire': widget.vetName,
        'date': _date!.toIso8601String().substring(0, 10),
        'diagnostic': _diag.text.trim(), 'notes': _notes.text.trim(),
        'source': 'veterinaire', 'vet_id': widget.vetUid,
        if (vetProfileId != null) 'vet_profile_id': vetProfileId,
        'visite_ref': widget.visiteRef,
        if (widget.rdvId != null) 'rdv_id': widget.rdvId!,
      });
      if (mounted) Navigator.pop(context, true);
      RegistreHelper.writeActe(
        animalId: widget.animalId, typeActe: 'visite', dateActe: _date!,
        intervenant: widget.vetName,
        description: '$_motif${_diag.text.trim().isNotEmpty ? " — ${_diag.text.trim()}" : ""}',
      );
      _notifyOwnerVetEntry(animalId: widget.animalId, vetName: widget.vetName, typeActe: 'visite').catchError((_) {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(controller: ctrl, maxLines: maxLines,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      decoration: InputDecoration(labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)));

  Widget _dp(BuildContext ctx, String label, DateTime? val, ValueChanged<DateTime> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(onTap: () async {
      final p = await showDatePicker(context: ctx, initialDate: val ?? DateTime.now(),
        firstDate: DateTime(2000), lastDate: DateTime(2060),
        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6E9E57))), child: child!));
      if (p != null) onChanged(p);
    }, child: InputDecorator(
      decoration: InputDecoration(labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6E9E57))),
      child: Text(val != null ? DateFormat('dd/MM/yyyy').format(val) : 'Sélectionner',
        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: val != null ? const Color(0xFF1F2A2E) : Colors.grey)))));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Visite vétérinaire', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(value: _motif,
            decoration: InputDecoration(labelText: 'Motif *',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
            items: _motifs.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) { if (v != null) setState(() => _motif = v); })),
        _dp(context, 'Date *', _date, (d) => setState(() => _date = d)),
        _tf('Diagnostic / Observations', _diag),
        _tf('Notes', _notes, maxLines: 3),
      ])),
      actions: _saving
          ? [const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())]
          : [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
              TextButton(onPressed: _save,
                  child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
            ],
    );
  }
}

// ─── VET06 : dialog ajout ordonnance PDF ─────────────────────────────────────

class _VetAddOrdoDialog extends StatefulWidget {
  final String animalId, vetUid, vetName;
  final String? ownerUid, rdvId, vetProfileId;
  const _VetAddOrdoDialog({required this.animalId, required this.vetUid,
      required this.vetName, this.vetProfileId, this.ownerUid, this.rdvId});
  @override State<_VetAddOrdoDialog> createState() => _VetAddOrdoDialogState();
}
class _VetAddOrdoDialogState extends State<_VetAddOrdoDialog> {
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  File? _pdfFile;
  bool _saving = false;

  @override
  void dispose() { _notes.dispose(); super.dispose(); }

  Future<void> _pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _pdfFile = File(result.files.single.path!));
    }
  }

  Future<void> _save() async {
    if (_pdfFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez sélectionner un fichier PDF')));
      return;
    }
    setState(() => _saving = true);
    try {
      final name  = '${DateTime.now().millisecondsSinceEpoch}.pdf';
      final url   = await uploadDocument(_pdfFile!, 'ordonnances/${widget.vetUid}/$name');
      final today = _date;
      String? ownerProfileId;
      if (widget.ownerUid != null) {
        final row = await Supabase.instance.client.from('user_profiles_complet').select('id').eq('uid', widget.ownerUid!).eq('is_main', true).maybeSingle();
        ownerProfileId = row?['id'] as String?;
      }
      await Supabase.instance.client.from('ordonnances').insert({
        'pro_uid':   widget.vetUid,
        if (widget.vetProfileId != null) 'pro_profile_id': widget.vetProfileId,
        'animal_id': widget.animalId,
        if (widget.ownerUid != null) 'owner_uid': widget.ownerUid,
        if (ownerProfileId != null) 'owner_profile_id': ownerProfileId,
        if (widget.rdvId != null) 'rdv_id': widget.rdvId!,
        'doc_url':   url,
        'date_emit': '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}',
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'source':    'veterinaire',
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Ordonnance PDF', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(onTap: () async {
            final p = await showDatePicker(context: context, initialDate: _date,
              firstDate: DateTime(2000), lastDate: DateTime(2060),
              builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6D28D9))), child: child!));
            if (p != null) setState(() => _date = p);
          }, child: InputDecorator(
            decoration: InputDecoration(labelText: 'Date',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6D28D9))),
            child: Text(DateFormat('dd/MM/yyyy').format(_date),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))))),
        OutlinedButton.icon(
          onPressed: _pickPdf,
          icon: const Icon(Icons.upload_file, size: 18, color: Color(0xFF6D28D9)),
          label: Text(
            _pdfFile != null ? _pdfFile!.path.split('/').last : 'Sélectionner un PDF *',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6D28D9)),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _pdfFile != null ? const Color(0xFF6D28D9) : Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size(double.infinity, 44),
            alignment: Alignment.centerLeft,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _notes, maxLines: 3,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
          decoration: InputDecoration(labelText: 'Notes / Posologie',
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D28D9))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
        ),
      ])),
      actions: _saving
          ? [const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Color(0xFF6D28D9)))]
          : [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
              TextButton(onPressed: _save,
                  child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Color(0xFF6D28D9)))),
            ],
    );
  }
}

// ─── VET06 : dialog ajout radio / examen ─────────────────────────────────────

class _VetAddRadioDialog extends StatefulWidget {
  final String animalId, vetUid, vetName, visiteRef;
  const _VetAddRadioDialog({required this.animalId, required this.vetUid,
      required this.vetName, required this.visiteRef});
  @override State<_VetAddRadioDialog> createState() => _VetAddRadioDialogState();
}
class _VetAddRadioDialogState extends State<_VetAddRadioDialog> {
  final _titre = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  File? _imgFile;
  bool _saving = false;

  @override
  void dispose() { _titre.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _imgFile = File(result.files.single.path!));
    }
  }

  Future<void> _save() async {
    if (_imgFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez sélectionner un fichier')));
      return;
    }
    setState(() => _saving = true);
    try {
      final name = '${DateTime.now().millisecondsSinceEpoch}.${_imgFile!.path.split('.').last}';
      final url  = await uploadDocument(_imgFile!, 'radios/${widget.vetUid}/$name');
      await Supabase.instance.client.from('radios').insert({
        'animal_id':   widget.animalId,
        'vet_id':      widget.vetUid,
        'veterinaire': widget.vetName,
        'titre':       _titre.text.trim().isNotEmpty ? _titre.text.trim() : 'Radio / Examen',
        'notes':       _notes.text.trim(),
        'image_url':   url,
        'date':        '${_date.year}-${_date.month.toString().padLeft(2,'0')}-${_date.day.toString().padLeft(2,'0')}',
        'source':      'veterinaire', 'visite_ref': widget.visiteRef,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Radio / Examen', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(controller: _titre,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            decoration: InputDecoration(labelText: 'Titre (ex: Radio thorax)',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0284C7))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true))),
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(onTap: () async {
            final p = await showDatePicker(context: context, initialDate: _date,
              firstDate: DateTime(2000), lastDate: DateTime(2060),
              builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF0284C7))), child: child!));
            if (p != null) setState(() => _date = p);
          }, child: InputDecorator(
            decoration: InputDecoration(labelText: 'Date',
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF0284C7))),
            child: Text(DateFormat('dd/MM/yyyy').format(_date),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))))),
        OutlinedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.upload_file, size: 18, color: Color(0xFF0284C7)),
          label: Text(
            _imgFile != null ? _imgFile!.path.split('/').last : 'Sélectionner un fichier (image/PDF) *',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF0284C7)),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _imgFile != null ? const Color(0xFF0284C7) : Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size(double.infinity, 44),
            alignment: Alignment.centerLeft,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _notes, maxLines: 2,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
          decoration: InputDecoration(labelText: 'Observations',
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0284C7))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
        ),
      ])),
      actions: _saving
          ? [const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Color(0xFF0284C7)))]
          : [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
              TextButton(onPressed: _save,
                  child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Color(0xFF0284C7)))),
            ],
    );
  }
}

// ─── Owner : dialog ajout radio / examen ─────────────────────────────────────

class _AddRadioDialog extends StatefulWidget {
  final String animalId;
  /// Saisie du vétérinaire : source / vet_id / nom sur la ligne.
  final String? vetId;
  final String? vetName;
  const _AddRadioDialog({required this.animalId, this.vetId, this.vetName});
  @override State<_AddRadioDialog> createState() => _AddRadioDialogState();
}
class _AddRadioDialogState extends State<_AddRadioDialog> {
  final _titre = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date;
  File? _file;
  bool _saving = false;

  @override
  void dispose() { _titre.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _file = File(result.files.single.path!));
    }
  }

  Future<void> _save() async {
    // Vétérinaire : pièce jointe facultative (résultats saisis) ; propriétaire : obligatoire.
    if ((_file == null && widget.vetId == null) || _date == null) return;
    setState(() => _saving = true);
    try {
      final uid  = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      String? url;
      if (_file != null) {
        final name = '${DateTime.now().millisecondsSinceEpoch}.${_file!.path.split('.').last}';
        url = await uploadDocument(_file!, 'radios/$uid/$name');
      }
      await Supabase.instance.client.from('radios').insert({
        'animal_id': widget.animalId,
        'titre':     _titre.text.trim().isNotEmpty ? _titre.text.trim() : 'Radio / Examen',
        'notes':     _notes.text.trim(), 'image_url': url,
        'date':      '${_date!.year}-${_date!.month.toString().padLeft(2,'0')}-${_date!.day.toString().padLeft(2,'0')}',
        if (widget.vetId != null) ...{'source': 'veterinaire', 'vet_id': widget.vetId, 'veterinaire': widget.vetName},
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _BaseDialog(
    title: 'Ajouter une radio / examen',
    fields: [
      _DF('Titre (ex: Radio thorax)', _titre),
      _DD('Date *', _date, (d) => setState(() => _date = d)),
      _DF('Observations', _notes, maxLines: 2),
    ],
    onSave: () async {
      if (_file == null && widget.vetId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sélectionnez d\'abord un fichier')));
        return false;
      }
      if (_date == null) return false;
      await _save();
      return false;
    },
  );
}

// ─── Rappels quotidiens traitement ───────────────────────────────────────────

Future<void> _scheduleTraitementDailyReminders({
  required String animalId,
  required String nom,
  required DateTime dateDebut,
  required DateTime dateFin,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  String animalNom = '';
  try {
    final a = await Supabase.instance.client
        .from('animaux').select('nom').eq('id', animalId).maybeSingle();
    animalNom = (a?['nom'] as String?) ?? '';
  } catch (_) {}
  final titre = 'Traitement${animalNom.isNotEmpty ? " $animalNom" : ""} — $nom';
  final proProfileId = await profilPourAnimal(animalId);
  final events = <Map<String, dynamic>>[];
  var day = DateTime(dateDebut.year, dateDebut.month, dateDebut.day);
  final end = DateTime(dateFin.year, dateFin.month, dateFin.day);
  while (!day.isAfter(end)) {
    events.add({
      'uid':            uid,
      'titre':          titre,
      'type':           'medication',
      'date_debut':     DateTime(day.year, day.month, day.day, 8, 0).toUtc().toIso8601String(),
      'animal_id':      animalId,
      'pro_profile_id': proProfileId,
    });
    day = day.add(const Duration(days: 1));
  }
  if (events.isEmpty) return;
  await Supabase.instance.client.from('agenda_events').insert(events);
}

// ─── Lien ordonnance liée (via visite_ref) ───────────────────────────────────

class _OrdonnanceLinkSection extends StatefulWidget {
  final String visiteRef;
  const _OrdonnanceLinkSection({required this.visiteRef});
  @override State<_OrdonnanceLinkSection> createState() => _OrdonnanceLinkSectionState();
}
class _OrdonnanceLinkSectionState extends State<_OrdonnanceLinkSection> {
  String? _url;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('ordonnances').select('doc_url')
          .eq('visite_ref', widget.visiteRef).limit(1);
      final list = rows as List;
      if (mounted) setState(() {
        _url = list.isNotEmpty ? list.first['doc_url'] as String? : null;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _url == null || _url!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(width: 130,
          child: Text('Ordonnance',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: Color(0xFF6F767B), fontWeight: FontWeight.w500))),
        Expanded(child: GestureDetector(
          onTap: () async {
            await ouvrirDocument(context, _url!);
          },
          child: const Text('Voir le document',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                fontWeight: FontWeight.w600, color: Color(0xFF6D28D9),
                decoration: TextDecoration.underline)),
        )),
      ]),
    );
  }
}

// ─── Lien consultation vétérinaire (via rdv_id) ──────────────────────────────

class _RdvLinkSection extends StatefulWidget {
  final String rdvId;
  const _RdvLinkSection({required this.rdvId});
  @override State<_RdvLinkSection> createState() => _RdvLinkSectionState();
}
class _RdvLinkSectionState extends State<_RdvLinkSection> {
  Map<String, dynamic>? _rdv;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rdv = await Supabase.instance.client
          .from('rdv').select('id, date_heure, cat_pro').eq('id', widget.rdvId).maybeSingle();
      if (mounted) setState(() { _rdv = rdv; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final label = _rdv != null
        ? 'Consultation du ${_rdv!['date_heure'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(_rdv!['date_heure'].toString())?.toLocal() ?? DateTime.now()) : '—'}'
        : 'Consultation vétérinaire';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(width: 130,
          child: Text('Consultation',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: Color(0xFF6F767B), fontWeight: FontWeight.w500))),
        Expanded(child: Text(label,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
              color: Color(0xFF0C5C6C), fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ─── Onglet Documents ────────────────────────────────────────────────────────

class _DocumentsTab extends StatefulWidget {
  final String animalId;
  const _DocumentsTab({required this.animalId});

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  static final _supa = Supabase.instance.client;
  static const _green = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _certs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await _supa
          .from('documents_animaux')
          .select('*')
          .eq('animal_id', widget.animalId)
          .order('created_at', ascending: false);
      final certs = await _supa
          .from('certificats_engagement')
          .select('id, nom_animal, acquereur_prenom, acquereur_nom, statut, date_remise, date_signature_acquereur, token_signature')
          .eq('animal_id', widget.animalId)
          .order('date_remise', ascending: false);
      if (mounted) {
        setState(() {
          _docs = List<Map<String, dynamic>>.from(docs);
          _certs = List<Map<String, dynamic>>.from(certs);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));
    final total = _docs.length + _certs.length;
    if (total == 0) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('Aucun document lié à cet animal',
              style: TextStyle(color: Colors.grey[500], fontFamily: 'Galey', fontSize: 15)),
          const SizedBox(height: 4),
          Text('Créez un contrat depuis Administratif → Contrats',
              style: TextStyle(color: Colors.grey[400], fontFamily: 'Galey', fontSize: 12)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_docs.isNotEmpty) ...[
            _sectionHeader('Contrats & Documents'),
            ..._docs.map(_buildDocCard),
          ],
          if (_certs.isNotEmpty) ...[
            if (_docs.isNotEmpty) const SizedBox(height: 16),
            _sectionHeader('Certificats d\'engagement'),
            ..._certs.map(_buildCertCard),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String titre) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titre,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 13, color: _green, letterSpacing: 0.3)),
      );

  Future<void> _transmettreDoc(Map<String, dynamic> doc) async {
    final id = doc['id'].toString();
    final token = doc['token'] as String?;
    if (token == null) return;
    await _supa.from('documents_animaux').update({'statut': 'en_attente'}).eq('id', id);
    // Notifier l'acquéreur s'il est sur PetsMatch
    final meta = doc['metadata'] as Map? ?? {};
    final acqEmail = meta['acquereur_email'] as String?;
    if (acqEmail != null && acqEmail.trim().isNotEmpty) {
      final target = await trouverUtilisateurParEmail(acqEmail.trim());
      if (target != null) {
        final acqUid = target['uid'] as String;
        final signingUrl = '$kSiteBaseUrl/signer-contrat/$token';
        final acqProfile = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', acqUid).eq('profile_type', 'particulier').maybeSingle();
        await _supa.from('notifications').insert({
          'uid': acqUid,
          'type': 'contrat_invite',
          'title': '📄 Contrat à signer',
          'body': '${doc['titre'] ?? 'Un contrat'} vous a été transmis — vérifiez et signez',
          if (acqProfile?['id'] != null) 'profile_id': acqProfile!['id'],
          'data': {'token': token, 'url': signingUrl},
          'read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }
    if (mounted) {
      setState(() {
        final idx = _docs.indexWhere((d) => d['id'] == id);
        if (idx != -1) _docs[idx] = {..._docs[idx], 'statut': 'en_attente'};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contrat transmis pour signature'), duration: Duration(seconds: 3)),
      );
    }
  }

  Widget _buildDocCard(Map<String, dynamic> doc) {
    final type = doc['type'] as String? ?? '';
    final statut = doc['statut'] as String? ?? 'brouillon';
    final meta = doc['metadata'] as Map? ?? {};
    final acq = '${meta['acquereur_prenom'] ?? meta['acquereur_nom'] ?? ''}'.trim();
    final date = doc['created_at'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(doc['created_at']).toLocal())
        : '';
    final url = doc['url'] as String?;
    final token = doc['token'] as String?;
    final signingUrl = token != null ? '$kSiteBaseUrl/signer-contrat/$token' : null;
    final isBrouillon = statut == 'brouillon';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Colors.grey[50],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: _green.withOpacity(0.1),
            child: Icon(_typeIcon(type), color: _green, size: 20),
          ),
          title: Text(_typeLabel(type),
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (acq.isNotEmpty)
              Text(acq, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
            Row(children: [
              Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey[500])),
              const SizedBox(width: 8),
              _statutBadge(statut),
            ]),
          ]),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (type == 'facture')
                IconButton(
                  icon: const Icon(Icons.visibility_outlined, size: 18, color: _green),
                  tooltip: 'Ouvrir la facture',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ContratSignaturePage(
                      token: token, documentId: token == null ? doc['id'] as String? : null,
                    ),
                  )),
                )
              else if (token != null && !isBrouillon) ...[
                IconButton(
                  icon: const Icon(Icons.draw_outlined, size: 18, color: _green),
                  tooltip: 'Lire et signer',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ContratSignaturePage(token: token),
                  )),
                ),
                IconButton(
                  icon: const Icon(Icons.link, size: 18, color: _green),
                  tooltip: 'Copier le lien',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: signingUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lien copié'), duration: Duration(seconds: 2)),
                    );
                  },
                ),
              ] else if (url != null && !isBrouillon)
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18, color: _green),
                  onPressed: () => ouvrirDocument(context, url),
                ),
            ],
          ),
        ),
        // Bouton Transmettre pour les brouillons
        if (isBrouillon && token != null && type != 'facture')
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: FilledButton.icon(
              onPressed: () => _transmettreDoc(doc),
              style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              icon: const Icon(Icons.send_outlined, size: 16),
              label: const Text('📤 Transmettre pour signature',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
      ]),
    );
  }

  Widget _buildCertCard(Map<String, dynamic> cert) {
    final statut = cert['statut'] as String? ?? 'en_attente';
    final acq = '${cert['acquereur_prenom'] ?? ''} ${cert['acquereur_nom'] ?? ''}'.trim();
    final dateRaw = cert['date_remise'] as String?;
    final dateSig = cert['date_signature_acquereur'] as String?;
    final date = dateRaw != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateRaw).toLocal())
        : '';
    final token = cert['token_signature'] as String?;
    final sigLink = token != null ? 'https://www.petsmatchapp.com/certificat/$token' : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Colors.grey[50],
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: token == null ? null : () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => ContratSignaturePage(certificatEngagementToken: token),
          ));
          _load();
        },
        leading: CircleAvatar(
          backgroundColor: Colors.amber.withOpacity(0.15),
          child: const Icon(Icons.verified_outlined, color: Colors.amber, size: 20),
        ),
        title: const Text('Certificat d\'engagement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (acq.isNotEmpty)
            Text(acq, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          Row(children: [
            Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey[500])),
            const SizedBox(width: 8),
            _statutBadgeCert(statut, dateSig),
          ]),
        ]),
        trailing: sigLink != null && statut != 'signe'
            ? IconButton(
                icon: const Icon(Icons.link, size: 18, color: _green),
                tooltip: 'Copier le lien de signature',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: sigLink));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lien copié'), duration: Duration(seconds: 2)),
                  );
                },
              )
            : null,
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'contrat_vente': return Icons.handshake_outlined;
      case 'contrat_reservation': return Icons.bookmark_border;
      case 'certificat_cession': return Icons.assignment_turned_in_outlined;
      case 'facture': return Icons.receipt_long_outlined;
      case 'devis': return Icons.request_quote_outlined;
      default: return Icons.description_outlined;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'contrat_vente': return 'Contrat de vente';
      case 'contrat_reservation': return 'Contrat de réservation';
      case 'contrat_saillie': return 'Contrat de saillie';
      case 'certificat_cession': return 'Certificat de cession';
      case 'contrat_adoption': return 'Contrat d\'adoption';
      case 'facture': return 'Facture';
      case 'devis': return 'Devis (éducateur)';
      default: return 'Document';
    }
  }

  Widget _statutBadge(String statut) {
    Color bg; Color fg; String label;
    switch (statut) {
      case 'signe':   bg = const Color(0xFFDCFCE7); fg = const Color(0xFF166534); label = 'Signé'; break;
      case 'partiellement_signe': bg = const Color(0xFFDBEAFE); fg = const Color(0xFF1E40AF); label = 'Partiel'; break;
      case 'en_attente': bg = const Color(0xFFFEF3C7); fg = const Color(0xFF92400E); label = 'Transmis'; break;
      case 'genere':  bg = const Color(0xFFE0F2FE); fg = const Color(0xFF075985); label = 'Émise'; break;
      case 'archive': bg = const Color(0xFFE5E7EB); fg = const Color(0xFF374151); label = 'Archivé'; break;
      default:        bg = const Color(0xFFFEF3C7); fg = const Color(0xFF92400E); label = 'Brouillon';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg, fontFamily: 'Galey')),
    );
  }

  Widget _statutBadgeCert(String statut, String? dateSig) {
    if (statut == 'signe') {
      final ds = dateSig != null ? DateFormat('dd/MM/yy').format(DateTime.parse(dateSig).toLocal()) : '';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
        child: Text('Signé${ds.isNotEmpty ? ' $ds' : ''}',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF166534), fontFamily: 'Galey')),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
      child: const Text('En attente',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF92400E), fontFamily: 'Galey')),
    );
  }
}

// ─── Notification propriétaire — entrée vétérinaire ──────────────────────────

/// Appel fire-and-forget depuis les dialogs vet pour notifier le proprio.
Future<void> _notifyOwnerVetEntry({
  required String animalId,
  required String vetName,
  required String typeActe, // 'vaccin' | 'traitement' | 'visite'
}) async {
  try {
    final fn = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('notifyOwnerVetEntry');
    await fn.call({'animalId': animalId, 'vetName': vetName, 'typeActe': typeActe});
  } catch (_) {} // fire-and-forget : n'interrompt pas le flux principal
}


/// Statut d'un animal d'association — pastille cliquable en haut de la fiche.
class _StatutAssoBar extends StatelessWidget {
  final String statut;
  final Future<void> Function(String) onChange;
  const _StatutAssoBar({required this.statut, required this.onChange});

  static const _statuts = [
    ('en_soin', 'En soin', Colors.orange, Icons.healing_outlined),
    ('disponible', 'Disponible à l\'adoption', Color(0xFF6E9E57), Icons.favorite_outline),
    ('adopte', 'Adopté', Color(0xFF0C5C6C), Icons.home_outlined),
    ('transfere', 'Transféré', Colors.blue, Icons.swap_horiz),
    ('decede', 'Décédé', Colors.redAccent, Icons.sentiment_dissatisfied_outlined),
  ];
  static const _sorties = {'adopte', 'transfere', 'decede'};

  Future<void> _choisir(BuildContext context) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Statut de l\'animal', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text('« En famille d\'accueil » se règle depuis Familles d\'accueil.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          for (final e in _statuts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.$4, color: e.$3),
              title: Text(e.$2, style: TextStyle(fontFamily: 'Galey',
                  fontWeight: e.$1 == statut ? FontWeight.w700 : FontWeight.w500)),
              trailing: e.$1 == statut ? Icon(Icons.check, color: e.$3) : null,
              onTap: () => Navigator.pop(ctx, e.$1),
            ),
        ]),
      )),
    );
    if (choix == null || choix == statut || !context.mounted) return;
    if (_sorties.contains(choix)) {
      final label = _statuts.firstWhere((e) => e.$1 == choix).$2;
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text('Passer en « $label » ?', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('L\'animal sortira de vos animaux présents et la sortie sera inscrite au registre. '
            'Complétez au besoin le destinataire dans « Registre Entrée / Sortie ».',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
        ],
      ));
      if (ok != true) return;
    }
    await onChange(choix);
  }

  @override
  Widget build(BuildContext context) {
    final e = _statuts.firstWhere((x) => x.$1 == statut,
        orElse: () => (statut, statut, Colors.grey, Icons.label_outline));
    return GestureDetector(
      onTap: () => _choisir(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: e.$3.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: e.$3.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(e.$4, color: e.$3, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Statut : ', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
            TextSpan(text: e.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: e.$3)),
          ]))),
          Text('Changer', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: e.$3)),
          Icon(Icons.expand_more, color: e.$3, size: 18),
        ]),
      ),
    );
  }
}
