// Bulle rouge « nouvelle facture » côté client (Administratif → Mes Factures).
// Non vue = facture reçue après la dernière ouverture de « Mes Factures »
// (table factures_vues, partagée avec l'appli — migration_factures_vues.sql).
// Même filtre que /mes-factures : client_profile_id du profil actif, sinon
// client_uid. Miroir appli : lib/services/factures_non_vues.dart.

import { supabase } from '@/lib/supabase';

export const FACTURES_VUES_EVENT = 'pm-factures-vues';

/** Sans ouverture enregistrée : seules les factures des 30 derniers jours. */
const FENETRE_MS = 30 * 86400000;

export async function compterFacturesNonVues(uid: string, profileId: string): Promise<number> {
  if (!uid) return 0;
  try {
    const { data: vu } = await supabase.from('factures_vues').select('vu_le').eq('cle', profileId || uid).maybeSingle();
    const depuis = (vu as { vu_le: string } | null)?.vu_le ?? new Date(Date.now() - FENETRE_MS).toISOString();
    const q = supabase.from('factures').select('id', { count: 'exact', head: true })
      .gt('created_at', depuis).neq('statut', 'annulee');
    const { count } = await (profileId ? q.eq('client_profile_id', profileId) : q.eq('client_uid', uid));
    return count ?? 0;
  } catch { return 0; }
}

export async function marquerFacturesVues(uid: string, profileId: string): Promise<void> {
  if (!uid) return;
  try {
    await supabase.from('factures_vues').upsert({ cle: profileId || uid, uid, vu_le: new Date().toISOString() });
  } catch { /* table absente : pas de bulle, rien de bloquant */ }
  window.dispatchEvent(new Event(FACTURES_VUES_EVENT));
}
