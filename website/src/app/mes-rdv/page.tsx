'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// ── Constants ──────────────────────────────────────────────────────────────────

const TEAL   = '#0C5C6C';
const GREEN  = '#6E9E57';
const ORANGE = '#FF9800';

const JOURS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const MOIS  = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];

const STATUT_STYLE: Record<string, { bg: string; color: string; label: string }> = {
  demande:            { bg: '#FFF3E0', color: '#e08000',  label: 'Demande'       },
  contre_proposition: { bg: '#E3F2FD', color: '#1565C0',  label: 'Contre-prop.'  },
  confirme:           { bg: '#E8F5E9', color: '#388E3C',  label: 'Confirmé'      },
  termine:            { bg: '#F5F5F5', color: '#757575',  label: 'Terminé'       },
  annule:             { bg: '#FFEBEE', color: '#d32f2f',  label: 'Annulé'        },
  refuse:             { bg: '#FFEBEE', color: '#d32f2f',  label: 'Refusé'        },
  no_show:            { bg: '#FFF8E1', color: '#F57F17',  label: 'No-show'       },
};

const PRO_TITLE: Record<string, string> = {
  veterinaire:      'Mes rendez-vous',
  sante:            'Mes rendez-vous',
  pension:          'Gestion des RDV',
  garde:            'Mes RDV de garde',
  education:        'Mes séances',
  toilettage:       'Mes RDV toilettage',
  comportementaliste: 'Mes séances',
  osteo:            'Mes séances',
  photographe:      'Mes séances photo',
  marechal_ferrant: 'Mes interventions',
};

// ── Types ──────────────────────────────────────────────────────────────────────

interface Rdv {
  id: string;
  pro_uid: string;
  client_uid: string;
  animal_id?: string | null;
  date_heure: string;
  motif?: string | null;
  statut: string;
  notes_annulation?: string | null;
  notes_pro?: string | null;
  duree_minutes?: number | null;
  premiere_visite?: boolean | null;
  clientName?: string;
  animalNom?: string;
  visitCount?: number;
}

type SlotStatus = 'disponible' | 'bloque';

// ── Helpers ────────────────────────────────────────────────────────────────────

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' });
}
function fmtHeure(iso: string) {
  return new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}
function getMonday(d: Date): Date {
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  const mon = new Date(d);
  mon.setDate(d.getDate() + diff);
  mon.setHours(0, 0, 0, 0);
  return mon;
}
function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// ── Modal Accepter ─────────────────────────────────────────────────────────────

