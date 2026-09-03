/**
 * Normalisation : ligne `public.factures` → modèle sémantique EN 16931.
 *
 * Fonction pure. Elle produit la meilleure représentation possible à partir des
 * données actuelles ; les manques (unité, IBAN structuré, SIREN acheteur…) sont
 * signalés par le validateur (`validate/en16931.ts`), pas ici.
 */

import {
  type En16931Invoice,
  type InvoiceLine,
  type VatBreakdown,
  type VatCategoryCode,
  type PaymentMeansCode,
  INVOICE_TYPE,
  VAT_CATEGORY,
  UNIT,
  PAYMENT_MEANS,
  VAT_EXEMPTION_REASON_TEXT,
} from '../model/en16931.js';
import type { FactureSource, FactureLigneSource } from '../model/facture-source.js';

const num = (v: unknown, fallback = 0): number => {
  const n = typeof v === 'string' ? parseFloat(v.replace(',', '.')) : Number(v);
  return Number.isFinite(n) ? n : fallback;
};
const round2 = (n: number): number => Math.round((n + Number.EPSILON) * 100) / 100;
const clean = (s: unknown): string | undefined => {
  const t = (s ?? '').toString().trim();
  return t.length > 0 ? t : undefined;
};
/** SIREN = 9 premiers chiffres du SIRET. */
const sirenFromSiret = (siret?: string | null): string | undefined => {
  const digits = (siret ?? '').replace(/\D/g, '');
  return digits.length >= 9 ? digits.slice(0, 9) : undefined;
};

function invoiceTypeCode(f: FactureSource): En16931Invoice['typeCode'] {
  if (f.type_facture === 'avoir') return INVOICE_TYPE.CREDIT_NOTE;
  if (f.type_facture === 'acompte') return INVOICE_TYPE.PREPAYMENT;
  return INVOICE_TYPE.COMMERCIAL;
}

function paymentMeansCode(label?: string | null): PaymentMeansCode {
  const l = (label ?? '').toLowerCase();
  if (l.includes('virement')) return PAYMENT_MEANS.SEPA_CREDIT_TRANSFER;
  if (l.includes('chèque') || l.includes('cheque')) return PAYMENT_MEANS.CHEQUE;
  if (l.includes('espèce') || l.includes('espece') || l.includes('cash')) return PAYMENT_MEANS.CASH;
  if (l.includes('carte') || l.includes('cb')) return PAYMENT_MEANS.BANK_CARD;
  if (l.includes('paypal') || l.includes('stripe') || l.includes('en ligne')) {
    return PAYMENT_MEANS.ONLINE_PAYMENT_SERVICE;
  }
  return PAYMENT_MEANS.SEPA_CREDIT_TRANSFER;
}

/** Catégorie de TVA d'une ligne selon le régime et le taux. */
function lineVatCategory(f: FactureSource, taux: number): VatCategoryCode {
  if (f.regime_tva === 'franchise') return VAT_CATEGORY.EXEMPT;
  if (taux === 0) return VAT_CATEGORY.EXEMPT;
  return VAT_CATEGORY.STANDARD;
}

function mapLine(f: FactureSource, l: FactureLigneSource, index: number): InvoiceLine {
  const quantity = num(l.quantite, 1);
  const netPrice = num(l.prixUnitaireHT);
  const netAmount = l.totalHT != null ? round2(num(l.totalHT)) : round2(quantity * netPrice);
  const rate = num(l.tauxTVA);
  const category = lineVatCategory(f, rate);
  return {
    id: String(index + 1),
    name: clean(l.designation) ?? clean(l.description) ?? 'Prestation',
    ...(clean(l.description) && clean(l.designation) ? { description: clean(l.description)! } : {}),
    quantity,
    unit: UNIT.UNIT, // GAP : l'unité réelle n'est pas stockée aujourd'hui
    netPrice,
    netAmount,
    vat: { category, rate: category === VAT_CATEGORY.EXEMPT ? 0 : rate },
  };
}

function buildVatBreakdown(f: FactureSource, lines: InvoiceLine[]): VatBreakdown[] {
  const groups = new Map<string, VatBreakdown>();
  for (const line of lines) {
    const key = `${line.vat.category}|${line.vat.rate}`;
    const existing = groups.get(key);
    if (existing) {
      existing.taxableAmount = round2(existing.taxableAmount + line.netAmount);
    } else {
      groups.set(key, {
        category: line.vat.category,
        rate: line.vat.rate,
        taxableAmount: line.netAmount,
        taxAmount: 0,
      });
    }
  }
  for (const g of groups.values()) {
    g.taxAmount = g.category === VAT_CATEGORY.EXEMPT ? 0 : round2((g.taxableAmount * g.rate) / 100);
    if (g.category === VAT_CATEGORY.EXEMPT) {
      g.exemptionReasonText =
        f.regime_tva === 'franchise'
          ? VAT_EXEMPTION_REASON_TEXT.FRANCHISE_293B
          : 'Opération exonérée de TVA';
    }
  }
  return [...groups.values()];
}

export interface NormalizeOptions {
  /** Numéro (BT-1) de la facture d'origine, si `facture_parente_id` est renseigné. */
  parentInvoiceNumber?: string;
  currencyCode?: string; // défaut EUR
}

