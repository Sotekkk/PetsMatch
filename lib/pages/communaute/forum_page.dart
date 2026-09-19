import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/particulier/social_feed_page.dart'
    show SocialProfilePage, resolveActiveAuthorProfileId, socialProfileName,
         socialProfileTypeLabel, socialProfilePhoto, kSocialAuthorCols;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/widgets/inline_video.dart';

const _tealC = Color(0xFF00ACC1);
const int _kMaxVideoBytes = 50 * 1024 * 1024; // 50 Mo, même limite que le journal pension

// ── Photo / vidéo jointe à un sujet ou une réponse ─────────────────────────────
// Un seul média par publication (comme le journal pension) : photo OU vidéo.

Future<File?> _pickForumPhoto() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
  return file == null ? null : File(file.path);
}

Future<File?> _pickForumVideo(BuildContext context) async {
  final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
  if (file == null) return null;
  final size = await File(file.path).length();
  if (size > _kMaxVideoBytes) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vidéo trop lourde (max 50 Mo).', style: TextStyle(fontFamily: 'Galey'))));
    }
    return null;
  }
  return File(file.path);
}

Future<({String? photoUrl, String? videoUrl})> _uploadForumMedia(
    String uid, File? photo, File? video) async {
  String? photoUrl;
  String? videoUrl;
  if (photo != null) {
    final path = 'forum_media/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    photoUrl = await storage.uploadPhoto(photo, path, quality: 80);
  }
  if (video != null) {
    final ext = video.path.split('.').last.toLowerCase();
    final path = 'forum_media/${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    videoUrl = await storage.uploadRawFile(video, path);
  }
  return (photoUrl: photoUrl, videoUrl: videoUrl);
}

/// Aperçu média joint (photo ou vidéo) affiché sous un sujet/une réponse.
Widget _forumMedia(Map<String, dynamic> row) {
  final photoUrl = row['photo_url']?.toString();
  final videoUrl = row['video_url']?.toString();
  if (videoUrl != null && videoUrl.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: InlineVideo(url: videoUrl, placeholderHeight: 200),
    );
  }
  if (photoUrl != null && photoUrl.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
        placeholder: (_, __) => Container(height: 200, color: const Color(0xFFF0F0F0)),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
  return const SizedBox.shrink();
}

/// Bouton photo + bouton vidéo + aperçu, pour les formulaires de création
/// (sujet / réponse). [onChanged] reçoit (photo, video) à chaque sélection
/// ou suppression.
class _MediaPickerRow extends StatelessWidget {
  final File? photo;
  final File? video;
  final void Function(File? photo, File? video) onChanged;
  const _MediaPickerRow({required this.photo, required this.video, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (photo != null || video != null) {
      return Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: photo != null
              ? Image.file(photo!, width: double.infinity, height: 160, fit: BoxFit.cover)
              : Container(
                  width: double.infinity, height: 160, color: Colors.black87,
                  child: const Center(child: Icon(Icons.videocam, color: Colors.white, size: 40)),
                ),
        ),
        Positioned(
          top: 6, right: 6,
          child: GestureDetector(
            onTap: () => onChanged(null, null),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ]);
    }
    return Row(children: [
      IconButton(
        onPressed: () async {
          final f = await _pickForumPhoto();
          if (f != null) onChanged(f, null);
        },
        icon: const Icon(Icons.image_outlined, color: _tealC),
        tooltip: 'Ajouter une photo',
      ),
      IconButton(
        onPressed: () async {
          final f = await _pickForumVideo(context);
          if (f != null) onChanged(null, f);
        },
        icon: const Icon(Icons.videocam_outlined, color: _tealC),
        tooltip: 'Ajouter une vidéo',
      ),
    ]);
  }
}

// ── Identité auteur (avatar/nom/badge) — même logique que Pets Social ─────────

/// Clé d'identité d'une ligne forum : `auteur_profile_id` si connu, sinon
/// repli `u:<uid>` (lignes créées avant la migration).
String _authorKey(Map<String, dynamic> row) {
  final pid = row['auteur_profile_id']?.toString();
  if (pid != null && pid.isNotEmpty) return pid;
  return 'u:${row['auteur_uid']}';
}

