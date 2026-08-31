import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

// Secrets à configurer dans Supabase Dashboard → Project Settings → Edge Functions → Secrets :
//   RESEND_API_KEY   — clé API Resend (https://resend.com)
//   ADMIN_EMAIL      — email admin (ex: nabil35830@gmail.com)
//   ADMIN_URL        — URL du dashboard admin (ex: https://petsmatch.fr/admin)

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const ADMIN_EMAIL    = Deno.env.get('ADMIN_EMAIL') ?? 'nabil35830@gmail.com';
const ADMIN_URL      = Deno.env.get('ADMIN_URL') ?? 'https://petsmatch.fr/admin';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const body = await req.json();

    // Payload Supabase Database Webhook : { type, table, record, old_record }
    const record = body?.record ?? body;
    const { conversation_id, reported_by_uid, reason, details } = record as {
      conversation_id: string;
      reported_by_uid: string;
      reason: string;
      details?: string;
    };

    if (!conversation_id || !reason) {
      return new Response(JSON.stringify({ skipped: 'missing fields' }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
    }

    if (!RESEND_API_KEY) {
      return new Response(JSON.stringify({ skipped: 'RESEND_API_KEY not configured' }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
    }

    const dateStr = new Date().toLocaleString('fr-FR', {
      timeZone: 'Europe/Paris',
      day: '2-digit', month: 'long', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });

    const html = `
<!DOCTYPE html>
<html>
<body style="font-family: 'Helvetica Neue', Arial, sans-serif; background: #F4F6F8; margin: 0; padding: 0;">
  <div style="max-width: 560px; margin: 32px auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.08);">
    <div style="background: #0C5C6C; padding: 24px 28px; display: flex; align-items: center; gap: 12px;">
      <span style="font-size: 24px;">🚨</span>
      <div>
        <h1 style="margin: 0; color: white; font-size: 18px; font-weight: 700;">Conversation signalée</h1>
        <p style="margin: 4px 0 0; color: rgba(255,255,255,0.75); font-size: 13px;">PetsMatch — Alerte modération</p>
      </div>
    </div>
    <div style="padding: 24px 28px; space-y: 16px;">
      <table style="width: 100%; border-collapse: collapse;">
        <tr>
          <td style="padding: 8px 0; color: #6B7280; font-size: 13px; width: 160px;">Conversation ID</td>
          <td style="padding: 8px 0; color: #1F2A2E; font-size: 13px; font-family: monospace;">${conversation_id}</td>
        </tr>
        <tr style="background: #F9FAFB;">
          <td style="padding: 8px 6px; color: #6B7280; font-size: 13px;">Signalé par (UID)</td>
          <td style="padding: 8px 6px; color: #1F2A2E; font-size: 13px; font-family: monospace;">${reported_by_uid}</td>
        </tr>
        <tr>
          <td style="padding: 8px 0; color: #6B7280; font-size: 13px;">Raison</td>
          <td style="padding: 8px 0;">
            <span style="background: #fee2e2; color: #dc2626; font-size: 12px; font-weight: 600; padding: 3px 10px; border-radius: 999px;">${reason}</span>
          </td>
        </tr>
        ${details ? `
        <tr style="background: #F9FAFB;">
          <td style="padding: 8px 6px; color: #6B7280; font-size: 13px; vertical-align: top;">Détails</td>
          <td style="padding: 8px 6px; color: #1F2A2E; font-size: 13px;">${details}</td>
        </tr>
        ` : ''}
        <tr>
          <td style="padding: 8px 0; color: #6B7280; font-size: 13px;">Date</td>
          <td style="padding: 8px 0; color: #1F2A2E; font-size: 13px;">${dateStr}</td>
        </tr>
      </table>
      <div style="margin-top: 24px; text-align: center;">
        <a href="${ADMIN_URL}"
          style="display: inline-block; background: #0C5C6C; color: white; text-decoration: none;
                 padding: 12px 28px; border-radius: 12px; font-size: 14px; font-weight: 600;">
          Voir le dashboard admin →
        </a>
      </div>
    </div>
  </div>
</body>
</html>`;

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'PetsMatch <admin@petsmatch.fr>',
        to: [ADMIN_EMAIL],
        subject: `🚨 Conversation signalée — ${reason}`,
        html,
      }),
    });

    const data = await res.json();
    if (!res.ok) throw new Error(`Resend: ${JSON.stringify(data)}`);

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});