function AccepterModal({ rdv, proName, onClose, onDone }: {
  rdv: Rdv; proName: string; onClose: () => void; onDone: () => void;
}) {
  const [mode, setMode]     = useState<'confirme' | 'contre_proposition'>('confirme');
  const [hour, setHour]     = useState(new Date(rdv.date_heure).getHours());
  const [minute, setMinute] = useState(0);
  const [date, setDate]     = useState(rdv.date_heure.slice(0, 10));
  const [duree, setDuree]   = useState(rdv.duree_minutes ?? 60);
  const [saving, setSaving] = useState(false);

  async function handleSubmit() {
    setSaving(true);
    try {
      const newDt     = new Date(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`);
      const newStatut = mode === 'confirme' ? 'confirme' : 'contre_proposition';

      await supabase.from('rdv').update({
        statut: newStatut, date_heure: newDt.toISOString(), duree_minutes: duree,
      }).eq('id', rdv.id);

      if (mode === 'confirme') {
        await supabase.from('agenda_events').upsert({
          uid: rdv.client_uid,
          titre: `RDV${rdv.animalNom ? ` — ${rdv.animalNom}` : ''}`,
          type: 'rdv', date_debut: newDt.toISOString(),
          duree_minutes: duree, rdv_id: rdv.id,
          animal_id: rdv.animal_id ?? null,
        }, { onConflict: 'rdv_id' });

        await supabase.from('agenda_events').delete()
          .eq('uid', rdv.pro_uid).eq('couleur', `rdv:${rdv.id}`);
        await supabase.from('agenda_events').insert({
          uid: rdv.pro_uid,
          titre: `RDV avec ${rdv.clientName ?? 'Client'}`,
          type: 'rdv', date_debut: newDt.toISOString(),
          duree_minutes: duree, couleur: `rdv:${rdv.id}`,
          animal_id: rdv.animal_id ?? null,
        });

        await supabase.from('notifications').insert({
          uid: rdv.client_uid, type: 'rdv_confirme',
          title: `RDV confirmé par ${proName}`,
          body: `Votre rendez-vous est confirmé pour le ${fmtDate(newDt.toISOString())} à ${fmtHeure(newDt.toISOString())}`,
          data: { rdv_id: rdv.id }, read: false,
        });
      } else {
        await supabase.from('notifications').insert({
          uid: rdv.client_uid, type: 'rdv_contre_proposition',
          title: 'Contre-proposition de créneau',
          body: `${proName} propose un autre créneau : ${fmtDate(newDt.toISOString())} à ${fmtHeure(newDt.toISOString())}`,
          data: { rdv_id: rdv.id }, read: false,
        });
      }
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-5" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Accepter le RDV</h2>

        <div className="bg-gray-50 rounded-xl p-3 text-sm text-gray-600">
          <p className="font-semibold">{rdv.clientName ?? '—'}{rdv.animalNom ? ` · ${rdv.animalNom}` : ''}</p>
          <p className="text-xs text-gray-400 mt-0.5">Demandé : {fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}</p>
          {rdv.motif && <p className="text-xs text-gray-400">Motif : {rdv.motif}</p>}
        </div>

        <div className="flex gap-2 bg-gray-100 rounded-xl p-1">
          {(['confirme', 'contre_proposition'] as const).map(m => (
            <button key={m} onClick={() => setMode(m)}
              className="flex-1 py-2 text-sm font-semibold rounded-lg transition-all"
              style={{ background: mode === m ? 'white' : 'transparent', color: mode === m ? TEAL : '#6b7280', fontFamily: 'Galey, sans-serif' }}>
              {m === 'confirme' ? 'Confirmer' : 'Autre créneau'}
            </button>
          ))}
        </div>

        {mode === 'contre_proposition' && (
          <div>
            <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</label>
            <input type="date" value={date} onChange={e => setDate(e.target.value)}
              className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
          </div>
        )}

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Heure</label>
          <div className="flex gap-2 mt-2">
            <select value={hour} onChange={e => setHour(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {Array.from({ length: 14 }, (_, i) => i + 7).map(h => (
                <option key={h} value={h}>{String(h).padStart(2, '0')}h</option>
              ))}
            </select>
            <select value={minute} onChange={e => setMinute(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {[0, 15, 30, 45].map(m => (
                <option key={m} value={m}>{String(m).padStart(2, '0')}</option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Durée</label>
          <div className="flex flex-wrap gap-2 mt-2">
            {[15, 30, 45, 60, 90, 120].map(d => (
              <button key={d} onClick={() => setDuree(d)}
                className="px-3 py-1.5 rounded-lg text-xs font-semibold border transition-colors"
                style={{ background: duree === d ? TEAL : 'white', color: duree === d ? 'white' : '#1E2025', borderColor: duree === d ? TEAL : '#e5e7eb', fontFamily: 'Galey, sans-serif' }}>
                {d < 60 ? `${d} min` : d === 60 ? '1 h' : `${d / 60} h`}
              </button>
            ))}
          </div>
        </div>

        <div className="flex gap-3 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">
            Annuler
          </button>
          <button onClick={handleSubmit} disabled={saving}
            className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold disabled:opacity-50"
            style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
            {saving ? '…' : mode === 'confirme' ? '✓ Confirmer' : 'Proposer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal Refuser / Annuler ────────────────────────────────────────────────────

function RefuserModal({ rdv, label, type, onClose, onDone }: {
  rdv: Rdv; label: string; type: 'refuse' | 'annule'; onClose: () => void; onDone: () => void;
}) {
  const [motif, setMotif]   = useState('');
  const [saving, setSaving] = useState(false);

  async function handleSubmit() {
    setSaving(true);
    try {
      await supabase.from('rdv').update({ statut: type, notes_annulation: motif || null }).eq('id', rdv.id);
      await supabase.from('agenda_events').delete().eq('rdv_id', rdv.id);
      await supabase.from('agenda_events').delete()
        .eq('uid', rdv.pro_uid).eq('couleur', `rdv:${rdv.id}`);
      await supabase.from('notifications').insert({
        uid: rdv.client_uid,
        type: type === 'refuse' ? 'rdv_refuse' : 'rdv_annule',
        title: type === 'refuse' ? 'Demande de RDV refusée' : 'RDV annulé',
        body: `${type === 'refuse' ? 'Votre demande a été refusée' : 'Votre RDV a été annulé'}${motif ? ` — Motif : ${motif}` : ''}`,
        data: { rdv_id: rdv.id }, read: false,
      });
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{label} ce RDV</h2>
        <div className="bg-gray-50 rounded-xl p-3 text-sm">
          <p className="font-semibold">{rdv.clientName ?? '—'}</p>
          <p className="text-xs text-gray-400 mt-0.5">{fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}</p>
        </div>
        <textarea value={motif} onChange={e => setMotif(e.target.value)} rows={3}
          placeholder="Motif (optionnel)…"
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none focus:outline-none"
          style={{ fontFamily: 'Galey, sans-serif' }} />
        <div className="flex gap-3">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">Retour</button>
          <button onClick={handleSubmit} disabled={saving}
            className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold bg-red-500 hover:bg-red-600 disabled:opacity-50">
            {saving ? '…' : label}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Carte RDV ──────────────────────────────────────────────────────────────────

function RdvCard({ rdv, tab, isVet, onAccepter, onRefuser, onAnnuler, onTerminer, onDelete, onOpenAnimal }: {
  rdv: Rdv;
  tab: 'demandes' | 'a_venir' | 'historique';
  isVet: boolean;
  onAccepter?: () => void;
  onRefuser?: () => void;
  onAnnuler?: () => void;
  onTerminer?: () => void;
  onDelete?: () => void;
  onOpenAnimal?: (id: string) => void;
}) {
  const [confirmDel, setConfirmDel] = useState(false);
  const st      = STATUT_STYLE[rdv.statut] ?? { bg: '#F5F5F5', color: '#757575', label: rdv.statut };
  const isFirst = rdv.visitCount === 0;

  return (
    <div className="bg-white rounded-2xl px-4 py-4 shadow-sm border border-gray-100 space-y-3">
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="font-bold text-[#1E2025] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
              {rdv.clientName ?? '—'}
            </p>
            <span className="text-xs px-2 py-0.5 rounded-full font-semibold"
              style={{ background: isFirst ? '#FFF8E1' : '#E3F2FD', color: isFirst ? '#F57F17' : '#1565C0', fontFamily: 'Galey, sans-serif' }}>
              {isFirst ? '⭐ 1ère visite' : `🔄 ${rdv.visitCount} visite${(rdv.visitCount ?? 0) > 1 ? 's' : ''}`}
            </span>
          </div>
          {rdv.animalNom && (
            <p className="text-xs text-gray-500 mt-0.5">🐾 {rdv.animalNom}</p>
          )}
          <p className="text-sm text-[#0C5C6C] mt-1 font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            {fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}
          </p>
          {rdv.duree_minutes && (
            <p className="text-xs text-gray-400">⏱ {rdv.duree_minutes} min</p>
          )}
          {rdv.motif && <p className="text-xs text-gray-400 mt-0.5 truncate">Motif : {rdv.motif}</p>}
          {rdv.notes_annulation && <p className="text-xs text-red-400 mt-0.5">Note : {rdv.notes_annulation}</p>}
        </div>
        <span className="text-xs px-2 py-0.5 rounded-full font-semibold flex-shrink-0"
          style={{ background: st.bg, color: st.color, fontFamily: 'Galey, sans-serif' }}>
          {st.label}
        </span>
      </div>

      <div className="flex gap-2 flex-wrap">
        {tab === 'demandes' && (
          <>
            <button onClick={onAccepter}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-white"
              style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
              ✓ Accepter
            </button>
            <button onClick={onRefuser}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-red-600 border border-red-200 hover:bg-red-50"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              ✗ Refuser
            </button>
          </>
        )}
        {tab === 'a_venir' && (
          <>
            {isVet && rdv.animal_id && (
              <button onClick={() => onOpenAnimal?.(rdv.animal_id!)}
                className="text-xs font-semibold px-3 py-2 rounded-xl border"
                style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
                🐾 Fiche animal
              </button>
            )}
            <button onClick={onTerminer}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-white"
              style={{ background: GREEN, fontFamily: 'Galey, sans-serif' }}>
              ✓ Terminé
            </button>
            <button onClick={onAnnuler}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-red-600 border border-red-200 hover:bg-red-50"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Annuler
            </button>
          </>
        )}
        {tab === 'historique' && (
          <>
            {isVet && rdv.animal_id && (
              <button onClick={() => onOpenAnimal?.(rdv.animal_id!)}
                className="text-xs font-semibold px-3 py-2 rounded-xl border"
                style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
                🐾 Fiche animal
              </button>
            )}
            {confirmDel ? (
              <div className="flex gap-2 items-center flex-1">
                <span className="text-xs text-gray-500 flex-1">Supprimer définitivement ?</span>
                <button onClick={() => setConfirmDel(false)}
                  className="px-3 py-1.5 rounded-xl text-xs border border-gray-200">Non</button>
                <button onClick={onDelete}
                  className="px-3 py-1.5 rounded-xl text-xs text-white bg-red-500 font-semibold">Oui</button>
              </div>
            ) : (
              <button onClick={() => setConfirmDel(true)}
                className="text-xs text-red-400 hover:text-red-600 px-3 py-1.5 rounded-xl border border-red-100"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Supprimer
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}

// ── Onglet Créneaux ────────────────────────────────────────────────────────────

// Helpers 15 min (partagés avec /pro/creneaux)
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
interface SlotRange { start: string; end: string; statut: SlotStatus; }
function groupRanges(slotsForDate: { time: string; statut: SlotStatus }[]): SlotRange[] {
  const sorted = [...slotsForDate].sort((a, b) => a.time.localeCompare(b.time));
  if (!sorted.length) return [];
  const ranges: SlotRange[] = [];
  let rStart = sorted[0].time;
  let prevMins = timeToMins(sorted[0].time);
  let curStatut = sorted[0].statut;
  for (let i = 1; i < sorted.length; i++) {
    const curMins = timeToMins(sorted[i].time);
    if (sorted[i].statut === curStatut && curMins === prevMins + 15) {
      prevMins = curMins;
    } else {
      ranges.push({ start: rStart, end: minsToTime(prevMins + 15), statut: curStatut });
      rStart = sorted[i].time; prevMins = curMins; curStatut = sorted[i].statut;
    }
  }
  ranges.push({ start: rStart, end: minsToTime(prevMins + 15), statut: curStatut });
  return ranges;
}

function CreneauxTab({ uid, profileId }: { uid: string; profileId: string }) {
  const [weekStart, setWeekStart]           = useState(() => getMonday(new Date()));
  const [selectedDayIdx, setSelectedDayIdx] = useState(0);
  const [slots, setSlots]                   = useState<Record<string, SlotStatus>>({});
  const [loadingSlots, setLoadingSlots]     = useState(false);
  const [saving, setSaving]                 = useState(false);
  const [replicating, setReplicating]       = useState(false);
  const [showRepModal, setShowRepModal]     = useState(false);
  const [repChoice, setRepChoice]           = useState<'4sem' | 'annee' | 'perso'>('4sem');
  const [repEndDate, setRepEndDate]         = useState('');
  // Add-range modal
  const [showAddModal, setShowAddModal]     = useState(false);
  const [addMode, setAddMode]               = useState<SlotStatus>('disponible');
  const [addStart, setAddStart]             = useState('09:00');
  const [addEnd, setAddEnd]                 = useState('10:00');

  const loadSlots = useCallback(async () => {
    setLoadingSlots(true);
    const end = new Date(weekStart);
    end.setDate(weekStart.getDate() + 6);
    try {
      const { data } = await supabase
        .from('creneaux_pro')
        .select('date, heure_debut, statut')
        .eq('pro_uid', uid)
        .eq('pro_profile_id', profileId)
        .in('statut', ['disponible', 'bloque'])
        .gte('date', toDateStr(weekStart))
        .lte('date', toDateStr(end));
      const map: Record<string, SlotStatus> = {};
      for (const r of (data ?? []) as { date: string; heure_debut: string; statut: SlotStatus }[]) {
        const hhmm = r.heure_debut.substring(0, 5); // 'HH:MM'
        map[`${r.date}_${hhmm}`] = r.statut;
      }
      setSlots(map);
    } catch { /* ignore */ }
    setLoadingSlots(false);
  }, [uid, profileId, weekStart]);

  useEffect(() => { loadSlots(); }, [loadSlots]);

  const days        = Array.from({ length: 7 }, (_, i) => { const d = new Date(weekStart); d.setDate(weekStart.getDate() + i); return d; });
  const selectedDay = days[selectedDayIdx];
  const dateStr     = toDateStr(selectedDay);

  // Plages regroupées pour le jour sélectionné
  const slotsForDay = Object.entries(slots)
    .filter(([k]) => k.startsWith(`${dateStr}_`))
    .map(([k, statut]) => ({ time: k.slice(dateStr.length + 1), statut }));
  const ranges = groupRanges(slotsForDay);

  async function applyRange(start: string, end: string, statut: SlotStatus) {
    if (saving) return;
    setSaving(true);
    let cur = timeToMins(start);
    const endM = timeToMins(end);
    const newSlots: Record<string, SlotStatus> = {};
    const rows: Record<string, unknown>[] = [];
    while (cur < endM) {
      const hhmm = minsToTime(cur);
      const fin  = minsToTime(cur + 15);
      const key  = `${dateStr}_${hhmm}`;
      newSlots[key] = statut;
      rows.push({ pro_uid: uid, pro_profile_id: profileId, date: dateStr,
        heure_debut: `${hhmm}:00`, heure_fin: `${fin}:00`, statut });
      cur += 15;
    }
    setSlots(s => ({ ...s, ...newSlots }));
    try {
      await supabase.from('creneaux_pro').upsert(rows, { onConflict: 'pro_uid,pro_profile_id,date,heure_debut' });
    } catch {
      setSlots(s => { const n = { ...s }; Object.keys(newSlots).forEach(k => delete n[k]); return n; });
    }
    setSaving(false);
  }

  async function deleteRange(r: SlotRange) {
    let cur = timeToMins(r.start);
    const endM = timeToMins(r.end);
    const hdList: string[] = [];
    const keyList: string[] = [];
    while (cur < endM) {
      const hhmm = minsToTime(cur);
      hdList.push(`${hhmm}:00`);
      keyList.push(`${dateStr}_${hhmm}`);
      cur += 15;
    }
    setSlots(s => { const n = { ...s }; keyList.forEach(k => delete n[k]); return n; });
    try {
      await supabase.from('creneaux_pro').delete()
        .eq('pro_uid', uid).eq('pro_profile_id', profileId)
        .eq('date', dateStr).in('heure_debut', hdList);
    } catch { loadSlots(); }
  }

  async function handleReplicate() {
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
          rows.push({ pro_uid: uid, pro_profile_id: profileId, date: toDateStr(tDay),
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

  return (
    <div className="space-y-4">
      {/* Navigation semaine */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <div className="flex items-center justify-between mb-3">
          <button onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() - 7); return n; }); }}
            className="p-2 rounded-lg hover:bg-gray-100 text-lg font-bold" style={{ color: TEAL }}>‹</button>
          <span className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            Semaine du {weekStart.getDate()} {MOIS[weekStart.getMonth()]}
          </span>
          <button onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() + 7); return n; }); }}
            className="p-2 rounded-lg hover:bg-gray-100 text-lg font-bold" style={{ color: TEAL }}>›</button>
        </div>
        <div className="flex gap-1.5 overflow-x-auto pb-1">
          {days.map((day, i) => {
            const sel     = i === selectedDayIdx;
            const isToday = toDateStr(day) === toDateStr(new Date());
            return (
              <button key={i} onClick={() => setSelectedDayIdx(i)}
                className="flex-shrink-0 w-11 py-2 rounded-xl text-center border transition-colors"
                style={{ background: sel ? TEAL : isToday ? `${TEAL}15` : 'white', borderColor: sel ? TEAL : isToday ? TEAL : '#e5e7eb' }}>
                <div className="text-[10px] font-semibold" style={{ color: sel ? 'white' : '#6B7280' }}>
                  {JOURS[day.getDay() === 0 ? 6 : day.getDay() - 1]}
                </div>
                <div className="text-sm font-bold" style={{ color: sel ? 'white' : isToday ? TEAL : '#1F2937' }}>
                  {day.getDate()}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-2">
        <button onClick={() => setShowAddModal(true)}
          className="flex-1 py-3 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-2"
          style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
          + Nouvelle plage
        </button>
        <button onClick={() => setShowRepModal(true)} disabled={dispCount === 0 || replicating}
          className="px-4 py-3 rounded-xl text-sm font-semibold border-2 transition-colors disabled:opacity-40"
          style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}
          title="Répliquer la semaine">
          🔁
        </button>
      </div>

      {/* Plages du jour */}
      {loadingSlots ? (
        <div className="flex justify-center py-10 text-sm text-gray-400">Chargement…</div>
      ) : ranges.length === 0 ? (
        <div className="bg-white rounded-2xl border border-dashed border-gray-200 p-8 text-center">
          <p className="text-3xl mb-2">🗓</p>
          <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
            Aucune plage configurée
          </p>
          <p className="text-xs text-gray-300 mt-1">Appuyez sur « + Nouvelle plage » pour ajouter une disponibilité ou un blocage</p>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {ranges.map((r, i) => {
            const isDisp = r.statut === 'disponible';
            return (
              <div key={i} className="bg-white rounded-2xl px-4 py-3.5 shadow-sm border-2 flex items-center gap-3"
                style={{ borderColor: isDisp ? GREEN : ORANGE }}>
                <div className="flex-1">
                  <p className="text-lg font-bold" style={{ fontFamily: 'Galey, sans-serif', color: isDisp ? '#4A7A32' : '#E65100' }}>
                    {r.start} → {r.end}
                  </p>
                  <span className="text-xs font-semibold px-2 py-0.5 rounded-full"
                    style={{ background: isDisp ? `${GREEN}22` : '#FFF3E0', color: isDisp ? '#4A7A32' : '#E65100' }}>
                    {isDisp ? '✓ Disponible' : '🚫 Bloqué'}
                  </span>
                </div>
                <button onClick={() => deleteRange(r)}
                  className="p-2 rounded-xl hover:bg-red-50 text-red-400 hover:text-red-600 transition-colors text-sm">
                  🗑
                </button>
              </div>
            );
          })}
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

            {/* Mode */}
            <div className="flex gap-2">
              {(['disponible', 'bloque'] as const).map(m => {
                const col = m === 'disponible' ? GREEN : ORANGE;
                return (
                  <button key={m} onClick={() => setAddMode(m)}
                    className="flex-1 py-2.5 rounded-xl text-sm font-semibold border-2 transition-all"
                    style={{ background: addMode === m ? `${col}18` : 'white', borderColor: addMode === m ? col : '#e5e7eb', color: addMode === m ? (m === 'disponible' ? '#4A7A32' : '#E65100') : '#6B7280', fontFamily: 'Galey, sans-serif' }}>
                    {m === 'disponible' ? '✓ Disponible' : '🚫 Bloqué'}
                  </button>
                );
              })}
            </div>

            {/* Horaires */}
            <div className="flex items-center gap-3">
              <div className="flex-1">
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">De</label>
                <input type="time" step="900" value={addStart}
                  onChange={e => setAddStart(snapTo15(e.target.value || addStart))}
                  className="w-full border-2 border-gray-200 rounded-xl px-3 py-3 text-xl font-bold text-center focus:outline-none focus:border-[#0C5C6C] text-[#1E2025]"
                  style={{ fontFamily: 'Galey, sans-serif' }} />
              </div>
              <span className="text-2xl text-gray-400 mt-5">→</span>
              <div className="flex-1">
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">À</label>
                <input type="time" step="900" value={addEnd}
                  onChange={e => setAddEnd(snapTo15(e.target.value || addEnd))}
                  className="w-full border-2 border-gray-200 rounded-xl px-3 py-3 text-xl font-bold text-center focus:outline-none focus:border-[#0C5C6C] text-[#1E2025]"
                  style={{ fontFamily: 'Galey, sans-serif' }} />
              </div>
            </div>

            {timeToMins(addEnd) <= timeToMins(addStart) && (
              <p className="text-xs text-red-500 -mt-2">L&apos;heure de fin doit être après l&apos;heure de début.</p>
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
                  await applyRange(addStart, addEnd, addMode);
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
          <div className="bg-white rounded-2xl px-8 py-5 text-sm font-semibold shadow-xl" style={{ color: TEAL }}>Réplication en cours…</div>
        </div>
      )}
    </div>
  );
}

// ── Page principale ────────────────────────────────────────────────────────────

type TabKey = 'demandes' | 'a_venir' | 'historique' | 'creneaux';

export default function MesRdvPage() {
  const { user, userData, loading } = useAuth();
  const router      = useRouter();
  const activeProfileId = useActiveProfile();

  const [activeTab, setActiveTab] = useState<TabKey>('demandes');
  const [rdvs, setRdvs]           = useState<Rdv[]>([]);
  const [fetching, setFetching]   = useState(true);
  const [catPro, setCatPro]       = useState('');

  const [modalAccepter, setModalAccepter] = useState<Rdv | null>(null);
  const [modalRefuser, setModalRefuser]   = useState<Rdv | null>(null);
  const [modalAnnuler, setModalAnnuler]   = useState<Rdv | null>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  // Résoudre le cat_pro depuis le profil actif
  useEffect(() => {
    async function resolveCatPro() {
      if (activeProfileId) {
        const { data } = await supabase.from('user_profiles')
          .select('profile_type, cat_pro').eq('id', activeProfileId).single();
        if (data) {
          const r = data as { profile_type: string; cat_pro: string };
          setCatPro(r.profile_type ?? r.cat_pro ?? '');
          return;
        }
      }
      setCatPro(userData?.catPro ?? '');
    }
    resolveCatPro();
  }, [activeProfileId, userData]);

  const isVet  = catPro === 'veterinaire' || catPro === 'sante';
  const proName = userData?.nameElevage ?? userData?.firstname ?? 'Le professionnel';

  const fetchRdvs = useCallback(async () => {
    if (!user) return;
    setFetching(true);
    try {
      const { data } = await supabase
        .from('rdv')
        .select('id, pro_uid, client_uid, animal_id, date_heure, motif, statut, notes_annulation, notes_pro, duree_minutes, premiere_visite')
        .eq('pro_uid', user.uid)
        .eq('pro_profile_id', activeProfileId)
        .order('date_heure', { ascending: true });

      const list = (data ?? []) as Rdv[];
      const clientUids = [...new Set(list.map(r => r.client_uid).filter(Boolean))];
      const animalIds  = [...new Set(list.map(r => r.animal_id).filter(Boolean) as string[])];

      const [usersRes, animauxRes] = await Promise.all([
        clientUids.length ? supabase.from('users').select('uid, firstname, lastname, prenom, nom').in('uid', clientUids) : Promise.resolve({ data: [] }),
        animalIds.length  ? supabase.from('animaux').select('id, nom').in('id', animalIds) : Promise.resolve({ data: [] }),
      ]);

      const usersMap: Record<string, string> = {};
      for (const u of (usersRes.data ?? [])) {
        const rec = u as { uid: string; firstname?: string; lastname?: string; prenom?: string; nom?: string };
        usersMap[rec.uid] = [rec.prenom ?? rec.firstname, rec.nom ?? rec.lastname].filter(Boolean).join(' ') || 'Client';
      }
      const animauxMap: Record<string, string> = {};
      for (const a of (animauxRes.data ?? [])) {
        const rec = a as { id: string; nom?: string };
        if (rec.nom) animauxMap[rec.id] = rec.nom;
      }

      const visitCounts: Record<string, number> = {};
      if (clientUids.length) {
        const { data: hist } = await supabase.from('rdv')
          .select('client_uid').eq('pro_uid', user.uid)
          .in('client_uid', clientUids).in('statut', ['confirme', 'termine']);
        for (const h of (hist ?? [])) {
          const cUid = (h as { client_uid: string }).client_uid;
          visitCounts[cUid] = (visitCounts[cUid] ?? 0) + 1;
        }
      }

      setRdvs(list.map(r => ({
        ...r,
        clientName: usersMap[r.client_uid] ?? undefined,
        animalNom:  r.animal_id ? animauxMap[String(r.animal_id)] ?? undefined : undefined,
        visitCount: visitCounts[r.client_uid] ?? 0,
      })));
    } catch { /* ignore */ } finally { setFetching(false); }
  }, [user, activeProfileId]);

  useEffect(() => { fetchRdvs(); }, [fetchRdvs]);

  async function marquerTermine(rdv: Rdv) {
    await supabase.from('rdv').update({ statut: 'termine' }).eq('id', rdv.id);
    fetchRdvs();
  }

  async function deleteRdv(rdvId: string) {
    await supabase.from('agenda_events').delete().eq('rdv_id', rdvId);
    if (user) {
      await supabase.from('agenda_events').delete()
        .eq('uid', user.uid).eq('couleur', `rdv:${rdvId}`);
    }
    await supabase.from('rdv').delete().eq('id', rdvId);
    setRdvs(prev => prev.filter(r => r.id !== rdvId));
  }

  function openAnimalFiche(animalId: string) {
    router.push(`/mes-patients/${animalId}`);
  }

  if (loading) return (
    <div className="flex justify-center py-32">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!user) return null;

  const now = new Date();
  const demandes   = rdvs.filter(r => r.statut === 'demande' || r.statut === 'contre_proposition');
  const aVenir     = rdvs.filter(r => r.statut === 'confirme' && new Date(r.date_heure) > now);
  const historique = rdvs.filter(r =>
    r.statut !== 'demande' && r.statut !== 'contre_proposition' &&
    !(r.statut === 'confirme' && new Date(r.date_heure) > now)
  );

  const TABS: { key: TabKey; label: string; badge: number }[] = [
    { key: 'demandes',   label: 'Demandes',   badge: demandes.length   },
    { key: 'a_venir',    label: 'À venir',    badge: aVenir.length     },
    { key: 'historique', label: 'Historique', badge: 0                 },
    { key: 'creneaux',   label: 'Créneaux',   badge: 0                 },
  ];

  const currentList = activeTab === 'demandes' ? demandes : activeTab === 'a_venir' ? aVenir : historique;

  const pageTitle = PRO_TITLE[catPro] ?? 'Mes rendez-vous';

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      {/* Header */}
      <div style={{ background: TEAL }} className="text-white px-4 py-6">
        <div className="max-w-3xl mx-auto">
          <div className="flex items-center gap-3 mb-4">
            <button onClick={() => router.back()}
              className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors">
              ←
            </button>
            <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{pageTitle}</h1>
          </div>

          {/* Stats rapides */}
          <div className="grid grid-cols-3 gap-2 mb-4">
            <div className="bg-white/10 rounded-xl p-2.5 text-center">
              <p className="text-xl font-bold">{demandes.length}</p>
              <p className="text-[10px] text-white/70">En attente</p>
            </div>
            <div className="bg-white/10 rounded-xl p-2.5 text-center">
              <p className="text-xl font-bold">{aVenir.length}</p>
              <p className="text-[10px] text-white/70">À venir</p>
            </div>
            <div className="bg-white/10 rounded-xl p-2.5 text-center">
              <p className="text-xl font-bold">{historique.length}</p>
              <p className="text-[10px] text-white/70">Historique</p>
            </div>
          </div>

          {/* Tabs */}
          <div className="flex gap-1 bg-white/10 rounded-xl p-1">
            {TABS.map(t => (
              <button key={t.key} onClick={() => setActiveTab(t.key)}
                className="flex-1 py-2 px-1 text-xs font-semibold rounded-lg transition-all flex items-center justify-center gap-1"
                style={{ background: activeTab === t.key ? 'white' : 'transparent', color: activeTab === t.key ? TEAL : 'rgba(255,255,255,0.75)', fontFamily: 'Galey, sans-serif' }}>
                {t.label}
                {t.badge > 0 && (
                  <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full"
                    style={{ background: activeTab === t.key ? TEAL : 'rgba(255,255,255,0.2)', color: 'white' }}>
                    {t.badge}
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* Onglet créneaux */}
        {activeTab === 'creneaux' && user && (
          <CreneauxTab uid={user.uid} profileId={activeProfileId ?? ''} />
        )}

        {/* Onglets RDV */}
        {activeTab !== 'creneaux' && (
          fetching ? (
            <div className="flex justify-center py-16">
              <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : currentList.length === 0 ? (
            <div className="text-center py-20 text-gray-400">
              <div className="text-5xl mb-4">📅</div>
              <p className="font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
                {activeTab === 'demandes' ? 'Aucune demande en attente' : activeTab === 'a_venir' ? 'Aucun RDV à venir' : 'Aucun historique'}
              </p>
              {activeTab === 'demandes' && (
                <p className="text-xs mt-2 text-gray-400">Les clients vous enverront des demandes via votre profil</p>
              )}
            </div>
          ) : (
            <div className="space-y-3">
              {currentList.map(rdv => (
                <RdvCard key={rdv.id} rdv={rdv} tab={activeTab as 'demandes' | 'a_venir' | 'historique'} isVet={isVet}
                  onAccepter={() => setModalAccepter(rdv)}
                  onRefuser={() => setModalRefuser(rdv)}
                  onAnnuler={() => setModalAnnuler(rdv)}
                  onTerminer={() => marquerTermine(rdv)}
                  onDelete={() => deleteRdv(rdv.id)}
                  onOpenAnimal={openAnimalFiche}
                />
              ))}
            </div>
          )
        )}
      </div>

      {modalAccepter && (
        <AccepterModal rdv={modalAccepter} proName={proName}
          onClose={() => setModalAccepter(null)}
          onDone={() => { setModalAccepter(null); fetchRdvs(); }} />
      )}
      {modalRefuser && (
        <RefuserModal rdv={modalRefuser} label="Refuser" type="refuse"
          onClose={() => setModalRefuser(null)}
          onDone={() => { setModalRefuser(null); fetchRdvs(); }} />
      )}
      {modalAnnuler && (
        <RefuserModal rdv={modalAnnuler} label="Annuler" type="annule"
          onClose={() => setModalAnnuler(null)}
          onDone={() => { setModalAnnuler(null); fetchRdvs(); }} />
      )}
    </div>
  );
}
