'use client';

import { useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';

// Pages accessibles même sans validation (éleveur/pro en attente)
const PUBLIC_PATHS = [
  '/',
  '/connexion',
  '/inscription',
  '/en-attente-validation',
  '/cgu-acceptation',
  '/cgu',
  '/confidentialite',
  '/mentions-legales',
  '/annonces',
  '/elevages',
  '/animaux-perdus',
  '/services',
  '/animal-friendly',
  '/marketplace',
];

function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.some(p => pathname === p || pathname.startsWith(p + '/'));
}

export default function ValidationGuard({ children }: { children: React.ReactNode }) {
  const { user, userData, loading } = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (loading) return;
    if (!user || !userData) return;

    // RGPD01 : CGU non acceptées → forcer l'acceptation (sauf pages publiques)
    if (!userData.cguAcceptedAt && !isPublicPath(pathname)) {
      router.replace('/cgu-acceptation');
      return;
    }

    if (isPublicPath(pathname)) return;

    // VALID01/02 : éleveur/pro non validé → page d'attente
    const needsValidation = userData.isElevage || userData.isPro;
    if (needsValidation && !userData.isValidate) {
      router.replace('/en-attente-validation');
    }
  }, [user, userData, loading, pathname, router]);

  return <>{children}</>;
}
