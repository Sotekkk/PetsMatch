// Annuler une portée créée depuis une gestation (erreur de saisie) : fiches
// des petits supprimées (carnet, poids… en cascade), tâches de protocole de
// naissance retirées, gestation déliée (bouton « Créer la portée » de retour).
// Refusé dès qu'un petit a vécu quelque chose qu'on ne doit pas effacer :
// plus présent (cédé, décédé), cession ou transfert, autre propriétaire.
// Miroir appli : lib/utils/annuler_portee.dart.
import { supabase } from '@/lib/supabase';

export interface ApercuAnnulationPortee {
  porteeId: string;
  ids: string[];
  noms: string[];
  /** Raison du refus, sinon null (annulation possible). */
  blocage: string | null;
}

const t = (v: unknown) => String(v ?? '').trim();

export async function apercuAnnulationPortee(gestationId: string): Promise<ApercuAnnulationPortee | null> {
  const { data: g } = await supabase.from('gestations').select('animal_id, portee_id').eq('id', gestationId).maybeSingle();
  const porteeId = t(g?.portee_id);
  if (!g || !porteeId) return null;
  const { data: mere } = await supabase.from('animaux').select('uid_eleveur').eq('id', t(g.animal_id)).maybeSingle();
  const eleveur = t(mere?.uid_eleveur);
  const { data } = await supabase.from('animaux').select('id, nom, statut, uid_eleveur').eq('portee_id', porteeId);
  const petits = (data ?? []) as { id: string; nom: string | null; statut: string | null; uid_eleveur: string | null }[];
  const ids = petits.map(p => t(p.id));
  const noms = petits.map(p => t(p.nom) || 'Sans nom');
  let blocage: string | null = null;
  const partis = petits.filter(p => t(p.statut) && t(p.statut) !== 'present');
  if (partis.length) {
    blocage = `${partis.map(p => t(p.nom)).join(', ')} ${partis.length > 1 ? 'ne sont plus présents' : "n'est plus présent"} (cédé, décédé…).`;
  } else if (petits.some(p => eleveur && t(p.uid_eleveur) !== eleveur)) {
    blocage = "Un petit n'appartient plus à l'élevage de la mère.";
  } else if (ids.length) {
    const [{ data: cessions }, { data: proprio }] = await Promise.all([
      supabase.from('cessions').select('animal_id').in('animal_id', ids).limit(1),
      supabase.from('animaux_proprietes').select('animal_id, uid_proprio, date_fin').in('animal_id', ids),
    ]);
    if ((cessions ?? []).length) blocage = 'Une cession a été préparée pour un petit.';
    else if (((proprio ?? []) as { uid_proprio: string | null; date_fin: string | null }[])
      .some(r => r.date_fin || (eleveur && t(r.uid_proprio) !== eleveur))) blocage = 'Un petit a changé de propriétaire.';
  }
  return { porteeId, ids, noms, blocage };
}

/** Annule après vérification ; renvoie un message d'erreur, ou null si c'est fait. */
export async function annulerPortee(gestationId: string): Promise<string | null> {
  const a = await apercuAnnulationPortee(gestationId);
  if (!a) return "Cette gestation n'a pas de portée créée.";
  if (a.blocage) return `Annulation impossible : ${a.blocage}`;
  if (a.ids.length) {
    // Tâches liées aux petits (protocoles de naissance, tâches manuelles).
    await supabase.from('plan_taches').delete().in('animal_id', a.ids);
    await supabase.from('plans_actifs').delete().in('reference_id', a.ids);
    await supabase.from('taches_elevage').delete().in('animal_id', a.ids);
    // Fiches : seulement celles vérifiées (même portée, toujours présentes).
    const { error } = await supabase.from('animaux').delete().in('id', a.ids).eq('portee_id', a.porteeId)
      .or('statut.is.null,statut.eq.present');
    if (error) return `L'annulation n'a pas pu aller au bout : ${error.message}`;
  }
  const { error: e2 } = await supabase.from('gestations').update({ portee_id: null }).eq('id', gestationId);
  return e2 ? `L'annulation n'a pas pu aller au bout : ${e2.message}` : null;
}
