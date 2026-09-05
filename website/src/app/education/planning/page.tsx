'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useEducationAccess } from '@/hooks/useEducationAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const TEAL = '#0C5C6C';
const PURPLE = '#7B5EA7';
const DAYS = 7;

interface Rdv {
  id: string;
  motif: string;
  date_heure: string;
  duree_minutes?: number | null;
}

interface Cours {
  id: string;
  titre: string;
  date_heure: string;
  duree_minutes: number;
  capacite_max: number;
  lieu?: string | null;
  notes?: string | null;
  statut: string;
  serie_id?: string | null;
}

interface Participant {
  id: string;
  client_uid: string;
  client_profile_id?: string | null;
  animal_id?: string | null;
  statut: string;
  client_nom?: string;
  animal_nom?: string;
}

function sameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

const DAY_FMT = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
const HOUR_FMT = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' });

export default function EducationPlanningPage() {
  const { user, userData, isEducation, loading: authLoading } = useEducationAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [cours, setCours] = useState<Cours[]>([]);
  const [participantsCount, setParticipantsCount] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [windowStart, setWindowStart] = useState(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; });
  const [creating, setCreating] = useState(false);
  const [detailFor, setDetailFor] = useState<Cours | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isEducation) { router.push('/'); return; }
  }, [user, userData, isEducation, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    const windowEnd = new Date(windowStart); windowEnd.setDate(windowEnd.getDate() + DAYS);
    const [{ data: r }, { data: c }] = await Promise.all([
      supabase.from('rdv').select('id, motif, date_heure, duree_minutes')
        .eq('pro_uid', user.uid).neq('statut', 'refuse')
        .gte('date_heure', windowStart.toISOString()).lt('date_heure', windowEnd.toISOString())
        .order('date_heure'),
      supabase.from('cours_collectifs').select('id, titre, date_heure, duree_minutes, capacite_max, lieu, notes, statut, serie_id')
        .eq('pro_uid', user.uid).neq('statut', 'annule')
        .gte('date_heure', windowStart.toISOString()).lt('date_heure', windowEnd.toISOString())
        .order('date_heure'),
    ]);
    const coursList = (c ?? []) as Cours[];
    const coursIds = coursList.map(x => x.id);
    const counts: Record<string, number> = {};
    if (coursIds.length > 0) {
      const { data: parts } = await supabase.from('cours_collectifs_participants')
        .select('cours_id').in('cours_id', coursIds).neq('statut', 'annule');
      for (const p of parts ?? []) counts[p.cours_id] = (counts[p.cours_id] ?? 0) + 1;
    }
    setRdvs((r ?? []) as Rdv[]);
    setCours(coursList);
    setParticipantsCount(counts);
    setLoading(false);
  }, [user, windowStart]);

  useEffect(() => { load(); }, [load]);

  if (!user || !userData) return null;

  const days = Array.from({ length: DAYS }, (_, i) => { const d = new Date(windowStart); d.setDate(d.getDate() + i); return d; });
  const today = new Date(); today.setHours(0, 0, 0, 0);

  function sessionsForDay(day: Date) {
    const list: Array<{ kind: 'rdv' | 'cours'; data: Rdv | Cours }> = [];
    for (const r of rdvs) { const d = new Date(r.date_heure); if (sameDay(d, day)) list.push({ kind: 'rdv', data: r }); }
    for (const c of cours) { const d = new Date(c.date_heure); if (sameDay(d, day)) list.push({ kind: 'cours', data: c }); }
    return list.sort((a, b) => a.data.date_heure.localeCompare(b.data.date_heure));
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-bold font-galey" style={{ color: TEAL }}>Planning des cours</h1>
        <div className="flex items-center gap-2">
          <button onClick={() => setWindowStart(d => { const n = new Date(d); n.setDate(n.getDate() - 7); return n; })}
            className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50 flex items-center justify-center">‹</button>
          <button onClick={() => { const d = new Date(); d.setHours(0, 0, 0, 0); setWindowStart(d); }}
            className="text-xs font-galey font-semibold px-3 py-1.5 rounded-full border border-gray-200 hover:bg-gray-50">
            Aujourd&apos;hui
          </button>
          <button onClick={() => setWindowStart(d => { const n = new Date(d); n.setDate(n.getDate() + 7); return n; })}
            className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50 flex items-center justify-center">›</button>
          <button onClick={() => setCreating(true)}
            className="text-xs font-galey font-semibold px-4 py-2 rounded-full text-white"
            style={{ backgroundColor: PURPLE }}>
            + Cours collectif
          </button>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2" style={{ borderColor: TEAL }} />
        </div>
      ) : (
        <div className="space-y-5">
          {days.map(day => {
            const sessions = sessionsForDay(day);
            return (
              <div key={day.toISOString()}>
                <span className="inline-block text-xs font-galey font-bold px-3 py-1 rounded-full capitalize"
                  style={{ backgroundColor: sameDay(day, today) ? TEAL : '#e5e7eb', color: sameDay(day, today) ? 'white' : '#374151' }}>
                  {DAY_FMT.format(day)}
                </span>
                <div className="mt-2 space-y-2">
                  {sessions.length === 0 ? (
                    <p className="text-xs font-galey text-gray-400">Aucune séance</p>
                  ) : sessions.map(s => {
                    const isCours = s.kind === 'cours';
                    const d = new Date(s.data.date_heure);
                    const titre = isCours ? (s.data as Cours).titre : (s.data as Rdv).motif;
                    const recurrent = isCours && !!(s.data as Cours).serie_id;
                    const sousTitre = isCours
                      ? `${participantsCount[s.data.id] ?? 0} / ${(s.data as Cours).capacite_max} inscrits`
                      : `Individuel — ${(s.data as Rdv).duree_minutes ?? 60} min`;
                    return (
                      <div key={s.data.id}
                        onClick={() => isCours && setDetailFor(s.data as Cours)}
                        className={`bg-white rounded-xl border p-3 flex items-center gap-3 ${isCours ? 'cursor-pointer hover:shadow-sm' : ''}`}
                        style={{ borderColor: isCours ? `${PURPLE}4D` : '#e5e7eb' }}>
                        <div className="w-1 h-9 rounded" style={{ backgroundColor: isCours ? PURPLE : TEAL }} />
                        <span className="w-12 text-sm font-galey font-bold">{HOUR_FMT.format(d)}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-galey font-semibold truncate">{recurrent && '🔁 '}{titre}</p>
                          <p className="text-xs font-galey text-gray-500">{sousTitre}</p>
                        </div>
                        {isCours && <span className="text-gray-300">›</span>}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {creating && (
        <CreateCoursModal
          proUid={user.uid}
          proProfileId={activeProfileId || null}
          onClose={() => setCreating(false)}
          onSaved={() => { setCreating(false); load(); }}
        />
      )}

      {detailFor && (
        <CoursDetailModal cours={detailFor} onClose={() => setDetailFor(null)} onChanged={load} />
      )}
    </div>
  );
}

function CreateCoursModal({ proUid, proProfileId, onClose, onSaved }: {
  proUid: string; proProfileId: string | null; onClose: () => void; onSaved: () => void;
}) {
  const [titre, setTitre] = useState('');
  const [date, setDate] = useState(() => new Date(Date.now() + 86400000).toISOString().slice(0, 10));
  const [heure, setHeure] = useState('18:00');
  const [duree, setDuree] = useState('90');
  const [capacite, setCapacite] = useState('6');
  const [lieu, setLieu] = useState('');
  const [notes, setNotes] = useState('');
  const [recurrent, setRecurrent] = useState(false);
  const [dateFin, setDateFin] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const HORIZON_SEMAINES = 8;

  async function save() {
    if (!titre.trim()) { setError('Le titre est obligatoire.'); return; }
    setSaving(true);
    setError('');
    const dateHeure = new Date(`${date}T${heure}:00`);
    const dureeMinutes = parseInt(duree, 10) || 90;
    const capaciteMax = parseInt(capacite, 10) || 6;
    const lieuVal = lieu.trim() || null;
    const notesVal = notes.trim() || null;

    let serieId: string | null = null;
    if (recurrent) {
      const { data: serie, error: serieErr } = await supabase.from('cours_collectifs_series').insert({
        pro_uid: proUid,
        pro_profile_id: proProfileId,
        titre: titre.trim(),
        date_debut: dateHeure.toISOString(),
        duree_minutes: dureeMinutes,
        capacite_max: capaciteMax,
        lieu: lieuVal,
        notes: notesVal,
        date_fin: dateFin || null,
      }).select('id').single();
      if (serieErr) { setError(serieErr.message); setSaving(false); return; }
      serieId = serie.id as string;
    }

    // Horizon de génération : jusqu'à la date de fin choisie si plus proche,
    // sinon HORIZON_SEMAINES (le reste est repris par la Cloud Function
    // generateCoursCollectifsOccurrences chaque jour).
    let horizonFin = new Date(dateHeure);
    horizonFin.setDate(horizonFin.getDate() + 7 * (HORIZON_SEMAINES - 1));
    if (recurrent && dateFin) {
      const finJour = new Date(`${dateFin}T23:59:59`);
      if (finJour < horizonFin) horizonFin = finJour;
    }
    const occurrences = [new Date(dateHeure)];
    if (recurrent) {
      let next = new Date(dateHeure);
      next.setDate(next.getDate() + 7);
      while (next <= horizonFin) {
        occurrences.push(new Date(next));
        next = new Date(next);
        next.setDate(next.getDate() + 7);
      }
    }

    for (const occDate of occurrences) {
      const { data: inserted, error: err } = await supabase.from('cours_collectifs').insert({
        pro_uid: proUid,
        pro_profile_id: proProfileId,
        titre: titre.trim(),
        date_heure: occDate.toISOString(),
        duree_minutes: dureeMinutes,
        capacite_max: capaciteMax,
        lieu: lieuVal,
        notes: notesVal,
        ...(serieId ? { serie_id: serieId } : {}),
      }).select('id').single();
      if (err) { setError(err.message); setSaving(false); return; }
      // Visible dans "Mon agenda" (même mécanisme que les RDV confirmés).
      try {
        await supabase.from('agenda_events').insert({
          uid: proUid,
          titre: `👥 ${titre.trim()}`,
          type: 'cours_collectif',
          date_debut: occDate.toISOString(),
          duree_minutes: dureeMinutes,
          couleur: `cours:${inserted?.id}`,
          pro_profile_id: proProfileId,
        });
      } catch { /* ignore */ }
    }
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-md p-6" onClick={e => e.stopPropagation()}>
        <h3 className="font-bold font-galey text-lg mb-4" style={{ color: PURPLE }}>Nouveau cours collectif</h3>
        <div className="space-y-3">
          <input value={titre} onChange={e => setTitre(e.target.value)} placeholder="Titre du cours"
            className="w-full px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
          <div className="grid grid-cols-2 gap-3">
            <input type="date" value={date} onChange={e => setDate(e.target.value)}
              className="px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
            <input type="time" value={heure} onChange={e => setHeure(e.target.value)}
              className="px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <input type="number" value={duree} onChange={e => setDuree(e.target.value)} placeholder="Durée (min)"
              className="px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
            <input type="number" value={capacite} onChange={e => setCapacite(e.target.value)} placeholder="Places max"
              className="px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
          </div>
          <input value={lieu} onChange={e => setLieu(e.target.value)} placeholder="Lieu (adresse ou à domicile)"
            className="w-full px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
          <textarea value={notes} onChange={e => setNotes(e.target.value)} placeholder="Notes (optionnel)" rows={2}
            className="w-full px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey resize-none" />
          <div className="flex items-center justify-between gap-4 rounded-xl border p-3"
            style={{ borderColor: recurrent ? PURPLE : '#E5E7EB', background: recurrent ? `${PURPLE}0D` : 'white' }}>
            <span className="text-sm font-galey font-semibold" style={{ color: recurrent ? PURPLE : '#374151' }}>
              Cours récurrent (chaque semaine)
            </span>
            <button type="button" onClick={() => setRecurrent(v => !v)}
              className="relative w-12 h-7 rounded-full transition-colors flex-shrink-0"
              style={{ backgroundColor: recurrent ? PURPLE : '#D1D5DB' }}>
              <span className="absolute top-0.5 left-0.5 w-6 h-6 bg-white rounded-full shadow transition-transform"
                style={{ transform: recurrent ? 'translateX(20px)' : 'translateX(0)' }} />
            </button>
          </div>
          {recurrent && (
            <div className="flex items-center gap-2">
              <input type="date" value={dateFin} onChange={e => setDateFin(e.target.value)}
                min={date} placeholder="Date de fin (optionnel)"
                className="flex-1 px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
              {dateFin && (
                <button type="button" onClick={() => setDateFin('')} className="text-xs font-galey text-gray-400 hover:text-gray-600">
                  Retirer
                </button>
              )}
            </div>
          )}
        </div>
        {error && <p className="text-xs text-red-500 mt-2">{error}</p>}
        <div className="flex gap-3 mt-4">
          <button onClick={onClose} className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-galey font-semibold">
            Annuler
          </button>
          <button onClick={save} disabled={saving} className="flex-1 text-white rounded-xl py-2.5 text-sm font-galey font-semibold disabled:opacity-50"
            style={{ backgroundColor: PURPLE }}>
            {saving ? '…' : 'Créer le cours'}
          </button>
        </div>
      </div>
    </div>
  );
}

function CoursDetailModal({ cours, onClose, onChanged }: { cours: Cours; onClose: () => void; onChanged: () => void }) {
  const router = useRouter();
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from('cours_collectifs_participants')
      .select('id, client_uid, animal_id, statut').eq('cours_id', cours.id).neq('statut', 'annule').order('created_at');
    const list = (data ?? []) as Participant[];
    const clientUids = [...new Set(list.map(p => p.client_uid))];
    const animalIds = [...new Set(list.map(p => p.animal_id).filter(Boolean))] as string[];
    if (clientUids.length > 0) {
      const { data: users } = await supabase.from('user_profiles').select('uid, firstname, lastname').in('uid', clientUids).eq('is_main', true);
      const names: Record<string, string> = {};
      for (const u of users ?? []) names[u.uid] = `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || 'Client';
      for (const p of list) p.client_nom = names[p.client_uid];
    }
    if (animalIds.length > 0) {
      const { data: animaux } = await supabase.from('animaux').select('id, nom').in('id', animalIds);
      const names: Record<string, string> = {};
      for (const a of animaux ?? []) names[a.id] = a.nom ?? 'Animal';
      for (const p of list) if (p.animal_id) p.animal_nom = names[p.animal_id];
    }
    setParticipants(list);
    setLoading(false);
  }, [cours.id]);

  useEffect(() => { load(); }, [load]);

  // Promeut le plus ancien participant en liste d'attente quand une place se
  // libère (même logique que la Cloud Function generateCoursCollectifsOccurrences
  // et l'auto-désinscription famille).
  async function promouvoirListeAttente() {
    const { data: attente } = await supabase.from('cours_collectifs_participants')
      .select('id, client_uid, client_profile_id').eq('cours_id', cours.id).eq('statut', 'en_attente')
      .order('created_at').limit(1);
    const row = attente?.[0];
    if (!row) return;
    await supabase.from('cours_collectifs_participants').update({ statut: 'inscrit' }).eq('id', row.id);
    const dateStr = new Date(cours.date_heure).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Europe/Paris' });
    await supabase.from('notifications').insert({
      uid: row.client_uid, type: 'cours_collectif_place_liberee',
      title: 'Une place s\'est libérée !',
      body: `Vous êtes maintenant inscrit au cours "${cours.titre}" du ${dateStr}.`,
      ...(row.client_profile_id ? { profile_id: row.client_profile_id } : {}),
      data: { coursId: cours.id }, read: false,
    });
  }

  async function updateStatut(id: string, statut: string) {
    const ancien = participants.find(p => p.id === id)?.statut;
    await supabase.from('cours_collectifs_participants').update({ statut }).eq('id', id);
    if (statut === 'annule' && ancien === 'inscrit') await promouvoirListeAttente();
    load();
  }

  async function cancelCours() {
    if (!window.confirm('Annuler ce cours ? Les participants ne seront pas notifiés automatiquement.')) return;
    await supabase.from('cours_collectifs').update({ statut: 'annule' }).eq('id', cours.id);
    onChanged();
    onClose();
  }

  async function cancelSerie() {
    if (!cours.serie_id) return;
    if (!window.confirm('Annuler toute la série ? Toutes les séances à venir seront annulées ' +
      '(les séances passées restent inchangées). Les participants ne seront pas notifiés automatiquement.')) return;
    await supabase.from('cours_collectifs_series').update({ statut: 'annule' }).eq('id', cours.serie_id);
    await supabase.from('cours_collectifs').update({ statut: 'annule' })
      .eq('serie_id', cours.serie_id).gt('date_heure', new Date().toISOString());
    onChanged();
    onClose();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-md max-h-[85vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between p-5 border-b border-gray-100">
          <h3 className="font-bold font-galey" style={{ color: PURPLE }}>{cours.titre}</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
        </div>
        <div className="p-4 overflow-y-auto flex-1">
          <p className="text-sm font-galey font-semibold mb-3">
            {participants.filter(p => p.statut !== 'en_attente').length} / {cours.capacite_max} inscrits
            {participants.some(p => p.statut === 'en_attente') &&
              ` · ${participants.filter(p => p.statut === 'en_attente').length} en liste d'attente`}
          </p>
          {loading ? (
            <div className="flex justify-center py-6"><div className="animate-spin rounded-full h-6 w-6 border-b-2" style={{ borderColor: PURPLE }} /></div>
          ) : participants.length === 0 ? (
            <p className="text-sm font-galey text-gray-400">Aucun participant inscrit pour l&apos;instant.</p>
          ) : (
            <div className="space-y-2">
              {participants.map(p => (
                <div key={p.id} className="flex items-center justify-between bg-gray-50 rounded-xl px-3 py-2">
                  <div>
                    <p className="text-sm font-galey font-semibold">{p.client_nom}</p>
                    {p.animal_nom && <p className="text-xs font-galey text-gray-500">{p.animal_nom}</p>}
                  </div>
                  <div className="flex items-center gap-2">
                    {p.animal_id && (
                      <button onClick={() => router.push(`/mes-patients/${p.animal_id}?tab=Éducation`)}
                        title="Ajouter un rapport" className="text-lg" style={{ color: PURPLE }}>
                        🎓
                      </button>
                    )}
                    <select value={p.statut} onChange={e => updateStatut(p.id, e.target.value)}
                      className="text-xs font-galey border border-gray-200 rounded-lg px-2 py-1">
                      <option value="inscrit">Inscrit</option>
                      <option value="en_attente">En liste d&apos;attente</option>
                      <option value="present">Présent</option>
                      <option value="absent">Absent</option>
                      <option value="annule">Retirer</option>
                    </select>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
        <div className="p-4 border-t border-gray-100 flex gap-2">
          <button onClick={cancelCours} className="flex-1 text-sm font-galey font-semibold text-red-500 border border-red-200 rounded-xl py-2">
            Annuler ce cours
          </button>
          {cours.serie_id && (
            <button onClick={cancelSerie} className="flex-1 text-sm font-galey font-semibold text-red-500 border border-red-200 rounded-xl py-2">
              Annuler la série
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
