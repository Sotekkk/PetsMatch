'use client';

import { useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';
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
  '/communaute',
  '/promenades',
  '/tarifs',
  '/contact',
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

    // VALID01/02 : un pro/éleveur/association REFUSÉ reste bloqué — un dossier
    // simplement en attente (jamais encore examiné) garde l'accès normal au
    // site, seule sa visibilité auprès des autres est restreinte (gérée par
    // les pages publiques elles-mêmes, pas ici).
    const needsValidation = userData.isElevage || userData.isPro || userData.isAssociation;
    if (needsValidation && !userData.isValidate && userData.statutPro === 'refuse') {
      router.replace('/en-attente-validation');
    }
  }, [user, userData, loading, pathname, router, refreshUserData]);

  // Bandeau persistant (non bloquant) tant que le dossier n'a pas encore été
  // examiné — reprend le message déjà utilisé sur /en-attente-validation.
  const needsValidation = !!userData && (userData.isElevage || userData.isPro || userData.isAssociation);
  const isPending = needsValidation && !userData!.isValidate && userData!.statutPro !== 'refuse';

  // Compte suspendu par un admin (bouton « Suspendre ») — bloquant, tous
  // types de compte confondus (y compris particulier), contrairement au
  // statut « refuse » qui ne concerne que la validation pro.
  const isSuspended = userData?.statutPro === 'suspendu';
  if (isSuspended && !isPublicPath(pathname)) {
    return (
      <div className="min-h-screen bg-[#F8F8F6] flex flex-col items-center justify-center gap-3 px-4 text-center">
        <span className="text-5xl">🚫</span>
        <p className="text-gray-700 font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
          Compte suspendu
        </p>
        <p className="text-gray-500 text-sm max-w-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
          Votre compte a été suspendu par un administrateur. Contactez le support si vous pensez qu&apos;il s&apos;agit d&apos;une erreur.
        </p>
        <button onClick={() => signOut(auth)}
          className="mt-2 px-5 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D]">
          Se déconnecter
        </button>
      </div>
    );
  }

  return (
    <>
      {isPending && !isPublicPath(pathname) && (
        <div className="bg-orange-50 border-b border-orange-200 px-4 py-2.5 flex items-center gap-2 text-sm text-orange-800">
          <span className="text-base">⏳</span>
          <span style={{ fontFamily: 'Galey, sans-serif' }}>
            Votre dossier professionnel est en cours d&apos;examen — vous pouvez utiliser votre compte normalement,
            mais votre profil n&apos;est pas encore visible par les autres utilisateurs.
          </span>
        </div>
      )}
      {children}
    </>
  );
}
