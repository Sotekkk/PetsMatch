// Documents faits par le professionnel lui-même (tous les métiers) :
//  • compte rendu chargé (PDF, ou photo convertie en PDF) — rangé dans
//    documents_animaux (type « compte_rendu_pro »), envoyé au client à la
//    place du compte rendu généré ;
//  • contrat chargé (type « contrat_document_pro ») — signé en ligne comme
//    les contrats générés (/signer-contrat/[token]) ; le PDF signé = le
//    document du pro + une page de signatures ajoutée à la fin.
// Stockage privé `documents` (documents-pro/<uid>/…), ouvert via lienDocument.
// Miroir appli : lib/utils/document_pro.dart.
import { jsPDF } from 'jspdf';
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import { supabase } from '@/lib/supabase';

export const ACCEPT_DOCUMENT_PRO = 'application/pdf,image/*';
export const TYPE_CR_PRO = 'compte_rendu_pro';
export const TYPE_CONTRAT_PRO = 'contrat_document_pro';

export interface RdvDocumentPro {
  id: string; animal_id?: string | null; pro_profile_id?: string | null;
  client_uid?: string | null; client_profile_id?: string | null;
}

function chargerImage(f: File): Promise<HTMLImageElement> {
  return new Promise((ok, ko) => {
    const url = URL.createObjectURL(f);
    const img = new Image();
    img.onload = () => { URL.revokeObjectURL(url); ok(img); };
    img.onerror = () => { URL.revokeObjectURL(url); ko(new Error('Image illisible')); };
    img.src = url;
  });
}

/** PDF tel quel ; photo → PDF A4 (image réduite à 1600 px, ajustée à la page). */
export async function fichierEnPdf(f: File): Promise<Blob> {
  if (f.type === 'application/pdf' || f.name.toLowerCase().endsWith('.pdf')) return f;
  if (!f.type.startsWith('image/')) throw new Error('Format accepté : PDF ou photo.');
  const img = await chargerImage(f);
  const r = Math.min(1, 1600 / Math.max(img.width, img.height));
  const c = document.createElement('canvas');
  c.width = Math.round(img.width * r); c.height = Math.round(img.height * r);
  c.getContext('2d')!.drawImage(img, 0, 0, c.width, c.height);
  const jpeg = c.toDataURL('image/jpeg', 0.85);
  const paysage = c.width > c.height;
  const doc = new jsPDF({ unit: 'pt', format: 'a4', orientation: paysage ? 'landscape' : 'portrait' });
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 24;
  const k = Math.min((W - 2 * M) / c.width, (H - 2 * M) / c.height);
  doc.addImage(jpeg, 'JPEG', (W - c.width * k) / 2, (H - c.height * k) / 2, c.width * k, c.height * k);
  return doc.output('blob');
}

async function deposer(blob: Blob, uid: string): Promise<string> {
  const path = `documents-pro/${uid}/${crypto.randomUUID()}.pdf`;
  const { error } = await supabase.storage.from('documents').upload(path, blob, { contentType: 'application/pdf', upsert: true });
  if (error) throw new Error(`Envoi du fichier : ${error.message}`);
  return supabase.storage.from('documents').getPublicUrl(path).data.publicUrl;
}

/** Compte rendu chargé par le pro, rattaché au RDV (et à l'animal s'il a une fiche). */
export async function chargerCompteRenduPro(blob: Blob, o: { rdv: RdvDocumentPro; uid: string; proProfileId: string | null; titre: string }) {
  const url = await deposer(blob, o.uid);
  const { data, error } = await supabase.from('documents_animaux').insert({
    uid_eleveur: o.uid, ...(o.proProfileId ? { pro_profile_id: o.proProfileId } : {}),
    animal_id: o.rdv.animal_id ?? null, rdv_id: o.rdv.id, type: TYPE_CR_PRO, titre: o.titre, url, statut: 'envoye',
    metadata: { client_uid: o.rdv.client_uid ?? null, client_profile_id: o.rdv.client_profile_id ?? null },
  }).select('id').single();
  if (error) throw new Error(error.message);
  return { id: String(data.id), url };
}

export interface DocumentProRdv { id: string; titre: string | null; url: string; created_at: string }

/** Comptes rendus chargés pour un RDV. */
export async function comptesRendusProDuRdv(rdvId: string): Promise<DocumentProRdv[]> {
  const { data } = await supabase.from('documents_animaux').select('id, titre, url, created_at')
    .eq('rdv_id', rdvId).eq('type', TYPE_CR_PRO).order('created_at');
  return (data ?? []) as DocumentProRdv[];
}

/** Contrat chargé par le pro : à signer en ligne par le client. */
export async function creerContratPro(blob: Blob, o: {
  rdv: RdvDocumentPro; uid: string; proProfileId: string | null; titre: string; clientNom: string; clientEmail: string | null;
}): Promise<{ id: string; token: string }> {
  const url = await deposer(blob, o.uid);
  const { data, error } = await supabase.from('documents_animaux').insert({
    uid_eleveur: o.uid, ...(o.proProfileId ? { pro_profile_id: o.proProfileId } : {}),
    animal_id: o.rdv.animal_id ?? null, rdv_id: o.rdv.id, type: TYPE_CONTRAT_PRO, titre: o.titre, statut: 'en_attente',
    url, pdf_original_url: url,
    // client_uid / client_profile_id / client_email : le contrat remonte dans « Mes contrats » du client.
    metadata: { document_pro: true, client_nom: o.clientNom, client_uid: o.rdv.client_uid ?? null,
      client_profile_id: o.rdv.client_profile_id ?? null, client_email: o.clientEmail },
  }).select('id, token').single();
  if (error) throw new Error(error.message);
  return { id: String(data.id), token: String(data.token) };
}

