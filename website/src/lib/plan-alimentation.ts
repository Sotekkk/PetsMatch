// Plan d'alimentation par repas — modèle, calculs et contrôles partagés par
// l'onglet Alimentation (propriétaire) et la vue lecture seule (pension,
// pet-sitter, vétérinaire, partage). Miroir exact de
// lib/utils/plan_alimentation.dart : toute règle changée ici doit l'être
// là-bas (mêmes libellés, mêmes seuils, mêmes messages).
//
// Méthodes de calcul selon l'espèce :
//  - chien / chat : énergie (kcal). Adulte : besoin au repos 70 × P^0,75 ×
//    coefficient (activité, stérilisation). Croissance : formules NRC 2006
//    (poids adulte estimé obligatoire). Chaque repas reçoit la même part
//    d'énergie, partagée entre ses aliments selon leur densité (kcal/100 g).
//  - cheval, ovin, caprin, porcin : % du poids vif selon l'activité (comme
//    l'ancien onglet), réparti par type d'aliment (foin 67 / concentrés 28 /
//    compléments 5).
//  - lapin : foin à volonté, granulés 22,5 g/kg, légumes 50 g/kg par jour.
//  - oiseau, NAC, autres : pas de recommandation, quantités saisies.

// ── Espèces ────────────────────────────────────────────────────────────────

export type Methode = 'energie' | 'poids_vif' | 'lapin' | 'aucune';

export interface ProfilEspece {
  methode: Methode;
  types: string[];
  /** Quantités saisies et affichées en kg (grands animaux). */
  uniteKg: boolean;
  /** Types pouvant être servis « à volonté » (sans quantité). */
  typesLibres: string[];
}

const HERBIVORE: ProfilEspece = {
  methode: 'poids_vif', types: ['foin', 'concentre', 'paturage', 'complement', 'autre'], uniteKg: true, typesLibres: ['foin', 'paturage'],
};

export function profilEspece(espece: string): ProfilEspece {
  switch ((espece ?? '').toLowerCase()) {
    case 'chien':
    case 'chat':
      return { methode: 'energie', types: ['croquettes', 'patee', 'barf', 'menagere', 'autre'], uniteKg: false, typesLibres: [] };
    case 'cheval':
    case 'ane':
    case 'ovin':
    case 'caprin':
      return HERBIVORE;
    case 'porcin':
      return { methode: 'poids_vif', types: ['granules', 'menagere', 'legumes', 'autre'], uniteKg: true, typesLibres: [] };
    case 'lapin':
      return { methode: 'lapin', types: ['foin', 'granules', 'legumes', 'autre'], uniteKg: false, typesLibres: ['foin'] };
    case 'oiseau':
      return { methode: 'aucune', types: ['graines', 'granules', 'legumes', 'autre'], uniteKg: false, typesLibres: [] };
    default:
      return { methode: 'aucune', types: ['granules', 'foin', 'legumes', 'graines', 'autre'], uniteKg: false, typesLibres: ['foin'] };
  }
}

export const LIBELLES_TYPE_ALIMENT: Record<string, string> = {
  croquettes: 'Croquettes',
  patee: 'Pâtée / humide',
  barf: 'BARF / cru',
  menagere: 'Ration ménagère',
  autre: 'Autre',
  foin: 'Foin / fourrage',
  concentre: 'Granulés / concentrés',
  paturage: 'Pâturage',
  complement: 'Complément',
  granules: 'Granulés',
  legumes: 'Légumes frais',
  graines: 'Graines / mélange',
};

/** Type du catalogue marques_aliments → type du plan (« pâtée » historique ;
 *  les granulés du catalogue sont enregistrés « croquettes » pour les autres
 *  espèces). */
export function typeDepuisCatalogue(t: string | null | undefined, espece: string): string {
  const p = profilEspece(espece);
  if (t === 'pâtée') return 'patee';
  if (t === 'croquettes' && p.methode !== 'energie') return p.types.includes('concentre') ? 'concentre' : 'granules';
  if (t && p.types.includes(t)) return t;
  return p.types[0];
}

export const typeVersCatalogue = (t: string) => (t === 'patee' ? 'pâtée' : t);

/** Servi à volonté par défaut : pâturage, foin du lapin. */
export const libreParDefaut = (type: string, p: ProfilEspece) =>
  type === 'paturage' || (type === 'foin' && p.methode === 'lapin');

export const ACTIVITES = ['sedentaire', 'normal', 'sportif'] as const;
export const LIBELLES_ACTIVITE: Record<string, string> = { sedentaire: 'Sédentaire', normal: 'Normal', sportif: 'Sportif' };

/** Ancien codage de l'activité (appli : repos…très actif ; site : actif…). */
export function activiteDepuisAncienne(a: string | null | undefined): string {
  switch (a) {
    case 'repos': case 'leger': case 'sedentaire': return 'sedentaire';
    case 'actif': case 'tres_actif': case 'sportif': return 'sportif';
    default: return 'normal';
  }
}

export function libellesRepas(n: number): string[] {
  switch (n) {
    case 1: return ['Repas unique'];
    case 2: return ['Matin', 'Soir'];
    case 3: return ['Matin', 'Midi', 'Soir'];
    case 4: return ['Matin', 'Midi', 'Après-midi', 'Soir'];
    case 5: return ['Matin', 'Milieu de matinée', 'Midi', 'Après-midi', 'Soir'];
    default: return Array.from({ length: n }, (_, i) => `Repas ${i + 1}`);
  }
}

/** Plages habituelles de densité énergétique (kcal/100 g) par type. */
export const PLAGES_KCAL: Record<string, [number, number]> = {
  croquettes: [250, 500], patee: [50, 150], barf: [100, 300], menagere: [80, 250], autre: [20, 600],
};

/** Poids plausibles par espèce (kg) — hors plage : avertissement. */
const POIDS_PLAUSIBLES: Record<string, [number, number]> = {
  chien: [0.5, 110], chat: [0.3, 15], cheval: [50, 1200], ane: [50, 500],
  lapin: [0.3, 10], ovin: [5, 200], caprin: [5, 150], porcin: [5, 350], oiseau: [0.005, 20],
};

/** Repères de composition des préparations maison (ancien onglet). */
export const REPARTITION_BARF: Record<string, number> = { muscles: 70, abats: 10, os: 10, legumes: 10 };
export const REPARTITION_MENAGERE: Record<string, number> = {
  proteines: 40, legumes: 20, feculents: 30, matieres_grasses: 5, complements: 5,
};
export const LIBELLES_REPARTITION: Record<string, string> = {
  muscles: 'Muscles', abats: 'Abats', os: 'Os charnus', legumes: 'Légumes',
  proteines: 'Protéines animales', feculents: 'Féculents', matieres_grasses: 'Matières grasses',
  complements: 'Complément minéral',
};

// ── Saisie des nombres ─────────────────────────────────────────────────────

export interface LectureNombre { v?: number; err?: string }

const RE_NOMBRE = /^\d+(?:[.,]\d+)?$/;

