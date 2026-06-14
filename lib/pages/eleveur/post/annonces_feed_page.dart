import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/pages/main_feed.dart' show UserSelected;
import 'package:PetsMatch/widgets/verification_badge.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils/storage_helper.dart' show thumbUrl;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Modèle ───────────────────────────────────────────────────────────────────

class _FeedItem {
  final String annonceId;
  final int? bebeIndex;
  final List<String> photos;
  final String nom;
  final String? race;
  final String? espece;
  final String? sexe;
  final double? prix;
  final String? statut;
  final String? description;
  final String? ville;
  final String? uidEleveur;
  final String? nomEleveur;
  final String? photoEleveur;
  final bool pedigree;
  final DateTime? dateNaissance;
  final String? typeVente;
  final bool eleveurVerifie;
  final bool eleveurPremium;

  const _FeedItem({
    required this.annonceId, required this.bebeIndex,
    required this.photos, required this.nom,
    this.race, this.espece, this.sexe, this.prix,
    this.statut, this.description, this.ville,
    this.uidEleveur, this.nomEleveur, this.photoEleveur,
    this.pedigree = false, this.dateNaissance,
    this.typeVente,
    this.eleveurVerifie = false, this.eleveurPremium = false,
  });

  _FeedItem withPhoto(String? p) => _FeedItem(
    annonceId: annonceId, bebeIndex: bebeIndex, photos: photos, nom: nom,
    race: race, espece: espece, sexe: sexe, prix: prix, statut: statut,
    description: description, ville: ville, uidEleveur: uidEleveur,
    nomEleveur: nomEleveur, photoEleveur: p, pedigree: pedigree,
    dateNaissance: dateNaissance, typeVente: typeVente,
    eleveurVerifie: eleveurVerifie, eleveurPremium: eleveurPremium,
  );

  _FeedItem withVerification({required bool verifie, required bool premium}) => _FeedItem(
    annonceId: annonceId, bebeIndex: bebeIndex, photos: photos, nom: nom,
    race: race, espece: espece, sexe: sexe, prix: prix, statut: statut,
    description: description, ville: ville, uidEleveur: uidEleveur,
    nomEleveur: nomEleveur, photoEleveur: photoEleveur, pedigree: pedigree,
    dateNaissance: dateNaissance, typeVente: typeVente,
    eleveurVerifie: verifie, eleveurPremium: premium,
  );
}

String? _ageLabel(DateTime? date) {
  if (date == null) return null;
  final days = DateTime.now().difference(date).inDays;
  if (days < 0) return null;
  if (days < 91) {
    final weeks = (days / 7).floor();
    return weeks <= 1 ? '1 semaine' : '$weeks semaines';
  }
  final months = (days / 30.44).floor();
  if (months >= 12) {
    final years = (days / 365.25).floor();
    return years <= 1 ? '1 an' : '$years ans';
  }
  return months <= 1 ? '1 mois' : '$months mois';
}

String _pedigreeLabel(String? espece, bool hasPedigree) {
  final String label;
  switch (espece) {
    case 'chien': label = 'LOF'; break;
    case 'chat':  label = 'LOOF'; break;
    case 'cheval':
    case 'ane':   label = 'Stud-book'; break;
    default:      label = 'Pedigree'; break;
  }
  return hasPedigree ? '$label ✓' : 'Non $label';
}

List<_FeedItem> _buildFeedItems(List<Map<String, dynamic>> rows) {
  final items = <_FeedItem>[];
  for (final a in rows) {
    final aPhotos    = List<String>.from(a['photos'] ?? []);
    final bebes      = List<Map<String, dynamic>>.from(a['animaux_portee'] ?? []);
    final uid        = a['uid_eleveur'] as String?;
    final nomEleveur = a['nom_eleveur'] as String?;

    final dateNaissancePortee = a['date_naissance'] is String
        ? DateTime.tryParse(a['date_naissance'] as String) : null;
    final dateNaissanceAnimal = a['date_naissance_animal'] is String
        ? DateTime.tryParse(a['date_naissance_animal'] as String) : null;

    if (a['type'] == 'portee' && bebes.isNotEmpty) {
      for (int i = 0; i < bebes.length; i++) {
        final b = bebes[i];
        final bPhotos = List<String>.from(b['photos'] ?? []);
        final photos  = bPhotos.isNotEmpty ? bPhotos : aPhotos;
        if (photos.isEmpty) continue;
        items.add(_FeedItem(
          annonceId: a['id'] as String, bebeIndex: i, photos: photos,
          nom: b['nom'] as String? ?? 'Bébé ${i + 1}',
          race: a['race'] as String?, espece: a['espece'] as String?,
          sexe: b['sexe'] as String?,
          prix: b['prix'] is num ? (b['prix'] as num).toDouble()
              : b['prix'] is String ? double.tryParse(b['prix'] as String) : null,
          statut: b['statut'] as String?,
          description: b['description'] as String?,
          ville: a['ville_eleveur'] as String?,
          uidEleveur: uid, nomEleveur: nomEleveur,
          pedigree: b['pedigree'] == true,
          dateNaissance: dateNaissancePortee,
          typeVente: a['type_vente'] as String?,
        ));
      }
    } else if (aPhotos.isNotEmpty) {
      items.add(_FeedItem(
        annonceId: a['id'] as String, bebeIndex: null, photos: aPhotos,
        nom: (a['titre'] as String?)?.isNotEmpty == true
            ? a['titre'] as String
            : '${a['espece'] ?? ''} ${a['race'] ?? ''}'.trim(),
        race: a['race'] as String?, espece: a['espece'] as String?,
        sexe: a['sexe'] as String?,
        prix: () { final v = a['saillie_prix'] ?? a['prix']; return v is num ? v.toDouble() : v is String ? double.tryParse(v) : null; }(),
        description: a['description'] as String?,
        pedigree: () {
          final rt = a['registre_type'];
          return rt is String && rt.isNotEmpty && !rt.startsWith('Non ');
        }(),
        ville: a['ville_eleveur'] as String?,
        uidEleveur: uid, nomEleveur: nomEleveur,
        dateNaissance: dateNaissanceAnimal,
        typeVente: a['type_vente'] as String?,
      ));
    }
  }
  return items;
}

