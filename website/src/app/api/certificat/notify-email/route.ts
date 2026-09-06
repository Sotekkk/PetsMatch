import { NextRequest, NextResponse } from 'next/server';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

export async function POST(req: NextRequest) {
  const { email, animal_nom, signing_url } =
    await req.json().catch(() => ({})) as {
      email: string;
      animal_nom?: string;
      signing_url: string;
    };

  if (!email || !signing_url) {
    return NextResponse.json({ error: 'email et signing_url requis' }, { status: 400 });
  }

  const animal = animal_nom || 'votre futur animal';

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:28px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:22px;font-weight:700;margin:0;letter-spacing:-0.3px;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.8);font-size:13px;margin:6px 0 0;">Certificat d'engagement et de connaissance</p>
    </div>
    <div style="padding:32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 16px;">Bonjour,</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 24px;">
        Avant l'arrivée de <strong>${animal}</strong>, le cédant vous transmet le
        <strong>certificat d'engagement et de connaissance</strong> (obligatoire pour les chiens et
        les chats, loi n° 2021-1539).<br/><br/>
        Prenez le temps de le lire : il décrit les besoins de l'animal et vos engagements.
        Vous pourrez ensuite le signer en ligne.
      </p>
      <div style="text-align:center;margin-bottom:28px;">
        <a href="${signing_url}"
          style="display:inline-block;background:#6E9E57;color:#ffffff;font-size:15px;font-weight:700;
                 text-decoration:none;padding:14px 36px;border-radius:12px;letter-spacing:0.2px;">
          📋 Lire et signer le certificat
        </a>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">
        Pour les chiens et chats, un délai de réflexion de 7 jours s'applique avant la signature.<br/>
        Créez un compte PetsMatch pour retrouver le carnet de santé et le suivi de votre animal.
      </p>
    </div>
    <div style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:16px 32px;text-align:center;">
      <p style="font-size:11px;color:#9CA3AF;margin:0;">
        PetsMatch · petsmatch.contact@gmail.com<br/>
        Lien direct : <a href="${signing_url}" style="color:#0C5C6C;">${signing_url}</a>
      </p>
    </div>
  </div>
</body>
</html>`;

  try {
    await mailTransporter.sendMail({
      from: MAIL_FROM,
      to: email,
      subject: `✍️ Certificat d'engagement à signer — ${animal} · PetsMatch`,
      html,
    });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[certificat/notify-email]', err);
    return NextResponse.json({ error: 'Erreur envoi email' }, { status: 500 });
  }
}
