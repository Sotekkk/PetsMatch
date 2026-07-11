import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/admin/admin_panel.dart';
import 'package:PetsMatch/pages/association/association_nav.dart';
import 'package:PetsMatch/pages/eleveur/eleveur_nav.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_asso.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_eleveur.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_pension.dart';
import 'package:PetsMatch/pages/onboarding/onboarding_garde.dart';
import 'package:PetsMatch/pages/particulier/particulier_nav.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/eleveur/user_elevage_feed.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';

class BottomNav extends StatefulWidget {
  @override
  _BottomNavState createState() => _BottomNavState();
}

// Types de profils "pro" (hors éleveur/association/particulier) — même liste
// que User_Info.applyProfile(). Aucun profil n'a littéralement profile_type
// == 'pro' : le bouton "Professionnel" doit matcher n'importe lequel de ces
// types, sinon le switch échoue silencieusement (activeProfileId reste sur
// l'ancien profil).
const _kProTypes = {
  'veterinaire', 'para_medical', 'education', 'petsitter',
  'pension', 'promeneur', 'photographe', 'marechal_ferrant',
  'restauration',
};

class _BottomNavState extends State<BottomNav> {
  int _selectedIndex = 0;
  // '' = rôles réels, 'eleveur', 'pro', 'particulier'
  String _previewRole = '';
  // Vrai seulement si le switch vient du tiroir BottomNav (affiche le bandeau).
  // Faux si le switch vient du ProfileSwitcherHeader (switch réel, pas besoin du bandeau).
  bool _fromDrawerSwitch = false;

  // Change le profil affiché ET met à jour User_Info.activeProfileId/activeType
  // pour que toutes les pages (agenda, etc.) voient le bon profil sans paramètre supplémentaire.
  void _switchPreviewRole(String role) {
    setState(() {
      _previewRole = role;
      _fromDrawerSwitch = role.isNotEmpty;
      _selectedIndex = 0;
    });
    final profiles = User_Info.availableProfiles;
    print('[SWITCH] role=$role availableProfiles=${profiles.map((p) => "${p['profile_type']}:${p['id']}").toList()}');
    if (role.isEmpty) {
      final main = profiles.firstWhere(
        (p) => p['is_main'] == true,
        orElse: () => profiles.isNotEmpty ? profiles.first : <String, dynamic>{},
      );
      if (main.isNotEmpty) User_Info.applyProfile(main);
    } else {
      final match = profiles.firstWhere(
        (p) {
          final type = p['profile_type'] as String? ?? '';
          return role == 'pro' ? _kProTypes.contains(type) : type == role;
        },
        orElse: () => <String, dynamic>{},
      );
      print('[SWITCH] match found=${match.isNotEmpty} id=${match["id"]}');
      if (match.isNotEmpty) User_Info.applyProfile(match);
    }
    print('[SWITCH] after applyProfile: activeType=${User_Info.activeType} activeProfileId=${User_Info.activeProfileId}');
  }

  bool get _asAssociation =>
      _previewRole == 'association' ||
      (_previewRole.isEmpty && User_Info.isAssociation);

  bool get _asElevage =>
      !_asAssociation && (
        _previewRole == 'eleveur' || _previewRole == 'pro' ||
        (_previewRole.isEmpty && (User_Info.isElevage || User_Info.isPro))
      );

  bool get _asParticulier =>
      !_asAssociation && (
        _previewRole == 'particulier' ||
        (_previewRole.isEmpty && !User_Info.isElevage && !User_Info.isPro)
      );

