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

class PensionPlanConfig {
  final String code;
  final String label;
  final bool hasInventaire;
  final bool hasEmployes;
  final int maxEmployes; // -1 = illimité
  final bool logementsIllimites;
  final int maxLogements; // -1 = illimité
  final bool hasProtocoles;
  final bool hasContratSignature;
  final bool hasFactureExport;
  final bool hasBadgePremium;
  final double prixMensuel;
  final double prixAnnuel;

  const PensionPlanConfig({
    required this.code,
    required this.label,
    required this.hasInventaire,
    required this.hasEmployes,
    required this.maxEmployes,
    required this.logementsIllimites,
    required this.maxLogements,
    required this.hasProtocoles,
    required this.hasContratSignature,
    required this.hasFactureExport,
    required this.hasBadgePremium,
    this.prixMensuel = 0,
    this.prixAnnuel = 0,
  });
}

class EducationPlanConfig {
  final String code;
  final String label;
  final bool hasEmployes;
  final int maxEmployes; // -1 = illimité
  final bool hasFactureExport;
  final bool hasBadgePremium;
  final bool hasAccesPrioritaire;
  final double prixMensuel;
  final double prixAnnuel;

  const EducationPlanConfig({
    required this.code,
    required this.label,
    required this.hasEmployes,
    required this.maxEmployes,
    required this.hasFactureExport,
    required this.hasBadgePremium,
    required this.hasAccesPrioritaire,
    this.prixMensuel = 0,
    this.prixAnnuel = 0,
  });
}

class GardePlanConfig {
  final String code;
  final String label;
  final bool hasInventaire;
  final bool hasEmployes;
  final int maxEmployes; // -1 = illimité
  final bool hasProtocoles;
  final bool hasFactureExport;
  final bool hasBadgePremium;
  final double prixMensuel;
  final double prixAnnuel;

  const GardePlanConfig({
    required this.code,
    required this.label,
    required this.hasInventaire,
    required this.hasEmployes,
    required this.maxEmployes,
    required this.hasProtocoles,
    required this.hasFactureExport,
    required this.hasBadgePremium,
    this.prixMensuel = 0,
    this.prixAnnuel = 0,
  });
}

class SantePlanConfig {
  final String code;
  final String label;
  final bool hasAjoutSeances;
  final bool hasFactureExport;
  final bool hasMultiIntervenants;
  final int maxIntervenants; // -1 = illimité
  final double prixMensuel;
  final double prixAnnuel;

  const SantePlanConfig({
    required this.code,
    required this.label,
    required this.hasAjoutSeances,
    required this.hasFactureExport,
    required this.hasMultiIntervenants,
    required this.maxIntervenants,
    this.prixMensuel = 0,
    this.prixAnnuel = 0,
  });
}

class ToilettagePlanConfig {
  final String code;
  final String label;
  final bool hasEmployesIllimites;
  final int maxEmployes; // -1 = illimité
  final bool hasFacturation;
  final bool hasStatistiques;
  final bool hasGalerie;
  final bool hasNotifications;
  final bool hasExport;
  final bool hasPlanningEmployes;
  final bool hasContratSignature;
  final bool hasPaiementEnLigne;
  final bool hasSyncGoogleAgenda;
  final bool hasMiseEnAvant;
  final double prixMensuel;
  final double prixAnnuel;

  const ToilettagePlanConfig({
    required this.code,
    required this.label,
    required this.hasEmployesIllimites,
    required this.maxEmployes,
    required this.hasFacturation,
    required this.hasStatistiques,
    required this.hasGalerie,
    required this.hasNotifications,
    required this.hasExport,
    required this.hasPlanningEmployes,
    required this.hasContratSignature,
    required this.hasPaiementEnLigne,
    required this.hasSyncGoogleAgenda,
    required this.hasMiseEnAvant,
    this.prixMensuel = 0,
    this.prixAnnuel = 0,
  });
}

class PlanService {
  static const String kWebsiteUrl = 'https://www.petsmatchapp.com';

