import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:PetsMatch/pages/particulier/abonnements_achats_page.dart' show CreditPacksSheet;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ⚠️  MULTI-PROFIL — NOTE POUR NABIL (et tout dev sur Pets Social)
//
// Un compte (uid) a PLUSIEURS profils (`user_profiles` : particulier, éleveur,
// pro, association…). Dans Pets Social, l'identité = le **profil ACTIF** de
// l'utilisateur (`User_Info.activeProfileId` / `activeType`), PAS son uid ni
// « le profil particulier » ni `is_main`.
//
// Règles :
//  • Écriture (post / commentaire / like / follow / repost / favori) → toujours
//    `author_profile_id` = `_activeAuthorProfileId(uid)` (premium requis pour un
//    profil non-particulier, sinon repli particulier).
//  • Lecture : résoudre l'auteur par `author_profile_id` (clé `_authorKey`),
//    JAMAIS par `uid` seul — deux profils d'un même uid se confondraient
//    (ex. « Angelique » particulier vs « Pomsky de la Luna » éleveur).
//  • « Mon profil / mes posts / mes abonnés / notifs / favoris » = scopés au
//    profil actif (`_myProfileId`), pas à l'uid.
//  • Favoris : `post_favorites.author_profile_id`.
//  • Cosmétiques : `owned` reste global (acheté une fois) mais l'équipé est par
//    profil → `user_cosmetics.active_by_profile` = { "<profile_id>": "<id>" }
//    (repli `active_value` = profil principal / lignes anciennes).
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Palette ──────────────────────────────────────────────────────────────────

const _tealC  = Color(0xFF0C5C6C);
const _darkC  = Color(0xFF0D1F22);
const _green  = Color(0xFF6E9E57);
const _greyC  = Color(0xFF5A6473);


// Fond — dégradé teal profond du haut vers le bas
const _bgGrad = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
  stops: [0.0, 0.5, 1.0],
);

// Ring avatar
const _ringGrad = LinearGradient(
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
  colors: [Color(0xFF6E9E57), Color(0xFF0C5C6C), Color(0xFF0A3F4A)],
);

// ─── Cosmétiques ───────────────────────────────────────────────────────────
const _cosmeticRings = <String, LinearGradient>{
  'ring_gold':    LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFFFD700), Color(0xFFFF9500), Color(0xFFFF6B00)]),
  'ring_rose':    LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFFF6B9D), Color(0xFFFF4081), Color(0xFF9B59B6)]),
  'ring_fire':    LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFFF4500), Color(0xFFFF6B00), Color(0xFFFFAA00)]),
  'ring_arctic':  LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF90E0EF), Color(0xFF48CAE4), Color(0xFF00B4DB)]),
  'ring_galaxy':  LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFF093FB), Color(0xFF764BA2), Color(0xFF667EEA)]),
  'ring_rainbow': LinearGradient(begin: Alignment.topLeft,  end: Alignment.bottomRight, colors: [Color(0xFFFF0080), Color(0xFFFF8C00), Color(0xFF00C9FF), Color(0xFF00FF87)]),
};

const _cosmeticBanners = <String, LinearGradient>{
  // ── Dégradés ──
  'banner_sunset': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFC5C7D), Color(0xFF6A3093)]),
  'banner_ocean':  LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2193B0), Color(0xFF6DD5FA)]),
  'banner_forest': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF134E5E), Color(0xFF71B280)]),
  'banner_galaxy': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A1A2E), Color(0xFF764BA2), Color(0xFFF093FB)]),
  'banner_rose':   LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFC466B), Color(0xFF3F5EFB)]),
  'banner_aurora': LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)]),
  // ── Couleurs unies (même couleur x2 = solid) ──
  'color_noir':    LinearGradient(colors: [Color(0xFF0A0A0A), Color(0xFF0A0A0A)]),
  'color_blanc':   LinearGradient(colors: [Color(0xFFF2F2F2), Color(0xFFF2F2F2)]),
  'color_teal':    LinearGradient(colors: [Color(0xFF0C5C6C), Color(0xFF0C5C6C)]),
  'color_vert':    LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF2D6A4F)]),
  'color_beige':   LinearGradient(colors: [Color(0xFFF5E6D3), Color(0xFFF5E6D3)]),
  'color_gris':    LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF2C3E50)]),
};

/// Résout la décoration d'une bannière à partir de son id :
/// - URL http → image réseau (BoxFit.cover)
/// - clé gradient/couleur → LinearGradient de _cosmeticBanners
/// - null → fond sombre par défaut
BoxDecoration _bannerDecoration(String? key) {
  if (key == null) return const BoxDecoration(gradient: _bgGrad);
  if (key.startsWith('http')) {
    return BoxDecoration(
      image: DecorationImage(image: NetworkImage(key), fit: BoxFit.cover),
    );
  }
  final grad = _cosmeticBanners[key];
  return grad != null ? BoxDecoration(gradient: grad) : const BoxDecoration(gradient: _bgGrad);
}

// Catalogue — ajouter ici les nouvelles bannières image quand prêtes
// Pour une bannière image : ajouter 'preview_url' avec l'URL de la miniature
const _cosmeticCatalog = <Map<String, Object>>[
  {'id': 'ring_gold',       'type': 'avatar_ring',    'label': 'Anneau Doré',              'cost': 150},
  {'id': 'ring_rose',       'type': 'avatar_ring',    'label': 'Anneau Rose Sakura',        'cost': 150},
  {'id': 'ring_fire',       'type': 'avatar_ring',    'label': 'Anneau Flammes',            'cost': 150},
  {'id': 'ring_arctic',     'type': 'avatar_ring',    'label': 'Anneau Arctique',           'cost': 150},
  {'id': 'ring_galaxy',     'type': 'avatar_ring',    'label': 'Anneau Galaxie',            'cost': 200},
  {'id': 'ring_rainbow',    'type': 'avatar_ring',    'label': 'Anneau Arc-en-ciel',        'cost': 250},
  // ── Bannières dégradé ──
  {'id': 'banner_sunset',   'type': 'profile_banner', 'label': 'Coucher de soleil',         'cost': 200},
  {'id': 'banner_ocean',    'type': 'profile_banner', 'label': 'Océan',                     'cost': 200},
  {'id': 'banner_forest',   'type': 'profile_banner', 'label': 'Forêt',                     'cost': 200},
  {'id': 'banner_galaxy',   'type': 'profile_banner', 'label': 'Galaxie',                   'cost': 250},
  {'id': 'banner_rose',     'type': 'profile_banner', 'label': 'Rose Violet',               'cost': 200},
  {'id': 'banner_aurora',   'type': 'profile_banner', 'label': 'Aurora',                    'cost': 250},
  // ── Couleurs unies ──
  {'id': 'color_noir',      'type': 'profile_banner', 'label': 'Noir',                      'cost': 100},
  {'id': 'color_blanc',     'type': 'profile_banner', 'label': 'Blanc',                     'cost': 100},
  {'id': 'color_teal',      'type': 'profile_banner', 'label': 'Teal',                      'cost': 100},
  {'id': 'color_vert',      'type': 'profile_banner', 'label': 'Vert forêt',                'cost': 100},
  {'id': 'color_beige',     'type': 'profile_banner', 'label': 'Beige',                     'cost': 100},
  {'id': 'color_gris',      'type': 'profile_banner', 'label': 'Gris ardoise',              'cost': 100},
  // ── Bannières image custom — ajouter ici ──
  // {'id': 'img_animaux',   'type': 'profile_banner', 'label': 'Animaux',  'cost': 350, 'preview_url': 'https://...', 'banner_url': 'https://...'},
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _profileName(Map<String, dynamic>? p) {
  if (p == null) return 'Membre';
  // Pseudo Pets Social choisi → il prime sur le vrai nom (tous types de profil).
  final pseudo = (p['social_pseudo'] ?? '').toString().trim();
  if (pseudo.isNotEmpty) return pseudo;
  final ne = (p['nom'] ?? '').toString().trim();
  final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
  // Profil pro / éleveur / association : on affiche le nom de la structure.
  final type = (p['profile_type'] ?? '').toString();
  if (type.isNotEmpty && type != 'particulier' && ne.isNotEmpty) return ne;
  if (n.isNotEmpty) return n;
  return ne.isNotEmpty ? ne : 'Membre';
}

/// Libellé lisible du type de profil (badge sous le nom dans les listes).
String? _socialTypeLabel(String? type) {
  switch (type) {
    case 'particulier': return null;
    case 'eleveur': return 'Éleveur';
    case 'association': return 'Association';
    case 'veterinaire':
    case 'sante': return 'Vétérinaire / Ostéo';
    case 'education': return 'Éducateur';
    case 'garde': return 'Pet Sitter';
    case 'toilettage': return 'Toiletteur';
    case 'photographe': return 'Photographe';
    case 'pension': return 'Pension';
    default: return (type != null && type.isNotEmpty) ? 'Professionnel' : null;
  }
}

const _kAuthorCols = 'id, uid, firstname, lastname, avatar_url, profile_picture_url_pro, profile_type, nom, is_influencer, social_pseudo';

/// Id du profil PARTICULIER d'un uid — identité utilisée dans le réseau social,
/// jamais le profil pro / is_main. Mémoïsé (les inserts like/follow l'appellent
/// souvent).
final Map<String, String?> _pidCache = {};
Future<String?> _particulierProfileId(String uid) async {
  if (uid.isEmpty) return null;
  if (_pidCache.containsKey(uid)) return _pidCache[uid];
  try {
    final rows = await Supabase.instance.client
        .from('user_profiles')
        .select('id')
        .eq('uid', uid)
        .eq('profile_type', 'particulier')
        .order('is_main', ascending: false)
        .limit(1);
    final id = (rows as List).isNotEmpty ? rows.first['id'] as String? : null;
    _pidCache[uid] = id;
    return id;
  } catch (_) {
    return null;
  }
}

/// Id du profil "social" d'un uid : son profil particulier s'il en a un, sinon
/// son profil principal (is_main). **Jamais null pour un compte existant** —
/// sert de cible aux follows / notifs même pour un compte pro-only.
final Map<String, String?> _socialPidCache = {};
Future<String?> _socialProfileId(String uid) async {
  if (uid.isEmpty) return null;
  if (_socialPidCache.containsKey(uid)) return _socialPidCache[uid];
  try {
    final rows = await Supabase.instance.client
        .from('user_profiles')
        .select('id, profile_type, is_main')
        .eq('uid', uid);
    final list = (rows as List).cast<Map<String, dynamic>>();
    String? id;
    if (list.isNotEmpty) {
      list.sort((a, b) {
        final ap = (a['profile_type'] == 'particulier') ? 0 : 1;
        final bp = (b['profile_type'] == 'particulier') ? 0 : 1;
        if (ap != bp) return ap - bp;
        final am = (a['is_main'] == true) ? 0 : 1;
        final bm = (b['is_main'] == true) ? 0 : 1;
        return am - bm;
      });
      id = list.first['id'] as String?;
    }
    _socialPidCache[uid] = id;
    return id;
  } catch (_) {
    return null;
  }
}

/// Id du profil **actif** de l'utilisateur — c'est son identité dans Pets
/// Social pour ce qu'il publie (post, commentaire, like, suivi).
///
/// - profil particulier → toujours autorisé ;
/// - profil éleveur / pro / association → autorisé (l'accès à Pets Social est
///   déjà réservé aux comptes premium à l'entrée de la page) ;
/// - repli : profil particulier de l'uid (compte non premium, ou profil actif
///   introuvable).
final Map<String, bool> _socialProAllowedCache = {};

/// Un profil non-particulier ne peut publier dans Pets Social que si le compte
/// est premium (l'accès à la page l'exige déjà, ce contrôle est une sécurité).
Future<bool> _socialProAllowed(String uid) async {
  if (_socialProAllowedCache.containsKey(uid)) return _socialProAllowedCache[uid]!;
  try {
    final code = await PlanService.getPlanCode(uid);
    final ok = code == 'premium';
    _socialProAllowedCache[uid] = ok;
    return ok;
  } catch (_) {
    return false;
  }
}

/// Identité du profil **actif** de l'utilisateur dans Pets Social (posts,
/// commentaires, likes, suivis, ET scope de lecture des abonnements/notifs).
/// Ne renvoie **jamais null** pour un compte connecté existant.
Future<String?> _activeAuthorProfileId(String uid) async {
  if (uid.isEmpty) return null;
  final activeId = User_Info.activeProfileId;
  final activeType = User_Info.activeType;
  try {
    if (activeType.isNotEmpty && activeType != 'particulier') {
      // Profil pro / éleveur / association : identité = ce profil **si** le
      // compte est premium ; sinon repli sur le profil particulier (s'il
      // existe), et à défaut on garde ce profil.
      if (await _socialProAllowed(uid)) {
        if (activeId.isNotEmpty) return activeId;
        final rows = await Supabase.instance.client
            .from('user_profiles').select('id')
            .eq('uid', uid).eq('is_main', true).limit(1);
        if ((rows as List).isNotEmpty) return rows.first['id'] as String?;
      } else {
        final part = await _particulierProfileId(uid);
        if (part != null) return part;
        if (activeId.isNotEmpty) return activeId;
      }
    } else if (activeId.isNotEmpty) {
      // Profil particulier secondaire explicite.
      return activeId;
    }
  } catch (_) {}
  // Repli : particulier sinon is_main — jamais null pour un compte existant.
  return _socialProfileId(uid);
}

/// Insère un like et envoie une push notif à l'auteur du post.
Future<void> _insertLike(String postId, String uid) async {
  final supa = Supabase.instance.client;
  final pid = await _activeAuthorProfileId(uid);
  await supa.from('post_likes').insert({
    'post_id': postId,
    'uid': uid,
    if (pid != null) 'author_profile_id': pid,
  });
  // Notification push — fire-and-forget, erreurs silencieuses
  _sendSocialNotif(
    supa: supa,
    actorUid: uid,
    postId: postId,
    type: 'social_like',
    titleSuffix: 'a aimé votre post',
    body: 'Votre publication vient de recevoir un nouveau like ❤️',
  );
}

/// Envoie une notification sociale vers l'auteur du post (likes/commentaires)
/// ou la personne ciblée (follows). Fire-and-forget.
void _sendSocialNotif({
  required SupabaseClient supa,
  required String actorUid,
  String? postId,
  String? targetUid,
  required String type,
  required String titleSuffix,
  required String body,
}) async {
  try {
    // Récupérer le destinataire depuis le post si pas de targetUid direct
    String? recipientUid = targetUid;
    if (recipientUid == null && postId != null) {
      final row = await supa
          .from('posts_socialmedia')
          .select('uid')
          .eq('id', postId)
          .maybeSingle();
      recipientUid = row?['uid'] as String?;
    }
    if (recipientUid == null || recipientUid == actorUid) return;

    // Nom de la personne qui agit (pseudo Pets Social s'il est défini)
    final actorRow = await supa
        .from('user_profiles')
        .select('firstname, lastname, social_pseudo')
        .eq('uid', actorUid)
        .limit(1)
        .maybeSingle();
    final actorPseudo = (actorRow?['social_pseudo'] as String? ?? '').trim();
    final actorName = actorPseudo.isNotEmpty
        ? actorPseudo
        : (actorRow != null
            ? '${actorRow['firstname'] ?? ''} ${actorRow['lastname'] ?? ''}'.trim()
            : 'Quelqu\'un');

    await supa.from('notifications').insert({
      'uid': recipientUid,
      'type': type,
      'title': '$actorName $titleSuffix',
      'body': body,
      'data': {
        if (postId != null) 'post_id': postId,
        if (targetUid != null) 'actor_uid': actorUid,
      },
      'read': false,
    });
  } catch (_) {}
}

/// Insère une relation de suivi et envoie une push notif à la personne suivie.
Future<void> _insertFollow(String followerUid, String followingUid,
    {String? followingProfileId}) async {
  final supa = Supabase.instance.client;
  final fp = await _activeAuthorProfileId(followerUid);
  final tp = followingProfileId ?? await _socialProfileId(followingUid);
  await supa.from('follows').insert({
    'follower_uid': followerUid,
    'following_uid': followingUid,
    if (fp != null) 'follower_profile_id': fp,
    if (tp != null) 'following_profile_id': tp,
  });
  _sendSocialNotif(
    supa: supa,
    actorUid: followerUid,
    targetUid: followingUid,
    type: 'social_follow',
    titleSuffix: 'vous suit maintenant',
    body: 'Découvrez son profil sur Pets Social 🐾',
  );
}

/// Désabonne le profil ACTIF de la cible — scopé par `follower_profile_id`,
/// ne touche jamais les abonnements des autres profils du compte.
Future<void> _removeFollow(String followerUid, String followingUid,
    {String? followingProfileId}) async {
  final fp = await _activeAuthorProfileId(followerUid);
  var d = Supabase.instance.client.from('follows').delete().eq('following_uid', followingUid);
  d = fp != null ? d.eq('follower_profile_id', fp) : d.eq('follower_uid', followerUid);
  if (followingProfileId != null) d = d.eq('following_profile_id', followingProfileId);
  await d;
}

/// UIDs suivis par le profil ACTIF de l'utilisateur (pour les boutons « Suivre »).
Future<Set<String>> _activeFollowingUids(String uid) async {
  final pid = await _activeAuthorProfileId(uid);
  if (pid == null) return <String>{};
  try {
    final rows = await Supabase.instance.client
        .from('follows').select('following_uid').eq('follower_profile_id', pid);
    return {for (final r in rows as List) r['following_uid'] as String};
  } catch (_) {
    return <String>{};
  }
}

/// Clé du profil AUTEUR d'une ligne (post / commentaire / repost). Pour un
/// repost = le **reposteur** (pas l'auteur original). `author_profile_id` sinon
/// `u:<uid>` (legacy). Deux profils d'un même compte ne se confondent plus.
String _authorKey(Map row) {
  final pid = row['author_profile_id'] as String?;
  return (pid != null && pid.isNotEmpty) ? pid : 'u:${row['uid']}';
}

/// Clé du profil de l'auteur ORIGINAL d'un repost (ce qui s'affiche dans le
/// corps de la carte).
String _origAuthorKey(Map row) {
  final pid = row['_orig_author_profile_id'] as String?;
  return (pid != null && pid.isNotEmpty) ? pid : 'u:${row['original_uid'] ?? row['uid']}';
}

/// Résout les profils auteurs de posts/commentaires. Retourne une map
/// **clé profil (`_authorKey`/`_origAuthorKey`) -> ligne user_profiles**.
Future<Map<String, Map<String, dynamic>>> _resolveAuthors(List<dynamic> rows) async {
  final supa = Supabase.instance.client;
  final out = <String, Map<String, dynamic>>{};
  final profIds = <String>{
    for (final r in rows) ...[
      if ((r['author_profile_id'] as String?)?.isNotEmpty == true) r['author_profile_id'] as String,
      if ((r['_orig_author_profile_id'] as String?)?.isNotEmpty == true) r['_orig_author_profile_id'] as String,
    ],
  }.toList();
  if (profIds.isNotEmpty) {
    final byId = await supa.from('user_profiles').select(_kAuthorCols).inFilter('id', profIds);
    for (final r in byId as List) {
      out[r['id'] as String] = Map<String, dynamic>.from(r as Map);
    }
  }
  // Lignes sans profil connu (legacy) → profil particulier de l'uid concerné.
  // Un repost sans author_profile_id → on résout SON reposteur (uid) ET son
  // auteur original (original_uid).
  final legacyUids = <String>{
    for (final r in rows) ...[
      if ((r['author_profile_id'] as String?)?.isNotEmpty != true) r['uid'] as String,
      if (r['is_repost'] == true
          && (r['_orig_author_profile_id'] as String?)?.isNotEmpty != true
          && r['original_uid'] != null) r['original_uid'] as String,
    ],
  }.where((u) => !out.containsKey('u:$u')).toList();
  if (legacyUids.isNotEmpty) {
    final byUid = await supa.from('user_profiles').select(_kAuthorCols)
        .inFilter('uid', legacyUids).eq('profile_type', 'particulier');
    for (final r in byUid as List) {
      out.putIfAbsent('u:${r['uid']}', () => Map<String, dynamic>.from(r as Map));
    }
  }
  // Anneau d'avatar équipé — par PROFIL (active_by_profile[id]), repli
  // active_value pour le profil principal / les lignes anciennes.
  final uids = out.values.map((v) => v['uid'] as String).toSet().toList();
  if (uids.isNotEmpty) {
    try {
      final cosmetics = await supa.from('user_cosmetics')
          .select('uid, active_value, active_by_profile')
          .inFilter('uid', uids)
          .eq('cosmetic_type', 'avatar_ring');
      final byUid = {for (final c in cosmetics as List) c['uid'] as String: c as Map};
      for (final e in out.entries) {
        final c = byUid[e.value['uid']];
        if (c == null) continue;
        final abp = (c['active_by_profile'] as Map?) ?? {};
        // e.key = profil id (ou 'u:<uid>') → on ne connaît le profil que si e.key
        // n'est pas legacy.
        final ring = (e.key.startsWith('u:') ? null : abp[e.key] as String?)
            ?? c['active_value'] as String?;
        if (ring != null) e.value['_ring'] = ring;
      }
    } catch (_) {}
  }
  return out;
}

String? _profilePhoto(Map<String, dynamic>? p) {
  if (p == null) return null;
  final type = (p['profile_type'] ?? '').toString();
  final pro = p['profile_picture_url_pro']?.toString();
  final av  = p['avatar_url']?.toString();
  // Profil pro / éleveur : photo « pro » d'abord (comme le bandeau de menu) ;
  // particulier : avatar. Repli sur l'autre si vide.
  if (type.isNotEmpty && type != 'particulier') {
    return (pro != null && pro.isNotEmpty) ? pro : av;
  }
  return (av != null && av.isNotEmpty) ? av : pro;
}

List<String> _mediaUrls(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  if (raw.startsWith('[')) {
    try { return List<String>.from(jsonDecode(raw) as List); } catch (_) {}
  }
  return [raw];
}

// ─── Tag animaux sur une publication ─────────────────────────────────────────
//
// Un post peut « taguer » un ou plusieurs animaux du compte (particulier OU
// pro/éleveur) via `posts_socialmedia.tagged_animal_ids uuid[]`. Depuis la
// fiche d'un animal, un bouton ouvre `AnimalTaggedPostsPage` — toutes les
// publications du réseau où cet animal est tagué.

const _kAnimalSortiStatuts = ['sorti', 'decede', 'cede', 'vendu', 'mort', 'retraite'];

/// Animaux taguables sur une publication : **uniquement ceux du PROFIL ACTIF**
/// (particulier ↔ éleveur strictement séparés) et **dont on est encore
/// propriétaire** (jamais un animal cédé). Aligné sur la logique de « Mes
/// Animaux » : `animaux_proprietes` filtré par `profile_id_proprio` + `date_fin`
/// NULL, complété par les animaux d'élevage du profil éleveur.
Future<List<Map<String, dynamic>>> _loadTaggableAnimals(String uid) async {
  if (uid.isEmpty) return [];
  final supa = Supabase.instance.client;
  // Profil actif résolu à un id concret (jamais null) → scope strict même
  // quand on est sur le profil principal (activeProfileId == '').
  final effectivePid = await _activeAuthorProfileId(uid);
  final activeType = User_Info.activeType;
  final ids = <String>{};

  // 1. Propriété ACTIVE (date_fin NULL) du profil actif.
  try {
    var migrated = false;
    if (effectivePid != null) {
      final check = await supa.from('animaux_proprietes').select('animal_id')
          .eq('uid_proprio', uid)
          .not('profile_id_proprio', 'is', null).limit(1);
      migrated = (check as List).isNotEmpty;
    }
    var q = supa.from('animaux_proprietes')
        .select('animal_id, profile_id_proprio, date_fin')
        .eq('uid_proprio', uid)
        .eq('statut', 'actif')
        .isFilter('date_fin', null);
    if (migrated && effectivePid != null) {
      q = q.eq('profile_id_proprio', effectivePid);
    }
    for (final r in await q as List) {
      final id = r['animal_id'] as String?;
      if (id != null && id.isNotEmpty) ids.add(id);
    }
  } catch (_) {}

  // 2. Animaux d'élevage — SEULEMENT depuis un profil éleveur/pro/asso, jamais
  //    depuis un profil particulier. Exclut les animaux sortis / cédés.
  if (activeType.isNotEmpty && activeType != 'particulier') {
    try {
      var q = supa.from('animaux')
          .select('id, profile_id, statut, date_sortie')
          .eq('uid_eleveur', uid);
      if (effectivePid != null) q = q.eq('profile_id', effectivePid);
      for (final r in await q as List) {
        final id = r['id'] as String?;
        final statut = (r['statut'] ?? '').toString();
        if (id == null || id.isEmpty) continue;
        if (_kAnimalSortiStatuts.contains(statut)) continue;
        if (r['date_sortie'] != null) continue;
        ids.add(id);
      }
    } catch (_) {}
  }

  if (ids.isEmpty) return [];
  try {
    final rows = await supa.from('animaux')
        .select('id, nom, espece, race, photo_url, sexe, statut, date_sortie')
        .inFilter('id', ids.toList());
    final list = List<Map<String, dynamic>>.from(rows as List)
        // Filet de sécurité : jamais un animal sorti / cédé / décédé.
        .where((a) => a['date_sortie'] == null &&
            !_kAnimalSortiStatuts.contains((a['statut'] ?? '').toString()))
        .toList();
    list.sort((a, b) => (a['nom'] ?? '').toString().toLowerCase()
        .compareTo((b['nom'] ?? '').toString().toLowerCase()));
    return list;
  } catch (_) {
    return [];
  }
}

/// Résout {id: {nom, photo_url}} pour une liste d'ids d'animaux tagués.
Future<Map<String, Map<String, dynamic>>> _resolveTaggedAnimals(
    List<String> ids) async {
  if (ids.isEmpty) return {};
  try {
    final rows = await Supabase.instance.client.from('animaux')
        .select('id, nom, photo_url, espece').inFilter('id', ids);
    return {
      for (final r in rows as List)
        r['id'] as String: Map<String, dynamic>.from(r as Map),
    };
  } catch (_) {
    return {};
  }
}

/// Extrait proprement la liste d'ids depuis la valeur brute `tagged_animal_ids`
/// (peut arriver en `List<dynamic>` ou en chaîne PostgREST `{a,b}`).
List<String> _taggedIds(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  if (raw is String && raw.length > 2 && raw.startsWith('{')) {
    return raw.substring(1, raw.length - 1)
        .split(',').map((s) => s.replaceAll('"', '').trim())
        .where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

/// Ouvre le détail d'une publication à partir de son id — point d'entrée des
/// liens de partage `petsmatchapp.com/p/<id>` (cf. `DeepLinkService`).
Future<void> openSharedSocialPost(BuildContext context, String postId) async {
  try {
    final row = await Supabase.instance.client
        .from('posts_socialmedia').select().eq('id', postId).maybeSingle();
    if (row == null || !context.mounted) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        child: _PostDetailSheet(post: Map<String, dynamic>.from(row), myUid: myUid),
      ),
    );
  } catch (_) {}
}

String _fmtDate(String iso) {
  try {
    final dt   = DateTime.parse(iso).toLocal();
    final now  = DateTime.now();
    final diff = now.difference(dt);
    final hhmm = DateFormat('HH:mm').format(dt);
    if (diff.inMinutes < 1)  return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24 && now.day == dt.day) return 'Aujourd\'hui à $hhmm';
    if (diff.inDays < 2 && now.day - dt.day == 1) return 'Hier à $hhmm';
    if (diff.inDays < 7) {
      const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      return '${jours[dt.weekday - 1]} à $hhmm';
    }
    const mois = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    final m = mois[dt.month - 1];
    if (dt.year == now.year) return '${dt.day} $m à $hhmm';
    return '${dt.day} $m ${dt.year}';
  } catch (_) {
    return '';
  }
}

