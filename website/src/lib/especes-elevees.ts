// especes_elevees est stocké sous deux formes selon le parcours de création :
//   • inscription / édition du profil élevage : [{espece: 'chien', races: […]}]
//   • « Ajouter un profil » (avant correctif)  : ['Chien', 'Chat', 'NAC']
// On normalise à la lecture comme à l'écriture (valeurs 'chien', 'nac'…).
// Miroir appli : lib/utils/especes_elevees.dart.

const ALIAS: Record<string, string> = {
  chien: 'chien', chiens: 'chien',
  chat: 'chat', chats: 'chat',
  cheval: 'cheval', chevaux: 'cheval', equide: 'cheval', 'équidé': 'cheval',
  lapin: 'lapin', lapins: 'lapin',
  oiseau: 'oiseau', oiseaux: 'oiseau',
  ovin: 'ovin', caprin: 'caprin', porcin: 'porcin',
  nac: 'nac', rongeur: 'nac', rongeurs: 'nac', reptile: 'nac', reptiles: 'nac',
  autre: 'autre',
};

export function especeCanonique(brut: string | null | undefined): string | null {
  const k = (brut ?? '').trim().toLowerCase();
  return k ? ALIAS[k] ?? null : null;
}

export type EspeceElevee = { espece: string; races: string[] };

/** Espèces élevées normalisées, quelle que soit la forme stockée (tableau, JSON texte, chaînes ou objets). */
export function especesEleveesDepuis(raw: unknown): EspeceElevee[] {
  let liste: unknown = raw;
  if (typeof raw === 'string') { try { liste = JSON.parse(raw); } catch { liste = []; } }
  if (!Array.isArray(liste)) return [];
  const out: EspeceElevee[] = [];
  for (const e of liste) {
    const obj = typeof e === 'object' && e ? e as { espece?: string; races?: string[] } : null;
    const v = especeCanonique(obj ? obj.espece : String(e ?? ''));
    if (!v) continue;
    const deja = out.find(x => x.espece === v);
    const races = Array.isArray(obj?.races) ? obj!.races : [];
    if (deja) deja.races = [...new Set([...deja.races, ...races])];
    else out.push({ espece: v, races });
  }
  return out;
}

/** Forme à enregistrer (celle de l'inscription) : [{espece, races}]. */
export function especesEleveesPourBdd(especes: Iterable<string>): EspeceElevee[] {
  return especesEleveesDepuis([...especes]);
}
