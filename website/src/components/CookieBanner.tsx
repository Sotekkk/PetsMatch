'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';

const CONSENT_KEY = 'pm_cookie_consent';

type Consent = 'accepted' | 'declined' | null;

export default function CookieBanner() {
  const [consent, setConsent] = useState<Consent | 'loading'>('loading');

  useEffect(() => {
    const stored = localStorage.getItem(CONSENT_KEY) as Consent;
    setConsent(stored ?? null);
  }, []);

  function accept() {
    localStorage.setItem(CONSENT_KEY, 'accepted');
    setConsent('accepted');
  }

  function decline() {
    localStorage.setItem(CONSENT_KEY, 'declined');
    setConsent('declined');
  }

  // Don't render until localStorage is read (avoids hydration mismatch)
  if (consent !== null) return null;

  return (
    <div
      role="dialog"
      aria-label="Gestion des cookies"
      className="fixed bottom-0 left-0 right-0 z-50 bg-[#1F2A2E] text-white shadow-2xl"
    >
      <div className="max-w-6xl mx-auto px-4 py-4 flex flex-col sm:flex-row items-start sm:items-center gap-4">
        <div className="flex-1 text-sm text-white/80 leading-relaxed">
          <p>
            Nous utilisons des cookies pour améliorer votre expérience et mesurer l&apos;audience du site
            (Google Analytics, Firebase). Les cookies fonctionnels sont nécessaires au fonctionnement du service.{' '}
            <Link href="/confidentialite" className="underline text-white/60 hover:text-white transition-colors">
              En savoir plus
            </Link>
          </p>
        </div>
        <div className="flex gap-3 shrink-0">
          <button
            onClick={decline}
            className="px-4 py-2 rounded-lg text-sm font-medium border border-white/30 hover:border-white/60 text-white/70 hover:text-white transition-colors"
          >
            Refuser
          </button>
          <button
            onClick={accept}
            className="px-5 py-2 rounded-lg text-sm font-semibold bg-[#6E9E57] hover:bg-[#5d8a49] text-white transition-colors"
          >
            Accepter
          </button>
        </div>
      </div>
    </div>
  );
}
