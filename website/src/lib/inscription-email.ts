import { signInWithCustomToken } from 'firebase/auth';
import { auth } from '@/lib/firebase';
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

const CHANGER_URL = 'https://europe-west1-petsmatch-eb96d.cloudfunctions.net/changerEmailInscription';

/** Adresse mal saisie (compte pas encore validé) : changée tout de suite sur le
 *  même compte. Retourne un message d'erreur, ou null si c'est fait. */
export async function changerEmailInscription(jeton: string, email: string): Promise<string | null> {
  try {
    const r = await fetch(CHANGER_URL, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${jeton}` },
      body: JSON.stringify({ email: email.trim() }),
    });
    const corps = (await r.json().catch(() => ({}))) as { error?: string; customToken?: string | null };
    if (!r.ok) return corps.error ?? 'Changement impossible. Réessayez.';
    // Adresse changée = session fermée par Firebase : reconnexion automatique
    // (jeton fourni par la Cloud Function), sans rien demander à la personne.
    if (corps.customToken) {
      try { await signInWithCustomToken(auth, corps.customToken); } catch { /* repli : reconnexion proposée */ }
    }
    return null;
  } catch {
    return 'Pas de connexion. Réessayez.';
  }
}