Widget _avatarWidget(String? photoUrl, double radius, {String? ringStyle}) {
  final grad = ringStyle != null ? (_cosmeticRings[ringStyle] ?? _ringGrad) : _ringGrad;
  return Container(
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: grad),
    child: Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFD4EDE8),
        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
            ? NetworkImage(photoUrl)
            : null,
        child: (photoUrl == null || photoUrl.isEmpty)
            ? Icon(Icons.pets_outlined, size: radius * 0.9, color: _tealC)
            : null,
      ),
    ),
  );
}

// ─── Page principale ──────────────────────────────────────────────────────────

class SocialFeedPage extends StatefulWidget {
  const SocialFeedPage({super.key});
  @override
  State<SocialFeedPage> createState() => _SocialFeedPageState();
}

class _SocialFeedPageState extends State<SocialFeedPage> {
  int _tabIndex   = 0;
  int _refresh    = 0;
  int _notifCount = 0;
  final _supa = Supabase.instance.client;
  String? _myProfileId; // profil ACTIF de l'utilisateur (identité Pets Social)

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid != null) {
      _activeAuthorProfileId(uid).then((id) {
        if (!mounted) return;
        setState(() => _myProfileId = id);
        _loadNotifCount(); // recompte avec le bon profil une fois résolu
      });
    }
    _loadNotifCount();
  }

  Future<void> _loadNotifCount() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final pid = _myProfileId ?? await _activeAuthorProfileId(uid);
      if (pid == null) return;
      final prefs = await SharedPreferences.getInstance();
      final lastSeenStr = prefs.getString('notif_seen_at_$uid');
      final lastSeen = lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;

      final myPosts = await _supa.from('posts_socialmedia').select('id')
          .eq('author_profile_id', pid);
      final postIds = (myPosts as List).map((p) => p['id'] as String).toList();
      int count = 0;
      if (postIds.isNotEmpty) {
        var q = _supa.from('post_comments')
            .select('id')
            .inFilter('post_id', postIds)
            .neq('uid', uid);
        if (lastSeen != null) {
          q = q.gt('created_at', lastSeen.toIso8601String());
        }
        final comments = await q.limit(99);
        count += (comments as List).length;
      }
      var fq = _supa.from('follows').select('follower_uid')
          .eq('following_profile_id', pid);
      if (lastSeen != null) {
        fq = fq.gt('created_at', lastSeen.toIso8601String());
      }
      final follows = await fq;
      count += (follows as List).length;
      if (mounted) setState(() => _notifCount = count > 99 ? 99 : count);
    } catch (_) {}
  }

  Future<void> _markNotifSeen() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_seen_at_$uid', DateTime.now().toIso8601String());
  }

  void _openCreate() {
    if (_uid == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostSheet(
        myUid: _uid!,
        onPosted: () => setState(() => _refresh++),
      ),
    );
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(myUid: _uid ?? ''),
    );
  }

  void _openNotifications() {
    if (_uid == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SocialNotificationsPage(myUid: _uid!, myProfileId: _myProfileId),
    ));
  }

  void _openMyProfile() {
    if (_uid == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SocialProfilePage(
        targetUid: _uid!, myUid: _uid!,
        targetProfileId: _myProfileId, myProfileId: _myProfileId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid ?? '';
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        // ── Fond dégradé + silhouettes ─────────────────────────────
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(gradient: _bgGrad),
          ),
        ),

        // ── Contenu ────────────────────────────────────────────────
        SafeArea(
          child: Column(children: [
            _buildHeader(),
            _buildPillTabs(),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _FeedList(
                      key: ValueKey('following_${_refresh}_$_myProfileId'),
                      type: 'following',
                      myUid: uid,
                      myProfileId: _myProfileId),
                  _FeedList(
                      key: ValueKey('discover_$_refresh'),
                      type: 'discover',
                      myUid: uid),
                  _MyPostsList(
                      key: ValueKey('myposts_${_refresh}_$_myProfileId'),
                      myUid: uid,
                      myProfileId: _myProfileId,
                      onRefresh: () => setState(() => _refresh++)),
                ],
              ),
            ),
          ]),
        ),
      ]),

      // ── FAB ────────────────────────────────────────────────────
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_tealC, _green]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: _tealC.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: _openCreate,
          child: const Icon(Icons.add_a_photo_outlined, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
      child: Row(children: [
        // ── Titre "Pets Social" — INTOUCHÉ ──────────────────────
        Expanded(
          child: Row(children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFFFFE080), Color(0xFFFFF5C3)],
              ).createShader(b),
              child: const Text('Pets',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: Colors.white)),
            ),
            const Text(' Social',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w300,
                    fontSize: 22,
                    color: Colors.white,
                    letterSpacing: 0.5)),
          ]),
        ),
        // ── Boutons header ───────────────────────────────────────
        _headerBtn(Icons.search_rounded, _openSearch),
        const SizedBox(width: 8),
        Stack(clipBehavior: Clip.none, children: [
          _headerBtn(Icons.notifications_outlined, () {
            setState(() => _notifCount = 0);
            _markNotifSeen();
            _openNotifications();
          }),
          if (_notifCount > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0D1F22), width: 1.5)),
                child: Text(_notifCount > 9 ? '9+' : '$_notifCount',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 9,
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ]),
        const SizedBox(width: 8),
        _headerBtn(Icons.person_outline_rounded, _openMyProfile),
      ]),
    );
  }

  Widget _headerBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildPillTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pill('Mon feed', 0),
          const SizedBox(width: 8),
          _pill('Découverte', 1),
          const SizedBox(width: 8),
          _pill('Mes posts', 2),
        ],
      ),
    );
  }

  Widget _pill(String label, int idx) {
    final active = _tabIndex == idx;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = idx),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: active ? const LinearGradient(colors: [_tealC, _green]) : null,
              color: active ? null : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: active
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.20)),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: _tealC.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ]
                  : null,
            ),
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: active ? 0.3 : 0)),
          ),
        ),
      ),
    );
  }
}

// ─── Skeleton loading ────────────────────────────────────────────────────────

class _SkeletonFeed extends StatefulWidget {
  const _SkeletonFeed();
  @override
  State<_SkeletonFeed> createState() => _SkeletonFeedState();
}

