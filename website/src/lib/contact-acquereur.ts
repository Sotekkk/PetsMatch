import { supabase } from '@/lib/supabase';

export interface ContactAcquereur {
  prenom?: string;
  nom?: string;
  tel?: string;
  email?: string;
  adresse?: string;
}

interface AnimalRef {
  id: string;
  uid_acquereur?: string | null;
  destinataire_nom?: string | null;
}

/**
 * Coordonnées de l'acquéreur d'un animal cédé. Priorité : **profil
 * particulier** PetsMatch de l'acquéreur (à jour, qu'il maîtrise) → contrat
 * signé (`documents_animaux`) → ligne `cessions` → `destinataire_nom` de
 * secours. Factorisé depuis `SuiviCessionsTab` (même logique que l'app,
 * `lib/pages/eleveur/animaux/acquereur_contact.dart`).
 */
export async function fetchContactAcquereur(a: AnimalRef): Promise<ContactAcquereur> {
  const c: ContactAcquereur = {};
  const put = (k: keyof ContactAcquereur, v: unknown) => {
    const s = (v ?? '').toString().trim();
    if (s && !c[k]) c[k] = s;
  };

  if (a.uid_acquereur) {
    const { data: p } = await supabase.from('user_profiles')
      .select('firstname, lastname, phone_number, email_contact, adresse, rue, code_postal, ville')
      .eq('uid', a.uid_acquereur).eq('profile_type', 'particulier').maybeSingle();
    if (p) {
      put('prenom', p.firstname); put('nom', p.lastname);
      put('tel', p.phone_number); put('email', p.email_contact);
      put('adresse', p.adresse ?? [p.rue, p.code_postal, p.ville].filter(Boolean).join(' '));
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

  return c;
}

/** Téléphone au format international sans « + » pour wa.me (France par défaut). */
export function waPhone(raw: string): string {
  let d = raw.replace(/[^0-9]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('0')) d = '33' + d.slice(1);
  return d;
}
