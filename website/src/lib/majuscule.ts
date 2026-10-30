// Valeur d'une ligne « Libellé : valeur » des PDF (race, sexe, motif…) :
// première lettre en majuscule, et après chaque séparateur « · », « — », « / »
// (« chien · berger allemand » → « Chien · Berger allemand »).
// Miroir appli : lib/utils/majuscule.dart.
export function majuscule(valeur: string): string {
  return valeur.replace(/(^\s*|[·—/]\s*)(\p{Ll})/gu, (_, avant: string, lettre: string) => avant + lettre.toUpperCase());
}
