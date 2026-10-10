import 'package:PetsMatch/pages/eleveur/animaux/acquereur_contact.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/portee_form_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/services/chip_scanner_service.dart';
import 'package:PetsMatch/services/chaleur_interval_service.dart';
import 'package:PetsMatch/pages/eleveur/animaux/portee_poids_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/portee_soin_sheet.dart';
import 'package:PetsMatch/pages/eleveur/animaux/portee_edit_sheet.dart';
import 'package:PetsMatch/pages/eleveur/animaux/suivi_cessions_tab.dart';
import 'package:PetsMatch/services/chaleurs_notif_service.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Données espèces ──────────────────────────────────────────────────────────

const kSpeciesData = [
  (value: 'tous',   label: 'Tous',     color: Color(0xFF1F2A2E)),
  (value: 'chien',  label: 'Chiens',   color: Color(0xFF6E9E57)),
  (value: 'chat',   label: 'Chats',    color: Color(0xFF0C5C6C)),
  (value: 'cheval', label: 'Chevaux',  color: Color(0xFF5B8648)),
  (value: 'lapin',  label: 'Lapins',   color: Color(0xFFE08080)),
  (value: 'ovin',   label: 'Ovins',    color: Color(0xFF5F9EAA)),
  (value: 'caprin', label: 'Caprins',  color: Color(0xFF8D6E63)),
  (value: 'porcin', label: 'Porcins',  color: Color(0xFFE25C5C)),
  (value: 'nac',    label: 'NAC',      color: Color(0xFFF4B400)),
  (value: 'oiseau', label: 'Oiseaux',  color: Color(0xFF26A69A)),
  (value: 'autre',  label: 'Autres',   color: Color(0xFF6F767B)),
];

String speciesLabel(String value) =>
    kSpeciesData.where((s) => s.value == value).firstOrNull?.label ?? value;

Color speciesColor(String value) =>
    kSpeciesData.where((s) => s.value == value).firstOrNull?.color ?? const Color(0xFF6E9E57);

Widget speciesIcon(String espece, double size, Color color) {
  switch (espece) {
    case 'chien':  return FaIcon(FontAwesomeIcons.dog,   size: size, color: color);
    case 'chat':   return FaIcon(FontAwesomeIcons.cat,   size: size, color: color);
    case 'cheval': return FaIcon(FontAwesomeIcons.horse, size: size, color: color);
    case 'lapin':  return FaIcon(FontAwesomeIcons.paw,   size: size, color: color);
    case 'oiseau': return FaIcon(FontAwesomeIcons.dove,  size: size, color: color);
    case 'nac':    return FaIcon(FontAwesomeIcons.bug,   size: size, color: color);
    case 'ovin':   return FaIcon(FontAwesomeIcons.leaf,  size: size, color: color);
    case 'caprin': return Icon(Icons.grass,              size: size, color: color);
    case 'porcin': return Icon(Icons.circle,             size: size, color: color);
    default:       return Icon(Icons.pets,               size: size, color: color);
  }
}

// ─── Page principale ──────────────────────────────────────────────────────────

class MesAnimauxPage extends StatefulWidget {
  /// 0 = Présents, 1 = Cédés, 2 = Suivi cessions, 3 = Décédés
  final int initialTab;
  const MesAnimauxPage({super.key, this.initialTab = 0});
  @override
  State<MesAnimauxPage> createState() => _MesAnimauxPageState();
}

