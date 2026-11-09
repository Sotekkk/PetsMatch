import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatTheme {
  final String id;
  final String name;
  final String emoji;
  final List<Color> bgGradient;
  final Color sentColor;
  final Color sentTextColor;
  final Color inputBarColor;
  final bool isDark;
  /// Motif répété en fond, posé sur le dégradé.
  final String? tileAsset;
  /// Prix en crédits ; 0 = gratuit.
  final int cost;

  const ChatTheme({
    required this.id,
    required this.name,
    required this.emoji,
    required this.bgGradient,
    required this.sentColor,
    required this.inputBarColor,
    this.sentTextColor = Colors.white,
    this.isDark = false,
    this.tileAsset,
    this.cost = 0,
  });

  bool get isPremium => cost > 0;
}

const kChatThemes = <ChatTheme>[
  ChatTheme(
    id: 'default',
    name: 'Classique',
    emoji: '💬',
    bgGradient: [Color(0xFFF5F5F0), Color(0xFFF0F0EB)],
    sentColor: Color(0xFF0C5C6C),
    inputBarColor: Colors.white,
  ),
  ChatTheme(
    id: 'sunset',
    name: 'Coucher de soleil',
    emoji: '🌅',
    bgGradient: [Color(0xFFFFE4CC), Color(0xFFFFB5C8)],
    sentColor: Color(0xFFD4603A),
    inputBarColor: Color(0xFFFFCCB5),
  ),
  ChatTheme(
    id: 'forest',
    name: 'Forêt',
    emoji: '🌿',
    bgGradient: [Color(0xFFE8F5E9), Color(0xFFC5DFC6)],
    sentColor: Color(0xFF3D7A32),
    inputBarColor: Color(0xFFB8D9BA),
  ),
  ChatTheme(
    id: 'ocean',
    name: 'Océan',
    emoji: '🌊',
    bgGradient: [Color(0xFFDCEEFD), Color(0xFFB3D4F5)],
    sentColor: Color(0xFF1256A0),
    inputBarColor: Color(0xFFA8CBF0),
  ),
  ChatTheme(
    id: 'lavender',
    name: 'Lavande',
    emoji: '💜',
    bgGradient: [Color(0xFFF3E8FA), Color(0xFFDDB8EE)],
    sentColor: Color(0xFF7B1FA2),
    inputBarColor: Color(0xFFCBA8E2),
  ),
  ChatTheme(
    id: 'night',
    name: 'Nuit',
    emoji: '🌙',
    bgGradient: [Color(0xFF1A1A2E), Color(0xFF0F213E)],
    sentColor: Color(0xFF2C5F8A),
    inputBarColor: Color(0xFF0D1525),
    isDark: true,
  ),
  ChatTheme(
    id: 'pattes',
    name: 'Pattes & os',
    emoji: '🐾',
    // Même beige que le fond de la tuile, pour l'en-tête et les bords.
    bgGradient: [Color(0xFFFBF3E8), Color(0xFFFBF3E8)],
    sentColor: Color(0xFF8D5B3A),
    inputBarColor: Colors.white,
    tileAsset: 'assets/chat_themes/tuile_pattes.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'pattes_nuit',
    name: 'Pattes de nuit',
    emoji: '🌙',
    bgGradient: [Color(0xFF012F2B), Color(0xFF012F2B)],
    sentColor: Color(0xFF2E8B7A),
    inputBarColor: Color(0xFF01211E),
    isDark: true,
    tileAsset: 'assets/chat_themes/tuile_pattes_nuit.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'chats',
    name: 'Chats & pelotes',
    emoji: '🐱',
    bgGradient: [Color(0xFFD18972), Color(0xFFD18972)],
    sentColor: Color(0xFF8C3E2A),
    inputBarColor: Colors.white,
    tileAsset: 'assets/chat_themes/tuile_chats.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'equitation',
    name: 'Équitation',
    emoji: '🐴',
    bgGradient: [Color(0xFFA9B38B), Color(0xFFA9B38B)],
    sentColor: Color(0xFF55623A),
    inputBarColor: Colors.white,
    tileAsset: 'assets/chat_themes/tuile_equitation.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'oiseaux',
    name: 'Oiseaux & plumes',
    emoji: '🐦',
    bgGradient: [Color(0xFF8AB3C9), Color(0xFF8AB3C9)],
    sentColor: Color(0xFF2F5D78),
    inputBarColor: Colors.white,
    tileAsset: 'assets/chat_themes/tuile_oiseaux.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'compagnons',
    name: 'Petits compagnons',
    emoji: '🐰',
    bgGradient: [Color(0xFFDAB372), Color(0xFFDAB372)],
    sentColor: Color(0xFF8A5A1E),
    inputBarColor: Colors.white,
    tileAsset: 'assets/chat_themes/tuile_compagnons.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'jardin',
    name: 'Jardin',
    emoji: '🌸',
    bgGradient: [Color(0xFFC7A8DF), Color(0xFFC7A8DF)],
    sentColor: Color(0xFF6A4A8C),
    inputBarColor: Colors.white,
    tileAsset: 'assets/chat_themes/tuile_jardin.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'plage',
    name: 'Plage',
    emoji: '🏖️',
    bgGradient: [Color(0xFF378B94), Color(0xFF378B94)],
    sentColor: Color(0xFFD9693F),
    inputBarColor: Colors.white,
    tileAsset: 'assets/chat_themes/tuile_plage.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'noel',
    name: 'Noël',
    emoji: '🎄',
    bgGradient: [Color(0xFF7B1920), Color(0xFF7B1920)],
    sentColor: Color(0xFF2E6B4A),
    inputBarColor: Color(0xFF5A1218),
    isDark: true,
    tileAsset: 'assets/chat_themes/tuile_noel.webp',
    cost: 100,
  ),
  ChatTheme(
    id: 'halloween',
    name: 'Halloween',
    emoji: '🎃',
    bgGradient: [Color(0xFF23011D), Color(0xFF23011D)],
    sentColor: Color(0xFFD9772B),
    inputBarColor: Color(0xFF170113),
    isDark: true,
    tileAsset: 'assets/chat_themes/tuile_halloween.webp',
    cost: 100,
  ),
];

