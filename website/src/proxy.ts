import { NextRequest, NextResponse } from 'next/server';

const WHITELISTED_PATHS = [
  '/beta-login',
  '/api/beta-login',
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
