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

const AnimauxPerdusMap = dynamic(() => import('@/components/AnimauxPerdusMap'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100 rounded-2xl">
      <div className="w-8 h-8 border-2 border-[#EF4444] border-t-transparent rounded-full animate-spin" />
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

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐇',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷', autre: '🐾',
};

const SEXE_LABEL: Record<string, string> = { male: '♂ Mâle', femelle: '♀ Femelle', inconnu: 'Inconnu' };

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
  const [loading, setLoading]       = useState(true);
  const [view, setView]             = useState<'liste' | 'carte'>('liste');
  const [selectedAlerte, setSelectedAlerte] = useState<Alerte | null>(null);
  const [contacting, setContacting] = useState(false);

  // Filtres
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
    supabase
      .from('alertes_perdus')
      .select('*')
      .eq('statut', 'perdu')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setAlertes((data as Alerte[]) ?? []);
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

  const filtered = alertes.filter((a) => {
    if (filtreEspece !== 'tous' && a.espece?.toLowerCase() !== filtreEspece) return false;
    if (filtreRace && !a.race?.toLowerCase().includes(filtreRace.toLowerCase())) return false;
    if (filtreVille) {
      const loc = `${a.ville ?? ''} ${a.derniere_localisation ?? ''}`.toLowerCase();
      if (!loc.includes(filtreVille.toLowerCase())) return false;
    }
    if (filtreRegion) {
      const depts = departmentsInRegion(filtreRegion);
      const loc = `${a.ville ?? ''} ${a.derniere_localisation ?? ''}`.toLowerCase();
      if (!depts.some(d => loc.includes(d.toLowerCase())) && !loc.includes(filtreRegion.toLowerCase())) return false;
    }
    if (filtreDept) {
      const loc = `${a.ville ?? ''} ${a.derniere_localisation ?? ''}`.toLowerCase();
      if (!loc.includes(filtreDept.toLowerCase())) return false;
    }
    return true;
  });

  const regionsDisponibles = filtrePays ? (REGIONS_BY_PAYS[filtrePays] ?? []) : [];
  const departementsDisponibles = filtreRegion ? departmentsInRegion(filtreRegion) : [];

  const distinctVilles = [...new Set(
    alertes.map(a => extractVille(a)).filter(Boolean)
  )].sort();

  // ── Map items ─────────────────────────────────────────────────────────────

  const withCoords: AlerteMapItem[] = filtered
    .filter(a => a.lat != null && a.lng != null)
    .map(a => ({
      id: a.id,
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
    }));

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

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="max-w-6xl mx-auto px-4 py-10">

      {/* En-tête */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
        <div>
          <h1 className="text-3xl font-bold text-[#1F2A2E] mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            Animaux perdus
          </h1>
          <p className="text-gray-500 text-sm">
            {filtered.length} alerte{filtered.length !== 1 ? 's' : ''}
            {view === 'carte' && withCoords.length < filtered.length ? ` · ${withCoords.length} sur la carte` : ''}
          </p>
        </div>
        <div className="flex items-center gap-3 flex-wrap">
          <a href="/animaux-perdus/declarer"
            className="flex items-center gap-2 bg-orange-600 hover:bg-orange-700 text-white font-semibold text-sm px-4 py-2.5 rounded-xl transition-colors shadow-sm">
            📍 Déclarer un animal perdu
          </a>
          {/* Toggle liste / carte */}
          <div className="flex bg-gray-100 rounded-xl p-1">
            <button onClick={() => setView('liste')}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${view === 'liste' ? 'bg-white text-[#1F2A2E] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
              ☰ Liste
            </button>
            <button onClick={() => setView('carte')}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${view === 'carte' ? 'bg-white text-[#1F2A2E] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
              🗺 Carte
            </button>
          </div>
        </div>
      </div>

      {/* ── Filtres ── */}
      <div className="bg-white border border-gray-100 rounded-2xl shadow-sm p-4 mb-6 space-y-3">
        {/* Ligne 1 : Espèce · Race · Ville */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Espèce</label>
            <select value={filtreEspece}
              onChange={e => { setFiltreEspece(e.target.value); setFiltreRace(''); setRaceSugg([]); }}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white">
              <option value="tous">Toutes les espèces</option>
              {ESPECES.map(e => (
                <option key={e} value={e}>{ESPECE_EMOJI[e]} {e.charAt(0).toUpperCase() + e.slice(1)}</option>
              ))}
            </select>
          </div>
          <div className="relative">
            <label className="block text-xs font-semibold text-gray-500 mb-1">Race</label>
            <input value={filtreRace}
              onChange={e => onRaceInput(e.target.value)}
              onFocus={() => filtreRace && setShowRaceSugg(raceSugg.length > 0)}
              onBlur={() => setTimeout(() => setShowRaceSugg(false), 150)}
              placeholder="Toutes les races"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white" />
            {showRaceSugg && (
              <div className="absolute z-20 top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                {raceSugg.map(b => (
                  <button key={b} type="button" onMouseDown={() => { setFiltreRace(b); setShowRaceSugg(false); }}
                    className="w-full text-left px-3 py-2 text-sm hover:bg-orange-50">{b}</button>
                ))}
              </div>
            )}
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">
              Ville {userData?.ville && <span className="text-orange-500 font-normal">(votre ville par défaut)</span>}
            </label>
            <input value={filtreVille} onChange={e => setFiltreVille(e.target.value)}
              placeholder="Ex : Rennes, Lyon…"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white" />
          </div>
        </div>
        {/* Ligne 2 : Pays · Région · Département */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Pays</label>
            <select value={filtrePays}
              onChange={e => { setFiltrePays(e.target.value); setFiltreRegion(''); setFiltreDept(''); }}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white">
              <option value="">Tous les pays</option>
              {PAYS_LIST.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Région</label>
            <select value={filtreRegion}
              onChange={e => { setFiltreRegion(e.target.value); setFiltreDept(''); }}
              disabled={regionsDisponibles.length === 0}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white disabled:opacity-50">
              <option value="">{filtrePays ? 'Toutes les régions' : 'Pays d\'abord'}</option>
              {regionsDisponibles.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Département</label>
            <select value={filtreDept} onChange={e => setFiltreDept(e.target.value)}
              disabled={departementsDisponibles.length === 0}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white disabled:opacity-50">
              <option value="">{filtreRegion ? 'Tous les départements' : 'Région d\'abord'}</option>
              {departementsDisponibles.map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </div>
        </div>
        {/* Reset */}
        {(filtreEspece !== 'tous' || filtreRace || filtreVille || filtrePays || filtreRegion || filtreDept) && (
          <button onClick={() => {
            setFiltreEspece('tous'); setFiltreRace(''); setFiltreVille('');
            setFiltrePays(''); setFiltreRegion(''); setFiltreDept('');
          }} className="text-xs text-gray-400 hover:text-gray-600 underline">
            Réinitialiser les filtres
          </button>
        )}
      </div>

      {/* Légende espèces */}
      <div className="flex flex-wrap gap-2 mb-5">
        {ESPECES.map(esp => {
          const c = ESPECE_COLORS[esp];
          const active = filtreEspece === esp;
          return (
            <button key={esp} onClick={() => setFiltreEspece(active ? 'tous' : esp)}
              className="flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full border transition-all"
              style={{ background: active ? c.dot : c.bg, color: active ? 'white' : c.text, borderColor: active ? c.dot : c.border }}>
              <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: active ? 'rgba(255,255,255,0.7)' : c.dot }} />
              {ESPECE_EMOJI[esp]} {esp.charAt(0).toUpperCase() + esp.slice(1)}
            </button>
          );
        })}
      </div>

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="w-8 h-8 border-2 border-[#EF4444] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : view === 'carte' ? (
        <div className="rounded-2xl overflow-hidden border border-gray-200 shadow-sm" style={{ height: '65vh' }}>
          <AnimauxPerdusMap alertes={withCoords} />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400">
          <div className="text-5xl mb-4">🔍</div>
          <p className="font-medium">Aucun animal perdu pour ces filtres</p>
          <button onClick={() => { setFiltreEspece('tous'); setFiltreRace(''); setFiltreVille(''); }}
            className="mt-3 text-sm text-orange-500 underline">Voir tous les animaux</button>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {filtered.map(a => (
            <AlerteCard key={a.id} alerte={a} onClick={() => setSelectedAlerte(a)} />
          ))}
        </div>
      )}

      {/* Detail modal */}
      {selectedAlerte && (
        <AlerteDetailModal
          alerte={selectedAlerte}
          onClose={() => setSelectedAlerte(null)}
          onContactMess={() => contactViaMess(selectedAlerte)}
          contacting={contacting}
          user={user}
        />
      )}
    </div>
  );
}

