/**
 * e-reporting (cahier des charges §19-20).
 *
 * Deux flux à transmettre à l'administration en plus des factures B2B :
 *  - `transaction` : données de vente B2C (et B2B international) — la facture
 *    elle-même n'est pas transmise, seules ses données agrégées le sont ;
 *  - `paiement`    : encaissement des prestations de services (exigibilité TVA
 *    sur les débits vs. encaissements).
 *
 * Ce module ne fait que **capturer** dans `pa.ereporting_queue` (statut
 * `a_transmettre`). La transmission effective vers la plateforme (PDP tierce
 * puis immatriculation propre) est un travail distinct.
 */

import { logEvent } from '../audit/journal.js';
import { paDb, type PaDb } from '../db/client.js';

/** Période de déclaration AAAA-MM à partir d'une date ISO. */
const ym = (iso: string): string => iso.slice(0, 7);

interface InvoiceRow {
  id: string;
  number: string;
  issue_date: string;
  currency_code: string;
  is_b2c: boolean;
  type_code: string;
  tax_exclusive_amount: number;
  tax_amount: number;
  tax_inclusive_amount: number;
}
interface VatRow {
  vat_category: string;
  vat_rate: number;
  taxable_amount: number;
  tax_amount: number;
}

async function loadInvoice(pa: PaDb, invoiceId: string): Promise<{ inv: InvoiceRow; vat: VatRow[] }> {
  const { data: inv, error: e1 } = await pa
    .from('invoices')
    .select(
      'id, number, issue_date, currency_code, is_b2c, type_code, tax_exclusive_amount, tax_amount, tax_inclusive_amount',
    )
    .eq('id', invoiceId)
    .maybeSingle();
  if (e1) throw new Error(`ereporting: lecture pa.invoices — ${e1.message}`);
  if (!inv) throw new Error(`ereporting: facture introuvable (${invoiceId}).`);
  const { data: vat, error: e2 } = await pa
    .from('invoice_vat')
    .select('vat_category, vat_rate, taxable_amount, tax_amount')
    .eq('invoice_id', invoiceId);
  if (e2) throw new Error(`ereporting: lecture pa.invoice_vat — ${e2.message}`);
  return { inv: inv as InvoiceRow, vat: (vat ?? []) as VatRow[] };
}

async function enqueue(
  pa: PaDb,
  invoiceId: string,
  kind: 'transaction' | 'paiement',
  period: string,
  payload: unknown,
): Promise<boolean> {
  // Idempotence : une seule ligne (invoice, kind, period) en file.
  const { data: existing, error: e1 } = await pa
    .from('ereporting_queue')
    .select('id')
    .eq('invoice_id', invoiceId)
    .eq('kind', kind)
    .eq('period', period)
    .maybeSingle();
  if (e1) throw new Error(`ereporting: lecture file — ${e1.message}`);
  if (existing) return false;

  const { error: e2 } = await pa
    .from('ereporting_queue')
    .insert({ invoice_id: invoiceId, kind, period, payload, status: 'a_transmettre' });
  if (e2) throw new Error(`ereporting: insert file — ${e2.message}`);

  await logEvent(
    { invoiceId, event: 'ereporting', detail: { kind, period }, actorKind: 'system' },
    pa,
  );
  return true;
}

export interface CaptureOptions {
  pa?: PaDb;
  /** Forcer même si la facture n'est pas B2C (B2B international). */
  force?: boolean;
}

/**
 * Capture les données de transaction d'une facture B2C émise.
 * Renvoie `false` si déjà en file ou si la facture est B2B (sans `force`).
 */
export async function captureB2cTransaction(
  invoiceId: string,
  opts: CaptureOptions = {},
): Promise<{ queued: boolean }> {
  const pa = opts.pa ?? paDb();
  const { inv, vat } = await loadInvoice(pa, invoiceId);
  if (!inv.is_b2c && !opts.force) return { queued: false };

  const payload = {
    kind: 'transaction' as const,
    invoiceNumber: inv.number,
    issueDate: inv.issue_date,
    currency: inv.currency_code,
    typeCode: inv.type_code,
    customerType: inv.is_b2c ? 'B2C' : 'B2B_INTL',
    totals: {
      taxExclusive: inv.tax_exclusive_amount,
      tax: inv.tax_amount,
      taxInclusive: inv.tax_inclusive_amount,
    },
    vatBreakdown: vat.map((v) => ({
      category: v.vat_category,
      rate: v.vat_rate,
      taxableAmount: v.taxable_amount,
      taxAmount: v.tax_amount,
    })),
  };
  const queued = await enqueue(pa, invoiceId, 'transaction', ym(inv.issue_date), payload);
  return { queued };
}

export interface PaymentCapture {
  amount: number;
  /** Date d'encaissement (ISO yyyy-mm-dd). */
  date: string;
  /** Code moyen de paiement (BT-81), optionnel. */
  meansCode?: string;
  reference?: string;
}

/**
 * Capture un encaissement (e-reporting de paiement, prestations de services).
 * Période = mois de l'encaissement.
 */
export async function capturePayment(
  invoiceId: string,
  payment: PaymentCapture,
  opts: CaptureOptions = {},
): Promise<{ queued: boolean }> {
  const pa = opts.pa ?? paDb();
  const { inv } = await loadInvoice(pa, invoiceId);

  const payload = {
    kind: 'paiement' as const,
    invoiceNumber: inv.number,
    currency: inv.currency_code,
    amount: payment.amount,
    paidAt: payment.date,
    ...(payment.meansCode ? { meansCode: payment.meansCode } : {}),
    ...(payment.reference ? { reference: payment.reference } : {}),
  };
  const queued = await enqueue(pa, invoiceId, 'paiement', ym(payment.date), payload);
  return { queued };
}
