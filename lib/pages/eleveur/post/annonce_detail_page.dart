import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/main_feed.dart' show UserSelected;
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Palette partagée ─────────────────────────────────────────────────────────
const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

// ─────────────────────────────────────────────────────────────────────────────
// Page principale
// ─────────────────────────────────────────────────────────────────────────────

class AnnonceDetailPage extends StatefulWidget {
  final String annonceId;
  final Map<String, dynamic>? initialData;
  const AnnonceDetailPage({super.key, required this.annonceId, this.initialData});
  @override
  State<AnnonceDetailPage> createState() => _AnnonceDetailPageState();
}

class _AnnonceDetailPageState extends State<AnnonceDetailPage> {
  int _photoIndex = 0;
  Map<String, dynamic>? _eleveurData;
  bool _eleveurLoaded = false;
  Map<String, dynamic>? _annonceData;

  bool _isLiked = false;
  int  _likeCount = 0;
  List<Map<String, dynamic>> _likers = [];

  static const _sigRaisons = [
    ('contenu_inapproprie', 'Contenu inapproprié'),
    ('spam',               'Spam ou arnaque'),
    ('faux_profil',        'Faux profil'),
    ('maltraitance',       'Maltraitance animale'),
    ('autre',              'Autre'),
  ];

  Future<void> _showSignalementDialog() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || !mounted) return;

    String motif = _sigRaisons.first.$1;
    final detailCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Signaler cette annonce'),
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
                  fillColor: Colors.grey[100],
                  border: const OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Envoyer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.from('signalements').insert({
        'reporter_uid': myUid,
        'target_type': 'annonce',
        'target_id': widget.annonceId,
        'raison': motif,
        if (detailCtrl.text.trim().isNotEmpty) 'description': detailCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signalement envoyé. Merci.')),
        );
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vous avez déjà signalé cette annonce.')),
        );
      }
    }
  }

  static Timestamp? _isoToTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v;
    try { return Timestamp.fromDate(DateTime.parse(v.toString())); } catch (_) { return null; }
  }

  static Map<String, dynamic> _fromSupabase(Map<String, dynamic> row) => {
    ...row,
    'uidEleveur':        row['uid_eleveur'],
    'nomEleveur':        row['nom_eleveur'],
    'villeEleveur':      row['ville_eleveur'],
    'typeVente':         row['type_vente'],
    'prixNegociable':    row['prix_negociable'] ?? false,
    'dateNaissance':     _isoToTs(row['date_naissance']),
    'nombreBebes':       row['nombre_bebes'],
    'animauxPortee':     row['animaux_portee'] ?? [],
    'prixMinPortee':     row['prix_min_portee'],
    'prixMaxPortee':     row['prix_max_portee'],
    'mereAnimalId':        row['mere_animal_id'],
    'merePhotoUrl':        row['mere_photo_url'],
    'mereNom':             row['mere_nom'] ?? '',
    'merePuce':            row['mere_identification'] ?? row['mere_puce'] ?? '',
    'mereRace':            row['mere_race'] ?? '',
    'mereCouleur':         row['mere_couleur'] ?? '',
    'mereDescription':     row['mere_description'] ?? '',
    'mereRegistre':        row['mere_registre'] ?? '',
    'pereAnimalId':        row['pere_animal_id'],
    'perePhotoUrl':        row['pere_photo_url'],
    'pereNom':             row['pere_nom'] ?? '',
    'perePuce':            row['pere_identification'] ?? row['pere_puce'] ?? '',
    'pereRace':            row['pere_race'] ?? '',
    'pereCouleur':         row['pere_couleur'] ?? '',
    'pereDescription':     row['pere_description'] ?? '',
    'pereRegistre':        row['pere_registre'] ?? '',
    'registreType':      row['registre_type'] ?? '',
    'numeroRegistre':    row['numero_registre'] ?? '',
    'clubPedigree':      row['club_pedigree'] ?? '',
    'bilanSante':        row['bilan_sante'] ?? false,
    'etalonAnimalId':    row['etalon_animal_id'],
    'sailliePrix': row['saillie_prix'] != null
        ? (row['saillie_prix'] is num
            ? (row['saillie_prix'] as num).toInt().toString()
            : double.tryParse(row['saillie_prix'].toString())?.toInt().toString() ?? '')
        : '',
    'saillieConditions': row['saillie_conditions'] ?? '',
    'dateNaissanceAnimal': _isoToTs(row['date_naissance_animal']),
    'createdAt':         _isoToTs(row['created_at']),
    'updatedAt':         _isoToTs(row['updated_at']),
  };

  static Map<String, dynamic> _normalizeUser(Map<String, dynamic> row) => {
    ...row,
    'nameElevage':              row['name_elevage'],
    'profilePictureUrlElevage': row['profile_picture_url_elevage'],
    'profilePictureUrl':        row['profile_picture_url'],
    'villeElevage':             row['ville_elevage'],
    'descEntreprise':           row['desc_entreprise'],
    'isPartenaire':             row['is_partenaire'] ?? false,
    'catPro':                   row['cat_pro'] ?? '',
    'professionPro':            row['profession_pro'] ?? '',
    'codeISOElevage':           row['code_iso_elevage'] ?? '',
    'numeroElevage':            row['numero_elevage'] ?? '',
    'adressElevage':            row['adress_elevage'] ?? '',
    'isValidate':               row['is_validate'] ?? false,
    'isElevage':                row['is_elevage'] ?? false,
    'isPro':                    row['is_pro'] ?? false,
    'isDog':                    row['is_dog'] ?? false,
    'isCat':                    row['is_cat'] ?? false,
    'dogBreeds':                row['dog_breeds'] ?? [],
    'catBreeds':                row['cat_breeds'] ?? [],
    'codePostalElevage':        row['code_postal_elevage'] ?? '',
    'paysElevage':              row['pays_elevage'] ?? '',
    'siret':                    row['siret'] ?? '',
  };

  @override
  void initState() {
    super.initState();
    _loadAnnonce();
    _loadLikeState();
    final uid = widget.initialData?['uidEleveur'] as String?
        ?? widget.initialData?['uid_eleveur'] as String?;
    if (uid != null) { _eleveurLoaded = true; _loadEleveur(uid); }
  }

  Future<void> _loadLikeState() async {
    try {
      final rows = await Supabase.instance.client
          .from('likes')
          .select('user_uid')
          .eq('annonce_id', widget.annonceId)
          .isFilter('bebe_index', null);
      final all = List<Map<String, dynamic>>.from(rows);
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      final liked = myUid != null && all.any((r) => r['user_uid'] == myUid);

      List<Map<String, dynamic>> likers = [];
      if (myUid != null && all.isNotEmpty) {
        final uids = all.map((r) => r['user_uid'] as String).take(5).toList();
        final users = await Supabase.instance.client
            .from('users')
            .select('uid, firstname, profile_picture_url')
            .inFilter('uid', uids);
        likers = List<Map<String, dynamic>>.from(users);
      }

      if (mounted) setState(() {
        _likeCount = all.length;
        _isLiked   = liked;
        _likers    = likers;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final wasLiked = _isLiked;
    setState(() {
      _isLiked   = !wasLiked;
      _likeCount = (_likeCount + (wasLiked ? -1 : 1)).clamp(0, 9999999);
    });
    try {
      if (wasLiked) {
        await Supabase.instance.client.from('likes').delete()
            .eq('user_uid', uid)
            .eq('annonce_id', widget.annonceId)
            .isFilter('bebe_index', null);
      } else {
        await Supabase.instance.client.from('likes').upsert({
          'user_uid':    uid,
          'annonce_id':  widget.annonceId,
          'bebe_index':  null,
          'profile_type': User_Info.activeType,
        });
      }
      await _loadLikeState();
    } catch (_) {
      if (mounted) setState(() {
        _isLiked   = wasLiked;
        _likeCount = (_likeCount + (wasLiked ? 1 : -1)).clamp(0, 9999999);
      });
    }
  }

  Future<void> _loadAnnonce() async {
    try {
      final row = await Supabase.instance.client
          .from('annonces').select().eq('id', widget.annonceId).single();
      final data = _fromSupabase(row);
      final me = FirebaseAuth.instance.currentUser?.uid;
      final uid = data['uidEleveur'] as String?;
      if (me != null && me != uid) {
        final currentVues = (row['vues'] as int?) ?? 0;
        Supabase.instance.client.from('annonces')
            .update({'vues': currentVues + 1})
            .eq('id', widget.annonceId).catchError((_) {});
      }
      if (!_eleveurLoaded && uid != null) { _eleveurLoaded = true; _loadEleveur(uid); }
      if (mounted) setState(() => _annonceData = data);
    } catch (_) {}
  }

  Future<void> _loadEleveur(String uid) async {
    try {
      final row = await Supabase.instance.client
          .from('users').select().eq('uid', uid).single();
      if (mounted) setState(() => _eleveurData = _normalizeUser(row));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = _annonceData ?? widget.initialData ?? <String, dynamic>{};

    final isOwner   = FirebaseAuth.instance.currentUser?.uid == data['uidEleveur'];
    final photos    = List<String>.from(data['photos'] ?? []);
    final espece    = (data['espece'] as String?) ?? '';
    final race      = (data['race'] as String?) ?? '';
    final titre     = (data['titre'] as String?) ?? '';
    final type      = (data['type'] as String?) ?? 'animal';
    final typeVente = (data['typeVente'] as String?) ?? 'vente';
    final desc      = (data['description'] as String?) ?? '';
    final registreType = (data['registreType'] as String?) ?? '';
    final displayTitle = titre.isNotEmpty ? titre
        : race.isNotEmpty ? race : speciesLabel(espece);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: Stack(children: [
        CustomScrollView(slivers: [
          // ── AppBar avec photo ────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: photos.isNotEmpty ? 300 : 0,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            title: Text(displayTitle,
                style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 16),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            flexibleSpace: photos.isNotEmpty
                ? FlexibleSpaceBar(
                    background: _PhotoCarousel(
                          photos: photos, espece: espece,
                          currentIndex: _photoIndex,
                          onChanged: (i) => setState(() => _photoIndex = i),
                        ))
                    : null,
                actions: [
                  if (isOwner)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Modifier',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CreateAnnoncePage(
                              annonceId: widget.annonceId, initialData: data))),
                    ),
                  if (!isOwner && FirebaseAuth.instance.currentUser != null)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) {
                        if (v == 'signaler') _showSignalementDialog();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'signaler',
                          child: Row(children: [
                            Icon(Icons.flag_outlined, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Signaler'),
                          ]),
                        ),
                      ],
                    ),
                ],
              ),
              // ── Contenu ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeaderCard(data: data),
                      const SizedBox(height: 8),
                      _LikesRow(
                        annonceId: widget.annonceId,
                        count: _likeCount,
                        isLiked: _isLiked,
                        likers: _likers,
                        onLike: _toggleLike,
                        onShowList: FirebaseAuth.instance.currentUser != null
                            ? () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => _LikersSheet(annonceId: widget.annonceId))
                            : null,
                      ),
                      const SizedBox(height: 4),
                      if (desc.isNotEmpty)
                        ...[_DescCard(desc: desc), const SizedBox(height: 12)],
                      if (type == 'portee')
                        ...[_PorteeCard(data: data, annonceId: widget.annonceId, uidEleveur: data['uidEleveur'] as String?), const SizedBox(height: 12)],
                      if (type != 'portee')
                        ...[_AnimalCard(data: data), const SizedBox(height: 12)],
                      if (typeVente == 'saillie')
                        ...[_SaillieCard(data: data), const SizedBox(height: 12)],
                      if (typeVente != 'saillie') ...[_ParentsCard(data: data), const SizedBox(height: 12)],
                      _SanteCard(data: data),
                      if (registreType.isNotEmpty)
                        ...[const SizedBox(height: 12),
                            _PedigreeCard(data: data, espece: espece)],
                      const SizedBox(height: 12),
                      _EleveurCard(
                        eleveurData: _eleveurData,
                        uidEleveur: (data['uidEleveur'] as String?) ?? '',
                      ),
                    ],
                  ),
                ),
              ),
            ]),
            // ── Barre basse ──────────────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _BottomBar(
                isOwner: isOwner,
                annonceId: widget.annonceId,
                data: data,
                uidEleveur: (data['uidEleveur'] as String?) ?? '',
              ),
            ),
          ]),
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carousel photos
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoCarousel extends StatelessWidget {
  final List<String> photos;
  final String espece;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  const _PhotoCarousel({required this.photos, required this.espece,
      required this.currentIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final h = constraints.maxHeight > 0 ? constraints.maxHeight : 300.0;
      return Stack(fit: StackFit.expand, children: [
        CarouselSlider(
          options: CarouselOptions(
            height: h,
            viewportFraction: 1.0,
            enableInfiniteScroll: photos.length > 1,
            onPageChanged: (i, _) => onChanged(i),
          ),
          items: photos.map((url) => CachedNetworkImage(
            imageUrl: url, fit: BoxFit.cover, width: double.infinity,
            placeholder: (_, __) => Container(color: const Color(0xFFEEF5EA)),
            errorWidget: (_, __, ___) => Container(
                color: const Color(0xFFEEF5EA),
                child: Center(child: speciesIcon(espece, 40, _green))),
          )).toList(),
        ),
        // Dégradé haut
        Positioned(top: 0, left: 0, right: 0, height: 90,
          child: DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black45, Colors.transparent])))),
        // Dégradé bas
        Positioned(bottom: 0, left: 0, right: 0, height: 60,
          child: DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black45, Colors.transparent])))),
        // Compteur
        if (photos.length > 1)
          Positioned(bottom: 14, right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${currentIndex + 1}/${photos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontFamily: 'Galey', fontWeight: FontWeight.w600)))),
        // Dots
        if (photos.length > 1)
          Positioned(bottom: 16, left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
              children: photos.asMap().entries.map((e) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: currentIndex == e.key ? 20 : 7, height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: currentIndex == e.key
                      ? Colors.white : Colors.white.withValues(alpha: 0.45)),
              )).toList())),
      ]);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte titre / prix / statut
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HeaderCard({required this.data});

  Color _statutColor(String s) => switch (s) {
    'disponible' => _green,
    'reserve'    => const Color(0xFFF59E0B),
    'vendu' || 'cede' => Colors.blueGrey,
    _ => Colors.redAccent,
  };

  String _statutLabel(String s) => switch (s) {
    'disponible' => 'Disponible',
    'reserve' => 'Réservé',
    'vendu'   => 'Vendu',
    'cede'    => 'Cédé',
    'expire'  => 'Expiré',
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    final espece    = (data['espece'] as String?) ?? '';
    final race      = (data['race'] as String?) ?? '';
    final titre     = (data['titre'] as String?) ?? '';
    final type      = (data['type'] as String?) ?? 'animal';
    final typeVente = (data['typeVente'] as String?) ?? 'vente';
    final statut    = (data['statut'] as String?) ?? 'disponible';
    final prix      = (data['prix'] as num?)?.toDouble();
    final prixMin   = (data['prixMinPortee'] as num?)?.toDouble();
    final prixMax   = (data['prixMaxPortee'] as num?)?.toDouble();
    final prixNeg   = data['prixNegociable'] as bool? ?? false;
    final createdAt = data['createdAt'] as Timestamp?;
    final fmt = DateFormat('dd/MM/yyyy');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          speciesIcon(espece, 13, _teal), const SizedBox(width: 5),
          Text(race.isNotEmpty ? race : speciesLabel(espece),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: _teal, fontWeight: FontWeight.w600)),
          const Spacer(),
          if ((data['vues'] as num?) != null && (data['vues'] as num) > 0) ...[
            Icon(Icons.visibility_outlined, size: 12, color: Colors.grey.shade400),
            const SizedBox(width: 3),
            Text('${data['vues']}', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(width: 10),
          ],
          if (createdAt != null)
            Text('Publié le ${fmt.format(createdAt.toDate())}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                    color: Colors.grey.shade400)),
        ]),
        const SizedBox(height: 8),
        Text(titre.isNotEmpty ? titre : race.isNotEmpty ? race : speciesLabel(espece),
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800,
                fontSize: 20, color: _dark)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _Badge(type == 'portee' ? 'Portée' : 'Animal individuel',
              type == 'portee' ? _teal : _green),
          _Badge(
            typeVente == 'vente' ? 'Vente'
                : typeVente == 'adoption' ? 'Adoption' : 'Saillie',
            typeVente == 'vente' ? const Color(0xFF6366F1)
                : typeVente == 'adoption' ? _green : const Color(0xFFEC4899),
          ),
          _Badge(_statutLabel(statut), _statutColor(statut)),
        ]),
        const SizedBox(height: 14),
        if (typeVente == 'vente') ...[
          if (type == 'portee' && (prixMin != null || prixMax != null))
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              Text(
                prixMin != null && prixMax != null
                    ? '${prixMin.toInt()} – ${prixMax.toInt()} €'
                    : prixMin != null
                        ? 'Dès ${prixMin.toInt()} €'
                        : "Jusqu'à ${prixMax!.toInt()} €",
                style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w800, fontSize: 26, color: _dark)),
              const SizedBox(width: 8),
              const Text('par bébé', style: TextStyle(fontFamily: 'Galey',
                  fontSize: 12, color: Color(0xFF6F767B))),
            ])
          else if (prix != null)
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              Text('${prix.toStringAsFixed(0)} €',
                  style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w800, fontSize: 28, color: _dark)),
              if (prixNeg) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: _green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Négociable',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: _green, fontWeight: FontWeight.w600))),
              ],
            ]),
        ] else if (typeVente == 'adoption')
          const Text('Adoption / Don',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800,
                  fontSize: 22, color: _green))
        else if (typeVente == 'saillie')
          const Text('Saillie',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800,
                  fontSize: 22, color: Color(0xFF5B8648))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Description
