// STUB — Webhook YouSign.
// Reçoit les événements YouSign (signature_request.done, signer.done, etc.).
// Actuellement retourne 200 immédiatement (pour ne pas faire échouer YouSign si configuré en avance).
//
// À implémenter une fois l'abonnement YouSign souscrit :
//   1. Valider la signature HMAC-SHA256 avec YOUSIGN_WEBHOOK_SECRET
//   2. Sur événement 'signature_request.done' :
//      a. Récupérer le PDF signé : YouSignProvider.downloadSignedDocument(requestId)
//      b. Uploader dans Supabase Storage : ContractStorageService.uploadSigned(documentId, pdfBlob)
//      c. Mettre documents_animaux.statut = 'signe' + signe_le = now
//      d. Mettre à jour contract_signers (statut = 'signe' pour chaque signataire)
//      e. log_contract_action 'signed'
//   3. Sur événement 'signer.done' (signature partielle) :
//      a. Mettre à jour contract_signers pour ce signataire
//      b. Si pas tous signés → statut 'partiellement_signe'
//      c. log_contract_action 'partially_signed'
//   4. Sur événement 'signature_request.refused' :
//      a. Mettre statut = 'refuse'
//      b. Stocker rejection_reason
//      c. log_contract_action 'refused'
//
// Configurer l'URL du webhook dans le dashboard YouSign :
//   https://petsmatchapp.com/api/yousign/webhook

import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  // TODO: valider HMAC
  // const webhookSecret = process.env.YOUSIGN_WEBHOOK_SECRET;
  // const signature = req.headers.get('x-yousign-signature-v3');
  // if (!validateHmac(await req.text(), signature, webhookSecret)) {
  //   return NextResponse.json({ error: 'Signature invalide' }, { status: 401 });
  // }

  // Lire l'événement sans traitement pour l'instant
  const _body = await req.json().catch(() => null);

  // Retourner 200 pour que YouSign ne réessaie pas l'envoi
  return NextResponse.json({ received: true, status: 'stub — non implémenté' });
}