/// Résout en un batch l'identité Pets Social (avatar/nom/type) des auteurs
/// d'une liste de sujets/réponses. Même stratégie que `_resolveAuthors` côté
/// Pets Social : par profil quand connu, repli sur le profil particulier
/// principal de l'uid pour les lignes historiques.
Future<Map<String, Map<String, dynamic>>> _resolveForumAuthors(List<Map<String, dynamic>> rows) async {
  final supa = Supabase.instance.client;
  final out = <String, Map<String, dynamic>>{};

  final profIds = rows
      .map((r) => r['auteur_profile_id']?.toString())
      .where((id) => id != null && id.isNotEmpty)
      .cast<String>()
      .toSet()
      .toList();
  if (profIds.isNotEmpty) {
    final byId = await supa.from('user_profiles').select(kSocialAuthorCols).inFilter('id', profIds);
    for (final r in byId as List) {
      out[r['id'] as String] = Map<String, dynamic>.from(r as Map);
    }
  }

  final legacyUids = rows
      .where((r) => (r['auteur_profile_id']?.toString().isNotEmpty ?? false) != true)
      .map((r) => r['auteur_uid']?.toString())
      .where((u) => u != null && u.isNotEmpty)
      .cast<String>()
      .toSet()
      .toList();
  if (legacyUids.isNotEmpty) {
    // Repli sur le profil particulier de l'uid — SANS filtrer is_main : un
    // compte peut très bien avoir un profil pro/éleveur comme principal
    // (ex. Natacha, is_main = éleveur) et un profil particulier secondaire ;
    // filtrer is_main affichait alors "Membre" à la place de son vrai nom.
    // Même logique que _resolveAuthors côté Pets Social.
    final byUid = await supa.from('user_profiles').select(kSocialAuthorCols)
        .inFilter('uid', legacyUids).eq('profile_type', 'particulier');
    for (final r in byUid as List) {
      out.putIfAbsent('u:${r['uid']}', () => Map<String, dynamic>.from(r as Map));
    }
  }
  return out;
}

/// Ligne cliquable avatar + nom + badge pro, ouvrant le profil Pets Social
/// de l'auteur (avec son statut suivi/ami visible depuis là-bas).
class _AuthorRow extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final String fallbackUid;
  final double avatarSize;
  final TextStyle? nameStyle;
  const _AuthorRow({required this.profile, required this.fallbackUid, this.avatarSize = 22, this.nameStyle});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final targetUid = profile?['uid']?.toString() ?? fallbackUid;
    final name = socialProfileName(profile);
    final photo = socialProfilePhoto(profile);
    final badge = socialProfileTypeLabel(profile?['profile_type']?.toString());

    return GestureDetector(
      onTap: targetUid.isEmpty ? null : () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SocialProfilePage(
          targetUid: targetUid,
          myUid: myUid,
          targetProfileId: profile?['id']?.toString(),
        )),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: avatarSize / 2,
          backgroundColor: const Color(0xFFE0F2F1),
          backgroundImage: (photo != null && photo.isNotEmpty) ? CachedNetworkImageProvider(photo) : null,
          child: (photo == null || photo.isEmpty) ? Icon(Icons.person, size: avatarSize * 0.55, color: _tealC) : null,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name,
                style: nameStyle ?? const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E2025)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (badge != null)
              Text(badge, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
          ]),
        ),
      ]),
    );
  }
}

// ── Couleurs par type d'animal (alignées sur animaux_perdus_page) ─────────────

const _kAnimalTypes = [
  ('Chien',  'chien'),
  ('Chat',   'chat'),
  ('Lapin',  'lapin'),
  ('Oiseau', 'oiseau'),
  ('NAC',    'nac'),
  ('Cheval', 'cheval'),
  ('Ovin',   'ovin'),
  ('Caprin', 'caprin'),
  ('Porc',   'porcin'),
  ('Autre',  'autre'),
];

Color _animalColor(String? type) {
  switch (type) {
    case 'chien':  return const Color(0xFFEA580C);
    case 'chat':   return const Color(0xFF9333EA);
    case 'lapin':  return const Color(0xFFDB2777);
    case 'oiseau': return const Color(0xFF0891B2);
    case 'nac':    return const Color(0xFF7C3AED);
    case 'cheval': return const Color(0xFF16A34A);
    case 'ovin':   return const Color(0xFFD97706);
    case 'caprin': return const Color(0xFF65A30D);
    case 'porcin': return const Color(0xFFE11D48);
    default:       return const Color(0xFF6B7280);
  }
}

// ── Catégories forum ──────────────────────────────────────────────────────────

