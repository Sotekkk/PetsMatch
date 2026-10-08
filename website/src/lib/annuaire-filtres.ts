// Annuaire des professionnels — filtres combinables : métier + lieu / rayon +
// animaux pris en charge (+ mot-clé). Même logique que l'app :
// lib/utils/annuaire_filtres.dart — garder les deux synchronisés.

// ── Métiers ──────────────────────────────────────────────────────────────────

export interface Metier {
  key: string;
  label: string;
  /** Groupe affiché dans le menu déroulant */
  groupe: string;
  /** profile_type acceptés ([] = tous les pros) */
  cats: string[];
  /** profession_pro acceptées (vide = toutes) */
  professions?: string[];
  /** Repli « promeneur » : pet-sitter qui propose des créneaux de ce type */
  creneauTypeGarde?: string[];
}

export const METIERS: Metier[] = [
  { key: '',                   label: 'Tous les métiers',               groupe: '',                          cats: [] },
  { key: 'sante',              label: 'Toute la santé & bien-être',     groupe: 'Santé & bien-être',         cats: ['sante', 'veterinaire', 'marechal_ferrant'] },
  { key: 'veterinaire',        label: 'Vétérinaire',                    groupe: 'Santé & bien-être',         cats: ['veterinaire'] },
  { key: 'osteopathe',         label: 'Ostéopathe',                     groupe: 'Santé & bien-être',         cats: ['sante'], professions: ['Ostéopathe'] },
  { key: 'kine',               label: 'Kinésithérapeute',               groupe: 'Santé & bien-être',         cats: ['sante'], professions: ['Kinésithérapeute'] },
  { key: 'marechal',           label: 'Maréchal-ferrant',               groupe: 'Santé & bien-être',         cats: ['marechal_ferrant', 'sante'], professions: ['Maréchal-ferrant', 'Maréchal-ferrant traditionnel', 'Parage naturel'] },
  { key: 'education',          label: 'Toute l\'éducation',             groupe: 'Éducation & comportement',  cats: ['education'] },
  { key: 'educateur',          label: 'Éducateur',                      groupe: 'Éducation & comportement',  cats: ['education'], professions: ['Éducateur canin', 'Dresseur'] },
  { key: 'comportementaliste', label: 'Comportementaliste',             groupe: 'Éducation & comportement',  cats: ['education'], professions: ['Comportementaliste'] },
  { key: 'garde',              label: 'Toute la garde & hébergement',   groupe: 'Garde & hébergement',       cats: ['garde', 'pension'] },
  { key: 'petsitter',          label: 'Pet-sitter',                     groupe: 'Garde & hébergement',       cats: ['garde'], professions: ['Pet sitter'] },
  { key: 'promeneur',          label: 'Promeneur',                      groupe: 'Garde & hébergement',       cats: ['garde'], professions: ['Promeneur de chiens'], creneauTypeGarde: ['prestation'] },
  { key: 'pension',            label: 'Pension',                        groupe: 'Garde & hébergement',       cats: ['pension'] },
  { key: 'toilettage',         label: 'Toilettage',                     groupe: 'Autres services',           cats: ['toilettage'] },
  { key: 'taxi',               label: 'Taxi animalier',                 groupe: 'Autres services',           cats: ['taxi_animalier'] },
  { key: 'photographe',        label: 'Photographe',                    groupe: 'Autres services',           cats: ['photographe'] },
  { key: 'boutiques',          label: 'Alimentation & boutiques',       groupe: 'Autres services',           cats: ['referencement'] },
  { key: 'assurance',          label: 'Assurances & juridique',         groupe: 'Autres services',           cats: ['assurance', 'juridique'] },
];

export const metierByKey = (key: string | null | undefined): Metier =>
  METIERS.find(m => m.key === (key ?? '')) ?? METIERS[0];

