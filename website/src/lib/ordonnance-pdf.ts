// Ordonnance vétérinaire (contenu structuré, migration_ordonnances_v2.sql) :
// en-tête de la clinique (n° d'Ordre), numéro d'ordonnance, patient,
// propriétaire, médicaments (présentation, posologie, voie, durée, quantité,
// renouvellement, instructions, mentions réglementaires), prescripteur,
// pages numérotées. Miroir app : lib/pages/pro/ordonnance_pdf.dart.

import { majuscule } from './majuscule';

export interface LigneOrdonnance {
  medicament: string; posologie: string; dureeJours?: number | null; notes?: string;
  principeActif?: string; presentation?: string; voie?: string; duree?: string; quantite?: string;
  renouvellement?: string; mentions?: string;
}

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
  remarques?: string;
  date?: Date;
  /** Numéro attribué à la validation (absent : aperçu). */
  numero?: string | null;
  /** Version rectificative : ordonnance remplacée (numéro, date). */
  remplace?: { numero?: string | null; date?: Date | null } | null;
  /** Aperçu avant validation : bandeau « Aperçu — non validée ». */
  apercu?: boolean;
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
  const BAS = H - 60; // limite du contenu (pied de page en dessous)
  const jour = (d.date ?? new Date()).toLocaleDateString('fr-FR');
  const largeur = W - 2 * M - 28;
  let y = 50;

  const entete = (suite: boolean) => {
    doc.setFont('helvetica', 'bold'); doc.setFontSize(suite ? 11 : 15); doc.setTextColor(...TEAL);
    doc.text(d.cliniqueNom, M, y);
    doc.setFontSize(suite ? 10 : 13);
    doc.text(d.remplace ? 'ORDONNANCE RECTIFICATIVE' : 'ORDONNANCE', W - M, y, { align: 'right' });
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...DARK);
    doc.text([d.numero ? `N° ${d.numero}` : (d.apercu ? 'N° attribué à la validation' : ''), `Le ${jour}`].filter(Boolean).join(' · '),
      W - M, y + 14, { align: 'right' });
    if (suite) { y += 26; doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y); y += 18; return; }
    for (const l of [d.cliniqueAdresse, d.cliniqueTel ? `Tél. ${d.cliniqueTel}` : '', d.numeroOrdre ? `N° d'inscription à l'Ordre : ${d.numeroOrdre}` : '']) {
      if (!l) continue;
      y += 13; doc.text(l, M, y);
    }
    y = Math.max(y + 16, 82);
    doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y);
    y += 14;
  };
  const sautSiBesoin = (h: number) => {
    if (y + h <= BAS) return;
    doc.addPage(); y = 50; entete(true);
  };

  entete(false);

  if (d.apercu) {
    doc.setFillColor(255, 248, 234); doc.roundedRect(M, y - 4, W - 2 * M, 22, 4, 4, 'F');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(138, 90, 0);
    doc.text('APERÇU — ordonnance non validée, sans valeur de prescription', W / 2, y + 10, { align: 'center' });
    y += 30;
  }
  if (d.remplace) {
    doc.setFont('helvetica', 'italic'); doc.setFontSize(9); doc.setTextColor(...DARK);
    const r = [`Annule et remplace l'ordonnance${d.remplace.numero ? ` n° ${d.remplace.numero}` : ''}`,
      d.remplace.date ? `du ${d.remplace.date.toLocaleDateString('fr-FR')}` : ''].filter(Boolean).join(' ');
    doc.text(`${r}.`, M, y + 4); y += 18;
  }

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
  doc.text(doc.splitTextToSize(d.proprietaire || '—', W - M - col2 - 10), col2, boxTop + 31);
  doc.setFontSize(9);
  let yy = boxTop + 44;
  for (const [l, v] of infosOrdo) {
    doc.setTextColor(...GREY); doc.text(`${l} : `, M + 10, yy);
    doc.setTextColor(...DARK); doc.text(majuscule(v), M + 10 + doc.getTextWidth(`${l} : `), yy);
    yy += 11;
  }
  y = boxTop + hOrdo + 24;

  // Prescription : une ligne = bloc insécable (sauf s'il dépasse une page).
  d.lignes.forEach((l, i) => {
    const titre = [l.medicament, l.presentation].filter(x => x?.trim()).join(' — ');
    const details: { texte: string; style: 'normal' | 'gris' | 'italique' }[] = [];
    if (l.principeActif?.trim()) details.push({ texte: `Principe actif : ${l.principeActif.trim()}`, style: 'gris' });
    if (l.posologie?.trim()) details.push({ texte: l.posologie.trim(), style: 'normal' });
    const carac = [l.voie?.trim() && `Voie : ${l.voie.trim()}`,
      l.duree?.trim() ? `Durée : ${l.duree.trim()}` : l.dureeJours ? `Pendant ${l.dureeJours} jour${l.dureeJours > 1 ? 's' : ''}` : '',
      l.quantite?.trim() && `Quantité à délivrer : ${l.quantite.trim()}`,
      `Renouvellement : ${l.renouvellement?.trim() || 'non'}`].filter(Boolean).join(' · ');
    if (l.duree !== undefined || l.voie || l.quantite) details.push({ texte: carac, style: 'gris' });
    else if (l.dureeJours) details.push({ texte: `Pendant ${l.dureeJours} jour${l.dureeJours > 1 ? 's' : ''}`, style: 'gris' });
    if (l.notes?.trim()) details.push({ texte: l.notes.trim(), style: 'italique' });
    if (l.mentions?.trim()) details.push({ texte: `Mentions : ${l.mentions.trim()}`, style: 'normal' });
    doc.setFontSize(10);
    const blocs = details.map(x => ({ ...x, lignes: doc.splitTextToSize(x.texte, largeur) as string[] }));
    const titreL = doc.splitTextToSize(titre || '—', largeur) as string[];
    const h = titreL.length * 13 + blocs.reduce((s, b) => s + b.lignes.length * 12, 0) + 18;
    sautSiBesoin(Math.min(h, BAS - 120));

    doc.setFillColor(...TEAL); doc.circle(M + 9, y - 3, 9, 'F');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(255, 255, 255);
    doc.text(String(i + 1), M + 9, y, { align: 'center' });
    doc.setFontSize(11); doc.setTextColor(...DARK);
    doc.text(titreL, M + 28, y);
    y += (titreL.length - 1) * 13;
    for (const b of blocs) {
      doc.setFont('helvetica', b.style === 'italique' ? 'italic' : 'normal');
      doc.setFontSize(b.style === 'normal' ? 10 : 9.5);
      doc.setTextColor(...(b.style === 'normal' ? DARK : GREY));
      for (const t of b.lignes) { y += 12; if (y > BAS) { doc.addPage(); y = 50; entete(true); } doc.text(t, M + 28, y); }
    }
    doc.setFont('helvetica', 'normal');
    y += 22;
  });

  if (d.remarques?.trim()) {
    const t = doc.splitTextToSize(d.remarques.trim(), W - 2 * M) as string[];
    sautSiBesoin(20 + t.length * 12);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TEAL); doc.text('Remarques', M, y);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...DARK);
    doc.text(t, M, y + 13); y += 13 + t.length * 12 + 10;
  }

  // Prescripteur (sur la dernière page, en bas, ou page suivante si plus de place).
  if (y > H - 170) { doc.addPage(); y = 50; entete(true); }
  const sy = H - 150;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...DARK);
  if (d.prescripteur.trim() && d.prescripteur.trim().toLowerCase() !== 'vétérinaire') doc.text(`Dr ${d.prescripteur}`, W - M - 180, sy);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...GREY);
  doc.text('Vétérinaire', W - M - 180, sy + 12);
  if (d.signature && !d.apercu) { try { doc.addImage(d.signature, 'PNG', W - M - 180, sy + 14, 130, 52); } catch { /* signature illisible */ } }
  doc.setDrawColor(...GREY); doc.line(W - M - 180, sy + 68, W - M - 20, sy + 68);
  doc.setFontSize(8); doc.text('Signature', W - M - 180, sy + 79);

  // Pied de page : mention + numérotation.
  const n = doc.getNumberOfPages();
  for (let p = 1; p <= n; p++) {
    doc.setPage(p);
    doc.setFont('helvetica', 'italic'); doc.setFontSize(7.5); doc.setTextColor(...GREY);
    doc.text('Ordonnance établie via PetsMatch — à présenter en pharmacie / à conserver dans le carnet de santé.', M, H - 40);
    doc.setFont('helvetica', 'normal');
    doc.text([d.numero ? `N° ${d.numero}` : '', `Page ${p} / ${n}`].filter(Boolean).join(' · '), W - M, H - 40, { align: 'right' });
  }

  return doc.output('blob');
}