/** Nombre positif, virgule française acceptée, sans unité ni signe. */
export function lireNombre(s: string | null | undefined, zeroAutorise = false): LectureNombre {
  const t = (s ?? '').trim();
  if (!t) return {};
  if (!RE_NOMBRE.test(t)) return { err: 'Saisissez un nombre positif, sans unité (ex. 135).' };
  const v = parseFloat(t.replace(',', '.'));
  if (v === 0 && !zeroAutorise) return { err: 'La valeur doit être supérieure à 0.' };
  return { v };
}

export const fr1 = (n: number) => (Math.round(n * 10) / 10).toFixed(1).replace('.', ',');
const frCoef = (n: number) => String(n).replace('.', ',');

/** Quantité lisible avec son unité : « 135 g » ou « 3,5 kg ». */
export const formatQuantite = (g: number, kg = false) => (kg || g >= 1000 ? `${fr1(g / 1000)} kg` : `${Math.round(g)} g`);

// ── Modèle ────────────────────────────────────────────────────────────────

export interface AlimentPlan {
  id?: string | null; // marques_aliments.id (null : préparation maison / ancien plan)
  marque: string;
  gamme: string;
  type: string;
  kcal?: number | null; // kcal/100 g, null = non renseignée
  source?: string | null; // 'fabricant' | 'composition' (estimation)
  /** Repère de composition d'une préparation maison (%), détaillé en grammes. */
  repartition?: Record<string, number> | null;
  // Non stockés dans le plan : relus du catalogue.
  doses?: unknown[];
  tableauCroissance?: unknown[];
}

export const nomAliment = (a: AlimentPlan) => (a.gamme.trim() ? `${a.marque} — ${a.gamme}` : a.marque);

export interface ItemRepas {
  a: number;
  /** Quantité choisie par le propriétaire (g) ; null = recommandation. */
  g?: number | null;
  /** À volonté (foin, pâturage) : pas de quantité. */
  libre?: boolean;
  /** Quantité enregistrée (lecture seule : pension, partage…). */
  gEnregistre?: number | null;
}

export interface RepasPlan { heure?: string | null; items: ItemRepas[] }

export interface PlanAlimentation {
  mode: 'unique' | 'mixte';
  categories: string[];
  activite: string;
  poidsAdulte?: number | null;
  /** Nombre de petits allaités (lactation), repris de la portée, modifiable. */
  nbPetits?: number | null;
  /** Mise bas (« yyyy-MM-dd ») à laquelle se rapporte nbPetits : une
   *  nouvelle portée remplace la saisie précédente. */
  nbPetitsMiseBas?: string | null;
  aliments: AlimentPlan[];
  repas: RepasPlan[];
  /** Plan reconstitué depuis l'ancien format (pas encore réenregistré). */
  repris?: boolean;
}

export function planNeuf(espece: string): PlanAlimentation {
  const n = espece === 'chat' || espece === 'cheval' ? 3 : 2;
  return { mode: 'unique', categories: [], activite: 'normal', aliments: [], repas: Array.from({ length: n }, () => ({ items: [] })) };
}

const copie = (p: PlanAlimentation): PlanAlimentation => ({
  ...p, categories: [...p.categories], aliments: [...p.aliments],
  repas: p.repas.map(r => ({ ...r, items: r.items.map(it => ({ ...it })) })),
});

/** Change le nombre de repas : les repas ajoutés reçoivent tous les aliments. */
export function changerNbRepas(plan: PlanAlimentation, n: number, profil: ProfilEspece): PlanAlimentation {
  const p = copie(plan);
  p.repas = p.repas.slice(0, n);
  while (p.repas.length < n) {
    p.repas.push({ items: p.aliments.map((a, i) => ({ a: i, libre: libreParDefaut(a.type, profil) })) });
  }
  return p;
}

/** Ajoute un aliment ; il est proposé à tous les repas (décochable ensuite). */
export function ajouterAliment(plan: PlanAlimentation, a: AlimentPlan, profil: ProfilEspece): PlanAlimentation {
  const p = copie(plan);
  if (p.mode === 'unique') {
    p.aliments = [a];
    p.repas = p.repas.map(r => ({ ...r, items: [{ a: 0, libre: libreParDefaut(a.type, profil) }] }));
    return p;
  }
  p.aliments.push(a);
  const idx = p.aliments.length - 1;
  p.repas.forEach(r => r.items.push({ a: idx, libre: libreParDefaut(a.type, profil) }));
  return p;
}

export function retirerAliment(plan: PlanAlimentation, idx: number): PlanAlimentation {
  const p = copie(plan);
  p.aliments.splice(idx, 1);
  p.repas.forEach(r => {
    r.items = r.items.filter(it => it.a !== idx).map(it => (it.a > idx ? { ...it, a: it.a - 1 } : it));
  });
  return p;
}

/** Coche / décoche un aliment pour un repas. */
export function basculer(plan: PlanAlimentation, repasIdx: number, a: number, profil: ProfilEspece): PlanAlimentation {
  const p = copie(plan);
  const r = p.repas[repasIdx];
  const i = r.items.findIndex(it => it.a === a);
  if (i >= 0) r.items.splice(i, 1);
  else {
    r.items.push({ a, libre: libreParDefaut(p.aliments[a].type, profil) });
    r.items.sort((x, y) => x.a - y.a);
  }
  return p;
}

/** Revenir à la ration recommandée : efface les quantités choisies, garde
 *  aliments, repas et horaires. */
export function revenirRecommandation(plan: PlanAlimentation): PlanAlimentation {
  const p = copie(plan);
  p.repas.forEach(r => r.items.forEach(it => { it.g = null; }));
  return p;
}

export const estPersonnalise = (plan: PlanAlimentation) => plan.repas.some(r => r.items.some(it => it.g != null));

export function planVersJson(plan: PlanAlimentation, c: CalculRation) {
  return {
    v: 1,
    mode: plan.mode,
    categories: plan.categories,
    activite: plan.activite,
    poids_adulte: plan.poidsAdulte ?? null,
    nb_petits: plan.nbPetits ?? null,
    nb_petits_mise_bas: plan.nbPetitsMiseBas ?? null,
    enregistre_le: new Date().toISOString(),
    aliments: plan.aliments.map(a => ({
      id: a.id ?? null, marque: a.marque, gamme: a.gamme, type: a.type, kcal: a.kcal ?? null, source: a.source ?? null,
      ...(a.repartition ? { repartition: a.repartition } : {}),
    })),
    repas: plan.repas.map((r, i) => ({
      heure: r.heure ?? null,
      items: r.items.map((it, j) => {
        const eff = c.lignes[i][j].eff;
        return { a: it.a, g: eff != null ? Math.round(eff) : null, perso: it.g != null, ...(it.libre ? { libre: true } : {}) };
      }),
    })),
  };
}

type Json = Record<string, unknown>;
const nombreOuNull = (v: unknown) => (typeof v === 'number' ? v : null);

