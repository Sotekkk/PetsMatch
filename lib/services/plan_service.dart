import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class PlanConfig {
  final String code;
  final String label;
  final int maxAnnonces; // -1 = illimité
  final int dureeDays;
  final bool hasRegistres;
  final String badge;
  final double prixMensuel;
  final double prixAnnuel;

  const PlanConfig({
    required this.code,
    required this.label,
    required this.maxAnnonces,
    required this.dureeDays,
    required this.hasRegistres,
    required this.badge,
    this.prixMensuel = 0,
    this.prixAnnuel = 0,
  });
}

class PlanService {
  static const String kWebsiteUrl = 'https://www.petsmatchapp.com';

  static const Map<String, PlanConfig> configs = {
    'free': PlanConfig(
      code: 'free', label: 'Gratuit', maxAnnonces: 3, dureeDays: 30,
      hasRegistres: false, badge: '🌱', prixMensuel: 0, prixAnnuel: 0,
    ),
    'pro': PlanConfig(
      code: 'pro', label: 'Pro', maxAnnonces: 10, dureeDays: 45,
      hasRegistres: true, badge: '⚡', prixMensuel: 15, prixAnnuel: 149,
    ),
    'premium': PlanConfig(
      code: 'premium', label: 'Premium', maxAnnonces: -1, dureeDays: 60,
      hasRegistres: true, badge: '👑', prixMensuel: 30, prixAnnuel: 299,
    ),
  };

  static PlanConfig getConfig(String planCode) =>
      configs[planCode] ?? configs['free']!;

  static Future<String> getPlanCode(String uid) async {
    try {
      final res = await Supabase.instance.client
          .from('abonnements')
          .select('plan_code')
          .eq('uid', uid)
          .eq('statut', 'actif')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (res?['plan_code'] as String?) ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

  static Future<int> countActiveAnnonces(String uid) async {
    try {
      final res = await Supabase.instance.client
          .from('annonces')
          .select('id')
          .eq('uid_eleveur', uid)
          .inFilter('statut', ['disponible', 'en_attente', 'pause', 'reserve']);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }
}
