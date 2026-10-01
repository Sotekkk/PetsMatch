import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Vérifie la réponse d'un défi (question / QR code) CÔTÉ SERVEUR : la
/// réponse attendue n'est plus lisible par les joueurs (masquée dans
/// balades_ludiques_points_complet sauf pour le créateur) — avant, elle
/// était téléchargée sur le téléphone et comparée localement (triche).
Future<bool> verifierDefi(String pointId, String reponse) async {
  try {
    final ok = await Supabase.instance.client
        .rpc('pm_verifier_defi', params: {'p_point_id': pointId, 'p_reponse': reponse});
    return ok == true;
  } catch (_) {
    return false;
  }
}

// ─── Palette & constantes partagées au module Balades ludiques ────────────────

const kBlTeal = Color(0xFF0C5C6C);
const kBlGreen = Color(0xFF6E9E57);
const kBlOrange = Color(0xFFC2410C);
const kBlDark = Color(0xFF1F2A2E);

const kBlEspeces = [
  ('tous', 'Toutes espèces', '🐾'),
  ('chien', 'Chien', '🐕'),
  ('chat', 'Chat', '🐈'),
  ('cheval', 'Cheval', '🐴'),
];

const kBlDifficultes = [
  ('facile', 'Facile', Color(0xFF6E9E57)),
  ('modere', 'Modéré', Color(0xFFF59E0B)),
  ('difficile', 'Difficile', Color(0xFFDC2626)),
];

const kBlTypesDefi = [
  ('photo', 'Photo', Icons.camera_alt_outlined),
  ('question', 'Question', Icons.quiz_outlined),
  ('objet_nature', 'Objet / élément naturel', Icons.eco_outlined),
  ('action_animal', 'Action avec son animal', Icons.pets_outlined),
  ('qr_code', 'QR code', Icons.qr_code_scanner_outlined),
  ('gps_seul', 'Localisation GPS', Icons.location_on_outlined),
];

String blDifficulteLabel(String v) =>
    kBlDifficultes.where((d) => d.$1 == v).firstOrNull?.$2 ?? v;

Color blDifficulteColor(String v) =>
    kBlDifficultes.where((d) => d.$1 == v).firstOrNull?.$3 ?? kBlTeal;

String blEspeceLabel(String v) =>
    kBlEspeces.where((e) => e.$1 == v).firstOrNull?.$2 ?? v;

String blEspeceEmoji(String v) =>
    kBlEspeces.where((e) => e.$1 == v).firstOrNull?.$3 ?? '🐾';

String blTypeDefiLabel(String v) =>
    kBlTypesDefi.where((t) => t.$1 == v).firstOrNull?.$2 ?? v;

IconData blTypeDefiIcon(String v) =>
    kBlTypesDefi.where((t) => t.$1 == v).firstOrNull?.$3 ?? Icons.flag_outlined;

String blDureeLabel(int? min) {
  if (min == null) return '';
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final r = min % 60;
  return r == 0 ? '${h}h' : '${h}h${r.toString().padLeft(2, '0')}';
}
