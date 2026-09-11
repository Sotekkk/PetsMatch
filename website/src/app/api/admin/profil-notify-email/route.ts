import { NextRequest, NextResponse } from 'next/server';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

// Email d'activation / refus d'un profil pro — miroir de
// lib/pages/admin/verification_detail.dart (app) pour que l'admin web
// envoie le même e-mail que l'admin app.
export async function POST(req: NextRequest) {
  const { email, firstname, approved, reason } = await req.json().catch(() => ({})) as {
    email?: string; firstname?: string; approved?: boolean; reason?: string;
  };

  if (!email) {
    return NextResponse.json({ error: 'email requis' }, { status: 400 });
  }

  const name = firstname || 'utilisateur';
  const subject = approved
    ? '✅ Votre compte PetsMatch a été approuvé'
    : "❌ Votre dossier PetsMatch n'a pas été accepté";

  const bodyHtml = approved
    ? `<p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 16px;">
        Bonne nouvelle ! Votre dossier a été examiné et votre compte professionnel PetsMatch est maintenant activé.
      </p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0;">
        Vous pouvez dès à présent vous connecter à l'application et accéder à toutes les fonctionnalités réservées aux éleveurs et professionnels.
      </p>`
    : `<p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 16px;">
        Nous avons examiné votre dossier et nous ne sommes malheureusement pas en mesure de valider votre compte pour la raison suivante :
      </p>
      <p style="font-size:14px;color:#1F2A2E;background:#FFF7ED;border:1px solid #FED7AA;border-radius:10px;padding:12px 16px;margin:0 0 16px;">
        ${reason?.trim() || 'Documents incomplets.'}
      </p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0;">
        Si vous pensez qu'il s'agit d'une erreur ou souhaitez soumettre de nouveaux documents, contactez-nous à support@petsmatch.fr en répondant à cet e-mail.
      </p>`;

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:${approved ? '#0C5C6C' : '#B91C1C'};padding:28px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:22px;font-weight:700;margin:0;letter-spacing:-0.3px;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.8);font-size:13px;margin:6px 0 0;">${approved ? 'Compte activé' : 'Dossier non accepté'}</p>
    </div>
    <div style="padding:32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 16px;">Bonjour <strong>${name}</strong>,</p>
      ${bodyHtml}
    </div>
    <div style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:16px 32px;text-align:center;">
      <p style="font-size:11px;color:#9CA3AF;margin:0;">PetsMatch · petsmatch.contact@gmail.com</p>
    </div>
  </div>
</body>
</html>`;

  try {
    await mailTransporter.sendMail({ from: MAIL_FROM, to: email, subject, html });
    return NextResponse.json({ ok: true });
  } catch (e) {
    console.error('[profil-notify-email]', e);
    return NextResponse.json({ error: 'Envoi e-mail échoué' }, { status: 500 });
  }
}
