import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/server-auth';
import { admin, nomStudio, BUCKET_GALERIES, DUREE_URL, ENTETES_PRIVEES, type AlbumRow } from '@/lib/galeries-server';

// Mes favoris > Shootings : photos aimées (coups de cœur) et sélectionnées
// dans les galeries partagées sur MON compte, pour le profil actif
// (?profileId= : galeries de ce profil ou sans profil précis).
export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const pid = req.nextUrl.searchParams.get('profileId');
  const { data } = await admin.from('albums_photo').select('*')
    .eq('client_uid', auth.uid).eq('partage_client', true).not('statut', 'in', '(brouillon,archivee)')
    .order('date_seance', { ascending: false, nullsFirst: false });
  const albums = ((data ?? []) as AlbumRow[]).filter(a => !pid || !a.client_profile_id || a.client_profile_id === pid);
  const galeries = [];
  for (const a of albums) {
    const { data: rows } = await admin.from('album_photos').select('id, storage_path, largeur, hauteur, aimee, selectionnee')
      .eq('album_id', a.id).or('aimee.eq.true,selectionnee.eq.true').not('storage_path', 'is', null).order('ordre');
    const photos = (rows ?? []) as { id: string; storage_path: string; largeur: number | null; hauteur: number | null; aimee: boolean; selectionnee: boolean }[];
    if (!photos.length) continue;
    const { data: signees } = await admin.storage.from(BUCKET_GALERIES).createSignedUrls(photos.map(p => p.storage_path), DUREE_URL);
    const urls: Record<string, string> = {};
    for (const s of signees ?? []) if (s.path && s.signedUrl) urls[s.path] = s.signedUrl;
    galeries.push({
      album: { id: a.id, titre: a.titre, date_seance: a.date_seance ?? null, studio: (await nomStudio(a)).nom },
      photos: photos.filter(p => urls[p.storage_path]).map(p => ({
        id: p.id, url: urls[p.storage_path], largeur: p.largeur, hauteur: p.hauteur, aimee: !!p.aimee, selectionnee: !!p.selectionnee,
      })),
    });
  }
  return NextResponse.json({ galeries }, { headers: ENTETES_PRIVEES });
}
