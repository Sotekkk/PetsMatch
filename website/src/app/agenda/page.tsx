'use client';

import { useEffect, useState, useCallback } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';

// ── Types ──────────────────────────────────────────────────────────────────────

interface RdvInfo {
  id: string;
  pro_uid: string;
  statut: string;
}

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
  rdv_id?: string | null;
  rdv?: RdvInfo | null;
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
  if (e.couleur && !e.couleur.startsWith('rdv:')) return e.couleur;
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
  return (new Date(year, month, 1).getDay() + 6) % 7;
}

// ── Modal annulation client ────────────────────────────────────────────────────

function AnnulerModal({ event, onClose, onDone }: { event: AgendaEvent; onClose: () => void; onDone: () => void }) {
  const [motif, setMotif] = useState('');
  const [saving, setSaving] = useState(false);

  async function handleAnnuler() {
    setSaving(true);
    try {
      if (event.rdv_id && event.rdv?.pro_uid) {
        await supabase.from('rdv').update({ statut: 'annule', notes_annulation: motif || null }).eq('id', event.rdv_id);
        await supabase.from('notifications').insert({
          uid: event.rdv.pro_uid,
          type: 'rdv_annule_client',
          title: 'RDV annulé par le client',
          body: `Le client a annulé le rendez-vous du ${fmtDate(event.date_debut)}.${motif ? ` Motif : ${motif}` : ''}`,
          data: { rdv_id: event.rdv_id },
          read: false,
        });
        // Supprimer l'entrée couleur côté pension
        await supabase.from('agenda_events').delete()
          .eq('uid', event.rdv.pro_uid).eq('couleur', `rdv:${event.rdv_id}`);
      }
      await supabase.from('agenda_events').delete().eq('id', event.id);
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-base text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Annuler ce rendez-vous
        </h2>
        <p className="text-sm text-gray-500">
          {event.titre}<br />
          <span className="text-[#0C5C6C] font-medium">{fmtDate(event.date_debut)} à {fmtTime(event.date_debut)}</span>
        </p>
        <textarea
          value={motif} onChange={e => setMotif(e.target.value)}
          rows={3} placeholder="Motif de l'annulation (optionnel)…"
          className="w-full px-3 py-2 border border-gray-200 rounded-xl text-sm resize-none focus:outline-none focus:border-red-400"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />
        <div className="flex gap-3 justify-end">
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50">
            Retour
          </button>
          <button onClick={handleAnnuler} disabled={saving}
            className="px-5 py-2 rounded-xl text-sm text-white bg-red-500 hover:bg-red-600 font-semibold disabled:opacity-50 transition-colors">
            {saving ? '…' : 'Annuler le RDV'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal modification client ──────────────────────────────────────────────────

function ModifierModal({ event, onClose, onDone }: { event: AgendaEvent; onClose: () => void; onDone: () => void }) {
  const [slotsLoading, setSlotsLoading] = useState(true);
  const [slotsByDate, setSlotsByDate] = useState<Record<string, number[]>>({});
  const [proUid, setProUid] = useState<string | null>(null);
  const [selDate, setSelDate] = useState('');
  const [selHour, setSelHour] = useState<number | null>(null);
  const [fallbackDate, setFallbackDate] = useState('');
  const [fallbackHour, setFallbackHour] = useState('10');
  const [fallbackMinute, setFallbackMinute] = useState('00');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!event.rdv_id) return;
    async function loadSlots() {
      const { data: rdvData } = await supabase
        .from('rdv').select('pro_uid, pro_profile_id').eq('id', event.rdv_id!).single();
      if (!rdvData) { setSlotsLoading(false); return; }
      const rd = rdvData as { pro_uid: string; pro_profile_id: string | null };
      const pUid = rd.pro_uid;
      const pProfileId = rd.pro_profile_id ?? '';
      setProUid(pUid);

      const today  = new Date().toISOString().slice(0, 10);
      const future = new Date(Date.now() + 90 * 24 * 3600 * 1000).toISOString().slice(0, 10);
      const { data: slotsData } = await supabase
        .from('creneaux_pro')
        .select('date, heure_debut')
        .eq('pro_uid', pUid)
        .eq('pro_profile_id', pProfileId)
        .eq('statut', 'disponible')
        .gte('date', today)
        .lte('date', future)
        .order('date', { ascending: true })
        .order('heure_debut', { ascending: true });

      const byDate: Record<string, number[]> = {};
      for (const s of (slotsData ?? [])) {
        const rec = s as { date: string; heure_debut: string };
        const h = parseInt(rec.heure_debut.split(':')[0], 10);
        if (!byDate[rec.date]) byDate[rec.date] = [];
        byDate[rec.date].push(h);
      }
      setSlotsByDate(byDate);
      const dates = Object.keys(byDate).sort();
      if (dates.length > 0) setSelDate(dates[0]);
      setSlotsLoading(false);
    }
    loadSlots();
  }, [event.rdv_id]);

  const hasSlots = Object.keys(slotsByDate).length > 0;
  const dates = Object.keys(slotsByDate).sort();

  async function handleModifier() {
    if (!event.rdv_id || !proUid) return;
    let chosen: Date;
    if (hasSlots) {
      if (selHour === null) return;
      chosen = new Date(`${selDate}T${String(selHour).padStart(2, '0')}:00:00`);
    } else {
      if (!fallbackDate) return;
      chosen = new Date(`${fallbackDate}T${fallbackHour.padStart(2, '0')}:${fallbackMinute}:00`);
    }
    setSaving(true);
    try {
      await supabase.from('rdv').update({
        statut: 'contre_proposition',
        date_heure: chosen.toISOString(),
      }).eq('id', event.rdv_id);

      const dateStr = chosen.toLocaleDateString('fr-FR', { day: '2-digit', month: 'long' })
        + ' à ' + chosen.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
      await supabase.from('notifications').insert({
        uid: proUid,
        type: 'rdv_contre_proposition',
        title: 'Modification demandée par le client',
        body: `Le client souhaite déplacer le RDV au ${dateStr}`,
        data: { rdv_id: event.rdv_id },
        read: false,
      });
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  const canConfirm = hasSlots ? selHour !== null : fallbackDate !== '';

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-base text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Modifier le rendez-vous
        </h2>
        <p className="text-sm text-gray-500">
          {event.titre}<br />
          <span className="text-[#0C5C6C] font-medium">{fmtDate(event.date_debut)} à {fmtTime(event.date_debut)}</span>
        </p>

        {slotsLoading ? (
          <div className="flex justify-center py-4">
            <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : hasSlots ? (
          <>
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Date</p>
              <div className="flex gap-2 overflow-x-auto pb-1">
                {dates.map(d => {
                  const dt = new Date(d + 'T12:00:00');
                  const label = dt.toLocaleDateString('fr-FR', { weekday: 'short', day: '2-digit', month: 'short' });
                  return (
                    <button key={d} onClick={() => { setSelDate(d); setSelHour(null); }}
                      className="flex-shrink-0 px-3 py-2 rounded-xl text-xs font-semibold border transition-colors"
                      style={{
                        background: selDate === d ? '#0C5C6C' : 'white',
                        color: selDate === d ? 'white' : '#1E2025',
                        borderColor: selDate === d ? '#0C5C6C' : '#e5e7eb',
                        fontFamily: 'Galey, sans-serif',
                      }}>
                      {label}
                    </button>
                  );
                })}
              </div>
            </div>
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Heure</p>
              <div className="flex flex-wrap gap-2">
                {(slotsByDate[selDate] ?? []).map(h => (
                  <button key={h} onClick={() => setSelHour(h)}
                    className="px-4 py-2 rounded-xl text-sm font-semibold border transition-colors"
                    style={{
                      background: selHour === h ? '#0C5C6C' : 'white',
                      color: selHour === h ? 'white' : '#1E2025',
                      borderColor: selHour === h ? '#0C5C6C' : '#e5e7eb',
                      fontFamily: 'Galey, sans-serif',
                    }}>
                    {String(h).padStart(2, '0')}h00
                  </button>
                ))}
              </div>
            </div>
          </>
        ) : (
          <>
            <p className="text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
              La pension n&apos;a pas configuré de créneaux. Choisissez une date et heure souhaitées.
            </p>
            <div>
              <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</label>
              <input type="date" value={fallbackDate} onChange={e => setFallbackDate(e.target.value)}
                min={new Date().toISOString().slice(0, 10)}
                className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]"
              />
            </div>
            <div>
              <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Heure</label>
              <div className="flex gap-2 mt-1">
                <select value={fallbackHour} onChange={e => setFallbackHour(e.target.value)}
                  className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]">
                  {Array.from({ length: 14 }, (_, i) => String(i + 7).padStart(2, '0')).map(h => (
                    <option key={h} value={h}>{h}h</option>
                  ))}
                </select>
                <select value={fallbackMinute} onChange={e => setFallbackMinute(e.target.value)}
                  className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]">
                  {['00', '15', '30', '45'].map(m => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
            </div>
          </>
        )}

        <div className="flex gap-3 justify-end pt-1">
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50">
            Retour
          </button>
          <button onClick={handleModifier} disabled={saving || slotsLoading || !canConfirm}
            className="px-5 py-2 rounded-xl text-sm text-white font-semibold disabled:opacity-50 transition-colors"
            style={{ background: '#0C5C6C', fontFamily: 'Galey, sans-serif' }}>
            {saving ? '…' : 'Proposer ce créneau'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function AgendaPage() {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [events, setEvents]   = useState<AgendaEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [pendingRdvs, setPendingRdvs] = useState<{id:string;date_debut:string;motif:string|null;client_uid:string;animal_id:number|null}[]>([]);
  const [view, setView]       = useState<'calendar' | 'list'>('calendar');
  const [focusedMonth, setFocusedMonth] = useState(() => {
    const n = new Date(); return { year: n.getFullYear(), month: n.getMonth() };
  });
  const [selectedDay, setSelectedDay] = useState<number | null>(new Date().getDate());
  const [showAdd, setShowAdd]         = useState(false);
  const [modalAnnuler, setModalAnnuler] = useState<AgendaEvent | null>(null);
  const [modalModifier, setModalModifier] = useState<AgendaEvent | null>(null);

  const uid = user?.uid ?? null;

  const load = useCallback(async () => {
    if (!uid) return;
    setLoading(true);
    const from = new Date(focusedMonth.year, focusedMonth.month - 1, 1).toISOString();
    const to   = new Date(focusedMonth.year, focusedMonth.month + 2, 0, 23, 59, 59).toISOString();

    // Filtre pro_profile_id : profil secondaire → filtre exact ; profil principal → null ou vide
    let q = supabase.from('agenda_events').select('*').eq('uid', uid)
      .gte('date_debut', from).lte('date_debut', to).order('date_debut');
    if (activeProfileId) {
      q = q.eq('pro_profile_id', activeProfileId);
    } else {
      q = q.or('pro_profile_id.is.null,pro_profile_id.eq.');
    }
    const { data } = await q;

    // Si profil pro secondaire actif : charger aussi les RDV en attente
    if (activeProfileId && uid) {
      const { data: rdvData } = await supabase.from('rdv')
        .select('id, date_debut, motif, client_uid, animal_id')
        .eq('pro_uid', uid).eq('pro_profile_id', activeProfileId)
        .eq('statut', 'en_attente').order('date_debut');
      setPendingRdvs((rdvData ?? []) as typeof pendingRdvs);
    } else {
      setPendingRdvs([]);
    }

    const list = (data ?? []) as AgendaEvent[];

    // Enrichir avec infos rdv
    const rdvIds = list.map(e => e.rdv_id).filter(Boolean) as string[];
    if (rdvIds.length > 0) {
      const { data: rdvsData } = await supabase
        .from('rdv').select('id, pro_uid, statut').in('id', rdvIds);
      const rdvMap: Record<string, RdvInfo> = {};
      for (const r of (rdvsData ?? [])) {
        const rec = r as RdvInfo;
        rdvMap[rec.id] = rec;
      }
      setEvents(list.map(e => ({ ...e, rdv: e.rdv_id ? rdvMap[e.rdv_id] ?? null : null })));
    } else {
      setEvents(list);
    }
    setLoading(false);
  }, [uid, focusedMonth, activeProfileId]);

  useEffect(() => { if (uid) load(); }, [uid, load]);

  function eventsForDay(day: number) {
    return events.filter(e => {
      const d = new Date(e.date_debut);
      return d.getFullYear() === focusedMonth.year && d.getMonth() === focusedMonth.month && d.getDate() === day;
    });
  }

  const upcoming = events.filter(e => new Date(e.date_debut) >= new Date(Date.now() - 86400000));
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
    setEvents(prev => prev.filter(e => e.id !== id));
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
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-3xl mx-auto flex items-center justify-between">
          <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>Mon Agenda</h1>
          <div className="flex items-center gap-2">
            <button onClick={() => setView(v => v === 'calendar' ? 'list' : 'calendar')}
              className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors"
              title={view === 'calendar' ? 'Vue liste' : 'Vue calendrier'}>
              {view === 'calendar' ? '☰' : '📅'}
            </button>
            <button onClick={() => setShowAdd(true)}
              className="flex items-center gap-1 px-3 py-2 rounded-lg bg-white text-[#0C5C6C] text-sm font-bold hover:bg-gray-100 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              + Ajouter
            </button>
          </div>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* RDV en attente — visible uniquement pour un profil pro secondaire */}
        {activeProfileId && pendingRdvs.length > 0 && (
          <div className="mb-6">
            <p className="text-xs font-bold text-gray-500 uppercase tracking-wide mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              RDV en attente de confirmation ({pendingRdvs.length})
            </p>
            <div className="space-y-2">
              {pendingRdvs.map(rdv => (
                <PendingRdvCard key={rdv.id} rdv={rdv} proUid={uid!} proProfileId={activeProfileId} onDone={load} />
              ))}
            </div>
          </div>
        )}

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
            onAnnuler={setModalAnnuler}
            onModifier={setModalModifier}
          />
        ) : (
          <ListView groups={grouped} keys={groupedKeys} onDelete={deleteEvent}
            onAnnuler={setModalAnnuler} onModifier={setModalModifier} />
        )}
      </div>

      {showAdd && uid && (
        <AddModal uid={uid} onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load(); }} />
      )}

      {modalAnnuler && (
        <AnnulerModal event={modalAnnuler} onClose={() => setModalAnnuler(null)}
          onDone={() => { setModalAnnuler(null); load(); }} />
      )}
      {modalModifier && (
        <ModifierModal event={modalModifier} onClose={() => setModalModifier(null)}
          onDone={() => { setModalModifier(null); load(); }} />
      )}
    </div>
  );
}

