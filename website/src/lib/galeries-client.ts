// Galeries privées photographe — côté navigateur : génération des aperçus
// (compression + filigrane facultatif) et import par lots vers le bucket
// privé via URL d'envoi signées (routes /api/galeries/*). Miroir appli :
// lib/utils/galeries_api.dart.
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';

/** Taille max (côté le plus long) et qualité des aperçus conservés. */
export const APERCU_MAX = 1600;
export const APERCU_QUALITE = 0.78;

export interface PhotoGalerie {
  id: string; url: string; largeur: number | null; hauteur: number | null; ordre: number;
  nom_fichier?: string | null; storage_path?: string | null; favori?: boolean;
}
export interface ContenuGalerie {
  role: 'pro' | 'client';
  album: {
    id: string; titre: string | null; description: string | null; statut: string; date_seance: string | null;
    /** Id de la photo de couverture (album_photos.id). */
    couverture_url: string | null; filigrane: boolean; partage_client: boolean;
    rdv_id?: string | null; client_uid?: string | null; client_profile_id?: string | null;
  };
  studio: { nom: string; avatar: string | null };
  photos: PhotoGalerie[];
}

export async function chargerGalerie(albumId: string, token?: string): Promise<ContenuGalerie> {
  const r = await apiFetch(`/api/galeries/${albumId}${token ? `?token=${encodeURIComponent(token)}` : ''}`, { cache: 'no-store' });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error ?? 'Galerie indisponible');
  return j as ContenuGalerie;
}

export async function chargerGalerieParLien(token: string): Promise<ContenuGalerie> {
  const r = await fetch(`/api/galeries/lien/${encodeURIComponent(token)}`, { cache: 'no-store' });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error ?? 'Lien expiré ou désactivé');
  return j as ContenuGalerie;
}

function chargerImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Image illisible')); };
    img.src = url;
  });
}

/** Aperçu compressé, proportions conservées, filigrane en diagonale si demandé. */
export async function preparerApercu(file: File, filigrane: string | null): Promise<{ blob: Blob; largeur: number; hauteur: number }> {
  const img = await chargerImage(file);
  const ratio = Math.min(1, APERCU_MAX / Math.max(img.width, img.height));
  const w = Math.round(img.width * ratio), h = Math.round(img.height * ratio);
  const canvas = document.createElement('canvas');
  canvas.width = w; canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Navigateur incompatible');
  ctx.drawImage(img, 0, 0, w, h);
  if (filigrane) {
    const taille = Math.max(18, Math.round(Math.min(w, h) / 16));
    ctx.save();
    ctx.translate(w / 2, h / 2);
    ctx.rotate(-Math.PI / 6);
    ctx.font = `600 ${taille}px Galey, Arial, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = 'rgba(255,255,255,0.32)';
    ctx.strokeStyle = 'rgba(0,0,0,0.18)';
    ctx.lineWidth = Math.max(1, taille / 18);
    const pasY = taille * 4, pasX = ctx.measureText(filigrane).width + taille * 3;
    const diag = Math.sqrt(w * w + h * h);
    for (let y = -diag / 2; y < diag / 2; y += pasY) {
      for (let x = -diag / 2; x < diag / 2; x += pasX) {
        const dx = (Math.round(y / pasY) % 2) * (pasX / 2);
        ctx.strokeText(filigrane, x + dx, y);
        ctx.fillText(filigrane, x + dx, y);
      }
    }
    ctx.restore();
  }
  const blob = await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error('Compression impossible'))), 'image/jpeg', APERCU_QUALITE));
  return { blob, largeur: w, hauteur: h };
}

export interface BilanImport { ajoutees: number; doublons: number; erreurs: string[] }

/** Import par lots : préparation serveur (doublons écartés), aperçu, envoi
 *  signé, puis enregistrement. onProgres(fait, total). */
export async function importerPhotos(albumId: string, files: File[], filigrane: string | null,
  onProgres: (fait: number, total: number) => void): Promise<BilanImport> {
  const bilan: BilanImport = { ajoutees: 0, doublons: 0, erreurs: [] };
  const LOT = 20;
  let fait = 0;
  for (let i = 0; i < files.length; i += LOT) {
    const lot = files.slice(i, i + LOT);
    const r = await apiFetch(`/api/galeries/${albumId}/photos`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'preparer', fichiers: lot.map(f => ({ nom: f.name, taille: f.size })) }),
    });
    const j = await r.json();
    if (!r.ok) throw new Error(j.error ?? 'Import impossible');
    const prets: { path: string; nom: string; taille: number; largeur: number; hauteur: number }[] = [];
    for (let k = 0; k < lot.length; k++) {
      const f = lot[k];
      const cible = (j.fichiers as { doublon: boolean; path?: string; token?: string }[])[k];
      if (!cible || cible.doublon || !cible.path || !cible.token) { bilan.doublons++; fait++; onProgres(fait, files.length); continue; }
      try {
        const { blob, largeur, hauteur } = await preparerApercu(f, filigrane);
        const { error } = await supabase.storage.from('galeries').uploadToSignedUrl(cible.path, cible.token, blob, { contentType: 'image/jpeg' });
        if (error) throw error;
        prets.push({ path: cible.path, nom: f.name, taille: f.size, largeur, hauteur });
      } catch (e) {
        bilan.erreurs.push(`${f.name} : ${(e as Error).message}`);
      }
      fait++; onProgres(fait, files.length);
    }
    if (prets.length) {
      const e = await apiFetch(`/api/galeries/${albumId}/photos`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'enregistrer', photos: prets }),
      });
      if (!e.ok) bilan.erreurs.push(((await e.json()) as { error?: string }).error ?? 'Enregistrement impossible');
      else bilan.ajoutees += prets.length;
    }
  }
  return bilan;
}

export async function supprimerPhotos(albumId: string, ids: string[]) {
  const r = await apiFetch(`/api/galeries/${albumId}/photos`, {
    method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ids }),
  });
  if (!r.ok) throw new Error(((await r.json()) as { error?: string }).error ?? 'Suppression impossible');
}

export async function supprimerGalerie(albumId: string) {
  const r = await apiFetch(`/api/galeries/${albumId}`, { method: 'DELETE' });
  if (!r.ok) throw new Error(((await r.json()) as { error?: string }).error ?? 'Suppression impossible');
}
