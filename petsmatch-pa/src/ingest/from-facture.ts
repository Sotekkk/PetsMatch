/**
 * Ingestion : `public.factures` (moteur commercial) → `pa.invoices` (base fiscale).
 *
 * Deux couches :
 *  - `buildInvoiceRecords()` — pure : ligne source → { modèle EN 16931, validation,
 *    enregistrements `pa.*` }. Testable sans base.
 *  - `ingestFacture()` — I/O : lit la facture, résout la facture d'origine d'un
 *    avoir, upsert l'en-tête, remplace lignes + ventilation, journalise
 *    `creation`/`update` puis `validation`.
 *
 * L'ingestion NE fait PAS émettre la facture : elle produit/rafraîchit le
 * brouillon structuré. L'émission (figeage Factur-X + transmission) est une
 * étape distincte pilotée par la machine à états. Une facture déjà figée
 * (statut ≠ `brouillon`) n'est jamais réécrite.
 */

import { normalizeFacture } from '../normalize/from-facture.js';
import { validateEn16931, type ValidationIssue, type ValidationResult } from '../validate/en16931.js';
import type { En16931Invoice, Seller, Buyer, PaymentInstructions } from '../model/en16931.js';
import type { FactureSource } from '../model/facture-source.js';
import { isLocked, type InvoiceStatus } from '../lifecycle/state-machine.js';
import { logEvent } from '../audit/journal.js';
import { paDb, sourceDb, type PaDb, type SourceDb } from '../db/client.js';

export type SourceKind = 'factures' | 'pension_factures';

// ── Enregistrements `pa.*` ──────────────────────────────────────────────────

export interface InvoiceHeaderRecord {
  source_facture_id: string;
  source_kind: SourceKind;
  profil_source: string | null;
  number: string;
  issue_date: string;
  type_code: En16931Invoice['typeCode'];
  currency_code: string;
  due_date: string | null;
  service_date: string | null;
  buyer_reference: string | null;
  preceding_invoice_number: string | null;
  is_b2c: boolean;
  seller: Seller;
  buyer: Buyer | null;
  line_net_total: number;
  tax_exclusive_amount: number;
  tax_amount: number;
  tax_inclusive_amount: number;
  paid_amount: number | null;
  amount_due: number;
  payment: PaymentInstructions | null;
  note: string | null;
  validation_ok: boolean;
  validation_issues: ValidationIssue[];
}

export interface InvoiceLineRecord {
  line_no: number;
  name: string;
  description: string | null;
  quantity: number;
  unit_code: string;
  net_price: number;
  net_amount: number;
  vat_category: string;
  vat_rate: number;
}

export interface InvoiceVatRecord {
  vat_category: string;
  vat_rate: number;
  taxable_amount: number;
  tax_amount: number;
  exemption_reason_code: string | null;
  exemption_reason_text: string | null;
}

export interface InvoiceRecords {
  invoice: En16931Invoice;
  validation: ValidationResult;
  header: InvoiceHeaderRecord;
  lines: InvoiceLineRecord[];
  vat: InvoiceVatRecord[];
}

export interface BuildRecordsOptions {
  sourceKind?: SourceKind;
  /** Numéro (BT-1) de la facture d'origine, si `facture_parente_id` est renseigné. */
  parentInvoiceNumber?: string;
}

/** Pure : ligne source → modèle + validation + enregistrements `pa.*`. */
export function buildInvoiceRecords(f: FactureSource, opts: BuildRecordsOptions = {}): InvoiceRecords {
  const sourceKind = opts.sourceKind ?? 'factures';
  const invoice = normalizeFacture(
    f,
    opts.parentInvoiceNumber ? { parentInvoiceNumber: opts.parentInvoiceNumber } : {},
  );
  const validation = validateEn16931(invoice);

  const header: InvoiceHeaderRecord = {
    source_facture_id: f.id,
    source_kind: sourceKind,
    profil_source: invoice.source.profilSource,
    number: invoice.number,
    issue_date: invoice.issueDate,
    type_code: invoice.typeCode,
    currency_code: invoice.currencyCode,
    due_date: invoice.dueDate ?? null,
    service_date: invoice.serviceDate ?? null,
    buyer_reference: invoice.buyerReference ?? null,
    preceding_invoice_number: invoice.precedingInvoiceReference?.number ?? null,
    is_b2c: invoice.source.isB2c,
    seller: invoice.seller,
    buyer: invoice.buyer ?? null,
    line_net_total: invoice.totals.lineNetTotal,
    tax_exclusive_amount: invoice.totals.taxExclusiveAmount,
    tax_amount: invoice.totals.taxAmount,
    tax_inclusive_amount: invoice.totals.taxInclusiveAmount,
    paid_amount: invoice.totals.paidAmount ?? null,
    amount_due: invoice.totals.amountDueForPayment,
    payment: invoice.payment ?? null,
    note: invoice.note ?? null,
    validation_ok: validation.ok,
    validation_issues: validation.issues,
  };

  const lines: InvoiceLineRecord[] = invoice.lines.map((l, i) => ({
    line_no: i + 1,
    name: l.name,
    description: l.description ?? null,
    quantity: l.quantity,
    unit_code: l.unit,
    net_price: l.netPrice,
    net_amount: l.netAmount,
    vat_category: l.vat.category,
    vat_rate: l.vat.rate,
  }));

  const vat: InvoiceVatRecord[] = invoice.vatBreakdown.map((v) => ({
    vat_category: v.category,
    vat_rate: v.rate,
    taxable_amount: v.taxableAmount,
    tax_amount: v.taxAmount,
    exemption_reason_code: v.exemptionReasonCode ?? null,
    exemption_reason_text: v.exemptionReasonText ?? null,
  }));

  return { invoice, validation, header, lines, vat };
}

