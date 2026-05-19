import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/eleveur/postDetail.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:url_launcher/url_launcher.dart';

class UserDetailPageFeed extends StatefulWidget {
  final UserSelected user;
  const UserDetailPageFeed({super.key, required this.user});

  @override
  State<UserDetailPageFeed> createState() => _UserDetailPageFeedState();
}

class _UserDetailPageFeedState extends State<UserDetailPageFeed> {
  bool _loadingChat = false;

  Future<void> _openChat() async {
    setState(() => _loadingChat = true);
    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;
      final eleveurId = widget.user.uid;
      final sortedIds = [currentUserId, eleveurId]..sort();
      final participantIds = sortedIds.join('_');

      final snap = await FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', isEqualTo: participantIds)
          .limit(1)
          .get();

      final DocumentReference ref = snap.docs.isEmpty
          ? await FirebaseFirestore.instance.collection('conversations').add({
              'participants': [currentUserId, eleveurId],
              'participantIds': participantIds,
              'lastMessage': '',
              'timestamp': FieldValue.serverTimestamp(),
            })
          : snap.docs.first.reference;

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatScreen(conversationId: ref.id, eleveurId: eleveurId),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  Future<void> _callPhone(String number) async {
    final url = 'tel:$number';
    if (await canLaunch(url)) await launch(url);
  }

  Future<void> _sendSignalement(String motif, String details) async {
    final smtp = gmail('petsmatch.contact@gmail.com', 'dppu ctgp buve bxjd');
    final msg = Message()
      ..from = Address('petsmatch.contact@gmail.com', 'PetsMatch - Signalement')
      ..recipients.add('petsmatch.contact@gmail.com')
      ..subject = '🚨 Signalement : ${widget.user.uid}'
      ..text =
          'Signalé : ${widget.user.uid}\nSignalant : ${User_Info.uid}\nMotif : $motif\nDétails : $details';
    try {
      await send(msg, smtp);
    } on MailerException catch (_) {}
  }

  String get _location {
    final data = {
      'villeElevage': widget.user.villeElevage,
      'codePostalElevage': widget.user.codePostalElevage,
      'paysElevage': widget.user.paysElevage,
    };
    final loc = FrenchGeo.formatLocation(data);
    if (loc.isNotEmpty) return loc;
    return widget.user.adressElevage;
  }

  void _showSignalementDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        String motif = 'Comportement abusif';
        final detailCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Signaler un utilisateur'),
            content: SingleChildScrollView(
              child: Column(children: [
                for (final m in [
                  'Comportement abusif',
                  'Contenu inapproprié',
                  'Spam ou arnaque',
                  'Autre'
                ])
                  RadioListTile(
                    title: Text(m),
                    value: m,
                    groupValue: motif,
                    onChanged: (v) => setS(() => motif = v!),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Détails (facultatif)',
                    filled: true,
                    fillColor: Colors.grey[200],
                    border: const OutlineInputBorder(),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6E9E57)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _sendSignalement(motif, detailCtrl.text.trim());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signalement envoyé.')),
                    );
                  }
                },
                child: const Text('Envoyer',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isOwnProfile = User_Info.uid == user.uid;
    final allBreeds = [...user.dogBreeds, ...user.catBreeds];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: CustomScrollView(
        slivers: [
          // App bar with photo
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: const Color(0xFFA7C79A),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (!isOwnProfile)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (v) {
                    if (v == 'signaler') _showSignalementDialog();
                    if (v == 'bloquer') {
                      FirebaseFirestore.instance
                          .collection('bloquer')
                          .doc(User_Info.uid)
                          .set({user.uid: true}, SetOptions(merge: true));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Utilisateur bloqué.')),
                      );
                      Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'signaler',
                        child: Row(children: [
                          Icon(Icons.report, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Signaler'),
                        ])),
                    const PopupMenuItem(
                        value: 'bloquer',
                        child: Row(children: [
                          Icon(Icons.block),
                          SizedBox(width: 8),
                          Text('Bloquer'),
                        ])),
                  ],
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  user.profilePictureUrlElevage.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: user.profilePictureUrlElevage,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _PlaceholderBanner(),
                        )
                      : _PlaceholderBanner(),
                  // Gradient pour lisibilité
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black38],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nom + badge + localisation
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.nameElevage,
                              style: const TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w500,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          if (user.isValidate)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF2E7D32).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFF2E7D32)
                                        .withOpacity(0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified,
                                      color: Color(0xFF2E7D32), size: 14),
                                  SizedBox(width: 4),
                                  Text('PRO Vérifié',
                                      style: TextStyle(
                                          color: Color(0xFF2E7D32),
                                          fontFamily: 'Galey',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (_location.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _location,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.grey,
                                    fontFamily: 'Galey'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (user.siret.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.badge_outlined,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              'SIRET : ${user.siret}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontFamily: 'Galey'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Espèces + races
                if (user.isDog || user.isCat) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (user.isDog) _SpeciesChip(label: '🐶 Chien'),
                        if (user.isCat) _SpeciesChip(label: '🐱 Chat'),
                        ...allBreeds.map((r) => _BreedChip(label: r)),
                      ],
                    ),
                  ),
                ],

