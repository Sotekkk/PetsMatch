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

const _catKeys = [null, 'animaux-perdus', 'annonces', 'communaute'];
const _catLabels = ['Tous', 'Perdus', 'Annonces', 'Communauté'];
const _catEmojis = ['💬', '🐾', '📢', '🌿'];

const _catBadgeColor = {
  'animaux-perdus': Color(0xFFFED7AA),
  'annonces':       Color(0xFFDBEAFE),
  'communaute':     Color(0xFFD1FAE5),
};
const _catBadgeText = {
  'animaux-perdus': Color(0xFFC2410C),
  'annonces':       Color(0xFF1D4ED8),
  'communaute':     Color(0xFF166534),
};
const _catBadgeLabel = {
  'animaux-perdus': '🐾 Perdus',
  'annonces':       '📢 Annonces',
  'communaute':     '🌿 Communauté',
};

const _teal = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);

class _MessagePageState extends State<MessagePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  int _catIndex = 0;

  final Map<String, Map<String, String?>> _userCache = {};
  final Map<String, Map<String, dynamic>> _conversationCache = {};
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
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.toLowerCase());
    });
    loadBlockedUsers().then((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadBlockedUsers() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('bloquer').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      _blockedUsers = (doc.data() as Map<String, dynamic>).keys.toList();
    }
  }

  Future<void> _deleteConversation(String conversationId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .update({'deletedFor.$uid': true});
  }

  void _showDeleteDialog(BuildContext context, String conversationId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer la conversation',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
            'Cette conversation sera supprimée de votre liste. L\'autre participant peut toujours y accéder.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteConversation(conversationId);
            },
            child: const Text('Supprimer',
                style: TextStyle(fontFamily: 'Galey', color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String?>> getUserInfo(String userId) async {
    if (_userCache.containsKey(userId)) return _userCache[userId]!;
    if (userId.isEmpty) {
      return {'name': 'Utilisateur inconnu', 'profilePictureUrl': null};
    }
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (userDoc.exists) {
      final data = userDoc.data() as Map<String, dynamic>;
      final name = data['isElevage'] == true
          ? (data['nameElevage'] ?? 'Élevage inconnu')
          : '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'.trim();
      final rawUrl = data['isElevage'] == true
          ? data['profilePictureUrlElevage']
          : data['profilePictureUrl'];
      const defaultPp = 'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
      final profilePictureUrl = (rawUrl != null && rawUrl.startsWith('http') && rawUrl != defaultPp)
          ? rawUrl as String
          : null;
      _userCache[userId] = {'name': name, 'profilePictureUrl': profilePictureUrl};
      return _userCache[userId]!;
    }
    return {'name': 'Utilisateur inconnu', 'profilePictureUrl': null};
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('HH:mm').format(dt);
    }
    if (now.difference(dt).inDays < 7) {
      return DateFormat('EEE', 'fr_FR').format(dt);
    }
    return DateFormat('dd/MM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Messages',
          style: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: _teal, size: 20),
                hintText: 'Rechercher une conversation…',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _teal, width: 1.5),
                ),
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
              itemBuilder: (context, i) {
                final isActive = _catIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _catIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isActive ? _teal : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive ? _teal : Colors.grey.shade200,
                      ),
                    ),
                    child: Text(
                      '${_catEmojis[i]}  ${_catLabels[i]}',
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Liste conversations
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .where('participants', arrayContains: currentUserId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _green));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _EmptyState(
                      emoji: _catEmojis[_catIndex],
                      label: 'Aucune conversation');
                }

                final activeCat = _catKeys[_catIndex];
                final conversations = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (activeCat != null && data['categorie'] != activeCat) return false;
                  final deletedFor = data['deletedFor'] as Map<String, dynamic>?;
                  if (deletedFor?[currentUserId] == true) return false;
                  final profileTypes = data['participant_profile_types'] as Map<String, dynamic>? ?? {};
                  final myType = profileTypes[currentUserId] as String?;
                  if (myType != null && myType.isNotEmpty && myType != _currentProfileType) return false;
                  if (User_Info.isPro && profileTypes[currentUserId] == null) {
                    final pid = User_Info.activeProfileId;
                    final convoProfileId = data['pro_profile_id'] as String? ?? '';
                    if (pid.isEmpty && convoProfileId.isNotEmpty) return false;
                    if (pid.isNotEmpty && convoProfileId != pid) return false;
                  }
                  return true;
                }).toList();

                if (conversations.isEmpty) {
                  return _EmptyState(
                      emoji: _catEmojis[_catIndex],
                      label: 'Aucun message dans ${_catLabels[_catIndex]}');
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: conversations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = conversations[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final conversationId = doc.id;
                    final categorie = data['categorie'] as String?;

                    _conversationCache[conversationId] = {
                      'lastMessage': data['lastMessage'] ?? '',
                      'timestamp': data['timestamp'] as Timestamp?,
                      'unreadCount': (data['unreadCount'] as Map<String, dynamic>?)?[currentUserId] ?? 0,
                    };

                    final lastMessage = _conversationCache[conversationId]!['lastMessage'] as String;
                    final timestamp = _conversationCache[conversationId]!['timestamp'] as Timestamp?;
                    final unreadCount = _conversationCache[conversationId]!['unreadCount'] as int;

                    final participantIds = (data['participants'] as List<dynamic>)
                        .where((id) => id != currentUserId)
                        .toList();
                    if (participantIds.isEmpty) return const SizedBox.shrink();

                    final otherParticipantId = participantIds[0] as String;
                    if (_blockedUsers.contains(otherParticipantId)) return const SizedBox.shrink();

                    return FutureBuilder<Map<String, String?>>(
                      future: getUserInfo(otherParticipantId),
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        final userInfo = snap.data!;
                        final name = userInfo['name'] ?? 'Inconnu';
                        if (_searchText.isNotEmpty &&
                            !name.toLowerCase().contains(_searchText)) {
                          return const SizedBox.shrink();
                        }

                        return GestureDetector(
                          onLongPress: () => _showDeleteDialog(context, conversationId),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  conversationId: conversationId,
                                  eleveurId: otherParticipantId,
                                ),
                              ),
                            ).then((_) {
                              FirebaseFirestore.instance
                                  .collection('conversations')
                                  .doc(conversationId)
                                  .update({'unreadCount.$currentUserId': 0});
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: const Color(0xFFD4E6CD),
                                      backgroundImage: userInfo['profilePictureUrl'] != null
                                          ? CachedNetworkImageProvider(userInfo['profilePictureUrl']!)
                                          : null,
                                      child: userInfo['profilePictureUrl'] == null
                                          ? const Icon(Icons.person, color: Colors.white, size: 26)
                                          : null,
                                    ),
                                    if (unreadCount > 0)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: const BoxDecoration(
                                            color: _teal,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 12),

                                // Contenu
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                fontFamily: 'Galey',
                                                fontWeight: unreadCount > 0
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (timestamp != null)
                                            Text(
                                              _formatTime(timestamp),
                                              style: TextStyle(
                                                fontFamily: 'Galey',
                                                fontSize: 11,
                                                color: unreadCount > 0
                                                    ? _teal
                                                    : Colors.grey.shade500,
                                                fontWeight: unreadCount > 0
                                                    ? FontWeight.w700
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              lastMessage,
                                              style: TextStyle(
                                                fontFamily: 'Galey',
                                                fontSize: 12,
                                                color: unreadCount > 0
                                                    ? Colors.black87
                                                    : Colors.grey.shade500,
                                                fontWeight: unreadCount > 0
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (unreadCount > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _teal,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                unreadCount > 9 ? '9+' : '$unreadCount',
                                                style: const TextStyle(
                                                    fontFamily: 'Galey',
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (categorie != null && _catBadgeLabel.containsKey(categorie)) ...[
                                        const SizedBox(height: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _catBadgeColor[categorie],
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _catBadgeLabel[categorie]!,
                                            style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 10,
                                              color: _catBadgeText[categorie],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
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

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String label;
  const _EmptyState({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 15,
                  color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }
}
