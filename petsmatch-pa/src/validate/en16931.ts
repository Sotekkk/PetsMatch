/**
 * Validateur pré-émission (cahier des charges §13).
 *
 * Vérifie une facture au sens EN 16931 avant qu'elle puisse être transmise :
 * champs obligatoires, cohérence arithmétique, règles métier, spécificités
 * françaises. Retourne des messages **lisibles** (« Numéro de TVA destinataire
 * invalide », pas `XML_ERROR_3427`).
 *
 * `error`   → transmission bloquée.
 * `warning` → transmission possible mais qualité de donnée à corriger.
 */

import { VAT_CATEGORY, type En16931Invoice } from '../model/en16931.js';

export type Severity = 'error' | 'warning';

export interface ValidationIssue {
  code: string; // identifiant stable (log, i18n)
  severity: Severity;
  field: string; // chemin logique (ex. 'seller.address.countryCode')
  message: string; // message lisible en français
}

export interface ValidationResult {
  ok: boolean; // true si aucune issue de sévérité 'error'
  issues: ValidationIssue[];
}

const round2 = (n: number): number => Math.round((n + Number.EPSILON) * 100) / 100;
const near = (a: number, b: number, tol = 0.02): boolean => Math.abs(a - b) <= tol;

/** Contrôle de Luhn sur les 14 chiffres du SIRET. */
function siretValid(siret: string): boolean {
  const d = siret.replace(/\D/g, '');
  if (d.length !== 14) return false;
  let sum = 0;
  for (let i = 0; i < 14; i++) {
    let v = Number(d[13 - i]);
    if (i % 2 === 1) {
      v *= 2;
      if (v > 9) v -= 9;
    }
    sum += v;
  }
  return sum % 10 === 0;
}

/** Format TVA intracommunautaire FR : FR + clé (2) + SIREN (9). */
function vatFrValid(vat: string): boolean {
  return /^FR[0-9A-HJ-NP-Z]{2}\d{9}$/i.test(vat.replace(/\s/g, ''));
}