// ─── Page principale ──────────────────────────────────────────────────────────

class AnnoncesFeedPage extends StatefulWidget {
  final String  initialTypeFilter;
  final String  initialEspece;
  final String? initialRace;
  final String? initialAnnonceId;
  final int?    initialBebeIndex;

  const AnnoncesFeedPage({
    super.key,
    this.initialTypeFilter = 'tous',
    this.initialEspece = 'tous',
    this.initialRace,
    this.initialAnnonceId,
    this.initialBebeIndex,
  });

  @override
  State<AnnoncesFeedPage> createState() => _AnnoncesFeedPageState();
}

class _AnnoncesFeedPageState extends State<AnnoncesFeedPage> {
  static const _teal = Color(0xFF0C5C6C);

  bool _feedStarted  = false;
  bool _loading      = false;
  bool _openingChat  = false;

  late String  _espece    = widget.initialEspece;
  late String  _typeVente = widget.initialTypeFilter;
  late String? _race      = widget.initialRace;
  List<String> _races     = [];
  final _raceCtrl   = TextEditingController();
  final _especeCtrl = TextEditingController();

  static const _especeToAsset = {
    'chien':   'assets/dog_breeds.json',
    'chat':    'assets/cat_breeds.json',
    'lapin':   'assets/rabbit_breeds.json',
    'oiseau':  'assets/bird_breeds.json',
    'cheval':  'assets/horse_breeds.json',
    'ane':     'assets/donkey_breeds.json',
    'ovin':    'assets/sheep_breeds.json',
    'caprin':  'assets/goat_breeds.json',
    'porcin':  'assets/pig_breeds.json',
    'nac':     'assets/nac_breeds.json',
  };

