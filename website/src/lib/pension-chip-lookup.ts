import { supabase } from '@/lib/supabase';
import type { PensionEntreePrefill } from '@/components/PensionEntreeModal';

interface PuceTrouvee {
  animal_id: string; nom: string | null; espece: string | null; detenteur: string;
  a_vous: boolean; deja_lie: boolean; owner_uid: string | null; owner_profile_id: string | null;
}

/** Recherche un animal par puce (une puce = une fiche, côté serveur :
 *  pm_puce_existante) et résout son propriétaire actuel — nom d'élevage en
 *  priorité si le propriétaire est un pro, sinon prénom+nom. Fiche créée par
 *  un autre pro : la pension y est rattachée (identité seule, son carnet et
 *  ses documents restent privés) si proProfileId est fourni. */
export async function lookupAnimalByChip(chip: string, proProfileId?: string | null): Promise<PensionEntreePrefill> {
  const { data: hits } = await supabase.rpc('pm_puce_existante', { p_identification: chip, p_profile: proProfileId ?? null });
  const hit = ((hits ?? []) as PuceTrouvee[])[0];
  if (!hit) return { puce: chip };
  const { data: row } = await supabase.from('animaux')
    .select('id, nom, espece, race, identification, uid_eleveur, uid_proprietaire').eq('id', hit.animal_id).maybeSingle();
  const found = row ?? { id: hit.animal_id, nom: hit.nom, espece: hit.espece, race: null, identification: chip, uid_eleveur: null, uid_proprietaire: null };

  const next: PensionEntreePrefill = {
    animal_id: found.id, animal_nom: found.nom ?? undefined,
    espece: found.espece ?? undefined, race: found.race ?? undefined,
    puce: found.identification ?? chip,
  };
  if (hit.detenteur === 'pro') {
    if (proProfileId && !hit.deja_lie && !hit.a_vous) {
      await supabase.rpc('pm_rattacher_fiche_pro', { p_profile: proProfileId, p_animal: hit.animal_id, p_client_id: null, p_client: null });
    }
    return next;
  }

  const { data: propRow } = await supabase.from('animaux_proprietes')
    .select('uid_proprio, profile_id_proprio').eq('animal_id', found.id).is('date_fin', null)
    .order('date_debut', { ascending: false }).limit(1).maybeSingle();
  const ownerUid = propRow?.uid_proprio ?? hit.owner_uid ?? found.uid_eleveur ?? found.uid_proprietaire;
  next.owner_uid = ownerUid ?? undefined;
  next.owner_profile_id = propRow?.profile_id_proprio ?? hit.owner_profile_id ?? undefined;

  // Coordonnées du PROFIL propriétaire précis (pas du compte en général) —
  // un éleveur déclare son numéro/nom professionnel sur user_profiles
  // (numero_elevage, nom), distinct du numéro personnel éventuel sur users.
  let filledFromProfile = false;
  if (propRow?.profile_id_proprio) {
    const { data: prof } = await supabase.from('user_profiles_complet')
      .select('nom, firstname, lastname, phone, numero_elevage, profile_type, adresse, rue, code_postal, ville')
      .eq('id', propRow.profile_id_proprio).maybeSingle();
    if (prof) {
      const firstLast = [prof.firstname, prof.lastname].filter(Boolean).join(' ');
      next.proprietaire_nom = prof.nom || firstLast || undefined;
      next.proprietaire_contact = (prof.profile_type === 'eleveur' ? (prof.numero_elevage || prof.phone) : (prof.phone || prof.numero_elevage)) || undefined;
      next.proprietaire_adresse = prof.adresse && prof.adresse !== 'none'
        ? prof.adresse
        : [prof.rue, [prof.code_postal, prof.ville].filter(Boolean).join(' ')].filter(Boolean).join(', ') || undefined;
      filledFromProfile = true;
    }
  }

  if (ownerUid) {
    const { data: owner } = await supabase.from('users_complet')
      .select('name_elevage, firstname, lastname, phone_number, email, adress_elevage, rue_elevage, ville_elevage, code_postal_elevage, rue, code_postal, ville')
      .eq('uid', ownerUid).maybeSingle();
    if (owner) {
      next.proprietaire_email = owner.email || undefined;
      if (!filledFromProfile) {
        const firstLast = [owner.firstname, owner.lastname].filter(Boolean).join(' ');
        next.proprietaire_nom = owner.name_elevage || firstLast || undefined;
        next.proprietaire_contact = owner.phone_number || undefined;
        const rue = owner.adress_elevage || owner.rue_elevage || owner.rue;
        const cp = owner.code_postal_elevage || owner.code_postal;
        const ville = owner.ville_elevage || owner.ville;
        next.proprietaire_adresse = [rue, [cp, ville].filter(Boolean).join(' ')].filter(Boolean).join(', ') || undefined;
      }
    }
  }
  return next;
}

/** Envoie une demande d'accès en lecture à la fiche — reste "pending" tant
 * que le propriétaire n'a pas approuvé depuis sa fiche animal (aucun accès
 * app/site avant validation). ownerProfileId, quand connu (résolu via
 * animaux_proprietes.profile_id_proprio), cible le profil PRÉCIS qui
 * possède l'animal — sinon on retombe sur le profil is_main du compte. */
export async function requestAnimalAccess(
  animalId: string, ownerUid: string, proUid: string, proProfileId: string | null,
  proNom: string, animalNom: string, ownerProfileId?: string | null,
) {
  try {
    if (!proProfileId) return;
    let resolvedOwnerProfileId = ownerProfileId ?? null;
    if (!resolvedOwnerProfileId) {
      const { data: ownerProfiles } = await supabase.from('user_profiles_complet')
        .select('id, is_main').eq('uid', ownerUid);
      resolvedOwnerProfileId = (ownerProfiles ?? []).find(p => p.is_main)?.id ?? ownerProfiles?.[0]?.id ?? null;
    }
    if (!resolvedOwnerProfileId) return;
    const { data: existing } = await supabase.from('animal_access')
      .select('id, statut').eq('pro_profile_id', proProfileId).eq('animal_id', animalId).maybeSingle();
    if (existing) {
      if (existing.statut === 'active' || existing.statut === 'pending') return;
      // Refusée précédemment : une nouvelle demande repart en attente.
      await supabase.from('animal_access').update({ statut: 'pending' }).eq('id', existing.id);
    } else {
      await supabase.from('animal_access').insert({
        pro_profile_id: proProfileId, animal_id: animalId,
        granted_by_profile_id: resolvedOwnerProfileId,
        permissions: ['read_basic', 'read_alimentation', 'read_sante', 'write_notes'],
        statut: 'pending',
      });
    }
    await supabase.from('notifications').insert({
      uid: ownerUid, type: 'pension_acces',
      title: `Demande d'accès à la fiche de ${animalNom}`,
      body: `${proNom} demande à consulter la fiche santé/alimentation de ${animalNom} (admission en pension). À valider depuis la fiche de l'animal.`,
      profile_id: resolvedOwnerProfileId,
      data: { pensionUid: proUid, pensionNom: proNom, animalId },
      read: false,
    });
  } catch { /* silencieux */ }
}
