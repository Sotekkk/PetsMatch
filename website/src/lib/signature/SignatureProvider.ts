// Interface abstraite du fournisseur de signature électronique.
// Permet de switcher entre canvas (SIGN00) et YouSign sans changer le code appelant.

export interface Signer {
  nom: string;
  email: string;
  role: 'vendeur' | 'acquereur' | 'co_eleveur' | 'temoin' | 'co_acquereur' | 'veterinaire';
  ordre?: number;
}

export interface ContractDoc {
  id: string;
  titre: string;
  htmlContent: string;  // HTML généré (pour conversion PDF ou envoi YouSign)
}

export type SignatureStatus =
  | 'en_attente'
  | 'notifie'
  | 'partiellement_signe'
  | 'signe'
  | 'refuse'
  | 'annule'
  | 'expire';

export interface SignatureProvider {
  /** Crée une demande de signature et retourne un identifiant opaque côté provider. */
  createSignatureRequest(doc: ContractDoc): Promise<string>;

  /** Ajoute un signataire à une demande existante. */
  addSigner(requestId: string, signer: Signer): Promise<void>;

  /** Envoie la demande (emails, notifications). */
  sendSignatureRequest(requestId: string): Promise<void>;

  /** Retourne le statut global de la demande. */
  getSignatureStatus(requestId: string): Promise<SignatureStatus>;

  /** Télécharge le PDF final signé (disponible uniquement quand statut = 'signe'). */
  downloadSignedDocument(requestId: string): Promise<Blob>;

  /** Annule la demande de signature. */
  cancelSignatureRequest(requestId: string): Promise<void>;
}
