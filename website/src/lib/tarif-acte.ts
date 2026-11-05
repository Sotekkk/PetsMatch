// Prix d'un acte depuis « Autres actes » du vétérinaire (tarifs_veto_extra) :
// libellé rapproché sans accents ni casse (« Détartrage » ↔ « Détartrage - de
// 10 kg »), tranche de poids choisie d'après le poids de l'animal (« - de
// 10 kg », « + de 10 kg », « < 10 kg », « moins de / plus de 10 kg »).
// Sert à la facture d'un RDV (intervention : détartrage…) et d'un motif /
// acte de consultation. Miroir appli : lib/utils/tarif_acte.dart.

export interface TarifExtra { label: string; prix: number }

const norm = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
/** Libellé sans la condition de poids. */
const sansPoids = (s: string) => norm(s).replace(/\(?\s*(?:[-+<>≤≥]|moins de|plus de)\s*(?:de\s*)?\d+(?:[.,]\d+)?\s*kg\s*\)?/g, '').replace(/[\s\-–—:]+$/, '').trim();

/** Condition de poids d'un libellé : vrai si l'animal (kg) la remplit, null si aucune condition. */
function conditionPoids(label: string, kg: number | null): boolean | null {
  const m = norm(label).match(/([-+<>≤≥]|moins de|plus de)\s*(?:de\s*)?(\d+(?:[.,]\d+)?)\s*kg/);
  if (!m) return null;
  if (kg == null) return false;
  const n = parseFloat(m[2].replace(',', '.'));
  return ['-', '<', '≤', 'moins de'].includes(m[1]) ? kg < n : kg >= n;
}

/** Prix TTC de l'acte (libellé du motif / de l'acte), ou null si aucun acte ne correspond.
 *  Strict (consultation) : libellé identique à celui de l'acte, tranche de poids mise à part
 *  (« Détartrage » ↔ « Détartrage - de 10 kg ») — rien ne change pour une consultation classique.
 *  [souple] (intervention) : l'un contient l'autre (« Détartrage » ↔ « Détartrage et polissage »). */
export function prixActeExtra(libelle: string, extras: TarifExtra[], kg: number | null, souple = false): number | null {
  const cible = sansPoids(libelle);
  if (!cible) return null;
  const candidats = extras.filter(e => {
    const base = sansPoids(e.label);
    return base && (cible === base || (souple && (cible.includes(base) || base.includes(cible))));
  });
  if (!candidats.length) return null;
  const avecPoids = candidats.filter(e => conditionPoids(e.label, kg) === true);
  const choisi = avecPoids[0] ?? candidats.find(e => conditionPoids(e.label, kg) === null) ?? (kg == null ? candidats[0] : null);
  return choisi && choisi.prix > 0 ? choisi.prix : null;
}

/** Ostéo / kiné : prix TTC d'une séance d'après le motif du RDV. D'abord « Autres actes »
 *  (tarifs_sante_extra), puis la grille : bilan / consultation → « Consultation », séance / suivi
 *  → « Séance de suivi », autre → « Autre prestation ». Motif sans tarif : grille selon le type de
 *  séance. Prix absent ou à 0 : null (à compléter sur la facture). */
export function prixSeanceSante(motif: string | null | undefined, tarifs: Record<string, unknown>, extras: TarifExtra[], kg: number | null, bilan = false): number | null {
  const grille = (k: string) => { const v = parseFloat(String(tarifs[k] ?? '').replace(',', '.')); return v > 0 ? v : null; };
  const m = norm(motif ?? '');
  const parMotif = !m ? null : prixActeExtra(m, extras, kg, true)
    ?? (/bilan|consultation/.test(m) ? grille('consultation') : /seance|suivi/.test(m) ? grille('seance') : m === 'autre' ? grille('autre') : null);
  return parMotif ?? grille(bilan ? 'consultation' : 'seance');
}

/** Ostéo / kiné : supplément déplacement de la grille, sinon de « Autres actes ». */
export function prixDeplacementSante(tarifs: Record<string, unknown>, extras: TarifExtra[]): number | null {
  const v = parseFloat(String(tarifs.deplacement ?? '').replace(',', '.'));
  return v > 0 ? v : prixActeExtra('deplacement', extras, null, true);
}

/** Autres actes lus depuis le profil (tableau JSON tarifs_veto_extra, tarifs_sante_extra). */
export const extrasDepuis = (v: unknown): TarifExtra[] => Array.isArray(v)
  ? (v as { label?: unknown; prix?: unknown }[]).map(e => ({ label: String(e.label ?? ''), prix: Number(e.prix ?? 0) })).filter(e => e.label.trim())
  : [];