// ─────────────────────────────────────────────────────────────────────────────

class _DescCard extends StatelessWidget {
  final String desc;
  const _DescCard({required this.desc});
  @override
  Widget build(BuildContext context) => _sectionCard('Description',
      Icons.description_outlined, [
    Text(desc, style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
        color: _dark, height: 1.6)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Portée + bébés
// ─────────────────────────────────────────────────────────────────────────────

class _PorteeCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String annonceId;
  final String? uidEleveur;
  const _PorteeCard({required this.data, required this.annonceId, this.uidEleveur});

  @override
  Widget build(BuildContext context) {
    final dateNaissance = data['dateNaissance'] as Timestamp?;
    final nombreBebes = (data['nombreBebes'] as num?)?.toInt() ?? 0;
    final animaux = List<Map<String, dynamic>>.from(data['animauxPortee'] ?? []);
    final fmt = DateFormat('dd/MM/yyyy');

    String ageStr = '';
    if (dateNaissance != null) {
      final age = DateTime.now().difference(dateNaissance.toDate());
      final weeks = (age.inDays / 7).floor();
      ageStr = weeks <= 0 ? 'À naître'
          : weeks < 13 ? '$weeks sem.'
          : weeks < 52 ? '${(weeks / 4.33).floor()} mois'
          : '${(weeks / 52).floor()} an${(weeks / 52).floor() > 1 ? 's' : ''}';
    }

    final disponibles =
        animaux.where((a) => a['statut'] == 'disponible').length;
    final prixMin = (data['prixMinPortee'] as num?)?.toDouble();
    final prixMax = (data['prixMaxPortee'] as num?)?.toDouble();

    return _sectionCard('Portée', Icons.group_outlined, [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _InfoChip(Icons.pets_outlined,
            '$nombreBebes bébé${nombreBebes > 1 ? 's' : ''}'),
        if (disponibles > 0)
          _InfoChip(Icons.check_circle_outline,
              '$disponibles disponible${disponibles > 1 ? 's' : ''}', _green),
        if (dateNaissance != null && ageStr.isNotEmpty)
          _InfoChip(Icons.cake_outlined, ageStr),
        if (dateNaissance != null)
          _InfoChip(Icons.calendar_today_outlined,
              'Né(e) le ${fmt.format(dateNaissance.toDate())}'),
        if (prixMin != null || prixMax != null)
          _InfoChip(Icons.euro_outlined,
            prixMin != null && prixMax != null
                ? '${prixMin.toInt()} – ${prixMax.toInt()} €'
                : prixMin != null
                    ? 'À partir de ${prixMin.toInt()} €'
                    : "Jusqu'à ${prixMax!.toInt()} €",
            const Color(0xFF6366F1)),
      ]),
      if (animaux.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Bébés',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 13, color: _dark)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 10,
            mainAxisSpacing: 10, childAspectRatio: 0.60),
          itemCount: animaux.length,
          itemBuilder: (_, i) => _BabyCard(animal: animaux[i], annonceId: annonceId, bebeIndex: i, uidEleveur: uidEleveur),
        ),
      ],
    ]);
  }
}

