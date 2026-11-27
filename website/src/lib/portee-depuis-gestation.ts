// Portée créée depuis une gestation (mise bas réelle saisie) : mère = la
// femelle, père = le mâle des saillies du cycle (vide s'il y en a plusieurs :
// filiation à faire), race des parents si identique, date de naissance =
// date de mise bas, un petit par « Nb nés ». Lien gestation → portée :
// gestations.portee_id (migration_gestation_portee.sql).
// Miroir appli : lib/utils/portee_depuis_gestation.dart.
import { supabase } from '@/lib/supabase';

export interface AnimalParent {
  id: string; nom?: string | null; nom_pedigree?: string | null; sexe?: string | null; espece?: string | null;
  race?: string | null; identification?: string | null; date_naissance?: string | null;
  uid_eleveur?: string | null; profile_id?: string | null; photo_url?: string | null;
}

export interface PorteeDepuisGestation {
  gestationId: string;
  espece: string;
  /** AAAA-MM-JJ */
  dateNaissance: string;
  nbNes: number;
  mere: AnimalParent;
  /** Père de l'élevage, si un seul mâle et qu'il a une fiche. */
  pere: AnimalParent | null;
  /** Père extérieur (saillie avec un mâle hors élevage). */
  pereNom: string;
  perePuce: string;
  /** Race commune des parents ; vide si à préciser. */
  race: string;
  alerteRace: string | null;
  /** Plusieurs mâles sur le cycle : père non rempli (filiation à faire). */
  malesMultiples: string[];
}

export const filiationAFaire = (p: PorteeDepuisGestation) => p.malesMultiples.length > 1;
export const mentionFiliation = (p: PorteeDepuisGestation) =>
  `Père à confirmer : saillies de ${p.malesMultiples.join(' et ')}. Filiation (test ADN) à faire pour confirmer la parenté.`;

const t = (v: unknown) => String(v ?? '').trim();
const SEL = 'id, nom, nom_pedigree, sexe, espece, race, identification, date_naissance, uid_eleveur, profile_id, photo_url';

function datesSaillie(s: Record<string, unknown>): Date[] {
  const out: Date[] = [];
  if (Array.isArray(s.dates)) for (const v of s.dates) { const d = new Date(String(v)); if (!isNaN(d.getTime())) out.push(d); }
  if (!out.length && s.date) { const d = new Date(String(s.date)); if (!isNaN(d.getTime())) out.push(d); }
  return out;
}

/** null si la gestation n'a pas de mise bas réelle ou de nombre de nés. */
export async function preparerPorteeDepuisGestation(gestationId: string): Promise<PorteeDepuisGestation | null> {
  const { data: g } = await supabase.from('gestations').select('*').eq('id', gestationId).maybeSingle();
  if (!g) return null;
  const naissance = t(g.date_naissance).slice(0, 10);
  const nb = parseInt(t(g.nb_nes), 10) || 0;
  if (!naissance || nb <= 0) return null;
  const { data: mere } = await supabase.from('animaux').select(SEL).eq('id', t(g.animal_id)).maybeSingle();
  if (!mere) return null;

  // Saillies du cycle : celle d'où vient la gestation (id « <saillie>_gest »)
  // et toutes celles de la femelle autour de la conception (± 21 jours).
  const conception = new Date(t(g.date) || naissance);
  const { data: ss } = await supabase.from('saillies').select('*').eq('animal_id', t(g.animal_id));
  const source = gestationId.endsWith('_gest') ? gestationId.slice(0, -5) : '';
  const duCycle = ((ss ?? []) as Record<string, unknown>[]).filter(s =>
    t(s.id) === source || datesSaillie(s).some(d => Math.abs(d.getTime() - conception.getTime()) <= 21 * 86400000));

  // Mâles distincts (fiche, sinon nom saisi).
  const males = new Map<string, { id: string; nom: string; puce: string }>();
  for (const s of duCycle) {
    const id = t(s.male_id);
    const nom = t(s.male_name) || t(s.nom_partenaire);
    const cle = id ? `id:${id}` : `nom:${nom.toLowerCase()}`;
    if (cle === 'nom:') continue;
    if (!males.has(cle)) males.set(cle, { id, nom, puce: t(s.ident_partenaire) });
  }

  let pere: AnimalParent | null = null;
  let pereNom = '', perePuce = '';
  const noms = [...males.values()].map(m => m.nom || 'mâle inconnu');
  if (males.size === 1) {
    const m = [...males.values()][0];
    if (m.id) pere = ((await supabase.from('animaux').select(SEL).eq('id', m.id).maybeSingle()).data as AnimalParent | null) ?? null;
    if (!pere) { pereNom = m.nom; perePuce = m.puce; }
  }

  // Race : celle des parents si identique ; père incertain → race commune de
  // la mère et de tous les mâles possibles.
  const raceMere = t(mere.race);
  const racesPere: string[] = [];
  if (pere) racesPere.push(t(pere.race));
  else if (males.size > 1) {
    for (const m of males.values()) {
      if (!m.id) { racesPere.push(''); continue; }
      const { data: a } = await supabase.from('animaux').select('race').eq('id', m.id).maybeSingle();
      racesPere.push(t(a?.race));
    }
  }
  const memeRace = !!raceMere && racesPere.length > 0 && racesPere.every(r => r.toLowerCase() === raceMere.toLowerCase());
  const alerteRace = memeRace ? null
    : racesPere.length === 0 || racesPere.includes('')
      ? "Race à préciser : la race du père n'est pas connue."
      : "Race à préciser : les parents n'ont pas la même race.";

  return {
    gestationId,
    espece: t(mere.espece) || 'chien',
    dateNaissance: naissance,
    nbNes: Math.min(nb, 30),
    mere: mere as AnimalParent,
    pere, pereNom, perePuce,
    race: memeRace ? raceMere : '',
    alerteRace,
    malesMultiples: males.size > 1 ? noms : [],
  };
}

/** Nom provisoire d'un petit (modifiable ensuite). */
export function nomProvisoirePetit(espece: string, i: number): string {
  const mots: Record<string, string> = { chien: 'Chiot', chat: 'Chaton', cheval: 'Poulain', lapin: 'Lapereau', ane: 'Ânon',
    ovin: 'Agneau', caprin: 'Chevreau', porcin: 'Porcelet' };
  return `${mots[espece] ?? 'Petit'} ${i}`;
}
