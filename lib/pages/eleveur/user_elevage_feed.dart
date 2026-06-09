import 'dart:async';
import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:PetsMatch/pages/eleveur/elevage_gestion_select_menu.dart';
import 'package:PetsMatch/pages/eleveur/postDetail.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  final _supa = Supabase.instance.client;
  File? _imageFile;
  bool _isImagePickerActive = false;
  String? addressElevage;
  String? numeroElevage;
  String? profilePictureUrlElevage;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Perdus tab
  List<Map<String, dynamic>> _alertes = [];
  bool _loadingAlertes = false;
  List<Map<String, dynamic>> _eleveurAnimaux = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchElevageInfo();
    _fetchAlertes();
    _fetchEleveurAnimaux();
    _tabController.addListener(() {
      if (_tabController.index == 3) _fetchAlertes();
    });
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
      final f = await pickAndCropSquare();
      setState(() {
        _imageFile = f ?? _imageFile;
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
      final uid = _auth.currentUser?.uid ?? 'unknown';
      final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await uploadPhoto(_imageFile!, 'profiles/$uid/$name');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(User_Info.uid)
          .update({'profilePictureUrlElevage': url});
      setState(() {
        profilePictureUrlElevage = url;
        _imageFile = null;
      });
    } catch (e) {
      debugPrint('Erreur upload: $e');
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
                            MaterialPageRoute(builder: (_) => User_Info.isPro ? ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null) : ProfilEleveurEditPage())),
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
              indicatorColor: const Color(0xFF6E9E57),
              labelColor: const Color(0xFF6E9E57),
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Profil'),
                Tab(text: 'Publications'),
                Tab(text: 'Élevage'),
                Tab(text: 'Perdus'),
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
            _buildPerdusTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchAlertes() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loadingAlertes = true);
    try {
      final data = await _supa
          .from('alertes_perdus')
          .select()
          .eq('uid_proprietaire', uid)
          .order('created_at', ascending: false);
      setState(() {
        _alertes = List<Map<String, dynamic>>.from(data);
        _loadingAlertes = false;
      });
    } catch (_) {
      setState(() => _loadingAlertes = false);
    }
  }

  Future<void> _fetchEleveurAnimaux() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('animaux')
          .where('uid_eleveur', isEqualTo: uid)
          .get();
      setState(() {
        _eleveurAnimaux = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      });
    } catch (_) {}
  }

  Future<void> _retrouveAlerte(String id) async {
    try {
      await _supa.from('alertes_perdus').update({
        'statut': 'retrouve',
        'date_retrouve': DateTime.now().toIso8601String().substring(0, 10),
      }).eq('id', id);
      setState(() {
        final idx = _alertes.indexWhere((a) => a['id'] == id);
        if (idx >= 0) _alertes[idx] = {..._alertes[idx], 'statut': 'retrouve'};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteAlerte(String id) async {
    try {
      await _supa.from('alertes_perdus').delete().eq('id', id);
      setState(() => _alertes.removeWhere((a) => a['id'] == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _editAlerte(Map<String, dynamic> a) async {
    final updated = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => AlertePerduFormPage(
        alerteId: a['id'] as String?,
        animalId: a['animal_id'] as String?,
        photoUrl: a['photo_url'] as String?,
      ),
    ));
    if (updated == true) _fetchAlertes();
  }

  void _showUpdateLocationSheet(String alerteId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _UpdateLocationSheet(
        alerteId: alerteId,
        onSaved: () { Navigator.pop(ctx); _fetchAlertes(); },
      ),
    );
  }

  void _showAnimalPickerForAlerte() {
    if (_eleveurAnimaux.isEmpty) {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AlertePerduFormPage()))
          .then((_) => _fetchAlertes());
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Quel animal est perdu ?',
                  style: TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          ..._eleveurAnimaux.map((a) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEEF5EA),
                  child: a['photo_url'] != null && (a['photo_url'] as String).isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                              imageUrl: a['photo_url'] as String,
                              width: 40, height: 40, fit: BoxFit.cover))
                      : Text(
                          (a['nom'] as String? ?? '?').isNotEmpty
                              ? (a['nom'] as String)[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
                title: Text(a['nom'] ?? 'Sans nom',
                    style: const TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                subtitle: a['espece'] != null
                    ? Text(_capitalize(a['espece'] as String),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12))
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlertePerduFormPage(
                        animalId: a['id'] as String?,
                        nom: a['nom'] as String?,
                        espece: a['espece'] as String?,
                        race: a['race'] as String?,
                        sexe: a['sexe'] as String?,
                        couleur: a['couleur'] as String?,
                        photoUrl: a['photo_url'] as String?,
                      ),
                    ),
                  ).then((_) => _fetchAlertes());
                },
              )),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFF3E0),
              child: Icon(Icons.add, color: Colors.orange),
            ),
            title: const Text('Autre animal (non enregistré)',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AlertePerduFormPage()))
                  .then((_) => _fetchAlertes());
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPerdusTab() {
    return Stack(
      children: [
        _loadingAlertes
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
            : _alertes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_searching,
                            size: 72, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Aucune alerte active',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 16,
                                color: Colors.grey.shade500)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Déclarez un animal perdu via le bouton +',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 13,
                                color: Colors.grey.shade400),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchAlertes,
                    color: const Color(0xFF6E9E57),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _alertes.length,
                      itemBuilder: (_, i) => _AlerteCard(
                        data: _alertes[i],
                        onRetrouve: () => _retrouveAlerte(_alertes[i]['id']),
                        onDelete: () => _deleteAlerte(_alertes[i]['id']),
                        onEdit: () => _editAlerte(_alertes[i]),
                        onUpdateLocation: () => _showUpdateLocationSheet(_alertes[i]['id']),
                      ),
                    ),
                  ),
        Positioned(
          right: 16,
          bottom: 90,
          child: FloatingActionButton(
            heroTag: 'add_alerte_eleveur_fab',
            backgroundColor: Colors.orange.shade700,
            onPressed: _showAnimalPickerForAlerte,
            child: const Icon(Icons.add_location_alt, color: Colors.white),
          ),
        ),
      ],
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
                  backgroundColor: const Color(0xFF6E9E57),
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
                  MaterialPageRoute(builder: (_) => User_Info.isPro ? ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null) : ProfilEleveurEditPage())),
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
            iconColor: const Color(0xFF6E9E57),
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

