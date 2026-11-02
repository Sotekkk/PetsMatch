// Génération d'un vrai PDF pour le moteur commun `factures` (éleveur, association,
// garde, éducateur, taxi, photographe, toilettage), côté navigateur (jsPDF).
// Même contenu que le PDF de l'app Flutter (_buildPdf) et que le rendu
// /facture/[token] : identité complète de l'émetteur, destinataire, lignes,
// mentions légales obligatoires. Utilisé pour figer + archiver la facture.

import { htLigneRemisee, libelleRemise, montantRemise } from './facture-remise';

const TEAL: [number, number, number] = [12, 92, 108];

const DARK_PAIEMENT: [number, number, number] = [30, 32, 37];

export interface FacturePdfLigne {
  designation?: string;
  description?: string;
  quantite?: number;
  prixUnitaireHT?: number;
  tauxTVA?: number;
  /** Rattachement : un animal (section par animal) … */
  animalId?: string | null;
  animalNom?: string | null;
  animalIdentification?: string | null;
  /** … ou prestation commune au dossier client (comptée une seule fois). */
  commune?: boolean;
  /** Remise en % (une seule par ligne) et son motif. */
  remise?: number | null;
  remiseMotif?: string | null;
}

/** Lignes JSON d'une facture (`factures.lignes`) → lignes du PDF. */
export function lignePdfDepuisJson(l: Record<string, unknown>): FacturePdfLigne {
  return {
    designation: String(l.designation ?? l.description ?? ''),
    description: '',
    quantite: Number(l.quantite ?? 1),
    prixUnitaireHT: Number(l.prixUnitaireHT ?? l.prixHT ?? l.prixUnitaire ?? 0),
    tauxTVA: Number(l.tauxTVA ?? l.tva ?? 0),
    animalId: (l.animalId as string | null | undefined) ?? null,
    animalNom: (l.animalNom as string | null | undefined) ?? null,
    animalIdentification: (l.animalIdentification as string | null | undefined) ?? null,
    commune: l.commune === true,
    remise: l.remisePct != null ? Number(l.remisePct) : null,
    remiseMotif: (l.remiseMotif as string | null | undefined) ?? null,
  };
}

export interface FacturePdfData {
  numero: string;
  typeFacture?: string | null; // 'avoir' | 'acompte' | null
  dateFacture?: string | null;
  datePrestation?: string | null;
  dateEcheance?: string | null;
  // Émetteur
  nomEmetteur?: string | null;
  rueEmetteur?: string | null;
  cpEmetteur?: string | null;
  villeEmetteur?: string | null;
  paysEmetteur?: string | null;
  telEmetteur?: string | null;
  emailEmetteur?: string | null;
  siretEmetteur?: string | null;
  tvaEmetteur?: string | null;
  formeJuridiqueEmetteur?: string | null;
  capitalEmetteur?: string | null;
  rcsEmetteur?: string | null;
  rmEmetteur?: string | null;
  // Client
  prenomClient?: string | null;
  nomClient?: string | null;
  rueClient?: string | null;
  cpClient?: string | null;
  villeClient?: string | null;
  paysClient?: string | null;
  emailClient?: string | null;
  siretClient?: string | null;
  tvaClient?: string | null;
  // Contenu
  lignes: FacturePdfLigne[];
  totalHT: number;
  totalTVA: number;
  totalTTC: number;
  franchise: boolean;
  modePaiement?: string | null;
  delaiPaiement?: string | null;
  conditionsEscompte?: string | null;
  noteComplementaire?: string | null;
  /** Facture réglée : mention « ACQUITTÉE le … — mode ». */
  acquittee?: { date?: string | null; mode?: string | null } | null;
  /** Montant déjà réglé (règlements partiels / acomptes) ; payée = total TTC. */
  dejaRegle?: number | null;
}

const arrondi = (v: number) => Math.round((v + Number.EPSILON) * 100) / 100;