const _kAllCategories = [
  _CatInfo('Santé',        Icons.local_hospital_outlined,  'sante',       Color(0xFF0EA5E9)),
  _CatInfo('Alimentation', Icons.restaurant_outlined,      'alimentation', Color(0xFFF59E0B)),
  _CatInfo('Éducation',    Icons.school_outlined,          'education',   Color(0xFF8B5CF6)),
  _CatInfo('Élevage',      Icons.cruelty_free_outlined,    'elevage',     Color(0xFF22C55E)),
  _CatInfo('Bien-être',    Icons.spa_outlined,             'bien_etre',   Color(0xFFEC4899)),
  _CatInfo('Général',      Icons.forum_outlined,           'general',     Color(0xFF6B7280)),
];

/// "Élevage" n'a rien à faire dans le forum du profil particulier —
/// réservé aux profils éleveur/pro/association.
List<_CatInfo> get _kCategories {
  final isParticulier = !User_Info.isPro && !User_Info.isElevage && !User_Info.isAssociation;
  if (!isParticulier) return _kAllCategories;
  return _kAllCategories.where((c) => c.slug != 'elevage').toList();
}

class _CatInfo {
  final String label;
  final IconData icon;
  final String slug;
  final Color color;
  const _CatInfo(this.label, this.icon, this.slug, this.color);
}

// ─────────────────────────────────────────────────────────────────────────────
// Page principale — liste des catégories
// ─────────────────────────────────────────────────────────────────────────────

class ForumPage extends StatelessWidget {
  const ForumPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Forum communauté',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        itemCount: _kCategories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final cat = _kCategories[i];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => _ForumCategorieePage(cat: cat)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(cat.icon, color: cat.color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(cat.label,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFF1E2025))),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: Colors.grey.shade400),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page catégorie — liste des sujets
// ─────────────────────────────────────────────────────────────────────────────

class _ForumCategorieePage extends StatefulWidget {
  final _CatInfo cat;
  const _ForumCategorieePage({required this.cat});

  @override
  State<_ForumCategorieePage> createState() => _ForumCategorieePageState();
}

class _ForumCategorieePageState extends State<_ForumCategorieePage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _sujets = [];
  Map<String, Map<String, dynamic>> _authors = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('forum_sujets')
          .select()
          .eq('categorie_slug', widget.cat.slug)
          .order('epingle', ascending: false)
          .order('created_at', ascending: false);
      final sujets = List<Map<String, dynamic>>.from(data);
      final authors = await _resolveForumAuthors(sujets);
      if (mounted) {
        setState(() {
          _sujets = sujets;
          _authors = authors;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreerSujetSheet(categorieSlug: widget.cat.slug),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: widget.cat.color,
        title: Text(widget.cat.label,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _uid.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: widget.cat.color,
              onPressed: _openCreation,
              child: const Icon(Icons.edit_outlined, color: Colors.white),
            )
          : null,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: widget.cat.color))
          : _sujets.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: widget.cat.color,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _sujets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _SujetTile(
                      sujet: _sujets[i],
                      author: _authors[_authorKey(_sujets[i])],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => _ForumSujetPage(sujet: _sujets[i])),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _empty() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined, size: 72, color: Color(0xFFCCCCCC)),
          SizedBox(height: 16),
          Text('Aucun sujet pour l\'instant',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFFAAAAAA))),
          SizedBox(height: 8),
          Text('Lancez la discussion !',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
}

// ─── Tile sujet ───────────────────────────────────────────────────────────────

class _SujetTile extends StatelessWidget {
  final Map<String, dynamic> sujet;
  final Map<String, dynamic>? author;
  final VoidCallback onTap;

  const _SujetTile({required this.sujet, required this.author, required this.onTap});

