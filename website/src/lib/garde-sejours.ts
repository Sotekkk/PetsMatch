// Regroupement des lignes `rdv` de type garde-journée en "séjours" (garde à
// domicile chez le prestataire, hébergement) — pour la tournée et le
// registre légal. Une ligne `rdv` = un jour ; un séjour = une suite de jours
// consécutifs (même client + même animal). Les promenades/visites à
// domicile client ne sont jamais des séjours (l'animal reste chez lui, non
// soumis au registre légal — cf. supabase/migration_garde_presence.sql).
// Même logique que lib/pages/pro/garde_sejour_helper.dart côté appli.

export interface GardeRdvRow {
  id: string;
  animal_id: string | null;
  client_uid: string | null;
  client_profile_id?: string | null;
  date_heure: string;
  motif?: string | null;
  statut?: string;
  arrivee_validee_le?: string | null;
  depart_valide_le?: string | null;
  _animal_nom?: string;
  _client_nom?: string;
}

export function estGardeJournee(rdv: Pick<GardeRdvRow, 'motif'>): boolean {
  const m = (rdv.motif ?? '').toLowerCase();
  return m.includes('garde') && (m.includes('journ') || m.includes('journée'));
}

export interface GardeSejour {
  animalId: string | null;
  clientUid: string | null;
  clientProfileId: string | null;
  jours: GardeRdvRow[]; // triés par date croissante
  dateEntree: Date;
  dateSortiePrevue: Date;
  arriveeValideeLe: Date | null;
  departValideLe: Date | null;
  statut: 'a_venir' | 'en_garde' | 'termine';
  animalNom: string;
  clientNom: string;
}

function buildSejour(jours: GardeRdvRow[]): GardeSejour {
  const premier = jours[0];
  const dernier = jours[jours.length - 1];
  const arriveeValideeLe = premier.arrivee_validee_le ? new Date(premier.arrivee_validee_le) : null;
  const departValideLe = dernier.depart_valide_le ? new Date(dernier.depart_valide_le) : null;
  return {
    animalId: premier.animal_id,
    clientUid: premier.client_uid,
    clientProfileId: premier.client_profile_id ?? null,
    jours,
    dateEntree: new Date(premier.date_heure),
    dateSortiePrevue: new Date(dernier.date_heure),
    arriveeValideeLe,
    departValideLe,
    // Rétrocompatibilité : une garde déjà marquée « terminée » (rdv.statut)
    // avant l'existence de la validation de présence n'a pas de
    // depart_valide_le rétroactif — sans ce repli elle resterait coincée
    // en « à venir » indéfiniment.
    statut: departValideLe || dernier.statut === 'termine' ? 'termine' : arriveeValideeLe ? 'en_garde' : 'a_venir',
    animalNom: premier._animal_nom ?? 'Animal',
    clientNom: premier._client_nom ?? 'Client',
  };
}

/** Regroupe une liste de `rdv` (déjà filtrée sur le statut voulu, avec
 * `_animal_nom`/`_client_nom` déjà résolus par l'appelant) en séjours
 * garde-journée. Les autres motifs (promenade/visite) sont ignorés — à
 * afficher séparément par l'appelant, en cartes individuelles. */
export function groupeGardeSejours(rdvRows: GardeRdvRow[]): GardeSejour[] {
  const joursGarde = rdvRows
    .filter(estGardeJournee)
    .slice()
    .sort((a, b) => new Date(a.date_heure).getTime() - new Date(b.date_heure).getTime());

  const sejours: GardeSejour[] = [];
  let courant: GardeRdvRow[] = [];
  let courantClient: string | null = null;
  let courantAnimal: string | null = null;
  let dernierJourDate: Date | null = null;

  const cloture = () => {
    if (courant.length) sejours.push(buildSejour(courant));
  };

  for (const r of joursGarde) {
    const date = new Date(r.date_heure);
    if (isNaN(date.getTime())) continue;
    const jourSeul = new Date(date.getFullYear(), date.getMonth(), date.getDate());

    const memeChaine =
      courant.length > 0 &&
      r.client_uid === courantClient &&
      r.animal_id === courantAnimal &&
      dernierJourDate !== null &&
      Math.round((jourSeul.getTime() - dernierJourDate.getTime()) / 86400000) <= 1;

    if (!memeChaine) {
      cloture();
      courant = [];
      courantClient = r.client_uid;
      courantAnimal = r.animal_id;
    }
    courant.push(r);
    dernierJourDate = jourSeul;
  }
  cloture();

  return sejours;
}
