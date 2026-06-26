import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/petfriends/petfriend_chat_page.dart';
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

  static const _green  = Color(0xFF2E7D5E);
  static const _orange = Color(0xFFEF6C00);

  late final TabController _tabs;

  List<_FriendRow> _friends  = [];
  List<_FriendRow> _received = [];
  List<_FriendRow> _sent     = [];
  bool _loading = true;

  // Groupes Supabase
  List<Map<String, dynamic>> _groupes = [];
  bool _loadingGroupes = false;
  RealtimeChannel? _convChannel;

  // Recherche
  List<Map<String, dynamic>> _allUsers = [];
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, String?> _searchStatuts = {};
  bool _loadingUsers = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
      if (_tabs.index == 2 && _groupes.isEmpty && !_loadingGroupes) _loadGroupes();
    });
    _load();
    _loadAllUsers();
    _subscribeGroupes();
  }

  @override
  void dispose() {
    _convChannel?.unsubscribe();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Chargement groupes Supabase ─────────────────────────────────────────

  Future<void> _loadGroupes() async {
    setState(() => _loadingGroupes = true);
    try {
      final rows = await _supa
          .from('conversations')
          .select()
          .eq('type', 'groupe')
          .filter('participants', 'cs', '["$_myUid"]')
          .order('updated_at', ascending: false);
      if (mounted) {
        setState(() {
          _groupes = List<Map<String, dynamic>>.from(rows as List);
          _loadingGroupes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGroupes = false);
    }
  }

  void _subscribeGroupes() {
    _convChannel = _supa
        .channel('pf_groupes_$_myUid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => _loadGroupes(),
        )
        .subscribe();
  }

  // ─── Chargement amis ─────────────────────────────────────────────────────

  Future<void> _loadAllUsers() async {
    try {
      final rows = await _supa
          .from('users')
          .select('uid, firstname, lastname, profile_picture_url, ville')
          .neq('uid', _myUid)
          .or('is_elevage.is.null,is_elevage.eq.false')
          .or('is_pro.is.null,is_pro.eq.false')
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
      final sent     = await _supa.from('petfriends').select('id, uid_recepteur, statut').eq('uid_demandeur', _myUid);
      final received = await _supa.from('petfriends').select('id, uid_demandeur, statut').eq('uid_recepteur', _myUid);

      final Map<String, Map<String, dynamic>> byUid = {};
      for (final r in (sent as List)) {
        byUid[r['uid_recepteur'].toString()] = {'id': r['id'], 'statut': r['statut'], 'dir': 'sent', 'other': r['uid_recepteur']};
      }
      for (final r in (received as List)) {
        byUid[r['uid_demandeur'].toString()] ??= {'id': r['id'], 'statut': r['statut'], 'dir': 'received', 'other': r['uid_demandeur']};
      }

      if (byUid.isEmpty) {
        if (mounted) setState(() { _friends = []; _received = []; _sent = []; _loading = false; });
        return;
      }

      final profiles = await _supa.from('users')
          .select('uid, firstname, lastname, profile_picture_url, ville')
          .inFilter('uid', byUid.keys.toList());
      final Map<String, Map<String, dynamic>> profMap = {
        for (final p in (profiles as List)) p['uid'].toString(): p as Map<String, dynamic>
      };

      List<_FriendRow> friends = [], recv = [], sentList = [];
      for (final e in byUid.entries) {
        final rel  = e.value;
        final prof = profMap[e.key];
        if (prof == null) continue;
        final row = _FriendRow(
          relId: rel['id'].toString(), uid: e.key,
          statut: rel['statut'].toString(), direction: rel['dir'].toString(),
          firstname: prof['firstname']?.toString() ?? '',
          lastname:  prof['lastname']?.toString()  ?? '',
          photoUrl:  prof['profile_picture_url']?.toString() ?? '',
          city:      prof['ville']?.toString() ?? '',
        );
        if (rel['statut'] == 'accepte')       friends.add(row);
        else if (rel['dir'] == 'received')    recv.add(row);
        else                                  sentList.add(row);
      }

      if (mounted) setState(() { _friends = friends; _received = recv; _sent = sentList; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Actions amis ────────────────────────────────────────────────────────

  void _onSearchChanged(String val) {
    final q = val.toLowerCase().trim();
    if (q.length < 2) { setState(() => _searchResults = []); return; }
    final filtered = _allUsers.where((u) {
      final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.toLowerCase();
      return nom.contains(q);
    }).take(20).toList();
    final Map<String, String?> statuts = {};
    for (final u in filtered) {
      final uid = u['uid'].toString();
      if (_friends.any((f) => f.uid == uid))         statuts[uid] = 'accepte';
      else if (_received.any((f) => f.uid == uid) || _sent.any((f) => f.uid == uid)) statuts[uid] = 'en_attente';
      else statuts[uid] = null;
    }
    setState(() { _searchResults = filtered; _searchStatuts = statuts; });
  }

  Future<void> _sendRequest(String targetUid) async {
    try {
      await _supa.from('petfriends').insert({
        'uid_demandeur': _myUid, 'uid_recepteur': targetUid, 'statut': 'en_attente',
        'created_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String(),
      });
      final me = await _supa.from('users').select('firstname, lastname').eq('uid', _myUid).maybeSingle();
      final nom = me != null ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim() : 'Quelqu\'un';
      await _supa.from('notifications').insert({
        'uid': targetUid, 'type': 'petfriend_request',
        'title': '🐾 Nouvelle demande PetFriend', 'body': '$nom veut être ton PetFriend !',
        'data': {'fromUid': _myUid}, 'read': false, 'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) setState(() => _searchStatuts[targetUid] = 'en_attente');
    } catch (_) {}
  }

  Future<void> _accept(_FriendRow row) async {
    await _supa.from('petfriends').update({'statut': 'accepte', 'updated_at': DateTime.now().toIso8601String()}).eq('id', row.relId);
    final me = await _supa.from('users').select('firstname, lastname').eq('uid', _myUid).maybeSingle();
    final nom = me != null ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim() : 'Quelqu\'un';
    await _supa.from('notifications').insert({
      'uid': row.uid, 'type': 'petfriend_accepted',
      'title': '🐾 PetFriend accepté !', 'body': '$nom a accepté ta demande PetFriend.',
      'data': {'fromUid': _myUid}, 'read': false, 'created_at': DateTime.now().toIso8601String(),
    });
    _load();
  }

  Future<void> _decline(_FriendRow row) async {
    await _supa.from('petfriends').delete().eq('id', row.relId);
    _load();
  }

  void _openProfile(String uid) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => PublicProfilePage(targetUid: uid)));

  // ─── Groupes ─────────────────────────────────────────────────────────────

  Future<void> _createGroupe() async {
    final nomCtrl = TextEditingController();
    final selectedUids = <String>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
          builder: (_, sc) => Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Nouveau groupe',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 14),
              TextField(
                controller: nomCtrl,
                style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(
                  labelText: 'Nom du groupe',
                  labelStyle: const TextStyle(fontFamily: 'Galey'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Ajouter des PetFriends',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Expanded(
                child: _friends.isEmpty
                    ? const Center(child: Text('Aucun PetFriend pour le moment',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                    : ListView.builder(
                        controller: sc,
                        itemCount: _friends.length,
                        itemBuilder: (_, i) {
                          final f = _friends[i];
                          final sel = selectedUids.contains(f.uid);
                          return CheckboxListTile(
                            value: sel, activeColor: _green,
                            onChanged: (_) => setModal(() {
                              if (sel) selectedUids.remove(f.uid); else selectedUids.add(f.uid);
                            }),
                            title: Text(f.fullName, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                            subtitle: f.city.isNotEmpty
                                ? Text(f.city, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)) : null,
                            secondary: CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFE8F5E9),
                              backgroundImage: f.photoUrl.isNotEmpty ? CachedNetworkImageProvider(f.photoUrl) : null,
                              child: f.photoUrl.isEmpty ? const Icon(Icons.person_outline, size: 20, color: _green) : null,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    final nom = nomCtrl.text.trim();
                    if (nom.isEmpty) return;
                    final members = [_myUid, ...selectedUids];
                    final myData = await _supa.from('users')
                        .select('firstname, lastname').eq('uid', _myUid).maybeSingle();
                    final myName = '${myData?['firstname'] ?? ''} ${myData?['lastname'] ?? ''}'.trim();
                    final unread = {for (final u in members) u: 0};
                    final Map<String, dynamic> participantsInfo = {
                      _myUid: {'name': myName.isEmpty ? 'Utilisateur' : myName},
                    };
                    // Charger les noms des autres membres
                    if (selectedUids.isNotEmpty) {
                      final others = await _supa.from('users')
                          .select('uid, firstname, lastname, profile_picture_url')
                          .inFilter('uid', selectedUids.toList());
                      for (final o in (others as List)) {
                        final oName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();
                        participantsInfo[o['uid'].toString()] = {
                          'name': oName.isEmpty ? 'Utilisateur' : oName,
                          if ((o['profile_picture_url'] as String?)?.isNotEmpty == true)
                            'photo': o['profile_picture_url'],
                        };
                      }
                    }
                    // Insérer dans Supabase (id auto-généré par DEFAULT)
                    await _supa.from('conversations').insert({
                      'type': 'groupe',
                      'nom': nom,
                      'participants': members,
                      'participant_ids': members.join(','),
                      'created_by': _myUid,
                      'participants_info': participantsInfo,
                      'last_message': '',
                      'unread_count': unread,
                      'updated_at': DateTime.now().toIso8601String(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadGroupes();
                  },
                  child: const Text('Créer le groupe',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _openGroupe(Map<String, dynamic> conv) {
    final convId = conv['id']?.toString() ?? '';
    final nom = conv['nom']?.toString() ?? 'Groupe';
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PetFriendChatPage(
        conversationId: convId,
        convNom: nom,
        isGroupe: true,
      ),
    ));
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

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
            const Tab(text: 'Groupes'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 2
          ? FloatingActionButton.extended(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              onPressed: _createGroupe,
              icon: const Icon(Icons.group_add),
              label: const Text('Nouveau groupe',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : TabBarView(
              controller: _tabs,
              children: [_buildFriendsTab(), _buildRequestsTab(), _buildGroupesTab()],
            ),
    );
  }

  Widget _buildGroupesTab() {
    if (_loadingGroupes) return const Center(child: CircularProgressIndicator(color: _green));
    if (_groupes.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.group_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Aucun groupe pour le moment',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Créez un groupe pour discuter avec vos PetFriends',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center),
        ]),
      ));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _groupes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final conv  = _groupes[i];
        final nom   = conv['nom']?.toString() ?? 'Groupe';
        final last  = conv['last_message']?.toString() ?? '';
        final members = (conv['participants'] as List?)?.length ?? 0;
        final unreadMap = conv['unread_count'] as Map? ?? {};
        final unread = (unreadMap[_myUid] as int?) ?? 0;
        return GestureDetector(
          onTap: () => _openGroupe(conv),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              const CircleAvatar(
                radius: 24, backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.group, color: _green, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                Text('$members membres${last.isNotEmpty ? ' · $last' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
                  child: Text('$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildFriendsTab() {
    return Column(children: [
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
                    onPressed: () { _searchCtrl.clear(); setState(() => _searchResults = []); })
                : null,
            filled: true, fillColor: Colors.white,
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
    if (_searchResults.isEmpty) return const Center(
        child: Text('Aucun résultat', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final u = _searchResults[i];
        final uid = u['uid'].toString();
        return _friendCard(
          uid: uid,
          nom: '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim(),
          city: u['ville']?.toString() ?? '',
          photoUrl: u['profile_picture_url']?.toString() ?? '',
          onTap: () => _openProfile(uid),
          trailing: _searchActionBtn(uid, _searchStatuts[uid]),
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
          minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
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
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Recherchez des utilisateurs pour commencer',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey), textAlign: TextAlign.center),
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
            child: Text('Reçues', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
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
            child: Text('Envoyées', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
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
            radius: 24, backgroundColor: const Color(0xFFE8F5E9),
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
    required this.relId, required this.uid, required this.statut, required this.direction,
    required this.firstname, required this.lastname, required this.photoUrl, required this.city,
  });
  String get fullName => '$firstname $lastname'.trim();
}
