import { NextRequest, NextResponse } from 'next/server';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

// POST /api/app/report-email — envoie TOUJOURS vers la boîte interne
// PetsMatch (petsmatch.contact@gmail.com), jamais vers un destinataire
// fourni par le client : remplace les envois SMTP faits directement depuis
// l'appli (identifiants Gmail auparavant codés en dur dans le binaire,
// donc extractibles par n'importe qui — cf. signalements, inscription pro).
// `uid` sert uniquement de traçabilité (qui a déclenché l'envoi).
export async function POST(req: NextRequest) {
  const { uid, subject, body } = await req.json().catch(() => ({})) as {
    uid?: string; subject?: string; body?: string;
  };
  if (!uid || !subject || !body) {
    return NextResponse.json({ error: 'uid, subject et body requis' }, { status: 400 });
  }

  try {
    await mailTransporter.sendMail({
      from: MAIL_FROM,
      to: 'petsmatch.contact@gmail.com',
      subject,
      text: body,
    });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[app/report-email]', err);
    return NextResponse.json({ error: 'Erreur envoi email' }, { status: 500 });
  }
}
