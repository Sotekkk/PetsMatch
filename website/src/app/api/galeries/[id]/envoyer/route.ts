import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/server-auth';
import { admin, chargerAlbum, estGestionnaire, estPremium, nomStudio, nomClientAlbum, lienClientAlbum } from '@/lib/galeries-server';
import { SITE_URL, echapperHtml, emailValide, gabaritEmail, envoyerEmail } from '@/lib/email-petsmatch';

// Envoi de la galerie au client par e-mail (photographe Premium) :
// { email, message? }. L'adresse est enregistrée sur la galerie (prochains
// envois : facture, livraison). Le client choisit ses photos depuis le lien :
//  • compte PetsMatch → galerie partagée sur son compte (/galerie/<id>) ;
//  • sans compte → lien privé « client » de 30 jours (/album/<token>).
const JOURS_LIEN = 30;

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  if (!(await estGestionnaire(album, auth.uid))) return NextResponse.json({ error: 'Réservé au photographe' }, { status: 403 });
  if (!(await estPremium(album.pro_uid))) return NextResponse.json({ error: 'Le partage de galerie est réservé à la formule Premium.' }, { status: 402 });
  const body = await req.json().catch(() => ({})) as { email?: string; message?: string };
  const email = (body.email ?? '').trim();
  if (!emailValide(email)) return NextResponse.json({ error: 'Adresse e-mail invalide' }, { status: 400 });
  const { count } = await admin.from('album_photos').select('id', { count: 'exact', head: true }).eq('album_id', id);
  if (!count) return NextResponse.json({ error: 'Ajoutez des photos avant d\'envoyer la galerie.' }, { status: 400 });

  const maintenant = new Date().toISOString();
  const compte = !!album.client_uid;
  await admin.from('albums_photo').update({
    client_email: email, updated_at: maintenant,
    ...(compte ? { partage_client: true } : {}),
    ...(album.statut === 'brouillon' || !album.statut ? { statut: 'partagee', partagee_le: maintenant } : {}),
  }).eq('id', id);

  const url = compte
    ? `${SITE_URL}/galerie/${id}`
    : `${SITE_URL}/album/${await lienClientAlbum(id, new Date(Date.now() + JOURS_LIEN * 86400000))}`;
  const studio = (await nomStudio(album)).nom || 'Votre photographe';
  const client = await nomClientAlbum(album);
  const titre = album.titre ?? 'Séance photo';
  const message = (body.message ?? '').trim().slice(0, 1500);

  if (compte && !album.partage_client) {
    await admin.from('notifications').insert({
      uid: album.client_uid, type: 'galerie_disponible', title: 'Votre galerie photo est disponible',
      body: `${studio} a partagé la galerie « ${titre} ».`,
      ...(album.client_profile_id ? { profile_id: album.client_profile_id } : {}),
      data: { albumId: id }, read: false,
    });
  }
  try {
    await envoyerEmail(email, `Vos photos — ${titre}`, gabaritEmail({
      sousTitre: 'Votre galerie photo est prête',
      salutation: `Bonjour${client ? ` <strong>${echapperHtml(client)}</strong>` : ''},`,
      paragraphes: [
        `<strong>${echapperHtml(studio)}</strong> a mis en ligne les photos de votre séance « ${echapperHtml(titre)} ».`,
        ...(message ? [echapperHtml(message).replace(/\n/g, '<br/>')] : []),
        "Ouvrez la galerie, touchez le cœur sur vos photos préférées, cochez celles que vous souhaitez recevoir, puis confirmez votre sélection. Les aperçus sont en qualité réduite : les fichiers définitifs vous seront remis après la retouche.",
        ...(compte ? [] : [`Ce lien est personnel et reste valable ${JOURS_LIEN} jours.`]),
      ],
      bouton: { label: 'Voir ma galerie', url },
    }));
  } catch (e) {
    return NextResponse.json({ error: `E-mail non envoyé : ${(e as Error).message}` }, { status: 502 });
  }
  return NextResponse.json({ ok: true, url });
}
