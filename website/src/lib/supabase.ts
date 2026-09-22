import { createClient } from '@supabase/supabase-js';
import { auth } from '@/lib/firebase';

// Le token Firebase est transmis à chaque requête (Third-Party Auth Firebase
// configuré côté Supabase) pour que auth.uid() reflète le vrai uid connecté
// côté Postgres, plutôt que le contournement USING(true) utilisé jusqu'ici
// faute d'identité côté DB. Sans session Firebase active (routes API
// serveur, ou visiteur non connecté), la fonction renvoie undefined et le
// comportement reste identique à aujourd'hui (anon key seule).
export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  {
    accessToken: async () => {
      try {
        return (await auth.currentUser?.getIdToken()) ?? null;
      } catch {
        return null;
      }
    },
  }
);
