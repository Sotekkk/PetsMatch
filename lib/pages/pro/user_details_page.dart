import 'package:PetsMatch/pages/eleveur/postDetail.dart';
import 'package:PetsMatch/pages/pro/partenaire.dart';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/utils.dart';

class UserDetailPage extends StatelessWidget {
  final User user;

  UserDetailPage({required this.user});

  Future<void> _openMap(String address) async {
    String googleUrl =
        'https://www.google.com/maps/search/?api=1&query=$address';
    String appleUrl = 'https://maps.apple.com/?q=$address';

    if (await canLaunch(googleUrl)) {
      await launch(googleUrl);
    } else if (await canLaunch(appleUrl)) {
      await launch(appleUrl);
    } else {
      throw 'Could not launch maps';
    }
  }

  Future<void> _callPhoneNumber(String phoneNumber) async {
    String telUrl = 'tel:$phoneNumber';

    if (await canLaunch(telUrl)) {
      await launch(telUrl);
    } else {
      throw 'Could not launch phone app';
    }
  }

  Future<void> _deletePost(String postId) async {
    final FirebaseFirestore _firestore = FirebaseFirestore.instance;
    await _firestore.collection('post').doc(postId).delete();

    // Suppression du post des likes des utilisateurs
    QuerySnapshot likedPostsSnapshot =
        await _firestore.collection('likedPost').get();
    for (var doc in likedPostsSnapshot.docs) {
      Map<String, dynamic> likedPosts = doc.data() as Map<String, dynamic>;
      if (likedPosts.containsKey(postId)) {
        likedPosts.remove(postId);
        await _firestore.collection('likedPost').doc(doc.id).set(likedPosts);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
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
                      height: UTILS.calculHeight(
                          141, UTILS.heightReference(context)),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(
                          53, UTILS.heightReference(context)),
                      left: UTILS.calculWidth(
                          40,
                          UTILS.widthReference(
                              context)), // Ajustez la valeur si nécessaire
                      right: UTILS.calculWidth(
                          40,
                          UTILS.widthReference(
                              context)), // Ajustez la valeur si nécessaire
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          user.nameElevage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(
                                20, UTILS.widthReference(context)),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(
                          42, UTILS.heightReference(context)),
                      left:
                          UTILS.calculWidth(10, UTILS.widthReference(context)),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: Colors.black), // Icône de la flèche noire
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                        backgroundColor: Colors.black,
                    radius: 39.5,
                    backgroundImage: user.profilePictureUrlElevage.isNotEmpty
                        ? NetworkImage(user.profilePictureUrlElevage)
                        : AssetImage('https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60')
                            as ImageProvider,
                  ),
                  SizedBox(
                      height: UTILS.calculHeight(
                          13, UTILS.heightReference(context))),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Photo de profil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                      ),
                    ),
                  ),
                  if (user.adressElevage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on,
                              size: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                              color: Colors.black),
                          SizedBox(
                              width: UTILS.calculWidth(
                                  8, UTILS.widthReference(context))),
                          GestureDetector(
                            onTap: () => _openMap(user.adressElevage),
                            child: Container(
                              width: UTILS.widthReference(context) *
                                  0.6, // Ajustez la largeur selon vos besoins
                              child: Text(
                                user.adressElevage,
                                style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w400,
                                  fontSize: UTILS.calculWidth(
                                      16, UTILS.widthReference(context)),
                                ),
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (user.numeroElevage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone,
                              size: UTILS.calculHeight(
                                  18, UTILS.heightReference(context)),
                              color: Colors.black),
                          SizedBox(
                              width: UTILS.calculWidth(
                                  8, UTILS.widthReference(context))),
                          GestureDetector(
                            onTap: () => _callPhoneNumber(user.numeroElevage),
                            child: Container(
                              width: UTILS.widthReference(context) *
                                  0.6, // Ajustez la largeur selon vos besoins
                              child: Text(
                                user.numeroElevage,
                                style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w400,
                                  fontSize: UTILS.calculWidth(
                                      16, UTILS.widthReference(context)),
                                ),
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                      height: UTILS.calculHeight(
                          13, UTILS.heightReference(context))),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('post')
                        .where('uidEleveur', isEqualTo: user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return CircularProgressIndicator();
                      }

                      final posts = snapshot.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        data['id'] = doc.id;
                        return data;
                      }).toList();

                      if (posts.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Aucun post à afficher.',
                            style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w400,
                              fontSize: UTILS.calculWidth(
                                  16, UTILS.widthReference(context)),
                            ),
                          ),
                        );
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: posts.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 5.0,
                          mainAxisSpacing: 5.0,
                        ),
                        itemBuilder: (context, index) {
                          final post = posts[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      PostDetailPage(post: post),
                                ),
                              );
                            },
                            onLongPress: () {},
                            child: post['mediaStockage'].length > 1
                                ? CarouselSlider.builder(
                                    itemCount: post['mediaStockage'].length,
                                    itemBuilder:
                                        (context, itemIndex, realIndex) {
                                      return Image.network(
                                        post['mediaStockage'][itemIndex]
                                            ['path'],
                                        fit: BoxFit.cover,
                                      );
                                    },
                                    options: CarouselOptions(
                                      viewportFraction: 1,
                                      aspectRatio: 1,
                                      enableInfiniteScroll: false,
                                    ),
                                  )
                                : Image.network(
                                    post['mediaStockage'][0]['path'],
                                    fit: BoxFit.cover,
                                  ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
