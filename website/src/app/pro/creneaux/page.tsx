'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import CreneauxWeekGrid from '@/components/pro/CreneauxWeekGrid';

const TEAL   = '#0C5C6C';
const GREEN  = '#6E9E57';
const ORANGE = '#FF9800';

const JOURS_FULL = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
const MOIS  = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];

function getMonday(d: Date): Date {
  const day = d.getDay();
  const mon = new Date(d);
  mon.setDate(d.getDate() + (day === 0 ? -6 : 1 - day));
  mon.setHours(0, 0, 0, 0);
  return mon;
}
function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function timeToMins(t: string): number {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
}
function minsToTime(m: number): string {
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}
function snapTo15(t: string): string {
  return minsToTime(Math.floor(timeToMins(t) / 15) * 15);
}

type SlotStatus = 'disponible' | 'bloque';
type TypePrestation = 'individuel' | 'collectif' | null;
interface SlotRange { start: string; end: string; statut: SlotStatus; type?: TypePrestation; domicile?: boolean; }

function groupRanges(slotsForDate: { time: string; statut: SlotStatus; type?: TypePrestation; domicile?: boolean }[]): SlotRange[] {
  const sorted = [...slotsForDate].sort((a, b) => a.time.localeCompare(b.time));
  if (!sorted.length) return [];
  const ranges: SlotRange[] = [];
  let rStart = sorted[0].time;
  let prevMins = timeToMins(sorted[0].time);
  let curStatut = sorted[0].statut;
  let curType = sorted[0].type ?? null;
  let curDomicile = sorted[0].domicile ?? false;
  for (let i = 1; i < sorted.length; i++) {
    const curMins = timeToMins(sorted[i].time);
    const t = sorted[i].type ?? null;
    const d = sorted[i].domicile ?? false;
    if (sorted[i].statut === curStatut && t === curType && d === curDomicile && curMins === prevMins + 15) {
      prevMins = curMins;
    } else {
      ranges.push({ start: rStart, end: minsToTime(prevMins + 15), statut: curStatut, type: curType, domicile: curDomicile });
      rStart = sorted[i].time; prevMins = curMins; curStatut = sorted[i].statut; curType = t; curDomicile = d;
    }
  }
  ranges.push({ start: rStart, end: minsToTime(prevMins + 15), statut: curStatut, type: curType, domicile: curDomicile });
  return ranges;
}