/** Anciens liens `?cat=…&prof=…` → métier équivalent (sinon « Tous »). */
export function metierFromLegacy(cat: string | null, prof: string | null): Metier {
  const norm = (s: string | null) => (s ?? '').split(',').map(x => x.trim().toLowerCase()).filter(Boolean).sort().join(',');
  const c = norm(cat), p = norm(prof);
  if (!c && !p) return METIERS[0];
  return METIERS.find(m => norm(m.cats.join(',')) === c && norm((m.professions ?? []).join(',')) === p)
    ?? METIERS.find(m => norm(m.cats.join(',')) === c && !m.professions)
    ?? METIERS[0];
}

export interface ProFiltrable {
  cat_pro?: string;
  profession?: string;
  profileTableId?: string;
}

/** [creneauOk] : ids de profils garde qui proposent des créneaux du type voulu. */
export function proMatchesMetier(p: ProFiltrable, m: Metier, creneauOk?: Set<string>): boolean {
  if (m.cats.length === 0) return true;
  if (!m.cats.includes(p.cat_pro ?? '')) return false;
  if (!m.professions?.length) return true;
  const prof = (p.profession ?? '').toLowerCase();
  if (m.professions.some(x => x.toLowerCase() === prof)) return true;
  return !!m.creneauTypeGarde && !!p.profileTableId && !!creneauOk?.has(p.profileTableId);
}

// ── Animaux pris en charge ───────────────────────────────────────────────────

export interface GroupeEspece {
  key: string;
  label: string;
  detail?: string;
  /** Valeurs de `especes_acceptees` (normalisées) rattachées au groupe */
  valeurs: string[];
}

export const GROUPES_ESPECES: GroupeEspece[] = [
  { key: 'chien',  label: 'Chiens',            valeurs: ['chien', 'chiens'] },
  { key: 'chat',   label: 'Chats',             valeurs: ['chat', 'chats'] },
  { key: 'cheval', label: 'Chevaux & ânes',    valeurs: ['cheval', 'chevaux', 'ane', 'anes', 'equide', 'equides', 'poney', 'poneys'] },
  { key: 'nac',    label: 'NAC',               detail: 'Lapins, rongeurs, reptiles…', valeurs: ['nac', 'lapin', 'lapins', 'rongeur', 'rongeurs', 'reptile', 'reptiles', 'furet', 'furets'] },
  { key: 'oiseau', label: 'Oiseaux',           valeurs: ['oiseau', 'oiseaux'] },
  { key: 'ferme',  label: 'Animaux de ferme',  detail: 'Moutons, chèvres, porcs…', valeurs: ['animaux de la ferme', 'animaux de ferme', 'ferme', 'ovin', 'ovins', 'caprin', 'caprins', 'porcin', 'porcins', 'bovin', 'bovins', 'volaille', 'volailles'] },
  { key: 'autre',  label: 'Autres',            valeurs: ['autre', 'autres'] },
];

const sansAccents = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

/** Groupes couverts par une liste `especes_acceptees` (ordre de GROUPES_ESPECES). */
export function groupesDesEspeces(especes: string[] | null | undefined): GroupeEspece[] {
  const vals = new Set((especes ?? []).map(sansAccents));
  return GROUPES_ESPECES.filter(g => g.valeurs.some(v => vals.has(v)));
}

/** Aucune sélection = toutes les espèces ; sinon au moins un groupe coché. */
export function proMatchesEspeces(especes: string[] | null | undefined, selection: string[]): boolean {
  if (selection.length === 0) return true;
  return groupesDesEspeces(especes).some(g => selection.includes(g.key));
}

// ── Lieu & rayon ─────────────────────────────────────────────────────────────

export interface LieuRecherche { label: string; lat: number; lng: number; ville?: string }

export const RAYONS_KM = [10, 25, 50, 100, 200];

export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export interface ProLocalisable {
  lat?: number | null; lng?: number | null; ville?: string;
  rayon_intervention?: number | null; se_deplace?: boolean | null;
}

/** Dans la zone : à moins de [rayonKm] du lieu, ou le pro se déplace jusque-là
 * (son rayon d'intervention le couvre). Sans coordonnées : même ville. */
