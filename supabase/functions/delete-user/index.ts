import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL         = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SERVICE_ACCOUNT      = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ── Firebase Auth JWT ─────────────────────────────────────────────────────────
async function getGoogleAccessToken(): Promise<string> {
  const b64u = (s: string) =>
    btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const now = Math.floor(Date.now() / 1000);
  const header  = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64u(JSON.stringify({
    iss: SERVICE_ACCOUNT.client_email,
    sub: SERVICE_ACCOUNT.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase',
  }));

  const sigInput = `${header}.${payload}`;
  const pkPem = (SERVICE_ACCOUNT.private_key as string)
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '');
  const pkDer = Uint8Array.from(atob(pkPem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', pkDer, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const sigBuf = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(sigInput));
  const sig = b64u(String.fromCharCode(...new Uint8Array(sigBuf)));
  const jwt = `${sigInput}.${sig}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) throw new Error(`OAuth: ${JSON.stringify(tokenData)}`);
  return tokenData.access_token;
}

// ── Supprime les fichiers d'un bucket/préfixe (non récursif) ─────────────────
async function deleteStoragePrefix(
  supa: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
) {
  const { data: files } = await supa.storage.from(bucket).list(prefix, { limit: 1000 });
  if (!files || files.length === 0) return;
  const paths = files
    .filter(f => f.name !== '.emptyFolderPlaceholder')
    .map(f => `${prefix}/${f.name}`);
  if (paths.length > 0) await supa.storage.from(bucket).remove(paths);
}

// ── Main ──────────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const { uid, adminUid } = await req.json() as { uid: string; adminUid: string };
    if (!uid || !adminUid) throw new Error('uid et adminUid requis');

    const supa = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Vérifier que l'appelant est admin
    const { data: admin } = await supa.from('users').select('is_admin').eq('uid', adminUid).single();
    if (!admin?.is_admin) throw new Error('Non autorisé');

    const log: string[] = [];

    // ── 1. Firebase Auth — OBLIGATOIRE en premier ─────────────────────────────
    // Si cette étape échoue (et ce n'est pas USER_NOT_FOUND), on annule tout
    // pour éviter qu'une suppression Supabase partielle bloque la ré-inscription.
    if (!SERVICE_ACCOUNT.project_id) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT non configuré dans les secrets Supabase');
    }
    const accessToken = await getGoogleAccessToken();
    const projectId   = SERVICE_ACCOUNT.project_id as string;
    const fbRes = await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:delete`,
      {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ localId: uid }),
      },
    );
    if (!fbRes.ok) {
      const fbErr = await fbRes.json();
      const msg = fbErr?.error?.message ?? String(fbRes.status);
      if (msg !== 'USER_NOT_FOUND') {
        // Échec critique : on n'efface rien dans Supabase pour ne pas bloquer l'email
        throw new Error(`Firebase Auth: ${msg}`);
      }
      log.push('Firebase Auth: USER_NOT_FOUND (déjà supprimé, ignoré)');
    } else {
      log.push('Firebase Auth: supprimé');
    }

    // ── 2. Supabase — tables sans CASCADE (supprimer avant users) ─────────────
    const explicitDeletes: Array<[string, string, string]> = [
      // [table, colonne, valeur]
      ['cessions',             'uid_eleveur',   uid],
      ['cessions',             'acheteur_uid',  uid],
      ['documents_animaux',    'uid_eleveur',   uid],
      ['signalements',         'reporter_uid',  uid],
      ['plan_templates',       'uid_eleveur',   uid],
      ['plans_actifs',         'uid_eleveur',   uid],
      ['plan_taches',          'uid_eleveur',   uid],
      ['inventaire_items',     'uid_eleveur',   uid],
      ['inventaire_mouvements','uid_eleveur',   uid],
    ];

    for (const [table, col, val] of explicitDeletes) {
      const { error } = await supa.from(table).delete().eq(col, val);
      if (error && !error.message.includes('does not exist')) {
        log.push(`${table}.${col}: ${error.message}`);
      }
    }

    // ── 3. Storage — media + documents ────────────────────────────────────────
    const mediaPrefixes = [
      `avatars/${uid}`,
      `annonces/${uid}`,
      `animaux/${uid}`,
      `posts/${uid}`,
      uid, // catch-all si des fichiers sont à la racine du uid
    ];
    for (const prefix of mediaPrefixes) {
      try { await deleteStoragePrefix(supa, 'media', prefix); } catch { /* dossier inexistant */ }
    }
    // Sous-dossiers connus dans annonces (photos bébés)
    try { await deleteStoragePrefix(supa, 'media', `annonces/${uid}/bebes`); } catch { /* */ }

    const docPrefixes = [`${uid}`, `documents/${uid}`];
    for (const prefix of docPrefixes) {
      try { await deleteStoragePrefix(supa, 'documents', prefix); } catch { /* */ }
    }
    log.push('Storage: nettoyé');

    // ── 4. Supabase users — CASCADE supprime le reste ─────────────────────────
    const { error: supaErr } = await supa.from('users').delete().eq('uid', uid);
    if (supaErr) throw new Error(`Supabase users: ${supaErr.message}`);
    log.push('Supabase: supprimé');

    return new Response(
      JSON.stringify({ success: true, log }),
      { headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ success: false, error: String(e) }),
      { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});
