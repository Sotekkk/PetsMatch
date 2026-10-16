import { NextRequest, NextResponse } from 'next/server';
import { verifiedUid, requireUser } from '@/lib/server-auth';
import { admin, BUCKET_GALERIES, BUCKET_LIVRAISONS, chargerAlbum, roleLecture, contenuGalerie, ENTETES_PRIVEES } from '@/lib/galeries-server';

// GET : contenu d'une galerie privée (fiche + aperçus en URL signées courtes).
// Accès : photographe / cogérant, client destinataire (galerie partagée) ou
// lien privé valide (?token=). Jamais d'URL publique permanente.
// DELETE : suppression contrôlée de la galerie (fichiers + lignes), réservée
// au photographe.
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  const uid = await verifiedUid(req);
  const role = await roleLecture(album, uid, req.nextUrl.searchParams.get('token'));
  if (!role) return NextResponse.json({ error: 'Accès non autorisé' }, { status: 403 });

  return NextResponse.json(await contenuGalerie(album, role), { headers: ENTETES_PRIVEES });
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  if (album.pro_uid !== auth.uid) return NextResponse.json({ error: 'Réservé au photographe' }, { status: 403 });
  const { data: rows } = await admin.from('album_photos').select('storage_path').eq('album_id', id);
  const chemins = ((rows ?? []) as { storage_path: string | null }[]).map(r => r.storage_path).filter((x): x is string => !!x);
  for (let i = 0; i < chemins.length; i += 100) {
    await admin.storage.from(BUCKET_GALERIES).remove(chemins.slice(i, i + 100));
  }
  // Livraison temporaire éventuelle (ZIP) : supprimée avec la galerie.
  const { data: liv } = await admin.from('album_livraisons').select('storage_path').eq('album_id', id);
  const zips = ((liv ?? []) as { storage_path: string }[]).map(r => r.storage_path);
  if (zips.length) await admin.storage.from(BUCKET_LIVRAISONS).remove(zips);
  await admin.from('album_partage').delete().eq('album_id', id);
  await admin.from('album_photos').delete().eq('album_id', id);
  const { error } = await admin.from('albums_photo').delete().eq('id', id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}