  Future<void> _loadRaces(String espece) async {
    final asset = _especeToAsset[espece];
    if (asset == null) { setState(() => _races = []); return; }
    try {
      final raw = await rootBundle.loadString(asset);
      final list = (jsonDecode(raw) as List).cast<String>();
      setState(() => _races = list);
    } catch (_) {
      setState(() => _races = []);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_espece != 'tous') {
      final label = _especeList.firstWhere((e) => e.$1 == _espece, orElse: () => ('', _espece, '')).$2;
      _especeCtrl.text = label;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRaces(_espece));
    }
    // Auto-démarrage si on vient d'une notification ou "Animaux similaires"
    if (widget.initialAnnonceId != null || widget.initialRace != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFeed());
    }
  }

  List<_FeedItem> _items = [];
  final _vertCtrl        = PageController();
  final _likedKeys        = <String>{};
  final _favoriKeys       = <String>{};
  final _likeCounts       = <String, int>{};
  final _favoriCounts     = <String, int>{};

  static const _especeList = [
    ('tous',    'Toutes espèces', '🐾'),
    ('chien',   'Chien',     '🐕'),
    ('chat',    'Chat',      '🐈'),
    ('cheval',  'Cheval',    '🐴'),
    ('ane',     'Âne',       '🫏'),
    ('lapin',   'Lapin',     '🐇'),
    ('oiseau',  'Oiseau',    '🦜'),
    ('nac',     'NAC',       '🦎'),
    ('ovin',    'Ovin',      '🐑'),
    ('caprin',  'Caprin',    '🐐'),
    ('porcin',  'Porcin',    '🐷'),
    ('autre',   'Autre',     '🐾'),
  ];

  // ── Chargement ──────────────────────────────────────────────────────────────

  Future<void> _loadFeed() async {
    setState(() => _loading = true);
    try {
      var q = Supabase.instance.client
          .from('annonces')
          .select('id, titre, espece, race, type, type_vente, photos, animaux_portee, prix, saillie_prix, ville_eleveur, sexe, nom_eleveur, uid_eleveur, description, registre_type, date_naissance, date_naissance_animal')
          .eq('statut', 'disponible');
      if (_espece != 'tous')       q = q.eq('espece', _espece);
      if (_race   != null)         q = q.eq('race', _race!);
      if (_typeVente == 'saillie') q = q.eq('type_vente', 'saillie');
      if (_typeVente == 'vente')   q = q.neq('type_vente', 'saillie');

      final rows = await q.order('created_at', ascending: false);
      var items = _buildFeedItems(List<Map<String, dynamic>>.from(rows));

      // Batch photos éleveurs
      final uids = items.map((i) => i.uidEleveur).whereType<String>().toSet().toList();
      if (uids.isNotEmpty) {
        try {
          final users = await Supabase.instance.client
              .from('users')
              .select('uid, profile_picture_url_elevage, profile_picture_url, statut_pro, siret, is_premium')
              .inFilter('uid', uids);
          final photoMap    = <String, String>{};
          final verifiedMap = <String, bool>{};
          final premiumMap  = <String, bool>{};
          for (final u in List<Map<String, dynamic>>.from(users)) {
            final id = u['uid'] as String?;
            if (id == null) continue;
            final ph = (u['profile_picture_url_elevage'] as String?)?.isNotEmpty == true
                ? u['profile_picture_url_elevage'] as String
                : (u['profile_picture_url'] as String?) ?? '';
            if (ph.isNotEmpty) photoMap[id] = ph;
            final siret = u['siret']?.toString() ?? '';
            verifiedMap[id] = u['statut_pro'] == 'actif' && siret.isNotEmpty;
            premiumMap[id]  = u['is_premium'] == true;
          }
          items = items.map((i) {
            final uid = i.uidEleveur;
            return i
              .withPhoto(uid != null ? photoMap[uid] : null)
              .withVerification(
                verifie: uid != null && (verifiedMap[uid] ?? false),
                premium: uid != null && (premiumMap[uid] ?? false),
              );
          }).toList();
        } catch (_) {}
      }

      // Likes & favoris
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final likes = await Supabase.instance.client
              .from('likes').select('annonce_id, bebe_index').eq('user_uid', uid);
          _likedKeys
            ..clear()
            ..addAll(List<Map<String, dynamic>>.from(likes)
                .map((l) => '${l['annonce_id']}_${l['bebe_index'] ?? 'null'}'));
        } catch (_) {}
        try {
          final favs = await Supabase.instance.client
              .from('favoris').select('annonce_id, bebe_index').eq('user_uid', uid);
          _favoriKeys
            ..clear()
            ..addAll(List<Map<String, dynamic>>.from(favs)
                .map((f) => '${f['annonce_id']}_${f['bebe_index'] ?? 'null'}'));
        } catch (_) {}
      }

      // Compteurs globaux (tous utilisateurs)
      try {
        final annonceIds = items.map((i) => i.annonceId).toSet().toList();
        if (annonceIds.isNotEmpty) {
          final allLikes = await Supabase.instance.client
              .from('likes').select('annonce_id, bebe_index').inFilter('annonce_id', annonceIds);
          _likeCounts.clear();
          for (final l in List<Map<String, dynamic>>.from(allLikes)) {
            final k = '${l['annonce_id']}_${l['bebe_index'] ?? 'null'}';
            _likeCounts[k] = (_likeCounts[k] ?? 0) + 1;
          }
          final allFavs = await Supabase.instance.client
              .from('favoris').select('annonce_id, bebe_index').inFilter('annonce_id', annonceIds);
          _favoriCounts.clear();
          for (final f in List<Map<String, dynamic>>.from(allFavs)) {
            final k = '${f['annonce_id']}_${f['bebe_index'] ?? 'null'}';
            _favoriCounts[k] = (_favoriCounts[k] ?? 0) + 1;
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() { _items = items; _loading = false; _feedStarted = true; });
        // Sauter directement à l'annonce demandée (ex: depuis une notification)
        if (widget.initialAnnonceId != null) {
          final idx = items.indexWhere((i) =>
              i.annonceId == widget.initialAnnonceId &&
              i.bebeIndex == widget.initialBebeIndex);
          if (idx > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_vertCtrl.hasClients) _vertCtrl.jumpToPage(idx);
            });
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Like ────────────────────────────────────────────────────────────────────

  Future<void> _toggleLike(_FeedItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key      = '${item.annonceId}_${item.bebeIndex ?? 'null'}';
    final wasLiked = _likedKeys.contains(key);
    setState(() {
      wasLiked ? _likedKeys.remove(key) : _likedKeys.add(key);
      _likeCounts[key] = ((_likeCounts[key] ?? 0) + (wasLiked ? -1 : 1)).clamp(0, 9999999);
    });
    try {
      if (wasLiked) {
        var q = Supabase.instance.client.from('likes').delete()
            .eq('user_uid', uid).eq('annonce_id', item.annonceId);
        item.bebeIndex != null ? await q.eq('bebe_index', item.bebeIndex!) : await q.isFilter('bebe_index', null);
      } else {
        await Supabase.instance.client.from('likes').upsert({
          'user_uid': uid, 'annonce_id': item.annonceId, 'bebe_index': item.bebeIndex,
          'profile_type': User_Info.activeType,
        });
        if (item.uidEleveur != null && item.uidEleveur != uid) {
          final name = User_Info.firstname.isNotEmpty ? User_Info.firstname : 'Quelqu\'un';
          await Supabase.instance.client.from('notifications').insert({
            'uid': item.uidEleveur, 'type': 'like',
            'title': '❤️ Nouveau like sur votre annonce',
            'body': '$name a aimé "${item.nom}"',
            'data': {'annonceId': item.annonceId, 'bebeIndex': item.bebeIndex, 'fromUid': uid},
            'read': false,
          });
          // Push via Firebase Cloud Functions (même infra que les alertes)
          unawaited(FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('sendLikeNotification')
              .call({
                'receiverUid': item.uidEleveur,
                'annonceId':   item.annonceId,
                'bebeIndex':   item.bebeIndex,
                'nomAnimal':   item.nom,
                'senderName':  name,
              }));
        }
      }
    } catch (_) {
      setState(() {
        wasLiked ? _likedKeys.add(key) : _likedKeys.remove(key);
        _likeCounts[key] = ((_likeCounts[key] ?? 0) + (wasLiked ? 1 : -1)).clamp(0, 9999999);
      });
    }
  }

  // ── Favori ──────────────────────────────────────────────────────────────────

  Future<void> _toggleFavori(_FeedItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = '${item.annonceId}_${item.bebeIndex ?? 'null'}';
    final was = _favoriKeys.contains(key);
    setState(() {
      was ? _favoriKeys.remove(key) : _favoriKeys.add(key);
      _favoriCounts[key] = ((_favoriCounts[key] ?? 0) + (was ? -1 : 1)).clamp(0, 9999999);
    });
    try {
      if (was) {
        var q = Supabase.instance.client.from('favoris').delete()
            .eq('user_uid', uid).eq('annonce_id', item.annonceId);
        item.bebeIndex != null ? await q.eq('bebe_index', item.bebeIndex!) : await q.isFilter('bebe_index', null);
      } else {
        await Supabase.instance.client.from('favoris').upsert({
          'user_uid': uid, 'annonce_id': item.annonceId, 'bebe_index': item.bebeIndex,
          'profile_type': User_Info.activeType,
        });
      }
    } catch (_) {
      setState(() {
        was ? _favoriKeys.add(key) : _favoriKeys.remove(key);
        _favoriCounts[key] = ((_favoriCounts[key] ?? 0) + (was ? 1 : -1)).clamp(0, 9999999);
      });
    }
  }

  // ── Partage ──────────────────────────────────────────────────────────────────

  void _shareItem(_FeedItem item) {
    final url = 'https://www.petsmatchapp.com/annonces/${item.annonceId}';
    final parts = <String>[
      item.nom,
      if (item.race?.isNotEmpty == true) item.race!,
      if (item.prix != null) '${item.prix!.toInt()} €',
      if (item.ville?.isNotEmpty == true) '📍 ${item.ville!}',
      if (item.nomEleveur?.isNotEmpty == true) '🏡 ${item.nomEleveur!}',
    ];
    final text = '${parts.join(' · ')}\n\n$url';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(text: text, url: url, nom: item.nom),
    );
  }

  // ── Profil éleveur ──────────────────────────────────────────────────────────

  Future<void> _navigateToEleveurProfile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted || !doc.exists) return;
      final user = UserSelected.fromMap(doc.data()!, uid);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => UserDetailPageFeed(user: user)));
      }
    } catch (_) {}
  }

  // ── Chat ────────────────────────────────────────────────────────────────────

  Future<void> _openChat(_FeedItem item) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    if (item.uidEleveur == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Éleveur introuvable pour cette annonce.')));
      return;
    }
    if (me == item.uidEleveur) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous ne pouvez pas vous envoyer un message.')));
      return;
    }
    setState(() => _openingChat = true);
    try {
      final sorted       = [me, item.uidEleveur!]..sort();
      final participantIds = sorted.join('_');
      final snap = await FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', isEqualTo: participantIds)
          .limit(1).get();
      final profileTypes = <String, String>{
        item.uidEleveur!: 'eleveur',
        me: User_Info.catPro.isNotEmpty ? User_Info.catPro
            : (User_Info.isElevage ? 'eleveur' : 'particulier'),
      };
      DocumentReference ref;
      if (snap.docs.isEmpty) {
        ref = await FirebaseFirestore.instance.collection('conversations').add({
          'participants': [me, item.uidEleveur!],
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
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(conversationId: ref.id, eleveurId: item.uidEleveur!)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur messagerie : $e'), duration: const Duration(seconds: 4)));
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  void dispose() { _vertCtrl.dispose(); _raceCtrl.dispose(); _especeCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _feedStarted ? _buildFeed() : _buildFilters();

  Widget _buildFilters() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F0), elevation: 0,
        foregroundColor: const Color(0xFF1F2A2E),
        title: const Text('Fil d\'actualité',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Personnalise ton feed',
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF6F767B))),
          const SizedBox(height: 24),
          const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () async {
              final selected = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _FeedSpeciesPicker(
                    species: _especeList, current: _espece),
              );
              if (selected != null) {
                setState(() { _espece = selected; _race = null; _races = []; _especeCtrl.text = _especeList.firstWhere((e) => e.$1 == selected).$2; });
                _loadRaces(selected);
              }
            },
            child: AbsorbPointer(
              child: TextField(
                controller: _especeCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Toutes les espèces',
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF9CA3AF)),
                  prefixIcon: Center(
                    widthFactor: 1,
                    child: Text(
                      _especeList.firstWhere((e) => e.$1 == _espece, orElse: () => ('', '', '🐾')).$3,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  suffixIcon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF0C5C6C)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: _espece != 'tous' ? _teal : const Color(0xFFE5E7EB), width: 1.5)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
                ),
              ),
            ),
          ),
          if (_races.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Race', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final breeds = List<String>.from(_races);
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => _FeedBreedPicker(breeds: breeds, current: _race ?? ''),
                );
                if (selected != null) {
                  setState(() {
                    _race = selected.isEmpty ? null : selected;
                    _raceCtrl.text = selected;
                  });
                }
              },
              child: AbsorbPointer(
                child: TextField(
                  controller: _raceCtrl,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Toutes les races',
                    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF9CA3AF)),
                    prefixIcon: const Icon(Icons.pets_outlined, size: 18, color: Color(0xFF0C5C6C)),
                    suffixIcon: _race != null
                        ? GestureDetector(
                            onTap: () => setState(() { _race = null; _raceCtrl.clear(); }),
                            child: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
                          )
                        : const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF0C5C6C)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: _race != null ? _teal : const Color(0xFFE5E7EB), width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Type', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          Row(children: [
            for (final t in [('tous', 'Tous'), ('vente', '🐾 Compagnon'), ('saillie', '💜 Saillie')])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _typeVente = t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _typeVente == t.$1 ? const Color(0xFFE8F4F6) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _typeVente == t.$1 ? _teal : const Color(0xFFE5E7EB), width: 2),
                    ),
                    child: Text(t.$2, textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                            color: _typeVente == t.$1 ? _teal : const Color(0xFF6F767B))),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _loadFeed,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                disabledBackgroundColor: _teal.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Lancer le feed  →',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildFeed() {
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Aucune annonce avec photos',
              style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontSize: 16)),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() => _feedStarted = false),
            child: const Text('Modifier les filtres', style: TextStyle(color: Colors.white54)),
          ),
        ])),
      );
    }

    return Stack(children: [
      Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _vertCtrl,
          scrollDirection: Axis.vertical,
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final item = _items[i];
            final key  = '${item.annonceId}_${item.bebeIndex ?? 'null'}';
            return _FeedCard(
              item:        item,
              isLiked:     _likedKeys.contains(key),
              isFavorited: _favoriKeys.contains(key),
              likeCount:   _likeCounts[key] ?? 0,
              favoriCount: _favoriCounts[key] ?? 0,
              onLike:      () => _toggleLike(item),
              onFavorite:  () => _toggleFavori(item),
              onMessage:   () => _openChat(item),
              onEleveurTap: item.uidEleveur != null
                  ? () => _navigateToEleveurProfile(item.uidEleveur!)
                  : null,
              onShare: () => _shareItem(item),
              onBack:   () => setState(() => _feedStarted = false),
              onDetail: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnnonceDetailPage(
                      annonceId: item.annonceId,
                      initialData: {'_id': item.annonceId}))),
              onSimilar: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnnoncesPublicPage(
                      typeFilter: 'compagnon',
                      initialEspece: item.espece ?? 'tous',
                      initialRace: item.race))),
            );
          },
        ),
      ),
      if (_openingChat)
        Container(color: Colors.black54,
            child: const Center(child: CircularProgressIndicator(color: Colors.white))),
    ]);
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _FeedCard extends StatefulWidget {
  final _FeedItem item;
  final bool isLiked;
  final bool isFavorited;
  final int likeCount;
  final int favoriCount;
  final VoidCallback onLike;
  final VoidCallback onFavorite;
  final VoidCallback onMessage;
  final VoidCallback onShare;
  final VoidCallback onBack;
  final VoidCallback onDetail;
  final VoidCallback onSimilar;
  final VoidCallback? onEleveurTap;

  const _FeedCard({
    required this.item,
    required this.isLiked, required this.isFavorited,
    required this.likeCount, required this.favoriCount,
    required this.onLike, required this.onFavorite,
    required this.onMessage, required this.onShare,
    required this.onBack, required this.onDetail,
    required this.onSimilar,
    this.onEleveurTap,
  });

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> with SingleTickerProviderStateMixin {
  final _horizCtrl   = PageController();
  int  _photoIndex   = 0;
  bool _descExpanded = false;

  late final AnimationController _likeAnim;
  late final Animation<double>   _likeScale;

  @override
  void initState() {
    super.initState();
    _likeAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _likeScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _likeAnim, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_FeedCard old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) setState(() { _descExpanded = false; _photoIndex = 0; });
  }

  @override
  void dispose() { _horizCtrl.dispose(); _likeAnim.dispose(); super.dispose(); }

  String _especeLabel(String e) {
    const map = {
      'chien': '🐕 Chien', 'chat': '🐈 Chat', 'cheval': '🐴 Cheval',
      'ane': '🫏 Âne', 'lapin': '🐇 Lapin', 'oiseau': '🦜 Oiseau',
      'nac': '🦎 NAC', 'ovin': '🐑 Ovin', 'caprin': '🐐 Caprin',
      'porcin': '🐷 Porcin', 'autre': '🐾 Autre',
    };
    return map[e] ?? '🐾 ${e[0].toUpperCase()}${e.substring(1)}';
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.redAccent),
            title: const Text('Signaler cette annonce',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500)),
            onTap: () { Navigator.pop(context); /* TODO: signalement */ },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.grey),
            title: const Text('Masquer cet élevage',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500)),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showFullDescription(BuildContext ctx, _FeedItem item) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.25,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: ListView(controller: scrollCtrl, padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
                Text(item.nom,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800,
                        fontSize: 20, color: Colors.white)),
                const SizedBox(height: 12),
                Text(item.description!,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 15,
                        color: Colors.white70, height: 1.55)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item   = widget.item;
    final photos = item.photos;
    final safe   = MediaQuery.of(context).padding;

    return LayoutBuilder(builder: (_, constraints) {
      final h = constraints.maxHeight;
      final w = constraints.maxWidth;
      // Header : safe area + padding(8) + row(42) + padding bas(12) = safe+62
      final headerH = safe.top + 48.0;
      // Photo 4:5 sous le header, max 70% de la hauteur disponible
      final photoH = (w * 1.25).clamp(200.0, h * 0.70);
      final bottomCardH = (h * 0.30).clamp(190.0, 270.0);
      // Boutons à 28% dans la zone photo
      final btnTop = headerH + photoH * 0.28;

    return Stack(children: [

      // ── 1. Fond flouté plein écran ────────────────────────────────────────
      Positioned.fill(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: CachedNetworkImage(
            imageUrl: thumbUrl(photos[_photoIndex], width: 300, quality: 30),
            fit: BoxFit.cover,
            width: double.infinity, height: double.infinity,
            placeholder: (_, __) => Container(color: Colors.black),
          ),
        ),
      ),
      Positioned.fill(child: IgnorePointer(
          child: Container(color: Colors.black.withValues(alpha: 0.40)))),

      // ── 2. Image principale 4:5, sous le header, BoxFit.contain ──────────
      Positioned(
        top: headerH, left: 0, right: 0, height: photoH,
        child: PageView.builder(
          controller: _horizCtrl,
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _photoIndex = i),
          itemBuilder: (_, pi) => CachedNetworkImage(
            imageUrl: thumbUrl(photos[pi], width: 900, quality: 90, resize: 'contain'),
            fit: BoxFit.contain,
            width: double.infinity, height: double.infinity,
            errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.pets, color: Colors.white24, size: 80)),
          ),
        ),
      ),

      // ── 3. Gradient haut ──────────────────────────────────────────────────
      Positioned(top: 0, left: 0, right: 0,
        child: IgnorePointer(child: Container(
          height: 180,
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          )),
        )),
      ),

      // ── 4. Gradient bas ───────────────────────────────────────────────────
      Positioned(bottom: 0, left: 0, right: 0,
        child: IgnorePointer(child: Container(
          height: bottomCardH + 80,
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Color(0xDD000000), Colors.transparent],
          )),
        )),
      ),

      // ── 5. Header overlay (fond sombre distinct) ──────────────────────────
      Positioned(top: 0, left: 0, right: 0,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10, safe.top + 8, 10, 12),
            child: Row(children: [
              _CircleBtn(icon: Icons.close, onTap: widget.onBack),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: widget.onEleveurTap,
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: ClipOval(child: item.photoEleveur?.isNotEmpty == true
                      ? CachedNetworkImage(imageUrl: item.photoEleveur!, fit: BoxFit.cover)
                      : Container(color: const Color(0xFF0C5C6C),
                          child: const Icon(Icons.store_outlined, color: Colors.white, size: 18))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onEleveurTap,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.nomEleveur ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 15, color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                    Text(item.nom,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w500,
                        fontSize: 13, color: Colors.white70,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                  ]),
                ),
              ),
              _CircleBtn(icon: Icons.more_vert, onTap: () => _showOptionsMenu(context)),
            ]),
          ),
        ]),
        ),
      ),

      // ── 5b. Dots carrousel (haut de la photo, ronds centrés) ────────────
      if (photos.length > 1)
        Positioned(
          top: headerH + 10,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: photos.asMap().entries.map((e) {
              final active = e.key == _photoIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width:  active ? 9.0 : 7.0,
                height: active ? 9.0 : 7.0,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.40),
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                ),
              );
            }).toList(),
          ),
        ),

      // ── 6. Boutons actions (droite, centré vertical) ──────────────────────
      Positioned(
        right: 12,
        top: btnTop,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _likeScale,
            child: _ActionIcon(
              icon: widget.isLiked ? Icons.favorite : Icons.favorite_border,
              color: widget.isLiked ? Colors.redAccent : Colors.white,
              label: 'J\'aime', size: 46, count: widget.likeCount,
              onTap: () { widget.onLike(); _likeAnim.forward(from: 0); },
            ),
          ),
          const SizedBox(height: 18),
          _ActionIcon(
            icon: widget.isFavorited ? Icons.bookmark : Icons.bookmark_border,
            color: widget.isFavorited ? Colors.amber : Colors.white,
            label: 'Sauvegarder', size: 46, count: widget.favoriCount,
            onTap: widget.onFavorite,
          ),
          const SizedBox(height: 18),
          _ActionIcon(icon: Icons.mail_outline_rounded, color: Colors.white,
              label: 'Message', size: 46, onTap: widget.onMessage),
          const SizedBox(height: 18),
          _ActionIcon(icon: Icons.share_outlined, color: Colors.white,
              label: 'Partager', size: 46, onTap: widget.onShare),
        ]),
      ),

      // ── 7. Overlay infos bas (glassmorphism) ──────────────────────────────
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 18, 20, safe.bottom + 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12), width: 0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne 1 : Nom + sexe + prix
                  Row(children: [
                    if (item.sexe != null) ...[
                      Text(item.sexe == 'male' ? '♂' : '♀',
                          style: const TextStyle(color: Colors.white70, fontSize: 18)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: Text(item.nom,
                      style: const TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w800,
                        fontSize: 21, color: Colors.white),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (item.prix != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C5C6C).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${item.prix!.toInt()} €',
                          style: const TextStyle(
                            fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 14, color: Colors.white)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  // Ligne 2 : Badges
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    VerificationBadge(
                      level: item.eleveurPremium
                          ? VerificationLevel.premium
                          : item.eleveurVerifie
                              ? VerificationLevel.verifie
                              : VerificationLevel.none,
                      fontSize: 10,
                    ),
                    if (item.typeVente == 'saillie')
                      _FeedBadge(
                        label: '💜 Saillie',
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.80)),
                    if (item.typeVente == 'retraite')
                      _FeedBadge(
                        label: '🏅 Retraité',
                        color: const Color(0xFFB45309).withValues(alpha: 0.80)),
                    if (item.espece?.isNotEmpty == true)
                      _FeedBadge(
                        label: _especeLabel(item.espece!),
                        color: Colors.white.withValues(alpha: 0.16)),
                    if (item.race?.isNotEmpty == true)
                      _FeedBadge(
                        label: item.race!,
                        color: Colors.white.withValues(alpha: 0.10)),
                    _FeedBadge(
                      label: _pedigreeLabel(item.espece, item.pedigree),
                      color: item.pedigree
                          ? const Color(0xFF0C5C6C).withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.10),
                    ),
                    if (_ageLabel(item.dateNaissance) != null)
                      _FeedBadge(
                        label: '🎂 ${_ageLabel(item.dateNaissance)!}',
                        color: Colors.white.withValues(alpha: 0.13)),
                  ]),
                  // Ligne 3 : Ville
                  if (item.ville?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white54, size: 13),
                      const SizedBox(width: 4),
                      Text(item.ville!,
                          style: const TextStyle(
                              fontFamily: 'Galey', fontSize: 13, color: Colors.white54)),
                    ]),
                  ],
                  // Ligne 4 : Description (tap pour tout voir)
                  if (item.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _showFullDescription(context, item),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(child: Text(item.description!,
                          style: const TextStyle(
                              fontFamily: 'Galey', fontSize: 13, color: Colors.white70),
                          maxLines: _descExpanded ? 8 : 2,
                          overflow: _descExpanded ? TextOverflow.visible : TextOverflow.ellipsis)),
                        if (!_descExpanded) ...[
                          const SizedBox(width: 4),
                          const Text('voir +',
                            style: TextStyle(
                                fontFamily: 'Galey', fontSize: 12,
                                color: Colors.white54, fontWeight: FontWeight.w600)),
                        ],
                      ]),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Boutons action
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onDetail,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C5C6C),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Center(child: Text('Voir l\'annonce',
                            style: TextStyle(
                              fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 14, color: Colors.white))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onSimilar,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: const Center(child: Text('Animaux similaires',
                            style: TextStyle(
                              fontFamily: 'Galey', fontWeight: FontWeight.w600,
                              fontSize: 13, color: Colors.white))),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),

    ]); // Stack
    }); // LayoutBuilder
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final double size;
  final int? count;
  const _ActionIcon({required this.icon, required this.color, required this.label, required this.onTap, this.size = 44, this.count});

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Icon(icon, color: color, size: size * 0.55),
      ),
      if (count != null && count! > 0) ...[
        const SizedBox(height: 3),
        Text(
          _fmt(count!),
          style: const TextStyle(
            color: Colors.white, fontSize: 11, fontFamily: 'Galey',
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ],
    ]),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
  );
}