// ── Alerte card ───────────────────────────────────────────────────────────────

class _AlerteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onRetrouve;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onUpdateLocation;

  const _AlerteCard({required this.data, required this.onRetrouve, required this.onDelete,
      required this.onEdit, required this.onUpdateLocation});

  @override
  Widget build(BuildContext context) {
    final nom     = data['nom_animal'] as String? ?? 'Animal inconnu';
    final espece  = data['espece'] as String?;
    final sexe    = data['sexe'] as String?;
    final loc     = data['derniere_localisation'] as String?;
    final statut  = data['statut'] as String? ?? 'perdu';
    final photoUrl = data['photo_url'] as String?;
    final numero  = data['numero_alerte'] as String?;
    final retrouve = statut == 'retrouve';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: retrouve ? const Color(0xFF6E9E57) : Colors.orange.shade300,
            width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl, width: 56, height: 56, fit: BoxFit.cover)
                  : Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: retrouve
                            ? const Color(0xFFEEF5EA)
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Icon(Icons.pets,
                          color: retrouve
                              ? const Color(0xFF6E9E57)
                              : Colors.orange.shade700,
                          size: 28),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(nom,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: retrouve
                              ? const Color(0xFFEEF5EA)
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          retrouve ? 'Retrouvé' : 'Perdu',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: retrouve
                                  ? const Color(0xFF6E9E57)
                                  : Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ),
                      if (espece != null || sexe != null)
                    Text(
                      [if (espece != null) _capitalize(espece),
                       if (sexe != null && sexe.isNotEmpty) _capitalize(sexe)].join(' · '),
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                    ),
                  if (loc != null && loc.isNotEmpty)
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: 12, color: Colors.orange.shade600),
                      const SizedBox(width: 3),
                      Expanded(child: Text(loc,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  if (numero != null && numero.isNotEmpty)
                    Text('N° $numero',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                            color: Colors.orange.shade400, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
              onSelected: (v) {
                if (v == 'retrouve') onRetrouve();
                if (v == 'edit') onEdit();
                if (v == 'location') onUpdateLocation();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit',
                  child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6E9E57)),
                      SizedBox(width: 8), Text('Modifier l\'alerte', style: TextStyle(fontFamily: 'Galey'))])),
                const PopupMenuItem(value: 'location',
                  child: Row(children: [Icon(Icons.my_location, size: 18, color: Color(0xFFE65100)),
                      SizedBox(width: 8), Text('Mettre à jour le lieu', style: TextStyle(fontFamily: 'Galey'))])),
                if (!retrouve)
                  const PopupMenuItem(value: 'retrouve',
                    child: Row(children: [Icon(Icons.check_circle_outline, color: Color(0xFF6E9E57), size: 18),
                        SizedBox(width: 8), Text('Marquer retrouvé', style: TextStyle(fontFamily: 'Galey'))])),
                const PopupMenuItem(value: 'delete',
                  child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8), Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Update location bottom sheet ──────────────────────────────────────────────

