// Exercice d'éducation ↔ tâche du jour dans l'agenda du propriétaire
// (taches_elevage.notes = 'exercice:<id>', créée chaque matin par
// sendExerciceReminders). Cocher la tâche valide la réussite / l'étape du jour ;
// valider l'exercice coche la tâche. Miroir appli : lib/utils/exercice_tache.dart.
import { supabase } from '@/lib/supabase';
import { majValidation, progression } from '@/lib/exercices-progression';

export const PREFIXE_TACHE_EXERCICE = 'exercice:';
const jour = () => new Date().toLocaleDateString('sv-SE');

/** Valider l'exercice : la tâche du jour suit (faite / à faire). */
export async function cocherTacheExercice(exerciceId: string, fait: boolean) {
  await supabase.from('taches_elevage').update({ statut: fait ? 'fait' : 'a_faire' })
    .eq('notes', `${PREFIXE_TACHE_EXERCICE}${exerciceId}`).eq('date', jour());
}

/** Tâche « Exercice : … » cochée / décochée dans l'agenda : valide (ou annule)
 *  la réussite ou l'étape du jour. Renvoie une erreur lisible si refusé. */
export async function validerExerciceDepuisTache(notes: string | null | undefined, fait: boolean): Promise<string | null> {
  if (!notes?.startsWith(PREFIXE_TACHE_EXERCICE)) return null;
  const id = notes.slice(PREFIXE_TACHE_EXERCICE.length);
  const { data } = await supabase.from('exercices_attribues')
    .select('id, statut, validations, nb_validations, etapes_snapshot, echeance').eq('id', id).maybeSingle();
  if (!data) return null;
  const ex = data as Parameters<typeof progression>[0];
  const p = progression(ex);
  if (fait && !p.peutValider) return null;          // déjà validé aujourd'hui / terminé
  if (!fait && !(ex.validations ?? []).includes(jour())) return null;
  const { error } = await supabase.from('exercices_attribues').update(majValidation(ex, fait ? 'valider' : 'annuler')).eq('id', id);
  return error ? 'L’exercice n’a pas pu être validé : réessayez.' : null;
}
