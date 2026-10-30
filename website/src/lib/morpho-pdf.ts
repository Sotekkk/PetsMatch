// Export PDF d'une séance / d'un suivi, côté navigateur (jsPDF) — miroir de
// morpho_pdf_service.dart côté appli. UN compte rendu = UN PDF : sections
// renseignées seulement (pas de section vide), titre jamais isolé en bas de
// page, textes qui s'écoulent sur plusieurs pages, exercices en blocs
// insécables, anatomie seulement si le bilan anatomique est activé.

import {
  labelTypeSuivi, titreCompteRendu, labelActivite, labelCategoriePoint, colorPointEffectif,
  CATEGORIES_OBSERVATION_STATIQUE, labelsValeurObservation, SOURCE_LABELS,
  MORPHO_AVERTISSEMENT, VUES_PHOTOS, SILHOUETTE_ASSETS, morphoSpeciesKey,
  NIVEAUX_ACTIVITE, type MorphoPoint, type ExerciceSeance,
} from './morpho';
import { majuscule } from './majuscule';

const TEAL: [number, number, number] = [12, 92, 108];
const DARK: [number, number, number] = [31, 42, 46];
const GREY: [number, number, number] = [136, 136, 136];

interface SuiviRow { [k: string]: unknown }

// Image réduite (côté max [maxDim] px) avant d'entrer dans le PDF : les
// photos d'origine (plusieurs Mo chacune) rendaient le compte rendu trop
// lourd pour l'envoi par e-mail. [png] : garde la transparence (schémas).
async function urlToDataUrl(url: string, { maxDim = 900, png = false }: { maxDim?: number; png?: boolean } = {}): Promise<{ data: string; w: number; h: number } | null> {
  try {
    const resp = await fetch(url);
    const blob = await resp.blob();
    const data = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
    const img = await new Promise<HTMLImageElement | null>((resolve) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => resolve(null);
      i.src = data;
    });
    if (!img) return { data, w: 1, h: 1 };
    const w0 = img.naturalWidth, h0 = img.naturalHeight;
    const k = Math.min(1, maxDim / Math.max(w0, h0));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(w0 * k)); canvas.height = Math.max(1, Math.round(h0 * k));
    const ctx = canvas.getContext('2d');
    if (!ctx) return { data, w: w0, h: h0 };
    if (!png) { ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, canvas.width, canvas.height); }
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    return { data: png ? canvas.toDataURL('image/png') : canvas.toDataURL('image/jpeg', 0.8), w: canvas.width, h: canvas.height };
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

const txt = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : null);

