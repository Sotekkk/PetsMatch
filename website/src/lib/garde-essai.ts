// Pet-sitter — visite d'essai d'un nouveau client (comme l'essai de la pension).
// Réglages dans user_profiles.tarifs_garde : essai_actif, essai (prix TTC),
// essai_duree (min), essai_obligatoire. RDV d'essai : rdv.est_essai ; résultat
// posé par le pet-sitter (rdv.essai_resultat). Miroir appli : lib/utils/garde_essai.dart.
import { supabase } from '@/lib/supabase';

export const MOTIF_ESSAI = "Visite d'essai";

export interface ReglagesEssai { actif: boolean; prix: number; duree: number; obligatoire: boolean }

export function reglagesEssai(tarifs?: Record<string, unknown> | null): ReglagesEssai {
  const t = tarifs ?? {};
  return {
    actif: Number(t.essai_actif) === 1,
    prix: Number(t.essai) || 0,
    duree: Number(t.essai_duree) || 30,
    obligatoire: Number(t.essai_obligatoire) === 1,
  };
}

/** Où en est ce client avec ce pet-sitter :
 *  connu (déjà gardé, ou essai concluant) · nouveau · essai en attente du
 *  résultat · essai non concluant. */
export type EtatEssai = 'connu' | 'nouveau' | 'en_attente' | 'non_concluant';

/** proProfileId : profil pro réservé ; sans profil (activité sur le compte
 *  principal du pet-sitter) : ses RDV sans profil, par son uid. */
export async function etatEssaiClient(clientUid: string, proProfileId: string | null, proUid?: string): Promise<{ etat: EtatEssai; date?: string; motif?: string | null }> {
  let q = supabase.from('rdv').select('statut, date_heure, est_essai, essai_resultat, essai_motif').eq('client_uid', clientUid);
  q = proProfileId ? q.eq('pro_profile_id', proProfileId) : q.eq('pro_uid', proUid ?? '').is('pro_profile_id', null);
  const { data, error } = await q.in('statut', ['demande', 'confirme', 'termine']).order('date_heure', { ascending: false }).limit(200);
  if (error) {
    // Migration migration_garde_essai.sql pas encore passée : règle d'avant.
    let q2 = supabase.from('rdv').select('id').eq('client_uid', clientUid);
    q2 = proProfileId ? q2.eq('pro_profile_id', proProfileId) : q2.eq('pro_uid', proUid ?? '').is('pro_profile_id', null);
    const { data: d2 } = await q2.in('statut', ['confirme', 'termine']).limit(1);
    return { etat: (d2 ?? []).length ? 'connu' : 'nouveau' };
  }
  const l = (data ?? []) as { statut: string; date_heure: string; est_essai?: boolean | null; essai_resultat?: string | null; essai_motif?: string | null }[];
  if (l.some(r => (!r.est_essai && ['confirme', 'termine'].includes(r.statut)) || r.essai_resultat === 'concluant')) return { etat: 'connu' };
  const essai = l.find(r => r.est_essai);
  if (essai?.essai_resultat === 'non_concluant') return { etat: 'non_concluant', date: essai.date_heure, motif: essai.essai_motif };
  if (essai) return { etat: 'en_attente', date: essai.date_heure };
  return { etat: 'nouveau' };
}

/** Résultat de l'essai posé par le pet-sitter, client prévenu. */
export async function poserResultatEssai(rdv: { id: string; client_uid: string; client_profile_id?: string | null; date_heure: string },
  concluant: boolean, motif: string | null, proNom: string): Promise<string | null> {
  const { error } = await supabase.from('rdv').update({
    essai_resultat: concluant ? 'concluant' : 'non_concluant', essai_motif: motif?.trim() || null,
    essai_resultat_le: new Date().toISOString(),
  }).eq('id', rdv.id);
  if (error) return error.message;
  const jour = new Date(rdv.date_heure).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' });
  await supabase.from('notifications').insert({
    uid: rdv.client_uid, type: 'rdv',
    title: concluant ? 'Essai concluant' : 'Essai non concluant',
    body: concluant
      ? `${proNom} valide la visite d'essai du ${jour} : vous pouvez réserver vos gardes.`
      : `${proNom} n'a pas validé la visite d'essai du ${jour}.${motif?.trim() ? ` Motif : ${motif.trim()}` : ''}`,
    data: { rdv_id: rdv.id }, read: false,
    ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
  });
  return null;
}