export default function ProCreneauxPage() {
  const { user, loading } = useAuth();
  const router            = useRouter();
  const { id: activeProfileId, loaded: profileLoaded } = useActiveProfileState();

  const [weekStart, setWeekStart]           = useState(() => getMonday(new Date()));
  const [slots, setSlots]                   = useState<Record<string, SlotStatus>>({});
  const [loadingSlots, setLoadingSlots]     = useState(false);
  const [saving, setSaving]                 = useState(false);
  const [replicating, setReplicating]       = useState(false);
  const [showRepModal, setShowRepModal]     = useState(false);
  const [repChoice, setRepChoice]           = useState<'4sem' | 'annee' | 'perso'>('4sem');
  const [repEndDate, setRepEndDate]         = useState('');
  const [showAddModal, setShowAddModal]     = useState(false);
  const [addDate, setAddDate]               = useState(() => toDateStr(new Date()));
  const [addMode, setAddMode]               = useState<SlotStatus>('disponible');
  const [addStart, setAddStart]             = useState('09:00');
  const [addEnd, setAddEnd]                 = useState('10:00');
  const [addType, setAddType]               = useState<TypePrestation>(null);
  const [addDomicile, setAddDomicile]       = useState(false);
  const [addPrestationId, setAddPrestationId] = useState<string | null>(null);
  const [coursCollectifs, setCoursCollectifs] = useState<{ id: string; nom: string }[]>([]);
  const [slotTypes, setSlotTypes]           = useState<Record<string, TypePrestation>>({});
  const [slotDomicile, setSlotDomicile]     = useState<Record<string, boolean>>({});
  const [catPro, setCatPro]                 = useState('');
  const [rdvs, setRdvs]                     = useState<{ date_heure: string; duree_minutes: number | null; motif: string | null }[]>([]);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!activeProfileId) return;
    supabase.from('user_profiles').select('profile_type, cat_pro').eq('id', activeProfileId).single()
      .then(({ data }) => setCatPro((data?.profile_type ?? data?.cat_pro ?? '') as string));
  }, [activeProfileId]);

  useEffect(() => {
    if (!user || catPro !== 'education') return;
    let q = supabase.from('prestations_education').select('id, nom')
      .eq('pro_uid', user.uid).eq('type', 'collectif').eq('actif', true);
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId);
    q.then(({ data }) => setCoursCollectifs((data ?? []) as { id: string; nom: string }[]));
  }, [user, activeProfileId, catPro]);

  const loadSlots = useCallback(async () => {
    if (!user || !profileLoaded || !activeProfileId) return;
    setLoadingSlots(true);
    const end = new Date(weekStart);
    end.setDate(weekStart.getDate() + 6);
    try {
      const { data } = await supabase
        .from('creneaux_pro')
        .select('date, heure_debut, statut, type_prestation, domicile_ok')
        .eq('pro_uid', user.uid)
        .eq('pro_profile_id', activeProfileId)
        .in('statut', ['disponible', 'bloque'])
        .gte('date', toDateStr(weekStart))
        .lte('date', toDateStr(end));
      const map: Record<string, SlotStatus> = {};
      const typeMap: Record<string, TypePrestation> = {};
      const domicileMap: Record<string, boolean> = {};
      for (const r of (data ?? []) as { date: string; heure_debut: string; statut: SlotStatus; type_prestation: TypePrestation; domicile_ok: boolean }[]) {
        const hhmm = r.heure_debut.substring(0, 5);
        const key = `${r.date}_${hhmm}`;
        map[key] = r.statut;
        if (r.type_prestation) typeMap[key] = r.type_prestation;
        if (r.domicile_ok) domicileMap[key] = true;
      }
      setSlots(map);
      setSlotTypes(typeMap);
      setSlotDomicile(domicileMap);

      const { data: rdvRows } = await supabase.from('rdv')
        .select('date_heure, duree_minutes, motif')
        .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId)
        .in('statut', ['confirme', 'demande'])
        .gte('date_heure', weekStart.toISOString())
        .lte('date_heure', new Date(end.getFullYear(), end.getMonth(), end.getDate(), 23, 59).toISOString());
      setRdvs((rdvRows ?? []) as typeof rdvs);
    } catch { /* ignore */ }
    setLoadingSlots(false);
  }, [user, profileLoaded, activeProfileId, weekStart]);

  useEffect(() => { loadSlots(); }, [loadSlots]);

  const days = Array.from({ length: 7 }, (_, i) => { const d = new Date(weekStart); d.setDate(weekStart.getDate() + i); return d; });

  // Plages + RDV groupés par jour pour la grille semaine (CreneauxWeekGrid).
  const rangesByDay: Record<string, ReturnType<typeof groupRanges>> = {};
  const rdvsByDay: Record<string, typeof rdvs> = {};
  for (const day of days) {
    const key = toDateStr(day);
    const slotsForThatDay = Object.entries(slots)
      .filter(([k]) => k.startsWith(`${key}_`))
      .map(([k, statut]) => ({ time: k.slice(key.length + 1), statut, type: slotTypes[k] ?? null, domicile: slotDomicile[k] ?? false }));
    rangesByDay[key] = groupRanges(slotsForThatDay);
    rdvsByDay[key] = rdvs.filter(r => toDateStr(new Date(r.date_heure)) === key);
  }

  // Recalcule le résumé "Horaires" (page profil) à partir des créneaux
  // disponibles de la semaine affichée — l'utilisateur ne saisit plus les
  // horaires à la main, ils sont dérivés de ce qui est réellement réservable.
  async function syncHorairesSummary(mergedSlots: Record<string, SlotStatus>) {
    if (!user) return;
    try {
      const horaires: Record<string, string> = {};
      for (const day of days) {
        const ds = toDateStr(day);
        const dispoSlots = Object.entries(mergedSlots)
          .filter(([k, v]) => k.startsWith(`${ds}_`) && v === 'disponible')
          .map(([k]) => ({ time: k.slice(ds.length + 1), statut: 'disponible' as SlotStatus }));
        const ranges = groupRanges(dispoSlots);
        const label = JOURS_FULL[day.getDay() === 0 ? 6 : day.getDay() - 1];
        horaires[label] = ranges.map(r => `${r.start}-${r.end}`).join(' ');
      }
      await supabase.from('user_profiles').update({ horaires }).eq('uid', user.uid).eq('id', activeProfileId);
    } catch { /* ignore — résumé informatif, pas bloquant */ }
  }

  async function applyRange(date: string, start: string, end: string, statut: SlotStatus, type: TypePrestation = null, domicile = false, prestationId: string | null = null) {
    if (!user || saving) return;
    setSaving(true);
    let cur = timeToMins(start);
    const endM = timeToMins(end);
    const newSlots: Record<string, SlotStatus> = {};
    const newTypes: Record<string, TypePrestation> = {};
    const newDomicile: Record<string, boolean> = {};
    const rows: Record<string, unknown>[] = [];
    while (cur < endM) {
      const hhmm = minsToTime(cur);
      const fin  = minsToTime(cur + 15);
      const key = `${date}_${hhmm}`;
      newSlots[key] = statut;
      if (type) newTypes[key] = type;
      newDomicile[key] = domicile;
      rows.push({ pro_uid: user.uid, pro_profile_id: activeProfileId, date,
        heure_debut: `${hhmm}:00`, heure_fin: `${fin}:00`, statut, type_prestation: type, domicile_ok: domicile,
        prestation_id: prestationId });
      cur += 15;
    }
    const merged = { ...slots, ...newSlots };
    setSlots(merged);
    setSlotTypes(prev => ({ ...prev, ...newTypes }));
    setSlotDomicile(prev => ({ ...prev, ...newDomicile }));
    try {
      await supabase.from('creneaux_pro').upsert(rows, { onConflict: 'pro_uid,pro_profile_id,date,heure_debut' });
      await syncHorairesSummary(merged);
    } catch {
      setSlots(s => { const n = { ...s }; Object.keys(newSlots).forEach(k => delete n[k]); return n; });
    }
    setSaving(false);
  }

  async function deleteRange(date: string, r: SlotRange) {
    if (!user) return;
    let cur = timeToMins(r.start);
    const endM = timeToMins(r.end);
    const hdList: string[] = [];
    const keyList: string[] = [];
    while (cur < endM) {
      const hhmm = minsToTime(cur);
      hdList.push(`${hhmm}:00`);
      keyList.push(`${date}_${hhmm}`);
      cur += 15;
    }
    const merged = { ...slots };
    keyList.forEach(k => delete merged[k]);
    setSlots(merged);
    setSlotDomicile(prev => { const n = { ...prev }; keyList.forEach(k => delete n[k]); return n; });
    try {
      await supabase.from('creneaux_pro').delete()
        .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId)
        .eq('date', date).in('heure_debut', hdList);
      await syncHorairesSummary(merged);
    } catch { loadSlots(); }
  }

  async function handleReplicate() {
    if (!user) return;
    const weekSlots = Object.entries(slots).filter(([, v]) => v === 'disponible');
    if (!weekSlots.length) return;
    let endDate: Date;
    if (repChoice === 'annee') {
      endDate = new Date(weekStart.getFullYear(), 11, 31);
    } else if (repChoice === 'perso' && repEndDate) {
      endDate = new Date(repEndDate);
    } else {
      endDate = new Date(weekStart); endDate.setDate(weekStart.getDate() + 28);
    }
    setReplicating(true); setShowRepModal(false);
    try {
      const rows: Record<string, unknown>[] = [];
      let target = new Date(weekStart);
      target.setDate(target.getDate() + 7);
      while (target <= endDate) {
        for (const [key] of weekSlots) {
          const underIdx = key.lastIndexOf('_');
          const datePart = key.slice(0, underIdx);
          const hhmm     = key.slice(underIdx + 1);
          const orig     = new Date(datePart);
          const dayDiff  = Math.round((orig.getTime() - weekStart.getTime()) / 86400000);
          const tDay     = new Date(target);
          tDay.setDate(target.getDate() + dayDiff);
          const fin = minsToTime(timeToMins(hhmm) + 15);
          rows.push({ pro_uid: user.uid, pro_profile_id: activeProfileId, date: toDateStr(tDay),
            heure_debut: `${hhmm}:00`, heure_fin: `${fin}:00`, statut: 'disponible' });
        }
        target = new Date(target); target.setDate(target.getDate() + 7);
      }
      const seen = new Set<string>();
      const deduped = rows.filter(r => {
        const k = `${r.date}_${r.heure_debut}`;
        return seen.has(k as string) ? false : (seen.add(k as string), true);
      });
      if (deduped.length) await supabase.from('creneaux_pro').upsert(deduped, { onConflict: 'pro_uid,pro_profile_id,date,heure_debut' });
    } catch { /* ignore */ }
    setReplicating(false);
  }

  const dispCount = Object.values(slots).filter(v => v === 'disponible').length;

  if (loading) return <div className="flex items-center justify-center min-h-screen text-gray-400">Chargement…</div>;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">

      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => router.back()}
          className="p-2 rounded-lg hover:bg-gray-100 transition-colors" style={{ color: TEAL }}>
          ←
        </button>
        <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif', color: TEAL }}>
          Mes créneaux
        </h1>
      </div>

      {/* Navigation semaine */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
        <div className="flex items-center justify-between mb-3">
          <button onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() - 7); return n; }); }}
            className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-lg font-bold" style={{ color: TEAL }}>‹</button>
          <span className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            Semaine du {weekStart.getDate()} {MOIS[weekStart.getMonth()]}
          </span>
          <button onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() + 7); return n; }); }}
            className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-lg font-bold" style={{ color: TEAL }}>›</button>
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-2 mb-2">
        <button onClick={() => { setAddDate(toDateStr(days[0] && days[0] > new Date() ? days[0] : new Date())); setShowAddModal(true); }}
          className="flex-1 py-3 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-2"
          style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
          + Nouvelle plage
        </button>
        <button onClick={() => setShowRepModal(true)} disabled={dispCount === 0 || replicating}
          className="px-4 py-3 rounded-xl text-sm font-semibold border-2 transition-colors disabled:opacity-40 flex items-center gap-1"
          style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
          🔁 Répliquer
        </button>
      </div>
      <p className="text-xs text-gray-400 mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
        Glissez sur une plage horaire libre pour créer un créneau.
      </p>

      {/* Grille semaine */}
      {loadingSlots ? (
        <div className="flex justify-center py-12 text-sm text-gray-400">Chargement…</div>
      ) : (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-3">
          <CreneauxWeekGrid
            days={days}
            rangesByDay={rangesByDay}
            rdvsByDay={rdvsByDay}
            onCreateRange={(day, start, end) => { setAddDate(toDateStr(day)); setAddStart(start); setAddEnd(end); setShowAddModal(true); }}
            onTapRange={(day, r) => deleteRange(toDateStr(day), r as SlotRange)}
          />
        </div>
      )}

      {/* Modal — Nouvelle plage */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4"
          onClick={() => setShowAddModal(false)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-sm p-6 space-y-5"
            onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-base text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Nouvelle plage
            </h3>

            {/* Mode Disponible / Bloqué */}
            <div className="flex gap-2">
              {(['disponible', 'bloque'] as const).map(m => {
                const col = m === 'disponible' ? GREEN : ORANGE;
                return (
                  <button key={m} onClick={() => setAddMode(m)}
                    className="flex-1 py-2.5 rounded-xl text-sm font-semibold border-2 transition-all"
                    style={{
                      background: addMode === m ? `${col}18` : 'white',
                      borderColor: addMode === m ? col : '#e5e7eb',
                      color: addMode === m ? (m === 'disponible' ? '#4A7A32' : '#E65100') : '#6B7280',
                      fontFamily: 'Galey, sans-serif',
                    }}>
                    {m === 'disponible' ? '✓ Disponible' : '🚫 Bloqué'}
                  </button>
                );
              })}
            </div>

            {/* Sélecteurs d'heure */}
            <div className="flex items-center gap-3">
              <div className="flex-1">
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1.5">De</label>
                <input type="time" step="900" value={addStart}
                  onChange={e => setAddStart(snapTo15(e.target.value || addStart))}
                  className="w-full border-2 border-gray-200 rounded-xl px-3 py-3 text-xl font-bold text-center focus:outline-none focus:border-[#0C5C6C] text-[#1E2025]"
                  style={{ fontFamily: 'Galey, sans-serif' }} />
              </div>
              <span className="text-2xl text-gray-400 mt-6">→</span>
              <div className="flex-1">
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1.5">À</label>
                <input type="time" step="900" value={addEnd}
                  onChange={e => setAddEnd(snapTo15(e.target.value || addEnd))}
                  className="w-full border-2 border-gray-200 rounded-xl px-3 py-3 text-xl font-bold text-center focus:outline-none focus:border-[#0C5C6C] text-[#1E2025]"
                  style={{ fontFamily: 'Galey, sans-serif' }} />
              </div>
            </div>

            {timeToMins(addEnd) <= timeToMins(addStart) && (
              <p className="text-xs text-red-500">L&apos;heure de fin doit être après l&apos;heure de début.</p>
            )}

            {/* Type de prestation (éducateur/comportementaliste uniquement) */}
            {catPro === 'education' && addMode === 'disponible' && (
              <div>
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1.5">
                  Réservé à
                </label>
                <div className="flex gap-2">
                  {([['individuel', '🎓 Individuel'], ['collectif', '👥 Collectif'], [null, 'Les deux']] as const).map(([v, label]) => (
                    <button key={label} onClick={() => setAddType(v)}
                      className="flex-1 py-2 rounded-xl text-xs font-semibold border-2 transition-all"
                      style={{
                        background: addType === v ? '#7B5EA718' : 'white',
                        borderColor: addType === v ? '#7B5EA7' : '#e5e7eb',
                        color: addType === v ? '#7B5EA7' : '#6B7280',
                        fontFamily: 'Galey, sans-serif',
                      }}>
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {catPro === 'education' && addMode === 'disponible' && addType === 'collectif' && coursCollectifs.length > 0 && (
              <div>
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1.5">
                  Cours associé (optionnel)
                </label>
                <select value={addPrestationId ?? ''} onChange={e => setAddPrestationId(e.target.value || null)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm">
                  <option value="">Aucun</option>
                  {coursCollectifs.map(c => <option key={c.id} value={c.id}>{c.nom}</option>)}
                </select>
              </div>
            )}

            {catPro === 'education' && addMode === 'disponible' && (
              <div className="flex items-center justify-between gap-4">
                <span className="text-xs font-semibold text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
                  Disponible à domicile
                </span>
                <button type="button" onClick={() => setAddDomicile(v => !v)}
                  className="relative w-11 h-6 rounded-full transition-colors flex-shrink-0"
                  style={{ backgroundColor: addDomicile ? '#7B5EA7' : '#D1D5DB' }}>
                  <span className="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full transition-transform"
                    style={{ transform: addDomicile ? 'translateX(20px)' : 'translateX(0)' }} />
                </button>
              </div>
            )}

            <div className="flex gap-3">
              <button onClick={() => setShowAddModal(false)}
                className="flex-1 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-500">
                Annuler
              </button>
              <button
                onClick={async () => {
                  if (timeToMins(addEnd) <= timeToMins(addStart)) return;
                  setShowAddModal(false);
                  await applyRange(addDate, addStart, addEnd, addMode, addMode === 'disponible' ? addType : null, addMode === 'disponible' && addDomicile,
                    addMode === 'disponible' && addType === 'collectif' ? addPrestationId : null);
                  await loadSlots();
                  setAddType(null);
                  setAddDomicile(false);
                  setAddPrestationId(null);
                }}
                disabled={saving || timeToMins(addEnd) <= timeToMins(addStart)}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50"
                style={{ background: addMode === 'disponible' ? GREEN : ORANGE, fontFamily: 'Galey, sans-serif' }}>
                {saving ? '…' : 'Appliquer'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal répliquer */}
      {showRepModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl">
            <h3 className="font-bold text-base mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Répliquer les créneaux</h3>
            <p className="text-sm text-gray-500 mb-4">{dispCount} créneau(x) disponibles à répliquer.</p>
            <div className="flex flex-col gap-2.5 mb-5">
              {([['4sem', '4 semaines suivantes'], ['annee', "Jusqu'à la fin de l'année"], ['perso', 'Date personnalisée…']] as const).map(([v, l]) => (
                <label key={v} className="flex items-center gap-2 cursor-pointer text-sm font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>
                  <input type="radio" name="rep" checked={repChoice === v} onChange={() => setRepChoice(v)} style={{ accentColor: TEAL }} />
                  {l}
                </label>
              ))}
              {repChoice === 'perso' && (
                <input type="date" value={repEndDate} onChange={e => setRepEndDate(e.target.value)}
                  className="mt-1 px-3 py-2 border border-gray-200 rounded-xl text-sm w-full focus:outline-none" />
              )}
            </div>
            <div className="flex gap-2">
              <button onClick={() => setShowRepModal(false)}
                className="flex-1 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-500">Annuler</button>
              <button onClick={handleReplicate}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>Répliquer</button>
            </div>
          </div>
        </div>
      )}

      {replicating && (
        <div className="fixed inset-0 bg-black/20 flex items-center justify-center z-50">
          <div className="bg-white rounded-2xl px-8 py-5 text-sm font-semibold shadow-xl"
            style={{ fontFamily: 'Galey, sans-serif', color: TEAL }}>
            Réplication en cours…
          </div>
        </div>
      )}
    </div>
  );
}
