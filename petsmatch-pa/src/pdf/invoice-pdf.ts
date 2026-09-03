/**
 * Rendu PDF lisible « de marque » d'une facture EN 16931 (cahier des charges §12
 * — la facture électronique porte une représentation visible).
 *
 * Ce PDF est le `sourcePdf` passé au builder Factur-X : le micro-service
 * l'emballe en PDF/A-3 avec le XML CII embarqué. S'il n'est pas fourni, le
 * micro-service produit un rendu minimal de repli.
 *
 * Porté depuis `website/src/lib/facture-pdf.ts` (même mise en page que l'app
 * Flutter et le rendu `/facture/[token]`), mais alimenté par le modèle
 * normalisé — PDF et XML sortent donc de la même source.
 */

import {
  type En16931Invoice,
  type InvoiceLine,
  PAYMENT_MEANS,
} from '../model/en16931.js';

const TEAL: [number, number, number] = [12, 92, 108];

const eur = (v: number): string => `${v.toFixed(2).replace('.', ',')} EUR`;
const fmtD = (iso?: string): string => {
  if (!iso) return '';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : iso;
};
const clean = (s?: string | null): string => (s ?? '').toString().trim();

const PAYMENT_LABEL: Record<string, string> = {
  [PAYMENT_MEANS.CASH]: 'Espèces',
  [PAYMENT_MEANS.CHEQUE]: 'Chèque',
  [PAYMENT_MEANS.CREDIT_TRANSFER]: 'Virement',
  [PAYMENT_MEANS.SEPA_CREDIT_TRANSFER]: 'Virement SEPA',
  [PAYMENT_MEANS.BANK_CARD]: 'Carte bancaire',
  [PAYMENT_MEANS.ONLINE_PAYMENT_SERVICE]: 'Paiement en ligne',
};

function lineLabel(l: InvoiceLine): string {
  return [clean(l.name), clean(l.description)].filter(Boolean).join(' — ');
}

/** Facture exonérée : aucune ventilation au taux standard. */
function isExempt(inv: En16931Invoice): boolean {
  return inv.totals.taxAmount === 0 && inv.vatBreakdown.every((v) => v.category !== 'S');
}

