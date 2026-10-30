// Fin de consultation (vétérinaire) : compte(s) rendu(s), ordonnance(s) et
// facture d'un RDV, envoyés au propriétaire en un seul e-mail, facture
// éventuellement marquée acquittée. Miroir appli : _terminerConsultation
// (lib/pages/pro/compte_rendu_page.dart).
import { supabase } from '@/lib/supabase';
import { compteRenduPdfBlob, ageAnimal, sexeAnimal } from '@/lib/ordonnance-pdf';
import { facturePdfBlob } from '@/lib/facture-pdf';
import { pdfDepuisUrl } from '@/lib/transmission-document';

export interface CrConsultation { id: string; animal_id: string; contenu: string | null; created_at: string }
export interface OrdoConsultation { id: string; animal_id: string; doc_url: string | null; created_at: string }
export type FactureConsultation = Record<string, unknown> & { id: string; statut?: string | null; numero_affichage?: string | null };

export interface DocsConsultation {
  rdvId: string; animalIdPrincipal: string | null; noms: Record<string, string>;
  crs: CrConsultation[]; ordos: OrdoConsultation[]; facture: FactureConsultation | null;
}

export async function chargerDocsConsultation(rdvId: string): Promise<DocsConsultation> {
  const [{ data: r }, { data: crs }, { data: ordos }, { data: fac }] = await Promise.all([
    supabase.from('rdv').select('animal_id, date_heure, pro_profile_id').eq('id', rdvId).maybeSingle(),
    supabase.from('comptes_rendus').select('id, animal_id, contenu, created_at, statut').eq('rdv_id', rdvId).eq('statut', 'valide').order('created_at'),
    supabase.from('ordonnances').select('id, animal_id, doc_url, created_at').eq('rdv_id', rdvId).order('created_at'),
    supabase.from('factures').select('*').eq('source_rdv_id', rdvId).neq('statut', 'annulee').order('created_at', { ascending: false }).limit(1),
  ]);
  // CR / ordonnance faits depuis la fiche (sans lien au RDV) : ceux de l'animal
  // du RDV, par ce profil, le jour du RDV ; facture de l'animal ce jour-là.
  let crsR = (crs ?? []) as CrConsultation[], ordosR = (ordos ?? []) as OrdoConsultation[], facR = (fac ?? []) as FactureConsultation[];
  const rr = r as { animal_id?: unknown; date_heure?: string; pro_profile_id?: string | null } | null;
  if (rr?.animal_id != null && rr.date_heure && rr.pro_profile_id && (!crsR.length || !ordosR.length || !facR.length)) {
    const j = new Date(rr.date_heure); const debut = new Date(j.getFullYear(), j.getMonth(), j.getDate());
    const fin = new Date(debut.getTime() + 86400000);
    const aid = String(rr.animal_id);
    const [c2, o2, f2] = await Promise.all([
      crsR.length ? null : supabase.from('comptes_rendus').select('id, animal_id, contenu, created_at, statut').eq('animal_id', aid)
        .eq('pro_profile_id', rr.pro_profile_id).eq('statut', 'valide').gte('created_at', debut.toISOString()).lt('created_at', fin.toISOString()).order('created_at'),
      ordosR.length ? null : supabase.from('ordonnances').select('id, animal_id, doc_url, created_at').eq('animal_id', aid)
        .eq('pro_profile_id', rr.pro_profile_id).gte('created_at', debut.toISOString()).lt('created_at', fin.toISOString()).order('created_at'),
      facR.length ? null : supabase.from('factures').select('*').eq('source_animal_id', aid).eq('profile_id', rr.pro_profile_id)
        .neq('statut', 'annulee').gte('created_at', debut.toISOString()).order('created_at', { ascending: false }).limit(1),
    ]);
    if (c2) crsR = (c2.data ?? []) as CrConsultation[];
    if (o2) ordosR = (o2.data ?? []) as OrdoConsultation[];
    if (f2) facR = (f2.data ?? []) as FactureConsultation[];
  }
  const ids = [...new Set([...crsR, ...ordosR].map(x => String((x as { animal_id: unknown }).animal_id)))];
  const { data: an } = ids.length ? await supabase.from('animaux').select('id, nom').in('id', ids) : { data: [] };
  return {
    rdvId,
    animalIdPrincipal: (r as { animal_id?: unknown } | null)?.animal_id != null ? String((r as { animal_id: unknown }).animal_id) : null,
    noms: Object.fromEntries(((an ?? []) as { id: string; nom: string }[]).map(a => [String(a.id), a.nom])),
    crs: crsR.map(c => ({ ...c, animal_id: String(c.animal_id) })),
    ordos: ordosR.map(o => ({ ...o, animal_id: String(o.animal_id) })),
    facture: facR[0] ?? null,
  };
}

