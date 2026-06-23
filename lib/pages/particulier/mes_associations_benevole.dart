import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/association/association_detail_page.dart';

class MesAssociationsBenevole extends StatefulWidget {
  const MesAssociationsBenevole({super.key});
  @override
  State<MesAssociationsBenevole> createState() => _MesAssociationsBenevoleState();
}

class _MesAssociationsBenevoleState extends State<MesAssociationsBenevole> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;

  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);
  static const _bg   = Color(0xFFF8F8F6);

  bool _loading = true;
  List<Map<String, dynamic>> _assos = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('employes')
          .select()
          .eq('uid_employe', _uid)
          .eq('type', 'benevole')
          .eq('actif', true)
          .order('created_at');

      final List<Map<String, dynamic>> result = [];
      for (final e in rows) {
        final assoUid = e['uid_eleveur'] as String;
        // Chercher d'abord dans user_profiles (profil secondaire association)
        final secProfile = await _supa
            .from('user_profiles')
            .select('name_elevage, profile_label, avatar_url, ville')
            .eq('uid', assoUid)
            .eq('profile_type', 'association')
            .maybeSingle();
        // Fallback sur users
        final userRow = await _supa
            .from('users')
            .select('uid, firstname, lastname, name_elevage, profile_picture_url, ville')
            .eq('uid', assoUid)
            .maybeSingle();

        String nom = 'Association';
        String? avatar;
        String? ville;
        if (secProfile != null) {
          nom = (secProfile['name_elevage'] as String? ?? '').trim().isNotEmpty
              ? secProfile['name_elevage'] as String
              : (secProfile['profile_label'] as String? ?? 'Association');
          avatar = secProfile['avatar_url'] as String?;
          ville  = secProfile['ville'] as String?;
        } else if (userRow != null) {
          final fn = (userRow['firstname'] as String? ?? '').trim();
          final ln = (userRow['lastname'] as String? ?? '').trim();
          nom    = (userRow['name_elevage'] as String? ?? '').trim().isNotEmpty
              ? userRow['name_elevage'] as String
              : '$fn $ln'.trim();
          avatar = userRow['profile_picture_url'] as String?;
          ville  = userRow['ville'] as String?;
        }
        result.add({
          ...e,
          'nom': nom,
          'avatar': avatar,
          'ville': ville,
          'uid': assoUid,
        });
      }
      if (mounted) setState(() { _assos = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _empty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🏠', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      Text('Aucune association',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
      const SizedBox(height: 8),
      Text('Vous n\'êtes bénévole dans aucune association active.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1F2A2E), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mes Associations',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1F2A2E))),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: _assos.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _assos.length,
                      itemBuilder: (_, i) {
                        final a = _assos[i];
                        final nom    = a['nom'] as String? ?? 'Association';
                        final avatar = a['avatar'] as String?;
                        final ville  = a['ville'] as String?;
                        final uid    = a['uid'] as String;
                        return GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AssociationDetailPage(
                              uid: uid,
                              name: nom,
                              avatar: avatar ?? '',
                              ville: ville ?? '',
                            ),
                          )),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 6, offset: const Offset(0, 2),
                              )],
                            ),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: _teal.withOpacity(0.12),
                                backgroundImage: avatar != null
                                    ? CachedNetworkImageProvider(avatar)
                                    : null,
                                child: avatar == null
                                    ? Icon(Icons.volunteer_activism, color: _teal, size: 22)
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nom.isEmpty ? 'Association' : nom,
                                      style: TextStyle(
                                        fontFamily: 'Galey', fontWeight: FontWeight.w600,
                                        fontSize: 15, color: _dark,
                                      ),
                                    ),
                                    if (ville != null && ville.isNotEmpty)
                                      Text('📍 $ville',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: Colors.grey.shade400),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
