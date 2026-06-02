'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/lib/supabase';

// ─── Types ───────────────────────────────────────────────────────────────────

interface AlimData {
  id?: string;
  type_ration?: string;
  phase?: string;
  activite?: string;
  cat_energie?: string;
  poids_ref?: number;
  dose_croquettes?: number;
  densite_kcal?: number;
  marque_id?: string;
  marque_label?: string;
  barf_muscle?: number;
  barf_os?: number;
  barf_abats?: number;
  barf_legumes?: number;
  barf_complementaires?: number;
  mixte_ratio_croq?: number;
  nb_repas?: number;
  etat_repro?: string;
  notes_alim?: string;
  supplements?: string[];
}

interface MarqueAliment {
  id: string;
  marque: string;
  gamme: string;
  densite_kcal_100g?: number;
  age_categorie?: string;
  taille_race?: string;
  type_aliment?: string;
}

interface Props {
  animalId: string;
  espece: string;
  sexe: string;
  sterilise: boolean;
  dateNaissance?: string;
  nom?: string;
  userId: string;
}

// ─── Constantes ──────────────────────────────────────────────────────────────

const ACT_LABELS: Record<string, string> = {
  sedentaire: 'Sédentaire', normal: 'Normal', actif: 'Actif', tres_actif: 'Très actif',
};
const ACT_FACTORS: Record<string, number> = {
  sedentaire: 1.2, normal: 1.4, actif: 1.6, tres_actif: 1.8,
};

const CAT_ENERGIE_LABELS: Record<string, string> = {
  basse: 'Basse énergie', normale: 'Normale', elevee: 'Haute énergie', geant: 'Race géante',
};
const CAT_ENERGIE_FACTORS: Record<string, number> = {
  basse: 0.85, normale: 1.0, elevee: 1.2, geant: 0.90,
};
const CAT_ENERGIE_EXEMPLES_CHIEN: Record<string, string> = {
  basse: 'Basset, Bouledogue, Shih-Tzu',
  normale: 'Golden, Labrador, Beagle',
  elevee: 'Border Collie, Malinois, Husky',
  geant: 'Dogue, Saint-Bernard, Newfoundland',
};
const CAT_ENERGIE_EXEMPLES_CHAT: Record<string, string> = {
  basse: 'Persane, British Shorthair',
  normale: 'Européen, Maine Coon',
  elevee: 'Siamois, Abyssin, Bengal',
  geant: 'Maine Coon adulte, Ragdoll',
};

const PHASE_FACTORS: Record<string, number> = {
  chiot: 2.0, junior: 1.6, adulte: 1.0, senior: 0.8, geront: 0.7,
};

const REPRO_FACTORS: Record<string, number> = {
  normal: 1.0, gestation_debut: 1.1, gestation_fin: 1.3, lactation: 1.5,
};

const SUPPLEMENTS = [
  'Oméga-3 (huile de poisson)', 'Probiotiques', 'Ostéo-articulaire (glucosamine)',
  'Vitamines & minéraux', 'Levure de bière', 'Spiruline', 'Homéopathie',
];

const REPAS_DEFAULTS: Record<string, Record<string, number>> = {
  chien: { croquettes: 2, barf: 2, mixte: 2, menagere: 2 },
  chat: { croquettes: 3, barf: 2, mixte: 3, menagere: 3 },
  cheval: { croquettes: 3, barf: 3, mixte: 3, menagere: 3 },
  lapin: { croquettes: 2, barf: 2, mixte: 2, menagere: 2 },
  default: { croquettes: 2, barf: 2, mixte: 2, menagere: 2 },
};

// ─── Calculs ─────────────────────────────────────────────────────────────────

function rer(poids: number): number {
  return 70 * Math.pow(poids, 0.75);
}

function der(poids: number, phase: string, catEnergie: string, activite: string, sterilise: boolean, espece: string, etatRepro: string): number {
  const phaseFactor = PHASE_FACTORS[phase] ?? 1.0;
  const catFactor = CAT_ENERGIE_FACTORS[catEnergie] ?? 1.0;
  const actFactor = phase === 'adulte' ? (ACT_FACTORS[activite] ?? 1.4) : 1.0;
  const sterilFactor = sterilise ? (espece === 'chat' ? 0.7 : 0.8) : 1.0;
  const reproFactor = REPRO_FACTORS[etatRepro] ?? 1.0;
  return rer(poids) * phaseFactor * catFactor * actFactor * sterilFactor * reproFactor;
}

function rationPctPoidsvif(espece: string): number {
  switch (espece) {
    case 'cheval': return 2.5;
    case 'lapin': return 5.0;
    case 'ovin': case 'caprin': return 3.5;
    case 'porcin': return 3.0;
    default: return 2.5;
  }
}

function isGrandEspece(espece: string): boolean {
  return ['cheval', 'lapin', 'ovin', 'caprin', 'porcin'].includes(espece);
}

// ─── Plan de repas ───────────────────────────────────────────────────────────

interface RepasItem { emoji: string; label: string; qte: string; desc: string; color: string; }

