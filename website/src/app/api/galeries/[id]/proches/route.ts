import { NextRequest, NextResponse } from 'next/server';
import { verifiedUid } from '@/lib/server-auth';
import { admin, chargerAlbum, roleLecture, ENTETES_PRIVEES } from '@/lib/galeries-server';

// Lien « proches » créé par le client pour partager sa galerie à sa famille :
// consultation seule, aperçus toujours filigranés (cf. /api/galeries/proches),
// ni sélection ni téléchargement. Valable 90 jours, un seul lien actif.
//  POST   → renvoie le lien actif (ou en crée un) ;
//  DELETE → désactive les liens proches de la galerie.
const JOURS = 90;

async function controle(req: NextRequest, id: string) {
  const album = await chargerAlbum(id);
  if (!album) return { err: NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 }) };
  const uid = await verifiedUid(req);
  const role = await roleLecture(album, uid, req.nextUrl.searchParams.get('token'));
  if (role !== 'client') return { err: NextResponse.json({ error: 'Réservé au client' }, { status: 403 }) };
  return { album, uid };
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const c = await controle(req, id);
  if (c.err) return c.err;
  const { data: actifs } = await admin.from('album_partage').select('token, expire_at')
    .eq('album_id', id).eq('type', 'proches').eq('actif', true).gt('expire_at', new Date().toISOString())
    .order('created_at', { ascending: false }).limit(1);
  const existant = (actifs ?? [])[0] as { token: string; expire_at: string } | undefined;
  if (existant) return NextResponse.json({ token: existant.token, expire_at: existant.expire_at }, { headers: ENTETES_PRIVEES });
  const expire = new Date(Date.now() + JOURS * 86400000).toISOString();
  const { data, error } = await admin.from('album_partage').insert({
    album_id: id, type: 'proches', expire_at: expire, actif: true, cree_par_uid: c.uid ?? null,
  }).select('token, expire_at').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json(data, { headers: ENTETES_PRIVEES });
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const c = await controle(req, id);
  if (c.err) return c.err;
  const { error } = await admin.from('album_partage').update({ actif: false }).eq('album_id', id).eq('type', 'proches');
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true }, { headers: ENTETES_PRIVEES });
}
