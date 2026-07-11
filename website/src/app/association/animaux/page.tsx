'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Animal {
  id: string;
  nom: string;
  espece?: string;
  race?: string;
  sexe?: string;
  statut: string;
  fa_id?: string | null;
  date_naissance?: string | null;
  age_estime?: boolean;
  photo_url?: string | null;
  date_entree?: string | null;
  uid_eleveur?: string | null;
}

const DETENUS_STATUTS = [
  { key: 'tous',      label: 'Tous',        color: 'bg-gray-100 text-gray-700' },
  { key: 'en_soin',   label: 'En soin',     color: 'bg-orange-100 text-orange-700' },
  { key: 'disponible',label: 'Disponible',  color: 'bg-green-100 text-green-700' },
  { key: 'en_fa',     label: 'En FA',       color: 'bg-purple-100 text-purple-700' },
];

const ANCIEN_STATUTS = [
  { key: 'tous',      label: 'Tous',        color: 'bg-gray-100 text-gray-700' },
  { key: 'adopte',    label: 'Adopté',      color: 'bg-teal-100 text-teal-700' },
  { key: 'transfere', label: 'Transféré',   color: 'bg-blue-100 text-blue-700' },
  { key: 'decede',    label: 'Décédé',      color: 'bg-red-100 text-red-700' },
];

const ANCIENS_VALUES = new Set(['adopte', 'transfere', 'decede']);

const STATUT_MAP = Object.fromEntries([...DETENUS_STATUTS, ...ANCIEN_STATUTS].map(s => [s.key, s]));

// Statuts assignables manuellement — "en_fa" n'en fait plus partie : c'est un état
// indépendant porté par fa_id (un animal en FA reste "disponible" ou "en soin").
const ASSIGNABLE_STATUTS = ['en_soin', 'disponible', 'adopte', 'transfere', 'decede'];