class _SkeletonFeedState extends State<_SkeletonFeed>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.04, end: 0.12).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => Container(
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: _anim.value * 2))),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 120, height: 12, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value * 2), borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 6),
                  Container(width: 70, height: 9, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value), borderRadius: BorderRadius.circular(6))),
                ]),
              ]),
              const SizedBox(height: 14),
              Container(width: double.infinity, height: 11, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value * 1.5), borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 8),
              Container(width: 200, height: 11, decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value), borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 16),
              Expanded(child: Container(decoration: BoxDecoration(color: Colors.white.withValues(alpha: _anim.value), borderRadius: BorderRadius.circular(14)))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Suggestions à suivre (empty state Mon feed) ──────────────────────────────

class _SuggestionsWidget extends StatefulWidget {
  final String myUid;
  final String? myProfileId; // profil actif — scope les abonnements
  final VoidCallback onFollowed;
  const _SuggestionsWidget({required this.myUid, this.myProfileId, required this.onFollowed});
  @override
  State<_SuggestionsWidget> createState() => _SuggestionsWidgetState();
}

class _SuggestionsWidgetState extends State<_SuggestionsWidget> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _suggestions = [];
  final Set<String> _followedKeys = {}; // profil id, sinon 'u:<uid>'
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // Abonnements du profil ACTIF (on suit des PROFILS) — strictement scopé,
    // jamais de repli sur l'uid (fuiterait les abonnements des autres profils).
    final pid = widget.myProfileId ?? await _activeAuthorProfileId(widget.myUid);
    if (pid == null) { if (mounted) setState(() => _loading = false); return; }
    final follows = await _supa.from('follows')
        .select('following_uid, following_profile_id')
        .eq('follower_profile_id', pid);
    for (final r in follows as List) {
      final pid = (r['following_profile_id'] as String?) ?? '';
      _followedKeys.add(pid.isNotEmpty ? pid : 'u:${r['following_uid']}');
    }

    final recent = await _supa.from('posts_socialmedia')
        .select('uid, author_profile_id')
        .order('created_at', ascending: false)
        .limit(120);

    // Candidats = profils distincts ayant publié récemment, hors moi / déjà suivis.
    final seen = <String>{};
    final candidatePids = <String>[];
    final candidateLegacyUids = <String>[];
    for (final r in recent as List) {
      final uid = r['uid'] as String;
      if (uid == widget.myUid) continue;
      final pid = (r['author_profile_id'] as String?) ?? '';
      final key = pid.isNotEmpty ? pid : 'u:$uid';
      if (_followedKeys.contains(key) || !seen.add(key)) continue;
      if (pid.isNotEmpty) { candidatePids.add(pid); } else { candidateLegacyUids.add(uid); }
      if (candidatePids.length + candidateLegacyUids.length >= 12) break;
    }
    if (candidatePids.isEmpty && candidateLegacyUids.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final out = <Map<String, dynamic>>[];
    if (candidatePids.isNotEmpty) {
      final rows = await _supa.from('user_profiles')
          .select('id, uid, firstname, lastname, avatar_url, profile_picture_url_pro, profile_type, nom, social_pseudo')
          .inFilter('id', candidatePids);
      out.addAll((rows as List).cast<Map<String, dynamic>>());
    }
    if (candidateLegacyUids.isNotEmpty) {
      final rows = await _supa.from('user_profiles')
          .select('id, uid, firstname, lastname, avatar_url, profile_picture_url_pro, profile_type, nom, social_pseudo')
          .inFilter('uid', candidateLegacyUids)
          .eq('profile_type', 'particulier');
      out.addAll((rows as List).cast<Map<String, dynamic>>());
    }
    if (mounted) {
      setState(() {
        _suggestions = out;
        _loading = false;
      });
    }
  }

  Future<void> _follow(Map<String, dynamic> prof) async {
    final targetUid = prof['uid'] as String;
    final pid = prof['id'] as String?;
    await _insertFollow(widget.myUid, targetUid, followingProfileId: pid);
    setState(() => _followedKeys.add((pid != null && pid.isNotEmpty) ? pid : 'u:$targetUid'));
    await Future.delayed(const Duration(milliseconds: 600));
    widget.onFollowed();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_suggestions.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_tealC, _green]), shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _tealC.withValues(alpha: 0.35), blurRadius: 24)]),
            child: const Icon(Icons.photo_library_outlined, size: 52, color: Colors.white)),
          const SizedBox(height: 20),
          const Text('Soyez le premier à publier !', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('Suggestions · À suivre', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
        ),
        ..._suggestions.map((prof) {
          final pid = (prof['id'] as String?) ?? '';
          final key = pid.isNotEmpty ? pid : 'u:${prof['uid']}';
          final isFollowed = _followedKeys.contains(key);
          final typeLabel = _socialTypeLabel((prof['profile_type'] ?? '').toString());
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: _avatarWidget(_profilePhoto(prof), 22),
              title: Text(_profileName(prof), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
              subtitle: typeLabel != null
                  ? Text(typeLabel, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green))
                  : const Text('Particulier', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white54)),
              trailing: GestureDetector(
                onTap: isFollowed ? null : () => _follow(prof),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isFollowed ? null : const LinearGradient(colors: [_tealC, _green]),
                    color: isFollowed ? Colors.white.withValues(alpha: 0.10) : null,
                    borderRadius: BorderRadius.circular(18),
                    border: isFollowed ? Border.all(color: Colors.white24) : null,
                  ),
                  child: Text(isFollowed ? 'Suivi ✓' : 'Suivre',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }
}

// ─── Feed list ────────────────────────────────────────────────────────────────

class _FeedList extends StatefulWidget {
  final String type;
  final String myUid;
  final String? myProfileId; // profil actif — scope le fil « Abonnements »
  final String? animalId;    // type == 'animal' : posts où cet animal est tagué
  const _FeedList({super.key, required this.type, required this.myUid, this.myProfileId, this.animalId});
  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _posts    = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  Set<String> _liked     = {};
  Set<String> _following = {};
  Set<String> _followingPids = {}; // abonnements du profil actif (following_profile_id)
  bool   _loading   = true;
  String? _feedError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _feedError = null; });
    String? activePid;
    try {
      if (widget.myUid.isNotEmpty) {
        try {
          // Abonnements du profil ACTIF uniquement (scope strict par profil).
          final pid = widget.myProfileId ?? await _activeAuthorProfileId(widget.myUid);
          activePid = pid;
          final rows = pid == null
              ? const <dynamic>[]
              : await _supa
                  .from('follows')
                  .select('following_uid, following_profile_id')
                  .eq('follower_profile_id', pid);
          _following = {for (final r in rows) r['following_uid'] as String};
          _followingPids = {
            for (final r in rows)
              if ((r['following_profile_id'] as String?)?.isNotEmpty == true)
                r['following_profile_id'] as String,
          };
        } catch (_) {
          _following = {};
          _followingPids = {};
        }
      }

      List<dynamic> posts;
      if (widget.type == 'animal') {
        // Toutes les publications du réseau où cet animal est tagué.
        posts = widget.animalId == null
            ? []
            : await _supa
                .from('posts_socialmedia')
                .select()
                .contains('tagged_animal_ids', [widget.animalId!])
                .order('created_at', ascending: false)
                .limit(100);
      } else if (widget.type == 'following') {
        final uids = <String>{
          ..._following,
          if (widget.myUid.isNotEmpty) widget.myUid,
        }.toList();
        if (uids.isEmpty) {
          posts = [];
        } else if (uids.length == 1) {
          posts = await _supa
              .from('posts_socialmedia')
              .select()
              .eq('uid', uids.first)
              .order('created_at', ascending: false)
              .limit(50);
        } else {
          posts = await _supa
              .from('posts_socialmedia')
              .select()
              .inFilter('uid', uids)
              .order('created_at', ascending: false)
              .limit(50);
        }
        // Scope au profil actif : on suit des PROFILS, pas des comptes. On garde
        // les posts dont l'author_profile_id est suivi (+ les miens du profil
        // actif) ; les lignes legacy sans profil restent tolérées.
        final keep = {
          ..._followingPids,
          if (activePid != null) activePid,
        };
        if (keep.isNotEmpty) {
          posts = posts.where((p) {
            final apid = p['author_profile_id'] as String?;
            if (apid == null || apid.isEmpty) return true;
            return keep.contains(apid);
          }).toList();
        }
      } else {
        posts = await _supa
            .from('posts_socialmedia')
            .select()
            .order('created_at', ascending: false)
            .limit(50);
        // Posts boostés remontent en tête de Découverte
        final now = DateTime.now();
        posts.sort((a, b) {
          final aUntil = a['boosted_until'] != null ? DateTime.tryParse(a['boosted_until'] as String) : null;
          final bUntil = b['boosted_until'] != null ? DateTime.tryParse(b['boosted_until'] as String) : null;
          final aBoosted = aUntil?.isAfter(now) == true;
          final bBoosted = bUntil?.isAfter(now) == true;
          if (aBoosted && !bBoosted) return -1;
          if (!aBoosted && bBoosted) return 1;
          return 0;
        });
      }

      if (posts.isEmpty) {
        if (mounted) setState(() { _posts = []; _loading = false; });
        return;
      }

      // Déduplique : enlève le post original si un repost de lui est déjà dans le feed
      final repostOrigIds = posts
          .where((p) => p['is_repost'] == true && p['original_post_id'] != null)
          .map((p) => p['original_post_id'] as String)
          .toSet();
      if (repostOrigIds.isNotEmpty) {
        posts = posts.where((p) =>
            p['is_repost'] == true || !repostOrigIds.contains(p['id'] as String)).toList();
      }

      // Reposts : récupère le profil auteur du post ORIGINAL (author_profile_id),
      // pas seulement l'uid — sinon un compte multi-profils s'affiche mal.
      final origPostIds = posts
          .where((p) => p['is_repost'] == true && p['original_post_id'] != null)
          .map((p) => p['original_post_id'] as String)
          .toSet().toList();
      if (origPostIds.isNotEmpty) {
        try {
          final origs = await _supa.from('posts_socialmedia')
              .select('id, uid, author_profile_id').inFilter('id', origPostIds);
          final byId = {for (final o in origs as List) o['id'] as String: o as Map};
          for (final p in posts) {
            if (p['is_repost'] == true) {
              final o = byId[p['original_post_id']];
              if (o != null) {
                p['_orig_author_profile_id'] = o['author_profile_id'];
                p['original_uid'] = o['uid'];
              }
            }
          }
        } catch (_) {}
      }

      _profiles = await _resolveAuthors(posts);

      // Pour les reposts, les likes/commentaires sont sur l'ID original
      String effectiveId(dynamic p) {
        final m = p as Map;
        return m['is_repost'] == true && m['original_post_id'] != null
            ? m['original_post_id'] as String : m['id'] as String;
      }
      final allQueryIds = posts.map(effectiveId).toSet().toList();
      // Stocke l'ID effectif dans le post pour usage dans itemBuilder
      for (final post in posts) {
        post['_effective_id'] = effectiveId(post);
      }

      final allLikes = await _supa
          .from('post_likes')
          .select('post_id, uid')
          .inFilter('post_id', allQueryIds);
      final likeCounts = <String, int>{};
      _liked = {};
      for (final l in allLikes as List) {
        final pid = l['post_id'] as String;
        likeCounts[pid] = (likeCounts[pid] ?? 0) + 1;
        if (l['uid'] == widget.myUid) _liked.add(pid);
      }

      final allComments = await _supa
          .from('post_comments')
          .select('post_id')
          .inFilter('post_id', allQueryIds);
      final commentCounts = <String, int>{};
      for (final c in allComments as List) {
        final pid = c['post_id'] as String;
        commentCounts[pid] = (commentCounts[pid] ?? 0) + 1;
      }

      for (final post in posts) {
        final eid = post['_effective_id'] as String;
        post['like_count']    = likeCounts[eid] ?? 0;
        post['comment_count'] = commentCounts[eid] ?? 0;
      }

      if (mounted) {
        setState(() {
          _posts   = posts.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _feedError = e.toString(); });
    }
  }

  Future<void> _toggleLike(String postId) async {
    final isLiked = _liked.contains(postId);
    setState(() {
      if (isLiked) {
        _liked.remove(postId);
        final i = _posts.indexWhere((p) => p['id'] == postId);
        if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) - 1;
      } else {
        _liked.add(postId);
        final i = _posts.indexWhere((p) => p['id'] == postId);
        if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) + 1;
      }
    });
    try {
      if (isLiked) {
        await _supa.from('post_likes').delete()
            .eq('post_id', postId).eq('uid', widget.myUid);
      } else {
        await _insertLike(postId, widget.myUid);
      }
    } catch (_) {
      setState(() {
        if (isLiked) {
          _liked.add(postId);
          final i = _posts.indexWhere((p) => p['id'] == postId);
          if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) + 1;
        } else {
          _liked.remove(postId);
          final i = _posts.indexWhere((p) => p['id'] == postId);
          if (i >= 0) _posts[i]['like_count'] = (_posts[i]['like_count'] as int) - 1;
        }
      });
    }
  }

  Future<void> _toggleFollow(String targetUid, {String? targetProfileId}) async {
    final isFollowing = targetProfileId != null
        ? _followingPids.contains(targetProfileId)
        : _following.contains(targetUid);
    setState(() {
      if (isFollowing) {
        _following.remove(targetUid);
        if (targetProfileId != null) _followingPids.remove(targetProfileId);
      } else {
        _following.add(targetUid);
        if (targetProfileId != null) _followingPids.add(targetProfileId);
      }
    });
    try {
      if (isFollowing) {
        await _removeFollow(widget.myUid, targetUid, followingProfileId: targetProfileId);
      } else {
        await _insertFollow(widget.myUid, targetUid, followingProfileId: targetProfileId);
      }
    } catch (_) {
      setState(() {
        if (isFollowing) {
          _following.add(targetUid);
          if (targetProfileId != null) _followingPids.add(targetProfileId);
        } else {
          _following.remove(targetUid);
          if (targetProfileId != null) _followingPids.remove(targetProfileId);
        }
      });
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _supa.from('posts_socialmedia').delete().eq('id', postId);
    setState(() => _posts.removeWhere((p) => p['id'] == postId));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const _SkeletonFeed();
    }
    if (_feedError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erreur: $_feedError',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Galey',
                  color: Colors.redAccent,
                  fontSize: 12)),
        ),
      );
    }
    if (_posts.isEmpty) {
      if (widget.type == 'following') {
        return _SuggestionsWidget(myUid: widget.myUid, myProfileId: widget.myProfileId, onFollowed: _load);
      }
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_tealC, _green]),
                shape: BoxShape.circle, boxShadow: [BoxShadow(color: _tealC.withValues(alpha: 0.35), blurRadius: 24)]),
            child: const Icon(Icons.photo_library_outlined, size: 52, color: Colors.white)),
          const SizedBox(height: 20),
          const Text('Aucune publication pour l\'instant', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
        ]),
      ));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _tealC,
      backgroundColor: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final post        = _posts[i];
          final postId      = post['id'] as String;
          final effectiveId = post['_effective_id'] as String? ?? postId;
          final isRepost    = post['is_repost'] == true;
          final reposterUid = post['uid'] as String;
          final originalUid = isRepost ? (post['original_uid'] as String? ?? reposterUid) : reposterUid;
          // Profil qui a republié : son author_profile_id (ou u:<uid>).
          final reposterProfile = isRepost ? _profiles[_authorKey(post)] : null;
          // Profil de l'auteur affiché (original si repost).
          final origKey = isRepost ? _origAuthorKey(post) : _authorKey(post);
          final displayProfile = _profiles[origKey];
          final isLegacyKey = origKey.startsWith('u:');
          final origProfileId = isLegacyKey ? null : origKey;
          final isFollowingAuthor = isLegacyKey
              ? _following.contains(originalUid)
              : _followingPids.contains(origKey);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (isRepost) Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 6),
              child: Row(children: [
                const Icon(Icons.repeat_rounded, size: 13, color: _greyC),
                const SizedBox(width: 5),
                Text('${_profileName(reposterProfile)} a republié',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _greyC)),
              ]),
            ),
            _SocialPostCard(
            post: post,
            profile: displayProfile,
            isLiked: _liked.contains(effectiveId),
            isFollowing: isFollowingAuthor,
            isMyPost: originalUid == widget.myUid,
            myUid: widget.myUid,
            onLike: () => _toggleLike(effectiveId),
            onFollow: () => _toggleFollow(originalUid, targetProfileId: origProfileId),
            onDelete: () => _deletePost(postId),
            onComment: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _CommentsSheet(
                postId: effectiveId,
                myUid: widget.myUid,
                postAuthorUid: originalUid,
                onCommentAdded: () => setState(() {
                  final idx = _posts.indexWhere((p) => p['id'] == postId);
                  if (idx >= 0) {
                    _posts[idx]['comment_count'] =
                        (_posts[idx]['comment_count'] as int) + 1;
                  }
                }),
              ),
            ),
          ),
          ]);
        },
      ),
    );
  }
}

// ─── Post card ────────────────────────────────────────────────────────────────

