import { NextRequest, NextResponse } from 'next/server';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

export async function POST(req: NextRequest) {
  const { email, client_nom, pro_nom, numero_facture, total_ttc, facture_url, pdf_url } =
    await req.json().catch(() => ({})) as {
      email: string;
      client_nom: string;
      pro_nom: string;
      numero_facture?: string;
      total_ttc?: number;
      facture_url: string;
      pdf_url?: string;
    };

  if (!email || !facture_url) {
    return NextResponse.json({ error: 'email et facture_url requis' }, { status: 400 });
  }

  // Pièce jointe PDF si l'appelant fournit une URL (facture pension : PDF déjà
  // généré et stocké). On échoue silencieusement si le téléchargement rate.
  const attachments: { filename: string; content: Buffer }[] = [];
  if (pdf_url) {
    try {
      const res = await fetch(pdf_url);
      if (res.ok) {
        const buf = Buffer.from(await res.arrayBuffer());
        if (buf.length > 0 && buf.length < 15 * 1024 * 1024) {
          attachments.push({ filename: `facture-${numero_facture ?? 'pension'}.pdf`, content: buf });
        }
      }
    } catch { /* pièce jointe optionnelle */ }
  }

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:28px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:22px;font-weight:700;margin:0;letter-spacing:-0.3px;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.8);font-size:13px;margin:6px 0 0;">Votre facture est disponible</p>
    </div>
    <div style="padding:32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 16px;">Bonjour <strong>${client_nom}</strong>,</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 24px;">
        <strong>${pro_nom}</strong> vous a envoyé ${numero_facture ? `la facture <strong>${numero_facture}</strong>` : 'une facture'}${total_ttc ? ` d'un montant de <strong>${total_ttc.toFixed(2)} €</strong>` : ''}.${attachments.length ? ' Le PDF est en pièce jointe.' : ''}
      </p>
      <div style="text-align:center;margin-bottom:28px;">
        <a href="${facture_url}"
          style="display:inline-block;background:#6E9E57;color:#ffffff;font-size:15px;font-weight:700;
                 text-decoration:none;padding:14px 36px;border-radius:12px;letter-spacing:0.2px;">
          🧾 Voir la facture
        </a>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">
        Si vous ne connaissez pas ce professionnel, ignorez cet email.
      </p>
    </div>
    <div style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:16px 32px;text-align:center;">
      <p style="font-size:11px;color:#9CA3AF;margin:0;">
        PetsMatch · petsmatch.contact@gmail.com<br/>
        Lien direct : <a href="${facture_url}" style="color:#0C5C6C;">${facture_url}</a>
      </p>
    </div>
  </div>
</body>
</html>`;

  try {
    await mailTransporter.sendMail({
      from: MAIL_FROM,
      to: email,
      subject: `🧾 Nouvelle facture — ${pro_nom} · PetsMatch`,
      html,
      ...(attachments.length ? { attachments } : {}),
    });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[facture/notify-email]', err);
    return NextResponse.json({ error: 'Erreur envoi email' }, { status: 500 });
  }
}