class _BabyCard extends StatefulWidget {
  final Map<String, dynamic> animal;
  final String annonceId;
  final int bebeIndex;
  final String? uidEleveur;
  const _BabyCard({required this.animal, required this.annonceId, required this.bebeIndex, this.uidEleveur});
  @override
  State<_BabyCard> createState() => _BabyCardState();
}

class _BabyCardState extends State<_BabyCard> {
  bool _isLiked = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadLike();
  }

  Future<void> _loadLike() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('likes').select('user_uid')
          .eq('annonce_id', widget.annonceId)
          .eq('bebe_index', widget.bebeIndex);
      final all = List<Map<String, dynamic>>.from(rows);
      if (mounted) setState(() {
        _likeCount = all.length;
        _isLiked = all.any((r) => r['user_uid'] == uid);
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final was = _isLiked;
    setState(() { _isLiked = !was; _likeCount = (_likeCount + (was ? -1 : 1)).clamp(0, 99999); });
    try {
      if (was) {
        await Supabase.instance.client.from('likes').delete()
            .eq('user_uid', uid)
            .eq('annonce_id', widget.annonceId)
            .eq('bebe_index', widget.bebeIndex);
      } else {
        await Supabase.instance.client.from('likes').upsert({
          'user_uid': uid,
          'annonce_id': widget.annonceId,
          'bebe_index': widget.bebeIndex,
          'profile_type': User_Info.activeType,
        });
        if (widget.uidEleveur != null && widget.uidEleveur != uid) {
          await Supabase.instance.client.from('notifications').insert({
            'uid': widget.uidEleveur,
            'type': 'like',
            'title': '❤️ Nouveau like sur votre portée',
            'body': 'Quelqu\'un a aimé un bébé de votre portée',
            'data': {'annonceId': widget.annonceId, 'bebeIndex': widget.bebeIndex},
            'read': false,
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() {
        _isLiked = was;
        _likeCount = (_likeCount + (was ? 1 : -1)).clamp(0, 99999);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final photos = List<String>.from(animal['photos'] ?? []);
    final statut = (animal['statut'] as String?) ?? 'disponible';
    final statusColor = statut == 'disponible' ? _green
        : statut == 'reserve' ? const Color(0xFFF59E0B) : Colors.blueGrey;
    final statutLabel = statut == 'disponible' ? 'Disponible'
        : statut == 'reserve' ? 'Réservé' : 'Vendu';

    Widget photo;
    if (photos.isNotEmpty) {
      final p = photos.first;
      photo = p.startsWith('http')
          ? CachedNetworkImage(imageUrl: p, fit: BoxFit.cover, width: double.infinity)
          : Image.file(File(p), fit: BoxFit.cover, width: double.infinity);
    } else {
      photo = Container(color: const Color(0xFFEEF5EA),
          child: const Center(child: Icon(Icons.pets, color: _green, size: 32)));
    }

    final prixRaw = animal['prix'];
    final prix = prixRaw is num ? prixRaw.toDouble()
        : prixRaw is String ? double.tryParse(prixRaw) : null;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _BabyDetailSheet(animal: animal)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(fit: StackFit.expand, children: [
                photo,
                // Indicateur "Voir les photos" (tap sur la carte entière)
                Positioned(bottom: 6, left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black45,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.photo_library_outlined, color: Colors.white, size: 10),
                      SizedBox(width: 3),
                      Text('Voir', style: TextStyle(color: Colors.white,
                          fontSize: 9, fontFamily: 'Galey')),
                    ]))),
                // Bouton like (intercepte le tap, n'ouvre pas le détail)
                Positioned(top: 6, right: 6,
                  child: GestureDetector(
                    onTap: _toggleLike,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black45,
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? Colors.red : Colors.white, size: 11),
                        if (_likeCount > 0) ...[
                          const SizedBox(width: 3),
                          Text('$_likeCount', style: const TextStyle(
                              color: Colors.white, fontSize: 9, fontFamily: 'Galey')),
                        ],
                      ]),
                    ),
                  )),
              ])),
          ),
          Padding(padding: const EdgeInsets.all(8), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              (animal['nom'] as String?)?.isNotEmpty == true
                  ? animal['nom'] as String : 'Bébé',
              style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 13, color: _dark),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${animal['sexe'] == 'male' ? '♂' : '♀'}'
              '${(animal['couleur'] as String?)?.isNotEmpty == true ? ' · ${animal['couleur']}' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                  color: Color(0xFF6F767B))),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(statutLabel, style: TextStyle(fontFamily: 'Galey',
                    fontSize: 10, fontWeight: FontWeight.w700, color: statusColor))),
              if (prix != null) ...[
                const Spacer(),
                Text('${prix.toInt()} €', style: const TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 12, color: _dark)),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ─── Détail bébé ──────────────────────────────────────────────────────────────

