import { supabase } from './supabase';
import { compressImage } from './compress-image';

const BUCKET = 'media';

/**
 * Compress a File then upload to Supabase Storage.
 * Returns the public URL.
 */
export async function uploadPhoto(
  file: File,
  storagePath: string,
  options: { maxDim?: number; quality?: number; square?: boolean } = {},
): Promise<string> {
  const { maxDim = 1200, quality = 0.82, square = false } = options;
  const blob = await compressImage(file, maxDim, quality, square);
  return _upload(blob, storagePath);
}

/**
 * Upload an already-compressed Blob to Supabase Storage.
 * Returns the public URL.
 */
export async function uploadBlob(
  blob: Blob,
  storagePath: string,
): Promise<string> {
  return _upload(blob, storagePath);
}

async function _upload(blob: Blob, storagePath: string): Promise<string> {
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(storagePath, blob, { contentType: 'image/jpeg', upsert: true });
  if (error) throw new Error(error.message);
  return supabase.storage.from(BUCKET).getPublicUrl(storagePath).data.publicUrl;
}

/**
 * Transform a Supabase Storage URL for thumbnail display.
 * Returns the original URL unchanged if not a Supabase Storage URL.
 */
export function thumbUrl(url: string, width = 600, quality = 75, resize: 'cover' | 'contain' | 'fill' = 'cover'): string {
  if (!url.includes('/storage/v1/object/public/')) return url;
  return url.replace('/storage/v1/object/', '/storage/v1/render/image/')
    + `?width=${width}&quality=${quality}&resize=${resize}`;
}
