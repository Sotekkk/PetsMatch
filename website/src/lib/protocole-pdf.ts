// Fiche A4 d'un protocole, pour les employés (à imprimer et afficher dans
// les locaux). Générée à partir des données (jsPDF), pas d'une capture :
// noir et blanc, police lisible, tableau des étapes avec sauts de page
// propres, nom de la structure et date de version. Si le protocole a été
// appliqué : animaux / groupes concernés et dates calculées.

import { supabase } from '@/lib/supabase';
import {
  acteLabel, frequenceLabel, perimetreLabel, quandLabel, refEventLabel, perimetreDe,
  TRANCHES_LABELS, type ProtocoleBase,
} from '@/lib/protocoles';

interface Application {
  libelle: string;
  dateReference: string | null;
  etapes: { etapeId: string; debut: string; fin: string; nb: number }[];
}

const fmt = (iso: string | null | undefined) => iso ? new Date(iso + (iso.length === 10 ? 'T12:00:00' : '')).toLocaleDateString('fr-FR') : '';

async function chargerApplications(t: ProtocoleBase): Promise<Application[]> {
  const { data: plans } = await supabase.from('plans_actifs')
    .select('id, reference_id, reference_label, date_reference, statut')
    .eq('template_id', t.id).eq('statut', 'actif')
    .order('date_reference', { ascending: false }).limit(60);
  if (!plans?.length) return [];
  const ids = plans.map(p => p.id as string);
  const { data: taches } = await supabase.from('plan_taches')
    .select('plan_id, etape_id, date_prevue, animal_nom').in('plan_id', ids);
  const animalIds = plans.map(p => p.reference_id).filter(Boolean) as string[];
  const noms = new Map<string, string>();
  if (animalIds.length) {
    const { data: an } = await supabase.from('animaux').select('id, nom').in('id', animalIds);
    for (const a of an ?? []) noms.set(a.id as string, a.nom as string);
  }
  return plans.map(p => {
    const ts = (taches ?? []).filter(x => x.plan_id === p.id);
    const parEtape = new Map<string, string[]>();
    for (const x of ts) {
      const k = (x.etape_id as string) ?? '';
      if (!parEtape.has(k)) parEtape.set(k, []);
      parEtape.get(k)!.push(x.date_prevue as string);
    }
    const nomTache = ts.find(x => x.animal_nom)?.animal_nom as string | undefined;
    return {
      libelle: (p.reference_label as string) || (p.reference_id ? noms.get(p.reference_id as string) : undefined) || nomTache
        || (perimetreDe(t) === 'locaux' ? (t.lieu || 'Locaux') : 'Groupe'),
      dateReference: (p.date_reference as string) ?? null,
      etapes: [...parEtape.entries()].map(([etapeId, ds]) => {
        const tri = [...ds].sort();
        return { etapeId, debut: tri[0], fin: tri[tri.length - 1], nb: tri.length };
      }),
    };
  });
}

