// Ordonnance vétérinaire générée depuis le compte rendu (mes-patients/[id]) :
// en-tête de la clinique (n° d'Ordre), patient, propriétaire, médicaments
// (posologie, durée), prescripteur. Miroir app : lib/pages/pro/ordonnance_pdf.dart.

import { majuscule } from './majuscule';

export interface LigneOrdonnance { medicament: string; posologie: string; dureeJours?: number | null; notes?: string }

export interface OrdonnanceData {
  cliniqueNom: string;
  cliniqueAdresse?: string;
  cliniqueTel?: string;
  numeroOrdre?: string;
  prescripteur: string;
  animalNom: string;
  animalEspeceRace?: string;
  animalSexe?: string;
  animalAge?: string;
  animalIdentification?: string;
  animalPoids?: string;
  proprietaire?: string;
  lignes: LigneOrdonnance[];
  date?: Date;
  /** Signature manuscrite du prescripteur (data-URL PNG). */
  signature?: string | null;
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
  const infosOrdo = ([['Espèce / race', d.animalEspeceRace], ['Sexe', d.animalSexe], ['Âge', d.animalAge],
    ['Identification', d.animalIdentification], ['Poids', d.animalPoids]] as const).filter(([, v]) => !!v) as [string, string][];
  const hOrdo = Math.max(78, 44 + infosOrdo.length * 11);
  doc.setFillColor(244, 247, 246); doc.roundedRect(M, boxTop, W - 2 * M, hOrdo, 6, 6, 'F');
  const col2 = M + (W - 2 * M) / 2 + 8;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TEAL);
  doc.text('Patient', M + 10, boxTop + 16); doc.text('Propriétaire', col2, boxTop + 16);
  doc.setFontSize(11); doc.setTextColor(...DARK);
  doc.text(d.animalNom, M + 10, boxTop + 31);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(10);
  doc.text(d.proprietaire || '—', col2, boxTop + 31);
  doc.setFontSize(9);
  let yy = boxTop + 44;
  for (const [l, v] of infosOrdo) {
    doc.setTextColor(...GREY); doc.text(`${l} : `, M + 10, yy);
    doc.setTextColor(...DARK); doc.text(majuscule(v), M + 10 + doc.getTextWidth(`${l} : `), yy);
    yy += 11;
  }
  y = boxTop + hOrdo + 20;

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
  if (d.prescripteur.trim() && d.prescripteur.trim().toLowerCase() !== 'vétérinaire') doc.text(`Dr ${d.prescripteur}`, W - M - 180, sy);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...GREY);
  doc.text('Vétérinaire', W - M - 180, sy + 12);
  if (d.signature) { try { doc.addImage(d.signature, 'PNG', W - M - 180, sy + 14, 130, 52); } catch { /* signature illisible */ } }
  doc.setDrawColor(...GREY); doc.line(W - M - 180, sy + 68, W - M - 20, sy + 68);
  doc.setFontSize(8); doc.text('Signature', W - M - 180, sy + 79);
  doc.setFont('helvetica', 'italic'); doc.setFontSize(7.5);
  doc.text('Ordonnance établie via PetsMatch — à présenter en pharmacie / à conserver dans le carnet de santé.', M, H - 40);

  return doc.output('blob');
}

export interface CompteRenduData {
  cliniqueNom: string; cliniqueAdresse?: string; cliniqueTel?: string; cliniqueEmail?: string;
  praticien: string; animalNom: string; animalEspeceRace?: string; animalSexe?: string; animalAge?: string;
  animalIdentification?: string;
  proprietaire?: string; contenu: string; date?: Date;
  /** Signature manuscrite du vétérinaire (data-URL PNG). */
  signature?: string | null;
}

/** Âge de l'animal (« 5 mois », « 3 ans ») d'après sa date de naissance,
 *  sinon l'âge estimé saisi. Miroir appli : ageAnimal (ordonnance_pdf.dart). */
export function ageAnimal(naissance?: string | null, estime?: string | number | null): string {
  const d = naissance ? new Date(naissance) : null;
  if (d && !isNaN(d.getTime())) {
    const n = new Date();
    const mois = (n.getFullYear() - d.getFullYear()) * 12 + n.getMonth() - d.getMonth() - (n.getDate() < d.getDate() ? 1 : 0);
    if (mois < 0) return '';
    if (mois < 12) return `${mois} mois`;
    const ans = Math.floor(mois / 12);
    return `${ans} an${ans > 1 ? 's' : ''}`;
  }
  const e = String(estime ?? '').trim();
  return /^\d+$/.test(e) ? `${e} an${Number(e) > 1 ? 's' : ''} (estimé)` : e;
}