class _MesAnimauxPageState extends State<MesAnimauxPage>
    with SingleTickerProviderStateMixin {
  // Présents filters
  String _filterEspece  = 'tous';
  String _filterSexe    = 'tous';
  String _filterRace     = '';
  String _presentsSubTab = 'tous'; // 'tous', 'repro', 'bebes'
  String _selectedPorteeId = ''; // '' = toutes les portées (filtre "Bébés")
  // Filtre "Bébés" : présents (défaut) ou cédés — pour retrouver une portée
  // et ses données après les départs.
  /// Onglet Cédés : tous les animaux, ou bébés regroupés par portée.
  String _cedesVue = 'tous';
  String _selectedPorteeCedeeId = '';
  bool _filterRetraite = false;
  bool _filterRepro    = false;
  bool _filterGestante = false;
  bool _filterChaleur  = false;
  // Réservation (statut commercial) — distincte de la présence à l'élevage
  String _filterReservation = 'tous';
  bool   _selectMode    = false;
  final Set<String> _selectedIds = {};

  // Cédés filters (ex-« Anciens », ne montre plus que les animaux sortis :
  // les décédés ont leur propre onglet, cf. _decedes* ci-dessous)
  String    _anciensEspece = 'tous';
  DateTime? _anciensDtDebut;
  DateTime? _anciensDtFin;

  // Décédés filters
  String    _decedesEspece = 'tous';
  DateTime? _decedesDtDebut;
  DateTime? _decedesDtFin;

  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  // uid Firebase réel du propriétaire de l'élevage actif — résolu dans
  // _loadAnimaux(), réutilisé pour les vérifications "suis-je le cédant/
  // l'éleveur" ailleurs dans la page (cf. _openFiche).
  String? _ownerUid;
  List<Map<String, dynamic>> _animauxData = [];
  Set<String> _currentOwnerIds    = {};   // date_fin IS NULL → propriétaire actuel
  Set<String> _formerOwnerIds     = {};   // date_fin NOT NULL → ancien propriétaire
  Set<String> _cessionEnAttenteIds = {};  // fallback : animaux 'sorti' avec contrat en attente
  Map<String, bool> _chaleurFlags  = {};
  Map<String, bool> _gestanteFlags = {};
  bool _loading = true;

  static const _green = Color(0xFF6E9E57);
  static const _teal  = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this,
        initialIndex: widget.initialTab.clamp(0, 3));
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() { _selectMode = false; _selectedIds.clear(); });
      }
    });
    _loadAnimaux();
  }

  static int _intervalChaleurs(String espece) {
    switch (espece.toLowerCase()) {
      case 'chien':  return 182;
      case 'chat':   return 21;
      case 'lapin':  return 14;
      case 'ovin':   return 17;
      case 'caprin': return 21;
      case 'porcin': return 21;
      case 'cheval': return 21;
      default:       return 0;
    }
  }

  // Âge de retraite (années) par espèce — même convention que la fiche
  // animal / le rappel de chaleurs. Une femelle à/après cet âge n'a plus de
  // cycle de chaleurs à suivre.
  static const _agesRetraite = <String, int>{
    'chien': 7, 'chat': 8, 'lapin': 5,
    'cheval': 18, 'ovin': 8, 'caprin': 8, 'porcin': 5, 'ane': 15,
  };

  // Fenêtre post mise-bas (jours) pendant laquelle le cycle est suspendu —
  // même seuil que « lactation récente » utilisé ailleurs dans l'app (< 8 sem).
  static const _joursLactation = 56;

  Future<void> _loadAnimaux() async {
    if (_uid == null) { setState(() => _loading = false); return; }
    if (_animauxData.isEmpty) setState(() => _loading = true);
    try {
      final supa = Supabase.instance.client;
      final activeProfileId = User_Info.activeProfileId;

      // uid Firebase RÉEL du propriétaire du profil actif — jamais forcément
      // _uid : un cogérant (elevage_cogerants) a un uid différent du gérant,
      // mais la ligne user_profiles du profil emprunté (activeProfileId)
      // reste celle du gérant. Sans ça, "Mes Animaux" resterait scopé sur
      // le compte personnel du cogérant (0 animal trouvé).
      String ownerUid = _uid!;
      if (activeProfileId.isNotEmpty) {
        final ownerRow = await supa.from('user_profiles_complet').select('uid').eq('id', activeProfileId).maybeSingle();
        ownerUid = (ownerRow?['uid'] as String?) ?? _uid!;
      }
      _ownerUid = ownerUid;

      // Vérifie si la migration V2.05 a été jouée (au moins une ligne avec profile_id_proprio)
      // → si oui, on filtre par profil ; si non, on retombe sur uid_proprio (rétrocompat)
      List ownRows;
      if (activeProfileId.isNotEmpty) {
        final check = await supa.from('animaux_proprietes')
            .select('animal_id')
            .eq('uid_proprio', ownerUid)
            .not('profile_id_proprio', 'is', null)
            .limit(1);
        if ((check as List).isNotEmpty) {
          // Migration faite → filtre strict par profil (liste vide = normal pour ce profil)
          ownRows = await supa.from('animaux_proprietes')
              .select('animal_id, date_fin, role_proprio')
              .eq('uid_proprio', ownerUid)
              .eq('profile_id_proprio', activeProfileId)
              .eq('statut', 'actif');
        } else {
          // Migration pas encore jouée → tous les animaux de l'uid
          ownRows = await supa.from('animaux_proprietes')
              .select('animal_id, date_fin, role_proprio')
              .eq('uid_proprio', ownerUid)
              .eq('statut', 'actif');
        }
      } else {
        ownRows = await supa.from('animaux_proprietes')
            .select('animal_id, date_fin, role_proprio')
            .eq('uid_proprio', ownerUid)
            .eq('statut', 'actif');
      }

      final currentIds = <String>{};
      final formerIds  = <String>{};
      for (final r in ownRows) {
        final id = r['animal_id'] as String? ?? '';
        if (id.isEmpty) continue;
        if (r['date_fin'] == null) currentIds.add(id); else formerIds.add(id);
      }

      final allAnimalIds = {...currentIds, ...formerIds}.toList();
      if (allAnimalIds.isEmpty) {
        setState(() { _animauxData = []; _loading = false; });
        return;
      }

      final rows = await supa.from('animaux').select()
          .inFilter('id', allAnimalIds);
      final animaux = List<Map<String, dynamic>>.from(rows as List);

      _currentOwnerIds = currentIds;
      _formerOwnerIds  = formerIds;

      // IDs des femelles présentes — stérilisées exclues (plus de cycle à
      // suivre) : ce filtre manquait, une femelle stérilisée pouvait encore
      // afficher le badge « chaleurs ».
      final femIds = animaux
          .where((a) => a['sexe'] == 'femelle' &&
              a['sterilise'] != true &&
              !['sorti','decede'].contains(a['statut'] ?? ''))
          .map((a) => a['id'] as String)
          .toList();

      Map<String, bool> cFlags = {};
      Map<String, bool> gFlags = {};

      if (femIds.isNotEmpty) {
        // Protocoles chaleur par race (configurés par l'éleveur) — priment
        // sur le défaut par espèce, mais restent en dessous d'un override
        // par animal.
        final raceIntervals = await ChaleurIntervalService.loadRaceIntervals(ownerUid);

        // Dernières chaleurs
        final chaleurs = await supa.from('chaleurs')
            .select('animal_id, date')
            .inFilter('animal_id', femIds)
            .order('date', ascending: false);

        final Map<String, DateTime> lastChaleur = {};
        for (final c in chaleurs) {
          final aid = c['animal_id']?.toString() ?? '';
          final d = DateTime.tryParse(c['date'] ?? '');
          if (d != null && !lastChaleur.containsKey(aid)) lastChaleur[aid] = d;
        }

        // Dernière mise-bas par animal — cycle suspendu pendant l'allaitement
        // (ex. Ana ne doit pas être signalée « en chaleurs » juste après avoir mis bas).
        final Map<String, DateTime> lastMiseBas = {};
        try {
          final naissances = await supa.from('gestations')
              .select('animal_id, date_naissance')
              .inFilter('animal_id', femIds)
              .not('date_naissance', 'is', null)
              .order('date_naissance', ascending: false);
          for (final n in naissances) {
            final aid = n['animal_id']?.toString() ?? '';
            if (lastMiseBas.containsKey(aid)) continue;
            final d = DateTime.tryParse(n['date_naissance'] ?? '');
            if (d != null) lastMiseBas[aid] = d;
          }
        } catch (_) {}

        final now = DateTime.now();
        for (final a in animaux) {
          final id = a['id'] as String? ?? '';
          if (!femIds.contains(id)) continue;
          final espece = a['espece'] as String? ?? '';
          final race = a['race'] as String?;
          final customInterval = a['intervalle_chaleurs_jours'] as int?;
          final interval = ChaleurIntervalService.resolve(
            raceIntervals: raceIntervals, espece: espece, race: race, animalOverride: customInterval,
          );
          if (interval == 0) continue;

          // Retraite : au-delà de l'âge de reproduction, plus de cycle à suivre.
          final naissance = DateTime.tryParse(a['date_naissance'] as String? ?? '');
          final ageRetraite = _agesRetraite[espece.toLowerCase()];
          if (naissance != null && ageRetraite != null) {
            final dateRetraite = DateTime(naissance.year + ageRetraite, naissance.month, naissance.day);
            if (!now.isBefore(dateRetraite)) continue;
          }

          // Mise-bas récente : cycle suspendu pendant l'allaitement.
          final miseBas = lastMiseBas[id];
          if (miseBas != null && now.difference(miseBas).inDays < _joursLactation) continue;

          // Une mise-bas postérieure à la dernière chaleur enregistrée redémarre
          // le cycle : sans ça, une femelle qui vient de mettre bas retombe sur
          // sa dernière chaleur d'AVANT la gestation, largement dépassée.
          final last = lastChaleur[id];
          final effectiveLast = (miseBas != null && (last == null || miseBas.isAfter(last)))
              ? miseBas : last;
          if (effectiveLast == null) continue;
          final diff = effectiveLast.add(Duration(days: interval)).difference(now).inDays;
          if (diff <= 7) cFlags[id] = true;
        }

        // Gestantes confirmées sans date_naissance
        final gests = await supa.from('gestations')
            .select('animal_id')
            .inFilter('animal_id', femIds)
            .eq('gestation_confirmee', true)
            .isFilter('date_naissance', null);
        for (final g in gests) {
          final aid = g['animal_id']?.toString() ?? '';
          if (aid.isNotEmpty) gFlags[aid] = true;
        }
      }

      // Animaux passés par le registre mouvements (re-cédés — ne sont plus uid_eleveur ni uid_acquereur)
      final existingIds = animaux.map((a) => a['id'] as String? ?? '').toSet();
      try {
        final mvts = await supa.from('registre_mouvements')
            .select('animal_id').eq('uid_eleveur', ownerUid);
        final mvtIds = (mvts as List)
            .map((m) => m['animal_id'] as String? ?? '')
            .where((id) => id.isNotEmpty && !existingIds.contains(id))
            .toSet().toList();
        if (mvtIds.isNotEmpty) {
          final historical = await supa.from('animaux').select().inFilter('id', mvtIds);
          animaux.addAll(List<Map<String, dynamic>>.from(historical as List));
        }
      } catch (_) {}

      // Cédé puis repris par une asso / un élevage : la fiche porte désormais
      // le statut du nouveau détenteur (« present », « disponible »…) — pour
      // ce profil, l'animal est sorti (onglet Cédés, fiche en lecture seule).
      for (final a in animaux) {
        final id = a['id'] as String? ?? '';
        final st = a['statut'] as String? ?? '';
        if (id.isEmpty || currentIds.contains(id)) continue;
        if (st == 'decede' || st == 'cession_en_cours' || st == 'en_attente_cession') continue;
        if (a['uid_eleveur'] != ownerUid) a['statut'] = 'sorti';
      }

      // Détecter les animaux 'sorti' avec un contrat de cession non signé
      final sortisIds = animaux
          .where((a) => (a['statut'] as String? ?? '') == 'sorti')
          .map((a) => a['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      Set<String> pendingIds = {};
      if (sortisIds.isNotEmpty) {
        try {
          final pendingDocs = await supa.from('documents_animaux')
              .select('animal_id')
              .inFilter('animal_id', sortisIds)
              .inFilter('type', ['contrat_vente', 'certificat_cession'])
              .not('statut', 'in', '(signe,annule,refuse,archive,expire)');
          pendingIds = (pendingDocs as List)
              .map((d) => d['animal_id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
        } catch (_) {}
      }

      if (mounted) setState(() {
        _animauxData          = animaux;
        _cessionEnAttenteIds  = pendingIds;
        _chaleurFlags         = cFlags;
        _gestanteFlags        = gFlags;
        _loading              = false;
        // (currentOwnerIds et formerOwnerIds déjà mis à jour avant le setState)
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAnimal(String id) async {
    try {
      await Supabase.instance.client.from('animaux').delete().eq('id', id);
      if (mounted) _loadAnimaux();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
      }
    }
  }

  Future<void> _toggleReproducteur(String id, bool current) async {
    try {
      await Supabase.instance.client.from('animaux')
          .update({'reproducteur': !current}).eq('id', id);
      if (mounted) setState(() {
        final idx = _animauxData.indexWhere((a) => a['id']?.toString() == id);
        if (idx >= 0) _animauxData[idx] = {..._animauxData[idx], 'reproducteur': !current};
      });
    } catch (_) {}
  }

  Future<void> _toggleRetraite(String id, bool current) async {
    try {
      await Supabase.instance.client.from('animaux')
          .update({'is_retraite': !current}).eq('id', id);
      if (mounted) setState(() {
        final idx = _animauxData.indexWhere((a) => a['id']?.toString() == id);
        if (idx >= 0) _animauxData[idx] = {..._animauxData[idx], 'is_retraite': !current};
      });
    } catch (_) {}
  }

  /// Rend visible / masque ce reproducteur sur le profil public de l'éleveur.
  Future<void> _toggleReproPublic(String id, bool current) async {
    try {
      await Supabase.instance.client.from('animaux')
          .update({'reproducteur_public': !current}).eq('id', id);
      if (mounted) setState(() {
        final idx = _animauxData.indexWhere((a) => a['id']?.toString() == id);
        if (idx >= 0) _animauxData[idx] = {..._animauxData[idx], 'reproducteur_public': !current};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!current
              ? 'Reproducteur visible sur votre profil public'
              : 'Reproducteur masqué du profil public'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {}
  }

  void _openAnnonceFromPortee(List<Map<String, dynamic>> members) {
    if (members.isEmpty) return;
    final first = members.first;
    final espece = (first['espece'] as String?) ?? 'chien';
    final race   = (first['race']   as String?) ?? '';
    final dn     = first['date_naissance'] as String?;

    // Chercher le père et la mère dans les animaux existants
    Map<String, dynamic>? _findAnimal(String nom, String puce) {
      if (nom.isEmpty && puce.isEmpty) return null;
      try {
        return _animauxData.firstWhere((a) =>
          (nom.isNotEmpty  && (a['nom']            as String? ?? '') == nom)  ||
          (puce.isNotEmpty && (a['identification'] as String? ?? '') == puce));
      } catch (_) { return null; }
    }

    final nomPere  = (first['nom_pere']  as String?) ?? '';
    final pucePere = (first['puce_pere'] as String?) ?? '';
    final nomMere  = (first['nom_mere']  as String?) ?? '';
    final puceMere = (first['puce_mere'] as String?) ?? '';

    final pereData = _findAnimal(nomPere, pucePere);
    final mereData = _findAnimal(nomMere, puceMere);

    // Construire animaux_portee avec isLinked
    final animauxPortee = members.map((m) {
      final photo = (m['photo_url'] as String?) ?? '';
      return <String, dynamic>{
        'animalId':  m['id'],
        'nom':       (m['nom']     as String?) ?? '',
        'sexe':      (m['sexe']    as String?) ?? 'male',
        'couleur':   (m['couleur'] as String?) ?? '',
        'couleur_yeux': (m['couleur_yeux'] as String?) ?? '',
        'photos':    photo.isNotEmpty ? [photo] : <String>[],
        'statut':    'disponible',
        'isLinked':  true,
      };
    }).toList();

    final initialData = <String, dynamic>{
      'type':           'portee',
      'type_vente':     'vente',
      'espece':         espece,
      'race':           race,
      'date_naissance': dn,
      'nombre_bebes':   members.length,
      'animaux_portee': animauxPortee,
      // Père
      if (pereData != null) ...{
        'pere_animal_id':  pereData['id'],
        'pere_nom':        (pereData['nom']            as String?) ?? nomPere,
        'pere_puce':       (pereData['identification'] as String?) ?? pucePere,
        'pere_race':       (pereData['race']           as String?) ?? '',
        'pere_photo_url':  (pereData['photo_url']      as String?) ?? '',
        'pere_couleur':    (pereData['couleur']        as String?) ?? '',
        'pere_couleur_yeux': (pereData['couleur_yeux'] as String?) ?? '',
        'pere_registre':   (pereData['pedigree_lof']   as String?) ?? '',
      } else if (nomPere.isNotEmpty) ...{
        'pere_nom':  nomPere,
        'pere_puce': pucePere,
      },
      // Mère
      if (mereData != null) ...{
        'mere_animal_id':  mereData['id'],
        'mere_nom':        (mereData['nom']            as String?) ?? nomMere,
        'mere_puce':       (mereData['identification'] as String?) ?? puceMere,
        'mere_race':       (mereData['race']           as String?) ?? (first['race_mere'] as String? ?? ''),
        'mere_photo_url':  (mereData['photo_url']      as String?) ?? '',
        'mere_couleur':    (mereData['couleur']        as String?) ?? '',
        'mere_couleur_yeux': (mereData['couleur_yeux'] as String?) ?? '',
        'mere_registre':   (mereData['pedigree_lof']   as String?) ?? '',
      } else if (nomMere.isNotEmpty) ...{
        'mere_nom':  nomMere,
        'mere_puce': puceMere,
        'mere_race': (first['race_mere'] as String?) ?? '',
      },
    };

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CreateAnnoncePage(initialData: initialData),
    ));
  }

  Future<void> _regrouperEnPortee() async {
    if (_selectedIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionne au moins 2 animaux')),
      );
      return;
    }
    final n = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Regrouper en portée ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text(
          '$n animal${n > 1 ? 'aux' : ''} seront liés dans la même portée.',
          style: const TextStyle(fontFamily: 'Galey'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Regrouper',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final porteeId = 'portee_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await Supabase.instance.client.from('animaux')
          .update({'portee_id': porteeId})
          .inFilter('id', _selectedIds.toList());
      setState(() { _selectMode = false; _selectedIds.clear(); });
      _loadAnimaux();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du regroupement')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  int get _presentsFilterCount {
    int c = 0;
    if (_filterEspece != 'tous') c++;
    if (_filterSexe != 'tous')   c++;
    if (_filterRace.isNotEmpty)  c++;
    if (_filterRetraite) c++;
    if (_filterGestante) c++;
    if (_filterChaleur)  c++;
    if (_filterReservation != 'tous') c++;
    return c;
  }

  int get _anciensFilterCount {
    int c = 0;
    if (_anciensEspece != 'tous') c++;
    if (_anciensDtDebut != null || _anciensDtFin != null) c++;
    return c;
  }

  int get _decedesFilterCount {
    int c = 0;
    if (_decedesEspece != 'tous') c++;
    if (_decedesDtDebut != null || _decedesDtFin != null) c++;
    return c;
  }

  // ── Filter Présents sheet ────────────────────────────────────────────────────

  Future<void> _openPresentsFilterSheet() async {
    Map<String, List<String>> racesByEspece = {};
    Set<String> availableSpeciesSet = {};

    for (final d in _animauxData) {
      final statut = d['statut'] as String? ?? '';
      final hasPending = _cessionEnAttenteIds.contains(d['id'] as String? ?? '');
      if (!hasPending && (statut == 'sorti' || statut == 'decede')) continue;
      final esp  = (d['espece'] ?? '') as String;
      final race = (d['race']   ?? '') as String;
      if (esp.isNotEmpty) {
        availableSpeciesSet.add(esp);
        if (race.isNotEmpty) {
          racesByEspece.putIfAbsent(esp, () => []);
          if (!racesByEspece[esp]!.contains(race)) racesByEspece[esp]!.add(race);
        }
      }
    }
    for (final k in racesByEspece.keys) racesByEspece[k]!.sort();
    if (!mounted) return;

    String tmpEspece  = _filterEspece;
    String tmpSexe    = _filterSexe;
    String tmpRace    = _filterRace;
    bool tmpRetraite  = _filterRetraite;
    bool tmpRepro     = _filterRepro;
    bool tmpGestante  = _filterGestante;
    bool tmpChaleur   = _filterChaleur;
    String tmpReservation = _filterReservation;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply({String? espece, String? sexe, String? race,
                     bool toggleRetraite = false, bool toggleRepro = false,
                     bool toggleGestante = false, bool toggleChaleur = false,
                     String? reservation}) {
            setSheet(() {
              if (espece != null) {
                tmpEspece = espece;
                final newRaces = racesByEspece[espece] ?? [];
                if (!newRaces.contains(tmpRace)) tmpRace = '';
              }
              if (sexe != null) tmpSexe = sexe;
              if (race != null) tmpRace = (tmpRace == race) ? '' : race;
              if (toggleRetraite) tmpRetraite = !tmpRetraite;
              if (toggleRepro)    tmpRepro    = !tmpRepro;
              if (toggleGestante) tmpGestante = !tmpGestante;
              if (toggleChaleur)  tmpChaleur  = !tmpChaleur;
              if (reservation != null) tmpReservation = reservation;
            });
            setState(() {
              _filterEspece   = tmpEspece;
              _filterSexe     = tmpSexe;
              _filterRace     = tmpRace;
              _filterRetraite = tmpRetraite;
              _filterRepro    = tmpRepro;
              _filterGestante = tmpGestante;
              _filterChaleur  = tmpChaleur;
              _filterReservation = tmpReservation;
            });
          }

          final races = tmpEspece != 'tous' ? (racesByEspece[tmpEspece] ?? <String>[]) : <String>[];

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Filtrer mes animaux',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 17, color: Color(0xFF1F2A2E))),
                const Spacer(),
                if (tmpEspece != 'tous' || tmpSexe != 'tous' || tmpRace.isNotEmpty ||
                    tmpRetraite || tmpGestante || tmpChaleur || tmpReservation != 'tous')
                  TextButton(
                    onPressed: () {
                      setSheet(() { tmpEspece = 'tous'; tmpSexe = 'tous'; tmpRace = '';
                        tmpRetraite = false; tmpRepro = false; tmpGestante = false; tmpChaleur = false;
                        tmpReservation = 'tous'; });
                      setState(() { _filterEspece = 'tous'; _filterSexe = 'tous'; _filterRace = '';
                        _filterRetraite = false; _filterRepro = false; _filterGestante = false; _filterChaleur = false;
                        _filterReservation = 'tous'; });
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Réinitialiser',
                        style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                  children: kSpeciesData
                      .where((sp) => sp.value == 'tous' || availableSpeciesSet.contains(sp.value))
                      .map((sp) {
                final active = tmpEspece == sp.value;
                return GestureDetector(
                  onTap: () => apply(espece: sp.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? sp.color : Colors.transparent,
                      border: Border.all(color: active ? sp.color : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (sp.value != 'tous') ...[
                        speciesIcon(sp.value, 13, active ? Colors.white : sp.color),
                        const SizedBox(width: 5),
                      ],
                      Text(sp.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: active ? Colors.white : Colors.black87,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ]),
                  ),
                );
              }).toList()),
              const SizedBox(height: 18),
              const Text('Sexe', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Row(children: [
                _SexeChip(label: 'Tous',       active: tmpSexe == 'tous',    onTap: () => apply(sexe: 'tous')),
                const SizedBox(width: 8),
                _SexeChip(label: 'Mâles',    active: tmpSexe == 'male',    onTap: () => apply(sexe: 'male')),
                const SizedBox(width: 8),
                _SexeChip(label: 'Femelles',  active: tmpSexe == 'femelle', onTap: () => apply(sexe: 'femelle')),
              ]),
              const SizedBox(height: 18),
              const Text('Réservation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Row(children: [
                _SexeChip(label: 'Toutes', active: tmpReservation == 'tous', onTap: () => apply(reservation: 'tous')),
                const SizedBox(width: 8),
                _SexeChip(label: 'Disponibles', active: tmpReservation == 'disponible', onTap: () => apply(reservation: 'disponible')),
                const SizedBox(width: 8),
                _SexeChip(label: 'Réservés', active: tmpReservation == 'reserve', onTap: () => apply(reservation: 'reserve')),
              ]),
              if (races.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Race', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                    fontSize: 13, color: Color(0xFF6F767B))),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: races.map((r) {
                  final active = tmpRace == r;
                  return GestureDetector(
                    onTap: () => apply(race: r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? _teal : Colors.transparent,
                        border: Border.all(color: active ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(r, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: active ? Colors.white : Colors.black87,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ),
                  );
                }).toList()),
              ],
              const SizedBox(height: 18),
              const Text('Statut spécial', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final item in [
                  ('Retraités',   tmpRetraite, const Color(0xFFB45309), () => apply(toggleRetraite: true)),
                  ('Gestantes',   tmpGestante, _green,                  () => apply(toggleGestante: true)),
                  ('En chaleur',  tmpChaleur,  const Color(0xFFDB2777), () => apply(toggleChaleur: true)),
                ] as List<(String, bool, Color, VoidCallback)>)
                  GestureDetector(
                    onTap: item.$4,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: item.$2 ? item.$3 : Colors.transparent,
                        border: Border.all(color: item.$2 ? item.$3 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(item.$1, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: item.$2 ? Colors.white : Colors.black87,
                          fontWeight: item.$2 ? FontWeight.w600 : FontWeight.normal)),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  // ── Filter Anciens sheet ─────────────────────────────────────────────────────

  Future<void> _openAnciensFilterSheet() async {
    Set<String> availableSpeciesSet = {};

    for (final d in _animauxData) {
      final statut = d['statut'] as String? ?? '';
      if (statut != 'sorti') continue;
      final esp = (d['espece'] ?? '') as String;
      if (esp.isNotEmpty) availableSpeciesSet.add(esp);
    }
    if (!mounted) return;

    String    tmpEspece = _anciensEspece;
    DateTime? tmpDebut  = _anciensDtDebut;
    DateTime? tmpFin    = _anciensDtFin;
    final fmt = DateFormat('dd/MM/yyyy');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply() {
            setState(() {
              _anciensEspece  = tmpEspece;
              _anciensDtDebut = tmpDebut;
              _anciensDtFin   = tmpFin;
            });
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Filtrer les cédés',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 17, color: Color(0xFF1F2A2E))),
                const Spacer(),
                if (tmpEspece != 'tous' || tmpDebut != null || tmpFin != null)
                  TextButton(
                    onPressed: () {
                      setSheet(() { tmpEspece = 'tous'; tmpDebut = null; tmpFin = null; });
                      setState(() { _anciensEspece = 'tous'; _anciensDtDebut = null; _anciensDtFin = null; });
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Réinitialiser',
                        style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
                  ),
              ]),
              const SizedBox(height: 16),

              // Espèce
              const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                  children: kSpeciesData
                      .where((sp) => sp.value == 'tous' || availableSpeciesSet.contains(sp.value))
                      .map((sp) {
                final active = tmpEspece == sp.value;
                return GestureDetector(
                  onTap: () { setSheet(() => tmpEspece = sp.value); apply(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? sp.color : Colors.transparent,
                      border: Border.all(color: active ? sp.color : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (sp.value != 'tous') ...[
                        speciesIcon(sp.value, 13, active ? Colors.white : sp.color),
                        const SizedBox(width: 5),
                      ],
                      Text(sp.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: active ? Colors.white : Colors.black87,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ]),
                  ),
                );
              }).toList()),
              const SizedBox(height: 18),

              // Période de sortie
              const Text('Période de sortie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: tmpDebut ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) { setSheet(() => tmpDebut = picked); apply(); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: tmpDebut != null ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 14,
                            color: tmpDebut != null ? _teal : Colors.grey),
                        const SizedBox(width: 6),
                        Text(tmpDebut != null ? fmt.format(tmpDebut!) : 'Du...',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: tmpDebut != null ? _teal : Colors.grey)),
                        if (tmpDebut != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () { setSheet(() => tmpDebut = null); apply(); },
                            child: const Icon(Icons.close, size: 14, color: Colors.grey),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: tmpFin ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) { setSheet(() => tmpFin = picked); apply(); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: tmpFin != null ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 14,
                            color: tmpFin != null ? _teal : Colors.grey),
                        const SizedBox(width: 6),
                        Text(tmpFin != null ? fmt.format(tmpFin!) : 'Au...',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: tmpFin != null ? _teal : Colors.grey)),
                        if (tmpFin != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () { setSheet(() => tmpFin = null); apply(); },
                            child: const Icon(Icons.close, size: 14, color: Colors.grey),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    switch (_tabController.index) {
      case 0:
        await _openPresentsFilterSheet();
        break;
      case 3:
        await _openDecedesFilterSheet();
        break;
      default:
        await _openAnciensFilterSheet();
    }
  }

  // ── Compteurs des onglets ─────────────────────────────────────────────────────

  int get _nbPresents => _animauxData.where((d) {
    final statut = d['statut'] as String? ?? '';
    return _currentOwnerIds.contains(d['id']) && statut != 'decede' && statut != 'sorti';
  }).length;
  int get _nbCedes => _animauxData.where((d) => d['statut'] == 'sorti').length;
  int get _nbDecedes => _animauxData.where((d) => d['statut'] == 'decede').length;

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPresents = _tabController.index == 0;
    final nbPresents = _nbPresents;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        titleSpacing: 16,
        title: _selectMode
            ? Text('${_selectedIds.length} sélectionné${_selectedIds.length != 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Mes animaux', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
                if (!_loading)
                  Text('$nbPresents présent${nbPresents > 1 ? 's' : ''} · ${_animauxData.length} au total',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70)),
              ]),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: _selectMode ? [
          IconButton(
            icon: Icon(Icons.group_work_outlined,
                color: _selectedIds.isNotEmpty ? Colors.white : Colors.white38),
            onPressed: _selectedIds.isNotEmpty ? _regrouperEnPortee : null,
            tooltip: 'Regrouper en portée',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() { _selectMode = false; _selectedIds.clear(); }),
            tooltip: 'Annuler',
          ),
        ] : [
          if (isPresents)
            IconButton(
              icon: const Icon(Icons.checklist_outlined),
              onPressed: () => setState(() { _selectMode = true; _selectedIds.clear(); }),
              tooltip: 'Sélectionner',
            ),
          if (_uid != null)
            IconButton(
              icon: const Icon(Icons.sensors_rounded),
              onPressed: () => ChipScannerService.scanFromElevage(context, _ownerUid ?? _uid),
              tooltip: 'Scanner une puce',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => _showAddSheet(context),
              style: TextButton.styleFrom(foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('+ Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(text: _loading ? 'Présents' : 'Présents · $nbPresents'),
              Tab(text: _loading ? 'Cédés' : 'Cédés · $_nbCedes'),
              const Tab(text: 'Suivi'),
              Tab(text: _loading ? 'Décédés' : 'Décédés · $_nbDecedes'),
            ],
            indicatorColor: _teal,
            indicatorWeight: 2,
            labelColor: _teal,
            unselectedLabelColor: const Color(0xFF6F767B),
            dividerColor: Colors.grey.shade300,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        Expanded(child: TabBarView(
          controller: _tabController,
          children: [
            _buildPresentsTab(),
            _buildAnciensTab(),
            SuiviCessionsTab(
              uid: _ownerUid ?? _uid,
              myUid: _uid,
              animaux: _animauxData,
              loading: _loading,
              onChanged: _loadAnimaux,
            ),
            _buildDecedesTab(),
          ],
        )),
      ]),
    );
  }

  // ── Barre : recherche, catégorie, portée, filtres ──────────────────────────

  InputDecoration _decoChamp(String hint, {Widget? prefix, Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Colors.grey.shade500),
    prefixIcon: prefix,
    suffixIcon: suffix,
    isDense: true,
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _teal, width: 1.5)),
  );

  Widget _buildSearchField() => TextField(
    controller: _searchController,
    onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
    decoration: _decoChamp('Rechercher par nom ou numéro de puce',
      prefix: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
      suffix: _search.isNotEmpty
          ? IconButton(
              icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
              onPressed: () { _searchController.clear(); setState(() => _search = ''); })
          : null),
  );

  Widget _boutonFiltres(int count) => OutlinedButton(
    onPressed: _openFilterSheet,
    style: OutlinedButton.styleFrom(
      foregroundColor: count > 0 ? _teal : const Color(0xFF1F2A2E),
      backgroundColor: count > 0 ? _teal.withValues(alpha: 0.06) : Colors.white,
      side: BorderSide(color: count > 0 ? _teal : Colors.grey.shade300),
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(count > 0 ? 'Filtres · $count' : 'Filtres',
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600)),
  );

  Widget _dropdown<T>({required T value, required List<(T, String)> items, required ValueChanged<T> onChanged, required String label}) =>
    DropdownButtonFormField<T>(
      initialValue: value,
      key: ValueKey('$label-$value'),
      isExpanded: true,
      decoration: _decoChamp(label),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFF1F2A2E)),
      items: [for (final it in items) DropdownMenuItem(value: it.$1, child: Text(it.$2, overflow: TextOverflow.ellipsis))],
      onChanged: (v) { if (v != null) onChanged(v); },
    );

  Widget _barre({required int filtres, List<Widget> menus = const []}) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(children: [
      _buildSearchField(),
      const SizedBox(height: 8),
      Row(children: [
        for (final m in menus) ...[Expanded(child: m), const SizedBox(width: 8)],
        if (menus.isEmpty) const Spacer(),
        _boutonFiltres(filtres),
      ]),
    ]),
  );

  // ── Présents tab ──────────────────────────────────────────────────────────────

  bool get _rechercheOuFiltre => _search.isNotEmpty || _presentsFilterCount > 0;

  bool _filtresCommuns(Map<String, dynamic> d) {
    if (_filterEspece != 'tous' && d['espece'] != _filterEspece) return false;
    if (_filterSexe != 'tous' && d['sexe'] != _filterSexe) return false;
    if (_filterRace.isNotEmpty &&
        (d['race'] ?? '').toString().toLowerCase() != _filterRace.toLowerCase()) return false;
    final statut = d['statut'] as String? ?? '';
    // Réservation (statut commercial) ≠ présence : un réservé reste présent
    if (_filterReservation == 'reserve' && statut != 'reserve') return false;
    if (_filterReservation == 'disponible' && statut == 'reserve') return false;
    final aid = d['id'] as String? ?? '';
    if (_filterGestante && !(_gestanteFlags[aid] ?? false)) return false;
    if (_filterChaleur  && !(_chaleurFlags[aid]  ?? false)) return false;
    if (_search.isNotEmpty) {
      final nom  = (d['nom']            ?? '').toString().toLowerCase();
      final puce = (d['identification'] ?? '').toString().toLowerCase();
      if (!nom.contains(_search) && !puce.contains(_search)) return false;
    }
    return true;
  }

  /// Animaux présents (onglet) selon la catégorie et les filtres.
  List<Map<String, dynamic>> _presentsDocs() {
    if (_presentsSubTab == 'bebes') {
      // Bébés présents seulement : les cédés sont dans Cédés › Bébés.
      return _animauxData.where((d) {
        final pid = d['portee_id'] as String? ?? '';
        final statut = d['statut'] as String? ?? '';
        if (pid.isEmpty || d['reproducteur'] == true) return false;
        if (statut == 'decede' || statut == 'sorti') return false;
        return _filtresCommuns(d);
      }).toList();
    }
    final base = _animauxData.where((d) {
      final statut = d['statut'] as String? ?? '';
      final aid = d['id'] as String? ?? '';
      // animaux_proprietes = source unique (date_fin IS NULL = présent) ; on
      // exclut aussi sorti/décédé d'après le statut de l'animal lui-même.
      if (!_currentOwnerIds.contains(aid)) return false;
      if (statut == 'decede' || statut == 'sorti') return false;
      if (_filterRetraite && d['is_retraite'] != true) return false;
      return _filtresCommuns(d);
    }).toList()
      ..sort((a, b) => (a['nom'] ?? '').toString().compareTo((b['nom'] ?? '').toString()));
    // Reproducteurs : marquage existant uniquement (jamais déduit du sexe ou de l'âge)
    return _presentsSubTab == 'repro' ? base.where((d) => d['reproducteur'] == true).toList() : base;
  }

  /// Portées (bébés) triées par date de naissance décroissante.
  Map<String, List<Map<String, dynamic>>> _groupesPortees(List<Map<String, dynamic>> docs, {bool cedes = false}) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final d in docs) {
      final pid = (d['portee_id'] as String?) ?? '';
      if (pid.isNotEmpty) groups.putIfAbsent(pid, () => []).add(d);
    }
    // Sans recherche ni filtre : on ajoute les frères et sœurs gardés comme reproducteurs
    if (!_rechercheOuFiltre) {
      for (final pid in groups.keys.toList()) {
        final ids = groups[pid]!.map((a) => a['id']).toSet();
        groups[pid]!.addAll(_animauxData.where((a) {
          final statut = (a['statut'] as String?) ?? '';
          return a['portee_id'] == pid && !ids.contains(a['id']) && statut != 'decede'
              && cedes == (statut == 'sorti');
        }));
      }
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(groups[a]!.first['date_naissance'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(groups[b]!.first['date_naissance'] as String? ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });
    return {for (final k in keys) k: groups[k]!};
  }

  String _titrePortee(Map<String, dynamic> first) {
    final nomMere = ((first['nom_mere'] as String?) ?? '').trim();
    return nomMere.isNotEmpty ? 'Portée de $nomMere' : 'Portée';
  }

  Widget _buildPresentsTab() {
    final docs = _presentsDocs();
    final groupes = _presentsSubTab == 'bebes' ? _groupesPortees(docs) : const <String, List<Map<String, dynamic>>>{};
    final fmt = DateFormat('dd/MM/yyyy');
    return Column(children: [
      _barre(filtres: _presentsFilterCount, menus: [
        _dropdown<String>(
          label: 'Catégorie', value: _presentsSubTab,
          items: const [('tous', 'Tous les animaux'), ('repro', 'Reproducteurs'), ('bebes', 'Bébés')],
          onChanged: (v) => setState(() { _presentsSubTab = v; _selectedPorteeId = ''; }),
        ),
        if (_presentsSubTab == 'bebes' && groupes.isNotEmpty)
          _dropdown<String>(
            label: 'Portée',
            value: groupes.containsKey(_selectedPorteeId) ? _selectedPorteeId : '',
            items: [
              ('', 'Toutes les portées'),
              for (final e in groupes.entries)
                (e.key, () {
                  final dn = DateTime.tryParse(e.value.first['date_naissance'] as String? ?? '');
                  return '${_titrePortee(e.value.first)}${dn != null ? ' — ${fmt.format(dn)}' : ''}';
                }()),
            ],
            onChanged: (v) => setState(() => _selectedPorteeId = v),
          ),
      ]),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      Expanded(child: _buildPresentsList(docs, groupes)),
    ]);
  }

  Widget _etatVide(String titre, String detail, {VoidCallback? onReset, String? resetLabel}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(titre, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(detail, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
        ],
        if (onReset != null)
          TextButton(onPressed: onReset,
              child: Text(resetLabel ?? 'Réinitialiser', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal))),
      ]),
    ),
  );

  void _resetPresents() => setState(() {
    _searchController.clear(); _search = '';
    _filterEspece = 'tous'; _filterSexe = 'tous'; _filterRace = ''; _filterReservation = 'tous';
    _filterRetraite = false; _filterRepro = false; _filterGestante = false; _filterChaleur = false;
  });

  /// Carte d'un animal présent (actions selon les droits).
  Widget _carte(Map<String, dynamic> data, {required bool vertical, bool isBebe = false}) {
    final id = data['id'] as String? ?? '';
    final cede = (data['statut'] as String? ?? '') == 'sorti';
    return _AnimalCard(
      id: id,
      data: data,
      vertical: vertical,
      isBebe: isBebe,
      reproducteur: data['reproducteur'] == true,
      isRetraite: data['is_retraite'] == true,
      chaleurFlag:  _chaleurFlags[id]  ?? false,
      gestanteFlag: _gestanteFlags[id] ?? false,
      selectMode: _selectMode,
      selected: _selectedIds.contains(id),
      peutAjouterPhoto: !cede && id.isNotEmpty,
      onTap: _selectMode
          ? () => setState(() {
              if (_selectedIds.contains(id)) { _selectedIds.remove(id); } else { _selectedIds.add(id); }
            })
          : () => _openFiche(context, id, data: data),
      onDelete: cede || id.isEmpty ? null : () => _deleteAnimal(id),
      onToggleReproducteur: cede || id.isEmpty ? null : () => _toggleReproducteur(id, data['reproducteur'] == true),
      onToggleRetraite: cede || id.isEmpty ? null : () => _toggleRetraite(id, data['is_retraite'] == true),
      reproPublic: data['reproducteur_public'] == true,
      onToggleReproPublic: cede || id.isEmpty ? null : () => _toggleReproPublic(id, data['reproducteur_public'] == true),
    );
  }

  /// Liste (mobile) ou grille (tablette) de cartes homogènes.
  Widget _cartes(List<Widget> Function(bool vertical) build, {bool scrollable = true, EdgeInsets padding = const EdgeInsets.all(16)}) =>
    LayoutBuilder(builder: (context, c) {
      final colonnes = c.maxWidth >= 1000 ? 4 : c.maxWidth >= 700 ? 3 : 1;
      final items = build(colonnes > 1);
      if (colonnes == 1) {
        return ListView.separated(
          shrinkWrap: !scrollable,
          physics: scrollable ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
          padding: padding,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => items[i],
        );
      }
      return GridView.count(
        shrinkWrap: !scrollable,
        physics: scrollable ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
        padding: padding,
        crossAxisCount: colonnes,
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: 0.68,
        children: items,
      );
    });

  Widget _buildPresentsList(List<Map<String, dynamic>> docs, Map<String, List<Map<String, dynamic>>> groupes) {
    if (_uid == null) return const Center(child: Text('Non connecté'));
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));

    final bebes = _presentsSubTab == 'bebes';
    final visibles = bebes
        ? (groupes.containsKey(_selectedPorteeId) ? [_selectedPorteeId] : groupes.keys.toList())
        : const <String>[];
    if ((bebes && visibles.isEmpty) || (!bebes && docs.isEmpty)) {
      if (_rechercheOuFiltre) {
        return _etatVide('Aucun animal ne correspond', 'Modifiez la recherche ou les filtres.', onReset: _resetPresents);
      }
      return _presentsSubTab == 'repro'
          ? _etatVide('Aucun reproducteur', 'Ouvrez le menu d’un animal pour le marquer comme reproducteur.')
          : bebes
              ? _etatVide('Aucun bébé présent', 'Les portées déjà parties se retrouvent dans Cédés › Bébés.')
              : _etatVide('Aucun animal présent', 'Ajoutez votre premier animal.',
                  onReset: () => _showAddSheet(context), resetLabel: 'Ajouter un animal');
    }

    if (bebes) {
      return _buildPorteeGroupedView(groupes, visibles,
          selection: _selectedPorteeId, onSelect: (v) => setState(() => _selectedPorteeId = v));
    }

    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _teal,
      child: _cartes((vertical) => [for (final d in docs) _carte(d, vertical: vertical)]),
    );
  }

  /// Toute la portée (présents, cédés, décédés) : la courbe de poids garde
  /// l'historique complet, cédés et décédés grisés (PorteePoidsPage).
  List<Map<String, dynamic>> _porteeComplete(String pid) =>
      _animauxData.where((a) => a['portee_id'] == pid).toList()
        ..sort((a, b) => (a['nom'] ?? '').toString().compareTo((b['nom'] ?? '').toString()));

  Widget _buildPorteeGroupedView(Map<String, List<Map<String, dynamic>>> groups, List<String> visibleKeys,
      {bool cedes = false, required String selection, required ValueChanged<String> onSelect}) {
    final fmt = DateFormat('dd/MM/yyyy');
    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _teal,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: visibleKeys.length + (selection.isNotEmpty ? 1 : 0),
        itemBuilder: (_, gi) {
          if (gi == visibleKeys.length) {
            return Align(alignment: Alignment.centerLeft, child: TextButton(
              onPressed: () => onSelect(''),
              child: const Text('Afficher toutes les portées', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal))));
          }
          final pid     = visibleKeys[gi];
          final members = groups[pid]!;
          final first   = members.first;
          final dn      = DateTime.tryParse(first['date_naissance'] as String? ?? '');
          final race    = (first['race'] as String?) ?? '';
          final espece  = (first['espece'] as String?) ?? '';
          final meta = [
            race.isNotEmpty ? race : speciesLabel(espece),
            '${members.length} ${members.length > 1 ? 'chiots' : 'chiot'}',
            if (dn != null) 'Nés le ${fmt.format(dn)}',
          ].join(' · ');
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_titrePortee(first), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 15, color: Color(0xFF1F2A2E))),
                    const SizedBox(height: 2),
                    Text(meta, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ])),
                  if (selection != pid)
                    OutlinedButton(
                      onPressed: () => onSelect(pid),
                      style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal),
                          minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Voir la portée', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Autres actions de la portée',
                    icon: const Icon(Icons.more_horiz, color: Color(0xFF4B5A60)),
                    onSelected: (v) async {
                      switch (v) {
                        case 'modifier':
                          final ok = await PorteeEditSheet.show(context, members);
                          if (ok && mounted) _loadAnimaux();
                        case 'poids':
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PorteePoidsPage(animals: _porteeComplete(pid), dateNaissance: dn)));
                        case 'soin':
                          final ok = await PorteeSoinSheet.show(context, members);
                          if (ok && mounted) _loadAnimaux();
                        case 'annonce':
                          _openAnnonceFromPortee(members);
                      }
                    },
                    itemBuilder: (_) => [
                      if (!cedes) const PopupMenuItem(value: 'modifier', child: Text('Modifier les informations de la portée', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
                      const PopupMenuItem(value: 'poids', child: Text('Courbes de poids', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
                      if (!cedes) const PopupMenuItem(value: 'soin', child: Text('Soin pour toute la portée', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
                      if (!cedes) const PopupMenuItem(value: 'annonce', child: Text('Créer une annonce', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
                    ],
                  ),
                ]),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              _cartes((vertical) => [for (final d in members) _carte(d, vertical: vertical, isBebe: d['reproducteur'] != true)],
                  scrollable: false, padding: const EdgeInsets.all(10)),
            ]),
          );
        },
      ),
    );
  }

  // ── Anciens tab ───────────────────────────────────────────────────────────────

  Widget _buildAnciensTab() {
    final bebes = _cedesVue == 'bebes';
    final groupes = bebes ? _groupesPortees(_bebesCedesDocs(), cedes: true) : const <String, List<Map<String, dynamic>>>{};
    final fmt = DateFormat('dd/MM/yyyy');
    return Column(children: [
      _barre(filtres: _anciensFilterCount, menus: [
        _dropdown<String>(
          label: 'Catégorie', value: _cedesVue,
          items: const [('tous', 'Tous les animaux'), ('bebes', 'Bébés (par portée)')],
          onChanged: (v) => setState(() { _cedesVue = v; _selectedPorteeCedeeId = ''; }),
        ),
        if (bebes && groupes.isNotEmpty)
          _dropdown<String>(
            label: 'Portée',
            value: groupes.containsKey(_selectedPorteeCedeeId) ? _selectedPorteeCedeeId : '',
            items: [
              ('', 'Toutes les portées'),
              for (final e in groupes.entries)
                (e.key, () {
                  final dn = DateTime.tryParse(e.value.first['date_naissance'] as String? ?? '');
                  return '${_titrePortee(e.value.first)}${dn != null ? ' — ${fmt.format(dn)}' : ''}';
                }()),
            ],
            onChanged: (v) => setState(() => _selectedPorteeCedeeId = v),
          ),
      ]),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      Expanded(child: !bebes
          ? _buildAnciensList()
          : _loading
              ? const Center(child: CircularProgressIndicator(color: _green))
              : groupes.isEmpty
                  ? _etatVide('Aucun bébé cédé', _anciensFilterCount > 0 || _search.isNotEmpty ? 'Modifiez la recherche ou les filtres.' : '')
                  : _buildPorteeGroupedView(groupes,
                      groupes.containsKey(_selectedPorteeCedeeId) ? [_selectedPorteeCedeeId] : groupes.keys.toList(),
                      cedes: true, selection: _selectedPorteeCedeeId,
                      onSelect: (v) => setState(() => _selectedPorteeCedeeId = v))),
    ]);
  }

  /// Bébés cédés (statut « sorti ») d'une portée, filtres de l'onglet Cédés.
  List<Map<String, dynamic>> _bebesCedesDocs() => _animauxData.where((d) {
        if ((d['portee_id'] as String? ?? '').isEmpty || d['reproducteur'] == true) return false;
        if ((d['statut'] as String? ?? '') != 'sorti') return false;
        if (_anciensEspece != 'tous' && d['espece'] != _anciensEspece) return false;
        if (_search.isNotEmpty) {
          final nom  = (d['nom']            ?? '').toString().toLowerCase();
          final puce = (d['identification'] ?? '').toString().toLowerCase();
          if (!nom.contains(_search) && !puce.contains(_search)) return false;
        }
        return true;
      }).toList();

  Widget _buildAnciensList() {
    if (_uid == null) return const Center(child: Text('Non connecté'));
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));

    var docs = _animauxData.where((data) {
      final statut = data['statut'] as String? ?? '';
      // Cédés = animaux dont le statut est « sorti » (cédés à un nouveau
      // propriétaire) uniquement ; le statut de l'animal fait foi, pas la
      // ligne animaux_proprietes (une cession déclarée manuellement dans le
      // registre ne clôture pas toujours cette ligne). Les décédés ont leur
      // propre onglet (cf. _buildDecedesList).
      if (statut != 'sorti') return false;
      if (_anciensEspece != 'tous' && data['espece'] != _anciensEspece) return false;
      if (_anciensDtDebut != null || _anciensDtFin != null) {
        final ds = data['date_sortie'] as String?;
        if (ds == null || ds.isEmpty) return false;
        final dt = DateTime.tryParse(ds);
        if (dt == null) return false;
        if (_anciensDtDebut != null && dt.isBefore(_anciensDtDebut!)) return false;
        if (_anciensDtFin != null &&
            dt.isAfter(_anciensDtFin!.add(const Duration(days: 1)))) return false;
      }
      if (_search.isNotEmpty) {
        final nom  = (data['nom']            ?? '').toString().toLowerCase();
        final puce = (data['identification'] ?? '').toString().toLowerCase();
        if (!nom.contains(_search) && !puce.contains(_search)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date_sortie'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['date_sortie'] as String? ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });

    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            _anciensFilterCount > 0
                ? 'Aucun animal cédé\ncorrespondant aux filtres'
                : 'Aucun animal cédé',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey', fontSize: 15),
          ),
          if (_anciensFilterCount > 0) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() {
                _anciensEspece = 'tous';
                _anciensDtDebut = null; _anciensDtFin = null;
              }),
              child: const Text('Réinitialiser les filtres',
                  style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
            ),
          ],
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _green,
      child: _cartes((vertical) => [
        for (final data in docs)
          _AnimalCard(
            id: data['id'] as String? ?? '',
            data: data,
            vertical: vertical,
            onTap: () => _openFiche(context, data['id'] as String?, data: data),
            onDelete: (data['id'] as String? ?? '').isEmpty ? null : () => _deleteAnimal(data['id'] as String),
          ),
      ]),
    );
  }

  // ── Décédés tab ───────────────────────────────────────────────────────────────

  Widget _buildDecedesTab() {
    return Column(children: [
      _barre(filtres: _decedesFilterCount),
      Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      Expanded(child: _buildDecedesList()),
    ]);
  }

  Widget _buildDecedesList() {
    if (_uid == null) return const Center(child: Text('Non connecté'));
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));

    var docs = _animauxData.where((data) {
      final statut = data['statut'] as String? ?? '';
      if (statut != 'decede') return false;
      if (_decedesEspece != 'tous' && data['espece'] != _decedesEspece) return false;
      if (_decedesDtDebut != null || _decedesDtFin != null) {
        final ds = data['date_sortie'] as String?;
        if (ds == null || ds.isEmpty) return false;
        final dt = DateTime.tryParse(ds);
        if (dt == null) return false;
        if (_decedesDtDebut != null && dt.isBefore(_decedesDtDebut!)) return false;
        if (_decedesDtFin != null &&
            dt.isAfter(_decedesDtFin!.add(const Duration(days: 1)))) return false;
      }
      if (_search.isNotEmpty) {
        final nom  = (data['nom']            ?? '').toString().toLowerCase();
        final puce = (data['identification'] ?? '').toString().toLowerCase();
        if (!nom.contains(_search) && !puce.contains(_search)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date_sortie'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['date_sortie'] as String? ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });

    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            _decedesFilterCount > 0
                ? 'Aucun animal décédé\ncorrespondant aux filtres'
                : 'Aucun animal décédé',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey', fontSize: 15),
          ),
          if (_decedesFilterCount > 0) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() {
                _decedesEspece = 'tous';
                _decedesDtDebut = null; _decedesDtFin = null;
              }),
              child: const Text('Réinitialiser les filtres',
                  style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
            ),
          ],
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _green,
      child: _cartes((vertical) => [
        for (final data in docs)
          _AnimalCard(
            id: data['id'] as String? ?? '',
            data: data,
            vertical: vertical,
            onTap: () => _openFiche(context, data['id'] as String?, data: data),
            onDelete: (data['id'] as String? ?? '').isEmpty ? null : () => _deleteAnimal(data['id'] as String),
          ),
      ]),
    );
  }

  Future<void> _openDecedesFilterSheet() async {
    Set<String> availableSpeciesSet = {};

    for (final d in _animauxData) {
      final statut = d['statut'] as String? ?? '';
      if (statut != 'decede') continue;
      final esp = (d['espece'] ?? '') as String;
      if (esp.isNotEmpty) availableSpeciesSet.add(esp);
    }
    if (!mounted) return;

    String    tmpEspece = _decedesEspece;
    DateTime? tmpDebut  = _decedesDtDebut;
    DateTime? tmpFin    = _decedesDtFin;
    final fmt = DateFormat('dd/MM/yyyy');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply() {
            setState(() {
              _decedesEspece  = tmpEspece;
              _decedesDtDebut = tmpDebut;
              _decedesDtFin   = tmpFin;
            });
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Filtrer les décédés',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 17, color: Color(0xFF1F2A2E))),
                const Spacer(),
                if (tmpEspece != 'tous' || tmpDebut != null || tmpFin != null)
                  TextButton(
                    onPressed: () {
                      setSheet(() { tmpEspece = 'tous'; tmpDebut = null; tmpFin = null; });
                      setState(() { _decedesEspece = 'tous'; _decedesDtDebut = null; _decedesDtFin = null; });
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Réinitialiser',
                        style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
                  ),
              ]),
              const SizedBox(height: 16),

              // Espèce
              const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                  children: kSpeciesData
                      .where((sp) => sp.value == 'tous' || availableSpeciesSet.contains(sp.value))
                      .map((sp) {
                final active = tmpEspece == sp.value;
                return GestureDetector(
                  onTap: () { setSheet(() => tmpEspece = sp.value); apply(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? sp.color : Colors.transparent,
                      border: Border.all(color: active ? sp.color : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (sp.value != 'tous') ...[
                        speciesIcon(sp.value, 13, active ? Colors.white : sp.color),
                        const SizedBox(width: 5),
                      ],
                      Text(sp.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: active ? Colors.white : Colors.black87,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ]),
                  ),
                );
              }).toList()),
              const SizedBox(height: 18),

              // Date de décès
              const Text('Date de décès', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: tmpDebut ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) { setSheet(() => tmpDebut = picked); apply(); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: tmpDebut != null ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 14,
                            color: tmpDebut != null ? _teal : Colors.grey),
                        const SizedBox(width: 6),
                        Text(tmpDebut != null ? fmt.format(tmpDebut!) : 'Du...',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: tmpDebut != null ? _teal : Colors.grey)),
                        if (tmpDebut != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () { setSheet(() => tmpDebut = null); apply(); },
                            child: const Icon(Icons.close, size: 14, color: Colors.grey),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: tmpFin ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) { setSheet(() => tmpFin = picked); apply(); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: tmpFin != null ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 14,
                            color: tmpFin != null ? _teal : Colors.grey),
                        const SizedBox(width: 6),
                        Text(tmpFin != null ? fmt.format(tmpFin!) : 'Au...',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: tmpFin != null ? _teal : Colors.grey)),
                        if (tmpFin != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () { setSheet(() => tmpFin = null); apply(); },
                            child: const Icon(Icons.close, size: 14, color: Colors.grey),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  void _openFiche(BuildContext context, String? animalId, {Map<String, dynamic>? data}) {
    final statut = data != null ? (data['statut'] as String? ?? '') : '';
    // Lecture seule si cédant original sur animal sorti — comparé à
    // _ownerUid (l'élevage), pas _uid : un cogérant a un uid différent du
    // gérant qui a réellement cédé l'animal.
    final isCededByMe = data != null && statut == 'sorti' && (
        (data['uid_eleveur'] == (_ownerUid ?? _uid) && data['uid_acquereur'] != null)
        // Repris par l'acquéreur (asso / élevage) : la fiche n'est plus à nous.
        || (data['uid_eleveur'] != (_ownerUid ?? _uid) && !_currentOwnerIds.contains(animalId)));
    // Lecture seule si acquéreur en attente de confirmation
    final isAcquereurPending = data != null && data['uid_acquereur'] == (_ownerUid ?? _uid)
        && statut == 'cession_en_cours';
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(
        animalId: animalId,
        initialData: data,
        preselectedEspece: _filterEspece != 'tous' ? _filterEspece : null,
        readOnly: isCededByMe || isAcquereurPending,
        // Un cogérant (elevage_cogerants) a un uid Firebase différent du
        // gérant : sans ce relais, un animal créé/modifié depuis "Mes
        // Animaux" s'enregistrerait avec uid_proprio = son propre uid au
        // lieu de celui de l'élevage (animaux_proprietes.profile_id_proprio
        // reste, lui, déjà correct — c'est activeProfileId directement).
        eleveurUidOverride: _ownerUid,
      ),
    )).then((_) => _loadAnimaux());
  }

  void _showAddSheet(BuildContext context) {
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
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Ajouter des animaux',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 17, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 20),
          _AddOptionTile(
            icon: Icons.pets,
            color: _green,
            title: 'Ajouter un animal',
            subtitle: 'Fiche individuelle complète',
            onTap: () {
              Navigator.pop(context);
              _openFiche(context, null);
            },
          ),
          const SizedBox(height: 12),
          _AddOptionTile(
            icon: Icons.diversity_3,
            color: _teal,
            title: 'Charger une portée',
            subtitle: 'Créer plusieurs animaux d\'un coup\navec parents communs',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const PorteeFormPage(),
              )).then((created) {
                if (created == true) _loadAnimaux();
              });
            },
          ),
        ]),
      ),
    );
  }
}

