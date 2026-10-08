import { NextRequest, NextResponse } from 'next/server';
import { requireUser, sanitizeEmailBody } from '@/lib/server-auth';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

// Envoi d'une ordonnance / d'un compte rendu (PDF joint) au propriétaire, y
// compris s'il n'a pas PetsMatch (patient créé par la clinique). Appelant
// authentifié ; textes nettoyés ; pièce jointe PDF uniquement, taille limitée.
const MAX_OCTETS = 4 * 1024 * 1024;

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const clean = sanitizeEmailBody(await req.json().catch(() => ({})), [], req);
  if (clean instanceof NextResponse) return clean;
  const { email, destinataire_nom, expediteur_nom, document_type, animal_nom, fichier_nom, pdf_base64 } = clean as {
    email?: string; destinataire_nom?: string; expediteur_nom?: string; document_type?: string;
    animal_nom?: string; fichier_nom?: string; pdf_base64?: string;
  };

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: 'Adresse e-mail invalide' }, { status: 400 });
  }
  if (!pdf_base64) return NextResponse.json({ error: 'Document manquant' }, { status: 400 });
  const contenu = Buffer.from(pdf_base64, 'base64');
  if (contenu.length === 0 || contenu.length > MAX_OCTETS || contenu.subarray(0, 4).toString() !== '%PDF') {
    return NextResponse.json({ error: 'Document PDF invalide' }, { status: 400 });
  }

  const quoi = document_type === 'ordonnance' ? 'une ordonnance' : 'un compte rendu';
  const titre = document_type === 'ordonnance' ? 'Ordonnance' : 'Compte rendu';
  const pro = expediteur_nom || 'Votre vétérinaire';
  const html = `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:24px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:20px;font-weight:700;margin:0;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.85);font-size:13px;margin:6px 0 0;">${titre}${animal_nom ? ` — ${animal_nom}` : ''}</p>
    </div>
    <div style="padding:28px 32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 14px;">Bonjour${destinataire_nom ? ` <strong>${destinataire_nom}</strong>` : ''},</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 18px;">
        <strong>${pro}</strong> vous transmet ${quoi}${animal_nom ? ` pour <strong>${animal_nom}</strong>` : ''}. Vous le trouverez en pièce jointe (PDF).
      </p>
      <p style="font-size:13px;color:#4B5563;line-height:1.6;margin:0 0 18px;">
        Avec l'application PetsMatch, retrouvez le carnet de santé de votre animal, ses ordonnances et des rappels automatiques (vaccins, traitements).
      </p>
      <div style="text-align:center;margin-bottom:18px;">
        <a href="https://petsmatchapp.com" style="display:inline-block;background:#0C5C6C;color:#ffffff;font-size:14px;font-weight:700;text-decoration:none;padding:11px 28px;border-radius:12px;">Découvrir PetsMatch</a>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">Message envoyé via PetsMatch pour le compte de ${pro}.</p>
    </div>
  </div>
</body></html>`;

  try {
    await mailTransporter.sendMail({
      from: MAIL_FROM,
      to: email,
      subject: `${titre}${animal_nom ? ` — ${animal_nom}` : ''} (${pro})`,
      html,
      attachments: [{
        filename: (fichier_nom || `${titre.toLowerCase().replace(' ', '-')}.pdf`).replace(/[^\w.\-À-ÿ ]/g, '_'),
        content: contenu,
        contentType: 'application/pdf',
      }],
    });
    return NextResponse.json({ success: true });
  } catch (e) {
    console.error('[documents/envoyer-email]', e);
    return NextResponse.json({ error: 'Envoi impossible' }, { status: 500 });
  }
}