class _BabyDetailSheet extends StatefulWidget {
  final Map<String, dynamic> animal;
  const _BabyDetailSheet({required this.animal});
  @override
  State<_BabyDetailSheet> createState() => _BabyDetailSheetState();
}

class _BabyDetailSheetState extends State<_BabyDetailSheet> {
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final photos = List<String>.from(animal['photos'] ?? []);
    final nom    = (animal['nom'] as String?)?.isNotEmpty == true
        ? animal['nom'] as String : 'Bébé';
    final sexe   = animal['sexe'] == 'male' ? '♂ Mâle' : '♀ Femelle';
    final couleur = (animal['couleur'] as String?) ?? '';
    final desc    = (animal['description'] as String?) ?? '';
    final prixRawSheet = animal['prix'];
    final prix    = prixRawSheet is num ? prixRawSheet.toDouble()
        : prixRawSheet is String ? double.tryParse(prixRawSheet) : null;
    final statut  = (animal['statut'] as String?) ?? 'disponible';
    final statusColor = statut == 'disponible' ? _green
        : statut == 'reserve' ? const Color(0xFFF59E0B) : Colors.blueGrey;
    final statutLabel = statut == 'disponible' ? 'Disponible'
        : statut == 'reserve' ? 'Réservé' : 'Vendu';

    Widget photoArea;
    final sqSize = MediaQuery.of(context).size.width;

    Widget _squareImage(String p) => Container(
      color: const Color(0xFFEEF5EA),
      child: p.startsWith('http')
          ? CachedNetworkImage(imageUrl: p, fit: BoxFit.contain,
              width: sqSize, height: sqSize)
          : Image.file(File(p), fit: BoxFit.contain,
              width: sqSize, height: sqSize),
    );

