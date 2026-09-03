/**
 * Génération du XML CII (UN/CEFACT Cross Industry Invoice) — la partie
 * structurée du Factur-X, profil EN 16931.
 *
 * Le XML respecte la séquence imposée par le schéma CII D16B. Il est ensuite
 * embarqué dans un PDF/A-3 (`src/facturx/pdf.ts`) sous le nom `factur-x.xml`.
 *
 * Réf. : spécification Factur-X 1.0 (FNFE-MPE) / EN 16931-1 / CII 16B.
 */

import {
  type En16931Invoice,
  type InvoiceLine,
  type VatBreakdown,
  type Seller,
  type Buyer,
  VAT_CATEGORY,
} from '../model/en16931.js';

/** Profil Factur-X supporté par ce générateur. */
export const FACTURX_PROFILE_EN16931 = 'urn:cen.eu:en16931:2017';

const NS = {
  rsm: 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100',
  ram: 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100',
  qdt: 'urn:un:unece:uncefact:data:standard:QualifiedDataType:100',
  udt: 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100',
};

// ── Helpers XML ─────────────────────────────────────────────────────────────

function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Montant EN 16931 : 2 décimales, point décimal. */
const amt = (n: number): string => (Math.round((n + Number.EPSILON) * 100) / 100).toFixed(2);
/** Quantité / prix : jusqu'à 4 décimales. */
const qty = (n: number): string => {
  const r = Math.round((n + Number.EPSILON) * 10000) / 10000;
  return Number.isInteger(r) ? r.toFixed(2) : String(r);
};
/** Pourcentage de taxe : 2 décimales. */
const pct = (n: number): string => n.toFixed(2);
/** ISO yyyy-mm-dd → CCYYMMDD (format 102). */
const d102 = (iso: string): string => iso.replaceAll('-', '');

class Xml {
  private parts: string[] = [];
  private indent = 0;
  private pad(): string {
    return '  '.repeat(this.indent);
  }
  open(tag: string, attrs?: Record<string, string>): this {
    const a = attrs
      ? Object.entries(attrs)
          .map(([k, v]) => ` ${k}="${esc(v)}"`)
          .join('')
      : '';
    this.parts.push(`${this.pad()}<${tag}${a}>`);
    this.indent++;
    return this;
  }
  close(tag: string): this {
    this.indent--;
    this.parts.push(`${this.pad()}</${tag}>`);
    return this;
  }
  leaf(tag: string, value: string | number, attrs?: Record<string, string>): this {
    const a = attrs
      ? Object.entries(attrs)
          .map(([k, v]) => ` ${k}="${esc(v)}"`)
          .join('')
      : '';
    this.parts.push(`${this.pad()}<${tag}${a}>${esc(String(value))}</${tag}>`);
    return this;
  }
  /** Élément uniquement si la valeur est non vide. */
  opt(tag: string, value: string | undefined | null, attrs?: Record<string, string>): this {
    if (value != null && String(value).trim() !== '') this.leaf(tag, String(value), attrs);
    return this;
  }
  raw(s: string): this {
    this.parts.push(s);
    return this;
  }
  toString(): string {
    return this.parts.join('\n');
  }
}

// ── Blocs ──────────────────────────────────────────────────────────────────

function dateTimeElem(x: Xml, tag: string, iso: string): void {
  x.open(tag);
  x.leaf('udt:DateTimeString', d102(iso), { format: '102' });
  x.close(tag);
}

