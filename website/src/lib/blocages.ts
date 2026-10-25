// Utilisateurs bloqués — source de vérité : table Supabase `bloquages`
// (messagerie, appli + site). L'ancienne liste Firestore `bloquer/{uid}`
// (fil d'actualité historique) est encore lue et tenue à jour pour ne perdre
// aucun blocage passé. Miroir de lib/services/blocages_service.dart (appli).
import { deleteField, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';

/** Bloque autreUid. Déjà bloqué : rien ne change, aucune erreur. */
export async function bloquer(moi: string, autreUid: string): Promise<void> {
  if (!moi || !autreUid || autreUid === moi) return;
  const { error } = await supabase.from('bloquages')
    .upsert({ uid: moi, blocked_uid: autreUid }, { onConflict: 'uid,blocked_uid', ignoreDuplicates: true });
  if (error) throw error;
  try { await setDoc(doc(db, 'bloquer', moi), { [autreUid]: true }, { merge: true }); } catch { /* ancienne liste */ }
}

/** Débloque autreUid des deux listes. */
export async function debloquer(moi: string, autreUid: string): Promise<void> {
  const { error } = await supabase.from('bloquages').delete().eq('uid', moi).eq('blocked_uid', autreUid);
  if (error) throw error;
  try { await updateDoc(doc(db, 'bloquer', moi), { [autreUid]: deleteField() }); } catch { /* absente */ }
}

/** Uids que j'ai bloqués (les deux listes réunies). */
export async function mesBloques(moi: string): Promise<string[]> {
  const ids = new Set<string>();
  const { data } = await supabase.from('bloquages').select('blocked_uid').eq('uid', moi);
  (data ?? []).forEach((r: { blocked_uid: string }) => ids.add(r.blocked_uid));
  try {
    const snap = await getDoc(doc(db, 'bloquer', moi));
    if (snap.exists()) Object.entries(snap.data() ?? {}).forEach(([k, v]) => { if (v === true) ids.add(k); });
  } catch { /* ancienne liste */ }
  ids.delete(moi);
  return [...ids];
}