/** Logo PetsMatch (version allégée de Logo_petsmatch_fond_blanc) en data URL. */
async function chargerLogo(): Promise<string | null> {
  try {
    const res = await fetch('/logo-pdf.jpg');
    if (!res.ok) return null;
    const blob = await res.blob();
    return await new Promise<string>((ok, ko) => {
      const r = new FileReader();
      r.onload = () => ok(r.result as string);
      r.onerror = ko;
      r.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

export async function genererFicheProtocole(t: ProtocoleBase, opts: { structure: string; profilSource?: string; logo?: string | null }): Promise<Blob> {
  const { jsPDF } = await import('jspdf');
  const { default: autoTable } = await import('jspdf-autotable');
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const W = doc.internal.pageSize.getWidth();
  const M = 16;
  const etapes = [...(t.plan_template_etapes ?? [])].sort((a, b) => a.ordre - b.ordre);
  const version = fmt((t.updated_at || t.created_at || new Date().toISOString()).slice(0, 10));
  const perimetre = perimetreLabel(t, opts.profilSource);
  const locaux = perimetreDe(t, opts.profilSource) === 'locaux';

  // En-tête : logo PetsMatch + structure
  doc.setTextColor(0);
  const logo = opts.logo === undefined ? await chargerLogo() : opts.logo;
  if (logo) {
    doc.addImage(logo, 'JPEG', M, 7, 20, 20);
  } else {
    doc.setFont('helvetica', 'bold'); doc.setFontSize(13);
    doc.text('PetsMatch', M, 18);
  }
  doc.setFont('helvetica', 'bold'); doc.setFontSize(11);
  doc.text(opts.structure || '', W - M, 16, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
  doc.text('Fiche protocole', W - M, 21, { align: 'right' });
  doc.setLineWidth(0.4); doc.line(M, 30, W - M, 30);

  // Titre + périmètre
  doc.setFont('helvetica', 'bold'); doc.setFontSize(20);
  const titre = doc.splitTextToSize(t.nom.toUpperCase(), W - 2 * M);
  doc.text(titre, W / 2, 42, { align: 'center' });
  let y = 42 + (titre.length - 1) * 8 + 8;
  doc.setFontSize(12);
  doc.text(perimetre, W / 2, y, { align: 'center' });
  y += 6;
  if (!locaux && t.reference_event) {
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10.5);
    doc.text(`Calcul des dates : ${refEventLabel(t.reference_event)}`, W / 2, y, { align: 'center' });
    y += 5;
  }
  if (t.description) {
    doc.setFont('helvetica', 'normal'); doc.setFontSize(11);
    const d = doc.splitTextToSize(t.description, W - 2 * M);
    y += 3; doc.text(d, M, y); y += d.length * 5;
  }
  y += 3; doc.line(M, y, W - M, y); y += 8;

  doc.setFont('helvetica', 'bold'); doc.setFontSize(13);
  doc.text('PROTOCOLE EMPLOYÉS', W / 2, y, { align: 'center' });
  y += 4;

  // Tableau des étapes
  autoTable(doc, {
    startY: y,
    margin: { left: M, right: M, bottom: 20 },
    head: [['Étape', 'Action', 'Quand', 'Fréquence / durée', 'Créneau', 'Consignes']],
    body: etapes.map((e, i) => {
      const consignes = [
        e.produit ? `Produit : ${e.produit}${e.dosage ? ` — ${e.dosage}` : ''}` : (e.dosage ? `Dosage : ${e.dosage}` : ''),
        e.lieu ? `Lieu : ${e.lieu}` : '',
        e.description ?? '',
      ].filter(Boolean).join('\n');
      return [
        String(i + 1),
        acteLabel(e.type_acte),
        quandLabel(e, t.reference_event),
        frequenceLabel(e),
        e.tranche_horaire ? (TRANCHES_LABELS[e.tranche_horaire] ?? e.tranche_horaire) : '—',
        consignes || '—',
      ];
    }),
    theme: 'grid',
    styles: { font: 'helvetica', fontSize: 10.5, textColor: 0, lineColor: 0, lineWidth: 0.25, cellPadding: 2.2, valign: 'top' },
    headStyles: { fillColor: [225, 225, 225], textColor: 0, fontStyle: 'bold', lineColor: 0, lineWidth: 0.25 },
    columnStyles: { 0: { cellWidth: 17, halign: 'center', fontStyle: 'bold' }, 1: { cellWidth: 30 }, 2: { cellWidth: 31 }, 3: { cellWidth: 31 }, 4: { cellWidth: 21 } },
    rowPageBreak: 'avoid',
    showHead: 'everyPage',
  });

  // Application(s) en cours
  const apps = await chargerApplications(t).catch(() => [] as Application[]);
  if (apps.length > 0) {
    let yy = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 10;
    if (yy > 250) { doc.addPage(); yy = 22; }
    doc.setFont('helvetica', 'bold'); doc.setFontSize(13);
    doc.text(locaux ? 'APPLICATION EN COURS' : 'ANIMAUX / GROUPES CONCERNÉS', M, yy);
    const numEtape = new Map(etapes.map((e, i) => [e.id ?? '', i + 1]));
    autoTable(doc, {
      startY: yy + 3,
      margin: { left: M, right: M, bottom: 20 },
      head: [['Concerné', 'Date de référence', 'Dates calculées']],
      body: apps.map(a => [
        a.libelle,
        fmt(a.dateReference) || '—',
        a.etapes
          .sort((x, y2) => (numEtape.get(x.etapeId) ?? 99) - (numEtape.get(y2.etapeId) ?? 99))
          .map(s => `Étape ${numEtape.get(s.etapeId) ?? '?'} : ${s.nb > 1 ? `du ${fmt(s.debut)} au ${fmt(s.fin)} (${s.nb} fois)` : `le ${fmt(s.debut)}`}`)
          .join('\n') || '—',
      ]),
      theme: 'grid',
      styles: { font: 'helvetica', fontSize: 10, textColor: 0, lineColor: 0, lineWidth: 0.25, cellPadding: 2, valign: 'top' },
      headStyles: { fillColor: [225, 225, 225], textColor: 0, fontStyle: 'bold' },
      columnStyles: { 0: { cellWidth: 45 }, 1: { cellWidth: 32 } },
      rowPageBreak: 'avoid',
    });
  }

  // Pied de page : version + pagination
  const n = doc.getNumberOfPages();
  for (let p = 1; p <= n; p++) {
    doc.setPage(p);
    const H = doc.internal.pageSize.getHeight();
    doc.setLineWidth(0.3); doc.line(M, H - 14, W - M, H - 14);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(0);
    doc.text(`Version du ${version}${opts.structure ? ` — ${opts.structure}` : ''}`, M, H - 9);
    doc.text(`Page ${p} / ${n}`, W - M, H - 9, { align: 'right' });
  }
  return doc.output('blob');
}

/** Ouvre la fiche dans un nouvel onglet (imprimer ou télécharger depuis le
 * lecteur PDF) ; repli : téléchargement direct si les onglets sont bloqués. */
export async function ouvrirFicheProtocole(t: ProtocoleBase, opts: { structure: string; profilSource?: string }) {
  const onglet = window.open('', '_blank');
  const blob = await genererFicheProtocole(t, opts);
  const url = URL.createObjectURL(blob);
  const nomFichier = `Protocole - ${t.nom}.pdf`.replace(/[\\/:*?"<>|]/g, '-');
  if (onglet) {
    onglet.location.href = url;
  } else {
    const a = document.createElement('a');
    a.href = url; a.download = nomFichier; a.click();
  }
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
