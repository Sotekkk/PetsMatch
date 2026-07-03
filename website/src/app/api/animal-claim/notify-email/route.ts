import { NextRequest, NextResponse } from 'next/server';
import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: { user: 'petsmatch.contact@gmail.com', pass: 'dppu ctgp buve bxjd' },
});

export async function POST(req: NextRequest) {
  const { email, nom_destinataire, animal_nom, pro_nom, claim_url } =
    await req.json().catch(() => ({})) as {
      email: string;
      nom_destinataire?: string;
      animal_nom: string;
      pro_nom: string;
      claim_url: string;
    };

  if (!email || !claim_url) {
    return NextResponse.json({ error: 'email et claim_url requis' }, { status: 400 });
  }

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:28px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:22px;font-weight:700;margin:0;letter-spacing:-0.3px;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.8);font-size:13px;margin:6px 0 0;">La fiche de votre animal vous attend</p>
    </div>
    <div style="padding:32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 16px;">Bonjour${nom_destinataire ? ` <strong>${nom_destinataire}</strong>` : ''},</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 24px;">
        <strong>${pro_nom}</strong> a créé une fiche PetsMatch pour <strong>${animal_nom}</strong> pendant son séjour.
        Récupérez-la pour suivre son carnet de santé, ses séjours et recevoir des nouvelles pendant qu'il est en pension.
      </p>
      <div style="text-align:center;margin-bottom:28px;">
        <a href="${claim_url}"
          style="display:inline-block;background:#6E9E57;color:#ffffff;font-size:15px;font-weight:700;
                 text-decoration:none;padding:14px 36px;border-radius:12px;letter-spacing:0.2px;">
          🐾 Récupérer la fiche de ${animal_nom}
        </a>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">
        Si vous n'avez pas encore de compte PetsMatch, vous pourrez en créer un en un clic.<br/>
        Si vous ne reconnaissez pas cette demande, ignorez cet email.
      </p>
    </div>
    <div style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:16px 32px;text-align:center;">
      <p style="font-size:11px;color:#9CA3AF;margin:0;">
        PetsMatch · petsmatch.contact@gmail.com<br/>
        Lien direct : <a href="${claim_url}" style="color:#0C5C6C;">${claim_url}</a>
      </p>
    </div>
  </div>
</body>
</html>`;

  try {
    await transporter.sendMail({
      from: '"PetsMatch" <petsmatch.contact@gmail.com>',
      to: email,
      subject: `🐾 La fiche de ${animal_nom} vous attend · PetsMatch`,
      html,
    });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[animal-claim/notify-email]', err);
    return NextResponse.json({ error: 'Erreur envoi email' }, { status: 500 });
  }
}