export function planDepuisJson(j: Json): PlanAlimentation {
  const aliments: AlimentPlan[] = (Array.isArray(j.aliments) ? j.aliments : [])
    .filter((m): m is Json => !!m && typeof m === 'object')
    .map(m => ({
      id: m.id != null ? String(m.id) : null,
      marque: String(m.marque ?? ''),
      gamme: String(m.gamme ?? ''),
      type: String(m.type ?? 'autre'),
      kcal: nombreOuNull(m.kcal),
      source: m.source != null ? String(m.source) : null,
      repartition: m.repartition && typeof m.repartition === 'object' ? (m.repartition as Record<string, number>) : null,
    }));
  const repas: RepasPlan[] = (Array.isArray(j.repas) ? j.repas : [])
    .filter((r): r is Json => !!r && typeof r === 'object')
    .map(r => {
      const items = (Array.isArray(r.items) ? r.items : [])
        .filter((it): it is Json => !!it && typeof it === 'object' && typeof it.a === 'number')
        .map(it => {
          const g = nombreOuNull(it.g);
          return { a: it.a as number, g: it.perso === true ? g : null, libre: it.libre === true, gEnregistre: g };
        })
        .filter(it => it.a >= 0 && it.a < aliments.length);
      const h = r.heure != null ? String(r.heure) : '';
      return { heure: h || null, items };
    });
  return {
    mode: (j.mode === 'mixte' || j.mode === 'unique') ? j.mode : (aliments.length > 1 ? 'mixte' : 'unique'),
    categories: Array.isArray(j.categories) ? j.categories.map(String) : [],
    activite: (ACTIVITES as readonly string[]).includes(String(j.activite)) ? String(j.activite) : 'normal',
    poidsAdulte: nombreOuNull(j.poids_adulte),
    nbPetits: nombreOuNull(j.nb_petits),
    nbPetitsMiseBas: j.nb_petits_mise_bas != null ? String(j.nb_petits_mise_bas) : null,
    aliments,
    repas: repas.length ? repas : [{ items: [] }],
  };
}

// ── Profil animal et besoin ───────────────────────────────────────────────

export interface ProfilAnimal {
  espece: string;
  nom?: string;
  sexe?: string;
  sterilise?: boolean;
  dateNaissance?: string | Date | null;
  poidsKg?: number | null;
  /** 'normal' | 'gestation_debut' | 'gestation_fin' | 'lactation' */
  etatRepro?: string;
  /** Semaine de lactation (1 = première semaine après la mise bas). */
  semaineLactation?: number | null;
}

export function ageMois(p: ProfilAnimal): number | null {
  if (!p.dateNaissance) return null;
  const d = new Date(p.dateNaissance);
  if (isNaN(d.getTime())) return null;
  return Math.floor((Date.now() - d.getTime()) / 86400000) / 30.44;
}

const nomOuAnimal = (p: ProfilAnimal) => (p.nom?.trim() ? p.nom.trim() : 'L’animal');

export interface Besoin {
  /** Énergie (kcal/jour) — chien / chat. */
  kcal?: number;
  /** Ration totale (g/jour) — méthode % du poids vif. */
  totalG?: number;
  /** Donnée indispensable manquante (message à afficher). */
  manque?: string;
  detail: string;
  croissance?: boolean;
  avertissement?: string;
}

/** Coefficient multiplicateur du besoin au repos (chien / chat adultes). */
export function coefficientAdulte(espece: string, sterilise: boolean, activite: string): number {
  const chienSt: Record<string, number> = { sedentaire: 1.4, normal: 1.6, sportif: 2.0 };
  const chienEn: Record<string, number> = { sedentaire: 1.6, normal: 1.8, sportif: 2.2 };
  const chatSt: Record<string, number> = { sedentaire: 1.0, normal: 1.2, sportif: 1.4 };
  const chatEn: Record<string, number> = { sedentaire: 1.2, normal: 1.4, sportif: 1.6 };
  const t = espece === 'chat' ? (sterilise ? chatSt : chatEn) : (sterilise ? chienSt : chienEn);
  return t[activite] ?? t.normal;
}

/** Gestation / lactation chien et chat (NRC 2006), en kcal/jour, sur le
 *  poids réel. Lactation : selon le nombre de petits et la semaine. null :
 *  état normal. `manque` renseigné si le nombre de petits est inconnu. */
function besoinRepro(p: ProfilAnimal, poids: number, nbPetits?: number | null): { kcal?: number; detail: string; manque?: string } | null {
  const chat = p.espece === 'chat';
  switch (p.etatRepro) {
    case 'gestation_debut':
    case 'gestation_fin':
      if (chat) return { kcal: 140 * Math.pow(poids, 0.67), detail: 'Gestation : 140 × P^0,67 (NRC 2006, chatte, toute la gestation).' };
      if (p.etatRepro === 'gestation_debut') return null; // chienne : entretien jusqu'aux 4 dernières semaines
      return { kcal: 132 * Math.pow(poids, 0.75) + 26 * poids, detail: 'Fin de gestation : 132 × P^0,75 + 26 × P (NRC 2006, dernières semaines).' };
    case 'lactation': {
      const n = nbPetits;
      if (n == null || n <= 0) return { detail: '', manque: `${nomOuAnimal(p)} allaite : indiquez le nombre de petits pour calculer sa ration de lactation.` };
      const sem = Math.min(8, Math.max(1, p.semaineLactation ?? 1));
      if (chat) {
        const lChat = [0.9, 0.9, 1.2, 1.2, 1.1, 1.0, 0.8];
        const l = lChat[Math.min(sem, 7) - 1];
        const coef = n <= 2 ? 18 : n <= 4 ? 60 : 70;
        return { kcal: 100 * Math.pow(poids, 0.67) + coef * poids * l,
          detail: `Lactation, ${n} chaton${n > 1 ? 's' : ''}, semaine ${sem} : 100 × P^0,67 + ${coef} × P × ${frCoef(l)} (NRC 2006).` };
      }
      const lChien = [0.75, 0.95, 1.1, 1.2];
      const l = lChien[Math.min(sem, 4) - 1];
      const premiers = Math.min(n, 4), suivants = Math.max(n - 4, 0);
      return { kcal: 145 * Math.pow(poids, 0.75) + poids * (24 * premiers + 12 * suivants) * l,
        detail: `Lactation, ${n} chiot${n > 1 ? 's' : ''}, semaine ${sem} : 145 × P^0,75 + P × (24 × ${premiers}${suivants > 0 ? ` + 12 × ${suivants}` : ''}) × ${frCoef(l)} (NRC 2006).` };
    }
  }
  return null;
}

const facteurRepro = (e?: string) => (e === 'gestation_debut' ? 1.1 : e === 'gestation_fin' ? 1.3 : e === 'lactation' ? 1.5 : 1.0);
const libRepro = (e?: string) =>
  e === 'gestation_debut' ? 'début de gestation ×1,1' : e === 'gestation_fin' ? 'fin de gestation ×1,3' : e === 'lactation' ? 'lactation ×1,5' : '';

/** Âge (mois) jusqu'auquel l'animal est considéré en croissance. */
function finCroissanceMois(espece: string, poidsAdulte?: number | null): number {
  switch (espece) {
    case 'chien': return (poidsAdulte ?? 0) >= 25 ? 18 : 12;
    case 'chat': return 12;
    case 'cheval': case 'ane': return 24;
    case 'lapin': return 4;
    default: return 6;
  }
}

