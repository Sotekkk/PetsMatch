import { auth } from '@/lib/firebase';

/**
 * fetch() vers les routes /api du site en joignant le jeton d'ID Firebase de
 * l'utilisateur connecté (`Authorization: Bearer …`). Les routes serveur en
 * déduisent l'identité de l'appelant (lib/server-auth.ts) — plus jamais d'uid
 * « de confiance » passé dans le corps ou l'URL.
 */
export async function apiFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  const user = auth.currentUser;
  if (user) headers.set('Authorization', `Bearer ${await user.getIdToken()}`);
  return fetch(input, { ...init, headers });
}
