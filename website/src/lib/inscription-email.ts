// Inscription : adresse prise par une inscription ABANDONNÉE (compte jamais
// validé) → la Cloud Function libererEmailInscription la supprime pour que la
// nouvelle inscription passe. Un compte validé n'est jamais touché.
// Miroir appli : lib/utils/inscription_email.dart.
const LIBERER_URL = 'https://europe-west1-petsmatch-eb96d.cloudfunctions.net/libererEmailInscription';

/** true si l'adresse est libre (ou vient d'être libérée). */
export async function libererEmailInscription(email: string): Promise<boolean> {
  try {
    const r = await fetch(LIBERER_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: email.trim() }) });
    if (!r.ok) return false;
    return ((await r.json()) as { libere?: boolean }).libere === true;
  } catch {
    return false;
  }
}
