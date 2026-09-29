'use client';

import { useCallback, useEffect, useState } from 'react';
import { Badge, fmtDate, downloadCsv } from './ui';
import { apiFetch } from '@/lib/api-fetch';

// Catalogue d'aliments (marques_aliments) — consultation / correction /
// suppression par l'admin, y compris les aliments ajoutés par les membres
// (kcal souvent estimées, à vérifier). Route : /api/admin/aliments.

interface Dose { poids_kg: number; grammes: number }
interface Aliment {
  id: string; marque: string; gamme: string; espece: string;
  taille_race: string | null; age_categorie: string | null; type_aliment: string | null;
  densite_kcal_100g: number | null; doses: Dose[] | null; notes: string | null;
  ajoute_par_uid: string | null; kcal_estime: boolean; formule_sterilise: boolean;
  created_at: string | null; nb_fiches: number;
}

const ESPECES_ALIM = ['chien', 'chat', 'cheval', 'lapin', 'oiseau'];
const AGES = ['junior', 'adulte', 'senior'];
const TYPES = ['croquettes', 'pâtée'];
const TAILLES = ['', 'petite', 'moyenne', 'grande', 'mini', 'medium', 'maxi', 'all'];

type Draft = Omit<Aliment, 'id' | 'created_at' | 'nb_fiches' | 'ajoute_par_uid' | 'doses' | 'densite_kcal_100g'> & {
  id?: string; densite: string; doses: { p: string; g: string }[];
};

function toDraft(a?: Aliment): Draft {
  return {
    id: a?.id, marque: a?.marque ?? '', gamme: a?.gamme ?? '', espece: a?.espece ?? 'chien',
    taille_race: a?.taille_race ?? '', age_categorie: a?.age_categorie ?? 'adulte',
    type_aliment: a?.type_aliment ?? 'croquettes', notes: a?.notes ?? '',
    kcal_estime: a?.kcal_estime ?? false, formule_sterilise: a?.formule_sterilise ?? false,
    densite: a?.densite_kcal_100g != null ? String(a.densite_kcal_100g) : '',
    doses: (a?.doses ?? []).map(d => ({ p: String(d.poids_kg), g: String(d.grammes) })),
  };
}

