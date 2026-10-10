'use client';

import { Suspense, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

import { changerStatutAnimalAsso, confirmerSortie } from '@/lib/statut-animal-asso';
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
  identification?: string | null;
}

const DETENUS_STATUTS = [
  { key: 'tous',      label: 'Tous',        color: 'bg-gray-100 text-gray-700' },
  { key: 'en_soin',   label: 'En soin',     color: 'bg-orange-100 text-orange-700' },
  { key: 'disponible',label: 'Disponible',  color: 'bg-green-100 text-green-700' },
  { key: 'en_fa',     label: 'En FA',       color: 'bg-purple-100 text-purple-700' },
];

const ANCIEN_STATUTS = [
  { key: 'tous',      label: 'Tous',        color: 'bg-gray-100 text-gray-700' },
  { key: 'adopte',    label: 'Adopté',      color: 'bg-teal-100 text-[#0C5C6C]' },
  { key: 'transfere', label: 'Transféré',   color: 'bg-blue-100 text-blue-700' },
  { key: 'sorti',     label: 'Cédé',        color: 'bg-amber-100 text-amber-700' },
  { key: 'decede',    label: 'Décédé',      color: 'bg-red-100 text-red-700' },
];

// 'sorti' = animal cédé via la fiche de cession (contrat / certificat).
const ANCIENS_VALUES = new Set(['adopte', 'transfere', 'sorti', 'decede']);

const STATUT_MAP = Object.fromEntries([...DETENUS_STATUTS, ...ANCIEN_STATUTS].map(s => [s.key, s]));

// Statuts assignables manuellement — "en_fa" n'en fait plus partie : c'est un état
// indépendant porté par fa_id (un animal en FA reste "disponible" ou "en soin").
const ASSIGNABLE_STATUTS = ['en_soin', 'disponible', 'adopte', 'transfere', 'decede'];

