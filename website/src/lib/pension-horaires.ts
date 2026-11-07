// Pension — horaires d'arrivée / de départ et créneaux de 15 min.
// Réglages : user_profiles.pension_horaires (migration_pension_horaires.sql).
// Une arrivée (ou un départ) occupe des créneaux de 15 min selon sa durée :
// premier séjour / client habitué, + minutes par animal supplémentaire.
// Arrivées et départs partagent le maximum de clients par créneau.
// Utilisé par la route /api/pension/sejour (serveur) et les écrans (site).
// Miroir appli : lib/utils/pension_horaires.dart.

export interface PlageHoraire { debut: string; fin: string }
export interface HorairesPension {
  arrivees: PlageHoraire[]; departs: PlageHoraire[];
  duree_arrivee_nouveau: number; duree_arrivee_habitue: number; duree_depart: number;
  minutes_par_animal: number; max_par_creneau: number;
}
/** Un passage déjà prévu (arrivée ou départ) : heure, durée, client. */
export interface Passage { heure: string; duree: number; client: string }

export const HORAIRES_DEFAUT: HorairesPension = {
  arrivees: [{ debut: '08:00', fin: '10:00' }, { debut: '17:00', fin: '19:00' }],
  departs: [{ debut: '08:00', fin: '10:00' }, { debut: '17:00', fin: '19:00' }],
  duree_arrivee_nouveau: 30, duree_arrivee_habitue: 15, duree_depart: 15, minutes_par_animal: 5, max_par_creneau: 3,
};

const HM = /^([01]\d|2[0-3]):([0-5]\d)$/;
export const enMinutes = (h: string) => { const m = HM.exec(h); return m ? Number(m[1]) * 60 + Number(m[2]) : NaN; };
export const enHeure = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
export const heureValide = (h?: string | null) => !!h && HM.test(h);
const arrondi15 = (m: number) => Math.max(15, Math.ceil(m / 15) * 15);

/** Réglages lus en base, nettoyés ; null = pas d'horaires (pas de choix d'heure). */
export function lireHoraires(brut: unknown): HorairesPension | null {
  if (!brut || typeof brut !== 'object') return null;
  const b = brut as Partial<HorairesPension>;
  const plages = (l: unknown) => (Array.isArray(l) ? l : [])
    .filter((p): p is PlageHoraire => !!p && heureValide((p as PlageHoraire).debut) && heureValide((p as PlageHoraire).fin)
      && enMinutes((p as PlageHoraire).debut) < enMinutes((p as PlageHoraire).fin));
  const n = (v: unknown, d: number, min = 0, max = 600) => { const x = Number(v); return Number.isFinite(x) ? Math.min(max, Math.max(min, Math.round(x))) : d; };
  const h: HorairesPension = {
    arrivees: plages(b.arrivees), departs: plages(b.departs),
    duree_arrivee_nouveau: n(b.duree_arrivee_nouveau, 30, 5), duree_arrivee_habitue: n(b.duree_arrivee_habitue, 15, 5),
    duree_depart: n(b.duree_depart, 15, 5), minutes_par_animal: n(b.minutes_par_animal, 5, 0, 120), max_par_creneau: n(b.max_par_creneau, 3, 1, 50),
  };
  return h.arrivees.length || h.departs.length ? h : null;
}

/** Durée d'une arrivée / d'un départ, arrondie au quart d'heure. */
export function dureePassage(h: HorairesPension, type: 'arrivee' | 'depart', nbAnimaux: number, nouveau: boolean) {
  const base = type === 'depart' ? h.duree_depart : nouveau ? h.duree_arrivee_nouveau : h.duree_arrivee_habitue;
  return arrondi15(base + Math.max(0, nbAnimaux - 1) * h.minutes_par_animal);
}

/** Clients présents sur chaque créneau de 15 min (un client compté une fois). */
function occupation(passages: Passage[]) {
  const parCreneau = new Map<number, Set<string>>();
  for (const p of passages) {
    const debut = enMinutes(p.heure);
    if (!Number.isFinite(debut)) continue;
    for (let t = Math.floor(debut / 15) * 15; t < debut + Math.max(15, p.duree); t += 15) {
      if (!parCreneau.has(t)) parCreneau.set(t, new Set());
      parCreneau.get(t)!.add(p.client);
    }
  }
  return parCreneau;
}

/** Heures de début possibles ce jour-là : dans une plage, la durée tient
 *  avant la fin de plage, et chaque créneau couvert garde une place. */
export function creneauxLibres(h: HorairesPension, type: 'arrivee' | 'depart', duree: number, passages: Passage[]) {
  const occ = occupation(passages);
  const out: string[] = [];
  for (const p of type === 'arrivee' ? h.arrivees : h.departs) {
    for (let t = enMinutes(p.debut); t + duree <= enMinutes(p.fin); t += 15) {
      let ok = true;
      for (let c = t; c < t + duree; c += 15) if ((occ.get(c)?.size ?? 0) >= h.max_par_creneau) { ok = false; break; }
      if (ok) out.push(enHeure(t));
    }
  }
  return [...new Set(out)].sort();
}
