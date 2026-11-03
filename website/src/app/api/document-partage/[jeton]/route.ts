import { NextRequest, NextResponse } from 'next/server';
import { admin } from '@/lib/galeries-server';
import { cibleStockage, empreinte } from '@/lib/liens-documents-server';

// Ouverture d'un document par lien sécurisé, sans compte : le jeton n'ouvre
// que SON document ; refusé s'il a expiré ou a été révoqué ; chaque ouverture
// est tracée (date, empreinte de l'IP, navigateur). Le PDF est servi par un
// lien signé de 10 minutes (jamais d'URL publique permanente).

export async function GET(req: NextRequest, ctx: { params: Promise<{ jeton: string }> }) {
  const { jeton } = await ctx.params;
  if (!jeton || jeton.length < 20) return NextResponse.json({ error: 'Lien invalide', code: 'invalide' }, { status: 404 });
  const { data: l } = await admin.from('liens_documents')
    .select('id, doc_url, titre, animal_nom, expediteur_nom, expire_le, revoque_le, nb_acces')
    .eq('jeton', jeton).maybeSingle();
  if (!l) return NextResponse.json({ error: 'Lien invalide', code: 'invalide' }, { status: 404 });
  if (l.revoque_le) return NextResponse.json({ error: 'Ce lien a été désactivé par la clinique.', code: 'revoque' }, { status: 410 });
  if (new Date(l.expire_le).getTime() < Date.now()) {
    return NextResponse.json({ error: 'Ce lien a expiré. Demandez un nouveau lien à la clinique.', code: 'expire' }, { status: 410 });
  }
  // Affichage de la page (sans ouverture du document) : rien n'est tracé.
  if (req.nextUrl.searchParams.get('info') === '1') {
    return NextResponse.json({ titre: l.titre, animal: l.animal_nom, clinique: l.expediteur_nom, expire_le: l.expire_le },
      { headers: { 'Cache-Control': 'no-store' } });
  }
  const cible = cibleStockage(String(l.doc_url));
  if (!cible) return NextResponse.json({ error: 'Document introuvable', code: 'introuvable' }, { status: 404 });
  const { data: signe, error } = await admin.storage.from(cible.bucket).createSignedUrl(cible.chemin, 600, {
    download: req.nextUrl.searchParams.get('telecharger') === '1' ? `${String(l.titre).replace(/[^\wÀ-ÿ -]/g, '_')}.pdf` : undefined,
  });
  if (error || !signe?.signedUrl) return NextResponse.json({ error: 'Document introuvable', code: 'introuvable' }, { status: 404 });

  // Traçabilité : une ligne par ouverture.
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim();
  await Promise.all([
    admin.from('liens_documents_acces').insert({ lien_id: l.id, ip_hash: ip ? empreinte(ip) : null, navigateur: (req.headers.get('user-agent') ?? '').slice(0, 200) }),
    admin.from('liens_documents').update({ nb_acces: (l.nb_acces ?? 0) + 1, dernier_acces_le: new Date().toISOString() }).eq('id', l.id),
  ]);
  return NextResponse.json({
    titre: l.titre, animal: l.animal_nom, clinique: l.expediteur_nom, expire_le: l.expire_le, url: signe.signedUrl,
  }, { headers: { 'Cache-Control': 'no-store' } });
}
