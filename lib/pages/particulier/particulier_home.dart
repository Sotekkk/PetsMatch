import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/particulier/balades/choix_animaux_balade.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/search/quick_search_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart' show speciesIcon, speciesLabel;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/animal_fiche_particulier.dart';
import 'package:PetsMatch/pages/particulier/balades/balade_live_page.dart';
import 'package:PetsMatch/pages/communaute/communaute_hub_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/annonces/trouver_animal_page.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/particulier/mes_annonces_particulier_page.dart';
import 'package:PetsMatch/pages/pro/pension_reservation_page.dart' show MesSejoursPensionPage;
import 'package:PetsMatch/pages/services/services_page.dart';

class ParticulierHomePage extends StatefulWidget {
  const ParticulierHomePage({super.key});

  @override
  State<ParticulierHomePage> createState() => _ParticulierHomePageState();
}

class _ParticulierHomePageState extends State<ParticulierHomePage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _tealLight = Color(0xFF5F9EAA);

  final _supa = Supabase.instance.client;

  String? _photoUrl;
  int _nbAnimaux = 0;
  int _streakCount = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _animaux = [];
  List<Map<String, dynamic>> _mesAlertes = [];
  List<Map<String, dynamic>> _alertesPubliques = [];
  bool _loadingAlertes = false;
  List<Map<String, dynamic>> _annonces = [];
  /// Soins à donner (prises de traitement, vermifuges sur plusieurs jours) :
  /// tâches créées par les rappels, du jour et en retard, à cocher.
  List<Map<String, dynamic>> _tachesSoin = [];
  /// Co-propriétaires de mes animaux : uid → nom affiché.
  final Map<String, String> _nomsCopro = {};
  // Mon quotidien : prochains événements de l'agenda (rendez-vous, tâches) du
  // profil actif + rappels santé à venir des animaux de ce profil.
  List<Map<String, dynamic>> _evenements = [];
  List<Map<String, dynamic>> _rappels = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = User_Info.uid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final activeProfileId = User_Info.activeProfileId;

      // Photo du profil actif : user_profiles.avatar_url (pas le doc partagé).
      // streak_count = flamme (série de jours actifs, cf. gamification Phase 1).
      String? profileAvatar;
      int streakCount = 0;
      try {
        final prow = activeProfileId.isNotEmpty
            ? await _supa.from('user_profiles_complet').select('avatar_url, streak_count').eq('id', activeProfileId).maybeSingle()
            : await _supa.from('user_profiles_complet').select('avatar_url, streak_count')
                .eq('uid', uid).eq('is_main', true).maybeSingle();
        profileAvatar = (prow?['avatar_url'] as String?)?.trim();
        streakCount = (prow?['streak_count'] as num?)?.toInt() ?? 0;
      } catch (_) {}

      List ownRows;
      if (activeProfileId.isNotEmpty) {
        final check = await _supa
            .from('animaux_proprietes')
            .select('animal_id')
            .eq('uid_proprio', uid)
            .not('profile_id_proprio', 'is', null)
            .limit(1);
        if ((check as List).isNotEmpty) {
          ownRows = await _supa
              .from('animaux_proprietes')
              .select('animal_id')
              .eq('uid_proprio', uid)
              .eq('profile_id_proprio', activeProfileId)
              .isFilter('date_fin', null);
        } else {
          ownRows = await _supa
              .from('animaux_proprietes')
              .select('animal_id')
              .eq('uid_proprio', uid)
              .isFilter('date_fin', null);
        }
      } else {
        ownRows = await _supa
            .from('animaux_proprietes')
            .select('animal_id')
            .eq('uid_proprio', uid)
            .isFilter('date_fin', null);
      }
      final myIds = (ownRows).map((r) => r['animal_id'] as String).toList();
      final animaux = myIds.isEmpty ? [] : await _supa
          .from('animaux')
          .select()
          .inFilter('id', myIds);
      // Alertes « perdu » de CE profil uniquement (une alerte créée depuis le
      // profil élevage ne doit pas allumer le compteur côté particulier).
      var qAlertesMes = _supa
          .from('alertes_perdus')
          .select()
          .eq('uid_proprietaire', uid)
          .eq('statut', 'perdu');
      if (activeProfileId.isNotEmpty) {
        qAlertesMes = qAlertesMes.eq('profile_id', activeProfileId);
      }
      final alertesMes = await qAlertesMes;
      final annonces = await _supa
          .from('annonces')
          .select('id, titre, espece, race, photos, prix, prix_min_portee, prix_max_portee, type, type_vente, ville_eleveur')
          .eq('statut', 'disponible')
          .order('created_at', ascending: false)
          .limit(6);

      // Mon quotidien — scopé au profil actif (jamais l'agenda d'un autre profil).
      final now = DateTime.now();
      final debutJour = DateTime(now.year, now.month, now.day);
      var evenements = <Map<String, dynamic>>[];
      try {
        final qEv = activeProfileId.isNotEmpty
            ? _supa.from('agenda_events').select().eq('pro_profile_id', activeProfileId)
            : _supa.from('agenda_events').select().eq('uid', uid).or('pro_profile_id.is.null,pro_profile_id.eq.');
        evenements = List<Map<String, dynamic>>.from(await qEv
            .gte('date_debut', debutJour.toIso8601String())
            .lte('date_debut', debutJour.add(const Duration(days: 15)).toIso8601String())
            .order('date_debut')
            .limit(8) as List);
      } catch (_) {}
      // Co-propriété : RDV, rappels et tâches de soin des animaux partagés,
      // créés chez l'autre co-propriétaire (« pris par » / « ajouté par »).
      if (myIds.isNotEmpty) {
        try {
          final co = await _supa.from('animaux_proprietes').select('uid_proprio, profile_id_proprio')
              .inFilter('animal_id', myIds).eq('statut', 'actif').isFilter('date_fin', null).neq('uid_proprio', uid);
          final profils = (co as List).map((r) => r['profile_id_proprio']?.toString()).whereType<String>().toSet().toList();
          if (profils.isNotEmpty) {
            final ups = await _supa.from('user_profiles_complet')
                .select('uid, nom, firstname, lastname').inFilter('id', profils).eq('profile_type', 'particulier');
            for (final u in ups as List) {
              final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
              _nomsCopro[u['uid'].toString()] = nom.isNotEmpty ? nom : (u['nom'] ?? 'Co-propriétaire').toString();
            }
          }
          if (_nomsCopro.isNotEmpty) {
            final partages = await _supa.from('agenda_events').select()
                .inFilter('animal_id', myIds).inFilter('uid', _nomsCopro.keys.toList())
                .gte('date_debut', debutJour.toIso8601String())
                .lte('date_debut', debutJour.add(const Duration(days: 15)).toIso8601String())
                .order('date_debut').limit(8);
            final vus = evenements.map((e) => e['id']).toSet();
            for (final e in partages as List) {
              if (!vus.add(e['id'])) continue;
              final m = Map<String, dynamic>.from(e as Map);
              m['titre'] = '${m['titre'] ?? ''} — ${m['type'] == 'rdv' ? 'pris par' : 'ajouté par'} ${_nomsCopro[m['uid']?.toString()]}';
              evenements.add(m);
            }
            evenements.sort((a, b) => (a['date_debut'] ?? '').toString().compareTo((b['date_debut'] ?? '').toString()));
          }
        } catch (_) {}
      }
      var tachesSoin = <Map<String, dynamic>>[];
      try {
        var qT = _supa.from('taches_elevage')
            .select('id, titre, date, heure, statut, animal_id, animal_nom, notes')
            .eq('uid_eleveur', uid).eq('profil_source', 'particulier').neq('statut', 'fait')
            .lte('date', DateFormat('yyyy-MM-dd').format(debutJour));
        if (activeProfileId.isNotEmpty) qT = qT.or('profile_id.eq.$activeProfileId,profile_id.is.null');
        tachesSoin = List<Map<String, dynamic>>.from(await qT.order('date').order('heure').limit(6) as List);
        if (myIds.isNotEmpty && _nomsCopro.isNotEmpty) {
          final partagees = await _supa.from('taches_elevage')
              .select('id, titre, date, heure, statut, animal_id, animal_nom, notes')
              .eq('profil_source', 'particulier').neq('statut', 'fait').inFilter('animal_id', myIds).neq('uid_eleveur', uid)
              .lte('date', DateFormat('yyyy-MM-dd').format(debutJour)).order('date').limit(6);
          final vus = tachesSoin.map((t) => t['id']).toSet();
          for (final t in partagees as List) {
            if (vus.add(t['id'])) tachesSoin.add(Map<String, dynamic>.from(t as Map));
          }
          tachesSoin.sort((a, b) => '${a['date']} ${a['heure'] ?? ''}'.compareTo('${b['date']} ${b['heure'] ?? ''}'));
          if (tachesSoin.length > 6) tachesSoin = tachesSoin.sublist(0, 6);
        }
      } catch (_) {}
      var rappels = <Map<String, dynamic>>[];
      if (myIds.isNotEmpty) {
        // Seule la dernière injection de chaque vaccin / produit compte : un
        // rappel déjà fait disparaît, un rappel en retard reste jusqu'à ce
        // qu'il soit fait (un an au plus).
        final de = DateFormat('yyyy-MM-dd').format(debutJour.subtract(const Duration(days: 365)));
        final a = DateFormat('yyyy-MM-dd').format(debutJour.add(const Duration(days: 30)));
        for (final t in const [('vaccinations', 'vaccin', 'Rappel vaccin'), ('vermifuges', 'produit', 'Vermifuge'), ('antiparasitaires', 'produit', 'Antiparasitaire')]) {
          try {
            final rows = await _supa.from(t.$1).select().inFilter('animal_id', myIds)
                .order('date', ascending: false, nullsFirst: false).limit(300);
            final vus = <String>{};
            for (final r in rows as List) {
              final m = Map<String, dynamic>.from(r as Map);
              final nom = (m['categorie'] ?? '').toString().isNotEmpty ? m['categorie'] : m[t.$2];
              if (!vus.add('${m['animal_id']}|${(nom ?? '').toString().toLowerCase()}')) continue;
              final dr = (m['date_rappel'] ?? '').toString();
              if (dr.isEmpty || dr.compareTo(de) < 0 || dr.compareTo(a) > 0) continue;
              m['_libelle'] = '${t.$3}${(m[t.$2] ?? '').toString().isNotEmpty ? ' ${m[t.$2]}' : ''}';
              m['_table'] = t.$1;
              rappels.add(m);
            }
          } catch (_) {}
        }
        rappels.sort((x, y) => (x['date_rappel'] ?? '').toString().compareTo((y['date_rappel'] ?? '').toString()));
      }

      if (!mounted) return;
      setState(() {
        _evenements = evenements;
        _tachesSoin = tachesSoin;
        _rappels = rappels.take(4).toList();
        final firestorePic = doc.data()?['profilePictureUrl'];
        _photoUrl = (profileAvatar != null && profileAvatar.isNotEmpty)
            ? profileAvatar
            : (activeProfileId.isEmpty ? firestorePic : null);
        _animaux = List<Map<String, dynamic>>.from(animaux as List);
        _nbAnimaux = _animaux.length;
        _streakCount = streakCount;
        _mesAlertes = List<Map<String, dynamic>>.from(alertesMes as List);
        _annonces = List<Map<String, dynamic>>.from(annonces as List);
        _loading = false;
      });
      _loadAlertesPubliques();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAlertesPubliques() async {
    if (!mounted) return;
    setState(() => _loadingAlertes = true);
    try {
      final rows = await _supa
          .from('alertes_perdus')
          .select()
          .eq('statut', 'perdu')
          .order('created_at', ascending: false)
          .limit(6);
      if (mounted) setState(() {
        _alertesPubliques = List<Map<String, dynamic>>.from(rows as List);
        _loadingAlertes = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAlertes = false);
    }
  }

  void _shareAlerte(Map<String, dynamic> a) {
    final nom = (a['nom_animal'] ?? 'Animal') as String;
    final espece = (a['espece'] ?? '') as String;
    final ville = (a['derniere_localisation'] ?? '') as String;
    final dateStr = a['date_perte'] as String?;
    final date = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final desc = (a['description'] as String?) ?? '';
    final text = [
      'ANIMAL PERDU — $nom ($espece)',
      if (ville.isNotEmpty) 'Dernière localisation : $ville',
      if (date.isNotEmpty) 'Disparu le $date',
      if (desc.isNotEmpty) desc,
      'Si vous l\'avez vu, signalez-le sur l\'app PetsMatch',
    ].join('\n');
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: _teal,
              expandedHeight: 180,
              floating: false,
              pinned: true,
              // Affiché dans la navigation du particulier (barre du bas) :
              // pas de flèche retour.
              automaticallyImplyLeading: false,
              actions: const [QuickSearchButton()],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: _teal,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const InfoUserSettings())),
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: const Color(0xFF5B9EAA),
                                  backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                                      ? CachedNetworkImageProvider(_photoUrl!)
                                      : null,
                                  child: (_photoUrl == null || _photoUrl!.isEmpty)
                                      ? const Icon(Icons.person, color: Colors.white, size: 24)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Tableau de bord · Particulier',
                                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFFCCE8EE))),
                                    Text('Bonjour ${User_Info.firstname}',
                                        style: const TextStyle(
                                            fontFamily: 'Galey',
                                            fontWeight: FontWeight.w800,
                                            fontSize: 20,
                                            color: Colors.white)),
                                    if (User_Info.ville.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on,
                                              color: Color(0xFFB2D8DE), size: 13),
                                          const SizedBox(width: 3),
                                          Text(User_Info.ville,
                                              style: const TextStyle(
                                                  fontFamily: 'Galey',
                                                  fontSize: 12,
                                                  color: Color(0xFFCCE8EE))),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (!_loading) _buildStatsRow(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (!User_Info.isProfileComplete()) ...[
                    _buildProfileIncompleteBanner(),
                    const SizedBox(height: 16),
                  ],
                  if (_animaux.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildMesAnimauxSection(),
                    const SizedBox(height: 20),
                  ],
                  if (_mesAlertes.isNotEmpty) ...[
                    _buildAlerteBanner(),
                    const SizedBox(height: 20),
                  ],
                  _buildMonQuotidien(),
                  const SizedBox(height: 24),
                  _buildQuickAccess(),
                  const SizedBox(height: 24),
                  _buildAnnoncesSection(),
                  const SizedBox(height: 24),
                  _buildAnimauxPerdusSection(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileIncompleteBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const InfoUserSettings())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade400, width: 1.5),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: Colors.amber.shade100,
            child: Icon(Icons.person_outline, color: Colors.amber.shade800, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Complétez votre profil',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.amber.shade900),
              ),
              Text(
                'Téléphone, ville et code postal manquants',
                style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, color: Colors.amber.shade700)),
            ]),
          ),
          Icon(Icons.chevron_right, color: Colors.amber.shade400),
        ]),
      ),
    );
  }

  Widget _buildStatsRow() {
    final nb = _mesAlertes.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatCard(
            value: '$_nbAnimaux',
            label: _nbAnimaux > 1 ? 'Animaux' : 'Animal',
            icon: Icons.pets,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UserParticulierFeed(initialTab: 1, animauxSeuls: true))),
          ),
          const SizedBox(width: 12),
          _StatCard(
            value: '$_streakCount',
            label: 'Jour${_streakCount > 1 ? 's' : ''} de suite',
            icon: Icons.local_fire_department,
            highlight: _streakCount > 0,
          ),
          const SizedBox(width: 12),
          _StatCard(
            value: '$nb',
            label: 'Alerte${nb > 1 ? 's' : ''} active${nb > 1 ? 's' : ''}',
            icon: Icons.location_searching,
            highlight: nb > 0,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MesAlertesPage())),
          ),
        ],
      ),
    );
  }

  // Un ou plusieurs animaux (choix_animaux_balade.dart).
  Future<void> _demarrerBalade() => demarrerBalade(context);

  Widget _titreSection(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF1F2A2E)));

  void _ouvrir(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Widget _buildQuickAccess() {
    final orange = Colors.orange.shade800;
    const vert = Color(0xFF4E7A3B);
    final tuiles = <(IconData, String, Color, VoidCallback)>[
      (Icons.description_outlined, 'Mes annonces', _teal, () => _ouvrir(const MesAnnoncesParticulierPage())),
      (Icons.medical_services_outlined, 'Trouver un pro', _teal, () => _ouvrir(const ServicesPage())),
      (Icons.location_searching, 'Perdus et trouvés', orange, () => _ouvrir(const AnimauxPerdusPage())),
      (Icons.groups_outlined, 'Communauté', _teal, () => _ouvrir(const CommunauteHubPage())),
      (Icons.house_outlined, 'Mes séjours', _teal, () => _ouvrir(const MesSejoursPensionPage())),
      (Icons.directions_walk, 'Démarrer une balade', vert, _demarrerBalade),
      (Icons.pets, 'Trouver un animal', _teal, () => _ouvrir(const TrouverAnimalPage())),
      (Icons.nfc_outlined, 'Recherche par puce', const Color(0xFF374151), () => showModalBottomSheet(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const ChipSearchSheet(),
          )),
      (Icons.notifications_active_outlined, 'Mes alertes', orange, () => _ouvrir(const MesAlertesPage())),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreSection('Accès rapides'),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: tuiles.map((t) => Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: t.$4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(t.$1, color: t.$3, size: 26),
                const SizedBox(height: 8),
                Text(t.$2, textAlign: TextAlign.center, maxLines: 2,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
              ]),
            ),
          ),
        )).toList(),
      ),
    ]);
  }

  // ── Mon quotidien : rendez-vous, à faire, rappels santé ─────────────────────
  Widget _buildMonQuotidien() {
    final rdv = _evenements.where((e) => const {'rdv', 'visite'}.contains(e['type'])).take(3).toList();
    final aFaire = _evenements.where((e) => !const {'rdv', 'visite'}.contains(e['type'])).take(3).toList();
    final rien = rdv.isEmpty && aFaire.isEmpty && _rappels.isEmpty && _tachesSoin.isEmpty;
    String quand(String? iso, {bool heure = false}) {
      final d = DateTime.tryParse(iso ?? '')?.toLocal();
      if (d == null) return '';
      final auj = DateTime.now();
      final j = DateTime(d.year, d.month, d.day).difference(DateTime(auj.year, auj.month, auj.day)).inDays;
      final jour = j == 0 ? 'Aujourd\'hui' : j == 1 ? 'Demain' : DateFormat('EEE d MMM', 'fr_FR').format(d);
      return heure && (d.hour != 0 || d.minute != 0) ? '$jour · ${DateFormat('HH:mm').format(d)}' : jour;
    }
    String enRetardRappel(String? iso) {
      final d = DateTime.tryParse(iso ?? '');
      final auj = DateTime.now();
      if (d != null && DateTime(d.year, d.month, d.day).isBefore(DateTime(auj.year, auj.month, auj.day))) {
        return 'En retard · ${DateFormat('d MMM', 'fr_FR').format(d)}';
      }
      return quand(iso);
    }
    String nomAnimal(dynamic id) {
      final a = _animaux.where((x) => x['id']?.toString() == id?.toString());
      return a.isEmpty ? '' : (a.first['nom'] ?? '').toString();
    }
    Widget sousTitre(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(t.toUpperCase(),
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.grey.shade600)),
        );
    Widget ligne(IconData icone, Color couleur, String titre, String detail, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icone, size: 18, color: couleur),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
                if (detail.isNotEmpty)
                  Text(detail, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ])),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
            ]),
          ),
        );
    void agenda() => _ouvrir(const AgendaPage(isParticulier: true));
    /// Ouvre la fiche de l'animal sur son carnet de santé (bon endroit pour
    /// valider un vaccin, un vermifuge, un traitement).
    /// [rappel] : ouvre directement le formulaire de rappel de cette entrée.
    void carnet(dynamic animalId, {Map<String, dynamic>? rappel}) {
      final a = _animaux.where((x) => x['id']?.toString() == animalId?.toString());
      if (a.isEmpty) { agenda(); return; }
      _ouvrir(AnimalFicheParticulierPage(animalId: a.first['id'] as String?, initialData: a.first,
          initialTabLabel: 'Carnet de santé',
          rappelSante: rappel == null ? null : (rappel['_table'].toString(), rappel['id'].toString())));
    }
    Future<void> valider(Map<String, dynamic> t) async {
      try {
        await _supa.from('taches_elevage').update({'statut': 'fait'}).eq('id', t['id']);
        if (!mounted) return;
        setState(() => _tachesSoin.removeWhere((x) => x['id'] == t['id']));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soin validé.'), behavior: SnackBarBehavior.floating));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation impossible, réessayez.')));
        }
      }
    }
    Widget soin(Map<String, dynamic> t) {
      final d = DateTime.tryParse(t['date']?.toString() ?? '');
      final auj = DateTime.now();
      final enRetard = d != null && DateTime(d.year, d.month, d.day).isBefore(DateTime(auj.year, auj.month, auj.day));
      final heure = (t['heure'] ?? '').toString();
      final detail = [
        enRetard ? 'En retard · ${DateFormat('d MMM', 'fr_FR').format(d)}' : 'Aujourd\'hui',
        if (heure.isNotEmpty) heure.length >= 5 ? heure.substring(0, 5) : heure,
        (t['notes'] ?? '').toString(),
      ].where((x) => x.isNotEmpty).join(' · ');
      return InkWell(
        onTap: () => carnet(t['animal_id']),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
          child: Row(children: [
            IconButton(
              tooltip: 'Valider',
              icon: const Icon(Icons.check_box_outline_blank, color: Color(0xFF4E7A3B)),
              onPressed: () => valider(t),
            ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((t['titre'] ?? 'Soin').toString().replaceFirst(RegExp(r'^\S*💊\S*\s*'), ''),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
              Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: enRetard ? Colors.red.shade700 : Colors.grey.shade600)),
            ])),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ]),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreSection('Mon quotidien'),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: rien
            ? Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Rien de prévu pour le moment.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
                  const SizedBox(height: 4),
                  Text('Profitez de vos compagnons. Vos rendez-vous, tâches et rappels santé apparaîtront ici.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: agenda,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: _teal),
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: const Text('Ouvrir mon agenda', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  ),
                ]),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (rdv.isNotEmpty) ...[
                  sousTitre('Prochains rendez-vous'),
                  ...rdv.map((e) => ligne(Icons.event_outlined, _teal, (e['titre'] ?? 'Rendez-vous').toString(),
                      [quand(e['date_debut']?.toString(), heure: true), nomAnimal(e['animal_id'])].where((x) => x.isNotEmpty).join(' · '), agenda)),
                ],
                if (_tachesSoin.isNotEmpty) ...[
                  sousTitre('Soins à donner'),
                  ..._tachesSoin.map(soin),
                ],
                if (aFaire.isNotEmpty) ...[
                  sousTitre('À faire'),
                  ...aFaire.map((e) => ligne(Icons.check_circle_outline, const Color(0xFF4E7A3B), (e['titre'] ?? 'Tâche').toString(),
                      [quand(e['date_debut']?.toString(), heure: true), nomAnimal(e['animal_id'])].where((x) => x.isNotEmpty).join(' · '), agenda)),
                ],
                if (_rappels.isNotEmpty) ...[
                  sousTitre('Rappels et échéances'),
                  ..._rappels.map((r) {
                    final animal = _animaux.where((x) => x['id']?.toString() == r['animal_id']?.toString());
                    return ligne(Icons.schedule, Colors.orange.shade800,
                        [r['_libelle'], nomAnimal(r['animal_id'])].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                        enRetardRappel(r['date_rappel']?.toString()),
                        () => animal.isEmpty ? null : carnet(animal.first['id'], rappel: r));
                  }),
                ],
                const SizedBox(height: 6),
              ]),
      ),
    ]);
  }

  Widget _buildMesAnimauxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.pets, color: _teal, size: 18),
              const SizedBox(width: 6),
              const Text('Mes animaux',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Color(0xFF1F2A2E))),
            ]),
            TextButton(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const UserParticulierFeed(initialTab: 1, animauxSeuls: true)));
                if (mounted) _load();
              },
              child: Text('Voir tout',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 185,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _animaux.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final a = _animaux[i];
              return _AnimalMiniCard(
                animal: a,
                onTap: () async {
                  // Sans ce rechargement, la page d'accueil garde
                  // l'instantané chargé à l'ouverture : une photo ajoutée/
                  // changée depuis la fiche (ou un animal tout juste créé)
                  // ne s'affiche pas tant qu'on ne quitte pas l'onglet
                  // Accueil et qu'on n'y revient pas.
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AnimalFicheParticulierPage(
                      animalId: a['id'] as String?,
                      initialData: a,
                    ),
                  ));
                  if (mounted) _load();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnoncesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.campaign_outlined, color: _teal, size: 18),
              const SizedBox(width: 6),
              const Text('Découvrir',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Color(0xFF1F2A2E))),
            ]),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TrouverAnimalPage())),
              child: Text('Voir tout',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_annonces.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text('Aucune annonce disponible',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: Colors.grey.shade500))),
          )
        else
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _annonces.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _AnnonceMiniCard(
                annonce: _annonces[i],
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnnonceDetailPage(
                    annonceId: _annonces[i]['id'] as String,
                    initialData: _annonces[i],
                  ),
                )),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAnimauxPerdusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(Icons.location_searching, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 6),
              const Text('Perdus & Trouvés',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF1F2A2E))),
            ]),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AnimauxPerdusPage())),
              child: Text('Voir tout',
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Colors.orange.shade700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingAlertes)
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2),
          ))
        else if (_alertesPubliques.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Center(
              child: Text('Aucun animal perdu signalé',
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
            ),
          )
        else
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _alertesPubliques.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) =>
                  _PerduMiniCard(alerte: _alertesPubliques[i],
                      onShare: () => _shareAlerte(_alertesPubliques[i]),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => AnimauxPerdusPage(
                              initialAlertId: _alertesPubliques[i]['id'] as String?)))),
            ),
          ),
      ],
    );
  }

  Widget _buildAlerteBanner() {
    final nb = _mesAlertes.length;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MesAlertesPage())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade300, width: 1.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: Icon(Icons.location_searching,
                  color: Colors.orange.shade700, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$nb alerte${nb > 1 ? 's' : ''} active${nb > 1 ? 's' : ''}',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.orange.shade800),
                  ),
                  Text(
                    nb == 1 ? 'Appuyez pour gérer votre alerte' : 'Appuyez pour gérer vos alertes',
                    style: TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.orange.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: highlight ? Colors.orange.shade200 : Colors.white,
              size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Colors.white)),
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 11, color: Colors.white70)),
            ],
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _QuickTileData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickTileData(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
}

