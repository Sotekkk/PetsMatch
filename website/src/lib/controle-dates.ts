// Cohérence des dates d'un acte du carnet de santé (vaccin, traitement,
// vermifuge, antiparasitaire, visite…) et format des heures de rappel.
// Miroir appli : lib/utils/controle_dates.dart.
// Les champs <input type="date"> laissent taper n'importe quelle année
// (« 12/03/0001 ») : on contrôle donc avant d'enregistrer.

export const PREMIERE_DATE_ACTE = '1990-01-01';

const ISO = /^\d{4}-\d{2}-\d{2}$/;
const HEURE = /^([01]\d|2[0-3]):[0-5]\d$/;

const ajouterAns = (iso: string, ans: number) => `${Number(iso.slice(0, 4)) + ans}${iso.slice(4, 10)}`;
const aujourdhui = () => new Date().toISOString().slice(0, 10);

/** Borne haute proposée aux champs date d'un acte : dans deux ans. */
export const derniereDateActe = () => ajouterAns(aujourdhui(), 2);

/** Date au format AAAA-MM-JJ, réelle (pas de 31/02) et dans les bornes. */
export function dateValide(iso: string): boolean {
  if (!ISO.test(iso)) return false;
  const d = new Date(`${iso}T00:00:00Z`); // UTC : pas de décalage horaire
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso;
}

/** Heures de rappel « 08:00, 20:00 » → liste, ou erreur de format. */
export function lireHeures(texte: string): { heures: string[]; erreur?: string } {
  const heures = texte.split(',').map(h => h.trim()).filter(Boolean);
  const fausse = heures.find(h => !HEURE.test(h));
  return fausse ? { heures, erreur: `Heure « ${fausse} » invalide : format HH:MM (ex. 08:00).` } : { heures };
}

/** Erreurs de saisie d'un acte de santé (vide = enregistrable).
 *  Clés reconnues : date, date_rappel, date_validite_debut, date_fin, rappel_heures. */
export function erreursDatesSante(form: Record<string, string>, champsDate: { key: string; label: string; required?: boolean }[]): string[] {
  const erreurs: string[] = [];
  const fr = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;
  for (const c of champsDate) {
    const v = (form[c.key] ?? '').trim();
    // La date de l'acte est toujours obligatoire (un soin sans date n'a pas de sens).
    if (!v) { if (c.required || c.key === 'date') erreurs.push(`${c.label} : obligatoire.`); continue; }
    if (!dateValide(v)) { erreurs.push(`${c.label} : date invalide (JJ/MM/AAAA).`); continue; }
    if (v < PREMIERE_DATE_ACTE) erreurs.push(`${c.label} : pas avant le ${fr(PREMIERE_DATE_ACTE)}.`);
  }
  const date = (form.date ?? '').trim();
  if (date && dateValide(date)) {
    if (date > derniereDateActe()) erreurs.push('Date : pas plus de deux ans dans le futur.');
    // Chirurgie / hospitalisation : prévue → à venir, réalisée → passée.
    if (form.statut === 'prevu' && date < aujourdhui()) erreurs.push('Intervention prévue : la date ne peut pas être passée (choisissez « Réalisée » si elle a eu lieu).');
    if (form.statut === 'realise' && date > aujourdhui()) erreurs.push('Intervention réalisée : la date ne peut pas être dans le futur (choisissez « Prévue »).');
    const limite = ajouterAns(date, 10);
    const apres = (cle: string, libelle: string) => {
      const v = (form[cle] ?? '').trim();
      if (!v || !dateValide(v)) return;
      if (v < date) erreurs.push(`${libelle} : ne peut pas être antérieure à la date de l'acte (${fr(date)}).`);
      else if (v > limite) erreurs.push(`${libelle} : pas plus de dix ans après la date de l'acte.`);
    };
    apres('date_rappel', 'Date de rappel');
    apres('date_validite_debut', 'Date de validité');
    apres('date_fin', 'Date de fin');
  }
  if (form.rappel_actif === 'true') {
    const { heures, erreur } = lireHeures(form.rappel_heures ?? '');
    if (erreur) erreurs.push(erreur);
    else if (!heures.length) erreurs.push('Ajoutez au moins une heure de rappel.');
  }
  return erreurs;
}
