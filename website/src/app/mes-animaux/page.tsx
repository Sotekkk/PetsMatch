'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { thumbUrl } from '@/lib/upload-media';

interface Animal {
  id: string;
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  identification?: string;
  date_naissance?: string;
  photo_url?: string;
  statut?: string;
  date_entree?: string;
  date_sortie?: string;
  portee_id?: string;
  intervalle_chaleurs_jours?: number | null;
}

const CHALEURS_INTERVAL_WEB: Record<string, number> = {
  chien: 182, chat: 21, lapin: 14, ovin: 17, caprin: 21, porcin: 21, cheval: 21,
};

const SPECIES = [
  { value: 'tous',   label: 'Tous',    color: '#1F2A2E' },
  { value: 'chien',  label: 'Chiens',  color: '#6E9E57' },
  { value: 'chat',   label: 'Chats',   color: '#0C5C6C' },
  { value: 'cheval', label: 'Chevaux', color: '#5B8648' },
  { value: 'lapin',  label: 'Lapins',  color: '#E08080' },
  { value: 'ovin',   label: 'Ovins',   color: '#5F9EAA' },
  { value: 'caprin', label: 'Caprins', color: '#8D6E63' },
  { value: 'porcin', label: 'Porcins', color: '#E25C5C' },
  { value: 'nac',    label: 'NAC',     color: '#F4B400' },
  { value: 'oiseau', label: 'Oiseaux', color: '#26A69A' },
  { value: 'autre',  label: 'Autres',  color: '#6F767B' },
];

const SPECIES_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷', autre: '🐾',
};

function speciesLabel(v: string) {
  return SPECIES.find(s => s.value === v)?.label ?? v;
}

function formatDate(d?: string) {
  if (!d) return '';
  return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: '2-digit' });
}

function Chip({
  label, active, color, onClick, emoji,
}: { label: string; active: boolean; color: string; onClick: () => void; emoji?: string }) {
  return (
    <button
      onClick={onClick}
      style={active ? { backgroundColor: color, borderColor: color, color: '#fff' } : { borderColor: '#d1d5db', color: '#374151' }}
      className="flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-medium transition-all">
      {emoji && <span>{emoji}</span>}
      {label}
    </button>
  );
}