function tradeParty(x: Xml, tag: string, p: Seller | Buyer, electronicAddress = true): void {
  x.open(`ram:${tag}`);
  x.leaf('ram:Name', p.name);
  if (p.legalRegistrationId || (p as Seller).tradingName) {
    x.open('ram:SpecifiedLegalOrganization');
    x.opt('ram:ID', p.legalRegistrationId, { schemeID: '0002' }); // 0002 = SIREN
    x.opt('ram:TradingBusinessName', (p as Seller).tradingName);
    x.close('ram:SpecifiedLegalOrganization');
  }
  if ('contactEmail' in p && (p.contactEmail || (p as Seller).contactPhone)) {
    x.open('ram:DefinedTradeContact');
    if ((p as Seller).contactPhone) {
      x.open('ram:TelephoneUniversalCommunication');
      x.leaf('ram:CompleteNumber', (p as Seller).contactPhone!);
      x.close('ram:TelephoneUniversalCommunication');
    }
    if (p.contactEmail) {
      x.open('ram:EmailURIUniversalCommunication');
      x.leaf('ram:URIID', p.contactEmail);
      x.close('ram:EmailURIUniversalCommunication');
    }
    x.close('ram:DefinedTradeContact');
  }
  x.open('ram:PostalTradeAddress');
  x.opt('ram:PostcodeCode', p.address.postCode);
  x.opt('ram:LineOne', p.address.line1);
  x.opt('ram:LineTwo', p.address.line2);
  x.opt('ram:CityName', p.address.city);
  x.leaf('ram:CountryID', p.address.countryCode);
  x.close('ram:PostalTradeAddress');
  if (electronicAddress && p.electronicAddress) {
    x.open('ram:URIUniversalCommunication');
    x.leaf('ram:URIID', p.electronicAddress.value, { schemeID: p.electronicAddress.scheme });
    x.close('ram:URIUniversalCommunication');
  }
  if (p.vatIdentifier) {
    x.open('ram:SpecifiedTaxRegistration');
    x.leaf('ram:ID', p.vatIdentifier, { schemeID: 'VA' });
    x.close('ram:SpecifiedTaxRegistration');
  }
  x.close(`ram:${tag}`);
}

function lineItem(x: Xml, l: InvoiceLine): void {
  x.open('ram:IncludedSupplyChainTradeLineItem');

  x.open('ram:AssociatedDocumentLineDocument');
  x.leaf('ram:LineID', l.id);
  x.close('ram:AssociatedDocumentLineDocument');

  x.open('ram:SpecifiedTradeProduct');
  x.leaf('ram:Name', l.name);
  x.opt('ram:Description', l.description);
  x.close('ram:SpecifiedTradeProduct');

  x.open('ram:SpecifiedLineTradeAgreement');
  x.open('ram:NetPriceProductTradePrice');
  x.leaf('ram:ChargeAmount', amt(l.netPrice));
  x.close('ram:NetPriceProductTradePrice');
  x.close('ram:SpecifiedLineTradeAgreement');

  x.open('ram:SpecifiedLineTradeDelivery');
  x.leaf('ram:BilledQuantity', qty(l.quantity), { unitCode: l.unit });
  x.close('ram:SpecifiedLineTradeDelivery');

  x.open('ram:SpecifiedLineTradeSettlement');
  x.open('ram:ApplicableTradeTax');
  x.leaf('ram:TypeCode', 'VAT');
  x.leaf('ram:CategoryCode', l.vat.category);
  x.leaf('ram:RateApplicablePercent', pct(l.vat.rate));
  x.close('ram:ApplicableTradeTax');
  x.open('ram:SpecifiedTradeSettlementLineMonetarySummation');
  x.leaf('ram:LineTotalAmount', amt(l.netAmount));
  x.close('ram:SpecifiedTradeSettlementLineMonetarySummation');
  x.close('ram:SpecifiedLineTradeSettlement');

  x.close('ram:IncludedSupplyChainTradeLineItem');
}

function tradeTax(x: Xml, v: VatBreakdown): void {
  x.open('ram:ApplicableTradeTax');
  x.leaf('ram:CalculatedAmount', amt(v.taxAmount));
  x.leaf('ram:TypeCode', 'VAT');
  x.opt('ram:ExemptionReason', v.exemptionReasonText);
  x.leaf('ram:BasisAmount', amt(v.taxableAmount));
  x.leaf('ram:CategoryCode', v.category);
  x.opt('ram:ExemptionReasonCode', v.exemptionReasonCode);
  if (v.category === VAT_CATEGORY.STANDARD || v.category === VAT_CATEGORY.ZERO) {
    x.leaf('ram:RateApplicablePercent', pct(v.rate));
  } else {
    // Pour les catégories exonérées, le taux est 0.
    x.leaf('ram:RateApplicablePercent', pct(0));
  }
  x.close('ram:ApplicableTradeTax');
}

// ── Point d'entrée ─────────────────────────────────────────────────────────