    if (photos.isEmpty) {
      photoArea = SizedBox(width: sqSize, height: sqSize,
          child: Container(color: const Color(0xFFEEF5EA),
              child: const Center(child: Icon(Icons.pets, color: _green, size: 64))));
    } else if (photos.length == 1) {
      photoArea = SizedBox(width: sqSize, height: sqSize,
          child: _squareImage(photos.first));
    } else {
      photoArea = SizedBox(width: sqSize, height: sqSize,
        child: Stack(children: [
          CarouselSlider(
            options: CarouselOptions(height: sqSize, viewportFraction: 1.0,
                onPageChanged: (i, _) => setState(() => _photoIndex = i)),
            items: photos.map((p) => _squareImage(p)).toList(),
          ),
          Positioned(bottom: 10, left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
              children: photos.asMap().entries.map((e) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _photoIndex == e.key ? 18 : 6, height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: _photoIndex == e.key
                      ? Colors.white : Colors.white.withValues(alpha: 0.5)),
              )).toList())),
          // Counter
          Positioned(top: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black45,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${_photoIndex + 1}/${photos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontFamily: 'Galey', fontWeight: FontWeight.w600)))),
        ]));
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        Expanded(child: SingleChildScrollView(child: Column(children: [
          ClipRRect(borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            child: photoArea),
          Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Text(nom, style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w800, fontSize: 20, color: _dark))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(statutLabel, style: TextStyle(fontFamily: 'Galey',
                    fontSize: 12, fontWeight: FontWeight.w700, color: statusColor))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _InfoChip(animal['sexe'] == 'male' ? Icons.male : Icons.female,
                  sexe, animal['sexe'] == 'male' ? _teal : const Color(0xFFEC4899)),
              if (couleur.isNotEmpty) _InfoChip(Icons.palette_outlined, couleur),
              if (prix != null) _InfoChip(Icons.euro_outlined,
                  '${prix.toInt()} €', const Color(0xFF6366F1)),
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Description', style: TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Text(desc, style: const TextStyle(fontFamily: 'Galey',
                  fontSize: 14, color: _dark, height: 1.5)),
            ],
            const SizedBox(height: 16),
          ])),
        ]))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animal individuel
// ─────────────────────────────────────────────────────────────────────────────

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnimalCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final sexe       = (data['sexe'] as String?) ?? '';
    final couleur    = (data['couleur'] as String?) ?? '';
    final dateNaiss  = data['dateNaissanceAnimal'] as Timestamp?;
    final sterilise  = data['sterilise'] as bool? ?? false;

    String ageStr = '';
    if (dateNaiss != null) {
      final age = DateTime.now().difference(dateNaiss.toDate());
      final years  = (age.inDays / 365).floor();
      final months = ((age.inDays % 365) / 30).floor();
      ageStr = years > 0
          ? '$years an${years > 1 ? 's' : ''}'
          : months > 0 ? '$months mois' : '${age.inDays} jours';
    }

    return _sectionCard('Animal', Icons.cruelty_free_outlined, [
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (sexe.isNotEmpty) _InfoChip(
          sexe == 'male' ? Icons.male : Icons.female,
          sexe == 'male' ? 'Mâle' : 'Femelle',
          sexe == 'male' ? _teal : const Color(0xFFEC4899)),
        if (couleur.isNotEmpty) _InfoChip(Icons.palette_outlined, couleur),
        if (ageStr.isNotEmpty) _InfoChip(Icons.cake_outlined, ageStr),
        if (dateNaiss != null)
          _InfoChip(Icons.calendar_today_outlined,
              'Né(e) le ${DateFormat('dd/MM/yyyy').format(dateNaiss.toDate())}'),
        if (sterilise) _InfoChip(Icons.cut_outlined, 'Stérilisé(e)', Colors.orange),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Saillie conditions
// ─────────────────────────────────────────────────────────────────────────────

class _SaillieCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SaillieCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final prix = (data['sailliePrix'] as String?) ?? '';
    final cond = (data['saillieConditions'] as String?) ?? '';

    return _sectionCard('Conditions de saillie', Icons.handshake_outlined, [
      if (prix.isNotEmpty) ...[
        Row(children: [
          const Icon(Icons.euro, size: 16, color: _teal),
          const SizedBox(width: 6),
          Text(prix.contains('€') ? prix : '$prix €',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 18, color: _dark)),
        ]),
        if (cond.isNotEmpty) const SizedBox(height: 10),
      ],
      if (cond.isNotEmpty)
        Text(cond, style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
            color: _dark, height: 1.5)),
      if (prix.isEmpty && cond.isEmpty)
        Text('Conditions à préciser',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Parents (mère + père) avec photos
// ─────────────────────────────────────────────────────────────────────────────

class _ParentsCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ParentsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final mereNom      = (data['mereNom'] as String?) ?? '';
    final merePuce     = (data['merePuce'] as String?) ?? '';
    final mereRace     = (data['mereRace'] as String?) ?? '';
    final mereCouleur  = (data['mereCouleur'] as String?) ?? '';
    final mereDesc     = (data['mereDescription'] as String?) ?? '';
    final mereRegistre = (data['mereRegistre'] as String?) ?? '';
    final merePhoto    = data['merePhotoUrl'] as String?;
    final pereNom      = (data['pereNom'] as String?) ?? '';
    final perePuce     = (data['perePuce'] as String?) ?? '';
    final pereRace     = (data['pereRace'] as String?) ?? '';
    final pereCouleur  = (data['pereCouleur'] as String?) ?? '';
    final pereDesc     = (data['pereDescription'] as String?) ?? '';
    final pereRegistre = (data['pereRegistre'] as String?) ?? '';
    final perePhoto    = data['perePhotoUrl'] as String?;

    final hasParents = mereNom.isNotEmpty || pereNom.isNotEmpty
        || merePhoto != null || perePhoto != null;
    if (!hasParents) return const SizedBox.shrink();

    return _sectionCard('Parents', Icons.family_restroom_outlined, [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _ParentColumn(
          sexe: 'femelle', label: 'Mère',
          color: const Color(0xFFEC4899),
          nom: mereNom, puce: merePuce, race: mereRace,
          couleur: mereCouleur, description: mereDesc,
          registre: mereRegistre, photoUrl: merePhoto)),
        const SizedBox(width: 12),
        Expanded(child: _ParentColumn(
          sexe: 'male', label: 'Père',
          color: _teal,
          nom: pereNom, puce: perePuce, race: pereRace,
          couleur: pereCouleur, description: pereDesc,
          registre: pereRegistre, photoUrl: perePhoto)),
      ]),
    ]);
  }
}

