import { NextRequest, NextResponse } from 'next/server';
import { admin, albumProches, nomStudio, ENTETES_PRIVEES } from '@/lib/galeries-server';

// Galerie partagée aux proches (lien créé par le client) : consultation
// seule. Les images passent par /photo/[photoId] (filigrane imposé), jamais
// par une URL de stockage : ni sélection, ni livraison, ni données client.
export async function GET(_req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const album = await albumProches(token);
  if (!album) return NextResponse.json({ error: 'Lien expiré ou désactivé' }, { status: 404, headers: ENTETES_PRIVEES });
  const { data: rows } = await admin.from('album_photos').select('id, largeur, hauteur, ordre')
    .eq('album_id', album.id).not('storage_path', 'is', null).order('ordre').order('created_at');
  const photos = (rows ?? []) as { id: string; largeur: number | null; hauteur: number | null; ordre: number }[];
  return NextResponse.json({
    role: 'proche',
    album: {
      id: album.id, titre: album.titre, description: album.description ?? null, statut: album.statut ?? 'partagee',
      date_seance: album.date_seance ?? null, couverture_url: null, filigrane: true, partage_client: false,
      selection_confirmee_le: null, selection_commentaire: null, nb_photos_incluses: null, livree_le: null,
    },
    studio: await nomStudio(album),
    livraison: [],
    photos: photos.map(p => ({
      id: p.id, url: `/api/galeries/proches/${encodeURIComponent(token)}/photo/${p.id}`,
      largeur: p.largeur, hauteur: p.hauteur, ordre: p.ordre, selectionnee: false, aimee: false,
    })),
  }, { headers: ENTETES_PRIVEES });
}
