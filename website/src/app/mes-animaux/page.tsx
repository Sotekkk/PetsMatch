'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';
import { thumbUrl } from '@/lib/upload-media';
import CessionModal from '@/components/animaux/CessionModal';

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
  description?: string;
  pedigree?: boolean;
  club_registre?: string;
  pedigree_lof?: string;
  nom_pere?: string;
  puce_pere?: string;
  nom_mere?: string;
  puce_mere?: string;
  race_mere?: string;
  date_naissance_mere?: string;
  reproducteur?: boolean;
  is_retraite?: boolean;
  intervalle_chaleurs_jours?: number | null;
  uid_eleveur?: string | null;
  uid_acquereur?: string | null;
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

function AnimalCard({ a, tab, showPorteeBadge = false, reproducteur = false, isRetraite = false, chaleurFlag = false, gestanteFlag = false, selectMode = false, selected = false, onDelete, onToggleReproducteur, onToggleRetraite, onSelect, onCeder, onTransferer }: {
  a: Animal; tab: 'presents' | 'anciens'; showPorteeBadge?: boolean;
  reproducteur?: boolean; isRetraite?: boolean; chaleurFlag?: boolean; gestanteFlag?: boolean;
  selectMode?: boolean; selected?: boolean;
  onDelete?: () => void; onToggleReproducteur?: () => void; onToggleRetraite?: () => void; onSelect?: () => void;
  onCeder?: () => void;
  onTransferer?: () => void;
}) {
  const espColor = SPECIES.find(s => s.value === a.espece)?.color ?? '#6F767B';
  const isMale   = (a.sexe ?? '').toLowerCase().startsWith('m');
  const isFemale = (a.sexe ?? '').toLowerCase().startsWith('f');
  const photo    = a.photo_url ? thumbUrl(a.photo_url, 400, 75, 'contain') : undefined;
  const [confirmDelete, setConfirmDelete] = useState(false);

  const imageArea = (
    <div className="aspect-square relative overflow-hidden" style={{ background: espColor + '18' }}>
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
      {tab === 'presents' && a.statut === 'en_attente_cession' && !selectMode && (
        <span className="absolute top-2 right-2 bg-amber-500 text-white text-[9px] font-bold px-1.5 py-0.5 rounded-lg">
          ⏳ Cession
        </span>
      )}
      {showPorteeBadge && a.portee_id && !selectMode && (
        <span className="absolute top-2 left-2 text-white text-[9px] font-bold px-1.5 py-0.5 rounded-lg bg-[#0C5C6C]/85">
          🐣 Portée
        </span>
      )}
      {tab === 'presents' && reproducteur && !selectMode && (
        <span className="absolute top-2 right-2 bg-amber-400/90 text-white text-[9px] font-bold w-5 h-5 rounded-full flex items-center justify-center">
          ⭐
        </span>
      )}
      {tab === 'presents' && isRetraite && !selectMode && (
        <span className="absolute top-2 left-2 bg-amber-800/90 text-white text-[9px] font-bold px-1.5 py-0.5 rounded-lg">
          Retraite
        </span>
      )}
      {selectMode && (
        <>
          {selected && <div className="absolute inset-0 bg-[#0C5C6C]/15" />}
          <div className={`absolute top-2 left-2 w-5 h-5 rounded-full border-2 flex items-center justify-center text-[10px] font-bold transition-colors ${
            selected ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'bg-white border-gray-400'
          }`}>
            {selected && '✓'}
          </div>
        </>
      )}
      {!selectMode && (gestanteFlag || chaleurFlag) && (
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
  );

  const infoArea = (
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
  );

  const innerCls = `bg-white rounded-2xl shadow-sm overflow-hidden transition-all ${selected ? 'ring-2 ring-[#0C5C6C]' : ''} ${!selectMode ? 'hover:shadow-md' : ''}`;

  return (
    <div className="relative group">
      {selectMode ? (
        <div onClick={onSelect} className={`${innerCls} cursor-pointer`}>
          {imageArea}{infoArea}
        </div>
      ) : (
        <Link href={`/mes-animaux/${a.id}`} className={innerCls}>
          {imageArea}{infoArea}
        </Link>
      )}
      {!selectMode && onToggleReproducteur && (
        <button
          onClick={e => { e.preventDefault(); onToggleReproducteur(); }}
          className={`absolute top-10 right-2 opacity-0 group-hover:opacity-100 transition-opacity rounded-full w-7 h-7 flex items-center justify-center shadow-md text-xs ${reproducteur ? 'bg-amber-400 text-white' : 'bg-white text-amber-400 border border-amber-400'}`}
          title={reproducteur ? 'Retirer reproducteur' : 'Marquer reproducteur'}>
          ⭐
        </button>
      )}
      {!selectMode && onToggleRetraite && (
        <button
          onClick={e => { e.preventDefault(); onToggleRetraite(); }}
          className={`absolute top-[72px] right-2 opacity-0 group-hover:opacity-100 transition-opacity rounded-full w-7 h-7 flex items-center justify-center shadow-md text-xs ${isRetraite ? 'bg-amber-800 text-white' : 'bg-white text-amber-800 border border-amber-800'}`}
          title={isRetraite ? 'Annuler la retraite' : 'Mettre en retraite'}>
          🏁
        </button>
      )}
      {!selectMode && tab === 'presents' && onCeder && (
        <button
          onClick={e => { e.preventDefault(); onCeder(); }}
          className="absolute top-[108px] right-2 opacity-0 group-hover:opacity-100 transition-opacity bg-amber-500 text-white rounded-full w-7 h-7 flex items-center justify-center shadow-md text-xs"
          title="Céder cet animal">
          🤝
        </button>
      )}
      {!selectMode && tab === 'presents' && onTransferer && (
        <button
          onClick={e => { e.preventDefault(); onTransferer(); }}
          className="absolute top-[108px] right-2 opacity-0 group-hover:opacity-100 transition-opacity bg-teal-600 text-white rounded-full w-7 h-7 flex items-center justify-center shadow-md text-xs"
          title="Transférer / donner cet animal">
          🔄
        </button>
      )}
      {!selectMode && onDelete && (
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
  const { user, userData, loading, activeProfileId } = useAuth();
  const { plan } = usePlan();
  const router = useRouter();

  const isEleveur = userData?.isElevage === true;

  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [cessionEnAttente, setCessionEnAttente] = useState<Set<string>>(new Set());
  const [fetching, setFetching] = useState(true);
  const [chaleurFlags, setChaleurFlags] = useState<Record<string, boolean>>({});
  const [gestanteFlags, setGestanteFlags] = useState<Record<string, boolean>>({});
  const [tab, setTab] = useState<'presents' | 'anciens'>('presents');
  const [cederAnimal, setCederAnimal] = useState<Animal | null>(null);
  const [nomElevage, setNomElevage] = useState('');
  const [adresseElevage, setAdresseElevage] = useState('');
  const [presentsSubTab, setPresentsSubTab] = useState<'tous' | 'repro' | 'bebes'>('tous');
  const [selectMode, setSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Modal soin portée
  const [soinPorteeAnimals, setSoinPorteeAnimals] = useState<Animal[] | null>(null);
  const [editPorteeGroup, setEditPorteeGroup] = useState<{ pid: string; members: Animal[] } | null>(null);

  // Filtres présents
  const [filtreEspece, setFiltreEspece] = useState('tous');
  const [filtreSexe, setFiltreSexe] = useState('tous');
  const [filtreRace, setFiltreRace] = useState('');
  const [filtreRetraite, setFiltreRetraite] = useState(false);
  const [filtreRepro, setFiltreRepro] = useState(false);
  const [filtreGestante, setFiltreGestante] = useState(false);
  const [filtreChaleur, setFiltreChaleur] = useState(false);

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
    if (!user || !isEleveur) return;
    supabase.from('users').select('name_elevage, rue_elevage, ville_elevage, email').eq('uid', user.uid).maybeSingle()
      .then(({ data }) => {
        if (data) {
          setNomElevage((data as {name_elevage?:string}).name_elevage ?? '');
          const parts = [(data as {rue_elevage?:string}).rue_elevage, (data as {ville_elevage?:string}).ville_elevage].filter(Boolean);
          setAdresseElevage(parts.join(', '));
        }
      });
  }, [user, isEleveur]);

  useEffect(() => {
    // Attendre que l'auth ET le profil actif soient chargés avant de requêter
    if (!user || loading) return;
    setFetching(true);
    let cancelled = false;

    async function loadAll() {
      const uid = user!.uid;

      // Source : animaux_proprietes — filtré par profile_id_proprio (post-migration V2.05)
      // Vérifie d'abord si la migration a été jouée, sinon retombe sur uid_proprio
      let ownRows: { animal_id: string; date_fin: string | null }[] = [];
      if (activeProfileId) {
        const { data: check } = await supabase
          .from('animaux_proprietes')
          .select('animal_id')
          .eq('uid_proprio', uid)
          .not('profile_id_proprio', 'is', null)
          .limit(1);
        if ((check ?? []).length > 0) {
          // Migration faite → filtre strict par profil (vide = correct pour ce profil)
          const { data: byProfile } = await supabase
            .from('animaux_proprietes')
            .select('animal_id, date_fin')
            .eq('uid_proprio', uid)
            .eq('profile_id_proprio', activeProfileId);
          ownRows = (byProfile ?? []) as typeof ownRows;
        } else {
          // Migration pas encore jouée → tous les animaux de l'uid
          const { data: fallback } = await supabase
            .from('animaux_proprietes')
            .select('animal_id, date_fin')
            .eq('uid_proprio', uid);
          ownRows = (fallback ?? []) as typeof ownRows;
        }
      } else {
        const { data } = await supabase
          .from('animaux_proprietes')
          .select('animal_id, date_fin')
          .eq('uid_proprio', uid);
        ownRows = (data ?? []) as typeof ownRows;
      }

      const rows = ownRows;
      const currentIds = new Set(rows.filter(r => !r.date_fin).map(r => r.animal_id as string));
      const allAnimalIds = [...new Set(rows.map(r => r.animal_id as string))];

      if (allAnimalIds.length === 0) {
        if (!cancelled) { setAnimaux([]); setCessionEnAttente(new Set()); setFetching(false); }
        return;
      }

      const { data } = await supabase
        .from('animaux')
        .select('*')
        .in('id', allAnimalIds)
        .order('nom', { ascending: true });

      const merged = (data ?? []) as Animal[];
      if (!cancelled) { setAnimaux(merged); setCessionEnAttente(currentIds); setFetching(false); }

      // Calcul flags chaleurs et gestante pour les femelles présentes
      const femIds = merged
        .filter((a: Animal) => (a.sexe ?? '').startsWith('f') && a.statut !== 'sorti' && a.statut !== 'decede')
        .map((a: Animal) => a.id);

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
      for (const a of merged) {
        if (!(a.id in lastChaleur)) continue;
        const interval = (a.intervalle_chaleurs_jours ?? CHALEURS_INTERVAL_WEB[a.espece ?? ''] ?? 0);
        if (!interval) continue;
        const next = new Date(lastChaleur[a.id].getTime() + interval * 86400000);
        if ((next.getTime() - now.getTime()) / 86400000 <= 7) cFlags[a.id] = true;
      }

      const gFlags: Record<string, boolean> = {};
      for (const g of (gests ?? [])) gFlags[g.animal_id as string] = true;

      if (cancelled) return;
      setChaleurFlags(cFlags);
      setGestanteFlags(gFlags);
    }

    loadAll().catch(() => { if (!cancelled) setFetching(false); });
    return () => { cancelled = true; };
  }, [user, loading, isEleveur, activeProfileId]);

  async function deleteAnimal(id: string) {
    await supabase.from('animaux').delete().eq('id', id);
    setAnimaux(prev => prev.filter(a => a.id !== id));
  }

  async function toggleReproducteur(id: string, current: boolean) {
    await supabase.from('animaux').update({ reproducteur: !current }).eq('id', id);
    setAnimaux(prev => prev.map(a => a.id === id ? { ...a, reproducteur: !current } : a));
  }

  async function toggleRetraite(id: string, current: boolean) {
    await supabase.from('animaux').update({ is_retraite: !current }).eq('id', id);
    setAnimaux(prev => prev.map(a => a.id === id ? { ...a, is_retraite: !current } : a));
  }

  function toggleSelect(id: string) {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  async function regrouperEnPortee() {
    if (selectedIds.size < 2) return;
    const porteeId = `portee_${Date.now()}`;
    await supabase.from('animaux').update({ portee_id: porteeId }).in('id', [...selectedIds]);
    setAnimaux(prev => prev.map(a => selectedIds.has(a.id) ? { ...a, portee_id: porteeId } : a));
    setSelectMode(false);
    setSelectedIds(new Set());
  }

  if (loading || !user) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  // Séparer présents / anciens via animaux_proprietes (source unique)
  // cessionEnAttente = animal_id où date_fin IS NULL = propriétaire actuel
  const presents = animaux.filter(a => cessionEnAttente.has(a.id) && a.statut !== 'decede');
  const anciens  = animaux.filter(a => !cessionEnAttente.has(a.id) || a.statut === 'decede');

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
    if (filtreRetraite && !a.is_retraite) return false;
    if (filtreRepro && !a.reproducteur) return false;
    if (filtreGestante && !gestanteFlags[a.id]) return false;
    if (filtreChaleur && !chaleurFlags[a.id]) return false;
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

  const activeFilterCount = tab === 'presents'
    ? (filtreEspece !== 'tous' ? 1 : 0) + (filtreSexe !== 'tous' ? 1 : 0) + (filtreRace ? 1 : 0) +
      (filtreRetraite ? 1 : 0) + (filtreRepro ? 1 : 0) + (filtreGestante ? 1 : 0) + (filtreChaleur ? 1 : 0)
    : (anciensEspece !== 'tous' ? 1 : 0) + (anciensStatut !== 'tous' ? 1 : 0);

  // Sub-tab filtering (presents only)
  const presentsForSubTab = (() => {
    if (presentsSubTab === 'repro') return filteredPresents.filter(a => a.reproducteur === true);
    if (presentsSubTab === 'bebes') return filteredPresents.filter(a => !!a.portee_id && !a.reproducteur);
    return filteredPresents;
  })();

  const currentList = tab === 'presents' ? presentsForSubTab : filteredAnciens;

  // Groupement par portée (bébés uniquement) — inclut les frères/sœurs reproducteurs
  const porteeGroups: Map<string, Animal[]> = new Map();
  if (tab === 'presents' && presentsSubTab === 'bebes') {
    // 1) Collecter les portee_id des vrais bébés (non-reproducteurs)
    const porteeIdsEnVue = new Set(
      filteredPresents.filter(a => !!a.portee_id && !a.reproducteur).map(a => a.portee_id!)
    );
    // 2) Inclure TOUS les membres de ces portées (y compris reproducteurs)
    for (const a of filteredPresents) {
      if (!a.portee_id || !porteeIdsEnVue.has(a.portee_id)) continue;
      const group = porteeGroups.get(a.portee_id) ?? [];
      group.push(a);
      porteeGroups.set(a.portee_id, group);
    }
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
      setFiltreEspece('tous'); setFiltreSexe('tous'); setFiltreRace('');
      setFiltreRetraite(false); setFiltreRepro(false); setFiltreGestante(false); setFiltreChaleur(false);
    } else {
      setAnciensEspece('tous'); setAnciensStatut('tous');
    }
  }

  return (
    <>
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
        <div className="relative" ref={addMenuRef}>
          {isEleveur ? (
            <>
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
            </>
          ) : (
            <Link href="/mes-animaux/ajouter"
              className="bg-[#6E9E57] hover:bg-[#5A8A45] text-white text-sm font-semibold px-4 py-2 rounded-full transition-colors">
              + Ajouter un animal
            </Link>
          )}
        </div>
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

      {/* Sous-onglets présents */}
      {tab === 'presents' && (
        <div className="flex items-center gap-2 mb-4 flex-wrap">
          {isEleveur && ([['tous', 'Tous'], ['repro', '⭐ Repro'], ['bebes', '🐣 Bébés']] as const).map(([v, l]) => (
            <button key={v} onClick={() => { setPresentsSubTab(v); setSelectMode(false); setSelectedIds(new Set()); }}
              className={`px-4 py-1.5 rounded-full border text-sm font-medium transition-all ${
                presentsSubTab === v
                  ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white'
                  : 'border-gray-300 text-gray-600 hover:border-gray-400'
              }`}>
              {l}
            </button>
          ))}
          <div className="ml-auto">
            {selectMode ? (
              <button onClick={() => { setSelectMode(false); setSelectedIds(new Set()); }}
                className="px-3 py-1.5 rounded-full border border-gray-300 text-sm text-gray-500 hover:border-gray-400">
                Annuler
              </button>
            ) : (
              <button onClick={() => setSelectMode(true)}
                className="px-3 py-1.5 rounded-full border border-gray-300 text-sm text-gray-600 hover:border-[#0C5C6C] hover:text-[#0C5C6C] transition-colors">
                ☑️ Sélectionner
              </button>
            )}
          </div>
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
              {/* Statut spécial */}
              <div>
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Statut spécial</p>
                <div className="flex flex-wrap gap-2">
                  {isEleveur && <Chip label="🏁 Retraité" active={filtreRetraite} color="#B45309" onClick={() => setFiltreRetraite(!filtreRetraite)} />}
                  {isEleveur && <Chip label="⭐ Repro"    active={filtreRepro}    color="#0C5C6C" onClick={() => setFiltreRepro(!filtreRepro)} />}
                  <Chip label="🤰 Gestante"    active={filtreGestante} color="#6E9E57" onClick={() => setFiltreGestante(!filtreGestante)} />
                  <Chip label="🌸 En chaleur"  active={filtreChaleur}  color="#F472B6" onClick={() => setFiltreChaleur(!filtreChaleur)} />
                </div>
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
            {tab === 'presents' && presentsSubTab === 'repro'
              ? 'Aucun animal reproducteur'
              : tab === 'presents' && presentsSubTab === 'bebes'
              ? 'Aucun bébé dans une portée'
              : tab === 'presents' ? 'Aucun animal présent' : 'Aucun ancien animal'}
          </p>
          <p className="text-gray-400 text-sm mt-1">
            {tab === 'presents' && presentsSubTab === 'repro'
              ? 'Survolez une carte et cliquez ⭐ pour marquer un reproducteur'
              : tab === 'presents' && animaux.length === 0
              ? 'Ajoutez votre premier animal'
              : 'Modifiez les filtres pour voir plus de résultats'}
          </p>
        </div>
      ) : presentsSubTab === 'bebes' && porteeGroups.size > 0 ? (
        <div className="space-y-6">
          {[...porteeGroups.entries()].map(([pid, members]) => {
            const first = members[0];
            const dn = first.date_naissance ? new Date(first.date_naissance).toLocaleDateString('fr-FR') : null;
            const race = first.race ?? '';
            const espece = first.espece ?? '';
            const nomMere = first.nom_mere?.trim() ?? '';
            return (
              <div key={pid}>
                <div className="flex items-center gap-3 px-4 py-3 rounded-xl mb-3"
                  style={{ background: '#0C5C6C0D', border: '1px solid #0C5C6C30' }}>
                  <span className="text-lg">🐣</span>
                  <div className="flex-1">
                    <p className="text-sm font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {nomMere ? `Portée de ${nomMere}` : 'Portée'} {espece && <span>· {SPECIES_EMOJI[espece] ?? ''} {speciesLabel(espece)}</span>}
                    </p>
                    {race && <p className="text-xs text-[#5F9EAA]">{race}</p>}
                    {dn && <p className="text-xs text-[#5F9EAA]">Nés le {dn}</p>}
                  </div>
                  <span className="text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C20] px-2 py-0.5 rounded-full">
                    {members.length}
                  </span>
                  <button
                    onClick={() => setEditPorteeGroup({ pid, members })}
                    className="flex items-center gap-1 text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C40] px-2.5 py-1.5 rounded-lg hover:bg-[#0C5C6C0D] transition-colors"
                    title="Modifier les informations de la portée"
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    ✏️ Modifier
                  </button>
                  <button
                    onClick={() => setSoinPorteeAnimals(members)}
                    className="flex items-center gap-1 text-xs font-semibold text-[#F57F17] border border-[#FFCA28] px-2.5 py-1.5 rounded-lg hover:bg-[#FFF8E1] transition-colors"
                    title="Soin pour toute la portée"
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    💊 Soin portée
                  </button>
                  <Link
                    href={`/annonces/creer?portee_id=${pid}`}
                    className="flex items-center gap-1.5 text-xs font-semibold text-[#6E9E57] border border-[#6E9E57] px-3 py-1.5 rounded-lg hover:bg-[#6E9E57] hover:text-white transition-colors"
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    📢 Créer annonce
                  </Link>
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                  {members.map(a => <AnimalCard key={a.id} a={a} tab={tab} showPorteeBadge
                    reproducteur={!!a.reproducteur} isRetraite={!!a.is_retraite}
                    chaleurFlag={!!chaleurFlags[a.id]} gestanteFlag={!!gestanteFlags[a.id]}
                    selectMode={selectMode} selected={selectedIds.has(a.id)} onSelect={() => toggleSelect(a.id)}
                    onDelete={selectMode ? undefined : () => deleteAnimal(a.id)}
                    onToggleReproducteur={isEleveur && !selectMode ? () => toggleReproducteur(a.id, !!a.reproducteur) : undefined}
                    onToggleRetraite={isEleveur && !selectMode ? () => toggleRetraite(a.id, !!a.is_retraite) : undefined} />)}
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          {currentList.map(a => <AnimalCard key={a.id} a={a} tab={tab}
            reproducteur={!!a.reproducteur} isRetraite={!!a.is_retraite}
            chaleurFlag={!!chaleurFlags[a.id]} gestanteFlag={!!gestanteFlags[a.id]}
            selectMode={tab === 'presents' && selectMode} selected={selectedIds.has(a.id)} onSelect={() => toggleSelect(a.id)}
            onDelete={selectMode ? undefined : () => deleteAnimal(a.id)}
            onToggleReproducteur={isEleveur && tab === 'presents' && !selectMode ? () => toggleReproducteur(a.id, !!a.reproducteur) : undefined}
            onToggleRetraite={isEleveur && tab === 'presents' && !selectMode ? () => toggleRetraite(a.id, !!a.is_retraite) : undefined}
            onCeder={isEleveur && tab === 'presents' && !selectMode && a.uid_eleveur === user?.uid ? () => setCederAnimal(a) : undefined}
            onTransferer={tab === 'presents' && !selectMode && a.uid_eleveur !== user?.uid && a.uid_acquereur === user?.uid ? () => setCederAnimal(a) : undefined} />)}
        </div>
      )}

      {/* Barre action sélection */}
      {selectMode && selectedIds.size > 0 && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-30 flex items-center gap-3 bg-[#1F2A2E] text-white rounded-2xl px-5 py-3 shadow-2xl">
          <span className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            {selectedIds.size} sélectionné{selectedIds.size > 1 ? 's' : ''}
          </span>
          <button
            onClick={regrouperEnPortee}
            disabled={selectedIds.size < 2}
            className="bg-[#0C5C6C] hover:bg-[#0a4d5b] disabled:opacity-40 text-white text-sm font-semibold px-4 py-1.5 rounded-xl transition-colors">
            🐣 Regrouper en portée
          </button>
        </div>
      )}

      {/* Liens admin éleveur */}
      {isEleveur && (
        <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 gap-3">
          {plan === 'free' ? (
            <>
              <Link href="/abonnement"
                className="flex items-center gap-3 bg-gray-100 border border-gray-200 rounded-2xl p-4 opacity-60 hover:opacity-80 transition-opacity">
                <span className="text-2xl">🏥</span>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <p className="font-semibold text-gray-500 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Registre sanitaire</p>
                    <span className="text-[10px] font-bold bg-amber-100 text-amber-600 px-1.5 py-0.5 rounded-full">Pro</span>
                  </div>
                  <p className="text-gray-400 text-xs">Actes vétérinaires</p>
                </div>
                <span className="text-gray-400 text-lg">🔒</span>
              </Link>
              <Link href="/abonnement"
                className="flex items-center gap-3 bg-gray-100 border border-gray-200 rounded-2xl p-4 opacity-60 hover:opacity-80 transition-opacity">
                <span className="text-2xl">📂</span>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <p className="font-semibold text-gray-500 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Entrées / Sorties</p>
                    <span className="text-[10px] font-bold bg-amber-100 text-amber-600 px-1.5 py-0.5 rounded-full">Pro</span>
                  </div>
                  <p className="text-gray-400 text-xs">Registre légal</p>
                </div>
                <span className="text-gray-400 text-lg">🔒</span>
              </Link>
            </>
          ) : (
            <>
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
            </>
          )}
        </div>
      )}
    </div>

    {/* Modal soin portée */}
    {soinPorteeAnimals && (
      <PorteeSoinModal
        animals={soinPorteeAnimals}
        uid={user?.uid ?? ''}
        activeProfileId={activeProfileId ?? null}
        onClose={() => setSoinPorteeAnimals(null)}
      />
    )}

    {/* Modal modifier portée */}
    {editPorteeGroup && (
      <EditPorteeModal
        pid={editPorteeGroup.pid}
        members={editPorteeGroup.members}
        uid={user?.uid ?? ''}
        activeProfileId={activeProfileId ?? null}
        onClose={() => setEditPorteeGroup(null)}
        onSaved={(fields) => {
          setAnimaux(prev => prev.map(a => a.portee_id === editPorteeGroup.pid ? { ...a, ...fields } : a));
          setEditPorteeGroup(null);
        }}
      />
    )}

    {/* Modal cession */}
    {cederAnimal && user && (
      <CessionModal
        animal={cederAnimal}
        uid={user.uid}
        profileId={activeProfileId || null}
        eleveurInfo={{ nom: nomElevage || user.email || 'Éleveur', adresse: adresseElevage, email: user.email ?? '' }}
        isReCession={cederAnimal.uid_eleveur !== user.uid && cederAnimal.uid_acquereur === user.uid}
        onClose={() => setCederAnimal(null)}
        onCeded={() => {
          setCederAnimal(null);
          setFetching(true);
          supabase.from('animaux')
            .select('*').or(`uid_eleveur.eq.${user.uid},uid_acquereur.eq.${user.uid}`)
            .order('nom', { ascending: true })
            .then(({ data }) => { setAnimaux((data ?? []) as Animal[]); setFetching(false); });
        }}
      />
    )}
    </>
  );
}

// ── Modal soin portée ─────────────────────────────────────────────────────────

const ACTE_TYPES = [
  { value: 'vermifuge',       label: 'Vermifuge',          emoji: '🐛' },
  { value: 'vaccination',     label: 'Vaccination',         emoji: '💉' },
  { value: 'antiparasitaire', label: 'Antiparasitaire',     emoji: '🛡️' },
  { value: 'traitement',      label: 'Traitement',          emoji: '💊' },
  { value: 'visite',          label: 'Visite vétérinaire',  emoji: '🏥' },
  { value: 'osteopathie',     label: 'Ostéopathie',         emoji: '🤲' },
  { value: 'chirurgie',       label: 'Chirurgie',           emoji: '🔬' },
  { value: 'autre',           label: 'Autre',               emoji: '📋' },
];

function PorteeSoinModal({ animals, uid, activeProfileId, onClose }: {
  animals: Animal[];
  uid: string;
  activeProfileId: string | null;
  onClose: () => void;
}) {
  const [typeActe, setTypeActe]       = useState('vermifuge');
  const [date, setDate]               = useState(new Date().toISOString().slice(0, 10));
  const [description, setDescription] = useState('');
  const [intervenant, setIntervenant] = useState('');
  const [ordonnance, setOrdonnance]   = useState('');
  const [dosage, setDosage]           = useState('');
  const [notes, setNotes]             = useState('');
  const [saving, setSaving]           = useState(false);
  const [saved, setSaved]             = useState(false);
  const [error, setError]             = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set(animals.map(a => a.id)));

  const toggleAnimal = useCallback((id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }, []);

  const handleSave = useCallback(async () => {
    if (!description.trim()) { setError('Le produit / la description est obligatoire.'); return; }
    if (selectedIds.size === 0) { setError('Sélectionnez au moins un animal.'); return; }
    setSaving(true); setError('');
    const dateIso = new Date(date).toISOString();
    const desc    = description.trim();
    const interv  = intervenant.trim();
    let success = 0;
    for (const animal of animals.filter(a => selectedIds.has(a.id))) {
      try {
        const entryId = `${Date.now()}_${animal.id}`;
        // Table spécifique (lue par le carnet de santé de la fiche)
        const n = notes.trim();
        if (typeActe === 'vermifuge') {
          await supabase.from('vermifuges').insert({
            id: entryId, animal_id: animal.id,
            produit: desc, date: dateIso, source: 'owner',
            ...(dosage.trim() ? { dosage: dosage.trim() } : {}),
            ...(n ? { notes: n } : {}),
          });
        } else if (typeActe === 'vaccination') {
          await supabase.from('vaccinations').insert({
            id: entryId, animal_id: animal.id,
            vaccin: desc, veterinaire: interv, date: dateIso, source: 'owner',
          });
        } else if (typeActe === 'antiparasitaire') {
          await supabase.from('antiparasitaires').insert({
            id: entryId, animal_id: animal.id,
            produit: desc, type: 'autre', date: dateIso, source: 'owner',
            ...(dosage.trim() ? { frequence: dosage.trim() } : {}),
            ...(n ? { notes: n } : {}),
          });
        } else if (typeActe === 'visite' || typeActe === 'osteopathie') {
          await supabase.from('visites').insert({
            id: entryId, animal_id: animal.id,
            motif: typeActe === 'osteopathie' ? 'Autre' : 'Consultation',
            veterinaire: interv, date: dateIso,
            diagnostic: typeActe === 'osteopathie' ? `Ostéopathie — ${desc}` : desc,
            ...(n ? { notes: n } : {}),
            source: 'owner',
          });
        } else {
          // traitement, chirurgie, autre
          await supabase.from('traitements').insert({
            id: entryId, animal_id: animal.id,
            nom: desc, type: typeActe === 'chirurgie' ? 'autre' : 'medicament',
            date: dateIso, source: 'owner',
          });
        }
        // Log consolidé dans registre_sanitaire
        await supabase.from('registre_sanitaire').insert({
          id:          `rs_${entryId}`,
          uid_eleveur: uid,
          ...(activeProfileId ? { eleveur_profile_id: activeProfileId } : {}),
          animal_id:   animal.id,
          animal_nom:  animal.nom ?? '',
          espece:      animal.espece ?? '',
          date_naissance: animal.date_naissance ?? null,
          identification: animal.identification ?? '',
          sexe:           animal.sexe ?? '',
          date_acte:      dateIso,
          type_acte:      typeActe,
          intervenant:    interv,
          description:    desc,
          ordonnance_num: ordonnance.trim(),
        });
        success++;
      } catch { /* continue */ }
    }
    setSaving(false);
    if (success > 0) { setSaved(true); setTimeout(onClose, 1200); }
    else setError('Erreur lors de l\'enregistrement. Vérifiez votre connexion.');
  }, [animals, uid, typeActe, date, description, dosage, notes, intervenant, ordonnance, onClose, selectedIds]);

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="p-5">
          {/* Titre */}
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-xl bg-[#FFF8E1] flex items-center justify-center text-xl">💊</div>
            <div className="flex-1">
              <p className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Soin pour la portée</p>
              <p className="text-xs text-[#6E9E57]">{selectedIds.size}/{animals.length} animal{animals.length > 1 ? 'aux' : ''} sélectionné{selectedIds.size > 1 ? 's' : ''}</p>
            </div>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
          </div>

          {/* Animaux concernés — cliquer pour désélectionner */}
          <div className="flex flex-wrap gap-1.5 mb-1">
            {animals.map(a => {
              const sel = selectedIds.has(a.id);
              return (
                <button key={a.id} onClick={() => toggleAnimal(a.id)}
                  className={`flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-lg border transition-all ${
                    sel
                      ? 'bg-[#0C5C6C12] text-[#0C5C6C] border-[#0C5C6C40]'
                      : 'bg-gray-100 text-gray-400 border-gray-200 line-through'
                  }`}
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  {a.nom ?? '?'}
                  {!sel && <span className="text-gray-300 text-[10px]">✕</span>}
                </button>
              );
            })}
          </div>
          <p className="text-[10px] text-gray-400 mb-4">Touchez un animal pour le retirer du soin</p>

          {/* Type d'acte */}
          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">Type de soin</p>
          <div className="flex flex-wrap gap-2 mb-4">
            {ACTE_TYPES.map(t => (
              <button key={t.value}
                className={`flex items-center gap-1 text-xs font-semibold px-3 py-1.5 rounded-lg border transition-colors ${
                  typeActe === t.value
                    ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                    : 'bg-gray-50 text-gray-700 border-gray-200 hover:border-[#0C5C6C]'
                }`}
                style={{ fontFamily: 'Galey, sans-serif' }}
                onClick={() => { setTypeActe(t.value); setDosage(''); }}>
                {t.emoji} {t.label}
              </button>
            ))}
          </div>

          {/* Date */}
          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Date du soin</p>
          <input type="date" value={date} onChange={e => setDate(e.target.value)}
            max={new Date().toISOString().slice(0, 10)}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          {/* Description */}
          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Produit / description *</p>
          <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2}
            placeholder="Ex : Milbemax® 1 comprimé par chiot de 0,5 kg à 10 kg"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 resize-none focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          {/* Dosage — vermifuge / antiparasitaire uniquement */}
          {(typeActe === 'vermifuge' || typeActe === 'antiparasitaire') && (
            <>
              <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
                {typeActe === 'antiparasitaire' ? 'Fréquence (optionnel)' : 'Dosage (optionnel)'}
              </p>
              <input value={dosage} onChange={e => setDosage(e.target.value)}
                placeholder={typeActe === 'antiparasitaire' ? 'Ex : 1 mois' : 'Ex : 1 cp / 5 kg'}
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 focus:outline-none focus:border-[#0C5C6C]"
                style={{ fontFamily: 'Galey, sans-serif' }} />
            </>
          )}

          {/* Administré par */}
          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Administré par (optionnel)</p>
          <input value={intervenant} onChange={e => setIntervenant(e.target.value)}
            placeholder="Éleveur, Dr. Dupont, …"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          {/* Notes */}
          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Notes (optionnel)</p>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
            placeholder="Observations, réactions, …"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 resize-none focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          {/* Ordonnance */}
          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">N° ordonnance (optionnel)</p>
          <input value={ordonnance} onChange={e => setOrdonnance(e.target.value)}
            placeholder="ORD-2024-XXXXX"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-5 focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          {error && <p className="text-sm text-red-600 mb-3 bg-red-50 rounded-xl px-3 py-2">{error}</p>}
          {saved && <p className="text-sm text-[#6E9E57] mb-3 bg-[#EEF5EA] rounded-xl px-3 py-2 font-semibold">✓ {animals.length} enregistrement{animals.length > 1 ? 's' : ''} ajouté{animals.length > 1 ? 's' : ''} au registre</p>}

          <div className="flex gap-3">
            <button onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-semibold py-3 rounded-xl text-sm hover:bg-gray-50 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Annuler
            </button>
            <button onClick={handleSave} disabled={saving || saved || selectedIds.size === 0}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 disabled:cursor-not-allowed text-white font-semibold py-3 rounded-xl text-sm transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {saving ? 'Enregistrement…' : `Enregistrer pour ${selectedIds.size} animal${selectedIds.size > 1 ? 'aux' : ''}`}
            </button>
          </div>
        </div>
      </div>

    </div>
  );
}

// ── Modal modifier portée (infos communes à tous les animaux) ────────────────

function EditPorteeModal({ pid, members, uid, activeProfileId, onClose, onSaved }: {
  pid: string;
  members: Animal[];
  uid: string;
  activeProfileId: string | null;
  onClose: () => void;
  onSaved: (fields: Partial<Animal>) => void;
}) {
  const first = members[0];
  const espece = first.espece ?? '';
  const [race, setRace] = useState(first.race ?? '');
  const [dateNaissance, setDateNaissance] = useState(first.date_naissance?.slice(0, 10) ?? '');
  const [description, setDescription] = useState(first.description ?? '');
  const [pedigree, setPedigree] = useState(!!first.pedigree);
  const [clubRegistre, setClubRegistre] = useState(first.club_registre ?? '');
  const [pedigreeLof, setPedigreeLof] = useState(first.pedigree_lof ?? '');
  const [nomPere, setNomPere] = useState(first.nom_pere ?? '');
  const [pucePere, setPucePere] = useState(first.puce_pere ?? '');
  const [nomMere, setNomMere] = useState(first.nom_mere ?? '');
  const [puceMere, setPuceMere] = useState(first.puce_mere ?? '');
  const [raceMere, setRaceMere] = useState(first.race_mere ?? '');
  const [dateNaissanceMere, setDateNaissanceMere] = useState(first.date_naissance_mere?.slice(0, 10) ?? '');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState('');

  const [showPerePicker, setShowPerePicker] = useState(false);
  const [myMales, setMyMales] = useState<Animal[]>([]);
  const [loadingMales, setLoadingMales] = useState(false);
  const [showMerePicker, setShowMerePicker] = useState(false);
  const [myFemelles, setMyFemelles] = useState<Animal[]>([]);
  const [loadingFemelles, setLoadingFemelles] = useState(false);

  async function loadMaleAnimals() {
    if (!uid) return;
    setLoadingMales(true);
    let qm = supabase.from('animaux')
      .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
      .eq('uid_eleveur', uid).eq('espece', espece).eq('sexe', 'male')
      .or('statut.is.null,statut.eq.present');
    if (activeProfileId) qm = qm.eq('profile_id', activeProfileId) as typeof qm;
    const { data } = await qm.order('nom');
    setMyMales((data ?? []) as Animal[]);
    setLoadingMales(false);
  }

  async function loadFemelleAnimals() {
    if (!uid) return;
    setLoadingFemelles(true);
    let qf = supabase.from('animaux')
      .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
      .eq('uid_eleveur', uid).eq('espece', espece).eq('sexe', 'femelle')
      .or('statut.is.null,statut.eq.present');
    if (activeProfileId) qf = qf.eq('profile_id', activeProfileId) as typeof qf;
    const { data } = await qf.order('nom');
    setMyFemelles((data ?? []) as Animal[]);
    setLoadingFemelles(false);
  }

  function selectPere(a: Animal) {
    setNomPere(a.nom ?? '');
    setPucePere(a.identification ?? '');
    setShowPerePicker(false);
  }

  function selectMere(a: Animal) {
    setNomMere(a.nom ?? '');
    setPuceMere(a.identification ?? '');
    setRaceMere(a.race ?? '');
    setDateNaissanceMere(a.date_naissance?.slice(0, 10) ?? '');
    setShowMerePicker(false);
  }

  const iCls = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]';

  async function handleSave() {
    if (!dateNaissance) { setError('La date de naissance est obligatoire.'); return; }
    setSaving(true); setError('');
    const fields: Partial<Animal> = {
      race: race.trim() || undefined,
      date_naissance: dateNaissance,
      date_entree: dateNaissance,
      description: description.trim() || undefined,
      pedigree,
      club_registre: clubRegistre.trim() || undefined,
      pedigree_lof: pedigreeLof.trim() || undefined,
      nom_pere: nomPere.trim() || undefined,
      puce_pere: pucePere.trim() || undefined,
      nom_mere: nomMere.trim() || undefined,
      puce_mere: puceMere.trim() || undefined,
      race_mere: raceMere.trim() || undefined,
      date_naissance_mere: dateNaissanceMere || undefined,
    };
    const dbFields = Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, v ?? null]));
    const { error: err } = await supabase.from('animaux').update(dbFields).eq('portee_id', pid);
    setSaving(false);
    if (err) { setError('Erreur lors de la sauvegarde.'); return; }
    setSaved(true);
    setTimeout(() => onSaved(fields), 800);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="p-5">
          {/* Titre */}
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-xl bg-[#0C5C6C0D] flex items-center justify-center text-xl">✏️</div>
            <div className="flex-1">
              <p className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Modifier la portée</p>
              <p className="text-xs text-gray-400">{members.length} animal{members.length > 1 ? 'aux' : ''} concerné{members.length > 1 ? 's' : ''}</p>
            </div>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
          </div>

          {/* Race + Date de naissance */}
          <div className="flex gap-3 mb-4">
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">Race</label>
              <input className={iCls} value={race} onChange={e => setRace(e.target.value)} placeholder="Race commune à tous" />
            </div>
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">
                Date de naissance <span className="text-red-400">*</span>
              </label>
              <input type="date" className={iCls} value={dateNaissance}
                onChange={e => setDateNaissance(e.target.value)}
                max={new Date().toISOString().slice(0, 10)} />
            </div>
          </div>

          {/* Description */}
          <div className="mb-4">
            <label className="block text-xs font-medium text-gray-600 mb-1">Description (optionnel)</label>
            <textarea rows={2} className={`${iCls} resize-none`} value={description}
              onChange={e => setDescription(e.target.value)}
              placeholder="Caractère, particularités de la portée…" />
          </div>

          {/* Pedigree & Registre */}
          <div className="border border-gray-100 rounded-xl p-4 space-y-3 mb-4">
            <p className="text-sm font-semibold text-gray-700">🏅 Pedigree &amp; Registre</p>
            <div className="flex items-center justify-between py-1">
              <span className="text-sm text-gray-700">Inscrit au registre (LOF / LOOF…)</span>
              <button type="button" onClick={() => setPedigree(!pedigree)}
                className={`w-11 h-6 rounded-full transition-colors relative flex-shrink-0 ${pedigree ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
                <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${pedigree ? 'translate-x-5' : 'translate-x-0.5'}`} />
              </button>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Club de race / Association pedigree</label>
              <input className={iCls} value={clubRegistre} onChange={e => setClubRegistre(e.target.value)}
                placeholder="Ex: SCC, Club du Berger Australien…" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">N° d&apos;inscription au registre</label>
              <input className={iCls} value={pedigreeLof} onChange={e => setPedigreeLof(e.target.value)}
                placeholder="Ex: LOF 12345/00, LOOF 67890…" />
            </div>
          </div>

          {/* Père */}
          <div className="border border-gray-100 rounded-xl p-4 space-y-3 mb-4">
            <p className="text-sm font-semibold text-gray-700">♂ Père (optionnel)</p>
            <div className="relative">
              <button type="button"
                onClick={async () => {
                  if (!showPerePicker) await loadMaleAnimals();
                  setShowPerePicker(v => !v);
                  setShowMerePicker(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                <span>🔍</span>
                <span>Chercher parmi mes animaux</span>
              </button>
              {showPerePicker && (
                <ParentPickerList animals={myMales} isLoading={loadingMales} onSelect={selectPere} />
              )}
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Nom du père</label>
                <input className={iCls} value={nomPere} onChange={e => setNomPere(e.target.value)} placeholder="Nom" />
              </div>
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">N° identification</label>
                <input className={iCls} value={pucePere} onChange={e => setPucePere(e.target.value)} placeholder="Puce / tatouage" />
              </div>
            </div>
          </div>

          {/* Mère */}
          <div className="border border-gray-100 rounded-xl p-4 space-y-3 mb-5">
            <p className="text-sm font-semibold text-gray-700">♀ Mère (optionnel)</p>
            <div className="relative">
              <button type="button"
                onClick={async () => {
                  if (!showMerePicker) await loadFemelleAnimals();
                  setShowMerePicker(v => !v);
                  setShowPerePicker(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                <span>🔍</span>
                <span>Chercher parmi mes animaux</span>
              </button>
              {showMerePicker && (
                <ParentPickerList animals={myFemelles} isLoading={loadingFemelles} onSelect={selectMere} />
              )}
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Nom de la mère</label>
                <input className={iCls} value={nomMere} onChange={e => setNomMere(e.target.value)} placeholder="Nom" />
              </div>
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">N° identification</label>
                <input className={iCls} value={puceMere} onChange={e => setPuceMere(e.target.value)} placeholder="Puce / tatouage" />
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Race de la mère</label>
                <input className={iCls} value={raceMere} onChange={e => setRaceMere(e.target.value)} placeholder="Race" />
              </div>
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Date de naissance</label>
                <input type="date" className={iCls} value={dateNaissanceMere}
                  onChange={e => setDateNaissanceMere(e.target.value)}
                  max={new Date().toISOString().slice(0, 10)} />
              </div>
            </div>
          </div>

          {error && <p className="text-sm text-red-600 mb-3 bg-red-50 rounded-xl px-3 py-2">{error}</p>}
          {saved && <p className="text-sm text-[#6E9E57] mb-3 bg-[#EEF5EA] rounded-xl px-3 py-2 font-semibold">✓ Portée mise à jour</p>}

          <div className="flex gap-3">
            <button onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-semibold py-3 rounded-xl text-sm hover:bg-gray-50 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Annuler
            </button>
            <button onClick={handleSave} disabled={saving || saved}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 disabled:cursor-not-allowed text-white font-semibold py-3 rounded-xl text-sm transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function ParentPickerList({ animals, isLoading, onSelect }: {
  animals: Animal[];
  isLoading: boolean;
  onSelect: (a: Animal) => void;
}) {
  const [search, setSearch] = useState('');
  const q = search.trim().toLowerCase();
  const filtered = q
    ? animals.filter(a =>
        (a.nom ?? '').toLowerCase().includes(q) ||
        (a.race ?? '').toLowerCase().includes(q))
    : animals;

  return (
    <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
      <div className="p-2 border-b border-gray-100">
        <input
          type="text"
          autoFocus
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Rechercher par nom…"
          className="w-full border border-gray-200 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]"
        />
      </div>
      <div className="max-h-52 overflow-y-auto">
        {isLoading ? (
          <p className="text-sm text-gray-400 text-center py-4">Chargement…</p>
        ) : filtered.length === 0 ? (
          <p className="text-sm text-gray-400 text-center py-4">Aucun animal trouvé</p>
        ) : filtered.map(a => (
          <button key={a.id} type="button" onClick={() => onSelect(a)}
            className="w-full flex items-center gap-3 px-3 py-2.5 hover:bg-[#E8F4F6] text-left border-b border-gray-50 last:border-0 transition-colors">
            <div className="w-10 h-10 rounded-lg overflow-hidden flex-shrink-0 bg-gray-100 flex items-center justify-center">
              {a.photo_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={a.photo_url} alt="" className="w-full h-full object-contain" />
              ) : (
                <span className="text-gray-300 text-lg">🐾</span>
              )}
            </div>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-gray-800 truncate">{a.nom || 'Sans nom'}</p>
              {a.race && <p className="text-xs text-gray-400 truncate">{a.race}</p>}
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
