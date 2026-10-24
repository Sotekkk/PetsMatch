import { NextRequest, NextResponse } from 'next/server';

// Lien de validation d'inscription (e-mail) : valable 10 minutes. La Cloud
// Function validerLienInscription vérifie l'heure d'envoi puis : sans ok=1,
// renvoie vers /valider-email (bouton à cliquer) ; avec ok=1 (clic), vers la
// validation Firebase. Lien expiré → /verifier-email?lien=expire.
export function GET(req: NextRequest) {
  const t = req.nextUrl.searchParams.get('t') ?? '';
  if (!/^[a-f0-9]{48}$/.test(t)) return NextResponse.redirect(new URL('/verifier-email?lien=expire', req.url));
  const ok = req.nextUrl.searchParams.get('ok') === '1' ? '&ok=1' : '';
  return NextResponse.redirect(`https://europe-west1-petsmatch-eb96d.cloudfunctions.net/validerLienInscription?t=${t}${ok}`);
}