                // Bouton contacter + téléphone
                if (!isOwnProfile) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _loadingChat ? null : _openChat,
                            icon: _loadingChat
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black),
                                  )
                                : const Icon(Icons.chat_bubble_outline,
                                    size: 18, color: Colors.black),
                            label: const Text('Contacter',
                                style: TextStyle(
                                    fontFamily: 'Galey',
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFFA7C79A),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        if (user.numeroElevage.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () => _callPhone(user.numeroElevage),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30)),
                              side: const BorderSide(
                                  color:
                                      Color(0xFFA7C79A)),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                            ),
                            child: const Icon(Icons.phone,
                                size: 20,
                                color: Color(0xFF6E9E57)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Description
                if (user.descEntreprise.isNotEmpty &&
                    user.descEntreprise !=
                        'Aucune description disponible') ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'À propos',
                      style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      user.descEntreprise,
                      style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontFamily: 'Galey'),
                    ),
                  ),
                ],

                // Annonces
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Annonces',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('post')
                      .where('uidEleveur', isEqualTo: user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                          child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                            color: Color(0xFFA7C79A)),
                      ));
                    }

                    final posts = snapshot.data!.docs.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      d['id'] = doc.id;
                      return d;
                    }).toList();

                    if (posts.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                        child: Text(
                          'Aucune annonce pour le moment.',
                          style: TextStyle(
                              color: Colors.grey, fontFamily: 'Galey'),
                        ),
                      );
                    }

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 100),
                      itemCount: posts.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemBuilder: (context, i) {
                        final post = posts[i];
                        final media = post['mediaStockage'] as List?;
                        if (media == null || media.isEmpty) {
                          return const SizedBox();
                        }
                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PostDetailPage(post: post),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: media.length > 1
                                ? CarouselSlider.builder(
                                    itemCount: media.length,
                                    itemBuilder: (_, idx, __) =>
                                        CachedNetworkImage(
                                      imageUrl: media[idx]['path'],
                                      fit: BoxFit.cover,
                                    ),
                                    options: CarouselOptions(
                                      viewportFraction: 1,
                                      aspectRatio: 1,
                                      enableInfiniteScroll: false,
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: media[0]['path'],
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        Container(color: Colors.grey[200]),
                                  ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFA7C79A).withOpacity(0.4),
      child: const Center(
        child: Icon(Icons.pets, size: 64, color: Color(0xFFA7C79A)),
      ),
    );
  }
}

class _SpeciesChip extends StatelessWidget {
  final String label;
  const _SpeciesChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFA7C79A).withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFA7C79A)),
      ),
      child: Text(label,
          style: const TextStyle(
              fontFamily: 'Galey',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black87)),
    );
  }
}

class _BreedChip extends StatelessWidget {
  final String label;
  const _BreedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label,
          style: const TextStyle(
              fontFamily: 'Galey', fontSize: 12, color: Colors.black54)),
    );
  }
}