export function proDansZone(p: ProLocalisable, lieu: LieuRecherche | null, rayonKm: number): boolean {
  if (!lieu) return true;
  if (p.lat == null || p.lng == null || (!p.lat && !p.lng)) {
    return !!lieu.ville && sansAccents(p.ville ?? '') === sansAccents(lieu.ville);
  }
  const d = haversineKm(lieu.lat, lieu.lng, p.lat, p.lng);
  if (d <= rayonKm) return true;
  const rayonPro = p.se_deplace === false ? 0 : (p.rayon_intervention ?? 0);
  return rayonPro > 0 && d <= rayonPro;
}

/** Communes françaises (API Adresse, data.gouv.fr). */
export async function chercherCommunes(q: string): Promise<LieuRecherche[]> {
  if (q.trim().length < 2) return [];
  try {
    const res = await fetch(`https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(q)}&type=municipality&limit=6`);
    const json = await res.json();
    return (json.features ?? []).map((f: { properties: { city?: string; label: string; postcode?: string }; geometry: { coordinates: [number, number] } }) => ({
      label: `${f.properties.city ?? f.properties.label}${f.properties.postcode ? ` (${f.properties.postcode.slice(0, 2)})` : ''}`,
      ville: f.properties.city ?? f.properties.label,
      lng: f.geometry.coordinates[0],
      lat: f.geometry.coordinates[1],
    }));
  } catch {
    return [];
  }
}

// ── Catégories de l'annuaire (cartes) et leurs types de service ─────────────
// Une catégorie sans type sélectionné = tout le domaine (`metier`) ; un type
// = un métier de METIERS. Miroir app : kCategoriesAnnuaire.

export interface CategorieAnnuaire {
  key: string;
  label: string;
  icon: string;
  color: string;
  /** Métier « tout le domaine » */
  metier: string;
  /** Types de service (clés de METIERS) — vide = pas de sous-type */
  types: string[];
}

export const CATEGORIES_ANNUAIRE: CategorieAnnuaire[] = [
  { key: 'sante',       label: 'Santé & bien-être',        icon: '🩺', color: '#2E7D5E', metier: 'sante',       types: ['veterinaire', 'osteopathe', 'kine', 'marechal'] },
  { key: 'education',   label: 'Éducation & comportement', icon: '🎓', color: '#E65100', metier: 'education',   types: ['educateur', 'comportementaliste'] },
  { key: 'garde',       label: 'Garde & hébergement',      icon: '🏠', color: '#F57C00', metier: 'garde',       types: ['petsitter', 'promeneur', 'pension'] },
  { key: 'toilettage',  label: 'Toilettage & soins',       icon: '✂️', color: '#C62828', metier: 'toilettage',  types: [] },
  { key: 'transport',   label: 'Transport',                icon: '🚐', color: '#00838F', metier: 'taxi',        types: ['taxi'] },
  { key: 'photographe', label: 'Photographes',             icon: '📷', color: '#AD1457', metier: 'photographe', types: [] },
  { key: 'boutiques',   label: 'Alimentation & boutiques', icon: '🛍️', color: '#6A1B9A', metier: 'boutiques',   types: [] },
  { key: 'assurance',   label: 'Assurances & juridique',   icon: '🛡️', color: '#1E3A5F', metier: 'assurance',   types: [] },
];

export const categorieByKey = (key: string | null | undefined) =>
  CATEGORIES_ANNUAIRE.find(c => c.key === key) ?? null;

/** Catégorie + type sélectionnés → métier à filtrer. */
export function metierSelectionne(categorie: string, type: string): Metier {
  if (type) return metierByKey(type);
  const c = categorieByKey(categorie);
  return c ? metierByKey(c.metier) : METIERS[0];
}

/** Métier (anciens liens ?metier= / ?cat=&prof=) → catégorie + type. */
export function selectionDepuisMetier(metierKey: string): { categorie: string; type: string } {
  if (!metierKey) return { categorie: '', type: '' };
  for (const c of CATEGORIES_ANNUAIRE) {
    if (c.types.includes(metierKey)) return { categorie: c.key, type: c.types.length > 1 ? metierKey : '' };
    if (c.metier === metierKey) return { categorie: c.key, type: '' };
  }
  return { categorie: '', type: '' };
}
