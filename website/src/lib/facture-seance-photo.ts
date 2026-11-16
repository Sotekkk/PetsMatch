// Photographe — « Facturer la sélection » depuis la galerie (16/11/2026) :
// facture préremplie d'après la séance (forfait de la prestation + photos
// supplémentaires choisies au-delà des photos incluses − acompte déjà réglé),
// coordonnées du client reprises de son profil. La facture est envoyée au
// client par e-mail (PDF) à sa création (/elevage/facturation). Même calcul
// que le dossier de la séance (DossierSeanceModal.facturer).
// Miroir appli : lib/utils/facture_seance_photo.dart.
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { pdfFacture, type FactureConsultation } from '@/lib/fin-consultation';

/** Prépare le préremplissage (sessionStorage pm_facture_prefill). Renvoie un
 *  message d'erreur, ou null : l'appelant ouvre alors /elevage/facturation. */
export async function preparerFactureSelectionPhoto(albumId: string, retour: string): Promise<string | null> {
  const { data: alb } = await supabase.from('albums_photo').select('id, rdv_id, nb_photos_incluses, prix_photo_supp, client_email').eq('id', albumId).maybeSingle();
  const album = alb as { id: string; rdv_id: string | null; nb_photos_incluses: number | null; prix_photo_supp: number | null; client_email: string | null } | null;
  if (!album?.rdv_id) return 'Galerie non rattachée à une séance : créez la facture depuis la Facturation.';
  const { data: rr } = await supabase.from('rdv')
    .select('id, date_heure, prestation_id, motif, animal_id, animal_nom_manuel, client_uid, client_profile_id, client_nom_manuel, client_telephone_manuel, client_email_manuel, lieu_type, adresse_depart')
    .eq('id', album.rdv_id).maybeSingle();
  const r = rr as Record<string, string | null> | null;
  if (!r) return 'Séance introuvable.';

  const v = (...x: (string | null | undefined)[]) => x.map(y => (y ?? '').trim()).find(Boolean) ?? '';
  const [{ data: prof }, { data: pres }, { data: ph }, { data: acomptes }] = await Promise.all([
    r.client_profile_id
      ? supabase.from('user_profiles_complet').select('firstname, lastname, nom, phone_number, phone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro')
        .eq('id', r.client_profile_id).maybeSingle()
      : Promise.resolve({ data: null }),
    r.prestation_id ? supabase.from('prestations_photographe').select('nom, prix').eq('id', r.prestation_id).maybeSingle() : Promise.resolve({ data: null }),
    supabase.from('album_photos').select('selectionnee').eq('album_id', albumId),
    supabase.from('factures').select('total_ttc, numero_affichage, numero_facture')
      .eq('source_rdv_id', album.rdv_id).eq('type_facture', 'acompte').eq('statut', 'payee'),
  ]);
  const p = prof as Record<string, string | null> | null;
  const presta = pres as { nom?: string | null; prix?: number | null } | null;
  const nbChoisies = ((ph ?? []) as { selectionnee: boolean | null }[]).filter(x => x.selectionnee).length;
  const supp = album.nb_photos_incluses != null && album.prix_photo_supp ? Math.max(0, nbChoisies - album.nb_photos_incluses) : 0;
  const animaux = (r.animal_nom_manuel ?? '').split('+').map(x => x.trim()).filter(Boolean).join(', ');
  const jour = r.date_heure ? new Date(r.date_heure).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' }) : '';
  const designation = `${[v(presta?.nom, r.motif, 'Séance photo'), animaux].filter(Boolean).join(' — ')}${jour ? ` — séance du ${jour}` : ''}`;
  const deductions = ((acomptes ?? []) as { total_ttc: number | null; numero_affichage?: string | null; numero_facture?: string | number | null }[])
    .filter(a => Number(a.total_ttc) > 0)
    .map(a => ({ description: `Acompte déjà réglé (facture n° ${a.numero_affichage ?? a.numero_facture ?? ''})`, quantite: 1, prixUnitaire: 0, prixTTC: -Number(a.total_ttc), tva: 20 }));
  try {
    // Tarifs affichés TTC : le HT est déduit selon le régime de TVA du pro.
    sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
      nomClient: v(p?.lastname, r.client_nom_manuel, p?.nom) || undefined, prenomClient: v(p?.firstname) || undefined,
      emailClient: v(p?.email_contact, r.client_email_manuel, album.client_email) || undefined, telClient: v(p?.phone_number, p?.phone, r.client_telephone_manuel) || undefined,
      rueClient: v(p?.rue, p?.rue_pro, r.lieu_type === 'domicile' ? r.adresse_depart : null) || undefined,
      cpClient: v(p?.code_postal, p?.code_postal_pro) || undefined, villeClient: v(p?.ville, p?.ville_pro) || undefined,
      sourceRdvId: r.id, sourceAnimalId: r.animal_id ?? undefined, retour,
      clientUid: r.client_uid ?? undefined, clientProfileId: r.client_profile_id ?? undefined,
      lignes: [
        { description: designation, quantite: 1, prixUnitaire: 0, prixTTC: Number(presta?.prix) || 0, tva: 20 },
        ...(supp > 0 ? [{ description: 'Photos supplémentaires', quantite: supp, prixUnitaire: 0, prixTTC: Number(album.prix_photo_supp), tva: 20 }] : []),
        ...deductions,
      ],
    }));
  } catch { return 'Préremplissage impossible : créez la facture depuis la Facturation.'; }
  return null;
}

async function enBase64(blob: Blob): Promise<string> {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(bin);
}

/** Facture marquée payée : PDF acquitté envoyé au client par e-mail (avec ou
 *  sans compte PetsMatch), à l'adresse de la facture. Renvoie le message à
 *  afficher. Miroir appli : envoyerFactureAcquitteePhoto. */
export async function envoyerFactureAcquittee(factureId: string): Promise<string> {
  try {
    const { data } = await supabase.from('factures').select('*').eq('id', factureId).maybeSingle();
    const f = data as FactureConsultation | null;
    if (!f) return 'Paiement enregistré.';
    const email = String(f.email_client ?? '').trim();
    if (!email) return 'Paiement enregistré. Pas d\'adresse e-mail sur la facture : la facture acquittée n\'a pas été envoyée.';
    const n = f.numero_affichage ?? String((f as { numero_facture?: unknown }).numero_facture ?? '');
    const res = await apiFetch('/api/documents/envoyer-email', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email, contexte: 'photo', document_type: 'facture', fichier_nom: `Facture-${n}-acquittee.pdf`,
        destinataire_nom: `${String(f.prenom_client ?? '')} ${String(f.nom_client ?? '')}`.trim() || undefined,
        expediteur_nom: String(f.nom_emetteur ?? '').trim() || undefined,
        pdf_base64: await enBase64(await pdfFacture({ ...f, statut: 'payee' })),
      }),
    });
    return res.ok ? `Paiement enregistré : facture acquittée envoyée à ${email}.`
      : 'Paiement enregistré, mais l\'envoi de la facture acquittée a échoué : renvoyez-la depuis la Facturation.';
  } catch {
    return 'Paiement enregistré, mais l\'envoi de la facture acquittée a échoué : renvoyez-la depuis la Facturation.';
  }
}
