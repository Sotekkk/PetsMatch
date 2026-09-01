// Helpers partagés pour la vitrine « Reproducteurs » du profil public éleveur.

export const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', cheval: 'Cheval', lapin: 'Lapin',
  oiseau: 'Oiseau', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin',
  porcin: 'Porcin', furet: 'Furet', autre: 'Autre',
};

export const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐶', chat: '🐱', cheval: '🐴', lapin: '🐰', oiseau: '🐦',
  nac: '🐹', ovin: '🐑', caprin: '🐐', porcin: '🐷', furet: '🦫', autre: '🐾',
};

export interface Repro {
  id: string;
  nom: string | null;
  nom_pedigree: string | null;
  espece: string | null;
  race: string | null;
  sexe: string | null;
  photo_url: string | null;
  date_naissance: string | null;
  couleur: string | null;
  pedigree_lof: string | null;
  pedigree_numero: string | null;
  club_registre: string | null;
  description: string | null;
  is_retraite: boolean | null;
}

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function ageLabel(iso?: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  const now = new Date();
  let mois = (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth());
  if (now.getDate() < d.getDate()) mois -= 1;
  if (mois < 0) mois = 0;
  if (mois < 12) return `${mois} mois`;
  const ans = Math.floor(mois / 12);
  return `${ans} an${ans > 1 ? 's' : ''}`;
}

export function sexeSymbol(sexe?: string | null): string {
  const s = (sexe ?? '').toLowerCase();
  if (s.startsWith('m')) return '♂';
  if (s.startsWith('f')) return '♀';
  return '';
}