function AnimalCard({ a, tab, showPorteeBadge = false, chaleurFlag = false, gestanteFlag = false, onDelete }: {
  a: Animal; tab: 'presents' | 'anciens'; showPorteeBadge?: boolean;
  chaleurFlag?: boolean; gestanteFlag?: boolean; onDelete?: () => void;
}) {
  const espColor = SPECIES.find(s => s.value === a.espece)?.color ?? '#6F767B';
  const isMale   = (a.sexe ?? '').toLowerCase().startsWith('m');
  const isFemale = (a.sexe ?? '').toLowerCase().startsWith('f');
  const photo    = a.photo_url ? thumbUrl(a.photo_url, 400, 75, 'contain') : undefined;
  const [confirmDelete, setConfirmDelete] = useState(false);

  return (
    <div className="relative group">
      <Link href={`/mes-animaux/${a.id}`}
        className="bg-white rounded-2xl shadow-sm overflow-hidden hover:shadow-md transition-all block">
        <div className="aspect-square relative overflow-hidden"
          style={{ background: espColor + '18' }}>
          {photo
            ? <img src={photo} alt={a.nom ?? ''} className="w-full h-full object-contain" />
            : <div className="w-full h-full flex items-center justify-center text-5xl">
                {SPECIES_EMOJI[a.espece ?? ''] ?? '🐾'}
              </div>}
          {tab === 'anciens' && (a.statut === 'sorti' || a.statut === 'decede') && (
            <span className={`absolute top-2 right-2 text-white text-[10px] font-bold px-2 py-0.5 rounded-lg ${
              a.statut === 'decede' ? 'bg-red-500' : 'bg-[#0C5C6C]'
            }`}>
              {a.statut === 'decede' ? 'Décédé' : 'Sorti'}
            </span>
          )}
          {showPorteeBadge && a.portee_id && (
            <span className="absolute top-2 left-2 text-white text-[9px] font-bold px-1.5 py-0.5 rounded-lg bg-[#0C5C6C]/85">
              🐣 Portée
            </span>
          )}
          {(gestanteFlag || chaleurFlag) && (
            <div className="absolute bottom-2 left-2 flex flex-col gap-1">
              {gestanteFlag && (
                <span className="text-white text-[9px] font-bold px-1.5 py-0.5 rounded-lg bg-[#6E9E57]/90">
                  🤰 Gestante
                </span>
              )}
              {chaleurFlag && (
                <span className="text-white text-[9px] font-bold px-1.5 py-0.5 rounded-lg bg-pink-400/90">
                  🌸 Chaleurs
                </span>
              )}
            </div>
          )}
        </div>
        <div className="p-3">
          <p className="font-bold text-[#1F2A2E] text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
            {a.nom ?? 'Sans nom'}
          </p>
          {a.race && <p className="text-[#6F767B] text-xs truncate mt-0.5">{a.race}</p>}
          <div className="flex items-center gap-1 mt-2 flex-wrap">
            <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full"
              style={{ background: espColor + '20', color: espColor }}>
              {SPECIES_EMOJI[a.espece ?? ''] ?? '🐾'} {speciesLabel(a.espece ?? '')}
            </span>
            {(isMale || isFemale) && (
              <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-[#5F9EAA]/20 text-[#5F9EAA]">
                {isMale ? '♂ Mâle' : '♀ Femelle'}
              </span>
            )}
          </div>
        </div>
      </Link>
      {onDelete && (
        <button
          onClick={e => { e.preventDefault(); setConfirmDelete(true); }}
          className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity bg-red-500 text-white rounded-full w-7 h-7 flex items-center justify-center shadow-md text-xs"
          title="Supprimer">
          ✕
        </button>
      )}
      {confirmDelete && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setConfirmDelete(false)}>
          <div className="bg-white rounded-2xl p-6 shadow-xl max-w-sm w-full mx-4" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E] text-base mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              Supprimer cet animal ?
            </p>
            <p className="text-sm text-gray-500 mb-5">
              La fiche de <strong>{a.nom ?? 'cet animal'}</strong> sera définitivement supprimée.
            </p>
            <div className="flex gap-3 justify-end">
              <button onClick={() => setConfirmDelete(false)}
                className="px-4 py-2 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50">
                Annuler
              </button>
              <button onClick={() => { setConfirmDelete(false); onDelete?.(); }}
                className="px-4 py-2 rounded-xl text-sm text-white bg-red-500 hover:bg-red-600 font-semibold">
                Supprimer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function MesAnimauxPage() {
  const { user, userData, loading } = useAuth();
  const router = useRouter();

  const isEleveur = userData?.isElevage === true;

  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [fetching, setFetching] = useState(true);
  const [chaleurFlags, setChaleurFlags] = useState<Record<string, boolean>>({});
  const [gestanteFlags, setGestanteFlags] = useState<Record<string, boolean>>({});
  const [tab, setTab] = useState<'presents' | 'anciens'>('presents');

  // Filtres présents
  const [filtreEspece, setFiltreEspece] = useState('tous');
  const [filtreSexe, setFiltreSexe] = useState('tous');
  const [filtreRace, setFiltreRace] = useState('');
  const [filtrePortee, setFiltrePortee] = useState(false);

  // Filtres anciens
  const [anciensEspece, setAnciensEspece] = useState('tous');
  const [anciensStatut, setAnciensStatut] = useState('tous');

  // Recherche
  const [search, setSearch] = useState('');

  // UI state
  const [filterOpen, setFilterOpen] = useState(false);
  const [addMenuOpen, setAddMenuOpen] = useState(false);
  const addMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (addMenuRef.current && !addMenuRef.current.contains(e.target as Node)) {
        setAddMenuOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    setFetching(true);
    const query = isEleveur
      ? supabase.from('animaux').select('*').eq('uid_eleveur', user.uid).order('nom', { ascending: true })
      : supabase.from('animaux').select('*').or(`uid_eleveur.eq.${user.uid},uid_proprietaire.eq.${user.uid}`).order('nom', { ascending: true });

    query.then(async ({ data }) => {
      const list = (data ?? []) as Animal[];
      setAnimaux(list);
      setFetching(false);

      // Calcul flags chaleurs et gestante pour les femelles présentes
      const femIds = list
        .filter(a => (a.sexe ?? '').startsWith('f') && a.statut !== 'sorti' && a.statut !== 'decede')
        .map(a => a.id);

      if (femIds.length === 0) return;

      const [{ data: chaleurs }, { data: gests }] = await Promise.all([
        supabase.from('chaleurs').select('animal_id, date').in('animal_id', femIds).order('date', { ascending: false }),
        supabase.from('gestations').select('animal_id').in('animal_id', femIds).eq('gestation_confirmee', true).is('date_naissance', null),
      ]);

      const lastChaleur: Record<string, Date> = {};
      for (const c of (chaleurs ?? [])) {
        const aid = c.animal_id as string;
        if (!lastChaleur[aid]) { const d = new Date(c.date as string); if (!isNaN(d.getTime())) lastChaleur[aid] = d; }
      }

      const cFlags: Record<string, boolean> = {};
      const now = new Date();
      for (const a of list) {
        if (!(a.id in lastChaleur)) continue;
        const interval = (a.intervalle_chaleurs_jours ?? CHALEURS_INTERVAL_WEB[a.espece ?? ''] ?? 0);
        if (!interval) continue;
        const next = new Date(lastChaleur[a.id].getTime() + interval * 86400000);
        if ((next.getTime() - now.getTime()) / 86400000 <= 7) cFlags[a.id] = true;
      }

      const gFlags: Record<string, boolean> = {};
      for (const g of (gests ?? [])) gFlags[g.animal_id as string] = true;

      setChaleurFlags(cFlags);
      setGestanteFlags(gFlags);
    });
  }, [user, isEleveur]);

  async function deleteAnimal(id: string) {
    await supabase.from('animaux').delete().eq('id', id);
    setAnimaux(prev => prev.filter(a => a.id !== id));
  }

  if (loading || !user) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  // Séparer présents / anciens
  const presents = animaux.filter(a => {
    const s = a.statut ?? 'present';
    return s !== 'sorti' && s !== 'decede';
  });
  const anciens = animaux.filter(a => a.statut === 'sorti' || a.statut === 'decede');

  // Espèces disponibles dans chaque groupe
  const especesPresents = [...new Set(presents.map(a => a.espece).filter(Boolean))] as string[];
  const especesAnciens  = [...new Set(anciens.map(a => a.espece).filter(Boolean))] as string[];

  // Races disponibles selon espèce sélectionnée (présents)
  const racesDisponibles = filtreEspece !== 'tous'
    ? [...new Set(presents.filter(a => a.espece === filtreEspece).map(a => a.race).filter(Boolean))] as string[]
    : [];

  const searchLower = search.toLowerCase().trim();

  // Filtrage présents
  const filteredPresents = presents.filter(a => {
    if (filtreEspece !== 'tous' && a.espece !== filtreEspece) return false;
    if (filtreSexe !== 'tous') {
      const s = (a.sexe ?? '').toLowerCase();
      if (filtreSexe === 'male' && !s.startsWith('m')) return false;
      if (filtreSexe === 'femelle' && !s.startsWith('f')) return false;
    }
    if (filtreRace && a.race !== filtreRace) return false;
    if (filtrePortee && !a.portee_id) return false;
    if (searchLower) {
      const nom  = (a.nom            ?? '').toLowerCase();
      const puce = (a.identification ?? '').toLowerCase();
      if (!nom.includes(searchLower) && !puce.includes(searchLower)) return false;
    }
    return true;
  });

  // Filtrage anciens
  const filteredAnciens = anciens.filter(a => {
    if (anciensEspece !== 'tous' && a.espece !== anciensEspece) return false;
    if (anciensStatut !== 'tous' && a.statut !== anciensStatut) return false;
    if (searchLower) {
      const nom  = (a.nom            ?? '').toLowerCase();
      const puce = (a.identification ?? '').toLowerCase();
      if (!nom.includes(searchLower) && !puce.includes(searchLower)) return false;
    }
    return true;
  });

  const currentList = tab === 'presents' ? filteredPresents : filteredAnciens;

  const activeFilterCount = tab === 'presents'
    ? (filtreEspece !== 'tous' ? 1 : 0) + (filtreSexe !== 'tous' ? 1 : 0) + (filtreRace ? 1 : 0) + (filtrePortee ? 1 : 0)
    : (anciensEspece !== 'tous' ? 1 : 0) + (anciensStatut !== 'tous' ? 1 : 0);

  // Groupement par portée
  const porteeGroups: Map<string, Animal[]> = new Map();
  if (filtrePortee) {
    for (const a of filteredPresents) {
      if (!a.portee_id) continue;
      const group = porteeGroups.get(a.portee_id) ?? [];
      group.push(a);
      porteeGroups.set(a.portee_id, group);
    }
    // Trier les groupes par date de naissance décroissante
    const sorted = [...porteeGroups.entries()].sort((a, b) => {
      const da = new Date(a[1][0]?.date_naissance ?? '').getTime();
      const db = new Date(b[1][0]?.date_naissance ?? '').getTime();
      return db - da;
    });
    porteeGroups.clear();
    for (const [k, v] of sorted) porteeGroups.set(k, v);
  }

  function resetFilters() {
    if (tab === 'presents') {
      setFiltreEspece('tous'); setFiltreSexe('tous'); setFiltreRace(''); setFiltrePortee(false);
    } else {
      setAnciensEspece('tous'); setAnciensStatut('tous');
    }
  }

  return (
    <div className="max-w-5xl mx-auto px-4 py-8">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes Animaux
          </h1>
          <p className="text-gray-500 text-sm mt-0.5">
            {presents.length} présent{presents.length !== 1 ? 's' : ''} · {animaux.length} au total
          </p>
        </div>
        {isEleveur && (
          <div className="relative" ref={addMenuRef}>
            <button
              onClick={() => setAddMenuOpen(v => !v)}
              className="bg-[#6E9E57] hover:bg-[#5A8A45] text-white text-sm font-semibold px-4 py-2 rounded-full transition-colors flex items-center gap-1">
              + Ajouter
              <svg className={`w-3 h-3 transition-transform ${addMenuOpen ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M19 9l-7 7-7-7" />
              </svg>
            </button>
            {addMenuOpen && (
              <div className="absolute right-0 top-full mt-2 w-60 bg-white rounded-2xl shadow-lg border border-gray-100 overflow-hidden z-20">
                <Link href="/mes-animaux/ajouter"
                  onClick={() => setAddMenuOpen(false)}
                  className="flex items-center gap-3 px-4 py-3.5 hover:bg-gray-50 transition-colors">
                  <div className="w-9 h-9 rounded-xl flex items-center justify-center text-xl"
                    style={{ background: '#6E9E5720' }}>🐾</div>
                  <div>
                    <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Ajouter un animal</p>
                    <p className="text-xs text-gray-400">Fiche individuelle</p>
                  </div>
                </Link>
                <div className="h-px bg-gray-100 mx-3" />
                <Link href="/mes-animaux/portee"
                  onClick={() => setAddMenuOpen(false)}
                  className="flex items-center gap-3 px-4 py-3.5 hover:bg-gray-50 transition-colors">
                  <div className="w-9 h-9 rounded-xl flex items-center justify-center text-xl"
                    style={{ background: '#0C5C6C20' }}>🐣</div>
                  <div>
                    <p className="text-sm font-semibold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>Charger une portée</p>
                    <p className="text-xs text-gray-400">Plusieurs animaux d&apos;un coup</p>
                  </div>
                </Link>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Tabs (éleveur uniquement) */}
      {isEleveur && (
        <div className="flex gap-1 bg-gray-100 rounded-xl p-1 mb-4">
          {(['presents', 'anciens'] as const).map((t) => (
            <button key={t} onClick={() => { setTab(t); setFilterOpen(false); }}
              className={`flex-1 py-2 text-sm font-semibold rounded-lg transition-all ${
                tab === t ? 'bg-white text-[#0C5C6C] shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}>
              {t === 'presents'
                ? `Présents (${presents.length})`
                : `Anciens (${anciens.length})`}
            </button>
          ))}
        </div>
      )}

      {/* Barre de recherche */}
      <div className="relative mb-3">
        <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[#6E9E57]">🔍</span>
        <input
          type="text"
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Nom ou numéro de puce..."
          className="w-full pl-9 pr-8 py-2.5 rounded-xl border border-gray-200 bg-[#F8F8F6] text-sm focus:outline-none focus:border-[#6E9E57] transition-colors"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />
        {search && (
          <button onClick={() => setSearch('')}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 text-sm">
            ✕
          </button>
        )}
      </div>

      {/* Barre filtres */}
      <div className="flex items-center gap-2 mb-4">
        <button
          onClick={() => setFilterOpen(!filterOpen)}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-sm font-medium transition-colors ${
            activeFilterCount > 0
              ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white'
              : 'border-gray-300 text-gray-600 hover:border-gray-400'
          }`}>
          ⚙️ Filtres
          {activeFilterCount > 0 && (
            <span className="bg-white text-[#0C5C6C] rounded-full text-xs w-4 h-4 flex items-center justify-center font-bold">
              {activeFilterCount}
            </span>
          )}
        </button>
        {activeFilterCount > 0 && (
          <button onClick={resetFilters}
            className="text-xs text-[#6E9E57] font-medium hover:underline">
            Réinitialiser
          </button>
        )}
      </div>

      {/* Panel filtres */}
      {filterOpen && (
        <div className="bg-white border border-gray-200 rounded-2xl p-4 mb-4 space-y-4">
          {tab === 'presents' ? (
            <>
              {/* Espèce */}
              <div>
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Espèce</p>
                <div className="flex flex-wrap gap-2">
                  {SPECIES.filter(s => s.value === 'tous' || especesPresents.includes(s.value)).map(sp => (
                    <Chip key={sp.value} label={sp.label} active={filtreEspece === sp.value}
                      color={sp.color} onClick={() => { setFiltreEspece(sp.value); setFiltreRace(''); }}
                      emoji={sp.value !== 'tous' ? (SPECIES_EMOJI[sp.value] ?? '') : undefined} />
                  ))}
                </div>
              </div>
              {/* Sexe */}
              <div>
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Sexe</p>
                <div className="flex gap-2">
                  {[{ v: 'tous', l: 'Tous' }, { v: 'male', l: '♂ Mâle' }, { v: 'femelle', l: '♀ Femelle' }].map(s => (
                    <Chip key={s.v} label={s.l} active={filtreSexe === s.v}
                      color="#0C5C6C" onClick={() => setFiltreSexe(s.v)} />
                  ))}
                </div>
              </div>
              {/* Race */}
              {racesDisponibles.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Race</p>
                  <div className="flex flex-wrap gap-2">
                    {racesDisponibles.map(r => (
                      <Chip key={r} label={r} active={filtreRace === r}
                        color="#0C5C6C" onClick={() => setFiltreRace(filtreRace === r ? '' : r)} />
                    ))}
                  </div>
                </div>
              )}
              {/* Portée */}
              <div>
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Portée</p>
                <Chip label="🐣 Portées uniquement" active={filtrePortee}
                  color="#0C5C6C" onClick={() => setFiltrePortee(v => !v)} />
              </div>
            </>
          ) : (
            <>
              {/* Espèce anciens */}
              <div>
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Espèce</p>
                <div className="flex flex-wrap gap-2">
                  {SPECIES.filter(s => s.value === 'tous' || especesAnciens.includes(s.value)).map(sp => (
                    <Chip key={sp.value} label={sp.label} active={anciensEspece === sp.value}
                      color={sp.color} onClick={() => setAnciensEspece(sp.value)}
                      emoji={sp.value !== 'tous' ? (SPECIES_EMOJI[sp.value] ?? '') : undefined} />
                  ))}
                </div>
              </div>
              {/* Statut anciens */}
              <div>
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Motif</p>
                <div className="flex gap-2">
                  {[{ v: 'tous', l: 'Tous' }, { v: 'sorti', l: 'Sorti / Vendu' }, { v: 'decede', l: 'Décédé' }].map(s => (
                    <Chip key={s.v} label={s.l} active={anciensStatut === s.v}
                      color="#0C5C6C" onClick={() => setAnciensStatut(s.v)} />
                  ))}
                </div>
              </div>
            </>
          )}
        </div>
      )}

      {/* Liste */}
      {fetching ? (
        <div className="flex justify-center py-16">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : currentList.length === 0 ? (
        <div className="flex flex-col items-center py-20 text-center">
          <span className="text-5xl mb-4">🐾</span>
          <p className="text-gray-500 font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>
            {tab === 'presents' ? 'Aucun animal présent' : 'Aucun ancien animal'}
          </p>
          <p className="text-gray-400 text-sm mt-1">
            {tab === 'presents' && animaux.length === 0
              ? 'Ajoutez votre premier animal'
              : 'Modifiez les filtres pour voir plus de résultats'}
          </p>
        </div>
      ) : filtrePortee && porteeGroups.size > 0 ? (
        <div className="space-y-6">
          {[...porteeGroups.entries()].map(([pid, members]) => {
            const first = members[0];
            const dn = first.date_naissance ? new Date(first.date_naissance).toLocaleDateString('fr-FR') : null;
            const race = first.race ?? '';
            const espece = first.espece ?? '';
            const espColor = SPECIES.find(s => s.value === espece)?.color ?? '#0C5C6C';
            return (
              <div key={pid}>
                <div className="flex items-center gap-3 px-4 py-3 rounded-xl mb-3"
                  style={{ background: '#0C5C6C0D', border: '1px solid #0C5C6C30' }}>
                  <span className="text-lg">🐣</span>
                  <div className="flex-1">
                    <p className="text-sm font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
                      Portée {race && <span>{race}</span>} {espece && <span>· {SPECIES_EMOJI[espece] ?? ''} {speciesLabel(espece)}</span>}
                    </p>
                    {dn && <p className="text-xs text-[#5F9EAA]">Nés le {dn}</p>}
                  </div>
                  <span className="text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C20] px-2 py-0.5 rounded-full">
                    {members.length}
                  </span>
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                  {members.map(a => <AnimalCard key={a.id} a={a} tab={tab} showPorteeBadge chaleurFlag={!!chaleurFlags[a.id]} gestanteFlag={!!gestanteFlags[a.id]} onDelete={() => deleteAnimal(a.id)} />)}
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          {currentList.map(a => <AnimalCard key={a.id} a={a} tab={tab} chaleurFlag={!!chaleurFlags[a.id]} gestanteFlag={!!gestanteFlags[a.id]} onDelete={() => deleteAnimal(a.id)} />)}
        </div>
      )}

      {/* Liens admin éleveur */}
      {isEleveur && (
        <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Link href="/elevage/registre-sanitaire"
            className="flex items-center gap-3 bg-[#E8F4F6] border border-[#0C5C6C]/20 rounded-2xl p-4 hover:shadow-md transition-shadow">
            <span className="text-2xl">🏥</span>
            <div>
              <p className="font-semibold text-[#0C5C6C] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Registre sanitaire</p>
              <p className="text-[#0C5C6C]/60 text-xs">Actes vétérinaires</p>
            </div>
          </Link>
          <Link href="/elevage/registre-entree-sortie"
            className="flex items-center gap-3 bg-[#EEF5EA] border border-[#6E9E57]/20 rounded-2xl p-4 hover:shadow-md transition-shadow">
            <span className="text-2xl">📂</span>
            <div>
              <p className="font-semibold text-[#5A8A45] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Entrées / Sorties</p>
              <p className="text-[#5A8A45]/60 text-xs">Registre légal</p>
            </div>
          </Link>
        </div>
      )}
    </div>
  );
}
