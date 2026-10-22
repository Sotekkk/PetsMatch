'use client';
// Vérification de l'adresse e-mail (comptes e-mail / mot de passe) — miroir
// de l'écran de l'appli (verifemail.dart) : renvoi de l'e-mail, détection
// automatique de la validation, rappel des spams.
import { Suspense, useCallback, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { sendEmailVerification, signOut } from 'firebase/auth';
import { changerEmailInscription } from '@/lib/inscription-email';
import { auth } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const DELAI_RENVOI_S = 60;

function VerifierEmail() {
  const { user, loading, refreshUserData } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const suite = params.get('suite') && params.get('suite') !== '/verifier-email' ? params.get('suite')! : '/';
  const [attente, setAttente] = useState(0);
  const [message, setMessage] = useState<string | null>(null);
  const [verifie, setVerifie] = useState(false);
  // Adresse mal saisie : correction sans refaire l'inscription (lien envoyé à la nouvelle adresse).
  const [edition, setEdition] = useState(false);
  const [nouvelEmail, setNouvelEmail] = useState('');
  const [adresseEnvoi, setAdresseEnvoi] = useState<string | null>(null);
  // Adresse changée côté serveur : la session du navigateur n'est plus valable,
  // il faut se reconnecter (avec la nouvelle adresse) pour constater la validation.
  const [sessionExpiree, setSessionExpiree] = useState(false);

  const verifier = useCallback(async () => {
    const u = auth.currentUser;
    if (!u) return false;
    try {
      await u.reload();
    } catch {
      setSessionExpiree(true);
      return false;
    }
    if (auth.currentUser?.emailVerified) {
      setVerifie(true);
      // Adresse corrigée et validée : le compte enregistre la nouvelle.
      const mail = auth.currentUser.email;
      if (mail) { try { await supabase.from('users').update({ email: mail }).eq('uid', auth.currentUser.uid); } catch { /* */ } }
      await auth.currentUser.getIdToken(true); // jeton à jour (email_verified)
      // Profil créé juste après le compte : rechargé avant la suite.
      try { await refreshUserData(); } catch { /* */ }
      router.replace(suite);
      return true;
    }
    return false;
  }, [router, suite, refreshUserData]);

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
    // Session plus valable (lien expiré, adresse changée, onglet resté ouvert) :
    // on propose de se reconnecter au lieu de ne rien faire.
    let jeton = '';
    try { if (u) jeton = await u.getIdToken(true); } catch { /* session expirée */ }
    if (!u || !jeton) {
      setSessionExpiree(true);
      setMessage('Votre session a expiré : reconnectez-vous pour recevoir un nouveau lien.');
      return;
    }
    // Renvoi par le serveur (l'envoi direct du navigateur échoue souvent en silence).
    const err = await changerEmailInscription(jeton, u.email ?? '');
    if (err) {
      try { await sendEmailVerification(u); setMessage('E-mail renvoyé. Pensez à regarder dans les spams.'); }
      catch { setMessage('Trop de demandes : réessayez dans quelques minutes.'); }
    } else {
      setMessage(`E-mail renvoyé à ${u.email}. Pensez à regarder dans les spams.`);
    }
    setAttente(DELAI_RENVOI_S);
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
        {sessionExpiree && !verifie ? (
          <div className="space-y-4">
            <p className="text-sm text-gray-600 leading-relaxed">
              Votre session a expiré{adresseEnvoi ? <> (adresse : <strong className="text-[#1F2A2E]">{adresseEnvoi}</strong>)</> : null}.
              Reconnectez-vous avec votre adresse et votre mot de passe : vos informations sont conservées et vous pourrez recevoir un nouveau lien de validation.
            </p>
            <button onClick={async () => {
              const mail = adresseEnvoi ?? auth.currentUser?.email ?? '';
              try { await signOut(auth); } catch { /* */ }
              router.replace(`/connexion?email=${encodeURIComponent(mail)}&suite=${encodeURIComponent(suite)}`);
            }} className="w-full py-3 rounded-xl bg-[#0C5C6C] text-white font-semibold hover:opacity-90">
              Me reconnecter
            </button>
          </div>
        ) : verifie ? (
          <p className="text-sm text-gray-600">Redirection en cours…</p>
        ) : (
          <>
            <p className="text-sm text-gray-600 leading-relaxed">
              Un e-mail de vérification a été envoyé à <strong className="text-[#1F2A2E]">{adresseEnvoi ?? email}</strong>.
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
              {edition ? (
                <div className="flex gap-2">
                  <input type="email" value={nouvelEmail} onChange={e => setNouvelEmail(e.target.value)} placeholder="Nouvelle adresse e-mail"
                    className="flex-1 min-w-0 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                  <button onClick={async () => {
                    const u = auth.currentUser; const mail = nouvelEmail.trim();
                    if (!u || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(mail)) { setMessage("Cette adresse n'est pas valide."); return; }
                    setMessage('Changement en cours…');
                    // Adresse changée tout de suite sur le même compte, puis nouvel e-mail de validation.
                    const err = await changerEmailInscription(await u.getIdToken(), mail);
                    if (err) { setMessage(err); return; }
                    // E-mail de validation envoyé par le serveur à la nouvelle adresse.
                    try { await u.reload(); } catch { /* */ }
                    setAdresseEnvoi(mail); setEdition(false);
                    setMessage(`Adresse corrigée : un lien de validation a été envoyé à ${mail}. Vos informations sont conservées.`);
                  }} className="px-4 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold">Valider</button>
                </div>
              ) : (
                <button onClick={() => { setEdition(true); setNouvelEmail(''); }}
                  className="w-full py-2 text-sm text-[#0C5C6C] font-semibold hover:underline">
                  Adresse erronée ? Modifier l&apos;adresse e-mail
                </button>
              )}
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
