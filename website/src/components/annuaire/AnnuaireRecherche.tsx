'use client';

// Annuaire des professionnels — page unique : recherche + filtres en haut
// (animaux concernés à cases à cocher, ville / code postal, rayon),
// catégories en cartes, types de service de la catégorie choisie, filtres
// actifs supprimables, résultats. Sur mobile, les filtres sont regroupés dans
// un panneau « Filtres ». Critères combinables (ex. Transport + Taxi
// animalier + Chevaux). Logique partagée : src/lib/annuaire-filtres.ts —
// miroir app : lib/pages/services/services_page.dart.

import { useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import type { ProMapItem } from '@/components/ServicesMap';
import AnimauxMultiSelect from '@/components/annuaire/AnimauxMultiSelect';
import LieuPicker from '@/components/annuaire/LieuPicker';
import {
  CATEGORIES_ANNUAIRE, GROUPES_ESPECES, RAYONS_KM,
  categorieByKey, metierByKey, metierFromLegacy, metierSelectionne, selectionDepuisMetier,
  proMatchesMetier, proMatchesEspeces, proDansZone, groupesDesEspeces, haversineKm,
  type LieuRecherche,
} from '@/lib/annuaire-filtres';

const ServicesMap = dynamic(() => import('@/components/ServicesMap'), { ssr: false });

type Pro = ProMapItem & { se_deplace?: boolean | null; description?: string };

const font = { fontFamily: 'Galey, sans-serif' };

function lireUrl(sp: URLSearchParams) {
  const especesValides = new Set(GROUPES_ESPECES.map(g => g.key));
  let categorie = sp.get('categorie') ?? '';
  let type = sp.get('type') ?? '';
  // Anciens liens : ?metier=… ou ?cat=…&prof=…
  if (!categorie && !type && (sp.has('metier') || sp.has('cat'))) {
    const m = sp.has('metier') ? metierByKey(sp.get('metier')).key : metierFromLegacy(sp.get('cat'), sp.get('prof')).key;
    ({ categorie, type } = selectionDepuisMetier(m));
  }
  if (!categorieByKey(categorie)) { categorie = ''; type = ''; }
  if (type && !categorieByKey(categorie)?.types.includes(type)) type = '';
  const lat = parseFloat(sp.get('lat') ?? ''), lng = parseFloat(sp.get('lng') ?? '');
  const lieuLabel = sp.get('lieu');
  const rayon = parseInt(sp.get('rayon') ?? '', 10);
  return {
    q: sp.get('q') ?? '',
    categorie, type,
    especes: (sp.get('especes') ?? '').split(',').filter(k => especesValides.has(k)),
    lieu: lieuLabel && !isNaN(lat) && !isNaN(lng) ? { label: lieuLabel, lat, lng, ville: sp.get('ville') ?? undefined } as LieuRecherche : null,
    rayon: RAYONS_KM.includes(rayon) ? rayon : 50,
    view: (sp.get('view') === 'map' ? 'map' : 'list') as 'map' | 'list',
  };
}

export default function AnnuaireRecherche() {
  const { user } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const init = useMemo(() => lireUrl(new URLSearchParams(searchParams.toString())), []); // eslint-disable-line react-hooks/exhaustive-deps

  const [pros, setPros] = useState<Pro[]>([]);
  const [creneauOk, setCreneauOk] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [maPosition, setMaPosition] = useState<LieuRecherche | null>(null);

  const [qSaisie, setQSaisie] = useState(init.q);
  const [q, setQ] = useState(init.q);
  const [categorie, setCategorie] = useState(init.categorie);
  const [type, setType] = useState(init.type);
  const [especes, setEspeces] = useState<string[]>(init.especes);
  const [lieu, setLieu] = useState<LieuRecherche | null>(init.lieu);
  const [rayon, setRayon] = useState(init.rayon);
  const [view, setView] = useState<'map' | 'list'>(init.view);
  const [panneau, setPanneau] = useState(false); // panneau Filtres (mobile)

  useEffect(() => { charger(); }, []);

  useEffect(() => {
    if (!user) { setMaPosition(null); return; }
    supabase.from('user_profiles_complet').select('lat, lng, ville')
      .eq('uid', user.uid).eq('is_main', true).maybeSingle()
      .then(({ data }) => {
        const lat = data?.lat as number | null, lng = data?.lng as number | null;
        setMaPosition(lat != null && lng != null
          ? { label: 'Autour de moi', lat, lng, ville: (data?.ville as string) || undefined } : null);
      });
  }, [user]);

  // URL ↔ recherche (retour depuis une fiche = même recherche)
  useEffect(() => {
    const p = new URLSearchParams();
    if (q) p.set('q', q);
    if (categorie) p.set('categorie', categorie);
    if (type) p.set('type', type);
    if (especes.length) p.set('especes', especes.join(','));
    if (lieu) {
      p.set('lieu', lieu.label); p.set('lat', String(lieu.lat)); p.set('lng', String(lieu.lng));
      if (lieu.ville) p.set('ville', lieu.ville);
      p.set('rayon', String(rayon));
    }
    if (view === 'map') p.set('view', 'map');
    const qs = p.toString();
    router.replace(qs ? `/services?${qs}` : '/services', { scroll: false });
  }, [q, categorie, type, especes, lieu, rayon, view, router]);

  async function charger() {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('user_profiles_complet')
        .select('*')
        .not('profile_type', 'is', null)
        .not('profile_type', 'in', '(eleveur,association)')
        .in('statut_pro', ['actif', 'validated']);
      const items: Pro[] = (data ?? []).map(row => ({
        uid: row.uid,
        profileTableId: row.id,
        name: row.nom || 'Professionnel',
        photo: row.avatar_url,
        banner: row.banner_url,
        profession: row.profession_pro,
        ville: row.ville_pro || row.ville,
        cat_pro: row.profile_type,
        especes: Array.isArray(row.especes_acceptees) ? row.especes_acceptees : [],
        accept_new_clients: row.accept_new_clients,
        lat: row.latitude ?? row.lat,
        lng: row.longitude ?? row.lng,
        rayon_intervention: row.rayon_intervention,
        se_deplace: row.se_deplace,
        description: row.desc_entreprise || row.description || '',
      }));
      setPros(items);
      const gardeIds = items.filter(p => p.cat_pro === 'garde' && p.profileTableId).map(p => p.profileTableId!);
      if (gardeIds.length) {
        const { data: cr } = await supabase.from('creneaux_pro')
          .select('pro_profile_id, type_garde').in('pro_profile_id', gardeIds).eq('statut', 'disponible');
        setCreneauOk(new Set((cr ?? []).filter(c => !c.type_garde || c.type_garde === 'prestation').map(c => c.pro_profile_id as string)));
      }
    } finally {
      setLoading(false);
    }
  }

  const cat = categorieByKey(categorie);
  const metier = metierSelectionne(categorie, type);
  const resultats = useMemo(() => pros.filter(p => {
    if (!proMatchesMetier(p, metier, creneauOk)) return false;
    if (!proMatchesEspeces(p.especes, especes)) return false;
    if (!proDansZone(p, lieu, rayon)) return false;
    if (q) {
      const s = q.toLowerCase();
      if (![p.name, p.ville, p.profession, p.description].some(x => (x ?? '').toLowerCase().includes(s))) return false;
    }
    return true;
  }).map(p => ({ ...p, distance: lieu && p.lat && p.lng ? haversineKm(lieu.lat, lieu.lng, p.lat, p.lng) : null }))
    .sort((a, b) => (a.distance ?? 1e9) - (b.distance ?? 1e9)),
  [pros, metier, creneauOk, especes, lieu, rayon, q]);

  // Changer de catégorie garde les animaux sélectionnés (et le lieu).
  const choisirCategorie = (k: string) => { setCategorie(c => c === k ? '' : k); setType(''); };
  const reinitialiser = () => {
    setQSaisie(''); setQ(''); setCategorie(''); setType(''); setEspeces([]); setLieu(null); setRayon(50);
  };

  const actifs: { key: string; label: string; retirer: () => void }[] = [
    ...(q ? [{ key: 'q', label: `« ${q} »`, retirer: () => { setQ(''); setQSaisie(''); } }] : []),
    ...(cat ? [{ key: 'cat', label: cat.label, retirer: () => { setCategorie(''); setType(''); } }] : []),
    ...(type ? [{ key: 'type', label: metierByKey(type).label, retirer: () => setType('') }] : []),
    ...especes.map(k => ({ key: `e-${k}`, label: GROUPES_ESPECES.find(g => g.key === k)?.label ?? k, retirer: () => setEspeces(e => e.filter(x => x !== k)) })),
    ...(lieu ? [{ key: 'lieu', label: lieu.ville ?? lieu.label, retirer: () => setLieu(null) }, { key: 'rayon', label: `${rayon} km`, retirer: () => setLieu(null) }] : []),
  ];
  const nbFiltresPanneau = especes.length + (lieu ? 1 : 0);

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* ── En-tête + recherche + filtres ─────────────────────────────── */}
      <div className="bg-gradient-to-b from-[#E6F2F1] to-[#F8F8F8] px-4 pt-6 pb-4">
        <div className="max-w-5xl mx-auto">
          <h1 className="text-2xl sm:text-3xl font-bold text-[#0C5C6C]" style={font}>Annuaire des professionnels</h1>
          <p className="text-sm text-gray-600 mt-0.5" style={font}>Trouvez le bon professionnel pour votre animal.</p>

          <form className="mt-4 flex gap-2" onSubmit={e => { e.preventDefault(); setQ(qSaisie.trim()); }}>
            <div className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl border border-gray-200 bg-white shadow-sm focus-within:border-[#0C5C6C]">
              <span className="text-gray-400">🔍</span>
              <input type="text" value={qSaisie} onChange={e => setQSaisie(e.target.value)}
                placeholder="Rechercher un professionnel ou un service…"
                className="flex-1 min-w-0 text-sm outline-none bg-transparent" style={font} />
            </div>
            <button type="button" onClick={() => setPanneau(true)}
              className="md:hidden px-4 rounded-2xl border border-gray-200 bg-white text-sm font-semibold text-[#0C5C6C] shadow-sm" style={font}>
              Filtres{nbFiltresPanneau ? ` (${nbFiltresPanneau})` : ''}
            </button>
          </form>

          {/* Filtres en ligne (ordinateur / tablette) */}
          <div className="hidden md:grid grid-cols-[1.4fr_1.2fr_0.7fr_auto] gap-2 mt-3">
            <AnimauxMultiSelect value={especes} onApply={setEspeces} />
            <LieuPicker value={lieu} maPosition={maPosition} onChange={setLieu} />
            <select value={rayon} disabled={!lieu} onChange={e => setRayon(parseInt(e.target.value, 10))}
              className="px-3 py-2.5 rounded-xl border border-gray-200 text-sm bg-white outline-none focus:border-[#0C5C6C] disabled:opacity-40" style={font}>
              {RAYONS_KM.map(r => <option key={r} value={r}>Rayon : {r} km</option>)}
            </select>
            <button type="button" onClick={() => setQ(qSaisie.trim())}
              className="px-6 bg-[#0C5C6C] hover:bg-[#0a4d5b] text-white rounded-xl text-sm font-semibold" style={font}>
              🔍 Rechercher
            </button>
          </div>
        </div>
      </div>

      <div className="max-w-5xl mx-auto px-4 pb-10">
        {/* ── Catégories ──────────────────────────────────────────────── */}
        <h2 className="text-lg font-bold text-[#1F2A2E] mt-2 mb-3" style={font}>Catégories</h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {CATEGORIES_ANNUAIRE.map(c => {
            const actif = c.key === categorie;
            return (
              <button key={c.key} onClick={() => choisirCategorie(c.key)}
                className={`bg-white rounded-2xl border-2 px-3 py-4 flex flex-col items-center gap-2 text-center transition-all ${actif ? 'shadow-md' : 'border-transparent shadow-sm hover:shadow-md'}`}
                style={actif ? { borderColor: c.color, backgroundColor: c.color + '0D' } : undefined}>
                <span className="w-12 h-12 rounded-xl flex items-center justify-center text-2xl" style={{ backgroundColor: c.color + '18' }}>{c.icon}</span>
                <span className={`text-[13px] leading-tight ${actif ? 'font-bold' : 'font-semibold text-[#1F2A2E]'}`}
                  style={{ ...font, color: actif ? c.color : undefined }}>{c.label}</span>
              </button>
            );
          })}
        </div>

        {/* ── Types de service de la catégorie ────────────────────────── */}
        {cat && cat.types.length > 0 && (
          <div className="mt-4 flex flex-wrap items-center gap-2">
            <span className="text-sm font-bold text-[#1F2A2E] mr-1" style={font}>Type de service ({cat.label}) :</span>
            {[{ key: '', label: 'Tous' }, ...cat.types.map(t => ({ key: t, label: metierByKey(t).label }))].map(t => {
              const actif = t.key === type;
              return (
                <button key={t.key || 'tous'} onClick={() => setType(t.key)}
                  className={`px-3.5 py-1.5 rounded-full text-xs font-semibold border transition-colors ${actif ? 'text-white' : 'bg-white text-gray-600 border-gray-200 hover:border-gray-300'}`}
                  style={{ ...font, ...(actif ? { backgroundColor: cat.color, borderColor: cat.color } : {}) }}>
                  {t.label}
                </button>
              );
            })}
          </div>
        )}

        {/* ── Filtres appliqués ───────────────────────────────────────── */}
        {actifs.length > 0 && (
          <div className="mt-4 pt-4 border-t border-gray-100 flex flex-wrap items-center gap-2">
            <span className="text-sm text-gray-500" style={font}>Filtres appliqués :</span>
            {actifs.map(a => (
              <span key={a.key} className="inline-flex items-center gap-1.5 pl-3 pr-2 py-1 rounded-full text-xs font-semibold bg-[#0C5C6C]/10 text-[#0C5C6C]" style={font}>
                {a.label}
                <button type="button" aria-label={`Retirer ${a.label}`} onClick={a.retirer}
                  className="w-4 h-4 rounded-full hover:bg-[#0C5C6C]/20 leading-none">✕</button>
              </span>
            ))}
            <button onClick={reinitialiser} className="text-xs font-semibold text-[#0C5C6C] underline ml-1" style={font}>↺ Réinitialiser</button>
          </div>
        )}

        {/* ── Résultats ───────────────────────────────────────────────── */}
        <div className="flex items-center justify-between mt-6 mb-3">
          <h2 className="text-lg font-bold text-[#1F2A2E]" style={font}>Professionnels correspondants</h2>
          <div className="flex items-center gap-3">
            <span className="text-xs text-gray-400" style={font}>{loading ? '…' : `${resultats.length} résultat${resultats.length > 1 ? 's' : ''}`}</span>
            <div className="flex bg-gray-100 rounded-full p-0.5">
              {(['list', 'map'] as const).map(v => (
                <button key={v} onClick={() => setView(v)}
                  className="px-3 py-1 rounded-full text-xs font-semibold"
                  style={{ ...font, background: view === v ? 'white' : 'transparent', color: view === v ? '#0C5C6C' : '#6B7280' }}>
                  {v === 'list' ? 'Liste' : 'Carte'}
                </button>
              ))}
            </div>
          </div>
        </div>

        {loading ? (
          <div className="h-48 flex items-center justify-center">
            <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : resultats.length === 0 ? (
          <div className="py-12 flex flex-col items-center gap-2 text-center bg-white rounded-2xl">
            <span className="text-4xl">🔍</span>
            <p className="text-sm text-gray-500" style={font}>Aucun professionnel ne correspond à ces critères.</p>
            {lieu && <p className="text-xs text-gray-400">Essayez un rayon plus large ou retirez le lieu.</p>}
            <button onClick={reinitialiser} className="text-xs text-[#0C5C6C] underline mt-1">Réinitialiser</button>
          </div>
        ) : view === 'map' ? (
          <div className="h-[60vh] min-h-[400px]">
            <ServicesMap pros={resultats.filter(p => p.lat && p.lng)} />
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {resultats.map((p, i) => <CarteResultat key={`${p.uid}-${p.cat_pro}-${i}`} pro={p} distance={p.distance} />)}
          </div>
        )}
      </div>

      {/* ── Panneau Filtres (mobile) ───────────────────────────────────── */}
      {panneau && (
        <PanneauFiltres especes={especes} lieu={lieu} rayon={rayon} maPosition={maPosition}
          onClose={() => setPanneau(false)}
          onApply={(e, l, r) => { setEspeces(e); setLieu(l); setRayon(r); setQ(qSaisie.trim()); setPanneau(false); }} />
      )}
    </div>
  );
}

