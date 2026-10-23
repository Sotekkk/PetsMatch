import { compressImage } from './compress-image';

// Allègement automatique de TOUS les envois du site vers Supabase Storage
// (branché sur le client dans lib/supabase.ts) : beaucoup de pages envoyaient
// la photo brute (avatar, bannière, galerie de 6 à 8 Mo), téléchargée en
// entier à chaque affichage — d'où le dépassement « Cached Egress ».
//   • photo choisie par l'utilisateur (File jpeg/png/webp) > 300 Ko →
//     réduite à 1600 px (2000 px pour les documents) en JPEG ;
//   • document non compressible (PDF…) > 15 Mo, vidéo > 50 Mo → refusé avec
//     un message clair.
// Les Blob déjà produits par le site (uploadPhoto, PDF générés) passent tels quels.

const SANS_COMPRESSION = new Set(['galeries', 'livraisons', 'story_music']); // originaux du photographe, musique
const IMAGES = /^image\/(jpeg|jpg|png|webp)$/i;
const MO = 1024 * 1024;
export const TAILLE_MAX_DOCUMENT = 15 * MO;
export const TAILLE_MAX_VIDEO = 50 * MO;

/** Chemin accepté par Supabase Storage : accents retirés, autres caractères
 *  non ASCII remplacés par « _ » (« santé reproducteur.webp » était refusé —
 *  « Invalid key »). Un chemin ASCII reste identique (fichiers existants). */
export function cheminStockage(chemin: string): string {
  if (/^[\x20-\x7E]*$/.test(chemin)) return chemin;
  return chemin.normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/œ/g, 'oe').replace(/Œ/g, 'OE').replace(/æ/g, 'ae').replace(/Æ/g, 'AE')
    .replace(/[^\x20-\x7E]/g, '_');
}

/** Formats acceptés pour les documents d'une fiche animal (stockage `media` :
 *  PDF et images seulement). Miroir appli : kFormatsDocuments. */
export const ACCEPT_DOCUMENTS = '.pdf,.jpg,.jpeg,.png,.webp';
export const FORMATS_DOCUMENTS = 'PDF, JPG, PNG ou WEBP — 15 Mo maximum';

export type ResultatAllegement =
  | { ok: true; body: unknown; jpeg: boolean }
  | { ok: false; message: string };

export async function allegerEnvoi(bucket: string, body: unknown): Promise<ResultatAllegement> {
  if (typeof window === 'undefined' || !(body instanceof File) || SANS_COMPRESSION.has(bucket)) {
    return { ok: true, body, jpeg: false };
  }
  const taille = (n: number) => `${Math.round(n / MO)} Mo`;
  if (IMAGES.test(body.type) && body.size > 300 * 1024) {
    // PNG (logos avec transparence) : seulement s'il est lourd, fond blanc.
    if (/png/i.test(body.type) && body.size < MO) return { ok: true, body, jpeg: false };
    const blob = await compressImage(body, bucket === 'documents' ? 2000 : 1600, 0.82, false);
    if (blob !== body && blob.size < body.size) return { ok: true, body: blob, jpeg: true };
    return { ok: true, body, jpeg: false };
  }
  if (body.type.startsWith('video/') && body.size > TAILLE_MAX_VIDEO) {
    return { ok: false, message: `Vidéo trop lourde (${taille(body.size)}, 50 Mo maximum). Raccourcissez-la ou baissez sa qualité.` };
  }
  if (!body.type.startsWith('video/') && !body.type.startsWith('image/') && body.size > TAILLE_MAX_DOCUMENT) {
    return { ok: false, message: `Fichier trop lourd (${taille(body.size)}, 15 Mo maximum). Pour un document scanné, envoyez plutôt une photo.` };
  }
  return { ok: true, body, jpeg: false };
}
