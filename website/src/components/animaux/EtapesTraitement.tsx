'use client';
// Saisie d'un traitement en étapes (propriétaire) : chaque étape a sa durée,
// son rythme et ses prises (heure + quantité). Ex. étape 1 : 4 jours,
// 08:00 · 1 cp et 20:00 · ½ cp ; étape 2 : 3 jours, 08:00 · ½ cp. La date de
// fin découle de la date de début et du total des jours. Enregistré en une
// ligne `traitements` par étape (même groupe_id, notes « Phase i/n »).
// Miroir appli : EtapesTraitementEditor / lignesEtapes
// (lib/widgets/carnet/prises_traitement.dart).
import { useState } from 'react';

export interface Prise { h: string; q: string }
export interface Etape { duree: number; frequence: number; prises: Prise[] }

const cls = 'border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
const etiquette = 'text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block';

const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const jourPlus = (iso: string, n: number) => { const d = new Date(`${iso}T12:00:00`); d.setDate(d.getDate() + n); return ymd(d); };
const fr = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

export const totalJours = (etapes: Etape[]) => etapes.reduce((s, e) => s + e.duree, 0);

/** « 1 cp à 08:00, ½ cp à 20:00, pendant 4 jours ». */
export function libelleEtape(e: Etape): string {
  const p = e.prises.map(x => (x.q ? `${x.q} à ${x.h}` : x.h)).join(', ');
  return [p, e.frequence > 1 ? `tous les ${e.frequence} jours` : '', `pendant ${e.duree} jour${e.duree > 1 ? 's' : ''}`]
    .filter(Boolean).join(', ');
}

/** Lignes `traitements` (une par étape, dates enchaînées, fin incluse). */
export function lignesEtapes({ base, debut, etapes, rappels, notes }: {
  base: Record<string, unknown>; debut: string; etapes: Etape[]; rappels: boolean; notes?: string;
}): Record<string, unknown>[] {
  const groupe = etapes.length > 1 ? crypto.randomUUID() : null;
  let jour = debut.slice(0, 10);
  return etapes.map((e, i) => {
    const fin = jourPlus(jour, e.duree - 1);
    const rappel = rappels && e.prises.length > 0;
    const ligne: Record<string, unknown> = {
      ...base,
      id: crypto.randomUUID(),
      ...(etapes.length > 1 || !String(base.posologie ?? '').trim() ? { posologie: libelleEtape(e) } : {}),
      date: jour, date_fin: fin,
      notes: [etapes.length > 1 ? `Phase ${i + 1}/${etapes.length}` : '', (notes ?? '').trim()].filter(Boolean).join(' — ') || null,
      ...(groupe ? { groupe_id: groupe } : {}),
      rappel_actif: rappel,
      ...(rappel ? {
        rappel_frequence_jours: e.frequence, rappel_duree_jours: e.duree, rappel_fin: fin,
        rappel_heures: e.prises.map(p => p.h),
        rappel_quantites: e.prises.some(p => p.q) ? e.prises.map(p => p.q) : null,
      } : {}),
    };
    jour = jourPlus(fin, 1);
    return ligne;
  });
}

