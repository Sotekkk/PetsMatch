import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/pages/profile/add_profile_page.dart';
import 'package:PetsMatch/services/profile_service.dart';

class ProfileSwitcherHeader extends StatefulWidget {
  final VoidCallback? onEditTap;
  final VoidCallback? onClose;

  const ProfileSwitcherHeader({super.key, this.onEditTap, this.onClose});

  @override
  State<ProfileSwitcherHeader> createState() => _ProfileSwitcherHeaderState();
}

class _ProfileSwitcherHeaderState extends State<ProfileSwitcherHeader> {
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    // Utilise les profils déjà chargés au login si disponibles
    if (User_Info.availableProfiles.isNotEmpty) {
      if (mounted) setState(() { _profiles = User_Info.availableProfiles; _loading = false; });
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final rows = await ProfileService.loadProfiles(uid);
      User_Info.availableProfiles = rows;
      if (mounted) setState(() { _profiles = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _currentName {
    if (User_Info.activeProfileId.isEmpty) return User_Info.primaryLabel;
    final p = _profiles.firstWhere(
      (r) => r['id']?.toString() == User_Info.activeProfileId,
      orElse: () => {},
    );
    return p['nom']?.toString() ?? p['profile_label']?.toString() ?? User_Info.primaryLabel;
  }

  String get _currentAvatar {
    if (User_Info.activeProfileId.isEmpty) return User_Info.primaryAvatar;
    final p = _profiles.firstWhere(
      (r) => r['id']?.toString() == User_Info.activeProfileId,
      orElse: () => {},
    );
    return p['avatar_url']?.toString() ?? User_Info.primaryAvatar;
  }

  String get _currentRoleLabel {
    final type = User_Info.activeProfileId.isEmpty
        ? User_Info.primaryType
        : (_profiles.firstWhere(
            (r) => r['id']?.toString() == User_Info.activeProfileId,
            orElse: () => {},
          )['profile_type']?.toString() ?? User_Info.primaryType);
    return _typeLabel(type);
  }

  static String _typeLabel(String type) => switch (type) {
    'particulier'      => 'Particulier',
    'eleveur'          => 'Éleveur',
    'association'      => 'Association',
    'veterinaire'      => 'Vétérinaire',
    'para_medical'     => 'Para-médical',
    'education'        => 'Éducation',
    'petsitter'        => 'Pet-sitter',
    'pension'          => 'Pension',
    'promeneur'        => 'Promeneur',
    'photographe'      => 'Photographe',
    'marechal_ferrant' => 'Maréchal-ferrant',
    'petfriendly'      => 'Lieu Pet-Friendly',
    'partenaire'       => 'Partenaire',
    _                  => 'Profil',
  };

  static IconData _typeIcon(String type) => switch (type) {
    'particulier'      => Icons.person_outline,
    'eleveur'          => Icons.pets,
    'association'      => Icons.favorite_outline,
    'veterinaire'      => Icons.local_hospital_outlined,
    'para_medical'     => Icons.self_improvement_outlined,
    'education'        => Icons.psychology_outlined,
    'petsitter'        => Icons.home_outlined,
    'pension'          => Icons.hotel_outlined,
    'promeneur'        => Icons.directions_walk_outlined,
    'photographe'      => Icons.camera_alt_outlined,
    'marechal_ferrant' => Icons.handyman_outlined,
    'petfriendly'      => Icons.place_outlined,
    'partenaire'       => Icons.handshake_outlined,
    _                  => Icons.account_circle_outlined,
  };

  Future<void> _switchToProfile(Map<String, dynamic> profile) async {
    Navigator.pop(context);
    final id = profile['id']?.toString() ?? '';
    if (User_Info.activeProfileId == id) return;
    User_Info.applyProfile(profile);
    if (mounted) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => BottomNav()),
        (_) => false,
      );
    }
  }