const echap = (s: string) => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));

/** Page de signature d'un contrat chargé : le document du pro, puis les deux signatures. */
export function contratProHtml(o: { titre: string; lien: string | null; proNom: string; clientNom: string }): string {
  const bloc = (role: 'vendeur' | 'acheteur', titre: string, nom: string) => `
<div class="sign-block" data-signer="${role}">
  <div class="sign-label">${titre}</div><div class="sign-name">${echap(nom || '…')}</div>
  <div class="sign-img"></div><div class="sign-note">« Lu et approuvé »</div>
</div>`;
  return `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>${echap(o.titre)}</title><style>
*{box-sizing:border-box}body{font-family:Arial,sans-serif;font-size:12px;margin:0;color:#222;line-height:1.5}
.page{max-width:820px;margin:0 auto;padding:24px 28px 60px}h1{font-size:17px;text-align:center;margin:0 0 6px}
.note{text-align:center;color:#666;font-size:11px;margin-bottom:12px}.doc{width:100%;height:70vh;border:1px solid #ddd;border-radius:8px}
.ouvrir{display:inline-block;margin:8px 0 16px;color:#0C5C6C;font-weight:bold}
.sign-section{margin-top:20px}.sign-row{display:flex;gap:24px}
.sign-block{flex:1;border:1px solid #ddd;border-radius:8px;padding:12px 14px;text-align:center}
.sign-label{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:.5px;color:#0C5C6C;margin-bottom:2px}
.sign-name{font-size:10px;color:#555;margin-bottom:6px}
.sign-img{height:64px;border-bottom:1px solid #888;display:flex;align-items:center;justify-content:center;margin-bottom:4px}
.sign-img img{max-height:60px;max-width:100%;object-fit:contain}.sign-note{font-size:9px;color:#888}
</style></head><body><div class="page">
<h1>${echap(o.titre)}</h1>
<div class="note">Contrat rédigé par ${echap(o.proNom || 'le professionnel')}. Lisez le document ci-dessous avant de signer.</div>
${o.lien ? `<iframe class="doc" src="${echap(o.lien)}"></iframe><div><a class="ouvrir" href="${echap(o.lien)}" target="_blank" rel="noopener">Ouvrir le document en grand</a></div>`
    : '<p class="note">Document momentanément indisponible : réessayez dans un instant.</p>'}
<div class="sign-section"><div class="sign-row">
${bloc('vendeur', 'Le Prestataire', o.proNom)}${bloc('acheteur', 'Le Client', o.clientNom)}
</div></div></div></body></html>`;
}

async function imageSignature(pdf: PDFDocument, dataUrl?: string | null) {
  if (!dataUrl?.startsWith('data:image/')) return null;
  const octets = Uint8Array.from(atob(dataUrl.split(',')[1] ?? ''), c => c.charCodeAt(0));
  return dataUrl.startsWith('data:image/png') ? pdf.embedPng(octets) : pdf.embedJpg(octets);
}

/** PDF du contrat chargé + une page de signatures à la fin. */
export async function contratProSigne(original: Blob, o: {
  titre: string; proNom: string; clientNom: string;
  sigPro?: string | null; sigClient?: string | null; signeLePro?: string | null; signeLeClient?: string | null;
}): Promise<Blob> {
  const pdf = await PDFDocument.load(await original.arrayBuffer(), { ignoreEncryption: true });
  const page = pdf.addPage([595.28, 841.89]);
  const gras = await pdf.embedFont(StandardFonts.HelveticaBold);
  const normal = await pdf.embedFont(StandardFonts.Helvetica);
  // Polices standard (WinAnsi) : caractères hors Latin-1 retirés.
  const t = (s: string) => s.replace(/[^\x20-\x7E\xA0-\xFF]/g, '');
  const teal = rgb(12 / 255, 92 / 255, 108 / 255);
  page.drawText(t('Signatures'), { x: 50, y: 780, size: 18, font: gras, color: teal });
  page.drawText(t(o.titre), { x: 50, y: 756, size: 11, font: normal, maxWidth: 495 });
  const colonne = async (x: number, titre: string, nom: string, sig?: string | null, le?: string | null) => {
    page.drawText(t(titre), { x, y: 700, size: 10, font: gras, color: teal });
    page.drawText(t(nom || '-'), { x, y: 684, size: 10, font: normal });
    const img = await imageSignature(pdf, sig);
    if (img) {
      const k = Math.min(220 / img.width, 80 / img.height);
      page.drawImage(img, { x, y: 590, width: img.width * k, height: img.height * k });
    }
    page.drawLine({ start: { x, y: 585 }, end: { x: x + 220, y: 585 }, thickness: 0.5, color: rgb(0.5, 0.5, 0.5) });
    page.drawText(t(le ? `Signé le ${new Date(le).toLocaleDateString('fr-FR')}` : sig ? 'Signé' : 'Non signé'), { x, y: 570, size: 9, font: normal });
    page.drawText(t('« Lu et approuvé »'), { x, y: 556, size: 8, font: normal, color: rgb(0.45, 0.45, 0.45) });
  };
  await colonne(50, 'Le Prestataire', o.proNom, o.sigPro, o.signeLePro);
  await colonne(320, 'Le Client', o.clientNom, o.sigClient, o.signeLeClient);
  page.drawText(t('Signatures électroniques recueillies sur PetsMatch.'), { x: 50, y: 60, size: 8, font: normal, color: rgb(0.5, 0.5, 0.5) });
  return new Blob([new Uint8Array(await pdf.save())], { type: 'application/pdf' });
}