class _FeedBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _FeedBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    ),
    child: Text(label,
      style: const TextStyle(
        fontFamily: 'Galey', fontSize: 12,
        fontWeight: FontWeight.w600, color: Colors.white)),
  );
}

// ─── Share sheet ──────────────────────────────────────────────────────────────

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
    final encoded = Uri.encodeComponent(text);
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
          _ShareBtn(
            icon: const Icon(Icons.link_rounded, color: Colors.white, size: 24),
            bg: const Color(0xFF3A3A4E),
            label: 'Copier le lien',
            onTap: () => _copy(context),
          ),
          _ShareBtn(
            icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 24),
            bg: const Color(0xFF25D366),
            label: 'WhatsApp',
            onTap: () => _launch(context, waUrl),
          ),
          _ShareBtn(
            icon: const Icon(Icons.sms_outlined, color: Colors.white, size: 24),
            bg: const Color(0xFF4A90E2),
            label: 'SMS',
            onTap: () => _launch(context, smsUrl),
          ),
          _ShareBtn(
            icon: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 24),
            bg: const Color(0xFFEA4335),
            label: 'Email',
            onTap: () => _launch(context, emailUrl),
          ),
        ]),
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

// ─── Sélecteur d'espèce (feed) ───────────────────────────────────────────────

