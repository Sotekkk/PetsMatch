'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

interface Balade {
  titre: string; nb_joueurs?: number; nb_completions?: number; note_moyenne?: number; nb_avis?: number; nb_favoris?: number;
}
interface Avis { id: string; note: number; commentaire?: string; }

export default function ParcoursStatsPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [balade, setBalade] = useState<Balade | null>(null);
  const [avis, setAvis] = useState<Avis[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      supabase.from('balades_ludiques').select('*').eq('id', id).single(),
      supabase.from('balades_ludiques_avis').select('*').eq('balade_id', id).order('created_at', { ascending: false }),
    ]).then(([{ data: b }, { data: a }]) => {
      setBalade(b as Balade);
      setAvis((a ?? []) as Avis[]);
      setLoading(false);
    });
  }, [id]);

  if (loading) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" /></div>;
  if (!balade) return null;

  const nbJoueurs = balade.nb_joueurs ?? 0;
  const nbCompletions = balade.nb_completions ?? 0;
  const taux = nbJoueurs === 0 ? 0 : Math.round((nbCompletions / nbJoueurs) * 100);

  const cards = [
    ['Joueurs', nbJoueurs, '#0C5C6C'],
    ['Complétions', nbCompletions, '#6E9E57'],
    ['Taux de réussite', `${taux}%`, '#C2410C'],
    ['Note moyenne', balade.note_moyenne ? `⭐ ${balade.note_moyenne}` : '—', '#D97706'],
    ['Avis', balade.nb_avis ?? 0, '#7C3AED'],
    ['Favoris', balade.nb_favoris ?? 0, '#DB2777'],
  ] as const;

  return (
    <div className="min-h-screen bg-[#F8F8F6]">
      <div className="bg-teal-700 text-white px-4 py-4">
        <div className="max-w-2xl mx-auto flex items-center gap-3">
          <button onClick={() => router.back()} className="text-xl">←</button>
          <h1 className="font-galey font-bold">{balade.titre}</h1>
        </div>
      </div>
      <div className="max-w-2xl mx-auto px-4 py-6">
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          {cards.map(([label, value, color]) => (
            <div key={label} className="bg-white rounded-2xl p-4">
              <p className="font-galey font-extrabold text-xl" style={{ color }}>{value}</p>
              <p className="text-xs font-galey text-gray-500">{label}</p>
            </div>
          ))}
        </div>
        {avis.length > 0 && (
          <div className="mt-6">
            <p className="font-galey font-bold text-sm mb-2">Avis des joueurs</p>
            {avis.map(a => (
              <div key={a.id} className="bg-white rounded-xl p-3 mb-2">
                <div className="text-amber-500 text-sm">{'⭐'.repeat(a.note)}</div>
                {a.commentaire && <p className="text-sm font-galey text-gray-600">{a.commentaire}</p>}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