class _UpdateLocationSheet extends StatefulWidget {
  final String alerteId;
  final VoidCallback onSaved;
  const _UpdateLocationSheet({required this.alerteId, required this.onSaved});

  @override
  State<_UpdateLocationSheet> createState() => _UpdateLocationSheetState();
}

class _UpdateLocationSheetState extends State<_UpdateLocationSheet> {
  final _supa = Supabase.instance.client;
  late final GoogleMapsPlaces _places;
  Timer? _debounce;

  final _searchCtrl = TextEditingController();
  final _rueCtrl    = TextEditingController();
  final _cpCtrl     = TextEditingController();
  final _villeCtrl  = TextEditingController();

  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  bool _locating = false;
  bool _saving = false;
  double? _lat, _lng;

  static const _orange = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _places.dispose();
    _searchCtrl.dispose();
    _rueCtrl.dispose();
    _cpCtrl.dispose();
    _villeCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _lat = null; _lng = null;
    _debounce?.cancel();
    if (val.trim().length < 3) {
      setState(() { _predictions = []; _loadingPredictions = false; });
      return;
    }
    setState(() => _loadingPredictions = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetchPredictions(val));
  }

  Future<void> _fetchPredictions(String input) async {
    try {
      final res = await _places.autocomplete(input,
          components: [Component(Component.country, 'fr'), Component(Component.country, 'be'),
                       Component(Component.country, 'ch'), Component(Component.country, 'lu')],
          language: 'fr');
      if (!mounted) return;
      setState(() { _predictions = res.isOkay ? res.predictions : []; _loadingPredictions = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPredictions = false);
    }
  }

  Future<void> _selectPrediction(Prediction p) async {
    setState(() { _predictions = []; _searchCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    try {
      final det = await _places.getDetailsByPlaceId(p.placeId!, language: 'fr');
      if (!mounted || !det.isOkay) return;
      String num = '', route = '', cp = '', ville = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('street_number')) num   = c.longName;
        if (c.types.contains('route'))         route = c.longName;
        if (c.types.contains('postal_code'))   cp    = c.longName;
        if (c.types.contains('locality'))      ville = c.longName;
        else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) ville = c.longName;
      }
      final loc = det.result.geometry?.location;
      setState(() {
        _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
        _cpCtrl.text    = cp;
        _villeCtrl.text = ville;
        if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
      });
    } catch (_) {}
  }

  Future<void> _geolocate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _lat = pos.latitude; _lng = pos.longitude;
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return;
      final m = marks.first;
      setState(() {
        _rueCtrl.text   = m.street ?? '';
        _cpCtrl.text    = m.postalCode ?? '';
        _villeCtrl.text = m.locality ?? m.subLocality ?? '';
        _searchCtrl.text = [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text].where((s) => s.isNotEmpty).join(', ');
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final localisation = [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
        .where((s) => s.isNotEmpty).join(', ');
    if (localisation.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _supa.from('alertes_perdus').update({
        'derniere_localisation': localisation,
        'lat': _lat,
        'lng': _lng,
      }).eq('id', widget.alerteId);
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Mettre à jour la localisation',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: TextField(
              controller: _searchCtrl, onChanged: _onChanged,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher une adresse…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                suffixIcon: (_loadingPredictions || _locating)
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _orange)))
                    : IconButton(icon: const Icon(Icons.my_location, size: 18, color: _orange), onPressed: _geolocate),
              ),
            ),
          ),
          if (_predictions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))]),
              child: Column(children: _predictions.take(5).map((p) => ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                onTap: () => _selectPrediction(p),
              )).toList()),
            ),
          const SizedBox(height: 10),
          _locField(_rueCtrl, 'Rue / Voie'),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 110, child: _locField(_cpCtrl, 'Code postal', num: true)),
            const SizedBox(width: 8),
            Expanded(child: _locField(_villeCtrl, 'Ville')),
          ]),
          if (_lat != null)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.check_circle, size: 13, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text('GPS enregistré', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.green.shade600)),
              ])),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _orange,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _locField(TextEditingController ctrl, String hint, {bool num = false}) => Container(
    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200)),
    child: TextField(
      controller: ctrl,
      keyboardType: num ? TextInputType.number : null,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      decoration: InputDecoration(hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: InputBorder.none),
    ),
  );
}
