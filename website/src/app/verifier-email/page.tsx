'use client';
// Vérification de l'adresse e-mail (comptes e-mail / mot de passe) — miroir
// de l'écran de l'appli (verifemail.dart) : renvoi de l'e-mail, détection
// automatique de la validation, rappel des spams.
import { Suspense, useCallback, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { sendEmailVerification, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import { changerEmailInscription, envoyerEmailValidation } from '@/lib/inscription-email';
import { auth } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const DELAI_RENVOI_S = 90;

function VerifierEmail() {
  const { user, loading, refreshUserData } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const suite = params.get('suite') && params.get('suite') !== '/verifier-email' ? params.get('suite')! : '/';
  const [attente, setAttente] = useState(0);
  const [message, setMessage] = useState<string | null>(null);
  const [verifie, setVerifie] = useState(false);
  const lienExpire = params.get('lien') === 'expire';
  // Adresse mal saisie : correction sans refaire l'inscription (lien envoyé à la nouvelle adresse).
  const [edition, setEdition] = useState(false);
  const [nouvelEmail, setNouvelEmail] = useState('');
  const [adresseEnvoi, setAdresseEnvoi] = useState<string | null>(null);
  // Adresse changée côté serveur : la session du navigateur n'est plus valable,
  // il faut se reconnecter (avec la nouvelle adresse) pour constater la validation.
  const [sessionExpiree, setSessionExpiree] = useState(false);
  const [mdpConfirme, setMdpConfirme] = useState('');
  // Dernière adresse connue : si Firebase ferme la session (adresse corrigée),
  // on reste sur cette page et on demande juste le mot de passe.
  // Lien expiré ouvert depuis la boîte mail (autre navigateur, pas de session) :
  // l'adresse arrive dans l'URL pour proposer tout de suite un nouveau lien.
  const [derniereAdresse, setDerniereAdresse] = useState(() => params.get('email') ?? '');
  useEffect(() => {
    const e = auth.currentUser?.email ?? user?.email;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (e) setDerniereAdresse(adresseEnvoi ?? e);
  }, [user, loading, adresseEnvoi]);
  const [erreurMdp, setErreurMdp] = useState('');

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
  // Lien expiré : simple message, ni redirection ni reconnexion.
  useEffect(() => {
    if (lienExpire) return;
    if (!loading && !user && !auth.currentUser) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (derniereAdresse) { setSessionExpiree(true); return; }
      router.replace('/connexion'); return;
    }
    const t = setInterval(() => { void verifier(); }, 5000);
    return () => clearInterval(t);
  }, [user, loading, router, verifier, derniereAdresse, lienExpire]);

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
      setMessage('');
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

  const email = auth.currentUser?.email ?? user?.email ?? derniereAdresse;

  if (lienExpire) {
    return (
      <div className="min-h-[70vh] flex items-center justify-center px-4 py-10 bg-[#F8F8F6]">
        <div className="w-full max-w-md bg-white rounded-3xl shadow-sm border border-gray-100 p-7 text-center">
          <h1 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Lien expiré</h1>
          <p className="text-sm text-gray-600">Renvoyez-en un.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-[70vh] flex items-center justify-center px-4 py-10 bg-[#F8F8F6]">
      <div className="w-full max-w-md bg-white rounded-3xl shadow-sm border border-gray-100 p-7 text-center">
        <div className="w-20 h-20 mx-auto rounded-full bg-[#0C5C6C]/10 flex items-center justify-center text-4xl mb-4">✉️</div>
        <h1 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
          {verifie ? 'Adresse vérifiée !' : 'Vérifiez votre adresse e-mail'}
        </h1>
        {lienExpire && !verifie && (
          <p className="mb-4 text-sm font-semibold text-[#B45309] bg-[#FEF3C7] rounded-xl px-3 py-2">
            Ce lien de validation a expiré (valable 10 minutes). Cliquez sur « Renvoyer l&apos;e-mail » pour en recevoir un nouveau.
          </p>
        )}
        {sessionExpiree && !verifie ? (
          <div className="space-y-4">
            <p className="text-sm text-gray-600 leading-relaxed">
              Pour continuer votre inscription avec <strong className="text-[#1F2A2E]">{adresseEnvoi ?? email}</strong>,
              confirmez simplement votre mot de passe. Vos informations sont conservées.
            </p>
            <form onSubmit={async (e) => {
              e.preventDefault();
              setErreurMdp('');
              try {
                const cred = await signInWithEmailAndPassword(auth, adresseEnvoi ?? email, mdpConfirme);
                setSessionExpiree(false); setMdpConfirme('');
                if (cred.user.emailVerified) { await verifier(); return; }
                // Nouveau lien envoyé tout de suite (lien précédent expiré).
                const ok = await envoyerEmailValidation(cred.user);
                setMessage(ok ? `Nouveau lien envoyé à ${cred.user.email} (valable 10 minutes).` : 'Envoi impossible pour le moment. Réessayez dans quelques minutes.');
                setAttente(DELAI_RENVOI_S);
              } catch {
                setErreurMdp('Mot de passe incorrect.');
              }
            }} className="space-y-3 text-left">
              <label htmlFor="mdp-confirme" className="block text-xs font-semibold text-gray-600">Mot de passe</label>
              <input id="mdp-confirme" type="password" value={mdpConfirme} onChange={e => setMdpConfirme(e.target.value)}
                autoComplete="current-password" className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm" />
              {erreurMdp && <p className="text-xs text-red-600">{erreurMdp}</p>}
              <button type="submit" disabled={!mdpConfirme}
                className="w-full py-3 rounded-xl bg-[#0C5C6C] text-white font-semibold hover:opacity-90 disabled:opacity-50">
                Continuer
              </button>
            </form>
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
