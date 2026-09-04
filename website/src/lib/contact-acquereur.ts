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
 * contrat signé (`documents_animaux`) → ligne `cessions` → `destinataire_nom`
 * de secours. Même logique que l'app,
 * `lib/pages/eleveur/animaux/acquereur_contact.dart`.
 */
export async function fetchContactAcquereur(a: AnimalRef): Promise<ContactAcquereurResult> {
  const c: ContactAcquereur = {};
  const put = (k: keyof ContactAcquereur, v: unknown) => {
    const s = (v ?? '').toString().trim();
    if (s && !c[k]) c[k] = s;
  };

  let hasLiveProfile = false;
  if (a.uid_acquereur) {
    const { data: p } = await supabase.from('user_profiles')
      .select('firstname, lastname, phone_number, email_contact, adresse, rue, code_postal, ville')
      .eq('uid', a.uid_acquereur).eq('profile_type', 'particulier').maybeSingle();
    if (p) {
      hasLiveProfile = true;
      put('prenom', p.firstname); put('nom', p.lastname);
      put('tel', p.phone_number); put('email', p.email_contact);
      put('adresse', p.adresse ?? [p.rue, p.code_postal, p.ville].filter(Boolean).join(' '));
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
  put('nom', a.destinataire_nom);

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
