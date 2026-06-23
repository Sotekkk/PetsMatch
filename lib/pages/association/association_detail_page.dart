import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AssociationDetailPage extends StatefulWidget {
  final String uid;
  final String name;
  final String avatar;
  final String ville;

  const AssociationDetailPage({
    super.key,
    required this.uid,
    required this.name,
    required this.avatar,
    required this.ville,
  });

  @override
  State<AssociationDetailPage> createState() => _AssociationDetailPageState();
}

class _AssociationDetailPageState extends State<AssociationDetailPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  final _supa = Supabase.instance.client;

  String _description  = '';
  String _loadedName   = '';
  String _loadedAvatar = '';
  String _loadedVille  = '';
  String _phone        = '';
  String _siteWeb      = '';
  List<Map<String, dynamic>> _animaux   = [];
  List<Map<String, dynamic>> _annonces  = [];
  bool _loading = true;
  bool _loadingChat = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _supa.from('users').select('description_elevage').eq('uid', widget.uid).maybeSingle(),
        // Animaux : filtre is_association si possible, sinon tous les animaux statut disponible
        _supa.from('animaux')
            .select('id,nom,espece,race,sexe,statut,date_naissance,photo_url')
            .eq('uid_eleveur', widget.uid)
            .eq('statut', 'disponible')
            .order('nom'),
        _supa.from('annonces')
            .select('id,titre,espece,race,sexe,photos,statut,ville_eleveur,nom_eleveur,date_naissance_animal,profil_source')
            .eq('uid_eleveur', widget.uid)
            .eq('profil_source', 'association')
            .eq('statut', 'disponible')
            .order('created_at', ascending: false),
        // Profil association : nom + description + avatar + ville + téléphone
        _supa.from('user_profiles')
            .select('name_elevage, profile_label, description, desc_entreprise, avatar_url, ville, phone, telephone, site_web')
            .eq('uid', widget.uid)
            .eq('profile_type', 'association')
            .maybeSingle(),
      ]);

      final userRow    = results[0] as Map<String, dynamic>?;
      final animaux    = results[1] as List;
      final annonces   = results[2] as List;
      final assoProfile = results[3] as Map<String, dynamic>?;

      // Nom réel de l'association (priorité : user_profiles.name_elevage)
      final nameEl = (assoProfile?['name_elevage'] as String?)?.trim();
      final label  = (assoProfile?['profile_label'] as String?)?.trim();
      final freshName = (nameEl?.isNotEmpty == true) ? nameEl!
          : (label?.isNotEmpty == true) ? label!
          : widget.name;

      // Description
      String desc = ((assoProfile?['desc_entreprise'] ?? assoProfile?['description']) as String?)?.trim() ?? '';
      if (desc.isEmpty) desc = userRow?['description_elevage']?.toString() ?? '';

      final phone = (assoProfile?['phone'] ?? assoProfile?['telephone'])?.toString().trim() ?? '';
      final siteWeb = assoProfile?['site_web']?.toString().trim() ?? '';

      // Filtre is_association sur les animaux si possible
      final allAnimaux = List<Map<String, dynamic>>.from(animaux);
      final hasIsAssociation = allAnimaux.any((a) => a.containsKey('is_association'));
      final filteredAnimaux = hasIsAssociation
          ? allAnimaux.where((a) => a['is_association'] == true).toList()
          : allAnimaux;

      if (mounted) {
        setState(() {
          _loadedName   = freshName;
          _loadedAvatar = (assoProfile?['avatar_url'] as String?)?.trim() ?? widget.avatar;
          _loadedVille  = (assoProfile?['ville'] as String?)?.trim() ?? widget.ville;
          _description  = desc;
          _phone   = phone;
          _siteWeb = siteWeb;
          _animaux  = filteredAnimaux;
          _annonces = List<Map<String, dynamic>>.from(annonces);
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid == widget.uid) return;
    setState(() => _loadingChat = true);
    try {
      final sortedIds = [currentUid, widget.uid]..sort();
      final participantIds = sortedIds.join('_');
      final snap = await FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', isEqualTo: participantIds)
          .limit(1)
          .get();
      final bool isNew = snap.docs.isEmpty;
      final String conversationId;
      final profileTypes = <String, String>{
        widget.uid: 'association',
        currentUid: User_Info.catPro.isNotEmpty ? User_Info.catPro
            : (User_Info.isAssociation ? 'association'
              : (User_Info.isElevage ? 'eleveur' : 'particulier')),
      };
      if (isNew) {
        final ref = await FirebaseFirestore.instance.collection('conversations').add({
          'participants': [currentUid, widget.uid],
          'participantIds': participantIds,
          'lastMessage': '',
          'timestamp': FieldValue.serverTimestamp(),
          'participant_profile_types': profileTypes,
        });
        conversationId = ref.id;
      } else {
        conversationId = snap.docs.first.id;
        final existing = snap.docs.first.data() as Map<String, dynamic>;
        if (existing['participant_profile_types'] == null) {
          await snap.docs.first.reference.update({'participant_profile_types': profileTypes});
        }
      }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          eleveurId: widget.uid,
          isNewConversation: isNew,
        ),
      ));
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  String _age(dynamic dateNaissance) {
    if (dateNaissance == null) return '';
    try {
      final dn = DateTime.parse(dateNaissance.toString());
      final mois = (DateTime.now().difference(dn).inDays / 30).floor();
      if (mois < 12) return '${mois}m';
      return '${(mois / 12).floor()}a';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0C5C6C), Color(0xFF6E9E57)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 80,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Colors.white24,
                          backgroundImage: _loadedAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(_loadedAvatar) as ImageProvider
                              : (widget.avatar.isNotEmpty ? CachedNetworkImageProvider(widget.avatar) as ImageProvider : null),
                          child: (_loadedAvatar.isEmpty && widget.avatar.isEmpty)
                              ? const Icon(Icons.favorite, color: Colors.white, size: 30) : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_loadedName.isNotEmpty ? _loadedName : widget.name,
                                  style: const TextStyle(
                                      fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                      fontSize: 18, color: Colors.white),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              if ((_loadedVille.isNotEmpty ? _loadedVille : widget.ville).isNotEmpty)
                                Row(children: [
                                  const Icon(Icons.location_on_outlined, size: 13, color: Colors.white70),
                                  const SizedBox(width: 3),
                                  Text(_loadedVille.isNotEmpty ? _loadedVille : widget.ville,
                                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white70)),
                                ]),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('Association / Refuge',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Boutons de contact
                        Row(children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _loadingChat ? null : _openChat,
                              icon: _loadingChat
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.message_outlined),
                              label: const Text('Message', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          if (_phone.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: () => launchUrl(Uri(scheme: 'tel', path: _phone)),
                              icon: const Icon(Icons.phone_outlined),
                              label: const Text('Appeler', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ]),
                        if (_phone.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: Text(_phone,
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                          ),
                        ],
                        // Description
                        if (_description.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text('À propos',
                              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                  fontSize: 16, color: _teal)),
                          const SizedBox(height: 8),
                          Text(_description,
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF444444), height: 1.5)),
                        ],
                        // Annonces association
                        if (_annonces.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text('Annonces d\'adoption',
                              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                  fontSize: 16, color: _teal)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _annonces.length,
                              itemBuilder: (_, i) {
                                final a = _annonces[i];
                                final photos = List<String>.from(a['photos'] ?? []);
                                final photo = photos.isNotEmpty ? photos.first : '';
                                return GestureDetector(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => AnnonceDetailPage(annonceId: a['id']?.toString() ?? ''))),
                                  child: Container(
                                    width: 140,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)],
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                        child: SizedBox(
                                          height: 120,
                                          width: double.infinity,
                                          child: photo.isNotEmpty
                                              ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover)
                                              : Container(color: const Color(0xFFF0F0EC),
                                                  child: const Icon(Icons.favorite_border, color: Colors.grey, size: 36)),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(a['titre']?.toString() ?? '',
                                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                          Text((a['race'] as String?)?.isNotEmpty == true ? a['race'] as String : (a['espece'] as String? ?? ''),
                                              style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ]),
                                      ),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],

                        // Animaux disponibles
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Text('Animaux disponibles à l\'adoption',
                                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                    fontSize: 16, color: _teal)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${_animaux.length}',
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_animaux.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.pets, size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 8),
                                Text('Aucun animal disponible actuellement',
                                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400)),
                              ]),
                            ),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: _animaux.length,
                            itemBuilder: (_, i) => _AnimalCard(
                              animal: _animaux[i],
                              age: _age(_animaux[i]['date_naissance']),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final String age;

  const _AnimalCard({required this.animal, required this.age});

  @override
  Widget build(BuildContext context) {
    final photo  = animal['photo_url']?.toString() ?? '';
    final nom    = animal['nom']?.toString() ?? 'Sans nom';
    final race   = animal['race']?.toString() ?? '';
    final espece = animal['espece']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: photo.isNotEmpty
                  ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover, width: double.infinity,
                      errorWidget: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(nom,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 13, color: Color(0xFF1F2A2E)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (age.isNotEmpty)
                    Text(age, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                ]),
                if (race.isNotEmpty || espece.isNotEmpty)
                  Text(race.isNotEmpty ? race : espece,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFF0F0EC),
    child: const Icon(Icons.pets, color: Color(0xFFCCCCCC), size: 40),
  );
}
