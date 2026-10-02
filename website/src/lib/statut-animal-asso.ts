// Changement de statut d'un animal d'association — MIROIR de l'appli
// (animal_fiche.dart _save) : une sortie (adopté / transféré / décédé)
// clôture la propriété (animaux_proprietes.date_fin) et s'inscrit au
// registre des mouvements ; un retour (sorti → présent) rouvre la propriété.
// Avant, le site n'écrivait que le statut (registre légal incomplet).
import { supabase } from '@/lib/supabase';

export const STATUTS_SORTIE = ['adopte', 'transfere', 'decede'];

export const LIBELLES_STATUT: Record<string, string> = {
  en_soin: 'En soin', disponible: "Disponible à l'adoption", adopte: 'Adopté',
  transfere: 'Transféré', decede: 'Décédé',
};

/** Demande confirmation pour une sortie. false = annulé. */
export function confirmerSortie(nouveau: string): boolean {
  if (!STATUTS_SORTIE.includes(nouveau)) return true;
  return window.confirm(
    `Passer en « ${LIBELLES_STATUT[nouveau] ?? nouveau} » ?\n\n` +
    "L'animal sortira de vos animaux présents et la sortie sera inscrite au registre. " +
    'Complétez au besoin le destinataire dans le registre entrées / sorties.',
  );
}

export async function changerStatutAnimalAsso(animalId: string, ancien: string | undefined, nouveau: string, uidProprio: string) {
  const { error } = await supabase.from('animaux').update({ statut: nouveau }).eq('id', animalId);
  if (error) throw error;
  const etaitSorti = STATUTS_SORTIE.includes(ancien ?? '');
  const devientSorti = STATUTS_SORTIE.includes(nouveau);
  const jour = new Date().toISOString().slice(0, 10);

  if (devientSorti && !etaitSorti) {
    await supabase.from('animaux_proprietes').update({ date_fin: jour })
      .eq('animal_id', animalId).eq('uid_proprio', uidProprio).is('date_fin', null);
    const { data: deja } = await supabase.from('registre_mouvements')
      .select('id').eq('animal_id', animalId).eq('type', 'sortie').limit(1);
    if (!deja || deja.length === 0) {
      await supabase.from('registre_mouvements').insert({
        animal_id: animalId, uid_eleveur: uidProprio, type: 'sortie',
        date_mouvement: jour, motif: nouveau === 'decede' ? 'autre' : 'cession',
      });
    }
  } else if (!devientSorti && etaitSorti) {
    await supabase.from('animaux_proprietes').update({ date_fin: null })
      .eq('animal_id', animalId).eq('uid_proprio', uidProprio).not('date_fin', 'is', null);
  }
}