function EditeurPrises({ prises, onChange }: { prises: Prise[]; onChange: (p: Prise[]) => void }) {
  const [h, setH] = useState('08:00');
  const [q, setQ] = useState('');
  const ajouter = () => {
    if (!h) return;
    onChange([...prises.filter(p => p.h !== h), { h, q: q.trim() }].sort((a, b) => a.h.localeCompare(b.h)));
    setQ('');
  };
  return (
    <div>
      <span className={etiquette}>Prises (heure et quantité)</span>
      <div className="flex gap-2 flex-wrap">
        <input type="time" value={h} onChange={e => setH(e.target.value)} step={300} className={cls} />
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="Quantité (ex. 1 cp, 1/2 cp, 5 ml)" className={`${cls} flex-1 min-w-[140px]`} />
        <button type="button" onClick={ajouter}
          className="px-3 py-2 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-semibold hover:bg-[#E6F4F7]">Ajouter</button>
      </div>
      {prises.length > 0 && (
        <div className="flex flex-wrap gap-1.5 mt-2">
          {prises.map(p => (
            <span key={p.h} className="inline-flex items-center gap-1 text-xs font-semibold text-[#0C5C6C] bg-[#0C5C6C]/10 rounded-full pl-2.5 pr-1 py-1">
              {p.h}{p.q ? ` · ${p.q}` : ''}
              <button type="button" onClick={() => onChange(prises.filter(x => x.h !== p.h))} aria-label={`Retirer ${p.h}`}
                className="w-4 h-4 rounded-full hover:bg-[#0C5C6C]/20 leading-none">×</button>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

/** Éditeur des étapes + total des jours et date de fin calculée. */
export function EditeurEtapes({ etapes, onChange, debut }: { etapes: Etape[]; onChange: (e: Etape[]) => void; debut: string }) {
  const maj = (i: number, p: Partial<Etape>) => onChange(etapes.map((e, j) => (j === i ? { ...e, ...p } : e)));
  const total = totalJours(etapes);
  const fin = debut && total > 0 ? jourPlus(debut.slice(0, 10), total - 1) : '';
  return (
    <div className="space-y-3">
      {etapes.map((e, i) => (
        <div key={i} className="rounded-xl border border-gray-200 bg-gray-50 p-3 space-y-3">
          <div className="flex items-center">
            <span className="flex-1 text-sm font-bold text-[#1F2A2E]">{etapes.length > 1 ? `Étape ${i + 1}` : 'Posologie'}</span>
            {etapes.length > 1 && (
              <button type="button" onClick={() => onChange(etapes.filter((_, j) => j !== i))} className="text-gray-400 hover:text-gray-600 px-1" aria-label="Retirer cette étape">×</button>
            )}
          </div>
          <div className="flex gap-4 flex-wrap text-sm text-gray-700">
            <label className="flex items-center gap-2">Pendant
              <input type="number" min={1} value={e.duree} onChange={ev => maj(i, { duree: Math.max(1, parseInt(ev.target.value, 10) || 1) })} className={`${cls} w-20`} /> jour(s)
            </label>
            <label className="flex items-center gap-2">Tous les
              <input type="number" min={1} value={e.frequence} onChange={ev => maj(i, { frequence: Math.max(1, parseInt(ev.target.value, 10) || 1) })} className={`${cls} w-20`} /> jour(s)
            </label>
          </div>
          <EditeurPrises prises={e.prises} onChange={p => maj(i, { prises: p })} />
        </div>
      ))}
      <button type="button"
        onClick={() => { const d = etapes[etapes.length - 1]; onChange([...etapes, { duree: 3, frequence: d?.frequence ?? 1, prises: (d?.prises ?? []).map(p => ({ ...p })) }]); }}
        className="px-3 py-2 rounded-xl border border-dashed border-[#0C5C6C] text-[#0C5C6C] text-sm font-semibold hover:bg-[#E6F4F7]">
        + Ajouter une étape (la posologie change ensuite)
      </button>
      <p className="text-xs font-semibold text-gray-600">
        Total : {total} jour{total > 1 ? 's' : ''}{fin ? ` · fin le ${fr(fin)}` : ' · choisissez la date de début'}
      </p>
    </div>
  );
}

/** Formulaire d'ajout d'un traitement (ou des étapes suivantes d'un traitement). */
export default function FormTraitementEtapes({ initial, onSave, onCancel, saving }: {
  initial?: { nom?: string; type?: string; description_maladie?: string; date?: string; etape?: Etape; etapes?: Etape[]; rappels?: boolean; notes?: string; posologie?: string };
  onSave: (d: { base: Record<string, string | null>; debut: string; etapes: Etape[]; rappels: boolean; notes: string }) => Promise<void>;
  onCancel: () => void; saving: boolean;
}) {
  const [nom, setNom] = useState(initial?.nom ?? '');
  const [type, setType] = useState(initial?.type ?? '');
  const [maladie, setMaladie] = useState(initial?.description_maladie ?? '');
  const [posologie, setPosologie] = useState(initial?.posologie ?? '');
  const [debut, setDebut] = useState(initial?.date ?? '');
  const [rappels, setRappels] = useState(initial?.rappels ?? true);
  const [notes, setNotes] = useState(initial?.notes ?? '');
  const [etapes, setEtapes] = useState<Etape[]>(initial?.etapes?.length ? initial.etapes : [initial?.etape ?? { duree: 7, frequence: 1, prises: [] }]);
  const [erreur, setErreur] = useState('');

  function enregistrer() {
    if (!nom.trim()) { setErreur('Indiquez le nom du traitement.'); return; }
    if (!debut) { setErreur('Indiquez la date de début.'); return; }
    if (rappels && etapes.some(e => !e.prises.length)) { setErreur('Ajoutez au moins une prise à chaque étape (ou désactivez les rappels).'); return; }
    setErreur('');
    void onSave({
      base: { nom: nom.trim(), type: type.trim() || null, description_maladie: maladie.trim() || null, ...(posologie.trim() ? { posologie: posologie.trim() } : {}) },
      debut, etapes, rappels, notes,
    });
  }

  return (
    <div className="space-y-3">
      <label className="block"><span className={etiquette}>Nom *</span><input value={nom} onChange={e => setNom(e.target.value)} className={`${cls} w-full`} /></label>
      <label className="block"><span className={etiquette}>Type</span><input value={type} onChange={e => setType(e.target.value)} className={`${cls} w-full`} /></label>
      <label className="block"><span className={etiquette}>Description de la maladie</span><input value={maladie} onChange={e => setMaladie(e.target.value)} className={`${cls} w-full`} /></label>
      <label className="block"><span className={etiquette}>Posologie (résumé, facultatif)</span><input value={posologie} onChange={e => setPosologie(e.target.value)} className={`${cls} w-full`} /></label>
      <label className="block"><span className={etiquette}>Date de début *</span><input type="date" value={debut} onChange={e => setDebut(e.target.value)} className={`${cls} w-full`} /></label>
      <label className="flex items-center gap-2 text-sm text-gray-700 cursor-pointer select-none">
        <input type="checkbox" checked={rappels} onChange={e => setRappels(e.target.checked)} className="accent-[#0C5C6C]" /> Rappel à chaque prise
      </label>
      <EditeurEtapes etapes={etapes} onChange={setEtapes} debut={debut} />
      <label className="block"><span className={etiquette}>Commentaires</span><textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className={`${cls} w-full`} /></label>
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      <div className="flex gap-2 pt-1">
        <button type="button" onClick={onCancel} className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button type="button" onClick={enregistrer} disabled={saving}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}
