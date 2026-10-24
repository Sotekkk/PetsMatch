import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/main.dart' show navigatorKey;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/lieux/lieu_detail_page.dart';
import 'package:PetsMatch/pages/nature/natural_place_detail_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/social_feed_page.dart' show openSharedSocialPost;

/// Gère les liens entrants (Android App Links / iOS Universal Links) du site
/// partagés depuis l'appli ou le site, quand l'appli est installée :
///   • `/p/<postId>` → publication Pets Social ;
///   • `/annonces/<id>` → fiche de l'annonce ;
///   • `/animaux-perdus?alerte=<id>` / `?trouve=<id>` → l'alerte ouverte ;
///   • `/lieux-naturels/<id>`, `/animal-friendly/<id>` → fiche du lieu.
/// Chemins déclarés : AndroidManifest.xml + public/.well-known/apple-app-site-association.
///
/// Un lien reçu avant que l'app soit prête (navigateur non monté ou utilisateur
/// pas encore connecté) est mis en attente et rejoué via [flushPending], appelé
/// une fois l'écran principal affiché.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  Uri? _pending;
  bool _started = false;

  Future<void> init() async {
    if (_started) return;
    _started = true;

    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  /// Rejoue le dernier lien mis en attente (à appeler quand l'UI est prête).
  void flushPending() {
    final uri = _pending;
    if (uri == null) return;
    _pending = null;
    _handle(uri);
  }

  void _handle(Uri uri) {
    final ouvrir = _destination(uri);
    if (ouvrir == null) return;

    final ctx = navigatorKey.currentContext;
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    if (ctx == null || !loggedIn) {
      _pending = uri; // rejoué par flushPending()
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = navigatorKey.currentContext;
      if (c != null) ouvrir(c);
    });
  }

  /// Sous-pages du site sans équivalent « fiche » (l'appli s'ouvre sur l'accueil).
  static const _pagesAnnonces = {'carte', 'creer', 'creer-cheval', 'creer-objet', 'feed', 'objets', 'paiement-boost', 'publier'};
  static const _pagesLieux = {'proposer', 'mes-contributions', 'recommander'};

  static void Function(BuildContext)? _destination(Uri uri) {
    final postId = _postIdFrom(uri);
    if (postId != null) return (c) => openSharedSocialPost(c, postId);

    final host = uri.host.replaceFirst('www.', '');
    if (host != 'petsmatchapp.com') return null;
    final seg = uri.pathSegments.where((x) => x.isNotEmpty).toList();
    if (seg.isEmpty) return null;
    final id = seg.length >= 2 ? seg[1] : null;
    void pousser(BuildContext c, Widget page) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => page));

    switch (seg[0]) {
      case 'annonces':
        if (id == null || _pagesAnnonces.contains(id)) return null;
        return (c) => pousser(c, AnnonceDetailPage(annonceId: id));
      case 'animaux-perdus':
        final alerte = uri.queryParameters['alerte'];
        final trouve = uri.queryParameters['trouve'];
        return (c) => pousser(c, AnimauxPerdusPage(initialAlertId: alerte, initialTrouveId: trouve));
      case 'animal-friendly':
        if (id == null || _pagesLieux.contains(id)) return null;
        return (c) => pousser(c, LieuDetailPage(id: id));
      case 'lieux-naturels':
        if (id == null || _pagesLieux.contains(id)) return null;
        return (c) async {
          try {
            final lieu = await Supabase.instance.client.from('natural_places').select().eq('id', id).maybeSingle();
            if (lieu != null && c.mounted) pousser(c, NaturalPlaceDetailPage(place: Map<String, dynamic>.from(lieu)));
          } catch (_) {}
        };
    }
    return null;
  }

  /// `/p/<id>` (avec ou sans `www`, http/https) → `<id>`.
  static String? _postIdFrom(Uri uri) {
    final host = uri.host.replaceFirst('www.', '');
    if (host != 'petsmatchapp.com') return null;
    final seg = uri.pathSegments;
    if (seg.length >= 2 && seg[0] == 'p' && seg[1].isNotEmpty) return seg[1];
    return null;
  }
}