export function calculerBesoin(p: ProfilAnimal, opts: { activite: string; poidsObjectif?: number | null; poidsAdulte?: number | null; nbPetits?: number | null }): Besoin {
  const { activite, poidsObjectif, poidsAdulte, nbPetits } = opts;
  const profil = profilEspece(p.espece);
  const nom = nomOuAnimal(p);
  if (profil.methode === 'aucune') {
    return { detail: 'Pas de calcul automatique pour cette espèce : indiquez les quantités servies.' };
  }
  const poids = p.poidsKg;
  if (poids == null || poids <= 0) {
    return { detail: '', manque: `Le poids de ${nom} n’est pas renseigné : ajoutez une pesée dans la fiche pour calculer la ration.` };
  }
  let avert: string | undefined;
  const plage = POIDS_PLAUSIBLES[p.espece];
  if (plage && (poids < plage[0] || poids > plage[1])) {
    avert = `Le poids enregistré (${fr1(poids)} kg) est inhabituel pour cette espèce : vérifiez la fiche avant de suivre la ration.`;
  }
  const age = ageMois(p);
  const enCroissance = age != null && age < finCroissanceMois(p.espece, poidsAdulte);
  const sterilise = !!p.sterilise;

  if (profil.methode === 'energie') {
    if (age != null && age < 2) {
      return { detail: '', manque: `Avant 8 semaines, la ration de ${nom} est fixée par l’éleveur ou le vétérinaire : PetsMatch ne la calcule pas.` };
    }
    if (enCroissance) {
      if (poidsAdulte == null || poidsAdulte <= 0) {
        return { detail: '', croissance: true,
          manque: `${nom} est en croissance : indiquez son poids adulte estimé (demandez à l’éleveur ou au vétérinaire) pour calculer sa ration.` };
      }
      const ratio = poids / poidsAdulte;
      if (ratio < 1) {
        const kcal = p.espece === 'chat'
          ? 100 * Math.pow(poids, 0.67) * 6.7 * (Math.exp(-0.189 * ratio) - 0.66)
          : 130 * Math.pow(poids, 0.75) * 3.2 * (Math.exp(-0.87 * ratio) - 0.1);
        return { kcal, croissance: true, avertissement: avert,
          detail: `Croissance : formule NRC 2006 (poids actuel ${fr1(poids)} kg, poids adulte estimé ${fr1(poidsAdulte)} kg). Estimation à ajuster selon la courbe de poids.` };
      }
    }
    const repro = sterilise ? null : besoinRepro(p, poids, nbPetits);
    if (repro) {
      if (repro.manque) return { detail: '', manque: repro.manque };
      return { kcal: repro.kcal, avertissement: avert,
        detail: `${repro.detail} Poids ${fr1(poids)} kg. Estimation : à ajuster selon l’état de la femelle.` };
    }
    const pCalc = poidsObjectif ?? poids;
    const rer = 70 * Math.pow(pCalc, 0.75);
    const coef = coefficientAdulte(p.espece, sterilise, activite);
    const parts = [
      sterilise ? 'adulte stérilisé' : 'adulte non stérilisé',
      `activité ${LIBELLES_ACTIVITE[activite].toLowerCase()}`,
      ...(poidsObjectif != null ? [`objectif ${fr1(poidsObjectif)} kg`] : []),
    ];
    return { kcal: rer * coef, avertissement: avert,
      detail: `Besoin au repos ${Math.round(rer)} kcal × ${frCoef(coef)} (${parts.join(', ')})${p.etatRepro === 'gestation_debut' ? ', début de gestation : besoins d’entretien' : ''}. Estimation : à ajuster selon l’évolution du poids.` };
  }

  if (enCroissance) {
    return { detail: '', croissance: true,
      manque: `${nom} est encore jeune : pour un animal en croissance de cette espèce, demandez la ration au vétérinaire. Indiquez les quantités servies.` };
  }
  const pCalc = poidsObjectif ?? poids;
  if (profil.methode === 'lapin') {
    return { avertissement: avert,
      detail: `Foin à volonté, granulés 22,5 g et légumes frais 50 g par kg de poids et par jour (poids ${fr1(pCalc)} kg).` };
  }
  const pct: Record<string, Record<string, number>> = {
    cheval: { sedentaire: 1.5, normal: 2.0, sportif: 2.5 },
    ovin: { sedentaire: 1.5, normal: 2.0, sportif: 2.2 },
    porcin: { sedentaire: 2.0, normal: 3.0, sportif: 3.0 },
  };
  const table = pct[p.espece === 'ane' ? 'cheval' : p.espece === 'caprin' ? 'ovin' : p.espece] ?? pct.cheval;
  const taux = table[activite] ?? table.normal;
  const repro = sterilise ? 1.0 : facteurRepro(p.etatRepro);
  const total = pCalc * 1000 * taux / 100 * repro;
  return { totalG: total, avertissement: avert,
    detail: `Ration totale ${formatQuantite(total, true)}/jour : ${frCoef(taux)} % du poids (${fr1(pCalc)} kg), activité ${LIBELLES_ACTIVITE[activite].toLowerCase()}${repro !== 1.0 ? `, ${libRepro(p.etatRepro)}` : ''}.` };
}

// ── Recommandation fabricant ──────────────────────────────────────────────

type Ligne = Record<string, unknown>;
const estNombre = (v: unknown): v is number => typeof v === 'number';

/** Quantité (g/jour) indiquée par le fabricant pour ce profil, sinon null. */
export function recommandationFabricant(a: AlimentPlan, p: ProfilAnimal, croissance: boolean, poidsAdulte?: number | null): number | null {
  const poids = p.poidsKg;
  if (croissance) {
    const age = ageMois(p);
    const rows = (a.tableauCroissance ?? []).filter((r): r is Ligne => !!r && typeof r === 'object')
      .filter(r => estNombre(r.g_jour) && estNombre(r.age_mois));
    if (!rows.length || age == null) return null;
    let cand = rows;
    if (poidsAdulte != null && rows.some(r => estNombre(r.poids_adulte_kg))) {
      const avecPoids = rows.filter(r => estNombre(r.poids_adulte_kg));
      const ecart = (r: Ligne) => Math.abs((r.poids_adulte_kg as number) - poidsAdulte);
      const best = Math.min(...avecPoids.map(ecart));
      cand = avecPoids.filter(r => ecart(r) === best);
    }
    cand = [...cand].sort((x, y) => (x.age_mois as number) - (y.age_mois as number));
    const avant = cand.filter(r => (r.age_mois as number) <= age);
    return ((avant.length ? avant[avant.length - 1] : cand[0]).g_jour as number);
  }
  if (poids == null || poids <= 0) return null;
  const pts = (a.doses ?? []).filter((d): d is Ligne => !!d && typeof d === 'object')
    .filter(d => estNombre(d.poids_kg) && estNombre(d.grammes))
    .map(d => [d.poids_kg as number, d.grammes as number] as const)
    .sort((x, y) => x[0] - y[0]);
  if (!pts.length) return null;
  if (poids <= pts[0][0]) return pts[0][1];
  for (let i = 0; i < pts.length - 1; i++) {
    const [p1, g1] = pts[i], [p2, g2] = pts[i + 1];
    if (poids >= p1 && poids <= p2) return g1 + (g2 - g1) * (poids - p1) / (p2 - p1);
  }
  return pts[pts.length - 1][1];
}

