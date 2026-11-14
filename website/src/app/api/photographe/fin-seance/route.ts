import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/server-auth';
import { admin, chargerAlbum, estGestionnaire, estPremium, nomStudio, lienClientAlbum, emailClientAlbum, nomClientAlbum, type AlbumRow } from '@/lib/galeries-server';
import { SITE_URL, echapperHtml, emailValide, gabaritEmail, envoyerEmail } from '@/lib/email-petsmatch';
import { texteTarifs } from '@/lib/tarifs-photo';

// Photographe — « Fin de séance » (14/11/2026), comme la fin de consultation du
// vétérinaire : UN e-mail juste après le shooting avec, au choix,
//  • le lien de la galerie pour vérifier et choisir ses photos (la galerie est
//    partagée, Premium : compte PetsMatch → /galerie/<id>, sinon lien privé 30 jours) ;
//  • le contrat (lien : à signer, ou à consulter s'il est signé) ;
//  • le rappel des tarifs : forfait (prix minimum), photos incluses, prix d'une
//    photo supplémentaire — pas de montant total ni de facture : la facture se
//    fait une fois la sélection confirmée.
// La livraison des photos retouchées reste un envoi à part (plus tard).
// Miroir appli : _finSeance (lib/pages/pro/photographe_dossier_seance.dart).
const JOURS_LIEN = 30;
const TYPES_CONTRAT = ['contrat_prestation_photo', 'contrat_document_pro'];

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const body = await req.json().catch(() => null) as {
    rdvId?: string; email?: string; galerie?: boolean; contrat?: boolean; tarifs?: boolean; message?: string;
  } | null;
  if (!body?.rdvId || !/^[0-9a-f-]{36}$/i.test(body.rdvId)) return NextResponse.json({ error: 'Rendez-vous manquant' }, { status: 400 });

  const { data: rdvRow } = await admin.from('rdv')
    .select('id, pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, motif, prestation_id').eq('id', body.rdvId).maybeSingle();
  const rdv = rdvRow as { id: string; pro_uid: string; pro_profile_id: string | null; client_uid: string | null; client_profile_id: string | null; date_heure: string; motif: string | null; prestation_id: string | null } | null;
  if (!rdv) return NextResponse.json({ error: 'Rendez-vous introuvable' }, { status: 404 });
  // Le photographe du rendez-vous, ou un cogérant actif de son compte.
  const pseudoAlbum = { pro_uid: rdv.pro_uid } as AlbumRow;
  if (!(await estGestionnaire(pseudoAlbum, auth.uid))) return NextResponse.json({ error: 'Réservé au photographe de la séance' }, { status: 403 });

  const { data: albRow } = await admin.from('albums_photo').select('id').eq('rdv_id', rdv.id).limit(1).maybeSingle();
  const album = albRow ? await chargerAlbum((albRow as { id: string }).id) : null;

  // Adresse : saisie dans la fenêtre, sinon celle de la galerie / du client.
  let email = (body.email ?? '').trim();
  if (!email && album) email = (await emailClientAlbum(album)) ?? '';
  if (!email && rdv.client_uid) {
    const { data } = await admin.from('users').select('email').eq('uid', rdv.client_uid).maybeSingle();
    email = (data as { email?: string | null } | null)?.email?.trim() ?? '';
  }
  if (!emailValide(email)) return NextResponse.json({ error: 'Adresse e-mail du client inconnue ou invalide', code: 'sans_email' }, { status: 400 });

  const maintenant = new Date().toISOString();
  const elements: string[] = [];
  let bouton: { label: string; url: string } | undefined;
  let consigneGalerie: string | null = null;

  // ── Galerie ──
  if (body.galerie) {
    if (!album) return NextResponse.json({ error: 'Créez d\'abord la galerie de la séance.' }, { status: 400 });
    if (!(await estPremium(album.pro_uid))) return NextResponse.json({ error: 'Le partage de galerie est réservé à la formule Premium : décochez la galerie.' }, { status: 402 });
    const { count } = await admin.from('album_photos').select('id', { count: 'exact', head: true }).eq('album_id', album.id);
    if (!count) return NextResponse.json({ error: 'Ajoutez des photos à la galerie avant de l\'envoyer (ou décochez-la).' }, { status: 400 });
    const compte = !!album.client_uid;
    await admin.from('albums_photo').update({
      client_email: email, updated_at: maintenant,
      ...(compte ? { partage_client: true } : {}),
      ...(album.statut === 'brouillon' || !album.statut ? { statut: 'partagee', partagee_le: maintenant } : {}),
    }).eq('id', album.id);
    const url = compte
      ? `${SITE_URL}/galerie/${album.id}`
      : `${SITE_URL}/album/${await lienClientAlbum(album.id, new Date(Date.now() + JOURS_LIEN * 86400000))}`;
    bouton = { label: 'Voir ma galerie et choisir mes photos', url };
    elements.push(`la galerie de votre séance (${count} photo${count > 1 ? 's' : ''}), à vérifier : bouton ci-dessous${compte ? '' : ` — lien personnel valable ${JOURS_LIEN} jours`}`);
    consigneGalerie = 'Dans la galerie, touchez le cœur sur vos photos préférées, cochez celles que vous souhaitez recevoir, puis confirmez votre sélection. Les aperçus sont en qualité réduite : les fichiers définitifs vous seront remis après la retouche.';
    if (compte && !album.partage_client) {
      await admin.from('notifications').insert({
        uid: album.client_uid, type: 'galerie_disponible', title: 'Votre galerie photo est disponible',
        body: `${(await nomStudio(album)).nom || 'Votre photographe'} a partagé la galerie « ${album.titre ?? 'Séance photo'} ».`,
        ...(album.client_profile_id ? { profile_id: album.client_profile_id } : {}), data: { albumId: album.id }, read: false,
      });
    }
  }

  // ── Contrat (lien) ──
  if (body.contrat) {
    const { data } = await admin.from('documents_animaux').select('token, statut').eq('rdv_id', rdv.id).in('type', TYPES_CONTRAT)
      .not('statut', 'in', '(annule,refuse)').order('created_at', { ascending: false }).limit(1).maybeSingle();
    const c = data as { token?: string | null; statut?: string } | null;
    if (c?.token) {
      const url = `${SITE_URL}/signer-contrat/${c.token}`;
      elements.push(c.statut === 'signe'
        ? `le contrat de prestation signé : <a href="${url}" style="color:#0C5C6C;font-weight:600;">le consulter</a>`
        : `le contrat de prestation, à signer : <a href="${url}" style="color:#0C5C6C;font-weight:600;">vérifier et signer</a>`);
    }
  }

  if (elements.length === 0) return NextResponse.json({ error: 'Rien à envoyer' }, { status: 400 });

  // ── Rappel des tarifs (valeurs figées sur la galerie, sinon la prestation) ──
  let tarifs: string | null = null;
  if (body.tarifs) {
    type Presta = { prix?: number | null; nb_photos?: number | null; prix_photo_supp?: number | null };
    const p: Presta | null = rdv.prestation_id
      ? (await admin.from('prestations_photographe').select('prix, nb_photos, prix_photo_supp').eq('id', rdv.prestation_id).maybeSingle()).data as Presta | null
      : null;
    tarifs = texteTarifs({
      forfait: p?.prix != null ? Number(p.prix) : null,
      incluses: album?.nb_photos_incluses ?? p?.nb_photos ?? null,
      prixPhoto: album?.prix_photo_supp != null ? Number(album.prix_photo_supp) : p?.prix_photo_supp != null ? Number(p.prix_photo_supp) : null,
    });
  }

  const studio = album ? (await nomStudio(album)).nom : '';
  let pro = studio;
  if (!pro && rdv.pro_profile_id) {
    const { data } = await admin.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', rdv.pro_profile_id).maybeSingle();
    const p = data as { nom?: string | null; firstname?: string | null; lastname?: string | null } | null;
    pro = (p?.nom ?? '').trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim();
  }
  pro = pro || 'Votre photographe';
  let client = album ? await nomClientAlbum(album) : '';
  if (!client && rdv.client_profile_id) {
    const { data } = await admin.from('user_profiles_complet').select('firstname, lastname').eq('id', rdv.client_profile_id).maybeSingle();
    const p = data as { firstname?: string | null; lastname?: string | null } | null;
    client = `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim();
  }
  const jour = new Date(rdv.date_heure).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Paris' });
  const message = (body.message ?? '').trim().slice(0, 1500);
  const tarifsTexte = tarifs ? tarifs.charAt(0).toUpperCase() + tarifs.slice(1) : null;

  try {
    await envoyerEmail(email, `Votre séance photo du ${jour} (${pro})`, gabaritEmail({
      sousTitre: 'Votre séance photo',
      salutation: `Bonjour${client ? ` <strong>${echapperHtml(client)}</strong>` : ''},`,
      paragraphes: [
        `Merci pour votre séance du ${jour}. <strong>${echapperHtml(pro)}</strong> vous transmet :`,
        elements.map(e => `• ${e}`).join('<br/>'),
        ...(tarifsTexte ? [`<strong>Tarifs</strong> : ${echapperHtml(tarifsTexte)}. La facture vous sera envoyée une fois votre sélection confirmée.`] : []),
        ...(message ? [echapperHtml(message).replace(/\n/g, '<br/>')] : []),
        ...(consigneGalerie ? [consigneGalerie] : []),
      ],
      bouton,
      pied: `Message envoyé via PetsMatch pour le compte de ${echapperHtml(pro)}.`,
    }));
  } catch (e) {
    return NextResponse.json({ error: `E-mail non envoyé : ${(e as Error).message}` }, { status: 502 });
  }
  await admin.from('rdv').update({ documents_envoyes_le: maintenant }).eq('id', rdv.id);
  return NextResponse.json({ ok: true });
}
