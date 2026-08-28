// Génération d'un vrai PDF de facture de pension, côté navigateur (jsPDF).
// Même contenu que pensionInvoiceHtml — utilisé pour stocker le PDF et le
// joindre à l'email au propriétaire.

import type { PensionFactureData } from './pension-facture-html';

const TEAL: [number, number, number] = [12, 92, 108];

const ESP: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau', cheval: 'Cheval',
  nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc', ane: 'Âne',
};
const espLabel = (e?: string | null) => ESP[e ?? ''] ?? (e ?? '');
const fmtD = (iso?: string | null) => {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
};
const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} EUR`;

export async function pensionInvoicePdfBlob(d: PensionFactureData): Promise<Blob> {
  const { jsPDF } = await import('jspdf');
  const autoTable = (await import('jspdf-autotable')).default;

  const nuits = Math.max(1, Math.round(d.nuits || 1));
  const tarif = d.tarifNuit || 0;
  const supp = d.suppMontant || 0;
  const sousTotal = tarif * nuits + supp;
  const tva = d.avecTVA ? sousTotal * 0.2 : 0;
  const total = sousTotal + tva;
  const pct = Math.min(100, Math.max(1, Math.round(d.acomptePct || 30)));
  const montant = d.isAcompte ? Math.round(total * pct) / 100 : total;
  const emise = d.emiseLe ? fmtD(d.emiseLe) : new Date().toLocaleDateString('fr-FR');

  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const M = 40;
  let y = 50;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(18);
  doc.setTextColor(...TEAL);
  doc.text(d.isAcompte ? `Facture d'acompte ${d.numero}` : `Facture ${d.numero}`, M, y);
  y += 16;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(110);
  doc.text(`${d.pensionNom} — émise le ${emise}${d.isAcompte ? ` · acompte de ${pct}% du séjour` : ''}`, M, y);
  y += 20;

  const boxW = (595 - M * 2 - 16) / 3;
  const boxes: [string, string[]][] = [
    ['ANIMAL', [
      `${d.animal.nom ?? '—'}${d.animal.espece ? ` · ${espLabel(d.animal.espece)}` : ''}`,
      ...(d.animal.race ? [d.animal.race] : []),
      ...(d.animal.puce ? [`Puce : ${d.animal.puce}`] : []),
    ]],
    ['PROPRIÉTAIRE', [
      d.proprietaire.nom ?? '—',
      ...(d.proprietaire.email ? [d.proprietaire.email] : []),
      ...(d.proprietaire.contact ? [d.proprietaire.contact] : []),
    ]],
    ['SÉJOUR', [
      `Entrée : ${fmtD(d.sejour.dateEntree)}`,
      `Sortie : ${fmtD(d.sejour.dateSortie)}`,
      `${nuits} nuit${nuits > 1 ? 's' : ''}`,
    ]],
  ];
  const boxH = 62;
  boxes.forEach(([titre, lignes], i) => {
    const x = M + i * (boxW + 8);
    doc.setFillColor(248, 248, 246);
    doc.roundedRect(x, y, boxW, boxH, 4, 4, 'F');
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(7);
    doc.setTextColor(140);
    doc.text(titre, x + 8, y + 12);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8.5);
    doc.setTextColor(40);
    lignes.slice(0, 4).forEach((l, j) => doc.text(String(l).slice(0, 42), x + 8, y + 26 + j * 11));
  });
  y += boxH + 18;

  autoTable(doc, {
    startY: y,
    margin: { left: M, right: M },
    head: [['Description', 'Qté', 'P.U. HT', 'Total HT']],
    body: [
      [
        `Pension du ${fmtD(d.sejour.dateEntree)} au ${fmtD(d.sejour.dateSortie)}`,
        String(nuits), eur(tarif), eur(tarif * nuits),
      ],
      ...(supp > 0 ? [[d.suppDesc || 'Suppléments', '1', eur(supp), eur(supp)]] : []),
    ],
    headStyles: { fillColor: TEAL, fontSize: 9 },
    bodyStyles: { fontSize: 9 },
    columnStyles: { 1: { halign: 'center' }, 2: { halign: 'right' }, 3: { halign: 'right' } },
  });

  // @ts-expect-error lastAutoTable est ajouté par le plugin
  y = (doc.lastAutoTable?.finalY ?? y + 40) + 16;

  const lineTotal = (label: string, value: string, bold = false) => {
    doc.setFont('helvetica', bold ? 'bold' : 'normal');
    doc.setFontSize(bold ? 11 : 9);
    doc.setTextColor(bold ? TEAL[0] : 90, bold ? TEAL[1] : 90, bold ? TEAL[2] : 90);
    doc.text(label, 595 - M - 200, y);
    doc.text(value, 595 - M, y, { align: 'right' });
    y += bold ? 16 : 12;
  };
  if (d.avecTVA) {
    lineTotal('Sous-total HT', eur(sousTotal));
    lineTotal('TVA 20%', eur(tva));
  }
  if (d.isAcompte) {
    lineTotal(d.avecTVA ? 'Total TTC séjour' : 'Total séjour', eur(total), true);
    lineTotal('Solde à la sortie', eur(total - montant));
    lineTotal(`ACOMPTE ${pct}% À RÉGLER`, eur(montant), true);
  } else {
    lineTotal(d.avecTVA ? 'TOTAL TTC' : 'TOTAL', eur(total), true);
  }

  y += 20;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(150);
  const foot = d.isAcompte
    ? `Acompte à régler pour confirmer la réservation. Le solde de ${eur(total - montant)} sera facturé à la fin du séjour. Document généré via PetsMatch.`
    : 'Paiement à réception de facture. Document généré via PetsMatch.';
  doc.text(doc.splitTextToSize(foot, 595 - M * 2), M, y);

  return doc.output('blob');
}