function getMealPlan(espece: string, type: string, nbRepas: number, derKcal: number, poids: number, densiteKcal: number, barfPct: number, mixtePct: number): RepasItem[] {
  const c = '#0C5C6C'; const g = '#6E9E57'; const o = '#E8A020'; const p = '#7B68EE';
  const doseCroq = densiteKcal > 0 ? derKcal * 100 / densiteKcal : 0;
  const doseBarf = poids * 1000 * 0.025;

  if (espece === 'chien' || espece === 'chat') {
    const perRepas = nbRepas > 0 ? 1 / nbRepas : 1;
    if (type === 'croquettes' && doseCroq > 0) {
      return Array.from({ length: nbRepas }, (_, i) => ({
        emoji: '🥣', label: `Repas ${i + 1}`, color: c,
        qte: `${Math.round(doseCroq * perRepas)} g`,
        desc: `${Math.round(doseCroq)} g/jour de croquettes`,
      }));
    }
    if (type === 'barf' && doseBarf > 0) {
      return Array.from({ length: nbRepas }, (_, i) => ({
        emoji: '🥩', label: `Repas BARF ${i + 1}`, color: g,
        qte: `${Math.round(doseBarf * perRepas)} g`,
        desc: `${Math.round(doseBarf)} g/jour — viande + os + abats`,
      }));
    }
    if (type === 'mixte') {
      const ratio = mixtePct / 100;
      const croqG = doseCroq * ratio;
      const barfG = doseBarf * (1 - ratio);
      return [
        { emoji: '🥣', label: 'Portion croquettes', qte: `${Math.round(croqG / nbRepas)} g × ${nbRepas}`, desc: `${Math.round(croqG)} g/jour`, color: c },
        { emoji: '🥩', label: 'Portion BARF', qte: `${Math.round(barfG / nbRepas)} g × ${nbRepas}`, desc: `${Math.round(barfG)} g/jour`, color: g },
      ];
    }
    if (type === 'menagere') {
      const totalG = poids * 1000 * 0.025;
      return Array.from({ length: nbRepas }, (_, i) => ({
        emoji: '🍲', label: `Repas maison ${i + 1}`, color: o,
        qte: `${Math.round(totalG * perRepas)} g`,
        desc: `${Math.round(totalG)} g/jour — ration ménagère`,
      }));
    }
  }

  if (espece === 'cheval') {
    const foinKg = poids * 0.015; const concentreKg = poids * 0.008;
    return [
      { emoji: '🌾', label: 'Foin (matin)', qte: `${(foinKg / 3).toFixed(1)} kg`, desc: 'Fourrage de base', color: g },
      { emoji: '🌾', label: 'Foin (midi)', qte: `${(foinKg / 3).toFixed(1)} kg`, desc: 'Fourrage de base', color: g },
      { emoji: '🌾', label: 'Foin (soir)', qte: `${(foinKg / 3).toFixed(1)} kg`, desc: 'Fourrage de base', color: g },
      { emoji: '🥣', label: 'Concentrés', qte: `${concentreKg.toFixed(1)} kg`, desc: 'Répartis en 2 repas', color: c },
    ];
  }

  if (espece === 'lapin') {
    const foinFree = '∞'; const pellets = `${(poids * 0.03 * 1000).toFixed(0)} g`;
    return [
      { emoji: '🌾', label: 'Foin', qte: foinFree, desc: 'À volonté (base)', color: g },
      { emoji: '🥣', label: 'Granulés', qte: pellets, desc: 'Une fois par jour', color: c },
      { emoji: '🥬', label: 'Légumes frais', qte: '2–3 feuilles', desc: 'Matin ou soir', color: p },
    ];
  }

  return [];
}

// ─── Composant BrandPicker ────────────────────────────────────────────────────

