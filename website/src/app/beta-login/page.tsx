'use client';

import { useState, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Image from 'next/image';

function BetaLoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const from = searchParams.get('from') ?? '/';

  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const res = await fetch('/api/beta-login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      });
      if (res.ok) {
        router.push(from);
        router.refresh();
      } else {
        const data = await res.json();
        setError(data.error ?? 'Mot de passe incorrect.');
      }
    } catch {
      setError('Une erreur est survenue. Réessaie.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-8">
          <div className="flex flex-col items-center mb-8">
            <Image
              src="/Logo_petsmatch_fond_blanc.png"
              alt="PetsMatch"
              width={80}
              height={80}
              className="object-contain mb-4"
            />
            <h1 className="text-lg font-semibold text-[#1F2A2E]">Accès bêta privé</h1>
            <p className="text-gray-500 text-sm mt-1 text-center">
              Ce site est en accès restreint.<br />Entre le mot de passe pour continuer.
            </p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-[#1F2A2E] mb-1">
                Mot de passe
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoFocus
                placeholder="••••••••"
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white"
              />
            </div>

            {error && <p className="text-red-500 text-sm">{error}</p>}

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors"
            >
              {loading ? 'Vérification…' : 'Accéder au site'}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

export default function BetaLoginPage() {
  return (
    <Suspense>
      <BetaLoginForm />
    </Suspense>
  );
}
