import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:PetsMatch/main.dart' show navigatorKey;
import 'package:PetsMatch/pages/particulier/social_feed_page.dart' show openSharedSocialPost;

/// Gère les liens entrants (Android App Links / iOS Universal Links) de la forme
/// `https://petsmatchapp.com/p/<postId>` → ouvre la publication dans Pets Social.
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
    final postId = _postIdFrom(uri);
    if (postId == null) return;

    final ctx = navigatorKey.currentContext;
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    if (ctx == null || !loggedIn) {
      _pending = uri; // rejoué par flushPending()
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = navigatorKey.currentContext;
      if (c != null) openSharedSocialPost(c, postId);
    });
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
