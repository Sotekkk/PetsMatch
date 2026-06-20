// ContractService — logique métier centralisée pour les contrats.
// Utilisé par les pages web et les API routes.
// La signature est déléguée à un SignatureProvider (canvas ou YouSign).

import { supabase } from '@/lib/supabase';
import type { SignatureProvider, Signer } from '@/lib/signature/SignatureProvider';
import { CanvasSignatureProvider } from '@/lib/signature/CanvasSignatureProvider';

export type ContractType = 'contrat_vente' | 'contrat_reservation' | 'certificat_cession' | 'certificat_engagement';

export type ContractStatut =
  | 'brouillon' | 'en_attente' | 'partiellement_signe'
  | 'signe' | 'refuse' | 'annule' | 'expire' | 'archive';

export interface CreateContractParams {
  animalId: string;
  uidEleveur: string;
  type: ContractType;
  titre: string;
  metadata: Record<string, unknown>;
  expiresInDays?: number;  // null = pas d'expiration
}

export class ContractService {
  private provider: SignatureProvider;

  constructor(provider?: SignatureProvider) {
    this.provider = provider ?? new CanvasSignatureProvider();
  }

  /** Crée un contrat en base et retourne son token. */
  async create(params: CreateContractParams): Promise<{ id: string; token: string }> {
    const expiresAt = params.expiresInDays
      ? new Date(Date.now() + params.expiresInDays * 86_400_000).toISOString()
      : null;

    const { data, error } = await supabase
      .from('documents_animaux')
      .insert({
        animal_id:   params.animalId,
        uid_eleveur: params.uidEleveur,
        type:        params.type,
        titre:       params.titre,
        statut:      'brouillon',
        metadata:    params.metadata,
        expires_at:  expiresAt,
      })
      .select('id, token')
      .single();

    if (error || !data) throw new Error(error?.message ?? 'Erreur création contrat');

    await supabase.rpc('log_contract_action', {
      p_document_id: data.id,
      p_action:      'created',
      p_actor_uid:   params.uidEleveur,
      p_actor_role:  'eleveur',
      p_details:     { type: params.type },
    });

    return { id: data.id, token: data.token };
  }

  /** Envoie le contrat à la signature (ajoute les signataires et active). */
  async sendForSignature(
    documentId: string,
    token: string,
    signers: Signer[],
    htmlContent: string,
    titre: string,
  ): Promise<void> {
    const requestId = await this.provider.createSignatureRequest({ id: documentId, titre, htmlContent });

    for (const signer of signers) {
      await this.provider.addSigner(requestId, signer);
    }

    await this.provider.sendSignatureRequest(requestId);

    // Stocker l'ID provider si différent du token (cas YouSign)
    if (requestId !== token) {
      await supabase
        .from('documents_animaux')
        .update({ yousign_id: requestId, statut: 'en_attente' })
        .eq('id', documentId);
    }
  }

  /** Annule un contrat. */
  async cancel(documentId: string, token: string, reason?: string): Promise<void> {
    await this.provider.cancelSignatureRequest(token);
    if (reason) {
      await supabase
        .from('documents_animaux')
        .update({ rejection_reason: reason })
        .eq('id', documentId);
    }
  }

  /** Récupère l'historique d'un contrat. */
  async getAuditLog(documentId: string) {
    const { data } = await supabase
      .from('contract_audit')
      .select('*')
      .eq('document_id', documentId)
      .order('created_at', { ascending: false });
    return data ?? [];
  }

  /** Vérifie si un contrat est expiré et met à jour son statut. */
  async checkExpiry(documentId: string): Promise<boolean> {
    const { data } = await supabase
      .from('documents_animaux')
      .select('expires_at, statut')
      .eq('id', documentId)
      .single();

    if (!data?.expires_at) return false;
    if (['signe', 'annule', 'expire', 'refuse'].includes(data.statut)) return false;

    if (new Date(data.expires_at) < new Date()) {
      await supabase.from('documents_animaux').update({ statut: 'expire' }).eq('id', documentId);
      await supabase.rpc('log_contract_action', {
        p_document_id: documentId,
        p_action:      'expired',
        p_actor_role:  'system',
      });
      return true;
    }
    return false;
  }
}
