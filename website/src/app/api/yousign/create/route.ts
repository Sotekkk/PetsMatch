// STUB — Endpoint création requête YouSign.
// Actuellement retourne 503 "non configuré".
// À implémenter une fois l'abonnement YouSign souscrit (voir PREP04 / YouSignProvider.ts).
//
// Flow attendu (à implémenter) :
//   1. Vérifier quota contrats_yousign_usage
//   2. Générer le PDF du contrat (ContractStorageService.uploadOriginal)
//   3. createYouSignProvider().createSignatureRequest(doc)
//   4. addSigner() pour vendeur + acquereur (+ co_eleveur si présent)
//   5. uploadDocument() → lier le PDF à la requête YouSign
//   6. sendSignatureRequest()
//   7. Stocker yousign_id dans documents_animaux
//   8. log_contract_action 'sent'

import { NextRequest, NextResponse } from 'next/server';

export async function POST(_req: NextRequest) {
  // TODO: implémenter quand YOUSIGN_API_KEY est configurée
  // const { documentId } = await req.json();
  // ...

  return NextResponse.json(
    { error: 'YouSign non configuré. Souscrivez à un abonnement YouSign et implémentez cet endpoint.' },
    { status: 503 },
  );
}
