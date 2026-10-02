// « Mettre à jour si la ligne existe, sinon créer » — À UTILISER À LA PLACE
// D'UN UPSERT sur `users` / `user_profiles`.
//
// Depuis la phase 2 des données personnelles, les colonnes privées (email,
// téléphone, adresse, lat / lng, is_admin…) ne sont plus lisibles via l'API.
// Un upsert (INSERT … ON CONFLICT DO UPDATE) exige de pouvoir LIRE les
// colonnes qu'il met à jour → « permission denied ». Un UPDATE (relecture
// de la seule clé) puis un INSERT n'ont pas cette contrainte.
import { supabase } from '@/lib/supabase';

type Client = typeof supabase;

export async function ecrireLigne(
  table: 'users' | 'user_profiles',
  data: Record<string, unknown>,
  cles: Record<string, string | number>,
  colRetour = 'uid',
  client: Client = supabase,
): Promise<{ id: unknown; error: { message: string } | null }> {
  let maj = client.from(table).update(data);
  for (const [k, v] of Object.entries(cles)) maj = maj.eq(k, v);
  const { data: existantes, error: errMaj } = await maj.select(colRetour);
  if (errMaj) return { id: null, error: errMaj };
  if (existantes && existantes.length > 0) {
    return { id: (existantes[0] as unknown as Record<string, unknown>)[colRetour], error: null };
  }
  const { data: cree, error } = await client.from(table).insert({ ...cles, ...data }).select(colRetour).single();
  return { id: cree ? (cree as unknown as Record<string, unknown>)[colRetour] : null, error };
}
