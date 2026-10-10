// Menu « Annonces » unifié (animaux + matériel & équipements) : quelles
// annonces d'animaux le profil actif peut gérer / publier. Le matériel &
// équipements est ouvert à tous les profils connectés. Miroir appli :
// lib/utils/annonces_droits.dart.

export interface DroitsAnnonces {
  /** Page « Mes annonces » du profil (animaux + matériel). */
  mesAnnonces: string;
  /** Annonces d'animaux autorisées pour ce profil (null = matériel seul). */
  animaux: { creer: string; libelle: string; detail: string } | null;
}

export const PROFILS_PRO = new Set(['veterinaire', 'sante', 'education', 'garde', 'pension', 'toilettage', 'photographe', 'marechal_ferrant', 'taxi_animalier']);

export function droitsAnnonces(typeProfil: string | null | undefined): DroitsAnnonces {
  if (typeProfil === 'association') {
    return {
      mesAnnonces: '/association/annonces',
      animaux: { creer: '/association/annonces/creer', libelle: 'Animal', detail: 'Annonce d’adoption pour un animal de l’association.' },
    };
  }
  if (typeProfil === 'eleveur') {
    return {
      mesAnnonces: '/mes-annonces',
      animaux: { creer: '/annonces/creer', libelle: 'Animal', detail: 'Compagnon, portée ou saillie, selon votre formule.' },
    };
  }
  if (typeProfil === 'particulier') {
    return {
      mesAnnonces: '/mes-annonces',
      animaux: { creer: '/annonces/creer-cheval', libelle: 'Animal', detail: 'Annonce pour un cheval (vente, location, demi-pension…).' },
    };
  }
  return { mesAnnonces: '/mes-annonces', animaux: null };
}

export type TypeAnnonceFiltre = 'toutes' | 'animaux' | 'materiel';

export const FILTRES_TYPE: { k: TypeAnnonceFiltre; label: string }[] = [
  { k: 'toutes', label: 'Toutes' },
  { k: 'animaux', label: 'Animaux' },
  { k: 'materiel', label: 'Matériel & équipements' },
];

export function lireFiltreType(v: string | null): TypeAnnonceFiltre {
  return v === 'animaux' || v === 'materiel' ? v : 'toutes';
}
