import { supabase } from '@/lib/supabase';

// Nombre d'étapes métier par type de profil (hors écrans bienvenue/fin
// communs) — doit rester synchro avec onboardingStepsCount dans
// lib/services/onboarding_service.dart (app Flutter).
export const onboardingStepsCount: Record<string, number> = {
  eleveur: 4,
  association: 4,
  particulier: 3,
  veterinaire: 4,
  pension: 4,
  garde: 4,
  education: 4,
  sante: 4,
  toilettage: 4,
  photographe: 3,
};

export function isSupported(profileType: string): boolean {
  return profileType in onboardingStepsCount;
}

export interface OnboardingProgressRow {
  id: string;
  profile_id: string;
  completed_steps: string[];
  completed_at: string | null;
  skipped: boolean;
  created_at: string;
}

export async function getProgress(profileId: string): Promise<OnboardingProgressRow | null> {
  if (!profileId) return null;
  const { data } = await supabase
    .from('onboarding_progress')
    .select('*')
    .eq('profile_id', profileId)
    .maybeSingle();
  return (data as OnboardingProgressRow | null) ?? null;
}

/** True uniquement à la toute première connexion : aucune ligne n'existe
 * encore pour ce profil. */
export async function shouldAutoLaunch(profileId: string, profileType: string): Promise<boolean> {
  if (!isSupported(profileType)) return false;
  const row = await getProgress(profileId);
  return row === null;
}

export async function isCompleted(profileId: string): Promise<boolean> {
  const row = await getProgress(profileId);
  return row?.completed_at != null;
}

/** Étapes restantes, pour le bandeau "Finalisez votre profil". */
export async function remainingSteps(profileId: string, profileType: string): Promise<number> {
  const total = onboardingStepsCount[profileType];
  if (!total) return 0;
  const row = await getProgress(profileId);
  if (!row) return total;
  if (row.completed_at) return 0;
  const done = row.completed_steps?.length ?? 0;
  return Math.max(0, Math.min(total, total - done));
}

export async function markStepCompleted(profileId: string, stepKey: string): Promise<void> {
  const row = await getProgress(profileId);
  const steps = Array.from(new Set([...(row?.completed_steps ?? []), stepKey]));
  await supabase.from('onboarding_progress').upsert(
    { profile_id: profileId, completed_steps: steps },
    { onConflict: 'profile_id' },
  );
}

export async function markCompleted(profileId: string): Promise<void> {
  await supabase.from('onboarding_progress').upsert(
    { profile_id: profileId, completed_at: new Date().toISOString() },
    { onConflict: 'profile_id' },
  );
}

/** Bouton "Passer" — n'efface pas la progression déjà faite, empêche juste
 * le relance automatique. */
export async function markSkipped(profileId: string): Promise<void> {
  await supabase.from('onboarding_progress').upsert(
    { profile_id: profileId, skipped: true },
    { onConflict: 'profile_id' },
  );
}

/** "Reprendre le guide" (relance complète depuis le début). */
export async function resetProgress(profileId: string): Promise<void> {
  await supabase.from('onboarding_progress').upsert(
    { profile_id: profileId, completed_steps: [], completed_at: null, skipped: false },
    { onConflict: 'profile_id' },
  );
}
