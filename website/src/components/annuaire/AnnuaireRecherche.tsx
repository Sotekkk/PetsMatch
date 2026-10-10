'use client';

// Annuaire des professionnels — page unique : recherche + barre de filtres
// compacte (catégorie et type de service, animaux concernés à cases à
// cocher, ville / code postal, rayon), filtres actifs supprimables,
// résultats. Sur mobile : filtres sur deux colonnes, le rayon passe dans le
// panneau « Filtres ». Critères combinables (ex. Transport + Taxi
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
import CategoriesSelect from '@/components/annuaire/CategoriesSelect';
import { couleurMarqueurPro } from '@/lib/annuaire-couleurs';
import { Icone } from '@/components/dashboard/kit';
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

  const champ = 'h-11 px-3 rounded-xl border border-[#E5E8E6] text-sm bg-white text-[#1E2025] outline-none focus:border-[#0C5C6C] disabled:bg-gray-50 disabled:text-gray-400';

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={font}>
      {/* ── En-tête + recherche + filtres ─────────────────────────────── */}
      <div className="max-w-5xl mx-auto px-4 pt-6">
        <h1 className="text-2xl sm:text-3xl font-bold text-[#1E2025]">Annuaire des professionnels</h1>
        <p className="text-sm text-gray-600 mt-0.5">Trouvez le bon professionnel pour votre animal.</p>

        <form className="mt-4" onSubmit={e => { e.preventDefault(); setQ(qSaisie.trim()); }}>
          <div className="h-12 flex items-center gap-2 px-4 rounded-xl border border-[#E5E8E6] bg-white focus-within:border-[#0C5C6C]">
            <Icone nom="recherche" taille={18} className="text-gray-400 flex-shrink-0" />
            <input type="text" value={qSaisie} onChange={e => setQSaisie(e.target.value)}
              placeholder="Rechercher un professionnel ou un service…"
              className="flex-1 min-w-0 text-sm outline-none bg-transparent" />
          </div>
        </form>

        {/* Filtres : 2 colonnes sur mobile, barre compacte sur ordinateur */}
        <div className="grid grid-cols-2 md:grid-cols-[1.2fr_1.3fr_1.4fr_0.9fr_auto] gap-2 mt-2">
          <CategoriesSelect categorie={categorie} type={type} onCategorie={choisirCategorie} onType={setType} />
          <AnimauxMultiSelect value={especes} onApply={setEspeces} />
          <LieuPicker value={lieu} maPosition={maPosition} onChange={setLieu} />
          {/* Rayon : en ligne sur ordinateur, dans « Filtres » sur mobile */}
          <select value={rayon} disabled={!lieu} onChange={e => setRayon(parseInt(e.target.value, 10))}
            className={`hidden md:block ${champ}`} aria-label="Rayon">
            {RAYONS_KM.map(r => <option key={r} value={r}>Rayon : {r} km</option>)}
          </select>
          <button type="button" onClick={() => setPanneau(true)}
            className="md:hidden h-11 inline-flex items-center justify-center gap-2 rounded-xl border border-[#0C5C6C]/40 bg-[#E8F4F6] text-sm font-semibold text-[#0C5C6C]">
            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></svg>
            Filtres{lieu ? ' (1)' : ''}
          </button>
          <button type="button" onClick={() => setQ(qSaisie.trim())}
            className="hidden md:block h-11 px-6 bg-[#0C5C6C] hover:bg-[#094F5D] text-white rounded-xl text-sm font-semibold">
            Rechercher
          </button>
        </div>
      </div>

      <div className="max-w-5xl mx-auto px-4 pb-10">
        {/* ── Filtres appliqués ───────────────────────────────────────── */}
        {actifs.length > 0 && (
          <div className="mt-3 flex flex-wrap items-center gap-2">
            {actifs.map(a => (
              <span key={a.key} className="inline-flex items-center gap-1 pl-3 pr-1.5 py-1 rounded-full text-xs font-semibold border border-[#0C5C6C]/25 bg-white text-[#0C5C6C]">
                {a.label}
                <button type="button" aria-label={`Retirer ${a.label}`} onClick={a.retirer}
                  className="w-5 h-5 rounded-full hover:bg-[#E8F4F6] leading-none text-base">×</button>
              </span>
            ))}
            <button onClick={reinitialiser} className="text-xs font-semibold text-[#0C5C6C] underline underline-offset-2 ml-1">Réinitialiser</button>
          </div>
        )}

        {/* ── Résultats ───────────────────────────────────────────────── */}
        <div className="flex flex-wrap items-center justify-between gap-3 mt-5 mb-3">
          <h2 className="text-lg font-bold text-[#1E2025]">
            {loading ? 'Recherche…' : `${resultats.length} professionnel${resultats.length > 1 ? 's' : ''}`}
          </h2>
          <div className="inline-flex rounded-xl border border-[#E5E8E6] overflow-hidden" role="group" aria-label="Affichage">
            {(['list', 'map'] as const).map(v => (
              <button key={v} onClick={() => setView(v)} aria-pressed={view === v}
                className={`px-4 py-2 text-sm font-semibold transition-colors ${v === 'map' ? 'border-l border-[#E5E8E6]' : ''} ${view === v ? 'bg-[#0C5C6C] text-white' : 'bg-white text-[#374151] hover:bg-gray-50'}`}>
                {v === 'list' ? 'Liste' : 'Carte'}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="h-48 flex items-center justify-center">
            <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : resultats.length === 0 ? (
          <div className="py-12 text-center bg-white border border-[#E5E8E6] rounded-2xl">
            <p className="text-sm text-[#1E2025]">Aucun professionnel ne correspond à ces critères.</p>
            {lieu && <p className="text-xs text-gray-500 mt-1">Essayez un rayon plus large ou retirez le lieu.</p>}
            <button onClick={reinitialiser} className="text-sm font-semibold text-[#0C5C6C] underline underline-offset-2 mt-3">Réinitialiser les filtres</button>
          </div>
        ) : view === 'map' ? (
          <div className="h-[60vh] min-h-[400px] relative isolate rounded-2xl overflow-hidden border border-[#E5E8E6]">
            <ServicesMap pros={resultats.filter(p => p.lat && p.lng)} />
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
            {resultats.map((p, i) => <CarteResultat key={`${p.uid}-${p.cat_pro}-${i}`} pro={p} distance={p.distance} />)}
          </div>
        )}
      </div>

      {/* ── Panneau Filtres (mobile) : critères hors barre (rayon) ─────── */}
      {panneau && (
        <PanneauFiltres lieu={lieu} rayon={rayon}
          onClose={() => setPanneau(false)}
          onApply={r => { setRayon(r); setQ(qSaisie.trim()); setPanneau(false); }} />
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
    <Link href={href}
      className="group bg-white rounded-2xl border border-[#E5E8E6] shadow-[0_1px_3px_rgba(16,24,40,0.06)] hover:shadow-md transition-shadow p-3 flex gap-3">
      <div className="w-24 h-24 sm:w-28 sm:h-28 flex-shrink-0 rounded-xl overflow-hidden bg-[#F3F4F6] flex items-center justify-center text-gray-400">
        {image
          // eslint-disable-next-line @next/next/no-img-element
          ? <img src={image} alt={pro.name} className="w-full h-full object-cover" />
          : <Icone nom="personne" taille={30} />}
      </div>
      <div className="flex-1 min-w-0 flex flex-col">
        <p className="text-[15px] font-bold text-[#1E2025] leading-snug line-clamp-2">{pro.name}</p>
        <p className="text-sm text-gray-600 mt-0.5 flex items-center gap-1.5 min-w-0">
          {/* Repère : couleur du marqueur de ce métier sur la carte */}
          <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: couleurMarqueurPro(pro.cat_pro) }} />
          <span className="truncate">{metierLabel}</span>
        </p>
        <p className="text-xs text-gray-500 mt-1 flex items-center gap-1 min-w-0">
          <Icone nom="pin" taille={13} className="flex-shrink-0" />
          <span className="truncate">
            {pro.ville || 'Ville non renseignée'}
            {distance != null && ` · à ${distance < 1 ? '< 1' : Math.round(distance)} km`}
          </span>
        </p>
        {groupes.length > 0 && (
          <p className="text-xs text-gray-500 mt-0.5 flex items-center gap-1 min-w-0">
            <Icone nom="patte" taille={13} className="flex-shrink-0" />
            <span className="line-clamp-2">{groupes.map(g => g.label).join(' · ')}</span>
          </p>
        )}
        <span className="mt-auto pt-1.5 text-sm font-semibold text-[#0C5C6C] group-hover:underline underline-offset-2">Voir la fiche →</span>
      </div>
    </Link>
  );
}

