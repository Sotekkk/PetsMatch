'use client';

// Annuaire des professionnels — recherche par filtres combinables :
// mot-clé + métier + lieu / rayon + animaux pris en charge (plusieurs choix).
// Logique partagée : src/lib/annuaire-filtres.ts (miroir app :
// lib/utils/annuaire_filtres.dart + ServiceListPage).

import { useEffect, useMemo, useState, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import type { ProMapItem } from '@/components/ServicesMap';
import AnimauxMultiSelect from '@/components/annuaire/AnimauxMultiSelect';
import LieuPicker from '@/components/annuaire/LieuPicker';
import {
  METIERS, GROUPES_ESPECES, RAYONS_KM, metierByKey, metierFromLegacy,
  proMatchesMetier, proMatchesEspeces, proDansZone, groupesDesEspeces,
  type LieuRecherche,
} from '@/lib/annuaire-filtres';

const ServicesMap = dynamic(() => import('@/components/ServicesMap'), { ssr: false });

type Pro = ProMapItem & { se_deplace?: boolean | null };

interface Criteres {
  q: string;
  metier: string;
  lieu: LieuRecherche | null;
  rayon: number;
  especes: string[];
}

function criteresDepuisUrl(sp: URLSearchParams): Criteres {
  const lat = parseFloat(sp.get('lat') ?? '');
  const lng = parseFloat(sp.get('lng') ?? '');
  const lieuLabel = sp.get('lieu');
  const especesValides = new Set(GROUPES_ESPECES.map(g => g.key));
  return {
    q: sp.get('q') ?? '',
    metier: sp.has('metier') ? metierByKey(sp.get('metier')).key : metierFromLegacy(sp.get('cat'), sp.get('prof')).key,
    lieu: lieuLabel && !isNaN(lat) && !isNaN(lng) ? { label: lieuLabel, lat, lng, ville: sp.get('ville') ?? undefined } : null,
    rayon: RAYONS_KM.includes(parseInt(sp.get('rayon') ?? '', 10)) ? parseInt(sp.get('rayon')!, 10) : 50,
    especes: (sp.get('especes') ?? '').split(',').filter(k => especesValides.has(k)),
  };
}

const labelCls = 'block text-xs font-semibold text-gray-500 mb-1';
const selectCls = 'w-full px-3 py-2.5 rounded-xl border border-gray-200 text-sm bg-white outline-none focus:border-[#0C5C6C] disabled:opacity-40';

// ─── Page ─────────────────────────────────────────────────────────────────────

function ServicesCarteContent() {
  const { user } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();

  const [pros, setPros] = useState<Pro[]>([]);
  const [creneauOk, setCreneauOk] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [maPosition, setMaPosition] = useState<LieuRecherche | null>(null);
  // Formulaire (brouillon) et critères appliqués (« Rechercher »)
  const [form, setForm] = useState<Criteres>(() => criteresDepuisUrl(new URLSearchParams(searchParams.toString())));
  const [criteres, setCriteres] = useState<Criteres>(form);
  const [viewMode, setViewMode] = useState<'map' | 'list'>(() =>
    (searchParams.get('view') as 'map' | 'list') ?? 'list'
  );

  useEffect(() => { loadPros(); }, []);

  // Position du profil connecté → option « Autour de moi »
  useEffect(() => {
    if (!user) { setMaPosition(null); return; }
    supabase.from('user_profiles_complet').select('lat, lng, ville')
      .eq('uid', user.uid).eq('is_main', true).maybeSingle()
      .then(({ data }) => {
        const lat = data?.lat as number | null, lng = data?.lng as number | null;
        setMaPosition(lat != null && lng != null
          ? { label: 'Autour de moi', lat, lng, ville: (data?.ville as string) || undefined }
          : null);
      });
  }, [user]);

  // URL ↔ critères appliqués (retour depuis une fiche pro = même recherche)
  useEffect(() => {
    const p = new URLSearchParams();
    if (criteres.q) p.set('q', criteres.q);
    if (criteres.metier) p.set('metier', criteres.metier);
    if (criteres.especes.length) p.set('especes', criteres.especes.join(','));
    if (criteres.lieu) {
      p.set('lieu', criteres.lieu.label);
      p.set('lat', String(criteres.lieu.lat));
      p.set('lng', String(criteres.lieu.lng));
      if (criteres.lieu.ville) p.set('ville', criteres.lieu.ville);
      p.set('rayon', String(criteres.rayon));
    }
    if (viewMode === 'map') p.set('view', 'map');
    const qs = p.toString();
    router.replace(qs ? `/services/carte?${qs}` : '/services/carte', { scroll: false });
  }, [criteres, viewMode, router]);

  async function loadPros() {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('user_profiles_complet')
        .select('id, uid, profile_type, nom, avatar_url, banner_url, profession_pro, ville, ville_pro, especes_acceptees, accept_new_clients, latitude, longitude, lat, lng, rayon_intervention, se_deplace')
        .not('profile_type', 'is', null)
        .not('profile_type', 'in', '(eleveur,association)')
        .in('statut_pro', ['actif', 'validated']);

      const items: Pro[] = [];
      for (const row of (data ?? [])) {
        const cat = row.profile_type ?? '';
        if (!cat) continue;
        items.push({
          uid:                row.uid,
          profileTableId:     row.id,
          name:               row.nom || 'Professionnel',
          photo:              row.avatar_url,
          banner:             row.banner_url,
          profession:         row.profession_pro,
          ville:              row.ville_pro || row.ville,
          cat_pro:            cat,
          especes:            Array.isArray(row.especes_acceptees) ? row.especes_acceptees : [],
          accept_new_clients: row.accept_new_clients,
          lat:                row.latitude ?? row.lat,
          lng:                row.longitude ?? row.lng,
          rayon_intervention: row.rayon_intervention,
          se_deplace:         row.se_deplace,
        });
      }
      setPros(items);

      // Promeneurs : pet-sitters qui proposent aussi des créneaux promenade
      const gardeIds = items.filter(p => p.cat_pro === 'garde' && p.profileTableId).map(p => p.profileTableId!);
      if (gardeIds.length) {
        const { data: cr } = await supabase.from('creneaux_pro')
          .select('pro_profile_id, type_garde').in('pro_profile_id', gardeIds).eq('statut', 'disponible');
        setCreneauOk(new Set((cr ?? [])
          .filter(c => !c.type_garde || c.type_garde === 'prestation')
          .map(c => c.pro_profile_id as string)));
      }
    } finally {
      setLoading(false);
    }
  }

  const metier = metierByKey(criteres.metier);
  const filtered = useMemo(() => pros.filter(p => {
    if (!proMatchesMetier(p, metier, creneauOk)) return false;
    if (!proMatchesEspeces(p.especes, criteres.especes)) return false;
    if (!proDansZone(p, criteres.lieu, criteres.rayon)) return false;
    if (criteres.q) {
      const q = criteres.q.toLowerCase();
      if (![p.name, p.ville, p.profession].some(s => (s ?? '').toLowerCase().includes(q))) return false;
    }
    return true;
  }), [pros, metier, creneauOk, criteres]);

  const rechercher = () => setCriteres(form);
  // Animaux : « Appliquer » (menu) et suppression d'une étiquette relancent
  // la recherche directement.
  const setEspeces = (keys: string[]) => {
    setForm(f => ({ ...f, especes: keys }));
    setCriteres(c => ({ ...c, especes: keys }));
  };
  const reinitialiser = () => {
    const vide: Criteres = { q: '', metier: '', lieu: null, rayon: 50, especes: [] };
    setForm(vide); setCriteres(vide);
  };
  const aDesCriteres = !!(criteres.q || criteres.metier || criteres.lieu || criteres.especes.length);
  const groupes = [...new Set(METIERS.map(m => m.groupe))];

  return (
    <div className="min-h-screen bg-[#F8F8F8] flex flex-col">
      {/* En-tête */}
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-4xl mx-auto">
          <Link href="/services" className="text-white/70 hover:text-white text-sm">← Annuaire</Link>
          <h1 className="text-xl font-bold mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            Annuaire des professionnels
          </h1>
          <p className="text-white/70 text-sm">Trouvez un professionnel pour prendre soin de vos animaux</p>
        </div>
      </div>

      {/* Formulaire de recherche */}
      <div className="bg-white border-b border-gray-100 px-4 py-4">
        <form className="max-w-4xl mx-auto space-y-3" onSubmit={e => { e.preventDefault(); rechercher(); }}>
          <div className="flex items-center gap-2 px-3 py-2.5 rounded-xl border border-gray-200 bg-white focus-within:border-[#0C5C6C]">
            <span className="text-sm text-gray-400">🔍</span>
            <input type="text" placeholder="Nom ou mot-clé" value={form.q}
              onChange={e => setForm(f => ({ ...f, q: e.target.value }))}
              className="flex-1 min-w-0 text-sm outline-none bg-transparent" style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className={labelCls}>Métier</label>
              <select value={form.metier} onChange={e => setForm(f => ({ ...f, metier: e.target.value }))}
                className={selectCls} style={{ fontFamily: 'Galey, sans-serif' }}>
                {groupes.map(g => g === ''
                  ? METIERS.filter(m => m.groupe === '').map(m => <option key={m.key} value={m.key}>{m.label}</option>)
                  : (
                    <optgroup key={g} label={g}>
                      {METIERS.filter(m => m.groupe === g).map(m => <option key={m.key} value={m.key}>{m.label}</option>)}
                    </optgroup>
                  ))}
              </select>
            </div>
            <div>
              <label className={labelCls}>Animaux pris en charge</label>
              <AnimauxMultiSelect value={form.especes} onApply={setEspeces} />
            </div>
            <div>
              <label className={labelCls}>Lieu</label>
              <LieuPicker value={form.lieu} maPosition={maPosition}
                onChange={l => setForm(f => ({ ...f, lieu: l }))} />
            </div>
            <div>
              <label className={labelCls}>Rayon</label>
              <select value={form.rayon} disabled={!form.lieu}
                onChange={e => setForm(f => ({ ...f, rayon: parseInt(e.target.value, 10) }))}
                className={selectCls} style={{ fontFamily: 'Galey, sans-serif' }}>
                {RAYONS_KM.map(r => <option key={r} value={r}>{r} km</option>)}
              </select>
            </div>
          </div>

          {form.especes.length > 0 && (
            <div className="flex flex-wrap gap-2">
              {form.especes.map(k => (
                <span key={k} className="inline-flex items-center gap-1.5 pl-3 pr-2 py-1 rounded-full text-xs font-semibold bg-[#0C5C6C]/10 text-[#0C5C6C]"
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  {GROUPES_ESPECES.find(g => g.key === k)?.label}
                  <button type="button" aria-label="Retirer" onClick={() => setEspeces(form.especes.filter(x => x !== k))}
                    className="w-4 h-4 rounded-full hover:bg-[#0C5C6C]/20 leading-none">✕</button>
                </span>
              ))}
            </div>
          )}

          <div className="flex gap-2">
            <button type="submit"
              className="flex-1 bg-[#0C5C6C] hover:bg-[#0a4d5b] text-white rounded-xl py-2.5 text-sm font-semibold"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              🔍 Rechercher
            </button>
            {aDesCriteres && (
              <button type="button" onClick={reinitialiser}
                className="px-4 border border-gray-200 text-gray-500 rounded-xl text-sm font-semibold hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Réinitialiser
              </button>
            )}
          </div>
        </form>
      </div>

      {/* Résultats */}
      <div className="flex-1 p-4">
        <div className="max-w-4xl mx-auto">
          <div className="flex items-center justify-between mb-3">
            <p className="text-sm font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Résultats <span className="font-normal text-gray-400">· {loading ? '…' : `${filtered.length} résultat${filtered.length > 1 ? 's' : ''}`}</span>
            </p>
            <div className="flex bg-gray-100 rounded-full p-0.5">
              {(['list', 'map'] as const).map(v => (
                <button key={v} onClick={() => setViewMode(v)}
                  className="px-3 py-1.5 rounded-full text-xs font-semibold transition-colors"
                  style={{
                    fontFamily: 'Galey, sans-serif',
                    background: viewMode === v ? 'white' : 'transparent',
                    color: viewMode === v ? '#0C5C6C' : '#6B7280',
                    boxShadow: viewMode === v ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
                  }}>
                  {v === 'list' ? '📋 Liste' : '🗺️ Carte'}
                </button>
              ))}
            </div>
          </div>

          {loading ? (
            <div className="h-[40vh] flex items-center justify-center bg-gray-100 rounded-2xl">
              <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="h-[30vh] flex flex-col items-center justify-center bg-gray-50 rounded-2xl gap-3 text-center px-4">
              <span className="text-4xl">🔍</span>
              <p className="text-sm text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
                Aucun professionnel ne correspond à cette recherche
              </p>
              {criteres.lieu && (
                <p className="text-xs text-gray-400">Essayez un rayon plus large ou « Toute la France ».</p>
              )}
              <button onClick={reinitialiser} className="text-xs text-[#0C5C6C] underline">Réinitialiser les filtres</button>
            </div>
          ) : viewMode === 'map' ? (
            <>
              {filtered.some(p => !p.lat || !p.lng) && (
                <div className="mb-2 flex items-center gap-2 bg-amber-50 border border-amber-200 rounded-xl px-4 py-2">
                  <span className="text-sm">⚠️</span>
                  <p className="text-xs text-amber-700" style={{ fontFamily: 'Galey, sans-serif' }}>
                    {filtered.filter(p => !p.lat || !p.lng).length} professionnel(s) sans coordonnées ne s&apos;affiche(nt) pas sur la carte.
                    Passez en <button onClick={() => setViewMode('list')} className="underline font-semibold">vue liste</button> pour tous les voir.
                  </p>
                </div>
              )}
              <div className="h-[60vh] min-h-[400px]">
                <ServicesMap pros={filtered.filter(p => p.lat && p.lng)} />
              </div>
            </>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pb-8">
              {filtered.map((p, i) => <ProCard key={`${p.uid}-${p.cat_pro}-${i}`} pro={p} />)}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function ServicesCartePage() {
  return (
    <Suspense>
      <ServicesCarteContent />
    </Suspense>
  );
}

// ─── ProCard (vue liste) — même layout que l'app Flutter ─────────────────────

interface ProCardPro {
  uid: string; name: string; photo?: string; banner?: string; profession?: string;
  ville?: string; cat_pro?: string; especes: string[]; accept_new_clients?: boolean;
  lat?: number; lng?: number; profileTableId?: string;
}

const CAT_COLORS: Record<string, string> = {
  veterinaire: '#2196F3', sante: '#2196F3', education: '#FF9800',
  garde: '#4CAF50', pension: '#8BC34A', toilettage: '#00BCD4',
  photographe: '#E91E63', marechal_ferrant: '#795548', referencement: '#CDDC39',
};

const CAT_LIST_LABELS: Record<string, string> = {
  veterinaire: 'Vétérinaire', sante: 'Santé', education: 'Éducateur',
  garde: 'Pension / Garde', pension: 'Pension', toilettage: 'Toilettage',
  photographe: 'Photographe', marechal_ferrant: 'Maréchal-ferrant', referencement: 'Commerce',
};

function ProCard({ pro }: { pro: ProCardPro }) {
  const catColor = CAT_COLORS[pro.cat_pro ?? ''] ?? '#6B7280';
  const catLabel = CAT_LIST_LABELS[pro.cat_pro ?? ''] ?? pro.cat_pro ?? '';
  const href = `/services/pro/${pro.uid}${pro.profileTableId ? `?profileId=${pro.profileTableId}` : ''}`;
  const accept = pro.accept_new_clients !== false;

  const bannerStyle: React.CSSProperties = pro.banner
    ? { backgroundImage: `url(${pro.banner})`, backgroundSize: 'cover', backgroundPosition: 'center' }
    : pro.photo
    ? { backgroundImage: `url(${pro.photo})`, backgroundSize: 'cover', backgroundPosition: 'center' }
    : { background: `linear-gradient(135deg, ${catColor}cc, #1E2025)` };

  return (
    <a
      href={href}
      className="bg-white rounded-2xl shadow-sm overflow-hidden hover:shadow-md transition-shadow block no-underline"
      style={{ border: '1px solid #F0F0F0' }}
    >
      {/* Bannière */}
      <div className="relative h-24 w-full" style={bannerStyle}>
        {/* Overlay sombre si photo utilisée comme bannière */}
        {(pro.banner || pro.photo) && (
          <div className="absolute inset-0" style={{ background: 'rgba(0,0,0,0.18)' }} />
        )}
        {/* Badge dispo */}
        <div className="absolute top-2 right-2">
          <span
            className="text-[10px] font-bold px-2 py-1 rounded-xl"
            style={{
              background: accept ? '#E8F5E9' : '#FFF3E0',
              color: accept ? '#388E3C' : '#F57C00',
            }}
          >
            {accept ? '✓ Dispo' : 'Complet'}
          </span>
        </div>
      </div>

      {/* Contenu — avec photo avatar qui déborde sur la bannière */}
      <div className="relative px-3 pb-3 pt-7">
        {/* Photo avatar */}
        <div
          className="absolute -top-6 left-3 w-12 h-12 rounded-full overflow-hidden border-2 border-white shadow"
          style={{ background: `${catColor}22` }}
        >
          {pro.photo
            ? <img src={pro.photo} alt={pro.name} className="w-full h-full object-cover" />
            : <div className="w-full h-full flex items-center justify-center text-xl">💼</div>
          }
        </div>

        <p className="font-bold text-[#1E2025] text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{pro.name}</p>
        {pro.profession && (
          <p className="text-xs font-semibold truncate" style={{ color: catColor, fontFamily: 'Galey, sans-serif' }}>
            {pro.profession}
          </p>
        )}
        {pro.ville && (
          <p className="text-[11px] text-gray-400 mt-0.5" style={{ fontFamily: 'Galey, sans-serif' }}>
            📍 {pro.ville}
          </p>
        )}
        {groupesDesEspeces(pro.especes).length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1.5">
            {groupesDesEspeces(pro.especes).map(g => g.label).map(e => (
              <span
                key={e}
                className="text-[10px] px-2 py-0.5 rounded-full font-semibold"
                style={{ background: `${catColor}18`, color: catColor, fontFamily: 'Galey, sans-serif' }}
              >
                {e}
              </span>
            ))}
          </div>
        )}
        {catLabel && (
          <div className="mt-1.5">
            <span
              className="text-[10px] px-2 py-0.5 rounded-full font-semibold"
              style={{ background: `${catColor}18`, color: catColor, fontFamily: 'Galey, sans-serif' }}
            >
              {catLabel}
            </span>
          </div>
        )}
      </div>
    </a>
  );
}
