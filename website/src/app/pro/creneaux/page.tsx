'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const TEAL   = '#0C5C6C';
const GREEN  = '#6E9E57';
const ORANGE = '#FF9800';

const JOURS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const MOIS  = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];

function getMonday(d: Date): Date {
  const day  = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  const mon  = new Date(d);
  mon.setDate(d.getDate() + diff);
  mon.setHours(0, 0, 0, 0);
  return mon;
}

function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

type SlotStatus = 'disponible' | 'bloque';

export default function ProCreneauxPage() {
  const { user, loading } = useAuth();
  const router        = useRouter();
  const activeProfileId = useActiveProfile();

  const [weekStart, setWeekStart]           = useState(() => getMonday(new Date()));
  const [selectedDayIdx, setSelectedDayIdx] = useState(0);
  const [mode, setMode]                     = useState<SlotStatus>('disponible');
  const [slots, setSlots]                   = useState<Record<string, SlotStatus>>({});
  const [loadingSlots, setLoadingSlots]     = useState(false);
  const [saving, setSaving]                 = useState<string | null>(null);
  const [replicating, setReplicating]       = useState(false);
  const [showModal, setShowModal]           = useState(false);
  const [repChoice, setRepChoice]           = useState<'4sem' | 'annee' | 'perso'>('4sem');
  const [repEndDate, setRepEndDate]         = useState('');

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  const loadSlots = useCallback(async () => {
    if (!user) return;
    setLoadingSlots(true);
    const end = new Date(weekStart);
    end.setDate(weekStart.getDate() + 6);
    try {
      const { data } = await supabase
        .from('creneaux_pro')
        .select('date, heure_debut, statut')
        .eq('pro_uid', user.uid)
        .eq('pro_profile_id', activeProfileId)
        .in('statut', ['disponible', 'bloque'])
        .gte('date', toDateStr(weekStart))
        .lte('date', toDateStr(end));
      const map: Record<string, SlotStatus> = {};
      for (const r of (data ?? []) as { date: string; heure_debut: string; statut: SlotStatus }[]) {
        const h = parseInt(r.heure_debut.split(':')[0], 10);
        map[`${r.date}_${h}`] = r.statut;
      }
      setSlots(map);
    } catch (e) { console.error(e); }
    setLoadingSlots(false);
  }, [user, activeProfileId, weekStart]);

  useEffect(() => { loadSlots(); }, [loadSlots]);

  const days        = Array.from({ length: 7 }, (_, i) => { const d = new Date(weekStart); d.setDate(weekStart.getDate() + i); return d; });
  const selectedDay = days[selectedDayIdx];
  const dateStr     = toDateStr(selectedDay);

  async function toggleSlot(hour: number) {
    if (!user || saving) return;
    const key    = `${dateStr}_${hour}`;
    const current = slots[key];
    const next    = current === mode ? null : mode;
    const prev    = current;

    setSaving(key);
    setSlots(s => { const n = { ...s }; if (next) n[key] = next; else delete n[key]; return n; });
    try {
      const hd = `${String(hour).padStart(2, '0')}:00:00`;
      const hf = `${String(hour + 1).padStart(2, '0')}:00:00`;
      if (!next) {
        await supabase.from('creneaux_pro').delete()
          .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId)
          .eq('date', dateStr).eq('heure_debut', hd);
      } else {
        await supabase.from('creneaux_pro').upsert({
          pro_uid:        user.uid,
          pro_profile_id: activeProfileId,
          date:           dateStr,
          heure_debut:    hd,
          heure_fin:      hf,
          statut:         next,
        }, { onConflict: 'pro_uid,pro_profile_id,date,heure_debut' });
      }
    } catch (e) {
      console.error(e);
      setSlots(s => { const n = { ...s }; if (prev) n[key] = prev; else delete n[key]; return n; });
    }
    setSaving(null);
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
      endDate = new Date(weekStart);
      endDate.setDate(weekStart.getDate() + 28);
    }
    setReplicating(true);
    setShowModal(false);
    try {
      const rows: Record<string, unknown>[] = [];
      let target = new Date(weekStart);
      target.setDate(target.getDate() + 7);
      while (target <= endDate) {
        for (const [key] of weekSlots) {
          const [datePart, hourStr] = key.split('_');
          const hour    = parseInt(hourStr, 10);
          const orig    = new Date(datePart);
          const dayDiff = Math.round((orig.getTime() - weekStart.getTime()) / 86400000);
          const tDay    = new Date(target);
          tDay.setDate(target.getDate() + dayDiff);
          rows.push({
            pro_uid:        user.uid,
            pro_profile_id: activeProfileId,
            date:           toDateStr(tDay),
            heure_debut:    `${String(hour).padStart(2, '0')}:00:00`,
            heure_fin:      `${String(hour + 1).padStart(2, '0')}:00:00`,
            statut:         'disponible',
          });
        }
        target = new Date(target);
        target.setDate(target.getDate() + 7);
      }
      const seen = new Set<string>();
      const deduped = rows.filter(r => { const k = `${r.date}_${r.heure_debut}`; return seen.has(k as string) ? false : (seen.add(k as string), true); });
      if (deduped.length) await supabase.from('creneaux_pro').upsert(deduped, { onConflict: 'pro_uid,pro_profile_id,date,heure_debut' });
    } catch (e) { console.error(e); }
    setReplicating(false);
  }

  if (loading) return <div className="flex items-center justify-center min-h-screen text-gray-400">Chargement…</div>;

  const dispCount = Object.values(slots).filter(v => v === 'disponible').length;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">

      {/* Titre + Répliquer */}
      <div className="flex items-center justify-between mb-5">
        <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif', color: TEAL }}>
          Mes créneaux
        </h1>
        <button
          onClick={() => setShowModal(true)}
          disabled={dispCount === 0 || replicating}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-sm font-semibold border-2 transition-colors disabled:opacity-40"
          style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
          🔁 Répliquer la semaine…
        </button>
      </div>

      {/* Navigation semaine */}
      <div className="flex items-center gap-2 mb-3">
        <button
          onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() - 7); return n; }); }}
          className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-lg font-bold"
          style={{ color: TEAL }}>‹</button>
        <span className="flex-1 text-center text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
          Semaine du {weekStart.getDate()} {MOIS[weekStart.getMonth()]}
        </span>
        <button
          onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() + 7); return n; }); }}
          className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-lg font-bold"
          style={{ color: TEAL }}>›</button>
      </div>

      {/* Sélecteur de jour */}
      <div className="flex gap-1.5 overflow-x-auto pb-1 mb-3">
        {days.map((day, i) => {
          const sel     = i === selectedDayIdx;
          const isToday = toDateStr(day) === toDateStr(new Date());
          return (
            <button key={i} onClick={() => setSelectedDayIdx(i)}
              className="flex-shrink-0 w-12 py-2 rounded-xl text-center transition-colors border"
              style={{
                background:  sel ? TEAL : isToday ? `${TEAL}15` : 'white',
                borderColor: sel ? TEAL : isToday ? TEAL : '#e5e7eb',
                fontFamily: 'Galey, sans-serif',
              }}>
              <div className="text-xs font-semibold" style={{ color: sel ? 'white' : '#6B7280' }}>
                {JOURS[day.getDay() === 0 ? 6 : day.getDay() - 1]}
              </div>
              <div className="text-sm font-bold" style={{ color: sel ? 'white' : isToday ? TEAL : '#1F2937' }}>
                {day.getDate()}
              </div>
            </button>
          );
        })}
      </div>

      {/* Mode selector */}
      <div className="flex gap-2 mb-3">
        <button onClick={() => setMode('disponible')}
          className="flex-1 py-2.5 rounded-xl text-sm font-semibold border-2 transition-all"
          style={{
            background:  mode === 'disponible' ? `${GREEN}20` : 'white',
            borderColor: mode === 'disponible' ? GREEN : '#e5e7eb',
            color:       mode === 'disponible' ? '#4A7A32' : '#6B7280',
            fontFamily: 'Galey, sans-serif',
          }}>
          ✓ Mode Disponible
        </button>
        <button onClick={() => setMode('bloque')}
          className="flex-1 py-2.5 rounded-xl text-sm font-semibold border-2 transition-all"
          style={{
            background:  mode === 'bloque' ? '#FFF3E0' : 'white',
            borderColor: mode === 'bloque' ? ORANGE : '#e5e7eb',
            color:       mode === 'bloque' ? '#E65100' : '#6B7280',
            fontFamily: 'Galey, sans-serif',
          }}>
          🚫 Mode Bloqué
        </button>
      </div>

      {/* Légende */}
      <div className="flex flex-wrap gap-4 text-xs text-gray-500 mb-4">
        {[
          { bg: `${GREEN}20`, border: GREEN,     label: 'Disponible' },
          { bg: 'white',      border: '#d1d5db', label: 'Libre' },
          { bg: '#FFF3E0',    border: ORANGE,    label: 'Bloqué' },
        ].map(({ bg, border, label }) => (
          <span key={label} className="flex items-center gap-1.5">
            <span className="w-3 h-3 rounded-full border-2 inline-block" style={{ background: bg, borderColor: border }} />
            {label}
          </span>
        ))}
      </div>

      {/* Grille horaire 8h–19h */}
      {loadingSlots ? (
        <div className="flex justify-center py-12 text-sm text-gray-400">Chargement…</div>
      ) : (
        <div className="flex flex-col gap-2">
          {Array.from({ length: 12 }, (_, i) => 8 + i).map(hour => {
            const key    = `${dateStr}_${hour}`;
            const status = slots[key];
            const isSav  = saving === key;

            const hStr = String(hour).padStart(2, '0');
            const h1   = String(hour + 1).padStart(2, '0');

            let bg = 'white', border = '#e5e7eb', textC = '#9CA3AF';
            let badge: string | null = null;
            let badgeBg = 'transparent';

            if (status === 'disponible') {
              bg = `${GREEN}1F`; border = GREEN; textC = '#4A7A32';
              badge = 'Disponible'; badgeBg = `${GREEN}33`;
            } else if (status === 'bloque') {
              bg = '#FFF3E0'; border = ORANGE; textC = '#E65100';
              badge = 'Bloqué'; badgeBg = '#FFE0B2';
            }

            return (
              <button key={hour}
                onClick={() => !isSav && toggleSlot(hour)}
                disabled={isSav}
                className="flex items-center px-4 py-3.5 rounded-xl border-2 transition-all text-left disabled:opacity-60 hover:opacity-90 active:scale-[0.99]"
                style={{ background: bg, borderColor: border, fontFamily: 'Galey, sans-serif' }}>
                <span className="flex-1 text-sm font-semibold" style={{ color: textC }}>
                  {hStr}:00 — {h1}:00
                </span>
                {badge ? (
                  <span className="text-xs font-bold px-2 py-0.5 rounded-lg" style={{ background: badgeBg, color: textC }}>
                    {badge}
                  </span>
                ) : (
                  <span className="text-xs" style={{ color: mode === 'disponible' ? GREEN : ORANGE }}>
                    {mode === 'disponible' ? '+ Disponible' : '🚫 Bloquer'}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      )}

      {/* Modal répliquer */}
      {showModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl">
            <h3 className="font-bold text-base mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
              Répliquer les créneaux
            </h3>
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
                  className="mt-1 px-3 py-2 border border-gray-200 rounded-xl text-sm w-full focus:outline-none focus:ring-2"
                  style={{ fontFamily: 'Galey, sans-serif' }} />
              )}
            </div>
            <div className="flex gap-2">
              <button onClick={() => setShowModal(false)}
                className="flex-1 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-500"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Annuler
              </button>
              <button onClick={handleReplicate}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white"
                style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                Répliquer
              </button>
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