class _SocialPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic>? profile;
  final bool isLiked;
  final bool isFollowing;
  final bool isMyPost;
  final String myUid;
  final VoidCallback onLike;
  final VoidCallback onFollow;
  final VoidCallback onDelete;
  final VoidCallback onComment;

  const _SocialPostCard({
    required this.post,
    required this.profile,
    required this.isLiked,
    required this.isFollowing,
    required this.isMyPost,
    required this.myUid,
    required this.onLike,
    required this.onFollow,
    required this.onDelete,
    required this.onComment,
  });

  @override
  State<_SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<_SocialPostCard> {
  final _supa = Supabase.instance.client;
  bool _showHeart = false;
  String? _boostedUntilOverride;
  bool _isSaved = false;
  bool _isReposted = false;
  int _repostCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _loadRepostCount();
  }

  String get _effectivePostId {
    if (widget.post['_effective_id'] != null) return widget.post['_effective_id'] as String;
    if (widget.post['is_repost'] == true && widget.post['original_post_id'] != null) {
      return widget.post['original_post_id'] as String;
    }
    return widget.post['id'] as String;
  }

  Future<void> _loadSaved() async {
    try {
      final pid = await _activeAuthorProfileId(widget.myUid);
      var q = _supa.from('post_favorites').select('id')
          .eq('uid', widget.myUid).eq('post_id', _effectivePostId);
      if (pid != null) q = q.eq('author_profile_id', pid);
      final row = await q.maybeSingle();
      if (mounted) setState(() => _isSaved = row != null);
    } catch (_) {}
  }

  Future<void> _loadRepostCount() async {
    try {
      final rows = await _supa.from('posts_socialmedia')
          .select('id, uid')
          .eq('original_post_id', _effectivePostId)
          .eq('is_repost', true);
      final list = rows as List;
      if (mounted) setState(() {
        _repostCount = list.length;
        _isReposted = list.any((r) => r['uid'] == widget.myUid);
      });
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    final eid = _effectivePostId;
    HapticFeedback.lightImpact();
    final newVal = !_isSaved;
    setState(() => _isSaved = newVal);
    try {
      final pid = await _activeAuthorProfileId(widget.myUid);
      if (newVal) {
        await _supa.from('post_favorites').insert({
          'uid': widget.myUid, 'post_id': eid,
          if (pid != null) 'author_profile_id': pid,
        });
      } else {
        var d = _supa.from('post_favorites').delete()
            .eq('uid', widget.myUid).eq('post_id', eid);
        if (pid != null) d = d.eq('author_profile_id', pid);
        await d;
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = !newVal);
    }
  }

  void _share() {
    final text = widget.post['texte']?.toString() ?? '';
    final name = _profileName(widget.profile);
    // Lien vers le post : l'original si c'est un repost.
    final shareId = (widget.post['is_repost'] == true
            ? widget.post['original_post_id']
            : (widget.post['_effective_id'] ?? widget.post['id']))
        ?.toString();
    final url = '$kSiteBaseUrl/p/${shareId ?? widget.post['id']}';
    final body = text.isNotEmpty ? '"$text"\n\n— $name sur Pets Social' : '— $name sur Pets Social';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SocialShareSheet(text: '$body\n$url', url: url, nom: name),
    );
  }

  Future<void> _repost() async {
    if (_isReposted) {
      // Annuler la republication
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0C3535),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Annuler la republication ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          content: const Text('Ce post ne sera plus dans le feed de tes abonnés.', style: TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text('Garder', style: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.5)))),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Annuler la repub.', style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent, fontWeight: FontWeight.w700))),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final origId = widget.post['is_repost'] == true
            ? (widget.post['original_post_id'] as String)
            : (widget.post['id'] as String);
        await _supa.from('posts_socialmedia')
            .delete()
            .eq('uid', widget.myUid)
            .eq('original_post_id', origId)
            .eq('is_repost', true);
        setState(() { _isReposted = false; if (_repostCount > 0) _repostCount--; });
        HapticFeedback.lightImpact();
      } catch (_) {}
    } else {
      // Republier (1 seule fois)
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0C3535),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Republier ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          content: const Text('Ce post sera partagé à tes abonnés.', style: TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.5)))),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Republier', style: TextStyle(fontFamily: 'Galey', color: _green, fontWeight: FontWeight.w700))),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final orig = widget.post;
        // Si c'est déjà un repost, pointer vers l'original (pas un repost de repost)
        final origId  = orig['is_repost'] == true ? (orig['original_post_id'] as String) : (orig['id'] as String);
        final origUid = orig['is_repost'] == true ? (orig['original_uid'] as String) : (orig['uid'] as String);
        final myPid = await _activeAuthorProfileId(widget.myUid);
        await _supa.from('posts_socialmedia').insert({
          'uid': widget.myUid,
          if (myPid != null) 'author_profile_id': myPid,
          'texte': orig['texte'],
          'media_url': orig['media_url'],
          'is_repost': true,
          'original_post_id': origId,
          'original_uid': origUid,
        });
        setState(() { _isReposted = true; _repostCount++; });
        HapticFeedback.mediumImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Post republié !', style: TextStyle(fontFamily: 'Galey')),
            backgroundColor: Color(0xFF0C5C6C),
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (_) {}
    }
  }

  void _doubleTapLike() {
    if (!widget.isLiked) widget.onLike();
    HapticFeedback.lightImpact();
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  void _goToProfile() {
    final targetUid = widget.profile?['uid'] as String?;
    if (targetUid == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SocialProfilePage(
        targetUid: targetUid, myUid: widget.myUid,
        targetProfileId: widget.profile?['id'] as String?,
      )));
  }

  void _showReportDialog() {
    final supa = Supabase.instance.client;
    final postId = widget.post['id'] as String;
    final reasons = ['Contenu inapproprié', 'Spam', 'Harcèlement', 'Fausse information', 'Autre'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C3535),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Signaler ce post', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pourquoi signaler ce contenu ?', style: TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            ...reasons.map((r) => GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await supa.from('post_reports').insert({
                    'post_id': postId,
                    'reporter_uid': widget.myUid,
                    'reason': r,
                  });
                } catch (_) {}
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Signalement envoyé, merci.', style: TextStyle(fontFamily: 'Galey')),
                    backgroundColor: Color(0xFF0C5C6C),
                    duration: Duration(seconds: 3),
                  ));
                }
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Text(r, style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 13)),
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  bool _isBoosted(String? until) {
    final raw = _boostedUntilOverride ?? until;
    if (raw == null) return false;
    final dt = DateTime.tryParse(raw);
    return dt != null && dt.isAfter(DateTime.now());
  }

  Future<void> _showBoostDialog() async {
    final supa = Supabase.instance.client;
    final uid = widget.myUid;
    const cost = 50;

    final walletRow = await supa.from('credit_wallets').select().eq('uid', uid).maybeSingle();
    final solde = (walletRow?['solde'] as int?) ?? 0;

    if (!mounted) return;

    if (solde < cost) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1F22),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Icon(Icons.toll_outlined, color: Colors.orangeAccent, size: 36),
            const SizedBox(height: 12),
            const Text('Crédits insuffisants', style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 8),
            Text('Tu as $solde cr. · Boost = $cost cr.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Center(child: Text('Fermer',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        fontSize: 15, color: Colors.white70))),
              ),
            ),
          ]),
        ),
      );
      return;
    }

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: const BoxDecoration(
          color: Color(0xFF0D1F22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFFFFAA00)]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          const Text('Booster ce post', style: TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Ton post sera mis en avant pendant 48h\ndans l\'onglet Découverte.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Coût', style: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
              Text('$cost crédits', style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Solde après', style: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
              Text('${solde - cost} crédits', style: TextStyle(
                  fontFamily: 'Galey',
                  color: (solde - cost) < 50 ? Colors.orangeAccent : _green,
                  fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Center(child: Text('Annuler',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        fontSize: 15, color: Colors.white70))),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFFFFAA00)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF6B00).withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: const Center(child: Text('Booster — 50 cr.',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 15, color: Colors.white))),
              ),
            )),
          ]),
        ]),
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      // Débit atomique côté serveur (RPC SECURITY DEFINER) puis boost.
      final spend = await supa.rpc('credit_spend', params: {
        'p_uid': uid,
        'p_cost': cost,
        'p_motif': 'Boost de post',
        'p_ref_id': widget.post['id'] as String,
      });
      if (!(spend is Map && spend['ok'] == true)) {
        if (mounted) {
          final s = (spend is Map ? spend['solde'] : null) ?? solde;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Crédits insuffisants ($s crédit${s == 1 ? '' : 's'}).',
                style: const TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      await supa.from('posts_socialmedia').update({
        'boosted_until': DateTime.now().add(const Duration(hours: 48)).toIso8601String(),
      }).eq('id', widget.post['id'] as String);
      if (mounted) {
        final until = DateTime.now().add(const Duration(hours: 48)).toIso8601String();
        setState(() => _boostedUntilOverride = until);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Post boosté ! 🚀', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF0C5C6C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur lors du boost', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name         = _profileName(widget.profile);
    final photoUrl     = _profilePhoto(widget.profile);
    final text         = widget.post['texte']?.toString() ?? '';
    final mediaUrl     = widget.post['media_url']?.toString();
    final date         = widget.post['created_at']?.toString() ?? '';
    final likeCount    = widget.post['like_count'] as int? ?? 0;
    final commentCount = widget.post['comment_count'] as int? ?? 0;
    final urls         = _mediaUrls(mediaUrl);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.95), width: 1.5),
            ),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Header (tap → profil) ────────────────────────
                GestureDetector(
                  onTap: _goToProfile,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 10, 0),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _avatarWidget(photoUrl, 20, ringStyle: widget.profile?['_ring'] as String?),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(name,
                                          style: const TextStyle(
                                              fontFamily: 'Galey',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Color(0xFF0D2A2E))),
                                    ),
                                    if (widget.profile?['profile_type'] == 'eleveur') ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [_tealC, Color(0xFF1E7A8C)]), borderRadius: BorderRadius.circular(8)),
                                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.verified, size: 9, color: Colors.white),
                                          SizedBox(width: 3),
                                          Text('Pro', style: TextStyle(fontFamily: 'Galey', fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                                        ]),
                                      ),
                                    ],
                                    if (widget.profile?['is_influencer'] == true) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6E9E57), Color(0xFF0C5C6C)]), shape: BoxShape.circle),
                                        child: const Icon(Icons.auto_awesome, size: 9, color: Colors.white),
                                      ),
                                    ],
                                    if (_isBoosted(widget.post['boosted_until']?.toString())) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.4)),
                                        ),
                                        child: const Text('Boosté', style: TextStyle(
                                              fontFamily: 'Galey', fontSize: 9,
                                              color: Color(0xFFFF6B35), fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ]),
                                  const SizedBox(height: 1),
                                  Text(_fmtDate(date),
                                      style: const TextStyle(
                                          fontFamily: 'Galey', fontSize: 11, color: _greyC)),
                                ]),
                          ),
                          if (!widget.isMyPost)
                            GestureDetector(
                              onTap: widget.onFollow,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: widget.isFollowing ? null : const LinearGradient(colors: [_tealC, _green]),
                                  color: widget.isFollowing ? const Color(0xFFE8F5F0) : null,
                                  borderRadius: BorderRadius.circular(20),
                                  border: widget.isFollowing ? Border.all(color: _tealC.withValues(alpha: 0.35)) : null,
                                  boxShadow: widget.isFollowing ? null : [
                                    BoxShadow(color: _tealC.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))
                                  ],
                                ),
                                child: Text(widget.isFollowing ? 'Suivi ✓' : 'Suivre',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: widget.isFollowing ? _tealC : Colors.white)),
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_horiz, color: _greyC, size: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            onSelected: (val) {
                              if (val == 'delete') { widget.onDelete(); }
                              if (val == 'report') { _showReportDialog(); }
                              if (val == 'boost')  { _showBoostDialog(); }
                            },
                            itemBuilder: (_) => [
                              if (widget.isMyPost) ...[
                                const PopupMenuItem(value: 'boost',
                                    child: Row(children: [
                                      Icon(Icons.rocket_launch_outlined, color: Color(0xFF0C5C6C), size: 18),
                                      SizedBox(width: 8),
                                      Text('Booster ce post', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C))),
                                    ])),
                                const PopupMenuItem(value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                      SizedBox(width: 8),
                                      Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
                                    ])),
                              ],
                              if (!widget.isMyPost)
                                const PopupMenuItem(value: 'report',
                                    child: Row(children: [
                                      Icon(Icons.flag_outlined, color: Colors.orange, size: 18),
                                      SizedBox(width: 8),
                                      Text('Signaler', style: TextStyle(fontFamily: 'Galey', color: Colors.orange)),
                                    ])),
                            ],
                          ),
                        ]),
                  ),
                ),

                // ── Texte ────────────────────────────────────────────
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Text(text, style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 14,
                        color: Color(0xFF0D2A2E), height: 1.5)),
                  ),

                // ── Animaux tagués ───────────────────────────────────
                _TaggedAnimalsRow(
                    ids: _taggedIds(widget.post['tagged_animal_ids'])),

                // ── Photo(s) double-tap to like ───────────────────
                if (urls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onDoubleTap: _doubleTapLike,
                    child: _ImagesDisplay(urls: urls),
                  ),
                ],

                // ── « Aimé par … » (tap → liste des personnes) ───────
                if (likeCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: GestureDetector(
                      onTap: () => _showPostLikes(context, widget.post['id'] as String, widget.myUid),
                      child: Text(
                        likeCount == 1 ? '1 j’aime' : '$likeCount j’aime',
                        style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 12,
                            fontWeight: FontWeight.w600, color: Color(0xFF6B7A72)),
                      ),
                    ),
                  ),

                // ── Actions ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Row(children: [
                    _ActionBtn(
                      icon: widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      label: likeCount > 0 ? '$likeCount' : '',
                      onLongPress: likeCount > 0
                          ? () => _showPostLikes(context, widget.post['id'] as String, widget.myUid)
                          : null,
                      color: widget.isLiked ? const Color(0xFFE03055) : _greyC,
                      onTap: widget.onLike,
                    ),
                    _ActionBtn(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: commentCount > 0 ? '$commentCount' : '',
                      color: _greyC,
                      onTap: widget.onComment,
                    ),
                    _ActionBtn(
                      icon: Icons.repeat_rounded,
                      label: _repostCount > 0 ? '$_repostCount' : '',
                      color: _isReposted ? _tealC : _greyC,
                      onTap: _repost,
                    ),
                    _ActionBtn(
                      icon: _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      label: '',
                      color: _isSaved ? _tealC : _greyC,
                      onTap: _toggleSave,
                    ),
                    _ActionBtn(
                      icon: Icons.ios_share_rounded,
                      label: '',
                      color: _greyC,
                      onTap: _share,
                    ),
                  ]),
                ),
              ]),
              // ── Cœur double-tap animation ─────────────────────────
              if (_showHeart)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _showHeart ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: AnimatedScale(
                          scale: _showHeart ? 1.0 : 0.4,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.elasticOut,
                          child: const Icon(Icons.favorite_rounded,
                              color: Colors.white, size: 90,
                              shadows: [Shadow(color: Colors.black38, blurRadius: 20)]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Ligne « animaux tagués » sous une publication ───────────────────────────

class _TaggedAnimalsRow extends StatefulWidget {
  final List<String> ids;
  const _TaggedAnimalsRow({required this.ids});
  @override
  State<_TaggedAnimalsRow> createState() => _TaggedAnimalsRowState();
}

class _TaggedAnimalsRowState extends State<_TaggedAnimalsRow> {
  Map<String, Map<String, dynamic>> _animals = {};

  @override
  void initState() {
    super.initState();
    if (widget.ids.isNotEmpty) {
      _resolveTaggedAnimals(widget.ids).then((m) {
        if (mounted) setState(() => _animals = m);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ids.isEmpty || _animals.isEmpty) return const SizedBox.shrink();
    final ordered = widget.ids.where(_animals.containsKey).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Wrap(
        spacing: 6, runSpacing: 6,
        children: [
          for (final id in ordered)
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AnimalTaggedPostsPage(
                  animalId: id,
                  animalName: (_animals[id]?['nom'] ?? 'cet animal').toString(),
                ),
              )),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F1EC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBFDDD1)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ClipOval(
                    child: SizedBox(
                      width: 18, height: 18,
                      child: (_animals[id]?['photo_url'] as String?)?.isNotEmpty == true
                          ? Image.network(_animals[id]!['photo_url'] as String,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.pets, size: 14, color: _tealC))
                          : const Icon(Icons.pets, size: 14, color: _tealC),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text((_animals[id]?['nom'] ?? '').toString(),
                      style: const TextStyle(
                          fontFamily: 'Galey', fontSize: 12,
                          fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Publications où un animal est tagué ─────────────────────────────────────

class AnimalTaggedPostsPage extends StatelessWidget {
  final String animalId;
  final String animalName;
  const AnimalTaggedPostsPage(
      {super.key, required this.animalId, required this.animalName});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: _bgGrad),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Pets Social',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white54)),
                    Text('Publications où $animalName est tagué',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 15,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: _FeedList(type: 'animal', animalId: animalId, myUid: myUid),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Mes posts ────────────────────────────────────────────────────────────────

class _MyPostsList extends StatefulWidget {
  final String myUid;
  final String? myProfileId;
  final VoidCallback onRefresh;
  const _MyPostsList(
      {super.key, required this.myUid, this.myProfileId, required this.onRefresh});
  @override
  State<_MyPostsList> createState() => _MyPostsListState();
}

class _MyPostsListState extends State<_MyPostsList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => false;

  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _myProfile;
  Map<String, Map<String, dynamic>> _origProfiles = {}; // auteurs originaux des reposts
  final Map<String, int> _likeCounts = {}; // post_id -> nb de j'aime
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // Scopé au profil ACTIF : ses posts + son identité.
      final pid = widget.myProfileId ?? await _activeAuthorProfileId(widget.myUid);
      final postsBase = _supa.from('posts_socialmedia').select();
      final postsQ = (pid != null
              ? postsBase.eq('author_profile_id', pid)
              : postsBase.eq('uid', widget.myUid))
          .order('created_at', ascending: false);
      final profQ = pid != null
          ? _supa.from('user_profiles').select(_kAuthorCols).eq('id', pid).maybeSingle()
          : _supa.from('user_profiles')
              .select(_kAuthorCols).eq('uid', widget.myUid).eq('profile_type', 'particulier').maybeSingle();
      final results = await Future.wait([postsQ, profQ]);
      final posts = (results[0] as List).cast<Map<String, dynamic>>();

      // Reposts : on affiche le contenu et l'auteur du post ORIGINAL, pas la
      // ligne repost (vide) sous mon nom.
      final origIds = posts
          .where((p) => p['is_repost'] == true && p['original_post_id'] != null)
          .map((p) => p['original_post_id'] as String).toSet().toList();
      final origProfiles = <String, Map<String, dynamic>>{};
      if (origIds.isNotEmpty) {
        final origs = await _supa.from('posts_socialmedia')
            .select('id, uid, texte, media_url, author_profile_id').inFilter('id', origIds);
        final byId = {for (final o in origs as List) o['id'] as String: o as Map};
        final origPids = <String>{};
        for (final p in posts) {
          if (p['is_repost'] != true) continue;
          final o = byId[p['original_post_id']];
          if (o == null) continue;
          p['_orig_texte']     = o['texte'];
          p['_orig_media_url']  = o['media_url'];
          p['_orig_author_profile_id'] = o['author_profile_id'];
          p['original_uid']     = o['uid'];
          final apid = (o['author_profile_id'] as String?) ?? '';
          if (apid.isNotEmpty) origPids.add(apid);
        }
        if (origPids.isNotEmpty) {
          final profs = await _supa.from('user_profiles')
              .select(_kAuthorCols).inFilter('id', origPids.toList());
          for (final r in profs as List) {
            origProfiles[r['id'] as String] = Map<String, dynamic>.from(r as Map);
          }
        }
      }

      // Nombre de j'aime par post (pour la ligne « N j'aime » tappable).
      _likeCounts.clear();
      final postIds = posts.map((p) => p['id'] as String).toList();
      if (postIds.isNotEmpty) {
        try {
          final likes = await _supa.from('post_likes')
              .select('post_id').inFilter('post_id', postIds) as List;
          for (final l in likes) {
            final pid = l['post_id'] as String;
            _likeCounts[pid] = (_likeCounts[pid] ?? 0) + 1;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _posts        = posts;
          _myProfile    = results[1] as Map<String, dynamic>?;
          _origProfiles = origProfiles;
          _loading      = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer ?',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('posts_socialmedia').delete().eq('id', postId);
    setState(() => _posts.removeWhere((p) => p['id'] == postId));
    widget.onRefresh();
  }

  Future<void> _edit(Map<String, dynamic> post) async {
    final ctrl =
        TextEditingController(text: post['texte']?.toString() ?? '');
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPostSheet(controller: ctrl),
    );
    if (saved == null || !mounted) return;
    try {
      await _supa
          .from('posts_socialmedia')
          .update({'texte': saved}).eq('id', post['id'].toString());
      setState(() {
        final i = _posts.indexWhere((p) => p['id'] == post['id']);
        if (i >= 0) _posts[i] = {..._posts[i], 'texte': saved};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur lors de la modification: $e',
            style: const TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white54));
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_tealC, _green]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _tealC.withValues(alpha: 0.35), blurRadius: 24)
              ],
            ),
            child: const Icon(Icons.photo_library_outlined,
                size: 52, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text('Vous n\'avez aucune publication',
              style: TextStyle(
                  fontFamily: 'Galey',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _tealC,
      backgroundColor: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final post     = _posts[i];
          final isRepost = post['is_repost'] == true;
          final origProf = isRepost ? _origProfiles[post['_orig_author_profile_id']] : null;
          final text     = (isRepost ? post['_orig_texte'] : post['texte'])?.toString() ?? '';
          final mediaUrl = (isRepost ? post['_orig_media_url'] : post['media_url'])?.toString();
          final date     = post['created_at']?.toString() ?? '';
          final headName  = isRepost ? _profileName(origProf) : _profileName(_myProfile);
          final headPhoto = isRepost ? _profilePhoto(origProf) : _profilePhoto(_myProfile);
          final myName = headName;
          final myPhoto = headPhoto;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (isRepost) Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 6),
            child: Row(children: const [
              Icon(Icons.repeat_rounded, size: 13, color: _greyC),
              SizedBox(width: 5),
              Text('Vous avez republié',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _greyC)),
            ]),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 5))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.95),
                        width: 1.5),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 10, 0),
                          child: Row(children: [
                            _avatarWidget(myPhoto, 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(myName,
                                        style: const TextStyle(
                                            fontFamily: 'Galey',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF0D2A2E))),
                                    const SizedBox(height: 1),
                                    Text(_fmtDate(date),
                                        style: TextStyle(
                                            fontFamily: 'Galey',
                                            fontSize: 11,
                                            color: _greyC)),
                                  ]),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz,
                                  color: _greyC, size: 20),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              onSelected: (val) {
                                if (val == 'edit') { _edit(post); }
                                if (val == 'delete') { _delete(post['id'] as String); }
                              },
                              itemBuilder: (_) => [
                                if (!isRepost)
                                  PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        Icon(Icons.edit_outlined,
                                            color: _tealC, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('Modifier',
                                            style: TextStyle(
                                                fontFamily: 'Galey')),
                                      ])),
                                PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      const Icon(Icons.delete_outline,
                                          color: Colors.red, size: 18),
                                      const SizedBox(width: 8),
                                      Text(isRepost ? 'Retirer le repost' : 'Supprimer',
                                          style: const TextStyle(
                                              fontFamily: 'Galey',
                                              color: Colors.red)),
                                    ])),
                              ],
                            ),
                          ]),
                        ),
                        if (text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                            child: Text(text,
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 14,
                                    color: Color(0xFF0D2A2E),
                                    height: 1.5)),
                          ),
                        if (mediaUrl != null) ...[
                          const SizedBox(height: 12),
                          _ImagesDisplay(urls: _mediaUrls(mediaUrl)),
                        ],
                        Builder(builder: (ctx) {
                          final lc = _likeCounts[post['id']] ?? 0;
                          if (lc == 0) return const SizedBox(height: 14);
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: GestureDetector(
                              onTap: () => _showPostLikes(ctx, post['id'] as String, widget.myUid),
                              child: Row(children: [
                                const Icon(Icons.favorite_rounded, size: 14, color: Color(0xFFE03055)),
                                const SizedBox(width: 6),
                                Text(lc == 1 ? '1 j’aime' : '$lc j’aime',
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                                        fontWeight: FontWeight.w600, color: Color(0xFF6B7A72))),
                              ]),
                            ),
                          );
                        }),
                      ]),
                ),
              ),
            ),
          ),
          ]);
        },
      ),
    );
  }
}

