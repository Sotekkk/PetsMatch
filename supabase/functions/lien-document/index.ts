// lien-document : lien temporaire (10 min) vers un document du stockage
// privé (bucket `documents`).
//
// Entrée : POST { url } — le lien tel qu'il est enregistré en base.
// Accès accordé si l'appelant :
//   • a déposé le fichier (owner_id du stockage = son uid) ;
//   • est admin ;
//   • ou VOIT, avec ses propres droits (RLS + vues masquées), une fiche qui
//     référence exactement ce lien (ordonnance, cession, profil, message…).
//     Les règles d'accès restent donc celles des tables : propriétaire,
//     co-propriétaire, véto, employé / cogérant scopés au profil, acquéreur
//     par lien secret (en-tête x-pm-token transmis tel quel).
// Les liens d'autres stockages (Firebase avec jeton, buckets publics) sont
// renvoyés tels quels.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createRemoteJWKSet, jwtVerify } from 'https://esm.sh/jose@5.9.6';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('PM_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PUBLIC_KEY   = Deno.env.get('PM_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!;
const FIREBASE_PROJECT = Deno.env.get('FIREBASE_PROJECT_ID')
  ?? JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}').project_id
  ?? 'petsmatch-eb96d';
const PRIVES = ['documents', 'contrats'];
const DUREE_S = 600;

// Fiches qui peuvent référencer un document privé : [table ou vue, colonnes].
const REFERENCES: [string, string[]][] = [
  ['ordonnances', ['doc_url']],
  ['comptes_rendus', ['doc_url']],
  ['vet_consultations', ['ordonnance_url']],
  ['radios', ['image_url']],
  ['documents_animaux', ['url', 'pdf_original_url', 'pdf_signe_url']],
  ['cessions', ['contrat_url', 'certificat_url']],
  ['animaux', ['cession_contrat_url', 'cession_certificat_url', 'pedigree_url']],
  ['certificats_engagement', ['pdf_url']],
  ['contrats', ['url']],
  ['factures', ['pdf_url']],
  ['pension_factures', ['pdf_url']],
  ['photographe_factures', ['pdf_url']],
  ['taxi_factures', ['pdf_url']],
  ['toilettage_factures', ['pdf_url']],
  ['education_attestations', ['pdf_url']],
  ['tests_genetiques', ['url']],
  ['messages', ['image_url']],
  ['promenades_messages', ['image_url']],
  ['pension_updates', ['photo_url', 'video_url']],
  ['user_profiles_complet', ['kbis_url', 'acaced_doc_url', 'diplome_url', 'statuts_url', 'arrete_prefectoral_url']],
  ['users_complet', ['kbis_url', 'acaced_doc_url', 'document_elevage']],
];

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-pm-token',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

const FIREBASE_JWKS = createRemoteJWKSet(new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
));
async function appelant(req: Request): Promise<{ uid: string; jeton: string } | null> {
  const m = (req.headers.get('authorization') ?? '').match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  try {
    const { payload } = await jwtVerify(m[1], FIREBASE_JWKS, {
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT}`,
      audience: FIREBASE_PROJECT,
    });
    return typeof payload.sub === 'string' && payload.sub ? { uid: payload.sub, jeton: m[1] } : null;
  } catch {
    return null;
  }
}

// https://<projet>.supabase.co/storage/v1/object/(public|sign|authenticated)/<bucket>/<chemin>[?…]
function analyser(url: string): { bucket: string; chemin: string } | null {
  try {
    const u = new URL(url);
    if (u.origin !== new URL(SUPABASE_URL).origin) return null;
    const m = u.pathname.match(/^\/storage\/v1\/object\/(?:public|sign|authenticated)\/([^/]+)\/(.+)$/);
    return m ? { bucket: m[1], chemin: decodeURIComponent(m[2]) } : null;
  } catch {
    return null;
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'POST attendu' }, 405);

  let url = '';
  try { url = String((await req.json()).url ?? ''); } catch { /* corps invalide */ }
  if (!url) return json({ error: 'url requise' }, 400);

  const cible = analyser(url);
  if (!cible || !PRIVES.includes(cible.bucket)) return json({ url }); // lien public ou externe : inchangé

  const qui = await appelant(req);
  const lienSecret = req.headers.get('x-pm-token');
  if (!qui && !lienSecret) return json({ error: 'Connexion requise' }, 401);

  const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  let autorise = false;
  if (qui) {
    const { data: proprio } = await service.rpc('pm_proprio_fichier', { p_bucket: cible.bucket, p_nom: cible.chemin });
    autorise = proprio === qui.uid;
    if (!autorise) {
      const { data: admin } = await service.rpc('is_admin_uid', { p_uid: qui.uid });
      autorise = admin === true;
    }
  }

  if (!autorise) {
    // Vérification avec les droits de l'appelant : RLS + vues masquées.
    const headers: Record<string, string> = {};
    if (lienSecret) headers['x-pm-token'] = lienSecret;
    const commeLui = createClient(SUPABASE_URL, PUBLIC_KEY, {
      auth: { persistSession: false },
      global: { headers },
      ...(qui ? { accessToken: async () => qui.jeton } : {}),
    });
    const essais = REFERENCES.flatMap(([rel, cols]) => cols.map((col) =>
      commeLui.from(rel).select(col).eq(col, url).limit(1)
        .then(({ data }) => (data?.length ?? 0) > 0, () => false)));
    // Documents de la fiche animal (liste JSON animaux.documents : [{url, nom…}])
    essais.push(commeLui.from('animaux').select('id').contains('documents', [{ url }]).limit(1)
      .then(({ data }) => (data?.length ?? 0) > 0, () => false));
    autorise = (await Promise.all(essais)).some(Boolean);
  }

  if (!autorise) return json({ error: 'Accès refusé' }, 403);

  const { data, error } = await service.storage.from(cible.bucket).createSignedUrl(cible.chemin, DUREE_S);
  if (error || !data?.signedUrl) return json({ error: 'Document introuvable' }, 404);
  return json({ url: data.signedUrl, expire_dans: DUREE_S });
});
