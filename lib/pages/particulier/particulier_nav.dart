import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/particulier/particulier_home.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:PetsMatch/pages/notifications_page.dart';

class ParticulierNav extends StatefulWidget {
  final VoidCallback? onAdminTap;
  const ParticulierNav({super.key, this.onAdminTap});
  @override
  State<ParticulierNav> createState() => _ParticulierNavState();
}

class _ParticulierNavState extends State<ParticulierNav> {
  int _selectedIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);

  Widget _tabContent(int index) => switch (index) {
        1 => MessagePage(),
        2 => const NotificationsPage(),
        _ => const ParticulierHomePage(),
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
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
          _DrawerHeader(),
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
                  label: 'Animaux perdus',
                  children: [
                    _DrawerSubItem(
                      label: 'Gérer mes animaux perdus',
                      icon: Icons.manage_search_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const MesAlertesPage(),
                        ));
                      },
                    ),
                    _DrawerSubItem(
                      label: 'Voir les animaux perdus',
                      icon: Icons.location_searching,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnimauxPerdusPage(),
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
                          builder: (_) => const AnnoncesFeedPage(initialTypeFilter: 'vente'),
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
                const Divider(height: 24),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: 'Paramètres',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsMainPage()));
                  },
                ),
                if (User_Info.isAdmin && widget.onAdminTap != null) ...[
                  const Divider(height: 8),
                  _DrawerItem(
                    icon: Icons.admin_panel_settings,
                    label: 'Administration',
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
            leading: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
            title: const Text('Déconnexion',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: Colors.redAccent)),
            onTap: () async {
              Navigator.pop(context);
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

// ── Drawer header ─────────────────────────────────────────────────────────────

class _DrawerHeader extends StatefulWidget {
  @override
  State<_DrawerHeader> createState() => _DrawerHeaderState();
}

class _DrawerHeaderState extends State<_DrawerHeader> {
  String? _name;
  String? _photoUrl;
  String? _ville;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    final d = doc.data() ?? {};
    setState(() {
      _name = '${d['firstname'] ?? ''} ${d['lastname'] ?? ''}'.trim();
      _photoUrl = d['profilePictureUrl'];
      _ville = d['ville'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C5C6C),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const UserParticulierFeed(initialTab: 0)));
            },
            child: CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF5B9EAA),
              backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(_photoUrl!)
                  : null,
              child: (_photoUrl == null || _photoUrl!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white, size: 28)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name?.isNotEmpty == true ? _name! : User_Info.firstname,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_ville != null && _ville!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFFB2D8DE), size: 13),
                      const SizedBox(width: 3),
                      Text(_ville!,
                          style: const TextStyle(
                              color: Color(0xFFCCE8EE), fontSize: 12, fontFamily: 'Galey')),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
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