// ─── Edit post sheet ──────────────────────────────────────────────────────────

class _EditPostSheet extends StatelessWidget {
  final TextEditingController controller;
  const _EditPostSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          const Text('Modifier la description',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.white)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context, controller.text.trim()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_tealC, _green]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: _tealC.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: const Text('Sauvegarder',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: TextField(
              controller: controller,
              maxLines: 5,
              minLines: 2,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Description...',
                hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.45)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _tealC, width: 1.5)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Action button ────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap,
      this.onLongPress});

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: color),
              if (label.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ),
      );
}

// ─── Images display (single or carousel) ─────────────────────────────────────

class _ImagesDisplay extends StatefulWidget {
  final List<String> urls;
  const _ImagesDisplay({required this.urls});
  @override
  State<_ImagesDisplay> createState() => _ImagesDisplayState();
}

class _ImagesDisplayState extends State<_ImagesDisplay> {
  int _page = 0;

  Widget _img(String url) => CachedNetworkImage(
        imageUrl: url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFD4EDE8), Color(0xFFD8EDCC)])),
          child: const Center(child: CircularProgressIndicator(color: _tealC, strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          color: const Color(0xFFF4F6F8),
          child: const Icon(Icons.broken_image_outlined, color: _greyC, size: 40)),
      );

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(12));
    const ratio  = 1.0; // Carré 1:1 — BoxFit.cover centre et remplit parfaitement

    if (widget.urls.length == 1) {
      return GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PhotoViewScreen(urls: widget.urls, initialIndex: 0))),
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(aspectRatio: ratio, child: _img(widget.urls.first)),
        ),
      );
    }

    return Stack(children: [
      ClipRRect(
        borderRadius: radius,
        child: AspectRatio(
          aspectRatio: ratio,
          child: PageView.builder(
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _PhotoViewScreen(urls: widget.urls, initialIndex: i))),
              child: _img(widget.urls[i]),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 10, left: 0, right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.urls.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _page ? 16 : 6, height: 6,
            decoration: BoxDecoration(
              color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(3),
            ),
          )),
        ),
      ),
    ]);
  }
}

// ─── Full-screen photo viewer ─────────────────────────────────────────────────

class _PhotoViewScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _PhotoViewScreen({required this.urls, this.initialIndex = 0});
  @override
  State<_PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<_PhotoViewScreen> {
  late int _page;
  @override
  void initState() { super.initState(); _page = widget.initialIndex; }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
              const Spacer(),
              if (widget.urls.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${_page + 1} / ${widget.urls.length}',
                      style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: widget.initialIndex),
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => PhotoView(
          imageProvider: CachedNetworkImageProvider(widget.urls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
          basePosition: Alignment.center,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          loadingBuilder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
          errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40)),
        ),
      ),
    );
  }
}

// ─── Comments sheet ───────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final String postId;
  final String myUid;
  final String postAuthorUid;
  final VoidCallback onCommentAdded;
  const _CommentsSheet(
      {required this.postId,
      required this.myUid,
      required this.postAuthorUid,
      required this.onCommentAdded});
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _supa = Supabase.instance.client;
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _comments  = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  bool _loading = true;
  bool _sending = false;
  String? _replyToName;
  String? _replyToId;
  Set<String> _following = {};
  String? _myProfileId;

  @override
  void initState() {
    super.initState();
    _load();
    _activeAuthorProfileId(widget.myUid).then((id) { if (mounted) _myProfileId = id; });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final rows = await _supa.from('post_comments').select()
        .eq('post_id', widget.postId).order('created_at') as List;
    _following = await _activeFollowingUids(widget.myUid);
    if (rows.isNotEmpty) {
      _profiles = await _resolveAuthors(rows);
    }
    if (mounted) {
      setState(() {
        _comments = rows.cast<Map<String, dynamic>>();
        _loading  = false;
      });
    }
  }

  // Regroupe : commentaire racine puis ses réponses via parent_id
  // Fallback @mention si parent_id absent (anciens commentaires)
  List<Map<String, dynamic>> _sortedComments() {
    final hasParentId = _comments.any((c) => c.containsKey('parent_id'));
    if (hasParentId) {
      // Mode parent_id : fiable et précis
      final roots    = _comments.where((c) => c['parent_id'] == null).toList();
      final replyMap = <String, List<Map<String, dynamic>>>{};
      for (final c in _comments) {
        final pid = c['parent_id'] as String?;
        if (pid != null) replyMap.putIfAbsent(pid, () => []).add(c);
      }
      final result = <Map<String, dynamic>>[];
      for (final root in roots) {
        result.add(root);
        result.addAll(replyMap[root['id'] as String? ?? ''] ?? []);
      }
      return result;
    }
    // Fallback @mention (compatibilité anciens commentaires)
    final roots   = _comments.where((c) => !(c['texte']?.toString() ?? '').startsWith('@')).toList();
    final replies = _comments.where((c) =>  (c['texte']?.toString() ?? '').startsWith('@')).toList();
    final result  = <Map<String, dynamic>>[];
    for (final root in roots) {
      result.add(root);
      final authorName = _profileName(_profiles[_authorKey(root)]);
      final matched = replies
          .where((r) => (r['texte']?.toString() ?? '').startsWith('@$authorName ') ||
                        (r['texte']?.toString() ?? '') == '@$authorName')
          .toList();
      result.addAll(matched);
      for (final m in matched) { replies.remove(m); }
    }
    result.addAll(replies);
    return result;
  }

  Future<void> _deleteComment(String commentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFF0C3535),
        title: const Text('Supprimer ce commentaire ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.55)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _supa.from('post_comments').delete().eq('id', commentId);
    if (mounted) {
      setState(() => _comments.removeWhere((c) => c['id'] == commentId));
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final pid = _myProfileId ?? await _activeAuthorProfileId(widget.myUid);
      final inserted = await _supa
          .from('post_comments')
          .insert({
            'post_id': widget.postId,
            'uid': widget.myUid,
            if (pid != null) 'author_profile_id': pid,
            'texte': text,
            if (_replyToId != null) 'parent_id': _replyToId,
          })
          .select()
          .single();
      _ctrl.clear();
      widget.onCommentAdded();
      if (mounted) {
        setState(() {
          _comments.add(inserted);
          _sending = false;
          _replyToName = null;
          _replyToId = null;
        });
      }
      // Notification push à l'auteur du post — fire-and-forget
      _sendSocialNotif(
        supa: _supa,
        actorUid: widget.myUid,
        postId: widget.postId,
        targetUid: widget.postAuthorUid,
        type: 'social_comment',
        titleSuffix: 'a commenté votre post',
        body: text.length > 60 ? '${text.substring(0, 60)}…' : text,
      );
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const SizedBox(width: 38),
            Expanded(
              child: ShaderMask(
                shaderCallback: (b) =>
                    const LinearGradient(colors: [_tealC, _green]).createShader(b),
                child: const Text('Commentaires',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: Colors.white)),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white54))
              : _comments.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_tealC, _green]),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text('Aucun commentaire',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 14)),
                    ]))
                  : Builder(builder: (ctx) {
                      final sorted = _sortedComments();
                      return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: sorted.length,
                      itemBuilder: (_, i) {
                        final c       = sorted[i];
                        final prof    = _profiles[_authorKey(c)];
                        final photo   = _profilePhoto(prof);
                        final cUid    = c['uid'] as String;
                        final text    = c['texte']?.toString() ?? '';
                        final isReply = c['parent_id'] != null || text.startsWith('@');

                        // Parse @mention for rich display
                        Widget commentText() {
                          if (!isReply) {
                            return Text(text,
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 13,
                                    color: Colors.white));
                          }
                          final sp = text.indexOf(' ');
                          if (sp == -1) {
                            return Text(text,
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 13,
                                    color: _green,
                                    fontWeight: FontWeight.w700));
                          }
                          return RichText(
                            text: TextSpan(children: [
                              TextSpan(
                                  text: '${text.substring(0, sp + 1)} ',
                                  style: const TextStyle(
                                      fontFamily: 'Galey',
                                      fontSize: 13,
                                      color: _green,
                                      fontWeight: FontWeight.w700)),
                              TextSpan(
                                  text: text.substring(sp + 1),
                                  style: const TextStyle(
                                      fontFamily: 'Galey',
                                      fontSize: 13,
                                      color: Colors.white)),
                            ]),
                          );
                        }

                        return Padding(
                          padding: EdgeInsets.only(
                              left: isReply ? 28 : 0,
                              top: i > 0 ? (isReply ? 6 : 10) : 0,
                              bottom: 0),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thread connector for replies
                                if (isReply)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 13, bottom: 4),
                                    child: Row(children: [
                                      Container(
                                        width: 1.5,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _tealC
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                      Container(
                                        width: 10,
                                        height: 1.5,
                                        decoration: BoxDecoration(
                                          color: _tealC
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                    ]),
                                  ),
                                // Comment row
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _avatarWidget(
                                          photo, isReply ? 12 : 15,
                                          ringStyle: prof?['_ring'] as String?),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          onLongPress: cUid == widget.myUid
                                              ? () => _deleteComment(c['id'] as String)
                                              : null,
                                          child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: 6, sigmaY: 6),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withValues(
                                                        alpha: isReply
                                                            ? 0.07
                                                            : 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.12)),
                                              ),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Row(children: [
                                                      Text(
                                                          _profileName(prof),
                                                          style: TextStyle(
                                                              fontFamily: 'Galey',
                                                              fontWeight: FontWeight.w700,
                                                              fontSize: isReply ? 11 : 12,
                                                              color: _green)),
                                                      if (prof?['is_influencer'] == true) ...[
                                                        const SizedBox(width: 4),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6E9E57), Color(0xFF0C5C6C)]), borderRadius: BorderRadius.circular(6)),
                                                          child: const Icon(Icons.auto_awesome, size: 8, color: Colors.white),
                                                        ),
                                                      ],
                                                    ]),
                                                    const SizedBox(height: 3),
                                                    commentText(),
                                                  ]),
                                            ),
                                          ),
                                        ),
                                        ),
                                      ),
                                      if (cUid != widget.myUid &&
                                          !_following.contains(cUid))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8, top: 4),
                                          child: GestureDetector(
                                            onTap: () async {
                                              await _insertFollow(widget.myUid, cUid);
                                              if (mounted) {
                                                setState(() =>
                                                    _following.add(cUid));
                                              }
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5),
                                              decoration: BoxDecoration(
                                                gradient:
                                                    const LinearGradient(
                                                        colors: [
                                                      _tealC,
                                                      _green
                                                    ]),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                      color: _tealC
                                                          .withValues(
                                                              alpha: 0.35),
                                                      blurRadius: 6,
                                                      offset:
                                                          const Offset(0, 2))
                                                ],
                                              ),
                                              child: const Text('Suivre',
                                                  style: TextStyle(
                                                      fontFamily: 'Galey',
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white)),
                                            ),
                                          ),
                                        ),
                                    ]),
                                // "Répondre" + hint suppression
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: isReply ? 20 : 40, top: 5),
                                  child: Row(children: [
                                    GestureDetector(
                                      onTap: () {
                                        final name = _profileName(prof);
                                        setState(() {
                                          _replyToName = name;
                                          _replyToId   = c['id'] as String?;
                                        });
                                        _ctrl.text = '@$name ';
                                        _ctrl.selection =
                                            TextSelection.fromPosition(
                                                TextPosition(offset: _ctrl.text.length));
                                      },
                                      child: Text('Répondre',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 11,
                                              color: Colors.white.withValues(alpha: 0.40))),
                                    ),
                                    if ((c['created_at'] as String?) != null)
                                      Text('  · ${_fmtDate(c['created_at'] as String)}',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 10,
                                              color: Colors.white.withValues(alpha: 0.30))),
                                    if (cUid == widget.myUid)
                                      Text('  · Maintenir pour supprimer',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 10,
                                              color: Colors.white.withValues(alpha: 0.22))),
                                  ]),
                                ),
                              ]),
                        );
                      },
                    );
                    }),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.15),
            border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_replyToName != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                decoration: BoxDecoration(
                  color: _tealC.withValues(alpha: 0.18),
                  border: Border(
                      bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(children: [
                  const Icon(Icons.reply_rounded, size: 13, color: _green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Répondre à @$_replyToName',
                        style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 12, color: _green)),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() { _replyToName = null; _replyToId = null; _ctrl.clear(); });
                    },
                    child: const Icon(Icons.close_rounded,
                        size: 15, color: Colors.white54),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 14,
                            color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Ajouter un commentaire...',
                          hintStyle: TextStyle(
                              fontFamily: 'Galey',
                              color: Colors.white.withValues(alpha: 0.45)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_tealC, _green]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: _tealC.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Create post sheet ────────────────────────────────────────────────────────

class _CreatePostSheet extends StatefulWidget {
  final String myUid;
  final VoidCallback onPosted;
  const _CreatePostSheet({required this.myUid, required this.onPosted});
  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _supa   = Supabase.instance.client;
  final _ctrl   = TextEditingController();
  final _images = <File>[];
  bool  _posting = false;
  int   _charCount = 0;
  String? _myProfileId;
  String? _myProfileName;
  String? _myProfileType;

  // Animaux du compte que l'on peut taguer sur la publication.
  List<Map<String, dynamic>> _myAnimals = [];
  final Set<String> _taggedAnimalIds = {};

  static const _maxChars = 2000;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() { if (mounted) setState(() => _charCount = _ctrl.text.length); });
    _loadTaggableAnimals(widget.myUid).then((list) {
      if (mounted) setState(() => _myAnimals = list);
    });
    _activeAuthorProfileId(widget.myUid).then((id) async {
      if (!mounted || id == null) return;
      _myProfileId = id;
      try {
        final r = await _supa.from('user_profiles')
            .select('firstname, lastname, nom, profile_type, social_pseudo').eq('id', id).maybeSingle();
        if (mounted && r != null) {
          setState(() {
            _myProfileType = r['profile_type'] as String?;
            _myProfileName = _profileName(Map<String, dynamic>.from(r));
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _pickImages(ImageSource source) async {
    if (source == ImageSource.camera) {
      final xFile = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 1080);
      if (xFile == null || !mounted) return;
      // Ouvre le recadrage immédiatement après la prise de vue
      final cropped = await _cropImage(xFile.path);
      if (cropped != null && mounted) setState(() => _images.add(File(cropped.path)));
    } else {
      final files = await ImagePicker()
          .pickMultiImage(imageQuality: 90, maxWidth: 1080);
      if (files.isNotEmpty && mounted) {
        // Ajout direct — le crop est accessible sur chaque miniature
        setState(() => _images.addAll(files.map((f) => File(f.path))));
      }
    }
  }

  Future<CroppedFile?> _cropImage(String sourcePath) => ImageCropper().cropImage(
    sourcePath: sourcePath,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Recadrer',
        toolbarColor: const Color(0xFF0C3535),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: const Color(0xFF6E9E57),
        initAspectRatio: CropAspectRatioPreset.square,
        lockAspectRatio: false,
        hideBottomControls: false,
        aspectRatioPresets: [
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9,
        ],
      ),
      IOSUiSettings(
        title: 'Recadrer',
        aspectRatioLockEnabled: false,
        resetAspectRatioEnabled: true,
        aspectRatioPickerButtonHidden: false,
        aspectRatioPresets: [
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9,
        ],
      ),
    ],
  );

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _images.isEmpty) return;
    setState(() => _posting = true);
    try {
      final urls = <String>[];
      for (final img in _images) {
        final compressed = await FlutterImageCompress.compressWithFile(
          img.path, quality: 72, minWidth: 1080, minHeight: 1080, keepExif: false,
        );
        final bytes = compressed ?? await img.readAsBytes();
        final ext  = 'jpg';
        final path = '${widget.myUid}/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.$ext';
        await _supa.storage.from('social').uploadBinary(
              path, bytes,
              fileOptions: const FileOptions(contentType: 'image/jpg', upsert: false),
            );
        urls.add(_supa.storage.from('social').getPublicUrl(path));
      }
      final mediaValue = urls.isEmpty
          ? null
          : urls.length == 1
              ? urls.first
              : jsonEncode(urls);
      final pid = _myProfileId ?? await _activeAuthorProfileId(widget.myUid);
      await _supa.from('posts_socialmedia').insert({
        'uid': widget.myUid,
        if (pid != null) 'author_profile_id': pid,
        if (text.isNotEmpty) 'texte': text,
        if (mediaValue != null) 'media_url': mediaValue,
        if (_taggedAnimalIds.isNotEmpty)
          'tagged_animal_ids': _taggedAnimalIds.toList(),
      });
      if (mounted) {
        Navigator.pop(context);
        await Future.delayed(const Duration(milliseconds: 400));
        widget.onPosted();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur: $e',
                style: const TextStyle(fontFamily: 'Galey')),
            duration: const Duration(seconds: 8)));
      }
    }
  }

  int _imgPage = 0;

  @override
  Widget build(BuildContext context) {
    final bottom   = MediaQuery.of(context).viewInsets.bottom;
    final hasImgs  = _images.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 40),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // ── Handle ───────────────────────────────────────────────
        const SizedBox(height: 12),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),

        // ── Header : titre + bouton Publier ──────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            ShaderMask(
              shaderCallback: (b) =>
                  const LinearGradient(colors: [_tealC, _green]).createShader(b),
              child: const Text('Nouvelle publication',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
            ),
            const Spacer(),
            if (_posting)
              const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
            else
              GestureDetector(
                onTap: _post,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_tealC, _green]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: _tealC.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: const Text('Publier',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Aperçu images EN HAUT — style Instagram ───────────────
        if (hasImgs) ...[
          Stack(children: [
            // PageView des images
            SizedBox(
              height: 300,
              child: PageView.builder(
                itemCount: _images.length,
                onPageChanged: (i) => setState(() => _imgPage = i),
                itemBuilder: (_, i) => Stack(fit: StackFit.expand, children: [
                  Image.file(_images[i], fit: BoxFit.cover),
                  // Dégradé haut (pour les boutons)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.center,
                          colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  // Dégradé bas (pour les indicateurs)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter, end: Alignment.center,
                          colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  // Supprimer (haut-gauche)
                  Positioned(
                    top: 12, left: 12,
                    child: GestureDetector(
                      onTap: () => setState(() { _images.removeAt(i); if (_imgPage >= _images.length && _imgPage > 0) _imgPage--; }),
                      child: Container(
                        width: 32, height: 32,
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  // Recadrer (haut-droite)
                  Positioned(
                    top: 12, right: 12,
                    child: GestureDetector(
                      onTap: () async {
                        final cropped = await _cropImage(_images[i].path);
                        if (cropped != null && mounted) setState(() => _images[i] = File(cropped.path));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.crop, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Recadrer', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            // Indicateurs de pages (multi-images)
            if (_images.length > 1)
              Positioned(
                bottom: 10, left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_images.length, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _imgPage ? 16 : 6, height: 6,
                    decoration: BoxDecoration(
                      color: i == _imgPage ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )),
                ),
              ),
          ]),
        ],

        // ── Contenu scrollable : profil + légende ─────────────────
        SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottom + 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // "Publier en tant que"
              if (_myProfileName != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Icon(
                      _myProfileType != null && _myProfileType != 'particulier'
                          ? Icons.storefront_outlined : Icons.person_outline,
                      size: 14, color: Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Publier en tant que $_myProfileName',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white38)),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 12),

              // Champ de texte
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: TextField(
                      controller: _ctrl,
                      maxLines: hasImgs ? 4 : 10,
                      minLines: hasImgs ? 3 : 6,
                      maxLength: _maxChars,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: hasImgs
                            ? 'Ajoutez une légende…'
                            : 'Partagez quelque chose avec la communauté…',
                        hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.40)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.10),
                        counterStyle: TextStyle(
                            fontFamily: 'Galey', fontSize: 11,
                            color: _charCount > _maxChars * 0.9 ? Colors.orangeAccent : Colors.white38),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _tealC, width: 1.5)),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),

        // ── Chips animaux tagués ──────────────────────────────────
        if (_taggedAnimalIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in _myAnimals.where((a) => _taggedAnimalIds.contains(a['id'])))
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                    avatar: const Icon(Icons.pets, size: 14, color: _green),
                    label: Text((a['nom'] ?? '').toString(),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white)),
                    deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white70),
                    onDeleted: () => setState(() => _taggedAnimalIds.remove(a['id'])),
                  ),
              ]),
            ),
          ),

        // ── Barre médias en bas ───────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
          ),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _iconBtn(Icons.photo_library_outlined, 'Galerie', () => _pickImages(ImageSource.gallery)),
                  const SizedBox(width: 10),
                  _iconBtn(Icons.camera_alt_outlined, 'Photo', () => _pickImages(ImageSource.camera)),
                  if (_myAnimals.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _iconBtn(
                      Icons.pets_outlined,
                      _taggedAnimalIds.isEmpty ? 'Taguer' : 'Taguer (${_taggedAnimalIds.length})',
                      _openAnimalTagSheet,
                    ),
                  ],
                ]),
              ),
            ),
            if (hasImgs) ...[
              const SizedBox(width: 8),
              Text('${_images.length} / 10',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: _green),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Future<void> _openAnimalTagSheet() async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnimalTagSheet(
        animals: _myAnimals,
        selected: Set<String>.from(_taggedAnimalIds),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _taggedAnimalIds
          ..clear()
          ..addAll(result);
      });
    }
  }
}