export default function AlimentsTab() {
  const [rows, setRows] = useState<Aliment[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [q, setQ] = useState('');
  const [espece, setEspece] = useState('');
  const [type, setType] = useState('');
  const [age, setAge] = useState('');
  const [source, setSource] = useState('');
  const [estime, setEstime] = useState(false);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let alive = true;
    const p = new URLSearchParams();
    if (q.trim()) p.set('q', q.trim());
    if (espece) p.set('espece', espece);
    if (type) p.set('type', type);
    if (age) p.set('age', age);
    if (source) p.set('source', source);
    if (estime) p.set('estime', '1');
    const t = setTimeout(() => {
      apiFetch(`/api/admin/aliments?${p}`)
        .then(r => r.json())
        .then(json => { if (!alive) return; setRows(json.aliments ?? []); setLoaded(true); })
        .catch(() => { if (alive) setLoaded(true); });
    }, 250);
    return () => { alive = false; clearTimeout(t); };
  }, [q, espece, type, age, source, estime, reload]);

  const save = useCallback(async () => {
    if (!draft) return;
    const num = (s: string) => { const v = parseFloat(s.replace(',', '.')); return Number.isFinite(v) ? v : null; };
    const body = {
      ...(draft.id ? { id: draft.id } : {}),
      marque: draft.marque, gamme: draft.gamme, espece: draft.espece,
      taille_race: draft.taille_race || null, age_categorie: draft.age_categorie,
      type_aliment: draft.type_aliment, notes: draft.notes || null,
      densite_kcal_100g: draft.densite.trim() ? num(draft.densite) : null,
      kcal_estime: draft.kcal_estime, formule_sterilise: draft.formule_sterilise,
      doses: draft.doses.map(d => ({ poids_kg: num(d.p), grammes: num(d.g) })),
    };
    setSaving(true); setError(null);
    const res = await apiFetch('/api/admin/aliments', {
      method: draft.id ? 'PATCH' : 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const json = await res.json().catch(() => ({}));
    setSaving(false);
    if (!res.ok) { setError(json.error ?? 'Enregistrement impossible.'); return; }
    setDraft(null);
    setReload(n => n + 1);
  }, [draft]);

  async function remove(a: Aliment) {
    const msg = `Supprimer « ${a.marque} — ${a.gamme} » ?` +
      (a.nb_fiches ? `\n\n${a.nb_fiches} fiche(s) d'alimentation l'utilisent : elles gardent leur marque et leurs kcal, seul le lien au catalogue est retiré.` : '');
    if (!window.confirm(msg)) return;
    const res = await apiFetch(`/api/admin/aliments?id=${encodeURIComponent(a.id)}`, { method: 'DELETE' });
    if (!res.ok) { window.alert('Suppression impossible.'); return; }
    setDraft(null);
    setReload(n => n + 1);
  }

  const inputCls = 'px-3 py-1.5 rounded-xl border border-gray-200 bg-white text-sm outline-none focus:border-[#A7C79A]';
  const field = 'w-full px-3 py-2 rounded-xl border border-gray-200 text-sm outline-none focus:border-[#A7C79A]';

  return (
    <div className="max-w-6xl mx-auto">
      <div className="flex flex-wrap gap-2 mb-3 items-center">
        <input className={`${inputCls} flex-1 min-w-[200px]`} placeholder="Marque ou gamme…" value={q} onChange={e => setQ(e.target.value)} />
        <select className={inputCls} value={espece} onChange={e => setEspece(e.target.value)}>
          <option value="">Toutes espèces</option>
          {ESPECES_ALIM.map(e => <option key={e} value={e}>{e}</option>)}
        </select>
        <select className={inputCls} value={type} onChange={e => setType(e.target.value)}>
          <option value="">Tous types</option>
          {TYPES.map(t => <option key={t} value={t}>{t}</option>)}
        </select>
        <select className={inputCls} value={age} onChange={e => setAge(e.target.value)}>
          <option value="">Tous âges</option>
          {AGES.map(a => <option key={a} value={a}>{a}</option>)}
        </select>
        <select className={inputCls} value={source} onChange={e => setSource(e.target.value)}>
          <option value="">Toutes sources</option>
          <option value="officiel">Catalogue officiel</option>
          <option value="membres">Ajoutés par les membres</option>
        </select>
        <label className="flex items-center gap-1.5 text-sm text-gray-600">
          <input type="checkbox" checked={estime} onChange={e => setEstime(e.target.checked)} /> kcal estimées
        </label>
        <span className="text-sm text-gray-400 ml-auto">{rows.length} aliments</span>
        <button onClick={() => downloadCsv('aliments.csv', [
          ['ID', 'Marque', 'Gamme', 'Espèce', 'Type', 'Âge', 'Taille', 'kcal/100g', 'kcal estimées', 'Stérilisé', 'Nb doses', 'Source', 'Fiches'],
          ...rows.map(r => [r.id, r.marque, r.gamme, r.espece, r.type_aliment, r.age_categorie, r.taille_race,
            r.densite_kcal_100g, r.kcal_estime ? 'oui' : 'non', r.formule_sterilise ? 'oui' : 'non',
            r.doses?.length ?? 0, r.ajoute_par_uid ? 'membre' : 'officiel', r.nb_fiches])])}
          className="text-sm px-3 py-1.5 rounded-xl border border-gray-200 hover:bg-gray-50">⬇ CSV</button>
        <button onClick={() => { setError(null); setDraft(toDraft()); }}
          className="text-sm px-3 py-1.5 rounded-xl bg-[#0C5C6C] text-white font-semibold">+ Nouvel aliment</button>
      </div>

      {!loaded ? (
        <div className="flex justify-center py-16"><div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" /></div>
      ) : rows.length === 0 ? (
        <p className="text-center text-sm text-gray-400 py-12">Aucun aliment ne correspond.</p>
      ) : (
        <div className="bg-white rounded-2xl border border-gray-100 overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-gray-400 border-b border-gray-100">
                <th className="px-3 py-2">Aliment</th><th className="px-3 py-2">Espèce</th><th className="px-3 py-2">Type</th>
                <th className="px-3 py-2">Âge</th><th className="px-3 py-2">kcal/100g</th><th className="px-3 py-2">Doses</th>
                <th className="px-3 py-2">Source</th><th className="px-3 py-2">Fiches</th><th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.id} className="border-b border-gray-50 hover:bg-gray-50">
                  <td className="px-3 py-2">
                    <p className="font-semibold text-[#1F2A2E]">{r.marque}</p>
                    <p className="text-xs text-gray-500">{r.gamme}{r.formule_sterilise ? ' · stérilisé/light' : ''}{r.taille_race ? ` · ${r.taille_race}` : ''}</p>
                  </td>
                  <td className="px-3 py-2">{r.espece}</td>
                  <td className="px-3 py-2">{r.type_aliment}</td>
                  <td className="px-3 py-2">{r.age_categorie}</td>
                  <td className="px-3 py-2">
                    {r.densite_kcal_100g ?? '—'}
                    {r.kcal_estime && <span className="ml-1"><Badge label="estimé" color="#c2410c" /></span>}
                  </td>
                  <td className="px-3 py-2 text-gray-500">{r.doses?.length ? `${r.doses.length} lignes` : '—'}</td>
                  <td className="px-3 py-2">
                    {r.ajoute_par_uid
                      ? <span title={`Ajouté le ${fmtDate(r.created_at)} par ${r.ajoute_par_uid}`}><Badge label="Membre" color="#0C5C6C" /></span>
                      : <Badge label="Officiel" color="#6E9E57" />}
                  </td>
                  <td className="px-3 py-2 text-gray-500">{r.nb_fiches || '—'}</td>
                  <td className="px-3 py-2 text-right whitespace-nowrap">
                    <button onClick={() => { setError(null); setDraft(toDraft(r)); }} className="text-[#0C5C6C] font-semibold mr-3">Modifier</button>
                    <button onClick={() => remove(r)} className="text-red-600">Supprimer</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {draft && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setDraft(null)}>
          <div className="bg-white rounded-2xl w-full max-w-xl max-h-[90vh] flex flex-col" onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b flex items-center">
              <h3 className="font-bold text-[#1F2A2E] flex-1">{draft.id ? 'Modifier l\'aliment' : 'Nouvel aliment (catalogue officiel)'}</h3>
              <button onClick={() => setDraft(null)} className="text-gray-400 text-2xl leading-none">×</button>
            </div>
            <div className="overflow-y-auto px-5 py-4 space-y-3 text-sm">
              <div className="grid grid-cols-2 gap-3">
                <label className="block"><span className="text-xs text-gray-500">Marque *</span>
                  <input className={field} value={draft.marque} onChange={e => setDraft({ ...draft, marque: e.target.value })} /></label>
                <label className="block"><span className="text-xs text-gray-500">Gamme / produit *</span>
                  <input className={field} value={draft.gamme} onChange={e => setDraft({ ...draft, gamme: e.target.value })} /></label>
                <label className="block"><span className="text-xs text-gray-500">Espèce</span>
                  <select className={field} value={draft.espece} onChange={e => setDraft({ ...draft, espece: e.target.value })}>
                    {ESPECES_ALIM.map(x => <option key={x} value={x}>{x}</option>)}
                  </select></label>
                <label className="block"><span className="text-xs text-gray-500">Type</span>
                  <select className={field} value={draft.type_aliment ?? ''} onChange={e => setDraft({ ...draft, type_aliment: e.target.value })}>
                    {TYPES.map(x => <option key={x} value={x}>{x}</option>)}
                  </select></label>
                <label className="block"><span className="text-xs text-gray-500">Âge</span>
                  <select className={field} value={draft.age_categorie ?? ''} onChange={e => setDraft({ ...draft, age_categorie: e.target.value })}>
                    {AGES.map(x => <option key={x} value={x}>{x}</option>)}
                  </select></label>
                <label className="block"><span className="text-xs text-gray-500">Taille de race</span>
                  <select className={field} value={draft.taille_race ?? ''} onChange={e => setDraft({ ...draft, taille_race: e.target.value })}>
                    {TAILLES.map(x => <option key={x} value={x}>{x || '—'}</option>)}
                  </select></label>
                <label className="block"><span className="text-xs text-gray-500">kcal / 100 g</span>
                  <input className={field} inputMode="decimal" value={draft.densite}
                    onChange={e => setDraft({ ...draft, densite: e.target.value })} /></label>
                <div className="flex flex-col justify-end gap-1 pb-1">
                  <label className="flex items-center gap-2"><input type="checkbox" checked={draft.kcal_estime}
                    onChange={e => setDraft({ ...draft, kcal_estime: e.target.checked })} /> kcal estimées</label>
                  <label className="flex items-center gap-2"><input type="checkbox" checked={draft.formule_sterilise}
                    onChange={e => setDraft({ ...draft, formule_sterilise: e.target.checked })} /> Formule stérilisé / light</label>
                </div>
              </div>
              <div>
                <p className="text-xs text-gray-500 mb-1">Tableau de rationnement (poids → grammes / jour)</p>
                {draft.doses.map((d, i) => (
                  <div key={i} className="flex gap-2 mb-2 items-center">
                    <input className={field} inputMode="decimal" placeholder="Poids (kg)" value={d.p}
                      onChange={e => setDraft({ ...draft, doses: draft.doses.map((x, j) => j === i ? { ...x, p: e.target.value } : x) })} />
                    <input className={field} inputMode="decimal" placeholder="g / jour" value={d.g}
                      onChange={e => setDraft({ ...draft, doses: draft.doses.map((x, j) => j === i ? { ...x, g: e.target.value } : x) })} />
                    <button onClick={() => setDraft({ ...draft, doses: draft.doses.filter((_, j) => j !== i) })} className="text-gray-400 px-1">✕</button>
                  </div>
                ))}
                <button onClick={() => setDraft({ ...draft, doses: [...draft.doses, { p: '', g: '' }] })}
                  className="text-[#0C5C6C] font-semibold">+ Ajouter une ligne</button>
              </div>
              <label className="block"><span className="text-xs text-gray-500">Notes</span>
                <textarea className={field} rows={2} value={draft.notes ?? ''} onChange={e => setDraft({ ...draft, notes: e.target.value })} /></label>
              {draft.id && (
                <p className="text-xs text-gray-400">Les fiches d&apos;alimentation déjà enregistrées gardent leurs valeurs ; la correction s&apos;applique aux prochaines sélections.</p>
              )}
              {error && <p className="text-red-600">{error}</p>}
            </div>
            <div className="px-5 py-4 border-t flex gap-2">
              {draft.id && (
                <button onClick={() => { const a = rows.find(r => r.id === draft.id); if (a) remove(a); }}
                  className="px-4 py-2 rounded-xl text-red-600 border border-red-200">Supprimer</button>
              )}
              <button onClick={() => setDraft(null)} className="ml-auto px-4 py-2 rounded-xl border border-gray-200 text-gray-600">Annuler</button>
              <button onClick={save} disabled={saving} className="px-4 py-2 rounded-xl bg-[#0C5C6C] text-white font-semibold disabled:opacity-50">
                {saving ? 'Enregistrement…' : 'Enregistrer'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