// ── Carte de résultat ─────────────────────────────────────────────────────────

function CarteResultat({ pro, distance }: { pro: Pro; distance: number | null }) {
  const href = `/services/pro/${pro.uid}${pro.profileTableId ? `?profileId=${pro.profileTableId}` : ''}`;
  const groupes = groupesDesEspeces(pro.especes);
  const image = pro.banner || pro.photo;
  const metierLabel = pro.profession || CATEGORIES_ANNUAIRE.find(c => metierByKey(c.metier).cats.includes(pro.cat_pro ?? ''))?.label || 'Professionnel';
  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-3 flex gap-3">
      <Link href={href} className="w-28 sm:w-36 flex-shrink-0 rounded-xl overflow-hidden bg-[#0C5C6C]/10 flex items-center justify-center" style={{ minHeight: 112 }}>
        {image
          ? <img src={image} alt={pro.name} className="w-full h-full object-cover" />
          : <span className="text-4xl opacity-40">💼</span>}
      </Link>
      <div className="flex-1 min-w-0 flex flex-col">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[15px] font-bold text-[#1F2A2E] truncate" style={font}>{metierLabel}</p>
            <p className="text-sm text-gray-600 truncate" style={font}>{pro.name}</p>
          </div>
          <Link href={href}
            className="hidden sm:inline-block flex-shrink-0 bg-[#0C5C6C] hover:bg-[#0a4d5b] text-white text-xs font-semibold px-3 py-1.5 rounded-lg" style={font}>
            Voir la fiche
          </Link>
        </div>
        <p className="text-xs text-gray-500 mt-1" style={font}>
          📍 {pro.ville || 'Ville non renseignée'}
          {distance != null && <span className="text-gray-400"> · à {distance < 1 ? '< 1' : Math.round(distance)} km</span>}
        </p>
        {groupes.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1.5">
            {groupes.map(g => (
              <span key={g.key} className="text-[11px] px-2 py-0.5 rounded-full font-semibold bg-[#0C5C6C]/10 text-[#0C5C6C]" style={font}>{g.label}</span>
            ))}
          </div>
        )}
        {pro.description && <p className="text-xs text-gray-500 mt-1.5 line-clamp-2" style={font}>{pro.description}</p>}
        <Link href={href} className="sm:hidden mt-2 self-start bg-[#0C5C6C] text-white text-xs font-semibold px-3 py-1.5 rounded-lg" style={font}>
          Voir la fiche
        </Link>
      </div>
    </div>
  );
}

