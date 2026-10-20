// Client d'un séjour en pension (pension_entrees) : la demande de séjour, sinon
// le propriétaire de la fiche (animaux_proprietes, profil EXACT — un élevage qui
// met un animal en pension reste l'élevage, jamais is_main). Coordonnées : le
// profil, sinon le compte (users_complet), sinon ce qui est saisi sur le séjour.
// Utilisé par la facture (navigateur) et le contrat (serveur, service role).
// Miroir appli : lib/utils/client_pension.dart.
import type { SupabaseClient } from '@supabase/supabase-js';

export interface ClientPension {
  uid: string | null; profileId: string | null; estPro: boolean;
  prenom: string; nom: string; email: string; tel: string; rue: string; cp: string; ville: string;
}

type Ligne = Record<string, unknown>;
const t = (v: unknown) => (v == null ? '' : String(v).trim());
const premier = (...v: unknown[]) => v.map(t).find(x => x !== '') ?? '';

export function nomComplet(c: ClientPension) { return `${c.prenom} ${c.nom}`.trim(); }
export function adresseClient(c: ClientPension) { return [c.rue, [c.cp, c.ville].filter(Boolean).join(' ')].filter(Boolean).join(', '); }

export async function clientDuSejour(sb: SupabaseClient, e: Ligne, pensionUid?: string | null): Promise<ClientPension> {
  let uid: string | null = null, pid: string | null = null;
  try {
    const { data: dem } = await sb.from('pension_demandes').select('client_uid, client_profile_id')
      .or(`entree_id.eq.${e.id},essai_entree_id.eq.${e.id}`).limit(1).maybeSingle();
    if (t((dem as Ligne | null)?.client_uid)) uid = t((dem as Ligne).client_uid);
    if (t((dem as Ligne | null)?.client_profile_id)) pid = t((dem as Ligne).client_profile_id);
  } catch { /* table absente */ }
  const animalId = t(e.animal_id);
  if (!uid && animalId) {
    const { data } = await sb.from('animaux_proprietes').select('uid_proprio, profile_id_proprio, role_proprio')
      .eq('animal_id', animalId).is('date_fin', null);
    const rows = ((data ?? []) as Ligne[]).filter(r => t(r.uid_proprio) !== t(pensionUid ?? e.pro_uid))
      .sort((a, b) => (a.role_proprio === 'principal' ? 0 : 1) - (b.role_proprio === 'principal' ? 0 : 1));
    if (rows[0]) { uid = t(rows[0].uid_proprio) || null; pid = t(rows[0].profile_id_proprio) || null; }
  }
  let prof: Ligne | null = null, compte: Ligne | null = null;
  if (pid) {
    const { data } = await sb.from('user_profiles_complet')
      .select('profile_type, nom, firstname, lastname, phone_number, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro')
      .eq('id', pid).maybeSingle();
    prof = data as Ligne | null;
  }
  if (uid) {
    const { data } = await sb.from('users_complet').select('firstname, lastname, email, phone_number, rue, code_postal, ville').eq('uid', uid).maybeSingle();
    compte = data as Ligne | null;
  }
  const type = t(prof?.profile_type);
  const estPro = !!type && type !== 'particulier';
  const contact = t(e.proprietaire_contact);
  const prenom = estPro ? '' : premier(prof?.firstname, compte?.firstname);
  let nom = estPro ? premier(prof?.nom) : premier(prof?.lastname, compte?.lastname);
  if (!prenom && !nom) nom = premier(e.proprietaire_nom, prof?.nom);
  const rue = estPro ? premier(prof?.rue_pro, prof?.rue) : premier(prof?.rue, compte?.rue);
  const cp = estPro ? premier(prof?.code_postal_pro, prof?.code_postal) : premier(prof?.code_postal, compte?.code_postal);
  const ville = estPro ? premier(prof?.ville_pro, prof?.ville) : premier(prof?.ville, compte?.ville);
  return {
    uid, profileId: pid, estPro, prenom, nom,
    email: premier(prof?.email_contact, e.proprietaire_email, contact.includes('@') ? contact : '', compte?.email),
    tel: premier(prof?.phone_number, contact.includes('@') ? '' : contact, compte?.phone_number),
    rue: !rue && !cp && !ville ? t(e.proprietaire_adresse) : rue, cp, ville,
  };
}