export async function morphoSuiviPdfBlob(params: {
  suivi: SuiviRow;
  animal: { nom?: string; espece?: string; race?: string; sexe?: string; date_naissance?: string; identification?: string };
  pro: { nom?: string; profession?: string; adresse?: string; tel?: string; email?: string };
  photos: { vue: string; url: string }[];
  points: MorphoPoint[];
  observations: { categorie: string; valeur: string; commentaire?: string | null }[];
  mouvements: { activite: string; observation?: string | null; gene_observee?: boolean | null; commentaire?: string | null }[];
  exercices?: ExerciceSeance[];
  /** Signature manuscrite du praticien (data-URL PNG, table signatures_pro). */
  signature?: string | null;
}): Promise<Blob> {
  const { suivi, animal, pro, photos, observations, mouvements } = params;
  const exercices = params.exercices ?? [];
  // Bilan anatomique facultatif : désactivé → aucune silhouette.
  const points = suivi.avec_anatomie === false ? [] : params.points;
  const source = (suivi.source as string) || 'proprietaire';
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const M = 40, PAGE_W = 595, PAGE_H = 842, BOTTOM = PAGE_H - 50, LH = 11.5;
  const W = PAGE_W - 2 * M;
  let y = 50;

  function ensureSpace(needed: number) {
    if (y + needed > BOTTOM) { doc.addPage(); y = 50; }
  }
  /** Titre de section : gardé avec au moins [suite] points de contenu. */
  function sectionTitle(t: string, suite = 30) {
    ensureSpace(22 + suite);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(11); doc.setTextColor(...TEAL);
    doc.text(t, M, y);
    y += 16;
  }
  function line(label: string, value?: string | number | null, x = M, width = W) {
    if (value === null || value === undefined || String(value).trim() === '') return;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...DARK);
    const lab = `${label} : `;
    const labelW = doc.getTextWidth(lab);
    doc.setFont('helvetica', 'normal');
    const lines = doc.splitTextToSize(majuscule(String(value)), width - labelW) as string[];
    ensureSpace(lines.length * LH);
    doc.setFont('helvetica', 'bold'); doc.text(lab, x, y);
    doc.setFont('helvetica', 'normal');
    lines.forEach((l, i) => doc.text(l, x + labelW, y + i * LH));
    y += lines.length * LH + 2;
  }
  /** Paragraphes libres : écoulement ligne par ligne sur les pages suivantes. */
  function paragraphes(texte: string) {
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...DARK);
    for (const para of texte.split(/\n+/).map(p => p.trim()).filter(Boolean)) {
      for (const l of doc.splitTextToSize(para, W) as string[]) {
        ensureSpace(LH);
        doc.text(l, M, y);
        y += LH;
      }
      y += 3;
    }
    y += 4;
  }
  function sectionTexte(titre: string, texte: unknown) {
    const t = txt(texte);
    if (!t) return;
    sectionTitle(titre);
    paragraphes(t);
  }

  const espece = morphoSpeciesKey(animal.espece) ?? 'chien';
  const date = fmtDate(suivi.date as string | undefined);

  // En-tête professionnel (papier à en-tête du cabinet)
  if (pro.nom && pro.nom.trim()) {
    const boxH = 14 + (pro.profession ? 11 : 0) + 13;
    doc.setFillColor(240, 247, 247);
    doc.roundedRect(M, y - 12, W, boxH, 3, 3, 'F');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(11); doc.setTextColor(...TEAL);
    doc.text(pro.nom, M + 8, y);
    y += 14;
    if (pro.profession) {
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...GREY);
      doc.text(pro.profession, M + 8, y);
      y += 11;
    }
    const coords = [pro.adresse, pro.tel, pro.email].filter(Boolean).join('   ·   ');
    if (coords) {
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...GREY);
      doc.text(coords, M + 8, y);
    }
    y += 22;
  }

  // Titre : d'après le type de prestation pour une séance pro.
  const titre = source === 'professionnel' ? titreCompteRendu(suivi.type_suivi as string) : 'Suivi morphologique & bien-être';
  doc.setFont('helvetica', 'bold'); doc.setFontSize(15); doc.setTextColor(...TEAL);
  doc.text(titre.toUpperCase(), PAGE_W / 2, y, { align: 'center' });
  y += 16;
  const sousTitre = [
    txt(suivi.intitule),
    source !== 'professionnel' ? labelTypeSuivi(suivi.type_suivi as string | undefined) : null,
    suivi.statut === 'brouillon' ? 'Brouillon — document de travail' : null,
  ].filter(Boolean).join('  ·  ');
  if (sousTitre) {
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...GREY);
    doc.text(sousTitre, PAGE_W / 2, y, { align: 'center' });
  }
  y += 24;

  // Identification : animal | séance
  const colW = (W - 20) / 2;
  const yStart = y;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...TEAL);
  doc.text('Animal', M, y); y += 16;
  line('Nom', (animal.nom as string) || (suivi.animal_nom_libre as string), M, colW);
  line('Espèce / race', [animal.espece, animal.race].filter(Boolean).join(' — '), M, colW);
  line('Sexe', animal.sexe, M, colW);
  if (animal.date_naissance) line('Né(e) le', fmtDate(animal.date_naissance), M, colW);
  line('Identification', animal.identification, M, colW);
  if (suivi.poids) line('Poids', `${suivi.poids} kg`, M, colW);
  if (suivi.taille) line('Taille', `${suivi.taille} cm`, M, colW);
  if (suivi.checkpoint_age) line('Étape', suivi.checkpoint_age as string, M, colW);
  if (suivi.client_nom_libre) line('Client', suivi.client_nom_libre as string, M, colW);
  if (suivi.client_contact_libre) line('Contact', suivi.client_contact_libre as string, M, colW);
  const yAfterLeft = y;

  y = yStart;
  const xRight = M + colW + 20;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...TEAL);
  doc.text(source === 'professionnel' ? 'Séance' : 'Suivi', xRight, y); y += 16;
  line('Date', date, xRight, colW);
  if (suivi.lieu === 'cabinet' || suivi.lieu === 'exterieur') line('Lieu', suivi.lieu === 'cabinet' ? 'Cabinet' : 'Intervention extérieure', xRight, colW);
  const professionnelNom = (suivi.professionnel_nom as string) || pro.nom;
  if (pro.nom) line('Réalisé par', [pro.nom, pro.profession].filter(Boolean).join(' — '), xRight, colW);
  else if (professionnelNom) line('Professionnel', professionnelNom, xRight, colW);
  else line('Source', SOURCE_LABELS[source], xRight, colW);
  if (suivi.niveau_activite && suivi.niveau_activite !== 'non_evalue') {
    line('Niveau d\'activité', NIVEAUX_ACTIVITE.find(n => n.key === suivi.niveau_activite)?.label, xRight, colW);
  }
  line('Activité sportive', txt(suivi.activite_sportive), xRight, colW);
  y = Math.max(yAfterLeft, y) + 8;

  sectionTexte('Motif de consultation', suivi.motif);

  // Observations et bilan : texte + posture + mouvement (chacun facultatif)
  sectionTexte('Observations et bilan', suivi.observations_bilan);
  if (observations.length > 0) {
    sectionTitle(txt(suivi.observations_bilan) ? 'Posture' : 'Observations et bilan — posture');
    doc.setFontSize(9);
    for (const o of observations) {
      const catLabel = CATEGORIES_OBSERVATION_STATIQUE.find(c => c.key === o.categorie)?.label ?? o.categorie;
      const valLabel = labelsValeurObservation(o.categorie)[o.valeur] ?? o.valeur;
      const com = o.commentaire ? (doc.splitTextToSize(String(o.commentaire), W - 320) as string[]) : [];
      ensureSpace(Math.max(1, com.length) * LH + 3);
      doc.setFont('helvetica', 'bold'); doc.setTextColor(...DARK);
      doc.text(catLabel, M, y);
      doc.setFont('helvetica', 'normal'); doc.setTextColor(...TEAL);
      doc.text(valLabel, M + 180, y);
      doc.setTextColor(...GREY);
      com.forEach((l, i) => doc.text(l, M + 320, y + i * LH));
      y += Math.max(1, com.length) * LH + 3;
    }
    y += 6;
  }
  if (mouvements.length > 0) {
    sectionTitle('En mouvement');
    for (const m of mouvements) {
      line(labelActivite(m.activite), [m.observation, m.gene_observee ? 'Gêne observée' : null, m.commentaire].filter(Boolean).join(' — ') || '—');
    }
    y += 6;
  }

  sectionTexte('Intervention réalisée', suivi.intervention);

  // Conseils et exercices — un bloc insécable par élément
  if (exercices.length > 0) {
    const imgs = await Promise.all(exercices.map(e => (e.photo_url ? urlToDataUrl(e.photo_url, { maxDim: 400 }) : Promise.resolve(null))));
    doc.setFontSize(9);
    exercices.forEach((e, i) => {
      const textW = W - 16 - (imgs[i] ? 90 : 0);
      doc.setFont('helvetica', 'normal');
      const desc = txt(e.description) ? (doc.splitTextToSize(txt(e.description)!, textW) as string[]) : [];
      const champs = ([['Consignes', e.consignes], ['Fréquence', e.frequence], ['Durée', e.duree], ['Précautions', e.precautions]] as [string, string][])
        .filter(([, v]) => txt(v))
        .map(([l, v]) => doc.splitTextToSize(`${l} : ${txt(v)}`, textW) as string[]);
      const hTexte = 14 + desc.length * LH + champs.reduce((n, c) => n + c.length * LH, 0);
      const h = Math.max(hTexte, imgs[i] ? 88 : 0) + 12;
      if (i === 0) sectionTitle('Conseils et exercices', h);
      else ensureSpace(h);
      doc.setFillColor(247, 250, 250); doc.setDrawColor(220);
      doc.roundedRect(M, y - 10, W, h, 3, 3, 'FD');
      let yy = y + 2;
      doc.setFont('helvetica', 'bold'); doc.setTextColor(...DARK);
      doc.text(`${i + 1}. ${e.nom}`, M + 8, yy); yy += 14;
      doc.setFont('helvetica', 'normal');
      desc.forEach(l => { doc.text(l, M + 8, yy); yy += LH; });
      doc.setTextColor(...DARK);
      champs.forEach(c => c.forEach(l => { doc.text(l, M + 8, yy); yy += LH; }));
      const img = imgs[i];
      if (img) doc.addImage(img.data, 'JPEG', M + W - 88, y - 4, 80, 80);
      y += h + 4;
    });
    doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...GREY);
    ensureSpace(12);
    doc.text('Ces recommandations ne constituent pas une prescription vétérinaire.', M, y);
    y += 16;
  }

  // Suivi recommandé
  if (txt(suivi.suivi_recommande) || suivi.orientation_veto === true || suivi.prochain_controle) {
    sectionTitle('Suivi recommandé');
    if (txt(suivi.suivi_recommande)) paragraphes(txt(suivi.suivi_recommande)!);
    if (suivi.orientation_veto === true) line('Orientation', 'consultation vétérinaire conseillée');
    if (suivi.prochain_controle) line('Contrôle conseillé', fmtDate(suivi.prochain_controle as string));
    y += 6;
  }

  // Photos (vues guidées + autres) — titre gardé avec la première rangée
  const photosVues = VUES_PHOTOS.map(v => ({ v, url: photos.find(p => p.vue === v.key)?.url })).filter(x => x.url);
  const photosAutres = photos.filter(p => p.vue === 'autre');
  if (photosVues.length + photosAutres.length > 0) {
    const thumb = 110, gap = 14;
    sectionTitle('Photos', thumb + 14);
    let x = M;
    const items = [...photosVues.map(x => ({ url: x.url!, label: x.v.label })), ...photosAutres.map(p => ({ url: p.url, label: '' }))];
    for (const it of items) {
      if (x + thumb > PAGE_W - M) { x = M; y += thumb + 24; }
      ensureSpace(thumb + 16);
      const img = await urlToDataUrl(it.url, { maxDim: 700 });
      if (img) {
        doc.setDrawColor(220); doc.rect(x, y, thumb, thumb);
        doc.addImage(img.data, 'JPEG', x, y, thumb, thumb);
      }
      if (it.label) {
        doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...GREY);
        doc.text(it.label, x, y + thumb + 10);
      }
      x += thumb + gap;
    }
    y += thumb + 24;
  }

  // Bilan anatomique (facultatif) — une silhouette insécable par vue
  const vuesAvecPoints = [...new Set(points.map(p => p.vue))];
  if (vuesAvecPoints.length > 0) {
    const w = 260;
    let premier = true;
    for (const v of vuesAvecPoints) {
      const asset = SILHOUETTE_ASSETS[espece]?.[v];
      if (!asset) continue;
      const h = w / asset.ratio;
      if (premier) { sectionTitle('Bilan anatomique — points relevés', h + 10); premier = false; }
      else ensureSpace(h + 12);
      const img = await urlToDataUrl(asset.src, { maxDim: 1000, png: true });
      if (img) {
        const x0 = (PAGE_W - w) / 2;
        doc.addImage(img.data, 'PNG', x0, y, w, h);
        for (const p of points.filter(p => p.vue === v)) {
          const [r, g, b] = hexToRgb(colorPointEffectif(p.categorie, p.couleur));
          doc.setFillColor(r, g, b);
          doc.circle(x0 + (p.x_pct / 100) * w, y + (p.y_pct / 100) * h, 4, 'F');
        }
      }
      y += h + 12;
    }
    for (const p of points.filter(p => p.note && p.note.trim())) {
      ensureSpace(14);
      const [r, g, b] = hexToRgb(colorPointEffectif(p.categorie, p.couleur));
      doc.setFillColor(r, g, b);
      doc.circle(M + 3, y - 3, 3.5, 'F');
      doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...DARK);
      doc.text(String(p.note), M + 12, y);
      const noteW = doc.getTextWidth(String(p.note));
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...GREY);
      doc.text(`  ${labelCategoriePoint(p.categorie)}`, M + 12 + noteW, y);
      y += 14;
    }
    y += 6;
  }

  sectionTexte('Notes complémentaires', suivi.commentaires);

  // Auteur du compte rendu
  const auteur = pro.nom || txt(suivi.professionnel_nom);
  if (source === 'professionnel' && auteur) {
    ensureSpace(20);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...GREY);
    const version = Number(suivi.version ?? 1);
    doc.text([
      `Compte rendu rédigé par ${auteur}`,
      suivi.finalise_a ? `finalisé le ${fmtDate(suivi.finalise_a as string)}` : null,
      version > 1 ? `version ${version}` : null,
    ].filter(Boolean).join(' — '), M, y + 6);
    y += 20;
    // Bloc signature : nom du praticien, date du jour, « Signature : » puis la signature.
    ensureSpace(100);
    const xs = M + W - 180;
    y += 10;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(30, 32, 37);
    doc.text(auteur, xs, y); y += 14;
    doc.setFont('helvetica', 'normal');
    doc.text(`Le ${new Date().toLocaleDateString('fr-FR')}`, xs, y); y += 14;
    doc.text('Signature :', xs, y);
    if (params.signature) { try { doc.addImage(params.signature, 'PNG', xs, y + 6, 130, 52); } catch { /* signature illisible */ } }
    y += 66;
  }

  // Avertissement
  ensureSpace(44);
  doc.setDrawColor(220); doc.rect(M, y, W, 34);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...GREY);
  doc.text(doc.splitTextToSize(MORPHO_AVERTISSEMENT, W - 16), M + 8, y + 12);

  // Pied de page numéroté
  const pageCount = doc.getNumberOfPages();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);
    doc.setFontSize(7); doc.setTextColor(...GREY);
    doc.text(`Compte rendu généré via PetsMatch le ${new Date().toLocaleDateString('fr-FR')} — page ${i}/${pageCount}`, PAGE_W / 2, PAGE_H - 24, { align: 'center' });
  }

  return doc.output('blob');
}
