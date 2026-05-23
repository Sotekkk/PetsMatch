import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/admin/admin_panel.dart';
import 'package:PetsMatch/pages/eleveur/eleveur_nav.dart';
import 'package:PetsMatch/pages/particulier/particulier_nav.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/eleveur/user_elevage_feed.dart';
import 'package:PetsMatch/pages/services/services_page.dart';

import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class BottomNav extends StatefulWidget {
  @override
  _BottomNavState createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  int _selectedIndex = 0;
  // '' = rôles réels, 'eleveur', 'pro', 'particulier'
  String _previewRole = '';

  bool get _asElevage =>
      _previewRole == 'eleveur' ||
      (_previewRole.isEmpty && (User_Info.isElevage || User_Info.isPro));

  bool get _asParticulier =>
      _previewRole == 'particulier' ||
      (_previewRole.isEmpty && !User_Info.isElevage && !User_Info.isPro);

  Widget _getPage(int index) {
    switch (index) {
      case 0: return FeedPage();
      case 1: return LikesPage();
      case 2: return MessagePage();
      case 3: return const EleveurListPage();
      case 4: return const ServicesPage();
      case 5: return _asElevage ? UserElevageFeed() : UserParticulierFeed();
      default: return FeedPage();
    }
  }

  void _onItemTapped(int index) {
    // Garde l'index valide si le nb d'items change selon le rôle
    setState(() => _selectedIndex = index);
  }

  void _showAdminMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Panel admin
            ListTile(
              leading: const Icon(Icons.admin_panel_settings,
                  color: Color(0xFF6E9E57)),
              title: const Text('Panel Admin',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => AdminPanel()),
                );
              },
            ),

            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Voir l\'app en tant que…',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontFamily: 'Galey')),
            ),

            _PreviewTile(
              icon: Icons.pets,
              label: 'Éleveur',
              active: _previewRole == 'eleveur',
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _previewRole = _previewRole == 'eleveur' ? '' : 'eleveur';
                  _selectedIndex = 0;
                });
              },
            ),
            _PreviewTile(
              icon: Icons.work_outline,
              label: 'Professionnel',
              active: _previewRole == 'pro',
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _previewRole = _previewRole == 'pro' ? '' : 'pro';
                  _selectedIndex = 0;
                });
              },
            ),
            _PreviewTile(
              icon: Icons.person_outline,
              label: 'Particulier',
              active: _previewRole == 'particulier',
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _previewRole = _previewRole == 'particulier' ? '' : 'particulier';
                  _selectedIndex = 0;
                });
              },
            ),

            if (_previewRole.isNotEmpty) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.grey),
                title: const Text('Revenir à mes rôles réels',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _previewRole = '';
                    _selectedIndex = 0;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewBanner(String label) => Positioned(
        top: 0, left: 0, right: 0,
        child: SafeArea(
          child: Container(
            color: const Color(0xE66E9E57),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.visibility, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text('Vue : $label',
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Galey',
                        fontSize: 12, fontWeight: FontWeight.w500)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() { _previewRole = ''; _selectedIndex = 0; }),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Éleveurs : navigation dédiée 3 icônes + tiroir
    if (_asElevage) {
      return Stack(
        children: [
          EleveurNav(onAdminTap: User_Info.isAdmin ? _showAdminMenu : null),
          if (_previewRole == 'eleveur') _previewBanner('Éleveur'),
        ],
      );
    }

    // Particuliers : navigation dédiée 3 icônes + tiroir
    if (_asParticulier) {
      return Stack(
        children: [
          ParticulierNav(onAdminTap: User_Info.isAdmin ? _showAdminMenu : null),
          if (_previewRole == 'particulier') _previewBanner('Particulier'),
        ],
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _getPage(_selectedIndex),
          // Bandeau de prévisualisation
          if (_previewRole.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  color: const Color(0xE66E9E57),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Vue : ${_previewRole[0].toUpperCase()}${_previewRole.substring(1)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Galey',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() {
                          _previewRole = '';
                          _selectedIndex = 0;
                        }),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: User_Info.isAdmin
          ? FloatingActionButton.small(
              heroTag: 'admin_fab',
              backgroundColor: _previewRole.isNotEmpty
                  ? const Color(0xFF6E9E57)
                  : const Color(0xFF6E9E57),
              tooltip: 'Admin',
              onPressed: _showAdminMenu,
              child: Icon(
                _previewRole.isNotEmpty
                    ? Icons.visibility
                    : Icons.admin_panel_settings,
                color: Colors.white,
                size: 20,
              ),
            )
          : null,
      bottomNavigationBar: Container(
        height: UTILS.calculHeight(102, UTILS.heightReference(context)),
        decoration: const BoxDecoration(
          color: Color(0xFF1F2A2E),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          child: BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/icon/home.png')),
                label: 'Accueil',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/icon/fav.png')),
                label: 'Favoris',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/icon/message.png')),
                label: 'Messages',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.pets),
                label: 'Élevages',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.storefront_outlined),
                label: 'Services',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.person),
                label: 'Profil',
              ),
            ],
            currentIndex: _selectedIndex.clamp(0, 5),
            selectedItemColor: const Color(0xFF6E9E57),
            unselectedItemColor: Colors.grey,
            onTap: _onItemTapped,
            backgroundColor: Colors.transparent,
            type: BottomNavigationBarType.fixed,
          ),
        ),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PreviewTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: active
              ? const Color(0xFF6E9E57)
              : Colors.black54),
      title: Text(label,
          style: TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500,
              color: active
                  ? const Color(0xFF6E9E57)
                  : Colors.black87)),
      trailing: active
          ? const Icon(Icons.check_circle,
              color: Color(0xFF6E9E57), size: 20)
          : null,
      onTap: onTap,
    );
  }
}