// ── PendingRdvCard ─────────────────────────────────────────────────────────────

function PendingRdvCard({ rdv, proUid, proProfileId, onDone }: {
  rdv: { id: string; date_debut: string; motif: string | null; client_uid: string; animal_id: number | null };
  proUid: string; proProfileId: string;
  onDone: () => void;
}) {
  const [saving, setSaving] = useState(false);
  const [clientName, setClientName] = useState('');

  useEffect(() => {
    supabase.from('users').select('nom, prenom').eq('uid', rdv.client_uid).single()
      .then(({ data }) => {
        if (data) {
          const d = data as { nom: string; prenom: string };
          setClientName([d.prenom, d.nom].filter(Boolean).join(' '));
        }
      });
  }, [rdv.client_uid]);

  async function accept() {
    setSaving(true);
    await supabase.from('rdv').update({ statut: 'confirme' }).eq('id', rdv.id);
    await supabase.from('agenda_events').insert({
      uid: proUid,
      titre: `RDV ${clientName || 'Client'}${rdv.motif ? ` — ${rdv.motif}` : ''}`,
      type: 'rdv',
      date_debut: rdv.date_debut,
      rdv_id: rdv.id,
      pro_profile_id: proProfileId,
    });
    await supabase.from('notifications').insert({
      uid: rdv.client_uid,
      type: 'rdv_confirme',
      title: 'RDV confirmé',
      body: `Votre rendez-vous du ${fmtDate(rdv.date_debut)} à ${fmtTime(rdv.date_debut)} a été confirmé.`,
      data: { rdv_id: rdv.id },
      read: false,
    });
    setSaving(false);
    onDone();
  }

  async function reject() {
    setSaving(true);
    await supabase.from('rdv').update({ statut: 'refuse' }).eq('id', rdv.id);
    await supabase.from('notifications').insert({
      uid: rdv.client_uid,
      type: 'rdv_refuse',
      title: 'RDV refusé',
      body: `Votre demande de rendez-vous du ${fmtDate(rdv.date_debut)} a été refusée.`,
      data: { rdv_id: rdv.id },
      read: false,
    });
    setSaving(false);
    onDone();
  }

  return (
    <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 space-y-2">
      <div className="flex items-center gap-3">
        <span className="text-xl">🕐</span>
        <div className="flex-1 min-w-0">
          <p className="font-bold text-sm text-[#1E2025] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
            {clientName || 'Chargement…'}
          </p>
          <p className="text-xs text-gray-500">
            {fmtDate(rdv.date_debut)} à {fmtTime(rdv.date_debut)}
            {rdv.motif && <span> · {rdv.motif}</span>}
          </p>
        </div>
        <span className="text-[10px] font-bold bg-amber-200 text-amber-700 px-2 py-0.5 rounded-full flex-shrink-0">
          En attente
        </span>
      </div>
      <div className="flex gap-2">
        <button onClick={accept} disabled={saving}
          className="flex-1 text-xs font-semibold py-1.5 rounded-lg bg-[#0C5C6C] text-white hover:bg-[#0a4a5a] disabled:opacity-50 transition-colors"
          style={{ fontFamily: 'Galey, sans-serif' }}>
          ✓ Confirmer
        </button>
        <button onClick={reject} disabled={saving}
          className="flex-1 text-xs font-semibold py-1.5 rounded-lg border border-red-200 text-red-500 hover:bg-red-50 disabled:opacity-50 transition-colors"
          style={{ fontFamily: 'Galey, sans-serif' }}>
          ✗ Refuser
        </button>
      </div>
    </div>
  );
}