// ─── Feuille de sélection des animaux à taguer ───────────────────────────────

class _AnimalTagSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final Set<String> selected;
  const _AnimalTagSheet({required this.animals, required this.selected});
  @override
  State<_AnimalTagSheet> createState() => _AnimalTagSheetState();
}

class _AnimalTagSheetState extends State<_AnimalTagSheet> {
  late final Set<String> _sel = Set<String>.from(widget.selected);
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.animals;
    return widget.animals.where((a) {
      final hay = [a['nom'], a['espece'], a['race']]
          .map((v) => (v ?? '').toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 36, height: 4,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_tealC, _green]),
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Text('Taguer mes animaux',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context, _sel),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_tealC, _green]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('OK',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Rechercher un animal…',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white38),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
              suffixIcon: _query.isEmpty ? null : IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                onPressed: () => setState(() { _query = ''; _searchCtrl.clear(); }),
              ),
              isDense: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text('Aucun animal',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white38)),
          ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final a = filtered[i];
              final id = a['id'] as String;
              final checked = _sel.contains(id);
              final photo = (a['photo_url'] as String?) ?? '';
              final sub = [a['espece'], a['race']]
                  .where((v) => v != null && v.toString().isNotEmpty)
                  .join(' · ');
              return ListTile(
                onTap: () => setState(() =>
                    checked ? _sel.remove(id) : _sel.add(id)),
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white12,
                  backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                  child: photo.isEmpty
                      ? const Icon(Icons.pets, size: 18, color: Colors.white70)
                      : null,
                ),
                title: Text((a['nom'] ?? 'Sans nom').toString(),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: sub.isEmpty ? null : Text(sub,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white38)),
                trailing: Icon(
                  checked ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: checked ? _green : Colors.white30,
                ),
              );
            },
          ),
        ),
      ]),
    ),
    );
  }
}


// ─── Search sheet ─────────────────────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  final String myUid;
  const _SearchSheet({required this.myUid});
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _supa    = Supabase.instance.client;
  final _ctrl    = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Set<String> _following = {};
  Map<String, String?> _rings = {}; // uid → ring style
  bool  _searching = false;
  Timer? _debounce;

  @override
  void initState() { super.initState(); _loadFollowing(); }

  @override
  void dispose() { _ctrl.dispose(); _debounce?.cancel(); super.dispose(); }

  Future<void> _loadFollowing() async {
    if (widget.myUid.isEmpty) return;
    try {
      final set = await _activeFollowingUids(widget.myUid);
      if (mounted) setState(() => _following = set);
    } catch (_) {}
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _doSearch(q.trim()));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted) return;
    try {
      // Particuliers + profils pro/éleveur (uniquement ceux qui ont déjà publié
      // → réellement présents sur Pets Social).
      final rows = await _supa
          .from('user_profiles')
          .select(_kAuthorCols)
          .or('firstname.ilike.%$q%,lastname.ilike.%$q%,nom.ilike.%$q%')
          .inFilter('profile_type', ['particulier', 'eleveur', 'association',
            'veterinaire', 'sante', 'education', 'garde', 'toilettage', 'photographe'])
          .neq('uid', widget.myUid)
          .limit(30);
      var results = (rows as List).cast<Map<String, dynamic>>();

      final proIds = results
          .where((r) => r['profile_type'] != 'particulier')
          .map((r) => r['id'] as String).toList();
      if (proIds.isNotEmpty) {
        final posted = await _supa.from('posts_socialmedia')
            .select('author_profile_id').inFilter('author_profile_id', proIds);
        final activePro = {for (final p in posted as List) p['author_profile_id'] as String};
        results = results.where((r) =>
            r['profile_type'] == 'particulier' || activePro.contains(r['id'])).toList();
      }
      results = results.take(20).toList();

      // Anneaux — par profil (active_by_profile[id]).
      final ringsById = <String, String?>{};
      if (results.isNotEmpty) {
        final uids = results.map((r) => r['uid'] as String).toSet().toList();
        final cosRows = await _supa.from('user_cosmetics')
            .select('uid, active_value, active_by_profile')
            .inFilter('uid', uids)
            .eq('cosmetic_type', 'avatar_ring');
        final byUid = {for (final c in cosRows as List) c['uid'] as String: c as Map};
        for (final r in results) {
          final c = byUid[r['uid']];
          if (c == null) continue;
          final abp = (c['active_by_profile'] as Map?) ?? {};
          ringsById[r['id'] as String] = (abp[r['id']] as String?) ?? c['active_value'] as String?;
        }
      }

      if (mounted) {
        setState(() {
          _results   = results;
          _rings     = ringsById;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _toggleFollow(String targetUid, {String? targetProfileId}) async {
    final isFollowing = _following.contains(targetUid);
    setState(() {
      if (isFollowing) { _following.remove(targetUid); }
      else { _following.add(targetUid); }
    });
    try {
      if (isFollowing) {
        await _removeFollow(widget.myUid, targetUid, followingProfileId: targetProfileId);
      } else {
        await _insertFollow(widget.myUid, targetUid, followingProfileId: targetProfileId);
      }
    } catch (_) {
      setState(() {
        if (isFollowing) { _following.add(targetUid); }
        else { _following.remove(targetUid); }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      margin: const EdgeInsets.only(top: 40),
      decoration: const BoxDecoration(
        color: Color(0xFF0C3535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_tealC, _green]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onSearch,
                style: const TextStyle(
                    fontFamily: 'Galey', color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Rechercher un profil...',
                  hintStyle: TextStyle(
                      fontFamily: 'Galey',
                      color: Colors.white.withValues(alpha: 0.45)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: _tealC, width: 1.5)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _searching
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white54))
              : _results.isEmpty
                  ? Center(
                      child: Text(
                          _ctrl.text.trim().length < 2
                              ? 'Tapez au moins 2 lettres'
                              : 'Aucun résultat',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 14)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r    = _results[i];
                        final uid  = r['uid'] as String;
                        final rpid = r['id'] as String?;
                        final name = _profileName(r);
                        final photo = _profilePhoto(r);
                        final ptype = (r['profile_type'] ?? '').toString();
                        final isPro = ptype.isNotEmpty && ptype != 'particulier';
                        final proLabel = ptype == 'eleveur' ? 'Éleveur certifié'
                            : ptype == 'association' ? 'Association'
                            : ptype == 'veterinaire' || ptype == 'sante' ? 'Vétérinaire / Ostéo'
                            : 'Professionnel';
                        final isFollowing = _following.contains(uid);
                        final ringStyle = _rings[rpid];
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => SocialProfilePage(
                                targetUid: uid, myUid: widget.myUid,
                                targetProfileId: rpid)));
                          },
                          child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.15)),
                                ),
                                child: Row(children: [
                                  _avatarWidget(photo, 20, ringStyle: ringStyle),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: const TextStyle(
                                                  fontFamily: 'Galey',
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: Colors.white)),
                                          if (isPro)
                                            Text(proLabel,
                                                style: const TextStyle(
                                                    fontFamily: 'Galey',
                                                    fontSize: 11,
                                                    color: _green)),
                                        ]),
                                  ),
                                  GestureDetector(
                                    onTap: () => _toggleFollow(uid, targetProfileId: rpid),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        gradient: isFollowing
                                            ? null
                                            : const LinearGradient(
                                                colors: [_tealC, _green]),
                                        color: isFollowing
                                            ? Colors.white
                                                .withValues(alpha: 0.12)
                                            : null,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: isFollowing
                                            ? Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.3))
                                            : null,
                                        boxShadow: isFollowing
                                            ? null
                                            : [
                                                BoxShadow(
                                                    color: _tealC.withValues(
                                                        alpha: 0.35),
                                                    blurRadius: 8,
                                                    offset:
                                                        const Offset(0, 3))
                                              ],
                                      ),
                                      child: Text(
                                          isFollowing ? 'Suivi ✓' : 'Suivre',
                                          style: const TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ));
                      },
                    ),
        ),
      ]),
    );
  }
}

// ─── Page profil utilisateur ──────────────────────────────────────────────────

class SocialProfilePage extends StatefulWidget {
  final String targetUid;
  final String myUid;
  final String? targetProfileId; // profil social affiché (auteur du post d'où on vient)
  final String? myProfileId;     // mon profil actif
  const SocialProfilePage({super.key, required this.targetUid, required this.myUid,
      this.targetProfileId, this.myProfileId});
  @override
  State<SocialProfilePage> createState() => _SocialProfilePageState();
}

class _SocialProfilePageState extends State<SocialProfilePage> {
  final _supa = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  String? _effectiveProfileId; // profil social affiché (résolu dans _load)
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _repostPosts = [];
  List<Map<String, dynamic>> _savedPosts = [];
  int _selectedTab = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isFollowing = false;
  bool _loading = true;
  String? _activeRing;
  String? _activeBanner;
  List<String> _ownedRings = [];
  List<String> _ownedBanners = [];
  List<Map<String, String?>> _mutualProfiles = [];
  int _mutualTotal = 0;

  bool get _isMyProfile => widget.targetUid == widget.myUid;

