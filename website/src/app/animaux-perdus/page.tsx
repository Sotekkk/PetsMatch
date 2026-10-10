'use client';

import { useEffect, useState, useCallback } from 'react';
import Image from 'next/image';
import dynamic from 'next/dynamic';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { PAYS_LIST, REGIONS_BY_PAYS, departmentsInRegion } from '@/lib/french-geo';
import { db } from '@/lib/firebase';
import { collection, addDoc, query, where, getDocs, serverTimestamp, doc, updateDoc } from 'firebase/firestore';
import { useAuth } from '@/lib/auth-context';
import type { AlerteMapItem } from '@/components/AnimauxPerdusMap';
import { MARQUEUR_ESPECE, MARQUEUR_PERDU_DEFAUT, MARQUEUR_TROUVE } from '@/lib/perdus-couleurs';
import { Icone } from '@/components/dashboard/kit';

const AnimauxPerdusMap = dynamic(() => import('@/components/AnimauxPerdusMap'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100 rounded-2xl">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  ),
});

// ── Types ─────────────────────────────────────────────────────────────────────

interface Alerte {
  id: string;
  uid_proprietaire?: string;
  nom_animal: string;
  espece: string;
  race?: string;
  sexe?: string;
  couleur?: string;
  couleur_yeux?: string;
  identification?: string;
  photo_url?: string;
  description?: string;
  contact?: string;
  date_perte?: string;
  date_derniere_localisation?: string;
  ville?: string;
  derniere_localisation?: string;
  numero_alerte?: string;
  statut?: string;
  lat?: number;
  lng?: number;
}

interface Trouve {
  id: string;
  uid_declarant?: string;
  espece: string;
  race?: string;
  sexe?: string;
  taille?: string;
  couleur?: string;
  couleur_yeux?: string;
  numero_puce?: string;
  etat_sante?: string;
  comportement?: string;
  description?: string;
  date_trouve?: string;
  localisation_adresse?: string;
  ville?: string;
  region?: string;
  pays?: string;
  photos?: string[];
  contact_email?: string;
  contact_telephone?: string;
  accepte_messagerie?: boolean;
  lat?: number;
  lng?: number;
}

// ── Constantes ────────────────────────────────────────────────────────────────

const ESPECES = ['chien', 'chat', 'lapin', 'oiseau', 'nac', 'cheval', 'ovin', 'caprin', 'porcin', 'autre'];

export const ESPECE_COLORS: Record<string, { bg: string; text: string; border: string; dot: string }> = {
  chien:  { bg: '#FFF7ED', text: '#EA580C', border: '#FED7AA', dot: '#F97316' },
  chat:   { bg: '#FDF4FF', text: '#9333EA', border: '#E9D5FF', dot: '#A855F7' },
  cheval: { bg: '#F0FDF4', text: '#16A34A', border: '#BBF7D0', dot: '#22C55E' },
  lapin:  { bg: '#FFF0F6', text: '#DB2777', border: '#FBCFE8', dot: '#EC4899' },
  oiseau: { bg: '#ECFEFF', text: '#0891B2', border: '#A5F3FC', dot: '#06B6D4' },
  nac:    { bg: '#F5F3FF', text: '#7C3AED', border: '#DDD6FE', dot: '#8B5CF6' },
  ovin:   { bg: '#FFFBEB', text: '#D97706', border: '#FDE68A', dot: '#F59E0B' },
  caprin: { bg: '#F7FEE7', text: '#65A30D', border: '#D9F99D', dot: '#84CC16' },
  porcin: { bg: '#FFF1F2', text: '#E11D48', border: '#FECDD3', dot: '#F43F5E' },
  autre:  { bg: '#F9FAFB', text: '#6B7280', border: '#E5E7EB', dot: '#9CA3AF' },
};

const ESPECE_LIBELLE: Record<string, string> = { nac: 'NAC' };
function nomEspece(e?: string): string {
  if (!e) return 'Animal';
  return ESPECE_LIBELLE[e.toLowerCase()] ?? e.charAt(0).toUpperCase() + e.slice(1);
}

const SEXE_LABEL: Record<string, string> = { male: 'Mâle', femelle: 'Femelle', inconnu: 'Inconnu' };

// Styles communs de la section (bleu pétrole, bordures fines).
const CHAMP = 'w-full border border-[#E5E8E6] rounded-xl px-3 py-2.5 text-sm text-[#1E2025] bg-white focus:outline-none focus:border-[#0C5C6C] disabled:bg-gray-50 disabled:text-gray-400';
const LIBELLE = 'block text-[13px] font-medium text-[#374151] mb-1.5';

function fmtDate(s?: string) {
  if (!s) return null;
  return new Date(s).toLocaleDateString('fr-FR');
}

function thumbUrl(url?: string): string | undefined {
  return url || undefined;
}

