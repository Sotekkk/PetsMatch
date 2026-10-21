// Dates de naissance plausibles — animaux (âge maximum selon l'espèce) et
// personnes (18 à 110 ans). Bornes min/max des champs date + messages d'erreur.
// Miroir appli : lib/utils/ages_plausibles.dart.

/** Longévité maximale raisonnable (années) — au-delà, la date est une erreur de saisie. */
const AGE_MAX_ESPECE: Record<string, number> = {
  chien: 30, chat: 35,
  cheval: 50, poney: 50, equide: 60, ane: 60, mule: 50, mulet: 50,
  lapin: 18, cobaye: 12, "cochon d'inde": 12, hamster: 5, gerbille: 6, rat: 5, souris: 4,
  chinchilla: 25, furet: 15, degu: 15, octodon: 15, nac: 30,
  perroquet: 80, oiseau: 80, perruche: 20, canari: 20, poule: 15, volaille: 15, canard: 20, oie: 30,
  tortue: 120, reptile: 100, serpent: 40, lezard: 30,
  poisson: 40,
  chevre: 25, caprin: 25, mouton: 25, ovin: 25, vache: 30, bovin: 30, cochon: 25, porcin: 25,
  alpaga: 30, lama: 30,
};
const AGE_MAX_DEFAUT = 50;
export const AGE_MIN_PERSONNE = 18;
export const AGE_MAX_PERSONNE = 110;

const norm = (s?: string | null) => (s ?? '').toLowerCase().trim().normalize('NFD').replace(/[̀-ͯ]/g, '');

export function ageMaxEspece(espece?: string | null): number {
  const e = norm(espece);
  if (!e) return AGE_MAX_DEFAUT;
  if (AGE_MAX_ESPECE[e]) return AGE_MAX_ESPECE[e];
  const sing = e.endsWith('s') ? e.slice(0, -1) : e;
  if (AGE_MAX_ESPECE[sing]) return AGE_MAX_ESPECE[sing];
  const k = Object.keys(AGE_MAX_ESPECE).find(c => e.includes(c));
  return k ? AGE_MAX_ESPECE[k] : AGE_MAX_DEFAUT;
}

const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const ilYa = (ans: number) => { const d = new Date(); d.setFullYear(d.getFullYear() - ans); return iso(d); };

/** Bornes min / max d'un champ « date de naissance » d'animal (AAAA-MM-JJ). */
export function bornesNaissanceAnimal(espece?: string | null) {
  return { min: ilYa(ageMaxEspece(espece)), max: iso(new Date()) };
}

/** Message d'erreur, ou null si la date est plausible (ou vide). */
export function erreurNaissanceAnimal(date: string | null | undefined, espece?: string | null): string | null {
  const d = (date ?? '').slice(0, 10);
  if (!d) return null;
  const { min, max } = bornesNaissanceAnimal(espece);
  if (d > max) return 'La date de naissance ne peut pas être dans le futur.';
  if (d < min) return `Date peu plausible : cette espèce vit rarement plus de ${ageMaxEspece(espece)} ans.`;
  return null;
}

/** Bornes d'une date de naissance de personne (18 à 110 ans par défaut). */
export function bornesNaissancePersonne(ageMin = AGE_MIN_PERSONNE) {
  return { min: ilYa(AGE_MAX_PERSONNE), max: ilYa(ageMin) };
}

export function erreurNaissancePersonne(date: string | null | undefined, ageMin = AGE_MIN_PERSONNE): string | null {
  const d = (date ?? '').slice(0, 10);
  if (!d) return null;
  const { min, max } = bornesNaissancePersonne(ageMin);
  if (d > max) return `Vous devez avoir au moins ${ageMin} ans.`;
  if (d < min) return 'Date de naissance invalide.';
  return null;
}
