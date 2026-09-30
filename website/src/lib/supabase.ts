import { createClient } from '@supabase/supabase-js';
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

export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  { accessToken: firebaseAccessToken }
);

// Client des pages ouvertes par LIEN secret (/album, /partage, /suivi,
// /reclamer-animal…) : envoie le token du lien dans l'en-tête `x-pm-token`
// sur TOUTES ses requêtes. Les policies RLS (pm_token_requete) n'ouvrent
// alors que les lignes liées à ce token (la ligne de partage, l'animal,
// l'album…), en plus de ce que l'utilisateur connecté voit déjà.
const clientsLien = new Map<string, typeof supabase>();
export function supabaseLien(token: string): typeof supabase {
  let c = clientsLien.get(token);
  if (!c) {
    c = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { accessToken: firebaseAccessToken, global: { headers: { 'x-pm-token': token } } }
    );
    clientsLien.set(token, c);
  }
  return c;
}
