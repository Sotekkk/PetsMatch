import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/eleveur/postDetail.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/services.dart' show Uint8List;
import 'package:cached_network_image/cached_network_image.dart';

class LikesPage extends StatefulWidget {
  @override
  _LikesPageState createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> {
  final Map<String, String> _imageCache = {};
  List<String> _blockedUserIds = [];
  Future<void> _loadBlockedUsers() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('bloquer')
        .doc(userId)
        .get();

    if (doc.exists && doc.data() != null) {
      _blockedUserIds = (doc.data() as Map<String, dynamic>).keys.toList();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers().then((_) {
      setState(() {}); // Rafraîchit l'interface après avoir chargé les blocs
    });
  }

  Future<List<Map<String, dynamic>>> _fetchLikedPosts(String userUid) async {
    final userLikesDoc = await FirebaseFirestore.instance
        .collection('likedPost')
        .doc(userUid)
        .get();

    if (!userLikesDoc.exists) {
      return [];
    }

    final userLikedPosts = userLikesDoc.data()!;
    final likedPostIds = userLikedPosts.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList();

    if (likedPostIds.isEmpty) {
      return [];
    }

    // Batch fetch posts
    final postSnapshots = await FirebaseFirestore.instance
        .collection('post')
        .where(FieldPath.documentId, whereIn: likedPostIds)
        .get();

    return postSnapshots.docs.map((doc) {
      final postData = doc.data();
      postData['uid'] = doc.id;
      return postData;
    }).where((post) {
      return !_blockedUserIds.contains(post['uidEleveur']);
    }).toList();
  }

  Future<String> _fetchAndCacheImage(String imageUrl) async {
    if (_imageCache.containsKey(imageUrl)) {
      // Return from cache
      return _imageCache[imageUrl]!;
    } else {
      // Fetch and add to cache
      _imageCache[imageUrl] = imageUrl;
      return imageUrl;
    }
  }

  void _showUnLikeDialog(BuildContext context, String userUid, String postUid) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Unlike Post"),
          content: Text("Do you want to unlike this post?"),
          actions: [
            TextButton(
              child: Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Unlike"),
              onPressed: () {
                dislikePost(postUid).then((_) {
                  Navigator.of(context).pop();
                  setState(() {}); // Refresh UI
                });
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> dislikePost(String postId) async {
    String userId = FirebaseAuth.instance.currentUser!.uid;
    DocumentReference likeDoc =
        FirebaseFirestore.instance.collection('likedPost').doc(userId);

    await likeDoc.update({postId: FieldValue.delete()});
  }

  @override
  Widget build(BuildContext context) {
    final userUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchLikedPosts(userUid),
        builder: (BuildContext context,
            AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final likedPosts = snapshot.data ?? [];
          return likedPosts.isEmpty
              ? Center(child: Text('Aucun post liké'))
              : Column(
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height * 0.2,
                      child: Stack(children: [
                        Image.asset(
                          'assets/deco/arrondideco.png',
                          fit: BoxFit.cover,
                          width: MediaQuery.of(context).size.width * 0.4,
                          height: MediaQuery.of(context).size.height * 0.2,
                        color: const Color(0xFFA7C79A),
                        colorBlendMode: BlendMode.srcIn,
                        ),
                        Positioned(
                          top: MediaQuery.of(context).size.height * 0.075,
                          left: 0,
                          right: 0,
                          child: Align(
                            alignment: Alignment.center,
                            child: Text(
                              'LIKES',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w500,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    SizedBox(height: 8),
                    Align(
                      alignment: Alignment(-0.8, 0),
                      child: Text(
                        'Ce que vous avez liké',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontFamily: 'Galey',
                          color: Color.fromARGB(255, 0, 0, 0),
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Expanded(
                      child: GridView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 2 / 3,
                        ),
                        itemCount: likedPosts.length,
                        itemBuilder: (context, index) {
                          final post = likedPosts[index];
                          final postUid = post['uid'];
                          final imageUrl = post['mediaStockage'][0]['path'];

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PostDetailPage(
                                      post: post), // Remplacez par votre widget
                                ),
                              );
                            },
                            onLongPress: () {
                              _showUnLikeDialog(context, userUid, postUid);
                            },
                            child: FutureBuilder<String>(
                              future: _fetchAndCacheImage(imageUrl),
                              builder: (context, imageSnapshot) {
                                if (imageSnapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                return Stack(
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: imageSnapshot.data!,
                                      placeholder: (context, url) => Center(
                                          child: CircularProgressIndicator()),
                                      errorWidget: (context, url, error) =>
                                          Icon(Icons.error),
                                      imageBuilder: (context, imageProvider) =>
                                          Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          image: DecorationImage(
                                            image: imageProvider,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 7,
                                      right: 10,
                                      child: Icon(
                                        Icons.favorite,
                                        color: Color(0xFF6E9E57),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
        },
      ),
    );
  }
}

class PostWidgetLike extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onLikePressed;

  PostWidgetLike({required this.post, required this.onLikePressed});

  @override
  _PostWidgetLikeState createState() => _PostWidgetLikeState();
}

class _PostWidgetLikeState extends State<PostWidgetLike> {
  bool isLiked = false;
  VideoPlayerController? _videoController;
  Uint8List? _videoThumbnail;
  String? nameElevage;
  String? profilePictureUrlElevage;

  @override
  void initState() {
    super.initState();
    checkIfLiked();
    fetchElevageInfo();
    initializeMedia();
  }

  Future<void> checkIfLiked() async {
    String? postId = widget.post[
        'uid']; // Assurez-vous que vous utilisez le bon champ pour l'ID du post
    if (postId != null && postId.isNotEmpty) {
      bool liked = await isPostLiked(postId);
      setState(() {
        isLiked = liked;
      });
    } else {
      print("Erreur: 'postId' est null ou vide.");
    }
  }

  Future<void> fetchElevageInfo() async {
    String uidEleveur = widget.post['uidEleveur'];
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uidEleveur)
        .get();

    if (userDoc.exists) {
      var userData = userDoc.data() as Map<String, dynamic>;
      setState(() {
        nameElevage = userData['nameElevage'] ?? 'Nom d\'élevage inconnu';
        profilePictureUrlElevage = userData['profilePictureUrlElevage'] ??
            'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
      });
    }
  }

  Future<void> initializeMedia() async {
    for (var media in widget.post['mediaStockage']) {
      if (!media['isPhoto']) {
        String videoPath = media['path'];
        _videoController = VideoPlayerController.network(videoPath)
          ..initialize().then((_) {
            if (mounted) {
              setState(() {});
              _videoController!.setVolume(media['isMuted'] ? 0 : 1);
              _videoController!.setLooping(true);
              _videoController!.play();
            }
          });
        _videoThumbnail = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 128,
          quality: 25,
        );
      }
    }
  }

  Future<void> toggleLike() async {
    String? postId = widget.post['postId'] ??
        widget.post['uid']; // Vérifiez une autre clé possible
    if (postId != null && postId.isNotEmpty) {
      if (isLiked) {
        await dislikePost(postId);
      } else {
        await likePost(postId);
      }
      setState(() {
        isLiked = !isLiked;
      });
      widget.onLikePressed();
    } else {
      print("Erreur: 'postId' ou 'uid' est null ou vide.");
    }
  }

  Future<void> openChatWithEleveur() async {
    String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    String eleveurId = widget.post['uidEleveur'];
    List<String> sortedIds = [currentUserId, eleveurId]..sort();
    String participantIds = sortedIds.join('_');

    QuerySnapshot conversationSnapshot = await FirebaseFirestore.instance
        .collection('conversations')
        .where('participantIds', isEqualTo: participantIds)
        .limit(1)
        .get();

    DocumentReference conversationRef;
    if (conversationSnapshot.docs.isEmpty) {
      conversationRef =
          await FirebaseFirestore.instance.collection('conversations').add({
        'participants': [currentUserId, eleveurId],
        'participantIds': participantIds,
        'lastMessage': '',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      conversationRef = conversationSnapshot.docs.first.reference;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
            conversationId: conversationRef.id, eleveurId: eleveurId),
      ),
    );
  }

  @override
  void dispose() {
    if (_videoController != null) {
      _videoController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.post['mediaStockage'] != null &&
                    widget.post['mediaStockage'].length > 0
                ? CarouselSlider(
                    options: CarouselOptions(
                      height: double.infinity,
                      viewportFraction: 1.0,
                      enlargeCenterPage: false,
                      autoPlay: false,
                    ),
                    items: widget.post['mediaStockage'].map<Widget>((media) {
                      if (media['isPhoto']) {
                        return Container(
                          color: Colors.black,
                          child: Center(
                            child: Image.network(
                              media['path'],
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      } else {
                        return Container(
                          color: Colors.black,
                          child: Center(
                            child: _videoController != null &&
                                    _videoController!.value.isInitialized
                                ? AspectRatio(
                                    aspectRatio:
                                        _videoController!.value.aspectRatio,
                                    child: VideoPlayer(_videoController!),
                                  )
                                : _videoThumbnail != null
                                    ? Image.memory(_videoThumbnail!,
                                        fit: BoxFit.contain)
                                    : Center(
                                        child: CircularProgressIndicator()),
                          ),
                        );
                      }
                    }).toList(),
                  )
                : Container(color: Colors.grey),
          ),
          Positioned(
            bottom: UTILS.calculHeight(0, UTILS.heightReference(context)),
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          String uidEleveur = widget.post['uidEleveur'];
                          DocumentSnapshot userDoc = await FirebaseFirestore
                              .instance
                              .collection('users')
                              .doc(uidEleveur)
                              .get();

                          if (userDoc.exists) {
                            var userData =
                                userDoc.data() as Map<String, dynamic>;

                            UserSelected user =
                                UserSelected.fromMap(userData, userDoc.id);

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    UserDetailPageFeed(user: user),
                              ),
                            );
                          } else {
                            print("L'utilisateur avec cet ID n'existe pas.");
                          }
                        },
                        child: CircleAvatar(
                          backgroundColor: const Color(0xFFA7C79A),
                          backgroundImage: profilePictureUrlElevage != null
                              ? NetworkImage(profilePictureUrlElevage!) as ImageProvider
                              : null,
                          child: profilePictureUrlElevage == null
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                      ),
                      SizedBox(
                          width: UTILS.calculWidth(
                              10, UTILS.widthReference(context))),
                      GestureDetector(
                        onTap: () async {
                          String uidEleveur = widget.post['uidEleveur'];
                          DocumentSnapshot userDoc = await FirebaseFirestore
                              .instance
                              .collection('users')
                              .doc(uidEleveur)
                              .get();

                          if (userDoc.exists) {
                            var userData =
                                userDoc.data() as Map<String, dynamic>;

                            UserSelected user =
                                UserSelected.fromMap(userData, userDoc.id);

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    UserDetailPageFeed(user: user),
                              ),
                            );
                          } else {
                            print("L'utilisateur avec cet ID n'existe pas.");
                          }
                        },
                        child: Text(
                          nameElevage ?? 'Nom d\'élevage inconnu',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculHeight(
                                18, UTILS.heightReference(context)),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                      height: UTILS.calculHeight(
                          10, UTILS.heightReference(context))),
                  ExpandableText(
                    text: widget.post['desc']!,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: UTILS.calculHeight(30, UTILS.heightReference(context)),
            right: UTILS.calculWidth(5, UTILS.widthReference(context)),
            child: Column(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.white,
                  ),
                  onPressed: toggleLike,
                ),
                IconButton(
                  icon: Icon(Icons.message),
                  onPressed: openChatWithEleveur,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