const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} EUR`;
const fmtD = (iso?: string | null) => {
  if (!iso) return '';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
};
const clean = (s?: string | null) => (s ?? '').toString().trim();

export async function facturePdfBlob(d: FacturePdfData): Promise<Blob> {
  const { jsPDF } = await import('jspdf');
  const autoTable = (await import('jspdf-autotable')).default;

  const isAvoir = d.typeFacture === 'avoir';
  const annee = new Date().getFullYear();
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = 595;
  const M = 40;
  let y = 50;

  // ── En-tête : émetteur (gauche) / titre + numéro (droite) ───────────────────
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(14);
  doc.setTextColor(...TEAL);
  doc.text(clean(d.nomEmetteur).slice(0, 60) || '—', M, y);

  doc.setFontSize(isAvoir ? 15 : 18);
  doc.text(isAvoir ? "FACTURE D'AVOIR" : 'FACTURE', W - M, y, { align: 'right' });

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  doc.setTextColor(40);
  doc.text(`N° ${d.numero}`, W - M, y + 16, { align: 'right' });

  y += 16;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(110);
  const emLines = [
    clean(d.formeJuridiqueEmetteur)
      ? `${clean(d.formeJuridiqueEmetteur)}${clean(d.capitalEmetteur) ? ` au capital de ${clean(d.capitalEmetteur)}` : ''}`
      : '',
    clean(d.rueEmetteur),
    [clean(d.cpEmetteur), clean(d.villeEmetteur)].filter(Boolean).join(' '),
    clean(d.paysEmetteur),
    clean(d.telEmetteur) ? `Tél. : ${clean(d.telEmetteur)}` : '',
    clean(d.emailEmetteur),
    clean(d.siretEmetteur) ? `SIRET : ${clean(d.siretEmetteur)}` : '',
    clean(d.tvaEmetteur) ? `N° TVA : ${clean(d.tvaEmetteur)}` : '',
    clean(d.rcsEmetteur),
    clean(d.rmEmetteur) ? `RM : ${clean(d.rmEmetteur)}` : '',
  ].filter(Boolean) as string[];
  emLines.forEach((l, i) => doc.text(l.slice(0, 80), M, y + 12 + i * 10));

  // Dates (sous le numéro, à droite)
  doc.setTextColor(110);
  let yd = y + 28;
  doc.text(`Date : ${fmtD(d.dateFacture)}`, W - M, yd, { align: 'right' });
  if (clean(d.datePrestation)) { yd += 11; doc.text(`Prestation : ${fmtD(d.datePrestation)}`, W - M, yd, { align: 'right' }); }
  if (clean(d.dateEcheance)) {
    yd += 11;
    doc.setFont('helvetica', 'bold');
    doc.text(`Échéance : ${fmtD(d.dateEcheance)}`, W - M, yd, { align: 'right' });
    doc.setFont('helvetica', 'normal');
  }
  // Statut du règlement (distinct de l'état du document : avoir, acompte).
  const regle = d.acquittee ? d.totalTTC : arrondi(Number(d.dejaRegle ?? 0));
  const statutReglement = isAvoir ? '' : regle >= d.totalTTC - 0.005 && d.totalTTC > 0 ? 'Payée' : regle > 0 ? 'Partiellement payée' : 'À payer';
  if (statutReglement) {
    yd += 11;
    doc.setFont('helvetica', 'bold');
    doc.text(`Statut : ${statutReglement}`, W - M, yd, { align: 'right' });
    doc.setFont('helvetica', 'normal');
  }

  y = Math.max(y + 12 + emLines.length * 10, yd + 6) + 16;

  // ── Destinataire ───────────────────────────────────────────────────────────
  doc.setDrawColor(220);
  doc.setFillColor(248, 248, 246);
  const clLines = [
    `${clean(d.prenomClient)} ${clean(d.nomClient)}`.trim() || '—',
    clean(d.rueClient),
    [clean(d.cpClient), clean(d.villeClient)].filter(Boolean).join(' '),
    clean(d.paysClient),
    clean(d.emailClient),
    clean(d.siretClient) ? `SIRET : ${clean(d.siretClient)}` : '',
    clean(d.tvaClient) ? `N° TVA : ${clean(d.tvaClient)}` : '',
  ].filter(Boolean) as string[];
  const clH = 20 + clLines.length * 11 + 8;
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
  const ht = (l: FacturePdfLigne) => htLigneRemisee(Number(l.quantite ?? 1), Number(l.prixUnitaireHT ?? 0), l.remise);
  const ttc = (l: FacturePdfLigne) => d.franchise ? ht(l) : arrondi(ht(l) * (1 + Number(l.tauxTVA ?? 0) / 100));
  const ligneTable = (l: FacturePdfLigne) => {
    const q = Number(l.quantite ?? 1);
    const pu = Number(l.prixUnitaireHT ?? 0);
    const remise = Number(l.remise ?? 0) > 0
      ? `\n${libelleRemise(Number(l.remise), l.remiseMotif, montantRemise(q, pu, l.remise))}` : '';
    const desig = [clean(l.designation), clean(l.description)].filter(Boolean).join(' — ') + remise;
    return d.franchise
      ? [desig, String(q), eur(pu), eur(ht(l))]
      : [desig, String(q), eur(pu), `${Number(l.tauxTVA ?? 0)} %`, eur(ht(l)), eur(ttc(l))];
  };
  const nbCol = d.franchise ? 4 : 6;
  // Regroupement : une section par animal (ordre d'apparition), puis les
  // prestations communes ; chaque ligne n'apparaît qu'une fois.
  const cleAnimal = (l: FacturePdfLigne) => l.commune ? '' : clean(l.animalId) || clean(l.animalNom);
  const sections: { cle: string; nom: string; ident: string; lignes: FacturePdfLigne[] }[] = [];
  const communes: FacturePdfLigne[] = [];
  const sansAnimal: FacturePdfLigne[] = [];
  for (const l of d.lignes) {
    if (l.commune) { communes.push(l); continue; }
    const cle = cleAnimal(l);
    if (!cle) { sansAnimal.push(l); continue; }
    let s = sections.find(x => x.cle === cle);
    if (!s) { s = { cle, nom: clean(l.animalNom) || 'Animal', ident: clean(l.animalIdentification), lignes: [] }; sections.push(s); }
    s.lignes.push(l);
  }
  const groupe = sections.length > 1 || (sections.length >= 1 && (communes.length > 0 || sansAnimal.length > 0));
  type Cellule = string | { content: string; colSpan?: number; styles?: Record<string, unknown> };
  const body: Cellule[][] = [];
  const entete = (titre: string) => body.push([{ content: titre, colSpan: nbCol,
    styles: { fillColor: [236, 244, 245], textColor: TEAL, fontStyle: 'bold', fontSize: 9.5 } }]);
  const sousTotal = (titre: string, ls: FacturePdfLigne[]) => {
    const sHt = arrondi(ls.reduce((a, l) => a + ht(l), 0));
    const sTtc = arrondi(ls.reduce((a, l) => a + ttc(l), 0));
    body.push([{ content: `Sous-total ${titre}`, colSpan: nbCol - (d.franchise ? 1 : 2), styles: { halign: 'right', fontStyle: 'bold', textColor: [70, 70, 70] } },
      ...(d.franchise ? [] : [{ content: eur(sHt), styles: { halign: 'right', fontStyle: 'bold' } }]),
      { content: eur(d.franchise ? sHt : sTtc), styles: { halign: 'right', fontStyle: 'bold' } }]);
  };
  if (!groupe) {
    // Un seul animal (ou aucun) : présentation simple, animal rappelé au-dessus.
    if (sections.length === 1) {
      doc.setFont('helvetica', 'bold'); doc.setFontSize(9.5); doc.setTextColor(...TEAL);
      doc.text(`Animal : ${sections[0].nom}${sections[0].ident ? ` — Identification : ${sections[0].ident}` : ''}`, M, y);
      y += 12;
    }
    for (const l of d.lignes) body.push(ligneTable(l));
  } else {
    for (const s of sections) {
      entete(`${s.nom.toUpperCase()}${s.ident ? `   ·   Identification : ${s.ident}` : ''}`);
      for (const l of s.lignes) body.push(ligneTable(l));
      sousTotal(s.nom, s.lignes);
    }
    if (sansAnimal.length) { entete('AUTRES PRESTATIONS'); for (const l of sansAnimal) body.push(ligneTable(l)); sousTotal('autres prestations', sansAnimal); }
    if (communes.length) {
      entete('PRESTATIONS COMMUNES');
      for (const l of communes) body.push(ligneTable(l));
      sousTotal('prestations communes', communes);
    }
  }
  autoTable(doc, {
    startY: y,
    margin: { left: M, right: M, bottom: 50 },
    head: d.franchise
      ? [['Désignation', 'Qté', 'P.U.', 'Total']]
      : [['Désignation', 'Qté', 'P.U. HT', 'TVA', 'Total HT', 'Total TTC']],
    body: body as never,
    showHead: 'everyPage',
    rowPageBreak: 'avoid',
    headStyles: { fillColor: TEAL, fontSize: 9 },
    bodyStyles: { fontSize: 9 },
    columnStyles: d.franchise
      ? { 1: { halign: 'center' }, 2: { halign: 'right' }, 3: { halign: 'right' } }
      : { 1: { halign: 'center' }, 2: { halign: 'right' }, 3: { halign: 'right' }, 4: { halign: 'right' }, 5: { halign: 'right' } },
  });

  // @ts-expect-error lastAutoTable est ajouté par le plugin
  y = (doc.lastAutoTable?.finalY ?? y + 40) + 16;

  const lineTotal = (label: string, value: string, bold = false) => {
    doc.setFont('helvetica', bold ? 'bold' : 'normal');
    doc.setFontSize(bold ? 11 : 9);
    if (bold) doc.setTextColor(...TEAL); else doc.setTextColor(90);
    doc.text(label, W - M - 200, y);
    doc.text(value, W - M, y, { align: 'right' });
    y += bold ? 16 : 12;
  };
  if (y > 740) { doc.addPage(); y = 50; }
  // Remises accordées (déjà déduites des montants HT des lignes).
  const totalRemises = arrondi(d.lignes.reduce((a, l) => a + montantRemise(Number(l.quantite ?? 1), Number(l.prixUnitaireHT ?? 0), l.remise), 0));
  if (totalRemises > 0) lineTotal(`Dont remises accordées${d.franchise ? '' : ' (HT)'}`, `-${eur(totalRemises)}`);
  if (!d.franchise) {
    lineTotal('Total HT', eur(d.totalHT));
    // Récapitulatif par taux (base HT et montant de TVA).
    const parTaux = new Map<number, number>();
    for (const l of d.lignes) parTaux.set(Number(l.tauxTVA ?? 0), (parTaux.get(Number(l.tauxTVA ?? 0)) ?? 0) + ht(l));
    const taux = [...parTaux.entries()].sort((a, b) => b[0] - a[0]);
    if (taux.length > 1 || (taux.length === 1 && taux[0][0] === 0)) {
      for (const [t, base] of taux) {
        lineTotal(t === 0 ? `Exonéré / 0 % (base ${eur(arrondi(base))})` : `TVA ${String(t).replace('.', ',')} % (base ${eur(arrondi(base))})`,
          eur(arrondi(base * t / 100)));
      }
    } else if (taux.length === 1) {
      lineTotal(`TVA ${String(taux[0][0]).replace('.', ',')} %`, eur(d.totalTVA));
    }
    if (taux.length > 1) lineTotal('Total TVA', eur(d.totalTVA));
    lineTotal('TOTAL TTC', eur(d.totalTTC), true);
  } else {
    lineTotal('TOTAL', eur(d.totalTTC), true);
  }
  if (!isAvoir && regle > 0) {
    lineTotal('Déjà réglé', eur(Math.min(regle, d.totalTTC)));
    lineTotal('RESTE À PAYER', eur(arrondi(Math.max(0, d.totalTTC - regle))), true);
  }

  if (d.acquittee) {
    // Tampon « PAYÉE » bien visible, détail du règlement dessous.
    const sous = `Facture acquittée${d.acquittee.date ? ` le ${fmtD(d.acquittee.date)}` : ''}${clean(d.acquittee.mode) ? ` — ${clean(d.acquittee.mode)}` : ''}`;
    y += 10;
    doc.setTextColor(46, 158, 91);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9);
    const wSous = doc.getTextWidth(sous);
    doc.setFontSize(20);
    const wTitre = doc.getTextWidth('PAYÉE');
    const w = Math.max(wSous, wTitre) + 24;
    doc.setDrawColor(46, 158, 91); doc.setLineWidth(2);
    doc.roundedRect(W - M - w, y - 4, w, 40, 4, 4);
    doc.text('PAYÉE', W - M - w / 2, y + 15, { align: 'center' });
    doc.setFontSize(9);
    doc.text(sous, W - M - w / 2, y + 29, { align: 'center' });
    y += 40;
  }

  y += 16;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  // Mode de paiement et délai de règlement en gras.
  doc.setFont('helvetica', 'bold'); doc.setTextColor(...DARK_PAIEMENT);
  if (clean(d.modePaiement)) { doc.text(`Mode de paiement : ${clean(d.modePaiement)}`, M, y); y += 11; }
  if (clean(d.delaiPaiement)) {
    doc.text(`Délai de règlement : ${clean(d.delaiPaiement)} jours à compter de la date d'émission.`, M, y);
    y += 11;
  }
  doc.setFont('helvetica', 'normal'); doc.setTextColor(90);
  if (clean(d.noteComplementaire)) {
    const nl = doc.splitTextToSize(clean(d.noteComplementaire), W - M * 2);
    doc.text(nl, M, y);
    y += nl.length * 10 + 4;
  }

  // ── Mentions légales obligatoires ──────────────────────────────────────────
  y += 8;
  doc.setDrawColor(200);
  doc.setFontSize(7.5);
  doc.setTextColor(120);
  const escompte = clean(d.conditionsEscompte) || 'Escompte pour paiement anticipé : néant.';
  // Client professionnel (SIRET / n° de TVA) : pénalités et indemnité de
  // recouvrement (art. L441-10 et D441-5 du Code de commerce) ; un particulier
  // n'est pas concerné par ces mentions.
  const clientPro = !!(clean(d.siretClient) || clean(d.tvaClient));
  const mentions = [
    d.franchise ? 'TVA non applicable, art. 293 B du CGI.' : '',
    escompte,
    clientPro
      ? `En cas de retard de paiement : pénalités au taux de 3 fois le taux d'intérêt légal en vigueur (${annee}), exigibles sans rappel le lendemain de la date d'échéance, et indemnité forfaitaire de recouvrement de 40 € (art. L441-10 et D441-5 du Code de commerce).`
      : 'Paiement selon les conditions indiquées ci-dessus.',
  ].filter(Boolean).join(' ');
  const ml = doc.splitTextToSize(mentions, W - M * 2);
  if (y + ml.length * 9 + 14 > 800) { doc.addPage(); y = 50; }
  doc.rect(M, y, W - M * 2, ml.length * 9 + 14);
  doc.text(ml, M + 7, y + 12);

  // Numéros de page.
  const nbPages = doc.getNumberOfPages();
  for (let i = 1; i <= nbPages; i++) {
    doc.setPage(i);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(150);
    doc.text(`${isAvoir ? "Facture d'avoir" : 'Facture'} N° ${d.numero} — page ${i} / ${nbPages}`, W / 2, 828, { align: 'center' });
  }

  return doc.output('blob');
}
