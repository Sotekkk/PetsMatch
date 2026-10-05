import { supabase } from '@/lib/supabase';

export interface ContactAcquereur {
  prenom?: string;
  nom?: string;
  tel?: string;
  email?: string;
  adresse?: string;
}

export interface ContactAcquereurResult {
  contact: ContactAcquereur;
  /** true si l'acquéreur n'a pas (ou plus) de compte PetsMatch actif : les
   * coordonnées peuvent alors être corrigées à la main par l'éleveur. */
  editable: boolean;
}

/** Adresse complète d'un profil : `adresse` (souvent la rue seule, sinon
 * `rue`) + code postal + ville, sans répéter ce qu'elle contient déjà. */
export function adresseComplete(adresse: unknown, cp: unknown, ville: unknown, rue?: unknown): string {
  let r = (adresse ?? '').toString().trim();
  if (!r) r = (rue ?? '').toString().trim();
  const suite = [cp, ville].map(e => (e ?? '').toString().trim())
    .filter(e => e && !r.toLowerCase().includes(e.toLowerCase())).join(' ');
  return [r, suite].filter(Boolean).join(', ');
}

interface AnimalRef {
  id: string;
  uid_acquereur?: string | null;
  destinataire_nom?: string | null;
}

/**
 * Coordonnées de l'acquéreur d'un animal cédé + indique si elles sont
 * modifiables. Priorité : **profil particulier** PetsMatch de l'acquéreur (à
 * jour, qu'il maîtrise) → **saisie manuelle de l'éleveur**
 * (`animaux.acquereur_contact_manuel`, uniquement si pas de profil actif) →
 * contrat signé (`documents_animaux`) → ligne `cessions` (cessions faites
 * dans l'app) → réservation et certificat d'engagement (seules traces du
 * téléphone / email pour les cessions faites sur le site avant qu'elles
 * remplissent `acquereur_contact_manuel`) → `destinataire_nom` /
 * `destinataire_adresse` de secours. Même logique que l'app,
 * `lib/pages/eleveur/animaux/acquereur_contact.dart`.
 */
export async function fetchContactAcquereur(a: AnimalRef): Promise<ContactAcquereurResult> {
  const c: ContactAcquereur = {};
  const cpRe = /\b\d{5}\b/;
  const put = (k: keyof ContactAcquereur, v: unknown) => {
    const s = (v ?? '').toString().trim();
    if (!s) return;
    // Adresse : une source plus loin peut avoir l'adresse complète (code
    // postal + ville) alors que la première n'a que la rue → on la préfère.
    if (!c[k] || (k === 'adresse' && !cpRe.test(c[k]!) && cpRe.test(s))) c[k] = s;
  };

  let hasLiveProfile = false;
  if (a.uid_acquereur) {
    const { data: p } = await supabase.from('user_profiles_complet')
      .select('firstname, lastname, phone_number, email_contact, adresse, rue, code_postal, ville')
      .eq('uid', a.uid_acquereur).eq('profile_type', 'particulier').maybeSingle();
    if (p) {
      hasLiveProfile = true;
      put('prenom', p.firstname); put('nom', p.lastname);
      put('tel', p.phone_number); put('email', p.email_contact);
      put('adresse', adresseComplete(p.adresse, p.code_postal, p.ville, p.rue));
    }
  }

  // Pas de compte PetsMatch actif derrière l'acquéreur → priorité à la
  // correction manuelle de l'éleveur (info reçue par tél./mail hors appli).
  if (!hasLiveProfile) {
    const { data: row } = await supabase.from('animaux')
      .select('acquereur_contact_manuel').eq('id', a.id).maybeSingle();
    const manuel = row?.acquereur_contact_manuel as ContactAcquereur | null;
    if (manuel) {
      put('prenom', manuel.prenom); put('nom', manuel.nom);
      put('tel', manuel.tel); put('email', manuel.email); put('adresse', manuel.adresse);
    }
  }

  const { data: doc } = await supabase.from('documents_animaux')
    .select('metadata')
    .eq('animal_id', a.id)
    .in('type', ['contrat_vente', 'certificat_cession'])
    .order('created_at', { ascending: false })
    .limit(1).maybeSingle();
  const m = (doc?.metadata ?? {}) as Record<string, unknown>;
  put('prenom', m.acquereur_prenom);
  put('nom', m.acquereur_nom_famille ?? m.acquereur_nom);
  put('tel', m.acquereur_tel);
  put('email', m.acquereur_email);
  put('adresse', [m.acquereur_adresse, [m.acquereur_cp, m.acquereur_ville].filter(Boolean).join(' ')]
    .filter((x) => x && String(x).trim()).join(', '));

  const { data: cs } = await supabase.from('cessions')
    .select('prenom_acquereur, nom_acquereur, tel_acquereur, email_acquereur, adresse_acquereur')
    .eq('animal_id', a.id).order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (cs) {
    put('prenom', cs.prenom_acquereur); put('nom', cs.nom_acquereur);
    put('tel', cs.tel_acquereur); put('email', cs.email_acquereur); put('adresse', cs.adresse_acquereur);
  }

  const { data: resa } = await supabase.from('reservations_animaux')
    .select('*')
    .eq('animal_id', a.id).neq('statut', 'annulee')
    .order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (resa) {
    // Ancien format : `nom` = nom complet, à ne reprendre que s'il est
    // accompagné d'un prénom séparé (sinon « Prénom Prénom Nom » à l'affichage).
    if ((resa.prenom ?? '').trim()) { put('prenom', resa.prenom); put('nom', resa.nom); }
    put('tel', resa.tel); put('email', resa.email); put('adresse', resa.adresse);
  }

  const { data: cert } = await supabase.from('certificats_engagement')
    .select('acquereur_prenom, acquereur_nom, acquereur_telephone, acquereur_email, acquereur_adresse')
    .eq('animal_id', a.id).order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (cert) {
    put('prenom', cert.acquereur_prenom); put('nom', cert.acquereur_nom);
    put('tel', cert.acquereur_telephone); put('email', cert.acquereur_email); put('adresse', cert.acquereur_adresse);
  }

  put('nom', a.destinataire_nom);
  if (!c.adresse || !cpRe.test(c.adresse)) {
    const { data: an } = await supabase.from('animaux')
      .select('destinataire_adresse').eq('id', a.id).maybeSingle();
    put('adresse', an?.destinataire_adresse);
  }

  // Les cessions de l'app stockent le nom complet dans `nom_acquereur` :
  // évite « Leslie Leslie de Mesquita » quand le prénom vient d'ailleurs.
  const pre = (c.prenom ?? '').toLowerCase();
  if (pre && c.nom && c.nom.toLowerCase().startsWith(pre + ' ')) c.nom = c.nom.slice(pre.length).trim();

  return { contact: c, editable: !hasLiveProfile };
}

/** Enregistre la correction manuelle de l'éleveur (pertinent seulement quand
 * l'acquéreur n'a pas de compte PetsMatch actif). */
export async function saveContactAcquereurManuel(animalId: string, data: ContactAcquereur) {
  await supabase.from('animaux').update({ acquereur_contact_manuel: data }).eq('id', animalId);
}

/** Téléphone au format international sans « + » pour wa.me (France par défaut). */
export function waPhone(raw: string): string {
  let d = raw.replace(/[^0-9]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('0')) d = '33' + d.slice(1);
  return d;
}
