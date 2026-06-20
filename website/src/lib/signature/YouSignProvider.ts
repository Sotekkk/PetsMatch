// YouSignProvider — stub vide prêt à implémenter.
// Toutes les méthodes lèvent une erreur jusqu'à l'activation de l'abonnement YouSign.
//
// Pour activer :
//   1. Définir YOUSIGN_API_KEY dans .env.local (sandbox: ys_... / prod: yp_...)
//   2. Implémenter chaque méthode selon https://developers.yousign.com/reference/
//   3. Configurer le webhook dans le dashboard YouSign (voir PREP06)

import type { SignatureProvider, ContractDoc, Signer, SignatureStatus } from './SignatureProvider';

const YOUSIGN_BASE_URL = 'https://api-sandbox.yousign.app/v3';  // remplacer par https://api.yousign.app/v3 en prod

export class YouSignProvider implements SignatureProvider {
  private readonly apiKey: string;
  private readonly baseUrl: string;

  constructor(apiKey: string, sandbox = true) {
    this.apiKey = apiKey;
    this.baseUrl = sandbox ? YOUSIGN_BASE_URL : 'https://api.yousign.app/v3';
  }

  private get headers() {
    return {
      'Authorization': `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json',
    };
  }

  async createSignatureRequest(_doc: ContractDoc): Promise<string> {
    // TODO:
    // POST /v3/signature_requests { name: doc.titre, delivery_mode: 'email' }
    // Retourner l'id de la signature_request
    throw new Error('[YouSign] Non configuré — souscrivez à un abonnement YouSign et implémentez cette méthode.');
  }

  async addSigner(_requestId: string, _signer: Signer): Promise<void> {
    // TODO:
    // POST /v3/signature_requests/{requestId}/signers
    //   { info: { first_name, last_name, email }, signature_level: 'electronic_signature' }
    throw new Error('[YouSign] Non configuré.');
  }

  async sendSignatureRequest(_requestId: string): Promise<void> {
    // TODO:
    // POST /v3/signature_requests/{requestId}/activate
    throw new Error('[YouSign] Non configuré.');
  }

  async getSignatureStatus(_requestId: string): Promise<SignatureStatus> {
    // TODO:
    // GET /v3/signature_requests/{requestId}
    // Mapper le statut YouSign → SignatureStatus
    //   'draft'     → 'en_attente'
    //   'ongoing'   → 'partiellement_signe' ou 'en_attente'
    //   'done'      → 'signe'
    //   'refused'   → 'refuse'
    //   'cancelled' → 'annule'
    //   'expired'   → 'expire'
    throw new Error('[YouSign] Non configuré.');
  }

  async downloadSignedDocument(_requestId: string): Promise<Blob> {
    // TODO:
    // GET /v3/signature_requests/{requestId}/documents/download
    // Retourner le Blob PDF
    throw new Error('[YouSign] Non configuré.');
  }

  async cancelSignatureRequest(_requestId: string): Promise<void> {
    // TODO:
    // POST /v3/signature_requests/{requestId}/cancel
    throw new Error('[YouSign] Non configuré.');
  }

  // ── Méthode utilitaire : upload du PDF source vers YouSign ────────────────
  // À appeler entre createSignatureRequest et addSigner
  async uploadDocument(_requestId: string, _pdfBlob: Blob, _filename: string): Promise<string> {
    // TODO:
    // POST /v3/signature_requests/{requestId}/documents (multipart/form-data)
    // Retourner l'id du document côté YouSign
    throw new Error('[YouSign] Non configuré.');
  }
}

// Factory : retourne le bon provider selon la config
export function createYouSignProvider(): YouSignProvider {
  const apiKey = process.env.YOUSIGN_API_KEY;
  if (!apiKey) throw new Error('YOUSIGN_API_KEY manquante dans les variables d\'environnement.');
  const isSandbox = apiKey.startsWith('ys_');
  return new YouSignProvider(apiKey, isSandbox);
}
