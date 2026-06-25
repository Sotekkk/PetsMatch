'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import Link from 'next/link';
import { signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';

export default function EnAttenteValidationPage() {
  const { user, userData, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!user) { router.replace('/connexion'); return; }
    // Already approved → back to home
    if (userData?.isValidate) { router.replace('/'); return; }
    // Not an éleveur/pro/association → no validation needed
    if (!userData?.isElevage && !userData?.isPro && !userData?.isAssociation) { router.replace('/'); return; }
  }, [user, userData, loading, router]);

  if (loading || !userData) {
    return (
      <div className="min-h-[60vh] flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const isRefused = userData.statutPro === 'refuse';

  return (
    <div className="min-h-[75vh] flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-8 text-center">
          <div className="flex justify-center mb-6">
            <Image src="/Banniere_petsmatch.png" alt="PetsMatch" width={220} height={70} className="object-contain" />
          </div>

          {isRefused ? (
            <>
              <div className="w-16 h-16 bg-red-50 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </div>
              <h1 className="text-xl font-bold text-[#1F2A2E] mb-2">Dossier non accepté</h1>
              <p className="text-sm text-gray-500 mb-4">
                Notre équipe a examiné votre dossier et ne peut pas l&apos;activer pour la raison suivante :
              </p>
              {userData.rejectionReason && (
                <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-6 text-left">
                  <p className="text-sm font-medium text-red-700 mb-1">Motif :</p>
                  <p className="text-sm text-red-600">{userData.rejectionReason}</p>
                </div>
              )}
              <p className="text-xs text-gray-400 mb-6">
                Vous pouvez corriger votre dossier et contacter notre équipe via le formulaire de contact
                pour soumettre à nouveau votre demande.
              </p>
            </>
          ) : (
            <>
              <div className="w-16 h-16 bg-orange-50 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-orange-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h1 className="text-xl font-bold text-[#1F2A2E] mb-2">Dossier en cours d&apos;examen</h1>
              <p className="text-sm text-gray-500 mb-4">
                Votre dossier est en cours de vérification par notre équipe.
                Vous recevrez un e-mail dès que votre compte sera activé.
              </p>
              <div className="bg-orange-50 border border-orange-200 rounded-xl p-4 mb-6 text-left">
                <p className="text-xs text-orange-700 font-medium mb-1">Délai habituel</p>
                <p className="text-xs text-orange-600">
                  Notre équipe traite les dossiers sous 48h ouvrées. Vérifiez vos spams si vous ne recevez pas d&apos;e-mail.
                </p>
              </div>
            </>
          )}

          <div className="space-y-3">
            <Link
              href="/contact"
              className="block w-full border border-[#0C5C6C] text-[#0C5C6C] rounded-xl py-2.5 text-sm font-semibold text-center hover:bg-[#0C5C6C10] transition-colors"
            >
              Contacter le support
            </Link>
            <button
              onClick={() => signOut(auth)}
              className="block w-full text-sm text-gray-400 hover:text-gray-600 py-2"
            >
              Se déconnecter
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