// ── Card ──────────────────────────────────────────────────────────────────────

function AlerteCard({ alerte: a, onClick }: { alerte: Alerte; onClick: () => void }) {
  const colors = ESPECE_COLORS[a.espece?.toLowerCase()] ?? ESPECE_COLORS.autre;
  const date   = fmtDate(a.date_perte);
  const loc    = extractVille(a);

  return (
    <div onClick={onClick} className="bg-white rounded-2xl shadow-sm border overflow-hidden hover:shadow-md transition-all cursor-pointer group"
      style={{ borderColor: colors.border }}>
      <div className="aspect-square relative overflow-hidden bg-gray-50">
        {thumbUrl(a.photo_url)
          ? <Image src={thumbUrl(a.photo_url)!} alt={a.nom_animal} fill className="object-contain group-hover:scale-105 transition-transform duration-300" sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw" />
          : <div className="w-full h-full flex items-center justify-center text-5xl" style={{ background: colors.bg }}>{ESPECE_EMOJI[a.espece] ?? '🐾'}</div>}
        {/* Badge espèce */}
        <span className="absolute top-2 left-2 text-xs font-bold px-2 py-0.5 rounded-full"
          style={{ background: colors.dot, color: 'white' }}>
          {ESPECE_EMOJI[a.espece] ?? '🐾'} {a.espece?.charAt(0).toUpperCase() + (a.espece?.slice(1) ?? '')}
        </span>
        <span className="absolute top-2 right-2 bg-red-500 text-white text-xs font-semibold px-2 py-0.5 rounded-full">
          Perdu
        </span>
      </div>
      <div className="p-4">
        <h3 className="font-bold text-[#1F2A2E] text-base truncate">{a.nom_animal}</h3>
        {a.race && <p className="text-sm capitalize truncate" style={{ color: colors.text }}>{a.race}</p>}
        {a.sexe && <p className="text-xs text-gray-400">{SEXE_LABEL[a.sexe] ?? a.sexe}</p>}
        {loc && <p className="text-gray-400 text-xs mt-1 truncate">📍 {loc}</p>}
        {date && <p className="text-gray-400 text-xs">🗓 Perdu le {date}</p>}
        <div className="mt-3 text-center text-xs font-semibold py-1.5 rounded-lg"
          style={{ background: colors.bg, color: colors.text }}>
          Voir le détail →
        </div>
      </div>
    </div>
  );
}

