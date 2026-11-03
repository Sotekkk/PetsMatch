// Dossier de la séance : « Prochain rendez-vous » (facultatif) — le pro peut
// programmer le suivant tout de suite, sinon le client le prend plus tard.
// Miroir appli : lib/utils/prochain_rdv.dart.
import { supabase } from '@/lib/supabase';

export interface ProchainRdv {
  /** Prochain RDV déjà pris avec ce pro pour cet animal (date ISO), ou null. */
  date: string | null;
  /** Page de prise de RDV préremplie (animal, motif). */
  chemin: string;
}

export async function prochainRdv(rdvId: string): Promise<ProchainRdv> {
  const { data: r } = await supabase.from('rdv').select('animal_id, pro_profile_id, pro_uid, date_heure, motif').eq('id', rdvId).maybeSingle();
  const x = r as { animal_id?: string | number | null; pro_profile_id?: string | null; pro_uid?: string | null; date_heure?: string; motif?: string | null } | null;
  const q = new URLSearchParams({ nouveau: '1' });
  if (x?.animal_id != null) q.set('animal', String(x.animal_id));
  if (x?.motif) q.set('motif', x.motif);
  let date: string | null = null;
  if (x?.animal_id != null && x.date_heure) {
    let s = supabase.from('rdv').select('date_heure').eq('animal_id', String(x.animal_id))
      .gt('date_heure', x.date_heure).in('statut', ['demande', 'confirme', 'contre_proposition'])
      .order('date_heure').limit(1);
    s = x.pro_profile_id ? s.eq('pro_profile_id', x.pro_profile_id) : s.eq('pro_uid', x.pro_uid ?? '');
    const { data } = await s.maybeSingle();
    date = (data as { date_heure?: string } | null)?.date_heure ?? null;
  }
  return { date, chemin: `/mes-rdv?${q.toString()}` };
}

export const libelleProchainRdv = (p: ProchainRdv | null) => !p ? '' : p.date
  ? `Prévu le ${new Date(p.date).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' })} à ${new Date(p.date).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`
  : 'Facultatif — le client peut aussi le prendre plus tard';