// ── Panneau Filtres (mobile) ──────────────────────────────────────────────────

function PanneauFiltres({ especes, lieu, rayon, maPosition, onClose, onApply }: {
  especes: string[]; lieu: LieuRecherche | null; rayon: number; maPosition: LieuRecherche | null;
  onClose: () => void; onApply: (e: string[], l: LieuRecherche | null, r: number) => void;
}) {
  const [e, setE] = useState(especes);
  const [l, setL] = useState(lieu);
  const [r, setR] = useState(rayon);
  return (
    <div className="fixed inset-0 z-50 flex items-end bg-black/40" onClick={onClose}>
      <div className="bg-white w-full rounded-t-3xl max-h-[88vh] overflow-y-auto" onClick={ev => ev.stopPropagation()}>
        <div className="flex items-center justify-between px-5 pt-4 pb-2">
          <p className="text-base font-bold text-[#1F2A2E]" style={font}>Filtres</p>
          <button onClick={onClose} className="text-gray-400 text-xl leading-none" aria-label="Fermer">×</button>
        </div>
        <div className="px-5 space-y-4 pb-4">
          <div>
            <p className="text-xs font-semibold text-gray-500 mb-1" style={font}>Animaux concernés <span className="font-normal">· plusieurs choix possibles</span></p>
            <div className="rounded-xl border border-gray-100 divide-y divide-gray-50">
              {GROUPES_ESPECES.map(g => (
                <label key={g.key} className="flex items-center gap-3 px-3 py-2.5">
                  <input type="checkbox" checked={e.includes(g.key)} className="w-4 h-4 accent-[#0C5C6C]"
                    onChange={() => setE(x => x.includes(g.key) ? x.filter(k => k !== g.key) : [...x, g.key])} />
                  <span className="text-sm text-[#1F2A2E]" style={font}>
                    {g.label}{g.detail && <span className="block text-[11px] text-gray-400">{g.detail}</span>}
                  </span>
                </label>
              ))}
            </div>
          </div>
          <div>
            <p className="text-xs font-semibold text-gray-500 mb-1" style={font}>Ville ou code postal</p>
            <LieuPicker value={l} maPosition={maPosition} onChange={setL} />
          </div>
          <div>
            <p className="text-xs font-semibold text-gray-500 mb-1" style={font}>Rayon</p>
            <div className="flex flex-wrap gap-2">
              {RAYONS_KM.map(x => (
                <button key={x} type="button" disabled={!l} onClick={() => setR(x)}
                  className={`px-3 py-1.5 rounded-full text-xs font-semibold border disabled:opacity-40 ${r === x ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}
                  style={font}>{x} km</button>
              ))}
            </div>
          </div>
        </div>
        <div className="sticky bottom-0 bg-white flex gap-2 px-5 py-3 border-t border-gray-100">
          <button onClick={() => { setE([]); setL(null); setR(50); }}
            className="flex-1 border border-gray-200 text-gray-600 rounded-xl py-2.5 text-sm font-semibold" style={font}>Réinitialiser</button>
          <button onClick={() => onApply(e, l, r)}
            className="flex-1 bg-[#0C5C6C] text-white rounded-xl py-2.5 text-sm font-semibold" style={font}>Appliquer</button>
        </div>
      </div>
    </div>
  );
}
