import { NextRequest, NextResponse } from 'next/server';
import { requireUser, sanitizeEmailBody, escapeHtml } from '@/lib/server-auth';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';
import { admin } from '@/lib/galeries-server';
import { SITE_URL } from '@/lib/email-petsmatch';
import { emailProprietaire } from '@/lib/email-proprietaire';
import { accesClinique, cliniqueDuDocument, messageParDefaut, nouveauJeton } from '@/lib/liens-documents-server';

// Liens sécurisés par document (lot 6 des documents vétérinaires).
// POST : crée un lien individuel (7 jours par défaut, 1 à 30), et l'envoie
//        par e-mail si demandé — « envoyé » seulement si le service d'envoi
//        a confirmé ; GET ?url= : liens de ce document (statut, accès).

const TYPES: Record<string, string> = {
  ordonnance: 'Ordonnance', compte_rendu: 'Compte rendu', consignes: 'Consignes après l’intervention',
};

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const clean = sanitizeEmailBody(await req.json().catch(() => ({})), ['url'], req);
  if (clean instanceof NextResponse) return clean;
  const { url, document_type, titre, animal_nom, expediteur_nom, cr_id, envoyer, message, destinataire_nom } = clean as {
    url?: string; document_type?: string; titre?: string; animal_nom?: string; expediteur_nom?: string; cr_id?: string;
    envoyer?: boolean; message?: string; destinataire_nom?: string;
  };
  let { email } = clean as { email?: string };
  const jours = Math.min(30, Math.max(1, Math.round(Number((clean as { jours?: number }).jours) || 7)));
  if (!url || !document_type || !TYPES[document_type]) return NextResponse.json({ error: 'Document invalide' }, { status: 400 });

  const clinique = await cliniqueDuDocument(url, auth.uid, cr_id ?? null);
  if (!clinique || !(await accesClinique(auth.uid, clinique.proUid, clinique.profileId))) {
    return NextResponse.json({ error: 'Accès refusé' }, { status: 403 });
  }

  // Destinataire : adresse saisie (client sans compte) ou celle du compte du propriétaire.
  let nomDest = destinataire_nom ?? '';
  if (envoyer && !email && clinique.animalId) {
    const p = await emailProprietaire(clinique.animalId, auth.uid);
    if (!p) return NextResponse.json({ error: 'Adresse du propriétaire introuvable', code: 'sans_email' }, { status: 404 });
    email = p.email; nomDest = nomDest || p.nom;
  }
  if (envoyer && (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
    return NextResponse.json({ error: 'Adresse e-mail invalide' }, { status: 400 });
  }

  const jeton = nouveauJeton();
  const expire = new Date(Date.now() + jours * 86400000);
  const libelle = titre?.trim() || TYPES[document_type];
  const { data: lien, error } = await admin.from('liens_documents').insert({
    jeton, doc_url: url, document_type, titre: libelle, animal_id: clinique.animalId, animal_nom: animal_nom ?? null,
    pro_uid: clinique.proUid, pro_profile_id: clinique.profileId, expediteur_nom: expediteur_nom ?? null,
    cree_par_uid: auth.uid, destinataire_email: envoyer ? email : null, expire_le: expire.toISOString(),
  }).select('id').single();
  if (error || !lien) return NextResponse.json({ error: 'Lien non créé' }, { status: 500 });
  const adresse = `${SITE_URL}/document/${jeton}`;

  if (!envoyer) return NextResponse.json({ id: lien.id, lien: adresse, expire_le: expire.toISOString(), envoye: false });

  const pro = expediteur_nom || 'Votre vétérinaire';
  const corps = escapeHtml((message?.trim() || messageParDefaut(animal_nom ?? ''))).replace(/\n/g, '<br/>');
  const jourExp = expire.toLocaleDateString('fr-FR', { timeZone: 'Europe/Paris' });
  const html = `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:24px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:18px;font-weight:700;margin:0;">${escapeHtml(pro)}</p>
      <p style="color:rgba(255,255,255,0.85);font-size:13px;margin:6px 0 0;">${escapeHtml(libelle)}${animal_nom ? ` — ${escapeHtml(animal_nom)}` : ''}</p>
    </div>
    <div style="padding:28px 32px;">
      <p style="font-size:14px;color:#374151;line-height:1.6;margin:0 0 20px;">${corps}</p>
      <div style="text-align:center;margin-bottom:16px;">
        <a href="${adresse}" style="display:inline-block;background:#0C5C6C;color:#ffffff;font-size:14px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:12px;">Consulter le document</a>
      </div>
      <p style="font-size:12px;color:#6B7280;text-align:center;margin:0 0 6px;">Lien personnel, valable jusqu’au ${jourExp}. Aucun compte n’est nécessaire.</p>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">Message envoyé via PetsMatch pour le compte de ${escapeHtml(pro)}.</p>
    </div>
  </div>
</body></html>`;
  try {
    await mailTransporter.sendMail({
      from: MAIL_FROM, to: email,
      subject: `Documents vétérinaires${animal_nom ? ` de ${animal_nom}` : ''} (${pro})`,
      html,
    });
  } catch (e) {
    console.error('[liens-documents]', e);
    // Lien créé mais e-mail non parti : on ne prétend pas l'avoir envoyé.
    return NextResponse.json({ id: lien.id, lien: adresse, expire_le: expire.toISOString(), envoye: false, error: 'Envoi impossible' }, { status: 502 });
  }
  return NextResponse.json({ id: lien.id, lien: adresse, expire_le: expire.toISOString(), envoye: true, destinataire: nomDest || null });
}

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const url = req.nextUrl.searchParams.get('url') ?? '';
  const crId = req.nextUrl.searchParams.get('cr_id');
  if (!url && !crId) return NextResponse.json({ liens: [] });
  let q = admin.from('liens_documents')
    .select('id, titre, destinataire_email, expire_le, revoque_le, nb_acces, dernier_acces_le, created_at, pro_uid, pro_profile_id, doc_url')
    .order('created_at', { ascending: false }).limit(20);
  q = url ? q.eq('doc_url', url) : q;
  const { data } = await q;
  const liens = [];
  for (const l of data ?? []) {
    if (await accesClinique(auth.uid, String(l.pro_uid), (l.pro_profile_id as string | null) ?? null)) {
      liens.push({ id: l.id, titre: l.titre, destinataire_email: l.destinataire_email, expire_le: l.expire_le, revoque_le: l.revoque_le,
        nb_acces: l.nb_acces, dernier_acces_le: l.dernier_acces_le, created_at: l.created_at });
    }
  }
  return NextResponse.json({ liens });
}
