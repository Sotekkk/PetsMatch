import { NextRequest, NextResponse } from 'next/server';

// Lien de validation d'inscription (e-mail) : valable 10 minutes. La Cloud
// Function validerLienInscription vérifie l'heure d'envoi et redirige vers la
// validation Firebase, ou vers /verifier-email?lien=expire.
export function GET(req: NextRequest) {
  const t = req.nextUrl.searchParams.get('t') ?? '';
  if (!/^[a-f0-9]{48}$/.test(t)) return NextResponse.redirect(new URL('/verifier-email?lien=expire', req.url));
  return NextResponse.redirect(`https://europe-west1-petsmatch-eb96d.cloudfunctions.net/validerLienInscription?t=${t}`);
}