  void _openSwitcherSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SwitcherSheet(
        profiles: _profiles,
        loading: _loading,
        activeProfileId: User_Info.activeProfileId,
        onSelect: _switchToProfile,
        onAddProfile: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const AddProfilePage(),
          )).then((_) => _loadProfiles());
        },
        onDelete: (id) async {
          await ProfileService.deleteProfile(id);
          _loadProfiles();
        },
        typeLabel: _typeLabel,
        typeIcon: _typeIcon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _currentAvatar;

    return Container(
      color: _teal,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 12, 16),
      child: Row(
        children: [
          // Avatar → édition du profil
          GestureDetector(
            onTap: widget.onEditTap,
            child: CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFA7C79A),
              backgroundImage: avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl) as ImageProvider
                  : null,
              child: avatarUrl.isEmpty
                  ? const Icon(Icons.pets, color: Colors.white, size: 28)
                  : null,
            ),
          ),
          const SizedBox(width: 14),

          // Nom + rôle
          Expanded(
            child: GestureDetector(
              onTap: _openSwitcherSheet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentName,
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
                      const Icon(Icons.swap_horiz, color: Color(0xFFA7C79A), size: 13),
                      const SizedBox(width: 4),
                      Text(
                        _currentRoleLabel,
                        style: const TextStyle(
                          color: Color(0xFFEEF5EA),
                          fontSize: 12,
                          fontFamily: 'Galey',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Switcher
          IconButton(
            icon: const Icon(Icons.unfold_more, color: Colors.white, size: 22),
            tooltip: 'Changer de profil',
            onPressed: _openSwitcherSheet,
          ),

          // Fermer le drawer
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet ───────────────────────────────────────────────────────────────

class _SwitcherSheet extends StatelessWidget {
  final List<Map<String, dynamic>> profiles;
  final bool loading;
  final String activeProfileId;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onAddProfile;
  final void Function(String id) onDelete;
  final String Function(String) typeLabel;
  final IconData Function(String) typeIcon;

  const _SwitcherSheet({
    required this.profiles,
    required this.loading,
    required this.activeProfileId,
    required this.onSelect,
    required this.onAddProfile,
    required this.onDelete,
    required this.typeLabel,
    required this.typeIcon,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poignée
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const Text('Mes profils',
                style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 12),

            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ...profiles.map((p) {
                final id = p['id']?.toString() ?? '';
                final type = p['profile_type']?.toString() ?? '';
                final isMain = p['is_main'] == true;
                return _ProfileRow(
                  label: p['nom']?.toString() ?? p['profile_label']?.toString() ?? typeLabel(type),
                  sublabel: typeLabel(type),
                  icon: typeIcon(type),
                  avatarUrl: p['avatar_url']?.toString() ?? '',
                  isActive: activeProfileId == id || (activeProfileId.isEmpty && isMain),
                  isMain: isMain,
                  onTap: () => onSelect(p),
                  onDelete: isMain ? null : () => onDelete(id),
                );
              }),

            const Divider(height: 24),

            // Ajouter un profil
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF5EA),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.add, color: Color(0xFF6E9E57)),
              ),
              title: const Text('Ajouter un profil',
                  style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w600,
                    color: Color(0xFF6E9E57),
                  )),
              onTap: onAddProfile,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final String avatarUrl;
  final bool isActive;
  final bool isMain;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ProfileRow({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.avatarUrl,
    required this.isActive,
    this.isMain = false,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFDCEDD5),
            backgroundImage: avatarUrl.isNotEmpty
                ? CachedNetworkImageProvider(avatarUrl) as ImageProvider
                : null,
            child: avatarUrl.isEmpty ? Icon(icon, color: const Color(0xFF6E9E57), size: 20) : null,
          ),
          if (isActive)
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 14, height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFF6E9E57),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 10),
              ),
            ),
        ],
      ),
      title: Row(children: [
        Flexible(child: Text(label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Galey',
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ))),
        if (isMain) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF5EA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('Principal',
              style: TextStyle(fontSize: 10, color: Color(0xFF6E9E57), fontFamily: 'Galey')),
          ),
        ],
      ]),
      subtitle: Text(sublabel,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
      trailing: onDelete != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
              tooltip: 'Supprimer ce profil',
              onPressed: onDelete,
            )
          : isActive
              ? const Icon(Icons.check_circle, color: Color(0xFF6E9E57), size: 20)
              : null,
      onTap: isActive ? null : onTap,
    );
  }
}
