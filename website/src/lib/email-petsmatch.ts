// E-mails transactionnels PetsMatch envoyés par le serveur (gabarit commun :
// bandeau, texte, bouton, mention de bas de page). Les textes fournis par
// les utilisateurs sont échappés. Envoi via le transporteur du site (mailer.ts).
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL || 'https://petsmatchapp.com').replace(/\/$/, '');

export const echapperHtml = (t: string) => t.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string));

export const emailValide = (e: string | null | undefined) => !!e && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e.trim());

/** Gabarit : `paragraphes` en HTML déjà échappé (utiliser echapperHtml). */
export function gabaritEmail({ sousTitre, salutation, paragraphes, bouton, alerte, pied }: {
  sousTitre: string; salutation?: string; paragraphes: string[];
  bouton?: { label: string; url: string }; alerte?: string; pied?: string;
}) {
  return `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
<div style="max-width:580px;margin:32px auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
  <div style="background:#0C5C6C;padding:26px 32px;text-align:center;">
    <p style="color:#fff;font-size:22px;font-weight:700;margin:0;">PetsMatch</p>
    <p style="color:rgba(255,255,255,0.85);font-size:13px;margin:6px 0 0;">${echapperHtml(sousTitre)}</p>
  </div>
  <div style="padding:30px 32px;">
    ${salutation ? `<p style="font-size:15px;color:#1F2A2E;margin:0 0 16px;">${salutation}</p>` : ''}
    ${paragraphes.map(p => `<p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 14px;">${p}</p>`).join('')}
    ${alerte ? `<p style="font-size:14px;color:#B3261E;background:#FDECEA;border-radius:10px;padding:12px 14px;line-height:1.5;margin:6px 0 18px;">${alerte}</p>` : ''}
    ${bouton ? `<div style="text-align:center;margin:22px 0 10px;"><a href="${bouton.url}" style="display:inline-block;background:#0C5C6C;color:#fff;font-size:15px;font-weight:700;text-decoration:none;padding:14px 34px;border-radius:12px;">${echapperHtml(bouton.label)}</a></div>
    <p style="font-size:11px;color:#9CA3AF;text-align:center;margin:0;word-break:break-all;">${bouton.url}</p>` : ''}
  </div>
  <div style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:14px 32px;text-align:center;">
    <p style="font-size:11px;color:#9CA3AF;margin:0;">${pied ?? 'Si vous ne connaissez pas ce professionnel, ignorez cet e-mail.'}<br/>PetsMatch · petsmatch.contact@gmail.com</p>
  </div>
</div></body></html>`;
}

export async function envoyerEmail(to: string, sujet: string, html: string, pieces: { filename: string; content: Buffer }[] = []) {
  await mailTransporter.sendMail({ from: MAIL_FROM, to, subject: sujet, html, attachments: pieces });
}
