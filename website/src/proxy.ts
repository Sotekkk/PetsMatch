import { NextRequest, NextResponse } from 'next/server';

const WHITELISTED_PATHS = [
  '/beta-login',
  // Routes API : appelées par l'APPLI (e-mails de certificat, contrat,
  // cession, facture, RDV…) sans cookie bêta → redirigées vers /beta-login,
  // aucun e-mail n'était envoyé. Chaque route vérifie elle-même l'appelant
  // (jeton Firebase, secret interne, signature webhook).
  '/api/',
  // Webhooks entrants (Stripe, YouSign) — jamais soumis à l'accès bêta.
  '/api/stripe/webhook',
  '/api/yousign/webhook',
  // Tâches planifiées appelées par un planificateur externe (auth par
  // CRON_SECRET dans la route elle-même).
  '/api/cron/',
  '/api/contracts/expire',
  // Lien de facture pension envoyé au propriétaire (token UUID) — doit rester
  // consultable même si le destinataire n'a pas l'accès bêta.
  '/facture-pension/',
  // Pages légales — doivent être accessibles sans connexion ni mot de passe
  // bêta (exigence Google Play/App Store, cf. rejet "Invalid Privacy policy" :
  // le robot de review n'a pas l'accès bêta).
  '/confidentialite',
  '/cgu',
  '/mentions-legales',
  // Mot de passe oublié + gestionnaire d'actions Firebase (lien de
  // réinitialisation / vérification d'e-mail) : sans accès bêta, la
  // redirection vers /beta-login perdait le code du lien (« lien expiré »).
  '/mot-de-passe-oublie',
  '/__/auth/',
];

const STATIC_EXTENSIONS = /\.(ico|png|jpg|jpeg|svg|webp|woff|woff2|ttf|otf)$/;

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (
    pathname.startsWith('/_next/') ||
    STATIC_EXTENSIONS.test(pathname) ||
    WHITELISTED_PATHS.some(p => pathname.startsWith(p))
  ) {
    return NextResponse.next();
  }

  const betaPassword = process.env.BETA_PASSWORD;
  if (!betaPassword) return NextResponse.next();

  const cookie = request.cookies.get('beta_access');
  if (cookie?.value === betaPassword) return NextResponse.next();

  const loginUrl = new URL('/beta-login', request.url);
  if (pathname !== '/') loginUrl.searchParams.set('from', pathname);
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
