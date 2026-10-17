import { randomUUID } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { verifiedUid, requireUser } from '@/lib/server-auth';
import { admin, BUCKET_LIVRAISONS, chargerAlbum, roleLecture, estGestionnaire, estPremium, ENTETES_PRIVEES,
  nomStudio, nomClientAlbum, emailClientAlbum, lienClientAlbum, factureSeance } from '@/lib/galeries-server';
import { SITE_URL, echapperHtml, emailValide, gabaritEmail, envoyerEmail } from '@/lib/email-petsmatch';
import { facturePdfBlob } from '@/lib/facture-pdf';
import { factureVersPdfData } from '@/lib/facture-pdf-data';

// Livraison des fichiers finaux — STOCKAGE TEMPORAIRE (bucket privé
// « livraisons ») :
//  GET  (client / photographe) : URL signées de téléchargement (10 min) des
//       ZIP non expirés ; compteur de téléchargements.
//  POST (photographe Premium) :
//    { action: 'preparer', parts }            → URL d'envoi signées des ZIP ;
//    { action: 'publier', parts: [...], jours, forcer? } → remplace la
//       livraison précédente, galerie « livrée », client prévenu (notif si
//       compte + e-mail avec le lien et la facture acquittée en PDF) ;
//       refusée (409 facture_non_payee) tant que la facture de la séance
//       n'est pas payée, sauf `forcer` (choix explicite du photographe) ;
//    { action: 'prolonger' }                  → +7 jours, une seule fois ;
//    { action: 'supprimer' }                  → retire la livraison.
// Volume limité (500 Mo, 3 / 7 / 14 jours) : stockage temporaire, pas d'archive.
const DUREE_TELECHARGEMENT = 600;
const JOURS_MAX = 14;
const JOURS_DEFAUT = 7;
const JOURS_PROLONGATION = 7;
const TAILLE_MAX_LIVRAISON = 500 * 1024 * 1024;
const PARTS_MAX = 12; // 12 × 45 Mo

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
  if (!(await estPremium(album.pro_uid))) return NextResponse.json({ error: 'La livraison est réservée à la formule Premium.' }, { status: 402 });
  const body = await req.json().catch(() => ({})) as {
    action?: string; parts?: number | { path?: string; nom?: string; taille?: number; nb?: number }[]; jours?: number; forcer?: boolean;
  };
  const jours = Math.min(JOURS_MAX, Math.max(1, Number(body.jours) || JOURS_DEFAUT));

  // Paiement avant livraison : facture de la séance payée, sinon choix explicite.
  const facture = await factureSeance(album);
  if ((body.action === 'preparer' || body.action === 'publier') && !body.forcer && facture?.statut !== 'payee') {
    return NextResponse.json({
      code: 'facture_non_payee',
      error: facture ? 'La facture de la séance n\'est pas encore payée.' : 'Aucune facture pour cette séance.',
    }, { status: 409 });
  }

  if (body.action === 'preparer') {
    const n = Number(body.parts) || 1;
    if (n > PARTS_MAX) return NextResponse.json({ error: 'Livraison limitée à 500 Mo : compressez les fichiers ou faites deux livraisons.' }, { status: 413 });
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
    const tailleTotale = parts.reduce((n, p) => n + (Number(p.taille) || 0), 0);
    if (tailleTotale > TAILLE_MAX_LIVRAISON || parts.length > PARTS_MAX) {
      await admin.storage.from(BUCKET_LIVRAISONS).remove(parts.map(p => p.path as string));
      return NextResponse.json({ error: 'Livraison limitée à 500 Mo : compressez les fichiers ou faites deux livraisons.' }, { status: 413 });
    }
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
    const dateLimite = new Date(expire).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    if (album.client_uid && album.partage_client) {
      await admin.from('notifications').insert({
        uid: album.client_uid, type: 'galerie_livree', title: 'Vos photos sont prêtes',
        body: `Les photos de « ${album.titre ?? 'Séance photo'} » sont à télécharger avant le ${dateLimite} : elles seront ensuite supprimées.`,
        ...(album.client_profile_id ? { profile_id: album.client_profile_id } : {}),
        data: { albumId: id }, read: false,
      });
    }
    // E-mail au client (avec ou sans compte) : lien de téléchargement, date
    // limite, facture acquittée en pièce jointe si elle est payée.
    let emailEnvoye = false;
    const email = await emailClientAlbum(album);
    if (emailValide(email)) {
      try {
        const url = album.client_uid && album.partage_client
          ? `${SITE_URL}/galerie/${id}`
          : `${SITE_URL}/album/${await lienClientAlbum(id, new Date(new Date(expire).getTime() + 86400000))}`;
        const pieces: { filename: string; content: Buffer }[] = [];
        if (facture?.statut === 'payee') {
          try {
            const pdf = await facturePdfBlob(factureVersPdfData(facture, true));
            const num = String(facture.numero_affichage ?? facture.numero_facture ?? '').replace(/[^\w-]+/g, '-');
            pieces.push({ filename: `facture-${num || 'acquittee'}.pdf`, content: Buffer.from(await pdf.arrayBuffer()) });
          } catch (e) { console.error('[livraison] PDF facture', e); }
        }
        const studio = (await nomStudio(album)).nom || 'Votre photographe';
        const client = await nomClientAlbum(album);
        const nb = parts.reduce((n, p) => n + (Number(p.nb) || 0), 0);
        await envoyerEmail(email as string, `Vos photos sont prêtes — ${album.titre ?? 'Séance photo'}`, gabaritEmail({
          sousTitre: 'Vos photos retouchées sont prêtes',
          salutation: `Bonjour${client ? ` <strong>${echapperHtml(client)}</strong>` : ''},`,
          paragraphes: [
            `<strong>${echapperHtml(studio)}</strong> vous livre ${nb ? `vos ${nb} photo${nb > 1 ? 's' : ''}` : 'vos photos'} de la séance « ${echapperHtml(album.titre ?? 'Séance photo')} », en haute définition.`,
            `Ouvrez la galerie et touchez « Télécharger » : ${parts.length > 1 ? `${parts.length} archives ZIP` : 'une archive ZIP'} à enregistrer sur votre ordinateur ou votre téléphone.`,
            ...(pieces.length ? ['Votre facture acquittée est jointe à cet e-mail.'] : []),
          ],
          alerte: `À télécharger avant le <strong>${dateLimite}</strong>. Passé cette date, les fichiers sont définitivement supprimés de nos serveurs : pensez à les enregistrer dès maintenant.`,
          bouton: { label: 'Télécharger mes photos', url },
        }), pieces);
        emailEnvoye = true;
      } catch (e) { console.error('[livraison] e-mail', e); }
    }
    return NextResponse.json({ ok: true, expire_le: expire, email_envoye: emailEnvoye });
  }

  if (body.action === 'prolonger') {
    const { data } = await admin.from('album_livraisons').select('expire_le, prolongee').eq('album_id', id).limit(1).maybeSingle();
    const l = data as { expire_le?: string; prolongee?: boolean } | null;
    if (!l?.expire_le) return NextResponse.json({ error: 'Aucune livraison' }, { status: 404 });
    if (l.prolongee) return NextResponse.json({ error: 'La livraison a déjà été prolongée une fois.' }, { status: 409 });
    const depart = Math.max(Date.now(), new Date(l.expire_le).getTime());
    const expire = new Date(depart + JOURS_PROLONGATION * 86400000).toISOString();
    await admin.from('album_livraisons').update({ expire_le: expire, rappel_envoye: false, prolongee: true }).eq('album_id', id);
    return NextResponse.json({ ok: true, expire_le: expire });
  }

  if (body.action === 'supprimer') {
    await retirerLivraison(id);
    return NextResponse.json({ ok: true });
  }

  return NextResponse.json({ error: 'Action inconnue' }, { status: 400 });
}
