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
  const annee = new Date().getFullYear();
  const em = d.emetteur ?? {};
  const escompte = (d.escompte ?? '').trim() || 'Escompte pour paiement anticipe : neant.';

  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const M = 40;
  let y = 50;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(15);
  doc.setTextColor(...TEAL);
  doc.text(String(em.nom || d.pensionNom).slice(0, 60), M, y);
  doc.setFontSize(15);
  doc.text(d.isAcompte ? "FACTURE D'ACOMPTE" : 'FACTURE', 595 - M, y, { align: 'right' });
  y += 14;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(110);
  const emLines = [
    em.formeJuridique ? `${em.formeJuridique}${em.capital ? ` - capital ${em.capital}` : ''}` : '',
    em.adresse ?? '',
    em.tel ? `Tel. : ${em.tel}` : '',
    em.email ?? '',
    em.siret ? `SIRET : ${em.siret}` : '',
    em.tva ? `N TVA : ${em.tva}` : '',
    em.rcs ?? '',
  ].filter(Boolean) as string[];
  emLines.forEach((l, i) => doc.text(String(l).slice(0, 70), M, y + i * 10));
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9);
  doc.setTextColor(40);
  doc.text(`N ${d.numero}`, 595 - M, y, { align: 'right' });
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(110);
  doc.text(`Emise le ${emise}`, 595 - M, y + 12, { align: 'right' });
  if (d.echeance) doc.text(`Echeance : ${fmtD(d.echeance)}`, 595 - M, y + 22, { align: 'right' });
  if (d.isAcompte) doc.text(`Acompte de ${pct}% du sejour`, 595 - M, y + (d.echeance ? 32 : 22), { align: 'right' });
  y += Math.max(emLines.length * 10, 34) + 14;

  const boxW = (595 - M * 2 - 16) / 3;
  const boxes: [string, string[]][] = [
    ['ANIMAL', [
      `${d.animal.nom ?? '—'}${d.animal.espece ? ` · ${espLabel(d.animal.espece)}` : ''}`,
      ...(d.animal.race ? [d.animal.race] : []),
      ...(d.animal.puce ? [`Puce : ${d.animal.puce}`] : []),
    ]],
    ['CLIENT', [
      d.proprietaire.nom ?? '—',
      ...(d.proprietaire.adresse ? [d.proprietaire.adresse] : []),
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

  y += 18;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  const pay = d.isAcompte
    ? `Acompte a regler pour confirmer la reservation. Le solde de ${eur(total - montant)} sera facture a la fin du sejour.`
    : d.echeance ? `Paiement du au plus tard le ${fmtD(d.echeance)}.` : 'Paiement a reception de facture.';
  doc.text(doc.splitTextToSize(pay, 595 - M * 2), M, y);
  y += 22;

  doc.setFontSize(7.5);
  doc.setTextColor(120);
  const mentions = [
    d.avecTVA ? '' : 'TVA non applicable, art. 293 B du CGI.',
    escompte,
    `En cas de retard de paiement : penalites au taux de 3 fois le taux d'interet legal en vigueur (${annee}), exigibles sans rappel le lendemain de la date d'echeance, et indemnite forfaitaire de recouvrement de 40 EUR (art. L441-10 et D441-5 du Code de commerce).`,
  ].filter(Boolean).join(' ');
  doc.text(doc.splitTextToSize(mentions, 595 - M * 2), M, y);

  return doc.output('blob');
}