// ── Calcul de la ration ───────────────────────────────────────────────────

export interface LigneRation { a: number; reco?: number | null; eff?: number | null; libre?: boolean; perso?: boolean }

export interface CalculRation {
  besoin: Besoin;
  lignes: LigneRation[][];
  totalParAliment: number[]; // g/jour
  alimentLibre: boolean[]; // servi à volonté partout
  totalG: number;
  kcalServies: number | null; // null si non calculable
  sansKcal: string[];
  recoDisponible: boolean;
  ecartPct: number | null;
  fabricant: (number | null)[]; // g/jour par aliment
  avertissements: string[];
}

export const ecartImportant = (c: CalculRation) => c.ecartPct != null && Math.abs(c.ecartPct) > 15;

const POIDS_TYPES: Record<string, number> = {
  foin: 67, concentre: 28, complement: 5, granules: 90, menagere: 90, legumes: 10,
};

export function calculerRation(plan: PlanAlimentation, animal: ProfilAnimal, poidsObjectif?: number | null): CalculRation {
  const profil = profilEspece(animal.espece);
  const besoin = calculerBesoin(animal, { activite: plan.activite, poidsObjectif, poidsAdulte: plan.poidsAdulte, nbPetits: plan.nbPetits });
  const n = plan.repas.length;
  const nAlim = plan.aliments.length;
  const repasParAliment = new Array(nAlim).fill(0) as number[];
  plan.repas.forEach(r => r.items.forEach(it => { if (!it.libre) repasParAliment[it.a]++; }));

  const recoJour = new Array(nAlim).fill(null) as (number | null)[];
  if (!besoin.manque) {
    if (profil.methode === 'poids_vif' && besoin.totalG != null) {
      const types = new Set<string>();
      for (let i = 0; i < nAlim; i++) if (repasParAliment[i] > 0) types.add(plan.aliments[i].type);
      const somme = [...types].reduce((s, t) => s + (POIDS_TYPES[t] ?? 0), 0);
      if (somme > 0) {
        types.forEach(t => {
          const idx: number[] = [];
          for (let i = 0; i < nAlim; i++) if (plan.aliments[i].type === t && repasParAliment[i] > 0) idx.push(i);
          const part = besoin.totalG! * (POIDS_TYPES[t] ?? 0) / somme / idx.length;
          if ((POIDS_TYPES[t] ?? 0) > 0) idx.forEach(i => { recoJour[i] = part; });
        });
      }
    } else if (profil.methode === 'lapin' && (animal.poidsKg ?? 0) > 0) {
      const pk = poidsObjectif ?? animal.poidsKg!;
      for (const t of ['granules', 'legumes']) {
        const idx: number[] = [];
        for (let i = 0; i < nAlim; i++) if (plan.aliments[i].type === t && repasParAliment[i] > 0) idx.push(i);
        idx.forEach(i => { recoJour[i] = pk * (t === 'granules' ? 22.5 : 50) / idx.length; });
      }
    }
  }

  const lignes: LigneRation[][] = plan.repas.map(r => {
    const aQuantite = r.items.filter(it => !it.libre);
    const energieOk = profil.methode === 'energie' && besoin.kcal != null &&
      aQuantite.length > 0 && aQuantite.every(it => (plan.aliments[it.a].kcal ?? 0) > 0);
    return r.items.map(it => {
      if (it.libre) return { a: it.a, libre: true };
      let reco: number | null = null;
      if (profil.methode === 'energie') {
        if (energieOk) reco = besoin.kcal! / n / aQuantite.length * 100 / plan.aliments[it.a].kcal!;
      } else if (recoJour[it.a] != null && repasParAliment[it.a] > 0) {
        reco = recoJour[it.a]! / repasParAliment[it.a];
      }
      return { a: it.a, reco, eff: it.g ?? reco, perso: it.g != null };
    });
  });

  const total = new Array(nAlim).fill(0) as number[];
  const servi = new Array(nAlim).fill(false) as boolean[];
  const libreSeul = new Array(nAlim).fill(true) as boolean[];
  lignes.forEach(l => l.forEach(x => {
    servi[x.a] = true;
    if (!x.libre) { libreSeul[x.a] = false; total[x.a] += x.eff ?? 0; }
  }));
  const sansKcal: string[] = [];
  let kcal = 0;
  for (let i = 0; i < nAlim; i++) {
    if (!servi[i] || libreSeul[i]) continue;
    const k = plan.aliments[i].kcal;
    if (k == null || k <= 0) sansKcal.push(nomAliment(plan.aliments[i]));
    else kcal += total[i] * k / 100;
  }
  const toutes = lignes.flat().filter(x => !x.libre);
  const recoDispo = !besoin.manque && toutes.length > 0 && toutes.every(x => x.reco != null);
  const calcEnergie = profil.methode === 'energie';
  const kcalServies = calcEnergie && !sansKcal.length && toutes.every(x => x.eff != null) ? kcal : null;

  let ecart: number | null = null;
  if (calcEnergie && kcalServies != null && besoin.kcal != null && besoin.kcal > 0) {
    ecart = (kcalServies - besoin.kcal) / besoin.kcal * 100;
  } else if (!calcEnergie && recoDispo) {
    const reco = toutes.reduce((s, x) => s + (x.reco ?? 0), 0);
    const eff = toutes.reduce((s, x) => s + (x.eff ?? 0), 0);
    if (reco > 0) ecart = (eff - reco) / reco * 100;
  }

  const avert: string[] = besoin.avertissement ? [besoin.avertissement] : [];
  const maxConcentre = animal.espece === 'cheval' || animal.espece === 'ane' ? 2500
    : (animal.espece === 'ovin' || animal.espece === 'caprin') ? 1500 : null;
  if (maxConcentre != null) {
    lignes.forEach((l, i) => {
      const g = l.filter(x => plan.aliments[x.a].type === 'concentre').reduce((s, x) => s + (x.eff ?? 0), 0);
      if (g > maxConcentre) {
        avert.push(`${libellesRepas(n)[i]} : ${formatQuantite(g, true)} de concentrés en un repas, au-delà de ${formatQuantite(maxConcentre, true)} le risque digestif augmente. Ajoutez un repas ou réduisez la quantité.`);
      }
    });
  }

  return {
    besoin, lignes, totalParAliment: total,
    alimentLibre: total.map((_, i) => servi[i] && libreSeul[i]),
    totalG: total.reduce((s, x) => s + x, 0),
    kcalServies, sansKcal, recoDisponible: recoDispo, ecartPct: ecart,
    fabricant: plan.aliments.map(a => recommandationFabricant(a, animal, !!besoin.croissance, plan.poidsAdulte)),
    avertissements: avert,
  };
}

// ── Contrôles d'étape ─────────────────────────────────────────────────────

