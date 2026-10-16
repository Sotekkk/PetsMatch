import { NextRequest, NextResponse } from 'next/server';
import { admin, chargerAlbum, contenuGalerie, lienValide, ENTETES_PRIVEES } from '@/lib/galeries-server';

// Galerie ouverte par lien privé (/album/<token>) : le lien ne donne accès
// qu'à SA galerie, tant qu'il est actif et non expiré, et jamais à une
// galerie en brouillon ou archivée.
export async function GET(_req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const { data } = await admin.from('album_partage').select('album_id').eq('token', token).maybeSingle();
  const albumId = (data as { album_id?: string } | null)?.album_id;
  const album = albumId ? await chargerAlbum(albumId) : null;
  if (!album || !(await lienValide(album.id, token)) || album.statut === 'brouillon' || album.statut === 'archivee') {
    return NextResponse.json({ error: 'Lien expiré ou désactivé' }, { status: 404, headers: ENTETES_PRIVEES });
  }
  return NextResponse.json(await contenuGalerie(album, 'client'), { headers: ENTETES_PRIVEES });
}