function AnimauxAssoPageInner() {
  const { user, activeProfileId } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  // Depuis le tableau de bord : ?statut=disponible|en_soin|en_fa|adopte — détermine
  // aussi l'onglet (detenus/ancien) puisque "adopte" vit dans l'onglet "ancien".
  const initialStatut = searchParams.get('statut');
  const initialTab: 'detenus' | 'ancien' = initialStatut && ANCIENS_VALUES.has(initialStatut) ? 'ancien' : 'detenus';
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [filtered, setFiltered] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'detenus' | 'ancien'>(initialTab);
  const [filterStatut, setFilterStatut] = useState(
    initialStatut && Object.prototype.hasOwnProperty.call(STATUT_MAP, initialStatut) ? initialStatut : 'tous'
  );
  const [search, setSearch] = useState('');
  const [myUid, setMyUid] = useState<string | null>(null);
  // Animaux que ce profil a cédés et qui ont été repris par une autre
  // asso / un élevage : consultables en lecture seule (fiche générique).
  const [anciensIds, setAnciensIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!user) return;
    setMyUid(user.uid);
    const cols = 'id, nom, espece, race, sexe, statut, fa_id, date_naissance, age_estime, photo_url, date_entree, uid_eleveur, identification';

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
      let fermes = new Set<string>();
      if (activeProfileId) {
        const { data: check } = await supabase.from('animaux_proprietes')
          .select('animal_id').eq('uid_proprio', uid)
          .not('profile_id_proprio', 'is', null).limit(1);
        if ((check ?? []).length > 0) {
          const { data: byProfile } = await supabase.from('animaux_proprietes')
            .select('animal_id, date_fin').eq('uid_proprio', uid).eq('profile_id_proprio', activeProfileId);
          const ids = [...new Set((byProfile ?? []).map(r => r.animal_id as string))];
          const ouverts = new Set((byProfile ?? []).filter(r => !r.date_fin).map(r => r.animal_id as string));
          fermes = new Set(ids.filter(i => !ouverts.has(i)));
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
      // Cédé puis repris par une autre structure : la fiche porte le statut
      // du nouveau détenteur (« disponible »…) → affiché « Transféré » ici.
      receivedList = receivedList.map(a => fermes.has(a.id) && !ANCIENS_VALUES.has(a.statut)
        ? { ...a, statut: 'transfere' } : a);
      setAnciensIds(fermes);
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
        const matchQ = !q || a.nom?.toLowerCase().includes(q) || a.espece?.toLowerCase().includes(q) || a.race?.toLowerCase().includes(q)
          || (!!a.identification && a.identification.replace(/\s/g, '').includes(q.replace(/\s/g, '')));
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

  // Miroir de l'appli : sortie → registre + propriété clôturée (statut-animal-asso).
  const handleChangeStatut = async (animalId: string, newStatut: string) => {
    const animal = animaux.find(x => x.id === animalId);
    if (!user || !confirmerSortie(newStatut)) return;
    try {
      await changerStatutAnimalAsso(animalId, animal?.statut, newStatut, animal?.uid_eleveur ?? user.uid);
      setAnimaux(prev => prev.map(a => a.id === animalId ? { ...a, statut: newStatut } : a));
    } catch (e) {
      alert(`Erreur : ${(e as Error).message}`);
    }
  };

  const statuts = tab === 'detenus' ? DETENUS_STATUTS : ANCIEN_STATUTS;
  const nbDetenus = animaux.filter(a => !ANCIENS_VALUES.has(a.statut)).length;
  const nbAnciens = animaux.length - nbDetenus;

  return (
    <div className="max-w-5xl mx-auto" style={{ fontFamily: 'Galey, sans-serif' }}>
      {/* En-tête */}
      <div className="flex items-start justify-between gap-3 mb-5">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]">Mes animaux</h1>
          <p className="text-gray-500 text-sm mt-1">{nbDetenus} protégé{nbDetenus !== 1 ? 's' : ''} · {animaux.length} animal{animaux.length !== 1 ? 'aux' : ''} au total</p>
        </div>
        <Link href="/association/animaux/nouveau"
          className="h-10 inline-flex items-center bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-4 rounded-lg transition-colors">
          + Ajouter
        </Link>
      </div>

      {/* Onglets */}
      <div className="flex gap-6 border-b border-gray-200 mb-4 overflow-x-auto" role="tablist">
        {(['detenus', 'ancien'] as const).map(t => (
          <button key={t} role="tab" aria-selected={tab === t} onClick={() => setTab(t)}
            className={`py-3 -mb-px border-b-2 text-sm font-semibold whitespace-nowrap transition-colors ${
              tab === t ? 'border-[#0C5C6C] text-[#0C5C6C]' : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}>
            {t === 'detenus' ? `Nos protégés · ${nbDetenus}` : `Anciens · ${nbAnciens}`}
          </button>
        ))}
      </div>

      {/* Recherche + statut */}
      <div className="flex flex-col sm:flex-row gap-2 mb-4">
        <label className="relative flex-1 min-w-0">
          <span className="sr-only">Rechercher un animal</span>
          <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden>
            <path strokeLinecap="round" d="M21 21l-5.2-5.2m0 0A7.5 7.5 0 105.2 5.2a7.5 7.5 0 0010.6 10.6z" />
          </svg>
          <input type="search" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher par nom, race ou n° de puce"
            className="w-full h-10 pl-9 pr-3 rounded-lg border border-gray-300 bg-white text-sm focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        <select value={filterStatut} aria-label="Statut" onChange={e => setFilterStatut(e.target.value)}
          className="h-10 sm:w-56 rounded-lg border border-gray-300 bg-white px-3 text-sm text-[#1F2A2E] focus:outline-none focus:border-[#0C5C6C]">
          {statuts.map(s => <option key={s.key} value={s.key}>{s.key === 'tous' ? 'Tous les statuts' : s.label}</option>)}
        </select>
      </div>

      {/* Liste */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-14 bg-white border border-gray-200 rounded-lg">
          <p className="text-sm text-gray-500">Aucun animal trouvé.</p>
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {filtered.map((a) => {
            const sc = STATUT_MAP[a.statut] ?? DETENUS_STATUTS[0];
            const isCession = !!myUid && a.uid_eleveur !== myUid;
            return (
              <div key={a.id} className="bg-white rounded-lg overflow-hidden border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all flex flex-col">
                <Link href={anciensIds.has(a.id) || isCession ? `/mes-animaux/${a.id}` : `/association/animaux/${a.id}`}>
                  <div className="aspect-square bg-[#F3F4F6] relative overflow-hidden">
                    {a.photo_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-gray-300">
                        <svg width="40" height="40" viewBox="0 0 24 24" fill="currentColor" aria-hidden><ellipse cx="12" cy="16.5" rx="4.2" ry="3.4" /><circle cx="6.5" cy="10.5" r="1.8" /><circle cx="9.8" cy="6.5" r="1.8" /><circle cx="14.2" cy="6.5" r="1.8" /><circle cx="17.5" cy="10.5" r="1.8" /></svg>
                      </div>
                    )}
                    <span className={`absolute top-2 right-2 text-xs font-semibold px-2 py-0.5 rounded-full ${sc.color}`}>
                      {sc.label}
                    </span>
                    {a.fa_id && (
                      <span className="absolute top-2 left-2 text-xs font-semibold px-2 py-0.5 rounded-full bg-purple-100 text-purple-700">
                        En FA
                      </span>
                    )}
                    {isCession && (
                      <span className="absolute bottom-2 left-2 text-xs font-semibold px-2 py-0.5 rounded-full bg-white/95 text-[#1F2A2E] border border-gray-200">
                        Cession
                      </span>
                    )}
                  </div>
                  <div className="p-3">
                    <div className="flex items-center justify-between gap-2">
                      <p className="font-semibold text-sm text-[#1F2A2E] truncate">{a.nom}</p>
                      {age(a.date_naissance, a.age_estime) && <span className="text-xs text-gray-500 flex-shrink-0">{age(a.date_naissance, a.age_estime)}</span>}
                    </div>
                    {(a.race || a.espece) && (
                      <p className="text-xs text-gray-500 truncate capitalize">{a.race || a.espece}</p>
                    )}
                  </div>
                </Link>
                {/* Changer statut */}
                <div className="px-3 pb-3 space-y-2 mt-auto">
                  <select
                    value={a.statut} aria-label="Changer le statut"
                    onChange={e => handleChangeStatut(a.id, e.target.value)}
                    className="w-full h-9 text-xs border border-gray-300 rounded-lg px-2 bg-white focus:outline-none focus:border-[#0C5C6C]"
                  >
                    {ASSIGNABLE_STATUTS.map(key => (
                      <option key={key} value={key}>{STATUT_MAP[key]?.label ?? key}</option>
                    ))}
                  </select>
                  {a.statut === 'disponible' && (
                    <button
                      onClick={() => router.push(`/association/annonces/creer?animalId=${a.id}`)}
                      className="w-full h-9 text-xs bg-white text-[#0C5C6C] border border-[#0C5C6C]/40 rounded-lg px-2 font-semibold hover:bg-[#E8F4F6] transition-colors"
                    >
                      Mettre en adoption
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

export default function AnimauxAssoPage() {
  return (
    <Suspense fallback={null}>
      <AnimauxAssoPageInner />
    </Suspense>
  );
}
