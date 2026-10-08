// Ordonnance vétérinaire générée depuis le compte rendu (mes-patients/[id]) :
// en-tête de la clinique (n° d'Ordre), patient, propriétaire, médicaments
// (posologie, durée), prescripteur. Miroir app : lib/pages/pro/ordonnance_pdf.dart.

export interface LigneOrdonnance { medicament: string; posologie: string; dureeJours?: number | null; notes?: string }

export interface OrdonnanceData {
  cliniqueNom: string;
  cliniqueAdresse?: string;
  cliniqueTel?: string;
  numeroOrdre?: string;
  prescripteur: string;
  animalNom: string;
  animalEspeceRace?: string;
  animalIdentification?: string;
  animalPoids?: string;
  proprietaire?: string;
  lignes: LigneOrdonnance[];
  date?: Date;
}

const TEAL: [number, number, number] = [12, 92, 108];
const DARK: [number, number, number] = [30, 32, 37];
const GREY: [number, number, number] = [111, 118, 123];

export async function ordonnancePdfBlob(d: OrdonnanceData): Promise<Blob> {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight();
  const M = 40;
  const jour = (d.date ?? new Date()).toLocaleDateString('fr-FR');
  let y = 50;

  // En-tête clinique
  doc.setFont('helvetica', 'bold'); doc.setFontSize(15); doc.setTextColor(...TEAL);
  doc.text(d.cliniqueNom, M, y);
  doc.setFontSize(13); doc.text('ORDONNANCE', W - M, y, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...DARK);
  doc.text(`Le ${jour}`, W - M, y + 14, { align: 'right' });
  for (const l of [d.cliniqueAdresse, d.cliniqueTel ? `Tél. ${d.cliniqueTel}` : '', d.numeroOrdre ? `N° d'inscription à l'Ordre : ${d.numeroOrdre}` : '']) {
    if (!l) continue;
    y += 13; doc.text(l, M, y);
  }
  y += 16;
  doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y);
  y += 14;

  // Patient / propriétaire
  const boxTop = y;
  doc.setFillColor(244, 247, 246); doc.roundedRect(M, boxTop, W - 2 * M, 78, 6, 6, 'F');
  const col2 = M + (W - 2 * M) / 2 + 8;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TEAL);
  doc.text('Patient', M + 10, boxTop + 16); doc.text('Propriétaire', col2, boxTop + 16);
  doc.setFontSize(11); doc.setTextColor(...DARK);
  doc.text(d.animalNom, M + 10, boxTop + 31);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(10);
  doc.text(d.proprietaire || '—', col2, boxTop + 31);
  doc.setFontSize(9);
  let yy = boxTop + 44;
  for (const [l, v] of [['Espèce / race', d.animalEspeceRace], ['Identification', d.animalIdentification], ['Poids', d.animalPoids]] as const) {
    if (!v) continue;
    doc.setTextColor(...GREY); doc.text(`${l} : `, M + 10, yy);
    doc.setTextColor(...DARK); doc.text(v, M + 10 + doc.getTextWidth(`${l} : `), yy);
    yy += 11;
  }
  y = boxTop + 98;

  // Prescription
  d.lignes.forEach((l, i) => {
    doc.setFillColor(...TEAL); doc.circle(M + 9, y - 3, 9, 'F');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(255, 255, 255);
    doc.text(String(i + 1), M + 9, y, { align: 'center' });
    doc.setFontSize(11); doc.setTextColor(...DARK);
    doc.text(l.medicament, M + 28, y);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10);
    let ly = y;
    if (l.posologie) { const t = doc.splitTextToSize(l.posologie, W - 2 * M - 28); ly += 13; doc.text(t, M + 28, ly); ly += (t.length - 1) * 12; }
    if (l.dureeJours) { ly += 12; doc.setTextColor(...GREY); doc.setFontSize(9.5); doc.text(`Pendant ${l.dureeJours} jour${l.dureeJours > 1 ? 's' : ''}`, M + 28, ly); }
    if (l.notes) { ly += 12; doc.setTextColor(...GREY); doc.setFontSize(9); doc.setFont('helvetica', 'italic'); doc.text(doc.splitTextToSize(l.notes, W - 2 * M - 28), M + 28, ly); doc.setFont('helvetica', 'normal'); }
    y = ly + 22;
  });

  // Prescripteur
  const sy = H - 150;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...DARK);
  doc.text(`Dr ${d.prescripteur}`, W - M - 180, sy);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...GREY);
  doc.text('Vétérinaire', W - M - 180, sy + 12);
  doc.setDrawColor(...GREY); doc.line(W - M - 180, sy + 50, W - M - 20, sy + 50);
  doc.setFontSize(8); doc.text('Signature', W - M - 180, sy + 61);
  doc.setFont('helvetica', 'italic'); doc.setFontSize(7.5);
  doc.text('Ordonnance établie via PetsMatch — à présenter en pharmacie / à conserver dans le carnet de santé.', M, H - 40);

  return doc.output('blob');
}

export interface CompteRenduData {
  cliniqueNom: string; cliniqueAdresse?: string; cliniqueTel?: string;
  praticien: string; animalNom: string; animalEspeceRace?: string; animalIdentification?: string;
  proprietaire?: string; contenu: string; date?: Date;
}

/** Compte rendu de consultation en PDF (impression / envoi au propriétaire). */
export async function compteRenduPdfBlob(d: CompteRenduData): Promise<Blob> {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight();
  const M = 40;
  let y = 50;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(15); doc.setTextColor(...TEAL);
  doc.text(d.cliniqueNom, M, y);
  doc.setFontSize(13); doc.text('COMPTE RENDU', W - M, y, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...DARK);
  doc.text(`Le ${(d.date ?? new Date()).toLocaleDateString('fr-FR')}`, W - M, y + 14, { align: 'right' });
  for (const l of [d.cliniqueAdresse, d.cliniqueTel ? `Tél. ${d.cliniqueTel}` : '']) { if (l) { y += 13; doc.text(l, M, y); } }
  y += 16; doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y); y += 14;
  doc.setFillColor(244, 247, 246); doc.roundedRect(M, y, W - 2 * M, 64, 6, 6, 'F');
  const col2 = M + (W - 2 * M) / 2 + 8;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TEAL);
  doc.text('Patient', M + 10, y + 16); doc.text('Propriétaire', col2, y + 16);
  doc.setFontSize(11); doc.setTextColor(...DARK); doc.text(d.animalNom, M + 10, y + 31);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.text(d.proprietaire || '—', col2, y + 31);
  doc.setFontSize(9);
  const infos = [d.animalEspeceRace, d.animalIdentification ? `Identification : ${d.animalIdentification}` : ''].filter(Boolean).join(' · ');
  if (infos) doc.text(infos, M + 10, y + 45);
  y += 86;
  doc.setFontSize(10.5);
  for (const ligne of doc.splitTextToSize(d.contenu || '', W - 2 * M) as string[]) {
    if (y > H - 90) { doc.addPage(); y = 50; }
    doc.text(ligne, M, y); y += 14;
  }
  y = Math.min(y + 24, H - 70);
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.text(`Dr ${d.praticien}`, W - M - 180, y);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...GREY); doc.text('Vétérinaire', W - M - 180, y + 12);
  return doc.output('blob');
}
