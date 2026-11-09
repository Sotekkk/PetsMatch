// Chiffre d'affaires d'un pro, calculé depuis ses factures (table factures,
// déjà filtrée sur son profil par la page Facturation). Miroir appli :
// lib/utils/chiffre_affaires.dart.
//   Facturé : factures non annulées, par date de facture (avoirs déduits ;
//             l'acompte compte, la facture de solde le déduit déjà).
//   Encaissé : factures payées, par date de paiement (sinon date de facture).
//   À encaisser : factures émises non payées (hors avoirs).

export interface FactureCA {
  statut?: string | null; type_facture?: string | null;
  date_facture?: string | null; date_paiement?: string | null;
  total_ht?: number | null; total_ttc?: number | null; montant_regle?: number | null;
}

export interface MoisCA { ht: number; ttc: number; encaisse: number; nb: number }
export interface ResumeCA { mois: MoisCA[]; ht: number; ttc: number; encaisse: number; nb: number; aEncaisser: number; ttcAnneePrec: number }

const signe = (f: FactureCA) => (f.type_facture === 'avoir' && Number(f.total_ttc ?? 0) > 0 ? -1 : 1);
const annee = (d?: string | null) => (d ? Number(d.slice(0, 4)) : NaN);
const mois = (d?: string | null) => (d ? Number(d.slice(5, 7)) - 1 : -1);

export function resumeCA(factures: FactureCA[], an: number): ResumeCA {
  const m: MoisCA[] = Array.from({ length: 12 }, () => ({ ht: 0, ttc: 0, encaisse: 0, nb: 0 }));
  let aEncaisser = 0, ttcAnneePrec = 0;
  for (const f of factures) {
    if (f.statut === 'annulee' || f.statut === 'brouillon') continue;
    const s = signe(f);
    const ttc = s * Number(f.total_ttc ?? 0);
    const ht = s * Number(f.total_ht ?? f.total_ttc ?? 0);
    if (annee(f.date_facture) === an && mois(f.date_facture) >= 0) {
      const x = m[mois(f.date_facture)];
      x.ht += ht; x.ttc += ttc; x.nb += 1;
    }
    if (annee(f.date_facture) === an - 1) ttcAnneePrec += ttc;
    if (f.statut === 'payee') {
      const d = f.date_paiement || f.date_facture;
      if (annee(d) === an && mois(d) >= 0) m[mois(d)].encaisse += s * Number(f.montant_regle ?? f.total_ttc ?? 0);
    } else if (f.type_facture !== 'avoir') {
      aEncaisser += Number(f.total_ttc ?? 0);
    }
  }
  const somme = (k: keyof MoisCA) => m.reduce((t, x) => t + x[k], 0);
  return { mois: m, ht: somme('ht'), ttc: somme('ttc'), encaisse: somme('encaisse'), nb: somme('nb'), aEncaisser, ttcAnneePrec };
}

export const MOIS_COURTS = ['Janv.', 'Févr.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.'];

export const euros = (n: number) => n.toLocaleString('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });
