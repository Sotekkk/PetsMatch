import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/server-auth';
import { admin, chargerAlbum, estGestionnaire, nomStudio, nomClientAlbum, emailClientAlbum, lienClientAlbum } from '@/lib/galeries-server';
import { SITE_URL, echapperHtml, emailValide, gabaritEmail, envoyerEmail } from '@/lib/email-petsmatch';

// Photographe : relance le client qui n'a pas confirmé sa sélection
// (notification s'il a un compte + e-mail avec le lien). Une relance par jour
// au plus ; le rappel automatique (purgerLivraisonsPhoto) s'appuie sur la
// même date (relance_selection_le).
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  if (!(await estGestionnaire(album, auth.uid))) return NextResponse.json({ error: 'Réservé au photographe' }, { status: 403 });
  if (album.statut !== 'partagee' || album.selection_confirmee_le) {
    return NextResponse.json({ error: 'Pas de sélection en attente pour cette galerie.' }, { status: 409 });
  }
  if (album.relance_selection_le && Date.now() - new Date(album.relance_selection_le).getTime() < 86400000) {
    return NextResponse.json({ error: 'Client déjà relancé il y a moins de 24 h.' }, { status: 429 });
  }
  const { count } = await admin.from('album_photos').select('id', { count: 'exact', head: true }).eq('album_id', id).eq('selectionnee', true);
  const nb = count ?? 0;
  const studio = (await nomStudio(album)).nom || 'Votre photographe';
  const titre = album.titre ?? 'Séance photo';
  const texte = nb
    ? `Vous avez choisi ${nb} photo${nb > 1 ? 's' : ''} : confirmez votre sélection pour que ${studio} lance la retouche.`
    : `${studio} attend votre sélection de photos pour lancer la retouche.`;

  let notifiee = false;
  if (album.client_uid && album.partage_client) {
    await admin.from('notifications').insert({
      uid: album.client_uid, type: 'galerie_disponible', title: 'Votre sélection de photos',
      body: `« ${titre} » — ${texte}`,
      ...(album.client_profile_id ? { profile_id: album.client_profile_id } : {}),
      data: { albumId: id }, read: false,
    });
    notifiee = true;
  }
  let emailEnvoye = false;
  const email = await emailClientAlbum(album);
  if (emailValide(email)) {
    try {
      const url = album.client_uid && album.partage_client
        ? `${SITE_URL}/galerie/${id}`
        : `${SITE_URL}/album/${await lienClientAlbum(id, new Date(Date.now() + 30 * 86400000))}`;
      const client = await nomClientAlbum(album);
      await envoyerEmail(email as string, `Votre sélection de photos — ${titre}`, gabaritEmail({
        sousTitre: 'Votre sélection de photos',
        salutation: `Bonjour${client ? ` <strong>${echapperHtml(client)}</strong>` : ''},`,
        paragraphes: [echapperHtml(texte), "Ouvrez la galerie, cochez les photos souhaitées puis touchez « Confirmer ma sélection »."],
        bouton: { label: nb ? 'Confirmer ma sélection' : 'Choisir mes photos', url },
      }));
      emailEnvoye = true;
    } catch (e) { console.error('[relancer] e-mail', e); }
  }
  if (!notifiee && !emailEnvoye) return NextResponse.json({ error: "Aucun moyen de joindre le client : renseignez son e-mail dans « Partage »." }, { status: 400 });
  await admin.from('albums_photo').update({ relance_selection_le: new Date().toISOString() }).eq('id', id);
  return NextResponse.json({ ok: true, notifiee, email_envoye: emailEnvoye });
}
