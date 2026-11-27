// Contrat d'hébergement (pension) signé en PDF, à envoyer au client par
// e-mail (avec ou sans compte). Même contenu que /signer-contrat
// (generateContratHebergementHTML, photographie du contrat dans metadata),
// signatures incluses. Miroir appli : contratPensionPdfBytes (contrat_pdf.dart).
import { supabase } from '@/lib/supabase';
import { generateContratHebergementHTML } from '@/lib/contrat-pension';
import { pdfDepuisHtmlContrat } from '@/lib/contrat-garde-pdf';

/** PDF du contrat de pension (signé), ou null si le document est introuvable. */
export async function pdfContratPensionSigne(docId: string): Promise<Blob | null> {
  const { data: doc } = await supabase.from('documents_animaux')
    .select('id, metadata, pension_entree_id, pro_profile_id, uid_eleveur, signe_le').eq('id', docId).maybeSingle();
  if (!doc) return null;
  const meta = (doc.metadata ?? {}) as Record<string, unknown>;
  const s = (k: string) => { const v = meta[k]; return v == null || v === '' ? undefined : String(v); };
  const n = (k: string) => { const v = Number(meta[k]); return Number.isFinite(v) && v > 0 ? v : undefined; };
  const v = (x: unknown) => String(x ?? '').trim();
  const [{ data: entree }, { data: pro }] = await Promise.all([
    doc.pension_entree_id
      ? supabase.from('pension_entrees').select('animal_nom, espece, race, proprietaire_nom, proprietaire_contact, date_entree, date_sortie_prevue')
        .eq('id', doc.pension_entree_id).maybeSingle()
      : Promise.resolve({ data: null }),
    doc.pro_profile_id
      ? supabase.from('user_profiles_complet').select('nom, firstname, lastname, rue_pro, code_postal_pro, ville_pro, rue, code_postal, ville, adresse, phone_number, phone, telephone, numero_elevage, email_contact, siret')
        .eq('id', doc.pro_profile_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  const e = (entree ?? {}) as Record<string, string | null>;
  const p = (pro ?? {}) as Record<string, string | null>;
  const adresse = (v(p.rue_pro) || v(p.ville_pro)
    ? [p.rue_pro, [p.code_postal_pro, p.ville_pro].map(v).filter(Boolean).join(' ')]
    : [v(p.adresse) || p.rue, v(p.adresse) ? '' : [p.code_postal, p.ville].map(v).filter(Boolean).join(' ')])
    .map(v).filter(Boolean).join(', ');
  const groupe = !!meta.entree_ids;
  let html = generateContratHebergementHTML(
    {
      animal_nom: s('animal_nom') ?? v(e.animal_nom),
      espece: s('espece') ?? (groupe ? undefined : v(e.espece) || undefined),
      race: s('race') ?? (groupe ? undefined : v(e.race) || undefined),
      proprietaire_nom: s('client_nom') ?? (v(e.proprietaire_nom) || undefined),
      proprietaire_contact: v(e.proprietaire_contact) || undefined,
      date_entree: s('date_entree') ?? (v(e.date_entree) || undefined),
      date_sortie_prevue: s('date_sortie_prevue') ?? (v(e.date_sortie_prevue) || undefined),
    },
    {
      nom: v(p.nom) || `${v(p.firstname)} ${v(p.lastname)}`.trim() || 'La Pension',
      adresse, email: v(p.email_contact), siret: v(p.siret),
      tel: v(p.numero_elevage) ? `+33 ${v(p.numero_elevage)}` : v(p.phone_number) || v(p.phone) || v(p.telephone),
    },
    {
      tarifNuit: s('tarif_nuit'), arrhesPourcentage: n('arrhes_pourcentage'), logementNom: s('logement_nom'), notes: s('notes'),
      nbNuits: n('nb_nuits'), reductionPct: n('reduction_pct'), prixTotal: n('prix_total'),
      clientEmail: s('client_email'), clientTel: s('client_tel'), clientAdresse: s('client_adresse'), puce: s('puce'),
      arrhesMontant: n('arrhes_montant'), soldeMoment: s('solde_moment'),
    },
  );
  // Signatures (images) dans les blocs, comme sur la page du contrat.
  const sig = (role: string, src?: string) => {
    if (!src?.startsWith('data:image')) return;
    html = html.replace(new RegExp(`(<div class="sign-block" data-signer="${role}">[\\s\\S]*?<div class="sign-img">)(</div>)`),
      `$1<img src="${src}" alt="">$2`);
  };
  sig('vendeur', s('signature_eleveur'));
  sig('acheteur', s('signature_acquereur'));
  // Date de signature (pas la date du jour).
  if (doc.signe_le) html = html.replace(/Fait le [0-9/]+/, `Fait le ${new Date(doc.signe_le).toLocaleDateString('fr-FR')}`);
  return pdfDepuisHtmlContrat(html);
}
