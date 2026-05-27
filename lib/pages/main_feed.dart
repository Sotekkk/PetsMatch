import 'dart:typed_data';
import 'dart:convert';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/filterpage.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'dart:math';

class UserSelected {
  final String uid;
  final String nameElevage;
  final String profilePictureUrlElevage;
  final String descEntreprise;
  final bool isPartenaire;
  final String catPro;
  final String professionPro;
  final String codeISOElevage;
  final String numeroElevage;
  final String adressElevage;
  final bool isValidate;
  final bool isElevage;
  final bool isPro;
  final bool isDog;
  final bool isCat;
  final List<String> dogBreeds;
  final List<String> catBreeds;
  final String villeElevage;
  final String codePostalElevage;
  final String paysElevage;
  final String siret;
  final String bannerUrl;

  UserSelected({
    required this.uid,
    required this.nameElevage,
    required this.profilePictureUrlElevage,
    required this.descEntreprise,
    required this.isPartenaire,
    required this.catPro,
    required this.professionPro,
    required this.codeISOElevage,
    required this.numeroElevage,
    required this.adressElevage,
    this.isValidate = false,
    this.isElevage = false,
    this.isPro = false,
    this.isDog = false,
    this.isCat = false,
    this.dogBreeds = const [],
    this.catBreeds = const [],
    this.villeElevage = '',
    this.codePostalElevage = '',
    this.paysElevage = '',
    this.siret = '',
    this.bannerUrl = '',
  });

  factory UserSelected.fromMap(Map<String, dynamic> data, String documentId) {
    return UserSelected(
      uid: documentId,
      nameElevage: data['nameElevage'] ?? 'Aucune information enregistrée',
      profilePictureUrlElevage: data['profilePictureUrlElevage'] ?? '',
      descEntreprise: data['descEntreprise'] ?? 'Aucune description disponible',
      isPartenaire: data['isPartenaire'] ?? false,
      catPro: data['catPro'] ?? '',
      professionPro: data['professionPro'] ?? '',
      codeISOElevage: data['codeISOElevage'] ?? '',
      numeroElevage: data['numeroElevage'] ?? '',
      adressElevage: data['adressElevage'] ?? '',
      isValidate: data['isValidate'] ?? false,
      isElevage: data['isElevage'] ?? false,
      isPro: data['isPro'] ?? false,
      isDog: data['isDog'] ?? false,
      isCat: data['isCat'] ?? false,
      dogBreeds: List<String>.from(data['dogBreeds'] ?? []),
      catBreeds: List<String>.from(data['catBreeds'] ?? []),
      villeElevage: data['villeElevage'] ?? '',
      codePostalElevage: data['codePostalElevage'] ?? '',
      paysElevage: data['paysElevage'] ?? '',
      siret: data['siret'] ?? '',
      bannerUrl: data['bannerUrl'] ?? '',
    );
  }
}

Future<void> likePost(String postId) async {
  String userId = FirebaseAuth.instance.currentUser!.uid;
  DocumentReference likeDoc =
      FirebaseFirestore.instance.collection('likedPost').doc(userId);

  await likeDoc.set({postId: true}, SetOptions(merge: true));
}

Future<void> dislikePost(String postId) async {
  String userId = FirebaseAuth.instance.currentUser!.uid;
  DocumentReference likeDoc =
      FirebaseFirestore.instance.collection('likedPost').doc(userId);

  await likeDoc.update({postId: FieldValue.delete()});
}

Future<bool> isPostLiked(String postId) async {
  try {
    String userId = FirebaseAuth.instance.currentUser!.uid;
    DocumentSnapshot likeDoc = await FirebaseFirestore.instance
        .collection('likedPost')
        .doc(userId)
        .get();

    if (likeDoc.exists) {
      if (likeDoc.data() is Map<String, dynamic>) {
        var data = likeDoc.data() as Map<String, dynamic>;
        return data.containsKey(postId);
      } else {
        print("Les données ne sont pas du type Map<String, dynamic>");
        return false;
      }
    } else {
      print("Le document n'existe pas");
      return false;
    }
  } catch (e) {
    print("Erreur lors de la vérification du like: $e");
    return false;
  }
}

