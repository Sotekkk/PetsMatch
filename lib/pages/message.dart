import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/utils.dart';
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

class _MessagePageState extends State<MessagePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";
  int _catIndex = 0;

  // Cache pour les utilisateurs et les conversations
  final Map<String, Map<String, String?>> _userCache = {};
  final Map<String, Map<String, dynamic>> _conversationCache = {};
  List<String> _blockedUsers = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.toLowerCase();
      });
    });
    loadBlockedUsers().then((_) { if (mounted) setState(() {}); });
  }

  Future<void> loadBlockedUsers() async {
    final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('bloquer')
        .doc(currentUserId)
        .get();
    if (doc.exists && doc.data() != null) {
      _blockedUsers = (doc.data() as Map<String, dynamic>).keys.toList();
    }
  }

  Future<Map<String, String?>> getUserInfo(String userId) async {
    // Vérifie si les données sont en cache
    if (_userCache.containsKey(userId)) {
      return _userCache[userId]!;
    }

    // Si l'ID est vide, retourne les valeurs par défaut
    if (userId.isEmpty) {
      return {
        'name': 'Utilisateur Inconnu',
        'profilePictureUrl':
            'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60',
      };
    }

    // Récupère les données utilisateur depuis Firestore
    DocumentSnapshot userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (userDoc.exists) {
      var userData = userDoc.data() as Map<String, dynamic>;

      // Récupération du nom
      String name = userData['isElevage'] == true
          ? (userData['nameElevage'] ?? 'Elevage Inconnu')
          : '${userData['firstname'] ?? ''} ${userData['lastname'] ?? ''}';

      // Récupération de l'image (null si pas de photo définie)
      String? rawUrl = userData['isElevage'] == true
          ? userData['profilePictureUrlElevage']
          : userData['profilePictureUrl'];
      const _defaultPp = 'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
      String? profilePictureUrl = (rawUrl != null && rawUrl.startsWith('http') && rawUrl != _defaultPp)
          ? rawUrl
          : null;

      // Ajoute les données dans le cache
      _userCache[userId] = {
        'name': name,
        'profilePictureUrl': profilePictureUrl,
      };

      return _userCache[userId]!;
    }

    // Valeurs par défaut si l'utilisateur n'existe pas
    return {
      'name': 'Utilisateur Inconnu',
      'profilePictureUrl': null,
    };
  }

  @override
  Widget build(BuildContext context) {
    String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      body: Container(
        child: Column(
          children: [
            // Barre de recherche et titre
            SizedBox(
              width: UTILS.widthReference(context),
              height: UTILS.calculHeight(141, UTILS.heightReference(context)),
              child: Stack(
                children: [
                  Image.asset(
                    'assets/deco/arrondideco.png',
                    fit: BoxFit.cover,
                    width:
                        UTILS.calculWidth(151, UTILS.widthReference(context)),
                    height:
                        UTILS.calculHeight(141, UTILS.heightReference(context)),
                  color: const Color(0xFFA7C79A),
                  colorBlendMode: BlendMode.srcIn,
                  ),
                  Positioned(
                    top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        'MESSAGE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          fontSize: UTILS.calculWidth(
                              20, UTILS.widthReference(context)),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
            SizedBox(height: UTILS.calculHeight(8, UTILS.heightReference(context))),
            SizedBox(
              width: UTILS.calculWidth(364, UTILS.widthReference(context)),
              height: UTILS.calculHeight(45, UTILS.heightReference(context)),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Recherche',
                  contentPadding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 15.0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: const Color(0x33A7C79A),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13.0),
                    borderSide: const BorderSide(color: Color(0xFFA7C79A), width: 2.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13.0),
                    borderSide: const BorderSide(color: Color(0xFFA7C79A), width: 2.0),
                  ),
                ),
              ),
            ),
            // Catégories
            SizedBox(height: UTILS.calculHeight(8, UTILS.heightReference(context))),
            SizedBox(
              height: 34,
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
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF0C5C6C) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_catEmojis[i]}  ${_catLabels[i]}',
                        style: TextStyle(
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
            SizedBox(height: UTILS.calculHeight(4, UTILS.heightReference(context))),
            // Liste des messages
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('conversations')
                    .where('participants', arrayContains: currentUserId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('Aucun message'));
                  }

                  final activeCat = _catKeys[_catIndex];
                  var conversations = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (activeCat != null) {
                      final cat = data['categorie'] as String?;
                      if (cat != activeCat) return false;
                    }
                    return true;
                  }).toList();

                  if (conversations.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_catEmojis[_catIndex], style: const TextStyle(fontSize: 40)),
                          const SizedBox(height: 8),
                          Text('Aucun message dans\n${_catLabels[_catIndex]}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      var conversation = conversations[index];
                      var conversationData =
                          conversation.data() as Map<String, dynamic>;
                      String conversationId = conversation.id;
                      final categorie = conversationData['categorie'] as String?;

                      if (!_conversationCache.containsKey(conversationId)) {
                        _conversationCache[conversationId] = {
                          'lastMessage': conversationData['lastMessage'] ?? '',
                          'timestamp': conversationData['timestamp'] as Timestamp?,
                          'unreadCount': (conversationData['unreadCount'] as Map<String, dynamic>?)?[currentUserId] ?? 0,
                        };
                      }

                      var lastMessage = _conversationCache[conversationId]!['lastMessage'];
                      var timestamp = _conversationCache[conversationId]!['timestamp'] as Timestamp?;
                      var unreadCount = _conversationCache[conversationId]!['unreadCount'] as int;

                      var participantIds =
                          (conversationData['participants'] as List<dynamic>)
                              .where((id) => id != currentUserId)
                              .toList();
                      if (participantIds.isEmpty) return const SizedBox();

                      String otherParticipantId = participantIds[0];
                      if (_blockedUsers.contains(otherParticipantId)) {
                        return const SizedBox();
                      }

                      return FutureBuilder<Map<String, String?>>(
                        future: getUserInfo(otherParticipantId),
                        builder: (context, userInfoSnapshot) {
                          if (!userInfoSnapshot.hasData) {
                            return const SizedBox();
                          }

                          var userInfo = userInfoSnapshot.data!;

                          if (_searchText.isNotEmpty &&
                              !userInfo['name']!.toLowerCase().contains(_searchText)) {
                            return const SizedBox();
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFA7C79A),
                              backgroundImage: userInfo['profilePictureUrl'] != null
                                  ? CachedNetworkImageProvider(userInfo['profilePictureUrl']!)
                                  : null,
                              child: userInfo['profilePictureUrl'] == null
                                  ? const Icon(Icons.person, color: Colors.white)
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    userInfo['name']!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: unreadCount > 0 ? Colors.red : Colors.black,
                                    ),
                                  ),
                                ),
                                if (categorie != null && _catBadgeLabel.containsKey(categorie))
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _catBadgeColor[categorie],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _catBadgeLabel[categorie]!,
                                      style: TextStyle(fontSize: 10, color: _catBadgeText[categorie], fontWeight: FontWeight.w600),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              lastMessage,
                              style: TextStyle(color: unreadCount > 0 ? Colors.red : Colors.black),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (timestamp != null)
                                  Text(
                                    DateFormat('HH:mm').format(timestamp.toDate()),
                                    style: TextStyle(color: unreadCount > 0 ? Colors.red : Colors.black),
                                  ),
                                if (unreadCount > 0)
                                  Container(
                                    padding: const EdgeInsets.all(4.0),
                                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                    child: Text(
                                      unreadCount > 9 ? '9+' : unreadCount.toString(),
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    conversationId: conversationId,
                                    eleveurId: otherParticipantId,
                                  ),
                                ),
                              ).then((value) {
                                FirebaseFirestore.instance
                                    .collection('conversations')
                                    .doc(conversationId)
                                    .update({'unreadCount.$currentUserId': 0});
                              });
                            },
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
      ),
    );
  }
}