export function validateEn16931(inv: En16931Invoice): ValidationResult {
  const issues: ValidationIssue[] = [];
  const err = (code: string, field: string, message: string) =>
    issues.push({ code, severity: 'error', field, message });
  const warn = (code: string, field: string, message: string) =>
    issues.push({ code, severity: 'warning', field, message });

  // ── En-tête ───────────────────────────────────────────────────────────────
  if (!inv.number) err('BR-2', 'number', 'La facture doit avoir un numéro.');
  if (!inv.issueDate || !/^\d{4}-\d{2}-\d{2}$/.test(inv.issueDate)) {
    err('BR-3', 'issueDate', "La date d'émission est absente ou mal formée (attendu AAAA-MM-JJ).");
  }
  if (!inv.currencyCode || inv.currencyCode.length !== 3) {
    err('BR-5', 'currencyCode', 'Le code devise (ISO 4217) est absent.');
  }
  if (inv.dueDate && inv.issueDate && inv.dueDate < inv.issueDate) {
    warn('BR-CO-25', 'dueDate', "La date d'échéance est antérieure à la date d'émission.");
  }
  if (inv.precedingInvoiceReference && inv.precedingInvoiceReference.number.startsWith('#')) {
    warn(
      'PM-PARENT-REF',
      'precedingInvoiceReference.number',
      "La facture d'origine est référencée par un identifiant interne, pas par son numéro.",
    );
  }

  // ── Vendeur (BG-4) ────────────────────────────────────────────────────────
  if (!inv.seller.name) err('BR-6', 'seller.name', 'Le nom du vendeur est obligatoire.');
  if (!inv.seller.address?.countryCode) {
    err('BR-9', 'seller.address.countryCode', 'Le pays du vendeur est obligatoire.');
  }
  if (!inv.seller.address?.line1 || !inv.seller.address?.city || !inv.seller.address?.postCode) {
    warn('PM-SELLER-ADDR', 'seller.address', "L'adresse du vendeur est incomplète (rue / code postal / ville).");
  }
  if (!inv.seller.legalRegistrationId && !inv.seller.vatIdentifier) {
    err(
      'BR-CO-26',
      'seller.legalRegistrationId',
      'Le vendeur doit être identifié par un SIREN et/ou un numéro de TVA.',
    );
  }
  if (inv.seller.siret && !siretValid(inv.seller.siret)) {
    err('PM-SIRET-SELLER', 'seller.siret', `SIRET vendeur invalide (${inv.seller.siret}).`);
  }
  if (inv.seller.vatIdentifier && inv.seller.vatIdentifier.toUpperCase().startsWith('FR') && !vatFrValid(inv.seller.vatIdentifier)) {
    err('PM-VAT-SELLER', 'seller.vatIdentifier', `Numéro de TVA vendeur invalide (${inv.seller.vatIdentifier}).`);
  }
  if (!inv.seller.electronicAddress) {
    warn('PM-SELLER-EAS', 'seller.electronicAddress', "Le vendeur n'a pas d'adresse électronique de routage.");
  }

  // ── Acheteur (BG-7) — présent uniquement en B2B ───────────────────────────
  if (inv.source.isB2c) {
    if (inv.buyer) warn('PM-B2C-BUYER', 'buyer', 'Facture marquée B2C mais un acheteur est renseigné.');
  } else {
    if (!inv.buyer) {
      err('BR-7', 'buyer', "Facture B2B sans acheteur identifié.");
    } else {
      if (!inv.buyer.name) err('BR-7', 'buyer.name', "Le nom de l'acheteur est obligatoire.");
      if (!inv.buyer.address?.countryCode) {
        err('BR-11', 'buyer.address.countryCode', "Le pays de l'acheteur est obligatoire.");
      }
      if (!inv.buyer.legalRegistrationId && !inv.buyer.vatIdentifier) {
        err(
          'BR-CO-11',
          'buyer.legalRegistrationId',
          "L'acheteur professionnel doit être identifié par un SIREN et/ou un numéro de TVA.",
        );
      }
      if (inv.buyer.siret && !siretValid(inv.buyer.siret)) {
        err('PM-SIRET-BUYER', 'buyer.siret', `SIRET destinataire invalide (${inv.buyer.siret}).`);
      }
      if (
        inv.buyer.vatIdentifier &&
        inv.buyer.vatIdentifier.toUpperCase().startsWith('FR') &&
        !vatFrValid(inv.buyer.vatIdentifier)
      ) {
        err('PM-VAT-BUYER', 'buyer.vatIdentifier', `Numéro de TVA destinataire invalide (${inv.buyer.vatIdentifier}).`);
      }
      if (!inv.buyer.electronicAddress) {
        err(
          'PM-BUYER-EAS',
          'buyer.electronicAddress',
          "Impossible de router la facture : l'adresse électronique du destinataire est inconnue (annuaire).",
        );
      }
    }
  }

  // ── Lignes (BG-25) ───────────────────────────────────────────────────────
  if (inv.lines.length === 0) err('BR-16', 'lines', 'La facture doit comporter au moins une ligne.');
  inv.lines.forEach((l, i) => {
    const p = `lines[${i}]`;
    if (!l.name) err('BR-25', `${p}.name`, `Ligne ${i + 1} : la désignation est obligatoire.`);
    if (!Number.isFinite(l.quantity)) err('BR-22', `${p}.quantity`, `Ligne ${i + 1} : quantité manquante.`);
    if (!near(round2(l.quantity * l.netPrice), l.netAmount)) {
      err(
        'BR-CO-10',
        `${p}.netAmount`,
        `Ligne ${i + 1} : le montant net (${l.netAmount}) ≠ quantité × prix (${round2(l.quantity * l.netPrice)}).`,
      );
    }
    if (l.vat.category === VAT_CATEGORY.STANDARD && l.vat.rate <= 0) {
      err('BR-DEC-14', `${p}.vat.rate`, `Ligne ${i + 1} : catégorie de TVA « standard » avec un taux nul.`);
    }
  });

  // ── Ventilation TVA (BG-23) ──────────────────────────────────────────────
  if (inv.vatBreakdown.length === 0) {
    err('BR-45', 'vatBreakdown', 'La ventilation de la TVA est absente.');
  }
  for (const v of inv.vatBreakdown) {
    const lineSum = round2(
      inv.lines
        .filter((l) => l.vat.category === v.category && l.vat.rate === v.rate)
        .reduce((s, l) => s + l.netAmount, 0),
    );
    if (!near(lineSum, v.taxableAmount)) {
      err(
        'BR-CO-14',
        'vatBreakdown.taxableAmount',
        `Ventilation TVA (${v.category} ${v.rate} %) : base ${v.taxableAmount} ≠ somme des lignes ${lineSum}.`,
      );
    }
    const expectedTax =
      v.category === VAT_CATEGORY.STANDARD ? round2((v.taxableAmount * v.rate) / 100) : 0;
    if (!near(expectedTax, v.taxAmount)) {
      err(
        'BR-CO-17',
        'vatBreakdown.taxAmount',
        `Ventilation TVA (${v.category} ${v.rate} %) : TVA ${v.taxAmount} ≠ ${expectedTax} attendu.`,
      );
    }
    const needsReason: string[] = [VAT_CATEGORY.EXEMPT, VAT_CATEGORY.REVERSE_CHARGE, VAT_CATEGORY.INTRA_COMMUNITY, VAT_CATEGORY.EXPORT, VAT_CATEGORY.OUT_OF_SCOPE];
    if (needsReason.includes(v.category) && !v.exemptionReasonText && !v.exemptionReasonCode) {
      err(
        'BR-E-10',
        'vatBreakdown.exemptionReason',
        `La catégorie de TVA « ${v.category} » exige un motif d'exonération (ex. « TVA non applicable, art. 293 B du CGI »).`,
      );
    }
  }

  // ── Totaux (BG-22) ───────────────────────────────────────────────────────
  const t = inv.totals;
  const lineNet = round2(inv.lines.reduce((s, l) => s + l.netAmount, 0));
  const vatSum = round2(inv.vatBreakdown.reduce((s, v) => s + v.taxAmount, 0));
  const baseSum = round2(inv.vatBreakdown.reduce((s, v) => s + v.taxableAmount, 0));
  if (!near(lineNet, t.lineNetTotal)) {
    err('BR-CO-10b', 'totals.lineNetTotal', `Somme des lignes ${lineNet} ≠ total lignes ${t.lineNetTotal}.`);
  }
  if (!near(baseSum, t.taxExclusiveAmount)) {
    err('BR-CO-13', 'totals.taxExclusiveAmount', `Total HT ${t.taxExclusiveAmount} ≠ somme des bases TVA ${baseSum}.`);
  }
  if (!near(vatSum, t.taxAmount)) {
    err('BR-CO-14b', 'totals.taxAmount', `Total TVA ${t.taxAmount} ≠ somme de la ventilation ${vatSum}.`);
  }
  if (!near(round2(t.taxExclusiveAmount + t.taxAmount), t.taxInclusiveAmount)) {
    err('BR-CO-15', 'totals.taxInclusiveAmount', `Total TTC ${t.taxInclusiveAmount} ≠ HT + TVA (${round2(t.taxExclusiveAmount + t.taxAmount)}).`);
  }
  const paid = t.paidAmount ?? 0;
  if (!near(round2(t.taxInclusiveAmount - paid), t.amountDueForPayment)) {
    err('BR-CO-16', 'totals.amountDueForPayment', `Reste à payer ${t.amountDueForPayment} ≠ TTC − acomptes (${round2(t.taxInclusiveAmount - paid)}).`);
  }

  // ── Paiement (BG-16) ─────────────────────────────────────────────────────
  if (inv.payment?.meansCode && ['30', '58'].includes(inv.payment.meansCode) && !inv.payment.iban) {
    warn('PM-IBAN', 'payment.iban', 'Paiement par virement annoncé mais aucun IBAN structuré (BT-84).');
  }

  return { ok: !issues.some((i) => i.severity === 'error'), issues };
}
