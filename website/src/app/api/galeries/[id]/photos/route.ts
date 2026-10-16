import { NextRequest, NextResponse } from 'next/server';
import { randomUUID } from 'crypto';
import { requireUser } from '@/lib/server-auth';
import { admin, BUCKET_GALERIES, chargerAlbum, estGestionnaire, estPremium } from '@/lib/galeries-server';

// Import des aperçus d'une galerie privée, en 2 temps (photographe Premium) :
//  1. action « preparer » : { fichiers: [{ nom, taille }] } → pour chaque
//     fichier non déjà présent (même nom + même taille = doublon), une URL
//     d'envoi signée vers le bucket privé « galeries » ;
//  2. action « enregistrer » : { photos: [{ path, nom, taille, largeur, hauteur }] }
//     → lignes album_photos (chemin vérifié : uniquement dans cette galerie).
// DELETE { ids } : suppression des aperçus (fichiers + lignes).
async function gestionnaire(req: NextRequest, id: string) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  if (!(await estGestionnaire(album, auth.uid))) return NextResponse.json({ error: 'Réservé au photographe' }, { status: 403 });
  return album;
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const album = await gestionnaire(req, id);
  if (album instanceof NextResponse) return album;
  if (!(await estPremium(album.pro_uid))) {
    return NextResponse.json({ error: 'Les galeries clients sont réservées aux photographes Premium.' }, { status: 402 });
  }
  const body = await req.json().catch(() => ({})) as {
    action?: string;
    fichiers?: { nom?: string; taille?: number }[];
    photos?: { path?: string; nom?: string; taille?: number; largeur?: number; hauteur?: number }[];
  };

  if (body.action === 'preparer') {
    const fichiers = (body.fichiers ?? []).slice(0, 200);
    const { data: existants } = await admin.from('album_photos').select('nom_fichier, taille_octets').eq('album_id', id);
    const deja = new Set(((existants ?? []) as { nom_fichier: string | null; taille_octets: number | null }[])
      .map(e => `${e.nom_fichier}|${e.taille_octets}`));
    const out: { nom: string; taille: number; doublon: boolean; path?: string; token?: string }[] = [];
    for (const f of fichiers) {
      const nom = String(f.nom ?? 'photo').slice(0, 200);
      const taille = Number(f.taille) || 0;
      const cle = `${nom}|${taille}`;
      if (deja.has(cle)) { out.push({ nom, taille, doublon: true }); continue; }
      deja.add(cle);
      const path = `${id}/${randomUUID()}.jpg`;
      const { data, error } = await admin.storage.from(BUCKET_GALERIES).createSignedUploadUrl(path);
      if (error || !data) return NextResponse.json({ error: error?.message ?? 'Envoi impossible' }, { status: 500 });
      out.push({ nom, taille, doublon: false, path, token: data.token });
    }
    return NextResponse.json({ fichiers: out });
  }

  if (body.action === 'enregistrer') {
    const photos = (body.photos ?? []).filter(p => typeof p.path === 'string' && p.path.startsWith(`${id}/`) && !p.path.includes('..'));
    if (!photos.length) return NextResponse.json({ ok: true, n: 0 });
    const { data: dernier } = await admin.from('album_photos').select('ordre').eq('album_id', id)
      .order('ordre', { ascending: false }).limit(1).maybeSingle();
    let ordre = ((dernier as { ordre?: number } | null)?.ordre ?? 0) + 1;
    const { error } = await admin.from('album_photos').insert(photos.map(p => ({
      album_id: id, storage_path: p.path, nom_fichier: String(p.nom ?? '').slice(0, 200) || null,
      taille_octets: Number(p.taille) || null, largeur: Number(p.largeur) || null, hauteur: Number(p.hauteur) || null,
      ordre: ordre++,
    })));
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    await admin.from('albums_photo').update({ updated_at: new Date().toISOString() }).eq('id', id);
    return NextResponse.json({ ok: true, n: photos.length });
  }

  return NextResponse.json({ error: 'Action inconnue' }, { status: 400 });
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const album = await gestionnaire(req, id);
  if (album instanceof NextResponse) return album;
  const { ids } = await req.json().catch(() => ({})) as { ids?: string[] };
  const liste = (ids ?? []).filter(x => /^[0-9a-f-]{36}$/i.test(x)).slice(0, 500);
  if (!liste.length) return NextResponse.json({ ok: true, n: 0 });
  const { data: rows } = await admin.from('album_photos').select('id, storage_path').eq('album_id', id).in('id', liste);
  const chemins = ((rows ?? []) as { storage_path: string | null }[]).map(r => r.storage_path).filter((x): x is string => !!x);
  if (chemins.length) await admin.storage.from(BUCKET_GALERIES).remove(chemins);
  await admin.from('album_photos').delete().eq('album_id', id).in('id', liste);
  await admin.from('albums_photo').update({ updated_at: new Date().toISOString() }).eq('id', id);
  return NextResponse.json({ ok: true, n: (rows ?? []).length });
}
