import { NextRequest, NextResponse } from 'next/server';
import { verifiedUid } from '@/lib/server-auth';
import { admin, chargerAlbum, roleLecture, ENTETES_PRIVEES } from '@/lib/galeries-server';

// Coup de cœur du client sur une photo ({ photoId, aimee }) : distinct de la
// sélection (qui engage la commande), possible à tout moment, même après
// confirmation. Les photos aimées remontent dans Mes favoris > Shootings.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  const uid = await verifiedUid(req);
  const role = await roleLecture(album, uid, req.nextUrl.searchParams.get('token'));
  if (role !== 'client') return NextResponse.json({ error: 'Réservé au client' }, { status: 403 });
  const body = await req.json().catch(() => ({})) as { photoId?: string; aimee?: boolean };
  if (!body.photoId || !/^[0-9a-f-]{36}$/i.test(body.photoId)) return NextResponse.json({ error: 'Photo inconnue' }, { status: 400 });
  const { error } = await admin.from('album_photos').update({ aimee: !!body.aimee }).eq('id', body.photoId).eq('album_id', id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true }, { headers: ENTETES_PRIVEES });
}