ChatTheme chatThemeById(String? id) =>
    kChatThemes.firstWhere((t) => t.id == (id ?? 'default'),
        orElse: () => kChatThemes.first);

/// Pixels de la tuile par point d'écran : une tuile de 1254 px s'affiche sur
/// ~418 points, quelle que soit la densité de l'écran (motifs à taille fixe).
const double kChatTileScale = 3;

/// Fond d'une conversation : photo perso, sinon motif répété sur le dégradé
/// du thème, sinon dégradé seul. Le motif est ancré en haut à gauche pour ne
/// pas bouger quand le clavier réduit la zone.
class ChatBackground extends StatelessWidget {
  final ChatTheme theme;
  final String? customBgUrl;
  final Widget? child;
  const ChatBackground({super.key, required this.theme, this.customBgUrl, this.child});

  @override
  Widget build(BuildContext context) {
    if (customBgUrl != null) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(image: NetworkImage(customBgUrl!), fit: BoxFit.cover),
        ),
        child: child,
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: theme.bgGradient,
        ),
        image: theme.tileAsset == null
            ? null
            : DecorationImage(
                image: AssetImage(theme.tileAsset!),
                repeat: ImageRepeat.repeat,
                alignment: Alignment.topLeft,
                scale: kChatTileScale,
              ),
      ),
      child: child,
    );
  }
}

/// Aperçu d'un thème (sélecteur du chat, boutique) : le vrai fond avec une
/// bulle reçue et une bulle envoyée, pour juger le rendu et la lisibilité.
class ChatThemePreview extends StatelessWidget {
  final ChatTheme theme;
  final double bubbleHeight;
  const ChatThemePreview({super.key, required this.theme, this.bubbleHeight = 14});

  Widget _bubble(Color color, double widthFactor) => FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: bubbleHeight,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(bubbleHeight / 2)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ChatBackground(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Align(alignment: Alignment.centerLeft, child: _bubble(Colors.white, 0.62)),
          SizedBox(height: bubbleHeight * 0.4),
          Align(alignment: Alignment.centerRight, child: _bubble(theme.sentColor, 0.5)),
        ]),
      ),
    );
  }
}

// ── Achat des fonds premium ─────────────────────────────────────────────────
// Possession rangée dans user_cosmetics comme les anneaux/bannières de la
// boutique Pets Social : achetés une fois pour le compte, utilisables ensuite
// dans toutes les conversations.

const kChatBackgroundCosmeticType = 'chat_background';

enum ChatThemePurchase { ok, insufficientCredits, error }

class ChatThemeStore {
  static SupabaseClient get _supa => Supabase.instance.client;

  static Future<Set<String>> _readOwned(String uid) async {
    final row = await _supa.from('user_cosmetics').select('owned')
        .eq('uid', uid).eq('cosmetic_type', kChatBackgroundCosmeticType).maybeSingle();
    return ((row?['owned'] as List?) ?? const []).map((e) => e.toString()).toSet();
  }

  /// Thèmes premium déjà achetés ; vide si la lecture échoue.
  static Future<Set<String>> ownedIds(String uid) async {
    try {
      return await _readOwned(uid);
    } catch (_) {
      return {};
    }
  }

  static Future<ChatThemePurchase> buy(String uid, ChatTheme theme) async {
    try {
      // Lecture qui échoue franchement : l'upsert final réécrit toute la liste,
      // une lecture vide par erreur effacerait les achats précédents.
      final owned = await _readOwned(uid);
      if (owned.contains(theme.id)) return ChatThemePurchase.ok;
      final spend = await _supa.rpc('credit_spend', params: {
        'p_uid': uid,
        'p_cost': theme.cost,
        'p_motif': 'Fond de discussion ${theme.name}',
        'p_ref_id': theme.id,
      });
      if (!(spend is Map && spend['ok'] == true)) return ChatThemePurchase.insufficientCredits;
      await _supa.from('user_cosmetics').upsert({
        'uid': uid,
        'cosmetic_type': kChatBackgroundCosmeticType,
        'owned': [...owned, theme.id],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'uid,cosmetic_type');
      return ChatThemePurchase.ok;
    } catch (_) {
      return ChatThemePurchase.error;
    }
  }
}
