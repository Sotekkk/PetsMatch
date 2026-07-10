'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { ESPECES, DIFFICULTES, especeEmoji, difficulteLabel, difficulteColor, dureeLabel } from './shared';

const BaladesLudiquesMap = dynamic(() => import('@/components/BaladesLudiquesMap'), {
  ssr: false,
  loading: () => <div className="flex items-center justify-center h-full bg-gray-100">
    <div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" /></div>,
});

interface Balade {
  id: string; titre: string; ville?: string; cover_url?: string;
  espece_cible?: string; difficulte?: string; duree_min?: number; distance_km?: number;
  gratuit?: boolean; prix?: number; note_moyenne?: number; nb_avis?: number;
  famille?: boolean; sportif?: boolean; accessible_pmr?: boolean;
  type_evenement?: string; event_debut?: string; event_fin?: string;
  lat_depart: number; lng_depart: number;
}

export default function BaladesLudiquesPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [balades, setBalades] = useState<Balade[]>([]);
  const [loading, setLoading] = useState(true);
  const [mapView, setMapView] = useState(false);
  const [search, setSearch] = useState('');
  const [espece, setEspece] = useState('tous');
  const [difficulte, setDifficulte] = useState<string | null>(null);
  const [dureeMax, setDureeMax] = useState<number | null>(null);
  const [famille, setFamille] = useState(false);
  const [sportif, setSportif] = useState(false);
  const [pmr, setPmr] = useState(false);
  const [gratuit, setGratuit] = useState(false);

  useEffect(() => {
    supabase.from('balades_ludiques').select('*').eq('statut', 'publie').order('created_at', { ascending: false })
      .then(({ data }) => { setBalades((data ?? []) as Balade[]); setLoading(false); });
  }, []);

  const filtered = balades.filter(b => {
    if (espece !== 'tous' && b.espece_cible !== 'tous' && b.espece_cible !== espece) return false;
    if (difficulte && b.difficulte !== difficulte) return false;
    if (dureeMax != null && (b.duree_min == null || b.duree_min > dureeMax)) return false;
    if (famille && !b.famille) return false;
    if (sportif && !b.sportif) return false;
    if (pmr && !b.accessible_pmr) return false;
    if (gratuit && !b.gratuit) return false;
    if (search) {
      const q = search.toLowerCase();
      if (!b.titre?.toLowerCase().includes(q) && !b.ville?.toLowerCase().includes(q)) return false;
    }
    return true;
  });

  const now = new Date();
  const evenementsOfficiels = balades.filter(b => {
    if (!b.type_evenement || b.type_evenement === 'communautaire') return false;
    if (!b.event_debut || !b.event_fin) return false;
    const d = new Date(b.event_debut), f = new Date(b.event_fin);
    return now >= d && now <= f;
  });

  return (
    <div className="min-h-screen bg-[#F8F8F6]">
      <div className="bg-teal-700 text-white px-4 py-6">
        <div className="max-w-4xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold font-galey">🧭 Balades ludiques</h1>
            <p className="text-white/70 text-sm font-galey mt-1">Chasses au trésor et parcours à défis avec votre animal</p>
          </div>
          <div className="flex gap-2">
            <Link href="/balades-ludiques/classement" className="bg-white/15 hover:bg-white/25 rounded-full px-3 py-2 text-xs font-galey font-semibold">
              🏆 Classement
            </Link>
            {user && (
              <Link href="/balades-ludiques/mes-parcours" className="bg-white/15 hover:bg-white/25 rounded-full px-3 py-2 text-xs font-galey font-semibold">
                📋 Mes parcours
              </Link>
            )}
          </div>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-4 space-y-4">
        {evenementsOfficiels.length > 0 && (
          <div className="bg-gradient-to-r from-orange-600 to-orange-500 text-white rounded-2xl p-4 flex items-center gap-3">
            <span className="text-2xl">🏆</span>
            <p className="font-galey font-bold text-sm">{evenementsOfficiels.length} chasse(s) au trésor officielle(s) en cours !</p>
          </div>
        )}

        <div className="flex gap-2">
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Rechercher un parcours, une ville..."
            className="flex-1 px-4 py-2.5 rounded-full border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400 bg-white" />
          <button onClick={() => setMapView(v => !v)}
            className="px-4 py-2.5 rounded-full bg-white border border-gray-200 text-sm font-galey">
            {mapView ? '📋 Liste' : '🗺️ Carte'}
          </button>
          {user && (
            <Link href="/balades-ludiques/creer" className="px-4 py-2.5 rounded-full bg-orange-600 text-white text-sm font-galey font-bold hover:bg-orange-700">
              + Créer
            </Link>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          {ESPECES.map(e => (
            <button key={e.value} onClick={() => setEspece(e.value)}
              className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
                espece === e.value ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'}`}>
              {e.emoji} {e.label}
            </button>
          ))}
          <span className="w-px bg-gray-300 mx-1" />
          {DIFFICULTES.map(d => (
            <button key={d.value} onClick={() => setDifficulte(difficulte === d.value ? null : d.value)}
              style={difficulte === d.value ? { background: d.color, borderColor: d.color } : {}}
              className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
                difficulte === d.value ? 'text-white' : 'bg-white text-gray-600 border-gray-200'}`}>
              {d.label}
            </button>
          ))}
          <span className="w-px bg-gray-300 mx-1" />
          {([[30, '< 30 min'], [60, '< 1h'], [120, '< 2h']] as [number, string][]).map(([max, label]) => (
            <button key={max} onClick={() => setDureeMax(dureeMax === max ? null : max)}
              className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
                dureeMax === max ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'}`}>
              {label}
            </button>
          ))}
          {([
            ['famille', '👨‍👩‍👧 Famille', famille, setFamille],
            ['sportif', '🏃 Sportif', sportif, setSportif],
            ['pmr', '♿ PMR', pmr, setPmr],
            ['gratuit', '🆓 Gratuit', gratuit, setGratuit],
          ] as [string, string, boolean, (v: boolean) => void][]).map(([key, label, value, setter]) => (
            <button key={key} onClick={() => setter(!value)}
              className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
                value ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'}`}>
              {label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="text-center py-20 text-gray-400 font-galey">Chargement...</div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-20 text-gray-400 font-galey">Aucun parcours trouvé</div>
        ) : mapView ? (
          <div className="h-[60vh] rounded-2xl overflow-hidden border border-gray-100">
            <BaladesLudiquesMap balades={filtered} onSelect={(id) => router.push(`/balades-ludiques/${id}`)} />
          </div>
        ) : (
          <div className="grid sm:grid-cols-2 gap-4">
            {filtered.map(b => (
              <Link key={b.id} href={`/balades-ludiques/${b.id}`}
                className="bg-white rounded-2xl overflow-hidden border border-gray-100 shadow-sm hover:shadow-md transition-shadow flex">
                <div className="w-28 h-28 bg-[#EEF5EA] flex-shrink-0 flex items-center justify-center overflow-hidden">
                  {b.cover_url ? <img src={b.cover_url} alt={b.titre} className="w-full h-full object-cover" /> : <span className="text-3xl">🧭</span>}
                </div>
                <div className="p-3 flex-1 min-w-0">
                  <div className="flex items-center gap-1">
                    {b.type_evenement && b.type_evenement !== 'communautaire' && <span className="text-xs">🏆</span>}
                    <p className="font-galey font-bold text-sm text-gray-800 truncate">{b.titre}</p>
                  </div>
                  <p className="text-xs text-gray-400 font-galey">{especeEmoji(b.espece_cible)} {b.ville}</p>
                  <div className="flex flex-wrap gap-1 mt-2">
                    <span className="text-[10px] font-galey font-semibold px-2 py-0.5 rounded-full"
                      style={{ background: `${difficulteColor(b.difficulte)}20`, color: difficulteColor(b.difficulte) }}>
                      {difficulteLabel(b.difficulte)}
                    </span>
                    {b.duree_min && <span className="text-[10px] font-galey text-gray-500 px-2 py-0.5 bg-gray-100 rounded-full">{dureeLabel(b.duree_min)}</span>}
                    <span className="text-[10px] font-galey font-semibold px-2 py-0.5 bg-teal-50 text-teal-700 rounded-full">
                      {b.gratuit ? 'Gratuit' : `${b.prix} €`}
                    </span>
                    {b.note_moyenne && <span className="text-[10px] font-galey text-amber-600 px-2 py-0.5 bg-amber-50 rounded-full">⭐ {b.note_moyenne}</span>}
                  </div>
                </div>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
