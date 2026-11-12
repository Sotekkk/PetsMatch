// Registre sanitaire : à quel registre une saisie appartient (profil actif) et
// qui l'a faite quand « Administré par » est laissé vide (la personne
// connectée). Miroir appli : RegistreHelper.writeActe / moiIntervenant
// (lib/pages/eleveur/admin/registre_sanitaire.dart).
import type { Profile, UserData } from '@/lib/auth-context';

export function sourceRegistre(profils: Profile[], activeProfileId: string | null | undefined, userData?: UserData | null): 'association' | 'pension' | 'eleveur' {
  const t = profils.find(p => p.id === activeProfileId)?.profile_type ?? (activeProfileId ? null : userData?.profileType ?? null);
  if (t === 'association') return 'association';
  if (t === 'pension') return 'pension';
  return 'eleveur';
}

export function moiIntervenant(userData?: UserData | null): string {
  return [userData?.firstname, userData?.lastname].map(x => (x ?? '').trim()).filter(Boolean).join(' ');
}