/** Message bloquant de l'étape (1 à 6), sinon null. */
export function erreurEtape(etape: number, plan: PlanAlimentation, c: CalculRation, o: {
  objectifTexte?: string; poidsAdulteTexte?: string; ecartConfirme?: boolean; saisiesInvalides?: Record<string, string>;
} = {}): string | null {
  switch (etape) {
    case 1:
      return plan.categories.length ? null : 'Choisissez au moins un type d’alimentation.';
    case 2: {
      const ob = lireNombre(o.objectifTexte);
      if (ob.err) return `Objectif de poids : ${ob.err}`;
      const pa = lireNombre(o.poidsAdulteTexte);
      if (pa.err) return `Poids adulte estimé : ${pa.err}`;
      return null;
    }
    case 3:
      if (plan.mode === 'unique' && plan.aliments.length !== 1) return 'Sélectionnez un aliment.';
      if (plan.mode === 'mixte' && plan.aliments.length < 2) return 'Une alimentation mixte comporte au moins deux aliments.';
      return null;
    case 4: {
      const labels = libellesRepas(plan.repas.length);
      for (let i = 0; i < plan.repas.length; i++) {
        if (!plan.repas[i].items.length) {
          return `Vous avez renseigné ${plan.repas.length} repas, mais aucun aliment pour le repas « ${labels[i]} ».`;
        }
      }
      for (let a = 0; a < plan.aliments.length; a++) {
        if (!plan.repas.some(r => r.items.some(it => it.a === a))) {
          return `« ${nomAliment(plan.aliments[a])} » n’est servi à aucun repas : cochez-le ou retirez-le à l’étape 3.`;
        }
      }
      return null;
    }
    case 5: {
      if (o.saisiesInvalides && Object.keys(o.saisiesInvalides).length) return 'Corrigez les quantités signalées en rouge.';
      const labels = libellesRepas(plan.repas.length);
      for (let i = 0; i < c.lignes.length; i++) {
        for (const x of c.lignes[i]) {
          if (!x.libre && x.eff == null) {
            return `${labels[i]} : indiquez la quantité de « ${nomAliment(plan.aliments[x.a])} » (pas de recommandation possible).`;
          }
        }
      }
      if (ecartImportant(c) && !o.ecartConfirme) {
        return 'Cette ration est très différente de l’estimation PetsMatch. Vérifiez les quantités avant de confirmer.';
      }
      return null;
    }
  }
  return null;
}

// ── Énergie d'un aliment ajouté ───────────────────────────────────────────

export interface EvaluationEnergie {
  err?: string;
  warn?: string;
  info?: string;
  kcal?: number;
  ok: boolean;
  estime: boolean;
  erreursChamps: Record<string, string>;
  composition: Record<string, number>;
}

export const CHAMPS_COMPOSITION: [string, string][] = [
  ['proteines', 'Protéines'], ['matieres_grasses', 'Matières grasses'], ['fibres', 'Fibres brutes'],
  ['cendres', 'Cendres brutes'], ['humidite', 'Humidité'], ['glucides', 'Glucides (si indiqués)'],
];

const TYPES_DE: Record<string, string> = {
  croquettes: 'des croquettes', patee: 'une pâtée', barf: 'du BARF', menagere: 'une ration ménagère', autre: 'cet aliment',
};

/** methode : 'A' (kcal connues), 'B' (composition), 'C' (aucune info). */
export function evaluerEnergie(o: { methode: string; type: string; kcalTexte?: string; unite?: string; compo?: Record<string, string> }): EvaluationEnergie {
  const out: EvaluationEnergie = { ok: false, estime: false, erreursChamps: {}, composition: {} };
  const plage = PLAGES_KCAL[o.type] ?? PLAGES_KCAL.autre;
  const plausible = (v: number) => {
    if (v < plage[0] || v > plage[1]) {
      out.warn = `La valeur énergétique semble inhabituelle pour ${TYPES_DE[o.type] ?? 'cet aliment'} (habituellement ${plage[0]} à ${plage[1]} kcal/100 g). Vérifiez si elle est indiquée pour 100 g ou pour 1 kg.`;
    }
  };
  if (o.methode === 'A') {
    const p = lireNombre(o.kcalTexte);
    if (p.err) { out.err = p.err; return out; }
    if (p.v == null) return out;
    const v = o.unite === 'kg' ? p.v / 10 : p.v;
    if (v >= 1000) {
      out.err = o.unite === 'kg'
        ? 'Valeur trop élevée, même pour 1 kg : vérifiez le chiffre recopié.'
        : 'Valeur trop élevée pour 100 g : elle est sans doute indiquée pour 1 kg. Sélectionnez alors « kcal/kg ».';
      return out;
    }
    if (o.unite === 'kg') out.info = `${Math.round(p.v)} kcal/kg = ${fr1(v)} kcal/100 g`;
    plausible(v);
    out.kcal = Math.round(v * 10) / 10;
    out.ok = true;
    return out;
  }
  if (o.methode === 'B') {
    const vals: Record<string, number> = {};
    for (const [k] of CHAMPS_COMPOSITION) {
      const q = lireNombre(o.compo?.[k], true);
      if (q.err) out.erreursChamps[k] = q.err;
      else if (q.v != null && q.v > 100) out.erreursChamps[k] = 'Un pourcentage est compris entre 0 et 100.';
      else if (q.v != null) vals[k] = q.v;
    }
    if (Object.keys(out.erreursChamps).length) return out;
    out.composition = vals;
    const somme = Object.values(vals).reduce((s, x) => s + x, 0);
    if (somme > 100.5) { out.err = 'La somme des pourcentages dépasse 100 %. Vérifiez les valeurs recopiées sur l’emballage.'; return out; }
    if (vals.proteines == null || vals.matieres_grasses == null) {
      if (Object.keys(vals).length) out.info = 'Protéines et matières grasses sont nécessaires à l’estimation.';
      return out;
    }
    let gluc: number;
    if (vals.glucides != null) gluc = vals.glucides;
    else {
      const manquants = ['fibres', 'cendres', 'humidite'].filter(k => vals[k] == null);
      if (manquants.length) {
        const lib = Object.fromEntries(CHAMPS_COMPOSITION.map(([k, l]) => [k, l.toLowerCase()]));
        out.info = `Encore à remplir pour estimer les glucides : ${manquants.map(k => lib[k]).join(', ')} (ou indiquez directement les glucides).`;
        return out;
      }
      gluc = 100 - (vals.proteines + vals.matieres_grasses + vals.fibres + vals.cendres + vals.humidite);
      if (gluc < -0.5) { out.err = 'Les glucides calculés par différence seraient négatifs : vérifiez les valeurs recopiées.'; return out; }
      gluc = Math.max(0, gluc);
    }
    const industriel = o.type === 'croquettes' || o.type === 'patee';
    const v = industriel
      ? 3.5 * vals.proteines + 8.5 * vals.matieres_grasses + 3.5 * gluc
      : 4 * vals.proteines + 9 * vals.matieres_grasses + 4 * gluc;
    if (v <= 0) { out.err = 'Estimation impossible avec ces valeurs.'; return out; }
    out.info = `Estimation : ${Math.round(v)} kcal/100 g${vals.glucides == null ? ` (glucides estimés par différence : ${fr1(gluc)} %)` : ''}. `
      + `${industriel ? 'Méthode Atwater modifiée (NRC 2006), adaptée aux aliments industriels.' : 'Méthode Atwater (4-9-4) : estimation moins précise pour un aliment cru ou maison.'} `
      + 'Ce n’est pas une valeur certifiée par le fabricant.';
    plausible(v);
    out.kcal = Math.round(v);
    out.ok = true;
    out.estime = true;
    return out;
  }
  if (o.methode === 'C') out.ok = true;
  return out;
}

