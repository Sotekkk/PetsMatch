import { supabase } from '@/lib/supabase';
import type { PensionEntreePrefill } from '@/components/PensionEntreeModal';

/** Recherche un animal par puce et résout son propriétaire actuel via
 * animaux_proprietes (source unique, date_fin IS NULL) — nom d'élevage
 * en priorité si le propriétaire est un pro, sinon prénom+nom. */
export async function lookupAnimalByChip(chip: string): Promise<PensionEntreePrefill> {
  const normalized = chip.replace(/[\s-]/g, '');
  const { data } = await supabase.from('animaux')
    .select('id, nom, espece, race, identification, uid_eleveur, uid_proprietaire')
    .not('identification', 'is', null);
  const found = (data ?? []).find(a => (a.identification ?? '').replace(/[\s-]/g, '') === normalized);
  if (!found) return { puce: chip };

  const next: PensionEntreePrefill = {
    animal_id: found.id, animal_nom: found.nom ?? undefined,
    espece: found.espece ?? undefined, race: found.race ?? undefined,
    puce: found.identification ?? chip,
  };

  const { data: propRow } = await supabase.from('animaux_proprietes')
    .select('uid_proprio').eq('animal_id', found.id).is('date_fin', null)
    .order('date_debut', { ascending: false }).limit(1).maybeSingle();
  const ownerUid = propRow?.uid_proprio ?? found.uid_eleveur ?? found.uid_proprietaire;
  next.owner_uid = ownerUid ?? undefined;
  if (ownerUid) {
    const { data: owner } = await supabase.from('users')
      .select('name_elevage, firstname, lastname, phone_number, email, adress_elevage, rue_elevage, ville_elevage, code_postal_elevage, rue, code_postal, ville')
      .eq('uid', ownerUid).maybeSingle();
    if (owner) {
      const firstLast = [owner.firstname, owner.lastname].filter(Boolean).join(' ');
      next.proprietaire_nom = owner.name_elevage || firstLast || undefined;
      next.proprietaire_contact = owner.phone_number || undefined;
      next.proprietaire_email = owner.email || undefined;
      const rue = owner.adress_elevage || owner.rue_elevage || owner.rue;
      const cp = owner.code_postal_elevage || owner.code_postal;
      const ville = owner.ville_elevage || owner.ville;
      next.proprietaire_adresse = [rue, [cp, ville].filter(Boolean).join(' ')].filter(Boolean).join(', ') || undefined;
    }
  }
  return next;
}

/** Demande d'accès en lecture à la fiche pour le pro connecté — no-op si
 * déjà demandé/accordé, silencieux en cas d'erreur (ex: profil introuvable). */
export async function requestAnimalAccess(animalId: string, ownerUid: string, proUid: string, proProfileId: string | null, proNom: string, animalNom: string) {
  try {
    if (!proProfileId) return;
    const { data: ownerProfile } = await supabase.from('user_profiles')
      .select('id').eq('uid', ownerUid).eq('is_main', true).maybeSingle();
    const ownerProfileId = ownerProfile?.id as string | undefined;
    if (!ownerProfileId) return;
    const { data: existing } = await supabase.from('animal_access')
      .select('id').eq('pro_profile_id', proProfileId).eq('animal_id', animalId).maybeSingle();
    if (existing) return;
    await supabase.from('animal_access').insert({
      pro_profile_id: proProfileId, animal_id: animalId,
      granted_by_profile_id: ownerProfileId,
      permissions: ['read_basic', 'read_alimentation', 'write_notes'],
      statut: 'pending',
    });
    await supabase.from('notifications').insert({
      uid: ownerUid, type: 'pension_acces',
      title: `Demande d'accès à la fiche de ${animalNom}`,
      body: `${proNom} souhaite consulter la fiche en pension (lecture seule).`,
      data: { pensionUid: proUid, pensionNom: proNom, animalId },
      read: false,
    });
  } catch { /* silencieux */ }
}
