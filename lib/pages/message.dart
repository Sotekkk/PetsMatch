import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chatScreen.dart';

class MessagePage extends StatefulWidget {
  @override
  _MessagePageState createState() => _MessagePageState();
}

// ── Catégories ───────────────────────────────────────────────────────────────

const _catKeys = <String?>[
  null, 'animaux-perdus', 'annonces', 'contact-elevage', 'service-professionnel', 'communaute', '__archived__',
];
const _catLabels = ['Tous', 'Perdus', 'Annonces', 'Élevages', 'Services', 'Communauté', 'Archivés'];
const _catEmojis = ['💬', '🐾', '📢', '🏡', '🔧', '🌿', '📦'];

const _catBadgeColor = {
  'animaux-perdus':        Color(0xFFFED7AA),
  'annonces':              Color(0xFFDBEAFE),
  'communaute':            Color(0xFFD1FAE5),
  'contact-elevage':       Color(0xFFCCEBF2),
  'service-professionnel': Color(0xFFEDE9FE),
};
const _catBadgeText = {
  'animaux-perdus':        Color(0xFFC2410C),
  'annonces':              Color(0xFF1D4ED8),
  'communaute':            Color(0xFF166534),
  'contact-elevage':       Color(0xFF0C5C6C),
  'service-professionnel': Color(0xFF6B21A8),
};
const _catBadgeLabel = {
  'animaux-perdus':        '🐾 Perdus',
  'annonces':              '📢 Annonces',
  'communaute':            '🌿 Communauté',
  'contact-elevage':       '🏡 Élevage',
  'service-professionnel': '🔧 Service',
};

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);

// ── Page ─────────────────────────────────────────────────────────────────────

class _MessagePageState extends State<MessagePage> {
  static final _supa = Supabase.instance.client;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  final _searchCtrl = TextEditingController();
  String _searchText = '';
  int _catIndex = 0;

  final Map<String, Map<String, String?>> _userCache = {};
  List<String> _blockedUsers = [];
  List<Map<String, dynamic>> _convs = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  String get _currentProfileType {
    if (User_Info.catPro.isNotEmpty) return User_Info.catPro;
    if (User_Info.isAssociation) return 'association';
    if (User_Info.isElevage) return 'eleveur';
    return 'particulier';
  }

