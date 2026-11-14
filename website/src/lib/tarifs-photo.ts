// Photographe — rappel des tarifs envoyé en fin de séance (avant la sélection) :
// forfait = prix minimum, photos incluses, prix d'une photo supplémentaire.
// Partagé entre FinSeancePhotoModal (aperçu) et /api/photographe/fin-seance (e-mail).
// Miroir appli : _texteTarifs (photographe_dossier_seance.dart).
export interface TarifsSeance { forfait: number | null; incluses: number | null; prixPhoto: number | null }

const eur = (v: number) => `${Number.isInteger(v) ? v : v.toFixed(2).replace('.', ',')} €`;
const photos = (n: number) => `${n} photo${n > 1 ? 's' : ''} incluse${n > 1 ? 's' : ''}`;

/** « forfait de 150 € (prix minimum), 10 photos incluses, puis 15 € par photo supplémentaire choisie », ou null. */
export function texteTarifs(t: TarifsSeance): string | null {
  const parts: string[] = [];
  if (t.forfait != null && t.forfait > 0) parts.push(`forfait de ${eur(t.forfait)} (prix minimum)${t.incluses ? `, ${photos(t.incluses)}` : ''}`);
  else if (t.incluses) parts.push(photos(t.incluses));
  if (t.prixPhoto != null && t.prixPhoto > 0) parts.push(`${parts.length ? 'puis ' : ''}${eur(t.prixPhoto)} par photo supplémentaire choisie`);
  return parts.length ? parts.join(', ') : null;
}
