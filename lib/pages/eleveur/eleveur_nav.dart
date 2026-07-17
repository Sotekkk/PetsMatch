import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/planning/planning_jour_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/planning_mois_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_list_page.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/eleveur/inventaire/inventaire_page.dart';
import 'package:PetsMatch/pages/eleveur/eleveur_home.dart';
import 'package:PetsMatch/pages/pro/restauration/restauration_home_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart';
import 'package:PetsMatch/pages/eleveur/admin/contrat_reservation.dart';
import 'package:PetsMatch/pages/particulier/mes_contrats_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/widgets/profile_switcher_header.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/communaute/communaute_hub_page.dart';
import 'package:PetsMatch/pages/lieux/mon_etablissement_page.dart';
import 'package:PetsMatch/pages/pro/restauration/inscription_restauration_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart';
import 'package:PetsMatch/pages/pro/pension_chenil_page.dart';
import 'package:PetsMatch/pages/pro/pension_planning_page.dart';
import 'package:PetsMatch/pages/pro/pension_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/fiches_pension_page.dart';
import 'package:PetsMatch/pages/pro/pension_documents_page.dart';
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart';
import 'package:PetsMatch/pages/pro/pension_factures_page.dart';
import 'package:PetsMatch/pages/pro/garde_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/registre_visites_page.dart';
import 'package:PetsMatch/pages/pro/cles_clients_page.dart';
import 'package:PetsMatch/pages/pro/tarifs_clients_page.dart';
import 'package:PetsMatch/pages/pro/tournee_page.dart';
import 'package:PetsMatch/pages/pro/taxi_tournee_page.dart';
import 'package:PetsMatch/pages/pro/taxi_trajets_page.dart';
import 'package:PetsMatch/pages/pro/taxi_factures_page.dart';
import 'package:PetsMatch/pages/pro/photographe_prestations_page.dart';
import 'package:PetsMatch/pages/pro/photographe_factures_page.dart';
import 'package:PetsMatch/pages/pro/photographe_dashboard_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_prestations_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_employes_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_planning_employes_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_factures_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_dashboard_page.dart';
import 'package:PetsMatch/pages/pro/education_planning_page.dart';
import 'package:PetsMatch/pages/pro/education_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/education_devis_page.dart';
import 'package:PetsMatch/pages/pro/vet_patients_page.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/eleveur/user_elevage_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/pages/marketplace/marketplace_page.dart';
import 'package:PetsMatch/pages/notifications_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_eleveur.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class EleveurNav extends StatefulWidget {
  final VoidCallback? onAdminTap;
  const EleveurNav({super.key, this.onAdminTap});
  @override
  State<EleveurNav> createState() => _EleveurNavState();
}

