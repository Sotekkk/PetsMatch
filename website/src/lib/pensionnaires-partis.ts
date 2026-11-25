// Animaux partis de la pension : dernier séjour terminé, aucun séjour en cours
// ou à venir, aucune demande de séjour ni RDV à venir, accès non redonné depuis
// la sortie. Retirés de « Accès fiche pensionnaire » (l'accès du propriétaire
// n'est pas supprimé).
// Miroir appli : lib/utils/pensionnaires_partis.dart.
import { supabase } from '@/lib/supabase';
import { idsAnimauxDuRdv } from '@/lib/acces-rdv';

const jour = (v?: string | null) => {
  if (!v) return '';
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? ''
    : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

/** `accesLe` : animal_id → date de l'accès (granted_at, sinon created_at).
 *  Une lecture en échec : aucun animal considéré comme parti. */
export async function animauxPartis(proProfileId: string, accesLe: Map<string, string>): Promise<Set<string>> {
  if (accesLe.size === 0) return new Set();
  const ids = [...accesLe.keys()];
  const [ent, dem, rdv] = await Promise.all([
    supabase.from('pension_entrees').select('animal_id, statut, date_sortie_effective, date_sortie_prevue')
      .eq('pro_profile_id', proProfileId).in('animal_id', ids),
    supabase.from('pension_demandes').select('animal_id')
      .eq('pro_profile_id', proProfileId).eq('statut', 'demande').in('animal_id', ids),
    supabase.from('rdv').select('*').eq('pro_profile_id', proProfileId)
      .in('statut', ['demande', 'contre_proposition', 'confirme'])
      .gte('date_heure', new Date(Date.now() - 86400000).toISOString()),
  ]);
  if (ent.error || dem.error || rdv.error) return new Set();
  const attendus = new Set<string>();
  for (const e of ent.data ?? []) if (e.statut === 'en_pension') attendus.add(String(e.animal_id));
  for (const d of dem.data ?? []) attendus.add(String(d.animal_id));
  for (const r of rdv.data ?? []) for (const id of idsAnimauxDuRdv(r)) attendus.add(id);
  const sortie = new Map<string, string>();
  for (const e of ent.data ?? []) {
    if (e.statut !== 'sorti') continue;
    const id = String(e.animal_id);
    const j = jour(e.date_sortie_effective) || jour(e.date_sortie_prevue);
    if (j >= (sortie.get(id) ?? '')) sortie.set(id, j);
  }
  const partis = new Set<string>();
  for (const [id, j] of sortie) {
    if (!attendus.has(id) && !(j && jour(accesLe.get(id)) > j)) partis.add(id);
  }
  return partis;
}
