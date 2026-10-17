// Galeries privées photographe — côté navigateur : génération des aperçus
// (compression + filigrane facultatif) et import par lots vers le bucket
// privé via URL d'envoi signées (routes /api/galeries/*). Miroir appli :
// lib/utils/galeries_api.dart.
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { zip } from 'fflate';

/** Taille max (côté le plus long) et qualité des aperçus conservés. */
export const APERCU_MAX = 1600;
export const APERCU_QUALITE = 0.78;

export interface PhotoGalerie {
  id: string; url: string; largeur: number | null; hauteur: number | null; ordre: number; selectionnee: boolean; aimee?: boolean;
  nom_fichier?: string | null; storage_path?: string | null; favori?: boolean;
}
export interface ContenuGalerie {
  /** 'proche' : lien partagé par le client à sa famille (consultation seule, filigrane). */
  role: 'pro' | 'client' | 'proche';
  album: {
    id: string; titre: string | null; description: string | null; statut: string; date_seance: string | null;
    /** Id de la photo de couverture (album_photos.id). */
    couverture_url: string | null; filigrane: boolean; partage_client: boolean;
    rdv_id?: string | null; client_uid?: string | null; client_profile_id?: string | null; client_email?: string | null;
    selection_confirmee_le: string | null; selection_commentaire: string | null; nb_photos_incluses: number | null; livree_le: string | null;
    prix_photo_supp?: number | null;
  };
  livraison: { id: string; numero: number; nom: string; taille: number | null; nb: number | null; expire_le: string; telechargements?: number; prolongee?: boolean }[];
  /** Photographe : facture de la séance. */
  facture?: { statut: string; numero: string; total_ttc: number } | null;
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

/** Galerie partagée aux proches (lien créé par le client). */
export async function chargerGalerieProches(token: string): Promise<ContenuGalerie> {
  const r = await fetch(`/api/galeries/proches/${encodeURIComponent(token)}`, { cache: 'no-store' });
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

const q = (token?: string) => (token ? `?token=${encodeURIComponent(token)}` : '');

/** Client : coche / décoche une photo (avant confirmation). */
export async function choisirPhoto(albumId: string, photoId: string, choisie: boolean, token?: string) {
  const r = await apiFetch(`/api/galeries/${albumId}/selection${q(token)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ photoId, choisie }),
  });
  if (!r.ok) throw new Error(((await r.json()) as { error?: string }).error ?? 'Sélection impossible');
}

/** Client : confirmation explicite et définitive de la sélection. */
export async function confirmerSelection(albumId: string, commentaire: string, token?: string) {
  const r = await apiFetch(`/api/galeries/${albumId}/selection${q(token)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ confirmer: true, commentaire }),
  });
  if (!r.ok) throw new Error(((await r.json()) as { error?: string }).error ?? 'Confirmation impossible');
}

