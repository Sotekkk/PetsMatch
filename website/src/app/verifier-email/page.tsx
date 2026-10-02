'use client';
// Vérification de l'adresse e-mail (comptes e-mail / mot de passe) — miroir
// de l'écran de l'appli (verifemail.dart) : renvoi de l'e-mail, détection
// automatique de la validation, rappel des spams.
import { Suspense, useCallback, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { sendEmailVerification, signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';

const DELAI_RENVOI_S = 60;

function VerifierEmail() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const suite = params.get('suite') && params.get('suite') !== '/verifier-email' ? params.get('suite')! : '/';
  const [attente, setAttente] = useState(0);
  const [message, setMessage] = useState<string | null>(null);
  const [verifie, setVerifie] = useState(false);

  const verifier = useCallback(async () => {
    const u = auth.currentUser;
    if (!u) return false;
    await u.reload();
    if (auth.currentUser?.emailVerified) {
      setVerifie(true);
      await auth.currentUser.getIdToken(true); // jeton à jour (email_verified)
      router.replace(suite);
      return true;
    }
    return false;
  }, [router, suite]);

  // Pas connecté → connexion ; vérification automatique toutes les 5 s.
  useEffect(() => {
    if (!loading && !user && !auth.currentUser) { router.replace('/connexion'); return; }
    const t = setInterval(() => { void verifier(); }, 5000);
    return () => clearInterval(t);
  }, [user, loading, router, verifier]);

  useEffect(() => {
    if (attente <= 0) return;
    const t = setTimeout(() => setAttente((a) => a - 1), 1000);
    return () => clearTimeout(t);
  }, [attente]);

  async function renvoyer() {
    const u = auth.currentUser;
    if (!u) return;
    try {
      await sendEmailVerification(u);
      setMessage('E-mail renvoyé. Pensez à regarder dans les spams.');
      setAttente(DELAI_RENVOI_S);
    } catch {
      setMessage('Trop de demandes : réessayez dans quelques minutes.');
      setAttente(DELAI_RENVOI_S);
    }
  }

  async function verifierMaintenant() {
    const ok = await verifier();
    if (!ok) setMessage("Votre adresse n'est pas encore vérifiée : cliquez sur le lien reçu par e-mail.");
  }

  const email = auth.currentUser?.email ?? user?.email ?? '';

  return (
    <div className="min-h-[70vh] flex items-center justify-center px-4 py-10 bg-[#F8F8F6]">
      <div className="w-full max-w-md bg-white rounded-3xl shadow-sm border border-gray-100 p-7 text-center">
        <div className="w-20 h-20 mx-auto rounded-full bg-[#0C5C6C]/10 flex items-center justify-center text-4xl mb-4">✉️</div>
        <h1 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
          {verifie ? 'Adresse vérifiée !' : 'Vérifiez votre adresse e-mail'}
        </h1>
        {verifie ? (
          <p className="text-sm text-gray-600">Redirection en cours…</p>
        ) : (
          <>
            <p className="text-sm text-gray-600 leading-relaxed">
              Un e-mail de vérification a été envoyé à <strong className="text-[#1F2A2E]">{email}</strong>.
              Cliquez sur le lien qu&apos;il contient — cette page se met à jour automatiquement.
            </p>
            <div className="mt-4 flex items-start gap-2 text-left bg-[#FFF7E6] border border-[#F5C26B] rounded-xl p-3">
              <span aria-hidden>📬</span>
              <p className="text-xs text-[#7A4E0F] leading-relaxed">
                Pas reçu ? Pensez à vérifier vos courriers indésirables (spams) et l&apos;onglet Promotions.
              </p>
            </div>
            {message && <p className="mt-4 text-sm text-[#0C5C6C]">{message}</p>}
            <div className="mt-6 space-y-2">
              <button onClick={verifierMaintenant}
                className="w-full py-3 rounded-xl bg-[#0C5C6C] text-white font-semibold hover:opacity-90">
                J&apos;ai cliqué sur le lien
              </button>
              <button onClick={renvoyer} disabled={attente > 0}
                className="w-full py-3 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] font-semibold disabled:opacity-50">
                {attente > 0 ? `Renvoyer l'e-mail (${attente} s)` : "Renvoyer l'e-mail de vérification"}
              </button>
              <button onClick={async () => { await signOut(auth); router.replace('/connexion'); }}
                className="w-full py-2 text-sm text-gray-500 hover:text-gray-700">
                Se déconnecter
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

export default function VerifierEmailPage() {
  return <Suspense fallback={null}><VerifierEmail /></Suspense>;
}
