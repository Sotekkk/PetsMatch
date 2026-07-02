import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/association/admin/chenil_planning_page.dart';
import 'package:PetsMatch/pages/association/animaux/mes_animaux_asso.dart';
import 'package:PetsMatch/pages/association/association_home.dart';
import 'package:PetsMatch/pages/association/equipe/equipe_page.dart';
import 'package:PetsMatch/pages/association/familles_accueil/familles_accueil_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/certificats_engagement_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart';
import 'package:PetsMatch/pages/association/admin/contrat_adoption_page.dart';
import 'package:PetsMatch/pages/eleveur/inventaire/inventaire_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_list_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/planning_mois_page.dart';
import 'package:PetsMatch/pages/association/associations_list_page.dart';
import 'package:PetsMatch/pages/communaute/communaute_hub_page.dart';
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/marketplace/marketplace_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/notifications_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/association/profil_association_edit.dart';
import 'package:PetsMatch/widgets/profile_switcher_header.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AssociationNav extends StatefulWidget {
  final VoidCallback? onAdminTap;
  const AssociationNav({super.key, this.onAdminTap});
  @override
  State<AssociationNav> createState() => _AssociationNavState();
}

class _AssociationNavState extends State<AssociationNav> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _dark = Color(0xFF1F2A2E);

  Widget _tabContent(int index) => switch (index) {
    1 => MessagePage(),
    2 => const NotificationsPage(),
    3 => AgendaPage(onBack: () => setState(() => _selectedIndex = 0), isAssociation: true),
    _ => const AssociationHomePage(),
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
      },
      child: Scaffold(
        key: _scaffoldKey,
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
                  _NavItem(
                    icon: Icons.notifications_outlined,
                    activeIcon: Icons.notifications,
                    label: 'Alertes',
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
                    onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
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
            onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
            onEditTap: () {
              _scaffoldKey.currentState?.closeEndDrawer();
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const ProfilAssociationEditPage(),
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
                _DrawerSection(
                  icon: Icons.favorite_outline,
                  label: 'Mon Association',
                  children: [
                    _DrawerSubItem(
                      label: 'Mes Animaux',
                      icon: Icons.pets_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const MesAnimauxAssoPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Familles d\'accueil',
                      icon: Icons.house_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const FamillesAccueilPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Chenil / Planning',
                      icon: Icons.home_work_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ChenilPlanningPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'RDV visites d\'adoption',
                      icon: Icons.event_available_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ProAgendaPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Contrat d\'adoption',
                      icon: Icons.handshake_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ContratAdoptionPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Certificats d\'engagement',
                      icon: Icons.edit_document,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const CertificatsEngagementPage(isAssociation: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Suivi sanitaire',
                      icon: Icons.health_and_safety_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const RegistreSanitairePage(isAssociation: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Entrées / Sorties',
                      icon: Icons.swap_horiz_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const RegistreEntreeSortiePage(isAssociation: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Mes Annonces',
                      icon: Icons.campaign_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const MesAnnoncesPage(isAssociation: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Équipe',
                      icon: Icons.groups_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const EquipePage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Planning du mois',
                      icon: Icons.calendar_month_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PlanningMoisPage(isAssociation: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Modèles de routines',
                      icon: Icons.repeat_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const PlanTemplateListPage(isAssociation: true),
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
                  ],
                ),
                _DrawerSection(
                  icon: Icons.campaign_outlined,
                  label: 'Annonces',
                  children: [
                    _DrawerSubItem(
                      label: 'Déposer une annonce',
                      icon: Icons.add_circle_outline_rounded,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const CreateAnnonceAssoPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Annonces d\'adoption',
                      icon: Icons.pets_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnnoncesPublicPage(isAssociation: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Fil adoption associations',
                      icon: Icons.favorite_border,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnnoncesFeedPage(isAssociationFeed: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Carte des associations',
                      icon: Icons.map_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AssociationsListPage(),
                        ));
                      },
                    ),
                  ],
                ),
                _DrawerSection(
                  icon: Icons.search_off_rounded,
                  label: 'Perdus & Trouvés',
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
                _DrawerItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'Mon Agenda',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AgendaPage(isAssociation: true),
                    ));
                  },
                ),
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
                  label: 'Services',
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
                _DrawerSection(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Administratif',
                  children: [
                    _DrawerSubItem(
                      label: 'Facturation',
                      icon: Icons.receipt_long_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const FacturationPage(isAssociation: true),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Contrats d\'adoption',
                      icon: Icons.handshake_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ContratAdoptionPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Documents',
                      icon: Icons.folder_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const CertificatsEngagementPage(isAssociation: true),
                        ));
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),
                _DrawerItem(
                  icon: Icons.person_outline,
                  label: 'Mon Profil',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ProfilAssociationEditPage(),
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

// ── Widgets helpers (identiques à EleveurNav) ─────────────────────────────────

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF0C5C6C), size: 22),
      title: Text(label,
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15)),
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

  const _DrawerSubItem({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 22),
      title: Row(
        children: [
          Icon(icon, color: const Color(0xFF6E9E57), size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E))),
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