class _ParentColumn extends StatelessWidget {
  final String sexe, label, nom, puce, race, couleur, description, registre;
  final Color color;
  final String? photoUrl;
  const _ParentColumn({
    required this.sexe, required this.label, required this.color,
    required this.nom, required this.puce,
    required this.race, required this.couleur, required this.description,
    required this.registre, this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = nom.isNotEmpty || photoUrl != null;
    final tappable = photoUrl != null || nom.isNotEmpty;

    return GestureDetector(
      onTap: tappable ? () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ParentDetailSheet(
          sexe: sexe, label: label, color: color,
          nom: nom, puce: puce, race: race,
          couleur: couleur, description: description,
          registre: registre, photoUrl: photoUrl,
        ),
      ) : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(sexe == 'femelle' ? Icons.female : Icons.male, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 13, color: color)),
            const Spacer(),
            if (tappable)
              Icon(Icons.open_in_new, size: 13, color: color.withValues(alpha: 0.5)),
          ]),
          const SizedBox(height: 8),
          // Photo parent (thumbnail)
          if (photoUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(color: const Color(0xFFEEF5EA),
                child: CachedNetworkImage(
                imageUrl: photoUrl!, height: 100, width: double.infinity,
                fit: BoxFit.contain,
                placeholder: (_, __) => Container(
                    height: 100, color: const Color(0xFFEEF5EA)),
                errorWidget: (_, __, ___) => Container(
                    height: 100,
                    color: const Color(0xFFEEF5EA),
                    child: Center(child: Icon(
                        sexe == 'femelle' ? Icons.female : Icons.male,
                        color: color.withValues(alpha: 0.4), size: 36))),
              ))),
            const SizedBox(height: 8),
          ],
          if (!hasData)
            Text('Non renseigné', style: TextStyle(fontFamily: 'Galey',
                fontSize: 12, color: Colors.grey.shade400,
                fontStyle: FontStyle.italic))
          else ...[
            if (nom.isNotEmpty)
              Text(nom, style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w600, fontSize: 13, color: _dark)),
            if (puce.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('Puce : $puce', style: TextStyle(fontFamily: 'Galey',
                  fontSize: 11, color: Colors.grey.shade500)),
            ],
            if (registre.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(registre, style: TextStyle(fontFamily: 'Galey',
                    fontSize: 10, fontWeight: FontWeight.w700, color: color))),
            ],
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Détail parent (photo en carré + infos)
// ─────────────────────────────────────────────────────────────────────────────

class _ParentDetailSheet extends StatelessWidget {
  final String sexe, label, nom, puce, race, couleur, description, registre;
  final Color color;
  final String? photoUrl;
  const _ParentDetailSheet({
    required this.sexe, required this.label, required this.color,
    required this.nom, required this.puce,
    required this.race, required this.couleur, required this.description,
    required this.registre, this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final sqSize = MediaQuery.of(context).size.width;

    return Container(
      decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        // Photo carré
        if (photoUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: SizedBox(width: sqSize, height: sqSize,
              child: Container(
                color: const Color(0xFFEEF5EA),
                child: CachedNetworkImage(
                  imageUrl: photoUrl!, fit: BoxFit.contain,
                  width: sqSize, height: sqSize,
                  placeholder: (_, __) => Container(
                      color: const Color(0xFFEEF5EA)),
                  errorWidget: (_, __, ___) => Center(
                      child: Icon(
                          sexe == 'femelle' ? Icons.female : Icons.male,
                          color: color.withValues(alpha: 0.4), size: 64)),
                ),
              ),
            ),
          )
        else
          Container(width: sqSize, height: 160, color: const Color(0xFFEEF5EA),
              child: Center(child: Icon(
                  sexe == 'femelle' ? Icons.female : Icons.male,
                  color: color.withValues(alpha: 0.35), size: 64))),
        // Infos
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(sexe == 'femelle' ? Icons.female : Icons.male,
                  color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w800, fontSize: 18, color: color)),
              if (nom.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('· $nom', style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
              ],
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (race.isNotEmpty)
                _InfoChip(Icons.pets_outlined, race),
              if (couleur.isNotEmpty)
                _InfoChip(Icons.palette_outlined, couleur),
            ]),
            if (puce.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.qr_code_outlined, size: 15, color: _teal),
                const SizedBox(width: 6),
                Expanded(child: Text('Puce : $puce',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                        color: _dark))),
              ]),
            ],
            if (registre.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(registre, style: TextStyle(fontFamily: 'Galey',
                    fontSize: 13, fontWeight: FontWeight.w700, color: color))),
            ],
            if (description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Description', style: TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 13,
                  color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Text(description, style: const TextStyle(fontFamily: 'Galey',
                  fontSize: 14, color: _dark, height: 1.5)),
            ],
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Santé
// ─────────────────────────────────────────────────────────────────────────────

class _SanteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SanteCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final vaccines      = data['vaccines']      as bool? ?? false;
    final vermifuge     = data['vermifuge']      as bool? ?? false;
    final identification = data['identification'] as bool? ?? false;
    final bilanSante    = data['bilanSante']     as bool? ?? false;
    final semaines      = (data['semaines'] as num?)?.toInt();
    final typeVente     = (data['typeVente'] as String?) ?? '';

    return _sectionCard('Santé & Conformité', Icons.health_and_safety_outlined, [
      _HealthRow(Icons.vaccines_outlined,           'Vacciné(e)',                   vaccines),
      _HealthRow(Icons.medication_outlined,         'Vermifugé(e)',                 vermifuge),
      _HealthRow(Icons.qr_code_outlined,            'Pucé(e) / Tatoué(e)',          identification),
      _HealthRow(Icons.medical_services_outlined,   'Bilan de santé vétérinaire',   bilanSante),
      if (semaines != null && typeVente != 'saillie') ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule_outlined, size: 16, color: _teal),
          const SizedBox(width: 8),
          Text('Cession à partir de $semaines semaines',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _dark)),
          if (semaines < 8) ...[
            const SizedBox(width: 6),
            const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
            const SizedBox(width: 3),
            const Text('min. légal : 8 sem.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.orange)),
          ],
        ]),
      ],
    ]);
  }
}

class _HealthRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool checked;
  const _HealthRow(this.icon, this.label, this.checked);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(checked ? Icons.check_circle : Icons.cancel_outlined,
          color: checked ? _green : Colors.grey.shade300, size: 18),
      const SizedBox(width: 10),
      Icon(icon, size: 15, color: Colors.grey.shade400),
      const SizedBox(width: 7),
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
          color: checked ? _dark : Colors.grey.shade400)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pedigree
// ─────────────────────────────────────────────────────────────────────────────

