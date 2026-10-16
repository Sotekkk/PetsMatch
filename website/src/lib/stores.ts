// Liens vers l'application dans les stores (pied de page, page de
// récupération d'une fiche, invitations). Surchargeables par variables
// d'environnement.
export const STORE_ANDROID = process.env.NEXT_PUBLIC_STORE_ANDROID || 'https://play.google.com/store/apps/details?id=com.application.petsmatchapp';
export const STORE_IOS = process.env.NEXT_PUBLIC_STORE_IOS || 'https://apps.apple.com/fr/developer/petsmatch/id1762868142';
