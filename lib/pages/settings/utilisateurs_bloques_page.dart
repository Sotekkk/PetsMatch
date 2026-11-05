import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/services/blocages_service.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _teal = Color(0xFF0C5C6C);

class UtilisatesBloquesPage extends StatefulWidget {
  const UtilisatesBloquesPage({super.key});

  @override
  State<UtilisatesBloquesPage> createState() => _UtilisatesBloquesPageState();
}

class _UtilisatesBloquesPageState extends State<UtilisatesBloquesPage> {
  bool _loading = true;
  List<_BlockedUser> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Blocages de la messagerie (Supabase) + ancienne liste du fil (Firestore).
    final ids = (await Blocages.mesBloques()).toList();

    final users = <_BlockedUser>[];
    final supa = Supabase.instance.client;
    final moi = FirebaseAuth.instance.currentUser?.uid ?? '';
    for (final id in ids) {
      // Le profil de la dernière conversation avec cette personne, sinon son profil
      // principal. Compte introuvable : affiché quand même, pour pouvoir le débloquer.
      var name = '';
      String? photo;
      try {
        String? profil;
        final conv = await supa.from('conversations').select('pro_profile_id, consumer_profile_id')
            .filter('participants', 'cs', '["$moi","$id"]').order('updated_at', ascending: false).limit(1).maybeSingle();
        final pids = [conv?['pro_profile_id'], conv?['consumer_profile_id']].where((x) => x != null).map((x) => x.toString()).toList();
        if (pids.isNotEmpty) {
          final p = await supa.from('user_profiles_complet').select('id').inFilter('id', pids).eq('uid', id).limit(1).maybeSingle();
          profil = p?['id']?.toString();
        }
        final d = await MessagingHelper.getDisplayInfo(id, profileId: profil);
        name = d['name']?.toString() ?? '';
        final url = d['photo'];
        photo = (url is String && url.startsWith('http')) ? url : null;
      } catch (_) {}
      users.add(_BlockedUser(id: id, name: name.isEmpty ? 'Utilisateur' : name, photo: photo));
    }

    if (mounted) setState(() { _users = users; _loading = false; });
  }

  Future<void> _unblock(String otherId) async {
    try {
      await Blocages.debloquer(otherId);
      if (mounted) setState(() => _users.removeWhere((u) => u.id == otherId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Déblocage impossible, réessayez.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Utilisateurs bloqués',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.block, size: 48, color: Color(0xFFC4C9CC)),
                      const SizedBox(height: 12),
                      const Text('Aucun utilisateur bloqué',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 6),
                      Text('Les utilisateurs que vous bloquez\napparaîtront ici.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFFD4E6CD),
                          backgroundImage: u.photo != null ? CachedNetworkImageProvider(u.photo!) : null,
                          child: u.photo == null ? const Icon(Icons.person, color: Colors.white, size: 24) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(u.name,
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('Débloquer',
                                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                                content: Text('Débloquer ${u.name} ? Vous recevrez à nouveau ses messages.',
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(d, true),
                                    child: const Text('Débloquer', style: TextStyle(color: _teal, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ) ?? false;
                            if (ok) await _unblock(u.id);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: _teal,
                            backgroundColor: const Color(0xFFE6F4F7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          ),
                          child: const Text('Débloquer',
                              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}

class _BlockedUser {
  final String id;
  final String name;
  final String? photo;
  const _BlockedUser({required this.id, required this.name, this.photo});
}
