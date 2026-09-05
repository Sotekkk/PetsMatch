import { NextRequest, NextResponse } from 'next/server';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

// Rappel de RDV pour un client SANS compte PetsMatch (client_email_manuel).
// Appelé par functions/rdv_reminders.js (24h / 30min avant).
export async function POST(req: NextRequest) {
  const { email, client_nom, pro_nom, date_heure, motif, duree_minutes, lieu, echeance } =
    await req.json().catch(() => ({})) as {
      email: string;
      client_nom?: string;
      pro_nom?: string;
      date_heure: string;
      motif?: string | null;
      duree_minutes?: number | null;
      lieu?: string | null;
      echeance?: string;
    };

  if (!email || !date_heure) {
    return NextResponse.json({ error: 'email et date_heure requis' }, { status: 400 });
  }

  const d = new Date(date_heure);
  const dateStr = d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
  const heureStr = d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  const pro = pro_nom || 'Le professionnel';
  const quand = echeance === '30min' ? 'dans 30 minutes' : echeance === '1h' ? 'dans 1 heure' : 'demain';
  const dureeStr = duree_minutes
    ? (duree_minutes < 60 ? `${duree_minutes} min` : `${Math.floor(duree_minutes / 60)} h${duree_minutes % 60 ? ` ${duree_minutes % 60}` : ''}`)
    : null;

  const row = (label: string, value: string) => `<tr>
    <td style="color:#6B7280;padding:4px 0;">${label}</td>
    <td style="color:#1F2A2E;font-weight:600;text-align:right;">${value}</td>
  </tr>`;

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:28px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:22px;font-weight:700;margin:0;letter-spacing:-0.3px;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.8);font-size:13px;margin:6px 0 0;">Rappel de rendez-vous</p>
    </div>
    <div style="padding:32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 16px;">Bonjour${client_nom ? ` <strong>${client_nom}</strong>` : ''},</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 24px;">
        Petit rappel : votre rendez-vous avec <strong>${pro}</strong> a lieu <strong>${quand}</strong>.
      </p>
      <div style="background:#F0F9FF;border:1px solid #BAE6FD;border-radius:12px;padding:16px;margin-bottom:24px;">
        <table style="width:100%;border-collapse:collapse;font-size:13px;">
          ${row('Professionnel', pro)}
          ${row('Date', dateStr)}
          ${row('Heure', heureStr)}
          ${motif ? row('Motif', motif) : ''}
          ${dureeStr ? row('Durée', dureeStr) : ''}
          ${lieu ? row('Lieu', lieu) : ''}
        </table>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">
        Besoin de modifier ou d'annuler ? Créez votre compte sur
        <a href="https://petsmatchapp.com" style="color:#0C5C6C;">petsmatchapp.com</a> ou contactez directement le professionnel.
      </p>
    </div>
    <div style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:16px 32px;text-align:center;">
      <p style="font-size:11px;color:#9CA3AF;margin:0;">PetsMatch · petsmatch.contact@gmail.com</p>
    </div>
  </div>
</body>
</html>`;

  try {
    await mailTransporter.sendMail({
      from: MAIL_FROM,
      to: email,
      subject: `⏰ Rappel — RDV ${quand} avec ${pro} · PetsMatch`,
      html,
    });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[rdv/reminder-email]', err);
    return NextResponse.json({ error: 'Erreur envoi email' }, { status: 500 });
  }
}