// ── CalendarView ───────────────────────────────────────────────────────────────

function CalendarView({ year, month, events, selectedDay, onPrev, onNext, onSelectDay, eventsForDay, onDelete, onAnnuler, onModifier }: {
  year: number; month: number; events: AgendaEvent[];
  selectedDay: number | null;
  onPrev: () => void; onNext: () => void;
  onSelectDay: (d: number) => void;
  eventsForDay: (d: number) => AgendaEvent[];
  onDelete: (id: number) => void;
  onAnnuler: (e: AgendaEvent) => void;
  onModifier: (e: AgendaEvent) => void;
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
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <div className="flex items-center justify-between mb-4">
          <button onClick={onPrev} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-[#0C5C6C]">‹</button>
          <span className="font-bold text-base capitalize" style={{ fontFamily: 'Galey, sans-serif', color: '#1E2025' }}>
            {monthName}
          </span>
          <button onClick={onNext} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-[#0C5C6C]">›</button>
        </div>
        <div className="grid grid-cols-7 mb-1">
          {WEEKDAYS.map((d, i) => (
            <div key={i} className="text-center text-xs font-semibold text-gray-400 py-1">{d}</div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {cells.map((day, i) => {
            if (!day) return <div key={i} />;
            const evts  = eventsForDay(day);
            const isT   = day === today.getDate() && month === today.getMonth() && year === today.getFullYear();
            const isSel = day === selectedDay;
            return (
              <button key={i} onClick={() => onSelectDay(day)}
                className="aspect-square rounded-xl flex flex-col items-center justify-center gap-0.5 transition-colors"
                style={{
                  background: isSel ? '#0C5C6C' : isT ? '#E0F2FE' : 'white',
                  border: isT && !isSel ? '1.5px solid #0C5C6C' : '1.5px solid transparent',
                }}>
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

      {selectedDay && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
          <p className="font-bold text-sm text-[#0C5C6C] mb-3 capitalize" style={{ fontFamily: 'Galey, sans-serif' }}>
            {new Date(year, month, selectedDay).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
          </p>
          {dayEvts.length === 0 ? (
            <p className="text-gray-400 text-sm text-center py-4" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun événement</p>
          ) : (
            <div className="space-y-2">
              {dayEvts.map(e => <EventCard key={e.id} event={e} onDelete={onDelete} onAnnuler={onAnnuler} onModifier={onModifier} />)}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ── ListView ───────────────────────────────────────────────────────────────────

function ListView({ groups, keys, onDelete, onAnnuler, onModifier }: {
  groups: Record<string, AgendaEvent[]>; keys: string[];
  onDelete: (id: number) => void;
  onAnnuler: (e: AgendaEvent) => void;
  onModifier: (e: AgendaEvent) => void;
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
              {evts.map(e => <EventCard key={e.id} event={e} onDelete={onDelete} onAnnuler={onAnnuler} onModifier={onModifier} />)}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── EventCard ─────────────────────────────────────────────────────────────────

function EventCard({ event: e, onDelete, onAnnuler, onModifier }: {
  event: AgendaEvent;
  onDelete: (id: number) => void;
  onAnnuler: (e: AgendaEvent) => void;
  onModifier: (e: AgendaEvent) => void;
}) {
  const color  = colorFor(e);
  const isRdv  = !!e.rdv_id;
  const plus24h = isRdv && new Date(e.date_debut).getTime() - Date.now() > 24 * 3600 * 1000;

  return (
    <div className="bg-white rounded-xl border border-gray-100 px-4 py-3 space-y-2"
      style={{ borderLeft: `4px solid ${color}` }}>
      <div className="flex items-center gap-3">
        <span className="text-xl flex-shrink-0">{TYPE_ICON[e.type] ?? '📅'}</span>
        <div className="flex-1 min-w-0">
          <p className="font-bold text-sm text-[#1E2025] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{e.titre}</p>
          <p className="text-xs text-gray-400">{fmtTime(e.date_debut)} · {TYPE_LABEL[e.type] ?? e.type}</p>
          {e.notes && <p className="text-xs text-gray-400 truncate">{e.notes}</p>}
        </div>
        {!isRdv && (
          <button onClick={() => onDelete(e.id)} className="text-gray-300 hover:text-red-400 transition-colors text-lg flex-shrink-0">×</button>
        )}
      </div>

      {isRdv && plus24h && (
        <div className="flex gap-2">
          <button onClick={() => onModifier(e)}
            className="flex-1 text-xs font-semibold py-1.5 rounded-lg border border-[#0C5C6C]/20 hover:border-[#0C5C6C] text-[#0C5C6C] transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            ✏️ Modifier
          </button>
          <button onClick={() => onAnnuler(e)}
            className="flex-1 text-xs font-semibold py-1.5 rounded-lg border border-red-100 hover:border-red-300 text-red-500 transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            Annuler
          </button>
        </div>
      )}
      {isRdv && !plus24h && (
        <p className="text-[10px] text-gray-400 flex items-center gap-1">
          <span>🔒</span> Annulation impossible moins de 24h avant
        </p>
      )}
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
        <input
          value={titre} onChange={e => setTitre(e.target.value)}
          placeholder="Titre *"
          className="w-full px-4 py-2.5 rounded-xl bg-gray-50 border border-gray-100 text-sm outline-none focus:border-[#0C5C6C]"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />
        <div className="flex flex-wrap gap-2">
          {TYPES.map(t => (
            <button key={t} onClick={() => setType(t)}
              className="px-3 py-1.5 rounded-full text-xs font-semibold transition-colors"
              style={{
                background: type === t ? TYPE_COLOR[t] : `${TYPE_COLOR[t]}18`,
                color: type === t ? 'white' : TYPE_COLOR[t],
                fontFamily: 'Galey, sans-serif',
              }}>
              {TYPE_ICON[t]} {TYPE_LABEL[t]}
            </button>
          ))}
        </div>
        <input
          type="datetime-local" value={date} onChange={e => setDate(e.target.value)}
          className="w-full px-4 py-2.5 rounded-xl bg-gray-50 border border-gray-100 text-sm outline-none focus:border-[#0C5C6C]"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />
        <textarea
          value={notes} onChange={e => setNotes(e.target.value)}
          placeholder="Notes (optionnel)"
          rows={2}
          className="w-full px-4 py-2.5 rounded-xl bg-gray-50 border border-gray-100 text-sm outline-none focus:border-[#0C5C6C] resize-none"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />
        <button onClick={save} disabled={saving || !titre.trim()}
          className="w-full py-3 rounded-xl text-white font-bold text-sm transition-opacity disabled:opacity-50"
          style={{ background: '#0C5C6C', fontFamily: 'Galey, sans-serif' }}>
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}
