'use client';

import { useState, useEffect } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  nac: '🦎', oiseau: '🦜', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

interface Animal {
  id: string;
  nom: string | null;
  espece: string | null;
  race: string | null;
  sexe: string | null;
  photo_url: string | null;
  date_naissance: string | null;
  date_sortie: string | null;
  cession_prix: number | null;
  uid_eleveur: string | null;
}

export default function MesAnimauxAcquisPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('animaux')
      .select('id, nom, espece, race, sexe, photo_url, date_naissance, date_sortie, cession_prix, uid_eleveur')
      .eq('uid_acquereur', user.uid)
      .order('date_sortie', { ascending: false })
      .then(({ data }) => {
        setAnimaux((data ?? []) as Animal[]);
        setLoading(false);
      }, () => setLoading(false));
  }, [user]);

  if (authLoading || loading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 pb-24">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.back()}
          className="p-2 rounded-xl hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes animaux acquis
          </h1>
          <p className="text-xs text-gray-400">Animaux reçus par cession — lecture seule</p>
        </div>
      </div>

      {animaux.length === 0 ? (
        <div className="text-center py-24 text-gray-400">
          <p className="text-5xl mb-3">🐾</p>
          <p className="font-semibold text-gray-500">Aucun animal acquis</p>
          <p className="text-sm mt-1">Les animaux qui vous sont cédés apparaîtront ici.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {animaux.map(a => {
            const dt = a.date_sortie ? new Date(a.date_sortie) : null;
            const dateStr = dt ? dt.toLocaleDateString('fr-FR') : null;
            const emoji = ESPECE_EMOJI[a.espece ?? ''] ?? '🐾';

            return (
              <Link key={a.id} href={`/mes-animaux/${a.id}?readOnly=1`}
                className="flex items-center gap-4 bg-white rounded-2xl p-4 shadow-sm border border-gray-100 hover:shadow-md transition-shadow">
                <div className="w-16 h-16 rounded-xl overflow-hidden bg-gray-50 flex-shrink-0 relative">
                  {a.photo_url ? (
                    <Image src={a.photo_url} alt={a.nom ?? ''} fill className="object-cover" sizes="64px" unoptimized />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-2xl">{emoji}</div>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-[#1F2A2E] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                    {a.nom ?? '—'}
                  </p>
                  <p className="text-sm text-gray-400 capitalize">
                    {a.espece}{a.race ? ` · ${a.race}` : ''}
                  </p>
                  {dateStr && (
                    <p className="text-xs text-[#6E9E57] font-medium mt-0.5">Acquis le {dateStr}</p>
                  )}
                  {a.cession_prix && (
                    <p className="text-xs text-gray-400">{a.cession_prix} €</p>
                  )}
                </div>
                <div className="flex flex-col items-end gap-1 flex-shrink-0">
                  <span className="text-xs bg-gray-100 text-gray-400 px-2 py-0.5 rounded-full">Lecture seule</span>
                  <svg className="w-5 h-5 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                  </svg>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