class _EleveurNavState extends State<EleveurNav> {
  int _selectedIndex = 0;
  String _planCode   = 'free';
  String _pensionPlanCode = 'free';
  String _educationPlanCode = 'free';
  String _gardePlanCode = 'free';

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }


  Future<void> _loadPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (User_Info.catPro == 'pension') {
      final code = await PlanService.getPensionPlanCode(uid);
      if (mounted) setState(() => _pensionPlanCode = code);
      return;
    }
    if (User_Info.catPro == 'education') {
      final code = await PlanService.getEducationPlanCode(uid);
      if (mounted) setState(() => _educationPlanCode = code);
      return;
    }
    if (User_Info.catPro == 'garde') {
      final code = await PlanService.getGardePlanCode(uid);
      if (mounted) setState(() => _gardePlanCode = code);
      return;
    }
    final code = await PlanService.getPlanCode(uid);
    if (mounted) setState(() => _planCode = code);
  }

  Widget _tabContent(int index) => switch (index) {
    1 => MessagePage(),
    2 => const NotificationsPage(),
    3 => AgendaPage(onBack: () => setState(() => _selectedIndex = 0)),
    _ => User_Info.catPro == 'restauration'
        ? const RestaurationHomePage()
        : const EleveurHomePage(),
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
      },
      child: Scaffold(
      key: drawerKey,
      endDrawer: _buildEndDrawer(context),
      body: _tabContent(_selectedIndex),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: _dark,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 5)],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Accueil',
                  active: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                MsgBadge(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  active: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                NotifBadge(
                  icon: Icons.notifications_outlined,
                  activeIcon: Icons.notifications,
                  active: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month_rounded,
                  label: 'Agenda',
                  active: _selectedIndex == 3,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
                _NavItem(
                  icon: Icons.menu,
                  activeIcon: Icons.menu,
                  label: 'Menu',
                  active: false,
                  onTap: () => drawerKey.currentState?.openEndDrawer(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildEndDrawer(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.82,
      backgroundColor: Colors.white,
      child: Column(
        children: [
          ProfileSwitcherHeader(
            onClose: () => drawerKey.currentState?.closeEndDrawer(),
            onEditTap: () {
              drawerKey.currentState?.closeEndDrawer();
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => User_Info.isPro
                    ? ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null)
                    : const ProfilEleveurEditPage(),
              ));
            },
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DrawerItem(
                  icon: Icons.home_outlined,
                  label: 'Accueil',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _selectedIndex = 0);
                  },
                ),
                if (!User_Info.isPro) ...[
                  _DrawerSection(
                    icon: Icons.pets,
                    label: 'Mon Élevage',
                    children: [
                      _DrawerSubItem(
                        label: 'Mes Animaux',
                        icon: Icons.cruelty_free_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const MesAnimauxPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Agenda',
                        icon: Icons.calendar_month_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _selectedIndex = 3);
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Protocoles',
                        icon: Icons.event_note_outlined,
                        locked: _planCode != 'premium',
                        badgeLabel: 'Premium',
                        onTap: () {
                          Navigator.pop(context);
                          if (_planCode != 'premium') {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const AbonnementPage(),
                            ));
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const PlanningMoisPage(),
                            ));
                          }
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Suivi sanitaire',
                        icon: Icons.health_and_safety_outlined,
                        locked: _planCode == 'free',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _planCode == 'free'
                                ? const AbonnementPage()
                                : const RegistreSanitairePage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Inventaire',
                        icon: Icons.inventory_2_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const InventairePage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Mes Employés',
                        icon: Icons.groups_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const EmployesPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Entrée - Sortie',
                        icon: Icons.swap_horiz_outlined,
                        locked: _planCode == 'free',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _planCode == 'free'
                                ? const AbonnementPage()
                                : const RegistreEntreeSortiePage(),
                          ));
                        },
                      ),
                    ],
                  ),
                  _DrawerSection(
                    icon: Icons.folder_outlined,
                    label: 'Administratif',
                    children: [
                      _DrawerSubItem(
                        label: 'Mes Contrats',
                        icon: Icons.description_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ContratReservationPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Mes Achats',
                        icon: Icons.shopping_bag_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const MesContratsParticulierPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Facturation',
                        icon: Icons.receipt_long_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const FacturationPage(),
                          ));
                        },
                      ),
                    ],
                  ),
                  _DrawerSection(
                    icon: Icons.campaign_outlined,
                    label: 'Annonces',
                    children: [
                      _DrawerSubItem(
                        label: 'Mes Annonces',
                        icon: Icons.campaign_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const MesAnnoncesPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Déposer une annonce',
                        icon: Icons.add_circle_outline_rounded,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const CreateAnnoncePage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Trouver un compagnon',
                        icon: Icons.pets_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const TrouverCompagnonPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Saillie',
                        icon: Icons.diversity_1_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const AnnoncesPublicPage(typeFilter: 'saillie'),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Carte des élevages',
                        icon: Icons.map_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const EleveurListPage(),
                          ));
                        },
                      ),
                    ],
                  ),
                ],
                _DrawerSection(
                  icon: Icons.search_off_rounded,
                  label: 'Animaux perdus / trouvés',
                  children: [
                    _DrawerSubItem(
                      label: 'Mes déclarations perdues/trouvées',
                      icon: Icons.manage_search_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const MesAlertesPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Animaux perdus/trouvés',
                      icon: Icons.location_searching,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnimauxPerdusPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'J\'ai trouvé un animal',
                      icon: Icons.pets,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnimalTrouveFormPage(),
                        ));
                      },
                    ),
                  ],
                ),

                if (!User_Info.isPro)
                  _DrawerItem(
                    icon: Icons.favorite_border,
                    label: 'Favoris',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => LikesPage(),
                      ));
                    },
                  ),
                _DrawerItem(
                  icon: Icons.storefront_outlined,
                  label: 'Annuaire professionnel',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ServicesPage(),
                    ));
                  },
                ),
                _DrawerItem(
                  icon: Icons.groups_outlined,
                  label: 'Communauté',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const CommunauteHubPage(),
                    ));
                  },
                ),
                _DrawerItem(
                  icon: Icons.local_offer_outlined,
                  label: 'Marketplace',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const MarketplacePage(),
                    ));
                  },
                ),
                if (User_Info.isPro && User_Info.catPro == 'restauration') ...[
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                    child: Text('Espace hébergement / restauration',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 11, color: Colors.grey.shade500, letterSpacing: 0.8)),
                  ),
                  _DrawerItem(
                    icon: Icons.storefront_outlined,
                    label: 'Mes établissements',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const MonEtablissementPage(),
                      ));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.person_outline,
                    label: 'Mon profil établissement',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const InscriptionRestaurationDetailPage(),
                      ));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Mon abonnement',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const AbonnementPage(),
                      ));
                    },
                  ),
                ],
                if (User_Info.isPro && User_Info.catPro != 'restauration') ...[
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                    child: Text('Espace pro',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 11, color: Colors.grey.shade500, letterSpacing: 0.8)),
                  ),
                  _DrawerItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'Mon agenda RDV',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const ProAgendaPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'pension') _DrawerItem(
                    icon: Icons.home_work_outlined,
                    label: 'Registre pension',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const RegistrePensionPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'veterinaire') _DrawerItem(
                    icon: Icons.medical_information_outlined,
                    label: 'Mes patients',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const VetPatientsPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'education') _DrawerItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'Planning des cours',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const EducationPlanningPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'education') _DrawerItem(
                    icon: Icons.request_quote_outlined,
                    label: 'Devis',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const DevisPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'education') _DrawerItem(
                    icon: Icons.groups_outlined,
                    label: 'Mes Employés',
                    locked: _educationPlanCode == 'free',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => _educationPlanCode == 'free'
                            ? const EducationAbonnementPage()
                            : const EmployesPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'education') _DrawerItem(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Mon abonnement',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const EducationAbonnementPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'sante' || User_Info.catPro == 'education' || User_Info.catPro == 'garde' || User_Info.catPro == 'marechal_ferrant' || User_Info.catPro == 'photographe') _DrawerItem(
                    icon: User_Info.catPro == 'education'
                        ? Icons.psychology_outlined
                        : User_Info.catPro == 'garde'
                            ? Icons.directions_walk_outlined
                            : User_Info.catPro == 'marechal_ferrant'
                                ? Icons.handyman_outlined
                                : User_Info.catPro == 'photographe'
                                    ? Icons.people_outline
                                    : Icons.self_improvement_outlined,
                    label: User_Info.catPro == 'education'
                        ? 'Mes animaux suivis'
                        : User_Info.catPro == 'garde'
                            ? 'Mes animaux en garde'
                            : User_Info.catPro == 'marechal_ferrant'
                                ? 'Mes équidés suivis'
                                : User_Info.catPro == 'photographe'
                                    ? 'Mes clients'
                                    : 'Mes patients',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const ProClientsPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'pension') _DrawerItem(
                    icon: Icons.folder_shared_outlined,
                    label: 'Fiches accessibles',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const FichesPensionPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'pension') _DrawerItem(
                    icon: Icons.folder_outlined,
                    label: 'Documents',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const PensionDocumentsPage(),
                      ));
                    },
                  ),
                  if (User_Info.catPro == 'pension') ...[
                    _DrawerItem(
                      icon: Icons.home_work_outlined,
                      label: 'Logements / Chenil',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PensionChenilPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.calendar_view_week_outlined,
                      label: 'Planning occupation',
                      locked: _pensionPlanCode == 'free',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _pensionPlanCode == 'free'
                              ? const PensionAbonnementPage()
                              : const PensionPlanningPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.inventory_2_outlined,
                      label: 'Inventaire',
                      locked: _pensionPlanCode == 'free',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _pensionPlanCode == 'free'
                              ? const PensionAbonnementPage()
                              : const InventairePage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.event_note_outlined,
                      label: 'Protocoles / Tâches',
                      locked: _pensionPlanCode == 'free',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _pensionPlanCode == 'free'
                              ? const PensionAbonnementPage()
                              : const PlanTemplateListPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.euro_outlined,
                      label: 'Tarifs',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PensionTarifsPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Mes Factures',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PensionFacturesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.groups_outlined,
                      label: 'Mes Employés',
                      locked: _pensionPlanCode == 'free',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _pensionPlanCode == 'free'
                              ? const PensionAbonnementPage()
                              : const EmployesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Mon abonnement',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PensionAbonnementPage(),
                        ));
                      },
                    ),
                  ],
                  if (User_Info.catPro == 'garde') ...[
                    _DrawerItem(
                      icon: Icons.checklist_outlined,
                      label: 'Registre visites',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const RegistreVisitesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.route_outlined,
                      label: 'Ma tournée',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TourneePage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.request_quote_outlined,
                      label: 'Devis',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const DevisPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.vpn_key_outlined,
                      label: 'Gestion des clés',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ClesClientsPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.sell_outlined,
                      label: 'Tarifs clients',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TarifsClientsPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.inventory_2_outlined,
                      label: 'Inventaire',
                      locked: _gardePlanCode == 'free',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _gardePlanCode == 'free'
                              ? const GardeAbonnementPage()
                              : const InventairePage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.event_note_outlined,
                      label: 'Protocoles / Tâches',
                      locked: _gardePlanCode == 'free',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _gardePlanCode == 'free'
                              ? const GardeAbonnementPage()
                              : const PlanTemplateListPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.groups_outlined,
                      label: 'Mes Employés',
                      locked: _gardePlanCode == 'free',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _gardePlanCode == 'free'
                              ? const GardeAbonnementPage()
                              : const EmployesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Facturation',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const FacturationPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Mon abonnement',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const GardeAbonnementPage(),
                        ));
                      },
                    ),
                  ],
                  if (User_Info.catPro == 'taxi_animalier') ...[
                    _DrawerItem(
                      icon: Icons.checklist_outlined,
                      label: 'Mes trajets',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TaxiTrajetsPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.route_outlined,
                      label: 'Ma tournée',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TaxiTourneePage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Mes factures',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TaxiFacturesPage(),
                        ));
                      },
                    ),
                  ],
                  if (User_Info.catPro == 'photographe') ...[
                    _DrawerItem(
                      icon: Icons.camera_alt_outlined,
                      label: 'Mes prestations',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PhotographePrestationsPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Mes factures',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PhotographeFacturesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.dashboard_outlined,
                      label: 'Tableau de bord',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PhotographeDashboardPage(),
                        ));
                      },
                    ),
                  ],
                  if (User_Info.catPro == 'toilettage') ...[
                    _DrawerItem(
                      icon: Icons.content_cut,
                      label: 'Mes prestations',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ToilettagePrestationsPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.groups_outlined,
                      label: 'Mes employés',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ToilettageEmployesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.calendar_view_day_outlined,
                      label: 'Planning employés',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ToilettagePlanningEmployesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Mes factures',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ToilettageFacturesPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.bar_chart_outlined,
                      label: 'Tableau de bord',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ToilettageDashboardPage(),
                        ));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Mon abonnement',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ToilettageAbonnementPage(),
                        ));
                      },
                    ),
                  ],
                ],
                const Divider(height: 24),
                _DrawerItem(
                  icon: Icons.person_outline,
                  label: 'Mon Profil',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => User_Info.isPro
                          ? ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null)
                          : const ProfilEleveurEditPage(),
                    ));
                  },
                ),
                if (User_Info.catPro == 'restauration') ...[
                  const Divider(height: 8),
                  _DrawerItem(
                    icon: Icons.store_outlined,
                    label: 'Mon Établissement',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const MonEtablissementPage()));
                    },
                  ),
                ],
                const Divider(height: 8),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: 'Paramètres',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const SettingsMainPage(),
                    ));
                  },
                ),
                if (widget.onAdminTap != null) ...[
                  const Divider(height: 8),
                  _DrawerItem(
                    icon: User_Info.isAdmin ? Icons.admin_panel_settings : Icons.swap_horiz_outlined,
                    label: User_Info.isAdmin ? 'Administration' : 'Prévisualiser un rôle',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onAdminTap!();
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.gavel_outlined, color: Color(0xFF9CA3AF), size: 20),
            title: const Text('CGU & Confidentialité',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF))),
            onTap: () async {
              await launchUrl(Uri.parse('https://www.petsmatchapp.com/cgu'), mode: LaunchMode.externalApplication);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
            title: const Text('Déconnexion',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15, color: Colors.redAccent)),
            onTap: () async {
              // Ne pas naviguer manuellement : AuthWrapper (racine de l'app) écoute
              // authStateChanges() et bascule seul sur WelcomePage. Un pushAndRemoveUntil
              // ici détruirait cet AuthWrapper racine et casserait la reconnexion suivante
              // (retour en boucle sur l'écran de bienvenue après un nouveau login).
              await FirebaseAuth.instance.signOut();
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool locked;
  final String badgeLabel;

  const _DrawerItem({
    required this.icon, required this.label, required this.onTap,
    this.locked = false, this.badgeLabel = 'Pro',
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: locked ? Colors.grey.shade400 : const Color(0xFF0C5C6C), size: 22),
      title: Row(children: [
        Flexible(child: Text(label,
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15,
                color: locked ? Colors.grey.shade400 : const Color(0xFF1F2A2E)))),
        if (locked) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(badgeLabel,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    fontFamily: 'Galey', color: Color(0xFFD97706))),
          ),
        ],
      ]),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
    );
  }
}