// ── Panneau Filtres (mobile) ──────────────────────────────────────────────────
// Critère qui n'a pas sa place dans la barre mobile : le rayon autour du lieu.

function PanneauFiltres({ lieu, rayon, onClose, onApply }: {
  lieu: LieuRecherche | null; rayon: number;
  onClose: () => void; onApply: (r: number) => void;
}) {
  const [r, setR] = useState(rayon);
  return (
    <div className="fixed inset-0 z-50 flex items-end bg-black/40" onClick={onClose}>
      <div className="bg-white w-full rounded-t-3xl max-h-[88vh] flex flex-col" onClick={ev => ev.stopPropagation()} style={font}>
        <div className="flex items-center justify-between px-5 pt-4 pb-2">
          <p className="text-lg font-bold text-[#1E2025]">Filtres</p>
          <button onClick={onClose} className="text-gray-400 text-2xl leading-none px-1" aria-label="Fermer">×</button>
        </div>
        <div className="px-5 pb-4 overflow-y-auto">
          <label className="block text-sm font-semibold text-[#374151] mb-1.5" htmlFor="rayon-mobile">Rayon autour du lieu</label>
          <select id="rayon-mobile" value={r} disabled={!lieu} onChange={e => setR(parseInt(e.target.value, 10))}
            className="w-full h-11 px-3 rounded-xl border border-[#E5E8E6] text-sm bg-white outline-none focus:border-[#0C5C6C] disabled:bg-gray-50 disabled:text-gray-400">
            {RAYONS_KM.map(x => <option key={x} value={x}>{x} km</option>)}
          </select>
          {!lieu && <p className="text-xs text-gray-500 mt-1.5">Choisissez d&apos;abord une ville ou un code postal.</p>}
        </div>
        <div className="flex gap-2 px-5 py-3 border-t border-[#E5E8E6]" style={{ paddingBottom: 'calc(0.75rem + env(safe-area-inset-bottom))' }}>
          <button onClick={() => setR(50)}
            className="flex-1 h-11 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-semibold">Réinitialiser</button>
          <button onClick={() => onApply(r)}
            className="flex-1 h-11 bg-[#0C5C6C] text-white rounded-xl text-sm font-semibold">Appliquer</button>
        </div>
      </div>
    </div>
  );
}
