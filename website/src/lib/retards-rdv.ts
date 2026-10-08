// Retards en cascade d'une journée, par praticien : un RDV terminé après
// l'heure prévue (rdv.termine_at) ou encore en cours décale les suivants.
// Même calcul que la Cloud Function sendRetardsAutomatiques
// (functions/retards_auto.js) et l'appli (lib/utils/retards_rdv.dart).

const OUBLI_MIN = 120; // RDV non clôturé 2 h après sa fin : clôture oubliée

export interface RdvRetard {
  id: string; date_heure: string; duree_minutes?: number | null; statut: string;
  termine_at?: string | null; instructeur_profile_id?: string | null;
}

/** rdv id → retard estimé (minutes) des RDV à venir aujourd'hui. */
export function retardsEnCascade(rdvs: RdvRetard[], maintenant = new Date()): Record<string, number> {
  const now = maintenant.getTime();
  const debutJour = new Date(maintenant.getFullYear(), maintenant.getMonth(), maintenant.getDate()).getTime();
  const finJour = debutJour + 86400000;
  const groupes: Record<string, RdvRetard[]> = {};
  for (const r of rdvs) {
    if (r.statut !== 'confirme' && r.statut !== 'termine') continue;
    const t = new Date(r.date_heure).getTime();
    if (t < debutJour || t >= finJour) continue;
    (groupes[r.instructeur_profile_id ?? ''] ??= []).push(r);
  }
  const out: Record<string, number> = {};
  for (const liste of Object.values(groupes)) {
    liste.sort((a, b) => a.date_heure.localeCompare(b.date_heure));
    let curseur: number | null = null;
    for (const r of liste) {
      const debut = new Date(r.date_heure).getTime();
      const duree = (r.duree_minutes ?? 30) * 60000;
      const finPrevue = debut + duree;
      if (r.statut === 'termine') {
        curseur = r.termine_at ? new Date(r.termine_at).getTime() : finPrevue;
        continue;
      }
      if (debut <= now) {
        const debutReel = Math.max(debut, curseur ?? debut);
        let fin = Math.max(debutReel + duree, now);
        if (now - finPrevue > OUBLI_MIN * 60000) fin = finPrevue;
        curseur = fin;
        continue;
      }
      const debutEstime = Math.max(debut, curseur ?? debut);
      const retard = Math.round((debutEstime - debut) / 60000);
      if (retard > 0) out[r.id] = retard;
      curseur = debutEstime + duree;
    }
  }
  return out;
}
