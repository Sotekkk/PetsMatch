'use client';
// Compte e-mail / mot de passe NON VÉRIFIÉ → page /verifier-email (miroir de
// l'appli : AuthWrapper impose la vérification à chaque ouverture). Les
// comptes Google sont déjà vérifiés par le fournisseur. Pages publiques et
// liens secrets (signature, factures, partages…) restent accessibles.
import { useEffect } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';

const LIBRES = [
  '/verifier-email', '/connexion', '/inscription', '/beta-login', '/cgu', '/cgu-acceptation',
  '/confidentialite', '/mentions-legales', '/contact', '/a-propos', '/tarifs',
  '/signer-cession', '/signer-contrat', '/certificat', '/devis', '/facture', '/facture-pension',
  '/partage', '/album', '/reclamer-animal', '/suivi', '/p/',
];

export default function EmailVerificationGuard() {
  const { user } = useAuth();
  const pathname = usePathname() ?? '/';
  const router = useRouter();

  useEffect(() => {
    const u = auth.currentUser ?? user;
    if (!u || u.emailVerified) return;
    const motDePasse = u.providerData.some((p) => p.providerId === 'password');
    if (!motDePasse) return;
    if (LIBRES.some((p) => pathname === p || pathname.startsWith(p.endsWith('/') ? p : `${p}/`))) return;
    router.replace(`/verifier-email?suite=${encodeURIComponent(pathname)}`);
  }, [user, pathname, router]);

  return null;
}
