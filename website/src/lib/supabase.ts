import { createClient } from '@supabase/supabase-js';
import { allegerEnvoi, cheminStockage } from '@/lib/alleger-envoi';
import { auth } from '@/lib/firebase';

// Le token Firebase est transmis à chaque requête (Third-Party Auth Firebase
// configuré côté Supabase) pour que auth.uid() reflète le vrai uid connecté
// côté Postgres, plutôt que le contournement USING(true) utilisé jusqu'ici
// faute d'identité côté DB. Sans session Firebase active (routes API
// serveur, ou visiteur non connecté), la fonction renvoie undefined et le
// comportement reste identique à aujourd'hui (anon key seule).
const firebaseAccessToken = async () => {
  try {
    return (await auth.currentUser?.getIdToken()) ?? null;
  } catch {
    return null;
  }
};

// Tous les envois vers le stockage passent par allegerEnvoi (photos réduites,
// documents / vidéos trop lourds refusés) — voir lib/alleger-envoi.ts.
function brancherAllegement<C extends { storage: ReturnType<typeof createClient>['storage'] }>(client: C): C {
  const from = client.storage.from.bind(client.storage);
  client.storage.from = ((bucket: string) => {
    const api = from(bucket);
    const upload = api.upload.bind(api);
    api.upload = (async (path, body, options) => {
      const r = await allegerEnvoi(bucket, body);
      // Même forme qu'un refus du serveur : les pages affichent error.message.
      if (!r.ok) return { data: null, error: Object.assign(new Error(r.message), { __isStorageError: true }) } as unknown as Awaited<ReturnType<typeof upload>>;
      return upload(cheminStockage(path), r.body as typeof body, r.jpeg ? { ...options, contentType: 'image/jpeg' } : options);
    }) as typeof api.upload;
    // Même chemin nettoyé à la lecture qu'à l'envoi (noms de fichier accentués).
    const getPublicUrl = api.getPublicUrl.bind(api);
    api.getPublicUrl = ((path: string, opts?: Parameters<typeof getPublicUrl>[1]) =>
      getPublicUrl(cheminStockage(path), opts)) as typeof api.getPublicUrl;
    const createSignedUrl = api.createSignedUrl.bind(api);
    api.createSignedUrl = ((path: string, expiresIn: number, opts?: Parameters<typeof createSignedUrl>[2]) =>
      createSignedUrl(cheminStockage(path), expiresIn, opts)) as typeof api.createSignedUrl;
    return api;
  }) as typeof client.storage.from;
  return client;
}

export const supabase = brancherAllegement(createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  { accessToken: firebaseAccessToken }
));

// Temps réel : le jeton n'était lu qu'à la connexion du canal, souvent avant que
// Firebase ait restauré la session → canal anonyme, les règles d'accès masquaient
// messages et conversations (rien en direct). Relu à chaque connexion /
// renouvellement du jeton Firebase.
if (typeof window !== 'undefined') {
  auth.onIdTokenChanged(() => { supabase.realtime.setAuth().catch(() => {}); });
}

// Client des pages ouvertes par LIEN secret (/album, /partage, /suivi,
// /reclamer-animal…) : envoie le token du lien dans l'en-tête `x-pm-token`
// sur TOUTES ses requêtes. Les policies RLS (pm_token_requete) n'ouvrent
// alors que les lignes liées à ce token (la ligne de partage, l'animal,
// l'album…), en plus de ce que l'utilisateur connecté voit déjà.
const clientsLien = new Map<string, typeof supabase>();
export function supabaseLien(token: string): typeof supabase {
  let c = clientsLien.get(token);
  if (!c) {
    c = brancherAllegement(createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { accessToken: firebaseAccessToken, global: { headers: { 'x-pm-token': token } } }
    ));
    clientsLien.set(token, c);
  }
  return c;
}
