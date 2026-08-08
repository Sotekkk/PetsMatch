import 'package:supabase_flutter/supabase_flutter.dart';

/// Nombre d'étapes métier par type de profil (hors écrans bienvenue/fin
/// communs), voir docs/PetsMatch_Specs_Onboarding_Anatomie.md §3-12.
const Map<String, int> onboardingStepsCount = {
  'eleveur': 4,
  'association': 4,
  'particulier': 3,
  'veterinaire': 4,
  'pension': 4,
  'garde': 4,
  'education': 4,
  'sante': 4,
  'toilettage': 4,
  'photographe': 3,
};

class OnboardingService {
  static final _supa = Supabase.instance.client;

  /// Types de profil couverts par l'onboarding métier (§3-12 du doc).
  /// Les autres profile_type (marechal_ferrant, restauration, taxi_animalier,
  /// petfriendly, partenaire...) n'ont pas de parcours dédié pour l'instant.
  static bool isSupported(String profileType) =>
      onboardingStepsCount.containsKey(profileType);

  static Future<Map<String, dynamic>?> getProgress(String profileId) async {
    if (profileId.isEmpty) return null;
    return await _supa
        .from('onboarding_progress')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle();
  }

  /// True uniquement à la toute première connexion : aucune ligne n'existe
  /// encore pour ce profil. Une fois démarré ou "passé", l'onboarding ne se
  /// relance plus tout seul — accessible ensuite via "Reprendre le guide".
  static Future<bool> shouldAutoLaunch(String profileId, String profileType) async {
    if (!isSupported(profileType)) return false;
    return await getProgress(profileId) == null;
  }

  static Future<bool> isCompleted(String profileId) async {
    final row = await getProgress(profileId);
    return row?['completed_at'] != null;
  }

  /// Étapes restantes, pour le bandeau "Finalisez votre profil — X étapes
  /// restantes". Retourne 0 si complété ou si le type n'a pas d'onboarding.
  static Future<int> remainingSteps(String profileId, String profileType) async {
    final total = onboardingStepsCount[profileType];
    if (total == null) return 0;
    final row = await getProgress(profileId);
    if (row == null) return total;
    if (row['completed_at'] != null) return 0;
    final done = (row['completed_steps'] as List?)?.length ?? 0;
    return (total - done).clamp(0, total);
  }

  /// Marque une étape comme complétée (crée la ligne de progression si besoin).
  static Future<void> markStepCompleted(String profileId, String stepKey) async {
    final row = await getProgress(profileId);
    final steps = <String>{
      ...?(row?['completed_steps'] as List?)?.map((e) => e.toString()),
      stepKey,
    }.toList();
    await _supa.from('onboarding_progress').upsert(
      {'profile_id': profileId, 'completed_steps': steps},
      onConflict: 'profile_id',
    );
  }

  static Future<void> markCompleted(String profileId) async {
    await _supa.from('onboarding_progress').upsert(
      {
        'profile_id': profileId,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'profile_id',
    );
  }

  /// Bouton "Passer" — n'efface pas la progression déjà faite, empêche juste
  /// le relance automatique. Le bandeau de rappel reste affiché tant que
  /// completed_at est null.
  static Future<void> markSkipped(String profileId) async {
    await _supa.from('onboarding_progress').upsert(
      {'profile_id': profileId, 'skipped': true},
      onConflict: 'profile_id',
    );
  }

  /// "Reprendre le guide" (Paramètres) — relance le parcours depuis le début.
  static Future<void> reset(String profileId) async {
    await _supa.from('onboarding_progress').upsert(
      {
        'profile_id': profileId,
        'completed_steps': <String>[],
        'completed_at': null,
        'skipped': false,
      },
      onConflict: 'profile_id',
    );
  }
}