export async function renderInvoicePdf(inv: En16931Invoice): Promise<Uint8Array> {
  const { jsPDF } = await import('jspdf');
  const { autoTable } = await import('jspdf-autotable');

  const isAvoir = inv.typeCode === '381';
  const exempt = isExempt(inv);
  const franchise293B = inv.vatBreakdown.some((v) => (v.exemptionReasonText ?? '').includes('293 B'));
  const annee = (inv.issueDate || '').slice(0, 4) || String(new Date().getFullYear());

  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = 595;
  const M = 40;
  let y = 50;

  const s = inv.seller;
  const b = inv.buyer;

  // ── En-tête ────────────────────────────────────────────────────────────────
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(14);
  doc.setTextColor(...TEAL);
  doc.text((clean(s.name) || '—').slice(0, 60), M, y);

  doc.setFontSize(isAvoir ? 15 : 18);
  doc.text(isAvoir ? "FACTURE D'AVOIR" : 'FACTURE', W - M, y, { align: 'right' });

  doc.setFontSize(10);
  doc.setTextColor(40);
  doc.text(`N° ${inv.number || '—'}`, W - M, y + 16, { align: 'right' });

  y += 16;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(110);
  const emLines = [
    clean(s.legalForm)
      ? `${clean(s.legalForm)}${clean(s.shareCapital) ? ` au capital de ${clean(s.shareCapital)}` : ''}`
      : '',
    clean(s.address.line1),
    [clean(s.address.postCode), clean(s.address.city)].filter(Boolean).join(' '),
    clean(s.address.countryCode) === 'FR' ? 'France' : clean(s.address.countryCode),
    clean(s.contactPhone) ? `Tél. : ${clean(s.contactPhone)}` : '',
    clean(s.contactEmail),
    clean(s.siret) ? `SIRET : ${clean(s.siret)}` : '',
    clean(s.vatIdentifier) ? `N° TVA : ${clean(s.vatIdentifier)}` : '',
    clean(s.rcs),
    clean(s.rm) ? `RM : ${clean(s.rm)}` : '',
  ].filter(Boolean);
  emLines.forEach((l, i) => doc.text(l.slice(0, 80), M, y + 12 + i * 10));

  // Dates (à droite)
  let yd = y + 28;
  doc.text(`Date : ${fmtD(inv.issueDate)}`, W - M, yd, { align: 'right' });
  if (inv.serviceDate) {
    yd += 11;
    doc.text(`Prestation : ${fmtD(inv.serviceDate)}`, W - M, yd, { align: 'right' });
  }
  if (inv.dueDate) {
    yd += 11;
    doc.setFont('helvetica', 'bold');
    doc.text(`Échéance : ${fmtD(inv.dueDate)}`, W - M, yd, { align: 'right' });
    doc.setFont('helvetica', 'normal');
  }
  if (isAvoir && inv.precedingInvoiceReference) {
    yd += 11;
    doc.text(`Facture d'origine : ${inv.precedingInvoiceReference.number}`, W - M, yd, { align: 'right' });
  }

  y += 12 + emLines.length * 10 + 16;

  // ── Destinataire ───────────────────────────────────────────────────────────
  const clLines = b
    ? [
        clean(b.name) || '—',
        clean(b.address.line1),
        [clean(b.address.postCode), clean(b.address.city)].filter(Boolean).join(' '),
        clean(b.address.countryCode) === 'FR' ? 'France' : clean(b.address.countryCode),
        clean(b.contactEmail),
        clean(b.siret) ? `SIRET : ${clean(b.siret)}` : '',
        clean(b.vatIdentifier) ? `N° TVA : ${clean(b.vatIdentifier)}` : '',
      ].filter(Boolean)
    : ['Client particulier'];
  const clH = 20 + clLines.length * 11 + 8;
  doc.setFillColor(248, 248, 246);
  doc.roundedRect(W - M - 240, y, 240, clH, 4, 4, 'F');
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(7);
  doc.setTextColor(140);
  doc.text('DESTINATAIRE', W - M - 240 + 10, y + 13);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(40);
  clLines.forEach((l, i) => doc.text(l.slice(0, 48), W - M - 240 + 10, y + 26 + i * 11));

  y += clH + 16;

  // ── Lignes ─────────────────────────────────────────────────────────────────
  autoTable(doc, {
    startY: y,
    margin: { left: M, right: M },
    head: exempt
      ? [['Désignation', 'Qté', 'P.U.', 'Total']]
      : [['Désignation', 'Qté', 'P.U. HT', 'TVA', 'Total HT']],
    body: inv.lines.map((l) =>
      exempt
        ? [lineLabel(l), String(l.quantity), eur(l.netPrice), eur(l.netAmount)]
        : [lineLabel(l), String(l.quantity), eur(l.netPrice), `${l.vat.rate} %`, eur(l.netAmount)],
    ),
    headStyles: { fillColor: TEAL, fontSize: 9 },
    bodyStyles: { fontSize: 9 },
    columnStyles: exempt
      ? { 1: { halign: 'center' }, 2: { halign: 'right' }, 3: { halign: 'right' } }
      : { 1: { halign: 'center' }, 2: { halign: 'right' }, 3: { halign: 'right' }, 4: { halign: 'right' } },
  });

  const at = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable;
  y = (at?.finalY ?? y + 40) + 16;

  const lineTotal = (label: string, value: string, bold = false): void => {
    doc.setFont('helvetica', bold ? 'bold' : 'normal');
    doc.setFontSize(bold ? 11 : 9);
    doc.setTextColor(...(bold ? TEAL : [90, 90, 90] as [number, number, number]));
    doc.text(label, W - M - 200, y);
    doc.text(value, W - M, y, { align: 'right' });
    y += bold ? 16 : 12;
  };
  if (exempt) {
    lineTotal('TOTAL', eur(inv.totals.taxInclusiveAmount), true);
  } else {
    lineTotal('Total HT', eur(inv.totals.taxExclusiveAmount));
    lineTotal('TVA', eur(inv.totals.taxAmount));
    lineTotal('TOTAL TTC', eur(inv.totals.taxInclusiveAmount), true);
  }
  if ((inv.totals.paidAmount ?? 0) > 0) {
    lineTotal('Déjà réglé', eur(inv.totals.paidAmount ?? 0));
    lineTotal('Reste à payer', eur(inv.totals.amountDueForPayment), true);
  }

  y += 16;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  if (inv.payment?.meansCode) {
    doc.text(`Mode de paiement : ${PAYMENT_LABEL[inv.payment.meansCode] ?? inv.payment.meansCode}`, M, y);
    y += 11;
  }
  if (inv.payment?.iban) {
    doc.text(`IBAN : ${inv.payment.iban}${inv.payment.bic ? `  —  BIC : ${inv.payment.bic}` : ''}`, M, y);
    y += 11;
  }
  if (inv.payment?.termsText) {
    const tl = doc.splitTextToSize(inv.payment.termsText, W - M * 2);
    doc.text(tl, M, y);
    y += tl.length * 10 + 4;
  }
  if (inv.note) {
    const nl = doc.splitTextToSize(inv.note, W - M * 2);
    doc.text(nl, M, y);
    y += nl.length * 10 + 4;
  }

  // ── Mentions légales obligatoires ──────────────────────────────────────────
  y += 8;
  doc.setFontSize(7.5);
  doc.setTextColor(120);
  const escompteText = inv.payment?.termsText?.includes('scompte')
    ? ''
    : 'Escompte pour paiement anticipé : néant.';
  const mentions = [
    franchise293B ? 'TVA non applicable, art. 293 B du CGI.' : '',
    escompteText,
    `En cas de retard de paiement : pénalités au taux de 3 fois le taux d'intérêt légal en vigueur (${annee}), ` +
      `exigibles sans rappel le lendemain de la date d'échéance, et indemnité forfaitaire de recouvrement de 40 € ` +
      `(art. L441-10 et D441-5 du Code de commerce).`,
  ]
    .filter(Boolean)
    .join(' ');
  const ml = doc.splitTextToSize(mentions, W - M * 2);
  doc.setDrawColor(200);
  doc.rect(M, y, W - M * 2, ml.length * 9 + 14);
  doc.text(ml, M + 7, y + 12);

  const buf = doc.output('arraybuffer');
  return new Uint8Array(buf);
}
