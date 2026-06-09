import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final rows = await ProfileService.loadProfiles(uid);
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
    return p['profile_label']?.toString() ?? User_Info.primaryLabel;
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
    'veterinaire'      => 'Vétérinaire',
    'sante'            => 'Santé animale',
    'education'        => 'Éducation',
    'garde'            => 'Garde',
    'pension'          => 'Pension',
    'toilettage'       => 'Toilettage',
    'photographe'      => 'Photographe',
    'marechal_ferrant' => 'Maréchal-ferrant',
    _                  => 'Profil',
  };

  static IconData _typeIcon(String type) => switch (type) {
    'particulier'      => Icons.person_outline,
    'eleveur'          => Icons.pets,
    'veterinaire'      => Icons.local_hospital_outlined,
    'sante'            => Icons.self_improvement_outlined,
    'education'        => Icons.psychology_outlined,
    'garde'            => Icons.home_outlined,
    'pension'          => Icons.hotel_outlined,
    'toilettage'       => Icons.content_cut,
    'photographe'      => Icons.camera_alt_outlined,
    'marechal_ferrant' => Icons.handyman_outlined,
    _                  => Icons.account_circle_outlined,
  };

  Future<void> _switchToProfile(Map<String, dynamic>? profile) async {
    Navigator.pop(context); // ferme le bottom sheet

    if (profile == null) {
      // Retour au profil principal
      if (User_Info.activeProfileId.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) User_Info.updateUserInfo(doc.data()!);
      } catch (_) {}
    } else {
      final id = profile['id']?.toString() ?? '';
      if (User_Info.activeProfileId == id) return;
      User_Info.applyProfile(profile);
    }

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
        primaryLabel: User_Info.primaryLabel,
        primaryType: User_Info.primaryType,
        primaryAvatar: User_Info.primaryAvatar,
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
  final String primaryLabel;
  final String primaryType;
  final String primaryAvatar;
  final void Function(Map<String, dynamic>?) onSelect;
  final VoidCallback onAddProfile;
  final void Function(String id) onDelete;
  final String Function(String) typeLabel;
  final IconData Function(String) typeIcon;

  const _SwitcherSheet({
    required this.profiles,
    required this.loading,
    required this.activeProfileId,
    required this.primaryLabel,
    required this.primaryType,
    required this.primaryAvatar,
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

            // Profil principal
            _ProfileRow(
              label: primaryLabel.isNotEmpty ? primaryLabel : 'Profil principal',
              sublabel: typeLabel(primaryType),
              icon: typeIcon(primaryType),
              avatarUrl: primaryAvatar,
              isActive: activeProfileId.isEmpty,
              onTap: () => onSelect(null),
            ),

            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ...profiles.map((p) {
                final id = p['id']?.toString() ?? '';
                final type = p['profile_type']?.toString() ?? '';
                return _ProfileRow(
                  label: p['profile_label']?.toString() ?? typeLabel(type),
                  sublabel: typeLabel(type),
                  icon: typeIcon(type),
                  avatarUrl: p['avatar_url']?.toString() ?? '',
                  isActive: activeProfileId == id,
                  onTap: () => onSelect(p),
                  onDelete: () => onDelete(id),
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
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ProfileRow({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.avatarUrl,
    required this.isActive,
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
      title: Text(label,
          style: TextStyle(
            fontFamily: 'Galey',
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          )),
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