// ── Detail modal ──────────────────────────────────────────────────────────────

function AlerteDetailModal({
  alerte: a, onClose, onContactMess, contacting, user
}: {
  alerte: Alerte;
  onClose: () => void;
  onContactMess: () => void;
  contacting: boolean;
  user: { uid: string } | null;
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
      `🚨 ANIMAL PERDU — ${a.nom_animal}${a.espece ? ` (${a.espece})` : ''}`,
      loc  ? `📍 ${loc}` : null,
      date ? `🗓 ${date}` : null,
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
            : <div className="w-full h-full flex items-center justify-center text-8xl" style={{ background: colors.bg }}>{ESPECE_EMOJI[a.espece] ?? '🐾'}</div>}
          <button onClick={onClose}
            className="absolute top-3 right-3 w-8 h-8 bg-black/50 hover:bg-black/70 text-white rounded-full flex items-center justify-center text-lg transition-colors">
            ×
          </button>
          <span className="absolute top-3 left-3 text-sm font-bold px-3 py-1 rounded-full"
            style={{ background: colors.dot, color: 'white' }}>
            {ESPECE_EMOJI[a.espece] ?? '🐾'} {a.espece?.charAt(0).toUpperCase() + (a.espece?.slice(1) ?? '')} — Perdu
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
            {a.race && <InfoRow icon="🐾" label="Race" value={a.race} />}
            {a.sexe && <InfoRow icon={a.sexe === 'male' ? '♂' : a.sexe === 'femelle' ? '♀' : '?'} label="Sexe" value={SEXE_LABEL[a.sexe] ?? a.sexe} />}
            {a.couleur && <InfoRow icon="🎨" label="Couleur" value={a.couleur} />}
            {a.identification && <InfoRow icon="💾" label="Identification" value={a.identification} />}
          </div>

          {/* Localisation + dates */}
          <div className="bg-orange-50 border border-orange-100 rounded-xl p-3 mb-4 space-y-1">
            {(a.derniere_localisation ?? a.ville) && (
              <p className="text-sm text-orange-800">
                <span className="font-semibold">📍 Dernière localisation :</span> {a.derniere_localisation ?? a.ville}
              </p>
            )}
            {a.date_perte && (
              <p className="text-sm text-orange-700">
                <span className="font-semibold">🗓 Disparu le :</span> {fmtDate(a.date_perte)}
              </p>
            )}
            {a.date_derniere_localisation && a.date_derniere_localisation !== a.date_perte && (
              <p className="text-sm text-orange-700">
                <span className="font-semibold">📅 Vu en dernier le :</span> {fmtDate(a.date_derniere_localisation)}
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
                  style={{ background: colors.dot }}>
                  {a.contact.includes('@') ? '✉️ Envoyer un email' : `📞 Appeler : ${a.contact}`}
                </a>
              )}
              {user && a.uid_proprietaire && (
                <button onClick={onContactMess} disabled={contacting}
                  className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-semibold text-sm bg-[#0C5C6C] hover:bg-[#094F5D] text-white transition-colors disabled:opacity-60">
                  {contacting
                    ? <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> Connexion…</>
                    : '💬 Contacter via la messagerie'}
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
            <a href="/mes-alertes"
              className="flex items-center justify-center w-full py-3 rounded-xl font-semibold text-sm border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors">
              Gérer mon alerte →
            </a>
          )}

          {/* Partager — toujours visible */}
          <button onClick={handleShare}
            className="flex items-center justify-center gap-2 w-full py-2.5 mt-2 rounded-xl text-sm font-semibold border border-gray-200 text-gray-500 hover:bg-gray-50 transition-colors">
            {copied
              ? <><span>✅</span> Lien copié !</>
              : <><svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
                </svg> Partager cette alerte</>}
          </button>
        </div>
      </div>
    </div>
  );
}

function InfoRow({ icon, label, value }: { icon: string; label: string; value: string }) {
  return (
    <div className="flex items-start gap-1.5">
      <span className="text-sm">{icon}</span>
      <div>
        <span className="text-xs text-gray-400">{label} </span>
        <span className="text-sm font-medium text-gray-700 capitalize">{value}</span>
      </div>
    </div>
  );
}

