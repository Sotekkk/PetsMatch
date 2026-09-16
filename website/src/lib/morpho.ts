// Suivi morphologique & bien-être — constantes partagées (miroir de
// lib/pages/animaux/morpho/morpho_constants.dart côté appli). Mêmes tables
// Supabase (suivis_morpho + _photos/_videos/_points/_observations/
// _mouvements), même vocabulaire — garder synchronisé si l'un évolue.

export const TEAL = '#0C5C6C';

export function morphoSpeciesKey(espece?: string | null): 'chien' | 'chat' | 'cheval' | null {
  const e = (espece || '').toLowerCase();
  if (e.includes('chien')) return 'chien';
  if (e.includes('chat')) return 'chat';
  if (e.includes('cheval')) return 'cheval';
  return null;
}
export function morphoSpeciesSupported(espece?: string | null) { return morphoSpeciesKey(espece) !== null; }

export const TYPES_SUIVI: { key: string; label: string }[] = [
  { key: 'bilan_morphologique', label: 'Bilan morphologique' },
  { key: 'bilan_posture', label: 'Bilan de posture' },
  { key: 'osteopathie', label: 'Ostéopathie' },
  { key: 'physiotherapie', label: 'Physiothérapie' },
  { key: 'suivi_veterinaire', label: 'Suivi vétérinaire' },
  { key: 'suivi_sportif', label: 'Suivi sportif' },
  { key: 'suivi_post_operatoire', label: 'Suivi post-opératoire' },
  { key: 'prevention', label: 'Prévention' },
  { key: 'autre', label: 'Autre' },
];
export function labelTypeSuivi(v?: string | null) { return TYPES_SUIVI.find(t => t.key === v)?.label ?? 'Suivi'; }

export const NIVEAUX_ACTIVITE: { key: string; label: string }[] = [
  { key: 'faible', label: 'Faible' },
  { key: 'moderee', label: 'Modérée' },
  { key: 'elevee', label: 'Élevée' },
  { key: 'non_evalue', label: 'Non évalué' },
];

export const VUES_PHOTOS: { key: string; label: string }[] = [
  { key: 'face', label: 'Face' },
  { key: 'dos', label: 'Arrière / dos' },
  { key: 'profil_g', label: 'Profil gauche' },
  { key: 'profil_d', label: 'Profil droit' },
];

export const ACTIVITES_MOUVEMENT: { key: string; label: string }[] = [
  { key: 'marche', label: 'Marche' },
  { key: 'trot', label: 'Trot' },
  { key: 'course', label: 'Course' },
  { key: 'assis_debout', label: 'Assis / debout' },
  { key: 'escaliers', label: 'Escaliers' },
  { key: 'saut', label: 'Saut' },
  { key: 'sport', label: 'Activité sportive' },
  { key: 'autre', label: 'Autre' },
];
export function labelActivite(v?: string | null) { return ACTIVITES_MOUVEMENT.find(a => a.key === v)?.label ?? 'Activité'; }

export const CATEGORIES_OBSERVATION_STATIQUE: { key: string; label: string }[] = [
  { key: 'aplombs_anterieurs', label: 'Aplombs antérieurs' },
  { key: 'aplombs_posterieurs', label: 'Aplombs postérieurs' },
  { key: 'symetrie', label: 'Symétrie générale' },
  { key: 'ligne_dos', label: 'Ligne du dos' },
  { key: 'position_bassin', label: 'Position du bassin' },
  { key: 'position_membres', label: 'Position des membres' },
];

export function labelsValeurObservation(categorie: string): Record<string, string> {
  if (categorie === 'symetrie') return { normal: 'Symétrique', a_surveiller: 'Asymétrie observée', non_evalue: 'Non évaluée' };
  return { normal: 'Normaux', a_surveiller: 'À surveiller', non_evalue: 'Non évalué' };
}
export function colorValeurObservation(v: string) {
  if (v === 'normal') return '#6E9E57';
  if (v === 'a_surveiller') return '#D97706';
  return '#9CA3AF';
}

export const SOURCE_LABELS: Record<string, string> = {
  proprietaire: 'Renseigné par le propriétaire',
  mesure: 'Mesure enregistrée',
  professionnel: 'Réalisé par un professionnel',
};

export const MORPHO_AVERTISSEMENT =
  "Les informations de cette section sont destinées au suivi de l'animal et ne remplacent pas l'avis d'un vétérinaire ou d'un professionnel de santé animale.";

