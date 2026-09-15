// Export PDF d'un suivi morphologique, côté navigateur (jsPDF) — miroir de
// morpho_pdf_service.dart côté appli. Compte rendu imprimable/téléchargeable
// pour un client qui n'utilise pas l'application.

import {
  labelTypeSuivi, labelActivite, labelCategoriePoint, colorCategoriePoint,
  CATEGORIES_OBSERVATION_STATIQUE, labelsValeurObservation, SOURCE_LABELS,
  MORPHO_AVERTISSEMENT, VUES_PHOTOS, SILHOUETTE_ASSETS, morphoSpeciesKey,
  NIVEAUX_ACTIVITE, type MorphoPoint,
} from './morpho';

const TEAL: [number, number, number] = [12, 92, 108];
const DARK: [number, number, number] = [31, 42, 46];
const GREY: [number, number, number] = [136, 136, 136];

interface SuiviRow { [k: string]: unknown }

async function urlToDataUrl(url: string): Promise<{ data: string; w: number; h: number } | null> {
  try {
    const resp = await fetch(url);
    const blob = await resp.blob();
    const data = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
    const dims = await new Promise<{ w: number; h: number }>((resolve) => {
      const img = new Image();
      img.onload = () => resolve({ w: img.naturalWidth, h: img.naturalHeight });
      img.onerror = () => resolve({ w: 1, h: 1 });
      img.src = data;
    });
    return { data, ...dims };
  } catch {
    return null;
  }
}

function fmtDate(iso?: string | null) {
  if (!iso) return '';
  try { return new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }); } catch { return iso; }
}