  static String _fmtDate(String iso) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final titre = sujet['titre']?.toString() ?? '';
    final contenu = sujet['contenu']?.toString() ?? '';
    final createdAt = sujet['created_at']?.toString() ?? '';
    final epingle = sujet['epingle'] == true;
    final animalType = sujet['animal_type']?.toString() ?? '';
    final animalColor = _animalColor(animalType.isEmpty ? null : animalType);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 1))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: animalColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _AuthorRow(profile: author, fallbackUid: sujet['auteur_uid']?.toString() ?? '', avatarSize: 20),
                    const SizedBox(height: 8),
                    Row(children: [
                      if (epingle) ...[
                        Icon(Icons.push_pin, size: 13, color: animalColor),
                        const SizedBox(width: 4),
                      ],
                      if ((sujet['video_url']?.toString().isNotEmpty ?? false)) ...[
                        Icon(Icons.videocam, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                      ] else if ((sujet['photo_url']?.toString().isNotEmpty ?? false)) ...[
                        Icon(Icons.image, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(titre,
                            style: const TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF1E2025))),
                      ),
                      Text(_fmtDate(createdAt),
                          style: const TextStyle(
                              fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                    ]),
                    if (contenu.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(contenu,
                          style: const TextStyle(
                              fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (animalType.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: animalColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          animalType[0].toUpperCase() + animalType.substring(1),
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: animalColor),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page sujet — réponses
// ─────────────────────────────────────────────────────────────────────────────

class _ForumSujetPage extends StatefulWidget {
  final Map<String, dynamic> sujet;
  const _ForumSujetPage({required this.sujet});

  @override
  State<_ForumSujetPage> createState() => _ForumSujetPageState();
}

class _ForumSujetPageState extends State<_ForumSujetPage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _reponses = [];
  Map<String, Map<String, dynamic>> _authors = {};
  bool _loading = true;
  String _newReponse = '';
  File? _replyPhoto;
  File? _replyVideo;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadReponses();
  }

  Future<void> _loadReponses() async {
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('forum_reponses')
          .select()
          .eq('sujet_id', widget.sujet['id'])
          .order('created_at');
      final reponses = List<Map<String, dynamic>>.from(data);
      final authors = await _resolveForumAuthors([widget.sujet, ...reponses]);
      if (mounted) {
        setState(() {
          _reponses = reponses;
          _authors = authors;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _envoyer() async {
    final texte = _newReponse.trim();
    if (texte.isEmpty && _replyPhoto == null && _replyVideo == null) return;
    if (_uid.isEmpty) return;
    setState(() => _sending = true);
    try {
      final pid = await resolveActiveAuthorProfileId(_uid);
      final media = await _uploadForumMedia(_uid, _replyPhoto, _replyVideo);
      final inserted = await _supa.from('forum_reponses').insert({
        'sujet_id': widget.sujet['id'],
        'auteur_uid': _uid,
        if (pid != null) 'auteur_profile_id': pid,
        'contenu': texte,
        'created_at': DateTime.now().toIso8601String(),
        if (media.photoUrl != null) 'photo_url': media.photoUrl,
        if (media.videoUrl != null) 'video_url': media.videoUrl,
      }).select().single();
      final row = Map<String, dynamic>.from(inserted);
      if (!_authors.containsKey(_authorKey(row))) {
        final resolved = await _resolveForumAuthors([row]);
        _authors.addAll(resolved);
      }
      if (mounted) {
        setState(() {
          _reponses.add(row);
          _newReponse = '';
          _replyPhoto = null;
          _replyVideo = null;
          _sending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titre = widget.sujet['titre']?.toString() ?? '';
    final contenu = widget.sujet['contenu']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _tealC,
        title: Text(titre,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: _reponses.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _tealC.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _tealC.withValues(alpha: 0.2)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _AuthorRow(
                            profile: _authors[_authorKey(widget.sujet)],
                            fallbackUid: widget.sujet['auteur_uid']?.toString() ?? '',
                            avatarSize: 26,
                          ),
                          const SizedBox(height: 10),
                          Text(contenu,
                              style: const TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 14,
                                  color: Color(0xFF1E2025))),
                          if ((widget.sujet['photo_url']?.toString().isNotEmpty ?? false) ||
                              (widget.sujet['video_url']?.toString().isNotEmpty ?? false)) ...[
                            const SizedBox(height: 10),
                            _forumMedia(widget.sujet),
                          ],
                        ]),
                      );
                    }
                    final r = _reponses[i - 1];
                    return _ReponseCard(reponse: r, author: _authors[_authorKey(r)]);
                  },
                ),
        ),
        if (_uid.isNotEmpty)
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_replyPhoto != null || _replyVideo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _replyPhoto != null
                          ? Image.file(_replyPhoto!, width: 90, height: 90, fit: BoxFit.cover)
                          : Container(width: 90, height: 90, color: Colors.black87,
                              child: const Icon(Icons.videocam, color: Colors.white)),
                    ),
                    Positioned(
                      top: 2, right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() { _replyPhoto = null; _replyVideo = null; }),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                ),
              Row(children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.add_circle_outline, color: _tealC),
                tooltip: 'Joindre un média',
                onSelected: (val) async {
                  if (val == 'photo') {
                    final f = await _pickForumPhoto();
                    if (f != null) setState(() { _replyPhoto = f; _replyVideo = null; });
                  } else if (val == 'video') {
                    final f = await _pickForumVideo(context);
                    if (f != null) setState(() { _replyVideo = f; _replyPhoto = null; });
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'photo', child: Text('Photo', style: TextStyle(fontFamily: 'Galey'))),
                  PopupMenuItem(value: 'video', child: Text('Vidéo', style: TextStyle(fontFamily: 'Galey'))),
                ],
              ),
              Expanded(
                child: TextFormField(
                  initialValue: _newReponse,
                  decoration: InputDecoration(
                    hintText: 'Votre réponse…',
                    hintStyle:
                        const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: _tealC, width: 1.5)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                  ),
                  maxLines: null,
                  onChanged: (v) => _newReponse = v,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : _envoyer,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      color: _tealC, shape: BoxShape.circle),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
              ]),
            ]),
          ),
      ]),
    );
  }
}

