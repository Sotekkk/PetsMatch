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

/** Échappe une valeur fournie par l'appelant avant insertion dans un e-mail HTML. */
export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
