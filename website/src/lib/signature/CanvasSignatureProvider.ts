// CanvasSignatureProvider — encapsule le flow de signature canvas (SIGN00).
// La "signature request" est le token UUID déjà présent dans documents_animaux.
// Pas d'envoi email natif : le partage se fait par lien manuel.

import type { SignatureProvider, ContractDoc, Signer, SignatureStatus } from './SignatureProvider';
import { supabase } from '@/lib/supabase';

export class CanvasSignatureProvider implements SignatureProvider {

  async createSignatureRequest(doc: ContractDoc): Promise<string> {
    // Le token est déjà généré par Supabase (gen_random_uuid()) à l'insertion.
    // On retourne le token existant comme requestId.
    const { data } = await supabase
      .from('documents_animaux')
      .select('token')
      .eq('id', doc.id)
      .single();
    if (!data?.token) throw new Error('Token introuvable pour le document ' + doc.id);
    return data.token as string;
  }

  async addSigner(requestId: string, signer: Signer): Promise<void> {
    // Insère un signataire dans contract_signers lié au document identifié par son token.
    const { data: doc } = await supabase
      .from('documents_animaux')
      .select('id')
      .eq('token', requestId)
      .single();
    if (!doc) throw new Error('Document introuvable pour le token ' + requestId);

    await supabase.from('contract_signers').upsert({
      document_id: doc.id,
      role:        signer.role,
      nom:         signer.nom,
      email:       signer.email ?? null,
      ordre:       signer.ordre ?? 1,
      statut:      'en_attente',
    }, { onConflict: 'document_id,role' });
  }

  async sendSignatureRequest(requestId: string): Promise<void> {
    // Passage en statut en_attente + log audit.
    const { data: doc } = await supabase
      .from('documents_animaux')
      .select('id')
      .eq('token', requestId)
      .single();
    if (!doc) return;

    await supabase.from('documents_animaux').update({ statut: 'en_attente' }).eq('id', doc.id);
    await supabase.rpc('log_contract_action', {
      p_document_id: doc.id,
      p_action:      'sent',
      p_actor_role:  'system',
      p_details:     { provider: 'canvas', link: `/signer-contrat/${requestId}` },
    });
  }

  async getSignatureStatus(requestId: string): Promise<SignatureStatus> {
    const { data } = await supabase
      .from('documents_animaux')
      .select('statut')
      .eq('token', requestId)
      .single();
    return (data?.statut as SignatureStatus) ?? 'en_attente';
  }

  async downloadSignedDocument(_requestId: string): Promise<Blob> {
    // Le canvas ne génère pas de PDF signé automatiquement.
    // PREP07 ajoutera un export PDF avec les signatures injectées.
    throw new Error('Export PDF signé non encore implémenté pour la signature canvas (voir PREP07).');
  }

  async cancelSignatureRequest(requestId: string): Promise<void> {
    const { data: doc } = await supabase
      .from('documents_animaux')
      .select('id')
      .eq('token', requestId)
      .single();
    if (!doc) return;

    const now = new Date().toISOString();
    await supabase.from('documents_animaux').update({
      statut: 'annule',
      cancelled_at: now,
    }).eq('id', doc.id);

    await supabase.rpc('log_contract_action', {
      p_document_id: doc.id,
      p_action:      'cancelled',
      p_actor_role:  'eleveur',
    });
  }
}
