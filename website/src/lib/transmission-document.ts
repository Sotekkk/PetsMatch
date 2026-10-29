// Imprimer / envoyer par e-mail une ordonnance ou un compte rendu (PDF), y
// compris à un propriétaire sans PetsMatch. Miroir app :
// lib/pages/pro/transmission_document.dart.
import { apiFetch } from '@/lib/api-fetch';
import { lienDocument } from '@/lib/document-prive';

/** Ouvre le PDF dans un onglet (impression via le lecteur du navigateur). */
/** Raison renvoyée par l'API d'envoi (« : Document trop lourd… »), sinon rien. */
async function raisonEchec(res: Response): Promise<string> {
  try { const j = await res.clone().json() as { error?: string }; return j.error ? ` : ${j.error}` : ''; } catch { return ''; }
}

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

/** Envoie le PDF par e-mail (demande l'adresse, pré-remplie). Avec
 *  [animalId] et sans adresse connue : propriétaire PetsMatch, envoyé à
 *  l'adresse de son compte, résolue par le serveur (jamais affichée). */
export async function envoyerPdfParEmail(blob: Blob, opts: {
  type: 'ordonnance' | 'compte_rendu' | 'facture'; emailParDefaut?: string | null; destinataireNom?: string;
  expediteur?: string; animalNom?: string; nomFichier: string; animalId?: string | null;
}): Promise<boolean> {
  if (!opts.emailParDefaut && opts.animalId) {
    const quoi = opts.type === 'ordonnance' ? "l'ordonnance" : opts.type === 'facture' ? 'la facture' : 'le compte rendu';
    if (!window.confirm(`Envoyer ${quoi} à ${opts.destinataireNom || 'le propriétaire'}, à l’adresse e-mail de son compte PetsMatch ?`)) return false;
    const res = await apiFetch('/api/documents/envoyer-email', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        animal_id: opts.animalId, destinataire_nom: opts.destinataireNom, expediteur_nom: opts.expediteur,
        document_type: opts.type, animal_nom: opts.animalNom, fichier_nom: opts.nomFichier, pdf_base64: await enBase64(blob),
      }),
    });
    if (res.ok) { alert(`Envoyé au propriétaire (adresse de son compte PetsMatch).`); return true; }
    if (res.status !== 404) { alert(`L'envoi a échoué${await raisonEchec(res)}.`); return false; }
    // Pas de compte / d'adresse connue : saisie de l'adresse comme avant.
  }
  const email = window.prompt('E-mail du propriétaire', opts.emailParDefaut ?? '');
  if (!email?.trim()) return false;
  const res = await apiFetch('/api/documents/envoyer-email', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: email.trim(), destinataire_nom: opts.destinataireNom, expediteur_nom: opts.expediteur,
      document_type: opts.type, animal_nom: opts.animalNom, fichier_nom: opts.nomFichier, pdf_base64: await enBase64(blob),
    }),
  });
  alert(res.ok ? `Envoyé à ${email.trim()}.` : `L'envoi a échoué${await raisonEchec(res)}.`);
  return res.ok;
}

/** Fin de consultation : plusieurs PDF (compte rendu, ordonnance, facture)
 *  dans un seul e-mail. Sans adresse connue et avec [animalId] : adresse du
 *  compte PetsMatch du propriétaire (résolue par le serveur), sinon saisie. */
export async function envoyerPiecesParEmail(pieces: { type: 'ordonnance' | 'compte_rendu' | 'facture'; blob: Blob; nomFichier: string }[], opts: {
  emailParDefaut?: string | null; destinataireNom?: string; expediteur?: string; animalNom?: string; animalId?: string | null;
}): Promise<boolean> {
  const corps = {
    destinataire_nom: opts.destinataireNom, expediteur_nom: opts.expediteur, animal_nom: opts.animalNom,
    pieces: await Promise.all(pieces.map(async p => ({ document_type: p.type, fichier_nom: p.nomFichier, pdf_base64: await enBase64(p.blob) }))),
  };
  if (!opts.emailParDefaut && opts.animalId) {
    const res = await apiFetch('/api/documents/envoyer-email', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...corps, animal_id: opts.animalId }),
    });
    if (res.ok) { alert('Envoyé au propriétaire (adresse de son compte PetsMatch).'); return true; }
    if (res.status !== 404) { alert(`L'envoi a échoué${await raisonEchec(res)}.`); return false; }
  }
  const email = window.prompt('E-mail du propriétaire', opts.emailParDefaut ?? '');
  if (!email?.trim()) return false;
  const res = await apiFetch('/api/documents/envoyer-email', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...corps, email: email.trim() }),
  });
  alert(res.ok ? `Envoyé à ${email.trim()}.` : `L'envoi a échoué${await raisonEchec(res)}.`);
  return res.ok;
}
