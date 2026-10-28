// Comptes rendus vétérinaires d'un RDV, par animal. Ceux rattachés au RDV
// (rdv_id), et à défaut ceux rédigés depuis la fiche de l'animal (sans lien)
// le jour du RDV par le même profil : ils comptent comme ceux du RDV.
// Miroir appli : choisirAnimalRdv / _loadExisting (rdv_animaux.dart, compte_rendu_page.dart).
import { supabase } from '@/lib/supabase';

export interface CrDuRdv { id: string; animal_id: string; statut: string | null; created_at: string; rattache: boolean }

export async function crsDuRdv(rdvId: string, animalIds: string[]): Promise<CrDuRdv[]> {
  const { data: lies } = await supabase.from('comptes_rendus').select('id, animal_id, statut, created_at').eq('rdv_id', rdvId)
    .order('created_at', { ascending: false });
  const res: CrDuRdv[] = ((lies ?? []) as Omit<CrDuRdv, 'rattache'>[]).map(c => ({ ...c, animal_id: String(c.animal_id), rattache: true }));
  const manquants = animalIds.filter(id => !res.some(c => c.animal_id === id));
  if (manquants.length === 0) return res;
  const { data: r } = await supabase.from('rdv').select('date_heure, pro_profile_id').eq('id', rdvId).maybeSingle();
  if (!r?.date_heure || !r.pro_profile_id) return res;
  const j = new Date(r.date_heure as string);
  const debut = new Date(j.getFullYear(), j.getMonth(), j.getDate());
  const { data: libres } = await supabase.from('comptes_rendus').select('id, animal_id, statut, created_at')
    .in('animal_id', manquants).is('rdv_id', null).eq('pro_profile_id', r.pro_profile_id)
    .gte('created_at', debut.toISOString()).lt('created_at', new Date(debut.getTime() + 86400000).toISOString())
    .order('created_at', { ascending: false });
  for (const c of (libres ?? []) as Omit<CrDuRdv, 'rattache'>[]) res.push({ ...c, animal_id: String(c.animal_id), rattache: false });
  return res;
}
