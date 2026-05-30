'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

// ── Types ──────────────────────────────────────────────────────────────────────

interface AgendaEvent {
  id: number;
  uid: string;
  titre: string;
  date_debut: string;
  date_fin?: string;
  type: string;
  notes?: string;
  couleur?: string;
  animal_id?: number;
}

const TYPE_LABEL: Record<string, string> = {
  rdv:        'RDV',
  mise_bas:   'Mise-bas',
  medication: 'Médicament',
  visite:     'Visite',
  autre:      'Autre',
};

const TYPE_ICON: Record<string, string> = {
  rdv:        '🩺',
  mise_bas:   '🐣',
  medication: '💊',
  visite:     '👀',
  autre:      '📅',
};

const TYPE_COLOR: Record<string, string> = {
  rdv:        '#2196F3',
  mise_bas:   '#E91E63',
  medication: '#FF9800',
  visite:     '#4CAF50',
  autre:      '#9E9E9E',
};

const TYPES = ['rdv', 'mise_bas', 'medication', 'visite', 'autre'];

function colorFor(e: AgendaEvent) {
  if (e.couleur) return e.couleur;
  return TYPE_COLOR[e.type] ?? '#9E9E9E';
}

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
}

function fmtTime(iso: string) {
  return new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}

function isToday(iso: string) {
  const d = new Date(iso);
  const t = new Date();
  return d.getDate() === t.getDate() && d.getMonth() === t.getMonth() && d.getFullYear() === t.getFullYear();
}

// ── Calendar helpers ───────────────────────────────────────────────────────────

function daysInMonth(year: number, month: number) {
  return new Date(year, month + 1, 0).getDate();
}

function firstWeekday(year: number, month: number) {
  // Monday = 0
  return (new Date(year, month, 1).getDay() + 6) % 7;
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function AgendaPage() {
  const [events, setEvents]   = useState<AgendaEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [view, setView]       = useState<'calendar' | 'list'>('calendar');
  const [focusedMonth, setFocusedMonth] = useState(() => {
    const n = new Date(); return { year: n.getFullYear(), month: n.getMonth() };
  });
  const [selectedDay, setSelectedDay] = useState<number | null>(new Date().getDate());
  const [showAdd, setShowAdd] = useState(false);
  const [uid, setUid]         = useState<string | null>(null);

  // Auth uid from Supabase session (web users login via Supabase Auth on web)
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setUid(data.session?.user?.id ?? null);
    });
  }, []);

  useEffect(() => {
    if (uid) load();
  }, [uid, focusedMonth]);

  async function load() {
    setLoading(true);
    const from = new Date(focusedMonth.year, focusedMonth.month - 1, 1).toISOString();
    const to   = new Date(focusedMonth.year, focusedMonth.month + 2, 0, 23, 59, 59).toISOString();
    const { data } = await supabase
      .from('agenda_events')
      .select('*')
      .eq('uid', uid!)
      .gte('date_debut', from)
      .lte('date_debut', to)
      .order('date_debut');
    setEvents(data ?? []);
    setLoading(false);
  }

  function eventsForDay(day: number) {
    return events.filter(e => {
      const d = new Date(e.date_debut);
      return d.getFullYear() === focusedMonth.year && d.getMonth() === focusedMonth.month && d.getDate() === day;
    });
  }

  const upcoming = events.filter(e => new Date(e.date_debut) >= new Date(Date.now() - 86400000));

  // Group upcoming by date key
  const grouped: Record<string, AgendaEvent[]> = {};
  for (const e of upcoming) {
    const key = e.date_debut.slice(0, 10);
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(e);
  }
  const groupedKeys = Object.keys(grouped).sort();

  function prevMonth() {
    setFocusedMonth(m => m.month === 0 ? { year: m.year - 1, month: 11 } : { year: m.year, month: m.month - 1 });
  }
  function nextMonth() {
    setFocusedMonth(m => m.month === 11 ? { year: m.year + 1, month: 0 } : { year: m.year, month: m.month + 1 });
  }

  async function deleteEvent(id: number) {
    await supabase.from('agenda_events').delete().eq('id', id);
    load();
  }

  if (!uid) return (
    <div className="min-h-screen bg-[#F8F8F8] flex items-center justify-center">
      <p className="text-gray-400 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
        Connectez-vous pour accéder à votre agenda.
      </p>
    </div>
  );

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-3xl mx-auto flex items-center justify-between">
          <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>Mon Agenda</h1>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setView(v => v === 'calendar' ? 'list' : 'calendar')}
              className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors"
              title={view === 'calendar' ? 'Vue liste' : 'Vue calendrier'}
            >
              {view === 'calendar' ? '☰' : '📅'}
            </button>
            <button
              onClick={() => setShowAdd(true)}
              className="flex items-center gap-1 px-3 py-2 rounded-lg bg-white text-[#0C5C6C] text-sm font-bold hover:bg-gray-100 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              + Ajouter
            </button>
          </div>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : view === 'calendar' ? (
          <CalendarView
            year={focusedMonth.year}
            month={focusedMonth.month}
            events={events}
            selectedDay={selectedDay}
            onPrev={prevMonth}
            onNext={nextMonth}
            onSelectDay={setSelectedDay}
            eventsForDay={eventsForDay}
            onDelete={deleteEvent}
          />
        ) : (
          <ListView groups={grouped} keys={groupedKeys} onDelete={deleteEvent} />
        )}
      </div>

      {showAdd && (
        <AddModal uid={uid} onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load(); }} />
      )}
    </div>
  );
}