// Silhouette — pointage libre, mêmes catégories que l'onglet Anatomie
// existant (AnatomiePoints.tsx / anatomie_points_page.dart).
export const CATEGORIES_OSTEO: { key: string; label: string; color: string }[] = [
  { key: 'tension_cervicale', label: 'Tension cervicale', color: '#E67E22' },
  { key: 'tension_thoracique', label: 'Tension thoracique', color: '#F39C12' },
  { key: 'tension_lombaire', label: 'Tension lombaire', color: '#3498DB' },
  { key: 'tension_sacro_iliaque', label: 'Tension sacro-iliaque', color: '#9B59B6' },
  { key: 'trigger', label: 'Point trigger', color: '#795548' },
  { key: 'acupuncture', label: "Point d'acupuncture", color: '#8BC34A' },
  { key: 'autre', label: 'Autre', color: '#9E9E9E' },
];
export function colorCategoriePoint(cat: string) { return CATEGORIES_OSTEO.find(c => c.key === cat)?.color ?? '#9E9E9E'; }
export function labelCategoriePoint(cat: string) { return CATEGORIES_OSTEO.find(c => c.key === cat)?.label ?? cat; }

// Palette de couleurs pour un point — indépendante de la catégorie, pour
// éviter de devoir sélectionner une catégorie (ex. « Point d'acupuncture »)
// juste pour obtenir une couleur distincte. La catégorie reste éditable
// (classement optionnel) ; c'est le libellé libre du point (obligatoire)
// qui sert de légende lisible. Miroir de kPaletteCouleursPoints (app).
export const PALETTE_COULEURS_POINTS = [
  '#E67E22', '#F39C12', '#3498DB', '#9B59B6', '#795548',
  '#8BC34A', '#E74C3C', '#1ABC9C', '#34495E', '#9E9E9E',
];

/** Couleur effective d'un point : sa couleur propre si choisie, sinon la couleur de sa catégorie. */
export function colorPointEffectif(categorie: string, couleur?: string | null) {
  return couleur ? `#${couleur.replace('#', '')}` : colorCategoriePoint(categorie);
}

// Nouveau design (ivoire/bleu) — mêmes fichiers que l'appli, copiés dans
// public/anatomie/ (chien2_*, chat2_*, cheval2_*).
export const SILHOUETTE_ASSETS: Record<string, Record<string, { src: string; ratio: number }>> = {
  chien: {
    face: { src: '/anatomie/chien2_face.png', ratio: 1024 / 1536 },
    profil_g: { src: '/anatomie/chien2_profil_gauche.png', ratio: 1536 / 1024 },
    profil_d: { src: '/anatomie/chien2_profil_droit.png', ratio: 1536 / 1024 },
    dos: { src: '/anatomie/chien2_dos.png', ratio: 1024 / 1536 },
  },
  chat: {
    face: { src: '/anatomie/chat2_face.png', ratio: 1024 / 1536 },
    profil_g: { src: '/anatomie/chat2_profil_gauche.png', ratio: 1536 / 1024 },
    profil_d: { src: '/anatomie/chat2_profil_droit.png', ratio: 1536 / 1024 },
    dos: { src: '/anatomie/chat2_dos.png', ratio: 1024 / 1536 },
  },
  cheval: {
    face: { src: '/anatomie/cheval2_face.png', ratio: 1024 / 1536 },
    profil_g: { src: '/anatomie/cheval2_profil_gauche.png', ratio: 1536 / 1024 },
    profil_d: { src: '/anatomie/cheval2_profil_droit.png', ratio: 1536 / 1024 },
    dos: { src: '/anatomie/cheval2_dos.png', ratio: 1024 / 1536 },
  },
};

const VUE_ORDER = ['face', 'profil_g', 'profil_d', 'dos'];
export function vuesDisponibles(espece: string): { key: string; label: string }[] {
  const assets = SILHOUETTE_ASSETS[espece] ?? SILHOUETTE_ASSETS.chien;
  return VUE_ORDER.filter(v => assets[v]).map(v => ({ key: v, label: VUES_PHOTOS.find(p => p.key === v)?.label ?? v }));
}

export interface MorphoPoint {
  id: string;
  x_pct: number; // 0-100
  y_pct: number; // 0-100
  categorie: string;
  note?: string | null;
  couleur?: string | null;
  vue: string;
}