  @override
  void initState() {
    super.initState();
    // Quand BottomNav est recréé après un switch de profil (pushAndRemoveUntil),
    // User_Info.activeType indique déjà le bon profil — on en déduit _previewRole
    // pour que le bon sous-nav s'affiche immédiatement.
    final at = User_Info.activeType;
    if (at == 'association') {
      _previewRole = 'association';
    } else if (at == 'particulier') {
      _previewRole = 'particulier';
    } else if (at.isNotEmpty) {
      // eleveur, pro, pension, photographe, etc.
      _previewRole = 'eleveur';
    }
    // '' → comportement par défaut (isAssociation / isElevage de Firebase)
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    // Charger les profils Supabase si pas encore fait (cas app restart sans LoginPage)
    if (User_Info.availableProfiles.isEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await User_Info.loadProfiles(uid);
    }

    final prefs = await SharedPreferences.getInstance();

    // Types de profils disponibles
    final assoProfiles    = User_Info.availableProfiles.where((p) => p['profile_type'] == 'association').toList();
    final pensionProfiles = User_Info.availableProfiles.where((p) => p['profile_type'] == 'pension').toList();
    final gardeProfiles   = User_Info.availableProfiles.where((p) => p['profile_type'] == 'garde').toList();
    final eleveurProfiles = User_Info.availableProfiles.where((p) =>
        !['particulier', 'association', 'pension', 'garde'].contains(p['profile_type'] ?? '')).toList();

    final hasAsso    = assoProfiles.isNotEmpty    || User_Info.isAssociation;
    final hasPension = pensionProfiles.isNotEmpty;
    final hasGarde   = gardeProfiles.isNotEmpty;
    final hasEleveur = eleveurProfiles.isNotEmpty || User_Info.isElevage ||
                       (User_Info.isPro && !hasPension && !hasGarde);

    // ── Lire les flags AVANT de les modifier ──────────────────────────────────
    bool assoDone    = prefs.getBool('onboarding_asso_done')    ?? false;
    bool pensionDone = prefs.getBool(OnboardingPensionPage.prefKey) ?? false;
    bool gardeDone   = prefs.getBool(OnboardingGardePage.prefKey) ?? false;
    bool eleveurDone = prefs.getBool('onboarding_eleveur_done') ?? false;

    // Si le profil existe déjà, on marque l'onboarding comme fait sans le montrer
    if (hasAsso    && !assoDone)    { await prefs.setBool('onboarding_asso_done',    true); assoDone    = true; }
    if (hasPension && !pensionDone) { await prefs.setBool(OnboardingPensionPage.prefKey, true); pensionDone = true; }
    if (hasGarde   && !gardeDone)   { await prefs.setBool(OnboardingGardePage.prefKey, true); gardeDone = true; }
    if (hasEleveur && !eleveurDone) { await prefs.setBool('onboarding_eleveur_done', true); eleveurDone = true; }

    // ── Vérifier ce qui reste à montrer ──────────────────────────────────────
    final needsAsso    = hasAsso    && !assoDone;
    final needsPension = hasPension && !pensionDone;
    final needsGarde   = hasGarde   && !gardeDone;
    final needsEleveur = hasEleveur && !eleveurDone;

    if (!needsAsso && !needsPension && !needsGarde && !needsEleveur) return;
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (needsAsso && (needsEleveur || needsPension || needsGarde)) {
        _showOnboardingChoice(prefs);
      } else if (needsAsso) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const OnboardingAssoPage(),
        ));
      } else if (needsPension) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const OnboardingPensionPage(),
        ));
      } else if (needsGarde) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const OnboardingGardePage(),
        ));
      } else if (needsEleveur) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const OnboardingEleveurPage(),
        ));
      }
    });
  }

  void _showOnboardingChoice(SharedPreferences prefs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Bienvenue sur PetsMatch !',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 20, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 6),
            Text('Quel espace voulez-vous découvrir en premier ?',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            _OnboardingChoiceCard(
              icon: Icons.favorite_outlined,
              color: const Color(0xFF0C5C6C),
              title: 'Espace Association',
              subtitle: 'Refuge, adoptions, équipe, familles d\'accueil',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OnboardingAssoPage(),
                  fullscreenDialog: true,
                ));
              },
            ),
            const SizedBox(height: 12),
            _OnboardingChoiceCard(
              icon: Icons.home_work_outlined,
              color: const Color(0xFF6E9E57),
              title: 'Espace Éleveur',
              subtitle: 'Animaux, annonces, planning, documents',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OnboardingEleveurPage(),
                  fullscreenDialog: true,
                ));
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                await prefs.setBool('onboarding_asso_done', true);
                await prefs.setBool('onboarding_eleveur_done', true);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text('Passer', style: TextStyle(
                  fontFamily: 'Galey', color: Colors.grey.shade400, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

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
              icon: Icons.favorite_outline,
              label: 'Association',
              active: _previewRole == 'association',
              onTap: () {
                Navigator.pop(context);
                _switchPreviewRole(_previewRole == 'association' ? '' : 'association');
              },
            ),
            _PreviewTile(
              icon: Icons.pets,
              label: 'Éleveur',
              active: _previewRole == 'eleveur',
              onTap: () {
                Navigator.pop(context);
                _switchPreviewRole(_previewRole == 'eleveur' ? '' : 'eleveur');
              },
            ),
            _PreviewTile(
              icon: Icons.work_outline,
              label: 'Professionnel',
              active: _previewRole == 'pro',
              onTap: () {
                Navigator.pop(context);
                _switchPreviewRole(_previewRole == 'pro' ? '' : 'pro');
              },
            ),
            _PreviewTile(
              icon: Icons.person_outline,
              label: 'Particulier',
              active: _previewRole == 'particulier',
              onTap: () {
                Navigator.pop(context);
                _switchPreviewRole(_previewRole == 'particulier' ? '' : 'particulier');
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
                  _switchPreviewRole('');
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
    // Associations : navigation dédiée
    if (_asAssociation) {
      return Stack(
        children: [
          AssociationNav(onAdminTap: User_Info.isAdmin ? _showAdminMenu : null),
          if (_fromDrawerSwitch && _previewRole == 'association') _previewBanner('Association'),
        ],
      );
    }

    // Éleveurs : navigation dédiée 3 icônes + tiroir
    if (_asElevage) {
      return Stack(
        children: [
          EleveurNav(onAdminTap: User_Info.isAdmin ? _showAdminMenu : null),
          if (_fromDrawerSwitch && _previewRole == 'eleveur') _previewBanner('Éleveur'),
        ],
      );
    }

    // Particuliers : navigation dédiée 3 icônes + tiroir
    if (_asParticulier) {
      return Stack(
        children: [
          ParticulierNav(onAdminTap: User_Info.isAdmin ? _showAdminMenu : null),
          if (_fromDrawerSwitch && _previewRole == 'particulier') _previewBanner('Particulier'),
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

class _OnboardingChoiceCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OnboardingChoiceCard({
    required this.icon, required this.color, required this.title,
    required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          border: Border.all(color: color.withAlpha(80)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 15, color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: Colors.grey.shade600)),
              ]),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
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
