import { NextRequest, NextResponse } from 'next/server';
import sharp from 'sharp';
import { admin, albumProches, nomStudio, BUCKET_GALERIES } from '@/lib/galeries-server';

// Aperçu d'une photo pour un lien « proches » : toujours filigrané. Si la
// galerie a été importée sans filigrane, il est apposé ici (nom du studio en
// diagonale, répété) ; l'aperçu de stockage n'est jamais exposé tel quel.
export const runtime = 'nodejs';

const ENTITES: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' };
const echapper = (t: string) => t.replace(/[&<>"']/g, c => ENTITES[c]);

function filigraneSvg(w: number, h: number, texte: string) {
  const taille = Math.max(18, Math.round(Math.min(w, h) / 16));
  const pasY = taille * 4, pasX = Math.round(texte.length * taille * 0.6 + taille * 3);
  const diag = Math.ceil(Math.sqrt(w * w + h * h));
  const lignes: string[] = [];
  let k = 0;
  for (let y = -diag / 2; y < diag / 2; y += pasY, k++) {
    for (let x = -diag / 2; x < diag / 2; x += pasX) {
      lignes.push(`<text x="${Math.round(x + (k % 2) * (pasX / 2))}" y="${Math.round(y)}">${echapper(texte)}</text>`);
    }
  }
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">`
    + `<g transform="translate(${w / 2} ${h / 2}) rotate(-30)" font-family="Arial, sans-serif" font-weight="600" font-size="${taille}" `
    + `text-anchor="middle" fill="rgba(255,255,255,0.34)" stroke="rgba(0,0,0,0.2)" stroke-width="${Math.max(1, taille / 18)}">`
    + `${lignes.join('')}</g></svg>`);
}

export async function GET(_req: NextRequest, { params }: { params: Promise<{ token: string; photoId: string }> }) {
  const { token, photoId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(photoId)) return new NextResponse(null, { status: 404 });
  const album = await albumProches(token);
  if (!album) return new NextResponse(null, { status: 404 });
  const { data: ph } = await admin.from('album_photos').select('storage_path').eq('id', photoId).eq('album_id', album.id).maybeSingle();
  const chemin = (ph as { storage_path?: string | null } | null)?.storage_path;
  if (!chemin) return new NextResponse(null, { status: 404 });
  const { data: blob, error } = await admin.storage.from(BUCKET_GALERIES).download(chemin);
  if (error || !blob) return new NextResponse(null, { status: 404 });
  let image: Buffer = Buffer.from(await blob.arrayBuffer());
  if (album.filigrane === false) {
    const img = sharp(image);
    const meta = await img.metadata();
    const w = meta.width ?? 1600, h = meta.height ?? 1600;
    const studio = (await nomStudio(album)).nom || 'PetsMatch';
    image = await img.composite([{ input: filigraneSvg(w, h, `© ${studio}`), top: 0, left: 0 }]).jpeg({ quality: 78 }).toBuffer();
  }
  return new NextResponse(new Uint8Array(image), {
    headers: { 'Content-Type': 'image/jpeg', 'Cache-Control': 'private, max-age=600', 'X-Robots-Tag': 'noindex, nofollow' },
  });
}
