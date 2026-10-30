// Compte rendu de toilettage en PDF (fiche technique du RDV : prestations,
// coupe, finition, produits, compte rendu, conseils de soin du pelage) —
// envoyé au client à la fin de séance avec la facture. Signature du
// toiletteur apposée. Miroir appli : compteRenduToilettagePdf
// (lib/pages/pro/toilettage_dossier_seance.dart).
import { supabase } from '@/lib/supabase';
import { TRAVAUX_TOILETTAGE } from '@/lib/toilettage';

const TEAL: [number, number, number] = [12, 92, 108];
const DARK: [number, number, number] = [30, 32, 37];

export interface SeanceToilettagePdf {
  id: string; animal_id: string | null; date_seance: string | null; travaux: string[] | null;
  longueur_coupe: string | null; zones: string | null; finition: string | null; produits: string | null;
  compte_rendu: string | null; conseils_pelage?: string | null; pro_profile_id?: string | null;
}

/** Fiche technique (seances_toilettage) du RDV, ou null. */
export async function seanceToilettageDuRdv(rdvId: string): Promise<SeanceToilettagePdf | null> {
  const { data } = await supabase.from('seances_toilettage').select('*').eq('rdv_id', rdvId).maybeSingle();
  return (data as SeanceToilettagePdf | null) ?? null;
}

export async function pdfCompteRenduToilettage(s: SeanceToilettagePdf, o: { proProfileId: string | null; signature?: string | null; nomAnimal?: string }): Promise<Blob> {
  const v = (x: unknown) => String(x ?? '').trim();
  const [{ data: pro }, { data: an }] = await Promise.all([
    o.proProfileId
      ? supabase.from('user_profiles_complet').select('nom, firstname, lastname, rue_pro, code_postal_pro, ville_pro, rue, code_postal, ville, phone_number, phone, email_contact')
        .eq('id', o.proProfileId).maybeSingle()
      : Promise.resolve({ data: null }),
    s.animal_id ? supabase.from('animaux').select('nom, espece, race').eq('id', s.animal_id).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  const p = (pro ?? {}) as Record<string, unknown>;
  const a = (an ?? {}) as Record<string, unknown>;
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight();
  const M = 40;
  let y = 50;
  const salon = v(p.nom) || `${v(p.firstname)} ${v(p.lastname)}`.trim() || 'Salon de toilettage';
  doc.setFont('helvetica', 'bold'); doc.setFontSize(15); doc.setTextColor(...TEAL);
  doc.text(salon, M, y);
  doc.setFontSize(12); doc.text('COMPTE RENDU DE TOILETTAGE', W - M, y, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...DARK);
  const date = s.date_seance ? new Date(s.date_seance) : new Date();
  doc.text(`Le ${date.toLocaleDateString('fr-FR')}`, W - M, y + 14, { align: 'right' });
  const adresse = (v(p.rue_pro) || v(p.ville_pro) ? [p.rue_pro, `${v(p.code_postal_pro)} ${v(p.ville_pro)}`.trim()] : [p.rue, `${v(p.code_postal)} ${v(p.ville)}`.trim()])
    .map(v).filter(Boolean).join(', ');
  for (const l of [adresse, v(p.phone_number) || v(p.phone) ? `Tél. ${v(p.phone_number) || v(p.phone)}` : '', v(p.email_contact)]) { if (l) { y += 13; doc.text(l, M, y); } }
  y += 16; doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y); y += 20;

  doc.setFont('helvetica', 'bold'); doc.setFontSize(12);
  doc.text(v(a.nom) || o.nomAnimal || 'Animal', M, y);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(10);
  const er = [a.espece, a.race].map(v).filter(Boolean).join(' · ');
  if (er) { y += 14; doc.text(er, M, y); }
  y += 22;

  const libelles = new Map(TRAVAUX_TOILETTAGE);
  const lignes: [string, string][] = [
    ['Prestations réalisées', (s.travaux ?? []).map(t => libelles.get(t) ?? t).join(', ')],
    ['Longueur de coupe', v(s.longueur_coupe)],
    ['Zones', v(s.zones)],
    ['Finition', v(s.finition)],
    ['Produits utilisés', v(s.produits)],
    ['Compte rendu', v(s.compte_rendu)],
    ['Conseils de soin du pelage', v(s.conseils_pelage)],
  ];
  const largeur = W - 2 * M;
  for (const [titre, texte] of lignes) {
    if (!texte) continue;
    if (y > H - 120) { doc.addPage(); y = 50; }
    doc.setFont('helvetica', 'bold'); doc.setFontSize(10.5); doc.setTextColor(...TEAL);
    doc.text(titre, M, y); y += 14;
    doc.setFont('helvetica', 'normal'); doc.setTextColor(...DARK);
    for (const t of doc.splitTextToSize(texte, largeur) as string[]) {
      if (y > H - 90) { doc.addPage(); y = 50; }
      doc.text(t, M, y); y += 13;
    }
    y += 8;
  }

  // Bloc signature : salon, date du jour, « Signature : » puis la signature.
  if (y + 110 > H - 40) { doc.addPage(); y = 50; }
  y += 16;
  const xs = W - M - 180;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...DARK);
  doc.text(salon, xs, y); y += 14;
  doc.setFont('helvetica', 'normal');
  doc.text(`Le ${new Date().toLocaleDateString('fr-FR')}`, xs, y); y += 14;
  doc.text('Signature :', xs, y);
  if (o.signature) { try { doc.addImage(o.signature, 'PNG', xs, y + 6, 130, 52); } catch { /* signature illisible */ } }
  return doc.output('blob');
}
