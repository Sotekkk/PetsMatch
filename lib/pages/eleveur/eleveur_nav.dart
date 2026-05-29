import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/eleveur_home.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart';
import 'package:PetsMatch/pages/eleveur/admin/contrat_reservation.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart';
import 'package:PetsMatch/pages/eleveur/user_elevage_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/pages/notifications_page.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EleveurNav extends StatefulWidget {
  final VoidCallback? onAdminTap;
  const EleveurNav({super.key, this.onAdminTap});
  @override
  State<EleveurNav> createState() => _EleveurNavState();
}

class _EleveurNavState extends State<EleveurNav> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);

  Widget _tabContent(int index) => switch (index) {
    1 => MessagePage(),
    2 => const NotificationsPage(),
    _ => const EleveurHomePage(),
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
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: 'Messages',
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
                        label: 'Facturation',
                        icon: Icons.receipt_long_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const FacturationPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Contrats',
                        icon: Icons.description_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ContratReservationPage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Suivi sanitaire',
                        icon: Icons.health_and_safety_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const RegistreSanitairePage(),
                          ));
                        },
                      ),
                      _DrawerSubItem(
                        label: 'Entrées / Sorties',
                        icon: Icons.swap_horiz_outlined,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const RegistreEntreeSortiePage(),
                          ));
                        },
                      ),
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
                    ],
                  ),
                  _DrawerSection(
                    icon: Icons.campaign_outlined,
                    label: 'Annonces',
                    children: [
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
                if (User_Info.isPro) ...[
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
                  if (User_Info.catPro == 'garde') _DrawerItem(
                    icon: Icons.home_work_outlined,
                    label: 'Registre pension',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const RegistrePensionPage(),
                      ));
                    },
                  ),
                ],
                const Divider(height: 24),
                _DrawerItem(
                  icon: Icons.person_outline,
                  label: 'Mon Profil',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => User_Info.isPro
                          ? const ProProfileEditPage()
                          : const ProfilEleveurEditPage(),
                    ));
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
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15, color: Colors.redAccent)),
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

class _DrawerHeader extends StatefulWidget {
  @override
  State<_DrawerHeader> createState() => _DrawerHeaderState();
}

class _DrawerHeaderState extends State<_DrawerHeader> {
  String? _name;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    final data = doc.data() ?? {};
    setState(() {
      _name = data['nameElevage'] ?? data['firstname'] ?? 'Mon élevage';
      _photoUrl = data['profilePictureUrlElevage'] ?? data['profilePictureUrl'];
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
                builder: (_) => User_Info.isPro ? const ProProfileEditPage() : const ProfilEleveurEditPage(),
              ));
            },
            child: CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFA7C79A),
              backgroundImage: _photoUrl != null ? CachedNetworkImageProvider(_photoUrl!) : null,
              child: _photoUrl == null ? const Icon(Icons.pets, color: Colors.white, size: 28) : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name ?? '...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.verified, color: Color(0xFFA7C79A), size: 14),
                    const SizedBox(width: 4),
                    Text(
                      User_Info.isPro ? 'Professionnel' : 'Éleveur vérifié',
                      style: const TextStyle(color: Color(0xFFEEF5EA), fontSize: 12, fontFamily: 'Galey'),
                    ),
                  ],
                ),
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
