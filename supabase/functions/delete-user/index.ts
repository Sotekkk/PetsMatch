import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL        = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// Set this secret in Supabase dashboard → Project Settings → Edge Functions → Secrets
// Key: FIREBASE_SERVICE_ACCOUNT  Value: (paste the full JSON content of your Firebase service account key)
const SERVICE_ACCOUNT = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ─── Create a signed JWT for the Firebase service account ────────────────────
async function getGoogleAccessToken(): Promise<string> {
  const b64u = (s: string) =>
    btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const now = Math.floor(Date.now() / 1000);
  const header  = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64u(JSON.stringify({
    iss:   SERVICE_ACCOUNT.client_email,
    sub:   SERVICE_ACCOUNT.client_email,
    aud:   'https://oauth2.googleapis.com/token',
    iat:   now,
    exp:   now + 3600,
    scope: 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase',
  }));

  const sigInput = `${header}.${payload}`;
  const pkPem = (SERVICE_ACCOUNT.private_key as string)
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
    'RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(sigInput),
  );
  const sig = b64u(String.fromCharCode(...new Uint8Array(sigBuf)));
  const jwt = `${sigInput}.${sig}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) throw new Error(`OAuth error: ${JSON.stringify(tokenData)}`);
  return tokenData.access_token;
}

// ─── Main handler ─────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const { uid, adminUid } = await req.json() as { uid: string; adminUid: string };
    if (!uid || !adminUid) throw new Error('uid et adminUid requis');

    const supa = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Vérifier que l'appelant est bien admin
    const { data: admin } = await supa
      .from('users').select('is_admin').eq('uid', adminUid).single();
    if (!admin?.is_admin) throw new Error('Non autorisé');

    const errors: string[] = [];

    // 1. Supprimer le compte Firebase Authentication
    try {
      const accessToken = await getGoogleAccessToken();
      const projectId   = SERVICE_ACCOUNT.project_id as string;
      const fbRes = await fetch(
        `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:delete`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type':  'application/json',
          },
          body: JSON.stringify({ localId: uid }),
        },
      );
      if (!fbRes.ok) {
        const fbErr = await fbRes.json();
        // USER_NOT_FOUND = déjà supprimé, on ignore
        if (fbErr?.error?.message !== 'USER_NOT_FOUND') {
          errors.push(`Firebase Auth: ${fbErr?.error?.message ?? fbRes.status}`);
        }
      }
    } catch (e) {
      errors.push(`Firebase Auth: ${e}`);
    }

    // 2. Supprimer la ligne users dans Supabase (CASCADE supprime tout le reste)
    const { error: supaErr } = await supa.from('users').delete().eq('uid', uid);
    if (supaErr) errors.push(`Supabase: ${supaErr.message}`);

    return new Response(
      JSON.stringify({ success: errors.length === 0, errors }),
      { headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ success: false, error: String(e) }),
      { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});
