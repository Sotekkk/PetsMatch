// Retards en cascade d'une journée, par praticien : un RDV terminé après
// l'heure prévue (rdv.termine_at) ou encore en cours décale les suivants.
// Ostéopathe / santé : le trajet entre deux RDV (domicile ↔ domicile ou
// cabinet) s'ajoute — vol d'oiseau à 30 km/h comme la réservation, sans la
// marge de planification ; sans coordonnées des deux côtés, aucun trajet.
// Même calcul que la Cloud Function sendRetardsAutomatiques
// (functions/retards_auto.js) et l'appli (lib/utils/retards_rdv.dart).

const OUBLI_MIN = 120; // RDV non clôturé 2 h après sa fin : clôture oubliée
export const VITESSE_TRAJET_KMH = 30;

export interface RdvRetard {
  id: string; date_heure: string; duree_minutes?: number | null; statut: string;
  termine_at?: string | null; instructeur_profile_id?: string | null;
  lieu?: string | null; lieu_lat?: number | null; lieu_lng?: number | null; salle_id?: string | null;
}
export type Position = { lat: number; lng: number };

function distanceKm(a: Position, b: Position) {
  const R = 6371, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** Adresse d'intervention géocodée, sinon le cabinet (RDV sans adresse), sinon inconnue. */
export function positionRdv(r: RdvRetard, cabinet: Position | null): Position | null {
  if (r.lieu_lat != null && r.lieu_lng != null) return { lat: r.lieu_lat, lng: r.lieu_lng };
  const exterieur = !!r.lieu?.trim() && !r.salle_id;
  return exterieur ? null : cabinet;
}

/** Minutes de trajet estimées entre deux RDV (0 si une position manque). */
export function trajetEntreRdv(a: RdvRetard, b: RdvRetard, cabinet: Position | null): number {
  const pa = positionRdv(a, cabinet), pb = positionRdv(b, cabinet);
  if (!pa || !pb) return 0;
  return Math.ceil(distanceKm(pa, pb) / VITESSE_TRAJET_KMH * 60);
}

/** rdv id → retard estimé (minutes) des RDV à venir aujourd'hui. */
export function retardsEnCascade(rdvs: RdvRetard[], maintenant = new Date(),
  opts: { avecTrajets?: boolean; cabinet?: Position | null } = {}): Record<string, number> {
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
    let precedent: RdvRetard | null = null;
    for (const r of liste) {
      const debut = new Date(r.date_heure).getTime();
      const duree = (r.duree_minutes ?? 30) * 60000;
      const finPrevue = debut + duree;
      // Heure à laquelle on peut être sur place : fin du précédent + trajet.
      const arrivee = curseur == null ? null
        : curseur + (opts.avecTrajets && precedent ? trajetEntreRdv(precedent, r, opts.cabinet ?? null) * 60000 : 0);
      precedent = r;
      if (r.statut === 'termine') {
        curseur = r.termine_at ? new Date(r.termine_at).getTime() : finPrevue;
        continue;
      }
      if (debut <= now) {
        const debutReel = Math.max(debut, arrivee ?? debut);
        let fin = Math.max(debutReel + duree, now);
        if (now - finPrevue > OUBLI_MIN * 60000) fin = finPrevue;
        curseur = fin;
        continue;
      }
      const debutEstime = Math.max(debut, arrivee ?? debut);
      const retard = Math.round((debutEstime - debut) / 60000);
      if (retard > 0) out[r.id] = retard;
      curseur = debutEstime + duree;
    }
  }
  return out;
}
