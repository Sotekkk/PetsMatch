import { randomUUID } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { verifiedUid, requireUser } from '@/lib/server-auth';
import { admin, BUCKET_LIVRAISONS, chargerAlbum, roleLecture, estGestionnaire, estPremium, ENTETES_PRIVEES } from '@/lib/galeries-server';

// Livraison des fichiers finaux — STOCKAGE TEMPORAIRE (bucket privé
// « livraisons ») :
//  GET  (client / photographe) : URL signées de téléchargement (10 min) des
//       ZIP non expirés ; compteur de téléchargements.
//  POST (photographe Premium) :
//    { action: 'preparer', parts }            → URL d'envoi signées des ZIP ;
//    { action: 'publier', parts: [...], jours } → remplace la livraison
//       précédente, galerie « livrée », client prévenu (s'il a un compte) ;
//    { action: 'prolonger', jours }           → repousse l'expiration ;
//    { action: 'supprimer' }                  → retire la livraison.
const DUREE_TELECHARGEMENT = 600;
const JOURS_MAX = 90;

async function retirerLivraison(albumId: string) {
  const { data } = await admin.from('album_livraisons').select('storage_path').eq('album_id', albumId);
  const chemins = ((data ?? []) as { storage_path: string }[]).map(r => r.storage_path);
  if (chemins.length) await admin.storage.from(BUCKET_LIVRAISONS).remove(chemins);
  await admin.from('album_livraisons').delete().eq('album_id', albumId);
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  const uid = await verifiedUid(req);
  const role = await roleLecture(album, uid, req.nextUrl.searchParams.get('token'));
  if (!role) return NextResponse.json({ error: 'Accès non autorisé' }, { status: 403 });
  const { data } = await admin.from('album_livraisons').select('id, numero, storage_path, nom_fichier, telechargements, expire_le')
    .eq('album_id', id).gt('expire_le', new Date().toISOString()).order('numero');
  const rows = (data ?? []) as { id: string; numero: number; storage_path: string; nom_fichier: string; telechargements: number; expire_le: string }[];
  const out: { id: string; nom: string; url: string }[] = [];
  for (const r of rows) {
    const { data: s } = await admin.storage.from(BUCKET_LIVRAISONS).createSignedUrl(r.storage_path, DUREE_TELECHARGEMENT, { download: r.nom_fichier });
    if (s?.signedUrl) out.push({ id: r.id, nom: r.nom_fichier, url: s.signedUrl });
    if (role === 'client') await admin.from('album_livraisons').update({ telechargements: r.telechargements + 1 }).eq('id', r.id);
  }
  return NextResponse.json({ fichiers: out }, { headers: ENTETES_PRIVEES });
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { id } = await params;
  const album = await chargerAlbum(id);
  if (!album) return NextResponse.json({ error: 'Galerie introuvable' }, { status: 404 });
  if (!(await estGestionnaire(album, auth.uid))) return NextResponse.json({ error: 'Réservé au photographe' }, { status: 403 });
  if (!(await estPremium(album.pro_uid))) return NextResponse.json({ error: 'La livraison est réservée aux photographes Premium.' }, { status: 402 });
  const body = await req.json().catch(() => ({})) as {
    action?: string; parts?: number | { path?: string; nom?: string; taille?: number; nb?: number }[]; jours?: number;
  };
  const jours = Math.min(JOURS_MAX, Math.max(1, Number(body.jours) || 30));

  if (body.action === 'preparer') {
    const n = Math.min(40, Math.max(1, Number(body.parts) || 1));
    const out: { path: string; token: string }[] = [];
    for (let i = 0; i < n; i++) {
      const path = `${id}/${randomUUID()}.zip`;
      const { data, error } = await admin.storage.from(BUCKET_LIVRAISONS).createSignedUploadUrl(path);
      if (error || !data) return NextResponse.json({ error: error?.message ?? 'Envoi impossible' }, { status: 500 });
      out.push({ path, token: data.token });
    }
    return NextResponse.json({ parts: out });
  }

  if (body.action === 'publier') {
    const parts = (Array.isArray(body.parts) ? body.parts : [])
      .filter(p => typeof p.path === 'string' && p.path.startsWith(`${id}/`) && p.path.endsWith('.zip') && !p.path.includes('..'));
    if (!parts.length) return NextResponse.json({ error: 'Aucun fichier' }, { status: 400 });
    // Les ZIP de la livraison précédente sont supprimés (hors nouveaux).
    const nouveaux = new Set(parts.map(p => p.path));
    const { data: anciens } = await admin.from('album_livraisons').select('storage_path').eq('album_id', id);
    const aRetirer = ((anciens ?? []) as { storage_path: string }[]).map(r => r.storage_path).filter(c => !nouveaux.has(c));
    if (aRetirer.length) await admin.storage.from(BUCKET_LIVRAISONS).remove(aRetirer);
    await admin.from('album_livraisons').delete().eq('album_id', id);
    const expire = new Date(Date.now() + jours * 86400000).toISOString();
    const base = (album.titre ?? 'photos').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60) || 'photos';
    const { error } = await admin.from('album_livraisons').insert(parts.map((p, i) => ({
      album_id: id, numero: i + 1, storage_path: p.path,
      nom_fichier: parts.length > 1 ? `${base}-${i + 1}-sur-${parts.length}.zip` : `${base}.zip`,
      taille_octets: Number(p.taille) || null, nb_fichiers: Number(p.nb) || null, expire_le: expire,
    })));
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    const maintenant = new Date().toISOString();
    await admin.from('albums_photo').update({ statut: 'livree', livree_le: maintenant, updated_at: maintenant }).eq('id', id);
    if (album.client_uid && album.partage_client) {
      await admin.from('notifications').insert({
        uid: album.client_uid, type: 'galerie_livree', title: 'Vos photos sont prêtes',
        body: `Les photos de « ${album.titre ?? 'Séance photo'} » sont disponibles au téléchargement jusqu'au ${new Date(expire).toLocaleDateString('fr-FR')}.`,
        ...(album.client_profile_id ? { profile_id: album.client_profile_id } : {}),
        data: { albumId: id }, read: false,
      });
    }
    return NextResponse.json({ ok: true, expire_le: expire });
  }

  if (body.action === 'prolonger') {
    const { data } = await admin.from('album_livraisons').select('expire_le').eq('album_id', id).limit(1).maybeSingle();
    const actuelle = (data as { expire_le?: string } | null)?.expire_le;
    if (!actuelle) return NextResponse.json({ error: 'Aucune livraison' }, { status: 404 });
    const depart = Math.max(Date.now(), new Date(actuelle).getTime());
    const expire = new Date(Math.min(depart + jours * 86400000, Date.now() + JOURS_MAX * 86400000)).toISOString();
    await admin.from('album_livraisons').update({ expire_le: expire, rappel_envoye: false }).eq('album_id', id);
    return NextResponse.json({ ok: true, expire_le: expire });
  }

  if (body.action === 'supprimer') {
    await retirerLivraison(id);
    return NextResponse.json({ ok: true });
  }

  return NextResponse.json({ error: 'Action inconnue' }, { status: 400 });
}
