'use client';

// Mot de passe oublié — miroir appli (lib/pages/password_oublier.dart).
// Un seul envoi puis 60 s d'attente : chaque nouvel envoi rend le lien de
// l'e-mail précédent invalide (« lien expiré » si on ouvre l'ancien).
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { sendPasswordResetEmail } from 'firebase/auth';
import { auth } from '@/lib/firebase';

export default function MotDePasseOubliePage() {
  const [email, setEmail] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [envoye, setEnvoye] = useState(false);
  const [erreur, setErreur] = useState('');
  const [attente, setAttente] = useState(0);

  useEffect(() => {
    const e = new URLSearchParams(window.location.search).get('email');
    if (e) setEmail(e);
  }, []);

  useEffect(() => {
    if (attente <= 0) return;
    const t = setTimeout(() => setAttente(a => a - 1), 1000);
    return () => clearTimeout(t);
  }, [attente]);

  async function envoyer(ev: React.FormEvent) {
    ev.preventDefault();
    const adresse = email.trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(adresse)) { setErreur('Adresse e-mail invalide.'); return; }
    if (envoi || attente > 0) return;
    setEnvoi(true); setErreur('');
    try {
      auth.languageCode = 'fr';
      await sendPasswordResetEmail(auth, adresse);
      setEnvoye(true);
      setAttente(60);
    } catch (e) {
      const code = (e as { code?: string }).code ?? '';
      setErreur(
        code === 'auth/invalid-email' ? 'Adresse e-mail invalide.'
        : code === 'auth/too-many-requests' ? 'Trop de demandes. Réessayez dans quelques minutes.'
        : code === 'auth/user-not-found' ? 'Aucun compte PetsMatch avec cette adresse.'
        : `Envoi impossible${code ? ` (${code})` : ''}. Réessayez.`,
      );
    } finally {
      setEnvoi(false);
    }
  }

  return (
    <div className="min-h-[70vh] flex items-center justify-center px-4 py-12">
      <form onSubmit={envoyer} className="w-full max-w-md bg-white rounded-2xl shadow-sm border border-gray-100 p-8 space-y-4">
        <h1 className="text-xl font-bold text-[#1F2A2E] font-galey">Réinitialiser votre mot de passe</h1>
        <p className="text-sm text-gray-500">
          Saisissez l&apos;adresse e-mail de votre compte : vous recevrez un lien pour choisir un nouveau mot de passe.
        </p>
        <input type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="email"
          placeholder="Adresse e-mail"
          className="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30" />
        {erreur && <p className="text-sm text-red-600">{erreur}</p>}
        {envoye && (
          <div className="rounded-xl bg-[#6E9E57]/10 border border-[#6E9E57]/35 p-4 text-sm text-[#3D6B2E] space-y-1">
            <p>✅ E-mail envoyé à {email.trim()}.</p>
            <p>• Ouvrez le lien du <strong>dernier</strong> e-mail reçu : chaque nouvel envoi rend les précédents invalides.</p>
            <p>• Pensez à regarder dans les spams / courriers indésirables.</p>
            <p>• Le lien est valable 1 heure.</p>
          </div>
        )}
        <button type="submit" disabled={envoi || attente > 0}
          className="w-full bg-[#6E9E57] hover:bg-[#5d8a48] disabled:opacity-40 text-white font-semibold py-3 rounded-xl transition-colors">
          {envoi ? 'Envoi…' : attente > 0 ? `Renvoyer dans ${attente} s` : envoye ? "Renvoyer l'e-mail" : 'Envoyer le lien'}
        </button>
        <Link href="/connexion" className="block text-center text-sm text-[#0C5C6C] hover:underline">← Retour à la connexion</Link>
      </form>
    </div>
  );
}
