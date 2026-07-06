import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/planning_mois_page.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/widgets/marketplace_banner.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart';
import 'package:PetsMatch/pages/pro/pension_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/pension_planning_page.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/pro/fiches_pension_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pension_documents_page.dart';
import 'package:PetsMatch/pages/pro/vet_patients_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EleveurHomePage extends StatefulWidget {
  const EleveurHomePage({super.key});

  @override
  State<EleveurHomePage> createState() => _EleveurHomePageState();
}

class _EleveurHomePageState extends State<EleveurHomePage> {
  int _animalCount = 0;
  int _postCount = 0;
  int _rdvTodayCount = 0;
  int _patientCount = 0;
  int _rdvMonthCount = 0;
  int _pensionnairesCount = 0;
  int _logementsDispo = 0;
  int _logementsTotal = 0;
  List<Map<String, dynamic>> _mesAlertes = [];
  bool _loading = true;
  List<Map<String, dynamic>> _recentAnnonces = [];
  String _planCode    = 'free';
  int    _activeCount = 0;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final supa = Supabase.instance.client;
    try {
      final alertes = await supa.from('alertes_perdus')
          .select().eq('uid_proprietaire', uid).eq('statut', 'perdu');

      if (!User_Info.isPro) {
        // Éleveur : animaux présents (date_fin IS NULL, filtrés par profil actif)
        final activeProfileId = User_Info.activeProfileId;
        int animalCount;
        if (activeProfileId.isNotEmpty) {
          final check = await supa.from('animaux_proprietes')
              .select('animal_id').eq('uid_proprio', uid)
              .not('profile_id_proprio', 'is', null).limit(1);
          if ((check as List).isNotEmpty) {
            final rows = await supa.from('animaux_proprietes')
                .select('animal_id').eq('uid_proprio', uid)
                .eq('profile_id_proprio', activeProfileId)
                .isFilter('date_fin', null);
            animalCount = (rows as List).length;
          } else {
            final rows = await supa.from('animaux_proprietes')
                .select('animal_id').eq('uid_proprio', uid)
                .isFilter('date_fin', null);
            animalCount = (rows as List).length;
          }
        } else {
          final rows = await supa.from('animaux_proprietes')
              .select('animal_id').eq('uid_proprio', uid)
              .isFilter('date_fin', null);
          animalCount = (rows as List).length;
        }
        final annonces = await supa.from('annonces').select('id')
            .eq('uid_eleveur', uid).inFilter('statut', ['disponible', 'reserve']);
        final recent = await supa.from('annonces')
            .select('id, titre, espece, race, photos, statut, vues, created_at')
            .eq('uid_eleveur', uid)
            .inFilter('statut', ['disponible', 'reserve', 'pause'])
            .order('created_at', ascending: false).limit(3);
        final planCode    = await PlanService.getPlanCode(uid);
        final activeCount = await PlanService.countActiveAnnonces(uid);
        if (!mounted) return;
        setState(() {
          _animalCount = animalCount;
          _postCount = (annonces as List).length;
          _recentAnnonces = List<Map<String, dynamic>>.from(recent);
          _mesAlertes = List<Map<String, dynamic>>.from(alertes as List);
          _planCode    = planCode;
          _activeCount = activeCount;
          _loading = false;
        });
      } else {
        // Pro : stats spécifiques selon catPro
        await _loadProStats(uid, supa);
        if (!mounted) return;
        setState(() {
          _mesAlertes = List<Map<String, dynamic>>.from(alertes as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProStats(String uid, dynamic supa) async {
    final now = DateTime.now();
    final todayStart = '${DateFormat('yyyy-MM-dd').format(now)}T00:00:00';
    final todayEnd   = '${DateFormat('yyyy-MM-dd').format(now)}T23:59:59';
    final monthStart = '${DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1))}T00:00:00';
    final monthEnd   = '${DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month + 1, 0))}T23:59:59';
    // RDV actifs = demandes en attente + confirmés (pas terminés/annulés)
    const activeStatuts = ['demande', 'confirme', 'contre_proposition'];
    final pid = User_Info.activeProfileId;

    // Helper : ajoute le filtre profil sur une requête déjà construite
    dynamic pf(dynamic q) => q.eq('pro_profile_id', pid);

    try {
      if (User_Info.catPro == 'veterinaire') {
        final patients = await pf(supa.from('animal_access')
            .select('id').eq('pro_profile_id', pid).eq('statut', 'active'));
        final rdvToday = await pf(supa.from('rdv').select('id')
            .eq('pro_uid', uid)
            .gte('date_heure', todayStart)
            .lte('date_heure', todayEnd)
            .inFilter('statut', activeStatuts));
        if (mounted) setState(() {
          _patientCount  = (patients as List).length;
          _rdvTodayCount = (rdvToday as List).length;
        });
      } else if (User_Info.catPro == 'pension') {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final rdvToday = await pf(supa.from('rdv').select('id')
            .eq('pro_uid', uid)
            .gte('date_heure', todayStart)
            .lte('date_heure', todayEnd)
            .inFilter('statut', activeStatuts));
        final logements = await supa.from('enclos_chenil').select('id, capacite').eq('uid_eleveur', uid);
        // Séjours réellement en cours aujourd'hui : statut actif + déjà arrivé (date_entree <= aujourd'hui)
        final entreesActives = await supa.from('pension_entrees').select('id, logement_id, date_entree')
            .eq('pro_uid', uid).eq('statut', 'en_pension').lte('date_entree', todayStr);
        final occupePerLogement = <String, int>{};
        for (final e in (entreesActives as List)) {
          final lid = e['logement_id'] as String?;
          if (lid != null) occupePerLogement[lid] = (occupePerLogement[lid] ?? 0) + 1;
        }
        var dispo = 0;
        var total = 0;
        for (final l in (logements as List)) {
          final capacite = (l['capacite'] as int?) ?? 1;
          final occupe = occupePerLogement[l['id']] ?? 0;
          total += capacite;
          dispo += (capacite - occupe).clamp(0, capacite);
        }
        if (mounted) setState(() {
          _pensionnairesCount = entreesActives.length;
          _rdvTodayCount      = (rdvToday as List).length;
          _logementsDispo     = dispo;
          _logementsTotal     = total;
        });
      } else {
        final rdvToday = await pf(supa.from('rdv').select('id')
            .eq('pro_uid', uid)
            .gte('date_heure', todayStart)
            .lte('date_heure', todayEnd)
            .inFilter('statut', activeStatuts));
        final rdvMonth = await pf(supa.from('rdv').select('id')
            .eq('pro_uid', uid)
            .gte('date_heure', monthStart)
            .lte('date_heure', monthEnd)
            .inFilter('statut', activeStatuts));
        if (mounted) setState(() {
          _rdvTodayCount = (rdvToday as List).length;
          _rdvMonthCount = (rdvMonth as List).length;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _green,
              child: CustomScrollView(
                slivers: [
                  _buildSliverHeader(context),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildStatsRow(),
                        if (User_Info.catPro == 'pension' && _logementsTotal > 0) ...[
                          const SizedBox(height: 12),
                          _buildDisponibiliteBanner(context),
                        ],
                        if (!User_Info.isProfileComplete()) ...[
                          const SizedBox(height: 16),
                          _buildProfileIncompleteBanner(context),
                        ],
                        if (_mesAlertes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildAlerteBanner(context),
                        ],
                        const SizedBox(height: 8),
                        MarketplaceBanner(
                          espece: null,
                          placement: 'dashboard',
                        ),
                        if (!User_Info.isPro) ...[
                          const SizedBox(height: 24),
                          _buildSectionTitle('Dernières annonces'),
                          const SizedBox(height: 12),
                          _buildRecentPosts(),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverHeader(BuildContext context) {
    final name = User_Info.nameElevage.isNotEmpty
        ? User_Info.nameElevage
        : '${User_Info.firstname} ${User_Info.lastname}'.trim();
    final city = User_Info.ville.isNotEmpty ? User_Info.ville : User_Info.villeElevage;
    final rawPhoto = User_Info.profilePictureUrlElevage.isNotEmpty
        ? User_Info.profilePictureUrlElevage
        : (User_Info.profilePictureUrl.isNotEmpty ? User_Info.profilePictureUrl : null);
    final photoUrl = (rawPhoto?.isNotEmpty == true) ? rawPhoto : null;

    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: _teal,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C5C6C), Color(0xFF5F9EAA)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => User_Info.isPro
    ? ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null)
    : const ProfilEleveurEditPage())),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: const Color(0xFFA7C79A),
                      backgroundImage: photoUrl != null
                          ? CachedNetworkImageProvider(photoUrl) : null,
                      child: photoUrl == null
                          ? const Icon(Icons.pets, color: Colors.white, size: 36) : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (city.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.location_on_outlined, color: Color(0xFFEEF5EA), size: 14),
                            const SizedBox(width: 4),
                            Text(city,
                                style: const TextStyle(color: Color(0xFFEEF5EA), fontSize: 13, fontFamily: 'Galey')),
                          ]),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => User_Info.isPro
    ? ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null)
    : const ProfilEleveurEditPage())),
                          icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white),
                          label: const Text('Modifier', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Galey')),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _proLabel() {
    switch (User_Info.catPro) {
      case 'veterinaire': return 'Vétérinaire';
      case 'sante': return 'Santé';
      case 'education': return 'Éducation';
      case 'garde': return 'Garde';
      case 'pension': return 'Pension';
      case 'toilettage': return 'Toilettage';
      case 'photographe': return 'Photographe';
      case 'marechal_ferrant': return 'Maréchal';
      default: return 'Pro';
    }
  }

  Widget _buildDisponibiliteBanner(BuildContext context) {
    final occupe = _logementsTotal - _logementsDispo;
    final tauxOccupation = _logementsTotal == 0 ? 0.0 : occupe / _logementsTotal;
    final color = _logementsDispo == 0 ? Colors.orange : _green;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PensionPlanningPage())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Icon(Icons.home_work_outlined, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_logementsDispo / $_logementsTotal places disponibles',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: tauxOccupation, backgroundColor: Colors.grey.shade100, color: color, minHeight: 5,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _buildStatsRow() {
    if (!User_Info.isPro) {
      return Row(children: [
        _StatCard(
          value: _animalCount.toString(), label: 'Animaux', icon: Icons.cruelty_free_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnimauxPage())),
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: _postCount.toString(), label: 'Annonces', icon: Icons.campaign_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnnoncesPage())),
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: 'Éleveur', label: 'Statut', icon: Icons.verified_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AbonnementPage())),
        ),
      ]);
    }
    if (User_Info.catPro == 'veterinaire') {
      return Row(children: [
        _StatCard(value: _patientCount.toString(), label: 'Patients', icon: Icons.favorite_outline),
        const SizedBox(width: 12),
        _StatCard(value: _rdvTodayCount.toString(), label: 'RDV aujourd\'hui', icon: Icons.calendar_today_outlined),
        const SizedBox(width: 12),
        _StatCard(value: 'Vétérinaire', label: 'Statut', icon: Icons.verified_outlined),
      ]);
    }
    if (User_Info.catPro == 'pension') {
      return Row(children: [
        _StatCard(
          value: _pensionnairesCount.toString(), label: 'Pensionnaires', icon: Icons.pets,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrePensionPage())),
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: _rdvTodayCount.toString(), label: 'RDV aujourd\'hui', icon: Icons.calendar_today_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AgendaPage(initialViewMode: 1, onBack: () => Navigator.pop(context)))),
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: 'Pension', label: 'Statut', icon: Icons.verified_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PensionAbonnementPage())),
        ),
      ]);
    }
    return Row(children: [
      _StatCard(value: _rdvTodayCount.toString(), label: 'RDV aujourd\'hui', icon: Icons.calendar_today_outlined),
      const SizedBox(width: 12),
      _StatCard(value: _rdvMonthCount.toString(), label: 'RDV ce mois', icon: Icons.calendar_month_outlined),
      const SizedBox(width: 12),
      _StatCard(value: _proLabel(), label: 'Statut', icon: Icons.verified_outlined),
    ]);
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: Color(0xFF1F2A2E),
        ));
  }

  Widget _buildQuotaCard(BuildContext context) {
    final config   = PlanService.getConfig(_planCode);
    final atLimit  = config.maxAnnonces != -1 && _activeCount >= config.maxAnnonces;
    final progress = config.maxAnnonces == -1
        ? 0.0 : (_activeCount / config.maxAnnonces).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AbonnementPage())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: atLimit ? const Color(0xFFFFF0F0) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: atLimit ? Colors.red.shade200 : Colors.grey.shade100),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${config.badge} Plan ${config.label}',
                  style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
              const SizedBox(width: 8),
              Text(
                config.maxAnnonces == -1 ? 'Illimité'
                    : '$_activeCount / ${config.maxAnnonces} annonces',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: atLimit ? Colors.red : Colors.grey.shade500),
              ),
              if (atLimit) ...[
                const SizedBox(width: 4),
                const Text('· Limite',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        color: Colors.red, fontWeight: FontWeight.w600)),
              ],
            ]),
            if (config.maxAnnonces != -1) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade100,
                  color: atLimit ? Colors.red.shade400 : _green,
                  minHeight: 5,
                ),
              ),
            ],
          ])),
          if (_planCode == 'free') ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('⚡ Pro',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 12, color: Color(0xFF0C5C6C))),
            ),
          ],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Color(0xFF5F9EAA), size: 16),
        ]),
      ),
    );
  }

  Widget _buildProfileIncompleteBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => User_Info.isPro
              ? ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null)
              : const InfoUserSettings())),
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

  Widget _buildAlerteBanner(BuildContext context) {
    final nb = _mesAlertes.length;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MesAlertesPage())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade300, width: 1.5),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: Colors.orange.shade100,
            child: Icon(Icons.location_searching,
                color: Colors.orange.shade700, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            ]),
          ),
          Icon(Icons.chevron_right, color: Colors.orange.shade400),
        ]),
      ),
    );
  }

  Widget _buildQuickAccess(BuildContext context) {
    final isPension = User_Info.isPro && User_Info.catPro == 'pension';
    final isVet = User_Info.isPro && User_Info.catPro == 'veterinaire';
    final isGenericPro = User_Info.isPro && !isPension && !isVet;

    final tiles = [
      if (!User_Info.isPro) ...[
        _QuickTile(icon: Icons.cruelty_free_outlined, label: 'Mes\nAnimaux', color: _green,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnimauxPage()))),
        _QuickTile(icon: Icons.campaign_outlined, label: 'Mes\nAnnonces', color: _teal,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnnoncesPage()))),
        _QuickTile(
            icon: Icons.health_and_safety_outlined,
            label: 'Suivi\nSanitaire',
            color: _planCode == 'free' ? Colors.grey : const Color(0xFF5B8648),
            isLocked: _planCode == 'free',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _planCode == 'free'
                    ? const AbonnementPage()
                    : const RegistreSanitairePage()))),
        _QuickTile(
            icon: Icons.folder_copy_outlined,
            label: 'Entrées\nSorties',
            color: _planCode == 'free' ? Colors.grey : const Color(0xFF374151),
            isLocked: _planCode == 'free',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _planCode == 'free'
                    ? const AbonnementPage()
                    : const RegistreEntreeSortiePage()))),
        _QuickTile(
            icon: Icons.groups_outlined,
            label: 'Mes\nEmployés',
            color: const Color(0xFF7B1FA2),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployesPage()))),
        _QuickTile(
            icon: Icons.event_note_outlined,
            label: 'Protocoles',
            color: _planCode == 'premium' ? const Color(0xFFD97706) : Colors.grey,
            isLocked: _planCode != 'premium',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _planCode == 'premium'
                    ? const PlanningMoisPage()
                    : const AbonnementPage()))),
      ] else if (isVet) ...[
        _QuickTile(icon: Icons.favorite_outline, label: 'Mes\nPatients', color: const Color(0xFF5B8648),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VetPatientsPage()))),
        _QuickTile(icon: Icons.calendar_month_outlined, label: 'Agenda', color: _teal,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProAgendaPage()))),
        _QuickTile(icon: Icons.storefront_outlined, label: 'Services', color: const Color(0xFF5F9EAA),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicesPage()))),
      ] else if (isPension) ...[
        _QuickTile(icon: Icons.menu_book_outlined, label: 'Registre', color: _teal,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrePensionPage()))),
        _QuickTile(icon: Icons.pets, label: 'Fiches\nanimaux', color: _green,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FichesPensionPage()))),
        _QuickTile(icon: Icons.calendar_month_outlined, label: 'Agenda', color: const Color(0xFF5B8648),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProAgendaPage()))),
        _QuickTile(icon: Icons.storefront_outlined, label: 'Services', color: const Color(0xFF5F9EAA),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicesPage()))),
        _QuickTile(icon: Icons.folder_outlined, label: 'Documents', color: const Color(0xFF374151),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PensionDocumentsPage()))),
      ] else if (isGenericPro) ...[
        _QuickTile(icon: Icons.calendar_month_outlined, label: 'Agenda', color: _teal,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProAgendaPage()))),
        _QuickTile(icon: Icons.storefront_outlined, label: 'Services', color: const Color(0xFF5F9EAA),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicesPage()))),
      ],
      if (!isVet && !isPension && !isGenericPro) ...[
        _QuickTile(icon: Icons.home_work_outlined, label: 'Élevages', color: const Color(0xFF5B8648),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EleveurListPage()))),
        _QuickTile(icon: Icons.storefront_outlined, label: 'Services', color: const Color(0xFF5F9EAA),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicesPage()))),
      ],
      _QuickTile(icon: Icons.location_searching, label: 'Animaux\nperdus', color: Colors.orange.shade700,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimauxPerdusPage()))),
      _QuickTile(icon: Icons.add_alert_outlined, label: 'Déclarer\nperdu', color: Colors.orange.shade800,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertePerduFormPage()))),
      _QuickTile(icon: Icons.pets, label: 'Animal\ntrouvé', color: const Color(0xFF0C5C6C),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimalTrouveFormPage()))),
      _QuickTile(icon: Icons.nfc_outlined, label: 'Rech.\npuce', color: const Color(0xFF374151),
          onTap: () => showModalBottomSheet(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const ChipSearchSheet(),
          )),
    ];

    return Column(children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: tiles,
      ),
      if (!User_Info.isPro) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TrouverCompagnonPage())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _teal.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.pets, color: _teal, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Trouver un compagnon',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 15, color: Color(0xFF0C5C6C))),
                SizedBox(height: 2),
                Text('Feed · Recherche · Carte',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        color: Color(0xFF5F9EAA))),
              ])),
              const Icon(Icons.chevron_right, color: Color(0xFF5F9EAA)),
            ]),
          ),
        ),
      ],
    ]);
  }

  Future<void> _confirmDeleteAnnonce(String annonceId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer l\'annonce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette annonce sera supprimée définitivement. Confirmer ?',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Supabase.instance.client.from('annonces').delete().eq('id', annonceId);
    _loadData();
  }

  Widget _buildRecentPosts() {
    if (_recentAnnonces.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Icon(Icons.campaign_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('Aucune annonce publiée',
              style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateAnnoncePage()))
                .then((_) { if (mounted) _loadData(); }),
            style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white),
            child: const Text('Créer une annonce',
                style: TextStyle(fontFamily: 'Galey')),
          ),
        ]),
      );
    }

    return Column(
      children: _recentAnnonces.map((data) {
        final photos = List<String>.from(data['photos'] ?? []);
        final statut = (data['statut'] as String?) ?? 'disponible';
        final espece = (data['espece'] as String?) ?? '';
        final race   = (data['race']   as String?) ?? '';
        final titre  = (data['titre']  as String?) ?? '';
        final vues   = (data['vues']   as num?)?.toInt() ?? 0;
        final createdAt = data['created_at'] as String?;

        final displayTitle = titre.isNotEmpty ? titre
            : race.isNotEmpty ? race : speciesLabel(espece);

        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => AnnonceDetailPage(
                  annonceId: data['id'] as String, initialData: data))),
          onLongPress: () => _confirmDeleteAnnonce(data['id'] as String),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 56, height: 56,
                  child: photos.isNotEmpty
                      ? CachedNetworkImage(imageUrl: photos.first,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: const Color(0xFFEEF5EA)),
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFFEEF5EA)))
                      : Container(color: const Color(0xFFEEF5EA),
                          child: Center(child: speciesIcon(espece, 24, const Color(0xFFA7C79A)))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayTitle,
                      style: const TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    _Badge(
                      statut == 'pause' ? 'En pause'
                          : statut == 'reserve' ? 'Réservé' : 'En ligne',
                      statut == 'pause' ? Colors.grey
                          : statut == 'reserve' ? const Color(0xFFF59E0B)
                          : _green),
                    const SizedBox(width: 8),
                    Icon(Icons.visibility_outlined, size: 12,
                        color: Colors.grey.shade400),
                    const SizedBox(width: 2),
                    Text('$vues',
                        style: TextStyle(fontFamily: 'Galey',
                            fontSize: 11, color: Colors.grey.shade400)),
                  ]),
                ],
              )),
              if (createdAt != null)
                Text(DateFormat('dd/MM').format(DateTime.parse(createdAt)),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: Colors.grey.shade400)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatCard({required this.value, required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF6E9E57), size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1F2A2E))),
          Text(label,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
        ],
      ),
    );
    return Expanded(
      child: onTap != null
          ? GestureDetector(onTap: onTap, child: card)
          : card,
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isLocked;

  const _QuickTile({
    required this.icon, required this.label, required this.color, required this.onTap,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            color: color.withOpacity(isLocked ? 0.06 : 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: color.withOpacity(isLocked ? 0.15 : 0.3),
                style: isLocked ? BorderStyle.solid : BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color.withOpacity(isLocked ? 0.4 : 1.0), size: 28),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                    color: color.withOpacity(isLocked ? 0.4 : 1.0),
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.3,
                  )),
            ],
          ),
        ),
        if (isLocked)
          Positioned(
            top: 6, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('Pro',
                  style: TextStyle(color: Colors.white,
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 9)),
            ),
          ),
      ]),
    );
  }
}


class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
    );
  }
}
