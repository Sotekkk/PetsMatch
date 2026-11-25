// Animaux d'une facture (tous ceux de ses lignes, avec leur identification),
// rappelés sous « Désignation : ».
// Miroir appli : lib/utils/facture_animaux.dart.

/** Animal d'une ligne qui en couvre plusieurs (acompte groupé). */
export interface AnimalLigne { id?: string | null; nom?: string | null; identification?: string | null }
export interface AnimalFacture { nom: string; identification: string }

interface LigneAnimaux {
  animalId?: string | null; animalNom?: string | null; animalIdentification?: string | null;
  commune?: boolean;
  animaux?: AnimalLigne[] | null;
}

const t = (v: unknown) => String(v ?? '').trim();

/** Animaux des lignes, sans doublon, dans l'ordre d'apparition. */
export function animauxDeLaFacture(lignes: LigneAnimaux[]): AnimalFacture[] {
  const vus = new Map<string, AnimalFacture>();
  const ajouter = (id: unknown, nom: unknown, ident: unknown) => {
    const cle = t(id) || t(nom);
    if (!cle || vus.get(cle)?.identification) return;
    vus.set(cle, { nom: t(nom) || 'Animal', identification: t(ident) });
  };
  for (const l of lignes) {
    for (const a of l.animaux ?? []) ajouter(a.id, a.nom, a.identification);
    if (!l.commune) ajouter(l.animalId, l.animalNom, l.animalIdentification);
  }
  return [...vus.values()];
}

export const titreAnimaux = (n: number) => n > 1 ? 'Animaux :' : 'Animal :';

export const libelleAnimalFacture = (a: AnimalFacture) =>
  a.identification ? `${a.nom} — Identification : ${a.identification}` : a.nom;
