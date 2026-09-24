import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/petfriends/petfriend_chat_page.dart';
import 'package:PetsMatch/pages/petfriends/public_profile_page.dart';
import 'package:PetsMatch/pages/particulier/social_feed_page.dart'
    show resolveActiveAuthorProfileId, socialProfileName, socialProfilePhoto,
         socialProfileTypeLabel, kSocialAuthorCols;

class PetFriendsPage extends StatefulWidget {
  const PetFriendsPage({super.key});

  @override
  State<PetFriendsPage> createState() => _PetFriendsPageState();
}

class _PetFriendsPageState extends State<PetFriendsPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  static const _accent = Color(0xFF7ED69D);
  static const _darkC  = Color(0xFF071C22);

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

  /// Résout MON profil ACTIF — jamais l'uid seul, jamais vide. Même
  /// résolveur que Pets Social (`_activeAuthorProfileId`) : chaque profil
  /// (particulier, éleveur, pro…) a sa propre liste de PetFriends.
  Future<String?> _myProfileId() => resolveActiveAuthorProfileId(_myUid);

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
      // PetFriends se base sur le profil_id, exactement comme Pets Social :
      // pas de filtre de type ni is_main, un compte peut apparaître via
      // plusieurs de ses profils (particulier, éleveur, pro…), chacun étant
      // une identité PetFriends distincte avec sa propre liste d'amis.
      final rows = await _supa
          .from('user_profiles')
          .select('$kSocialAuthorCols, ville')
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
      final myProfileId = await _myProfileId() ?? '';
      final sent     = await _supa.from('petfriends').select('id, uid_recepteur, recepteur_profile_id, statut').eq('demandeur_profile_id', myProfileId);
      final received = await _supa.from('petfriends').select('id, uid_demandeur, demandeur_profile_id, statut').eq('recepteur_profile_id', myProfileId);

      // Clé = profil_id de L'AUTRE partie (pas son uid : un même uid peut
      // avoir plusieurs profils, chacun une relation PetFriends à part).
      // Lignes historiques sans profil_id stocké → ignorées (pas de profil
      // à afficher de toute façon sans migration de données).
      final Map<String, Map<String, dynamic>> byProfileId = {};
      for (final r in (sent as List)) {
        final pid = r['recepteur_profile_id']?.toString();
        if (pid == null || pid.isEmpty) continue;
        byProfileId[pid] = {'id': r['id'], 'statut': r['statut'], 'dir': 'sent', 'uid': r['uid_recepteur']};
      }
      for (final r in (received as List)) {
        final pid = r['demandeur_profile_id']?.toString();
        if (pid == null || pid.isEmpty) continue;
        byProfileId[pid] ??= {'id': r['id'], 'statut': r['statut'], 'dir': 'received', 'uid': r['uid_demandeur']};
      }

      if (byProfileId.isEmpty) {
        if (mounted) setState(() { _friends = []; _received = []; _sent = []; _loading = false; });
        return;
      }

      final profiles = await _supa.from('user_profiles')
          .select('$kSocialAuthorCols, ville')
          .inFilter('id', byProfileId.keys.toList());
      final Map<String, Map<String, dynamic>> profMap = {
        for (final p in (profiles as List)) p['id'].toString(): p as Map<String, dynamic>
      };

      List<_FriendRow> friends = [], recv = [], sentList = [];
      for (final e in byProfileId.entries) {
        final rel  = e.value;
        final prof = profMap[e.key];
        if (prof == null) continue;
        final row = _FriendRow(
          relId: rel['id'].toString(), uid: rel['uid'].toString(), profileId: e.key,
          statut: rel['statut'].toString(), direction: rel['dir'].toString(),
          fullName: socialProfileName(prof),
          typeLabel: socialProfileTypeLabel(prof['profile_type']?.toString()),
          photoUrl: socialProfilePhoto(prof) ?? '',
          city: prof['ville']?.toString() ?? '',
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
      final nom = socialProfileName(u).toLowerCase();
      return nom.contains(q);
    }).take(20).toList();
    final Map<String, String?> statuts = {};
    for (final u in filtered) {
      final pid = u['id'].toString();
      if (_friends.any((f) => f.profileId == pid))         statuts[pid] = 'accepte';
      else if (_received.any((f) => f.profileId == pid) || _sent.any((f) => f.profileId == pid)) statuts[pid] = 'en_attente';
      else statuts[pid] = null;
    }
    setState(() { _searchResults = filtered; _searchStatuts = statuts; });
  }

  Future<void> _sendRequest(String targetUid, String targetProfileId) async {
    try {
      final myProfileId = await _myProfileId() ?? '';
      await _supa.from('petfriends').insert({
        'uid_demandeur': _myUid,
        if (myProfileId.isNotEmpty) 'demandeur_profile_id': myProfileId,
        'uid_recepteur': targetUid,
        'recepteur_profile_id': targetProfileId,
        'statut': 'en_attente',
        'created_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String(),
      });
      Map<String, dynamic>? me;
      if (myProfileId.isNotEmpty) {
        me = await _supa.from('user_profiles').select(kSocialAuthorCols).eq('id', myProfileId).maybeSingle();
      }
      me ??= await _supa.from('user_profiles').select(kSocialAuthorCols).eq('uid', _myUid).eq('is_main', true).maybeSingle();
      final nom = me != null ? socialProfileName(me) : 'Quelqu\'un';
      await _supa.from('notifications').insert({
        'uid': targetUid, 'type': 'petfriend_request',
        'title': '🐾 Nouvelle demande PetFriend', 'body': '$nom veut être ton PetFriend !',
        'profile_id': targetProfileId,
        'data': {'fromUid': _myUid, if (myProfileId.isNotEmpty) 'fromProfileId': myProfileId},
        'read': false, 'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) setState(() => _searchStatuts[targetProfileId] = 'en_attente');
    } catch (_) {}
  }

  Future<void> _accept(_FriendRow row) async {
    await _supa.from('petfriends').update({'statut': 'accepte', 'updated_at': DateTime.now().toIso8601String()}).eq('id', row.relId);
    final myProfileId = await _myProfileId() ?? '';
    Map<String, dynamic>? me;
    if (myProfileId.isNotEmpty) {
      me = await _supa.from('user_profiles').select(kSocialAuthorCols).eq('id', myProfileId).maybeSingle();
    }
    me ??= await _supa.from('user_profiles').select(kSocialAuthorCols).eq('uid', _myUid).eq('is_main', true).maybeSingle();
    final nom = me != null ? socialProfileName(me) : 'Quelqu\'un';
    await _supa.from('notifications').insert({
      'uid': row.uid, 'type': 'petfriend_accepted',
      'title': '🐾 PetFriend accepté !', 'body': '$nom a accepté ta demande PetFriend.',
      'profile_id': row.profileId,
      'data': {'fromUid': _myUid, if (myProfileId.isNotEmpty) 'fromProfileId': myProfileId},
      'read': false, 'created_at': DateTime.now().toIso8601String(),
    });
    _load();
  }

  Future<void> _decline(_FriendRow row) async {
    await _supa.from('petfriends').delete().eq('id', row.relId);
    _load();
  }

  void _openProfile(String uid, String profileId) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => PublicProfilePage(targetUid: uid, targetProfileId: profileId)));

  // ─── Groupes ─────────────────────────────────────────────────────────────

  Future<void> _createGroupe() async {
    final nomCtrl = TextEditingController();
    final memberSearchCtrl = TextEditingController();
    final selectedUids = <String>{};
    // Comme Facebook/Instagram : un groupe peut inclure n'importe qui, pas
    // seulement des PetFriends déjà acceptés — on cherche dans tous les
    // profils, avec un badge 🐾 pour repérer les PetFriends existants.
    final friendUids = _friends.map((f) => f.uid).toSet();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E2A30),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final query = memberSearchCtrl.text.trim().toLowerCase();
          final candidates = query.isEmpty
              ? _allUsers
              : _allUsers.where((u) => socialProfileName(u).toLowerCase().contains(query)).toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
            builder: (_, sc) => Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nouveau groupe',
                  style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 18, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nomCtrl,
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nom du groupe',
                    labelStyle: const TextStyle(fontFamily: 'Galey', color: Colors.white60),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ajouter des membres (${selectedUids.length})',
                  style: const TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w600,
                    fontSize: 14, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: memberSearchCtrl,
                  onChanged: (_) => setModal(() {}),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Rechercher n\'importe qui (pas seulement vos PetFriends)…',
                    hintStyle: const TextStyle(
                      fontFamily: 'Galey', fontSize: 12,
                      color: Colors.white38,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white60),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: candidates.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun résultat',
                            style: TextStyle(fontFamily: 'Galey', color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          controller: sc,
                          itemCount: candidates.length,
                          itemBuilder: (_, i) {
                            final u = candidates[i];
                            final uid = u['uid'].toString();
                            final sel = selectedUids.contains(uid);
                            final isFriend = friendUids.contains(uid);
                            final photo = socialProfilePhoto(u) ?? '';
                            return CheckboxListTile(
                              value: sel,
                              activeColor: _accent,
                              checkColor: _darkC,
                              onChanged: (_) => setModal(() {
                                if (sel) selectedUids.remove(uid); else selectedUids.add(uid);
                              }),
                              title: Text(
                                socialProfileName(u),
                                style: const TextStyle(
                                  fontFamily: 'Galey', fontSize: 14, color: Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (isFriend) '🐾 PetFriend',
                                  if ((u['ville']?.toString() ?? '').isNotEmpty) u['ville'].toString(),
                                ].join(' · '),
                                style: const TextStyle(
                                  fontFamily: 'Galey', fontSize: 12, color: Colors.white60,
                                ),
                              ),
                              secondary: CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.white.withValues(alpha: 0.20),
                                backgroundImage: photo.isNotEmpty
                                    ? CachedNetworkImageProvider(photo)
                                    : null,
                                child: photo.isEmpty
                                    ? const Icon(Icons.person_outline, size: 20, color: Colors.white70)
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: _darkC,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: () async {
                      final nom = nomCtrl.text.trim();
                      if (nom.isEmpty) return;
                      final members = [_myUid, ...selectedUids];
                      final myData = await _supa.from('user_profiles')
                          .select('firstname, lastname').eq('uid', _myUid).eq('is_main', true).maybeSingle();
                      final myName = '${myData?['firstname'] ?? ''} ${myData?['lastname'] ?? ''}'.trim();
                      final unread = {for (final u in members) u: 0};
                      final Map<String, dynamic> participantsInfo = {
                        _myUid: {'name': myName.isEmpty ? 'Utilisateur' : myName},
                      };
                      // Charger les noms des autres membres
                      if (selectedUids.isNotEmpty) {
                        final others = await _supa.from('user_profiles')
                            .select('uid, firstname, lastname, profile_picture_url:avatar_url')
                            .inFilter('uid', selectedUids.toList()).eq('is_main', true);
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
                    child: const Text(
                      'Créer le groupe',
                      style: TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
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
      backgroundColor: _darkC,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  // Header frosted glass
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'PetFriend',
                            style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // TabBar
                  TabBar(
                    controller: _tabs,
                    indicatorColor: _accent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    dividerColor: Colors.white.withValues(alpha: 0.1),
                    labelStyle: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    tabs: [
                      Tab(text: 'Amis (${_friends.length})'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Demandes'),
                            if (pendingCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: _accent,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$pendingCount',
                                  style: const TextStyle(
                                    color: _darkC,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Tab(text: 'Conversations'),
                    ],
                  ),
                  // Contenu
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: _accent),
                          )
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              _buildFriendsTab(),
                              _buildRequestsTab(),
                              _buildGroupesTab(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            // Bouton fixe bas — onglet Conversations
            if (_tabs.index == 2)
              Positioned(
                bottom: 24,
                right: 16,
                child: GestureDetector(
                  onTap: _createGroupe,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.group_add, color: _darkC, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Nouveau groupe',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            color: _darkC,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupesTab() {
    if (_loadingGroupes) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_groupes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.group_outlined, size: 64, color: Colors.white.withValues(alpha: 0.30)),
            const SizedBox(height: 16),
            const Text(
              'Aucun groupe pour le moment',
              style: TextStyle(
                fontFamily: 'Galey', fontSize: 15, color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Créez un groupe pour discuter avec vos PetFriends',
              style: TextStyle(
                fontFamily: 'Galey', fontSize: 13, color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: _groupes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final conv    = _groupes[i];
        final nom     = conv['nom']?.toString() ?? 'Groupe';
        final last    = conv['last_message']?.toString() ?? '';
        final members = (conv['participants'] as List?)?.length ?? 0;
        final unreadMap = conv['unread_count'] as Map? ?? {};
        final unread  = (unreadMap[_myUid] as int?) ?? 0;
        return GestureDetector(
          onTap: () => _openGroupe(conv),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.20),
                child: const Icon(Icons.group, color: Colors.white70, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    nom,
                    style: const TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 14, color: Colors.white,
                    ),
                  ),
                  Text(
                    '$members membres${last.isNotEmpty ? ' · $last' : ''}',
                    style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 12, color: Colors.white60,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: _darkC, fontSize: 10, fontWeight: FontWeight.bold,
                    ),
                  ),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Rechercher un utilisateur…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.white38),
                prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white60),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchResults = []);
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accent),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: _searchCtrl.text.trim().length >= 2
            ? _buildSearchResults()
            : _buildFriendsList(),
      ),
    ]);
  }

  Widget _buildSearchResults() {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'Aucun résultat',
          style: TextStyle(fontFamily: 'Galey', color: Colors.white70),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final u   = _searchResults[i];
        final uid = u['uid'].toString();
        final pid = u['id'].toString();
        return _friendCard(
          uid: uid,
          nom: socialProfileName(u),
          typeLabel: socialProfileTypeLabel(u['profile_type']?.toString()),
          city: u['ville']?.toString() ?? '',
          photoUrl: socialProfilePhoto(u) ?? '',
          onTap: () => _openProfile(uid, pid),
          trailing: _searchActionBtn(uid, pid, _searchStatuts[pid]),
        );
      },
    );
  }

  Widget _searchActionBtn(String uid, String profileId, String? statut) {
    if (statut == 'accepte') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent),
        ),
        child: const Text(
          '✓ PetFriend',
          style: TextStyle(
            fontFamily: 'Galey', fontSize: 12,
            color: _accent, fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (statut == 'en_attente') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: const Text(
          '⏳ En attente',
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _sendRequest(uid, profileId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          '+ Ajouter',
          style: TextStyle(
            fontFamily: 'Galey', fontWeight: FontWeight.w700,
            fontSize: 12, color: _darkC,
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.people_outline, size: 64, color: Colors.white.withValues(alpha: 0.30)),
            const SizedBox(height: 16),
            const Text(
              'Vous n\'avez pas encore de PetFriends',
              style: TextStyle(
                fontFamily: 'Galey', fontSize: 15, color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Recherchez des utilisateurs pour commencer',
              style: TextStyle(
                fontFamily: 'Galey', fontSize: 13, color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final f = _friends[i];
        return _friendCard(
          uid: f.uid,
          nom: f.fullName,
          typeLabel: f.typeLabel,
          city: f.city,
          photoUrl: f.photoUrl,
          onTap: () => _openProfile(f.uid, f.profileId),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        );
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_received.isEmpty && _sent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_search_outlined,
                size: 64, color: Colors.white.withValues(alpha: 0.30)),
            const SizedBox(height: 16),
            const Text(
              'Aucune demande en cours',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white70),
            ),
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_received.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Reçues',
              style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 14, color: Colors.white,
              ),
            ),
          ),
          ...List.generate(_received.length, (i) {
            final r = _received[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _friendCard(
                uid: r.uid,
                nom: r.fullName,
                typeLabel: r.typeLabel,
                city: r.city,
                photoUrl: r.photoUrl,
                onTap: () => _openProfile(r.uid, r.profileId),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () => _accept(r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Accepter',
                        style: TextStyle(
                          fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 12, color: _darkC,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _decline(r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.60)),
                      ),
                      child: const Text(
                        'Refuser',
                        style: TextStyle(
                          fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 12, color: Colors.redAccent,
                        ),
                      ),
                    ),
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
            child: Text(
              'Envoyées',
              style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 14, color: Colors.white,
              ),
            ),
          ),
          ...List.generate(_sent.length, (i) {
            final s = _sent[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _friendCard(
                uid: s.uid,
                nom: s.fullName,
                typeLabel: s.typeLabel,
                city: s.city,
                photoUrl: s.photoUrl,
                onTap: () => _openProfile(s.uid, s.profileId),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                  ),
                  child: const Text(
                    '⏳ En attente',
                    style: TextStyle(
                      fontFamily: 'Galey', fontSize: 11, color: Colors.white70,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _friendCard({
    required String uid,
    required String nom,
    required String city,
    required String photoUrl,
    required Widget trailing,
    required VoidCallback onTap,
    String? typeLabel,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withValues(alpha: 0.20),
            backgroundImage: photoUrl.isNotEmpty
                ? CachedNetworkImageProvider(photoUrl)
                : null,
            child: photoUrl.isEmpty
                ? const Icon(Icons.person_outline, size: 24, color: Colors.white70)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                nom.isNotEmpty ? nom : '—',
                style: const TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 14, color: Colors.white,
                ),
              ),
              if (typeLabel != null)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                  ),
                  child: Text(
                    typeLabel,
                    style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 11, color: Colors.white70,
                    ),
                  ),
                ),
              if (city.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    city,
                    style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 12, color: Colors.white54,
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      ),
    );
  }
}

class _FriendRow {
  final String relId, uid, profileId, statut, direction, fullName, photoUrl, city;
  final String? typeLabel;
  _FriendRow({
    required this.relId, required this.uid, required this.profileId, required this.statut, required this.direction,
    required this.fullName, this.typeLabel, required this.photoUrl, required this.city,
  });
}
