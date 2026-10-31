// Page ouverte dans un panneau (iframe) par-dessus une autre page — ex. la
// fiche animal ou le devis ouverts depuis le dossier de la séance, sans
// quitter Gérer mes RDV (components/PanneauPage.tsx). En panneau, la page
// s'affiche sans en-tête ni pied de page (SiteShell) et, au lieu de
// naviguer vers son « retour », demande au parent de refermer le panneau.

export const MSG_PANNEAU_FERMER = 'pm-panneau-fermer';
export const MSG_PANNEAU_PRET = 'pm-panneau-pret';

export function estDansPanneau(): boolean {
  try { return typeof window !== 'undefined' && window.self !== window.top; } catch { return true; }
}

export function signalerPanneau(type: string) {
  try { window.parent.postMessage({ type }, window.location.origin); } catch { /* parent inaccessible */ }
}

/** Retour après une action : referme le panneau, sinon navigue vers `url`. */
export function allerOuFermer(router: { push: (url: string) => void }, url: string) {
  if (estDansPanneau()) { signalerPanneau(MSG_PANNEAU_FERMER); return; }
  router.push(url);
}
