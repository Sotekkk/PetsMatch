import 'package:flutter/material.dart';

class ChatTheme {
  final String id;
  final String name;
  final String emoji;
  final List<Color> bgGradient;
  final Color sentColor;
  final Color sentTextColor;
  final Color inputBarColor;
  final bool isDark;
  final bool isPremium;

  const ChatTheme({
    required this.id,
    required this.name,
    required this.emoji,
    required this.bgGradient,
    required this.sentColor,
    required this.inputBarColor,
    this.sentTextColor = Colors.white,
    this.isDark = false,
    this.isPremium = false,
  });
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
];

ChatTheme chatThemeById(String? id) =>
    kChatThemes.firstWhere((t) => t.id == (id ?? 'default'),
        orElse: () => kChatThemes.first);