class _PedigreeCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String espece;
  const _PedigreeCard({required this.data, required this.espece});

  String get _registreLabel => switch (espece) {
    'chien' => 'LOF', 'chat' => 'LOOF', 'cheval' => 'SIRE', _ => 'Registre',
  };

  @override
  Widget build(BuildContext context) {
    final registreType = (data['registreType'] as String?) ?? '';
    final numRegistre  = (data['numeroRegistre'] as String?) ?? '';
    final clubPedigree = (data['clubPedigree'] as String?) ?? '';
    final studbook     = (data['studbook'] as String?) ?? '';

    return _sectionCard('Pedigree & $_registreLabel', Icons.account_tree_outlined, [
      if (registreType.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _teal.withValues(alpha: 0.2))),
          child: Text(registreType, style: const TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: _teal))),
        const SizedBox(height: 10),
      ],
      if (numRegistre.isNotEmpty)
        _InfoRow('N° inscription', numRegistre),
      if (studbook.isNotEmpty)
        _InfoRow('Studbook', studbook),
      if (clubPedigree.isNotEmpty)
        _InfoRow('Club de race', clubPedigree),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Éleveur
// ─────────────────────────────────────────────────────────────────────────────

class _EleveurCard extends StatelessWidget {
  final Map<String, dynamic>? eleveurData;
  final String uidEleveur;
  const _EleveurCard({this.eleveurData, required this.uidEleveur});

  @override
  Widget build(BuildContext context) {
    if (eleveurData == null) return const SizedBox.shrink();
    final name     = (eleveurData!['nameElevage'] ?? eleveurData!['firstname'] ?? 'Éleveur') as String;
    final photoUrl = (eleveurData!['profilePictureUrlElevage'] ?? eleveurData!['profilePictureUrl']) as String?;
    final ville    = (eleveurData!['villeElevage'] ?? eleveurData!['ville'] ?? '') as String;

    void goToProfile() {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => UserDetailPageFeed(
          user: UserSelected.fromMap(eleveurData!, uidEleveur)),
      ));
    }

    return Container(
      decoration: _cardDeco(),
      child: Column(children: [
        // ── Profil row (tappable) ───────────────────────────────────────
        InkWell(
          onTap: goToProfile,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 28, backgroundColor: const Color(0xFFEEF5EA),
                backgroundImage: photoUrl != null
                    ? CachedNetworkImageProvider(photoUrl) : null,
                child: photoUrl == null
                    ? const Icon(Icons.pets, color: _green, size: 24) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 15, color: _dark),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.verified, color: _green, size: 13),
                  const SizedBox(width: 4),
                  const Text('Éleveur vérifié', style: TextStyle(fontFamily: 'Galey',
                      fontSize: 12, color: _green, fontWeight: FontWeight.w500)),
                ]),
                if (ville.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(ville, style: TextStyle(fontFamily: 'Galey',
                        fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                ],
              ])),
              const SizedBox(width: 8),
              Text('Voir le profil', style: TextStyle(fontFamily: 'Galey',
                  fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, color: _teal, size: 18),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Barre basse CTA
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatefulWidget {
  final bool isOwner;
  final String annonceId;
  final Map<String, dynamic> data;
  final String uidEleveur;
  const _BottomBar({
    required this.isOwner, required this.annonceId,
    required this.data, required this.uidEleveur,
  });
  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _loading = false;

  void _share() {
    final data = widget.data;
    final espece    = (data['espece'] as String?) ?? '';
    final race      = (data['race'] as String?) ?? '';
    final titre     = (data['titre'] as String?) ?? '';
    final typeVente = (data['typeVente'] as String?) ?? '';
    final prix      = (data['prix'] as num?)?.toInt();
    final ville     = (data['villeEleveur'] as String?) ?? '';
    final displayTitle = titre.isNotEmpty ? titre : race.isNotEmpty ? race : espece;
    final annonceUrl = 'https://www.petsmatchapp.com/annonces/${widget.annonceId}';

    final lines = <String>['🐾 $displayTitle'];
    if (espece.isNotEmpty || race.isNotEmpty)
      lines.add([espece, race].where((s) => s.isNotEmpty).join(' · '));
    if (typeVente == 'vente' && prix != null) lines.add('💰 $prix €');
    if (typeVente == 'adoption') lines.add('💚 Adoption / Don');
    if (typeVente == 'saillie') lines.add('💜 Saillie');
    if (ville.isNotEmpty) lines.add('📍 $ville');
    lines.addAll(['', 'Voir l\'annonce sur PetsMatch 🐾', annonceUrl]);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(text: lines.join('\n'), url: annonceUrl, nom: displayTitle),
    );
  }

  Future<void> _openChat() async {
    if (widget.uidEleveur.isEmpty) return;
    setState(() => _loading = true);
    // Track contact click
    Supabase.instance.client.from('annonces')
        .select('contacts').eq('id', widget.annonceId).single()
        .then((r) => Supabase.instance.client.from('annonces')
            .update({'contacts': ((r['contacts'] as int?) ?? 0) + 1})
            .eq('id', widget.annonceId))
        .catchError((_) {});
    try {
      final me = FirebaseAuth.instance.currentUser!.uid;
      final sorted = [me, widget.uidEleveur]..sort();
      final participantIds = sorted.join('_');
      final snap = await FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', isEqualTo: participantIds)
          .limit(1).get();
      final profileTypes = <String, String>{
        widget.uidEleveur: 'eleveur',
        me: User_Info.catPro.isNotEmpty ? User_Info.catPro
            : (User_Info.isElevage ? 'eleveur' : 'particulier'),
      };
      DocumentReference ref;
      if (snap.docs.isEmpty) {
        ref = await FirebaseFirestore.instance.collection('conversations').add({
          'participants': [me, widget.uidEleveur],
          'participantIds': participantIds,
          'lastMessage': '',
          'timestamp': FieldValue.serverTimestamp(),
          'categorie': 'annonces',
          'participant_profile_types': profileTypes,
        });
      } else {
        ref = snap.docs.first.reference;
        final existing = snap.docs.first.data() as Map<String, dynamic>;
        if (existing['participant_profile_types'] == null) {
          await ref.update({'participant_profile_types': profileTypes});
        }
      }
      if (mounted) Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatScreen(
              conversationId: ref.id, eleveurId: widget.uidEleveur)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
            color: Colors.black12, blurRadius: 12, offset: Offset(0, -3))],
      ),
      child: Row(children: [
        Expanded(
          child: widget.isOwner
              ? OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CreateAnnoncePage(
                          annonceId: widget.annonceId, initialData: widget.data))),
                  icon: const Icon(Icons.edit_outlined, size: 18, color: _teal),
                  label: const Text('Modifier l\'annonce',
                      style: TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w700, fontSize: 15, color: _teal)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _teal),
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ))
              : ElevatedButton(
                  onPressed: _loading ? null : _openChat,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.chat_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Contacter l\'éleveur', style: TextStyle(
                              fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                        ]),
                ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 50, width: 50,
          child: OutlinedButton(
            onPressed: _share,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Icon(Icons.share_outlined, color: _teal, size: 22),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets partagés
// ─────────────────────────────────────────────────────────────────────────────

BoxDecoration _cardDeco() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  boxShadow: [BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 8, offset: const Offset(0, 2))],
);

