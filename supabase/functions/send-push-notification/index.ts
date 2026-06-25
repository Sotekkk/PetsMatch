import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Secrets requis dans Supabase Dashboard → Project Settings → Edge Functions → Secrets :
//   SUPABASE_URL             (auto-injecté)
//   SUPABASE_SERVICE_ROLE_KEY (auto-injecté)
//   FIREBASE_SERVICE_ACCOUNT  (coller le JSON complet du service account Firebase)

const SUPABASE_URL         = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SERVICE_ACCOUNT      = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ─── JWT signé pour l'API FCM HTTP v1 ─────────────────────────────────────────
async function getFcmAccessToken(): Promise<string> {
  const b64u = (s: string) =>
    btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const now     = Math.floor(Date.now() / 1000);
  const header  = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64u(JSON.stringify({
    iss:   SERVICE_ACCOUNT.client_email,
    sub:   SERVICE_ACCOUNT.client_email,
    aud:   'https://oauth2.googleapis.com/token',
    iat:   now,
    exp:   now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }));

  const sigInput = `${header}.${payload}`;
  const pkPem    = (SERVICE_ACCOUNT.private_key as string)
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '');
  const pkDer = Uint8Array.from(atob(pkPem), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    'pkcs8', pkDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );
  const sigBuf = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(sigInput));
  const sig = b64u(String.fromCharCode(...new Uint8Array(sigBuf)));
  const jwt = `${sigInput}.${sig}`;

  const res  = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) throw new Error(`OAuth: ${JSON.stringify(data)}`);
  return data.access_token;
}

// ─── Main handler (appelé par Database Webhook sur INSERT notifications) ───────
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const body = await req.json();

    // Payload Supabase Database Webhook : { type, table, record, old_record }
    const record = body?.record ?? body;
    const { uid, title, body: notifBody, data, recipient_profile_id } = record as {
      uid: string; title: string; body: string; data: Record<string, unknown>;
      recipient_profile_id?: string;
    };

    if (!uid || !title) {
      return new Response(JSON.stringify({ skipped: 'missing uid or title' }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
    }

    const supa = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Résoudre le nom du profil destinataire si présent
    let profileSuffix = '';
    let profileName   = '';
    let profileType   = '';
    if (recipient_profile_id) {
      const { data: profileRow } = await supa
        .from('user_profiles')
        .select('profile_name, profile_type')
        .eq('id', recipient_profile_id)
        .maybeSingle();
      if (profileRow) {
        profileName = (profileRow as { profile_name: string; profile_type: string }).profile_name ?? '';
        profileType = (profileRow as { profile_name: string; profile_type: string }).profile_type ?? '';
        if (profileName) profileSuffix = ` → ${profileName}`;
      }
    }

    // Récupérer le FCM token de l'utilisateur cible
    const { data: userRow } = await supa
      .from('users')
      .select('fcm_token')
      .eq('uid', uid)
      .single();

    const fcmToken = userRow?.fcm_token as string | null;
    if (!fcmToken) {
      return new Response(JSON.stringify({ skipped: 'no fcm_token for user' }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
    }

    const accessToken = await getFcmAccessToken();
    const projectId   = SERVICE_ACCOUNT.project_id as string;

    // Convertir les valeurs data en string (FCM exige tout en string)
    const dataStr: Record<string, string> = {};
    if (data && typeof data === 'object') {
      for (const [k, v] of Object.entries(data)) {
        dataStr[k] = v != null ? String(v) : '';
      }
    }
    // Injecter le profil destinataire dans le payload FCM (utilisé pour le switch automatique)
    if (recipient_profile_id) dataStr['recipient_profile_id'] = recipient_profile_id;
    if (profileName)          dataStr['recipient_profile_name'] = profileName;
    if (profileType)          dataStr['recipient_profile_type'] = profileType;

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body: (notifBody ?? '') + profileSuffix },
            data: dataStr,
            android: {
              priority: 'high',
              notification: {
                channel_id: 'high_importance_channel',
                sound: 'default',
              },
            },
          },
        }),
      },
    );

    const fcmData = await fcmRes.json();
    if (!fcmRes.ok) throw new Error(`FCM: ${JSON.stringify(fcmData)}`);

    return new Response(
      JSON.stringify({ success: true, messageId: fcmData.name }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});