/** « Femelle » / « Mâle » quel que soit le codage (F, femelle, female…). */
export function sexeAnimal(sexe?: string | null): string {
  const s = (sexe ?? '').trim().toLowerCase();
  if (!s) return '';
  return s.startsWith('f') ? 'Femelle' : s.startsWith('m') ? 'Mâle' : (sexe ?? '');
}

// Paragraphes du CR : titre en gras (« Motif : », « Poids : », « Recommandations »…).
const TITRE_PARAGRAPHE = /^([A-ZÀ-Ý][^:\n.]{0,40}?)\s*:\s*([\s\S]*)$/;
const TITRE_SEUL = /^(recommandations?|conclusion|conseils?|diagnostic|examen clinique|observations?|traitement)\s*:?\s*$/i;

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
  for (const l of [d.cliniqueAdresse, d.cliniqueTel ? `Tél. ${d.cliniqueTel}` : '', d.cliniqueEmail]) { if (l) { y += 13; doc.text(l, M, y); } }
  y += 16; doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y); y += 14;
  const infosPatient = ([['Espèce / race', d.animalEspeceRace], ['Sexe', d.animalSexe], ['Âge', d.animalAge],
    ['Identification', d.animalIdentification]] as const).filter(([, v]) => !!v) as [string, string][];
  const hBoite = Math.max(64, 40 + infosPatient.length * 11);
  doc.setFillColor(244, 247, 246); doc.roundedRect(M, y, W - 2 * M, hBoite, 6, 6, 'F');
  const col2 = M + (W - 2 * M) / 2 + 8;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TEAL);
  doc.text('Patient', M + 10, y + 16); doc.text('Propriétaire', col2, y + 16);
  doc.setFontSize(11); doc.setTextColor(...DARK); doc.text(d.animalNom, M + 10, y + 31);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.text(d.proprietaire || '—', col2, y + 31);
  doc.setFontSize(9);
  infosPatient.forEach(([l, v], i) => {
    doc.setTextColor(...GREY); doc.text(`${l} : `, M + 10, y + 45 + i * 11);
    doc.setTextColor(...DARK); doc.text(majuscule(v), M + 10 + doc.getTextWidth(`${l} : `), y + 45 + i * 11);
  });
  y += hBoite + 22;
  // Contenu : titres de paragraphe en gras, suite en texte normal.
  doc.setFontSize(10.5); doc.setTextColor(...DARK);
  const largeur = W - 2 * M;
  const ecrire = (t: string, x: number) => { if (y > H - 90) { doc.addPage(); y = 50; } doc.text(t, x, y); y += 14; };
  for (const brut of (d.contenu || '').split('\n')) {
    const l = brut.trim();
    if (!l) { y += 6; continue; }
    if (TITRE_SEUL.test(l)) { doc.setFont('helvetica', 'bold'); ecrire(l, M); doc.setFont('helvetica', 'normal'); continue; }
    const m = TITRE_PARAGRAPHE.exec(l);
    if (!m) { for (const t of doc.splitTextToSize(l, largeur) as string[]) ecrire(t, M); continue; }
    const titre = `${m[1]} : `;
    doc.setFont('helvetica', 'bold');
    const lt = doc.getTextWidth(titre);
    if (y > H - 90) { doc.addPage(); y = 50; }
    doc.text(titre, M, y);
    doc.setFont('helvetica', 'normal');
    const [premiere, ...reste] = doc.splitTextToSize(m[2], largeur - lt) as string[];
    doc.text(premiere ?? '', M + lt, y); y += 14;
    const suite = reste.join(' ');
    if (suite) for (const t of doc.splitTextToSize(suite, largeur) as string[]) ecrire(t, M);
  }
  // Sans nom de praticien : pas de « Dr Vétérinaire ».
  const praticien = d.praticien.trim().toLowerCase() === 'vétérinaire' ? '' : d.praticien.trim();
  // Bloc signature : nom du vétérinaire, date du jour, « Signature : » puis la signature.
  if (y + 110 > H - 40) { doc.addPage(); y = 50; }
  y += 24;
  const xs = W - M - 180;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...DARK);
  if (praticien) { doc.text(`Dr ${praticien}`, xs, y); y += 14; }
  doc.setFont('helvetica', 'normal');
  doc.text(`Le ${new Date().toLocaleDateString('fr-FR')}`, xs, y); y += 14;
  doc.text('Signature :', xs, y);
  if (d.signature) { try { doc.addImage(d.signature, 'PNG', xs, y + 6, 130, 52); } catch { /* signature illisible */ } }
  return doc.output('blob');
}