export function normalizeFacture(f: FactureSource, opts: NormalizeOptions = {}): En16931Invoice {
  const lignes = Array.isArray(f.lignes) ? f.lignes : [];
  const lines = lignes.map((l, i) => mapLine(f, l, i));
  const vatBreakdown = buildVatBreakdown(f, lines);

  const lineNetTotal = round2(lines.reduce((s, l) => s + l.netAmount, 0));
  const taxAmount = round2(vatBreakdown.reduce((s, v) => s + v.taxAmount, 0));
  const taxInclusiveAmount = round2(lineNetTotal + taxAmount);

  const isB2c = !clean(f.siret_client) && !clean(f.tva_client);

  const note = [clean(f.note_complementaire), clean(f.conditions_escompte)]
    .filter(Boolean)
    .join(' — ');

  const inv: En16931Invoice = {
    number: clean(f.numero_affichage) ?? (f.numero_facture != null ? String(f.numero_facture) : ''),
    issueDate: clean(f.date_facture) ?? '',
    typeCode: invoiceTypeCode(f),
    currencyCode: opts.currencyCode ?? 'EUR',
    ...(clean(f.date_echeance) ? { dueDate: clean(f.date_echeance)! } : {}),
    ...(clean(f.date_prestation) ? { serviceDate: clean(f.date_prestation)! } : {}),
    ...(f.facture_parente_id
      ? {
          precedingInvoiceReference: {
            number: opts.parentInvoiceNumber ?? `#${f.facture_parente_id}`,
          },
        }
      : {}),

    seller: {
      name: clean(f.nom_emetteur) ?? '',
      ...(clean(f.tva_emetteur) ? { vatIdentifier: clean(f.tva_emetteur)! } : {}),
      ...(sirenFromSiret(f.siret_emetteur) ? { legalRegistrationId: sirenFromSiret(f.siret_emetteur)! } : {}),
      ...(clean(f.siret_emetteur) ? { siret: clean(f.siret_emetteur)! } : {}),
      address: {
        ...(clean(f.rue_emetteur) ? { line1: clean(f.rue_emetteur)! } : {}),
        ...(clean(f.ville_emetteur) ? { city: clean(f.ville_emetteur)! } : {}),
        ...(clean(f.cp_emetteur) ? { postCode: clean(f.cp_emetteur)! } : {}),
        countryCode: countryCode(f.pays_emetteur),
      },
      ...(clean(f.siret_emetteur)
        ? { electronicAddress: { value: clean(f.siret_emetteur)!.replace(/\D/g, ''), scheme: '0009' } }
        : {}),
      ...(clean(f.email_emetteur) ? { contactEmail: clean(f.email_emetteur)! } : {}),
      ...(clean(f.tel_emetteur) ? { contactPhone: clean(f.tel_emetteur)! } : {}),
      ...(clean(f.forme_juridique_emetteur) ? { legalForm: clean(f.forme_juridique_emetteur)! } : {}),
      ...(clean(f.capital_emetteur) ? { shareCapital: clean(f.capital_emetteur)! } : {}),
      ...(clean(f.rcs_emetteur) ? { rcs: clean(f.rcs_emetteur)! } : {}),
      ...(clean(f.rm_emetteur) ? { rm: clean(f.rm_emetteur)! } : {}),
    },

    ...(isB2c
      ? {}
      : {
          buyer: {
            name: [clean(f.prenom_client), clean(f.nom_client)].filter(Boolean).join(' ') || (clean(f.nom_client) ?? ''),
            ...(clean(f.tva_client) ? { vatIdentifier: clean(f.tva_client)! } : {}),
            ...(sirenFromSiret(f.siret_client) ? { legalRegistrationId: sirenFromSiret(f.siret_client)! } : {}),
            ...(clean(f.siret_client) ? { siret: clean(f.siret_client)! } : {}),
            address: {
              ...(clean(f.rue_client) ? { line1: clean(f.rue_client)! } : {}),
              ...(clean(f.ville_client) ? { city: clean(f.ville_client)! } : {}),
              ...(clean(f.cp_client) ? { postCode: clean(f.cp_client)! } : {}),
              countryCode: countryCode(f.pays_client),
            },
            ...(clean(f.siret_client)
              ? { electronicAddress: { value: clean(f.siret_client)!.replace(/\D/g, ''), scheme: '0009' } }
              : {}),
            ...(clean(f.email_client) ? { contactEmail: clean(f.email_client)! } : {}),
          },
        }),

    lines,
    vatBreakdown,
    totals: {
      lineNetTotal,
      taxExclusiveAmount: lineNetTotal,
      taxAmount,
      taxInclusiveAmount,
      amountDueForPayment: taxInclusiveAmount,
    },
    ...(clean(f.mode_paiement) || clean(f.delai_paiement) || note
      ? {
          payment: {
            meansCode: paymentMeansCode(f.mode_paiement),
            // GAP : IBAN/BIC structurés absents de `factures` (souvent dans la note)
            ...(clean(f.conditions_escompte) || clean(f.delai_paiement)
              ? {
                  termsText: [
                    clean(f.delai_paiement) ? `Paiement à ${clean(f.delai_paiement)} jours.` : undefined,
                    clean(f.conditions_escompte),
                  ]
                    .filter(Boolean)
                    .join(' '),
                }
              : {}),
          },
        }
      : {}),
    ...(note ? { note } : {}),

    source: {
      factureId: f.id,
      profilSource: f.profil_source ?? null,
      isB2c,
    },
  };

  return inv;
}

/** Nom de pays libre → code ISO 3166-1 alpha-2 (best effort, défaut FR). */
function countryCode(pays?: string | null): string {
  const p = (pays ?? '').trim().toLowerCase();
  if (!p) return 'FR';
  if (p === 'france' || p === 'fr') return 'FR';
  if (p === 'belgique' || p === 'be') return 'BE';
  if (p === 'suisse' || p === 'ch') return 'CH';
  if (p === 'luxembourg' || p === 'lu') return 'LU';
  if (/^[a-z]{2}$/.test(p)) return p.toUpperCase();
  return 'FR';
}
