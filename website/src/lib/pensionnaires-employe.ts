// Pensionnaires présents d'une pension, vus par un employé autorisé
// (« Planning pension » = read_planning_pension, lecture du registre ouverte
// par la RLS pension_entrees_employe_read_planning). Scopé sur le profil
// pension de la relation, jamais sur le seul uid de l'employeur.
// Miroir appli : lib/utils/pensionnaires_employe.dart.
import { supabase } from '@/lib/supabase';

export interface PensionnaireEmploye {
  id: string;
  animal_id: string | null;
  animal_nom: string | null;
  espece: string | null;
  race: string | null;
  puce: string | null;
  date_entree: string | null;
  date_sortie_prevue: string | null;
  logement: string | null;
  photo_url: string | null;
}

/** Séjours en cours (arrivés, ou dont la date d'entrée est passée), triés par nom. */
export async function pensionnairesPresents(pensionProfileId: string): Promise<PensionnaireEmploye[]> {
  if (!pensionProfileId) return [];
  const auj = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabase.from('pension_entrees')
    .select('id, animal_id, animal_nom, espece, race, puce, logement_id, date_entree, date_sortie_prevue, arrivee_reelle_le')
    .eq('pro_profile_id', pensionProfileId).eq('statut', 'en_pension');
  if (error) throw error;
  type Row = Omit<PensionnaireEmploye, 'logement' | 'photo_url'> & { logement_id: string | null; arrivee_reelle_le: string | null };
  const presents = ((data ?? []) as Row[]).filter(e => !!e.arrivee_reelle_le || (e.date_entree ?? '').slice(0, 10) <= auj);
  if (presents.length === 0) return [];

  // Photos des fiches et noms des logements : facultatifs (droits de lecture
  // variables), la liste s'affiche sans eux.
  const ids = [...new Set(presents.map(e => e.animal_id).filter((x): x is string => !!x))];
  const logIds = [...new Set(presents.map(e => e.logement_id).filter((x): x is string => !!x))];
  const [anim, logs] = await Promise.all([
    ids.length ? supabase.from('animaux').select('id, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
    logIds.length ? supabase.from('enclos_chenil').select('id, nom').in('id', logIds) : Promise.resolve({ data: [] }),
  ]);
  const photos = new Map(((anim.data ?? []) as { id: string; photo_url: string | null }[]).map(a => [String(a.id), a.photo_url]));
  const noms = new Map(((logs.data ?? []) as { id: string; nom: string | null }[]).map(l => [String(l.id), l.nom]));
  return presents.map(e => ({
    id: e.id, animal_id: e.animal_id, animal_nom: e.animal_nom, espece: e.espece, race: e.race, puce: e.puce,
    date_entree: e.date_entree, date_sortie_prevue: e.date_sortie_prevue,
    logement: e.logement_id ? noms.get(String(e.logement_id)) ?? null : null,
    photo_url: e.animal_id ? photos.get(String(e.animal_id)) ?? null : null,
  })).sort((a, b) => (a.animal_nom ?? '').localeCompare(b.animal_nom ?? '', 'fr'));
}
