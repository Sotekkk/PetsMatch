// Contrat de garde signé en PDF (fin de garde : envoyé au client à la place du
// lien quand les deux parties ont signé). Même contenu que /signer-contrat
// (generateContratGardeHTML), mis en page texte + signatures avec jsPDF.
// Miroir appli : contratGardePdfBytes (lib/pages/eleveur/animaux/contrat_pdf.dart).
import { supabase } from '@/lib/supabase';
import { generateContratGardeHTML } from '@/lib/contrat-garde';

type Bloc = { k: 'titre' | 'art' | 'texte' | 'ligne'; t: string } | { k: 'img'; src: string } | { k: 'sig'; titre: string; nom: string; src?: string };

const BLOCS = new Set(['DIV', 'P', 'H1', 'H2', 'H3', 'TABLE', 'TBODY', 'TR', 'SECTION', 'UL', 'LI']);

function texte(el: Element): string {
  let s = '';
  el.childNodes.forEach(n => {
    if (n.nodeType === 3) s += n.textContent ?? '';
    else if ((n as Element).tagName === 'BR') s += '\n';
    else if (n.nodeType === 1) s += texte(n as Element);
  });
  return s.replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n').trim();
}

function blocs(el: Element, out: Bloc[]) {
  for (const c of Array.from(el.children)) {
    const cls = c.getAttribute('class') ?? '';
    if (c.tagName === 'STYLE' || c.tagName === 'SCRIPT' || cls.includes('foot')) continue;
    if (cls.includes('sign-block')) {
      const img = c.querySelector('img');
      out.push({ k: 'sig', titre: texte(c.querySelector('.sign-label') ?? c), nom: texte(c.querySelector('.sign-name') ?? c), src: img?.getAttribute('src') ?? undefined });
      continue;
    }
    if (c.tagName === 'H1' || c.tagName === 'H2' || c.tagName === 'H3') { out.push({ k: 'titre', t: texte(c) }); continue; }
    if (cls.includes('art-title')) { out.push({ k: 'art', t: texte(c) }); continue; }
    if (c.tagName === 'TR') { out.push({ k: 'ligne', t: Array.from(c.children).map(td => texte(td)).filter(Boolean).join(' : ') }); continue; }
    if (c.tagName === 'IMG') { const src = c.getAttribute('src'); if (src) out.push({ k: 'img', src }); continue; }
    const aBlocs = Array.from(c.children).some(x => BLOCS.has(x.tagName) || (x.getAttribute('class') ?? '').includes('sign'));
    if (aBlocs) blocs(c, out);
    else { const t = texte(c); if (t) out.push({ k: 'texte', t }); }
  }
}

/** PDF du contrat de garde signé, ou null si le document est introuvable. */
export async function pdfContratGardeSigne(docId: string): Promise<Blob | null> {
  const { data: doc } = await supabase.from('documents_animaux')
    .select('id, titre, metadata, animal_id, pro_profile_id, signe_le').eq('id', docId).maybeSingle();
  if (!doc) return null;
  const meta = (doc.metadata ?? {}) as Record<string, string>;
  const [{ data: pro }, { data: an }] = await Promise.all([
    doc.pro_profile_id
      ? supabase.from('user_profiles_complet').select('nom, firstname, lastname, rue_pro, code_postal_pro, ville_pro, rue, code_postal, ville, phone_number, phone, numero_elevage, email_contact, siret')
        .eq('id', doc.pro_profile_id).maybeSingle()
      : Promise.resolve({ data: null }),
    doc.animal_id ? supabase.from('animaux').select('nom, espece, race').eq('id', doc.animal_id).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  const p = (pro ?? {}) as Record<string, string | null>;
  const v = (x: unknown) => String(x ?? '').trim();
  const adresse = (v(p.rue_pro) || v(p.ville_pro) ? [p.rue_pro, [p.code_postal_pro, p.ville_pro].map(v).filter(Boolean).join(' ')] : [p.rue, [p.code_postal, p.ville].map(v).filter(Boolean).join(' ')])
    .map(v).filter(Boolean).join(', ');
  const a = (an ?? {}) as Record<string, string | null>;
  let html = generateContratGardeHTML(
    {
      animal_nom: meta.animal_nom || v(a.nom), espece: v(a.espece) || undefined, race: v(a.race) || undefined,
      client_nom: meta.client_nom, client_contact: meta.client_contact || meta.client_email,
      client_email: meta.client_email, client_tel: meta.client_tel, client_adresse: meta.client_adresse,
      date_visite: meta.date_visite, type_prestation: meta.type_prestation,
    },
    {
      nom: v(p.nom) || `${v(p.firstname)} ${v(p.lastname)}`.trim() || 'Le Prestataire',
      adresse, email: v(p.email_contact), siret: v(p.siret),
      tel: v(p.numero_elevage) ? `+33 ${v(p.numero_elevage)}` : v(p.phone_number) || v(p.phone),
    },
    { tarif: meta.tarif, notes: meta.notes },
    { signatureEleveur: meta.signature_eleveur, signatureAcquereur: meta.signature_acquereur },
  );
  // Date de signature (pas la date d'envoi).
  const signe = doc.signe_le ? new Date(doc.signe_le).toLocaleDateString('fr-FR') : null;
  if (signe) html = html.replace(/Fait le [0-9/]+/, `Fait le ${signe}`);

  const out: Bloc[] = [];
  blocs(new DOMParser().parseFromString(html, 'text/html').body, out);

  const { jsPDF } = await import('jspdf');
  const pdf = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = pdf.internal.pageSize.getWidth(), H = pdf.internal.pageSize.getHeight(), M = 42, L = W - 2 * M;
  let y = 50;
  const place = (h: number) => { if (y + h > H - 46) { pdf.addPage(); y = 50; } };
  const ecrire = (t: string, size: number, gras: boolean, couleur: [number, number, number] = [30, 32, 37], apres = 4) => {
    pdf.setFont('helvetica', gras ? 'bold' : 'normal'); pdf.setFontSize(size); pdf.setTextColor(...couleur);
    for (const l of pdf.splitTextToSize(t, L) as string[]) { place(size + 3); pdf.text(l, M, y); y += size + 3; }
    y += apres;
  };
  const sigs: Extract<Bloc, { k: 'sig' }>[] = [];
  for (const b of out) {
    if (b.k === 'sig') { sigs.push(b); continue; }
    if (b.k === 'img') continue;
    if (b.k === 'titre') { y += 4; ecrire(b.t, 13, true, [12, 92, 108], 6); }
    else if (b.k === 'art') ecrire(b.t, 10.5, true, [12, 92, 108], 2);
    else ecrire(b.t, 9.5, false);
  }
  // Signatures côte à côte.
  if (sigs.length) {
    place(110);
    const col = L / sigs.length;
    sigs.forEach((s, i) => {
      const x = M + i * col;
      pdf.setFont('helvetica', 'bold'); pdf.setFontSize(10); pdf.setTextColor(12, 92, 108);
      pdf.text(s.titre, x, y);
      pdf.setFont('helvetica', 'normal'); pdf.setFontSize(9.5); pdf.setTextColor(30, 32, 37);
      pdf.text(s.nom, x, y + 13);
      if (s.src?.startsWith('data:image')) {
        try { pdf.addImage(s.src, s.src.includes('png') ? 'PNG' : 'JPEG', x, y + 20, Math.min(col - 20, 160), 60); } catch { /* signature illisible */ }
      }
      pdf.setFontSize(8.5); pdf.setTextColor(110); pdf.text('« Lu et approuvé »', x, y + 92);
    });
    y += 104;
  }
  return pdf.output('blob');
}
