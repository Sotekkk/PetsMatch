import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
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
  final _searchCtrl = TextEditingController();
  String _searchText = '';
  int _catIndex = 0;

  final Map<String, Map<String, String?>> _userCache = {};
  List<String> _blockedUsers = [];

  String get _currentProfileType {
    if (User_Info.catPro.isNotEmpty) return User_Info.catPro;
    if (User_Info.isAssociation) return 'association';
    if (User_Info.isElevage) return 'eleveur';
    return 'particulier';
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _searchText = _searchCtrl.text.toLowerCase()));
    _loadBlockedUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBlockedUsers() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('bloquer').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      final keys = (doc.data() as Map<String, dynamic>).keys.toList();
      if (mounted) setState(() => _blockedUsers = keys);
    }
  }

  // ── Actions Firestore ───────────────────────────────────────────────────────

  Future<void> _togglePin(String id, bool current) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('conversations').doc(id)
        .update({'pinnedFor.$uid': !current});
  }

  Future<void> _toggleArchive(String id, bool current) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('conversations').doc(id)
        .update({'archivedFor.$uid': !current});
  }

  Future<void> _toggleMute(String id, bool current) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final until = current ? 0 : DateTime.now().add(const Duration(hours: 8)).millisecondsSinceEpoch;
    await FirebaseFirestore.instance.collection('conversations').doc(id)
        .update({'mutedFor.$uid': until});
  }

  Future<void> _blockUser(String otherId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('bloquer').doc(uid)
        .set({otherId: true}, SetOptions(merge: true));
    if (mounted) setState(() => _blockedUsers.add(otherId));
  }

  Future<void> _delete(String id) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('conversations').doc(id)
        .update({'deletedFor.$uid': true});
  }

  // ── Bottom sheet options ────────────────────────────────────────────────────

  void _showOptions(BuildContext ctx, String id, String otherId, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final isPinned  = (data['pinnedFor']  as Map?)?[uid] == true;
    final isArchived = (data['archivedFor'] as Map?)?[uid] == true;
    final mutedUntil = ((data['mutedFor'] as Map?)?[uid] as int?) ?? 0;
    final isMuted   = mutedUntil > DateTime.now().millisecondsSinceEpoch;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            _Option(
              icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: isPinned ? 'Désépingler' : 'Épingler',
              color: _teal,
              onTap: () async { Navigator.pop(ctx); await _togglePin(id, isPinned); },
            ),
            _Option(
              icon: isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              label: isArchived ? 'Désarchiver' : 'Archiver',
              color: Colors.blueGrey,
              onTap: () async { Navigator.pop(ctx); await _toggleArchive(id, isArchived); },
            ),
            _Option(
              icon: isMuted ? Icons.notifications_outlined : Icons.notifications_off_outlined,
              label: isMuted ? 'Réactiver les notifications' : 'Mettre en sourdine (8h)',
              color: Colors.orange.shade700,
              onTap: () async { Navigator.pop(ctx); await _toggleMute(id, isMuted); },
            ),
            _Option(
              icon: Icons.block_outlined,
              label: 'Bloquer cet utilisateur',
              color: Colors.red.shade700,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm(ctx, 'Bloquer cet utilisateur',
                    'Vous ne recevrez plus de messages de cet utilisateur.');
                if (ok) await _blockUser(otherId);
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            _Option(
              icon: Icons.delete_outline,
              label: 'Supprimer la conversation',
              color: Colors.red,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm(ctx, 'Supprimer la conversation',
                    "Cette conversation sera supprimée de votre liste. L'autre participant peut toujours y accéder.");
                if (ok) await _delete(id);
              },
            ),
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

  // ── User info ───────────────────────────────────────────────────────────────

  Future<Map<String, String?>> _userInfo(String uid, {Map<String, dynamic>? cached}) async {
    if (_userCache.containsKey(uid)) return _userCache[uid]!;
    if (uid.isEmpty) return {'name': 'Utilisateur inconnu', 'photo': null};

    // Priorité aux infos stockées dans la conversation (participants_info)
    if (cached != null) {
      final name = (cached['name'] as String?) ?? '';
      final photo = cached['photo'] as String?;
      _userCache[uid] = {'name': name.isEmpty ? 'Utilisateur' : name, 'photo': photo};
      return _userCache[uid]!;
    }

    // Fallback Firestore
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (snap.exists) {
        final d = snap.data()!;
        final name = d['isElevage'] == true
            ? (d['nameElevage'] ?? 'Élevage')
            : '${d['firstname'] ?? ''} ${d['lastname'] ?? ''}'.trim();
        const dflt = 'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
        final rawUrl = d['isElevage'] == true ? d['profilePictureUrlElevage'] : d['profilePictureUrl'];
        final photo = (rawUrl != null && rawUrl.startsWith('http') && rawUrl != dflt) ? rawUrl as String : null;
        _userCache[uid] = {'name': name.isEmpty ? 'Utilisateur' : name, 'photo': photo};
      } else {
        _userCache[uid] = {'name': 'Utilisateur inconnu', 'photo': null};
      }
    } catch (_) {
      _userCache[uid] = {'name': 'Utilisateur inconnu', 'photo': null};
    }
    return _userCache[uid]!;
  }

  String _fmtTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) return DateFormat('HH:mm').format(dt);
    if (now.difference(dt).inDays < 7) return DateFormat('EEE', 'fr_FR').format(dt);
    return DateFormat('dd/MM').format(dt);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal, elevation: 0, automaticallyImplyLeading: false,
        title: const Text('Messages', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
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
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: _teal, width: 1.5)),
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
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .where('participants', arrayContains: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _green));
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return _EmptyState(emoji: _catEmojis[_catIndex], label: 'Aucune conversation');
                }

                final activeCat = _catKeys[_catIndex];

                var docs = snap.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;

                  if ((data['deletedFor'] as Map?)?[uid] == true) return false;

                  // Filtre profil (V2 multi-profil)
                  final convProPid      = data['pro_profile_id']      as String? ?? '';
                  final convConsumerPid = data['consumer_profile_id'] as String? ?? '';
                  final activePid       = User_Info.activeProfileId;

                  if (activePid.isNotEmpty) {
                    // Profil secondaire actif : montrer convs où je suis le pro OU le consommateur
                    // Les convs sans aucun tag (anciennes données) restent visibles
                    final isMePro      = convProPid == activePid;
                    final isMeConsumer = convConsumerPid == activePid;
                    final isUntagged   = convProPid.isEmpty && convConsumerPid.isEmpty;
                    if (!isMePro && !isMeConsumer && !isUntagged) return false;
                  } else {
                    // Vue particulier : cacher les convs taguées à un profil secondaire de l'utilisateur
                    final myProfileIds = User_Info.availableProfiles.map((p) => p['id']?.toString() ?? '').toList();
                    if (convProPid.isNotEmpty && myProfileIds.contains(convProPid)) return false;
                    if (convConsumerPid.isNotEmpty && myProfileIds.contains(convConsumerPid)) return false;
                  }

                  // Rétrocompat : ancien champ participant_profile_types (si présent)
                  final profileTypes = data['participant_profile_types'] as Map? ?? {};
                  final myType = profileTypes[uid] as String?;
                  if (myType != null && myType.isNotEmpty && myType != _currentProfileType) return false;

                  // Bloqués
                  final others = (data['participants'] as List).where((p) => p != uid);
                  if (others.any((p) => _blockedUsers.contains(p))) return false;

                  // Archive
                  final isArchived = (data['archivedFor'] as Map?)?[uid] == true;
                  if (activeCat == '__archived__') return isArchived;
                  if (isArchived) return false;

                  // Catégorie
                  if (activeCat != null && data['categorie'] != activeCat) return false;

                  return true;
                }).toList();

                // Tri : épinglées en premier, puis timestamp desc
                docs.sort((a, b) {
                  final da = a.data() as Map<String, dynamic>;
                  final db = b.data() as Map<String, dynamic>;
                  final ap = (da['pinnedFor'] as Map?)?[uid] == true;
                  final bp = (db['pinnedFor'] as Map?)?[uid] == true;
                  if (ap && !bp) return -1;
                  if (!ap && bp) return 1;
                  final at = (da['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  final bt = (db['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  return bt.compareTo(at);
                });

                if (docs.isEmpty) {
                  return _EmptyState(emoji: _catEmojis[_catIndex], label: 'Aucun message dans ${_catLabels[_catIndex]}');
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d     = docs[i];
                    final data  = d.data() as Map<String, dynamic>;
                    final id    = d.id;
                    final cat   = data['categorie'] as String?;
                    final isPinned = (data['pinnedFor'] as Map?)?[uid] == true;
                    final mutedUntil = ((data['mutedFor'] as Map?)?[uid] as int?) ?? 0;
                    final isMuted = mutedUntil > DateTime.now().millisecondsSinceEpoch;

                    final lastMsg = (data['lastMessage'] ?? '') as String;
                    final ts      = data['timestamp'] as Timestamp?;
                    final unread  = ((data['unreadCount'] as Map?)?[uid] as int?) ?? 0;
                    final shown   = isMuted ? 0 : unread;

                    final others = (data['participants'] as List).where((p) => p != uid).toList();
                    if (others.isEmpty) return const SizedBox.shrink();
                    final otherId = others[0].toString();

                    // Infos mises en cache dans la conversation (stockées à l'envoi)
                    final pInfoMap = data['participants_info'];
                    final cached = (pInfoMap is Map) ? (pInfoMap[otherId] as Map<String, dynamic>?) : null;

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
                            )).then((_) {
                              FirebaseFirestore.instance.collection('conversations')
                                  .doc(id).update({'unreadCount.$uid': 0});
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
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    if (isPinned) ...[
                                      const Icon(Icons.push_pin, size: 12, color: _teal),
                                      const SizedBox(width: 3),
                                    ],
                                    Expanded(
                                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontFamily: 'Galey', fontWeight: shown > 0 ? FontWeight.w700 : FontWeight.w600, fontSize: 14, color: Colors.black87)),
                                    ),
                                    if (isMuted) ...[const SizedBox(width: 4), const Icon(Icons.notifications_off, size: 12, color: Colors.grey)],
                                    if (ts != null) Text(_fmtTime(ts),
                                      style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                          color: shown > 0 ? _teal : Colors.grey.shade500,
                                          fontWeight: shown > 0 ? FontWeight.w700 : FontWeight.normal)),
                                  ]),
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    Expanded(
                                      child: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                            color: shown > 0 ? Colors.black87 : Colors.grey.shade500,
                                            fontWeight: shown > 0 ? FontWeight.w600 : FontWeight.normal)),
                                    ),
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
                                        style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: _catBadgeText[cat], fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ]),
                              ),
                            ]),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
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
