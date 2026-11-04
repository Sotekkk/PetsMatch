// Historique des RDV d'un pro : plus récents en haut, filtre par client / animal,
// par jour et par hospitalisation (RDV « Intervention »).
// Miroir appli : lib/utils/historique_rdv.dart.

export interface RdvHistorique {
  date_heure: string; motif?: string | null; intervention_type?: string | null;
  admis_le?: string | null; sortie_le?: string | null;
  clientName?: string; client_nom_manuel?: string | null; animalNom?: string; animal_nom_manuel?: string | null;
}

const norm = (v: unknown) => String(v ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/œ/gi, 'oe').replace(/æ/gi, 'ae').toLowerCase().trim();
/** AAAA-MM-JJ, heure locale. */
const jourLocal = (iso: string) => new Date(iso).toLocaleDateString('sv-SE');

/** Plus récents en haut. */
export const historiqueTrie = <T extends RdvHistorique>(rdvs: T[]): T[] =>
  [...rdvs].sort((a, b) => new Date(b.date_heure).getTime() - new Date(a.date_heure).getTime());

/** Tous les mots de [recherche] dans le client, l'animal ou le motif ; [jour] (AAAA-MM-JJ) : RDV
 *  ce jour-là, ou hospitalisation en cours ce jour-là (du dépôt à la récupération). */
export function historiqueFiltre<T extends RdvHistorique>(rdvs: T[], f: { recherche?: string; jour?: string; hospitalisations?: boolean }): T[] {
  const mots = norm(f.recherche).split(/\s+/).filter(Boolean);
  return rdvs.filter(r => {
    if (f.hospitalisations && !r.intervention_type) return false;
    if (mots.length) {
      const texte = norm([r.clientName, r.client_nom_manuel, r.animalNom, r.animal_nom_manuel, r.motif].join(' '));
      if (!mots.every(m => texte.includes(m))) return false;
    }
    if (f.jour) {
      const d0 = jourLocal(r.date_heure);
      const d1 = r.intervention_type && r.sortie_le ? jourLocal(r.sortie_le) : d0;
      if (f.jour < d0 || f.jour > d1) return false;
    }
    return true;
  });
}

const jourHeure = (iso: string) => {
  const d = new Date(iso);
  return `le ${d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })} à ${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }).replace(':', 'h')}`;
};

/** « Déposé le 04/11 à 10h15 · récupéré le 05/11 à 15h28 » (null si pas d'intervention commencée). */
export function ligneHospitalisation(r: RdvHistorique): string | null {
  if (!r.intervention_type || (!r.admis_le && !r.sortie_le)) return null;
  return [r.admis_le ? `Déposé ${jourHeure(r.admis_le)}` : '', r.sortie_le ? `récupéré ${jourHeure(r.sortie_le)}` : ''].filter(Boolean).join(' · ');
}
