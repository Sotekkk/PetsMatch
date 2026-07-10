'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Balade { id: string; titre: string; statut: string; cover_url?: string; nb_joueurs?: number; }

const STATUT_LABELS: Record<string, { label: string; color: string }> = {
  brouillon: { label: 'Brouillon', color: 'bg-gray-100 text-gray-600' },
  publie: { label: 'Publié', color: 'bg-green-100 text-green-700' },
  desactive: { label: 'Désactivé', color: 'bg-orange-100 text-orange-700' },
};

export default function MesParcoursPage() {
  const { user } = useAuth();
  const [parcours, setParcours] = useState<Balade[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    supabase.from('balades_ludiques').select('id, titre, statut, cover_url, nb_joueurs')
      .eq('createur_uid', user.uid).neq('statut', 'supprime').order('created_at', { ascending: false })
      .then(({ data }) => { setParcours((data ?? []) as Balade[]); setLoading(false); });
  }, [user]);

  return (
    <div className="min-h-screen bg-[#F8F8F6]">
      <div className="bg-teal-700 text-white px-4 py-6">
        <div className="max-w-2xl mx-auto flex items-center justify-between">
          <h1 className="text-xl font-bold font-galey">Mes parcours</h1>
          <Link href="/balades-ludiques/creer" className="bg-orange-600 hover:bg-orange-700 rounded-full px-4 py-2 text-sm font-galey font-bold">
            + Créer
          </Link>
        </div>
      </div>
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-3">
        {loading ? (
          <p className="text-center text-gray-400 font-galey py-10">Chargement...</p>
        ) : parcours.length === 0 ? (
          <p className="text-center text-gray-400 font-galey py-10">Vous n&apos;avez pas encore créé de parcours</p>
        ) : parcours.map(p => {
          const st = STATUT_LABELS[p.statut] ?? { label: p.statut, color: 'bg-gray-100 text-gray-600' };
          return (
            <Link key={p.id} href={`/balades-ludiques/${p.id}`}
              className="flex items-center gap-3 bg-white rounded-2xl p-3 border border-gray-100 hover:shadow-sm">
              <div className="w-14 h-14 rounded-xl bg-[#EEF5EA] flex-shrink-0 overflow-hidden flex items-center justify-center">
                {p.cover_url ? <img src={p.cover_url} alt={p.titre} className="w-full h-full object-cover" /> : <span className="text-xl">🧭</span>}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-galey font-bold text-sm truncate">{p.titre}</p>
                <div className="flex items-center gap-2 mt-1">
                  <span className={`text-[10px] font-galey font-semibold px-2 py-0.5 rounded-full ${st.color}`}>{st.label}</span>
                  <span className="text-[11px] font-galey text-gray-400">{p.nb_joueurs ?? 0} joueur(s)</span>
                </div>
              </div>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
