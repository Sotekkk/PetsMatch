import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:PetsMatch/pages/eleveur/elevage_gestion_select_menu.dart';
import 'package:PetsMatch/pages/eleveur/postDetail.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserElevageFeed extends StatefulWidget {
  const UserElevageFeed({super.key});

  @override
  State<UserElevageFeed> createState() => _UserElevageFeedState();
}

class _UserElevageFeedState extends State<UserElevageFeed>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isImagePickerActive = false;
  String? addressElevage;
  String? numeroElevage;
  String? profilePictureUrlElevage;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchElevageInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchElevageInfo() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      setState(() {
        addressElevage = doc.data()?['adressElevage'];
        numeroElevage = doc.data()?['numeroElevage'];
        profilePictureUrlElevage = doc.data()?['profilePictureUrlElevage'];
      });
    }
  }

  Future<void> _pickImage() async {
    if (_isImagePickerActive) return;
    try {
      setState(() => _isImagePickerActive = true);
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      setState(() {
        _imageFile = pickedFile != null ? File(pickedFile.path) : _imageFile;
        _isImagePickerActive = false;
      });
      if (_imageFile != null) await _uploadFile();
    } catch (e) {
      setState(() => _isImagePickerActive = false);
    }
  }

  Future<void> _uploadFile() async {
    if (_imageFile == null) return;
    try {
      final name = _imageFile!.path.split('/').last;
      final ref = FirebaseStorage.instance.ref().child('files/$name');
      final snapshot = await ref.putFile(_imageFile!);
      final url = await snapshot.ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(User_Info.uid)
          .update({'profilePictureUrlElevage': url});
      setState(() {
        profilePictureUrlElevage = url;
        _imageFile = null;
      });
    } catch (e) {
      print('Erreur upload: $e');
    }
  }

  Future<void> _openMap(String address) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$address';
    if (await canLaunch(url)) await launch(url);
  }

  Future<void> _callPhoneNumber(String phone) async {
    final url = 'tel:$phone';
    if (await canLaunch(url)) await launch(url);
  }

  Future<void> _deletePost(String postId) async {
    await FirebaseFirestore.instance.collection('post').doc(postId).delete();
    final liked = await FirebaseFirestore.instance.collection('likedPost').get();
    for (final doc in liked.docs) {
      final data = doc.data();
      if (data.containsKey(postId)) {
        data.remove(postId);
        await FirebaseFirestore.instance.collection('likedPost').doc(doc.id).set(data);
      }
    }
  }

  Future<void> _confirmDeletePost(String postId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: const Text('Voulez-vous vraiment supprimer ce post ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Non')),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _deletePost(postId);
            },
            child: const Text('Oui'),
          ),
        ],
      ),
    );
  }

  static const _defaultAvatar =
      'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            backgroundColor: const Color(0xFF1E2025),
            automaticallyImplyLeading: false,
            expandedHeight: 100,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 4, 50),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Mon Élevage',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => InfoUserSettings())),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
                        onSelected: (value) {
                          if (value == 'settings') {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) => SettingsMainPage()));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'settings',
                            child: Row(children: [
                              Icon(Icons.settings, size: 18),
                              SizedBox(width: 8),
                              Text('Paramètres', style: TextStyle(fontFamily: 'Galey')),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFF8484),
              labelColor: const Color(0xFFFF8484),
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Profil'),
                Tab(text: 'Publications'),
                Tab(text: 'Élevage'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildProfilTab(),
            _buildPublicationsTab(),
            _buildElevageTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.transparent,
                  backgroundImage: _imageFile != null
                      ? FileImage(_imageFile!) as ImageProvider
                      : CachedNetworkImageProvider(
                          profilePictureUrlElevage ?? _defaultAvatar),
                ),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFFFFB2AD),
                  child: const Icon(Icons.edit, size: 16, color: Colors.black),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            User_Info.nameElevage,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 20),
          if (addressElevage != null && addressElevage!.isNotEmpty)
            _InfoRow(
              icon: Icons.location_on_outlined,
              text: addressElevage!,
              onTap: () => _openMap(addressElevage!),
            ),
          if (numeroElevage != null && numeroElevage!.isNotEmpty)
            _InfoRow(
              icon: Icons.phone_outlined,
              text: numeroElevage!,
              onTap: () => _callPhoneNumber(numeroElevage!),
            ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E2025),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
              label: const Text('Modifier mon profil',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => InfoUserSettings())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicationsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('post')
          .where('uidEleveur', isEqualTo: _auth.currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();

        if (posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('Aucune publication',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        color: Colors.grey.shade500,
                        fontSize: 16)),
                const SizedBox(height: 8),
                Text('Allez dans l\'onglet Élevage pour créer une annonce',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        color: Colors.grey.shade400,
                        fontSize: 12)),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 100),
          itemCount: posts.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            final post = posts[index];
            return GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PostDetailPage(post: post))),
              onLongPress: () => _confirmDeletePost(post['id']),
              child: post['mediaStockage'].length > 1
                  ? CarouselSlider.builder(
                      itemCount: post['mediaStockage'].length,
                      itemBuilder: (_, i, __) => CachedNetworkImage(
                        imageUrl: post['mediaStockage'][i]['path'],
                        fit: BoxFit.cover,
                      ),
                      options: CarouselOptions(
                        viewportFraction: 1,
                        aspectRatio: 1,
                        enableInfiniteScroll: false,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: post['mediaStockage'][0]['path'],
                      fit: BoxFit.cover,
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildElevageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        children: [
          _ElevageActionCard(
            icon: Icons.add_photo_alternate_outlined,
            color: const Color(0xFFE3F2FD),
            iconColor: const Color(0xFF1E88E5),
            title: 'Publications',
            subtitle: 'Créer et gérer vos annonces',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ChoicePublicationType())),
          ),
          const SizedBox(height: 14),
          _ElevageActionCard(
            icon: Icons.pets,
            color: const Color(0xFFE8F5E9),
            iconColor: const Color(0xFF43A047),
            title: 'Gestion élevage',
            subtitle: 'Gérer vos animaux et reproductions',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ElevageSelectGestionPage())),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _InfoRow({required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElevageActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ElevageActionCard({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: Container(
            width: 48,
            height: 48,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          title: Text(title,
              style: const TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          subtitle: Text(subtitle,
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 12,
                  color: Colors.grey.shade600)),
          trailing: Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}
