import { NextRequest, NextResponse } from 'next/server';
import { verifiedUid } from '@/lib/server-auth';
import { admin, chargerAlbum, roleLecture, ENTETES_PRIVEES } from '@/lib/galeries-server';

// Sélection des photos par le client (compte destinataire ou lien privé) :
//  { photoId, choisie }        → coche / décoche une photo ;
//  { confirmer: true, commentaire? } → confirmation EXPLICITE et définitive
//     (statut « selection_recue », photographe prévenu une seule fois).
// Rien n'est modifiable après confirmation, sauf si le photographe rouvre
// la sélection.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  const uid = await verifiedUid(req);
  const role = await roleLecture(album, uid, req.nextUrl.searchParams.get('token'));
  if (role !== 'client') return NextResponse.json({ error: 'Sélection réservée au client' }, { status: 403 });
  if (album.selection_confirmee_le) return NextResponse.json({ error: 'Sélection déjà confirmée' }, { status: 409 });
  if (album.statut !== 'partagee') return NextResponse.json({ error: 'La sélection n\'est pas ouverte pour cette galerie' }, { status: 409 });

  const body = await req.json().catch(() => ({})) as { photoId?: string; choisie?: boolean; confirmer?: boolean; commentaire?: string };

  if (body.confirmer) {
    const { count } = await admin.from('album_photos').select('id', { count: 'exact', head: true }).eq('album_id', id).eq('selectionnee', true);
    if (!count) return NextResponse.json({ error: 'Sélectionnez au moins une photo' }, { status: 400 });
    const maintenant = new Date().toISOString();
    const { error } = await admin.from('albums_photo').update({
      selection_confirmee_le: maintenant, statut: 'selection_recue', updated_at: maintenant,
      selection_commentaire: (body.commentaire ?? '').trim().slice(0, 1000) || null,
    }).eq('id', id).is('selection_confirmee_le', null);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    await admin.from('notifications').insert({
      uid: album.pro_uid, type: 'galerie_selection_recue', title: 'Sélection reçue',
      body: `Votre client a confirmé sa sélection de ${count} photo${count > 1 ? 's' : ''} — « ${album.titre ?? 'Séance photo'} ».`,
      ...(album.pro_profile_id ? { profile_id: album.pro_profile_id } : {}),
      data: { albumId: id }, read: false,
    });
    return NextResponse.json({ ok: true, n: count }, { headers: ENTETES_PRIVEES });
  }

  if (!body.photoId || !/^[0-9a-f-]{36}$/i.test(body.photoId)) return NextResponse.json({ error: 'Photo inconnue' }, { status: 400 });
  const { error } = await admin.from('album_photos').update({ selectionnee: !!body.choisie })
    .eq('id', body.photoId).eq('album_id', id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true }, { headers: ENTETES_PRIVEES });
}
