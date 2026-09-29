import { NextRequest, NextResponse } from 'next/server';
import { createRemoteJWKSet, jwtVerify } from 'jose';

// Authentification des routes API côté serveur.
//
// RÈGLE : une route ne doit JAMAIS croire un uid envoyé dans le corps ou l'URL
// de la requête (n'importe qui peut y mettre l'uid de quelqu'un d'autre — les
// uid sont publics, ex. auteur d'un post). L'identité de l'appelant vient
// UNIQUEMENT du jeton d'ID Firebase envoyé dans `Authorization: Bearer <jeton>`
// (côté site : apiFetch() de lib/api-fetch.ts ; côté appli :
// FirebaseAuth.instance.currentUser.getIdToken()).
//
// Vérification locale de la signature avec les clés publiques Google
// (securetoken) + émetteur/audience du projet Firebase : aucun secret requis.

const PROJECT_ID = process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? '';
const JWKS = createRemoteJWKSet(new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
));

/** uid Firebase vérifié de l'appelant, ou null (jeton absent/invalide/expiré). */
export async function verifiedUid(req: NextRequest): Promise<string | null> {
  const m = (req.headers.get('authorization') ?? '').match(/^Bearer\s+(.+)$/i);
  if (!m || !PROJECT_ID) return null;
  try {
    const { payload } = await jwtVerify(m[1], JWKS, {
      issuer: `https://securetoken.google.com/${PROJECT_ID}`,
      audience: PROJECT_ID,
    });
    return typeof payload.sub === 'string' && payload.sub ? payload.sub : null;
  } catch {
    return null;
  }
}

/**
 * Exige un utilisateur connecté. Usage :
 *   const auth = await requireUser(req);
 *   if (auth instanceof NextResponse) return auth;
 *   const uid = auth.uid;
 */
export async function requireUser(req: NextRequest): Promise<{ uid: string } | NextResponse> {
  const uid = await verifiedUid(req);
  if (!uid) return NextResponse.json({ error: 'Non authentifié' }, { status: 401 });
  return { uid };
}

/**
 * Appel autorisé si : utilisateur connecté (jeton Firebase vérifié) OU serveur
 * PetsMatch présentant `x-internal-secret` = INTERNAL_API_SECRET (Cloud
 * Functions, route qui en appelle une autre).
 * `allowIfSecretUnset` : transition pour un appel serveur existant — tant que
 * INTERNAL_API_SECRET n'est pas configuré côté hébergeur, on laisse passer
 * (avec un avertissement) au lieu de casser l'envoi ; dès qu'il l'est, le
 * secret devient obligatoire.
 */
export async function requireUserOrInternal(
  req: NextRequest,
  opts: { allowIfSecretUnset?: boolean } = {},
): Promise<{ uid: string | null } | NextResponse> {
  const secret = process.env.INTERNAL_API_SECRET;
  const given = req.headers.get('x-internal-secret');
  if (secret && given && given === secret) return { uid: null };
  const uid = await verifiedUid(req);
  if (uid) return { uid };
  if (!secret && opts.allowIfSecretUnset) {
    console.warn(`[auth] ${req.nextUrl.pathname} appelé sans authentification — configurer INTERNAL_API_SECRET`);
    return { uid: null };
  }
  return NextResponse.json({ error: 'Non authentifié' }, { status: 401 });
}

/** Lien autorisé dans un e-mail envoyé par PetsMatch : notre site (prod, domaine
 *  configuré, ou l'hôte qui sert la requête) ou le stockage Supabase (PDF).
 *  Empêche d'utiliser nos e-mails pour renvoyer vers un site d'hameçonnage. */
export function isTrustedUrl(url: unknown, req: NextRequest): boolean {
  if (typeof url !== 'string' || !url || /[\s"'<>`]/.test(url)) return false;
  let u: URL;
  try { u = new URL(url); } catch { return false; }
  const hosts = new Set(['petsmatchapp.com', 'www.petsmatchapp.com', req.nextUrl.host]);
  for (const env of [process.env.NEXT_PUBLIC_SITE_URL, process.env.NEXT_PUBLIC_SUPABASE_URL]) {
    try { if (env) hosts.add(new URL(env).host); } catch { /* ignoré */ }
  }
  const localDev = u.hostname === 'localhost' && u.host === req.nextUrl.host;
  return (u.protocol === 'https:' || localDev) && hosts.has(u.host);
}

/**
 * Prépare le corps d'une requête d'e-mail : retire des champs texte les
 * caractères d'injection HTML (< > " `) — sans les convertir en entités, pour
 * garder un objet d'e-mail lisible — et vérifie les champs URL (isTrustedUrl).
 * Retourne une réponse 400 si un lien n'est pas autorisé.
 */
export function sanitizeEmailBody<T extends Record<string, unknown>>(
  body: T, urlFields: string[], req: NextRequest,
): T | NextResponse {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body ?? {})) {
    if (urlFields.includes(k)) {
      if (v == null || v === '') { out[k] = v; continue; }
      if (!isTrustedUrl(v, req)) {
        return NextResponse.json({ error: `Lien non autorisé (${k})` }, { status: 400 });
      }
      out[k] = v;
    } else {
      out[k] = typeof v === 'string' ? v.replace(/[<>"`]/g, '') : v;
    }
  }
  return out as T;
}

/** Échappe une valeur fournie par l'appelant avant insertion dans un e-mail HTML. */
export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
