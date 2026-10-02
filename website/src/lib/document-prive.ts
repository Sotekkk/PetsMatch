// Documents du stockage PRIVÉ (buckets `documents` / `contrats`) : le lien
// enregistré en base ne s'ouvre plus directement. L'Edge Function
// `lien-document` vérifie les droits de l'utilisateur sur la fiche qui
// référence le document, puis renvoie un lien valable 10 minutes.
// Tout autre lien (photo publique, Firebase…) est renvoyé tel quel.
import { supabase, supabaseLien } from '@/lib/supabase';

const PRIVE = /\/storage\/v1\/object\/public\/(documents|contrats)\//;
const cache = new Map<string, { url: string; expire: number }>();

export function estDocumentPrive(url?: string | null): boolean {
  return !!url && PRIVE.test(url);
}

/** Lien utilisable pour [url]. [lienSecret] : jeton d'un lien de partage (x-pm-token). */
export async function lienDocument(url: string, lienSecret?: string): Promise<string> {
  if (!estDocumentPrive(url)) return url;
  const cle = `${url}|${lienSecret ?? ''}`;
  const c = cache.get(cle);
  if (c && c.expire > Date.now()) return c.url;
  const client = lienSecret ? supabaseLien(lienSecret) : supabase;
  const { data, error } = await client.functions.invoke('lien-document', { body: { url } });
  const signe = (data as { url?: string } | null)?.url;
  if (error || !signe) throw new Error('Document inaccessible');
  cache.set(cle, { url: signe, expire: Date.now() + 9 * 60 * 1000 });
  return signe;
}

/** Ouvre [url] dans un nouvel onglet (lien temporaire si document privé). */
export async function ouvrirDocument(url: string, lienSecret?: string): Promise<void> {
  if (!estDocumentPrive(url)) { window.open(url, '_blank', 'noopener'); return; }
  // Onglet ouvert tout de suite (sinon bloqué comme pop-up après l'attente).
  const onglet = window.open('', '_blank');
  try {
    const lien = await lienDocument(url, lienSecret);
    if (onglet) onglet.location.href = lien; else window.location.href = lien;
  } catch {
    onglet?.close();
    alert("Impossible d'ouvrir le document.");
  }
}
