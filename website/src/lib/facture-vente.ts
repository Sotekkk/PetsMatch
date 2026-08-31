// Génération d'une facture de vente d'animal (PDF, côté navigateur, jsPDF).
// Miroir web de `factureVentePdfBytes` (app Flutter, contrat_pdf.dart).

const TEAL: [number, number, number] = [12, 92, 108];

const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} €`;
const fmtD = (iso?: string | null) => {
  if (!iso) return new Date().toLocaleDateString('fr-FR');
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
};

export interface FactureVenteData {
  numero: string;
  date?: string | null;
  montantTtc: number;
  acompte?: number;
  tvaTaux?: number;           // 0 = non assujetti
  emetteur: { nom: string; adresse?: string; siret?: string; tel?: string; email?: string };
  client: { nom?: string; adresse?: string; tel?: string; email?: string };
  animal: { nom?: string | null; espece?: string | null; race?: string | null; identification?: string | null; date_naissance?: string | null };
  modePaiement?: string;
}

export async function factureVentePdfBlob(d: FactureVenteData): Promise<Blob> {
  const { jsPDF } = await import('jspdf');

  const assujetti = (d.tvaTaux ?? 0) > 0;
  const ttc = d.montantTtc || 0;
  const ht = assujetti ? ttc / (1 + (d.tvaTaux as number) / 100) : ttc;
  const tva = ttc - ht;
  const acompte = d.acompte ?? 0;
  const reste = ttc - acompte;

  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const M = 40;
  const W = 595;
  let y = 52;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(18);
  doc.setTextColor(...TEAL);
  doc.text('FACTURE', M, y);
  y += 15;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(110);
  doc.text(`N° ${d.numero}   ·   ${fmtD(d.date)}`, M, y);
  y += 22;

  const colW = (W - M * 2 - 16) / 2;
  const block = (x: number, titre: string, lignes: string[]) => {
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(8);
    doc.setTextColor(120);
    doc.text(titre, x, y);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(9);
    doc.setTextColor(40);
    lignes.filter(Boolean).slice(0, 6).forEach((l, i) => doc.text(doc.splitTextToSize(l, colW), x, y + 14 + i * 12));
  };
  block(M, 'ÉMETTEUR', [
    d.emetteur.nom,
    d.emetteur.adresse ?? '',
    d.emetteur.siret ? `SIRET : ${d.emetteur.siret}` : '',
    d.emetteur.tel ?? '',
    d.emetteur.email ?? '',
  ]);
  block(M + colW + 16, 'CLIENT', [
    d.client.nom ?? '',
    d.client.adresse ?? '',
    d.client.tel ?? '',
    d.client.email ?? '',
  ]);
  y += 14 + 6 * 12;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9);
  doc.setTextColor(40);
  doc.text('Désignation', M, y);
  y += 13;
  doc.setFont('helvetica', 'normal');
  const especeRace = [d.animal.espece, d.animal.race].filter(Boolean).join(' — ');
  const design = [
    d.animal.nom ? `Animal : ${d.animal.nom}` : '',
    especeRace,
    d.animal.identification ? `Puce n° ${d.animal.identification}` : '',
    d.animal.date_naissance ? `Né(e) le ${fmtD(d.animal.date_naissance)}` : '',
  ].filter(Boolean).join('  ·  ');
  doc.setTextColor(70);
  doc.text(doc.splitTextToSize(`Cession d'un animal de compagnie${design ? ` — ${design}` : ''}`, W - M * 2), M, y);
  y += 26;

  const bx = W - M - 230;
  doc.setDrawColor(200);
  doc.roundedRect(bx, y - 12, 230, assujetti || acompte > 0 ? 84 : 30, 3, 3, 'S');
  const totLine = (label: string, value: string, bold = false) => {
    doc.setFont('helvetica', bold ? 'bold' : 'normal');
    doc.setFontSize(bold ? 11 : 9);
    doc.setTextColor(bold ? TEAL[0] : 90, bold ? TEAL[1] : 90, bold ? TEAL[2] : 90);
    doc.text(label, bx + 10, y);
    doc.text(value, W - M - 10, y, { align: 'right' });
    y += bold ? 16 : 13;
  };
  if (assujetti) {
    totLine('Total HT', eur(ht));
    totLine(`TVA (${String(d.tvaTaux).replace('.', ',')} %)`, eur(tva));
  }
  totLine('Total TTC', eur(ttc), true);
  if (acompte > 0) {
    totLine('Acompte déjà versé', `- ${eur(acompte)}`);
    totLine('Reste à payer', eur(reste), true);
  }

  y += 16;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(90);
  if (d.modePaiement) { doc.text(`Mode de règlement : ${d.modePaiement}`, M, y); y += 13; }
  if (!assujetti) { doc.text('TVA non applicable, art. 293 B du CGI.', M, y); y += 13; }

  doc.setFontSize(8);
  doc.setTextColor(150);
  doc.text(`Facture générée via PetsMatch le ${fmtD(d.date)}`, M, 800);

  return doc.output('blob');
}