function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export async function morphoSuiviPdfBlob(params: {
  suivi: SuiviRow;
  animal: { nom?: string; espece?: string; race?: string };
  pro: { nom?: string; adresse?: string; tel?: string; email?: string };
  photos: { vue: string; url: string }[];
  points: MorphoPoint[];
  observations: { categorie: string; valeur: string; commentaire?: string | null }[];
  mouvements: { activite: string; observation?: string | null; gene_observee?: boolean | null; commentaire?: string | null }[];
}): Promise<Blob> {
  const { suivi, animal, pro, photos, points, observations, mouvements } = params;
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const M = 40, PAGE_W = 595, PAGE_H = 842;
  let y = 50;

  function ensureSpace(needed: number) {
    if (y + needed > PAGE_H - 50) { doc.addPage(); y = 50; }
  }
  function sectionTitle(t: string) {
    ensureSpace(24);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(11); doc.setTextColor(...TEAL);
    doc.text(t, M, y);
    y += 16;
  }
  function line(label: string, value?: string | number | null) {
    if (value === null || value === undefined || String(value).trim() === '') return;
    ensureSpace(14);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...DARK);
    doc.text(`${label} :`, M, y);
    const labelW = doc.getTextWidth(`${label} : `);
    doc.setFont('helvetica', 'normal');
    doc.text(String(value), M + labelW, y);
    y += 13;
  }

  const espece = morphoSpeciesKey(animal.espece) ?? 'chien';
  const date = fmtDate(suivi.date as string | undefined);

  doc.setFont('helvetica', 'bold'); doc.setFontSize(15); doc.setTextColor(...TEAL);
  doc.text('SUIVI MORPHOLOGIQUE & BIEN-ÊTRE', PAGE_W / 2, y, { align: 'center' });
  y += 16;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...GREY);
  doc.text(labelTypeSuivi(suivi.type_suivi as string | undefined), PAGE_W / 2, y, { align: 'center' });
  y += 26;

  const colW = (PAGE_W - 2 * M - 20) / 2;
  const yStart = y;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...TEAL);
  doc.text('Animal', M, y); y += 16;
  line('Nom', (animal.nom as string) || (suivi.animal_nom_libre as string));
  const especeRace = [animal.espece, animal.race].filter(Boolean).join(' — ');
  line('Espèce / race', especeRace);
  if (suivi.poids) line('Poids', `${suivi.poids} kg`);
  if (suivi.taille) line('Taille', `${suivi.taille} cm`);
  if (suivi.checkpoint_age) line('Étape', suivi.checkpoint_age as string);
  if (suivi.client_nom_libre) line('Client', suivi.client_nom_libre as string);
  if (suivi.client_contact_libre) line('Contact', suivi.client_contact_libre as string);
  const yAfterLeft = y;

  y = yStart;
  const xRight = M + colW + 20;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...TEAL);
  doc.text('Suivi', xRight, y); y += 16;
  const lineR = (label: string, value?: string | null) => {
    if (!value) return;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...DARK);
    doc.text(`${label} :`, xRight, y);
    doc.setFont('helvetica', 'normal');
    doc.text(value, xRight + doc.getTextWidth(`${label} : `), y);
    y += 13;
  };
  lineR('Date', date);
  lineR('Professionnel', (suivi.professionnel_nom as string) || pro.nom);
  lineR('Motif', suivi.motif as string);
  lineR('Source', SOURCE_LABELS[(suivi.source as string) || 'proprietaire']);
  if (suivi.niveau_activite && suivi.niveau_activite !== 'non_evalue') {
    lineR('Niveau d\'activité', NIVEAUX_ACTIVITE.find(n => n.key === suivi.niveau_activite)?.label);
  }

  y = Math.max(yAfterLeft, y) + 6;

  if (suivi.commentaires) {
    sectionTitle('Commentaires généraux');
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...DARK);
    const lines = doc.splitTextToSize(String(suivi.commentaires), PAGE_W - 2 * M);
    ensureSpace(lines.length * 11);
    doc.text(lines, M, y);
    y += lines.length * 11 + 6;
  }

  // Photos de référence
  const photosByVue = new Map(photos.filter(p => VUES_PHOTOS.some(v => v.key === p.vue)).map(p => [p.vue, p.url]));
  if (photosByVue.size > 0) {
    sectionTitle('Photos de référence');
    const thumbSize = 110, gap = 14;
    let x = M;
    for (const v of VUES_PHOTOS) {
      const url = photosByVue.get(v.key);
      if (!url) continue;
      ensureSpace(thumbSize + 24);
      const img = await urlToDataUrl(url);
      if (img) {
        doc.setDrawColor(220); doc.rect(x, y, thumbSize, thumbSize);
        doc.addImage(img.data, 'JPEG', x, y, thumbSize, thumbSize);
      }
      doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...GREY);
      doc.text(v.label, x, y + thumbSize + 10);
      x += thumbSize + gap;
      if (x + thumbSize > PAGE_W - M) { x = M; y += thumbSize + 24; }
    }
    y += thumbSize + 20;
  }

  // Silhouette + points
  const vuesAvecPoints = [...new Set(points.map(p => p.vue))];
  if (vuesAvecPoints.length > 0) {
    sectionTitle('Silhouette — points relevés');
    const w = 260;
    for (const v of vuesAvecPoints) {
      const asset = SILHOUETTE_ASSETS[espece]?.[v];
      if (!asset) continue;
      const h = w / asset.ratio;
      ensureSpace(h + 20);
      const img = await urlToDataUrl(asset.src);
      if (img) {
        doc.addImage(img.data, 'PNG', M, y, w, h);
        for (const p of points.filter(p => p.vue === v)) {
          const [r, g, b] = hexToRgb(colorCategoriePoint(p.categorie));
          doc.setFillColor(r, g, b);
          doc.circle(M + (p.x_pct / 100) * w, y + (p.y_pct / 100) * h, 4, 'F');
        }
      }
      y += h + 12;
    }
    // Légende
    ensureSpace(14);
    const usedCats = [...new Set(points.map(p => p.categorie))];
    let lx = M;
    doc.setFontSize(8);
    for (const catKey of usedCats) {
      const [r, g, b] = hexToRgb(colorCategoriePoint(catKey));
      doc.setFillColor(r, g, b);
      doc.circle(lx + 3, y - 3, 3, 'F');
      doc.setTextColor(...GREY);
      const label = labelCategoriePoint(catKey);
      doc.text(label, lx + 10, y);
      lx += doc.getTextWidth(label) + 24;
      if (lx > PAGE_W - M - 60) { lx = M; y += 12; }
    }
    y += 16;
    for (const p of points.filter(p => p.note && p.note.trim())) {
      line(labelCategoriePoint(p.categorie), p.note);
    }
  }

  // Observations statiques
  if (observations.length > 0) {
    sectionTitle('Observation statique');
    doc.setFontSize(9);
    for (const o of observations) {
      ensureSpace(14);
      const catLabel = CATEGORIES_OBSERVATION_STATIQUE.find(c => c.key === o.categorie)?.label ?? o.categorie;
      const valLabel = labelsValeurObservation(o.categorie)[o.valeur] ?? o.valeur;
      doc.setFont('helvetica', 'bold'); doc.setTextColor(...DARK);
      doc.text(catLabel, M, y);
      doc.setFont('helvetica', 'normal'); doc.setTextColor(...TEAL);
      doc.text(valLabel, M + 180, y);
      if (o.commentaire) { doc.setTextColor(...GREY); doc.text(String(o.commentaire).slice(0, 60), M + 320, y); }
      y += 14;
    }
    y += 6;
  }

  // Observations dynamiques
  if (mouvements.length > 0) {
    sectionTitle('Observation en mouvement');
    doc.setFontSize(9);
    for (const m of mouvements) {
      ensureSpace(14);
      doc.setFont('helvetica', 'bold'); doc.setTextColor(...DARK);
      doc.text(labelActivite(m.activite), M, y);
      const parts = [m.observation, m.gene_observee ? 'Gêne observée' : null, m.commentaire].filter(Boolean).join(' — ');
      if (parts) { doc.setFont('helvetica', 'normal'); doc.setTextColor(...GREY); doc.text(parts.slice(0, 80), M + 90, y); }
      y += 14;
    }
    y += 6;
  }

  // Avertissement
  ensureSpace(40);
  doc.setDrawColor(220); doc.rect(M, y, PAGE_W - 2 * M, 34);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...GREY);
  const avLines = doc.splitTextToSize(MORPHO_AVERTISSEMENT, PAGE_W - 2 * M - 16);
  doc.text(avLines, M + 8, y + 12);

  // Pied de page
  const pageCount = doc.getNumberOfPages();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);
    doc.setFontSize(7); doc.setTextColor(...GREY);
    doc.text(`Compte rendu généré via PetsMatch le ${new Date().toLocaleDateString('fr-FR')} — page ${i}/${pageCount}`, PAGE_W / 2, PAGE_H - 24, { align: 'center' });
  }

  return doc.output('blob');
}