  // Fallback statique si plans_tarifaires est indisponible — les prix affichés
  // à l'utilisateur viennent toujours de la BDD (éditable depuis l'admin).
  static const Map<String, PensionPlanConfig> pensionConfigs = {
    'free': PensionPlanConfig(
      code: 'free', label: 'Découverte', hasInventaire: false, hasEmployes: false, maxEmployes: 0,
      logementsIllimites: false, maxLogements: 1, hasProtocoles: false, hasContratSignature: false,
      hasFactureExport: false, hasBadgePremium: false, prixMensuel: 0, prixAnnuel: 0,
    ),
    'pro': PensionPlanConfig(
      code: 'pro', label: 'Pro', hasInventaire: true, hasEmployes: true, maxEmployes: 3,
      logementsIllimites: true, maxLogements: -1, hasProtocoles: true, hasContratSignature: true,
      hasFactureExport: true, hasBadgePremium: false, prixMensuel: 14, prixAnnuel: 140,
    ),
    'premium': PensionPlanConfig(
      code: 'premium', label: 'Premium', hasInventaire: true, hasEmployes: true, maxEmployes: -1,
      logementsIllimites: true, maxLogements: -1, hasProtocoles: true, hasContratSignature: true,
      hasFactureExport: true, hasBadgePremium: true, prixMensuel: 24, prixAnnuel: 240,
    ),
  };

  static PensionPlanConfig getPensionConfig(String planCode) =>
      pensionConfigs[planCode] ?? pensionConfigs['free']!;

  /// Tarifs pension à jour depuis plans_tarifaires (éditables depuis l'admin
  /// web sans déploiement). Retombe sur pensionConfigs si la BDD est injoignable.
  static Future<Map<String, PensionPlanConfig>> getPensionPlansLive() async {
    try {
      final rows = await Supabase.instance.client
          .from('plans_tarifaires')
          .select('plan_code, label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', 'pension')
          .eq('actif', true);
      final out = <String, PensionPlanConfig>{};
      for (final row in (rows as List)) {
        final code = row['plan_code'] as String?;
        if (code == null) continue;
        final fallback = getPensionConfig(code);
        final f = (row['features'] as Map<String, dynamic>?) ?? {};
        out[code] = PensionPlanConfig(
          code: code,
          label: (row['label'] as String?) ?? fallback.label,
          hasInventaire: f['hasInventaire'] as bool? ?? fallback.hasInventaire,
          hasEmployes: f['hasEmployes'] as bool? ?? fallback.hasEmployes,
          maxEmployes: (f['maxEmployes'] as num?)?.toInt() ?? fallback.maxEmployes,
          logementsIllimites: f['logementsIllimites'] as bool? ?? fallback.logementsIllimites,
          maxLogements: (f['maxLogements'] as num?)?.toInt() ?? fallback.maxLogements,
          hasProtocoles: f['hasProtocoles'] as bool? ?? fallback.hasProtocoles,
          hasContratSignature: f['hasContratSignature'] as bool? ?? fallback.hasContratSignature,
          hasFactureExport: f['hasFactureExport'] as bool? ?? fallback.hasFactureExport,
          hasBadgePremium: f['hasBadgePremium'] as bool? ?? fallback.hasBadgePremium,
          prixMensuel: (row['prix_mensuel'] as num?)?.toDouble() ?? fallback.prixMensuel,
          prixAnnuel: (row['prix_annuel'] as num?)?.toDouble() ?? fallback.prixAnnuel,
        );
      }
      return out.isEmpty ? pensionConfigs : out;
    } catch (_) {
      return pensionConfigs;
    }
  }

