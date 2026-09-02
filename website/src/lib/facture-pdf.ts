// Génération d'un vrai PDF pour le moteur commun `factures` (éleveur, association,
// garde, éducateur, taxi, photographe, toilettage), côté navigateur (jsPDF).
// Même contenu que le PDF de l'app Flutter (_buildPdf) et que le rendu
// /facture/[token] : identité complète de l'émetteur, destinataire, lignes,
// mentions légales obligatoires. Utilisé pour figer + archiver la facture.

const TEAL: [number, number, number] = [12, 92, 108];

export interface FacturePdfLigne {
  designation?: string;
  description?: string;
  quantite?: number;
  prixUnitaireHT?: number;
  tauxTVA?: number;
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
}

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

  y += 12 + emLines.length * 10 + 16;

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
  autoTable(doc, {
    startY: y,
    margin: { left: M, right: M },
    head: d.franchise
      ? [['Désignation', 'Qté', 'P.U.', 'Total']]
      : [['Désignation', 'Qté', 'P.U. HT', 'TVA', 'Total HT']],
    body: d.lignes.map((l) => {
      const q = Number(l.quantite ?? 1);
      const pu = Number(l.prixUnitaireHT ?? 0);
      const desig = [clean(l.designation), clean(l.description)].filter(Boolean).join(' — ');
      return d.franchise
        ? [desig, String(q), eur(pu), eur(q * pu)]
        : [desig, String(q), eur(pu), `${Number(l.tauxTVA ?? 0)} %`, eur(q * pu)];
    }),
    headStyles: { fillColor: TEAL, fontSize: 9 },
    bodyStyles: { fontSize: 9 },
    columnStyles: d.franchise
      ? { 1: { halign: 'center' }, 2: { halign: 'right' }, 3: { halign: 'right' } }
      : { 1: { halign: 'center' }, 2: { halign: 'right' }, 3: { halign: 'right' }, 4: { halign: 'right' } },
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
  if (!d.franchise) {
    lineTotal('Total HT', eur(d.totalHT));
    lineTotal('TVA', eur(d.totalTVA));
    lineTotal('TOTAL TTC', eur(d.totalTTC), true);
  } else {
    lineTotal('TOTAL', eur(d.totalTTC), true);
  }

  y += 16;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  if (clean(d.modePaiement)) { doc.text(`Mode de paiement : ${clean(d.modePaiement)}`, M, y); y += 11; }
  if (clean(d.delaiPaiement)) {
    doc.text(`Délai de règlement : ${clean(d.delaiPaiement)} jours à compter de la date d'émission.`, M, y);
    y += 11;
  }
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
  const mentions = [
    d.franchise ? 'TVA non applicable, art. 293 B du CGI.' : '',
    escompte,
    `En cas de retard de paiement : pénalités au taux de 3 fois le taux d'intérêt légal en vigueur (${annee}), exigibles sans rappel le lendemain de la date d'échéance, et indemnité forfaitaire de recouvrement de 40 € (art. L441-10 et D441-5 du Code de commerce).`,
  ].filter(Boolean).join(' ');
  const ml = doc.splitTextToSize(mentions, W - M * 2);
  doc.rect(M, y, W - M * 2, ml.length * 9 + 14);
  doc.text(ml, M + 7, y + 12);

  return doc.output('blob');
}