export default function AnimauxAssoPage() {
  const { user, activeProfileId } = useAuth();
  const router = useRouter();
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [filtered, setFiltered] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'detenus' | 'ancien'>('detenus');
  const [filterStatut, setFilterStatut] = useState('tous');
  const [search, setSearch] = useState('');
  const [myUid, setMyUid] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    setMyUid(user.uid);
    const cols = 'id, nom, espece, race, sexe, statut, fa_id, date_naissance, age_estime, photo_url, date_entree, uid_eleveur';

    async function load() {
      const uid = user!.uid;
      const { data: ownedData } = await supabase.from('animaux').select(cols)
        .eq('uid_eleveur', uid).eq('is_association', true).order('nom');
      const ownedList = (ownedData ?? []) as Animal[];
      const ownedIds = new Set(ownedList.map(a => a.id));

      // Cessions reçues : un même uid Firebase peut porter plusieurs profils
      // (élevage + association). On ne garde que les animaux réellement reçus
      // par CE profil (animaux_proprietes.profile_id_proprio), sinon un animal
      // cédé au profil élevage apparaît aussi dans l'association.
      let receivedList: Animal[] = [];
      if (activeProfileId) {
        const { data: check } = await supabase.from('animaux_proprietes')
          .select('animal_id').eq('uid_proprio', uid)
          .not('profile_id_proprio', 'is', null).limit(1);
        if ((check ?? []).length > 0) {
          const { data: byProfile } = await supabase.from('animaux_proprietes')
            .select('animal_id').eq('uid_proprio', uid).eq('profile_id_proprio', activeProfileId);
          const ids = [...new Set((byProfile ?? []).map(r => r.animal_id as string))];
          if (ids.length > 0) {
            const { data } = await supabase.from('animaux').select(cols)
              .in('id', ids).order('date_entree', { ascending: false });
            receivedList = (data ?? []) as Animal[];
          }
        } else {
          const { data } = await supabase.from('animaux').select(cols)
            .eq('uid_acquereur', uid).order('date_entree', { ascending: false });
          receivedList = (data ?? []) as Animal[];
        }
      } else {
        const { data } = await supabase.from('animaux').select(cols)
          .eq('uid_acquereur', uid).order('date_entree', { ascending: false });
        receivedList = (data ?? []) as Animal[];
      }

      receivedList = receivedList.filter(a => !ownedIds.has(a.id));
      setAnimaux([...ownedList, ...receivedList]);
      setLoading(false);
    }
    load();
  }, [user, activeProfileId]);

  useEffect(() => {
    const statuts = tab === 'detenus' ? DETENUS_STATUTS : ANCIEN_STATUTS;
    if (!statuts.some(s => s.key === filterStatut)) setFilterStatut('tous');
  }, [tab, filterStatut]);

  useEffect(() => {
    setFiltered(
      animaux.filter(a => {
        const matchTab = tab === 'detenus' ? !ANCIENS_VALUES.has(a.statut) : ANCIENS_VALUES.has(a.statut);
        if (!matchTab) return false;
        const matchS = filterStatut === 'tous'
          || (filterStatut === 'en_fa' ? !!a.fa_id : a.statut === filterStatut);
        const q = search.toLowerCase();
        const matchQ = !q || a.nom?.toLowerCase().includes(q) || a.espece?.toLowerCase().includes(q) || a.race?.toLowerCase().includes(q);
        return matchS && matchQ;
      })
    );
  }, [animaux, tab, filterStatut, search]);

  const age = (dn: string | null | undefined, estime?: boolean) => {
    if (!dn) return '';
    const mois = Math.floor((Date.now() - new Date(dn).getTime()) / (1000 * 60 * 60 * 24 * 30));
    const val = mois < 12 ? `${mois}m` : `${Math.floor(mois / 12)}a`;
    return estime ? `~${val} (estimation)` : val;
  };

  const handleChangeStatut = async (animalId: string, newStatut: string) => {
    await supabase.from('animaux').update({ statut: newStatut }).eq('id', animalId);
    setAnimaux(prev => prev.map(a => a.id === animalId ? { ...a, statut: newStatut } : a));
  };

  const statuts = tab === 'detenus' ? DETENUS_STATUTS : ANCIEN_STATUTS;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Mes Animaux</h1>
        <Link href="/association/animaux/nouveau"
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Ajouter
        </Link>
      </div>

      {/* Onglets */}
      <div className="flex border-b border-gray-200">
        {(['detenus', 'ancien'] as const).map(t => (
          <button key={t} onClick={() => setTab(t)}
            className={`px-4 py-2 text-sm font-galey font-semibold border-b-2 transition-colors ${
              tab === t ? 'border-teal-700 text-teal-800' : 'border-transparent text-gray-400 hover:text-gray-600'
            }`}>
            {t === 'detenus' ? 'Nos protégés' : 'Ancien'}
          </button>
        ))}
      </div>

      {/* Search */}
      <input
        type="text"
        placeholder="Rechercher un animal…"
        value={search}
        onChange={e => setSearch(e.target.value)}
        className="w-full px-4 py-2.5 rounded-xl border border-gray-200 bg-white text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300"
      />

      {/* Filtres statut */}
      <div className="flex gap-2 flex-wrap">
        {statuts.map(s => (
          <button
            key={s.key}
            onClick={() => setFilterStatut(s.key)}
            className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold transition-all ${
              filterStatut === s.key ? s.color + ' ring-2 ring-offset-1 ring-current' : 'bg-white border border-gray-200 text-gray-500 hover:bg-gray-50'
            }`}
          >
            {s.label}
          </button>
        ))}
      </div>

      {/* Liste */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🐾</p>
          <p className="font-galey">Aucun animal trouvé</p>
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {filtered.map((a) => {
            const sc = STATUT_MAP[a.statut] ?? DETENUS_STATUTS[0];
            const isCession = !!myUid && a.uid_eleveur !== myUid;
            return (
              <div key={a.id} className="bg-white rounded-2xl shadow-sm overflow-hidden border border-gray-100 hover:border-teal-200 hover:shadow-md transition-all">
                <Link href={`/association/animaux/${a.id}`}>
                  <div className="aspect-square bg-gray-100 relative overflow-hidden">
                    {a.photo_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-4xl text-gray-300">🐾</div>
                    )}
                    <span className={`absolute top-2 right-2 text-xs font-galey font-bold px-2 py-0.5 rounded-full ${sc.color}`}>
                      {sc.label}
                    </span>
                    {a.fa_id && (
                      <span className="absolute top-2 left-2 text-xs font-galey font-bold px-2 py-0.5 rounded-full bg-purple-600 text-white">
                        🏡 FA
                      </span>
                    )}
                    {isCession && (
                      <span className="absolute bottom-2 left-2 text-xs font-galey font-bold px-2 py-0.5 rounded-full bg-black/60 text-white">
                        🤝 Cession
                      </span>
                    )}
                  </div>
                  <div className="p-3">
                    <div className="flex items-center justify-between">
                      <p className="font-bold font-galey text-sm text-gray-900 truncate">{a.nom}</p>
                      {age(a.date_naissance, a.age_estime) && <span className="text-xs text-gray-400">{age(a.date_naissance, a.age_estime)}</span>}
                    </div>
                    {(a.race || a.espece) && (
                      <p className="text-xs text-gray-500 font-galey truncate">{a.race || a.espece}</p>
                    )}
                  </div>
                </Link>
                {/* Changer statut */}
                <div className="px-3 pb-3 space-y-2">
                  <select
                    value={a.statut}
                    onChange={e => handleChangeStatut(a.id, e.target.value)}
                    className="w-full text-xs border border-gray-200 rounded-lg px-2 py-1 font-galey focus:outline-none focus:ring-1 focus:ring-teal-400"
                  >
                    {ASSIGNABLE_STATUTS.map(key => (
                      <option key={key} value={key}>{STATUT_MAP[key]?.label ?? key}</option>
                    ))}
                  </select>
                  {a.statut === 'disponible' && (
                    <button
                      onClick={() => router.push(`/association/annonces/creer?animalId=${a.id}`)}
                      className="w-full text-xs bg-teal-50 text-teal-700 border border-teal-200 rounded-lg px-2 py-1.5 font-galey font-semibold hover:bg-teal-100 transition-colors"
                    >
                      💚 Mettre en adoption
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