function BrandPickerModal({ espece, phase, onSelect, onClose }: {
  espece: string; phase: string;
  onSelect: (b: MarqueAliment) => void; onClose: () => void;
}) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<MarqueAliment[]>([]);
  const [loading, setLoading] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const doFetch = useCallback(async (q: string) => {
    setLoading(true);
    try {
      let req = supabase.from('marques_aliments')
        .select('id, marque, gamme, densite_kcal_100g, age_categorie, taille_race, type_aliment')
        .eq('espece', espece);
      if (phase !== 'junior') req = req.eq('age_categorie', 'adulte');
      if (q) req = req.or(`marque.ilike.%${q}%,gamme.ilike.%${q}%`);
      const { data } = await req.order('marque').limit(50);
      setResults((data ?? []) as MarqueAliment[]);
    } finally { setLoading(false); }
  }, [espece, phase]);

  useEffect(() => { doFetch(''); }, [doFetch]);

  function onChange(q: string) {
    setQuery(q);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => doFetch(q), 350);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-white w-full max-w-lg rounded-t-2xl sm:rounded-2xl max-h-[80vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="px-4 pt-4 pb-2 border-b border-gray-100">
          <div className="w-10 h-1 bg-gray-300 rounded-full mx-auto mb-3 sm:hidden" />
          <p className="text-base font-bold text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>Choisir un aliment</p>
          <input
            autoFocus
            value={query}
            onChange={e => onChange(e.target.value)}
            placeholder="Ex : Royal Canin, Orijen, Pro Plan…"
            className="w-full px-3 py-2 text-sm bg-gray-100 rounded-full outline-none"
          />
          {loading && <div className="h-0.5 bg-[#0C5C6C] mt-2 animate-pulse rounded-full" />}
        </div>
        <div className="overflow-y-auto flex-1">
          {results.length === 0 && !loading ? (
            <p className="text-center text-sm text-gray-400 py-8">
              {query ? `Aucun résultat pour « ${query} »` : 'Aucune marque dans la base'}
            </p>
          ) : results.map(b => (
            <button key={b.id} onClick={() => onSelect(b)}
              className="w-full text-left px-4 py-3 border-b border-gray-50 hover:bg-gray-50 transition-colors">
              <p className="text-sm font-semibold text-[#1F2A2E]">{b.marque} — {b.gamme}</p>
              <div className="flex gap-2 mt-0.5 flex-wrap">
                {b.densite_kcal_100g && <span className="text-xs text-gray-400">{b.densite_kcal_100g} kcal/100g</span>}
                {b.age_categorie === 'junior' && <span className="text-xs px-1.5 py-0.5 bg-amber-100 text-amber-700 rounded">Junior</span>}
                {b.taille_race && b.taille_race !== 'toutes' && <span className="text-xs px-1.5 py-0.5 bg-gray-100 text-gray-500 rounded">{b.taille_race}</span>}
              </div>
            </button>
          ))}
        </div>
        <div className="p-3 border-t border-gray-100">
          <button onClick={onClose} className="w-full py-2 text-sm text-gray-500 font-medium">Annuler</button>
        </div>
      </div>
    </div>
  );
}

// ─── Composant AlimentationTab ────────────────────────────────────────────────

