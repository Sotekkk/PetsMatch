import { auth } from '@/lib/firebase';

/**
 * fetch() vers les routes /api du site en joignant le jeton d'ID Firebase de
 * l'utilisateur connecté (`Authorization: Bearer …`). Les routes serveur en
 * déduisent l'identité de l'appelant (lib/server-auth.ts) — plus jamais d'uid
 * « de confiance » passé dans le corps ou l'URL.
 */
export async function apiFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  // Au chargement d'une page (retour Stripe, fiche admin…), Firebase n'a pas
  // encore restauré la session : sans cette attente, l'appel partait sans
  // jeton → « Non authentifié ».
  await auth.authStateReady();
  const user = auth.currentUser;
  if (user) headers.set('Authorization', `Bearer ${await user.getIdToken()}`);
  return fetch(input, { ...init, headers });
}