class _DrawerSection extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Widget> children;

  const _DrawerSection({required this.icon, required this.label, required this.children});

  @override
  State<_DrawerSection> createState() => _DrawerSectionState();
}

class _DrawerSectionState extends State<_DrawerSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(widget.icon, color: const Color(0xFF0C5C6C), size: 22),
          title: Text(widget.label,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15)),
          trailing: AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0C5C6C)),
          ),
          onTap: () => setState(() => _expanded = !_expanded),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            color: const Color(0xFFF8F8F6),
            child: Column(children: widget.children),
          ),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

class _DrawerSubItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool locked;
  final String badgeLabel;

  const _DrawerSubItem({
    required this.label, required this.icon, required this.onTap,
    this.locked = false, this.badgeLabel = 'Pro',
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 22),
      title: Row(
        children: [
          Icon(icon, color: locked ? Colors.grey.shade400 : const Color(0xFF6E9E57), size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
              color: locked ? Colors.grey.shade400 : const Color(0xFF1F2A2E))),
          if (locked) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(badgeLabel,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                      fontFamily: 'Galey', color: Color(0xFFD97706))),
            ),
          ],
        ],
      ),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              color: active ? const Color(0xFF6E9E57) : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Galey',
                color: active ? const Color(0xFF6E9E57) : Colors.grey,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
