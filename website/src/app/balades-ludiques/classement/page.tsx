'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

interface Explorateur { user_uid: string; xp_total: number; nb_parcours_completes: number; }
interface CreateurAgg { createur_uid: string; nb_completions: number; notes: number[]; }

export default function ClassementPage() {
  const router = useRouter();
  const [tab, setTab] = useState<'explorateurs' | 'createurs'>('explorateurs');
  const [explorateurs, setExplorateurs] = useState<Explorateur[]>([]);
  const [createurs, setCreateurs] = useState<CreateurAgg[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      supabase.from('joueurs_xp').select('*').order('xp_total', { ascending: false }).limit(50),
      supabase.from('balades_ludiques').select('createur_uid, nb_completions, note_moyenne').eq('statut', 'publie'),
    ]).then(([{ data: exp }, { data: bal }]) => {
      setExplorateurs((exp ?? []) as Explorateur[]);
      const parCreateur = new Map<string, CreateurAgg>();
      for (const row of bal ?? []) {
        const agg = parCreateur.get(row.createur_uid) ?? { createur_uid: row.createur_uid, nb_completions: 0, notes: [] };
        agg.nb_completions += row.nb_completions ?? 0;
        if (row.note_moyenne != null) agg.notes.push(row.note_moyenne);
        parCreateur.set(row.createur_uid, agg);
      }
      setCreateurs([...parCreateur.values()].sort((a, b) => b.nb_completions - a.nb_completions));
      setLoading(false);
    });
  }, []);

  function medaille(rang: number) {
    return rang === 1 ? '🥇' : rang === 2 ? '🥈' : rang === 3 ? '🥉' : null;
  }

  return (
    <div className="min-h-screen bg-[#F8F8F6]">
      <div className="bg-teal-700 text-white px-4 py-4">
        <div className="max-w-2xl mx-auto flex items-center gap-3">
          <button onClick={() => router.back()} className="text-xl">←</button>
          <h1 className="font-galey font-bold text-lg">Classement</h1>
        </div>
        <div className="max-w-2xl mx-auto flex gap-2 mt-4">
          {(['explorateurs', 'createurs'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-4 py-2 rounded-full text-sm font-galey font-semibold ${tab === t ? 'bg-white text-teal-700' : 'bg-white/15 text-white'}`}>
              {t === 'explorateurs' ? 'Explorateurs' : 'Créateurs'}
            </button>
          ))}
        </div>
      </div>
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-2">
        {loading ? (
          <p className="text-center text-gray-400 font-galey py-10">Chargement...</p>
        ) : tab === 'explorateurs' ? (
          explorateurs.length === 0 ? <p className="text-center text-gray-400 font-galey py-10">Aucun classement disponible</p> :
          explorateurs.map((e, i) => (
            <div key={e.user_uid} className="flex items-center gap-3 bg-white rounded-2xl p-3">
              <span className="w-8 h-8 rounded-full bg-teal-50 flex items-center justify-center font-galey text-sm text-teal-700">
                {medaille(i + 1) ?? i + 1}
              </span>
              <p className="flex-1 font-galey font-semibold text-sm">Explorateur {e.user_uid.slice(0, 6)}</p>
              <p className="font-galey font-extrabold text-orange-600">{e.xp_total} XP</p>
            </div>
          ))
        ) : (
          createurs.length === 0 ? <p className="text-center text-gray-400 font-galey py-10">Aucun classement disponible</p> :
          createurs.map((c, i) => {
            const moyenne = c.notes.length ? c.notes.reduce((a, b) => a + b, 0) / c.notes.length : null;
            return (
              <div key={c.createur_uid} className="flex items-center gap-3 bg-white rounded-2xl p-3">
                <span className="w-8 h-8 rounded-full bg-teal-50 flex items-center justify-center font-galey text-sm text-teal-700">
                  {medaille(i + 1) ?? i + 1}
                </span>
                <p className="flex-1 font-galey font-semibold text-sm">Créateur {c.createur_uid.slice(0, 6)}</p>
                {moyenne != null && <p className="font-galey text-xs text-gray-500 mr-2">⭐ {moyenne.toFixed(1)}</p>}
                <p className="font-galey font-extrabold text-green-700">{c.nb_completions} complétions</p>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