// ─── Card animal ──────────────────────────────────────────────────────────────

class _AnimalCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleReproducteur;
  final VoidCallback? onToggleRetraite;
  final VoidCallback? onToggleReproPublic;
  /// Grille (tablette) : photo en haut ; liste (mobile) : photo à gauche.
  final bool vertical;
  /// Chiot d'une portée : statut « Disponible » au lieu de « Présent ».
  final bool isBebe;
  final bool peutAjouterPhoto;
  final bool reproducteur;
  final bool reproPublic;
  final bool isRetraite;
  final bool chaleurFlag;
  final bool gestanteFlag;
  final bool selectMode;
  final bool selected;
  const _AnimalCard({
    required this.id,
    required this.data,
    required this.onTap,
    this.onDelete,
    this.onToggleReproducteur,
    this.onToggleRetraite,
    this.onToggleReproPublic,
    this.vertical = false,
    this.isBebe = false,
    this.peutAjouterPhoto = false,
    this.reproducteur = false,
    this.reproPublic = false,
    this.isRetraite = false,
    this.chaleurFlag = false,
    this.gestanteFlag = false,
    this.selectMode = false,
    this.selected = false,
  });

  static const _dark = Color(0xFF1F2A2E);

  /// Présence (présent / cédé / décédé) distincte de la réservation.
  (String, Color) get _etat {
    final statut = data['statut'] as String? ?? '';
    return switch (statut) {
      'decede' => ('Décédé', const Color(0xFFE25C5C)),
      'sorti' => ('Cédé', const Color(0xFF0C5C6C)),
      'en_attente_cession' || 'cession_en_cours' => ('Cession en cours', const Color(0xFFF59E0B)),
      'reserve' => ('Réservé', const Color(0xFFD97706)),
      _ => (isBebe ? 'Disponible' : 'Présent', const Color(0xFF6E9E57)),
    };
  }

  bool get _aDesActions => !selectMode && (onDelete != null || onToggleReproducteur != null || onToggleRetraite != null);

  void _menu(BuildContext context) {
    final nom = data['nom'] as String? ?? 'Sans nom';
    Widget item(String label, VoidCallback action, {bool danger = false}) => ListTile(
      title: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 15,
          color: danger ? Colors.redAccent : _dark, fontWeight: danger ? FontWeight.w600 : FontWeight.normal)),
      onTap: () { Navigator.pop(context); action(); },
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark))),
          item('Ouvrir la fiche', onTap),
          if (onToggleReproducteur != null)
            item(reproducteur ? 'Retirer des reproducteurs' : 'Marquer comme reproducteur', onToggleReproducteur!),
          if (onToggleReproPublic != null && reproducteur)
            item(reproPublic ? 'Masquer du profil public' : 'Afficher sur mon profil public', onToggleReproPublic!),
          if (onToggleRetraite != null)
            item(isRetraite ? 'Annuler la retraite' : 'Mettre en retraite', onToggleRetraite!),
          if (onDelete != null)
            item('Supprimer la fiche', () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: const Text('Supprimer cet animal ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  content: Text('La fiche de $nom sera définitivement supprimée.', style: const TextStyle(fontFamily: 'Galey')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
                    TextButton(onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent, fontWeight: FontWeight.w700))),
                  ],
                ),
              );
              if (confirm == true) onDelete!();
            }, danger: true),
        ]),
      )),
    );
  }

  /// Emplacement photo neutre (absente ou en erreur de chargement), même cadre.
  Widget _photo(String? url) {
    final vide = Container(
      color: const Color(0xFFEDF2F2),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.image_outlined, size: 26, color: Color(0xFF8B9FA1)),
        if (peutAjouterPhoto && vertical) ...[
          const SizedBox(height: 4),
          const Text('Ajouter une photo', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
              fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
        ],
      ]),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url == null || url.isEmpty ? vide
          : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: const Color(0xFFEDF2F2)),
              errorWidget: (_, __, ___) => vide),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['photo_url'] as String?;
    final nom    = data['nom']    as String? ?? 'Sans nom';
    final espece = data['espece'] as String? ?? '';
    final race   = data['race']   as String? ?? '';
    final sexe   = data['sexe']   as String? ?? '';
    final ident  = (data['identification'] as String? ?? '').trim();
    final statut = data['statut'] as String? ?? '';
    final (etatLabel, etatColor) = _etat;
    final ligne1 = [
      if (sexe == 'male') 'Mâle' else if (sexe == 'femelle') 'Femelle',
      race.isNotEmpty ? race : speciesLabel(espece),
    ].join(' · ');
    final ligne2 = ident.isNotEmpty ? 'Puce $ident' : 'Identification non renseignée';
    final reperes = <(String, Color)>[
      if (reproducteur) ('Reproducteur', const Color(0xFF0C5C6C)),
      if (reproducteur && reproPublic) ('Profil public', const Color(0xFF0C5C6C)),
      if (isRetraite) ('Retraité', const Color(0xFFB45309)),
      if (gestanteFlag) ('Gestante', const Color(0xFF6E9E57)),
      if (chaleurFlag) ('En chaleur', const Color(0xFFDB2777)),
    ];

    final infos = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark))),
        const SizedBox(width: 6),
        Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: etatColor, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(etatLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: etatColor)),
      ]),
      const SizedBox(height: 3),
      Text(ligne1, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      Text(ligne2, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      if (reperes.isNotEmpty) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 2, children: [
          for (final r in reperes)
            Text(r.$1, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: r.$2)),
        ]),
      ],
    ]);

    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      if (statut == 'sorti')
        SizedBox(width: 36, height: 36, child: Center(child: ContactAcquereurButton(animal: data, size: 18))),
      if (_aDesActions)
        IconButton(
          tooltip: 'Autres actions',
          icon: const Icon(Icons.more_horiz, color: Color(0xFF4B5A60)),
          onPressed: () => _menu(context),
          visualDensity: VisualDensity.compact,
        )
      else if (!selectMode && !vertical)
        const Icon(Icons.chevron_right, color: Color(0xFFB0B8BB)),
    ]);

    final caseSelection = Container(
      width: 22, height: 22,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF0C5C6C) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: selected ? const Color(0xFF0C5C6C) : Colors.grey.shade400, width: 1.5),
      ),
      child: selected ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
    );

    final contenu = vertical
        ? Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(aspectRatio: 4 / 3, child: Stack(fit: StackFit.expand, children: [
                _photo(photoUrl),
                if (selectMode) Positioned(top: 6, left: 6, child: caseSelection),
              ])),
              const SizedBox(height: 8),
              Expanded(child: infos),
              Align(alignment: Alignment.centerRight, child: actions),
            ]),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(children: [
              if (selectMode) ...[caseSelection, const SizedBox(width: 10)],
              SizedBox(width: 72, height: 72, child: _photo(photoUrl)),
              const SizedBox(width: 12),
              Expanded(child: infos),
              actions,
            ]),
          );

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? const Color(0xFF0C5C6C) : Colors.grey.shade300, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: _aDesActions ? () => _menu(context) : null,
        child: contenu,
      ),
    );
  }
}

// ─── Widgets helpers ──────────────────────────────────────────────────────────


class _SexeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SexeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF5F9EAA) : Colors.transparent,
          border: Border.all(color: active ? const Color(0xFF5F9EAA) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
            fontFamily: 'Galey', fontSize: 13,
            color: active ? Colors.white : Colors.black87,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _AddOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AddOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 15, color: color)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                color: Color(0xFF6F767B))),
          ])),
          Icon(Icons.chevron_right, color: color.withOpacity(0.6)),
        ]),
      ),
    );
  }
}