export function buildCii(inv: En16931Invoice): string {
  const x = new Xml();
  x.raw('<?xml version="1.0" encoding="UTF-8"?>');
  x.open('rsm:CrossIndustryInvoice', {
    'xmlns:rsm': NS.rsm,
    'xmlns:ram': NS.ram,
    'xmlns:qdt': NS.qdt,
    'xmlns:udt': NS.udt,
  });

  // ── Contexte ──
  x.open('rsm:ExchangedDocumentContext');
  x.open('ram:GuidelineSpecifiedDocumentContextParameter');
  x.leaf('ram:ID', FACTURX_PROFILE_EN16931);
  x.close('ram:GuidelineSpecifiedDocumentContextParameter');
  x.close('rsm:ExchangedDocumentContext');

  // ── Document ──
  x.open('rsm:ExchangedDocument');
  x.leaf('ram:ID', inv.number);
  x.leaf('ram:TypeCode', inv.typeCode);
  dateTimeElem(x, 'ram:IssueDateTime', inv.issueDate);
  if (inv.note) {
    x.open('ram:IncludedNote');
    x.leaf('ram:Content', inv.note);
    x.close('ram:IncludedNote');
  }
  x.close('rsm:ExchangedDocument');

  // ── Transaction ──
  x.open('rsm:SupplyChainTradeTransaction');

  for (const l of inv.lines) lineItem(x, l);

  // Agreement (BG-4 / BG-7)
  x.open('ram:ApplicableHeaderTradeAgreement');
  x.opt('ram:BuyerReference', inv.buyerReference);
  tradeParty(x, 'SellerTradeParty', inv.seller);
  if (inv.buyer) tradeParty(x, 'BuyerTradeParty', inv.buyer);
  x.close('ram:ApplicableHeaderTradeAgreement');

  // Delivery (BT-72)
  x.open('ram:ApplicableHeaderTradeDelivery');
  if (inv.serviceDate) {
    x.open('ram:ActualDeliverySupplyChainEvent');
    dateTimeElem(x, 'ram:OccurrenceDateTime', inv.serviceDate);
    x.close('ram:ActualDeliverySupplyChainEvent');
  }
  x.close('ram:ApplicableHeaderTradeDelivery');

  // Settlement
  x.open('ram:ApplicableHeaderTradeSettlement');
  x.leaf('ram:InvoiceCurrencyCode', inv.currencyCode);

  if (inv.payment) {
    x.open('ram:SpecifiedTradeSettlementPaymentMeans');
    x.leaf('ram:TypeCode', inv.payment.meansCode);
    if (inv.payment.iban) {
      x.open('ram:PayeePartyCreditorFinancialAccount');
      x.leaf('ram:IBANID', inv.payment.iban);
      x.close('ram:PayeePartyCreditorFinancialAccount');
    }
    x.close('ram:SpecifiedTradeSettlementPaymentMeans');
  }

  for (const v of inv.vatBreakdown) tradeTax(x, v);

  if (inv.payment?.termsText || inv.dueDate) {
    x.open('ram:SpecifiedTradePaymentTerms');
    x.opt('ram:Description', inv.payment?.termsText);
    if (inv.dueDate) dateTimeElem(x, 'ram:DueDateDateTime', inv.dueDate);
    x.close('ram:SpecifiedTradePaymentTerms');
  }

  const t = inv.totals;
  x.open('ram:SpecifiedTradeSettlementHeaderMonetarySummation');
  x.leaf('ram:LineTotalAmount', amt(t.lineNetTotal));
  x.leaf('ram:TaxBasisTotalAmount', amt(t.taxExclusiveAmount));
  x.leaf('ram:TaxTotalAmount', amt(t.taxAmount), { currencyID: inv.currencyCode });
  x.leaf('ram:GrandTotalAmount', amt(t.taxInclusiveAmount));
  x.leaf('ram:TotalPrepaidAmount', amt(t.paidAmount ?? 0));
  x.leaf('ram:DuePayableAmount', amt(t.amountDueForPayment));
  x.close('ram:SpecifiedTradeSettlementHeaderMonetarySummation');

  if (inv.precedingInvoiceReference) {
    x.open('ram:InvoiceReferencedDocument');
    x.leaf('ram:IssuerAssignedID', inv.precedingInvoiceReference.number);
    if (inv.precedingInvoiceReference.issueDate) {
      x.open('ram:FormattedIssueDateTime');
      x.leaf('qdt:DateTimeString', d102(inv.precedingInvoiceReference.issueDate), { format: '102' });
      x.close('ram:FormattedIssueDateTime');
    }
    x.close('ram:InvoiceReferencedDocument');
  }

  x.close('ram:ApplicableHeaderTradeSettlement');
  x.close('rsm:SupplyChainTradeTransaction');
  x.close('rsm:CrossIndustryInvoice');

  return x.toString();
}