class _QuickTile extends StatelessWidget {
  final _QuickTileData data;
  const _QuickTile({required this.data});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.10),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                ),
                child: Icon(data.icon, color: data.color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(data.label,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ],
          ),
        ),
      );
}

class _AnimalMiniCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback onTap;
  const _AnimalMiniCard({required this.animal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom = (animal['nom'] ?? 'Sans nom') as String;
    final espece = (animal['espece'] ?? '') as String;
    final race = (animal['race'] ?? '') as String;
    final sexe = ((animal['sexe'] ?? '') as String).toLowerCase();
    final photoUrl = animal['photo_url'] as String?;
    final isMale = sexe.startsWith('m');
    final isFemale = sexe.startsWith('f');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 135,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(espece),
                          errorWidget: (_, __, ___) => _placeholder(espece))
                      : _placeholder(espece),
                  // Sex badge top-right
                  if (isMale || isFemale)
                    Positioned(
                      top: 5, right: 5,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isMale ? Colors.blue.shade100 : Colors.pink.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isMale ? Icons.male : Icons.female,
                          size: 12,
                          color: isMale ? Colors.blue.shade700 : Colors.pink.shade700,
                        ),
                      ),
                    ),
                  // Species icon bottom-left
                  if (espece.isNotEmpty)
                    Positioned(
                      bottom: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: speciesIcon(espece, 12, const Color(0xFF6E9E57)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 12, color: Color(0xFF1F2A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Text(race.isNotEmpty ? race : speciesLabel(espece),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(String espece) => Container(
        color: const Color(0xFFEAF4EC),
        child: Center(child: speciesIcon(espece.isNotEmpty ? espece : 'autre', 32, const Color(0xFF6E9E57))),
      );
}

class _PerduMiniCard extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final VoidCallback onShare;
  final VoidCallback onTap;
  const _PerduMiniCard(
      {required this.alerte, required this.onShare, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom = (alerte['nom_animal'] ?? '') as String;
    final espece = (alerte['espece'] ?? '') as String;
    final ville = (alerte['derniere_localisation'] ?? '') as String;
    final photoUrl = alerte['photo_url'] as String?;
    final dateStr = alerte['date_perte'] as String?;
    final date = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200, width: 1.2),
          boxShadow: [
            BoxShadow(
                color: Colors.orange.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: SizedBox(
              height: 80,
              width: double.infinity,
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(nom,
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF1F2A2E)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$espece${ville.isNotEmpty ? ' · $ville' : ''}',
              style: const TextStyle(
                  fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(date,
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 10,
                      color: Colors.orange.shade700)),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: SizedBox(
              width: double.infinity,
              height: 26,
              child: OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share, size: 11),
                label: const Text('Partager',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  side: BorderSide(color: Colors.orange.shade300, width: 0.8),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.orange.shade50,
        child: Center(
            child: Icon(Icons.pets, color: Colors.orange.shade200, size: 28)),
      );
}

// ── Bouton accès rapide pleine largeur ────────────────────────────────────────

class _QuickTileWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _QuickTileWide({
    required this.icon, required this.label, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
          Text(subtitle, style: TextStyle(
              fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        ])),
        Icon(Icons.play_arrow_rounded, color: color, size: 22),
      ]),
    ),
  );
}

// ── Mini-carte annonce ────────────────────────────────────────────────────────

class _AnnonceMiniCard extends StatelessWidget {
  final Map<String, dynamic> annonce;
  final VoidCallback onTap;
  const _AnnonceMiniCard({required this.annonce, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final titre    = (annonce['titre'] as String?) ?? '';
    final espece   = (annonce['espece'] as String?) ?? '';
    final race     = (annonce['race'] as String?) ?? '';
    final photos   = List<String>.from(annonce['photos'] ?? []);
    final isSaillie = annonce['type_vente'] == 'saillie';
    final isPortee  = annonce['type'] == 'portee';
    final ville    = (annonce['ville_eleveur'] as String?) ?? '';

    final prixRaw = isPortee
        ? (annonce['prix_min_portee'] ?? annonce['prix_max_portee'])
        : annonce['prix'];
    final prix = prixRaw != null ? '${(prixRaw as num).toInt()} €' : null;

    final displayTitle = titre.isNotEmpty ? titre
        : (race.isNotEmpty ? race : speciesLabel(espece));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                photos.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photos.first, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: const Color(0xFFEEF5EA)),
                        errorWidget: (_, __, ___) => Container(color: const Color(0xFFEEF5EA)))
                    : Container(color: const Color(0xFFEEF5EA),
                        child: Center(child: speciesIcon(espece, 32, const Color(0xFF6E9E57)))),
                Positioned(top: 5, left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSaillie
                          ? const Color(0xFF8B5CF6)
                          : isPortee ? const Color(0xFFF59E0B) : const Color(0xFF6E9E57),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isSaillie ? 'Saillie' : isPortee ? 'Portée' : 'Compagnon',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 8,
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(displayTitle,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 11, color: Color(0xFF1F2A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (prix != null)
                Text(prix, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0C5C6C))),
              if (ville.isNotEmpty)
                Text(ville,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 9,
                        color: Color(0xFF9CA3AF)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}
