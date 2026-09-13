// Helpers de facturation garde — mêmes règles que lib/pages/pro/garde_facture_helper.dart
// (gardePrestationKey, gardeJoursAFacturer, gardePeriodeLabel, gardeTarif).
// Regroupement en "séjour" pur (sans requête) : voir garde-sejours.ts.

import { supabase } from '@/lib/supabase';

export function gardePrestationKey(motif?: string | null): string {
  const m = (motif ?? '').toLowerCase();
  if (m.includes('visite')) return 'visite';
  if (m.includes('promenade') && m.includes('30')) return 'promenade_30min';
  if (m.includes('promenade') && m.includes('2')) return 'promenade_2h';
  if (m.includes('promenade')) return 'promenade_1h';
  if (m.includes('garde') || m.includes('journ')) return 'garde_journee';
  return 'autre';
}

export interface GardeRdvFacture {
  id: string;
  animal_id: string | null;
  client_uid: string | null;
  client_profile_id?: string | null;
  date_heure: string;
  motif?: string | null;
  statut?: string | null;
  facture_id?: string | null;
}

/** Jours d'une même garde encore non facturés (mêmes client + animal, motif
 * garde-journée, statut confirmé/terminé, facture_id nul), triés par date.
 * Inclut `rdv` lui-même. Retourne `[rdv]` si ce n'est pas une garde-journée. */
export async function gardeJoursAFacturer(
  proUid: string, proProfileId: string | null, rdv: GardeRdvFacture,
): Promise<GardeRdvFacture[]> {
  if (gardePrestationKey(rdv.motif) !== 'garde_journee') return [rdv];
  if (!rdv.client_uid) return [rdv];
  let q = supabase.from('rdv').select('id, animal_id, client_uid, client_profile_id, date_heure, motif, statut, facture_id')
    .eq('pro_uid', proUid).eq('client_uid', rdv.client_uid);
  if (proProfileId) q = q.eq('pro_profile_id', proProfileId) as typeof q;
  if (rdv.animal_id) q = q.eq('animal_id', rdv.animal_id) as typeof q;
  const { data } = await q.in('statut', ['confirme', 'termine']).is('facture_id', null).order('date_heure', { ascending: true });
  const jours = ((data ?? []) as GardeRdvFacture[]).filter(r => gardePrestationKey(r.motif) === 'garde_journee');
  return jours.length ? jours : [rdv];
}

/** « du JJ/MM au JJ/MM » (ou « le JJ/MM » si un seul jour). */
export function gardePeriodeLabel(jours: GardeRdvFacture[]): string {
  const dates = jours.map(j => new Date(j.date_heure)).filter(d => !isNaN(d.getTime())).sort((a, b) => a.getTime() - b.getTime());
  if (!dates.length) return '';
  const f = (d: Date) => d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
  return dates.length === 1 ? `le ${f(dates[0])}` : `du ${f(dates[0])} au ${f(dates[dates.length - 1])}`;
}

/** Prix HT (€) : surcharge client (tarifs_clients_garde) sinon tarif standard
 * (user_profiles.tarifs_garde) sinon 0. */
export async function gardeTarif(proUid: string, proProfileId: string | null, rdv: GardeRdvFacture): Promise<number> {
  if (!proProfileId) return 0;
  const key = gardePrestationKey(rdv.motif);
  if (rdv.client_profile_id) {
    const { data } = await supabase.from('tarifs_clients_garde').select('prix')
      .eq('pro_uid', proUid).eq('pro_profile_id', proProfileId)
      .eq('owner_profile_id', rdv.client_profile_id).eq('prestation_type', key).maybeSingle();
    const p = data?.prix as number | undefined;
    if (p != null && p > 0) return p;
  }
  const { data: prof } = await supabase.from('user_profiles').select('tarifs_garde').eq('id', proProfileId).maybeSingle();
  const tg = prof?.tarifs_garde as Record<string, number> | null;
  return (tg && typeof tg[key] === 'number') ? tg[key] : 0;
}
