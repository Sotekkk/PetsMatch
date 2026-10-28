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

export async function enregistrerSignaturePro(uid: string, dataUrl: string): Promise<boolean> {
  const { error } = await supabase.from('signatures_pro')
    .upsert({ uid, signature: dataUrl, updated_at: new Date().toISOString() }, { onConflict: 'uid' });
  return !error;
}
