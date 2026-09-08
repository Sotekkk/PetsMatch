import { NextRequest, NextResponse } from 'next/server';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { pseudo, instagram, tiktok, autre, message, preuves } = body as {
      pseudo?: string;
      instagram?: string;
      tiktok?: string;
      autre?: string;
      message?: string;
      preuves?: string[];
    };

    const linksHtml = [
      instagram ? `<li>Instagram : <a href="${instagram}">${instagram}</a></li>` : '',
      tiktok    ? `<li>TikTok : <a href="${tiktok}">${tiktok}</a></li>` : '',
      autre     ? `<li>Autre : <a href="${autre}">${autre}</a></li>` : '',
    ].filter(Boolean).join('');

    const preuvesHtml = (preuves ?? []).map((url) =>
      `<a href="${url}"><img src="${url}" style="max-width:200px;max-height:200px;border-radius:8px;margin:4px;" /></a>`
    ).join('');

    const html = `
      <div style="font-family:sans-serif;max-width:600px;margin:auto;">
        <h2 style="color:#7C3AED;">⭐ Nouvelle demande de badge Influenceur</h2>
        <p><strong>Pseudo :</strong> ${pseudo ?? 'Non renseigné'}</p>
        <h3>Liens</h3>
        <ul>${linksHtml || '<li>Aucun lien fourni</li>'}</ul>
        <h3>Message de motivation</h3>
        <p style="background:#f5f5f5;padding:12px;border-radius:8px;">${message ?? '—'}</p>
        ${preuvesHtml ? `<h3>Captures d'écran</h3><div>${preuvesHtml}</div>` : ''}
        <hr/>
        <p style="color:#888;font-size:12px;">Validez ou refusez la demande depuis le <strong>panel admin PetsMatch → Influenceurs</strong>.</p>
      </div>
    `;

    await mailTransporter.sendMail({
      from: MAIL_FROM,
      to: 'contact@petsmatchapp.com',
      subject: `[PetsMatch] Demande badge Influenceur — ${pseudo ?? 'Utilisateur'}`,
      html,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error('influencer notify-email error', err);
    return NextResponse.json({ error: String(err) }, { status: 500 });
  }
}
