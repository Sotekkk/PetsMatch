// Imprimer / envoyer par e-mail une ordonnance ou un compte rendu (PDF), y
// compris à un propriétaire sans PetsMatch. Miroir app :
// lib/pages/pro/transmission_document.dart.
import { apiFetch } from '@/lib/api-fetch';
import { lienDocument } from '@/lib/document-prive';

/** Ouvre le PDF dans un onglet (impression via le lecteur du navigateur). */
export function imprimerPdf(blob: Blob) {
  const url = URL.createObjectURL(blob);
  const w = window.open(url, '_blank');
  if (w) w.addEventListener('load', () => { try { w.print(); } catch { /* lecteur PDF */ } });
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

/** PDF stocké (ordonnance) → Blob, via un lien temporaire si privé. */
export async function pdfDepuisUrl(url: string): Promise<Blob> {
  const res = await fetch(await lienDocument(url));
  if (!res.ok) throw new Error('Document inaccessible');
  return res.blob();
}

async function enBase64(blob: Blob): Promise<string> {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(bin);
}

/** Envoie le PDF par e-mail (demande l'adresse, pré-remplie). */
export async function envoyerPdfParEmail(blob: Blob, opts: {
  type: 'ordonnance' | 'compte_rendu'; emailParDefaut?: string | null; destinataireNom?: string;
  expediteur?: string; animalNom?: string; nomFichier: string;
}): Promise<boolean> {
  const email = window.prompt('E-mail du propriétaire', opts.emailParDefaut ?? '');
  if (!email?.trim()) return false;
  const res = await apiFetch('/api/documents/envoyer-email', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: email.trim(), destinataire_nom: opts.destinataireNom, expediteur_nom: opts.expediteur,
      document_type: opts.type, animal_nom: opts.animalNom, fichier_nom: opts.nomFichier, pdf_base64: await enBase64(blob),
    }),
  });
  alert(res.ok ? `Envoyé à ${email.trim()}.` : "L'envoi a échoué.");
  return res.ok;
}
