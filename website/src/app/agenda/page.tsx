'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';

// ── Types ──────────────────────────────────────────────────────────────────────

interface RdvInfo {
  id: string;
  pro_uid: string;
  statut: string;
  animal_id?: string | number | null;
  duree_minutes?: number | null;
  motif?: string | null;
  client_uid?: string | null;
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
  animal_id?: string | number | null;
  rdv_id?: string | null;
  rdv?: RdvInfo | null;
  duree_minutes?: number | null;
}

interface Task {
  id: string;
  titre: string;
  date: string;
  statut: string;
  uid_eleveur: string;
  assigne_a: string | null;
  responsable_nom?: string;
  _source: 'manuel' | 'protocole';
  type_acte?: string;
  animal_nom?: string;
  etape_id?: string | null;
}

interface TaskGroupe {
  key: string;
  label: string;
  typeActe?: string;
  tasks: Task[];
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
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [events, setEvents]   = useState<AgendaEvent[]>([]);
  const [tasks, setTasks]     = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [pendingRdvs, setPendingRdvs] = useState<{id:string;date_debut:string;motif:string|null;client_uid:string;animal_id:number|null}[]>([]);
  const [view, setView]       = useState<'calendar' | 'day' | 'list'>('calendar');
  const [focusedMonth, setFocusedMonth] = useState(() => {
    const n = new Date(); return { year: n.getFullYear(), month: n.getMonth() };
  });
  const [selectedDay, setSelectedDay] = useState<number | null>(new Date().getDate());
  const [selectedDate, setSelectedDate] = useState<Date>(() => new Date());
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
        .from('rdv').select('id, pro_uid, statut, animal_id, duree_minutes, motif, client_uid').in('id', rdvIds);
      const rdvMap: Record<string, RdvInfo> = {};
      for (const r of (rdvsData ?? [])) {
        const rec = r as RdvInfo;
        rdvMap[rec.id] = rec;
      }
      setEvents(list.map(e => ({ ...e, rdv: e.rdv_id ? rdvMap[e.rdv_id] ?? null : null })));
    } else {
      setEvents(list);
    }

    // Charger les tâches du mois — vue particulier : uniquement les tâches assignées à l'utilisateur
    const taskFrom = new Date(focusedMonth.year, focusedMonth.month - 1, 1).toISOString().slice(0, 10);
    const taskTo   = new Date(focusedMonth.year, focusedMonth.month + 2, 0).toISOString().slice(0, 10);

    const { data: manuelData } = await supabase
      .from('taches_elevage')
      .select('id,titre,date,statut,uid_eleveur,assigne_a')
      .eq('assigne_a', uid)
      .gte('date', taskFrom).lte('date', taskTo);
    const manuelTasks: Task[] = ((manuelData ?? []) as { id: string; titre: string; date: string; statut: string; uid_eleveur: string; assigne_a: string | null }[]).map(t => ({ ...t, _source: 'manuel' as const, etape_id: null }));

    const [p2Res] = await Promise.all([
      supabase.from('plan_taches').select('id,label,date_prevue,statut,assigned_to,uid_eleveur,type_acte,animal_nom,etape_id').eq('assigned_to', uid).gte('date_prevue', taskFrom).lte('date_prevue', taskTo),
    ]);
    const seenProto = new Set<string>();
    const protoTasks: Task[] = [];
    for (const t of [...(p2Res.data ?? [])]) {
      const pt = t as { id: string; label: string; date_prevue: string; statut: string; assigned_to: string | null; uid_eleveur: string; type_acte?: string; animal_nom?: string; etape_id?: string | null };
      if (seenProto.has(pt.id)) continue;
      seenProto.add(pt.id);
      protoTasks.push({ id: pt.id, titre: pt.label, date: (pt.date_prevue ?? '').split('T')[0], statut: pt.statut, uid_eleveur: pt.uid_eleveur, assigne_a: pt.assigned_to, _source: 'protocole', type_acte: pt.type_acte, animal_nom: pt.animal_nom, etape_id: pt.etape_id ?? null });
    }

    const allTasks = [...manuelTasks, ...protoTasks];

    // Résoudre les noms des responsables
    const taskUids = new Set<string>();
    for (const t of allTasks) {
      if (t.assigne_a) taskUids.add(t.assigne_a);
      if (t.uid_eleveur) taskUids.add(t.uid_eleveur);
    }
    if (taskUids.size > 0) {
      const { data: usersData } = await supabase
        .from('users')
        .select('uid,firstname,lastname,name_elevage,is_elevage')
        .in('uid', [...taskUids]);
      const nomMap: Record<string, string> = {};
      for (const u of (usersData ?? []) as { uid: string; firstname?: string; lastname?: string; name_elevage?: string; is_elevage?: boolean }[]) {
        const nom = (u.is_elevage && u.name_elevage)
          ? u.name_elevage
          : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
        if (nom) nomMap[u.uid] = nom;
      }
      setTasks(allTasks.map(t => ({ ...t, responsable_nom: nomMap[t.assigne_a ?? t.uid_eleveur ?? ''] ?? undefined })));
    } else {
      setTasks(allTasks);
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

  function eventsForDate(date: Date) {
    return events.filter(e => {
      const d = new Date(e.date_debut);
      return d.getFullYear() === date.getFullYear() && d.getMonth() === date.getMonth() && d.getDate() === date.getDate();
    }).sort((a, b) => new Date(a.date_debut).getTime() - new Date(b.date_debut).getTime());
  }

  function tasksForDate(date: Date) {
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    return tasks.filter(t => (t.date ?? '').startsWith(key));
  }

  function tasksForDay(day: number) {
    const key = `${focusedMonth.year}-${String(focusedMonth.month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    return tasks.filter(t => (t.date ?? '').startsWith(key));
  }

  async function toggleTask(t: Task) {
    if (t._source === 'protocole') {
      const newStatut = t.statut === 'fait' ? 'en_attente' : 'fait';
      setTasks(prev => prev.map(x => x.id === t.id ? { ...x, statut: newStatut } : x));
      await supabase.from('plan_taches').update({ statut: newStatut }).eq('id', t.id);
    } else {
      const newStatut = t.statut === 'fait' ? 'a_faire' : 'fait';
      setTasks(prev => prev.map(x => x.id === t.id ? { ...x, statut: newStatut } : x));
      await supabase.from('taches_elevage').update({ statut: newStatut }).eq('id', t.id);
    }
  }

  function navigateToAnimal(animalId: string | number | null | undefined) {
    if (!animalId) return;
    router.push(`/mes-patients/${animalId}`);
  }

  function navigateDay(dir: 'prev' | 'next') {
    setSelectedDate(d => {
      const next = new Date(d);
      next.setDate(next.getDate() + (dir === 'next' ? 1 : -1));
      setFocusedMonth({ year: next.getFullYear(), month: next.getMonth() });
      return next;
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
            <div className="flex rounded-lg bg-white/10 overflow-hidden text-xs font-semibold">
              {([['calendar', 'Mois'], ['day', 'Jour'], ['list', 'Liste']] as const).map(([v, label]) => (
                <button key={v} onClick={() => { setView(v); if (v === 'day') setSelectedDate(new Date()); }}
                  className="px-3 py-1.5 transition-colors"
                  style={{ background: view === v ? 'rgba(255,255,255,0.25)' : 'transparent' }}>
                  {label}
                </button>
              ))}
            </div>
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
            tasks={tasks}
            selectedDay={selectedDay}
            onPrev={prevMonth}
            onNext={nextMonth}
            onSelectDay={setSelectedDay}
            eventsForDay={eventsForDay}
            tasksForDay={tasksForDay}
            onDelete={deleteEvent}
            onAnnuler={setModalAnnuler}
            onModifier={setModalModifier}
            onNavigateToAnimal={navigateToAnimal}
            onToggleTask={toggleTask}
            uid={uid ?? ''}
            onUpdated={load}
          />
        ) : view === 'day' ? (
          <DayView
            date={selectedDate}
            events={eventsForDate(selectedDate)}
            tasks={tasksForDate(selectedDate)}
            onNavigate={navigateDay}
            onDelete={deleteEvent}
            onAnnuler={setModalAnnuler}
            onModifier={setModalModifier}
            onNavigateToAnimal={navigateToAnimal}
            onToggleTask={toggleTask}
            uid={uid ?? ''}
            onUpdated={load}
          />
        ) : (
          <ListView groups={grouped} keys={groupedKeys} onDelete={deleteEvent}
            onAnnuler={setModalAnnuler} onModifier={setModalModifier} onNavigateToAnimal={navigateToAnimal} />
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

// ── Helpers tâches ─────────────────────────────────────────────────────────────

function protoEmoji(typeActe?: string) {
  const m: Record<string, string> = { vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️', traitement: '🩺', visite: '🏥', alimentaire: '🍽️', toilettage: '✂️', nettoyage: '🧴', promenade: '🦮', socialisation: '🦮' };
  return m[typeActe ?? ''] ?? '📋';
}

function groupProtocole(tasks: Task[]): TaskGroupe[] {
  const map = new Map<string, Task[]>();
  for (const t of tasks) {
    const key = t.etape_id ?? `solo_${t.id}`;
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(t);
  }
  return [...map.entries()].map(([key, ts]) => ({ key, label: ts[0].titre, typeActe: ts[0].type_acte, tasks: ts }));
}

// ── ProtoDetailModal ────────────────────────────────────────────────────────────

function ProtoDetailModal({ groupe, onClose, onUpdated }: { groupe: TaskGroupe; onClose: () => void; onUpdated: () => void }) {
  const [items, setItems] = useState(groupe.tasks);
  const total = items.length;
  const done  = items.filter(t => t.statut === 'fait').length;
  const pct   = total > 0 ? done / total : 0;

  async function toggle(idx: number) {
    const t = items[idx];
    const newStatut = t.statut === 'fait' ? 'en_attente' : 'fait';
    await supabase.from('plan_taches').update({ statut: newStatut }).eq('id', t.id);
    setItems(prev => prev.map((x, i) => i === idx ? { ...x, statut: newStatut } : x));
    onUpdated();
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end justify-center" onClick={onClose}>
      <div className="bg-white rounded-t-3xl w-full max-w-md pb-8" onClick={e => e.stopPropagation()}>
        <div className="flex justify-center pt-3 pb-1"><div className="w-10 h-1 rounded-full bg-gray-300" /></div>
        <div className="px-5 pt-2 pb-3">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xl">{protoEmoji(groupe.typeActe)}</span>
            <p className="flex-1 font-bold text-[#0C5C6C] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>{groupe.label}</p>
            <span className="text-sm font-bold text-[#0C5C6C]">{done}/{total}</span>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl ml-1">×</button>
          </div>
          <div className="h-1.5 rounded-full bg-[#0C5C6C]/12 overflow-hidden">
            <div className="h-full rounded-full transition-all" style={{ width: `${pct * 100}%`, background: done === total ? '#d1d5db' : '#0C5C6C' }} />
          </div>
          <p className="text-[10px] text-right text-gray-400 mt-0.5">{Math.round(pct * 100)} %</p>
        </div>
        <div className="border-t border-gray-100" />
        <div className="px-2 pt-2 space-y-0.5 max-h-72 overflow-y-auto">
          {items.map((t, idx) => {
            const isDone = t.statut === 'fait';
            const nom = t.animal_nom || `Animal #${idx + 1}`;
            return (
              <button key={t.id} onClick={() => toggle(idx)}
                className="w-full flex items-center gap-3 py-2.5 px-3 rounded-xl hover:bg-gray-50 transition-colors text-left">
                <span className={`w-5 h-5 rounded-full border-2 flex-shrink-0 flex items-center justify-center transition-colors ${isDone ? 'bg-[#0C5C6C] border-[#0C5C6C]' : 'border-gray-300'}`}>
                  {isDone && <svg className="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" /></svg>}
                </span>
                <span className="text-sm">🐾</span>
                <span className={`flex-1 text-sm ${isDone ? 'line-through text-gray-400' : 'text-[#1E2025] font-semibold'}`} style={{ fontFamily: 'Galey, sans-serif' }}>{nom}</span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ── ReporterModal ───────────────────────────────────────────────────────────────

function ReporterModal({ task, onClose, onReport }: { task: Task; onClose: () => void; onReport: (date: string) => Promise<void> }) {
  const [date, setDate] = useState(() => { const d = new Date(); d.setDate(d.getDate() + 1); return d.toISOString().slice(0, 10); });
  const [saving, setSaving] = useState(false);
  const minDate = new Date().toISOString().slice(0, 10);

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-xs p-5 space-y-4" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <p className="font-bold text-sm text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Reporter la tâche</p>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
        </div>
        <p className="text-xs text-gray-500 truncate">{task.titre}</p>
        <input type="date" value={date} min={minDate} onChange={e => setDate(e.target.value)}
          className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30" />
        <div className="flex gap-2">
          <button onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 text-sm font-semibold py-2.5 rounded-xl hover:bg-gray-50">Annuler</button>
          <button disabled={saving || !date} onClick={async () => { setSaving(true); await onReport(date); }}
            className="flex-1 bg-[#0C5C6C] text-white text-sm font-semibold py-2.5 rounded-xl hover:bg-[#094F5D] disabled:opacity-50">
            {saving ? '…' : 'Reporter'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── AssignerModal ───────────────────────────────────────────────────────────────

function AssignerModal({ task, uid, onClose, onAssign }: { task: Task; uid: string; onClose: () => void; onAssign: (uid: string | null) => Promise<void> }) {
  const [members, setMembers] = useState<{ uid: string; nom: string }[]>([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    async function load() {
      const { data: emps } = await supabase.from('employes').select('uid_employe').eq('uid_eleveur', uid).eq('actif', true);
      if (!emps?.length) return;
      const uids = (emps as { uid_employe: string }[]).map(e => e.uid_employe);
      const { data: users } = await supabase.from('users').select('uid,firstname,lastname,name_elevage,is_elevage').in('uid', uids);
      setMembers(((users ?? []) as { uid: string; firstname?: string; lastname?: string; name_elevage?: string; is_elevage?: boolean }[]).map(u => ({
        uid: u.uid,
        nom: (u.is_elevage && u.name_elevage) ? u.name_elevage : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim(),
      })));
    }
    load();
  }, [uid]);

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-xs p-5 space-y-3" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <p className="font-bold text-sm text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Assigner à</p>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
        </div>
        <p className="text-xs text-gray-500 truncate">{task.titre}</p>
        {members.length === 0 ? (
          <p className="text-xs text-gray-400 text-center py-4">Aucun employé dans votre équipe</p>
        ) : (
          <div className="space-y-1 max-h-48 overflow-y-auto">
            <button disabled={saving} onClick={async () => { setSaving(true); await onAssign(null); }}
              className="w-full text-left px-3 py-2.5 rounded-xl text-sm text-gray-500 hover:bg-gray-50 border border-gray-100 disabled:opacity-50">
              — Retirer l&apos;assignation
            </button>
            {members.map(m => (
              <button key={m.uid} disabled={saving} onClick={async () => { setSaving(true); await onAssign(m.uid); }}
                className="w-full text-left px-3 py-2.5 rounded-xl text-sm font-semibold text-[#1E2025] hover:bg-[#EDF6F7] border border-gray-100 disabled:opacity-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                👤 {m.nom}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ── ProtoCard ───────────────────────────────────────────────────────────────────

function ProtoCard({ groupe, effectuee = false, onOpenDetail, onReport }: {
  groupe: TaskGroupe;
  effectuee?: boolean;
  onOpenDetail: (g: TaskGroupe) => void;
  onReport: (t: Task) => void;
}) {
  const total = groupe.tasks.length;
  const done  = groupe.tasks.filter(t => t.statut === 'fait').length;
  const pct   = total > 0 ? done / total : 0;
  const allDone = done === total;
  return (
    <div onClick={() => !effectuee && onOpenDetail(groupe)}
      className={`mb-2 px-3 py-2.5 rounded-xl border transition-colors ${allDone ? 'bg-gray-50 border-gray-100' : 'bg-white border-[#0C5C6C]/25 cursor-pointer hover:border-[#0C5C6C]'}`}>
      <div className="flex items-center gap-2">
        <span className="text-sm">{protoEmoji(groupe.typeActe)}</span>
        <span className={`flex-1 text-sm font-semibold truncate ${allDone ? 'line-through text-gray-400' : 'text-[#1E2025]'}`} style={{ fontFamily: 'Galey, sans-serif' }}>
          {groupe.label}
        </span>
        {!effectuee && <>
          <span className={`text-xs font-bold ${allDone ? 'text-gray-400' : 'text-[#0C5C6C]'}`}>{done}/{total}</span>
          <button onClick={e => { e.stopPropagation(); onReport(groupe.tasks[0]); }}
            title="Reporter" className="text-gray-300 hover:text-[#0C5C6C] px-1 py-0.5 rounded hover:bg-[#0C5C6C]/10 text-sm transition-colors ml-1">↷</button>
          <svg className="w-4 h-4 text-gray-300 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" /></svg>
        </>}
      </div>
      {total > 1 && !effectuee && (
        <div className="mt-2 h-1.5 rounded-full bg-[#0C5C6C]/12 overflow-hidden">
          <div className="h-full rounded-full transition-all" style={{ width: `${pct * 100}%`, background: allDone ? '#d1d5db' : '#0C5C6C' }} />
        </div>
      )}
    </div>
  );
}

// ── ManuelRow ───────────────────────────────────────────────────────────────────

function ManuelRow({ t, onToggle, onReport, onAssign }: {
  t: Task;
  onToggle: (t: Task) => void;
  onReport: (t: Task) => void;
  onAssign: (t: Task) => void;
}) {
  const done = t.statut === 'fait';
  return (
    <div className="mb-1.5 flex items-center gap-2">
      <button onClick={() => onToggle(t)}
        className={`w-5 h-5 rounded-full border-2 flex-shrink-0 flex items-center justify-center transition-colors ${done ? 'bg-[#6E9E57] border-[#6E9E57]' : 'border-gray-300 hover:border-[#6E9E57]'}`}>
        {done && <svg className="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" /></svg>}
      </button>
      <div className="flex-1 min-w-0">
        <span className={`block text-sm truncate ${done ? 'line-through text-gray-400' : 'text-[#1E2025]'}`} style={{ fontFamily: 'Galey, sans-serif' }}>{t.titre}</span>
        {t.responsable_nom && <span className="block text-[11px] text-gray-400">{done ? `Fait par : ${t.responsable_nom}` : `👤 ${t.responsable_nom}`}</span>}
      </div>
      {!done && (
        <div className="flex gap-0.5 flex-shrink-0">
          <button onClick={() => onReport(t)} title="Reporter" className="text-[11px] text-gray-400 hover:text-[#0C5C6C] px-1.5 py-1 rounded hover:bg-[#0C5C6C]/10 transition-colors">↷</button>
          <button onClick={() => onAssign(t)} title="Assigner" className="text-[11px] text-gray-400 hover:text-[#0C5C6C] px-1.5 py-1 rounded hover:bg-[#0C5C6C]/10 transition-colors">👤</button>
        </div>
      )}
    </div>
  );
}

// ── DayTasksSection ─────────────────────────────────────────────────────────────

function DayTasksSection({ tasks, uid, onToggle, onUpdated }: { tasks: Task[]; uid: string; onToggle: (t: Task) => void; onUpdated: () => void }) {
  const [protoDetail, setProtoDetail] = useState<TaskGroupe | null>(null);
  const [reportingTask, setReportingTask] = useState<Task | null>(null);
  const [assigningTask, setAssigningTask] = useState<Task | null>(null);

  const manuel = tasks.filter(t => t._source !== 'protocole');
  const proto  = tasks.filter(t => t._source === 'protocole');
  const protoGroups = groupProtocole(proto);

  const manuelEnCours   = manuel.filter(t => t.statut !== 'fait');
  const manuelEffectues = manuel.filter(t => t.statut === 'fait');
  const protoEnCours    = protoGroups.filter(g => !g.tasks.every(t => t.statut === 'fait'));
  const protoEffectues  = protoGroups.filter(g => g.tasks.every(t => t.statut === 'fait'));
  const totalItems = manuel.length + protoGroups.length;
  const doneItems  = manuelEffectues.length + protoEffectues.length;

  async function doReport(task: Task, newDate: string) {
    if (task._source === 'protocole') {
      await supabase.from('plan_taches').update({ date_prevue: `${newDate}T00:00:00` }).eq('id', task.id);
    } else {
      await supabase.from('taches_elevage').update({ date: newDate }).eq('id', task.id);
    }
    onUpdated();
  }

  async function doAssign(task: Task, assigneeUid: string | null) {
    if (task._source === 'protocole') {
      await supabase.from('plan_taches').update({ assigned_to: assigneeUid }).eq('id', task.id);
    } else {
      await supabase.from('taches_elevage').update({ assigne_a: assigneeUid }).eq('id', task.id);
    }
    onUpdated();
  }

  return (
    <>
      <div className="bg-[#EDF6F7] rounded-xl border border-[#C8E4E8] px-3 py-3">
        <div className="flex items-center gap-1.5 mb-2">
          <span className="text-xs">✅</span>
          <span className="text-xs font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>Tâches du jour</span>
          <span className="ml-auto text-[11px] text-gray-400">{doneItems}/{totalItems}</span>
        </div>
        {protoEnCours.map(g => <ProtoCard key={g.key} groupe={g} onOpenDetail={setProtoDetail} onReport={setReportingTask} />)}
        {manuelEnCours.map(t => <ManuelRow key={t.id} t={t} onToggle={onToggle} onReport={setReportingTask} onAssign={setAssigningTask} />)}
        {doneItems > 0 && (
          <>
            <div className="flex items-center gap-2 my-2">
              <div className="flex-1 border-t border-gray-300/60" />
              <span className="text-[10px] text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>Effectuées ({doneItems})</span>
              <div className="flex-1 border-t border-gray-300/60" />
            </div>
            {protoEffectues.map(g => <ProtoCard key={g.key} groupe={g} effectuee onOpenDetail={setProtoDetail} onReport={setReportingTask} />)}
            {manuelEffectues.map(t => <ManuelRow key={t.id} t={t} onToggle={onToggle} onReport={setReportingTask} onAssign={setAssigningTask} />)}
          </>
        )}
      </div>

      {protoDetail && <ProtoDetailModal groupe={protoDetail} onClose={() => setProtoDetail(null)} onUpdated={() => { onUpdated(); setProtoDetail(null); }} />}
      {reportingTask && <ReporterModal task={reportingTask} onClose={() => setReportingTask(null)} onReport={async (d) => { await doReport(reportingTask, d); setReportingTask(null); }} />}
      {assigningTask && <AssignerModal task={assigningTask} uid={uid} onClose={() => setAssigningTask(null)} onAssign={async (u) => { await doAssign(assigningTask, u); setAssigningTask(null); }} />}
    </>
  );
}

// ── CalendarView ───────────────────────────────────────────────────────────────

function CalendarView({ year, month, events, tasks, selectedDay, onPrev, onNext, onSelectDay, eventsForDay, tasksForDay, onDelete, onAnnuler, onModifier, onNavigateToAnimal, onToggleTask, uid, onUpdated }: {
  year: number; month: number; events: AgendaEvent[]; tasks: Task[];
  selectedDay: number | null;
  onPrev: () => void; onNext: () => void;
  onSelectDay: (d: number) => void;
  eventsForDay: (d: number) => AgendaEvent[];
  tasksForDay: (d: number) => Task[];
  onDelete: (id: number) => void;
  onAnnuler: (e: AgendaEvent) => void;
  onModifier: (e: AgendaEvent) => void;
  onNavigateToAnimal: (id: string | number | null | undefined) => void;
  onToggleTask: (t: Task) => void;
  uid: string;
  onUpdated: () => void;
}) {
  const WEEKDAYS = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  const monthName = new Date(year, month, 1).toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' });
  const totalDays = daysInMonth(year, month);
  const offset    = firstWeekday(year, month);
  const today     = new Date();
  const cells: (number | null)[] = [...Array(offset).fill(null), ...Array.from({ length: totalDays }, (_, i) => i + 1)];
  while (cells.length % 7 !== 0) cells.push(null);

  const dayEvts   = selectedDay ? eventsForDay(selectedDay) : [];
  const dayTasks  = selectedDay ? tasksForDay(selectedDay) : [];

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
            const dtasks = tasksForDay(day);
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
                {(evts.length > 0 || dtasks.length > 0) && (
                  <div className="flex gap-0.5">
                    {evts.slice(0, 2).map((e, j) => (
                      <div key={j} className="w-1.5 h-1.5 rounded-full"
                        style={{ background: isSel ? 'rgba(255,255,255,0.7)' : colorFor(e) }} />
                    ))}
                    {dtasks.length > 0 && (
                      <div className="w-1.5 h-1.5 rounded-full"
                        style={{ background: isSel ? 'rgba(255,255,255,0.7)' : '#6E9E57' }} />
                    )}
                  </div>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {selectedDay && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 space-y-3">
          <p className="font-bold text-sm text-[#0C5C6C] mb-1 capitalize" style={{ fontFamily: 'Galey, sans-serif' }}>
            {new Date(year, month, selectedDay).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
          </p>

          {/* Tâches du jour */}
          {dayTasks.length > 0 && (
            <DayTasksSection tasks={dayTasks} uid={uid} onToggle={onToggleTask} onUpdated={onUpdated} />
          )}

          {/* Événements du jour */}
          {dayEvts.length === 0 && dayTasks.length === 0 ? (
            <p className="text-gray-400 text-sm text-center py-4" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun événement ni tâche</p>
          ) : dayEvts.length === 0 ? null : (
            <div className="space-y-2">
              {dayEvts.map(e => <EventCard key={e.id} event={e} onDelete={onDelete} onAnnuler={onAnnuler} onModifier={onModifier} onNavigateToAnimal={onNavigateToAnimal} />)}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ── ListView ───────────────────────────────────────────────────────────────────

function ListView({ groups, keys, onDelete, onAnnuler, onModifier, onNavigateToAnimal }: {
  groups: Record<string, AgendaEvent[]>; keys: string[];
  onDelete: (id: number) => void;
  onAnnuler: (e: AgendaEvent) => void;
  onModifier: (e: AgendaEvent) => void;
  onNavigateToAnimal: (id: string | number | null | undefined) => void;
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
              {evts.map(e => <EventCard key={e.id} event={e} onDelete={onDelete} onAnnuler={onAnnuler} onModifier={onModifier} onNavigateToAnimal={onNavigateToAnimal} />)}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── EventCard ─────────────────────────────────────────────────────────────────

function EventCard({ event: e, onDelete, onAnnuler, onModifier, onNavigateToAnimal }: {
  event: AgendaEvent;
  onDelete: (id: number) => void;
  onAnnuler: (e: AgendaEvent) => void;
  onModifier: (e: AgendaEvent) => void;
  onNavigateToAnimal: (id: string | number | null | undefined) => void;
}) {
  const color  = colorFor(e);
  const isRdv  = !!e.rdv_id;
  const plus24h = isRdv && new Date(e.date_debut).getTime() - Date.now() > 24 * 3600 * 1000;
  const animalId = e.animal_id ?? e.rdv?.animal_id;

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

      {animalId && (
        <button onClick={() => onNavigateToAnimal(animalId)}
          className="w-full text-xs font-semibold py-1.5 rounded-lg border border-[#0C5C6C]/20 hover:border-[#0C5C6C] text-[#0C5C6C] transition-colors"
          style={{ fontFamily: 'Galey, sans-serif' }}>
          🐾 Ouvrir la fiche animal
        </button>
      )}

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

// ── DayView ───────────────────────────────────────────────────────────────────

const TIMELINE_START = 7;
const TIMELINE_END   = 20;
const TIMELINE_PX    = 780; // height of the full grid in px
const TOTAL_MIN      = (TIMELINE_END - TIMELINE_START) * 60;

function minutesFromTop(iso: string): number {
  const d = new Date(iso);
  return (d.getHours() - TIMELINE_START) * 60 + d.getMinutes();
}

function DayView({ date, events, tasks, onNavigate, onDelete, onAnnuler, onModifier, onNavigateToAnimal, onToggleTask, uid, onUpdated }: {
  date: Date;
  events: AgendaEvent[];
  tasks: Task[];
  onNavigate: (dir: 'prev' | 'next') => void;
  onDelete: (id: number) => void;
  onAnnuler: (e: AgendaEvent) => void;
  onModifier: (e: AgendaEvent) => void;
  onNavigateToAnimal: (id: string | number | null | undefined) => void;
  onToggleTask: (t: Task) => void;
  uid: string;
  onUpdated: () => void;
}) {
  const HOURS = Array.from({ length: TIMELINE_END - TIMELINE_START + 1 }, (_, i) => i + TIMELINE_START);
  const today = new Date();
  const isToday = date.toDateString() === today.toDateString();

  return (
    <div className="space-y-4">
      {/* Navigation jour */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-3">
        <div className="flex items-center justify-between">
          <button onClick={() => onNavigate('prev')} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-[#0C5C6C] text-xl font-light">‹</button>
          <div className="text-center">
            <span className="font-bold text-sm capitalize" style={{ fontFamily: 'Galey, sans-serif', color: '#1E2025' }}>
              {date.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
            </span>
            {isToday && (
              <span className="ml-2 text-[10px] font-bold bg-[#0C5C6C] text-white px-2 py-0.5 rounded-full">Aujourd&apos;hui</span>
            )}
          </div>
          <button onClick={() => onNavigate('next')} className="p-2 rounded-lg hover:bg-gray-100 transition-colors text-[#0C5C6C] text-xl font-light">›</button>
        </div>
      </div>

      {/* Tâches du jour */}
      {tasks.length > 0 && (
        <DayTasksSection tasks={tasks} uid={uid} onToggle={onToggleTask} onUpdated={onUpdated} />
      )}

      {/* Timeline */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        {events.length === 0 && (
          <p className="text-center text-gray-400 text-sm py-8" style={{ fontFamily: 'Galey, sans-serif' }}>
            Aucun événement ce jour
          </p>
        )}
        <div className="relative select-none" style={{ height: TIMELINE_PX }}>
          {/* Hour grid lines */}
          {HOURS.map(h => (
            <div key={h} className="absolute left-0 right-0 flex items-start pointer-events-none"
              style={{ top: `${((h - TIMELINE_START) / (TIMELINE_END - TIMELINE_START)) * 100}%` }}>
              <span className="text-[10px] text-gray-400 w-12 pl-2 flex-shrink-0" style={{ marginTop: -8 }}>{String(h).padStart(2, '0')}:00</span>
              <div className="flex-1 border-t border-gray-100 mt-0" />
            </div>
          ))}

          {/* Events */}
          {events.map(e => {
            const mins = minutesFromTop(e.date_debut);
            const dur = e.duree_minutes ?? e.rdv?.duree_minutes ?? 30;
            const topPct = Math.max(0, mins) / TOTAL_MIN * 100;
            const heightPct = Math.max(0.5, dur / TOTAL_MIN * 100);
            const color = colorFor(e);
            const animalId = e.animal_id ?? e.rdv?.animal_id;
            const isRdv = !!e.rdv_id;
            const statut = e.rdv?.statut ?? '';
            return (
              <div key={e.id}
                onClick={() => animalId ? onNavigateToAnimal(animalId) : undefined}
                className="absolute rounded-xl px-2.5 py-1.5 overflow-hidden shadow-sm transition-shadow hover:shadow-md"
                style={{
                  left: 52, right: 8,
                  top: `${topPct}%`,
                  height: `max(44px, ${heightPct}%)`,
                  background: `${color}18`,
                  borderLeft: `3px solid ${color}`,
                  cursor: animalId ? 'pointer' : 'default',
                }}>
                <div className="flex items-start justify-between gap-1">
                  <div className="min-w-0">
                    <p className="text-xs font-bold truncate leading-tight" style={{ color, fontFamily: 'Galey, sans-serif' }}>
                      {TYPE_ICON[e.type] ?? '📅'} {e.titre}
                    </p>
                    <p className="text-[10px] text-gray-500 leading-tight">
                      {fmtTime(e.date_debut)}{dur ? ` · ${dur} min` : ''}
                    </p>
                    {e.rdv?.motif && <p className="text-[10px] text-gray-400 truncate leading-tight">{e.rdv.motif}</p>}
                  </div>
                  {isRdv && statut && (
                    <span className="text-[9px] font-bold flex-shrink-0 px-1.5 py-0.5 rounded-full"
                      style={{
                        background: statut === 'confirme' ? '#dcfce7' : statut === 'annule' ? '#fee2e2' : '#fef9c3',
                        color: statut === 'confirme' ? '#16a34a' : statut === 'annule' ? '#dc2626' : '#ca8a04',
                      }}>
                      {statut === 'confirme' ? '✓' : statut === 'annule' ? '✗' : '⏳'}
                    </span>
                  )}
                </div>
                {animalId && (
                  <p className="text-[9px] text-gray-400 mt-0.5">Tap → fiche animal</p>
                )}
              </div>
            );
          })}
        </div>
      </div>
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