function extractVille(a: Alerte): string {
  if (a.ville) return a.ville;
  if (a.derniere_localisation) {
    const parts = a.derniere_localisation.split(',').map(p => p.trim());
    return parts[parts.length - 1] ?? '';
  }
  return '';
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function AnimauxPerdusPage() {
  const { user, userData } = useAuth();
  const router = useRouter();

  const [alertes, setAlertes]       = useState<Alerte[]>([]);
  const [trouves, setTrouves]       = useState<Trouve[]>([]);
  const [loading, setLoading]       = useState(true);
  const [view, setView]             = useState<'liste' | 'carte'>('liste');
  const [selectedAlerte, setSelectedAlerte] = useState<Alerte | null>(null);
  const [selectedTrouve, setSelectedTrouve] = useState<Trouve | null>(null);
  const [contacting, setContacting] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [legendeOuverte, setLegendeOuverte] = useState(true);

  // Filtres
  const [filterType,   setFilterType]   = useState<'perdu' | 'trouve' | 'tous'>('perdu');
  const [filtreEspece, setFiltreEspece] = useState('tous');
  const [filtreRace,   setFiltreRace]   = useState('');
  const [filtreVille,  setFiltreVille]  = useState('');
  const [filtrePays,   setFiltrePays]   = useState('');
  const [filtreRegion, setFiltreRegion] = useState('');
  const [filtreDept,   setFiltreDept]   = useState('');

  // Breed autocomplete
  const [breeds, setBreeds]           = useState<string[]>([]);
  const [raceSugg, setRaceSugg]       = useState<string[]>([]);
  const [showRaceSugg, setShowRaceSugg] = useState(false);

  // ── Load data ─────────────────────────────────────────────────────────────

  useEffect(() => {
    Promise.all([
      supabase.from('alertes_perdus').select('*').eq('statut', 'perdu').order('created_at', { ascending: false }),
      supabase.from('animaux_trouves').select('*').order('created_at', { ascending: false }),
    ]).then(([{ data: perdus }, { data: found }]) => {
      setAlertes((perdus as Alerte[]) ?? []);
      setTrouves((found as Trouve[]) ?? []);
      setLoading(false);
    });
  }, []);

  // Default ville from user profile
  useEffect(() => {
    if (userData?.ville && !filtreVille) setFiltreVille(userData.ville);
  }, [userData]);

  // Load breeds when espece changes
  const BREED_FILES: Record<string, string> = {
    chien: 'dog_breeds', chat: 'cat_breeds', cheval: 'horse_breeds',
    lapin: 'rabbit_breeds', oiseau: 'bird_breeds', nac: 'nac_breeds',
    ovin: 'sheep_breeds', caprin: 'goat_breeds', porcin: 'pig_breeds',
  };
  useEffect(() => {
    const file = BREED_FILES[filtreEspece];
    if (!file) { setBreeds([]); return; }
    fetch(`/breeds/${file}.json`).then(r => r.json()).then(setBreeds).catch(() => setBreeds([]));
  }, [filtreEspece]);

  // ── Filter logic ──────────────────────────────────────────────────────────

  function applyFilters(loc: string, espece?: string, race?: string): boolean {
    if (filtreEspece !== 'tous' && espece?.toLowerCase() !== filtreEspece) return false;
    if (filtreRace && !race?.toLowerCase().includes(filtreRace.toLowerCase())) return false;
    if (filtreVille && !loc.includes(filtreVille.toLowerCase())) return false;
    if (filtreRegion) {
      const depts = departmentsInRegion(filtreRegion);
      if (!depts.some(d => loc.includes(d.toLowerCase())) && !loc.includes(filtreRegion.toLowerCase())) return false;
    }
    if (filtreDept && !loc.includes(filtreDept.toLowerCase())) return false;
    return true;
  }

  const filteredPerdus = (filterType === 'perdu' || filterType === 'tous') ? alertes.filter(a => {
    const loc = `${a.ville ?? ''} ${a.derniere_localisation ?? ''}`.toLowerCase();
    return applyFilters(loc, a.espece, a.race);
  }) : [];

  const filteredTrouves = (filterType === 'trouve' || filterType === 'tous') ? trouves.filter(a => {
    const loc = `${a.ville ?? ''} ${a.localisation_adresse ?? ''} ${a.region ?? ''}`.toLowerCase();
    return applyFilters(loc, a.espece, a.race);
  }) : [];

  const filtered = alertes.filter((a) => {
    const loc = `${a.ville ?? ''} ${a.derniere_localisation ?? ''}`.toLowerCase();
    return applyFilters(loc, a.espece, a.race);
  });

  const regionsDisponibles = filtrePays ? (REGIONS_BY_PAYS[filtrePays] ?? []) : [];
  const departementsDisponibles = filtreRegion ? departmentsInRegion(filtreRegion) : [];

  const distinctVilles = [...new Set(
    alertes.map(a => extractVille(a)).filter(Boolean)
  )].sort();

  // ── Map items ─────────────────────────────────────────────────────────────

  const withCoords: AlerteMapItem[] = [
    ...filteredPerdus
      .filter(a => a.lat != null && a.lng != null)
      .map(a => ({
        id: a.id,
        type: 'perdu' as const,
        nom_animal: a.nom_animal,
        espece: a.espece,
        race: a.race,
        photo_url: a.photo_url,
        derniere_localisation: a.derniere_localisation ?? a.ville,
        contact: a.contact,
        date_perte: a.date_perte,
        lat: a.lat!,
        lng: a.lng!,
        onDetail: () => setSelectedAlerte(a),
      })),
    ...filteredTrouves
      .filter(a => a.lat != null && a.lng != null)
      .map(a => ({
        id: a.id,
        type: 'trouve' as const,
        nom_animal: '',
        espece: a.espece,
        race: a.race,
        photo_url: a.photos?.[0],
        derniere_localisation: a.localisation_adresse ?? a.ville,
        date_trouve: a.date_trouve,
        lat: a.lat!,
        lng: a.lng!,
        onDetail: () => setSelectedTrouve(a),
      })),
  ];

  // ── Breed autocomplete ────────────────────────────────────────────────────

  function onRaceInput(val: string) {
    setFiltreRace(val);
    if (!val) { setRaceSugg([]); setShowRaceSugg(false); return; }
    const q = val.toLowerCase();
    const m = breeds.filter(b => b.toLowerCase().includes(q)).slice(0, 6);
    setRaceSugg(m); setShowRaceSugg(m.length > 0);
  }

  // ── Contact via messagerie ────────────────────────────────────────────────

  const contactViaMess = useCallback(async (a: Alerte) => {
    if (!user) { router.push('/connexion'); return; }
    const ownerUid = a.uid_proprietaire;
    if (!ownerUid || ownerUid === user.uid) return;

    setContacting(true);
    try {
      const ref  = a.numero_alerte ?? a.id;
      const sexe = a.sexe ? (SEXE_LABEL[a.sexe] ?? a.sexe) : '';
      const msg  = `Bonjour, je vous contacte au sujet de votre alerte N° ${ref} : ${a.nom_animal}${a.espece ? ` (${[a.espece, a.race, sexe].filter(Boolean).join(', ')})` : ''} perdu(e).`;

      // Find or create conversation
      const q = query(collection(db, 'conversations'), where('participants', 'array-contains', user.uid));
      const snap = await getDocs(q);
      let convId: string | null = null;
      snap.forEach(doc => {
        if ((doc.data().participants as string[])?.includes(ownerUid)) convId = doc.id;
      });

      if (!convId) {
        const convRef = await addDoc(collection(db, 'conversations'), {
          participants: [user.uid, ownerUid],
          lastMessage: msg,
          timestamp: serverTimestamp(),
          unreadCount: { [ownerUid]: 1 },
          categorie: 'animaux-perdus',
        });
        convId = convRef.id;
        await addDoc(collection(db, `conversations/${convId}/messages`), {
          text: msg, senderId: user.uid,
          timestamp: serverTimestamp(), isRead: false,
        });
      } else {
        // Always ensure the conversation is tagged as animaux-perdus
        const existingDoc = snap.docs.find(d => d.id === convId);
        if (existingDoc && existingDoc.data().categorie !== 'animaux-perdus') {
          await updateDoc(doc(db, 'conversations', convId!), { categorie: 'animaux-perdus' });
        }
      }
      router.push(`/messages?conv=${convId}`);
    } catch {
      setContacting(false);
    }
  }, [user, router]);

  // ── Owner actions (A03) ───────────────────────────────────────────────────

  const retrouveAlerte = useCallback(async (id: string) => {
    if (!confirm('Confirmer que votre animal a été retrouvé ?')) return;
    setActionLoading(true);
    try {
      await supabase.from('alertes_perdus').update({
        statut: 'retrouve',
        date_retrouve: new Date().toISOString().substring(0, 10),
      }).eq('id', id);
      setAlertes(prev => prev.filter(a => a.id !== id));
      setSelectedAlerte(null);
    } finally {
      setActionLoading(false);
    }
  }, []);

  const deleteAlerte = useCallback(async (id: string) => {
    if (!confirm('Supprimer cette alerte définitivement ?')) return;
    setActionLoading(true);
    try {
      await supabase.from('alertes_perdus').delete().eq('id', id);
      setAlertes(prev => prev.filter(a => a.id !== id));
      setSelectedAlerte(null);
    } finally {
      setActionLoading(false);
    }
  }, []);

  const deleteTrouve = useCallback(async (id: string) => {
    if (!confirm('Supprimer cette déclaration définitivement ?')) return;
    setActionLoading(true);
    try {
      await supabase.from('animaux_trouves').delete().eq('id', id);
      setTrouves(prev => prev.filter(a => a.id !== id));
      setSelectedTrouve(null);
    } finally {
      setActionLoading(false);
    }
  }, []);

  const totalFiltered = filteredPerdus.length + filteredTrouves.length;

  // ── Render ────────────────────────────────────────────────────────────────

  const filtresActifs = filtreEspece !== 'tous' || !!filtreRace || !!filtreVille || !!filtrePays || !!filtreRegion || !!filtreDept;
  const reinitialiserFiltres = () => {
    setFiltreEspece('tous'); setFiltreRace(''); setFiltreVille('');
    setFiltrePays(''); setFiltreRegion(''); setFiltreDept('');
  };
  const bascule = (actif: boolean) =>
    `px-4 py-2 text-sm font-semibold transition-colors ${actif ? 'bg-[#0C5C6C] text-white' : 'bg-white text-[#374151] hover:bg-gray-50'}`;

  return (
    <div className="bg-[#F6F7F5] min-h-screen" style={{ fontFamily: 'Galey, sans-serif' }}>
    <div className="max-w-6xl mx-auto px-4 py-8">

      {/* En-tête */}
      <h1 className="text-2xl sm:text-3xl font-bold text-[#1E2025]">Animaux perdus / trouvés</h1>
      <p className="text-gray-500 text-sm mt-1">
        {totalFiltered} résultat{totalFiltered !== 1 ? 's' : ''}
        {view === 'carte' && withCoords.length < totalFiltered ? ` · ${withCoords.length} sur la carte` : ''}
      </p>
      <div className="flex flex-wrap items-center gap-3 mt-4 mb-5">
        <a href="/animaux-perdus/declarer"
          className="inline-flex items-center justify-center bg-[#E8590C] hover:bg-[#C2410C] text-white font-semibold text-sm px-5 py-2.5 rounded-xl transition-colors">
          Déclarer un animal perdu
        </a>
        <a href="/animaux-perdus/declarer-trouve"
          className="inline-flex items-center justify-center bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold text-sm px-5 py-2.5 rounded-xl transition-colors">
          J&apos;ai trouvé un animal
        </a>
        <div className="sm:ml-auto inline-flex rounded-xl border border-[#E5E8E6] overflow-hidden" role="group" aria-label="Affichage">
          <button onClick={() => setView('liste')} aria-pressed={view === 'liste'} className={bascule(view === 'liste')}>Liste</button>
          <button onClick={() => setView('carte')} aria-pressed={view === 'carte'} className={`${bascule(view === 'carte')} border-l border-[#E5E8E6]`}>Carte</button>
        </div>
      </div>

      {/* ── Filtres ── */}
      <div className="bg-white border border-[#E5E8E6] rounded-2xl shadow-[0_1px_3px_rgba(16,24,40,0.06)] p-4 sm:p-5 mb-6">
        {/* Ligne 1 : Statut · Espèce · Race */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
          <div>
            <label className={LIBELLE} htmlFor="f-statut">Statut</label>
            <select id="f-statut" value={filterType} onChange={e => setFilterType(e.target.value as 'perdu' | 'trouve' | 'tous')} className={CHAMP}>
              <option value="tous">Tous</option>
              <option value="perdu">Perdus</option>
              <option value="trouve">Trouvés</option>
            </select>
          </div>
          <div>
            <label className={LIBELLE} htmlFor="f-espece">Espèce</label>
            <select id="f-espece" value={filtreEspece}
              onChange={e => { setFiltreEspece(e.target.value); setFiltreRace(''); setRaceSugg([]); }}
              className={CHAMP}>
              <option value="tous">Toutes les espèces</option>
              {ESPECES.map(e => <option key={e} value={e}>{nomEspece(e)}</option>)}
            </select>
          </div>
          <div className="relative">
            <label className={LIBELLE} htmlFor="f-race">Race</label>
            <input id="f-race" value={filtreRace}
              onChange={e => onRaceInput(e.target.value)}
              onFocus={() => filtreRace && setShowRaceSugg(raceSugg.length > 0)}
              onBlur={() => setTimeout(() => setShowRaceSugg(false), 150)}
              placeholder="Toutes les races"
              autoComplete="off"
              className={CHAMP} />
            {showRaceSugg && (
              <div className="absolute z-20 top-full left-0 right-0 mt-1 bg-white border border-[#E5E8E6] rounded-xl shadow-lg overflow-hidden">
                {raceSugg.map(b => (
                  <button key={b} type="button" onMouseDown={() => { setFiltreRace(b); setShowRaceSugg(false); }}
                    className="w-full text-left px-3 py-2 text-sm hover:bg-[#E8F4F6]">{b}</button>
                ))}
              </div>
            )}
          </div>
        </div>
        {/* Ligne 2 : Ville · Pays · Région · Département */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 mt-3 sm:mt-4">
          <div>
            <label className={LIBELLE} htmlFor="f-ville">
              Ville {userData?.ville && <span className="text-gray-400 font-normal">(votre ville par défaut)</span>}
            </label>
            <input id="f-ville" value={filtreVille} onChange={e => setFiltreVille(e.target.value)}
              placeholder="Ex : Rennes, Lyon…" className={CHAMP} />
          </div>
          <div>
            <label className={LIBELLE} htmlFor="f-pays">Pays</label>
            <select id="f-pays" value={filtrePays}
              onChange={e => { setFiltrePays(e.target.value); setFiltreRegion(''); setFiltreDept(''); }}
              className={CHAMP}>
              <option value="">Tous les pays</option>
              {PAYS_LIST.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>
          <div>
            <label className={LIBELLE} htmlFor="f-region">Région</label>
            <select id="f-region" value={filtreRegion}
              onChange={e => { setFiltreRegion(e.target.value); setFiltreDept(''); }}
              disabled={regionsDisponibles.length === 0} className={CHAMP}>
              <option value="">{filtrePays ? 'Toutes les régions' : 'Choisir un pays d\'abord'}</option>
              {regionsDisponibles.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </div>
          <div>
            <label className={LIBELLE} htmlFor="f-dept">Département</label>
            <select id="f-dept" value={filtreDept} onChange={e => setFiltreDept(e.target.value)}
              disabled={departementsDisponibles.length === 0} className={CHAMP}>
              <option value="">{filtreRegion ? 'Tous les départements' : 'Choisir une région d\'abord'}</option>
              {departementsDisponibles.map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </div>
        </div>
        {/* Réinitialiser (toujours visible) */}
        <button onClick={reinitialiserFiltres} disabled={!filtresActifs}
          className="mt-4 text-sm font-medium text-[#0C5C6C] underline underline-offset-2 hover:text-[#094F5D] disabled:text-gray-400 disabled:no-underline">
          Réinitialiser les filtres
        </button>
      </div>

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : view === 'carte' ? (
        <div className="relative isolate rounded-2xl overflow-hidden border border-[#E5E8E6] shadow-[0_1px_3px_rgba(16,24,40,0.06)]" style={{ height: '65vh' }}>
          <AnimauxPerdusMap alertes={withCoords} />
          {/* Légende des espèces (couleurs des marqueurs « Perdu ») */}
          <div className="absolute top-3 left-3 z-[1000] bg-white rounded-xl border border-[#E5E8E6] shadow-md text-sm max-w-[200px]">
            <button onClick={() => setLegendeOuverte(o => !o)} aria-expanded={legendeOuverte}
              className="w-full flex items-center justify-between gap-3 px-3 py-2 font-semibold text-[#0C5C6C]">
              Légende des espèces
              <Icone nom="fleche" taille={14} className={`transition-transform ${legendeOuverte ? '-rotate-90' : 'rotate-90'}`} />
            </button>
            {legendeOuverte && (
              <ul className="px-3 pb-3 space-y-1.5 max-h-[40vh] overflow-y-auto">
                {ESPECES.map(esp => (
                  <li key={esp} className="flex items-center gap-2 text-[#1E2025]">
                    <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: MARQUEUR_ESPECE[esp] ?? MARQUEUR_PERDU_DEFAUT }} />
                    {nomEspece(esp)}
                  </li>
                ))}
              </ul>
            )}
          </div>
          {/* Légende des statuts */}
          <div className="absolute top-3 right-3 z-[1000] bg-white rounded-xl border border-[#E5E8E6] shadow-md px-3 py-2 text-sm text-[#1E2025] space-y-1 pointer-events-none">
            <div className="flex items-center gap-2"><span className="w-2.5 h-2.5 rounded-full border-2 border-gray-400 flex-shrink-0" />Perdu <span className="text-gray-500">(couleur de l&apos;espèce)</span></div>
            <div className="flex items-center gap-2"><span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: MARQUEUR_TROUVE }} />Trouvé</div>
          </div>
        </div>
      ) : totalFiltered === 0 ? (
        <div className="text-center py-14 bg-white border border-[#E5E8E6] rounded-2xl">
          <p className="font-medium text-[#1E2025]">Aucun résultat pour ces filtres.</p>
          <button onClick={() => { setFiltreEspece('tous'); setFiltreRace(''); setFiltreVille(''); }}
            className="mt-3 text-sm font-medium text-[#0C5C6C] underline underline-offset-2">Réinitialiser les filtres</button>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {filteredPerdus.map(a => (
            <AlerteCard key={`p_${a.id}`} alerte={a} onClick={() => setSelectedAlerte(a)} />
          ))}
          {filteredTrouves.map(a => (
            <TrouveCard key={`t_${a.id}`} trouve={a} onClick={() => setSelectedTrouve(a)} />
          ))}
        </div>
      )}

      {/* Detail modal — perdu */}
      {selectedAlerte && (
        <AlerteDetailModal
          alerte={selectedAlerte}
          onClose={() => setSelectedAlerte(null)}
          onContactMess={() => contactViaMess(selectedAlerte)}
          contacting={contacting}
          actionLoading={actionLoading}
          user={user}
          onRetrouve={() => retrouveAlerte(selectedAlerte.id)}
          onDelete={() => deleteAlerte(selectedAlerte.id)}
        />
      )}

      {/* Detail modal — trouvé */}
      {selectedTrouve && (
        <TrouveDetailModal
          trouve={selectedTrouve}
          onClose={() => setSelectedTrouve(null)}
          actionLoading={actionLoading}
          user={user}
          onDelete={() => deleteTrouve(selectedTrouve.id)}
        />
      )}
    </div>
    </div>
  );
}

// ── Card ──────────────────────────────────────────────────────────────────────

function AlerteCard({ alerte: a, onClick }: { alerte: Alerte; onClick: () => void }) {
  const colors = ESPECE_COLORS[a.espece?.toLowerCase()] ?? ESPECE_COLORS.autre;
  const date   = fmtDate(a.date_perte);
  const loc    = extractVille(a);
  return (
    <CarteResultat onClick={onClick} photo={thumbUrl(a.photo_url)} alt={a.nom_animal} fond={colors.bg}
      espece={a.espece} pastille={colors.dot} statut="Perdu" statutCouleur="#C2410C" statutFond="#FFEDD5"
      titre={a.nom_animal} race={a.race} sexe={a.sexe} lieu={loc} date={date ? `Perdu le ${date}` : null} />
  );
}

/** Carte de résultat sobre, commune aux déclarations perdues et trouvées. */
function CarteResultat({ onClick, photo, alt, fond, espece, pastille, statut, statutCouleur, statutFond, titre, race, sexe, lieu, date }: {
  onClick: () => void; photo?: string; alt: string; fond: string; espece?: string; pastille: string;
  statut: string; statutCouleur: string; statutFond: string; titre: string; race?: string; sexe?: string;
  lieu?: string; date?: string | null;
}) {
  return (
    <button type="button" onClick={onClick}
      className="text-left bg-white rounded-2xl border border-[#E5E8E6] shadow-[0_1px_3px_rgba(16,24,40,0.06)] overflow-hidden hover:shadow-md transition-shadow group">
      <div className="aspect-[4/3] relative overflow-hidden bg-[#F3F4F6]">
        {photo
          ? <Image src={photo} alt={alt} fill className="object-contain group-hover:scale-[1.03] transition-transform duration-300" sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 25vw" />
          : <div className="w-full h-full flex items-center justify-center text-gray-400" style={{ background: fond }}><Icone nom="patte" taille={36} /></div>}
        <span className="absolute top-2 left-2 inline-flex items-center gap-1.5 bg-white/95 border border-[#E5E8E6] text-[#1E2025] text-xs font-semibold px-2 py-0.5 rounded-full">
          <span className="w-2 h-2 rounded-full" style={{ background: pastille }} />{nomEspece(espece)}
        </span>
        <span className="absolute top-2 right-2 text-xs font-semibold px-2 py-0.5 rounded-full"
          style={{ color: statutCouleur, background: statutFond, border: `1px solid ${statutCouleur}33` }}>
          {statut}
        </span>
      </div>
      <div className="p-4">
        <h3 className="font-bold text-[#1E2025] text-[15px] truncate">{titre}</h3>
        {(race || sexe) && (
          <p className="text-sm text-gray-600 truncate capitalize">{[race, sexe ? (SEXE_LABEL[sexe] ?? sexe) : null].filter(Boolean).join(' · ')}</p>
        )}
        {lieu && <p className="text-gray-500 text-xs mt-1.5 truncate flex items-center gap-1"><Icone nom="pin" taille={13} className="flex-shrink-0" />{lieu}</p>}
        {date && <p className="text-gray-500 text-xs mt-0.5 flex items-center gap-1"><Icone nom="calendrier" taille={13} className="flex-shrink-0" />{date}</p>}
        <p className="mt-3 pt-3 border-t border-[#EEF0EE] text-xs font-semibold text-[#0C5C6C]">Voir le détail →</p>
      </div>
    </button>
  );
}

// ── Detail modal ──────────────────────────────────────────────────────────────

function AlerteDetailModal({
  alerte: a, onClose, onContactMess, contacting, actionLoading, user, onRetrouve, onDelete
}: {
  alerte: Alerte;
  onClose: () => void;
  onContactMess: () => void;
  contacting: boolean;
  actionLoading: boolean;
  user: { uid: string } | null;
  onRetrouve: () => void;
  onDelete: () => void;
}) {
  const colors   = ESPECE_COLORS[a.espece?.toLowerCase()] ?? ESPECE_COLORS.autre;
  const isOwner  = user?.uid === a.uid_proprietaire;
  const [copied, setCopied] = useState(false);

  async function handleShare() {
    const origin = typeof window !== 'undefined' ? window.location.origin : '';
    const url    = `${origin}/animaux-perdus`;
    const loc    = a.derniere_localisation ?? a.ville ?? '';
    const date   = a.date_perte ? `perdu le ${fmtDate(a.date_perte)}` : '';
    const text   = [
      `ANIMAL PERDU — ${a.nom_animal}${a.espece ? ` (${a.espece})` : ''}`,
      loc  ? `Lieu : ${loc}` : null,
      date ? date.charAt(0).toUpperCase() + date.slice(1) : null,
      'Aidez à retrouver cet animal !',
    ].filter(Boolean).join('\n');
    const title = `Animal perdu : ${a.nom_animal}`;

    if (typeof navigator.share === 'function') {
      try {
        if (a.photo_url && typeof navigator.canShare === 'function') {
          try {
            const resp = await fetch(a.photo_url);
            const blob = await resp.blob();
            const file = new File([blob], 'animal.jpg', { type: blob.type || 'image/jpeg' });
            if (navigator.canShare({ files: [file] })) {
              await navigator.share({ title, text, url, files: [file] });
              return;
            }
          } catch {}
        }
        await navigator.share({ title, text, url });
        return;
      } catch (err) {
        if ((err as Error).name === 'AbortError') return;
      }
    }
    try {
      await navigator.clipboard.writeText(`${text}\n\n${url}`);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    } catch {}
  }

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto shadow-2xl"
        onClick={e => e.stopPropagation()}>

        {/* Photo */}
        <div className="relative aspect-video bg-gray-50">
          {a.photo_url
            ? <Image src={a.photo_url} alt={a.nom_animal} fill className="object-contain" sizes="(max-width: 768px) 100vw, 512px" />
            : <div className="w-full h-full flex items-center justify-center text-gray-400" style={{ background: colors.bg }}><Icone nom="patte" taille={56} /></div>}
          <button onClick={onClose} aria-label="Fermer"
            className="absolute top-3 right-3 w-8 h-8 bg-black/50 hover:bg-black/70 text-white rounded-full flex items-center justify-center text-lg transition-colors">
            ×
          </button>
          <span className="absolute top-3 left-3 inline-flex items-center gap-1.5 text-sm font-semibold px-3 py-1 rounded-full bg-white/95 text-[#1E2025] border border-[#E5E8E6]">
            <span className="w-2 h-2 rounded-full" style={{ background: colors.dot }} />{nomEspece(a.espece)} — Perdu
          </span>
          {a.numero_alerte && (
            <span className="absolute bottom-3 right-3 text-xs bg-black/60 text-white px-2 py-1 rounded-full">
              N° {a.numero_alerte}
            </span>
          )}
        </div>

        <div className="p-5">
          {/* Nom */}
          <h2 className="text-2xl font-bold text-[#1F2A2E] mb-1">{a.nom_animal}</h2>

          {/* Infos identité */}
          <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 mb-4 text-sm">
            {a.race && <InfoRow label="Race" value={a.race} />}
            {a.sexe && <InfoRow label="Sexe" value={SEXE_LABEL[a.sexe] ?? a.sexe} />}
            {a.couleur && <InfoRow label="Couleur" value={a.couleur} />}
            {a.couleur_yeux && <InfoRow label="Couleur des yeux" value={a.couleur_yeux} />}
            {a.identification && <InfoRow label="Identification" value={a.identification} />}
          </div>

          {/* Localisation + dates */}
          <div className="bg-[#FFF7ED] border border-[#FED7AA] rounded-xl p-3 mb-4 space-y-1">
            {(a.derniere_localisation ?? a.ville) && (
              <p className="text-sm text-orange-800">
                <span className="font-semibold">Dernière localisation :</span> {a.derniere_localisation ?? a.ville}
              </p>
            )}
            {a.date_perte && (
              <p className="text-sm text-orange-700">
                <span className="font-semibold">Disparu le :</span> {fmtDate(a.date_perte)}
              </p>
            )}
            {a.date_derniere_localisation && a.date_derniere_localisation !== a.date_perte && (
              <p className="text-sm text-orange-700">
                <span className="font-semibold">Vu en dernier le :</span> {fmtDate(a.date_derniere_localisation)}
              </p>
            )}
          </div>

          {/* Description */}
          {a.description && (
            <div className="mb-4">
              <p className="text-xs font-semibold text-gray-500 mb-1">Description</p>
              <p className="text-sm text-gray-700 leading-relaxed">{a.description}</p>
            </div>
          )}

          {/* Boutons contact */}
          {!isOwner && (
            <div className="space-y-2">
              {a.contact && (
                <a href={a.contact.includes('@') ? `mailto:${a.contact}` : `tel:${a.contact}`}
                  className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm text-white transition-colors"
                  style={{ background: '#0C5C6C' }}>
                  {a.contact.includes('@') ? 'Envoyer un e-mail' : `Appeler : ${a.contact}`}
                </a>
              )}
              {user && a.uid_proprietaire && (
                <button onClick={onContactMess} disabled={contacting}
                  className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm bg-[#0C5C6C] hover:bg-[#094F5D] text-white transition-colors disabled:opacity-60">
                  {contacting
                    ? <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> Connexion…</>
                    : 'Contacter via la messagerie'}
                </button>
              )}
              {!user && (
                <a href="/connexion"
                  className="flex items-center justify-center w-full py-3 rounded-xl font-semibold text-sm bg-gray-100 text-gray-600 hover:bg-gray-200 transition-colors">
                  Connectez-vous pour envoyer un message
                </a>
              )}
            </div>
          )}
          {isOwner && (
            <div className="space-y-2">
              <button onClick={onRetrouve} disabled={actionLoading}
                className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm bg-[#EEF5EA] text-[#6E9E57] hover:bg-[#DCF0D2] transition-colors disabled:opacity-60">
                Animal retrouvé
              </button>
              <button onClick={onDelete} disabled={actionLoading}
                className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm bg-red-50 text-red-600 hover:bg-red-100 transition-colors disabled:opacity-60">
                Supprimer l&apos;alerte
              </button>
              <a href="/mes-alertes"
                className="flex items-center justify-center w-full py-2 rounded-xl text-sm border border-gray-200 text-gray-500 hover:bg-gray-50 transition-colors">
                Modifier / Mettre à jour →
              </a>
            </div>
          )}

          {/* Partager — toujours visible */}
          <button onClick={handleShare}
            className="flex items-center justify-center gap-2 w-full py-2.5 mt-2 rounded-xl text-sm font-semibold border border-gray-200 text-gray-500 hover:bg-gray-50 transition-colors">
            {copied
              ? <>Lien copié</>
              : <><svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
                </svg> Partager cette alerte</>}
          </button>
        </div>
      </div>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start gap-1.5">
      <div>
        <span className="text-xs text-gray-400">{label} </span>
        <span className="text-sm font-medium text-gray-700 capitalize">{value}</span>
      </div>
    </div>
  );
}

// ── Trouvé card ───────────────────────────────────────────────────────────────

function TrouveCard({ trouve: a, onClick }: { trouve: Trouve; onClick: () => void }) {
  const colors = ESPECE_COLORS[a.espece?.toLowerCase()] ?? ESPECE_COLORS.autre;
  const date = fmtDate(a.date_trouve);
  const loc = a.localisation_adresse ?? a.ville ?? '';
  return (
    <CarteResultat onClick={onClick} photo={a.photos?.[0]} alt="Animal trouvé" fond={colors.bg}
      espece={a.espece} pastille={colors.dot} statut="Trouvé" statutCouleur="#0C5C6C" statutFond="#E8F4F6"
      titre={a.espece ? `${nomEspece(a.espece)} trouvé${a.sexe === 'femelle' ? 'e' : ''}` : 'Animal trouvé'}
      race={a.race} sexe={a.sexe} lieu={loc} date={date ? `Trouvé le ${date}` : null} />
  );
}

// ── Trouvé detail modal ───────────────────────────────────────────────────────

function TrouveDetailModal({
  trouve: a, onClose, actionLoading, user, onDelete,
}: {
  trouve: Trouve;
  onClose: () => void;
  actionLoading: boolean;
  user: { uid: string } | null;
  onDelete: () => void;
}) {
  const colors  = ESPECE_COLORS[a.espece?.toLowerCase()] ?? ESPECE_COLORS.autre;
  const isOwner = user?.uid === a.uid_declarant;
  const photos  = a.photos ?? [];
  const [photoIdx, setPhotoIdx] = useState(0);
  const photoUrl = photos[photoIdx];
  const accepte  = a.accepte_messagerie !== false;

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto shadow-2xl"
        onClick={e => e.stopPropagation()}>

        {/* Photo(s) */}
        <div className="relative aspect-video bg-gray-50">
          {photoUrl
            ? <Image src={photoUrl} alt="Animal trouvé" fill className="object-contain" sizes="(max-width: 768px) 100vw, 512px" />
            : <div className="w-full h-full flex items-center justify-center text-gray-400" style={{ background: colors.bg }}><Icone nom="patte" taille={56} /></div>}
          <button onClick={onClose} aria-label="Fermer"
            className="absolute top-3 right-3 w-8 h-8 bg-black/50 hover:bg-black/70 text-white rounded-full flex items-center justify-center text-lg transition-colors">
            ×
          </button>
          <span className="absolute top-3 left-3 inline-flex items-center gap-1.5 text-sm font-semibold px-3 py-1 rounded-full bg-white/95 text-[#1E2025] border border-[#E5E8E6]">
            <span className="w-2 h-2 rounded-full" style={{ background: colors.dot }} />{nomEspece(a.espece)} — Trouvé
          </span>
          {photos.length > 1 && (
            <div className="absolute bottom-3 left-0 right-0 flex justify-center gap-2">
              {photos.map((_, i) => (
                <button key={i} onClick={() => setPhotoIdx(i)}
                  className={`rounded-full transition-all ${i === photoIdx ? 'w-4 h-2.5 bg-white' : 'w-2.5 h-2.5 bg-white/60'}`} />
              ))}
            </div>
          )}
        </div>

        <div className="p-5">
          <h2 className="text-xl font-bold text-[#1F2A2E] mb-1">
            {a.espece ? `${a.espece.charAt(0).toUpperCase()}${a.espece.slice(1)} trouvé${a.sexe === 'femelle' ? 'e' : ''}` : 'Animal trouvé'}
          </h2>

          {/* Infos */}
          <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 mb-4 text-sm">
            {a.race && <InfoRow label="Race" value={a.race} />}
            {a.sexe && <InfoRow label="Sexe" value={a.sexe} />}
            {a.taille && <InfoRow label="Taille" value={a.taille} />}
            {a.couleur && <InfoRow label="Couleur" value={a.couleur} />}
            {a.couleur_yeux && <InfoRow label="Couleur des yeux" value={a.couleur_yeux} />}
            {a.numero_puce && <InfoRow label="Puce" value={a.numero_puce} />}
          </div>

          {/* Date + lieu */}
          <div className="bg-[#E8F4F6] border border-[#89CDD8] rounded-xl p-3 mb-4 space-y-1">
            {(a.localisation_adresse ?? a.ville) && (
              <p className="text-sm text-[#0C5C6C]">
                <span className="font-semibold">Trouvé à :</span> {a.localisation_adresse ?? a.ville}
              </p>
            )}
            {a.date_trouve && (
              <p className="text-sm text-[#0C5C6C]">
                <span className="font-semibold">Trouvé le :</span> {fmtDate(a.date_trouve)}
              </p>
            )}
          </div>

          {a.etat_sante && (
            <div className="mb-3">
              <p className="text-xs font-semibold text-gray-500 mb-1">État de santé</p>
              <p className="text-sm text-gray-700">{a.etat_sante}</p>
            </div>
          )}
          {a.comportement && (
            <div className="mb-3">
              <p className="text-xs font-semibold text-gray-500 mb-1">Comportement</p>
              <p className="text-sm text-gray-700">{a.comportement}</p>
            </div>
          )}
          {a.description && (
            <div className="mb-4">
              <p className="text-xs font-semibold text-gray-500 mb-1">Description</p>
              <p className="text-sm text-gray-700 leading-relaxed">{a.description}</p>
            </div>
          )}

          {/* Contact */}
          {!isOwner && (
            <div className="space-y-2">
              {accepte ? (
                <p className="text-sm text-center text-gray-500 py-2 bg-[#E8F4F6] rounded-xl">
                  Connectez-vous pour contacter via la messagerie
                </p>
              ) : (
                <>
                  {a.contact_telephone && (
                    <a href={`tel:${a.contact_telephone}`}
                      className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm bg-[#0C5C6C] text-white hover:bg-[#094F5D] transition-colors">
                      Appeler : {a.contact_telephone}
                    </a>
                  )}
                  {a.contact_email && (
                    <a href={`mailto:${a.contact_email}`}
                      className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm bg-gray-100 text-gray-700 hover:bg-gray-200 transition-colors">
                      {a.contact_email}
                    </a>
                  )}
                </>
              )}
            </div>
          )}
          {isOwner && (
            <div className="space-y-2">
              <button onClick={onDelete} disabled={actionLoading}
                className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm bg-red-50 text-red-600 hover:bg-red-100 transition-colors disabled:opacity-60">
                Supprimer la déclaration
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