Widget _sectionCard(String title, IconData icon, List<Widget> children) =>
    Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: _teal, size: 18), const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 14, color: _teal)),
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
        fontWeight: FontWeight.w700, color: color)),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _InfoChip(this.icon, this.label, [this.color]);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color ?? _teal),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
          fontWeight: FontWeight.w600, color: color ?? _dark)),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120,
        child: Text(label, style: TextStyle(fontFamily: 'Galey',
            fontSize: 12, color: Colors.grey.shade500))),
      Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Galey',
          fontWeight: FontWeight.w600, fontSize: 12, color: _dark))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Share sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String text, url, nom;
  const _ShareSheet({required this.text, required this.url, required this.nom});

  Future<void> _copy(BuildContext ctx) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (ctx.mounted) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Lien copié !'), duration: Duration(seconds: 2)));
    }
  }

  Future<void> _launch(BuildContext ctx, Uri uri) async {
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
    if (ctx.mounted) Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final encoded  = Uri.encodeComponent(text);
    final waUrl    = Uri.parse('https://wa.me/?text=$encoded');
    final smsUrl   = Uri.parse('sms:?body=$encoded');
    final emailUrl = Uri.parse('mailto:?subject=${Uri.encodeComponent(nom)}&body=$encoded');
    final safe     = MediaQuery.of(context).padding;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, safe.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(nom,
            style: const TextStyle(color: Colors.white, fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 15),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ShareBtn(icon: const Icon(Icons.link_rounded, color: Colors.white, size: 24),
              bg: const Color(0xFF3A3A4E), label: 'Copier le lien',
              onTap: () => _copy(context)),
          _ShareBtn(icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 24),
              bg: const Color(0xFF25D366), label: 'WhatsApp',
              onTap: () => _launch(context, waUrl)),
          _ShareBtn(icon: const Icon(Icons.sms_outlined, color: Colors.white, size: 24),
              bg: const Color(0xFF4A90E2), label: 'SMS',
              onTap: () => _launch(context, smsUrl)),
          _ShareBtn(icon: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 24),
              bg: const Color(0xFFEA4335), label: 'Email',
              onTap: () => _launch(context, emailUrl)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Likes row (sous le header de l'annonce)
// ─────────────────────────────────────────────────────────────────────────────

class _LikesRow extends StatelessWidget {
  final String annonceId;
  final int count;
  final bool isLiked;
  final List<Map<String, dynamic>> likers;
  final VoidCallback onLike;
  final VoidCallback? onShowList;

  const _LikesRow({
    required this.annonceId,
    required this.count,
    required this.isLiked,
    required this.likers,
    required this.onLike,
    this.onShowList,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = FirebaseAuth.instance.currentUser != null;
    return Row(
      children: [
        // Bouton like
        GestureDetector(
          onTap: isConnected ? onLike : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isLiked
                  ? Colors.redAccent.withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isLiked ? Colors.redAccent.withValues(alpha: 0.4) : Colors.grey.shade300,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.redAccent : Colors.grey.shade500,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                count > 0 ? '$count' : "J'aime",
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isLiked ? Colors.redAccent : Colors.grey.shade600,
                ),
              ),
            ]),
          ),
        ),
        // Avatars des likeurs (connectés seulement)
        if (isConnected && likers.isNotEmpty) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onShowList,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              // Avatars empilés
              SizedBox(
                width: likers.length * 20.0 + 12,
                height: 28,
                child: Stack(
                  children: likers.asMap().entries.map((e) {
                    final u = e.value;
                    final photo = u['profile_picture_url'] as String?;
                    return Positioned(
                      left: e.key * 20.0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: ClipOval(
                          child: photo != null && photo.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: photo,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                      color: _teal,
                                      child: const Icon(Icons.person, color: Colors.white, size: 14)),
                                )
                              : Container(
                                  color: _teal,
                                  child: const Icon(Icons.person, color: Colors.white, size: 14)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 6),
              if (count > 0)
                Text(
                  count == 1
                      ? '${likers.first['firstname'] ?? ''} a aimé'
                      : count <= likers.length
                          ? '${likers.first['firstname'] ?? ''} et ${count - 1} autre${count > 2 ? 's' : ''}'
                          : 'Voir les ${count} j\'aimes',
                  style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
            ]),
          ),
        ],
        // Anonyme : juste le compte si > 0 et pas de bouton
        if (!isConnected && count > 0) ...[
          const SizedBox(width: 10),
          Text(
            '$count j\'aime${count > 1 ? 's' : ''}',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet : liste complète des likeurs
// ─────────────────────────────────────────────────────────────────────────────

class _LikersSheet extends StatefulWidget {
  final String annonceId;
  const _LikersSheet({required this.annonceId});
  @override
  State<_LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends State<_LikersSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('likes')
          .select('user_uid')
          .eq('annonce_id', widget.annonceId)
          .isFilter('bebe_index', null)
          .order('created_at', ascending: false);
      final uids = List<Map<String, dynamic>>.from(rows)
          .map((r) => r['user_uid'] as String)
          .toList();
      if (uids.isEmpty) {
        if (mounted) setState(() { _list = []; _loading = false; });
        return;
      }
      final users = await Supabase.instance.client
          .from('users')
          .select('uid, firstname, lastname, profile_picture_url')
          .inFilter('uid', uids);
      final userMap = <String, Map<String, dynamic>>{
        for (final u in List<Map<String, dynamic>>.from(users))
          u['uid'] as String: u,
      };
      final ordered = uids.map((id) => userMap[id]).whereType<Map<String, dynamic>>().toList();
      if (mounted) setState(() { _list = ordered; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(0, 12, 0, safe.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              _loading ? "J'aimes" : '${_list.length} j\'aime${_list.length > 1 ? 's' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 15, color: _dark),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
        else if (_list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text("Sois le premier à aimer cette annonce !",
                style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500,
                    fontSize: 13),
                textAlign: TextAlign.center),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _list.length,
              itemBuilder: (_, i) {
                final u = _list[i];
                final photo = u['profile_picture_url'] as String?;
                final name = [u['firstname'], u['lastname']]
                    .where((s) => s?.toString().isNotEmpty == true)
                    .join(' ');
                return ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: _teal,
                    backgroundImage: photo?.isNotEmpty == true
                        ? CachedNetworkImageProvider(photo!) : null,
                    child: photo?.isNotEmpty != true
                        ? const Icon(Icons.person, color: Colors.white, size: 18) : null,
                  ),
                  title: Text(name.isNotEmpty ? name : 'Utilisateur',
                      style: const TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  trailing: const Icon(Icons.favorite, color: Colors.redAccent, size: 16),
                );
              },
            ),
          ),
      ]),
    );
  }
}

class _ShareBtn extends StatelessWidget {
  final Widget icon;
  final Color bg;
  final String label;
  final VoidCallback onTap;
  const _ShareBtn({required this.icon, required this.bg, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Center(child: icon),
      ),
      const SizedBox(height: 6),
      SizedBox(width: 60,
        child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Galey'),
            textAlign: TextAlign.center, maxLines: 2)),
    ]),
  );
}
