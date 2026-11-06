// « Terminé » cliqué par erreur : le RDV redevient confirmé, pour tous les
// métiers (agenda Gérer mes RDV, tableaux de bord). Miroir appli :
// lib/utils/rdv_reouvrir.dart.
//  • statut 'confirme', heure réelle de fin effacée ;
//  • garde : départ validé effacé ; intervention vétérinaire : sortie effacée
//    (le trigger trg_rdv_sortie_statut suit) ;
//  • demande d'avis envoyée au client à la clôture : retirée si elle n'est pas lue.
// Rien d'autre n'est touché : compte rendu, facture, contrat, documents envoyés,
// forfait (décompte rendu depuis le dossier, « Rendre au forfait »).
import { supabase } from '@/lib/supabase';

export async function rouvrirRdv(rdv: { id: string; client_uid?: string | null }): Promise<string | null> {
  const { data: r } = await supabase.from('rdv').select('statut, depart_valide_le, sortie_le').eq('id', rdv.id).maybeSingle();
  const x = r as { statut?: string; depart_valide_le?: string | null; sortie_le?: string | null } | null;
  if (!x) return 'Rendez-vous introuvable.';
  if (x.statut !== 'termine') return null;
  const { error } = await supabase.from('rdv').update({
    statut: 'confirme', termine_at: null,
    ...(x.depart_valide_le ? { depart_valide_le: null } : {}),
    ...(x.sortie_le ? { sortie_le: null } : {}),
  }).eq('id', rdv.id);
  if (error) return error.message;
  if (rdv.client_uid) {
    try {
      await supabase.from('notifications').delete().eq('uid', rdv.client_uid).eq('type', 'avis_demande')
        .eq('read', false).contains('data', { rdv_id: rdv.id });
    } catch { /* la demande d'avis reste : sans effet sur le RDV */ }
  }
  return null;
}

export const MESSAGE_CONFIRMER_TERMINE = 'Marquer ce rendez-vous comme terminé ?\n\nVous pourrez annuler avec « Annuler « Terminé » » dans l’historique.';
