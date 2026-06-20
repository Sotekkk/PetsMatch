import { NextRequest, NextResponse } from 'next/server';

const WHITELISTED_PATHS = [
  '/beta-login',
  '/api/beta-login',
  '/api/stripe/webhook',
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
