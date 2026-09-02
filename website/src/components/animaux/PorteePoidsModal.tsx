'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface AnimalLite {
  id: string;
  nom?: string | null;
  sexe?: string | null;
  date_naissance?: string | null;
}

interface Pesee { id: string; animal_id: string; date: string | null; valeur: string | number | null; }

const SERIES_COLORS = [
  '#5F9EAA', '#6E9E57', '#E57373', '#FFB74D',
  '#9575CD', '#4DB6AC', '#E91E63', '#795548',
];

// ── Helpers ───────────────────────────────────────────────────────────────────

function poidsLabel(kg: number): string {
  if (kg < 1) return `${Math.round(kg * 1000)} g`;
  return `${kg.toFixed(1).replace('.', ',')} kg`;
}
function poidsAxis(kg: number): string {
  if (kg < 1) return `${Math.round(kg * 1000)}g`;
  return `${kg.toFixed(1)}k`;
}
function fmtDate(iso?: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString('fr-FR');
}
function fmtInput(v: number): string {
  if (Number.isInteger(v)) return String(v);
  return v.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

// ── Graphe multi-séries ───────────────────────────────────────────────────────

function ageLabel(days: number): string {
  if (days < 14) return `${Math.round(days)} j`;
  if (days < 90) return `${Math.round(days / 7)} sem`;
  return `${Math.round(days / 30)} mois`;
}

function MultiWeightChart({ series, colors, names }: {
  series: Record<string, { x: number; y: number }[]>;
  colors: Record<string, string>;
  names: Record<string, string>;
}) {
  const W = 360, H = 200, L = 40, T = 18, R = 12, B = 26;
  const w = W - L - R, h = H - T - B;
  const [sel, setSel] = useState<{ id: string; i: number } | null>(null);

  const all = Object.values(series).flat();
  if (all.length === 0) return null;
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const p of all) {
    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
  }
  const rangeX = maxX - minX < 1 ? 1 : maxX - minX;
  const rangeY = maxY - minY < 0.001 ? 1 : (maxY - minY) * 1.25;
  const baseY = minY - rangeY * 0.1;
  const cx = (x: number) => L + (rangeX < 1 ? w / 2 : ((x - minX) / rangeX) * w);
  const cy = (y: number) => T + h - ((y - baseY) / rangeY) * h;

  const selPt = sel ? series[sel.id]?.[sel.i] : undefined;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ maxHeight: 200 }}>
      {[0, 1, 2, 3, 4].map(g => {
        const yVal = baseY + (g * rangeY) / 4;
        const yPx = T + h - (g * h) / 4;
        return (
          <g key={g}>
            <line x1={L} y1={yPx} x2={W - R} y2={yPx} stroke="#F0F0F0" />
            <text x={L - 4} y={yPx + 3} textAnchor="end" fontSize="8" fill="#BBB">{poidsAxis(yVal < 0 ? 0 : yVal)}</text>
          </g>
        );
      })}
      {[0, 0.25, 0.5, 0.75, 1].map(f => {
        const xDays = minX + f * rangeX;
        const xPx = L + f * w;
        const lbl = xDays < 14 ? `${Math.round(xDays)}j`
          : xDays < 90 ? `${Math.round(xDays / 7)}sem`
          : `${Math.round(xDays / 30)}m`;
        return <text key={f} x={xPx} y={T + h + 14} textAnchor="middle" fontSize="8" fill="#BBB">{lbl}</text>;
      })}
      {Object.entries(series).map(([id, pts]) => {
        const c = colors[id] ?? SERIES_COLORS[0];
        const d = pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${cx(p.x)},${cy(p.y)}`).join(' ');
        return (
          <g key={id}>
            {pts.length >= 2 && <path d={d} fill="none" stroke={c} strokeWidth={2} strokeLinecap="round" />}
            {pts.map((p, i) => {
              const isSel = sel?.id === id && sel.i === i;
              return (
                <g key={i} style={{ cursor: 'pointer' }}
                  onClick={() => setSel(isSel ? null : { id, i })}>
                  <circle cx={cx(p.x)} cy={cy(p.y)} r={9} fill="transparent" />
                  <circle cx={cx(p.x)} cy={cy(p.y)} r={isSel ? 5 : 3.5} fill={c} />
                  <circle cx={cx(p.x)} cy={cy(p.y)} r={isSel ? 2.6 : 1.8} fill="white" />
                </g>
              );
            })}
          </g>
        );
      })}
      {sel && selPt && (() => {
        const c = colors[sel.id] ?? SERIES_COLORS[0];
        const px = cx(selPt.x), py = cy(selPt.y);
        const l1 = names[sel.id] ?? 'Bébé';
        const l2 = poidsLabel(selPt.y);
        const l3 = ageLabel(selPt.x);
        const bw = Math.max(l1.length, l2.length, l3.length) * 5.4 + 14;
        const bh = 40;
        let bx = px - bw / 2;
        let by = py - bh - 8;
        if (bx < L) bx = L;
        if (bx + bw > W - R) bx = W - R - bw;
        if (by < 0) by = py + 8;
        return (
          <g>
            <rect x={bx} y={by} width={bw} height={bh} rx={6} fill={c} />
            <text x={bx + 7} y={by + 13} fontSize="9" fontWeight="700" fill="white">{l1}</text>
            <text x={bx + 7} y={by + 25} fontSize="10" fontWeight="700" fill="white">{l2}</text>
            <text x={bx + 7} y={by + 35} fontSize="8" fill="rgba(255,255,255,0.8)">{l3}</text>
          </g>
        );
      })()}
    </svg>
  );
}

// ── Panneau pesées d'un bébé ──────────────────────────────────────────────────

function BebePanel({ animal, pesees, canWrite, onChanged }: {
  animal: AnimalLite;
  pesees: Pesee[];
  canWrite: boolean;
  onChanged: () => void;
}) {
  const sorted = [...pesees].sort((a, b) => String(b.date ?? '').localeCompare(String(a.date ?? '')));
  const lastKg = sorted.length ? parseFloat(String(sorted[0].valeur ?? '0')) : null;

  const [unite, setUnite] = useState<'g' | 'kg'>(lastKg != null && lastKg >= 1 ? 'kg' : 'g');
  const [value, setValue] = useState('');
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [busy, setBusy] = useState(false);

  function switchUnite(u: 'g' | 'kg') {
    if (u === unite) return;
    const v = parseFloat(value.replace(',', '.'));
    setUnite(u);
    if (Number.isFinite(v)) setValue(fmtInput(u === 'g' ? v * 1000 : v / 1000));
  }

  async function add() {
    const v = parseFloat(value.replace(',', '.'));
    if (!Number.isFinite(v) || !date) return;
    const kg = unite === 'g' ? v / 1000 : v;
    setBusy(true);
    await supabase.from('poids').insert({
      id: crypto.randomUUID(), animal_id: animal.id,
      valeur: kg, date: new Date(date).toISOString(),
    });
    setValue('');
    setBusy(false);
    onChanged();
  }

  async function del(id: string) {
    await supabase.from('poids').delete().eq('id', id);
    onChanged();
  }

  const iCls = 'border border-gray-200 rounded-lg px-2.5 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';

  return (
    <div className="bg-gray-50 rounded-xl p-3 mt-1.5">
      {canWrite && (
        <>
          <div className="flex flex-wrap items-end gap-2">
            <div>
              <label className="block text-[10px] font-semibold text-gray-400 uppercase mb-0.5">Date</label>
              <input type="date" value={date} onChange={e => setDate(e.target.value)} className={iCls} />
            </div>
            <div>
              <label className="block text-[10px] font-semibold text-gray-400 uppercase mb-0.5">Poids</label>
              <div className="flex">
                <input type="number" step="any" inputMode="decimal" value={value}
                  onChange={e => setValue(e.target.value)}
                  onKeyDown={e => { if (e.key === 'Enter') add(); }}
                  className={`${iCls} w-20 rounded-r-none`} />
                <div className="flex rounded-r-lg border border-l-0 border-gray-200 overflow-hidden">
                  {(['g', 'kg'] as const).map(u => (
                    <button key={u} type="button" onClick={() => switchUnite(u)}
                      className={`px-2 text-xs font-bold ${unite === u ? 'bg-[#6E9E57] text-white' : 'bg-white text-gray-400'}`}>
                      {u}
                    </button>
                  ))}
                </div>
              </div>
            </div>
            <button type="button" onClick={add} disabled={busy || !value}
              className="h-[34px] px-3 rounded-lg bg-[#0C5C6C] text-white text-sm font-semibold disabled:opacity-50">
              {busy ? '…' : '+ Ajouter'}
            </button>
          </div>
          <p className="text-[10px] text-gray-400 mt-1">Ajoutez plusieurs pesées d&apos;affilée — le panneau reste ouvert.</p>
        </>
      )}
      {!canWrite && sorted.length === 0 && (
        <p className="text-[11px] text-gray-400">Aucune pesée.</p>
      )}

      {sorted.length > 0 && (
        <div className="mt-2 divide-y divide-gray-100 border-t border-gray-100">
          {sorted.map(p => (
            <div key={p.id} className="flex items-center gap-2 py-1.5">
              <span className="text-xs text-gray-500 flex-1">{fmtDate(p.date)}</span>
              <span className="text-sm font-bold text-[#1F2A2E]">
                {poidsLabel(parseFloat(String(p.valeur ?? '0')) || 0)}
              </span>
              {canWrite && (
                <button onClick={() => del(p.id)} className="text-red-400 hover:text-red-600 text-sm px-1">×</button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Modal principale ──────────────────────────────────────────────────────────

export default function PorteePoidsModal({ animals, dateNaissance, canWrite = true, onClose }: {
  animals: AnimalLite[];
  dateNaissance?: string | null;
  canWrite?: boolean;
  onClose: () => void;
}) {
  const [pesees, setPesees] = useState<Pesee[]>([]);
  const [loading, setLoading] = useState(true);
  const [openId, setOpenId] = useState<string | null>(null);

  const ids = useMemo(() => animals.map(a => a.id), [animals]);

  const load = useCallback(async () => {
    if (ids.length === 0) { setLoading(false); return; }
    const { data } = await supabase.from('poids').select('id, animal_id, date, valeur')
      .in('animal_id', ids).order('date', { ascending: true });
    setPesees((data ?? []) as Pesee[]);
    setLoading(false);
  }, [ids]);

  useEffect(() => { load(); }, [load]);

  const byAnimal = useMemo(() => {
    const m: Record<string, Pesee[]> = {};
    for (const p of pesees) (m[p.animal_id] ??= []).push(p);
    return m;
  }, [pesees]);

  const colors = useMemo(() => {
    const m: Record<string, string> = {};
    animals.forEach((a, i) => { m[a.id] = SERIES_COLORS[i % SERIES_COLORS.length]; });
    return m;
  }, [animals]);

  const names = useMemo(() => {
    const m: Record<string, string> = {};
    animals.forEach((a, i) => { m[a.id] = a.nom?.trim() || `Bébé ${i + 1}`; });
    return m;
  }, [animals]);

  const series = useMemo(() => {
    const s: Record<string, { x: number; y: number }[]> = {};
    for (const a of animals) {
      const docs = (byAnimal[a.id] ?? []).filter(d => d.date && d.valeur != null);
      if (docs.length === 0) continue;
      // docs[0].date est garanti non-null par le filtre ci-dessus.
      const birth = new Date(dateNaissance ?? a.date_naissance ?? (docs[0].date as string));
      const pts = docs.map(d => ({
        x: (new Date(d.date as string).getTime() - birth.getTime()) / 86400000,
        y: parseFloat(String(d.valeur)) || 0,
      })).sort((p, q) => p.x - q.x);
      if (pts.length) s[a.id] = pts;
    }
    return s;
  }, [animals, byAnimal, dateNaissance]);

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[92vh] overflow-y-auto">
        <div className="p-5">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-xl bg-[#0C5C6C12] flex items-center justify-center text-xl">📈</div>
            <div className="flex-1">
              <p className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Courbes de poids — Portée</p>
              <p className="text-xs text-[#6E9E57]">
                {canWrite ? 'Touchez un bébé pour saisir / corriger ses pesées' : 'Touchez un bébé pour voir ses pesées'}
              </p>
            </div>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
          </div>

          {loading ? (
            <div className="flex justify-center py-10">
              <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : (
            <>
              <div className="border border-gray-100 rounded-xl p-2 mb-4 bg-white">
                {Object.keys(series).length > 0 ? (
                  <MultiWeightChart series={series} colors={colors} names={names} />
                ) : (
                  <p className="text-center text-xs text-gray-400 py-8">
                    Aucune pesée pour l&apos;instant — touchez un bébé ci-dessous pour commencer.
                  </p>
                )}
              </div>

              <div className="divide-y divide-gray-100">
                {animals.map((a, i) => {
                  const docs = byAnimal[a.id] ?? [];
                  const nb = docs.length;
                  const last = nb ? [...docs].sort((x, y) => String(y.date ?? '').localeCompare(String(x.date ?? '')))[0] : null;
                  const isOpen = openId === a.id;
                  return (
                    <div key={a.id} className="py-1">
                      <button
                        onClick={() => setOpenId(isOpen ? null : a.id)}
                        className="w-full flex items-center gap-2.5 py-2 text-left">
                        <span className="w-3.5 h-3.5 rounded-[4px] shrink-0"
                          style={{ background: nb > 0 ? colors[a.id] : 'transparent', border: `1.5px solid ${colors[a.id] ?? '#ccc'}` }} />
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold text-[#1F2A2E] truncate">
                            {a.nom?.trim() || `Bébé ${i + 1}`}{a.sexe ? ` · ${a.sexe}` : ''}
                          </p>
                          <p className={`text-[11px] ${nb === 0 ? 'text-[#E29B3B]' : 'text-gray-400'}`}>
                            {nb === 0 ? 'Aucune pesée' : `${nb} pesée${nb > 1 ? 's' : ''}`}
                          </p>
                        </div>
                        {last && (
                          <span className="text-xs font-bold px-2 py-0.5 rounded-lg shrink-0"
                            style={{ background: `${colors[a.id]}1F`, color: colors[a.id] }}>
                            {poidsLabel(parseFloat(String(last.valeur ?? '0')) || 0)}
                          </span>
                        )}
                        <span className="text-gray-300 text-sm shrink-0">{isOpen ? '▾' : (canWrite ? '＋' : '›')}</span>
                      </button>
                      {isOpen && (
                        <BebePanel animal={a} pesees={docs} canWrite={canWrite} onChanged={load} />
                      )}
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
