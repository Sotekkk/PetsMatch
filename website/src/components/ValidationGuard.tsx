'use client';

import { useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

// Pages accessibles même sans validation (éleveur/pro en attente)
const PUBLIC_PATHS = [
  '/',
  '/beta-login',
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
  const { user, userData, loading, refreshUserData } = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (loading) return;
    if (!user || !userData) return;

    // RGPD01 : CGU non acceptées → forcer l'acceptation (sauf pages publiques)
    if (!userData.cguAcceptedAt && !isPublicPath(pathname)) {
      // Comptes créés avant l'introduction de la CGU web (inscrits via app) :
      // ils ont déjà accepté dans l'app → on backfille silencieusement.
      const isEleveurOrPro = userData.isElevage || userData.isPro || userData.isAssociation;
      if (!isEleveurOrPro && userData.isValidate) {
        // Particulier validé sans cgu_accepted_at → inscription antérieure, on accepte
        supabase.from('users')
          .update({ cgu_accepted_at: new Date().toISOString() })
          .eq('uid', user.uid)
          .then(() => refreshUserData());
        return; // ne pas rediriger
      }
      router.replace('/cgu-acceptation');
      return;
    }

    if (isPublicPath(pathname)) return;

    // VALID01/02 : éleveur/pro non validé → page d'attente
    const needsValidation = userData.isElevage || userData.isPro || userData.isAssociation;
    if (needsValidation && !userData.isValidate) {
      router.replace('/en-attente-validation');
    }
  }, [user, userData, loading, pathname, router, refreshUserData]);

  return <>{children}</>;
}