class _FeedSpeciesPicker extends StatefulWidget {
  final List<(String, String, String)> species;
  final String current;
  const _FeedSpeciesPicker({required this.species, required this.current});
  @override State<_FeedSpeciesPicker> createState() => _FeedSpeciesPickerState();
}

class _FeedSpeciesPickerState extends State<_FeedSpeciesPicker> {
  late List<(String, String, String)> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _filtered = widget.species; }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _filter(String q) => setState(() {
    _filtered = q.isEmpty
        ? widget.species
        : widget.species.where((e) => e.$2.toLowerCase().contains(q.toLowerCase())).toList();
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Expanded(child: Text('Choisir une espèce',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17))),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Rechercher une espèce...',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final e = _filtered[i];
                final selected = e.$1 == widget.current;
                return ListTile(
                  leading: Text(e.$3, style: const TextStyle(fontSize: 22)),
                  title: Text(e.$2, style: TextStyle(
                      fontFamily: 'Galey', fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      color: selected ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  trailing: selected ? const Icon(Icons.check, color: Color(0xFF0C5C6C), size: 18) : null,
                  onTap: () => Navigator.pop(context, e.$1),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Sélecteur de race (feed) ─────────────────────────────────────────────────

class _FeedBreedPicker extends StatefulWidget {
  final List<String> breeds;
  final String current;
  const _FeedBreedPicker({required this.breeds, required this.current});
  @override State<_FeedBreedPicker> createState() => _FeedBreedPickerState();
}

class _FeedBreedPickerState extends State<_FeedBreedPicker> {
  late List<String> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _filtered = widget.breeds; }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _filter(String q) => setState(() {
    _filtered = q.isEmpty
        ? widget.breeds
        : widget.breeds.where((b) => b.toLowerCase().contains(q.toLowerCase())).toList();
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Expanded(child: Text('Choisir une race',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17))),
              if (widget.current.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Effacer', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C))),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher une race...',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final b = _filtered[i];
                final selected = b == widget.current;
                return ListTile(
                  dense: true,
                  title: Text(b, style: TextStyle(
                      fontFamily: 'Galey', fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      color: selected ? const Color(0xFF0C5C6C) : const Color(0xFF1F2A2E))),
                  trailing: selected ? const Icon(Icons.check, color: Color(0xFF0C5C6C), size: 18) : null,
                  onTap: () => Navigator.pop(context, b),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