export default function AlimentationTab({ animalId, espece, sexe, sterilise, dateNaissance, nom, userId }: Props) {
  const [alim, setAlim] = useState<AlimData>({
    type_ration: 'croquettes', phase: 'adulte', activite: 'normal',
    cat_energie: 'normale', poids_ref: 0, densite_kcal: 350,
    barf_muscle: 70, barf_os: 15, barf_abats: 10, barf_legumes: 5, barf_complementaires: 0,
    mixte_ratio_croq: 50, nb_repas: 2, etat_repro: 'normal', supplements: [],
  });
  const [poidsActuel, setPoidsActuel] = useState<number>(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [view, setView] = useState<'summary' | 'calc'>('summary');
  const [showBrand, setShowBrand] = useState(false);
  const [hasData, setHasData] = useState(false);

  // ── Load ────────────────────────────────────────────────────────────────────

  const load = useCallback(async () => {
    if (!animalId) return;
    setLoading(true);
    try {
      const [{ data: alimData }, { data: poidsData }] = await Promise.all([
        supabase.from('alimentations').select('*').eq('animal_id', animalId).maybeSingle(),
        supabase.from('poids').select('valeur').eq('animal_id', animalId).order('date', { ascending: false }).limit(1),
      ]);
      if (alimData) {
        setAlim(prev => ({ ...prev, ...alimData }));
        setHasData(true);
        setView('summary');
      } else {
        setView('calc');
      }
      if (poidsData && poidsData.length > 0) {
        setPoidsActuel(parseFloat(poidsData[0].valeur) || 0);
      }
    } finally { setLoading(false); }
  }, [animalId]);

  useEffect(() => { load(); }, [load]);

  // ── Helpers calcul ──────────────────────────────────────────────────────────

  const poids = alim.poids_ref || poidsActuel || 0;
  const phase = alim.phase ?? 'adulte';
  const catEnergie = alim.cat_energie ?? 'normale';
  const activite = alim.activite ?? 'normal';
  const etatRepro = alim.etat_repro ?? 'normal';
  const type = alim.type_ration ?? 'croquettes';
  const densiteKcal = alim.densite_kcal ?? 350;
  const nbRepas = alim.nb_repas ?? 2;

  const rerVal = poids > 0 ? rer(poids) : null;
  const derVal = poids > 0 ? der(poids, phase, catEnergie, activite, sterilise, espece, etatRepro) : null;

  const doseCroquettes = derVal && densiteKcal > 0 ? derVal * 100 / densiteKcal : null;
  const doseBarf = poids > 0 ? poids * 1000 * 0.025 : null;
  const rationGrandEspece = poids > 0 ? poids * rationPctPoidsvif(espece) / 100 : null;

  // ── Save ────────────────────────────────────────────────────────────────────

  async function save() {
    if (!animalId) return;
    setSaving(true);
    try {
      const payload = {
        ...alim,
        animal_id: animalId,
        uid_eleveur: userId,
        poids_ref: poids,
        updated_at: new Date().toISOString(),
      };
      if (alim.id) {
        await supabase.from('alimentations').update(payload).eq('id', alim.id);
      } else {
        const { data } = await supabase.from('alimentations').insert({ ...payload, id: crypto.randomUUID() }).select().single();
        if (data) setAlim(prev => ({ ...prev, id: data.id }));
      }
      setHasData(true);
      setView('summary');
    } finally { setSaving(false); }
  }

  // ── Phase de vie auto depuis date de naissance ──────────────────────────────

  function ageEnMois(): number | null {
    if (!dateNaissance) return null;
    const diff = Date.now() - new Date(dateNaissance).getTime();
    return Math.floor(diff / (1000 * 60 * 60 * 24 * 30.5));
  }

  function phaseAuto(): string {
    const m = ageEnMois();
    if (m === null) return 'adulte';
    if (m < 6) return 'chiot';
    if (m < 12) return 'junior';
    if (espece === 'chien' && m > 96) return 'senior';
    if (espece === 'chat' && m > 144) return 'geront';
    if (espece === 'chat' && m > 84) return 'senior';
    return 'adulte';
  }

  // ── Meal plan ───────────────────────────────────────────────────────────────

  const mealPlan = derVal && poids > 0
    ? getMealPlan(espece, type, nbRepas, derVal, poids, densiteKcal, alim.barf_muscle ?? 70, alim.mixte_ratio_croq ?? 50)
    : [];

  const COLOR_MAP: Record<string, string> = {
    '#0C5C6C': 'bg-[#0C5C6C]/10 border-[#0C5C6C]/20 text-[#0C5C6C]',
    '#6E9E57': 'bg-[#6E9E57]/10 border-[#6E9E57]/20 text-[#6E9E57]',
    '#E8A020': 'bg-[#E8A020]/10 border-[#E8A020]/20 text-[#E8A020]',
    '#7B68EE': 'bg-[#7B68EE]/10 border-[#7B68EE]/20 text-[#7B68EE]',
  };

  if (loading) {
    return <div className="flex justify-center py-16"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  // ── VUE RÉSUMÉ ──────────────────────────────────────────────────────────────

  if (view === 'summary' && hasData) {
    const typeLabel: Record<string, string> = { croquettes: '🥣 Croquettes', barf: '🥩 BARF', mixte: '🔀 Mixte', menagere: '🍲 Ménagère' };
    const phaseLabel: Record<string, string> = { chiot: 'Chiot', junior: 'Junior', adulte: 'Adulte', senior: 'Senior', geront: 'Gérontologie' };

    return (
      <div className="space-y-4">
        {/* En-tête résumé */}
        <div className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
          <div className="flex items-center justify-between mb-3">
            <p className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Profil alimentaire</p>
            <button onClick={() => setView('calc')}
              className="text-xs text-[#0C5C6C] font-semibold border border-[#0C5C6C]/30 rounded-full px-3 py-1 hover:bg-[#0C5C6C]/5">
              Modifier
            </button>
          </div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="bg-gray-50 rounded-lg p-2">
              <p className="text-gray-400">Type de ration</p>
              <p className="font-semibold text-[#1F2A2E] mt-0.5">{typeLabel[type] ?? type}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-2">
              <p className="text-gray-400">Phase de vie</p>
              <p className="font-semibold text-[#1F2A2E] mt-0.5">{phaseLabel[phase] ?? phase}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-2">
              <p className="text-gray-400">Poids de référence</p>
              <p className="font-semibold text-[#1F2A2E] mt-0.5">{poids > 0 ? `${poids} kg` : '—'}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-2">
              <p className="text-gray-400">Nb repas / jour</p>
              <p className="font-semibold text-[#1F2A2E] mt-0.5">{nbRepas}</p>
            </div>
            {sterilise && (
              <div className="bg-[#6E9E57]/10 rounded-lg p-2 col-span-2 flex items-center gap-2">
                <span>✂️</span>
                <p className="text-xs text-[#4A7C39] font-medium">Stérilisé(e) — facteur ×{espece === 'chat' ? '0.7' : '0.8'} appliqué</p>
              </div>
            )}
            {etatRepro !== 'normal' && (
              <div className="bg-[#0C5C6C]/8 rounded-lg p-2 col-span-2">
                <p className="text-[#0C5C6C] text-xs font-medium">
                  {etatRepro === 'gestation_debut' ? '🤰 Gestation début — +10%' : etatRepro === 'gestation_fin' ? '🍼 Gestation fin — +30%' : '🤱 Lactation — +50%'}
                </p>
              </div>
            )}
          </div>
        </div>

        {/* Besoins énergétiques */}
        {derVal && (
          <div className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
            <p className="font-bold text-[#1F2A2E] text-sm mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>⚡ Besoins énergétiques</p>
            <div className="space-y-1.5 text-xs">
              <div className="flex justify-between"><span className="text-gray-500">RER (besoins repos)</span><span className="font-bold text-[#1F2A2E]">{rerVal?.toFixed(0)} kcal</span></div>
              <div className="flex justify-between"><span className="text-gray-500">Facteurs appliqués</span><span className="text-gray-400 text-right">phase · activité{sterilise ? ' · stéril.' : ''}{etatRepro !== 'normal' ? ' · repro' : ''}</span></div>
              <div className="flex justify-between border-t border-gray-100 pt-1.5 mt-1.5">
                <span className="font-bold text-[#0C5C6C]">DER (besoins réels)</span>
                <span className="font-bold text-[#0C5C6C] text-sm">{derVal.toFixed(0)} kcal/j</span>
              </div>
            </div>
          </div>
        )}

        {/* Ration du jour */}
        {poids > 0 && (
          <div className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
            <p className="font-bold text-[#1F2A2E] text-sm mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>🥗 Ration du jour</p>
            <div className="space-y-1.5 text-xs">
              {type === 'croquettes' && doseCroquettes && (
                <>
                  <div className="flex justify-between"><span className="text-gray-500">Croquettes / jour</span><span className="font-bold text-[#1F2A2E]">{doseCroquettes.toFixed(0)} g</span></div>
                  {alim.marque_label && <div className="flex justify-between"><span className="text-gray-500">Marque</span><span className="text-gray-600">{alim.marque_label}</span></div>}
                  <div className="flex justify-between"><span className="text-gray-500">Densité</span><span className="text-gray-400">{densiteKcal} kcal/100g</span></div>
                </>
              )}
              {type === 'barf' && doseBarf && (
                <div className="flex justify-between"><span className="text-gray-500">Ration BARF / jour</span><span className="font-bold text-[#1F2A2E]">{doseBarf.toFixed(0)} g</span></div>
              )}
              {type === 'mixte' && doseCroquettes && doseBarf && (
                <>
                  <div className="flex justify-between"><span className="text-gray-500">Croquettes / jour</span><span className="font-bold text-[#1F2A2E]">{(doseCroquettes * (alim.mixte_ratio_croq ?? 50) / 100).toFixed(0)} g</span></div>
                  <div className="flex justify-between"><span className="text-gray-500">BARF / jour</span><span className="font-bold text-[#1F2A2E]">{(doseBarf * (1 - (alim.mixte_ratio_croq ?? 50) / 100)).toFixed(0)} g</span></div>
                </>
              )}
              {isGrandEspece(espece) && rationGrandEspece && (
                <div className="flex justify-between"><span className="text-gray-500">Ration / jour</span><span className="font-bold text-[#1F2A2E]">{(rationGrandEspece * 1000).toFixed(0)} g ({rationGrandEspece.toFixed(2)} kg)</span></div>
              )}
            </div>
          </div>
        )}

        {/* Plan de repas */}
        {mealPlan.length > 0 && (
          <div className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
            <p className="font-bold text-[#1F2A2E] text-sm mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>📅 Plan de repas</p>
            <div className="space-y-2">
              {mealPlan.map((r, i) => (
                <div key={i} className={`flex items-center justify-between rounded-xl p-3 border ${COLOR_MAP[r.color] ?? 'bg-gray-50 border-gray-100 text-gray-600'}`}>
                  <div className="flex items-center gap-2">
                    <span className="text-lg">{r.emoji}</span>
                    <div>
                      <p className="text-xs font-bold">{r.label}</p>
                      <p className="text-xs opacity-70">{r.desc}</p>
                    </div>
                  </div>
                  <span className="text-sm font-bold">{r.qte}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Suppléments */}
        {(alim.supplements ?? []).length > 0 && (
          <div className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
            <p className="font-bold text-[#1F2A2E] text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>💊 Suppléments</p>
            <div className="flex flex-wrap gap-2">
              {(alim.supplements ?? []).map(s => (
                <span key={s} className="text-xs px-2.5 py-1 bg-[#0C5C6C]/10 text-[#0C5C6C] rounded-full font-medium">{s}</span>
              ))}
            </div>
          </div>
        )}

        {alim.notes_alim && (
          <div className="bg-amber-50 rounded-2xl p-4 border border-amber-100">
            <p className="text-xs font-bold text-amber-700 mb-1">📝 Notes</p>
            <p className="text-xs text-amber-800">{alim.notes_alim}</p>
          </div>
        )}
      </div>
    );
  }

  // ── VUE CALCULATEUR ─────────────────────────────────────────────────────────

  const phaseOptions = espece === 'cheval'
    ? [['adulte', 'Adulte'], ['senior', 'Senior']]
    : [['chiot', 'Chiot / Chaton'], ['junior', 'Junior'], ['adulte', 'Adulte'], ['senior', 'Senior'], ['geront', 'Gérontologie']];

  const phaseDetecte = phaseAuto();

  return (
    <div className="space-y-5">
      {hasData && (
        <button onClick={() => setView('summary')}
          className="text-sm text-[#0C5C6C] font-medium flex items-center gap-1">
          ← Retour au résumé
        </button>
      )}

      {/* Type de ration */}
      <section>
        <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Type de ration</p>
        <div className="grid grid-cols-2 gap-2">
          {[['croquettes', '🥣', 'Croquettes'], ['barf', '🥩', 'BARF'], ['mixte', '🔀', 'Mixte'], ['menagere', '🍲', 'Ménagère']].map(([k, e, l]) => (
            <button key={k} onClick={() => setAlim(p => ({ ...p, type_ration: k }))}
              className={`py-2.5 rounded-xl text-sm font-semibold transition-all flex items-center justify-center gap-1.5 ${type === k ? 'bg-[#0C5C6C] text-white' : 'bg-white border border-gray-200 text-gray-600 hover:border-[#0C5C6C]/30'}`}>
              {e} {l}
            </button>
          ))}
        </div>
      </section>

      {/* Poids */}
      <section>
        <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Poids de référence</p>
        <div className="flex items-center gap-3">
          <input type="number" step="0.1" min="0" value={alim.poids_ref || ''}
            onChange={e => setAlim(p => ({ ...p, poids_ref: parseFloat(e.target.value) || 0 }))}
            placeholder={poidsActuel > 0 ? `${poidsActuel} kg (dernier pesage)` : 'Ex: 12.5'}
            className="flex-1 border border-gray-200 rounded-xl px-3 py-2.5 text-sm outline-none focus:border-[#0C5C6C]" />
          <span className="text-sm text-gray-400">kg</span>
        </div>
        {poidsActuel > 0 && !alim.poids_ref && (
          <p className="text-xs text-gray-400 mt-1.5">Dernier pesage : {poidsActuel} kg
            <button onClick={() => setAlim(p => ({ ...p, poids_ref: poidsActuel }))} className="text-[#0C5C6C] ml-2 font-medium">Utiliser</button>
          </p>
        )}
      </section>

      {/* Phase de vie */}
      <section>
        <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Phase de vie</p>
        <div className="flex flex-wrap gap-2">
          {phaseOptions.map(([k, l]) => (
            <button key={k} onClick={() => setAlim(p => ({ ...p, phase: k }))}
              className={`px-3 py-2 rounded-full text-xs font-semibold transition-all flex items-center gap-1 ${phase === k ? 'bg-[#0C5C6C] text-white' : 'bg-white border border-gray-200 text-[#1F2A2E] hover:border-[#0C5C6C]/30'}`}>
              {l}
              {k === phaseDetecte && phase !== k && <span className="text-[9px] px-1 py-0.5 bg-gray-100 text-gray-400 rounded ml-1">auto</span>}
              {k === phaseDetecte && phase === k && <span className="text-[9px] px-1 py-0.5 bg-white/20 text-white rounded ml-1">auto</span>}
            </button>
          ))}
        </div>
      </section>

      {/* Énergie de la race (chien/chat adulte) */}
      {['chien', 'chat'].includes(espece) && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Énergie de la race</p>
          <div className="space-y-2">
            {Object.entries(CAT_ENERGIE_LABELS).map(([k, l]) => {
              const ex = espece === 'chat' ? CAT_ENERGIE_EXEMPLES_CHAT[k] : CAT_ENERGIE_EXEMPLES_CHIEN[k];
              return (
                <button key={k} onClick={() => setAlim(p => ({ ...p, cat_energie: k }))}
                  className={`w-full text-left rounded-xl px-3 py-2.5 transition-all border ${catEnergie === k ? 'bg-[#0C5C6C] border-[#0C5C6C]' : 'bg-white border-gray-200 hover:border-[#0C5C6C]/30'}`}>
                  <p className={`text-sm font-semibold ${catEnergie === k ? 'text-white' : 'text-[#1F2A2E]'}`}>{l}</p>
                  <p className={`text-xs mt-0.5 ${catEnergie === k ? 'text-white/70' : 'text-gray-400'}`}>{ex}</p>
                </button>
              );
            })}
          </div>
        </section>
      )}

      {/* Niveau d'activité (adultes) */}
      {phase === 'adulte' && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Niveau d&apos;activité</p>
          <div className="grid grid-cols-2 gap-2">
            {Object.entries(ACT_LABELS).map(([k, l]) => (
              <button key={k} onClick={() => setAlim(p => ({ ...p, activite: k }))}
                className={`py-2.5 rounded-xl text-xs font-semibold transition-all ${activite === k ? 'bg-[#0C5C6C] text-white' : 'bg-white border border-gray-200 text-gray-600 hover:border-[#0C5C6C]/30'}`}>
                {l}
              </button>
            ))}
          </div>
        </section>
      )}

      {/* État reproducteur */}
      {(sterilise || sexe === 'femelle') && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">État reproducteur</p>
          {sterilise ? (
            <div className="space-y-2">
              <div className="inline-flex items-center gap-2 px-3 py-2 bg-[#6E9E57] text-white rounded-full text-xs font-bold">
                ✂️ Stérilisé(e)
              </div>
              <div className="flex items-center gap-2 bg-[#6E9E57]/8 rounded-xl px-3 py-2 border border-[#6E9E57]/20">
                <span>✂️</span>
                <p className="text-xs text-[#4A7C39]">Réduction stérilisé appliquée : ×{espece === 'chat' ? '0.7' : '0.8'} sur les besoins énergétiques</p>
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap gap-2">
              {[['normal', '⚪', 'Normal'], ['gestation_debut', '🤰', 'Gestation (début)'], ['gestation_fin', '🍼', 'Gestation (fin)'], ['lactation', '🤱', 'Lactation']].map(([k, e, l]) => (
                <button key={k} onClick={() => setAlim(p => ({ ...p, etat_repro: p.etat_repro === k ? 'normal' : k }))}
                  className={`px-3 py-2 rounded-full text-xs font-semibold transition-all flex items-center gap-1 ${etatRepro === k ? 'bg-[#0C5C6C] text-white' : 'bg-white border border-gray-200 text-[#1F2A2E] hover:border-[#0C5C6C]/30'}`}>
                  {e} {l}
                </button>
              ))}
            </div>
          )}
          {!sterilise && etatRepro !== 'normal' && (
            <div className="mt-2 bg-[#E8F4F7] rounded-xl p-3 border border-[#0C5C6C]/15">
              <p className="text-xs font-bold text-[#0C5C6C]">
                {etatRepro === 'gestation_debut' ? 'Gestation (début) — Apports +10%' : etatRepro === 'gestation_fin' ? 'Gestation (fin) — Apports +30%' : 'Lactation — Apports +50%'}
              </p>
              <p className="text-xs text-gray-500 mt-1">
                {etatRepro === 'gestation_debut'
                  ? 'Augmentez progressivement les rations. Préférez une alimentation riche en protéines.'
                  : etatRepro === 'gestation_fin'
                    ? 'Dernières semaines : fractionnez les repas (3–4/j). Augmentez les apports progressivement.'
                    : 'Alimentation à volonté recommandée. Eau fraîche disponible en permanence.'}
              </p>
            </div>
          )}
        </section>
      )}

      {/* Paramètres croquettes */}
      {type === 'croquettes' && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Produit</p>
          <button onClick={() => setShowBrand(true)}
            className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm text-left flex items-center justify-between hover:border-[#0C5C6C]/40 transition-colors">
            <span className={alim.marque_label ? 'text-[#1F2A2E] font-medium' : 'text-gray-400'}>
              {alim.marque_label ?? 'Sélectionner une marque…'}
            </span>
            <span className="text-gray-300">›</span>
          </button>
          <div className="mt-2 flex items-center gap-3">
            <div className="flex-1">
              <p className="text-xs text-gray-400 mb-1">Densité kcal/100g</p>
              <input type="number" min="100" max="600" value={alim.densite_kcal || ''}
                onChange={e => setAlim(p => ({ ...p, densite_kcal: parseInt(e.target.value) || 350 }))}
                placeholder="350"
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm outline-none focus:border-[#0C5C6C]" />
            </div>
            <div className="text-center pt-4">
              <p className="text-xs text-gray-400">Dose jour</p>
              <p className="text-base font-bold text-[#0C5C6C]">{doseCroquettes ? `${doseCroquettes.toFixed(0)} g` : '—'}</p>
            </div>
          </div>
        </section>
      )}

      {/* Paramètres BARF */}
      {(type === 'barf' || type === 'mixte') && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-3 uppercase tracking-wide">
            {type === 'mixte' ? 'Composition BARF (partie crue)' : 'Composition BARF'}
          </p>
          {([
            { k: 'barf_muscle'        as const, e: '🥩', l: 'Muscle',          c: '#0C5C6C' },
            { k: 'barf_os'           as const, e: '🦴', l: 'Os charnus',       c: '#6E9E57' },
            { k: 'barf_abats'        as const, e: '🫀', l: 'Abats',            c: '#E8A020' },
            { k: 'barf_legumes'      as const, e: '🥬', l: 'Légumes / fruits', c: '#7B68EE' },
            { k: 'barf_complementaires' as const, e: '🌿', l: 'Compléments',   c: '#888'    },
          ]).map(({ k, e, l, c }) => {
            const val = (alim[k] as number | undefined) ?? 0;
            return (
              <div key={k} className="mb-2">
                <div className="flex justify-between text-xs mb-1">
                  <span>{e} {l}</span>
                  <span className="font-bold" style={{ color: c }}>{val}%</span>
                </div>
                <input type="range" min={0} max={100} value={val}
                  onChange={ev => setAlim(p => ({ ...p, [k]: parseInt(ev.target.value) }))}
                  className="w-full accent-[#0C5C6C] h-1" />
              </div>
            );
          })}
          {doseBarf && <p className="text-xs text-center text-[#0C5C6C] font-bold mt-1">Total BARF : {doseBarf.toFixed(0)} g/jour</p>}
        </section>
      )}

      {/* Ratio mixte */}
      {type === 'mixte' && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Ratio croquettes / BARF</p>
          <div className="flex items-center gap-3 text-xs">
            <span className="text-gray-500 w-20 text-right">Croq. {alim.mixte_ratio_croq ?? 50}%</span>
            <input type="range" min={0} max={100} value={alim.mixte_ratio_croq ?? 50}
              onChange={e => setAlim(p => ({ ...p, mixte_ratio_croq: parseInt(e.target.value) }))}
              className="flex-1 accent-[#0C5C6C] h-1" />
            <span className="text-gray-500 w-20">BARF {100 - (alim.mixte_ratio_croq ?? 50)}%</span>
          </div>
        </section>
      )}

      {/* Nb repas */}
      <section>
        <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Nombre de repas / jour</p>
        <div className="flex gap-2">
          {[1, 2, 3, 4].map(n => (
            <button key={n} onClick={() => setAlim(p => ({ ...p, nb_repas: n }))}
              className={`flex-1 py-2.5 rounded-xl text-sm font-bold transition-all ${nbRepas === n ? 'bg-[#0C5C6C] text-white' : 'bg-white border border-gray-200 text-gray-600 hover:border-[#0C5C6C]/30'}`}>
              {n}
            </button>
          ))}
        </div>
      </section>

      {/* Résultats */}
      {derVal && poids > 0 && (
        <section className="bg-[#E8F4F7] rounded-2xl p-4 border border-[#0C5C6C]/15">
          <p className="text-xs font-bold text-[#0C5C6C] mb-3 uppercase tracking-wide">Résultats calculés</p>
          <div className="space-y-1.5 text-xs">
            <div className="flex justify-between"><span className="text-gray-500">RER</span><span className="font-bold text-[#1F2A2E]">{rerVal?.toFixed(0)} kcal/j</span></div>
            <div className="flex justify-between">
              <span className="text-gray-400 text-[10px]">
                70 × {poids}^0.75
                {sterilise ? ` × ${espece === 'chat' ? '0.7' : '0.8'}` : ''}
                {etatRepro !== 'normal' ? ` × ${(REPRO_FACTORS[etatRepro] ?? 1).toFixed(1)}` : ''}
              </span>
            </div>
            <div className="flex justify-between border-t border-[#0C5C6C]/15 pt-1.5">
              <span className="font-bold text-[#0C5C6C]">DER</span>
              <span className="font-bold text-[#0C5C6C]">{derVal.toFixed(0)} kcal/j</span>
            </div>
            {type === 'croquettes' && doseCroquettes && (
              <div className="flex justify-between border-t border-[#0C5C6C]/15 pt-1.5">
                <span className="font-semibold text-[#1F2A2E]">Croquettes / jour</span>
                <span className="font-bold text-[#1F2A2E]">{doseCroquettes.toFixed(0)} g</span>
              </div>
            )}
            {type === 'barf' && doseBarf && (
              <div className="flex justify-between border-t border-[#0C5C6C]/15 pt-1.5">
                <span className="font-semibold text-[#1F2A2E]">Ration BARF / jour</span>
                <span className="font-bold text-[#1F2A2E]">{doseBarf.toFixed(0)} g</span>
              </div>
            )}
            {isGrandEspece(espece) && rationGrandEspece && (
              <div className="flex justify-between border-t border-[#0C5C6C]/15 pt-1.5">
                <span className="font-semibold text-[#1F2A2E]">Ration ({rationPctPoidsvif(espece)}% poids vif)</span>
                <span className="font-bold text-[#1F2A2E]">{(rationGrandEspece * 1000).toFixed(0)} g/j</span>
              </div>
            )}
          </div>
        </section>
      )}

      {/* Plan de repas */}
      {mealPlan.length > 0 && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Plan de repas</p>
          <div className="space-y-2">
            {mealPlan.map((r, i) => (
              <div key={i} className={`flex items-center justify-between rounded-xl p-3 border ${COLOR_MAP[r.color] ?? 'bg-gray-50 border-gray-100 text-gray-600'}`}>
                <div className="flex items-center gap-2">
                  <span className="text-lg">{r.emoji}</span>
                  <div>
                    <p className="text-xs font-bold">{r.label}</p>
                    <p className="text-xs opacity-70">{r.desc}</p>
                  </div>
                </div>
                <span className="text-sm font-bold">{r.qte}</span>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Suppléments */}
      <section>
        <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Suppléments</p>
        <div className="flex flex-wrap gap-2">
          {SUPPLEMENTS.map(s => {
            const active = (alim.supplements ?? []).includes(s);
            return (
              <button key={s} onClick={() => setAlim(p => ({
                ...p, supplements: active
                  ? (p.supplements ?? []).filter(x => x !== s)
                  : [...(p.supplements ?? []), s]
              }))}
                className={`text-xs px-2.5 py-1.5 rounded-full border font-medium transition-all ${active ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]/30'}`}>
                {s}
              </button>
            );
          })}
        </div>
      </section>

      {/* Notes */}
      <section>
        <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">Notes alimentaires</p>
        <textarea value={alim.notes_alim ?? ''} rows={3}
          onChange={e => setAlim(p => ({ ...p, notes_alim: e.target.value }))}
          placeholder="Intolérances, préférences, conseils du vétérinaire…"
          className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm outline-none focus:border-[#0C5C6C] resize-none" />
      </section>

      {/* Avertissement */}
      {poids === 0 && (
        <div className="bg-amber-50 rounded-xl p-3 border border-amber-200 text-xs text-amber-700">
          ⚠️ Renseignez le poids de référence pour obtenir les calculs de ration.
        </div>
      )}

      {/* Bouton enregistrer */}
      <button onClick={save} disabled={saving}
        className="w-full py-3.5 bg-[#0C5C6C] hover:bg-[#0a4f5e] text-white font-bold rounded-2xl text-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
        {saving ? 'Enregistrement…' : 'Enregistrer'}
      </button>

      {/* Brand picker modal */}
      {showBrand && (
        <BrandPickerModal espece={espece} phase={phase}
          onSelect={b => {
            setAlim(p => ({
              ...p,
              marque_id: b.id,
              marque_label: `${b.marque} — ${b.gamme}`,
              densite_kcal: b.densite_kcal_100g ?? p.densite_kcal,
            }));
            setShowBrand(false);
          }}
          onClose={() => setShowBrand(false)} />
      )}
    </div>
  );
}
