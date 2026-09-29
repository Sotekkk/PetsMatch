import { NextRequest, NextResponse } from 'next/server';
import { requireAdmin } from '../_lib/guard';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

// POST /api/admin/notify-email — envoi d'email vers un destinataire arbitraire
// (validation/refus de profil pro, relances d'abonnement), réservé aux admins
// (jeton Firebase requis — l'uid n'est plus lu dans le corps).
// Remplace les envois SMTP faits directement depuis l'appli avec des
// identifiants Gmail codés en dur (extractibles depuis le binaire).
export async function POST(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;
  const { to, subject, body } = await req.json().catch(() => ({})) as {
    to?: string; subject?: string; body?: string;
  };
  if (!to || !subject || !body) {
    return NextResponse.json({ error: 'to, subject et body requis' }, { status: 400 });
  }

  try {
    await mailTransporter.sendMail({ from: MAIL_FROM, to, subject, text: body });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[admin/notify-email]', err);
    return NextResponse.json({ error: 'Erreur envoi email' }, { status: 500 });
  }
}
