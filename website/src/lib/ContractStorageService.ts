// ContractStorageService — upload/download des PDFs dans Supabase Storage.
// Bucket : 'contrats' (déjà existant depuis migration_contrats_storage.sql)

import { supabase } from '@/lib/supabase';

const BUCKET = 'contrats';

export class ContractStorageService {

  /** Upload le PDF original (avant signatures) et retourne l'URL publique. */
  async uploadOriginal(documentId: string, pdfBlob: Blob): Promise<string> {
    const path = `${documentId}/original.pdf`;
    const { error } = await supabase.storage
      .from(BUCKET)
      .upload(path, pdfBlob, { contentType: 'application/pdf', upsert: true });
    if (error) throw new Error(`Upload PDF original : ${error.message}`);

    const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
    await supabase
      .from('documents_animaux')
      .update({ pdf_original_url: data.publicUrl })
      .eq('id', documentId);

    return data.publicUrl;
  }

  /** Upload le PDF signé final et retourne l'URL publique. */
  async uploadSigned(documentId: string, pdfBlob: Blob): Promise<string> {
    const path = `${documentId}/signe.pdf`;
    const { error } = await supabase.storage
      .from(BUCKET)
      .upload(path, pdfBlob, { contentType: 'application/pdf', upsert: true });
    if (error) throw new Error(`Upload PDF signé : ${error.message}`);

    const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
    await supabase
      .from('documents_animaux')
      .update({ pdf_signe_url: data.publicUrl })
      .eq('id', documentId);

    return data.publicUrl;
  }

  /** Télécharge le PDF signé depuis Supabase Storage. */
  async downloadSigned(documentId: string): Promise<Blob> {
    const { data, error } = await supabase.storage
      .from(BUCKET)
      .download(`${documentId}/signe.pdf`);
    if (error || !data) throw new Error(`Téléchargement PDF signé : ${error?.message ?? 'introuvable'}`);
    return data;
  }

  /** Retourne l'URL publique du PDF signé (null si pas encore disponible). */
  async getSignedUrl(documentId: string): Promise<string | null> {
    const { data } = await supabase
      .from('documents_animaux')
      .select('pdf_signe_url')
      .eq('id', documentId)
      .single();
    return (data?.pdf_signe_url as string | null) ?? null;
  }
}