  /// Plan pension actif pour ce uid — distinct du plan éleveur (abonnements
  /// est scopé par profil_type, un même compte peut avoir les deux).
  static Future<String> getPensionPlanCode(String uid) async {
    try {
      final res = await Supabase.instance.client
          .from('abonnements')
          .select('plan_code')
          .eq('uid', uid)
          .eq('profil_type', 'pension')
          .eq('statut', 'actif')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (res?['plan_code'] as String?) ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

  static const Map<String, EducationPlanConfig> educationConfigs = {
    'free': EducationPlanConfig(
      code: 'free', label: 'Découverte', hasEmployes: false, maxEmployes: 0,
      hasFactureExport: false, hasBadgePremium: false, hasAccesPrioritaire: false,
      prixMensuel: 0, prixAnnuel: 0,
    ),
    'pro': EducationPlanConfig(
      code: 'pro', label: 'Pro', hasEmployes: true, maxEmployes: 3,
      hasFactureExport: true, hasBadgePremium: false, hasAccesPrioritaire: false,
      prixMensuel: 14, prixAnnuel: 140,
    ),
    'premium': EducationPlanConfig(
      code: 'premium', label: 'Premium', hasEmployes: true, maxEmployes: -1,
      hasFactureExport: true, hasBadgePremium: true, hasAccesPrioritaire: true,
      prixMensuel: 24, prixAnnuel: 240,
    ),
  };

  static EducationPlanConfig getEducationConfig(String planCode) =>
      educationConfigs[planCode] ?? educationConfigs['free']!;

  /// Tarifs éducateur à jour depuis plans_tarifaires (éditables depuis
  /// l'admin web sans déploiement). Retombe sur educationConfigs si la BDD
  /// est injoignable.
  static Future<Map<String, EducationPlanConfig>> getEducationPlansLive() async {
    try {
      final rows = await Supabase.instance.client
          .from('plans_tarifaires')
          .select('plan_code, label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', 'education')
          .eq('actif', true);
      final out = <String, EducationPlanConfig>{};
      for (final row in (rows as List)) {
        final code = row['plan_code'] as String?;
        if (code == null) continue;
        final fallback = getEducationConfig(code);
        final f = (row['features'] as Map<String, dynamic>?) ?? {};
        out[code] = EducationPlanConfig(
          code: code,
          label: (row['label'] as String?) ?? fallback.label,
          hasEmployes: f['hasEmployes'] as bool? ?? fallback.hasEmployes,
          maxEmployes: (f['maxEmployes'] as num?)?.toInt() ?? fallback.maxEmployes,
          hasFactureExport: f['hasFactureExport'] as bool? ?? fallback.hasFactureExport,
          hasBadgePremium: f['hasBadgePremium'] as bool? ?? fallback.hasBadgePremium,
          hasAccesPrioritaire: f['hasAccesPrioritaire'] as bool? ?? fallback.hasAccesPrioritaire,
          prixMensuel: (row['prix_mensuel'] as num?)?.toDouble() ?? fallback.prixMensuel,
          prixAnnuel: (row['prix_annuel'] as num?)?.toDouble() ?? fallback.prixAnnuel,
        );
      }
      return out.isEmpty ? educationConfigs : out;
    } catch (_) {
      return educationConfigs;
    }
  }

  /// Plan éducateur actif pour ce uid — distinct du plan éleveur/pension
  /// (abonnements est scopé par profil_type).
  static Future<String> getEducationPlanCode(String uid) async {
    try {
      final res = await Supabase.instance.client
          .from('abonnements')
          .select('plan_code')
          .eq('uid', uid)
          .eq('profil_type', 'education')
          .eq('statut', 'actif')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (res?['plan_code'] as String?) ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

  static const Map<String, GardePlanConfig> gardeConfigs = {
    'free': GardePlanConfig(
      code: 'free', label: 'Découverte', hasInventaire: false, hasEmployes: false, maxEmployes: 0,
      hasProtocoles: false, hasFactureExport: false, hasBadgePremium: false,
      prixMensuel: 0, prixAnnuel: 0,
    ),
    'pro': GardePlanConfig(
      code: 'pro', label: 'Pro', hasInventaire: true, hasEmployes: true, maxEmployes: 3,
      hasProtocoles: true, hasFactureExport: true, hasBadgePremium: false,
      prixMensuel: 14, prixAnnuel: 140,
    ),
    'premium': GardePlanConfig(
      code: 'premium', label: 'Premium', hasInventaire: true, hasEmployes: true, maxEmployes: -1,
      hasProtocoles: true, hasFactureExport: true, hasBadgePremium: true,
      prixMensuel: 24, prixAnnuel: 240,
    ),
  };

  static GardePlanConfig getGardeConfig(String planCode) =>
      gardeConfigs[planCode] ?? gardeConfigs['free']!;

  /// Tarifs garde (petsitter/promeneur) à jour depuis plans_tarifaires
  /// (éditables depuis l'admin web sans déploiement). Retombe sur
  /// gardeConfigs si la BDD est injoignable.
  static Future<Map<String, GardePlanConfig>> getGardePlansLive() async {
    try {
      final rows = await Supabase.instance.client
          .from('plans_tarifaires')
          .select('plan_code, label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', 'garde')
          .eq('actif', true);
      final out = <String, GardePlanConfig>{};
      for (final row in (rows as List)) {
        final code = row['plan_code'] as String?;
        if (code == null) continue;
        final fallback = getGardeConfig(code);
        final f = (row['features'] as Map<String, dynamic>?) ?? {};
        out[code] = GardePlanConfig(
          code: code,
          label: (row['label'] as String?) ?? fallback.label,
          hasInventaire: f['hasInventaire'] as bool? ?? fallback.hasInventaire,
          hasEmployes: f['hasEmployes'] as bool? ?? fallback.hasEmployes,
          maxEmployes: (f['maxEmployes'] as num?)?.toInt() ?? fallback.maxEmployes,
          hasProtocoles: f['hasProtocoles'] as bool? ?? fallback.hasProtocoles,
          hasFactureExport: f['hasFactureExport'] as bool? ?? fallback.hasFactureExport,
          hasBadgePremium: f['hasBadgePremium'] as bool? ?? fallback.hasBadgePremium,
          prixMensuel: (row['prix_mensuel'] as num?)?.toDouble() ?? fallback.prixMensuel,
          prixAnnuel: (row['prix_annuel'] as num?)?.toDouble() ?? fallback.prixAnnuel,
        );
      }
      return out.isEmpty ? gardeConfigs : out;
    } catch (_) {
      return gardeConfigs;
    }
  }

  /// Plan garde actif pour ce uid — distinct du plan éleveur/pension/éducateur
  /// (abonnements est scopé par profil_type).
  static Future<String> getGardePlanCode(String uid) async {
    try {
      final res = await Supabase.instance.client
          .from('abonnements')
          .select('plan_code')
          .eq('uid', uid)
          .eq('profil_type', 'garde')
          .eq('statut', 'actif')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (res?['plan_code'] as String?) ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

  // "Soins para-médicaux" — profils santé (ostéo/kiné) et maréchal-ferrant,
  // regroupés sous la même grille tarifaire (Spec §8.1) mais suivis comme des
  // abonnements distincts par profil_type (un compte peut cumuler les deux).
  static const Map<String, SantePlanConfig> santeConfigs = {
    'free': SantePlanConfig(
      code: 'free', label: 'Découverte', hasAjoutSeances: false, hasFactureExport: false,
      hasMultiIntervenants: false, maxIntervenants: 1, prixMensuel: 0, prixAnnuel: 0,
    ),
    'essentiel': SantePlanConfig(
      code: 'essentiel', label: 'Essentiel', hasAjoutSeances: true, hasFactureExport: false,
      hasMultiIntervenants: false, maxIntervenants: 1, prixMensuel: 19, prixAnnuel: 190,
    ),
    'pro': SantePlanConfig(
      code: 'pro', label: 'Pro', hasAjoutSeances: true, hasFactureExport: true,
      hasMultiIntervenants: true, maxIntervenants: 3, prixMensuel: 29, prixAnnuel: 290,
    ),
  };

  static SantePlanConfig getSanteConfig(String planCode) =>
      santeConfigs[planCode] ?? santeConfigs['free']!;

  /// Tarifs santé/maréchal-ferrant à jour depuis plans_tarifaires (éditables
  /// depuis l'admin web sans déploiement). Retombe sur santeConfigs si la BDD
  /// est injoignable. [profilType] : 'sante' ou 'marechal_ferrant'.
  static Future<Map<String, SantePlanConfig>> getSantePlansLive(String profilType) async {
    try {
      final rows = await Supabase.instance.client
          .from('plans_tarifaires')
          .select('plan_code, label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', profilType)
          .eq('actif', true);
      final out = <String, SantePlanConfig>{};
      for (final row in (rows as List)) {
        final code = row['plan_code'] as String?;
        if (code == null) continue;
        final fallback = getSanteConfig(code);
        final f = (row['features'] as Map<String, dynamic>?) ?? {};
        out[code] = SantePlanConfig(
          code: code,
          label: (row['label'] as String?) ?? fallback.label,
          hasAjoutSeances: f['hasAjoutSeances'] as bool? ?? fallback.hasAjoutSeances,
          hasFactureExport: f['hasFactureExport'] as bool? ?? fallback.hasFactureExport,
          hasMultiIntervenants: f['hasMultiIntervenants'] as bool? ?? fallback.hasMultiIntervenants,
          maxIntervenants: (f['maxIntervenants'] as num?)?.toInt() ?? fallback.maxIntervenants,
          prixMensuel: (row['prix_mensuel'] as num?)?.toDouble() ?? fallback.prixMensuel,
          prixAnnuel: (row['prix_annuel'] as num?)?.toDouble() ?? fallback.prixAnnuel,
        );
      }
      return out.isEmpty ? santeConfigs : out;
    } catch (_) {
      return santeConfigs;
    }
  }

  /// Plan santé/maréchal-ferrant actif pour ce uid — distinct des autres
  /// profils (abonnements est scopé par profil_type). [profilType] : 'sante'
  /// ou 'marechal_ferrant'.
  static Future<String> getSantePlanCode(String uid, String profilType) async {
    try {
      final res = await Supabase.instance.client
          .from('abonnements')
          .select('plan_code')
          .eq('uid', uid)
          .eq('profil_type', profilType)
          .eq('statut', 'actif')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (res?['plan_code'] as String?) ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

  // Toiletteur — grille dédiée (pas partagée avec un autre profil_type),
  // GRATUIT/PRO/PREMIUM.
  static const Map<String, ToilettagePlanConfig> toilettageConfigs = {
    'free': ToilettagePlanConfig(
      code: 'free', label: 'Découverte', hasEmployesIllimites: false, maxEmployes: 1,
      hasFacturation: false, hasStatistiques: false, hasGalerie: false, hasNotifications: false,
      hasExport: false, hasPlanningEmployes: false, hasContratSignature: false,
      hasPaiementEnLigne: false, hasSyncGoogleAgenda: false, hasMiseEnAvant: false,
      prixMensuel: 0, prixAnnuel: 0,
    ),
    'pro': ToilettagePlanConfig(
      code: 'pro', label: 'Pro', hasEmployesIllimites: true, maxEmployes: -1,
      hasFacturation: true, hasStatistiques: true, hasGalerie: true, hasNotifications: true,
      hasExport: true, hasPlanningEmployes: false, hasContratSignature: false,
      hasPaiementEnLigne: false, hasSyncGoogleAgenda: false, hasMiseEnAvant: false,
      prixMensuel: 15, prixAnnuel: 150,
    ),
    'premium': ToilettagePlanConfig(
      code: 'premium', label: 'Premium', hasEmployesIllimites: true, maxEmployes: -1,
      hasFacturation: true, hasStatistiques: true, hasGalerie: true, hasNotifications: true,
      hasExport: true, hasPlanningEmployes: true, hasContratSignature: true,
      hasPaiementEnLigne: true, hasSyncGoogleAgenda: true, hasMiseEnAvant: true,
      prixMensuel: 25, prixAnnuel: 250,
    ),
  };

  static ToilettagePlanConfig getToilettageConfig(String planCode) =>
      toilettageConfigs[planCode] ?? toilettageConfigs['free']!;

  /// Tarifs toiletteur à jour depuis plans_tarifaires (éditables depuis
  /// l'admin web sans déploiement). Retombe sur toilettageConfigs si la BDD
  /// est injoignable.
  static Future<Map<String, ToilettagePlanConfig>> getToilettagePlansLive() async {
    try {
      final rows = await Supabase.instance.client
          .from('plans_tarifaires')
          .select('plan_code, label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', 'toilettage')
          .eq('actif', true);
      final out = <String, ToilettagePlanConfig>{};
      for (final row in (rows as List)) {
        final code = row['plan_code'] as String?;
        if (code == null) continue;
        final fallback = getToilettageConfig(code);
        final f = (row['features'] as Map<String, dynamic>?) ?? {};
        out[code] = ToilettagePlanConfig(
          code: code,
          label: (row['label'] as String?) ?? fallback.label,
          hasEmployesIllimites: f['hasEmployesIllimites'] as bool? ?? fallback.hasEmployesIllimites,
          maxEmployes: (f['maxEmployes'] as num?)?.toInt() ?? fallback.maxEmployes,
          hasFacturation: f['hasFacturation'] as bool? ?? fallback.hasFacturation,
          hasStatistiques: f['hasStatistiques'] as bool? ?? fallback.hasStatistiques,
          hasGalerie: f['hasGalerie'] as bool? ?? fallback.hasGalerie,
          hasNotifications: f['hasNotifications'] as bool? ?? fallback.hasNotifications,
          hasExport: f['hasExport'] as bool? ?? fallback.hasExport,
          hasPlanningEmployes: f['hasPlanningEmployes'] as bool? ?? fallback.hasPlanningEmployes,
          hasContratSignature: f['hasContratSignature'] as bool? ?? fallback.hasContratSignature,
          hasPaiementEnLigne: f['hasPaiementEnLigne'] as bool? ?? fallback.hasPaiementEnLigne,
          hasSyncGoogleAgenda: f['hasSyncGoogleAgenda'] as bool? ?? fallback.hasSyncGoogleAgenda,
          hasMiseEnAvant: f['hasMiseEnAvant'] as bool? ?? fallback.hasMiseEnAvant,
          prixMensuel: (row['prix_mensuel'] as num?)?.toDouble() ?? fallback.prixMensuel,
          prixAnnuel: (row['prix_annuel'] as num?)?.toDouble() ?? fallback.prixAnnuel,
        );
      }
      return out.isEmpty ? toilettageConfigs : out;
    } catch (_) {
      return toilettageConfigs;
    }
  }

  /// Plan toiletteur actif pour ce uid — distinct des autres profils
  /// (abonnements est scopé par profil_type).
  static Future<String> getToilettagePlanCode(String uid) async {
    try {
      final res = await Supabase.instance.client
          .from('abonnements')
          .select('plan_code')
          .eq('uid', uid)
          .eq('profil_type', 'toilettage')
          .eq('statut', 'actif')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (res?['plan_code'] as String?) ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

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