// ─── Réponse card ─────────────────────────────────────────────────────────────

class _ReponseCard extends StatelessWidget {
  final Map<String, dynamic> reponse;
  final Map<String, dynamic>? author;
  const _ReponseCard({required this.reponse, required this.author});

  static String _fmtDate(String iso) {
    try {
      return DateFormat('dd/MM · HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final contenu = reponse['contenu']?.toString() ?? '';
    final auteur = reponse['auteur_uid']?.toString() ?? '';
    final date = reponse['created_at']?.toString() ?? '';
    final isMe = auteur == (FirebaseAuth.instance.currentUser?.uid ?? '');

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFE0F7FA) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!isMe) ...[
            _AuthorRow(profile: author, fallbackUid: auteur, avatarSize: 20,
                nameStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF1E2025))),
            const SizedBox(height: 6),
          ],
          if (contenu.isNotEmpty)
            Text(contenu,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1E2025))),
          if ((reponse['photo_url']?.toString().isNotEmpty ?? false) ||
              (reponse['video_url']?.toString().isNotEmpty ?? false)) ...[
            if (contenu.isNotEmpty) const SizedBox(height: 8),
            SizedBox(width: 220, child: _forumMedia(reponse)),
          ],
          const SizedBox(height: 4),
          Text(_fmtDate(date),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }
}

// ─── Sheet créer sujet ────────────────────────────────────────────────────────

class _CreerSujetSheet extends StatefulWidget {
  final String categorieSlug;
  const _CreerSujetSheet({required this.categorieSlug});

  @override
  State<_CreerSujetSheet> createState() => _CreerSujetSheetState();
}

class _CreerSujetSheetState extends State<_CreerSujetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _titre = '';
  String _contenu = '';
  String? _animalType;
  File? _photo;
  File? _video;
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      final pid = await resolveActiveAuthorProfileId(_uid);
      final media = await _uploadForumMedia(_uid, _photo, _video);
      await _supa.from('forum_sujets').insert({
        'categorie_slug': widget.categorieSlug,
        'auteur_uid': _uid,
        if (pid != null) 'auteur_profile_id': pid,
        'titre': _titre,
        'contenu': _contenu,
        'created_at': DateTime.now().toIso8601String(),
        if (_animalType != null) 'animal_type': _animalType,
        if (media.photoUrl != null) 'photo_url': media.photoUrl,
        if (media.videoUrl != null) 'video_url': media.videoUrl,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(
                      child: Text('Nouveau sujet',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 18))),
                  IconButton(
                      icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ]),
                const SizedBox(height: 20),

                _lbl('Animal concerné'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kAnimalTypes.map((t) {
                    final sel = _animalType == t.$2;
                    final color = _animalColor(t.$2);
                    return GestureDetector(
                      onTap: () => setState(() => _animalType = sel ? null : t.$2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? color : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: sel ? color : Colors.grey.shade300),
                        ),
                        child: Text(t.$1,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : Colors.grey.shade700)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                _lbl('Titre *'),
                TextFormField(
                  decoration: _dec('Titre de votre question ou discussion'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _titre = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Contenu *'),
                TextFormField(
                  decoration: _dec('Décrivez votre sujet en détail…'),
                  maxLines: 5,
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _contenu = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _MediaPickerRow(
                  photo: _photo,
                  video: _video,
                  onChanged: (p, v) => setState(() { _photo = p; _video = v; }),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: _tealC,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Publier',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF6F767B))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _tealC, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}