  void _openShop() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CosmeticsShopSheet(
        myUid: widget.myUid,
        myProfileId: _effectiveProfileId,
        ownedRings: _ownedRings,
        ownedBanners: _ownedBanners,
        activeRing: _activeRing,
        activeBanner: _activeBanner,
        onEquip: (type, value, ownedRings, ownedBanners, activeRing, activeBanner) {
          setState(() {
            _ownedRings = ownedRings;
            _ownedBanners = ownedBanners;
            _activeRing = activeRing;
            _activeBanner = activeBanner;
          });
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Profil social affiché : celui passé (auteur du post d'où on vient) ; pour
    // « mon profil » = mon profil actif ; sinon repli particulier de l'uid.
    // Profil social affiché : celui passé (auteur du post d'où on vient) ; pour
    // « mon profil » = mon profil actif ; sinon profil social de la cible.
    // Toujours résolu à un id concret → scope strict par profil, pas d'uid.
    final tpid = widget.targetProfileId
        ?? (_isMyProfile
            ? (widget.myProfileId ?? await _activeAuthorProfileId(widget.targetUid))
            : await _socialProfileId(widget.targetUid));
    _effectiveProfileId = tpid;
    final mpid = widget.myProfileId ?? await _activeAuthorProfileId(widget.myUid);

    final profQ = tpid != null
        ? _supa.from('user_profiles').select(_kAuthorCols).eq('id', tpid).maybeSingle()
        : _supa.from('user_profiles')
            .select(_kAuthorCols).eq('uid', widget.targetUid).eq('profile_type', 'particulier').maybeSingle();
    final postsBase = _supa.from('posts_socialmedia').select();
    final postsQ = (tpid != null ? postsBase.eq('author_profile_id', tpid) : postsBase.eq('uid', widget.targetUid))
        .order('created_at', ascending: false);
    final folBase = _supa.from('follows').select('follower_uid, follower_profile_id');
    final followersQ = tpid != null ? folBase.eq('following_profile_id', tpid) : folBase.eq('following_uid', widget.targetUid);
    final folBase2 = _supa.from('follows').select('following_uid, following_profile_id');
    final followingQ = tpid != null ? folBase2.eq('follower_profile_id', tpid) : folBase2.eq('follower_uid', widget.targetUid);

    final results = await Future.wait([
      profQ,
      postsQ,
      followersQ,
      followingQ,
      _supa.from('user_cosmetics')
          .select('cosmetic_type, active_value, active_by_profile, owned')
          .eq('uid', widget.targetUid),
    ]);

    var followCheckQ = _supa.from('follows').select('follower_uid');
    followCheckQ = mpid != null ? followCheckQ.eq('follower_profile_id', mpid) : followCheckQ.eq('follower_uid', widget.myUid);
    followCheckQ = tpid != null ? followCheckQ.eq('following_profile_id', tpid) : followCheckQ.eq('following_uid', widget.targetUid);
    final followCheck = await followCheckQ.maybeSingle();

    String? ring; String? banner;
    List<String> ownedRings = []; List<String> ownedBanners = [];
    for (final c in (results[4] as List)) {
      final t = c['cosmetic_type'] as String;
      final abp = (c['active_by_profile'] as Map?) ?? {};
      // Cosmétique équipé DU profil affiché (repli active_value = profil principal).
      final val = (tpid != null ? abp[tpid] as String? : null) ?? c['active_value'] as String?;
      final owned = (c['owned'] as List?)?.cast<String>() ?? [];
      if (t == 'avatar_ring')    { ring = val; ownedRings = owned; }
      if (t == 'profile_banner') { banner = val; ownedBanners = owned; }
    }

    // Abonnés communs : followers du profil cible qui sont aussi suivis par moi
    List<Map<String, String?>> mutualProfiles = [];
    int mutualTotal = 0;
    if (!_isMyProfile) {
      try {
        final targetFollowerUids = (results[2] as List)
            .map((r) => r['follower_uid'] as String)
            .toSet();
        final List myFollowingRows = mpid != null
            ? await _supa.from('follows').select('following_uid').eq('follower_profile_id', mpid)
            : const [];
        final myFollowingUids = myFollowingRows
            .map((r) => r['following_uid'] as String)
            .toSet();
        final commonUids = targetFollowerUids.intersection(myFollowingUids).toList();
        mutualTotal = commonUids.length;
        if (commonUids.isNotEmpty) {
          final sample = commonUids.take(6).toList();
          final profRows = await _supa.from('user_profiles')
              .select('uid, firstname, lastname, nom, avatar_url, social_pseudo')
              .inFilter('uid', sample);
          final seen = <String>{};
          for (final r in profRows as List) {
            final uid = r['uid'] as String;
            if (seen.contains(uid)) continue;
            seen.add(uid);
            final pseudo = (r['social_pseudo'] as String? ?? '').trim();
            final fn  = r['firstname'] as String? ?? '';
            final nom = r['nom'] as String? ?? '';
            final ln  = r['lastname'] as String? ?? '';
            final name = pseudo.isNotEmpty ? pseudo : (fn.isNotEmpty ? fn : (nom.isNotEmpty ? nom : ln));
            if (name.isNotEmpty) {
              mutualProfiles.add({'name': name, 'avatar': r['avatar_url'] as String?});
            }
            if (mutualProfiles.length >= 3) break;
          }
        }
      } catch (_) {}
    }

    // Favoris du profil actif (seulement sur mon profil)
    List<Map<String, dynamic>> savedPosts = [];
    if (widget.targetUid == widget.myUid) {
      try {
        var favQ = _supa.from('post_favorites').select('post_id').eq('uid', widget.myUid);
        if (mpid != null) favQ = favQ.eq('author_profile_id', mpid);
        final favRows = await favQ;
        final postIds = (favRows as List).map((r) => r['post_id'] as String).toList();
        if (postIds.isNotEmpty) {
          final favPosts = await _supa.from('posts_socialmedia')
              .select().inFilter('id', postIds).order('created_at', ascending: false);
          savedPosts = (favPosts as List).cast<Map<String, dynamic>>();
        }
      } catch (_) {}
    }

    final allPosts = (results[1] as List).cast<Map<String, dynamic>>();

    if (mounted) {
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _posts = allPosts.where((p) => p['is_repost'] != true).toList();
        _repostPosts = allPosts.where((p) => p['is_repost'] == true).toList();
        _savedPosts = savedPosts;
        _followersCount = (results[2] as List).length;
        _followingCount = (results[3] as List).length;
        _isFollowing = followCheck != null;
        _activeRing = ring; _activeBanner = banner;
        _ownedRings = ownedRings; _ownedBanners = ownedBanners;
        _mutualProfiles = mutualProfiles;
        _mutualTotal = mutualTotal;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_isMyProfile) return;
    // On suit / désuit le PROFIL affiché (_effectiveProfileId), scopé au profil
    // actif de l'utilisateur.
    if (_isFollowing) {
      await _removeFollow(widget.myUid, widget.targetUid,
          followingProfileId: _effectiveProfileId);
      setState(() { _isFollowing = false; _followersCount--; });
    } else {
      await _insertFollow(widget.myUid, widget.targetUid,
          followingProfileId: _effectiveProfileId);
      setState(() { _isFollowing = true; _followersCount++; });
    }
  }

  String _buildMutualText() {
    final names = _mutualProfiles.map((p) => p['name'] ?? '').toList();
    final extra = _mutualTotal - names.length;
    final joined = names.join(', ');
    if (extra <= 0) return 'Suivi par $joined';
    return 'Suivi par $joined et $extra autre${extra > 1 ? 's' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final name = _profileName(_profile);
    final photo = _profilePhoto(_profile);
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        // Couvre status bar + AppBar en un seul bloc pour éviter le raccord
        if (_activeBanner != null)
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).padding.top + kToolbarHeight,
            child: Container(decoration: _bannerDecoration(_activeBanner)),
          ),
        SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _tealC,
                  backgroundColor: Colors.white,
                  child: CustomScrollView(slivers: [
                  // ── AppBar ──────────────────────────────────────
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    iconTheme: const IconThemeData(color: Colors.white),
                    pinned: false,
                    flexibleSpace: null,
                    actions: [
                      if (_isMyProfile)
                        IconButton(
                          icon: const Icon(Icons.auto_awesome, color: Colors.white),
                          tooltip: 'Boutique cosmétiques',
                          onPressed: () => _openShop(),
                        ),
                    ],
                    title: Text(name,
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 18, color: Colors.white)),
                    centerTitle: true,
                  ),

                  SliverToBoxAdapter(child: Stack(children: [
                    if (_activeBanner != null)
                      Positioned.fill(child: Container(decoration: _bannerDecoration(_activeBanner))),
                    Column(children: [
                    const SizedBox(height: 8),
                    // ── Avatar ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _activeRing != null
                            ? (_cosmeticRings[_activeRing!] ?? const LinearGradient(colors: [_tealC, _green], begin: Alignment.topLeft, end: Alignment.bottomRight))
                            : const LinearGradient(colors: [_tealC, _green], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: const Color(0xFF1A3A42),
                        backgroundImage: photo != null ? NetworkImage(photo) : null,
                        child: photo == null ? const Icon(Icons.pets, color: _tealC, size: 36) : null,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Nom + badge ─────────────────────────────────
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(name, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
                      if (_profile?['profile_type'] == 'eleveur') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [_tealC, Color(0xFF1E7A8C)]), borderRadius: BorderRadius.circular(10)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.verified, size: 11, color: Colors.white),
                            SizedBox(width: 3),
                            Text('Pro', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ],
                      if (_profile?['is_influencer'] == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6E9E57), Color(0xFF0C5C6C)]), shape: BoxShape.circle),
                          child: const Icon(Icons.auto_awesome, size: 11, color: Colors.white),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 20),

                    // ── Stats ───────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 32),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                            _statCol('Posts', _posts.length),
                            Container(width: 1, height: 36, color: Colors.white30),
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                                  _FollowListPage(targetUid: widget.targetUid, myUid: widget.myUid,
                                      targetProfileId: _effectiveProfileId, type: 'followers'))),
                              child: _statCol('Abonnés', _followersCount)),
                            Container(width: 1, height: 36, color: Colors.white30),
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                                  _FollowListPage(targetUid: widget.targetUid, myUid: widget.myUid,
                                      targetProfileId: _effectiveProfileId, type: 'following'))),
                              child: _statCol('Abonnements', _followingCount)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Abonnés communs ─────────────────────────────
                    if (!_isMyProfile && _mutualProfiles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          // Mini avatars empilés
                          SizedBox(
                            width: 26.0 + (_mutualProfiles.length - 1) * 18.0,
                            height: 28,
                            child: Stack(
                              children: List.generate(_mutualProfiles.length, (i) {
                                final av = _mutualProfiles[i]['avatar'];
                                return Positioned(
                                  left: i * 18.0,
                                  child: Container(
                                    width: 28, height: 28,
                                    padding: const EdgeInsets.all(1.5),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(colors: [_tealC, _green]),
                                    ),
                                    child: ClipOval(child: av != null && av.isNotEmpty
                                        ? Image.network(av, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1A4A50)))
                                        : const ColoredBox(color: Color(0xFF1A4A50), child: Icon(Icons.pets_outlined, size: 12, color: Colors.white54))),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: Text(
                            _buildMutualText(),
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white54),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                        ]),
                      ),
                      const SizedBox(height: 12),
                    ] else
                      const SizedBox(height: 16),

                    // ── Bouton suivre / mon profil ──────────────────
                    if (!_isMyProfile)
                      GestureDetector(
                        onTap: _toggleFollow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: _isFollowing ? null : const LinearGradient(colors: [_tealC, _green]),
                            color: _isFollowing ? Colors.white.withValues(alpha: 0.12) : null,
                            borderRadius: BorderRadius.circular(24),
                            border: _isFollowing ? Border.all(color: Colors.white30) : null,
                            boxShadow: _isFollowing ? null : [BoxShadow(color: _tealC.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Text(_isFollowing ? 'Abonné(e) ✓' : 'Suivre',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Séparateur ──────────────────────────────────
                    Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
                    const SizedBox(height: 4),
                  ]),   // Column
                ])),    // Stack + SliverToBoxAdapter

                  // ── Barre d'onglets ─────────────────────────────────
                  SliverToBoxAdapter(child: _buildProfileTabBar()),

                  // ── Contenu selon onglet ─────────────────────────────
                  ..._buildProfileContent(),
                ]),
                ),  // RefreshIndicator
        ),
      ]),
    );
  }

  Widget _buildProfileTabBar() {
    final tabs = ['Posts', 'Reposts', if (_isMyProfile) 'Favoris'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final sel = _selectedTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = i),
              child: Container(
                margin: EdgeInsets.only(right: i < tabs.length - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: sel ? Border.all(color: Colors.white24) : null,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tabs[i],
                      style: TextStyle(
                          fontFamily: 'Galey', fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          color: sel ? Colors.white : Colors.white54),
                      textAlign: TextAlign.center),
                  if (sel) ...[
                    const SizedBox(height: 4),
                    Container(width: 20, height: 2,
                        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(1))),
                  ],
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildProfileContent() {
    final List<Map<String, dynamic>> posts = _selectedTab == 0
        ? _posts
        : _selectedTab == 1
            ? _repostPosts
            : _savedPosts;

    final emptyMsg = _selectedTab == 0
        ? (_isMyProfile ? 'Tu n\'as pas encore posté' : 'Aucun post')
        : _selectedTab == 1
            ? 'Aucune republication'
            : 'Aucun favori';

    if (posts.isEmpty) {
      return [SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(child: Text(emptyMsg,
              style: const TextStyle(fontFamily: 'Galey', color: Colors.white60, fontSize: 15))),
        ),
      )];
    }

    return [SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          final post = posts[i];
          final urls = _mediaUrls(post['media_url']?.toString());
          final thumb = urls.isNotEmpty ? urls.first : null;
          return GestureDetector(
            onTap: () => showDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (_) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
                child: _PostDetailSheet(post: post, myUid: widget.myUid),
              )),
            child: Container(
              margin: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(color: Color(0xFF1A3A42)),
              child: thumb != null
                  ? Image.network(thumb, fit: BoxFit.cover)
                  : Center(child: Text(post['texte']?.toString() ?? '',
                      style: const TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 11),
                      maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
            ),
          );
        },
        childCount: posts.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 0, crossAxisSpacing: 0),
    )];
  }

  Widget _statCol(String label, int count) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$count', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white60)),
    ]);
  }
}

// ─── Page notifications ───────────────────────────────────────────────────────

class SocialNotificationsPage extends StatefulWidget {
  final String myUid;
  final String? myProfileId; // profil actif — scope les notifs
  const SocialNotificationsPage({super.key, required this.myUid, this.myProfileId});
  @override
  State<SocialNotificationsPage> createState() => _SocialNotificationsPageState();
}

class _SocialNotificationsPageState extends State<SocialNotificationsPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pid = widget.myProfileId ?? await _activeAuthorProfileId(widget.myUid);
    if (pid == null) { if (mounted) setState(() => _loading = false); return; }

    // 1. Posts du profil ACTIF → commentaires reçus (scope strict par profil).
    final myPosts = await _supa.from('posts_socialmedia').select('id')
        .eq('author_profile_id', pid);
    final postIds = (myPosts as List).map((p) => p['id'] as String).toList();

    List<Map<String, dynamic>> comments = [];
    if (postIds.isNotEmpty) {
      final rows = await _supa.from('post_comments')
          .select()
          .inFilter('post_id', postIds)
          .neq('uid', widget.myUid)
          .order('created_at', ascending: false)
          .limit(30);
      comments = (rows as List).cast<Map<String, dynamic>>();
    }

    // 2. Nouveaux abonnés du profil ACTIF (scope strict par profil).
    final followers = await _supa.from('follows').select()
        .eq('following_profile_id', pid)
        .order('created_at', ascending: false).limit(20);
    final followerRows = (followers as List).cast<Map<String, dynamic>>();

    // 3. Profils des acteurs — résolus par leur author_profile_id / follower_profile_id.
    final actorProfIds = <String>{
      for (final c in comments)
        if ((c['author_profile_id'] as String?)?.isNotEmpty == true) c['author_profile_id'] as String,
      for (final f in followerRows)
        if ((f['follower_profile_id'] as String?)?.isNotEmpty == true) f['follower_profile_id'] as String,
    }.toList();
    final legacyUids = <String>{
      for (final c in comments) if ((c['author_profile_id'] as String?)?.isNotEmpty != true) c['uid'] as String,
      for (final f in followerRows) if ((f['follower_profile_id'] as String?)?.isNotEmpty != true) f['follower_uid'] as String,
    }.toList();
    final profByKey = <String, Map<String, dynamic>>{};
    if (actorProfIds.isNotEmpty) {
      final rows = await _supa.from('user_profiles').select(_kAuthorCols).inFilter('id', actorProfIds);
      for (final r in rows as List) { profByKey[r['id'] as String] = Map<String, dynamic>.from(r as Map); }
    }
    if (legacyUids.isNotEmpty) {
      final rows = await _supa.from('user_profiles').select(_kAuthorCols)
          .inFilter('uid', legacyUids).eq('profile_type', 'particulier');
      for (final r in rows as List) { profByKey['u:${r['uid']}'] = Map<String, dynamic>.from(r as Map); }
    }
    Map<String, dynamic>? actorOf(Map row, {bool follower = false}) {
      final k = (follower ? row['follower_profile_id'] : row['author_profile_id']) as String?;
      if (k != null && profByKey.containsKey(k)) return profByKey[k];
      return profByKey['u:${follower ? row['follower_uid'] : row['uid']}'];
    }

    // Merge en une liste triée par date
    final all = <Map<String, dynamic>>[];
    for (final c in comments) {
      all.add({
        'type': 'comment',
        'created_at': c['created_at'],
        'profile': actorOf(c),
        'texte': c['texte'],
        'post_id': c['post_id'],
      });
    }
    for (final f in followerRows) {
      all.add({
        'type': 'follow',
        'created_at': f['created_at'],
        'profile': actorOf(f, follower: true),
        'follower_uid': f['follower_uid'],
      });
    }
    all.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));

    if (mounted) setState(() { _notifs = all; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        SafeArea(
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                const Text('Notifications', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _tealC))
                  : _notifs.isEmpty
                      ? const Center(child: Text('Aucune notification', style: TextStyle(fontFamily: 'Galey', color: Colors.white60, fontSize: 15)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 70),
                          itemCount: _notifs.length,
                          itemBuilder: (_, i) {
                            final n = _notifs[i];
                            final prof = n['profile'] as Map<String, dynamic>?;
                            final name = _profileName(prof);
                            final photo = _profilePhoto(prof);
                            final isFollow = n['type'] == 'follow';
                            final date = n['created_at'] as String? ?? '';
                            return Dismissible(
                              key: ValueKey('${n['type']}_${n['created_at']}_${prof?['uid']}'),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => setState(() => _notifs.removeAt(i)),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: Colors.red.shade700,
                                child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: GestureDetector(
                                  onTap: () {
                                    final uid = prof?['uid'] as String?;
                                    if (uid == null) return;
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => SocialProfilePage(
                                        targetUid: uid, myUid: widget.myUid,
                                        targetProfileId: prof?['id'] as String?)));
                                  },
                                  child: _avatarWidget(photo, 22),
                                ),
                                title: RichText(text: TextSpan(
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white),
                                  children: [
                                    TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    TextSpan(text: isFollow ? ' a commencé à te suivre' : ' a commenté ton post'),
                                  ],
                                )),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isFollow)
                                      Text('"${() { final t = n['texte'] as String? ?? ''; return t.length > 50 ? '${t.substring(0, 50)}…' : t; }()}"',
                                          style: const TextStyle(fontFamily: 'Galey', color: Colors.white54, fontSize: 12)),
                                    if (date.isNotEmpty)
                                      Text(_fmtDate(date),
                                          style: const TextStyle(fontFamily: 'Galey', color: Colors.white30, fontSize: 11)),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [_tealC, _green]),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(isFollow ? Icons.person_add_rounded : Icons.chat_bubble_outline_rounded,
                                      color: Colors.white, size: 14),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Post detail sheet (depuis grille profil) ────────────────────────────────

class _PostDetailSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final String myUid;
  const _PostDetailSheet({required this.post, required this.myUid});
  @override
  State<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends State<_PostDetailSheet> {
  final _supa = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLiked    = false;
  bool _isFollowing = false;
  bool _loading    = true;
  String? _authorProfileId; // profil de l'auteur affiché (pour suivre/désuivre)

  String get _effectiveId {
    if (widget.post['_effective_id'] != null) return widget.post['_effective_id'] as String;
    if (widget.post['is_repost'] == true && widget.post['original_post_id'] != null) {
      return widget.post['original_post_id'] as String;
    }
    return widget.post['id'] as String;
  }

  String get _authorUid {
    if (widget.post['is_repost'] == true && widget.post['original_uid'] != null) {
      return widget.post['original_uid'] as String;
    }
    return widget.post['uid'] as String;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _authorUid;
    // Pour un repost, l'auteur affiché est celui du post ORIGINAL — on résout
    // son author_profile_id, pas celui du reposteur.
    String? authorPid = widget.post['author_profile_id'] as String?;
    if (widget.post['is_repost'] == true) {
      authorPid = widget.post['_orig_author_profile_id'] as String?;
      if (authorPid == null && widget.post['original_post_id'] != null) {
        try {
          final o = await _supa.from('posts_socialmedia')
              .select('author_profile_id').eq('id', widget.post['original_post_id']).maybeSingle();
          authorPid = o?['author_profile_id'] as String?;
        } catch (_) {}
      }
    }
    final profQ = authorPid != null
        ? _supa.from('user_profiles').select(_kAuthorCols).eq('id', authorPid).maybeSingle()
        : _supa.from('user_profiles').select(_kAuthorCols)
            .eq('uid', uid).eq('profile_type', 'particulier').maybeSingle();
    final myPid = await _activeAuthorProfileId(widget.myUid);
    var followCheckQ = _supa.from('follows').select('follower_uid').eq('following_uid', uid);
    followCheckQ = myPid != null
        ? followCheckQ.eq('follower_profile_id', myPid)
        : followCheckQ.eq('follower_uid', widget.myUid);
    if (authorPid != null) followCheckQ = followCheckQ.eq('following_profile_id', authorPid);
    final results = await Future.wait<dynamic>([
      profQ,
      _supa.from('post_likes').select('uid').eq('post_id', _effectiveId).eq('uid', widget.myUid).maybeSingle(),
      followCheckQ.maybeSingle(),
      _supa.from('post_likes').select('uid').eq('post_id', _effectiveId),
      _supa.from('post_comments').select('id').eq('post_id', _effectiveId),
      _supa.from('user_cosmetics').select('active_value, active_by_profile')
          .eq('uid', uid).eq('cosmetic_type', 'avatar_ring').maybeSingle(),
    ]);
    if (mounted) {
      widget.post['like_count']    = (results[3] as List).length;
      widget.post['comment_count'] = (results[4] as List).length;
      final prof = (results[0] as Map?)?.cast<String, dynamic>();
      final cosmeticRow = results[5] as Map?;
      final abp = (cosmeticRow?['active_by_profile'] as Map?) ?? {};
      final ring = (authorPid != null ? abp[authorPid] as String? : null)
          ?? cosmeticRow?['active_value'] as String?;
      if (prof != null && ring != null) prof['_ring'] = ring;
      setState(() {
        _profile     = prof;
        _authorProfileId = authorPid ?? prof?['id'] as String?;
        _isLiked     = results[1] != null;
        _isFollowing = results[2] != null;
        _loading     = false;
      });
    }
  }

  Future<void> _toggleLike() async {
    if (_isLiked) {
      await _supa.from('post_likes').delete().eq('post_id', _effectiveId).eq('uid', widget.myUid);
      setState(() {
        _isLiked = false;
        widget.post['like_count'] = ((widget.post['like_count'] as int?) ?? 1) - 1;
      });
    } else {
      await _insertLike(_effectiveId, widget.myUid);
      setState(() {
        _isLiked = true;
        widget.post['like_count'] = ((widget.post['like_count'] as int?) ?? 0) + 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        height: 220,
        child: const Center(child: CircularProgressIndicator(color: _tealC)),
      );
    }
    // Column(min) empêche le card de s'étirer à toute la hauteur du dialog
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SocialPostCard(
          post: widget.post,
          profile: _profile,
          isLiked: _isLiked,
          isFollowing: _isFollowing,
          isMyPost: _authorUid == widget.myUid,
          myUid: widget.myUid,
          onLike: _toggleLike,
          onFollow: () async {
            final uid = _authorUid;
            if (_isFollowing) {
              await _removeFollow(widget.myUid, uid, followingProfileId: _authorProfileId);
              setState(() => _isFollowing = false);
            } else {
              await _insertFollow(widget.myUid, uid, followingProfileId: _authorProfileId);
              setState(() => _isFollowing = true);
            }
          },
          onDelete: () => Navigator.pop(context),
          onComment: () => showModalBottomSheet(
            context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
            builder: (_) => _CommentsSheet(
              postId: _effectiveId,
              myUid: widget.myUid,
              postAuthorUid: _authorUid,
              onCommentAdded: () => setState(() {
                widget.post['comment_count'] = ((widget.post['comment_count'] as int?) ?? 0) + 1;
              }))),
        ),
      ],
    );
  }

}

