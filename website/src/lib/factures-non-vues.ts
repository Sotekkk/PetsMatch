// Bulle rouge « nouvelle facture » côté client (Administratif → Mes Factures).
// Non vue = facture reçue après la dernière ouverture de « Mes Factures »
// (table factures_vues, partagée avec l'appli — migration_factures_vues.sql).
// Même filtre que /mes-factures : client_profile_id du profil actif, sinon
// client_uid. Miroir appli : lib/services/factures_non_vues.dart.

import { supabase } from '@/lib/supabase';

export const FACTURES_VUES_EVENT = 'pm-factures-vues';

/** Sans ouverture enregistrée : seules les factures des 30 derniers jours. */
const FENETRE_MS = 30 * 86400000;

/** Profil principal = une seule clé (uid), comme l'appli ; profil secondaire = son identifiant. */
async function cleVue(uid: string, profileId: string): Promise<string> {
  if (!profileId) return uid;
  const { data } = await supabase.from('user_profiles').select('is_main').eq('id', profileId).maybeSingle();
  return (data as { is_main?: boolean } | null)?.is_main ? uid : profileId;
}

/** Date de la dernière ouverture de « Mes Factures », ou null. */
export async function derniereVueFactures(uid: string, profileId: string): Promise<string | null> {
  const { data } = await supabase.from('factures_vues').select('vu_le').eq('cle', await cleVue(uid, profileId)).maybeSingle();
  return (data as { vu_le: string } | null)?.vu_le ?? null;
}

export async function compterFacturesNonVues(uid: string, profileId: string): Promise<number> {
  if (!uid) return 0;
  try {
    const vuLe = await derniereVueFactures(uid, profileId);
    const depuis = vuLe ?? new Date(Date.now() - FENETRE_MS).toISOString();
    const q = supabase.from('factures').select('id', { count: 'exact', head: true })
      .gt('created_at', depuis).neq('statut', 'annulee');
    const { count } = await (profileId ? q.eq('client_profile_id', profileId) : q.eq('client_uid', uid));
    return count ?? 0;
  } catch { return 0; }
}

export async function marquerFacturesVues(uid: string, profileId: string): Promise<void> {
  if (!uid) return;
  try {
    await supabase.from('factures_vues').upsert({ cle: await cleVue(uid, profileId), uid, vu_le: new Date().toISOString() });
  } catch { /* table absente : pas de bulle, rien de bloquant */ }
  window.dispatchEvent(new Event(FACTURES_VUES_EVENT));
}
