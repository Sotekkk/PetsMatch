// Accès à la fiche des animaux d'un RDV, accordé à la confirmation par le pro
// (A60, miroir appli : pro_agenda.dart _autoGrantAccess). Sans lui, la fiche
// d'un RDV confirmé (ex. visite de la pension, visite d'essai du pet-sitter)
// restait « accès refusé » sur le site. Tous les animaux du RDV (animal_id,
// animaux_ids, animaux_detail). Un accès déjà donné par le propriétaire
// (réservation, séjour) n'est jamais écrasé.
import { supabase } from '@/lib/supabase';

type RdvAcces = {
  animal_id?: string | number | null; animaux_ids?: unknown; animaux_detail?: unknown;
  client_profile_id?: string | null; pro_profile_id?: string | null;
};

export function idsAnimauxDuRdv(rdv: RdvAcces): string[] {
  const ids = new Set<string>();
  if (rdv.animal_id) ids.add(String(rdv.animal_id));
  if (Array.isArray(rdv.animaux_ids)) for (const x of rdv.animaux_ids) if (x) ids.add(String(x));
  if (Array.isArray(rdv.animaux_detail)) for (const x of rdv.animaux_detail as { id?: unknown }[]) if (x?.id) ids.add(String(x.id));
  return [...ids];
}

export async function accorderAccesRdv(rdv: RdvAcces, catPro?: string | null, proProfileIdDefaut?: string | null): Promise<void> {
  const proProfileId = rdv.pro_profile_id || proProfileIdDefaut;
  if (!proProfileId) return;
  if (!catPro) {
    const { data: pp } = await supabase.from('user_profiles_complet').select('cat_pro').eq('id', proProfileId).maybeSingle();
    catPro = (pp as { cat_pro?: string | null } | null)?.cat_pro ?? null;
  }
  const permissions = catPro === 'veterinaire' ? ['read_basic', 'read_health', 'write_health']
    : catPro === 'pension' ? ['read_basic', 'read_alimentation', 'write_notes']
    : ['read_basic', 'write_notes'];
  for (const animalId of idsAnimauxDuRdv(rdv)) {
    try {
      // Profil propriétaire : celui du client du RDV, sinon le propriétaire actuel.
      let owner = rdv.client_profile_id ?? null;
      if (!owner) {
        const { data } = await supabase.from('animaux_proprietes').select('profile_id_proprio')
          .eq('animal_id', animalId).is('date_fin', null).limit(1);
        owner = ((data ?? [])[0] as { profile_id_proprio?: string | null } | undefined)?.profile_id_proprio ?? null;
      }
      if (!owner) continue;
      const { data: existant } = await supabase.from('animal_access').select('statut')
        .eq('animal_id', animalId).eq('pro_profile_id', proProfileId).maybeSingle();
      if (existant && (existant as { statut?: string }).statut !== 'pending') continue;
      await supabase.from('animal_access').upsert({
        animal_id: animalId, pro_profile_id: proProfileId, granted_by_profile_id: owner,
        permissions, statut: 'active', granted_at: new Date().toISOString(),
      }, { onConflict: 'animal_id,pro_profile_id' });
    } catch { /* accès non accordé : la fiche affichera pourquoi */ }
  }
}
