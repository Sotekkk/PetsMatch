// Espace pension d'un employé autorisé (« Planning pension » =
// read_planning_pension, lecture du registre ouverte par la RLS
// pension_entrees_employe_read_planning) : pensionnaires présents, arrivées
// et départs du jour. Scopé sur le profil pension de la relation, jamais sur
// le seul uid de l'employeur.
// Miroir appli : lib/utils/pensionnaires_employe.dart.
import { supabase } from '@/lib/supabase';

/** Ligne complète de pension_entrees (pour enregistrer arrivée / départ) + nom du logement et photo. */
export interface SejourEmploye {
  id: string;
  pro_uid: string;
  pro_profile_id: string | null;
  animal_id: string | null;
  animal_nom: string | null;
  espece: string | null;
  race: string | null;
  puce?: string | null;
  proprietaire_nom: string | null;
  logement_id: string | null;
  date_entree: string | null;
  date_sortie_prevue: string | null;
  heure_arrivee_prevue?: string | null;
  heure_depart_prevue?: string | null;
  arrivee_reelle_le?: string | null;
  effets_personnels?: string | null;
  consignes_sejour?: string | null;
  logement: string | null;
  photo_url: string | null;
}

export interface EspacePension {
  /** Présents (arrivée enregistrée, ou séjour commencé un jour passé). */
  presents: SejourEmploye[];
  /** Attendus aujourd'hui, arrivée pas encore enregistrée. */
  arrivees: SejourEmploye[];
  /** Présents dont le départ est prévu aujourd'hui (ou en retard). */
  departs: SejourEmploye[];
}

const jourLocal = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

export async function chargerEspacePension(pensionProfileId: string): Promise<EspacePension> {
  const vide: EspacePension = { presents: [], arrivees: [], departs: [] };
  if (!pensionProfileId) return vide;
  const auj = jourLocal();
  const { data, error } = await supabase.from('pension_entrees').select('*')
    .eq('pro_profile_id', pensionProfileId).eq('statut', 'en_pension');
  if (error) throw error;
  type Row = Omit<SejourEmploye, 'logement' | 'photo_url'>;
  const enCours = ((data ?? []) as Row[]).filter(e => !!e.arrivee_reelle_le || (e.date_entree ?? '').slice(0, 10) <= auj);
  if (enCours.length === 0) return vide;

  // Photos des fiches et noms des logements : facultatifs (droits de lecture
  // variables), les listes s'affichent sans eux.
  const ids = [...new Set(enCours.map(e => e.animal_id).filter((x): x is string => !!x))];
  const logIds = [...new Set(enCours.map(e => e.logement_id).filter((x): x is string => !!x))];
  const [anim, logs] = await Promise.all([
    ids.length ? supabase.from('animaux').select('id, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
    logIds.length ? supabase.from('enclos_chenil').select('id, nom').in('id', logIds) : Promise.resolve({ data: [] }),
  ]);
  const photos = new Map(((anim.data ?? []) as { id: string; photo_url: string | null }[]).map(a => [String(a.id), a.photo_url]));
  const noms = new Map(((logs.data ?? []) as { id: string; nom: string | null }[]).map(l => [String(l.id), l.nom]));
  const tous: SejourEmploye[] = enCours.map(e => ({
    ...e,
    logement: e.logement_id ? noms.get(String(e.logement_id)) ?? null : null,
    photo_url: e.animal_id ? photos.get(String(e.animal_id)) ?? null : null,
  })).sort((a, b) => (a.animal_nom ?? '').localeCompare(b.animal_nom ?? '', 'fr'));
  const arrivees = tous.filter(e => !e.arrivee_reelle_le && (e.date_entree ?? '').slice(0, 10) === auj);
  const presents = tous.filter(e => !arrivees.includes(e));
  const departs = presents.filter(e => !!e.date_sortie_prevue && e.date_sortie_prevue.slice(0, 10) <= auj);
  return { presents, arrivees, departs };
}
