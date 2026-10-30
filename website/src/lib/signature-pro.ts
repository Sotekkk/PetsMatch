// Signature manuscrite du professionnel (table signatures_pro, migration
// migration_signatures_pro.sql) : dessinée une fois, comme pour les contrats,
// puis apposée sur ses comptes rendus et ordonnances. Lisible par son seul
// propriétaire. Miroir appli : lib/utils/signature_pro.dart.
import { supabase } from '@/lib/supabase';

/** Signature enregistrée (data-URL PNG), ou null. */
export async function maSignaturePro(uid: string): Promise<string | null> {
  const { data } = await supabase.from('signatures_pro').select('signature').eq('uid', uid).maybeSingle();
  return (data as { signature?: string } | null)?.signature || null;
}

/** Contrat généré par le pro : sa signature enregistrée y est apposée d'office
 *  (côté « professionnel » du contrat). Faux si aucune signature / échec. */
export async function signerContratAvecSignaturePro(docId: string, uid: string, nom: string, signature?: string | null): Promise<boolean> {
  const sig = signature ?? await maSignaturePro(uid).catch(() => null);
  if (!sig) return false;
  const res = await fetch(`/api/contracts/${docId}/sign`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ role: 'eleveur', signature: sig, actorUid: uid, actorNom: nom }),
  });
  return res.ok;
}

export async function enregistrerSignaturePro(uid: string, dataUrl: string): Promise<boolean> {
  const { error } = await supabase.from('signatures_pro')
    .upsert({ uid, signature: dataUrl, updated_at: new Date().toISOString() }, { onConflict: 'uid' });
  return !error;
}
