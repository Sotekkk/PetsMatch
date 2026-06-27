import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class UserDetailPageFeed extends StatefulWidget {
  final UserSelected user;
  const UserDetailPageFeed({super.key, required this.user});

  @override
  State<UserDetailPageFeed> createState() => _UserDetailPageFeedState();
}

class _UserDetailPageFeedState extends State<UserDetailPageFeed> {
  bool _loadingChat = false;
  List<Map<String, dynamic>> _annonces = [];
  bool _loadingAnnonces = true;
  late String _bannerUrl;

  @override
  void initState() {
    super.initState();
    _bannerUrl = widget.user.bannerUrl;
    _loadAnnonces();
    if (_bannerUrl.isEmpty) _loadBannerFromSupabase();
  }

  Future<void> _loadBannerFromSupabase() async {
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('banner_url')
          .eq('uid', widget.user.uid)
          .maybeSingle();
      final url = row?['banner_url'] as String?;
      if (mounted && url != null && url.isNotEmpty) setState(() => _bannerUrl = url);
    } catch (_) {}
  }

  Future<void> _loadAnnonces() async {
    try {
      final rows = await Supabase.instance.client
          .from('annonces')
          .select('id, titre, espece, race, photos, prix, saillie_prix, prix_min_portee, prix_max_portee, type_vente, statut, uid_eleveur, ville_eleveur, created_at')
          .eq('uid_eleveur', widget.user.uid)
          .eq('statut', 'disponible')
          .order('created_at', ascending: false);
      if (mounted) setState(() { _annonces = List<Map<String, dynamic>>.from(rows as List); _loadingAnnonces = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingAnnonces = false);
    }
  }

  Future<void> _openChat() async {
    setState(() => _loadingChat = true);
    try {
      final eleveurId = widget.user.uid;
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: eleveurId,
        categorie: 'communaute',
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatScreen(conversationId: convId, eleveurId: eleveurId),
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

  Future<void> _sendSignalement(String raison, String details) async {
    final myUid = User_Info.uid;
    if (myUid.isEmpty) return;
    try {
      await Supabase.instance.client.from('signalements').insert({
        'reporter_uid': myUid,
        'target_type': 'user',
        'target_id': widget.user.uid,
        'raison': raison,
        if (details.isNotEmpty) 'description': details,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vous avez déjà signalé ce profil.')),
        );
      }
    }
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

  static const _sigRaisons = [
    ('contenu_inapproprie', 'Contenu inapproprié'),
    ('spam',               'Spam ou arnaque'),
    ('faux_profil',        'Faux profil'),
    ('maltraitance',       'Maltraitance animale'),
    ('autre',              'Autre'),
  ];

  void _showSignalementDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        String motif = _sigRaisons.first.$1;
        final detailCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Signaler un utilisateur'),
            content: SingleChildScrollView(
              child: Column(children: [
                for (final (key, label) in _sigRaisons)
                  RadioListTile<String>(
                    title: Text(label),
                    value: key,
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
                      const SnackBar(content: Text('Signalement envoyé. Merci.')),
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
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0C5C6C),
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
                        const SnackBar(content: Text('Utilisateur bloqué.')),
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
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Banner + photo profil (style Facebook) ─────────────────
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bannière paysage
                        SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _bannerUrl.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: _bannerUrl, fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => _PlaceholderBanner())
                                  : (user.profilePictureUrlElevage.isNotEmpty
                                      ? CachedNetworkImage(imageUrl: user.profilePictureUrlElevage, fit: BoxFit.cover,
                                          color: Colors.black26, colorBlendMode: BlendMode.darken,
                                          errorWidget: (_, __, ___) => _PlaceholderBanner())
                                      : _PlaceholderBanner()),
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black45],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Section blanche — padding top = 44 (moitié photo) + 8
                        Container(
                          color: Colors.white,
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (!isOwnProfile && user.numeroElevage.isNotEmpty) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton(
                                  onPressed: () => _callPhone(user.numeroElevage),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    side: const BorderSide(color: Color(0xFFA7C79A)),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Icon(Icons.phone, size: 18, color: Color(0xFF6E9E57)),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(children: [
                              Expanded(
                                child: Text(
                                  user.nameElevage,
                                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 22, color: Color(0xFF1F2A2E)),
                                ),
                              ),
                              if (user.isValidate)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.verified, color: Color(0xFF16A34A), size: 13),
                                    SizedBox(width: 3),
                                    Text('PRO Vérifié', style: TextStyle(color: Color(0xFF16A34A), fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                            ]),
                            if (_location.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                                const SizedBox(width: 3),
                                Expanded(child: Text(_location, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Galey'))),
                              ]),
                            ],
                            if (user.siret.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('🪪 SIRET : ${user.siret}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Galey')),
                            ],
                          ]),
                        ),
                      ],
                    ),
                    // Photo de profil chevauchant la bannière (top: 200 - 44 = 156)
                    Positioned(
                      top: 156,
                      left: 16,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
                        ),
                        child: ClipOval(
                          child: user.profilePictureUrlElevage.isNotEmpty
                              ? CachedNetworkImage(imageUrl: user.profilePictureUrlElevage, fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _AvatarPlaceholder())
                              : _AvatarPlaceholder(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Espèces + races ────────────────────────────────────────
                if (allBreeds.isNotEmpty || user.isDog || user.isCat) ...[
                  Container(
                    color: Colors.white,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      if (user.isDog) _SpeciesChip(label: '🐶 Chien'),
                      if (user.isCat) _SpeciesChip(label: '🐱 Chat'),
                      ...allBreeds.map((r) => _BreedChip(label: r)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Bouton contacter ───────────────────────────────────────
                if (!isOwnProfile) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loadingChat ? null : _openChat,
                        icon: _loadingChat
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Contacter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0C5C6C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── À propos ───────────────────────────────────────────────
                if (user.descEntreprise.isNotEmpty && user.descEntreprise != 'Aucune description disponible') ...[
                  Container(
                    color: Colors.white,
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('À propos', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A2E))),
                      const SizedBox(height: 8),
                      Text(user.descEntreprise, style: const TextStyle(fontSize: 13, color: Colors.black87, fontFamily: 'Galey', height: 1.5)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Annonces (éleveurs uniquement) ────────────────────────
                if (user.isElevage) ...[
                  Container(
                    color: Colors.white,
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(children: [
                      const Text('Annonces', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A2E))),
                      if (_annonces.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('${_annonces.length}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
                      ],
                    ]),
                  ),
                  if (_loadingAnnonces)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C))),
                    )
                  else if (_annonces.isEmpty)
                    Container(
                      color: Colors.white,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      child: const Text('Aucune annonce active pour le moment.', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'), textAlign: TextAlign.center),
                    )
                  else
                    Container(
                    color: Colors.white,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                      itemCount: _annonces.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.72,
                      ),
                      itemBuilder: (context, i) {
                        final a = _annonces[i];
                        final photos = (a['photos'] as List?)?.cast<String>() ?? [];
                        final isSaillie = a['type_vente'] == 'saillie';
                        final titreRaw = (a['titre'] as String?) ?? '';
                        final espece = (a['espece'] as String?) ?? '';
                        final race = (a['race'] as String?) ?? '';
                        final titre = titreRaw.isNotEmpty ? titreRaw : '$espece $race'.trim();
                        final ville = (a['ville_eleveur'] as String?) ?? '';
                        final String? prix;
                        if (isSaillie) {
                          prix = a['saillie_prix'] != null ? '${a['saillie_prix']} €' : null;
                        } else if (a['prix_min_portee'] != null && a['prix_max_portee'] != null) {
                          prix = '${a['prix_min_portee']} – ${a['prix_max_portee']} €';
                        } else if (a['prix_min_portee'] != null) {
                          prix = 'Dès ${a['prix_min_portee']} €';
                        } else if (a['prix'] != null) {
                          prix = '${a['prix']} €';
                        } else {
                          prix = null;
                        }

                        return GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => AnnonceDetailPage(annonceId: a['id'] as String, initialData: a))),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        photos.isNotEmpty
                                            ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) => _AnnoncePlaceholder(a))
                                            : _AnnoncePlaceholder(a),
                                        Positioned(
                                          top: 6, left: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isSaillie ? const Color(0xFFA855F7) : const Color(0xFF6E9E57),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              isSaillie ? 'Saillie' : 'Compagnon',
                                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        titre.isNotEmpty ? titre : '–',
                                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF1F2A2E)),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                      if (espece.isNotEmpty || race.isNotEmpty)
                                        Text(
                                          '${espece.isNotEmpty ? espece : ''}${race.isNotEmpty ? ' · $race' : ''}'.trim(),
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                      if (ville.isNotEmpty)
                                        Text('📍 $ville', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      if (prix != null)
                                        Text(prix, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0C5C6C))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ], // if (user.isElevage)
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0C5C6C), Color(0xFF6E9E57)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Icon(Icons.pets, size: 48, color: Colors.white38)),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFEEF5EA),
    child: const Center(child: Icon(Icons.store_outlined, size: 36, color: Color(0xFF6E9E57))),
  );
}

class _AnnoncePlaceholder extends StatelessWidget {
  final Map<String, dynamic> a;
  const _AnnoncePlaceholder(this.a);
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF0F9F0),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.pets, color: Color(0xFFA7C79A), size: 24),
      if ((a['race'] as String?)?.isNotEmpty == true)
        Padding(padding: const EdgeInsets.only(top: 4), child:
          Text(a['race'] as String, style: const TextStyle(fontSize: 9, color: Colors.grey), textAlign: TextAlign.center, maxLines: 2)),
    ])),
  );
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
