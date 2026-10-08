'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/lib/supabase';
import { auth } from '@/lib/firebase';

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
  marque?: string;
  gamme?: string;
  barf_muscle?: number;
  barf_os?: number;
  barf_abats?: number;
  barf_legumes?: number;
  mixte_ratio_croq?: number;
  nb_repas?: number;
  etat_repro?: string;
  notes_alim?: string;
  supplements?: string[];
  // Second composant d'une ration mixte (chien/chat) : BARF, pâtée ou
  // ration ménagère + densité de la pâtée si applicable, et si les deux
  // composants sont mélangés à chaque repas ou donnés séparément
  // (ex. croquettes le matin, pâtée le soir).
  type_mixte2?: 'barf' | 'patee' | 'menagere';
  densite_patee?: number;
  mixte_separe_repas?: boolean;
}

interface MarqueAliment {
  id: string;
  marque: string;
  gamme: string;
  densite_kcal_100g?: number;
  age_categorie?: string;
  taille_race?: string;
  type_aliment?: string;
  ajoute_par_uid?: string | null;
  kcal_estime?: boolean;
}

const MARQUE_COLS = 'id, marque, gamme, densite_kcal_100g, doses, age_categorie, taille_race, type_aliment, ajoute_par_uid, kcal_estime';

/** Estimation kcal/100 g quand l'utilisateur ne la connaît pas — moyennes du
 *  catalogue marques_aliments par espèce/type/âge (miroir de
 *  estimationKcal100g, lib/widgets/ajout_aliment_sheet.dart). */
function estimationKcal100g(espece: string, type: string, age: string, sterilise: boolean): number | null {
  const e = espece.toLowerCase();
  const patee = type === 'pâtée';
  const jr = age === 'junior', sr = age === 'senior', st = sterilise && !jr;
  if (e === 'chien') return patee ? (jr ? 90 : st ? 75 : sr ? 80 : 85) : (jr ? 390 : st ? 330 : sr ? 350 : 370);
  if (e === 'chat') return patee ? (jr ? 80 : (st || sr) ? 70 : 75) : (jr ? 390 : st ? 340 : sr ? 345 : 360);
  if (patee) return null;
  if (e === 'lapin') return 280;
  if (e === 'cheval') return 300;
  if (e === 'oiseau') return 365;
  return null;
}

