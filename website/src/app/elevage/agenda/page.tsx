'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';

// ── Types ──────────────────────────────────────────────────────────────────────

type ViewMode = 'mois' | 'semaine' | 'jour';

interface Routine {
  id: string;
  label: string;
  date_prevue: string;
  statut: string;
  type_acte?: string | null;
  animal_nom?: string | null;
  etape_id?: string | null;
  assigned_to?: string | null;
  valide_par?: string | null;
  valide_at?: string | null;
}

interface TacheManuelle {
  id: string;
  titre: string;
  date: string;
  statut: string;
  heure?: string | null;
  assigne_a?: string | null;
  assignes_a?: string[] | null;
  fait_par?: string | null;
  notes?: string | null;
}

interface RoutineGroupe {
  etapeId: string;
  routines: Routine[];
  label: string;
  typeActe: string;
}

interface Employe { uid: string; nom: string; avatar?: string | null; }

// ── Constantes ────────────────────────────────────────────────────────────────

const ACTE_EMOJIS: Record<string, string> = {
  vermifuge: '💊', vaccination: '💉', antiparasitaire: '🛡️',
  traitement: '🩺', visite: '🏥', alimentaire: '🍽️',
  toilettage: '✂️', nettoyage: '🧴',
  promenade: '🦮', socialisation: '🦮', autre: '📋',
};

const ACTE_COLOR: Record<string, string> = {
  vaccination: '#2196F3', vermifuge: '#FF9800', antiparasitaire: '#4CAF50',
  traitement: '#E91E63', visite: '#9C27B0', alimentaire: '#FF9800',
  toilettage: '#E91E63', nettoyage: '#00BCD4',
  promenade: '#8BC34A', socialisation: '#8BC34A', autre: '#9E9E9E',
};

const DAY_FR = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
const HOUR_START = 6;
const HOUR_END   = 21;
const PX_PER_HOUR = 64;

// ── Helpers ───────────────────────────────────────────────────────────────────

function toISODate(d: Date) { return d.toISOString().split('T')[0]; }
function addDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }
function daysInMonthFn(y: number, m: number) { return new Date(y, m + 1, 0).getDate(); }
function firstWeekdayFn(y: number, m: number) { return (new Date(y, m, 1).getDay() + 6) % 7; }

function getWeekMonday(d: Date): Date {
  const day = (d.getDay() + 6) % 7; // Mon=0
  const r = new Date(d); r.setDate(d.getDate() - day); return r;
}

function timeToMinutes(heure: string): number {
  const [h, m] = heure.split(':').map(Number);
  return h * 60 + (m || 0);
}

function groupRoutines(routines: Routine[]): RoutineGroupe[] {
  const byKey = new Map<string, Routine[]>();
  for (const r of routines) {
    const key = r.etape_id ?? `solo_${r.id}`;
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key)!.push(r);
  }
  return [...byKey.entries()].map(([etapeId, rs]) => ({
    etapeId, routines: rs,
    label: (rs[0]?.label ?? '').split(' — ')[0],
    typeActe: rs[0]?.type_acte ?? '',
  }));
}

// ── Ajout tâche manuelle depuis l'agenda ─────────────────────────────────────

