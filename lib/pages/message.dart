import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chatscreen.dart';

class MessagePage extends StatefulWidget {
  @override
  _MessagePageState createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  // Cache pour les utilisateurs et les conversations
  final Map<String, Map<String, String>> _userCache = {};
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
    loadBlockedUsers().then((_) => setState(() {}));
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

  Future<Map<String, String>> getUserInfo(String userId) async {
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

      // Récupération de l'image avec remplacement si nécessaire
      String profilePictureUrl = userData['isElevage'] == true
          ? (userData['profilePictureUrlElevage'] ??
              'assets/logo/default_pp.png')
          : (userData['profilePictureUrl'] ?? 'assets/logo/default_pp.png');

      // Remplace tout chemin local par l'URL distante
      if (!profilePictureUrl.startsWith('http')) {
        profilePictureUrl =
            'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
      }

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
      'profilePictureUrl':
          'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60',
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
            SizedBox(
                height: UTILS.calculHeight(8, UTILS.heightReference(context))),
            SizedBox(
              width: UTILS.calculWidth(364, UTILS.widthReference(context)),
              height: UTILS.calculHeight(45, UTILS.heightReference(context)),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Recherche',
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 5.0, horizontal: 15.0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0x33A7C79A),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13.0),
                    borderSide: const BorderSide(
                      color: Color(0xFFA7C79A),
                      width: 2.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13.0),
                    borderSide: const BorderSide(
                      color: Color(0xFFA7C79A),
                      width: 2.0,
                    ),
                  ),
                ),
              ),
            ),
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

                  var conversations = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      var conversation = conversations[index];
                      var conversationData =
                          conversation.data() as Map<String, dynamic>;
                      String conversationId = conversation.id;

                      // Si la conversation est déjà en cache, l'utiliser
                      if (!_conversationCache.containsKey(conversationId)) {
                        _conversationCache[conversationId] = {
                          'lastMessage': conversationData['lastMessage'] ?? '',
                          'timestamp':
                              conversationData['timestamp'] as Timestamp?,
                          'unreadCount': conversationData['unreadCount']
                                  [currentUserId] ??
                              0,
                        };
                      }

                      var lastMessage =
                          _conversationCache[conversationId]!['lastMessage'];
                      var timestamp =
                          _conversationCache[conversationId]!['timestamp']
                              as Timestamp?;
                      var unreadCount =
                          _conversationCache[conversationId]!['unreadCount']
                              as int;

                      var participantIds =
                          (conversationData['participants'] as List<dynamic>)
                              .where((id) => id != currentUserId)
                              .toList();
                      if (participantIds.isEmpty) return const SizedBox();

                      String otherParticipantId = participantIds[0];
                      if (_blockedUsers.contains(otherParticipantId)) {
                        return const SizedBox(); // Ignore la conversation bloquée
                      }

                      return FutureBuilder<Map<String, String>>(
                        future: getUserInfo(otherParticipantId),
                        builder: (context, userInfoSnapshot) {
                          if (!userInfoSnapshot.hasData) {
                            // Si aucune donnée en cache, ne rien afficher
                            return const SizedBox();
                          }

                          var userInfo = userInfoSnapshot.data!;

                          if (_searchText.isNotEmpty &&
                              !userInfo['name']!
                                  .toLowerCase()
                                  .contains(_searchText)) {
                            return const SizedBox();
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.black,
                              backgroundImage: CachedNetworkImageProvider(
                                userInfo['profilePictureUrl']!,
                              ),
                            ),
                            title: Text(
                              userInfo['name']!,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    unreadCount > 0 ? Colors.red : Colors.black,
                              ),
                            ),
                            subtitle: Text(
                              lastMessage,
                              style: TextStyle(
                                color:
                                    unreadCount > 0 ? Colors.red : Colors.black,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (timestamp != null)
                                  Text(
                                    DateFormat('HH:mm')
                                        .format(timestamp.toDate()),
                                    style: TextStyle(
                                      color: unreadCount > 0
                                          ? Colors.red
                                          : Colors.black,
                                    ),
                                  ),
                                if (unreadCount > 0)
                                  Container(
                                    padding: const EdgeInsets.all(4.0),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      unreadCount > 9
                                          ? '9+'
                                          : unreadCount.toString(),
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12),
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
