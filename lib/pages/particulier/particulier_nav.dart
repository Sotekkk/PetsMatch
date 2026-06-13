import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/association/associations_list_page.dart';
import 'package:PetsMatch/pages/association/post/annonces_asso_feed_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/marketplace/marketplace_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/particulier/particulier_home.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:PetsMatch/pages/notifications_page.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/widgets/profile_switcher_header.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class ParticulierNav extends StatefulWidget {
  final VoidCallback? onAdminTap;
  const ParticulierNav({super.key, this.onAdminTap});
  @override
  State<ParticulierNav> createState() => _ParticulierNavState();
}

class _ParticulierNavState extends State<ParticulierNav> {
  int _selectedIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isEmploye = false;

  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);

  @override
  void initState() {
    super.initState();
    _checkIsEmploye();
  }

  Future<void> _checkIsEmploye() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final rows = await Supabase.instance.client
        .from('employes')
        .select('id')
        .eq('uid_employe', uid)
        .eq('actif', true)
        .limit(1);
    if (mounted) setState(() => _isEmploye = (rows as List).isNotEmpty);
  }

  Widget _tabContent(int index) => switch (index) {
        1 => MessagePage(),
        2 => const NotificationsPage(),
        3 => AgendaPage(onBack: () => setState(() => _selectedIndex = 0)),
        _ => const ParticulierHomePage(),
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
      endDrawer: _buildDrawer(context),
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
                  icon: Icons.home_outlined, activeIcon: Icons.home,
                  label: 'Accueil', active: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                _NavItem(
                  icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble,
                  label: 'Messages', active: _selectedIndex == 1,
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
                  icon: Icons.menu, activeIcon: Icons.menu,
                  label: 'Menu', active: false,
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

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.82,
      backgroundColor: Colors.white,
      child: Column(
        children: [
          ProfileSwitcherHeader(
            onClose: () => _scaffoldKey.currentState?.closeDrawer(),
            onEditTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const UserParticulierFeed(initialTab: 0),
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
                  icon: Icons.person_outline,
                  label: 'Mon Profil',
                  initiallyExpanded: true,
                  children: [
                    _DrawerSubItem(
                      label: 'Mon Profil',
                      icon: Icons.edit_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const UserParticulierFeed(initialTab: 0),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Mes Animaux',
                      icon: Icons.pets_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const UserParticulierFeed(initialTab: 1),
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
                _DrawerSection(
                  icon: Icons.campaign_outlined,
                  label: 'Annonces',
                  children: [
                    _DrawerSubItem(
                      label: 'Trouver un compagnon',
                      icon: Icons.favorite_border,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TrouverCompagnonPage(),
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
                    _DrawerSubItem(
                      label: 'Annonces d\'adoption',
                      icon: Icons.favorite_border,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnnoncesAssoFeedPage(),
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
                if (_isEmploye)
                  _DrawerItem(
                    icon: Icons.work_outline,
                    label: 'Mes Employeurs',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const MesEmployeursPage(),
                      ));
                    },
                  ),
                _DrawerItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'Mon Agenda',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _selectedIndex = 3);
                  },
                ),
                _DrawerItem(
                  icon: Icons.favorite_border,
                  label: 'Favoris',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => LikesPage()));
                  },
                ),
                _DrawerItem(
                  icon: Icons.storefront_outlined,
                  label: 'Services',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicesPage()));
                  },
                ),
                _DrawerItem(
                  icon: Icons.local_offer_outlined,
                  label: 'Marketplace',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplacePage()));
                  },
                ),
                const Divider(height: 24),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: 'Paramètres',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsMainPage()));
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
              await launchUrl(Uri.parse('https://petsmatch.fr/cgu'), mode: LaunchMode.externalApplication);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
            title: const Text('Déconnexion',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: Colors.redAccent)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => WelcomePage()),
                  (route) => false,
                );
              }
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

// ── Shared nav/drawer widgets ─────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon, required this.activeIcon,
    required this.label, required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? activeIcon : icon,
                  color: active ? const Color(0xFF6E9E57) : Colors.grey, size: 24),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Galey',
                      color: active ? const Color(0xFF6E9E57) : Colors.grey,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      );
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: const Color(0xFF0C5C6C), size: 22),
        title: Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15)),
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      );
}

class _DrawerSection extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _DrawerSection({
    required this.icon, required this.label, required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<_DrawerSection> createState() => _DrawerSectionState();
}

class _DrawerSectionState extends State<_DrawerSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) => Column(
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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

class _DrawerSubItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DrawerSubItem({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const SizedBox(width: 22),
        title: Row(
          children: [
            Icon(icon, color: const Color(0xFF6E9E57), size: 18),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E))),
          ],
        ),
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      );
}