  static bool _purgeRanThisSession = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _searchText = _searchCtrl.text.toLowerCase()));
    _loadBlockedUsers();
    _loadConversations();
    _subscribeRealtime();
    if (!_purgeRanThisSession) {
      _purgeRanThisSession = true;
      _autoPurge();
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Données ─────────────────────────────────────────────────────────────────

  Future<void> _loadBlockedUsers() async {
    try {
      final rows = await _supa.from('bloquages')
          .select('blocked_uid').eq('uid', _uid);
      if (mounted) setState(() => _blockedUsers = (rows as List).map((r) => r['blocked_uid'].toString()).toList());
    } catch (_) {}
  }

  Future<void> _loadConversations() async {
    if (_uid.isEmpty) return;
    setState(() => _loading = true);
    try {
      final pid = User_Info.activeProfileId;
      final isMainOrEleveur = User_Info.activeType != 'particulier' && User_Info.activeType != 'association';

      final rows = await _supa
          .from('conversations')
          .select()
          .filter('participants', 'cs', '["$_uid"]')
          .order('updated_at', ascending: false);

      final all = List<Map<String, dynamic>>.from(rows as List);
      final filtered = pid.isEmpty ? all : all.where((c) {
        final cPro = (c['pro_profile_id'] as String?) ?? '';
        final cCon = (c['consumer_profile_id'] as String?) ?? '';
        if (cPro == pid || cCon == pid) return true;
        // Conversations sans profil : visibles uniquement pour le profil éleveur principal
        if (cPro.isEmpty && cCon.isEmpty && isMainOrEleveur) return true;
        return false;
      }).toList();

      if (mounted) setState(() {
        _convs = filtered;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    final pid = User_Info.activeProfileId;
    _channel = _supa.channel('msg_list_${_uid}_$pid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => _loadConversations(),
        )
        .subscribe();
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _togglePin(String id, bool current) async {
    final pin = Map<String, dynamic>.from(
        await _getJsonb(id, 'pinned_for'));
    pin[_uid] = !current;
    await _supa.from('conversations').update({'pinned_for': pin}).eq('id', id);
    _loadConversations();
  }

  Future<void> _toggleArchive(String id, bool current) async {
    final arc = Map<String, dynamic>.from(await _getJsonb(id, 'archived_for'));
    arc[_uid] = !current;
    await _supa.from('conversations').update({'archived_for': arc}).eq('id', id);
    _loadConversations();
  }

  Future<void> _toggleMute(String id, bool current) async {
    final muted = Map<String, dynamic>.from(await _getJsonb(id, 'muted_for'));
    final until = current ? 0 : DateTime.now().add(const Duration(hours: 8)).millisecondsSinceEpoch;
    muted[_uid] = until;
    await _supa.from('conversations').update({'muted_for': muted}).eq('id', id);
    _loadConversations();
  }

  Future<void> _blockUser(String otherId) async {
    try {
      await _supa.from('bloquages').insert({'uid': _uid, 'blocked_uid': otherId});
      if (mounted) setState(() => _blockedUsers.add(otherId));
    } catch (_) {}
  }

  Future<void> _delete(String id) async {
    final del = Map<String, dynamic>.from(await _getJsonb(id, 'deleted_for'));
    del[_uid] = true;
    await _supa.from('conversations').update({'deleted_for': del}).eq('id', id);
    _loadConversations();
  }

  // Purge automatique via RPC Supabase (SECURITY DEFINER → bypass RLS).
  // Puis nettoyage Storage des images supprimées.
  Future<void> _autoPurge() async {
    if (_uid.isEmpty) return;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 90));
    try {
      // 1. Récupère les image_url à nettoyer avant suppression
      final convRows = await _supa
          .from('conversations')
          .select('id, updated_at')
          .filter('participants', 'cs', '["$_uid"]');

      final expiredIds = <String>[];
      final activeIds  = <String>[];
      for (final conv in convRows as List) {
        // Archive protection : si la colonne archived_for existe dans _convs déjà chargée, on s'en sert
        final cached = _convs.firstWhere(
          (c) => c['id']?.toString() == conv['id']?.toString(),
          orElse: () => {},
        );
        final archivedFor = (cached['archived_for'] as Map?) ?? {};
        if (archivedFor[_uid] == true) continue;

        final updatedAt = DateTime.tryParse(conv['updated_at']?.toString() ?? '')?.toUtc();
        if (updatedAt == null) continue;
        if (updatedAt.isBefore(cutoff)) {
          expiredIds.add(conv['id'].toString());
        } else {
          activeIds.add(conv['id'].toString());
        }
      }

      // 2. Collecte les URLs images avant suppression (pour nettoyage Storage)
      final allTargetIds = [...expiredIds, ...activeIds];
      List imgRows = [];
      if (allTargetIds.isNotEmpty) {
        final q = _supa.from('messages').select('image_url, conversation_id, created_at')
            .inFilter('conversation_id', allTargetIds)
            .eq('msg_type', 'image')
            .not('image_url', 'is', null);
        imgRows = await q;
      }

      // 3. Appel RPC avec les IDs déjà filtrés côté Flutter (pas de référence à archived_for en SQL)
      await _supa.rpc('purge_old_messages', params: {
        'p_expired_conv_ids': expiredIds,
        'p_active_conv_ids':  activeIds,
        'p_cutoff':           cutoff.toIso8601String(),
      });

      // 4. Nettoie Storage : images des conv expirées + vieux msgs des conv actives
      final toCleanUrls = (imgRows).where((r) {
        final convId    = r['conversation_id']?.toString() ?? '';
        final createdAt = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toUtc();
        if (expiredIds.contains(convId)) return true;
        if (activeIds.contains(convId) && createdAt != null && createdAt.isBefore(cutoff)) return true;
        return false;
      }).map((r) => r['image_url'] as String?).whereType<String>().toList();

      await _cleanStorageUrls(toCleanUrls);

      if (mounted) _loadConversations();
    } catch (e) {
      debugPrint('[autoPurge] erreur: $e');
    }
  }

  Future<void> _cleanStorageUrls(List<String> urls) async {
    for (final url in urls) {
      if (url.isEmpty) continue;
      try {
        final segments = Uri.parse(url).pathSegments;
        final idx = segments.indexOf('media');
        if (idx >= 0 && idx < segments.length - 1) {
          await _supa.storage.from('media').remove([segments.sublist(idx + 1).join('/')]);
        }
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _getJsonb(String convId, String col) async {
    final row = await _supa.from('conversations')
        .select(col).eq('id', convId).maybeSingle();
    return Map<String, dynamic>.from((row?[col] as Map?) ?? {});
  }

  // ── Bottom sheet options ─────────────────────────────────────────────────────

  void _showOptions(BuildContext ctx, String id, String otherId, Map<String, dynamic> data) {
    final isPinned  = (data['pinned_for']  as Map?)?[_uid] == true;
    final isArchived = (data['archived_for'] as Map?)?[_uid] == true;
    final mutedUntil = ((data['muted_for'] as Map?)?[_uid] as int?) ?? 0;
    final isMuted   = mutedUntil > DateTime.now().millisecondsSinceEpoch;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            _Option(icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: isPinned ? 'Désépingler' : 'Épingler', color: _teal,
              onTap: () async { Navigator.pop(ctx); await _togglePin(id, isPinned); }),
            _Option(icon: isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              label: isArchived ? 'Désarchiver' : 'Archiver (conserve indéfiniment)', color: Colors.blueGrey,
              onTap: () async { Navigator.pop(ctx); await _toggleArchive(id, isArchived); }),
            _Option(icon: isMuted ? Icons.notifications_outlined : Icons.notifications_off_outlined,
              label: isMuted ? 'Réactiver les notifications' : 'Mettre en sourdine (8h)',
              color: Colors.orange.shade700,
              onTap: () async { Navigator.pop(ctx); await _toggleMute(id, isMuted); }),
            _Option(icon: Icons.block_outlined, label: 'Bloquer cet utilisateur',
              color: Colors.red.shade700,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm(ctx, 'Bloquer cet utilisateur', 'Vous ne recevrez plus de messages de cet utilisateur.');
                if (ok) await _blockUser(otherId);
              }),
            const Divider(height: 1, indent: 20, endIndent: 20),
            _Option(icon: Icons.delete_outline, label: 'Supprimer la conversation',
              color: Colors.red,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm(ctx, 'Supprimer la conversation',
                    "Cette conversation sera supprimée de votre liste. L'autre participant peut toujours y accéder.\n\nRappel : les conversations non archivées sont supprimées automatiquement après 3 mois.");
                if (ok) await _delete(id);
              }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(BuildContext ctx, String title, String body) async {
    return await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(body, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(title.startsWith('Suppr') ? 'Supprimer' : 'Confirmer',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ) ?? false;
  }

  // ── User info ─────────────────────────────────────────────────────────────────

  Future<Map<String, String?>> _userInfo(String uid, {Map<String, dynamic>? cached}) async {
    if (_userCache.containsKey(uid)) return _userCache[uid]!;
    if (uid.isEmpty) return {'name': 'Utilisateur inconnu', 'photo': null};
    if (cached != null) {
      final name = (cached['name'] as String?) ?? '';
      _userCache[uid] = {'name': name.isEmpty ? 'Utilisateur' : name, 'photo': cached['photo'] as String?};
      return _userCache[uid]!;
    }
    try {
      final snap = await _supa.from('users')
          .select('firstname, lastname, profile_picture_url, is_elevage, name_elevage')
          .eq('uid', uid).maybeSingle();
      if (snap != null) {
        final isElevage = snap['is_elevage'] == true;
        final name = isElevage && (snap['name_elevage'] as String?)?.isNotEmpty == true
            ? snap['name_elevage'] as String
            : '${snap['firstname'] ?? ''} ${snap['lastname'] ?? ''}'.trim();
        _userCache[uid] = {'name': name.isEmpty ? 'Utilisateur' : name, 'photo': snap['profile_picture_url'] as String?};
      } else {
        _userCache[uid] = {'name': 'Utilisateur inconnu', 'photo': null};
      }
    } catch (_) {
      _userCache[uid] = {'name': 'Utilisateur inconnu', 'photo': null};
    }
    return _userCache[uid]!;
  }

  String _fmtIso(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) return DateFormat('HH:mm').format(dt);
    if (now.difference(dt).inDays < 7) return DateFormat('EEE', 'fr_FR').format(dt);
    return DateFormat('dd/MM').format(dt);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal, elevation: 0, automaticallyImplyLeading: false,
        title: const Text('Messages',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
      ),
      body: Column(
        children: [
          // Recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: _teal, size: 20),
                hintText: 'Rechercher une conversation…',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide(color: _teal, width: 1.5)),
              ),
            ),
          ),

          // Filtres catégories
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _catKeys.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final active = _catIndex == i;
                final isArchive = _catKeys[i] == '__archived__';
                return GestureDetector(
                  onTap: () => setState(() => _catIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? (isArchive ? Colors.blueGrey : _teal) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? (isArchive ? Colors.blueGrey : _teal) : Colors.grey.shade200),
                    ),
                    child: Text('${_catEmojis[i]}  ${_catLabels[i]}',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                          color: active ? Colors.white : const Color(0xFF6B7280))),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Liste
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final uid = _uid;
    final activeCat = _catKeys[_catIndex];

    var filtered = _convs.where((data) {
      // Supprimé
      if ((data['deleted_for'] as Map?)?[uid] == true) return false;

      // Type groupes PetFriends : exclure de la liste messagerie pro
      final type = data['type']?.toString() ?? 'direct';
      if (type == 'groupe') return false;

      // Filtre profil (V2)
      final convProPid      = data['pro_profile_id']?.toString()      ?? '';
      final convConsumerPid = data['consumer_profile_id']?.toString() ?? '';
      final activePid       = User_Info.activeProfileId;
      if (activePid.isNotEmpty) {
        final isMePro      = convProPid == activePid;
        final isMeConsumer = convConsumerPid == activePid;
        final isUntagged   = convProPid.isEmpty && convConsumerPid.isEmpty;
        if (!isMePro && !isMeConsumer && !isUntagged) return false;
      } else {
        final myProfileIds = User_Info.availableProfiles
            .map((p) => p['id']?.toString() ?? '').toList();
        if (convProPid.isNotEmpty && myProfileIds.contains(convProPid)) return false;
        if (convConsumerPid.isNotEmpty && myProfileIds.contains(convConsumerPid)) return false;
      }

      // Bloqués
      final others = (data['participants'] as List? ?? []).where((p) => p != uid);
      if (others.any((p) => _blockedUsers.contains(p))) return false;

      // Archive
      final isArchived = (data['archived_for'] as Map?)?[uid] == true;
      if (activeCat == '__archived__') return isArchived;
      if (isArchived) return false;

      // Catégorie
      if (activeCat != null && data['categorie'] != activeCat) return false;

      return true;
    }).toList();

    // Tri : épinglées en premier, puis updated_at desc
    filtered.sort((a, b) {
      final ap = (a['pinned_for'] as Map?)?[uid] == true;
      final bp = (b['pinned_for'] as Map?)?[uid] == true;
      if (ap && !bp) return -1;
      if (!ap && bp) return 1;
      final at = DateTime.tryParse(a['updated_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
      final bt = DateTime.tryParse(b['updated_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    if (filtered.isEmpty) {
      return _EmptyState(emoji: _catEmojis[_catIndex], label: 'Aucune conversation');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final data = filtered[i];
        final id  = data['id'].toString();
        final cat = data['categorie']?.toString();
        final isPinned   = (data['pinned_for']  as Map?)?[uid] == true;
        final mutedUntil = ((data['muted_for'] as Map?)?[uid] as int?) ?? 0;
        final isMuted    = mutedUntil > DateTime.now().millisecondsSinceEpoch;

        final lastMsg = data['last_message']?.toString() ?? '';
        final updatedAt = data['updated_at']?.toString();
        final unreadMap = data['unread_count'] as Map? ?? {};
        final updatedAtDt = DateTime.tryParse(updatedAt ?? '');
        final daysOld = updatedAtDt != null ? DateTime.now().difference(updatedAtDt).inDays : 0;
        final daysLeft = 90 - daysOld;
        final isExpiringSoon = activeCat != '__archived__' && daysOld >= 60 && daysOld < 90;
        final unread  = (unreadMap[uid] as int?) ?? 0;
        final shown   = isMuted ? 0 : unread;

        final participants = (data['participants'] as List? ?? [])
            .where((p) => p.toString() != uid).toList();
        if (participants.isEmpty) return const SizedBox.shrink();
        final otherId = participants[0].toString();

        final pInfoMap = data['participants_info'] as Map?;
        final cached = pInfoMap?[otherId] as Map<String, dynamic>?;

        if (_searchText.isNotEmpty) {
          final name = (cached?['name'] as String? ?? '').toLowerCase();
          if (!name.contains(_searchText)) return const SizedBox.shrink();
        }

        return FutureBuilder<Map<String, String?>>(
          future: _userInfo(otherId, cached: cached),
          builder: (context, userSnap) {
            if (!userSnap.hasData) return const SizedBox.shrink();
            final info = userSnap.data!;
            final name = info['name'] ?? 'Inconnu';

            if (_searchText.isNotEmpty && !name.toLowerCase().contains(_searchText)) {
              return const SizedBox.shrink();
            }

            return GestureDetector(
              onLongPress: () => _showOptions(context, id, otherId, data),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(conversationId: id, eleveurId: otherId),
                )).then((_) async {
                  final unread2 = Map<String, dynamic>.from(unreadMap);
                  unread2[uid] = 0;
                  await _supa.from('conversations').update({'unread_count': unread2}).eq('id', id);
                });
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isPinned ? const Color(0xFFF0F9FF) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: isPinned ? Border.all(color: _teal.withValues(alpha: 0.2)) : null,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Row(children: [
                  Stack(children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFFD4E6CD),
                      backgroundImage: info['photo'] != null ? CachedNetworkImageProvider(info['photo']!) : null,
                      child: info['photo'] == null ? const Icon(Icons.person, color: Colors.white, size: 26) : null,
                    ),
                    if (shown > 0)
                      Positioned(right: 0, top: 0,
                        child: Container(width: 14, height: 14,
                          decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle))),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (isPinned) ...[
                        const Icon(Icons.push_pin, size: 12, color: _teal),
                        const SizedBox(width: 3),
                      ],
                      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Galey',
                            fontWeight: shown > 0 ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 14, color: Colors.black87))),
                      if (isMuted) ...[const SizedBox(width: 4), const Icon(Icons.notifications_off, size: 12, color: Colors.grey)],
                      if (updatedAt != null) Text(_fmtIso(updatedAt),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                            color: shown > 0 ? _teal : Colors.grey.shade500,
                            fontWeight: shown > 0 ? FontWeight.w700 : FontWeight.normal)),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(child: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                            color: shown > 0 ? Colors.black87 : Colors.grey.shade500,
                            fontWeight: shown > 0 ? FontWeight.w600 : FontWeight.normal))),
                      if (shown > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(10)),
                          child: Text(shown > 9 ? '9+' : '$shown',
                            style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    if (cat != null && _catBadgeLabel.containsKey(cat)) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: _catBadgeColor[cat], borderRadius: BorderRadius.circular(8)),
                        child: Text(_catBadgeLabel[cat]!,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                              color: _catBadgeText[cat], fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (isExpiringSoon) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          '⏳ Supprimée dans ${daysLeft}j sans activité · Archiver pour conserver',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                              color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ])),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Option({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color, size: 22),
    title: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: color, fontWeight: FontWeight.w500)),
    onTap: onTap,
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
  );
}

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String label;
  const _EmptyState({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(label, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Color(0xFF9CA3AF))),
      ],
    ),
  );
}