// ── CalendarView ───────────────────────────────────────────────────────────────

function CalendarView({ year, month, events, selectedDay, onPrev, onNext, onSelectDay, eventsForDay, onDelete }: {
  year: number; month: number; events: AgendaEvent[];
  selectedDay: number | null;
  onPrev: () => void; onNext: () => void;
  onSelectDay: (d: number) => void;
  eventsForDay: (d: number) => AgendaEvent[];
  onDelete: (id: number) => void;
}) {
  const WEEKDAYS = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  const monthName = new Date(year, month, 1).toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' });
  const totalDays = daysInMonth(year, month);
  const offset    = firstWeekday(year, month);
  const today     = new Date();
  const cells: (number | null)[] = [...Array(offset).fill(null), ...Array.from({ length: totalDays }, (_, i) => i + 1)];
  while (cells.length % 7 !== 0) cells.push(null);

  const dayEvts = selectedDay ? eventsForDay(selectedDay) : [];

  return (
    <div className="space-y-4">
      {/* Month nav */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <div className="flex items-center justify-between mb-4">
          <button onClick={onPrev} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-[#0C5C6C]">‹</button>
          <span className="font-bold text-base capitalize" style={{ fontFamily: 'Galey, sans-serif', color: '#1E2025' }}>
            {monthName}
          </span>
          <button onClick={onNext} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-[#0C5C6C]">›</button>
        </div>

        {/* Weekday headers */}
        <div className="grid grid-cols-7 mb-1">
          {WEEKDAYS.map((d, i) => (
            <div key={i} className="text-center text-xs font-semibold text-gray-400 py-1">{d}</div>
          ))}
        </div>

        {/* Day cells */}
        <div className="grid grid-cols-7 gap-1">
          {cells.map((day, i) => {
            if (!day) return <div key={i} />;
            const evts       = eventsForDay(day);
            const isT        = day === today.getDate() && month === today.getMonth() && year === today.getFullYear();
            const isSel      = day === selectedDay;
            return (
              <button
                key={i}
                onClick={() => onSelectDay(day)}
                className="aspect-square rounded-xl flex flex-col items-center justify-center gap-0.5 transition-colors"
                style={{
                  background: isSel ? '#0C5C6C' : isT ? '#E0F2FE' : 'white',
                  border: isT && !isSel ? '1.5px solid #0C5C6C' : '1.5px solid transparent',
                }}
              >
                <span className="text-sm font-bold" style={{ color: isSel ? 'white' : '#1E2025' }}>{day}</span>
                {evts.length > 0 && (
                  <div className="flex gap-0.5">
                    {evts.slice(0, 3).map((e, j) => (
                      <div key={j} className="w-1.5 h-1.5 rounded-full"
                        style={{ background: isSel ? 'rgba(255,255,255,0.7)' : colorFor(e) }} />
                    ))}
                  </div>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Selected day events */}
      {selectedDay && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
          <p className="font-bold text-sm text-[#0C5C6C] mb-3 capitalize" style={{ fontFamily: 'Galey, sans-serif' }}>
            {new Date(year, month, selectedDay).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
          </p>
          {dayEvts.length === 0 ? (
            <p className="text-gray-400 text-sm text-center py-4" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun événement</p>
          ) : (
            <div className="space-y-2">
              {dayEvts.map(e => <EventCard key={e.id} event={e} onDelete={onDelete} />)}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ── ListView ───────────────────────────────────────────────────────────────────

function ListView({ groups, keys, onDelete }: {
  groups: Record<string, AgendaEvent[]>; keys: string[]; onDelete: (id: number) => void;
}) {
  if (keys.length === 0) return (
    <div className="text-center py-20">
      <p className="text-4xl mb-3">📅</p>
      <p className="text-gray-400 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun événement à venir</p>
    </div>
  );

  return (
    <div className="space-y-4">
      {keys.map(key => {
        const evts = groups[key];
        const d    = new Date(key + 'T12:00:00');
        const label = isToday(key + 'T12:00:00')
          ? "Aujourd'hui"
          : d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
        return (
          <div key={key}>
            <p className="text-xs font-bold text-gray-500 mb-2 uppercase tracking-wide" style={{ fontFamily: 'Galey, sans-serif' }}>
              {label}
            </p>
            <div className="space-y-2">
              {evts.map(e => <EventCard key={e.id} event={e} onDelete={onDelete} />)}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── EventCard ─────────────────────────────────────────────────────────────────

function EventCard({ event: e, onDelete }: { event: AgendaEvent; onDelete: (id: number) => void }) {
  const color = colorFor(e);
  return (
    <div className="flex items-center gap-3 bg-white rounded-xl border border-gray-100 px-4 py-3"
      style={{ borderLeft: `4px solid ${color}` }}>
      <span className="text-xl flex-shrink-0">{TYPE_ICON[e.type] ?? '📅'}</span>
      <div className="flex-1 min-w-0">
        <p className="font-bold text-sm text-[#1E2025] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{e.titre}</p>
        <p className="text-xs text-gray-400">{fmtTime(e.date_debut)} · {TYPE_LABEL[e.type] ?? e.type}</p>
        {e.notes && <p className="text-xs text-gray-400 truncate">{e.notes}</p>}
      </div>
      <button onClick={() => onDelete(e.id)} className="text-gray-300 hover:text-red-400 transition-colors text-lg flex-shrink-0">×</button>
    </div>
  );
}

// ── AddModal ──────────────────────────────────────────────────────────────────

function AddModal({ uid, onClose, onSaved }: { uid: string; onClose: () => void; onSaved: () => void }) {
  const [titre, setTitre]   = useState('');
  const [type, setType]     = useState('autre');
  const [date, setDate]     = useState(() => new Date().toISOString().slice(0, 16));
  const [notes, setNotes]   = useState('');
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!titre.trim()) return;
    setSaving(true);
    await supabase.from('agenda_events').insert({
      uid,
      titre: titre.trim(),
      type,
      date_debut: new Date(date).toISOString(),
      notes: notes.trim() || null,
    });
    setSaving(false);
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end md:items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="font-bold text-base text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Nouvel événement</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
        </div>

        {/* Titre */}
        <input
          value={titre} onChange={e => setTitre(e.target.value)}
          placeholder="Titre *"
          className="w-full px-4 py-2.5 rounded-xl bg-gray-50 border border-gray-100 text-sm outline-none focus:border-[#0C5C6C]"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />

        {/* Type */}
        <div className="flex flex-wrap gap-2">
          {TYPES.map(t => (
            <button key={t} onClick={() => setType(t)}
              className="px-3 py-1.5 rounded-full text-xs font-semibold transition-colors"
              style={{
                background: type === t ? TYPE_COLOR[t] : `${TYPE_COLOR[t]}18`,
                color:      type === t ? 'white' : TYPE_COLOR[t],
                fontFamily: 'Galey, sans-serif',
              }}
            >
              {TYPE_ICON[t]} {TYPE_LABEL[t]}
            </button>
          ))}
        </div>

        {/* Date */}
        <input
          type="datetime-local" value={date} onChange={e => setDate(e.target.value)}
          className="w-full px-4 py-2.5 rounded-xl bg-gray-50 border border-gray-100 text-sm outline-none focus:border-[#0C5C6C]"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />

        {/* Notes */}
        <textarea
          value={notes} onChange={e => setNotes(e.target.value)}
          placeholder="Notes (optionnel)"
          rows={2}
          className="w-full px-4 py-2.5 rounded-xl bg-gray-50 border border-gray-100 text-sm outline-none focus:border-[#0C5C6C] resize-none"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />

        <button onClick={save} disabled={saving || !titre.trim()}
          className="w-full py-3 rounded-xl text-white font-bold text-sm transition-opacity disabled:opacity-50"
          style={{ background: '#0C5C6C', fontFamily: 'Galey, sans-serif' }}
        >
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}