function AddTacheModal({ selectedDate, uid, profilSource, onClose, onSaved }: {
  selectedDate: string;
  uid: string;
  profilSource: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [titre, setTitre] = useState('');
  const [heure, setHeure] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!titre.trim()) return;
    setSaving(true);
    await supabase.from('taches_elevage').insert({
      uid_eleveur: uid,
      titre: titre.trim(),
      date: selectedDate,
      heure: heure || null,
      notes: notes.trim() || null,
      statut: 'a_faire',
      profil_source: profilSource,
    });
    setSaving(false);
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4">
      <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl">
        <h2 className="font-bold text-gray-800 mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
          Nouvelle tâche
        </h2>
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Titre *</label>
            <input
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
              placeholder="Ex: Nettoyage cage, Pesée…"
              value={titre}
              onChange={e => setTitre(e.target.value)}
              autoFocus
              onKeyDown={e => e.key === 'Enter' && save()}
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Heure (optionnel)</label>
            <input
              type="time"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
              value={heure}
              onChange={e => setHeure(e.target.value)}
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Notes (optionnel)</label>
            <textarea
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400 resize-none"
              placeholder="Informations complémentaires…"
              rows={3}
              value={notes}
              onChange={e => setNotes(e.target.value)}
            />
          </div>
        </div>
        <div className="flex gap-3 mt-5">
          <button onClick={onClose}
            className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
            Annuler
          </button>
          <button onClick={save} disabled={!titre.trim() || saving}
            className="flex-1 py-2.5 bg-teal-600 hover:bg-teal-700 disabled:opacity-40 text-white rounded-xl text-sm font-semibold transition-colors">
            {saving ? 'Ajout…' : 'Ajouter'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Ajout protocole depuis l'agenda ───────────────────────────────────────────

const ACTE_OPTIONS = [
  { value: 'vermifuge',      label: '💊 Vermifuge' },
  { value: 'vaccination',    label: '💉 Vaccination' },
  { value: 'antiparasitaire',label: '🛡️ Antiparasitaire' },
  { value: 'traitement',     label: '🩺 Traitement' },
  { value: 'visite',         label: '🏥 Visite' },
  { value: 'alimentaire',    label: '🍽️ Alimentaire' },
  { value: 'toilettage',     label: '✂️ Toilettage' },
  { value: 'nettoyage',      label: '🧴 Nettoyage' },
  { value: 'promenade',      label: '🦮 Promenade' },
  { value: 'socialisation',  label: '🦮 Socialisation' },
  { value: 'autre',          label: '📋 Autre' },
];

function AddProtocoleModal({ selectedDate, uid, profilSource, onClose, onSaved }: {
  selectedDate: string;
  uid: string;
  profilSource: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [label, setLabel]       = useState('');
  const [typeActe, setTypeActe] = useState('autre');
  const [animalNom, setAnimalNom] = useState('');
  const [saving, setSaving]     = useState(false);

  async function save() {
    if (!label.trim()) return;
    setSaving(true);
    await supabase.from('plan_taches').insert({
      uid_eleveur:   uid,
      label:         label.trim(),
      date_prevue:   `${selectedDate}T00:00:00`,
      statut:        'a_faire',
      type_acte:     typeActe,
      animal_nom:    animalNom.trim() || null,
      profil_source: profilSource,
    });
    setSaving(false);
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4">
      <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl">
        <h2 className="font-bold text-gray-800 mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
          Nouveau protocole
        </h2>
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Intitulé *</label>
            <input
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              placeholder="Ex: Vermifugation, Vaccination…"
              value={label}
              onChange={e => setLabel(e.target.value)}
              autoFocus
              onKeyDown={e => e.key === 'Enter' && save()}
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Type d&apos;acte</label>
            <select
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
              value={typeActe}
              onChange={e => setTypeActe(e.target.value)}
            >
              {ACTE_OPTIONS.map(o => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Animal concerné (optionnel)</label>
            <input
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              placeholder="Nom de l'animal…"
              value={animalNom}
              onChange={e => setAnimalNom(e.target.value)}
            />
          </div>
        </div>
        <div className="flex gap-3 mt-5">
          <button onClick={onClose}
            className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
            Annuler
          </button>
          <button onClick={save} disabled={!label.trim() || saving}
            className="flex-1 py-2.5 disabled:opacity-40 text-white rounded-xl text-sm font-semibold transition-colors"
            style={{ backgroundColor: '#D97706' }}>
            {saving ? 'Ajout…' : 'Ajouter'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Attribution Modal (tâches manuelles — multi-employés) ─────────────────────

function AttributionModal({ tache, employes, currentUid, onClose, onSaved }: {
  tache: TacheManuelle;
  employes: Employe[];
  currentUid: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const existing = tache.assignes_a?.length
    ? tache.assignes_a
    : (tache.assigne_a ? [tache.assigne_a] : []);
  const [selected, setSelected] = useState<Set<string>>(new Set(existing));
  const [saving, setSaving] = useState(false);

  const toggle = (uid: string) =>
    setSelected(s => { const n = new Set(s); n.has(uid) ? n.delete(uid) : n.add(uid); return n; });

  async function save() {
    setSaving(true);
    const arr = [...selected];
    await supabase.from('taches_elevage').update({
      assignes_a: arr,
      assigne_a: arr[0] ?? null,
    }).eq('id', tache.id);
    setSaving(false);
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4"
      onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="bg-white rounded-2xl w-full max-w-sm flex flex-col shadow-xl">
        <div className="flex items-center justify-between px-5 pt-5 pb-3 border-b">
          <div>
            <p className="font-bold text-gray-800 text-sm">Attribuer à des employés</p>
            <p className="text-xs text-gray-400 mt-0.5 truncate max-w-[220px]">{tache.titre}</p>
          </div>
          <button onClick={onClose} className="text-gray-400 text-2xl leading-none">×</button>
        </div>

        {employes.length === 0 ? (
          <div className="px-5 py-8 text-center text-sm text-gray-400">
            Aucun employé actif.<br />
            <a href="/employes" className="text-teal-600 underline mt-1 inline-block">Gérer les employés →</a>
          </div>
        ) : (
          <div className="overflow-y-auto max-h-64 py-2">
            {employes.map(e => {
              const sel = selected.has(e.uid);
              return (
                <button key={e.uid} onClick={() => toggle(e.uid)}
                  className="w-full flex items-center gap-3 px-5 py-3 hover:bg-gray-50 transition-colors">
                  <div className={`w-5 h-5 rounded border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                    sel ? 'bg-teal-600 border-teal-600' : 'border-gray-300'
                  }`}>
                    {sel && <span className="text-white text-xs font-bold">✓</span>}
                  </div>
                  <div className="w-8 h-8 rounded-full bg-teal-50 flex items-center justify-center text-teal-700 font-bold text-sm flex-shrink-0">
                    {e.avatar
                      ? <img src={e.avatar} alt="" className="w-full h-full rounded-full object-cover" />
                      : e.nom[0]?.toUpperCase()}
                  </div>
                  <span className="text-sm text-gray-800 font-medium">{e.nom}</span>
                  {e.uid === currentUid && <span className="text-xs text-gray-400 ml-auto">(moi)</span>}
                </button>
              );
            })}
          </div>
        )}

        <div className="px-5 py-4 border-t flex gap-3">
          <button onClick={onClose}
            className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 font-medium hover:bg-gray-50">
            Annuler
          </button>
          <button onClick={save} disabled={saving}
            className="flex-1 py-2.5 bg-teal-600 text-white rounded-xl text-sm font-semibold hover:bg-teal-700 disabled:opacity-60">
            {saving ? 'Enregistrement…' : 'Confirmer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal routines — checkboxes par animal + attribution employé ───────────────

function RoutineModal({ groupe, selectedDate, employes, currentUid, onClose, onUpdated, onDeleteGroupe }: {
  groupe: RoutineGroupe;
  selectedDate: string;
  employes: Employe[];
  currentUid: string;
  onClose: () => void;
  onUpdated: () => void;
  onDeleteGroupe: (g: RoutineGroupe) => void;
}) {
  const [items, setItems] = useState<Routine[]>([...groupe.routines]);
  const [assigningIdx, setAssigningIdx] = useState<number | null>(null);
  const [globalAssignOpen, setGlobalAssignOpen] = useState(false);
  const [globalAssigning, setGlobalAssigning] = useState(false);
  const nomFor = (uid: string | null | undefined) => uid
    ? (employes.find(e => e.uid === uid)?.nom ?? uid.slice(0, 8))
    : null;

  const toggle = async (idx: number) => {
    const r = items[idx];
    const newStatut = r.statut === 'fait' ? 'en_attente' : 'fait';
    const update: Record<string, unknown> = { statut: newStatut };
    if (newStatut === 'fait') {
      update.valide_par = currentUid;
      update.valide_at  = new Date().toISOString();
    } else {
      update.valide_par = null;
      update.valide_at  = null;
    }
    await supabase.from('plan_taches').update(update).eq('id', r.id);
    setItems(prev => prev.map((it, i) => i === idx
      ? { ...it, statut: newStatut, valide_par: newStatut === 'fait' ? currentUid : null }
      : it));
  };

  const assignEmp = async (idx: number, empUid: string | null) => {
    await supabase.from('plan_taches').update({ assigned_to: empUid }).eq('id', items[idx].id);
    setItems(prev => prev.map((it, i) => i === idx ? { ...it, assigned_to: empUid } : it));
    setAssigningIdx(null);
  };

  const assignAll = async (empUid: string | null) => {
    setGlobalAssigning(true);
    const ids = items.map(r => r.id);
    await supabase.from('plan_taches').update({ assigned_to: empUid }).in('id', ids);
    setItems(prev => prev.map(it => ({ ...it, assigned_to: empUid })));
    setGlobalAssigning(false);
    setGlobalAssignOpen(false);
  };

  const deleteItem = async (r: Routine, idx: number) => {
    if (!confirm(`Supprimer "${r.animal_nom || `Animal #${idx + 1}`}" de ce protocole ?`)) return;
    await supabase.from('plan_taches').delete()
      .eq('id', r.id)
      .gte('date_prevue', `${selectedDate}T00:00:00`)
      .lte('date_prevue', `${selectedDate}T23:59:59`);
    setItems(prev => prev.filter((_, i) => i !== idx));
    onUpdated();
  };

  const total = items.length;
  const done  = items.filter(r => r.statut === 'fait').length;
  const pct   = total > 0 ? Math.round((done / total) * 100) : 0;
  const emoji = ACTE_EMOJIS[groupe.typeActe] ?? '📋';

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center sm:items-center p-4"
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="bg-white rounded-2xl w-full max-w-md max-h-[85vh] flex flex-col">

        {/* Header */}
        <div className="p-5 border-b">
          <div className="flex items-start gap-3">
            <span className="text-2xl flex-shrink-0">{emoji}</span>
            <div className="flex-1 min-w-0">
              <h3 className="font-bold text-gray-800 text-base">{groupe.label}</h3>
              <p className="text-xs text-gray-400 mt-0.5">Protocole · {done}/{total} validé{done > 1 ? 's' : ''}</p>
            </div>
            <button onClick={() => onDeleteGroupe(groupe)}
              className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-2xl leading-none">×</button>
          </div>
          <div className="mt-3">
            <div className="w-full bg-gray-100 rounded-full h-2">
              <div className={`h-2 rounded-full transition-all ${done === total ? 'bg-green-500' : 'bg-teal-500'}`}
                style={{ width: `${pct}%` }} />
            </div>
            <p className="text-right text-xs text-gray-400 mt-1">{pct} %</p>
          </div>

          {/* Attribution globale */}
          {employes.length > 0 && (
            <div className="mt-3 pt-3 border-t border-gray-100 relative">
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-500 font-medium">👥 Attribuer tous les animaux à :</span>
                <button
                  onClick={() => setGlobalAssignOpen(o => !o)}
                  disabled={globalAssigning}
                  className="text-xs text-teal-600 border border-teal-200 rounded-full px-3 py-1 hover:bg-teal-50 font-semibold flex items-center gap-1 disabled:opacity-50">
                  {globalAssigning ? 'En cours…' : (
                    (() => {
                      const uid = items[0]?.assigned_to;
                      const allSame = uid && items.every(it => it.assigned_to === uid);
                      return allSame ? nomFor(uid) ?? 'Choisir' : 'Choisir';
                    })()
                  )}
                  <span className="text-gray-400">▾</span>
                </button>
              </div>
              {globalAssignOpen && (
                <div className="absolute right-0 top-full mt-1 z-20 bg-white border border-gray-200 rounded-xl shadow-lg w-48 py-1">
                  <button onClick={() => assignAll(null)}
                    className="w-full text-left px-4 py-2.5 text-xs text-gray-500 hover:bg-gray-50 border-b border-gray-100">
                    Aucun (retirer l&apos;attribution)
                  </button>
                  {employes.map(e => (
                    <button key={e.uid} onClick={() => assignAll(e.uid)}
                      className="w-full text-left px-4 py-2.5 text-xs text-gray-800 hover:bg-teal-50 flex items-center gap-2">
                      <div className="w-6 h-6 rounded-full bg-teal-50 flex items-center justify-center text-teal-700 font-bold text-xs flex-shrink-0">
                        {e.nom[0]?.toUpperCase()}
                      </div>
                      <span className="flex-1">{e.nom}</span>
                      {e.uid === items[0]?.assigned_to && items.every(it => it.assigned_to === e.uid) && (
                        <span className="text-teal-600 font-bold">✓</span>
                      )}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Liste animaux */}
        <div className="overflow-y-auto flex-1">
          {items.map((r, idx) => {
            const isDone = r.statut === 'fait';
            const nom    = r.animal_nom?.trim() || `Animal #${idx + 1}`;
            const valPar = nomFor(r.valide_par);
            const assigneNom = nomFor(r.assigned_to);
            return (
              <div key={r.id} className="border-b border-gray-50 last:border-0">
                <div className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50 transition-colors">
                  <button onClick={() => toggle(idx)}
                    className={`w-5 h-5 rounded border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                      isDone ? 'bg-teal-600 border-teal-600' : 'border-gray-300 hover:border-teal-400'
                    }`}>
                    {isDone && <span className="text-white text-xs font-bold">✓</span>}
                  </button>
                  <span className="text-sm mr-0.5">🐾</span>
                  <div className="flex-1 min-w-0 cursor-pointer" onClick={() => toggle(idx)}>
                    <p className={`text-sm font-medium ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                      {nom}
                    </p>
                    {isDone && valPar && (
                      <p className="text-xs text-green-600 mt-0.5">✓ Fait par {valPar}</p>
                    )}
                    {!isDone && assigneNom && (
                      <p className="text-xs text-teal-600 mt-0.5">👤 {assigneNom}</p>
                    )}
                  </div>
                  {/* Attribution */}
                  {employes.length > 0 && (
                    <div className="relative">
                      <button onClick={() => setAssigningIdx(assigningIdx === idx ? null : idx)}
                        className="text-xs text-teal-600 border border-teal-200 rounded-full px-2 py-0.5 hover:bg-teal-50 font-medium flex-shrink-0">
                        {assigneNom ? '✎' : '+ Attrib.'}
                      </button>
                      {assigningIdx === idx && (
                        <div className="absolute right-0 top-7 z-10 bg-white border border-gray-200 rounded-xl shadow-lg w-44 py-1">
                          <button onClick={() => assignEmp(idx, null)}
                            className="w-full text-left px-3 py-2 text-xs text-gray-500 hover:bg-gray-50">
                            Aucun
                          </button>
                          {employes.map(e => (
                            <button key={e.uid} onClick={() => assignEmp(idx, e.uid)}
                              className={`w-full text-left px-3 py-2 text-xs hover:bg-teal-50 ${
                                r.assigned_to === e.uid ? 'text-teal-700 font-semibold' : 'text-gray-700'
                              }`}>
                              {e.nom}
                              {r.assigned_to === e.uid && ' ✓'}
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                  <button onClick={() => deleteItem(r, idx)}
                    className="p-1 rounded hover:bg-red-50 text-gray-300 hover:text-red-400 flex-shrink-0">
                    <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                </div>
              </div>
            );
          })}
        </div>

        <div className="p-4 border-t">
          <button onClick={onUpdated}
            className="w-full py-2.5 bg-teal-600 text-white rounded-xl text-sm font-semibold hover:bg-teal-700">
            Fermer
          </button>
        </div>
      </div>
    </div>
  );
}

// ── DayTimeline ───────────────────────────────────────────────────────────────

function DayTimeline({ groupes, tachesM, employes, currentUid, selectedDate, onValidateGroupe,
  onToggleManuel, onAttributeManuel, onDeleteManuel, onDeleteGroupe, load }:
{
  groupes: RoutineGroupe[];
  tachesM: TacheManuelle[];
  employes: Employe[];
  currentUid: string;
  selectedDate: string;
  onValidateGroupe: (g: RoutineGroupe) => void;
  onToggleManuel: (t: TacheManuelle) => void;
  onAttributeManuel: (t: TacheManuelle) => void;
  onDeleteManuel: (t: TacheManuelle) => void;
  onDeleteGroupe: (g: RoutineGroupe) => void;
  load: () => void;
}) {
  const nomFor = (uid: string | null | undefined) => uid
    ? (employes.find(e => e.uid === uid)?.nom ?? uid.slice(0, 8))
    : null;

  // Sépare les tâches manuelles : avec heure (timeline) vs sans heure (all-day)
  const tachesTimed   = tachesM.filter(t => t.heure && t.heure.length >= 5);
  const tachesAllDay  = tachesM.filter(t => !t.heure);
  const allDayEmpty   = groupes.length === 0 && tachesAllDay.length === 0;

  const hours = Array.from({ length: HOUR_END - HOUR_START }, (_, i) => HOUR_START + i);

  return (
    <div>
      {/* Zone all-day — protocoles + tâches sans heure */}
      {!allDayEmpty && (
        <div className="mb-3 bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <div className="px-4 pt-3 pb-1 flex items-center gap-2">
            <span className="text-xs font-bold text-gray-400 uppercase tracking-wider">Tâches du jour</span>
            <span className="text-xs text-gray-300">{groupes.length + tachesAllDay.length}</span>
          </div>
          <div className="px-3 pb-3 space-y-2">
            {/* Groupes protocoles */}
            {groupes.map(g => {
              const done    = g.routines.filter(r => r.statut === 'fait').length;
              const total   = g.routines.length;
              const allDone = done === total;
              return (
                <div key={g.etapeId}
                  className={`flex items-center gap-3 rounded-xl px-3 py-2.5 cursor-pointer transition-colors ${
                    allDone ? 'bg-gray-50 opacity-70' : 'bg-teal-50 hover:bg-teal-100'
                  }`}
                  style={{ borderLeft: `3px solid ${ACTE_COLOR[g.typeActe] ?? '#9E9E9E'}` }}
                  onClick={() => onValidateGroupe(g)}>
                  <span className="text-base">{ACTE_EMOJIS[g.typeActe] ?? '📋'}</span>
                  <div className="flex-1 min-w-0">
                    <p className={`text-sm font-semibold ${allDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                      {g.label}
                    </p>
                    <p className="text-xs text-gray-400">{done}/{total} animal{total > 1 ? 'x' : ''}</p>
                  </div>
                  {!allDone && (
                    <div className="w-8 h-8 rounded-full bg-white flex items-center justify-center text-xs font-bold text-teal-600 border border-teal-200 flex-shrink-0">
                      {done}/{total}
                    </div>
                  )}
                  {allDone && <span className="text-green-500 text-lg">✓</span>}
                </div>
              );
            })}
            {/* Tâches manuelles sans heure */}
            {tachesAllDay.map(t => {
              const isDone    = t.statut === 'fait';
              const assignees = t.assignes_a?.length ? t.assignes_a : (t.assigne_a ? [t.assigne_a] : []);
              const faitPar   = nomFor(t.fait_par);
              return (
                <div key={t.id}
                  className={`flex items-center gap-3 rounded-xl px-3 py-2.5 transition-colors ${
                    isDone ? 'bg-gray-50 opacity-70' : 'bg-white border border-gray-100 hover:border-teal-200'
                  }`}>
                  <button onClick={() => onToggleManuel(t)}
                    className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
                      isDone ? 'bg-green-500 border-green-500' : 'border-gray-300 hover:border-teal-400'
                    }`}>
                    {isDone && <span className="text-white text-xs font-bold">✓</span>}
                  </button>
                  <div className="flex-1 min-w-0" onClick={() => onToggleManuel(t)}>
                    <p className={`text-sm font-medium cursor-pointer ${isDone ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                      {t.titre}
                    </p>
                    {isDone && faitPar && (
                      <p className="text-xs text-green-600 mt-0.5">✓ Fait par {faitPar}</p>
                    )}
                    {!isDone && assignees.length > 0 && (
                      <p className="text-xs text-teal-600 mt-0.5">
                        👤 {assignees.map(uid => nomFor(uid) ?? uid.slice(0,6)).join(', ')}
                      </p>
                    )}
                  </div>
                  {employes.length > 0 && (
                    <button onClick={() => onAttributeManuel(t)}
                      className="text-xs text-teal-600 border border-teal-200 rounded-full px-2 py-0.5 hover:bg-teal-50 flex-shrink-0">
                      {assignees.length > 0 ? '✎' : '+ Attrib.'}
                    </button>
                  )}
                  <button onClick={() => onDeleteManuel(t)}
                    className="p-1 rounded hover:bg-red-50 text-gray-300 hover:text-red-400 flex-shrink-0">
                    <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Timeline horaire */}
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
        <div className="px-4 pt-3 pb-1">
          <span className="text-xs font-bold text-gray-400 uppercase tracking-wider">Timeline</span>
        </div>
        <div className="relative overflow-y-auto" style={{ maxHeight: '520px' }}>
          {/* Grille heures */}
          <div className="relative" style={{ height: `${(HOUR_END - HOUR_START) * PX_PER_HOUR}px` }}>
            {hours.map(h => (
              <div key={h} className="absolute left-0 right-0 border-t border-gray-100 flex items-start"
                style={{ top: `${(h - HOUR_START) * PX_PER_HOUR}px`, height: `${PX_PER_HOUR}px` }}>
                <span className="text-xs text-gray-300 w-12 text-right pr-3 pt-0.5 flex-shrink-0 select-none">
                  {String(h).padStart(2, '0')}:00
                </span>
                <div className="flex-1 relative h-full" />
              </div>
            ))}

            {/* Tâches manuelles avec heure */}
            {tachesTimed.map(t => {
              const mins    = timeToMinutes(t.heure!);
              const top     = (mins - HOUR_START * 60) * (PX_PER_HOUR / 60);
              const isDone  = t.statut === 'fait';
              const faitPar = nomFor(t.fait_par);
              const assignees = t.assignes_a?.length ? t.assignes_a : (t.assigne_a ? [t.assigne_a] : []);
              if (top < 0 || top > (HOUR_END - HOUR_START) * PX_PER_HOUR) return null;
              return (
                <div key={t.id}
                  className="absolute left-14 right-3 rounded-xl px-3 py-2 cursor-pointer group"
                  style={{
                    top: `${top}px`,
                    minHeight: '44px',
                    background: isDone ? '#F0FDF4' : '#E6F4F7',
                    border: `1.5px solid ${isDone ? '#86EFAC' : '#0C5C6C33'}`,
                  }}>
                  <div className="flex items-start gap-2">
                    <button onClick={() => onToggleManuel(t)}
                      className={`w-4 h-4 rounded border-2 flex items-center justify-center flex-shrink-0 mt-0.5 transition-colors ${
                        isDone ? 'bg-green-500 border-green-500' : 'border-[#0C5C6C] hover:bg-teal-100'
                      }`}>
                      {isDone && <span className="text-white text-[9px] font-bold">✓</span>}
                    </button>
                    <div className="flex-1 min-w-0">
                      <p className={`text-xs font-semibold ${isDone ? 'line-through text-gray-400' : 'text-[#0C5C6C]'}`}>
                        {t.titre}
                      </p>
                      <p className="text-[10px] text-gray-400">
                        {t.heure?.slice(0, 5)}
                        {isDone && faitPar && <span className="text-green-600 ml-1">· Fait par {faitPar}</span>}
                        {!isDone && assignees.length > 0 && (
                          <span className="text-teal-600 ml-1">
                            · {assignees.map(uid => nomFor(uid) ?? '').join(', ')}
                          </span>
                        )}
                      </p>
                    </div>
                    {employes.length > 0 && (
                      <button onClick={() => onAttributeManuel(t)}
                        className="text-[10px] text-teal-600 opacity-0 group-hover:opacity-100 border border-teal-200 rounded-full px-1.5 flex-shrink-0">
                        {assignees.length > 0 ? '✎' : '+'}
                      </button>
                    )}
                    <button onClick={() => onDeleteManuel(t)}
                      className="opacity-0 group-hover:opacity-100 p-0.5 text-gray-300 hover:text-red-400 flex-shrink-0">
                      <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                </div>
              );
            })}

            {/* Ligne heure actuelle */}
            {(() => {
              const now = new Date();
              if (selectedDate !== toISODate(now)) return null;
              const totalMins = now.getHours() * 60 + now.getMinutes();
              const top = (totalMins - HOUR_START * 60) * (PX_PER_HOUR / 60);
              if (top < 0 || top > (HOUR_END - HOUR_START) * PX_PER_HOUR) return null;
              return (
                <div className="absolute left-12 right-0 pointer-events-none"
                  style={{ top: `${top}px` }}>
                  <div className="flex items-center gap-1">
                    <div className="w-2 h-2 rounded-full bg-red-500 flex-shrink-0" />
                    <div className="flex-1 h-px bg-red-400" />
                  </div>
                </div>
              );
            })()}

            {tachesTimed.length === 0 && (
              <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                <p className="text-xs text-gray-300">Aucune tâche avec horaire</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// ── WeekStrip ─────────────────────────────────────────────────────────────────

function WeekStrip({ selectedDate, onSelectDay, monthDates }:
  { selectedDate: string; onSelectDay: (d: string) => void; monthDates: Map<string, string[]> }) {
  const selDate  = new Date(selectedDate + 'T12:00:00');
  const monday   = getWeekMonday(selDate);
  const weekDays = Array.from({ length: 7 }, (_, i) => addDays(monday, i));
  const today    = toISODate(new Date());

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 mb-4">
      <div className="grid grid-cols-7 gap-1">
        {weekDays.map((d, i) => {
          const ds     = toISODate(d);
          const isSel  = ds === selectedDate;
          const isT    = ds === today;
          const colors = monthDates.get(ds) ?? [];
          return (
            <button key={i} onClick={() => onSelectDay(ds)}
              className="flex flex-col items-center py-2 px-1 rounded-xl transition-all"
              style={{ background: isSel ? '#0d9488' : isT ? '#ccfbf1' : 'transparent',
                       border: isT && !isSel ? '1.5px solid #0d9488' : '1.5px solid transparent' }}>
              <span className="text-[10px] font-semibold" style={{ color: isSel ? 'rgba(255,255,255,0.7)' : '#9CA3AF' }}>
                {DAY_FR[d.getDay()]}
              </span>
              <span className="text-base font-bold mt-0.5" style={{ color: isSel ? 'white' : '#374151' }}>
                {d.getDate()}
              </span>
              {colors.length > 0 && (
                <div className="flex gap-0.5 mt-1">
                  {colors.slice(0, 3).map((c, ci) => (
                    <div key={ci} className="w-1.5 h-1.5 rounded-full"
                      style={{ background: isSel ? 'rgba(255,255,255,0.7)' : c }} />
                  ))}
                </div>
              )}
            </button>
          );
        })}
      </div>
      {/* Navigation semaine */}
      <div className="flex items-center justify-between mt-3 pt-3 border-t border-gray-100">
        <button onClick={() => onSelectDay(toISODate(addDays(monday, -7)))}
          className="text-teal-600 text-sm font-medium hover:text-teal-700 flex items-center gap-1">
          ‹ Semaine préc.
        </button>
        <span className="text-xs text-gray-400">
          {monday.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })} –{' '}
          {addDays(monday, 6).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' })}
        </span>
        <button onClick={() => onSelectDay(toISODate(addDays(monday, 7)))}
          className="text-teal-600 text-sm font-medium hover:text-teal-700 flex items-center gap-1">
          Sem. suiv. ›
        </button>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════════════════

export default function AgendaElevagePage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const profilSource = pathname.startsWith('/association') ? 'association' : 'eleveur';
  const { config: planConfig, loading: planLoading } = usePlan();

  const [viewMode, setViewMode]         = useState<ViewMode>('mois');
  const [selectedDate, setSelectedDate] = useState(toISODate(new Date()));
  const [focusedYear, setFocusedYear]   = useState(new Date().getFullYear());
  const [focusedMois, setFocusedMois]   = useState(new Date().getMonth());
  const [routines, setRoutines]         = useState<Routine[]>([]);
  const [tachesM, setTachesM]           = useState<TacheManuelle[]>([]);
  const [employes, setEmployes]         = useState<Employe[]>([]);
  const [loadingData, setLoadingData]   = useState(true);
  const [validateGroupe, setValidateGroupe] = useState<RoutineGroupe | null>(null);
  const [attributionTask, setAttributionTask] = useState<TacheManuelle | null>(null);
  const [confirmDelete, setConfirmDelete]     = useState<{ label: string; onConfirm: () => void } | null>(null);
  const [showAddTache, setShowAddTache]         = useState(false);
  const [showAddProtocole, setShowAddProtocole] = useState(false);
  const [monthDates, setMonthDates]     = useState<Map<string, string[]>>(new Map());

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [user, loading, router]);

  // Charge les employés de l'éleveur
  const loadEmployes = useCallback(async () => {
    if (!user) return;
    try {
      const { data: emps } = await supabase
        .from('employes')
        .select('uid_employe')
        .eq('uid_eleveur', user.uid)
        .eq('actif', true);
      if (!emps?.length) return;
      const uids = emps.map((e: { uid_employe: string }) => e.uid_employe);
      const { data: users } = await supabase
        .from('users')
        .select('uid, firstname, lastname, profile_picture_url')
        .in('uid', uids);
      setEmployes((users ?? []).map((u: { uid: string; firstname?: string; lastname?: string; profile_picture_url?: string }) => ({
        uid: u.uid,
        nom: `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || u.uid.slice(0, 8),
        avatar: u.profile_picture_url ?? null,
      })));
    } catch {}
  }, [user]);

  useEffect(() => { if (user) loadEmployes(); }, [user, loadEmployes]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoadingData(true);
    const [r1, r2, tm] = await Promise.all([
      (() => { const q = supabase.from('plan_taches')
        .select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id,assigned_to,valide_par,valide_at')
        .eq('uid_eleveur', user.uid).eq('date_prevue', selectedDate);
        return profilSource === 'association' ? q.eq('profil_source', 'association') : q.or('profil_source.is.null,profil_source.eq.eleveur'); })(),
      supabase.from('plan_taches')
        .select('id,label,date_prevue,statut,type_acte,animal_nom,etape_id,assigned_to,valide_par,valide_at')
        .eq('assigned_to', user.uid).eq('date_prevue', selectedDate),
      (() => { const q = supabase.from('taches_elevage')
        .select('id,titre,date,statut,heure,assigne_a,assignes_a,fait_par,notes')
        .eq('uid_eleveur', user.uid).eq('date', selectedDate);
        return profilSource === 'association' ? q.eq('profil_source', 'association') : q.or('profil_source.is.null,profil_source.eq.eleveur'); })(),
    ]);
    const seen = new Set<string>();
    const allR = [...(r1.data ?? []), ...(r2.data ?? [])] as Routine[];
    setRoutines(allR.filter(r => { if (seen.has(r.id)) return false; seen.add(r.id); return true; }));
    setTachesM((tm.data ?? []) as TacheManuelle[]);
    setLoadingData(false);
  }, [user, selectedDate]);

  useEffect(() => { if (user) load(); }, [user, load]);

  const loadMonth = useCallback(async () => {
    if (!user) return;
    const mm   = String(focusedMois + 1).padStart(2, '0');
    const from = `${focusedYear}-${mm}-01`;
    const to   = `${focusedYear}-${mm}-${String(daysInMonthFn(focusedYear, focusedMois)).padStart(2, '0')}`;
    const [r1, r2, tm] = await Promise.all([
      (() => { const q = supabase.from('plan_taches').select('date_prevue,type_acte').eq('uid_eleveur', user.uid)
        .gte('date_prevue', `${from}T00:00:00`).lte('date_prevue', `${to}T23:59:59`);
        return profilSource === 'association' ? q.eq('profil_source', 'association') : q.or('profil_source.is.null,profil_source.eq.eleveur'); })(),
      supabase.from('plan_taches').select('date_prevue,type_acte').eq('assigned_to', user.uid)
        .gte('date_prevue', `${from}T00:00:00`).lte('date_prevue', `${to}T23:59:59`),
      (() => { const q = supabase.from('taches_elevage').select('date').eq('uid_eleveur', user.uid)
        .gte('date', from).lte('date', to);
        return profilSource === 'association' ? q.eq('profil_source', 'association') : q.or('profil_source.is.null,profil_source.eq.eleveur'); })(),
    ]);
    const map = new Map<string, Set<string>>();
    const addC = (date: string, c: string) => {
      if (!map.has(date)) map.set(date, new Set());
      map.get(date)!.add(c);
    };
    [...(r1.data ?? []), ...(r2.data ?? [])].forEach((r: { date_prevue: string; type_acte?: string }) =>
      addC(r.date_prevue.split('T')[0], ACTE_COLOR[r.type_acte ?? ''] ?? '#9E9E9E'));
    ((tm.data ?? []) as { date: string }[]).forEach(t => addC(t.date, '#6E9E57'));
    setMonthDates(new Map([...map.entries()].map(([d, s]) => [d, [...s]])));
  }, [user, focusedYear, focusedMois]);

  useEffect(() => { if (user) loadMonth(); }, [user, loadMonth]);

  const handleSelectDate = useCallback((ds: string) => {
    setSelectedDate(ds);
    const d = new Date(ds + 'T12:00:00');
    setFocusedYear(d.getFullYear());
    setFocusedMois(d.getMonth());
  }, []);

  const deleteGroupe = useCallback(async (g: RoutineGroupe) => {
    await supabase.from('plan_taches').delete().in('id', g.routines.map(r => r.id))
      .gte('date_prevue', `${selectedDate}T00:00:00`)
      .lte('date_prevue', `${selectedDate}T23:59:59`);
    load();
  }, [selectedDate, load]);

  const toggleManuel = useCallback(async (t: TacheManuelle) => {
    const newStatut = t.statut === 'fait' ? 'a_faire' : 'fait';
    const update: Record<string, unknown> = { statut: newStatut };
    if (newStatut === 'fait') {
      update.fait_par = user!.uid;
      update.fait_a   = new Date().toISOString();
    } else {
      update.fait_par = null;
      update.fait_a   = null;
    }
    await supabase.from('taches_elevage').update(update).eq('id', t.id);
    load();
  }, [user, load]);

  const deleteManuel = useCallback(async (t: TacheManuelle) => {
    setConfirmDelete({
      label: `Supprimer la tâche "${t.titre}" ?`,
      onConfirm: async () => {
        await supabase.from('taches_elevage').delete().eq('id', t.id);
        load();
      },
    });
  }, [load]);

  // Early returns après tous les hooks
  if (loading || !user) return (
    <div className="flex justify-center items-center h-64">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
    </div>
  );

  if (!planLoading && !planConfig.hasPlanning) return (
    <div className="min-h-screen bg-[#F8F8F6] flex items-center justify-center p-6">
      <div className="bg-white rounded-2xl shadow-sm border border-[#E5E7EB] max-w-md w-full p-8 text-center">
        <div className="text-5xl mb-4">👑</div>
        <h2 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
          Fonctionnalité Premium
        </h2>
        <p className="text-[#6B7280] text-sm mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>
          L&apos;agenda des protocoles est réservé aux abonnements <strong>Premium</strong>.
        </p>
        <button onClick={() => router.push('/abonnement')}
          className="w-full py-3 rounded-xl text-white font-semibold text-sm"
          style={{ backgroundColor: '#D97706' }}>
          Passer en Premium
        </button>
      </div>
    </div>
  );

  const groupes           = groupRoutines(routines);
  const groupesEnCours    = groupes.filter(g => !g.routines.every(r => r.statut === 'fait'));
  const groupesEffectuees = groupes.filter(g => g.routines.every(r => r.statut === 'fait'));
  const tachesMEnCours    = tachesM.filter(t => t.statut !== 'fait');
  const tachesMEffectuees = tachesM.filter(t => t.statut === 'fait');
  const totalItems        = groupes.length + tachesM.length;
  const doneItems         = groupesEffectuees.length + tachesMEffectuees.length;

  const today      = new Date();
  const totalDays  = daysInMonthFn(focusedYear, focusedMois);
  const calOffset  = firstWeekdayFn(focusedYear, focusedMois);
  const calCells: (number | null)[] = [...Array(calOffset).fill(null), ...Array.from({ length: totalDays }, (_, i) => i + 1)];
  while (calCells.length % 7 !== 0) calCells.push(null);

  const dateLabel = selectedDate === toISODate(new Date())
    ? "Aujourd'hui"
    : new Date(selectedDate + 'T12:00:00').toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });

  // ── Render ─────────────────────────────────────────────────────────────────

  const GroupeCard = ({ g, effectuee = false }: { g: RoutineGroupe; effectuee?: boolean }) => {
    const done    = g.routines.filter(r => r.statut === 'fait').length;
    const total   = g.routines.length;
    const pct     = total > 0 ? done / total : 0;
    const allDone = done === total;
    const emoji   = ACTE_EMOJIS[g.typeActe] ?? '📋';
    return (
      <div className={`bg-white rounded-2xl shadow-sm border p-4 ${
        effectuee ? 'border-gray-100 opacity-70' : allDone ? 'border-gray-100 opacity-60' : 'border-teal-100'
      }`}>
        <div className="flex items-center gap-3">
          <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-xl flex-shrink-0 cursor-pointer hover:shadow-md transition-all ${
            effectuee || allDone ? 'bg-gray-50' : 'bg-teal-50'
          }`} onClick={() => !effectuee && setValidateGroupe(g)}>
            {emoji}
          </div>
          <div className="flex-1 min-w-0 cursor-pointer" onClick={() => !effectuee && setValidateGroupe(g)}>
            <p className={`font-semibold text-sm ${effectuee || allDone ? 'text-gray-400 line-through' : 'text-gray-800'}`}>
              {g.label}
            </p>
            <p className="text-xs text-gray-400 mt-0.5">Protocole · {total} animal{total > 1 ? 'x' : ''}</p>
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            {!effectuee && (
              <span className={`text-sm font-bold ${allDone ? 'text-gray-400' : 'text-teal-600'}`}>{done}/{total}</span>
            )}
            <button onClick={() => setConfirmDelete({
              label: `Supprimer le protocole "${g.label}" de ce jour ?`,
              onConfirm: () => deleteGroupe(g),
            })} className="p-1 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
          </div>
        </div>
        {total > 1 && !effectuee && (
          <div className="mt-3">
            <div className="w-full bg-gray-100 rounded-full h-1.5">
              <div className={`h-1.5 rounded-full transition-all ${allDone ? 'bg-gray-300' : 'bg-teal-500'}`}
                style={{ width: `${pct * 100}%` }} />
            </div>
          </div>
        )}
      </div>
    );
  };

  const ManuelRow = ({ t }: { t: TacheManuelle }) => {
    const isDone    = t.statut === 'fait';
    const nomFor    = (uid: string | null | undefined) => uid ? (employes.find(e => e.uid === uid)?.nom ?? uid.slice(0,8)) : null;
    const assignees = t.assignes_a?.length ? t.assignes_a : (t.assigne_a ? [t.assigne_a] : []);
    const faitPar   = nomFor(t.fait_par);
    return (
      <div
        className="rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3"
        style={{
          borderLeftWidth: '4px',
          borderLeftColor: isDone ? '#6E9E57' : '#0C5C6C',
          backgroundColor: isDone ? '#F4FAF1' : 'white',
        }}
      >
        <button onClick={() => toggleManuel(t)}
          className={`w-6 h-6 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
            isDone ? 'border-[#6E9E57] bg-[#6E9E57]' : 'border-gray-300 hover:border-teal-400'
          }`}>
          {isDone && <span className="text-white text-xs font-bold leading-none">✓</span>}
        </button>
        <div className="flex-1 min-w-0">
          <span className="text-sm font-medium text-gray-800">{t.titre}</span>
          {t.heure && !isDone && (
            <p className="text-xs text-gray-400 mt-0.5">🕐 {t.heure}</p>
          )}
          {isDone && (
            <span className="inline-flex items-center gap-1 text-xs font-semibold px-2 py-0.5 rounded-full mt-1"
              style={{ backgroundColor: '#E8F5E2', color: '#4A7C3A' }}>
              ✓ Effectué{faitPar ? ` par ${faitPar}` : ''}
            </span>
          )}
          {!isDone && assignees.length > 0 && (
            <p className="text-xs text-teal-600 mt-0.5">
              👤 {assignees.map(uid => nomFor(uid) ?? '').join(', ')}
            </p>
          )}
        </div>
        {!isDone && employes.length > 0 && (
          <button onClick={() => setAttributionTask(t)}
            className="text-xs text-teal-600 border border-teal-200 rounded-full px-2 py-0.5 hover:bg-teal-50 flex-shrink-0">
            {assignees.length > 0 ? '✎' : '+ Attrib.'}
          </button>
        )}
        <button onClick={() => deleteManuel(t)}
          className="p-1 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 flex-shrink-0">
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      </div>
    );
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">

      {/* Header + toggle vue */}
      <div className="flex items-center justify-between mb-5">
        <h1 className="text-2xl font-bold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>Agenda</h1>
        <div className="flex bg-gray-100 rounded-xl p-1 gap-0.5">
          {(['mois', 'semaine', 'jour'] as ViewMode[]).map(v => (
            <button key={v} onClick={() => setViewMode(v)}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all capitalize ${
                viewMode === v
                  ? 'bg-white text-teal-700 shadow-sm'
                  : 'text-gray-500 hover:text-gray-700'
              }`}>
              {v}
            </button>
          ))}
        </div>
      </div>

      {/* ── VUE MOIS ─────────────────────────────────────────────────────────── */}
      {viewMode === 'mois' && (
        <>
          {/* Calendrier */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
            <div className="flex items-center justify-between mb-3">
              <button onClick={() => { if (focusedMois === 0) { setFocusedYear(y => y-1); setFocusedMois(11); } else setFocusedMois(m => m-1); }}
                className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">‹</button>
              <span className="font-bold text-sm capitalize text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
                {new Date(focusedYear, focusedMois, 1).toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })}
              </span>
              <button onClick={() => { if (focusedMois === 11) { setFocusedYear(y => y+1); setFocusedMois(0); } else setFocusedMois(m => m+1); }}
                className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">›</button>
            </div>
            <div className="grid grid-cols-7 mb-1">
              {['L','M','M','J','V','S','D'].map((d, i) => (
                <div key={i} className="text-center text-xs font-semibold text-gray-400 py-1">{d}</div>
              ))}
            </div>
            <div className="grid grid-cols-7 gap-1">
              {calCells.map((day, i) => {
                if (!day) return <div key={i} />;
                const ds    = `${focusedYear}-${String(focusedMois+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
                const isT   = day === today.getDate() && focusedMois === today.getMonth() && focusedYear === today.getFullYear();
                const isSel = ds === selectedDate;
                const colors = monthDates.get(ds) ?? [];
                return (
                  <button key={i} onClick={() => handleSelectDate(ds)}
                    className="aspect-square rounded-xl flex flex-col items-center justify-center gap-0.5 transition-colors"
                    style={{ background: isSel ? '#0d9488' : isT ? '#ccfbf1' : 'white',
                             border: isT && !isSel ? '1.5px solid #0d9488' : '1.5px solid transparent' }}>
                    <span className="text-sm font-bold" style={{ color: isSel ? 'white' : '#374151' }}>{day}</span>
                    {colors.length > 0 && (
                      <div className="flex gap-0.5">
                        {colors.slice(0,3).map((c, ci) => (
                          <div key={ci} className="w-1.5 h-1.5 rounded-full"
                            style={{ background: isSel ? 'rgba(255,255,255,0.75)' : c }} />
                        ))}
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Navigateur jour */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-3 mb-4">
            <div className="flex items-center justify-between">
              <button onClick={() => {
                const d = new Date(selectedDate+'T12:00:00'); d.setDate(d.getDate()-1);
                handleSelectDate(toISODate(d));
              }} className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">‹</button>
              <div className="text-center">
                <span className="font-bold text-sm capitalize text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {dateLabel}
                </span>
                {totalItems > 0 && (
                  <span className="ml-2 text-xs font-semibold text-teal-700 bg-teal-50 border border-teal-200 px-2 py-0.5 rounded-full">
                    {doneItems}/{totalItems}
                  </span>
                )}
              </div>
              <button onClick={() => {
                const d = new Date(selectedDate+'T12:00:00'); d.setDate(d.getDate()+1);
                handleSelectDate(toISODate(d));
              }} className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">›</button>
            </div>
          </div>

          {/* Boutons ajout */}
          <div className="flex justify-end gap-2 mb-3">
            <button onClick={() => setShowAddProtocole(true)}
              className="flex items-center gap-1.5 text-sm font-semibold rounded-xl px-3 py-2 border transition-colors"
              style={{ color: '#92400E', backgroundColor: '#FFF7ED', borderColor: '#FED7AA' }}
              onMouseEnter={e => (e.currentTarget.style.backgroundColor = '#FEF3C7')}
              onMouseLeave={e => (e.currentTarget.style.backgroundColor = '#FFF7ED')}>
              <span className="text-base leading-none">+</span> Protocole
            </button>
            <button onClick={() => setShowAddTache(true)}
              className="flex items-center gap-1.5 text-sm font-semibold text-teal-700 bg-teal-50 border border-teal-200 rounded-xl px-3 py-2 hover:bg-teal-100 transition-colors">
              <span className="text-base leading-none">+</span> Tâche
            </button>
          </div>

          {/* Liste du jour */}
          {loadingData ? (
            <div className="flex justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
            </div>
          ) : totalItems === 0 ? (
            <div className="text-center py-16">
              <div className="text-5xl mb-4">✅</div>
              <p className="text-gray-500 mb-2">Rien de prévu ce jour</p>
              <p className="text-gray-400 text-sm">
                Créez des protocoles depuis{' '}
                <a href="/elevage/planning" className="text-teal-600 underline font-medium">Planning</a>
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {groupesEnCours.map(g => <GroupeCard key={g.etapeId} g={g} />)}
              {tachesMEnCours.length > 0 && groupesEnCours.length > 0 && (
                <div className="flex items-center gap-2 py-1">
                  <div className="flex-1 h-px bg-gray-200" />
                  <span className="text-xs text-gray-400 font-semibold px-1">Tâches manuelles</span>
                  <div className="flex-1 h-px bg-gray-200" />
                </div>
              )}
              {tachesMEnCours.map(t => <ManuelRow key={t.id} t={t} />)}
              {doneItems > 0 && (
                <>
                  <div className="flex items-center gap-2 py-1">
                    <div className="flex-1 h-px bg-gray-200" />
                    <span className="text-xs text-gray-400 font-semibold px-2">Effectuées ({doneItems})</span>
                    <div className="flex-1 h-px bg-gray-200" />
                  </div>
                  {groupesEffectuees.map(g => <GroupeCard key={g.etapeId} g={g} effectuee />)}
                  {tachesMEffectuees.map(t => <ManuelRow key={t.id} t={t} />)}
                </>
              )}
            </div>
          )}
        </>
      )}

      {/* ── VUE SEMAINE ──────────────────────────────────────────────────────── */}
      {viewMode === 'semaine' && (
        <>
          <WeekStrip selectedDate={selectedDate} onSelectDay={handleSelectDate} monthDates={monthDates} />

          {/* Navigateur jour */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-3 mb-4">
            <div className="flex items-center justify-between">
              <button onClick={() => {
                const d = new Date(selectedDate+'T12:00:00'); d.setDate(d.getDate()-1);
                handleSelectDate(toISODate(d));
              }} className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">‹</button>
              <div className="text-center">
                <span className="font-bold text-sm capitalize text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {dateLabel}
                </span>
                {totalItems > 0 && (
                  <span className="ml-2 text-xs font-semibold text-teal-700 bg-teal-50 border border-teal-200 px-2 py-0.5 rounded-full">
                    {doneItems}/{totalItems}
                  </span>
                )}
              </div>
              <button onClick={() => {
                const d = new Date(selectedDate+'T12:00:00'); d.setDate(d.getDate()+1);
                handleSelectDate(toISODate(d));
              }} className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">›</button>
            </div>
          </div>

          {/* Boutons ajout */}
          <div className="flex justify-end gap-2 mb-3">
            <button onClick={() => setShowAddProtocole(true)}
              className="flex items-center gap-1.5 text-sm font-semibold rounded-xl px-3 py-2 border transition-colors"
              style={{ color: '#92400E', backgroundColor: '#FFF7ED', borderColor: '#FED7AA' }}
              onMouseEnter={e => (e.currentTarget.style.backgroundColor = '#FEF3C7')}
              onMouseLeave={e => (e.currentTarget.style.backgroundColor = '#FFF7ED')}>
              <span className="text-base leading-none">+</span> Protocole
            </button>
            <button onClick={() => setShowAddTache(true)}
              className="flex items-center gap-1.5 text-sm font-semibold text-teal-700 bg-teal-50 border border-teal-200 rounded-xl px-3 py-2 hover:bg-teal-100 transition-colors">
              <span className="text-base leading-none">+</span> Tâche
            </button>
          </div>

          {loadingData ? (
            <div className="flex justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
            </div>
          ) : totalItems === 0 ? (
            <div className="text-center py-16">
              <div className="text-5xl mb-4">✅</div>
              <p className="text-gray-500 mb-2">Rien de prévu ce jour</p>
            </div>
          ) : (
            <DayTimeline
              groupes={groupes}
              tachesM={tachesM}
              employes={employes}
              currentUid={user.uid}
              selectedDate={selectedDate}
              onValidateGroupe={setValidateGroupe}
              onToggleManuel={toggleManuel}
              onAttributeManuel={setAttributionTask}
              onDeleteManuel={deleteManuel}
              onDeleteGroupe={g => setConfirmDelete({
                label: `Supprimer le protocole "${g.label}" de ce jour ?`,
                onConfirm: () => deleteGroupe(g),
              })}
              load={load}
            />
          )}
        </>
      )}

      {/* ── VUE JOUR ─────────────────────────────────────────────────────────── */}
      {viewMode === 'jour' && (
        <>
          {/* Navigateur jour */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-3 mb-4">
            <div className="flex items-center justify-between">
              <button onClick={() => {
                const d = new Date(selectedDate+'T12:00:00'); d.setDate(d.getDate()-1);
                handleSelectDate(toISODate(d));
              }} className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">‹</button>
              <div className="text-center">
                <span className="font-bold text-sm capitalize text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {dateLabel}
                </span>
                {totalItems > 0 && (
                  <span className="ml-2 text-xs font-semibold text-teal-700 bg-teal-50 border border-teal-200 px-2 py-0.5 rounded-full">
                    {doneItems}/{totalItems}
                  </span>
                )}
              </div>
              <button onClick={() => {
                const d = new Date(selectedDate+'T12:00:00'); d.setDate(d.getDate()+1);
                handleSelectDate(toISODate(d));
              }} className="p-2 rounded-lg hover:bg-gray-100 text-teal-600 text-xl font-light">›</button>
            </div>
          </div>

          {/* Boutons ajout */}
          <div className="flex justify-end gap-2 mb-3">
            <button onClick={() => setShowAddProtocole(true)}
              className="flex items-center gap-1.5 text-sm font-semibold rounded-xl px-3 py-2 border transition-colors"
              style={{ color: '#92400E', backgroundColor: '#FFF7ED', borderColor: '#FED7AA' }}
              onMouseEnter={e => (e.currentTarget.style.backgroundColor = '#FEF3C7')}
              onMouseLeave={e => (e.currentTarget.style.backgroundColor = '#FFF7ED')}>
              <span className="text-base leading-none">+</span> Protocole
            </button>
            <button onClick={() => setShowAddTache(true)}
              className="flex items-center gap-1.5 text-sm font-semibold text-teal-700 bg-teal-50 border border-teal-200 rounded-xl px-3 py-2 hover:bg-teal-100 transition-colors">
              <span className="text-base leading-none">+</span> Tâche
            </button>
          </div>

          {loadingData ? (
            <div className="flex justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
            </div>
          ) : totalItems === 0 ? (
            <div className="text-center py-16">
              <div className="text-5xl mb-4">✅</div>
              <p className="text-gray-500 mb-2">Rien de prévu ce jour</p>
              <p className="text-gray-400 text-sm">
                Créez des protocoles depuis{' '}
                <a href="/elevage/planning" className="text-teal-600 underline font-medium">Planning</a>
              </p>
            </div>
          ) : (
            <DayTimeline
              groupes={groupes}
              tachesM={tachesM}
              employes={employes}
              currentUid={user.uid}
              selectedDate={selectedDate}
              onValidateGroupe={setValidateGroupe}
              onToggleManuel={toggleManuel}
              onAttributeManuel={setAttributionTask}
              onDeleteManuel={deleteManuel}
              onDeleteGroupe={g => setConfirmDelete({
                label: `Supprimer le protocole "${g.label}" de ce jour ?`,
                onConfirm: () => deleteGroupe(g),
              })}
              load={load}
            />
          )}
        </>
      )}

      {/* ── Modals ──────────────────────────────────────────────────────────── */}

      {showAddTache && (
        <AddTacheModal
          selectedDate={selectedDate}
          uid={user.uid}
          profilSource={profilSource}
          onClose={() => setShowAddTache(false)}
          onSaved={() => { setShowAddTache(false); load(); }}
        />
      )}

      {showAddProtocole && (
        <AddProtocoleModal
          selectedDate={selectedDate}
          uid={user.uid}
          profilSource={profilSource}
          onClose={() => setShowAddProtocole(false)}
          onSaved={() => { setShowAddProtocole(false); load(); }}
        />
      )}

      {validateGroupe && (
        <RoutineModal
          groupe={validateGroupe}
          selectedDate={selectedDate}
          employes={employes}
          currentUid={user.uid}
          onClose={() => setValidateGroupe(null)}
          onUpdated={() => { setValidateGroupe(null); load(); }}
          onDeleteGroupe={g => {
            setValidateGroupe(null);
            setConfirmDelete({
              label: `Supprimer le protocole "${g.label}" de ce jour ?`,
              onConfirm: () => deleteGroupe(g),
            });
          }}
        />
      )}

      {attributionTask && (
        <AttributionModal
          tache={attributionTask}
          employes={employes}
          currentUid={user.uid}
          onClose={() => setAttributionTask(null)}
          onSaved={() => { setAttributionTask(null); load(); }}
        />
      )}

      {confirmDelete && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl p-6 max-w-sm w-full shadow-xl">
            <p className="text-sm font-semibold text-gray-800 mb-5 text-center">{confirmDelete.label}</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmDelete(null)}
                className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
                Annuler
              </button>
              <button onClick={() => { confirmDelete.onConfirm(); setConfirmDelete(null); }}
                className="flex-1 py-2.5 bg-red-500 text-white rounded-xl text-sm font-semibold hover:bg-red-600">
                Supprimer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
