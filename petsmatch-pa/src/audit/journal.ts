/**
 * Journal de preuve (cahier des charges §22-23).
 *
 * Écriture seule, dans `pa.invoice_events` (table append-only : accès
 * service_role, RLS FORCE, jamais d'UPDATE/DELETE applicatif). Chaque entrée
 * porte : qui / quoi / quand / résultat / empreinte / version du modèle.
 */

import { paDb, type PaDb } from '../db/client.js';
import { MODEL_VERSION } from '../version.js';
import type { InvoiceStatus } from '../lifecycle/state-machine.js';

export type JournalEvent =
  | 'creation'
  | 'update'
  | 'validation'
  | 'transition'
  | 'emission'
  | 'transmission'
  | 'reception'
  | 'ereporting';

export interface JournalEntry {
  invoiceId?: string;
  sourceFactureId?: string;
  event: JournalEvent;
  fromStatus?: InvoiceStatus;
  toStatus?: InvoiceStatus;
  actorUid?: string;
  actorKind?: 'user' | 'system' | 'pa';
  result?: 'success' | 'failure';
  detail?: unknown;
  contentHash?: string;
}

export async function logEvent(entry: JournalEntry, db: PaDb = paDb()): Promise<void> {
  const { error } = await db.from('invoice_events').insert({
    invoice_id: entry.invoiceId ?? null,
    source_facture_id: entry.sourceFactureId ?? null,
    event: entry.event,
    from_status: entry.fromStatus ?? null,
    to_status: entry.toStatus ?? null,
    actor_uid: entry.actorUid ?? null,
    actor_kind: entry.actorKind ?? 'system',
    result: entry.result ?? 'success',
    detail: entry.detail ?? null,
    content_hash: entry.contentHash ?? null,
    model_version: MODEL_VERSION,
  });
  if (error) throw new Error(`journal: ${error.message}`);
}
