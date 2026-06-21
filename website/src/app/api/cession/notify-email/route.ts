import { NextRequest, NextResponse } from 'next/server';
import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: { user: 'petsmatch.contact@gmail.com', pass: 'dppu ctgp buve bxjd' },
});

export async function POST(req: NextRequest) {
  const { email, nom_acquereur, animal_nom, eleveur_nom, signing_url, prix, date_cession } =
    await req.json().catch(() => ({})) as {
      email: string;
      nom_acquereur: string;
      animal_nom: string;
      eleveur_nom: string;
      signing_url: string;
      prix?: string;
      date_cession?: string;
    };

  if (!email || !signing_url) {
    return NextResponse.json({ error: 'email et signing_url requis' }, { status: 400 });
  }

  const dateStr = date_cession
    ? new Date(date_cession).toLocaleDateString('fr-FR', { dateStyle: 'long' })
    : new Date().toLocaleDateString('fr-FR', { dateStyle: 'long' });

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <!-- Header -->
    <div style="background:#0C5C6C;padding:28px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:22px;font-weight:700;margin:0;letter-spacing:-0.3px;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.8);font-size:13px;margin:6px 0 0;">Votre signature est requise</p>
    </div>

    <!-- Corps -->
    <div style="padding:32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 16px;">Bonjour <strong>${nom_acquereur}</strong>,</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 24px;">
        <strong>${eleveur_nom}</strong> souhaite vous céder <strong>${animal_nom}</strong>
        ${prix ? ` pour <strong>${prix} €</strong>` : ''} le ${dateStr}.<br/>
        Veuillez signer le contrat de cession en cliquant sur le bouton ci-dessous.
      </p>

      <!-- Récap -->
      <div style="background:#F0F9FF;border:1px solid #BAE6FD;border-radius:12px;padding:16px;margin-bottom:24px;">
        <table style="width:100%;border-collapse:collapse;font-size:13px;">
          <tr>
            <td style="color:#6B7280;padding:4px 0;">Animal</td>
            <td style="color:#1F2A2E;font-weight:600;text-align:right;">${animal_nom}</td>
          </tr>
          <tr>
            <td style="color:#6B7280;padding:4px 0;">Éleveur / Cédant</td>
            <td style="color:#1F2A2E;font-weight:600;text-align:right;">${eleveur_nom}</td>
          </tr>
          ${prix ? `<tr>
            <td style="color:#6B7280;padding:4px 0;">Prix</td>
            <td style="color:#1F2A2E;font-weight:600;text-align:right;">${prix} €</td>
          </tr>` : ''}
          <tr>
            <td style="color:#6B7280;padding:4px 0;">Date de cession</td>
            <td style="color:#1F2A2E;font-weight:600;text-align:right;">${dateStr}</td>
          </tr>
        </table>
      </div>

      <!-- CTA -->
      <div style="text-align:center;margin-bottom:28px;">
        <a href="${signing_url}"
          style="display:inline-block;background:#6E9E57;color:#ffffff;font-size:15px;font-weight:700;
                 text-decoration:none;padding:14px 36px;border-radius:12px;letter-spacing:0.2px;">
          ✍️ Signer le contrat
        </a>
      </div>

      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">
        Lien valable tant que la cession est en attente.<br/>
        Si vous ne connaissez pas cet éleveur, ignorez cet email.
      </p>
    </div>

    <!-- Footer -->
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
    await transporter.sendMail({
      from: '"PetsMatch" <petsmatch.contact@gmail.com>',
      to: email,
      subject: `✍️ Signature requise — ${animal_nom} · PetsMatch`,
      html,
    });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[cession/notify-email]', err);
    return NextResponse.json({ error: 'Erreur envoi email' }, { status: 500 });
  }
}
