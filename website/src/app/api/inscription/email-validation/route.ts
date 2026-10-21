import { NextRequest, NextResponse } from 'next/server';
import { requireUserOrInternal } from '@/lib/server-auth';
import { emailValide, envoyerEmail, gabaritEmail } from '@/lib/email-petsmatch';

// E-mail de validation de l'adresse après correction à l'inscription. Le lien
// est généré par la Cloud Function changerEmailInscription (Admin SDK) ; seuls
// les liens d'action Firebase du projet sont acceptés (pas d'envoi de lien tiers).
const HOTES_AUTORISES = ['petsmatch-eb96d.firebaseapp.com', 'petsmatchapp.com', 'www.petsmatchapp.com'];

export async function POST(req: NextRequest) {
  const auth = await requireUserOrInternal(req, { allowIfSecretUnset: true });
  if (auth instanceof NextResponse) return auth;
  const { email, lien } = await req.json().catch(() => ({})) as { email?: string; lien?: string };
  if (!email || !emailValide(email)) return NextResponse.json({ error: 'E-mail invalide' }, { status: 400 });
  let url: URL;
  try { url = new URL(lien ?? ''); } catch { return NextResponse.json({ error: 'Lien invalide' }, { status: 400 }); }
  if (url.protocol !== 'https:' || !HOTES_AUTORISES.includes(url.hostname) || url.searchParams.get('mode') !== 'verifyEmail') {
    return NextResponse.json({ error: 'Lien non autorisé' }, { status: 400 });
  }
  const html = gabaritEmail({
    sousTitre: 'Validez votre adresse e-mail',
    salutation: 'Bonjour,',
    paragraphes: [
      'Votre adresse e-mail a bien été corrigée. Il reste une étape pour finaliser votre inscription sur PetsMatch : validez cette adresse.',
    ],
    bouton: { label: 'Valider mon adresse e-mail', url: url.toString() },
    pied: "Si vous n'êtes pas à l'origine de cette inscription, ignorez simplement cet e-mail.",
  });
  await envoyerEmail(email, 'Validez votre adresse e-mail — PetsMatch', html);
  return NextResponse.json({ ok: true });
}