export interface CompteRenduData {
  cliniqueNom: string; cliniqueAdresse?: string; cliniqueTel?: string; cliniqueEmail?: string;
  praticien: string; animalNom: string; animalEspeceRace?: string; animalSexe?: string; animalAge?: string;
  animalIdentification?: string;
  proprietaire?: string; contenu: string; date?: Date;
  /** Signature manuscrite du vétérinaire (data-URL PNG). */
  signature?: string | null;
  /** Autres métiers (éducateur…) : titre du document, « Dr » ou rien devant le
   *  nom, libellé de l'encadré animal. Défauts : vétérinaire. */
  titre?: string; prefixePraticien?: string; libelleAnimal?: string;
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
  doc.setFontSize(13); doc.text(d.titre ?? 'COMPTE RENDU', W - M, y, { align: 'right' });
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
  doc.text(d.libelleAnimal ?? 'Patient', M + 10, y + 16); doc.text('Propriétaire', col2, y + 16);
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
  if (praticien) { doc.text(`${d.prefixePraticien ?? 'Dr '}${praticien}`, xs, y); y += 14; }
  doc.setFont('helvetica', 'normal');
  doc.text(`Le ${new Date().toLocaleDateString('fr-FR')}`, xs, y); y += 14;
  doc.text('Signature :', xs, y);
  if (d.signature) { try { doc.addImage(d.signature, 'PNG', xs, y + 6, 130, 52); } catch { /* signature illisible */ } }
  return doc.output('blob');
}
