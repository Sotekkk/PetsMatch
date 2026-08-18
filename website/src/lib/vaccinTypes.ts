// Types de vaccins par espèce, avec délai de rappel (années) et durée de
// validité de la première injection (jours) — partagé entre toutes les
// fiches animal du site (mes-animaux/[id] et association/animaux/[id]) pour
// ne jamais diverger entre profils. Même table que l'app Flutter
// (lib/data/vaccin_types.dart).
export const TYPES_VACCIN_PAR_ESPECE: Record<string, { label: string; rappelAns: number; validiteJours: number }[]> = {
  chien: [
    { label: 'Rage', rappelAns: 3, validiteJours: 21 },
    { label: 'CHPPI (Carré, Hépatite, Parvovirose, Parainfluenza)', rappelAns: 1, validiteJours: 0 },
    { label: 'Leptospirose (L4)', rappelAns: 1, validiteJours: 0 },
    { label: 'Toux du chenil (Bordetella)', rappelAns: 1, validiteJours: 0 },
    { label: 'Piroplasmose', rappelAns: 1, validiteJours: 0 },
    { label: 'Autre', rappelAns: 1, validiteJours: 0 },
  ],
  chat: [
    { label: 'Rage', rappelAns: 3, validiteJours: 21 },
    { label: 'Typhus (panleucopénie)', rappelAns: 1, validiteJours: 0 },
    { label: 'Coryza', rappelAns: 1, validiteJours: 0 },
    { label: 'Leucose (FeLV)', rappelAns: 1, validiteJours: 0 },
    { label: 'PIF (coronavirus félin)', rappelAns: 1, validiteJours: 0 },
    { label: 'Autre', rappelAns: 1, validiteJours: 0 },
  ],
  lapin: [
    { label: 'Myxomatose', rappelAns: 1, validiteJours: 0 },
    { label: 'VHD (maladie hémorragique)', rappelAns: 1, validiteJours: 0 },
    { label: 'Autre', rappelAns: 1, validiteJours: 0 },
  ],
  cheval: [
    { label: 'Rage', rappelAns: 3, validiteJours: 21 },
    { label: 'Grippe équine', rappelAns: 1, validiteJours: 0 },
    { label: 'Tétanos', rappelAns: 1, validiteJours: 0 },
    { label: 'Autre', rappelAns: 1, validiteJours: 0 },
  ],
};
// Espèces hors liste ci-dessus (oiseau, nac, ovin, caprin, porcin, autre) :
// choix générique, toujours avec "Autre" pour saisie manuelle libre.
export const TYPES_VACCIN_DEFAUT = [
  { label: 'Rage', rappelAns: 3, validiteJours: 21 },
  { label: 'Autre', rappelAns: 1, validiteJours: 0 },
];
export function typesVaccinPour(espece?: string) {
  return (espece ? TYPES_VACCIN_PAR_ESPECE[espece] : undefined) ?? TYPES_VACCIN_DEFAUT;
}
export function categorieOptions(espece?: string) {
  return [{ value: '', label: 'Sélectionner…' }, ...typesVaccinPour(espece).map(t => ({ value: t.label, label: t.label }))];
}

// Le délai légal (ex: rage = 21 jours) ne s'applique qu'à la toute première
// injection de ce type de vaccin pour cet animal : un rappel d'un vaccin
// déjà administré est valide dès le jour même.
export function suggestFromCategorie(espece: string | undefined, categorie: string, dateInjection: string, dejaVaccine: boolean) {
  const def = typesVaccinPour(espece).find(t => t.label === categorie);
  if (!def || !dateInjection) return null;
  const dInj = new Date(dateInjection);
  if (isNaN(dInj.getTime())) return null;
  const validite = new Date(dInj);
  validite.setDate(validite.getDate() + (dejaVaccine ? 0 : def.validiteJours));
  const rappel = new Date(dInj);
  rappel.setFullYear(rappel.getFullYear() + def.rappelAns);
  return { validite: validite.toISOString().slice(0, 10), rappel: rappel.toISOString().slice(0, 10) };
}
