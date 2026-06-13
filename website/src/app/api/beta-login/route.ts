import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  const { password } = await req.json();
  const betaPassword = process.env.BETA_PASSWORD;

  if (!betaPassword || password !== betaPassword) {
    return NextResponse.json({ error: 'Mot de passe incorrect.' }, { status: 401 });
  }

  const res = NextResponse.json({ ok: true });
  res.cookies.set('beta_access', betaPassword, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: 60 * 60 * 24 * 30,
    path: '/',
  });
  return res;
}
