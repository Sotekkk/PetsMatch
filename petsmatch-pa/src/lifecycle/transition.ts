/**
 * Application d'une transition d'état sur une facture `pa.invoices`.
 *
 * Enchaîne : lecture du statut courant → contrôle (`assertTransition`) →
 * écriture du nouveau statut → journalisation (`event = 'transition'`).
 * Toute transition interdite lève `InvalidTransitionError` avant écriture.
 */

import { assertTransition, type InvoiceStatus } from './state-machine.js';
import { logEvent } from '../audit/journal.js';
import { paDb, type PaDb } from '../db/client.js';

export interface TransitionOptions {
  actorUid?: string;
  actorKind?: 'user' | 'system' | 'pa';
  /** Empreinte du contenu concerné (PDF/A-3, accusé de transmission…). */
  contentHash?: string;
  detail?: unknown;
  pa?: PaDb;
}

export interface TransitionResult {
  invoiceId: string;
  from: InvoiceStatus;
  to: InvoiceStatus;
}

export async function transitionInvoice(
  invoiceId: string,
  to: InvoiceStatus,
  opts: TransitionOptions = {},
): Promise<TransitionResult> {
  const pa = opts.pa ?? paDb();

  const { data: row, error: e1 } = await pa
    .from('invoices')
    .select('id, status')
    .eq('id', invoiceId)
    .maybeSingle();
  if (e1) throw new Error(`transition: lecture pa.invoices — ${e1.message}`);
  if (!row) throw new Error(`transition: facture introuvable (${invoiceId}).`);

  const from = row.status as InvoiceStatus;
  assertTransition(from, to); // lève avant toute écriture

  const now = new Date().toISOString();
  const { error: e2 } = await pa
    .from('invoices')
    .update({ status: to, status_changed_at: now, updated_at: now })
    .eq('id', invoiceId)
    .eq('status', from); // garde optimiste : pas de course sur le statut
  if (e2) throw new Error(`transition: écriture statut — ${e2.message}`);

  await logEvent(
    {
      invoiceId,
      event: 'transition',
      fromStatus: from,
      toStatus: to,
      ...(opts.actorUid ? { actorUid: opts.actorUid } : {}),
      actorKind: opts.actorKind ?? 'system',
      ...(opts.contentHash ? { contentHash: opts.contentHash } : {}),
      ...(opts.detail !== undefined ? { detail: opts.detail } : {}),
    },
    pa,
  );

  return { invoiceId, from, to };
}
