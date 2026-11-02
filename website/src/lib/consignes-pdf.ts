// PDF « Consignes après l'intervention de … » pour le propriétaire : en-tête
// de la clinique, animal / propriétaire, sections (titres, listes, gras),
// signature du vétérinaire, pages numérotées. Miroir appli :
// lib/pages/pro/consignes_pdf.dart.

import { blocsConsigne, type SectionConsigne, type Segment } from './consignes-postop';

const TEAL: [number, number, number] = [12, 92, 108];
const DARK: [number, number, number] = [30, 32, 37];
const GREY: [number, number, number] = [111, 118, 123];

export interface ConsignesData {
  cliniqueNom: string; cliniqueAdresse?: string; cliniqueTel?: string; cliniqueEmail?: string;
  praticien: string; animalNom: string; animalEspeceRace?: string;
  proprietaire?: string; proprietaireCoord?: string[];
  dateIntervention?: Date | null;
  sections: SectionConsigne[];
  signature?: string | null;
  apercu?: boolean;
}

export async function consignesPdfBlob(d: ConsignesData): Promise<Blob> {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight();
  const M = 40, BAS = H - 60;
  let y = 50;
  const nouvellePage = () => { doc.addPage(); y = 50; };
  const place = (h: number) => { if (y + h > BAS) nouvellePage(); };

  // En-tête
  doc.setFont('helvetica', 'bold'); doc.setFontSize(14); doc.setTextColor(...TEAL);
  doc.text(d.cliniqueNom, M, y);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...DARK);
  for (const l of [d.cliniqueAdresse, d.cliniqueTel ? `Tél. ${d.cliniqueTel}` : '', d.cliniqueEmail]) { if (l) { y += 12; doc.text(l, M, y); } }
  y += 26;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(16); doc.setTextColor(...TEAL);
  for (const t of doc.splitTextToSize(`Consignes après l'intervention de ${d.animalNom}`, W - 2 * M) as string[]) { doc.text(t, M, y); y += 19; }
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...GREY);
  const sous = [d.animalEspeceRace, d.dateIntervention ? `Intervention du ${d.dateIntervention.toLocaleDateString('fr-FR')}` : '',
    d.proprietaire ? `Propriétaire : ${d.proprietaire}` : ''].filter(Boolean).join(' · ');
  if (sous) { for (const t of doc.splitTextToSize(sous, W - 2 * M) as string[]) { doc.text(t, M, y); y += 12; } }
  if (d.apercu) {
    y += 4; doc.setFillColor(255, 248, 234); doc.roundedRect(M, y - 10, W - 2 * M, 20, 4, 4, 'F');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(138, 90, 0);
    doc.text('APERÇU — document non validé par le vétérinaire', W / 2, y + 3, { align: 'center' }); y += 16;
  }
  y += 10; doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y); y += 20;

  // Texte avec segments gras, retour à la ligne automatique.
  const ecrireSegments = (segments: Segment[], x: number, largeur: number, taille: number) => {
    doc.setFontSize(taille);
    const mots: { t: string; gras: boolean }[] = [];
    for (const s of segments) for (const m of s.texte.split(/(\s+)/)) if (m) mots.push({ t: m, gras: s.gras });
    let ligne: { t: string; gras: boolean }[] = [], larg = 0;
    const largeurMot = (m: { t: string; gras: boolean }) => { doc.setFont('helvetica', m.gras ? 'bold' : 'normal'); return doc.getTextWidth(m.t); };
    const vider = () => {
      place(taille + 4);
      let cx = x;
      for (const m of ligne) { doc.setFont('helvetica', m.gras ? 'bold' : 'normal'); doc.setTextColor(...DARK); doc.text(m.t, cx, y); cx += doc.getTextWidth(m.t); }
      y += taille + 4; ligne = []; larg = 0;
    };
    for (const m of mots) {
      const w = largeurMot(m);
      if (larg + w > largeur && ligne.length && m.t.trim()) vider();
      if (!ligne.length && !m.t.trim()) continue;
      ligne.push(m); larg += w;
    }
    if (ligne.length) vider();
  };

  for (const s of d.sections.filter(x => x.texte.trim())) {
    place(40);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(11.5); doc.setTextColor(...TEAL);
    doc.text(s.titre, M, y); y += 16;
    for (const b of blocsConsigne(s.texte)) {
      if (b.type === 'titre') { y += 2; ecrireSegments(b.segments.map(x => ({ ...x, gras: true })), M, W - 2 * M, 10.5); }
      else if (b.type === 'puce') {
        place(14);
        doc.setFillColor(...DARK); doc.circle(M + 6, y - 3.5, 1.6, 'F');
        ecrireSegments(b.segments, M + 16, W - 2 * M - 16, 10);
      } else ecrireSegments(b.segments, M, W - 2 * M, 10);
    }
    y += 12;
  }

  // Signature du vétérinaire
  place(100);
  y += 10;
  const xs = W - M - 180;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...DARK);
  if (d.praticien.trim() && d.praticien.trim().toLowerCase() !== 'vétérinaire') { doc.text(`Dr ${d.praticien.trim()}`, xs, y); y += 13; }
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...GREY);
  doc.text('Vétérinaire', xs, y);
  if (d.signature && !d.apercu) { try { doc.addImage(d.signature, 'PNG', xs, y + 4, 130, 52); } catch { /* signature illisible */ } }

  const n = doc.getNumberOfPages();
  for (let p = 1; p <= n; p++) {
    doc.setPage(p);
    doc.setFont('helvetica', 'italic'); doc.setFontSize(7.5); doc.setTextColor(...GREY);
    doc.text('En cas de doute ou d’inquiétude, contactez la clinique.', M, H - 40);
    doc.setFont('helvetica', 'normal');
    doc.text(`Page ${p} / ${n}`, W - M, H - 40, { align: 'right' });
  }
  return doc.output('blob');
}
