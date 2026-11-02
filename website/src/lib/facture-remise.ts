// Remises d'une facture (lot 4 de la refonte) : une remise en % par ligne,
// motif affiché sur la facture (« Remise globale », « Tarif dégressif —
// 2e animal »…). Une ligne n'a qu'une remise : appliquer une remise par
// animal, globale ou dégressive remplace celle de la ligne (pas de cumul).
// Miroir appli : lib/utils/facture_remise.dart.

const arrondi = (v: number) => Math.round((v + Number.EPSILON) * 100) / 100;

/** Montant HT de la ligne, remise déduite (arrondi au centime). */
export function htLigneRemisee(quantite: number, prixUnitaireHT: number, remisePct?: number | null): number {
  const brut = arrondi(quantite * prixUnitaireHT);
  const pct = Math.min(100, Math.max(0, Number(remisePct ?? 0)));
  return pct > 0 ? arrondi(brut * (1 - pct / 100)) : brut;
}

/** Montant de la remise (HT, positif). */
export function montantRemise(quantite: number, prixUnitaireHT: number, remisePct?: number | null): number {
  return arrondi(arrondi(quantite * prixUnitaireHT) - htLigneRemisee(quantite, prixUnitaireHT, remisePct));
}

const pctTxt = (p: number) => `${String(p).replace('.', ',')} %`;

/** « Remise 10 % (Tarif dégressif — 2e animal) : -6,00 EUR HT » */
export function libelleRemise(remisePct: number, motif: string | null | undefined, montant: number, devise = 'EUR'): string {
  return `${(motif ?? '').trim() || 'Remise'} ${pctTxt(remisePct)} : -${montant.toFixed(2).replace('.', ',')} ${devise} HT`;
}

export interface LigneRemisable {
  animalId?: string | null;
  animalNom?: string | null;
  commune?: boolean;
  remise?: number | null;
  remiseMotif?: string | null;
}

/** Animaux dans l'ordre d'apparition des lignes (hors prestations communes). */
export function animauxDesLignes(lignes: LigneRemisable[]): string[] {
  const ids: string[] = [];
  for (const l of lignes) {
    const cle = l.commune ? '' : (l.animalId || l.animalNom || '');
    if (cle && !ids.includes(cle)) ids.push(cle);
  }
  return ids;
}

/** Lignes qui ont déjà une remise différente de celle qu'on applique. */
export function remisesRemplacees<T extends LigneRemisable>(lignes: T[], cible: (l: T, i: number) => number | null): number {
  return lignes.filter((l, i) => { const p = cible(l, i); return p != null && Number(l.remise ?? 0) > 0 && Number(l.remise) !== p; }).length;
}

/**
 * Applique une remise : `cible` renvoie le % pour une ligne (null : ligne
 * inchangée) ; `motif` son libellé. Remplace la remise existante de la ligne.
 */
export function appliquerRemise<T extends LigneRemisable>(lignes: T[], cible: (l: T, i: number) => number | null,
  motif: (l: T, i: number) => string): T[] {
  return lignes.map((l, i) => {
    const p = cible(l, i);
    if (p == null) return l;
    return p > 0 ? { ...l, remise: p, remiseMotif: motif(l, i) } : { ...l, remise: null, remiseMotif: null };
  });
}

/** Tarif dégressif : % du 2e animal, puis du 3e et des suivants (1er plein tarif). */
export function cibleDegressif<T extends LigneRemisable>(lignes: T[], pct2: number, pct3: number) {
  const ordre = animauxDesLignes(lignes);
  const rang = (l: T) => l.commune ? -1 : ordre.indexOf(l.animalId || l.animalNom || '');
  return {
    cible: (l: T) => { const r = rang(l); return r < 1 ? null : r === 1 ? pct2 : pct3; },
    motif: (l: T) => `Tarif dégressif — ${rang(l) + 1}e animal`,
  };
}
