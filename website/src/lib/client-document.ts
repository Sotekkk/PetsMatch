// Propriétaire / client porté sur les documents médicaux (compte rendu,
// ordonnance, comptes rendus d'intervention) : nom ET coordonnées (adresse,
// téléphone, e-mail), avec la même cascade que la facture — coordonnées de
// facturation PetsMatch (pm_client_facturation), sinon fichier clients de la
// clinique, sinon client saisi sur le RDV. Miroir appli :
// lib/utils/client_document.dart.

import { supabase } from '@/lib/supabase';

export interface ClientDocument {
  nom: string;
  /** Lignes affichées sous le nom : adresse, téléphone, e-mail. */
  coord: string[];
  email: string | null;
}

const v = (x: unknown) => String(x ?? '').trim();

function lignes(rue: unknown, cp: unknown, ville: unknown, tel: unknown, email: unknown): string[] {
  const villeTxt = `${v(cp)} ${v(ville)}`.trim();
  return [
    [v(rue), villeTxt].filter(Boolean).join(', '),
    v(tel) ? `Tél. ${v(tel)}` : '',
    v(email),
  ].filter(Boolean);
}

export async function clientDocument(animalId: string, opts: { rdvId?: string | null; clientProfileId?: string | null } = {}): Promise<ClientDocument> {
  let rdv: Record<string, unknown> | null = null;
  if (opts.rdvId) {
    const { data } = await supabase.from('rdv').select('client_profile_id, client_nom_manuel, client_email_manuel, client_telephone_manuel')
      .eq('id', opts.rdvId).maybeSingle();
    rdv = (data ?? null) as Record<string, unknown> | null;
  }
  const profil = opts.clientProfileId ?? (v(rdv?.client_profile_id) || null);

  // 1. Client PetsMatch : coordonnées de facturation (particulier, élevage, association).
  const { data: cf } = await supabase.rpc('pm_client_facturation', { p_animal_id: animalId, ...(profil ? { p_client_profile_id: profil } : {}) });
  const j = (cf ?? null) as Record<string, string> | null;
  if (j && (v(j.nom) || v(j.prenom) || v(j.societe))) {
    const nom = v(j.societe) || `${v(j.prenom)} ${v(j.nom)}`.trim();
    return { nom, coord: lignes(j.rue, j.code_postal, j.ville, j.telephone, j.email), email: v(j.email) || null };
  }
  // 2. Client du fichier de la clinique (sans compte PetsMatch).
  const { data: an } = await supabase.from('animaux').select('client_clinique_id, uid_proprietaire').eq('id', animalId).maybeSingle();
  const a = (an ?? {}) as Record<string, unknown>;
  if (a.client_clinique_id) {
    const { data: cc } = await supabase.from('clients_clinique').select('nom, prenom, email, telephone, adresse, code_postal, ville')
      .eq('id', a.client_clinique_id as string).maybeSingle();
    if (cc) return { nom: `${v(cc.prenom)} ${v(cc.nom)}`.trim(), coord: lignes(cc.adresse, cc.code_postal, cc.ville, cc.telephone, cc.email), email: v(cc.email) || null };
  }
  // 3. Client saisi sur le RDV.
  if (rdv && v(rdv.client_nom_manuel)) {
    return { nom: v(rdv.client_nom_manuel), coord: lignes('', '', '', rdv.client_telephone_manuel, rdv.client_email_manuel), email: v(rdv.client_email_manuel) || null };
  }
  // 4. Nom du compte propriétaire.
  if (a.uid_proprietaire) {
    const { data: u } = await supabase.from('users_complet').select('firstname, lastname').eq('uid', a.uid_proprietaire as string).maybeSingle();
    return { nom: `${v(u?.firstname)} ${v(u?.lastname)}`.trim(), coord: [], email: null };
  }
  return { nom: '', coord: [], email: null };
}