Future<Position?> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  try {
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return null;
      }
    }

    return await Geolocator.getCurrentPosition();
  } catch (e) {
    print("Erreur de géolocalisation : $e");
    return null;
  }
}

class LatLng {
  final double latitude;
  final double longitude;
  LatLng(this.latitude, this.longitude);
}

Future<LatLng?> getLatLngFromAddress(String address) async {
  try {
    List<geocoding.Location> locations =
        await geocoding.locationFromAddress(address);
    if (locations.isNotEmpty) {
      return LatLng(locations.first.latitude, locations.first.longitude);
    }
  } catch (e) {
    print("Erreur de geocoding pour l'adresse : $address => $e");
  }
  return null;
}

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  List<Map<String, dynamic>> posts = [];
  bool isLoading = false;
  bool hasMore = true;
  int documentLimit = 15;
  DocumentSnapshot? lastDocument;

  // Filtres
  bool filterIsDog = false;
  bool filterIsCat = false;
  bool filterIsPuppy = false;
  bool filterIsAdult = false;
  bool filterIsSell = false;
  bool filterIsSailli = false;
  bool filterIsRetraite = false;
  bool filterIsLoof = false;
  bool filterIsLof = false;
  bool filterIsVaccined = false;
  bool filterIsMale = false;
  bool filterIsFemale = false;
  List<String> filterTags = [];
  List<String> tags = [];
  bool isEleveurTab = true; // Onglet actif par défaut

  final TextEditingController _tagController = TextEditingController();
  List<String> _suggestedTags = [];

  @override
  void initState() {
    super.initState();
    loadTags();
    fetchPosts();
  }

  Future<Set<String>> getBlockedUsers() async {
    String currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    DocumentSnapshot doc = await FirebaseFirestore.instance
        .collection('bloquer')
        .doc(currentUserUid)
        .get();

    if (!doc.exists) return {};

    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return data.keys.toSet();
  }

  Future<void> loadTags() async {
    String data = await rootBundle.loadString('assets/tags.json');
    final List<dynamic> jsonResult = json.decode(data);
    if (mounted) {
      setState(() {
        tags = List<String>.from(jsonResult);
      });
    }
  }

  Future<void> fetchPosts() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
    });

    try {
      Query query = FirebaseFirestore.instance.collection('post');

      // Sélection des posts selon l'onglet actif
      if (isEleveurTab) {
        query = query
            .where('isPro', isEqualTo: false)
            .orderBy('isUrgent', descending: true)
            .orderBy('isBoost', descending: true)
            .orderBy('timestamp', descending: true)
            .limit(documentLimit);
      } else {
        query = query
            .where('isPro', isEqualTo: true)
            .orderBy('timestamp', descending: true)
            .limit(documentLimit);
      }

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument!);
      }

      // Filtres appliqués aux deux types pour l’instant
      if (filterIsDog) query = query.where('isDog', isEqualTo: true);
      if (filterIsCat) query = query.where('isCat', isEqualTo: true);
      if (filterIsPuppy) {
        query = query.where('moreEightWeeks', whereIn: [true, false]);
      }
      if (filterIsAdult) query = query.where('isAdult', isEqualTo: true);
      if (filterIsSell) query = query.where('isSell', isEqualTo: true);
      if (filterIsSailli) query = query.where('isSailli', isEqualTo: true);
      if (filterIsRetraite) query = query.where('isRetraite', isEqualTo: true);
      if (filterIsLoof) query = query.where('isLoof', isEqualTo: true);
      if (filterIsLof) query = query.where('isLof', isEqualTo: true);
      if (filterIsVaccined) query = query.where('isVaccined', isEqualTo: true);
      if (filterIsMale) query = query.where('isMale', isEqualTo: true);
      if (filterIsFemale) query = query.where('isMale', isEqualTo: false);

      QuerySnapshot querySnapshot = await query.get();

      if (querySnapshot.docs.isNotEmpty) {
        lastDocument = querySnapshot.docs.last;
        Set<String> blockedUsers = await getBlockedUsers();

        for (var doc in querySnapshot.docs) {
          Map<String, dynamic> post = doc.data() as Map<String, dynamic>;
          String uidEleveur = post['uidEleveur'];

          if (blockedUsers.contains(uidEleveur)) continue;

          post['postId'] = doc.id;

          DocumentSnapshot userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uidEleveur)
              .get();

          if (userDoc.exists) {
            var userData = userDoc.data() as Map<String, dynamic>;
            String adressElevage = userData['adressElevage'] ?? '';
            if (adressElevage.isNotEmpty) {
              LatLng? coords = await getLatLngFromAddress(adressElevage);
              if (coords != null) {
                post['latitude'] = coords.latitude;
                post['longitude'] = coords.longitude;
              } else {
                post['latitude'] = null;
                post['longitude'] = null;
              }
            } else {
              post['latitude'] = null;
              post['longitude'] = null;
            }

            post['profilePictureUrlElevage'] = userData[
                    'profilePictureUrlElevage'] ??
                'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
            post['nameElevage'] = userData['nameElevage'] ?? 'Elevage Inconnu';
          } else {
            post['profilePictureUrlElevage'] =
                'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';
            post['nameElevage'] = 'Elevage Inconnu';
          }

          posts.add(post);
        }

        // Si on est dans l’onglet Éleveur, on trie urgent / boost / normal
        if (isEleveurTab || !isEleveurTab) {
          // donc les 2 cas, tu peux enlever la condition

          List<Map<String, dynamic>> urgentPosts = [];
          List<Map<String, dynamic>> boostPosts = [];
          List<Map<String, dynamic>> regularPosts = [];

          Position? userPosition = await determinePosition();
          LatLng? userCoords;
          if (userPosition != null) {
            userCoords = LatLng(userPosition.latitude, userPosition.longitude);
          }

          for (var post in posts) {
            if (post['latitude'] != null &&
                post['longitude'] != null &&
                userCoords != null) {
              double distanceInMeters = Geolocator.distanceBetween(
                userCoords.latitude,
                userCoords.longitude,
                post['latitude'],
                post['longitude'],
              );
              post['distance'] = distanceInMeters;
            } else {
              post['distance'] = double.infinity;
            }

            if (post['isUrgent'] == true) {
              urgentPosts.add(post);
            } else if (post['isBoost'] == true) {
              boostPosts.add(post);
            } else {
              regularPosts.add(post);
            }
          }

          urgentPosts.sort((a, b) => (a['distance']).compareTo(b['distance']));
          boostPosts.sort((a, b) => (a['distance']).compareTo(b['distance']));
          regularPosts.sort((a, b) => (a['distance']).compareTo(b['distance']));

          posts = [...urgentPosts, ...boostPosts, ...regularPosts];
        }
      } else {
        setState(() {
          hasMore = false;
        });
      }
    } catch (e) {
      print("Erreur lors de la récupération des posts : $e");
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> refreshPosts() async {
    setState(() {
      posts.clear();
      lastDocument = null;
      hasMore = true;
    });
    await fetchPosts();
  }

  void openFilterPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FilterPage(
          filterIsDog: filterIsDog,
          filterIsCat: filterIsCat,
          filterIsPuppy: filterIsPuppy,
          filterIsAdult: filterIsAdult,
          filterIsSell: filterIsSell,
          filterIsSailli: filterIsSailli,
          filterIsRetraite: filterIsRetraite,
          filterIsLoof: filterIsLoof,
          filterIsLof: filterIsLof,
          filterIsVaccined: filterIsVaccined,
          filterIsMale: filterIsMale,
          filterIsFemale: filterIsFemale,
          filterTags: filterTags,
          tags: tags,
          refreshPosts: refreshPosts,
          onApplyFilters: (newFilters, newTags) {
            setState(() {
              filterIsDog = newFilters['filterIsDog'] ?? false;
              filterIsCat = newFilters['filterIsCat'] ?? false;
              filterIsPuppy = newFilters['filterIsPuppy'] ?? false;
              filterIsAdult = newFilters['filterIsAdult'] ?? false;
              filterIsSell = newFilters['filterIsSell'] ?? false;
              filterIsSailli = newFilters['filterIsSailli'] ?? false;
              filterIsRetraite = newFilters['filterIsRetraite'] ?? false;
              filterIsLoof = newFilters['filterIsLoof'] ?? false;
              filterIsLof = newFilters['filterIsLof'] ?? false;
              filterIsVaccined = newFilters['filterIsVaccined'] ?? false;
              filterIsMale = newFilters['filterIsMale'] ?? false;
              filterIsFemale = newFilters['filterIsFemale'] ?? false;
              filterTags = newTags;
            });
          },
        ),
      ),
    );

    if (result != null) {
      refreshPosts(); // Rafraîchit les posts après l'application des filtres
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: Colors.white,
        backgroundColor: Color(0xFF6E9E57),
        onRefresh: refreshPosts,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (!isLoading &&
                hasMore &&
                scrollInfo.metrics.pixels ==
                    scrollInfo.metrics.maxScrollExtent) {
              fetchPosts();
              return true;
            }
            return false;
          },
          child: Stack(
            children: [
              posts.isEmpty
                  ? Center(
                      child: Container(
                        color: Colors.transparent,
                        child: Text(
                          "Aucun post de publier",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: UTILS.calculHeight(
                                20, UTILS.heightReference(context)),
                          ),
                        ),
                      ),
                    )
                  : PageView.builder(
                      scrollDirection: Axis.vertical,
                      itemCount: posts.length + 1,
                      onPageChanged: (index) {
                        if (index + 1 < posts.length) {
                          for (var media in posts[index + 1]['mediaStockage']) {
                            if (media['isPhoto']) {
                              precacheImage(
                                  NetworkImage(media['path']), context);
                            }
                          }
                        }
                      },
                      itemBuilder: (context, index) {
                        if (index == posts.length) {
                          return hasMore
                              ? Center(child: CircularProgressIndicator())
                              : Center(
                                  child: Text("Aucun post supplémentaire"));
                        }

                        return PostWidget(
                          post: posts[index],
                          onLikePressed: () {},
                          onRefreshRequested: refreshPosts,
                        );
                      },
                    ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height:
                      UTILS.calculHeight(120, UTILS.heightReference(context)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.black.withOpacity(0.0),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 0.0, vertical: 0.0),
                    child: Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            top: UTILS.calculHeight(
                                55,
                                UTILS.heightReference(
                                    context)), // ✅ Décalé vers le bas
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (!isEleveurTab) {
                                    setState(() {
                                      isEleveurTab = true;
                                      posts.clear();
                                      lastDocument = null;
                                      hasMore = true;
                                    });
                                    fetchPosts();
                                  }
                                },
                                child: Column(
                                  children: [
                                    Text(
                                      'Éleveur',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(
                                            isEleveurTab ? 1.0 : 0.5),
                                        fontWeight: FontWeight.bold,
                                        fontSize: UTILS.calculHeight(
                                            18, UTILS.heightReference(context)),
                                      ),
                                    ),
                                    if (isEleveurTab)
                                      Container(
                                        height: 2,
                                        width: 60,
                                        margin: EdgeInsets.only(top: 4),
                                        color: Colors.white,
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 20),
                              GestureDetector(
                                onTap: () {
                                  if (isEleveurTab) {
                                    setState(() {
                                      isEleveurTab = false;
                                      posts.clear();
                                      lastDocument = null;
                                      hasMore = true;
                                    });
                                    fetchPosts();
                                  }
                                },
                                child: Column(
                                  children: [
                                    Text(
                                      'Professionnel',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(
                                            isEleveurTab ? 0.5 : 1.0),
                                        fontWeight: FontWeight.bold,
                                        fontSize: UTILS.calculHeight(
                                            18, UTILS.heightReference(context)),
                                      ),
                                    ),
                                    if (!isEleveurTab)
                                      Container(
                                        height: 2,
                                        width: 100,
                                        margin: EdgeInsets.only(top: 4),
                                        color: Colors.white,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: UTILS.calculHeight(
                              45, UTILS.heightReference(context)),
                          child: IconButton(
                            icon: ImageIcon(
                                AssetImage('assets/icon/icon_filter.png')),
                            onPressed: () {
                              if (isEleveurTab) {
                                openFilterPage(); // Ton filtre existant
                              } else {
                                // Tu peux créer une autre page pour les pros plus tard
                                openFilterPage(); // Pour l'instant on garde le même
                              }
                            },
                            color: Colors.white,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: UTILS.calculHeight(
                              40, UTILS.heightReference(context)),
                          child: IconButton(
                            icon: Icon(Icons.refresh),
                            onPressed: refreshPosts,
                            color: Colors.white,
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
      ),
    );
  }
}

class PostWidget extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onLikePressed;
  final VoidCallback onRefreshRequested; // 👈

  PostWidget({
    required this.post,
    required this.onLikePressed,
    required this.onRefreshRequested, // 👈
  });

  @override
  _PostWidgetState createState() => _PostWidgetState();
}

class _PostWidgetState extends State<PostWidget> {
  bool isLiked = false;
  VideoPlayerController? _videoController;
  Uint8List? _videoThumbnail;
  bool _showFullDescription = false;
  final GlobalKey _menuKey = GlobalKey();
  int _currentMediaIndex = 0;

  @override
  void initState() {
    super.initState();
    checkIfLiked();
    initializeMedia();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    preloadCurrentPostImages();
  }

  void preloadCurrentPostImages() {
    for (var media in widget.post['mediaStockage']) {
      if (media['isPhoto']) {
        final image = Image.network(media['path']);
        precacheImage(image.image, context);
      }
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
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  Future<void> checkIfLiked() async {
    bool liked = await isPostLiked(widget.post['postId']);
    if (mounted) {
      setState(() {
        isLiked = liked;
      });
    }
  }

  void toggleLike() async {
    if (isLiked) {
      await dislikePost(widget.post['postId']);
    } else {
      await likePost(widget.post['postId']);
    }
    if (mounted) {
      setState(() {
        isLiked = !isLiked;
      });
    }
  }

  void toggleDescription() {
    setState(() {
      _showFullDescription = !_showFullDescription;
    });
  }

  String buildAnimalDetails() {
    String animalType = widget.post['isCat'] == true
        ? "Chat"
        : widget.post['isDog'] == true
            ? "Chien"
            : "Aucune information enregistrée";

    String race = (widget.post['tags'] != null &&
            widget.post['tags'] is List &&
            widget.post['tags'].isNotEmpty &&
            widget.post['tags'][0] is Map &&
            widget.post['tags'][0]['tag'] != null)
        ? widget.post['tags'][0]['tag']
        : "Aucune information enregistrée";

    String ageCategory;
    if (widget.post['isAdult'] == true) {
      ageCategory = "Adulte";
    } else if (widget.post['moreEightWeeks'] == true) {
      ageCategory = "+ de 8 semaines";
    } else if (widget.post['isAdult'] == false &&
        widget.post['moreEightWeeks'] == false) {
      ageCategory = "- de 8 semaines";
    } else {
      ageCategory = "Aucune information enregistrée";
    }

    String dateOfBirth =
        widget.post['dateOfBirth'] ?? "Aucune information enregistrée";

    String typeVente;
    if (widget.post['isRetraite'] == true) {
      typeVente = "Retraite";
    } else if (widget.post['isSailli'] == true) {
      typeVente = "Saillie";
    } else if (widget.post['isSell'] == true) {
      typeVente = "Vente";
    } else {
      typeVente = "Aucune information enregistrée";
    }

    String vaccinationStatus =
        widget.post['isVaccined'] == true ? "Vacciné" : "Non vacciné";

    String lofLoofStatus;
    if (widget.post['isCat'] == true) {
      lofLoofStatus = widget.post['isLoof'] == true ? "Loof" : "Non Loof";
    } else if (widget.post['isDog'] == true) {
      lofLoofStatus = widget.post['isLof'] == true ? "Lof" : "Non Lof";
    } else {
      lofLoofStatus = "Aucune information enregistrée";
    }

    String puceNumber;
    if (widget.post['isAdult'] == false &&
        widget.post['moreEightWeeks'] == false) {
      puceNumber =
          "Puce de la mère: ${widget.post['puceMotherNumber'] ?? "Aucune information enregistrée"}";
    } else {
      puceNumber =
          "Puce de l'animal: ${widget.post['puceNumber'] ?? "Aucune information enregistrée"}";
    }
    String price = widget.post['price'] != null &&
            widget.post['price'].toString().isNotEmpty
        ? "${widget.post['price']} €"
        : "Aucun prix ajouté";

    return "Type d'animal : $animalType\n"
        "Prix : $price\n"
        "Race : $race\n"
        "Âge : $ageCategory\n"
        "Date de naissance : $dateOfBirth\n"
        "Type de vente : $typeVente\n"
        "Vaccination : $vaccinationStatus\n"
        "Statut : $lofLoofStatus\n"
        "$puceNumber";
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
        'categorie': 'annonces',
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

  Future<SendReport> _sendSignalementEmail({
    required String uidSignaleur,
    required String uidSignale,
    required String motif,
    String? details,
  }) async {
    String username = 'petsmatch.contact@gmail.com';
    String password = 'dppu ctgp buve bxjd'; // mot de passe d'application Gmail

    final smtpServer = gmail(username, password);

    final message = Message()
      ..from = Address(username, 'PetsMatch - Signalement')
      ..recipients.add('petsmatch.contact@gmail.com')
      ..subject = '🔔 Signalement utilisateur : $uidSignale'
      ..text = '''
Un utilisateur a été signalé via l'application PetsMatch.

🔹 UID de l'utilisateur signalé : $uidSignale
🔹 UID de la personne ayant signalé : $uidSignaleur
🔹 Motif : $motif
🔹 Détails : ${details ?? "Non précisé"}

Veuillez traiter ce signalement sous 24h conformément aux CGU.

- PetsMatch App
    ''';

    try {
      final sendReport = await send(message, smtpServer);
      print('Signalement envoyé : ${sendReport.toString()}');
      return sendReport;
    } on MailerException catch (e) {
      print('Erreur envoi signalement : $e');
      for (var p in e.problems) {
        print('Problème: ${p.code}: ${p.msg}');
      }
      rethrow; // Rethrow the exception to ensure the function doesn't complete normally
    }
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
    return Stack(
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
                    onPageChanged: (index, reason) {
                      setState(() {
                        _currentMediaIndex = index;
                      });
                    },
                  ),
                  items: widget.post['mediaStockage'].map<Widget>((media) {
                    if (media['isPhoto']) {
                      return Container(
                        color: Colors.black,
                        child: Center(
                            child: CachedNetworkImage(
                          imageUrl: media['path'],
                          fit: BoxFit.contain,
                          errorWidget: (context, url, error) =>
                              Icon(Icons.error, color: Colors.red),
                        )),
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
                                  : Center(child: CircularProgressIndicator()),
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
                  Colors.black.withOpacity(1.0),
                  Colors.black.withOpacity(0.0),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ajout du titre de la publication
                Text(
                  widget.post['title'] ?? 'Aucun titre à la publication',
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w600,
                    fontSize:
                        UTILS.calculHeight(18, UTILS.heightReference(context)),
                    color: Colors.white,
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(5, UTILS.heightReference(context))),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        DocumentSnapshot userDoc = await FirebaseFirestore
                            .instance
                            .collection('users')
                            .doc(widget.post['uidEleveur'])
                            .get();

                        if (userDoc.exists) {
                          var userData = userDoc.data() as Map<String, dynamic>;

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
                        backgroundImage: (widget.post['profilePictureUrlElevage'] != null &&
                                widget.post['profilePictureUrlElevage'] != 'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60')
                            ? NetworkImage(widget.post['profilePictureUrlElevage']) as ImageProvider
                            : null,
                        child: (widget.post['profilePictureUrlElevage'] == null ||
                                widget.post['profilePictureUrlElevage'] == 'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60')
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                    ),
                    SizedBox(
                        width: UTILS.calculWidth(
                            10, UTILS.widthReference(context))),
                    GestureDetector(
                      onTap: () async {
                        DocumentSnapshot userDoc = await FirebaseFirestore
                            .instance
                            .collection('users')
                            .doc(widget.post['uidEleveur'])
                            .get();

                        if (userDoc.exists) {
                          var userData = userDoc.data() as Map<String, dynamic>;

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
                        widget.post['nameElevage'] ?? 'Nom non disponible',
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
                    height:
                        UTILS.calculHeight(10, UTILS.heightReference(context))),
                GestureDetector(
                  onTap: toggleDescription,
                  child: _showFullDescription
                      ? Container(
                          width: double.infinity,
                          constraints: BoxConstraints(
                            maxHeight: UTILS.calculHeight(
                                450, UTILS.heightReference(context)),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: UTILS.calculWidth(
                                12, UTILS.widthReference(context)),
                            vertical: UTILS.calculHeight(
                                4, UTILS.heightReference(context)),
                          ),
                          child: SingleChildScrollView(
                            child: Stack(
                              children: [
                                // contour noir
                                Text(
                                  buildAnimalDetails() +
                                      "\n\n" +
                                      (widget.post['desc'] ??
                                          'Description non disponible'),
                                  style: TextStyle(
                                    fontSize: UTILS.calculHeight(
                                        18, UTILS.heightReference(context)),
                                    fontFamily: 'Galey',
                                    fontWeight: FontWeight.w500,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 1.5
                                      ..color =
                                          const Color.fromARGB(131, 0, 0, 0),
                                  ),
                                ),
                                // texte blanc
                                Text(
                                  buildAnimalDetails() +
                                      "\n\n" +
                                      (widget.post['desc'] ??
                                          'Description non disponible'),
                                  style: TextStyle(
                                    fontSize: UTILS.calculHeight(
                                        18, UTILS.heightReference(context)),
                                    fontFamily: 'Galey',
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Text(
                          'En savoir plus...',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculHeight(
                                16, UTILS.heightReference(context)),
                            color: Color(0xFFA7C79A),
                          ),
                        ),
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
              IconButton(
                key: _menuKey,
                icon: Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {
                  final RenderBox button =
                      _menuKey.currentContext!.findRenderObject() as RenderBox;
                  final RenderBox overlay = Overlay.of(context)
                      .context
                      .findRenderObject() as RenderBox;
                  final Offset position =
                      button.localToGlobal(Offset.zero, ancestor: overlay);

                  showMenu(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      position.dx,
                      position.dy,
                      overlay.size.width - position.dx,
                      overlay.size.height - position.dy,
                    ),
                    items: [
                      PopupMenuItem(
                        value: 'signaler',
                        child: Row(
                          children: [
                            Icon(Icons.report, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Signaler'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'bloquer',
                        child: Row(
                          children: [
                            Icon(Icons.block, color: Colors.black),
                            SizedBox(width: 8),
                            Text('Bloquer'),
                          ],
                        ),
                      ),
                    ],
                  ).then((value) async {
                    if (value == 'signaler') {
                      String selectedMotif = 'Comportement abusif';
                      TextEditingController detailController =
                          TextEditingController();

                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return StatefulBuilder(
                            builder: (context, setState) => AlertDialog(
                              title: Text('Signaler le post'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RadioListTile(
                                      title: Text('Comportement abusif'),
                                      value: 'Comportement abusif',
                                      groupValue: selectedMotif,
                                      onChanged: (value) => setState(
                                          () => selectedMotif = value!),
                                    ),
                                    RadioListTile(
                                      title: Text('Contenu inapproprié'),
                                      value: 'Contenu inapproprié',
                                      groupValue: selectedMotif,
                                      onChanged: (value) => setState(
                                          () => selectedMotif = value!),
                                    ),
                                    RadioListTile(
                                      title: Text('Spam ou arnaque'),
                                      value: 'Spam ou arnaque',
                                      groupValue: selectedMotif,
                                      onChanged: (value) => setState(
                                          () => selectedMotif = value!),
                                    ),
                                    RadioListTile(
                                      title: Text('Autre'),
                                      value: 'Autre',
                                      groupValue: selectedMotif,
                                      onChanged: (value) => setState(
                                          () => selectedMotif = value!),
                                    ),
                                    SizedBox(height: 10),
                                    Container(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: TextField(
                                        controller: detailController,
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Détails (facultatif)',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Annuler'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF6E9E57), // Couleur de fond du bouton
                                  ),
                                  onPressed: () async {
                                    try {
                                      await _sendSignalementEmail(
                                        uidSignaleur: FirebaseAuth
                                            .instance.currentUser!.uid,
                                        uidSignale: widget.post['uidEleveur'],
                                        motif: selectedMotif,
                                        details: detailController.text.trim(),
                                      );

                                      // ignore: use_build_context_synchronously
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '✅ Signalement envoyé avec succès.')),
                                      );
                                      Navigator.pop(
                                          context); // Ferme la boîte de dialogue
                                    } catch (e) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '❌ Erreur lors de l\'envoi du signalement.')),
                                      );
                                      Navigator.pop(
                                          context); // Ferme la boîte de dialogue
                                    }
                                  },
                                  child: Text('Envoyer',
                                      style: TextStyle(
                                        color: Colors.white,
                                      )),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    } else if (value == 'bloquer') {
                      String currentUserUid =
                          FirebaseAuth.instance.currentUser!.uid;
                      String blockedUserUid = widget.post['uidEleveur'];

                      await FirebaseFirestore.instance
                          .collection('bloquer')
                          .doc(currentUserUid)
                          .set({blockedUserUid: true}, SetOptions(merge: true));

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('🚫 Utilisateur bloqué avec succès.'),
                        ),
                      );

// Appelle le callback pour rafraîchir la liste
                      widget.onRefreshRequested();
                    }
                  });
                },
              )
            ],
          ),
        ),
        // Affichage du nombre de médias (photo/vidéo)

        Positioned(
          top: UTILS.calculHeight(100, UTILS.heightReference(context)),
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children:
                List.generate(widget.post['mediaStockage'].length, (index) {
              return Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentMediaIndex == index
                      ? Colors.white
                      : Colors.white.withOpacity(0.4),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class ExpandableText extends StatefulWidget {
  final String text;

  ExpandableText({required this.text});

  @override
  _ExpandableTextState createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _isExpanded = false;
  static const int _maxLines = 3;
  bool _isLongText = false;
  final GlobalKey _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final textHeight = _textKey.currentContext!.size!.height;
      final lineHeight = calculateLineHeight(context);
      final numberOfLines = textHeight / lineHeight;
      setState(() {
        _isLongText = numberOfLines > _maxLines;
      });
    });
  }

  double calculateLineHeight(BuildContext context) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: 'A',
        style: TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    return textPainter.size.height;
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleExpand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: UTILS.calculWidth(332, UTILS.widthReference(context)),
            child: Text(
              widget.text,
              key: _textKey,
              maxLines: _isExpanded ? null : _maxLines,
              overflow:
                  _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                fontSize:
                    UTILS.calculHeight(13, UTILS.heightReference(context)),
                color: Colors.white,
              ),
            ),
          ),
          if (!_isExpanded && _isLongText)
            Text(
              '... voir plus',
              style: TextStyle(
                color: Color(0xFF6E9E57),
              ),
            ),
        ],
      ),
    );
  }
}
