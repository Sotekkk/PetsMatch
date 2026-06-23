import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/petfriends/public_profile_page.dart';

class PetFriendsPage extends StatefulWidget {
  const PetFriendsPage({super.key});

  @override
  State<PetFriendsPage> createState() => _PetFriendsPageState();
}

class _PetFriendsPageState extends State<PetFriendsPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  static const _green = Color(0xFF2E7D5E);
  static const _orange = Color(0xFFEF6C00);

  late final TabController _tabs;

  List<_FriendRow> _friends = [];
  List<_FriendRow> _received = [];
  List<_FriendRow> _sent = [];
  bool _loading = true;

  // Recherche — chargement initial de tous les users
  List<Map<String, dynamic>> _allUsers = [];
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, String?> _searchStatuts = {}; // uid → statut (null = aucun)
  bool _loadingUsers = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
    _loadAllUsers();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    try {
      final rows = await _supa
          .from('users')
          .select('uid, firstname, lastname, profile_picture_url, city')
          .neq('uid', _myUid)
          .limit(500);
      if (mounted) setState(() {
        _allUsers = List<Map<String, dynamic>>.from(rows as List);
        _loadingUsers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Toutes les relations où je suis impliqué
      final sent = await _supa
          .from('petfriends')
          .select('id, uid_recepteur, statut')
          .eq('uid_demandeur', _myUid);
      final received = await _supa
          .from('petfriends')
          .select('id, uid_demandeur, statut')
          .eq('uid_recepteur', _myUid);

      // Construire les maps uid → relation
      final Map<String, Map<String, dynamic>> byUid = {};
      for (final r in (sent as List)) {
        byUid[r['uid_recepteur'].toString()] = {
          'id': r['id'], 'statut': r['statut'], 'dir': 'sent',
          'other': r['uid_recepteur'],
        };
      }
      for (final r in (received as List)) {
        byUid[r['uid_demandeur'].toString()] ??= {
          'id': r['id'], 'statut': r['statut'], 'dir': 'received',
          'other': r['uid_demandeur'],
        };
      }

      if (byUid.isEmpty) {
        if (mounted) setState(() { _friends = []; _received = []; _sent = []; _loading = false; });
        return;
      }

      // Charger les profils
      final uids = byUid.keys.toList();
      final profiles = await _supa
          .from('users')
          .select('uid, firstname, lastname, profile_picture_url, city')
          .inFilter('uid', uids);
      final Map<String, Map<String, dynamic>> profMap = {
        for (final p in (profiles as List)) p['uid'].toString(): p as Map<String, dynamic>
      };

      List<_FriendRow> friends = [], recv = [], sentList = [];
      for (final entry in byUid.entries) {
        final rel = entry.value;
        final prof = profMap[entry.key];
        if (prof == null) continue;
        final row = _FriendRow(
          relId: rel['id'].toString(),
          uid: entry.key,
          statut: rel['statut'].toString(),
          direction: rel['dir'].toString(),
          firstname: prof['firstname']?.toString() ?? '',
          lastname: prof['lastname']?.toString() ?? '',
          photoUrl: prof['profile_picture_url']?.toString() ?? '',
          city: prof['city']?.toString() ?? '',
        );
        if (rel['statut'] == 'accepte') friends.add(row);
        else if (rel['dir'] == 'received') recv.add(row);
        else sentList.add(row);
      }

      if (mounted) {
        setState(() {
          _friends = friends;
          _received = recv;
          _sent = sentList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String val) {
    final q = val.toLowerCase().trim();
    if (q.length < 2) {
      setState(() { _searchResults = []; });
      return;
    }
    final filtered = _allUsers.where((u) {
      final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.toLowerCase();
      return nom.contains(q);
    }).take(20).toList();

    // Enrichir avec statuts depuis les relations déjà chargées
    final Map<String, String?> statuts = {};
    for (final u in filtered) {
      final uid = u['uid'].toString();
      final friend = _friends.where((f) => f.uid == uid).firstOrNull;
      final recv = _received.where((f) => f.uid == uid).firstOrNull;
      final snt = _sent.where((f) => f.uid == uid).firstOrNull;
      if (friend != null) statuts[uid] = 'accepte';
      else if (recv != null || snt != null) statuts[uid] = 'en_attente';
      else statuts[uid] = null;
    }
    setState(() { _searchResults = filtered; _searchStatuts = statuts; });
  }

  Future<void> _sendRequest(String targetUid) async {
    try {
      await _supa.from('petfriends').insert({
        'uid_demandeur': _myUid,
        'uid_recepteur': targetUid,
        'statut': 'en_attente',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      final me = await _supa.from('users').select('firstname, lastname').eq('uid', _myUid).maybeSingle();
      final nom = me != null ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim() : 'Quelqu\'un';
      await _supa.from('notifications').insert({
        'uid': targetUid,
        'type': 'petfriend_request',
        'title': '🐾 Nouvelle demande PetFriend',
        'body': '$nom veut être ton PetFriend !',
        'data': {'fromUid': _myUid},
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) setState(() => _searchStatuts[targetUid] = 'en_attente');
    } catch (_) {}
  }

  Future<void> _accept(_FriendRow row) async {
    await _supa.from('petfriends').update({
      'statut': 'accepte',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', row.relId);
    final me = await _supa.from('users').select('firstname, lastname').eq('uid', _myUid).maybeSingle();
    final nom = me != null ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim() : 'Quelqu\'un';
    await _supa.from('notifications').insert({
      'uid': row.uid,
      'type': 'petfriend_accepted',
      'title': '🐾 PetFriend accepté !',
      'body': '$nom a accepté ta demande PetFriend.',
      'data': {'fromUid': _myUid},
      'read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
    _load();
  }

  Future<void> _decline(_FriendRow row) async {
    await _supa.from('petfriends').delete().eq('id', row.relId);
    _load();
  }

  void _openProfile(String uid) {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => PublicProfilePage(targetUid: uid)));
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _received.length;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mes PetFriends',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _orange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Amis (${_friends.length})'),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Demandes'),
              if (pendingCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
                  child: Text('$pendingCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ])),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : TabBarView(
              controller: _tabs,
              children: [_buildFriendsTab(), _buildRequestsTab()],
            ),
    );
  }

  Widget _buildFriendsTab() {
    return Column(children: [
      // Recherche
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Rechercher un utilisateur…',
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            prefixIcon: const Icon(Icons.search, size: 20, color: _green),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() { _searchResults = []; });
                    })
                : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ),
      Expanded(child: _searchCtrl.text.trim().length >= 2
          ? _buildSearchResults()
          : _buildFriendsList()),
    ]);
  }

  Widget _buildSearchResults() {
    if (_loadingUsers) return const Center(child: CircularProgressIndicator(color: _green));
    if (_searchResults.isEmpty) {
      return const Center(child: Text('Aucun résultat',
          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final u = _searchResults[i];
        final uid = u['uid'].toString();
        final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
        final city = u['city']?.toString() ?? '';
        final photo = u['profile_picture_url']?.toString() ?? '';
        final statut = _searchStatuts[uid];

        return _friendCard(
          uid: uid, nom: nom, city: city, photoUrl: photo,
          trailing: _searchActionBtn(uid, statut),
          onTap: () => _openProfile(uid),
        );
      },
    );
  }

  Widget _searchActionBtn(String uid, String? statut) {
    if (statut == 'accepte') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: _green.withAlpha(20), borderRadius: BorderRadius.circular(20)),
        child: const Text('✓ PetFriend',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
      );
    }
    if (statut == 'en_attente') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.shade300)),
        child: Text('⏳ En attente',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.amber.shade800)),
      );
    }
    return FilledButton(
      onPressed: () => _sendRequest(uid),
      style: FilledButton.styleFrom(backgroundColor: _green,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: const Text('+ Ajouter',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.people_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Vous n\'avez pas encore de PetFriends',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Recherchez des utilisateurs pour commencer',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center),
        ]),
      ));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final f = _friends[i];
        return _friendCard(
          uid: f.uid, nom: f.fullName, city: f.city, photoUrl: f.photoUrl,
          onTap: () => _openProfile(f.uid),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        );
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_received.isEmpty && _sent.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.person_search_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Aucune demande en cours',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey)),
        ]),
      ));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_received.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Reçues',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          ...List.generate(_received.length, (i) {
            final r = _received[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _friendCard(
                uid: r.uid, nom: r.fullName, city: r.city, photoUrl: r.photoUrl,
                onTap: () => _openProfile(r.uid),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton(
                    onPressed: () => _accept(r),
                    style: FilledButton.styleFrom(backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('Accepter',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () => _decline(r),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('Refuser',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ]),
              ),
            );
          }),
          if (_sent.isNotEmpty) const SizedBox(height: 16),
        ],
        if (_sent.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Envoyées',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          ...List.generate(_sent.length, (i) {
            final s = _sent[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _friendCard(
                uid: s.uid, nom: s.fullName, city: s.city, photoUrl: s.photoUrl,
                onTap: () => _openProfile(s.uid),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.shade300)),
                  child: Text('⏳ En attente',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.amber.shade800)),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _friendCard({
    required String uid, required String nom, required String city,
    required String photoUrl, required Widget trailing, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE8F5E9),
            backgroundImage: photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
            child: photoUrl.isEmpty ? const Icon(Icons.person_outline, size: 24, color: _green) : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom.isNotEmpty ? nom : '—',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
            if (city.isNotEmpty)
              Text(city, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          ])),
          trailing,
        ]),
      ),
    );
  }
}

class _FriendRow {
  final String relId, uid, statut, direction, firstname, lastname, photoUrl, city;
  _FriendRow({
    required this.relId, required this.uid, required this.statut,
    required this.direction, required this.firstname, required this.lastname,
    required this.photoUrl, required this.city,
  });
  String get fullName => '$firstname $lastname'.trim();
}