// ── Orchestrateur I/O ──────────────────────────────────────────────────────

export interface IngestOptions {
  sourceKind?: SourceKind;
  actorUid?: string;
  actorKind?: 'user' | 'system' | 'pa';
  /** Clients injectables (tests). Par défaut : singletons `db/client.ts`. */
  pa?: PaDb;
  source?: SourceDb;
}

export interface IngestResult {
  invoiceId: string | null;
  status: InvoiceStatus;
  created: boolean;
  skipped?: 'locked' | 'not_found';
  validation: ValidationResult | null;
}

export async function ingestFacture(factureId: string, opts: IngestOptions = {}): Promise<IngestResult> {
  const pa = opts.pa ?? paDb();
  const source = opts.source ?? sourceDb();
  const sourceKind = opts.sourceKind ?? 'factures';

  // 1. Charger la facture commerciale d'origine.
  const { data: row, error: e1 } = await source
    .from(sourceKind)
    .select('*')
    .eq('id', factureId)
    .maybeSingle();
  if (e1) throw new Error(`ingest: lecture ${sourceKind} — ${e1.message}`);
  if (!row) {
    return { invoiceId: null, status: 'brouillon', created: false, skipped: 'not_found', validation: null };
  }
  const f = row as FactureSource;

  // 2. Déjà ingérée ? Si figée (≠ brouillon), on ne retouche pas le contenu.
  const { data: existing, error: e2 } = await pa
    .from('invoices')
    .select('id, status')
    .eq('source_kind', sourceKind)
    .eq('source_facture_id', factureId)
    .maybeSingle();
  if (e2) throw new Error(`ingest: lecture pa.invoices — ${e2.message}`);
  if (existing && isLocked(existing.status as InvoiceStatus)) {
    return {
      invoiceId: existing.id as string,
      status: existing.status as InvoiceStatus,
      created: false,
      skipped: 'locked',
      validation: null,
    };
  }

  // 3. Résoudre le numéro de la facture d'origine (avoir / rectificative).
  let parentInvoiceNumber: string | undefined;
  if (f.facture_parente_id) {
    const { data: parent } = await source
      .from(sourceKind)
      .select('numero_affichage, numero_facture')
      .eq('id', f.facture_parente_id)
      .maybeSingle();
    if (parent) {
      parentInvoiceNumber =
        (parent.numero_affichage as string | null) ??
        (parent.numero_facture != null ? String(parent.numero_facture) : undefined);
    }
  }

  // 4. Normaliser + valider + cartographier.
  const { header, lines, vat, validation } = buildInvoiceRecords(f, {
    sourceKind,
    ...(parentInvoiceNumber ? { parentInvoiceNumber } : {}),
  });

  // 5. Upsert de l'en-tête (le statut n'est pas touché : reste 'brouillon').
  const now = new Date().toISOString();
  const { data: up, error: e3 } = await pa
    .from('invoices')
    .upsert(
      { ...header, validated_at: now, updated_at: now },
      { onConflict: 'source_kind,source_facture_id' },
    )
    .select('id')
    .single();
  if (e3) throw new Error(`ingest: upsert pa.invoices — ${e3.message}`);
  const invoiceId = up.id as string;

  // 6. Remplacer lignes + ventilation TVA (le brouillon est reconstruit).
  const { error: e4a } = await pa.from('invoice_lines').delete().eq('invoice_id', invoiceId);
  if (e4a) throw new Error(`ingest: purge pa.invoice_lines — ${e4a.message}`);
  if (lines.length > 0) {
    const { error: e4b } = await pa
      .from('invoice_lines')
      .insert(lines.map((l) => ({ ...l, invoice_id: invoiceId })));
    if (e4b) throw new Error(`ingest: insert pa.invoice_lines — ${e4b.message}`);
  }
  const { error: e5a } = await pa.from('invoice_vat').delete().eq('invoice_id', invoiceId);
  if (e5a) throw new Error(`ingest: purge pa.invoice_vat — ${e5a.message}`);
  if (vat.length > 0) {
    const { error: e5b } = await pa
      .from('invoice_vat')
      .insert(vat.map((v) => ({ ...v, invoice_id: invoiceId })));
    if (e5b) throw new Error(`ingest: insert pa.invoice_vat — ${e5b.message}`);
  }

  // 7. Journal de preuve : création/màj puis résultat de validation.
  await logEvent(
    {
      invoiceId,
      sourceFactureId: factureId,
      event: existing ? 'update' : 'creation',
      ...(opts.actorUid ? { actorUid: opts.actorUid } : {}),
      actorKind: opts.actorKind ?? 'system',
      detail: { number: header.number, typeCode: header.type_code, isB2c: header.is_b2c },
    },
    pa,
  );
  await logEvent(
    {
      invoiceId,
      sourceFactureId: factureId,
      event: 'validation',
      result: validation.ok ? 'success' : 'failure',
      actorKind: 'system',
      detail: { ok: validation.ok, issues: validation.issues },
    },
    pa,
  );

  return {
    invoiceId,
    status: (existing?.status as InvoiceStatus | undefined) ?? 'brouillon',
    created: !existing,
    validation,
  };
}