/** Client : coup de cœur sur une photo (distinct de la sélection). */
export async function aimerPhoto(albumId: string, photoId: string, aimee: boolean, token?: string) {
  const r = await apiFetch(`/api/galeries/${albumId}/aimer${q(token)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ photoId, aimee }),
  });
  if (!r.ok) throw new Error(((await r.json()) as { error?: string }).error ?? 'Action impossible');
}

/** Client : lien de partage aux proches (créé au besoin, 90 jours). */
export async function lienProches(albumId: string, token?: string): Promise<{ url: string; expire_at: string }> {
  const r = await apiFetch(`/api/galeries/${albumId}/proches${q(token)}`, { method: 'POST' });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error ?? 'Partage impossible');
  return { url: `${window.location.origin}/galerie-proches/${j.token}`, expire_at: j.expire_at };
}

export async function desactiverLienProches(albumId: string, token?: string) {
  const r = await apiFetch(`/api/galeries/${albumId}/proches${q(token)}`, { method: 'DELETE' });
  if (!r.ok) throw new Error(((await r.json()) as { error?: string }).error ?? 'Action impossible');
}

export interface FavorisShooting {
  album: { id: string; titre: string | null; date_seance: string | null; studio: string };
  photos: { id: string; url: string; largeur: number | null; hauteur: number | null; aimee: boolean; selectionnee: boolean }[];
}

/** Mes favoris > Shootings : photos aimées et sélectionnées (profil actif). */
export async function mesFavorisShootings(profileId: string | null): Promise<FavorisShooting[]> {
  const r = await apiFetch(`/api/galeries/mes-favoris${profileId ? `?profileId=${encodeURIComponent(profileId)}` : ''}`, { cache: 'no-store' });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error ?? 'Chargement impossible');
  return j.galeries as FavorisShooting[];
}

/** Liens de téléchargement (URL signées de 10 min) des ZIP livrés. */
export async function liensLivraison(albumId: string, token?: string): Promise<{ id: string; nom: string; url: string }[]> {
  const r = await apiFetch(`/api/galeries/${albumId}/livraison${q(token)}`, { cache: 'no-store' });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error ?? 'Téléchargement indisponible');
  return j.fichiers;
}

/** Taille max d'une partie ZIP (limite d'envoi du stockage). */
export const PART_MAX = 45 * 1024 * 1024;
/** Volume max d'une livraison (stockage temporaire) et durées proposées. */
export const LIVRAISON_MAX = 500 * 1024 * 1024;
export const JOURS_LIVRAISON = [3, 7, 14];
export const JOURS_LIVRAISON_DEFAUT = 7;

/** Livraison refusée tant que la facture de la séance n'est pas payée. */
export class FactureNonPayeeError extends Error {}

/** Photographe : envoie la galerie au client par e-mail (adresse enregistrée sur la galerie). */
export async function envoyerGalerie(albumId: string, email: string, message: string) {
  const r = await apiFetch(`/api/galeries/${albumId}/envoyer`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, message }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error((j as { error?: string }).error ?? 'Envoi impossible');
}

function zipper(fichiers: Record<string, Uint8Array>): Promise<Uint8Array> {
  return new Promise((resolve, reject) => zip(fichiers, { level: 0 }, (e, d) => (e ? reject(e) : resolve(d))));
}

/** Photographe : livre les fichiers finaux. ZIP construits dans le
 *  navigateur (parties de 45 Mo max, fichiers déjà compressés : stockage
 *  sans recompression), envoyés au stockage temporaire privé, puis publiés
 *  avec une durée de disponibilité. */
export async function livrerFichiers(albumId: string, files: File[], jours: number, onProgres: (t: string) => void, forcer = false): Promise<{ email_envoye?: boolean }> {
  if (files.reduce((n, f) => n + f.size, 0) > LIVRAISON_MAX) {
    throw new Error('Livraison limitée à 500 Mo : compressez les fichiers (JPEG haute qualité) ou faites deux livraisons.');
  }
  const groupes: File[][] = [];
  let courant: File[] = [], taille = 0;
  for (const f of files) {
    if (courant.length && taille + f.size > PART_MAX) { groupes.push(courant); courant = []; taille = 0; }
    courant.push(f); taille += f.size;
  }
  if (courant.length) groupes.push(courant);
  const r = await apiFetch(`/api/galeries/${albumId}/livraison`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'preparer', parts: groupes.length, forcer }),
  });
  const j = await r.json();
  if (r.status === 409 && j.code === 'facture_non_payee') throw new FactureNonPayeeError(j.error);
  if (!r.ok) throw new Error(j.error ?? 'Livraison impossible');
  const cibles = j.parts as { path: string; token: string }[];
  const publies: { path: string; taille: number; nb: number }[] = [];
  for (let i = 0; i < groupes.length; i++) {
    onProgres(`Compression ${i + 1} / ${groupes.length}…`);
    const contenu: Record<string, Uint8Array> = {};
    const noms = new Set<string>();
    for (const f of groupes[i]) {
      let nom = f.name; let k = 2;
      while (noms.has(nom)) nom = f.name.replace(/(\.[^.]*)?$/, `-${k++}$1`);
      noms.add(nom);
      contenu[nom] = new Uint8Array(await f.arrayBuffer());
    }
    const data = await zipper(contenu);
    onProgres(`Envoi ${i + 1} / ${groupes.length}…`);
    const { error } = await supabase.storage.from('livraisons').uploadToSignedUrl(cibles[i].path, cibles[i].token,
      new Blob([data as BlobPart], { type: 'application/zip' }), { contentType: 'application/zip' });
    if (error) throw new Error(error.message.includes('size') || error.message.includes('large')
      ? 'Fichier trop volumineux pour le stockage (une photo dépasse 45 Mo ?)' : error.message);
    publies.push({ path: cibles[i].path, taille: data.byteLength, nb: groupes[i].length });
  }
  const p = await apiFetch(`/api/galeries/${albumId}/livraison`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'publier', parts: publies, jours, forcer }),
  });
  const pj = await p.json().catch(() => ({})) as { error?: string; email_envoye?: boolean };
  if (!p.ok) throw new Error(pj.error ?? 'Publication impossible');
  return pj;
}

export async function actionLivraison(albumId: string, action: 'prolonger' | 'supprimer', jours = 30) {
  const r = await apiFetch(`/api/galeries/${albumId}/livraison`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action, jours }),
  });
  if (!r.ok) throw new Error(((await r.json()) as { error?: string }).error ?? 'Action impossible');
}

export const fmtTaille = (o: number | null | undefined) =>
  !o ? '' : o > 1024 * 1024 ? `${(o / 1024 / 1024).toFixed(1).replace('.', ',')} Mo` : `${Math.round(o / 1024)} Ko`;