/** PDF d'un compte rendu (en-tête du profil, patient, propriétaire, signature). */
export async function pdfCompteRendu(cr: CrConsultation, o: {
  proProfileId: string | null; praticien: string; signature?: string | null; emailCompte?: string | null;
  /** Nom du client du RDV, en dernier recours. */
  proprietaire?: string | null;
  /** Autres métiers : présentation du PDF (cf. CompteRenduData). */
  titre?: string; prefixePraticien?: string; libelleAnimal?: string; nomParDefaut?: string;
}) {
  const v = (x: unknown) => String(x ?? '').trim();
  const [{ data: cl }, { data: an }] = await Promise.all([
    o.proProfileId
      ? supabase.from('user_profiles_complet')
        .select('nom, firstname, lastname, rue_pro, code_postal_pro, ville_pro, rue, code_postal, ville, phone_number, phone, telephone, email_contact')
        .eq('id', o.proProfileId).maybeSingle()
      : Promise.resolve({ data: null }),
    supabase.from('animaux').select('nom, espece, race, sexe, date_naissance, age_estime, identification, client_clinique_id, uid_proprietaire').eq('id', cr.animal_id).maybeSingle(),
  ]);
  const c = (cl ?? {}) as Record<string, unknown>;
  const a = (an ?? {}) as Record<string, unknown>;
  let proprio = '';
  if (a.client_clinique_id) {
    const { data: cc } = await supabase.from('clients_clinique').select('nom, prenom').eq('id', a.client_clinique_id as string).maybeSingle();
    proprio = `${v(cc?.prenom)} ${v(cc?.nom)}`.trim();
  } else {
    // Nom et prénom du propriétaire : colonnes privées du profil, lues par la
    // même fonction que la facture (le pro y a droit pour son patient).
    const { data: cf } = await supabase.rpc('pm_client_facturation', { p_animal_id: cr.animal_id });
    const j = (cf ?? null) as Record<string, string> | null;
    proprio = `${v(j?.prenom)} ${v(j?.nom)}`.trim();
    if (!proprio && a.uid_proprietaire) {
      const { data: u } = await supabase.from('users_complet').select('firstname, lastname').eq('uid', a.uid_proprietaire as string).maybeSingle();
      proprio = `${v(u?.firstname)} ${v(u?.lastname)}`.trim();
    }
  }
  if (!proprio) proprio = v(o.proprietaire);
  return compteRenduPdfBlob({
    cliniqueNom: v(c.nom) || (o.nomParDefaut ?? 'Cabinet vétérinaire'),
    cliniqueAdresse: (v(c.rue_pro) || v(c.ville_pro)
      ? [c.rue_pro, `${v(c.code_postal_pro)} ${v(c.ville_pro)}`.trim()] : [c.rue, `${v(c.code_postal)} ${v(c.ville)}`.trim()])
      .filter(x => v(x)).join(', '),
    cliniqueTel: v(c.phone_number) || v(c.phone) || v(c.telephone),
    cliniqueEmail: v(c.email_contact) || v(o.emailCompte),
    praticien: `${v(c.firstname)} ${v(c.lastname)}`.trim() || o.praticien,
    animalNom: v(a.nom) || 'Animal', animalEspeceRace: [a.espece, a.race].filter(x => v(x)).join(' · '),
    animalSexe: sexeAnimal(a.sexe as string | null), animalAge: ageAnimal(a.date_naissance as string | null, a.age_estime as string | null),
    animalIdentification: v(a.identification), proprietaire: proprio,
    contenu: cr.contenu ?? '', date: new Date(cr.created_at), signature: o.signature,
    titre: o.titre, prefixePraticien: o.prefixePraticien, libelleAnimal: o.libelleAnimal,
  });
}

export async function pdfOrdonnance(o: OrdoConsultation) {
  if (!o.doc_url) throw new Error('Ordonnance sans PDF');
  return pdfDepuisUrl(o.doc_url);
}

/** PDF de la facture (mention « ACQUITTÉE » si réglée). */
export async function pdfFacture(f: FactureConsultation) {
  const t = (k: string) => (f[k] as string | null | undefined) ?? null;
  const n = (k: string) => Number(f[k] ?? 0);
  const lignes = ((f.lignes ?? []) as Record<string, unknown>[]).map(l => ({
    designation: String(l.designation ?? l.description ?? ''), description: '',
    quantite: Number(l.quantite ?? 1),
    prixUnitaireHT: Number(l.prixUnitaireHT ?? l.prixHT ?? l.prixUnitaire ?? 0),
    tauxTVA: Number(l.tauxTVA ?? l.tva ?? 0),
  }));
  return facturePdfBlob({
    numero: t('numero_affichage') ?? String(f.numero_facture ?? ''), typeFacture: t('type_facture'),
    dateFacture: t('date_facture'), datePrestation: t('date_prestation'), dateEcheance: t('date_echeance'),
    nomEmetteur: t('nom_emetteur'), rueEmetteur: t('rue_emetteur'), cpEmetteur: t('cp_emetteur'), villeEmetteur: t('ville_emetteur'),
    paysEmetteur: t('pays_emetteur'), telEmetteur: t('tel_emetteur'), emailEmetteur: t('email_emetteur'), siretEmetteur: t('siret_emetteur'),
    tvaEmetteur: t('tva_emetteur'), formeJuridiqueEmetteur: t('forme_juridique_emetteur'), capitalEmetteur: t('capital_emetteur'),
    rcsEmetteur: t('rcs_emetteur'), rmEmetteur: t('rm_emetteur'),
    prenomClient: t('prenom_client'), nomClient: t('nom_client'), rueClient: t('rue_client'), cpClient: t('cp_client'),
    villeClient: t('ville_client'), paysClient: t('pays_client'), emailClient: t('email_client'),
    lignes, totalHT: n('total_ht'), totalTVA: n('total_tva'), totalTTC: n('total_ttc'),
    franchise: t('regime_tva') === 'franchise', modePaiement: t('mode_paiement'), delaiPaiement: t('delai_paiement'),
    noteComplementaire: t('note_complementaire'),
    acquittee: f.statut === 'payee' ? { date: t('date_paiement'), mode: t('mode_paiement') } : null,
  });
}