// ── Gestation / lactation détectées ───────────────────────────────────────

export interface EtatRepro {
  /** 'normal' | 'gestation_debut' | 'gestation_fin' | 'lactation' */
  etat: string;
  semaine?: number;
  nbPetits?: number | null;
  /** Date de mise bas retenue (« yyyy-MM-dd »). */
  miseBas?: string;
  /** D'où vient le nombre de petits, à afficher. */
  source?: string;
}

const DUREES_GESTATION: Record<string, number> = { chien: 63, chat: 65, cheval: 340, ane: 365, ovin: 150, caprin: 150, porcin: 114, lapin: 31 };
/** Petits qui ne tètent plus : décédés ou déjà partis. */
const STATUTS_HORS_PORTEE = new Set(['decede', 'sorti', 'adopte']);

const jourLocal = (v: unknown): Date | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v ?? ''));
  return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null;
};
const jourIso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const jourFr = (d: Date) => `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
const joursEntre = (a: Date, b: Date) => Math.floor((b.getTime() - a.getTime()) / 86400000);

/** État reproducteur d'une femelle à partir de sa dernière gestation (onglet
 *  Repro : `date` = saillie, `date_naissance` = mise bas, `nb_nes`) et des
 *  portées dont elle est la mère (fiches des petits : `portee_id`,
 *  `date_naissance`, `statut`). La portée la plus récente fait foi pour la
 *  mise bas et le nombre de petits encore présents, même si la gestation
 *  n'a pas été mise à jour. Lactation jusqu'à 8 semaines. */
export function detecterReproduction(o: { espece: string; gestation?: Ligne | null; portees?: Ligne[]; maintenant?: Date }): EtatRepro {
  const now = o.maintenant ?? new Date();
  const g = o.gestation ?? null;
  const saillie = jourLocal(g?.date);
  const miseBasG = jourLocal(g?.date_naissance);
  const nbNes = typeof g?.nb_nes === 'number' ? g.nb_nes : null;

  const parPortee = new Map<string, { date: Date; presents: number; total: number }>();
  for (const r of o.portees ?? []) {
    const d = jourLocal(r.date_naissance);
    const id = r.portee_id != null ? String(r.portee_id) : '';
    if (!d || !id) continue;
    const prev = parPortee.get(id);
    const present = !STATUTS_HORS_PORTEE.has(String(r.statut ?? ''));
    parPortee.set(id, { date: prev?.date ?? d, presents: (prev?.presents ?? 0) + (present ? 1 : 0), total: (prev?.total ?? 0) + 1 });
  }
  let derniere: { date: Date; presents: number; total: number } | null = null;
  parPortee.forEach(p => { if (!derniere || p.date > derniere.date) derniere = p; });

  let miseBas = miseBasG;
  let nb: number | null = nbNes;
  let source: string | undefined = nbNes != null ? `Repris de la gestation (${nbNes} nés)` : undefined;
  const d = derniere as { date: Date; presents: number; total: number } | null;
  if (d && (!miseBas || d.date >= miseBas)) {
    miseBas = d.date;
    nb = d.presents;
    source = `Repris de la portée née le ${jourFr(d.date)} (${d.presents} petit${d.presents > 1 ? 's' : ''}${d.total > d.presents ? ` sur ${d.total} nés` : ''})`;
  }

  if (saillie && (!miseBas || miseBas < saillie)) {
    const jours = joursEntre(saillie, now);
    const total = DUREES_GESTATION[o.espece] ?? 63;
    if (jours >= 0 && jours <= total + 7) return { etat: jours >= total - 21 ? 'gestation_fin' : 'gestation_debut' };
    return { etat: 'normal' };
  }
  if (miseBas) {
    const jours = joursEntre(miseBas, now);
    if (jours >= 0 && jours < 56) return { etat: 'lactation', semaine: Math.floor(jours / 7) + 1, nbPetits: nb, miseBas: jourIso(miseBas), source };
  }
  return { etat: 'normal' };
}

// ── Lecture d'une ligne `alimentations` ───────────────────────────────────

/** Plan de la ligne : colonne `plan` si elle est à jour, sinon reconstitué
 *  depuis l'ancien format (type_ration, marque, notes « …|nbRepas|… »).
 *  null : rien d'exploitable. */
export function planDepuisLigne(row: Ligne | null | undefined, espece: string): PlanAlimentation | null {
  if (!row) return null;
  const brut = row.plan;
  if (brut && typeof brut === 'object') {
    const plan = planDepuisJson(brut as Json);
    // Réenregistré depuis une ancienne version de l'appli après le plan ?
    const enr = Date.parse(String((brut as Json).enregistre_le ?? ''));
    const maj = Date.parse(String(row.updated_at ?? ''));
    const perime = !isNaN(enr) && !isNaN(maj) && (maj - enr) / 1000 > 30;
    if (plan.aliments.length && !perime) return plan;
  }
  return planAncien(row, espece);
}

function planAncien(row: Ligne, espece: string): PlanAlimentation | null {
  const profil = profilEspece(espece);
  const type = String(row.type_ration ?? '');
  const notes = String(row.notes ?? '');
  const parts = notes.includes('|') ? notes.split('|') : [];
  const part = (i: number) => (i < parts.length ? parts[i].trim() : '');
  const nombre = (v: unknown) => {
    const d = parseFloat(String(v ?? '').replace(',', '.'));
    return isFinite(d) && d > 0 ? d : null;
  };
  const nbCol = typeof row.nb_repas === 'number' ? Math.round(row.nb_repas) : null;
  const nbNotes = parseInt(part(3), 10);
  const nb = Math.min(4, Math.max(1, nbCol ?? (isNaN(nbNotes) ? 2 : nbNotes)));
  const marque = String(row.marque ?? '').trim();
  const gamme = String(row.gamme ?? '').trim();
  const densite = nombre(row.densite_calorique) ?? nombre(part(11));
  const marqueId = row.marque_id != null ? String(row.marque_id) : null;
  const plan: PlanAlimentation = {
    mode: 'unique', categories: [], activite: activiteDepuisAncienne(row.niveau_activite as string), repris: true,
    aliments: [], repas: Array.from({ length: nb }, () => ({ items: [] })),
  };
  const produit = (typeDefaut: string, libelle: string, kcal: number | null = null): AlimentPlan => ({
    id: marqueId, marque: marque || libelle, gamme: marque ? gamme : '', type: typeDefaut, kcal,
    source: kcal != null ? 'fabricant' : null,
  });
  const ration1 = nombre(row.ration_grammes) ?? nombre(part(5));
  const ration2 = nombre(row.ration2_grammes) ?? nombre(part(6));
  const servirPartout = (a: number, jour: number | null, libre = false) =>
    plan.repas.forEach(r => r.items.push({ a, libre, g: jour != null ? jour / nb : null }));

  if (profil.methode === 'energie') {
    switch (type) {
      case 'barf':
        plan.aliments.push({ marque: 'BARF', gamme: 'préparation', type: 'barf', repartition: {
          muscles: nombre(row.pourcentage_muscles) ?? 70, abats: nombre(row.pourcentage_abats) ?? 10,
          os: nombre(row.pourcentage_os) ?? 10, legumes: nombre(row.pourcentage_legumes) ?? 10,
        } });
        servirPartout(0, ration1);
        break;
      case 'menagere':
        plan.aliments.push({ marque: 'Ration ménagère', gamme: '', type: 'menagere', repartition: { ...REPARTITION_MENAGERE } });
        servirPartout(0, ration1);
        break;
      case 'mixte': {
        plan.mode = 'mixte';
        plan.aliments.push(produit('croquettes', 'Croquettes', densite));
        const t2 = part(7) || 'patee';
        const kcal2 = t2 === 'patee' ? nombre(part(8)) : null;
        plan.aliments.push({
          marque: t2 === 'barf' ? 'BARF' : t2 === 'menagere' ? 'Ration ménagère' : 'Pâtée', gamme: '',
          type: t2 === 'barf' ? 'barf' : t2 === 'menagere' ? 'menagere' : 'patee',
          kcal: kcal2, source: kcal2 != null ? 'fabricant' : null,
        });
        if (part(4) === '1' && nb >= 2) {
          const pct = (typeof row.mixte_ratio_croq === 'number' ? row.mixte_ratio_croq : null) ?? nombre(part(10)) ?? 50;
          const nCroq = Math.min(nb - 1, Math.max(1, Math.round(nb * pct / 100)));
          for (let i = 0; i < nb; i++) {
            const a = i < nCroq ? 0 : 1;
            const jour = a === 0 ? ration1 : ration2;
            const nRepas = a === 0 ? nCroq : nb - nCroq;
            plan.repas[i].items.push({ a, g: jour != null ? jour / nRepas : null });
          }
        } else {
          servirPartout(0, ration1);
          servirPartout(1, ration2);
        }
        break;
      }
      default:
        if (!type && !marque) return null;
        plan.aliments.push(produit('croquettes', 'Croquettes', densite));
        servirPartout(0, ration1);
    }
  } else {
    const total = ration1;
    const pctFoin = nombre(part(0)) ?? 67, pctGran = nombre(part(1)) ?? 28, pctComp = nombre(part(2)) ?? 0;
    const sommePct = pctFoin + pctGran + pctComp;
    const partDe = (pct: number) => (total != null ? total * pct / sommePct : null);
    const simple = (marqueLib: string, t: string): AlimentPlan => ({ marque: marqueLib, gamme: '', type: t });
    switch (espece) {
      case 'lapin':
        plan.aliments.push(simple('Foin', 'foin'));
        servirPartout(0, null, true);
        plan.aliments.push(produit('granules', 'Granulés', densite));
        servirPartout(1, null);
        if (type !== 'granules') {
          plan.mode = 'mixte';
          plan.aliments.push(simple('Légumes frais', 'legumes'));
          servirPartout(2, null);
        }
        break;
      case 'oiseau':
        plan.aliments.push(produit(type === 'granules' ? 'granules' : 'graines', type === 'granules' ? 'Granulés' : 'Graines / mélange'));
        servirPartout(0, total);
        break;
      case 'porcin':
        plan.aliments.push(type === 'menagere' ? simple('Ration ménagère', 'menagere') : produit('granules', 'Aliment complet'));
        servirPartout(0, total);
        break;
      default:
        if (type === 'paturage') {
          plan.aliments.push(simple('Pâturage', 'paturage'));
          servirPartout(0, null, true);
        } else if (type === 'complement') {
          plan.aliments.push(produit('complement', 'Complément'));
          servirPartout(0, total);
        } else if (type === 'foin') {
          plan.aliments.push(simple('Foin / fourrage', 'foin'));
          servirPartout(0, total);
        } else if (profil.types.includes('concentre')) {
          plan.mode = 'mixte';
          plan.aliments.push(simple('Foin / fourrage', 'foin'));
          servirPartout(0, partDe(pctFoin));
          plan.aliments.push(produit('concentre', 'Granulés / concentrés'));
          servirPartout(1, partDe(pctGran));
          if (pctComp > 0) {
            plan.aliments.push(simple('Complément', 'complement'));
            servirPartout(2, partDe(pctComp));
          }
        } else {
          if (!type && !marque) return null;
          plan.aliments.push(produit(profil.types[0], LIBELLES_TYPE_ALIMENT[profil.types[0]]));
          servirPartout(0, total);
        }
    }
  }
  plan.categories = [...new Set(plan.aliments.map(a => a.type))];
  if (plan.aliments.length > 1) plan.mode = 'mixte';
  return plan;
}

/** Colonnes historiques, encore lues par d'anciens écrans. */
export function colonnesHistoriques(plan: PlanAlimentation, c: CalculRation) {
  const a0 = plan.aliments[0];
  return {
    type_ration: plan.aliments.length > 1 ? 'mixte' : (a0?.type ?? 'croquettes'),
    niveau_activite: plan.activite,
    phase_vie: 'auto',
    marque_id: a0?.id ?? null,
    marque: a0?.marque ?? null,
    gamme: a0?.gamme ? a0.gamme : null,
    densite_calorique: a0?.kcal ?? null,
    nb_repas: plan.repas.length,
    ration_grammes: c.totalParAliment[0] > 0 ? Math.round(c.totalParAliment[0]) : null,
    ration2_grammes: c.totalParAliment.length > 1 && c.totalParAliment[1] > 0 ? Math.round(c.totalParAliment[1]) : null,
    ration_kcal: c.kcalServies != null ? Math.round(c.kcalServies) : null,
  };
}

/** Pour la vue lecture seule (pros) : quantités enregistrées, sans recalcul. */
export function calculEnregistre(plan: PlanAlimentation): CalculRation {
  const lignes = plan.repas.map(r => r.items.map(it => ({ a: it.a, libre: !!it.libre, eff: it.gEnregistre ?? it.g ?? null, perso: it.g != null })));
  const total = new Array(plan.aliments.length).fill(0) as number[];
  const libreSeul = new Array(plan.aliments.length).fill(true) as boolean[];
  const servi = new Array(plan.aliments.length).fill(false) as boolean[];
  lignes.forEach(l => l.forEach(x => {
    servi[x.a] = true;
    if (!x.libre) { libreSeul[x.a] = false; total[x.a] += x.eff ?? 0; }
  }));
  return {
    besoin: { detail: '' }, lignes, totalParAliment: total,
    alimentLibre: total.map((_, i) => servi[i] && libreSeul[i]),
    totalG: total.reduce((s, x) => s + x, 0),
    kcalServies: null, sansKcal: [], recoDisponible: false, ecartPct: null, fabricant: [], avertissements: [],
  };
}
