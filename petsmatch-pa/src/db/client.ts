/**
 * Accès à la base fiscale (schéma `pa`).
 *
 * Le service petsmatch-pa utilise la clé `service_role` : il est le seul à
 * pouvoir lire/écrire le schéma `pa` (RLS FORCE, aucune policy — cf.
 * migration_pa_01_schema.sql).
 *
 * `sourceDb()` accède au schéma `public` (lecture de `factures`) — à retirer
 * quand l'ingestion passera par l'API interne plutôt que par un accès direct.
 */

import { createClient, type SupabaseClient } from '@supabase/supabase-js';

export type PaDb = SupabaseClient<any, 'pa'>;
export type SourceDb = SupabaseClient<any, 'public'>;

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Variable d'environnement manquante : ${name}`);
  return v;
}

let _pa: PaDb | undefined;
let _source: SourceDb | undefined;

export function paDb(): PaDb {
  if (!_pa) {
    _pa = createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
      db: { schema: 'pa' },
      auth: { persistSession: false, autoRefreshToken: false },
    }) as PaDb;
  }
  return _pa;
}

export function sourceDb(): SourceDb {
  if (!_source) {
    _source = createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
      db: { schema: 'public' },
      auth: { persistSession: false, autoRefreshToken: false },
    }) as SourceDb;
  }
  return _source;
}

/** Pour les tests : injecter des clients factices. */
export function __setClients(pa?: PaDb, source?: SourceDb): void {
  _pa = pa;
  _source = source;
}