// ─── Liste abonnés / abonnements ─────────────────────────────────────────────

class _FollowListPage extends StatefulWidget {
  final String targetUid;
  final String myUid;
  final String? targetProfileId; // profil dont on liste les abonnés / abonnements
  final String type; // 'followers' or 'following'
  const _FollowListPage({required this.targetUid, required this.myUid,
      this.targetProfileId, required this.type});
  @override
  State<_FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<_FollowListPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  Set<String> _myFollowing = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // Profil dont on liste abonnés/abonnements : toujours résolu à un id
    // concret (transmis par SocialProfilePage, sinon profil social de la cible).
    final tpid = widget.targetProfileId ?? await _socialProfileId(widget.targetUid);
    // Colonne côté "eux" et côté "profil cible" selon followers/following.
    final theirUidCol   = widget.type == 'followers' ? 'follower_uid' : 'following_uid';
    final theirPidCol   = widget.type == 'followers' ? 'follower_profile_id' : 'following_profile_id';
    final targetUidCol  = widget.type == 'followers' ? 'following_uid' : 'follower_uid';
    final targetPidCol  = widget.type == 'followers' ? 'following_profile_id' : 'follower_profile_id';

    final listBase = _supa.from('follows').select('$theirUidCol, $theirPidCol');
    final listQ = tpid != null
        ? listBase.eq(targetPidCol, tpid)
        : listBase.eq(targetUidCol, widget.targetUid);
    final rows = await listQ as List;
    _myFollowing = await _activeFollowingUids(widget.myUid);

    final pids = <String>{for (final r in rows) if ((r[theirPidCol] as String?)?.isNotEmpty == true) r[theirPidCol] as String}.toList();
    final legacyUids = <String>{for (final r in rows) if ((r[theirPidCol] as String?)?.isNotEmpty != true) r[theirUidCol] as String}.toList();
    if (pids.isEmpty && legacyUids.isEmpty) { if (mounted) setState(() => _loading = false); return; }
    final users = <Map<String, dynamic>>[];
    if (pids.isNotEmpty) {
      final r = await _supa.from('user_profiles').select(_kAuthorCols).inFilter('id', pids);
      users.addAll((r as List).cast<Map<String, dynamic>>());
    }
    if (legacyUids.isNotEmpty) {
      final r = await _supa.from('user_profiles').select(_kAuthorCols)
          .inFilter('uid', legacyUids).eq('profile_type', 'particulier');
      users.addAll((r as List).cast<Map<String, dynamic>>());
    }
    if (mounted) {
      setState(() { _users = users; _loading = false; });
    }
  }

  Future<void> _toggleFollow(String targetUid) async {
    if (_myFollowing.contains(targetUid)) {
      await _removeFollow(widget.myUid, targetUid);
      setState(() => _myFollowing.remove(targetUid));
    } else {
      await _insertFollow(widget.myUid, targetUid);
      setState(() => _myFollowing.add(targetUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'followers' ? 'Abonnés' : 'Abonnements';
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20)),
              const SizedBox(width: 16),
              Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
            ])),
          const Divider(color: Colors.white12, height: 1),
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : _users.isEmpty
                  ? Center(child: Text('Aucun $title'.toLowerCase(), style: const TextStyle(fontFamily: 'Galey', color: Colors.white60, fontSize: 15)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 70),
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final prof = _users[i];
                        final uid = prof['uid'] as String;
                        final isMe = uid == widget.myUid;
                        final isFollowed = _myFollowing.contains(uid);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => SocialProfilePage(targetUid: uid, myUid: widget.myUid,
                                    targetProfileId: prof['id'] as String?))),
                            child: _avatarWidget(_profilePhoto(prof), 22)),
                          title: Text(_profileName(prof), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                          subtitle: prof['profile_type'] == 'eleveur'
                              ? const Text('Éleveur Pro', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green))
                              : null,
                          trailing: isMe ? null : GestureDetector(
                            onTap: () => _toggleFollow(uid),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: isFollowed ? null : const LinearGradient(colors: [_tealC, _green]),
                                color: isFollowed ? Colors.white12 : null,
                                borderRadius: BorderRadius.circular(18),
                                border: isFollowed ? Border.all(color: Colors.white24) : null,
                              ),
                              child: Text(isFollowed ? 'Suivi ✓' : 'Suivre',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        );
                      },
                    )),
        ])),
      ]),
    );
  }
}

// ─── Liste des personnes qui ont aimé un post ────────────────────────────────

void _showPostLikes(BuildContext context, String postId, String myUid) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostLikesSheet(postId: postId, myUid: myUid),
  );
}

class _PostLikesSheet extends StatefulWidget {
  final String postId;
  final String myUid;
  const _PostLikesSheet({required this.postId, required this.myUid});
  @override
  State<_PostLikesSheet> createState() => _PostLikesSheetState();
}

class _PostLikesSheetState extends State<_PostLikesSheet> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final likes = await _supa.from('post_likes')
          .select('uid, author_profile_id, created_at')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: false) as List;
      final pids = <String>{
        for (final l in likes)
          if ((l['author_profile_id'] as String?)?.isNotEmpty == true)
            l['author_profile_id'] as String,
      }.toList();
      final legacyUids = <String>{
        for (final l in likes)
          if ((l['author_profile_id'] as String?)?.isNotEmpty != true)
            l['uid'] as String,
      }.toList();
      final byKey = <String, Map<String, dynamic>>{};
      if (pids.isNotEmpty) {
        final r = await _supa.from('user_profiles').select(_kAuthorCols).inFilter('id', pids);
        for (final p in r as List) {
          byKey[p['id'] as String] = Map<String, dynamic>.from(p as Map);
        }
      }
      if (legacyUids.isNotEmpty) {
        final r = await _supa.from('user_profiles').select(_kAuthorCols)
            .inFilter('uid', legacyUids).eq('profile_type', 'particulier');
        for (final p in r as List) {
          byKey['u:${p['uid']}'] = Map<String, dynamic>.from(p as Map);
        }
      }
      final ordered = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final l in likes) {
        final apid = (l['author_profile_id'] as String?) ?? '';
        final key = apid.isNotEmpty ? apid : 'u:${l['uid']}';
        if (!seen.add(key)) continue;
        final p = byKey[key];
        if (p != null) ordered.add(p);
      }
      if (mounted) setState(() { _users = ordered; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          gradient: _bgGrad,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('J’aime', style: TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white))),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _tealC))
                : _users.isEmpty
                    ? const Center(child: Text('Personne pour l’instant',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.white54)))
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white10, height: 1, indent: 70),
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final prof = _users[i];
                          final uid = prof['uid'] as String;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: _avatarWidget(_profilePhoto(prof), 22),
                            title: Text(_profileName(prof),
                                style: const TextStyle(fontFamily: 'Galey',
                                    fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                            subtitle: _socialTypeLabel(prof['profile_type'] as String?) != null
                                ? Text(_socialTypeLabel(prof['profile_type'] as String?)!,
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green))
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => SocialProfilePage(
                                      targetUid: uid, myUid: widget.myUid,
                                      targetProfileId: prof['id'] as String?)));
                            },
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Boutique cosmétiques
// ═══════════════════════════════════════════════════════════════════════════

typedef _OnEquip = void Function(
  String type, String value,
  List<String> ownedRings, List<String> ownedBanners,
  String? activeRing, String? activeBanner,
);

class _CosmeticsShopSheet extends StatefulWidget {
  final String myUid;
  final String? myProfileId; // profil qui équipe (active_by_profile)
  final List<String> ownedRings;
  final List<String> ownedBanners;
  final String? activeRing;
  final String? activeBanner;
  final _OnEquip onEquip;
  const _CosmeticsShopSheet({
    required this.myUid, this.myProfileId, required this.ownedRings, required this.ownedBanners,
    required this.activeRing, required this.activeBanner, required this.onEquip,
  });
  @override
  State<_CosmeticsShopSheet> createState() => _CosmeticsShopSheetState();
}

class _CosmeticsShopSheetState extends State<_CosmeticsShopSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _supa = Supabase.instance.client;
  bool _busy = false;
  late List<String> _ownedRings;
  late List<String> _ownedBanners;
  late String? _activeRing;
  late String? _activeBanner;
  int _solde = 0;
  List<Map<String, dynamic>> _packs = [];

  /// Écrit le cosmétique équipé du profil courant. `owned` reste global.
  /// `active_by_profile[<profileId>] = value` ; `active_value` suivi si on est
  /// sur le profil principal (myProfileId nul) pour la compatibilité.
  Future<void> _persistActive(String type, String? value, List<String> owned) async {
    final pid = widget.myProfileId;
    Map<String, dynamic> abp = {};
    if (pid != null) {
      try {
        final row = await _supa.from('user_cosmetics')
            .select('active_by_profile')
            .eq('uid', widget.myUid).eq('cosmetic_type', type).maybeSingle();
        abp = Map<String, dynamic>.from((row?['active_by_profile'] as Map?) ?? {});
      } catch (_) {}
      if (value == null) { abp.remove(pid); } else { abp[pid] = value; }
    }
    await _supa.from('user_cosmetics').upsert({
      'uid': widget.myUid, 'cosmetic_type': type,
      if (pid == null) 'active_value': value,
      'active_by_profile': abp,
      'owned': owned,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'uid,cosmetic_type');
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _ownedRings = List.from(widget.ownedRings);
    _ownedBanners = List.from(widget.ownedBanners);
    _activeRing = widget.activeRing;
    _activeBanner = widget.activeBanner;
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final results = await Future.wait([
        _supa.from('credit_wallets').select('solde').eq('uid', widget.myUid).maybeSingle(),
        _supa.from('credit_packs').select().eq('actif', true).order('ordre'),
      ]);
      if (mounted) {
        setState(() {
          _solde = (results[0] as Map<String, dynamic>?)?['solde'] as int? ?? 0;
          _packs = (results[1] as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  void _openCreditsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreditPacksSheet(
        packs: _packs,
        myUid: widget.myUid,
        onSuccess: _loadWallet,
      ),
    );
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _buyOrEquip(Map<String, Object> item) async {
    if (_busy) return;
    final id = item['id'] as String;
    final type = item['type'] as String;
    final cost = item['cost'] as int;
    final isRing = type == 'avatar_ring';
    final owned = isRing ? _ownedRings : _ownedBanners;
    final alreadyOwned = owned.contains(id);

    if (!alreadyOwned) {
      // Confirmation avant achat
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1F22),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Icon(Icons.toll_outlined, color: _green, size: 36),
            const SizedBox(height: 12),
            Text('Confirmer l\'achat', style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 8),
            Text('${item['label']}  ·  $cost crédits',
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white.withValues(alpha: 0.65))),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Center(child: Text('Annuler',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                          fontSize: 15, color: Colors.white70))),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_tealC, _green]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: _tealC.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Center(child: Text('Acheter — $cost cr.',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 15, color: Colors.white))),
                ),
              )),
            ]),
          ]),
        ),
      );
      if (confirmed != true) return;

      // Acheter
      setState(() => _busy = true);
      try {
        final walletRow = await _supa.from('credit_wallets').select().eq('uid', widget.myUid).maybeSingle();
        final solde = (walletRow?['solde'] as int?) ?? 0;
        if (solde < cost) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Crédits insuffisants ($solde cr. disponibles, $cost cr. requis)',
                  style: const TextStyle(fontFamily: 'Galey')),
              backgroundColor: const Color(0xFF1F2A2E), behavior: SnackBarBehavior.floating,
            ));
          }
          setState(() => _busy = false);
          return;
        }
        final newOwned = [...owned, id];
        // Débit atomique côté serveur (RPC SECURITY DEFINER).
        final spend = await _supa.rpc('credit_spend', params: {
          'p_uid': widget.myUid,
          'p_cost': cost,
          'p_motif': 'Cosmétique ${item['label']}',
          'p_ref_id': id,
        });
        if (!(spend is Map && spend['ok'] == true)) {
          if (mounted) {
            final s = (spend is Map ? spend['solde'] : null) ?? solde;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Crédits insuffisants ($s cr. disponibles, $cost cr. requis)',
                  style: const TextStyle(fontFamily: 'Galey')),
              backgroundColor: const Color(0xFF1F2A2E), behavior: SnackBarBehavior.floating,
            ));
            setState(() => _busy = false);
          }
          return;
        }
        await _persistActive(type, id, newOwned);
        if (mounted) {
          setState(() {
            if (isRing) { _ownedRings = newOwned; _activeRing = id; }
            else { _ownedBanners = newOwned; _activeBanner = id; }
            _busy = false;
          });
          widget.onEquip(type, id, _ownedRings, _ownedBanners, _activeRing, _activeBanner);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${item['label']} acheté et équipé !', style: const TextStyle(fontFamily: 'Galey')),
            backgroundColor: _tealC, behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (_) {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      // Équiper / déséquiper
      final isActive = isRing ? _activeRing == id : _activeBanner == id;
      final newActive = isActive ? null : id;
      try {
        await _persistActive(type, newActive, owned);
        if (mounted) {
          setState(() {
            if (isRing) { _activeRing = newActive; }
            else { _activeBanner = newActive; }
          });
          widget.onEquip(type, id, _ownedRings, _ownedBanners, _activeRing, _activeBanner);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final rings   = _cosmeticCatalog.where((c) => c['type'] == 'avatar_ring').toList();
    final banners = _cosmeticCatalog.where((c) => c['type'] == 'profile_banner').toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1F22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Boutique', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
        const SizedBox(height: 4),
        Text('Personnalisez votre profil Pets Social', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 14),
        TabBar(
          controller: _tab,
          indicatorColor: _green,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Anneaux avatar'), Tab(text: 'Bannières profil')],
        ),
        Expanded(child: TabBarView(controller: _tab, children: [
          _itemGrid(rings,   isRing: true),
          _itemGrid(banners, isRing: false),
        ])),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.toll_outlined, size: 16, color: _green),
                const SizedBox(width: 6),
                Text('$_solde cr.',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _openCreditsSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_tealC, _green]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('Acheter des crédits',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _bannerPreviewWidget(Map<String, Object> item, bool active) {
    final id = item['id'] as String;
    final previewUrl = item['preview_url'] as String?;
    final bannerUrl  = item['banner_url']  as String?;
    final url = previewUrl ?? bannerUrl;
    final isImage = url != null || id.startsWith('http');

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 80, height: 32,
        child: isImage
            ? Image.network(url ?? id, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.white12))
            : Container(decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: _cosmeticBanners[id] ?? _bgGrad,
              )),
      ),
    );
  }

  Widget _itemGrid(List<Map<String, Object>> items, {required bool isRing}) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 1.1, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final id = item['id'] as String;
        final owned = isRing ? _ownedRings.contains(id) : _ownedBanners.contains(id);
        final active = isRing ? _activeRing == id : _activeBanner == id;
        final grad = isRing
            ? (_cosmeticRings[id] ?? _ringGrad)
            : (_cosmeticBanners[id] ?? _bgGrad);

        return GestureDetector(
          onTap: _busy ? null : () => _buyOrEquip(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? _green : (owned ? Colors.white24 : Colors.white12),
                width: active ? 2.5 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0.03)],
              ),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Preview
              if (isRing)
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: grad),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0D1F22)),
                    child: const Icon(Icons.pets, color: Colors.white38, size: 22),
                  ),
                )
              else
                _bannerPreviewWidget(item, active),
              const SizedBox(height: 8),
              Text(item['label'] as String,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 4),
              if (!owned)
                Text('${item['cost']} cr.', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: _green))
              else if (active)
                const Text('Équipé ✓', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: _green, fontWeight: FontWeight.w700))
              else
                Text('Équiper', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.white.withValues(alpha: 0.5))),
            ]),
          ),
        );
      },
    );
  }
}

// ─── Feuille de partage (même approche que le feed des annonces : liens directs,
// pas de Share.share OS qui plante sur certains appareils) ────────────────────

class _SocialShareSheet extends StatelessWidget {
  final String text, url, nom;
  const _SocialShareSheet({required this.text, required this.url, required this.nom});

  Future<void> _copy(BuildContext ctx) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (ctx.mounted) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text('Lien copié !', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: const Color(0xFF0C5C6C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
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
    final emailUrl = Uri.parse('mailto:?subject=${Uri.encodeComponent('Pets Social — $nom')}&body=$encoded');
    final safe     = MediaQuery.of(context).padding;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C3535), Color(0xFF071C22)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(28, 14, 28, safe.bottom + 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_tealC, _green]),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Titre avec gradient
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Colors.white, Color(0xFF86D4C8)],
              ).createShader(b),
              child: const Text('Partager',
                style: TextStyle(color: Colors.white, fontFamily: 'Galey',
                    fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            const SizedBox(height: 6),
            Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                  fontFamily: 'Galey', fontSize: 12)),

            const SizedBox(height: 28),

            // Boutons
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _SocialShareBtn(
                icon: const Icon(Icons.link_rounded, color: Colors.white, size: 22),
                gradient: const LinearGradient(colors: [Color(0xFF0C5C6C), Color(0xFF0E7A8E)]),
                glowColor: const Color(0xFF0C5C6C),
                label: 'Lien',
                onTap: () => _copy(context),
              ),
              _SocialShareBtn(
                icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 22),
                gradient: const LinearGradient(colors: [Color(0xFF1DAF54), Color(0xFF25D366)]),
                glowColor: const Color(0xFF25D366),
                label: 'WhatsApp',
                onTap: () => _launch(context, waUrl),
              ),
              _SocialShareBtn(
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 22),
                gradient: const LinearGradient(colors: [Color(0xFF3E78D8), Color(0xFF5B96F5)]),
                glowColor: const Color(0xFF4A90E2),
                label: 'SMS',
                onTap: () => _launch(context, smsUrl),
              ),
              _SocialShareBtn(
                icon: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 22),
                gradient: const LinearGradient(colors: [Color(0xFFD93025), Color(0xFFEA4335)]),
                glowColor: const Color(0xFFEA4335),
                label: 'Email',
                onTap: () => _launch(context, emailUrl),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SocialShareBtn extends StatelessWidget {
  final Widget icon;
  final LinearGradient gradient;
  final Color glowColor;
  final String label;
  final VoidCallback onTap;
  const _SocialShareBtn({
    required this.icon,
    required this.gradient,
    required this.glowColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 62, height: 62,
        decoration: BoxDecoration(
          gradient: gradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(child: icon),
      ),
      const SizedBox(height: 10),
      Text(label,
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontSize: 11,
            fontFamily: 'Galey',
            fontWeight: FontWeight.w600),
        textAlign: TextAlign.center),
    ]),
  );
}