interface Props {
  animalId: string;
  espece: string;
  sexe: string;
  sterilise: boolean;
  dateNaissance?: string;
  nom?: string;
  userId: string;
  // Poids renseigné sur la fiche animale — dernier repli si aucun pesage
  // n'a été enregistré dans l'historique (table `poids`).
  poidsFiche?: string;
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

// ─── Encodage `notes` compatible avec l'app Flutter ───────────────────────────
// lib/pages/eleveur/animaux/animal_fiche.dart encode certains réglages
// (sans colonne dédiée) dans `notes` :
// foinMix|granMix|compMix|nbRepas|separeParRepas|doseMan|doseMan2|typeMixte2|densitePatee|densiteGran|pctCroquMix|densiteCtrl
// Le site pilote nbRepas/separeParRepas/typeMixte2/densitePatee/doseMan(2) : le
// reste est préservé tel quel pour ne pas écraser des réglages faits côté app.
function parseNotes(raw: string | null | undefined) {
  const parts = (raw ?? '').split('|');
  return {
    foinMix: parts[0] ?? '67', granMix: parts[1] ?? '28', compMix: parts[2] ?? '5',
    nbRepas: parseInt(parts[3] ?? '', 10) || 2,
    separeParRepas: parts[4] === '1',
    doseMan: parts[5] ?? '', doseMan2: parts[6] ?? '',
    typeMixte2: ((parts[7] || 'barf') as 'barf' | 'patee' | 'menagere'),
    densitePatee: parts[8] ?? '', densiteGran: parts[9] ?? '', densiteCtrl: parts[11] ?? '',
  };
}

function buildNotes(existingRaw: string, nbRepas: number, separeParRepas: boolean,
    typeMixte2: string, densitePatee: number | undefined, pctCroquMix: number,
    doseMan?: string, doseMan2?: string): string {
  const p = parseNotes(existingRaw);
  return [
    p.foinMix, p.granMix, p.compMix, String(nbRepas), separeParRepas ? '1' : '0',
    doseMan ?? p.doseMan, doseMan2 ?? p.doseMan2, typeMixte2, densitePatee ? String(densitePatee) : '',
    p.densiteGran, String(Math.round(pctCroquMix)), p.densiteCtrl,
  ].join('|');
}

// ─── Plan de repas ───────────────────────────────────────────────────────────

interface RepasItem { emoji: string; label: string; qte: string; desc: string; color: string; }

function getMealPlan(espece: string, type: string, nbRepas: number, derKcal: number, poids: number, densiteKcal: number, barfPct: number, mixtePct: number,
    typeMixte2: 'barf' | 'patee' | 'menagere' = 'barf', densitePatee = 0, separeParRepas = false,
    saisies: { croq?: number; second?: number } = {}): RepasItem[] {
  const c = '#0C5C6C'; const g = '#6E9E57'; const o = '#E8A020'; const p = '#7B68EE';
  // Quantité quotidienne saisie (comme l'app) prioritaire sur la quantité calculée
  const doseCroq = (type !== 'mixte' ? saisies.croq : undefined) ?? (densiteKcal > 0 ? derKcal * 100 / densiteKcal : 0);
  const doseBarf = (type === 'barf' ? saisies.croq : undefined) ?? poids * 1000 * 0.025;

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
      const croqG = saisies.croq ?? doseCroq * ratio;
      const secondG = saisies.second ?? (typeMixte2 === 'menagere' ? (derKcal * (1 - ratio) / 120) * 100
        : typeMixte2 === 'patee' && densitePatee > 0 ? (derKcal * (1 - ratio) / densitePatee) * 100
        : doseBarf * (1 - ratio));
      const secondLabel = typeMixte2 === 'menagere' ? 'Ménagère' : typeMixte2 === 'patee' ? 'Pâtée' : 'BARF';
      const secondEmoji = typeMixte2 === 'menagere' ? '🍲' : typeMixte2 === 'patee' ? '🥫' : '🥩';

      if (separeParRepas && nbRepas >= 2) {
        // Un type par repas (ex : croquettes le matin, second composant le
        // soir) plutôt que mélangés à chaque repas.
        const croqRepas = Math.max(1, nbRepas - Math.floor(nbRepas / 2));
        const secondRepas = nbRepas - croqRepas;
        const items: RepasItem[] = [];
        for (let i = 0; i < croqRepas; i++) {
          items.push({ emoji: '🥣', label: `Repas ${i + 1} — Croquettes`, color: c,
            qte: `${Math.round(croqG / croqRepas)} g`, desc: `${Math.round(croqG)} g/jour au total` });
        }
        for (let i = 0; i < secondRepas; i++) {
          items.push({ emoji: secondEmoji, label: `Repas ${croqRepas + i + 1} — ${secondLabel}`, color: g,
            qte: `${Math.round(secondG / secondRepas)} g`, desc: `${Math.round(secondG)} g/jour au total` });
        }
        return items;
      }
      return [
        { emoji: '🥣', label: 'Portion croquettes', qte: `${Math.round(croqG / nbRepas)} g × ${nbRepas}`, desc: `${Math.round(croqG)} g/jour`, color: c },
        { emoji: secondEmoji, label: `Portion ${secondLabel}`, qte: `${Math.round(secondG / nbRepas)} g × ${nbRepas}`, desc: `${Math.round(secondG)} g/jour`, color: g },
      ];
    }
    if (type === 'menagere') {
      const totalG = saisies.croq ?? poids * 1000 * 0.025;
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

/** Formulaire « Ajouter mon aliment » (marque absente du catalogue) — la
 *  ligne créée est visible des autres membres (« ajouté par un membre »). */
function AjoutAlimentForm({ espece, phase, userId, marqueInitiale, onCreated, onCancel }: {
  espece: string; phase: string; userId: string; marqueInitiale: string;
  onCreated: (b: MarqueAliment) => void; onCancel: () => void;
}) {
  const [marque, setMarque] = useState(marqueInitiale);
  const [gamme, setGamme] = useState('');
  const [type, setType] = useState<'croquettes' | 'pâtée'>('croquettes');
  const [age, setAge] = useState(['junior', 'adulte', 'senior'].includes(phase) ? phase : 'adulte');
  const [sterilise, setSterilise] = useState(false);
  const [taille, setTaille] = useState<string | null>(null);
  const [kcal, setKcal] = useState('');
  const [doses, setDoses] = useState<{ p: string; g: string }[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const est = estimationKcal100g(espece, type, age, sterilise);
  const chip = (on: boolean) => `px-3 py-1.5 rounded-full text-sm border ${on ? 'bg-[#0C5C6C]/10 border-[#0C5C6C] text-[#0C5C6C] font-semibold' : 'border-gray-200 text-gray-600'}`;
  const input = 'w-full px-3 py-2 text-sm bg-gray-100 rounded-xl outline-none';
  const num = (s: string) => { const v = parseFloat(s.replace(',', '.')); return Number.isFinite(v) ? v : null; };

  async function save() {
    if (!marque.trim() || !gamme.trim()) { setError('Indiquez la marque et le nom du produit.'); return; }
    const saisi = kcal.trim() ? num(kcal) : null;
    if (kcal.trim() && (saisi === null || saisi < 20 || saisi > 700)) { setError('Valeur énergétique invalide (en kcal pour 100 g, ex. 370).'); return; }
    const d = doses.map(x => ({ poids_kg: num(x.p), grammes: num(x.g) }))
      .filter((x): x is { poids_kg: number; grammes: number } => !!x.poids_kg && !!x.grammes && x.poids_kg > 0 && x.grammes > 0)
      .sort((a, b) => a.poids_kg - b.poids_kg);
    setSaving(true); setError(null);
    const { data, error: err } = await supabase.from('marques_aliments').insert({
      marque: marque.trim(), gamme: gamme.trim(), espece: espece.toLowerCase(),
      type_aliment: type, age_categorie: age, formule_sterilise: sterilise && age !== 'junior',
      ...(taille ? { taille_race: taille } : {}),
      densite_kcal_100g: saisi ?? est, kcal_estime: saisi === null,
      // Auteur = utilisateur connecté (la RLS l'exige) — userId peut désigner
      // le propriétaire de l'animal quand un co-propriétaire consulte la fiche.
      doses: d, notes: 'Ajouté par un membre', ajoute_par_uid: auth.currentUser?.uid ?? userId,
    }).select(MARQUE_COLS).single();
    setSaving(false);
    if (err || !data) { setError('Enregistrement impossible, réessayez.'); return; }
    onCreated(data as MarqueAliment);
  }

  return (
    <div className="overflow-y-auto flex-1 px-4 py-3 space-y-3 text-sm">
      <div><p className="font-semibold mb-1">Marque *</p>
        <input value={marque} onChange={e => setMarque(e.target.value)} placeholder="Ex : Josera, Carnilove…" className={input} /></div>
      <div><p className="font-semibold mb-1">Nom du produit / gamme *</p>
        <input value={gamme} onChange={e => setGamme(e.target.value)} placeholder="Ex : Adult Medium Agneau" className={input} /></div>
      <div><p className="font-semibold mb-1">Type</p>
        <div className="flex gap-2">
          {(['croquettes', 'pâtée'] as const).map(t => <button key={t} type="button" onClick={() => setType(t)} className={chip(type === t)}>{t === 'croquettes' ? 'Croquettes' : 'Pâtée'}</button>)}
        </div></div>
      <div><p className="font-semibold mb-1">Âge</p>
        <div className="flex gap-2 flex-wrap">
          {[['junior', 'Junior / chiot, chaton'], ['adulte', 'Adulte'], ['senior', 'Senior']].map(([v, l]) =>
            <button key={v} type="button" onClick={() => setAge(v)} className={chip(age === v)}>{l}</button>)}
        </div></div>
      {age !== 'junior' && (
        <label className="flex items-center gap-2"><input type="checkbox" checked={sterilise} onChange={e => setSterilise(e.target.checked)} /> Formule stérilisé / light</label>
      )}
      {espece.toLowerCase() === 'chien' && (
        <div><p className="font-semibold mb-1">Taille de race (facultatif)</p>
          <div className="flex gap-2 flex-wrap">
            {([[null, 'Toutes'], ['petite', 'Petite'], ['moyenne', 'Moyenne'], ['grande', 'Grande']] as const).map(([v, l]) =>
              <button key={l} type="button" onClick={() => setTaille(v)} className={chip(taille === v)}>{l}</button>)}
          </div></div>
      )}
      <div><p className="font-semibold mb-1">Valeur énergétique (kcal pour 100 g)</p>
        <div className="p-3 rounded-xl bg-amber-50 border border-amber-300 text-amber-900 text-xs leading-relaxed mb-2">
          ⚠️ Information essentielle pour calculer la bonne ration. Elle figure sur le paquet (« valeur énergétique » ou
          « énergie métabolisable », en kcal/100 g ou kcal/kg ÷ 10).{' '}
          {est !== null
            ? <>Si vous ne l&apos;avez pas, nous utiliserons une estimation ({est} kcal/100 g) : la ration sera moins précise.</>
            : <>Sans elle, la ration ne pourra pas être calculée pour cette espèce.</>}
        </div>
        <input value={kcal} onChange={e => setKcal(e.target.value)} inputMode="decimal" placeholder={est !== null ? `Ex : ${est}` : 'Ex : 370'} className={input} /></div>
      <div><p className="font-semibold mb-1">Tableau de rationnement du paquet (recommandé)</p>
        <p className="text-xs text-gray-500 mb-2">Au dos du paquet : la quantité par jour selon le poids de l&apos;animal.</p>
        {doses.map((d, i) => (
          <div key={i} className="flex gap-2 mb-2 items-center">
            <input value={d.p} onChange={e => setDoses(ds => ds.map((x, j) => j === i ? { ...x, p: e.target.value } : x))} inputMode="decimal" placeholder="Poids (kg)" className={input} />
            <input value={d.g} onChange={e => setDoses(ds => ds.map((x, j) => j === i ? { ...x, g: e.target.value } : x))} inputMode="decimal" placeholder="g / jour" className={input} />
            <button type="button" onClick={() => setDoses(ds => ds.filter((_, j) => j !== i))} className="text-gray-400 px-1">✕</button>
          </div>
        ))}
        <button type="button" onClick={() => setDoses(ds => [...ds, { p: '', g: '' }])} className="text-[#0C5C6C] font-semibold text-sm">+ Ajouter une ligne poids → quantité</button></div>
      {error && <p className="text-red-600 text-sm">{error}</p>}
      <p className="text-xs text-gray-400">L&apos;aliment sera visible des autres membres pour cette espèce (« ajouté par un membre »).</p>
      <div className="flex gap-2 pt-1">
        <button type="button" onClick={onCancel} className="flex-1 py-2 border border-gray-200 rounded-xl text-gray-600">Retour</button>
        <button type="button" onClick={save} disabled={saving} className="flex-1 py-2 bg-[#0C5C6C] text-white rounded-xl font-semibold disabled:opacity-50">
          {saving ? 'Enregistrement…' : 'Ajouter et sélectionner'}
        </button>
      </div>
    </div>
  );
}

function BrandPickerModal({ espece, phase, userId, onSelect, onClose }: {
  espece: string; phase: string; userId: string;
  onSelect: (b: MarqueAliment) => void; onClose: () => void;
}) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<MarqueAliment[]>([]);
  const [loading, setLoading] = useState(false);
  const [adding, setAdding] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const doFetch = useCallback(async (q: string) => {
    setLoading(true);
    try {
      let req = supabase.from('marques_aliments')
        .select(MARQUE_COLS)
        .eq('espece', espece);
      // Hors junior : adulte ET senior (un chien senior doit trouver sa gamme senior).
      if (phase !== 'junior') req = req.in('age_categorie', ['adulte', 'senior']);
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
          <p className="text-base font-bold text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
            {adding ? 'Ajouter mon aliment' : 'Choisir un aliment'}
          </p>
          {!adding && <>
            <input
              autoFocus
              value={query}
              onChange={e => onChange(e.target.value)}
              placeholder="Ex : Royal Canin, Orijen, Pro Plan…"
              className="w-full px-3 py-2 text-sm bg-gray-100 rounded-full outline-none"
            />
            {loading && <div className="h-0.5 bg-[#0C5C6C] mt-2 animate-pulse rounded-full" />}
          </>}
        </div>
        {adding ? (
          <AjoutAlimentForm espece={espece} phase={phase} userId={userId} marqueInitiale={query.trim()}
            onCreated={onSelect} onCancel={() => setAdding(false)} />
        ) : <>
        <div className="overflow-y-auto flex-1">
          {results.length === 0 && !loading ? (
            <div className="text-center py-8">
              <p className="text-sm text-gray-400 mb-3">
                {query ? `Aucun résultat pour « ${query} »` : 'Aucune marque dans la base'}
              </p>
              <button onClick={() => setAdding(true)} className="px-4 py-2 bg-[#0C5C6C] text-white rounded-xl text-sm font-semibold">
                + Ajouter mon aliment
              </button>
            </div>
          ) : results.map(b => (
            <button key={b.id} onClick={() => onSelect(b)}
              className="w-full text-left px-4 py-3 border-b border-gray-50 hover:bg-gray-50 transition-colors">
              <p className="text-sm font-semibold text-[#1F2A2E]">{b.marque} — {b.gamme}</p>
              <div className="flex gap-2 mt-0.5 flex-wrap">
                {b.densite_kcal_100g && (b.kcal_estime
                  ? <span className="text-xs text-orange-700">≈ {b.densite_kcal_100g} kcal/100g (estimé)</span>
                  : <span className="text-xs text-gray-400">{b.densite_kcal_100g} kcal/100g</span>)}
                {b.type_aliment === 'pâtée' && <span className="text-xs text-gray-400">Pâtée</span>}
                {b.ajoute_par_uid && <span className="text-xs px-1.5 py-0.5 bg-[#EAF2F4] text-[#0C5C6C] rounded">Ajouté par un membre</span>}
                {b.age_categorie === 'junior' && <span className="text-xs px-1.5 py-0.5 bg-amber-100 text-amber-700 rounded">Junior</span>}
                {b.taille_race && b.taille_race !== 'toutes' && <span className="text-xs px-1.5 py-0.5 bg-gray-100 text-gray-500 rounded">{b.taille_race}</span>}
              </div>
            </button>
          ))}
        </div>
        <div className="p-3 border-t border-gray-100">
          {results.length > 0 && (
            <button onClick={() => setAdding(true)} className="w-full py-2 text-sm text-[#0C5C6C] font-semibold">
              + Mon aliment n&apos;est pas dans la liste — l&apos;ajouter
            </button>
          )}
          <button onClick={onClose} className="w-full py-2 text-sm text-gray-500 font-medium">Annuler</button>
        </div>
        </>}
      </div>
    </div>
  );
}

// ─── Composant AlimentationTab ────────────────────────────────────────────────

export default function AlimentationTab({ animalId, espece, sexe, sterilise, dateNaissance, nom, userId, poidsFiche }: Props) {
  const [alimState, setAlim] = useState<AlimData>({
    type_ration: 'croquettes', phase: 'adulte', activite: 'normal',
    cat_energie: 'normale', poids_ref: 0, densite_kcal: 350,
    barf_muscle: 70, barf_os: 15, barf_abats: 10, barf_legumes: 5,
    mixte_ratio_croq: 50, nb_repas: 2, etat_repro: 'normal', supplements: [],
    type_mixte2: 'barf', mixte_separe_repas: false,
  });
  // Notes brutes telles que chargées, pour préserver au réenregistrement les
  // champs qu'on ne pilote pas depuis le site (voir buildNotes plus haut).
  const alim = alimState;
  const [notesRaw, setNotesRaw] = useState('');
  const [poidsActuel, setPoidsActuel] = useState<number>(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [view, setView] = useState<'summary' | 'calc'>('summary');
  const [showBrand, setShowBrand] = useState(false);
  const [hasData, setHasData] = useState(false);
  // Quantité quotidienne saisie (g/jour) — partagée avec l'app via `notes`
  const [doseMan, setDoseMan] = useState('');
  const [doseMan2, setDoseMan2] = useState('');

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
        // La table `alimentations` utilise des noms de colonnes différents de
        // l'état local (aligné historiquement sur un autre schéma) : on
        // traduit explicitement plutôt que de spreader alimData tel quel,
        // sinon rien ne se charge (ni ne s'enregistre, voir save() plus bas).
        setAlim(prev => ({
          ...prev,
          id: alimData.id,
          type_ration: alimData.type_ration ?? prev.type_ration,
          phase: (alimData.phase_vie && alimData.phase_vie !== 'auto') ? alimData.phase_vie : phaseAuto(),
          activite: alimData.niveau_activite ?? prev.activite,
          cat_energie: alimData.categorie_energie ?? prev.cat_energie,
          poids_ref: alimData.poids_objectif ?? 0,
          densite_kcal: alimData.densite_calorique ?? prev.densite_kcal,
          marque_id: alimData.marque_id ?? undefined,
          marque: alimData.marque ?? undefined,
          gamme: alimData.gamme ?? undefined,
          barf_muscle: alimData.pourcentage_muscles ?? prev.barf_muscle,
          barf_os: alimData.pourcentage_os ?? prev.barf_os,
          barf_abats: alimData.pourcentage_abats ?? prev.barf_abats,
          barf_legumes: alimData.pourcentage_legumes ?? prev.barf_legumes,
          mixte_ratio_croq: alimData.mixte_ratio_croq ?? prev.mixte_ratio_croq,
          type_mixte2: parseNotes(alimData.notes).typeMixte2,
          mixte_separe_repas: parseNotes(alimData.notes).separeParRepas,
          densite_patee: parseFloat(parseNotes(alimData.notes).densitePatee) || undefined,
          nb_repas: parseNotes(alimData.notes).nbRepas,
        }));
        setNotesRaw(alimData.notes ?? '');
        setDoseMan(parseNotes(alimData.notes).doseMan);
        setDoseMan2(parseNotes(alimData.notes).doseMan2);
        setHasData(true);
        setView('summary');
      } else {
        setView('calc');
      }
      // Dernier pesage de l'historique, sinon le poids renseigné sur la fiche
      // animale (ex : aucune entrée dans le suivi de poids mais un poids a
      // été saisi à la création de la fiche).
      const dernierPesage = poidsData && poidsData.length > 0 ? parseFloat(poidsData[0].valeur) || 0 : 0;
      const poidsFicheNum = poidsFiche ? parseFloat(poidsFiche.replace(',', '.')) || 0 : 0;
      setPoidsActuel(dernierPesage || poidsFicheNum || 0);
    } finally { setLoading(false); }
  }, [animalId, poidsFiche]);

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

  // Second composant d'une ration mixte : BARF, pâtée (densité requise) ou
  // ration ménagère (calcul énergétique, sans densité à saisir).
  const typeMixte2 = alim.type_mixte2 ?? 'barf';
  const mixteSepareParRepas = alim.mixte_separe_repas ?? false;
  const densitePatee = alim.densite_patee ?? 0;
  const pctSecond = 1 - (alim.mixte_ratio_croq ?? 50) / 100;
  const doseMixteSecond = !derVal ? null
    : typeMixte2 === 'menagere' ? (derVal * pctSecond / 120) * 100
    : typeMixte2 === 'patee' ? (densitePatee > 0 ? (derVal * pctSecond / densitePatee) * 100 : null)
    : doseBarf != null ? doseBarf * pctSecond : null;
  const mixteSecondLabel = typeMixte2 === 'menagere' ? 'Ménagère' : typeMixte2 === 'patee' ? 'Pâtée' : 'BARF';

  // Doses effectives (saisie prioritaire) et apport calculé — mêmes règles que l'app
  const num = (v: string) => { const n = parseFloat(v.replace(',', '.')); return isFinite(n) && n > 0 ? n : null; };
  const doseMenagere = poids > 0 ? poids * 1000 * 0.025 : null;
  const doseMixteCroq = doseCroquettes != null ? doseCroquettes * (alim.mixte_ratio_croq ?? 50) / 100 : null;
  const doseCalculee = type === 'croquettes' ? doseCroquettes : type === 'barf' ? doseBarf
    : type === 'menagere' ? doseMenagere : type === 'mixte' ? doseMixteCroq : null;
  const doseEff = num(doseMan) ?? doseCalculee;
  const doseEff2 = num(doseMan2) ?? doseMixteSecond;
  const kcalApport: number | null = (() => {
    if (doseEff == null) return null;
    if (type === 'croquettes') return densiteKcal > 0 ? doseEff * densiteKcal / 100 : null;
    if (type === 'barf') return doseEff * 1.25;
    if (type === 'menagere') return doseEff * 1.2;
    if (type === 'mixte') {
      let t = densiteKcal > 0 ? doseEff * densiteKcal / 100 : 0;
      if (doseEff2 != null) {
        t += typeMixte2 === 'barf' ? doseEff2 * 1.25 : typeMixte2 === 'menagere' ? doseEff2 * 1.2
          : densitePatee > 0 ? doseEff2 * densitePatee / 100 : 0;
      }
      return t > 0 ? t : null;
    }
    return null;
  })();

  // ── Save ────────────────────────────────────────────────────────────────────

  async function save(patch: Partial<AlimData> = {}) {
    if (!animalId) return;
    const alim = { ...alimState, ...patch };
    setSaving(true);
    try {
      // N'écrit que des colonnes qui existent réellement sur `alimentations`
      // (mêmes noms que l'app Flutter) — étatRepro/suppléments n'ont pas de
      // colonne dédiée et restent locaux à cette session ; nb de repas, type
      // du 2e composant mixte et densité pâtée passent par `notes` (même
      // encodage que l'app, voir buildNotes plus haut).
      const payload = {
        animal_id: animalId,
        uid_eleveur: userId,
        type_ration: alim.type_ration,
        niveau_activite: alim.activite,
        categorie_energie: alim.cat_energie,
        phase_vie: alim.phase,
        poids_objectif: poids || null,
        marque_id: alim.marque_id ?? null,
        marque: alim.marque ?? null,
        gamme: alim.gamme ?? null,
        densite_calorique: alim.densite_kcal ?? null,
        pourcentage_muscles: alim.barf_muscle ?? null,
        pourcentage_abats: alim.barf_abats ?? null,
        pourcentage_os: alim.barf_os ?? null,
        pourcentage_legumes: alim.barf_legumes ?? null,
        mixte_ratio_croq: alim.mixte_ratio_croq ?? null,
        notes: buildNotes(notesRaw, alim.nb_repas ?? 2, alim.mixte_separe_repas ?? false,
          alim.type_mixte2 ?? 'barf', alim.densite_patee, alim.mixte_ratio_croq ?? 50, doseMan, doseMan2),
        updated_at: new Date().toISOString(),
      };
      if (alim.id) {
        await supabase.from('alimentations').update(payload).eq('id', alim.id);
      } else {
        const { data } = await supabase.from('alimentations').insert({ ...payload, id: crypto.randomUUID() }).select().single();
        if (data) setAlim(prev => ({ ...prev, id: data.id }));
      }
      setNotesRaw(payload.notes);
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
    ? getMealPlan(espece, type, nbRepas, derVal, poids, densiteKcal, alim.barf_muscle ?? 70, alim.mixte_ratio_croq ?? 50,
        typeMixte2, densitePatee, mixteSepareParRepas,
        { croq: num(doseMan) ?? undefined, second: num(doseMan2) ?? undefined })
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
    const typeLabel: Record<string, string> = { croquettes: 'Croquettes', barf: 'BARF', mixte: 'Ration mixte', menagere: 'Ration ménagère' };
    const phaseLabel: Record<string, string> = { chiot: 'Chiot', junior: 'Junior', adulte: 'Adulte', senior: 'Senior', geront: 'Gérontologie' };
    const etatLabel: Record<string, string> = { gestation_debut: 'Gestation (début)', gestation_fin: 'Gestation (fin)', lactation: 'Lactation' };
    const ajustement: Record<string, string> = { gestation_debut: 'début de gestation (+10 %)', gestation_fin: 'fin de gestation (+30 %)', lactation: 'lactation (+50 %)' };
    const chienChat = espece === 'chien' || espece === 'chat';
    const fmtKg = (v: number) => v.toFixed(1).replace('.', ',');

    // Apport calculé : correspondance calorique (couleurs fonctionnelles existantes)
    let apport: { color: string; pct: number; statut: string } | null = null;
    if (kcalApport != null && derVal) {
      const diff = kcalApport - derVal;
      const ok = Math.abs(diff) / derVal < 0.15;
      apport = {
        color: ok ? '#6E9E57' : diff > 0 ? '#E65100' : '#0C5C6C',
        pct: Math.round((diff / derVal) * 100),
        statut: ok ? 'Correspond aux besoins caloriques' : diff > 0 ? 'Supérieur aux besoins caloriques' : 'Inférieur aux besoins caloriques',
      };
    }

    const titre = (children: React.ReactNode, onModifier?: () => void) => (
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-[17px] font-extrabold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{children}</h3>
        {onModifier && (
          <button type="button" onClick={onModifier}
            className="h-10 px-2 text-sm font-semibold text-[#0C5C6C] hover:underline">
            Modifier
          </button>
        )}
      </div>
    );
    const ligne = (label: string, value: string) => (
      <div key={label} className="flex items-center justify-between gap-3 px-4 min-h-[48px] py-3">
        <span className="text-[15px] text-gray-600">{label}</span>
        <span className="text-[15px] font-semibold text-[#1F2A2E] text-right">{value}</span>
      </div>
    );
    const panneau = 'bg-white border border-gray-300 rounded-xl divide-y divide-gray-200 overflow-hidden';
    const champDose = (label: string, value: string, onChange: (v: string) => void, calcule: number | null) => (
      <div>
        <label className="block text-sm text-gray-600 mb-1.5">{label}</label>
        <div className="flex h-[52px] rounded-[10px] border border-gray-300 overflow-hidden bg-white focus-within:border-[#0C5C6C] focus-within:ring-1 focus-within:ring-[#0C5C6C]">
          <input type="text" inputMode="decimal" value={value} onChange={e => onChange(e.target.value)}
            placeholder={calcule != null ? String(Math.round(calcule)) : 'Quantité'}
            className="flex-1 min-w-0 px-3.5 text-base font-semibold text-[#1F2A2E] placeholder:text-gray-500 outline-none" />
          <span className="flex items-center px-3.5 bg-gray-100 border-l border-gray-300 text-[15px] text-gray-700">g/jour</span>
        </div>
        {value && calcule != null && (
          <button type="button" onClick={() => onChange('')}
            className="mt-1 h-9 text-[13px] text-[#0C5C6C] hover:underline">
            Revenir à la quantité calculée ({Math.round(calcule)} g)
          </button>
        )}
      </div>
    );

    return (
      <div className="max-w-2xl">
        {/* Profil de l'animal */}
        {titre("Profil de l'animal", () => setView('calc'))}
        <div className={panneau}>
          {ligne('Poids', poids > 0 ? `${fmtKg(poids)} kg` : '—')}
          {ligne("Phase", phaseLabel[phase] ?? phase)}
          {phase === 'adulte' && ligne('Activité', ACT_LABELS[activite] ?? activite)}
          {sterilise && ligne('Stérilisé(e)', 'Oui')}
          {etatRepro !== 'normal' && ligne('État', etatLabel[etatRepro] ?? etatRepro)}
        </div>

        {/* Besoins caloriques */}
        {rerVal && (
          <div className="mt-4 flex bg-white border border-gray-300 rounded-xl overflow-hidden">
            <div className="w-1 bg-[#0C5C6C] flex-shrink-0" />
            <div className="px-4 py-3.5">
              <p className="text-sm text-gray-600">Besoins caloriques</p>
              <p className="text-[28px] leading-tight font-extrabold text-[#0C5C6C] mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>
                {derVal ? `${derVal.toFixed(0)} kcal/jour` : `${rerVal.toFixed(0)} kcal/jour (RER)`}
              </p>
              {derVal && <p className="text-[13px] text-gray-600 mt-1">RER {rerVal.toFixed(0)} × facteurs (phase, activité, état)</p>}
            </div>
          </div>
        )}

        <hr className="my-6 border-gray-200" />

        {/* Ration : croquettes / BARF / ménagère / mixte */}
        {titre(typeLabel[type] ?? type, () => setView('calc'))}
        {chienChat ? (
          <div className="space-y-3">
            {(type === 'croquettes' || type === 'mixte') && alim.marque && (
              <p className="text-base font-semibold text-[#1F2A2E]">{alim.marque}{alim.gamme ? ` — ${alim.gamme}` : ''}</p>
            )}
            {type === 'mixte' ? (
              <>
                {champDose(`Croquettes (${alim.mixte_ratio_croq ?? 50} %)`, doseMan, setDoseMan, doseMixteCroq)}
                {champDose(`${mixteSecondLabel} (${100 - (alim.mixte_ratio_croq ?? 50)} %)`, doseMan2, setDoseMan2, doseMixteSecond)}
                <p className="text-[13px] text-gray-600">{mixteSepareParRepas ? 'Un type par repas' : 'Mélangés à chaque repas'}</p>
              </>
            ) : (
              champDose("Quantité quotidienne", doseMan, setDoseMan, doseCalculee)
            )}
            {type === 'barf' && doseEff != null && (
              <div className={panneau}>
                {ligne("Muscles", `${Math.round(doseEff * (alim.barf_muscle ?? 70) / 100)} g`)}
                {ligne("Abats", `${Math.round(doseEff * (alim.barf_abats ?? 10) / 100)} g`)}
                {ligne("Os", `${Math.round(doseEff * (alim.barf_os ?? 15) / 100)} g`)}
                {ligne("Légumes", `${Math.round(doseEff * (alim.barf_legumes ?? 5) / 100)} g`)}
              </div>
            )}
          </div>
        ) : (
          <div className={panneau}>
            {rationGrandEspece
              ? ligne('Ration / jour', `${(rationGrandEspece * 1000).toFixed(0)} g (${rationGrandEspece.toFixed(2)} kg)`)
              : ligne('Ration / jour', 'Renseignez le poids pour calculer')}
          </div>
        )}

        {/* Apport calculé */}
        {apport && kcalApport != null && (
          <div className="mt-3.5 rounded-[10px] border px-3.5 py-3"
            style={{ borderColor: `${apport.color}4D`, backgroundColor: `${apport.color}0F` }}>
            <p className="text-[15px] font-bold" style={{ color: apport.color }}>Apport calculé : {Math.round(kcalApport)} kcal/jour</p>
            <p className="mt-1 flex items-center gap-2 text-[13px] text-gray-700">
              <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: apport.color }} />
              Écart aux besoins : {apport.pct > 0 ? '+' : ''}{apport.pct} % · {apport.statut}
            </p>
          </div>
        )}

        <button type="button" onClick={() => save()} disabled={saving}
          className="mt-4 w-full h-[50px] rounded-[10px] bg-[#0C5C6C] text-white text-[15px] font-bold hover:bg-[#0a4f5d] disabled:bg-gray-300 transition-colors">
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>

        {/* Rations journalières */}
        {mealPlan.length > 0 && (
          <>
            <hr className="my-6 border-gray-200" />
            {titre('Rations journalières')}
            {chienChat && (
              <div className="flex items-center justify-between gap-3">
                <span className="text-[15px] text-gray-700">Repas par jour</span>
                <div className="flex h-11 rounded-[10px] border border-gray-300 overflow-hidden" role="group" aria-label="Repas par jour">
                  {[1, 2, 3, 4].map(n => (
                    <button key={n} type="button" aria-pressed={nbRepas === n}
                      onClick={() => { setAlim(p => ({ ...p, nb_repas: n })); save({ nb_repas: n }); }}
                      className={`w-12 sm:w-14 text-[15px] font-bold transition-colors ${n > 1 ? 'border-l border-gray-300' : ''} ${nbRepas === n ? 'bg-[#0C5C6C] text-white' : 'bg-white text-[#1F2A2E] hover:bg-gray-50'}`}>
                      {n}
                    </button>
                  ))}
                </div>
              </div>
            )}
            {etatRepro !== 'normal' && ajustement[etatRepro] && (
              <p className="mt-2 text-[13px] text-gray-600">Ration ajustée : {ajustement[etatRepro]}</p>
            )}
            <div className={`${panneau} mt-3.5`}>
              {mealPlan.map((r, i) => (
                <div key={i} className="flex items-center justify-between gap-3 px-4 py-3">
                  <div className="min-w-0">
                    <p className="text-[15px] font-bold text-[#1F2A2E]">{r.label}</p>
                    <p className="text-[13px] text-gray-600">{r.desc}</p>
                  </div>
                  <span className="text-[15px] font-bold text-[#0C5C6C] whitespace-nowrap">{r.qte}</span>
                </div>
              ))}
            </div>
          </>
        )}

        {/* Suppléments */}
        {(alim.supplements ?? []).length > 0 && (
          <>
            <hr className="my-6 border-gray-200" />
            {titre('Suppléments')}
            <div className={panneau}>
              {(alim.supplements ?? []).map(s => ligne(s, ""))}
            </div>
          </>
        )}

        {alim.notes_alim && (
          <>
            <hr className="my-6 border-gray-200" />
            {titre('Notes')}
            <p className="text-sm text-gray-700 whitespace-pre-line">{alim.notes_alim}</p>
          </>
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
            placeholder={poidsActuel > 0 ? `${poidsActuel} kg` : 'Ex: 12.5'}
            className="flex-1 border border-gray-200 rounded-xl px-3 py-2.5 text-sm outline-none focus:border-[#0C5C6C]" />
          <span className="text-sm text-gray-400">kg</span>
        </div>
        {poidsActuel > 0 && !alim.poids_ref && (
          <p className="text-xs text-gray-400 mt-1.5">Poids connu : {poidsActuel} kg
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

      {/* Paramètres croquettes (aussi utilisé par le composant croquettes d'une ration mixte) */}
      {(type === 'croquettes' || type === 'mixte') && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">
            {type === 'mixte' ? 'Croquettes (marque)' : 'Produit'}
          </p>
          <button onClick={() => setShowBrand(true)}
            className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm text-left flex items-center justify-between hover:border-[#0C5C6C]/40 transition-colors">
            <span className={alim.marque ? 'text-[#1F2A2E] font-medium' : 'text-gray-400'}>
              {alim.marque ? `${alim.marque} — ${alim.gamme}` : 'Sélectionner une marque…'}
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
              <p className="text-base font-bold text-[#0C5C6C]">
                {doseCroquettes
                  ? `${(type === 'mixte' ? doseCroquettes * (alim.mixte_ratio_croq ?? 50) / 100 : doseCroquettes).toFixed(0)} g`
                  : '—'}
              </p>
            </div>
          </div>
        </section>
      )}

      {/* Second composant (mixte uniquement) */}
      {type === 'mixte' && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">2ᵉ composant (avec les croquettes)</p>
          <div className="grid grid-cols-3 gap-2">
            {([['barf', '🥩', 'BARF'], ['patee', '🥫', 'Pâtée'], ['menagere', '🍲', 'Ménagère']] as const).map(([k, e, l]) => (
              <button key={k} onClick={() => setAlim(p => ({ ...p, type_mixte2: k }))}
                className={`py-2 rounded-xl text-xs font-semibold transition-all flex items-center justify-center gap-1 ${typeMixte2 === k ? 'bg-[#0C5C6C] text-white' : 'bg-white border border-gray-200 text-gray-600 hover:border-[#0C5C6C]/30'}`}>
                {e} {l}
              </button>
            ))}
          </div>
          {typeMixte2 === 'patee' && (
            <div className="mt-2">
              <p className="text-xs text-gray-400 mb-1">Densité pâtée (kcal/100g, sur l&apos;emballage)</p>
              <input type="number" min="50" max="200" value={alim.densite_patee || ''}
                onChange={e => setAlim(p => ({ ...p, densite_patee: parseInt(e.target.value) || undefined }))}
                placeholder="Ex : 85"
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm outline-none focus:border-[#0C5C6C]" />
            </div>
          )}
        </section>
      )}

      {/* Paramètres BARF */}
      {(type === 'barf' || (type === 'mixte' && typeMixte2 === 'barf')) && (
        <section>
          <p className="text-xs font-bold text-[#1F2A2E] mb-3 uppercase tracking-wide">
            {type === 'mixte' ? 'Composition BARF (partie crue)' : 'Composition BARF'}
          </p>
          {([
            { k: 'barf_muscle'        as const, e: '🥩', l: 'Muscle',          c: '#0C5C6C' },
            { k: 'barf_os'           as const, e: '🦴', l: 'Os charnus',       c: '#6E9E57' },
            { k: 'barf_abats'        as const, e: '🫀', l: 'Abats',            c: '#E8A020' },
            { k: 'barf_legumes'      as const, e: '🥬', l: 'Légumes / fruits', c: '#7B68EE' },
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
          <p className="text-xs font-bold text-[#1F2A2E] mb-2 uppercase tracking-wide">
            Ratio croquettes / {typeMixte2 === 'menagere' ? 'ménagère' : typeMixte2 === 'patee' ? 'pâtée' : 'BARF'}
          </p>
          <div className="flex items-center gap-3 text-xs">
            <span className="text-gray-500 w-20 text-right">Croq. {alim.mixte_ratio_croq ?? 50}%</span>
            <input type="range" min={0} max={100} value={alim.mixte_ratio_croq ?? 50}
              onChange={e => setAlim(p => ({ ...p, mixte_ratio_croq: parseInt(e.target.value) }))}
              className="flex-1 accent-[#0C5C6C] h-1" />
            <span className="text-gray-500 w-20">{mixteSecondLabel.replace(/^[^\s]+\s/, '')} {100 - (alim.mixte_ratio_croq ?? 50)}%</span>
          </div>

          <p className="text-xs font-bold text-[#1F2A2E] mb-2 mt-4 uppercase tracking-wide">Répartition des repas</p>
          <div className="grid grid-cols-2 gap-2">
            <button onClick={() => setAlim(p => ({ ...p, mixte_separe_repas: false }))}
              className={`text-left px-3 py-2.5 rounded-xl border transition-all ${!mixteSepareParRepas ? 'bg-[#0C5C6C] border-[#0C5C6C]' : 'bg-white border-gray-200 hover:border-[#0C5C6C]/30'}`}>
              <p className={`text-xs font-semibold ${!mixteSepareParRepas ? 'text-white' : 'text-[#1F2A2E]'}`}>Mélangés à chaque repas</p>
              <p className={`text-[10px] mt-0.5 ${!mixteSepareParRepas ? 'text-white/70' : 'text-gray-400'}`}>Les deux composants à chaque repas</p>
            </button>
            <button onClick={() => setAlim(p => ({ ...p, mixte_separe_repas: true }))}
              className={`text-left px-3 py-2.5 rounded-xl border transition-all ${mixteSepareParRepas ? 'bg-[#0C5C6C] border-[#0C5C6C]' : 'bg-white border-gray-200 hover:border-[#0C5C6C]/30'}`}>
              <p className={`text-xs font-semibold ${mixteSepareParRepas ? 'text-white' : 'text-[#1F2A2E]'}`}>Un type par repas</p>
              <p className={`text-[10px] mt-0.5 ${mixteSepareParRepas ? 'text-white/70' : 'text-gray-400'}`}>Ex : croquettes le matin, {typeMixte2 === 'menagere' ? 'ménagère' : typeMixte2 === 'patee' ? 'pâtée' : 'BARF'} le soir</p>
            </button>
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
            {type === 'mixte' && doseCroquettes && (
              <>
                <div className="flex justify-between border-t border-[#0C5C6C]/15 pt-1.5">
                  <span className="font-semibold text-[#1F2A2E]">Croquettes / jour</span>
                  <span className="font-bold text-[#1F2A2E]">{(doseCroquettes * (alim.mixte_ratio_croq ?? 50) / 100).toFixed(0)} g</span>
                </div>
                <div className="flex justify-between">
                  <span className="font-semibold text-[#1F2A2E]">{mixteSecondLabel} / jour</span>
                  <span className="font-bold text-[#1F2A2E]">{doseMixteSecond != null ? `${doseMixteSecond.toFixed(0)} g` : '—'}</span>
                </div>
              </>
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
      <button onClick={() => save()} disabled={saving}
        className="w-full py-3.5 bg-[#0C5C6C] hover:bg-[#0a4f5e] text-white font-bold rounded-2xl text-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
        {saving ? 'Enregistrement…' : 'Enregistrer'}
      </button>

      {/* Brand picker modal */}
      {showBrand && (
        <BrandPickerModal espece={espece} phase={phase} userId={userId}
          onSelect={b => {
            setAlim(p => ({
              ...p,
              marque_id: b.id,
              marque: b.marque,
              gamme: b.gamme,
              densite_kcal: b.densite_kcal_100g ?? p.densite_kcal,
            }));
            setShowBrand(false);
          }}
          onClose={() => setShowBrand(false)} />
      )}
    </div>
  );
}
