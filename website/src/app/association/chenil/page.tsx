'use client';

import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Enclos {
  id: string;
  nom: string;
  type: string;
  capacite: number;
  dernier_nettoyage: string | null;
  notes: string | null;
}

interface Animal {
  id: string;
  nom: string;
  espece: string | null;
  photo_url: string | null;
  statut: string | null;
  enclos_id: string | null;
}

// ── Constantes ────────────────────────────────────────────────────────────────

const TYPE_ICONS: Record<string, string> = {
  box: '🏠', enclos: '🌿', chatterie: '🐈', cage: '🔲',
};
const TYPE_LABELS: Record<string, string> = {
  box: 'Box', enclos: 'Enclos', chatterie: 'Chatterie', cage: 'Cage',
};
const STATUT_COLORS: Record<string, string> = {
  en_soin: 'bg-orange-100 text-orange-700',
  disponible: 'bg-green-100 text-green-700',
  en_fa: 'bg-purple-100 text-purple-700',
  adopte: 'bg-teal-100 text-teal-700',
  transfere: 'bg-blue-100 text-blue-700',
  present: 'bg-gray-100 text-gray-600',
};

function daysSince(dateStr: string | null): number | null {
  if (!dateStr) return null;
  return Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
}

function fmtDate(d: string | null) {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: '2-digit' });
}

// ── Composant enclos card ─────────────────────────────────────────────────────

function EnclosCard({
  enclos, occupants, allAnimaux,
  onEdit, onClean, onAssign,
}: {
  enclos: Enclos;
  occupants: Animal[];
  allAnimaux: Animal[];
  onEdit: (e: Enclos) => void;
  onClean: (id: string) => void;
  onAssign: (enclosId: string, animalId: string, assign: boolean) => void;
}) {
  const [showAssign, setShowAssign] = useState(false);
  const jours = daysSince(enclos.dernier_nettoyage);
  const pct = Math.min(occupants.length / Math.max(enclos.capacite, 1), 1);
  const barColor = pct >= 1 ? 'bg-red-400' : pct >= 0.7 ? 'bg-orange-400' : 'bg-green-400';

  const dispo = enclos.capacite - occupants.length;
  const cleanBadge = jours === null
    ? { label: 'Jamais nettoyé', cls: 'bg-red-100 text-red-600' }
    : jours === 0
    ? { label: 'Nettoyé aujourd\'hui', cls: 'bg-green-100 text-green-700' }
    : jours <= 2
    ? { label: `Il y a ${jours}j`, cls: 'bg-green-100 text-green-700' }
    : jours <= 7
    ? { label: `Il y a ${jours}j`, cls: 'bg-amber-100 text-amber-700' }
    : { label: `Il y a ${jours}j`, cls: 'bg-red-100 text-red-600' };

  const unassigned = allAnimaux.filter(a => !a.enclos_id || a.enclos_id === enclos.id);

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
      {/* Header */}
      <div className="bg-teal-50 px-4 py-3 flex items-center justify-between border-b border-teal-100">
        <div className="flex items-center gap-2">
          <span className="text-xl">{TYPE_ICONS[enclos.type] ?? '🏠'}</span>
          <div>
            <p className="font-bold font-galey text-teal-800 leading-tight">{enclos.nom}</p>
            <p className="text-xs text-teal-600">{TYPE_LABELS[enclos.type] ?? enclos.type}</p>
          </div>
        </div>
        <button onClick={() => onEdit(enclos)} className="text-gray-400 hover:text-teal-700 text-sm px-2 py-1 rounded-lg hover:bg-white/60 transition-colors">
          ✏️
        </button>
      </div>

      <div className="p-4 space-y-3">
        {/* Capacité */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-gray-500 font-galey">Occupation</span>
            <span className={`text-xs font-bold font-galey ${pct >= 1 ? 'text-red-600' : 'text-gray-700'}`}>
              {occupants.length}/{enclos.capacite} {dispo > 0 ? `· ${dispo} libre${dispo > 1 ? 's' : ''}` : '· Complet'}
            </span>
          </div>
          <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
            <div className={`h-full rounded-full transition-all ${barColor}`} style={{ width: `${pct * 100}%` }} />
          </div>
        </div>

        {/* Dernier nettoyage */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-1.5">
            <span className="text-sm">🧹</span>
            <span className={`text-xs font-galey font-semibold px-2 py-0.5 rounded-full ${cleanBadge.cls}`}>
              {cleanBadge.label}
            </span>
          </div>
          <button
            onClick={() => onClean(enclos.id)}
            className="text-xs font-galey font-semibold text-teal-700 border border-teal-200 px-2.5 py-1 rounded-full hover:bg-teal-50 transition-colors">
            Marquer propre
          </button>
        </div>

        {/* Notes */}
        {enclos.notes && (
          <p className="text-xs text-gray-400 font-galey italic border-l-2 border-teal-100 pl-2">{enclos.notes}</p>
        )}

        {/* Occupants */}
        <div>
          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2 font-galey">
            {occupants.length === 0 ? 'Aucun animal' : `${occupants.length} animal${occupants.length > 1 ? 'x' : ''}`}
          </p>
          <div className="space-y-1.5">
            {occupants.map(a => (
              <div key={a.id} className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-7 h-7 rounded-full overflow-hidden bg-teal-50 flex-shrink-0">
                    {a.photo_url
                      ? <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                      : <span className="w-full h-full flex items-center justify-center text-xs">🐾</span>}
                  </div>
                  <span className="text-sm font-galey font-semibold text-gray-800">{a.nom}</span>
                  {a.statut && (
                    <span className={`text-[10px] font-galey font-bold px-1.5 py-0.5 rounded-full ${STATUT_COLORS[a.statut] ?? 'bg-gray-100 text-gray-500'}`}>
                      {a.statut.replace('_', ' ')}
                    </span>
                  )}
                </div>
                <button onClick={() => onAssign(enclos.id, a.id, false)}
                  className="text-xs text-red-400 hover:text-red-600 px-1.5 py-0.5 rounded hover:bg-red-50 transition-colors">
                  ✕
                </button>
              </div>
            ))}
          </div>
        </div>

        {/* Bouton ajouter un animal */}
        {dispo > 0 && (
          <button
            onClick={() => setShowAssign(v => !v)}
            className="w-full text-xs font-galey font-semibold text-teal-700 border border-dashed border-teal-300 py-2 rounded-xl hover:bg-teal-50 transition-colors">
            + Ajouter un animal
          </button>
        )}

        {/* Dropdown assignation */}
        {showAssign && (
          <div className="border border-teal-100 rounded-xl overflow-hidden">
            {unassigned.filter(a => a.enclos_id !== enclos.id).length === 0 ? (
              <p className="text-xs text-gray-400 font-galey text-center py-3">Aucun animal disponible</p>
            ) : (
              unassigned.filter(a => a.enclos_id !== enclos.id).map(a => (
                <button key={a.id}
                  onClick={() => { onAssign(enclos.id, a.id, true); setShowAssign(false); }}
                  className="w-full flex items-center gap-2 px-3 py-2 text-sm font-galey text-gray-700 hover:bg-teal-50 border-b border-gray-50 last:border-0 transition-colors text-left">
                  <div className="w-6 h-6 rounded-full overflow-hidden bg-teal-50 flex-shrink-0">
                    {a.photo_url
                      ? <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                      : <span className="w-full h-full flex items-center justify-center text-[10px]">🐾</span>}
                  </div>
                  <span>{a.nom}</span>
                  {a.espece && <span className="text-gray-400 text-xs">· {a.espece}</span>}
                </button>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Modal enclos (ajout / édition) ────────────────────────────────────────────

function EnclosModal({ enclos, uid, isAssociation, onClose, onSaved }: {
  enclos: Enclos | null;
  uid: string;
  isAssociation: boolean;
  onClose: () => void;
  onSaved: (e: Enclos) => void;
}) {
  const [nom, setNom] = useState(enclos?.nom ?? '');
  const [type, setType] = useState(enclos?.type ?? 'box');
  const [capacite, setCapacite] = useState(enclos?.capacite ?? 1);
  const [notes, setNotes] = useState(enclos?.notes ?? '');
  const [saving, setSaving] = useState(false);

  async function handleSave(ev: React.FormEvent) {
    ev.preventDefault();
    if (!nom.trim()) return;
    setSaving(true);
    const payload = { nom: nom.trim(), type, capacite, notes: notes.trim() || null, uid_eleveur: uid, is_association: isAssociation };
    if (enclos) {
      const { data } = await supabase.from('enclos_chenil').update({ ...payload, updated_at: new Date().toISOString() }).eq('id', enclos.id).select().single();
      if (data) onSaved(data as Enclos);
    } else {
      const { data } = await supabase.from('enclos_chenil').insert(payload).select().single();
      if (data) onSaved(data as Enclos);
    }
    setSaving(false);
  }

  const inp = "w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300";

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-md" onClick={e => e.stopPropagation()}>
        <div className="bg-teal-700 text-white px-5 py-4 rounded-t-2xl">
          <h2 className="font-bold font-galey text-lg">{enclos ? 'Modifier l\'enclos' : 'Nouvel enclos'}</h2>
        </div>
        <form onSubmit={handleSave} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Nom *</label>
            <input value={nom} onChange={e => setNom(e.target.value)} placeholder="Ex: Box 1, Chatterie A…" className={inp} required />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Type</label>
              <select value={type} onChange={e => setType(e.target.value)} className={inp}>
                {Object.entries(TYPE_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Capacité</label>
              <input type="number" min={1} max={99} value={capacite} onChange={e => setCapacite(Number(e.target.value))} className={inp} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Notes</label>
            <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} placeholder="Infos utiles…" className={inp + ' resize-none'} />
          </div>
          <div className="flex gap-3 pt-1">
            <button type="submit" disabled={saving || !nom.trim()}
              className="flex-1 bg-teal-700 hover:bg-teal-800 disabled:opacity-50 text-white font-galey font-semibold py-2.5 rounded-xl text-sm transition-colors">
              {saving ? 'Enregistrement…' : (enclos ? 'Modifier' : 'Créer')}
            </button>
            <button type="button" onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-galey font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
              Annuler
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Page principale ───────────────────────────────────────────────────────────

function mondayOf(d: Date) {
  const day = new Date(d);
  day.setDate(d.getDate() - (d.getDay() === 0 ? 6 : d.getDay() - 1));
  day.setHours(0, 0, 0, 0);
  return day;
}
function addDays(d: Date, n: number) {
  const r = new Date(d); r.setDate(r.getDate() + n); return r;
}
const JOURS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

export default function ChenilWebPage() {
  const { user } = useAuth();
  const [enclos, setEnclos] = useState<Enclos[]>([]);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'enclos' | 'week'>('enclos');
  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()));
  const [editEnclos, setEditEnclos] = useState<Enclos | null | 'new'>( null);
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const [{ data: enc }, { data: ani }] = await Promise.all([
      supabase.from('enclos_chenil').select('*').eq('uid_eleveur', user.uid).eq('is_association', true).order('nom'),
      supabase.from('animaux').select('id, nom, espece, photo_url, statut, enclos_id, date_entree, date_sortie')
        .eq('uid_eleveur', user.uid).eq('is_association', true).order('nom'),
    ]);
    setEnclos((enc ?? []) as Enclos[]);
    setAnimaux((ani ?? []) as Animal[]);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function handleClean(enclosId: string) {
    const today = new Date().toISOString().slice(0, 10);
    await supabase.from('enclos_chenil').update({ dernier_nettoyage: today, updated_at: new Date().toISOString() }).eq('id', enclosId);
    setEnclos(prev => prev.map(e => e.id === enclosId ? { ...e, dernier_nettoyage: today } : e));
  }

  async function handleAssign(enclosId: string, animalId: string, assign: boolean) {
    await supabase.from('animaux').update({ enclos_id: assign ? enclosId : null }).eq('id', animalId);
    setAnimaux(prev => prev.map(a => a.id === animalId ? { ...a, enclos_id: assign ? enclosId : null } : a));
  }

  async function handleDelete(enclosId: string) {
    // Désassigner les animaux d'abord
    await supabase.from('animaux').update({ enclos_id: null }).eq('enclos_id', enclosId);
    await supabase.from('enclos_chenil').delete().eq('id', enclosId);
    setAnimaux(prev => prev.map(a => a.enclos_id === enclosId ? { ...a, enclos_id: null } : a));
    setEnclos(prev => prev.filter(e => e.id !== enclosId));
    setDeleteConfirm(null);
  }

  function handleSaved(saved: Enclos) {
    setEnclos(prev => {
      const idx = prev.findIndex(e => e.id === saved.id);
      if (idx >= 0) { const n = [...prev]; n[idx] = saved; return n; }
      return [...prev, saved].sort((a, b) => a.nom.localeCompare(b.nom));
    });
    setEditEnclos(null);
  }

  const days = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
  const today = new Date(); today.setHours(0, 0, 0, 0);

  function isPresent(a: Animal & { date_entree?: string; date_sortie?: string }, day: Date) {
    const ae = (a as any).date_entree;
    if (!ae) return false;
    const start = new Date(ae); start.setHours(0, 0, 0, 0);
    const end = (a as any).date_sortie ? new Date((a as any).date_sortie) : new Date('2099-12-31');
    end.setHours(0, 0, 0, 0);
    return day >= start && day <= end;
  }

  // Stats globales
  const totalPlaces = enclos.reduce((s, e) => s + e.capacite, 0);
  const occupes = animaux.filter(a => a.enclos_id).length;
  const sansEnclos = animaux.filter(a => !a.enclos_id && ['present', 'en_soin', 'disponible'].includes(a.statut ?? '')).length;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Chenil / Hébergement</h1>
        <button onClick={() => setEditEnclos('new')}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Enclos
        </button>
      </div>

      {/* Tabs */}
      <div className="flex gap-2">
        {(['enclos', 'week'] as const).map(t => (
          <button key={t} onClick={() => setActiveTab(t)}
            className={`px-4 py-2 rounded-full text-sm font-galey font-semibold transition-colors ${
              activeTab === t ? 'bg-teal-700 text-white' : 'bg-white border border-gray-200 text-gray-600 hover:bg-gray-50'}`}>
            {t === 'enclos' ? '🏠 Enclos' : '📅 Planning semaine'}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : activeTab === 'enclos' ? (
        <>
          {/* Résumé global */}
          {enclos.length > 0 && (
            <div className="grid grid-cols-3 gap-3">
              <div className="bg-white rounded-xl p-3 border border-gray-100 text-center">
                <p className="text-2xl font-bold font-galey text-teal-700">{occupes}/{totalPlaces}</p>
                <p className="text-xs text-gray-400 font-galey">Places occupées</p>
              </div>
              <div className="bg-white rounded-xl p-3 border border-gray-100 text-center">
                <p className="text-2xl font-bold font-galey text-green-600">{totalPlaces - occupes}</p>
                <p className="text-xs text-gray-400 font-galey">Places libres</p>
              </div>
              <div className="bg-white rounded-xl p-3 border border-gray-100 text-center">
                <p className={`text-2xl font-bold font-galey ${sansEnclos > 0 ? 'text-amber-500' : 'text-gray-400'}`}>{sansEnclos}</p>
                <p className="text-xs text-gray-400 font-galey">Sans enclos</p>
              </div>
            </div>
          )}

          {/* Grille d'enclos */}
          {enclos.length === 0 ? (
            <div className="text-center py-16 text-gray-400">
              <p className="text-5xl mb-3">🏠</p>
              <p className="font-galey font-semibold text-gray-600 mb-1">Aucun enclos configuré</p>
              <p className="text-sm mb-4">Créez vos boxes, chatteries et enclos pour gérer l'hébergement.</p>
              <button onClick={() => setEditEnclos('new')}
                className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800">
                Créer un enclos
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
              {enclos.map(e => (
                <div key={e.id}>
                  <EnclosCard
                    enclos={e}
                    occupants={animaux.filter(a => a.enclos_id === e.id)}
                    allAnimaux={animaux}
                    onEdit={enc => setEditEnclos(enc)}
                    onClean={handleClean}
                    onAssign={handleAssign}
                  />
                  {deleteConfirm === e.id ? (
                    <div className="mt-2 flex gap-2 items-center bg-red-50 rounded-xl px-3 py-2">
                      <p className="text-xs text-red-600 font-galey flex-1">Supprimer cet enclos ?</p>
                      <button onClick={() => handleDelete(e.id)} className="text-xs font-bold text-red-600 hover:text-red-800">Oui</button>
                      <button onClick={() => setDeleteConfirm(null)} className="text-xs text-gray-400 hover:text-gray-600 ml-1">Annuler</button>
                    </div>
                  ) : (
                    <button onClick={() => setDeleteConfirm(e.id)}
                      className="mt-1 w-full text-xs text-gray-300 hover:text-red-400 font-galey transition-colors text-center py-1">
                      Supprimer l'enclos
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Animaux sans enclos */}
          {sansEnclos > 0 && (
            <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4">
              <p className="text-sm font-bold font-galey text-amber-700 mb-2">⚠️ Animaux sans enclos assigné ({sansEnclos})</p>
              <div className="flex flex-wrap gap-2">
                {animaux
                  .filter(a => !a.enclos_id && ['present', 'en_soin', 'disponible'].includes(a.statut ?? ''))
                  .map(a => (
                    <div key={a.id} className="flex items-center gap-1.5 bg-white rounded-full px-3 py-1 border border-amber-200">
                      <span className="text-xs font-galey font-semibold text-gray-700">{a.nom}</span>
                      {a.espece && <span className="text-xs text-gray-400">· {a.espece}</span>}
                    </div>
                  ))}
              </div>
            </div>
          )}
        </>
      ) : (
        /* ── Planning semaine ── */
        <div className="bg-white rounded-2xl shadow-sm overflow-hidden border border-gray-100">
          <div className="flex items-center justify-between px-4 py-3 bg-teal-50 border-b border-teal-100">
            <button onClick={() => setWeekStart(d => addDays(d, -7))}
              className="text-teal-700 hover:text-teal-900 font-bold text-lg px-2">‹</button>
            <p className="font-bold font-galey text-teal-800 text-sm">
              Semaine du {weekStart.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' })}
            </p>
            <button onClick={() => setWeekStart(d => addDays(d, 7))}
              className="text-teal-700 hover:text-teal-900 font-bold text-lg px-2">›</button>
          </div>
          <div className="flex border-b border-gray-100">
            <div className="w-28 flex-shrink-0" />
            {days.map((d, i) => {
              const isToday = d.getTime() === today.getTime();
              return (
                <div key={i} className={`flex-1 text-center py-2 text-xs font-galey ${isToday ? 'bg-teal-50 text-teal-700 font-bold' : 'text-gray-500'}`}>
                  <p>{JOURS[i]}</p>
                  <p className="font-bold">{d.getDate()}</p>
                </div>
              );
            })}
          </div>
          {animaux.length === 0 ? (
            <div className="text-center py-8 text-gray-400 font-galey text-sm">Aucun animal</div>
          ) : (
            animaux.map(a => {
              const sc = a.statut ? STATUT_COLORS[a.statut] : null;
              const enclosNom = enclos.find(e => e.id === a.enclos_id)?.nom;
              return (
                <div key={a.id} className="flex border-b border-gray-50 hover:bg-gray-50/50">
                  <div className="w-28 flex-shrink-0 flex flex-col justify-center px-3 py-2">
                    <span className="text-xs font-galey font-semibold text-gray-800 truncate">{a.nom}</span>
                    {enclosNom && <span className="text-[10px] text-teal-600 truncate">{enclosNom}</span>}
                  </div>
                  {days.map((d, i) => {
                    const present = isPresent(a as any, d);
                    return (
                      <div key={i}
                        className={`flex-1 mx-0.5 my-1.5 rounded ${present ? 'opacity-60' : ''} ${present && sc ? sc.split(' ')[0] : ''}`}
                        style={{ minHeight: 28 }} />
                    );
                  })}
                </div>
              );
            })
          )}
        </div>
      )}

      {/* Modal enclos */}
      {editEnclos !== null && (
        <EnclosModal
          enclos={editEnclos === 'new' ? null : editEnclos}
          uid={user?.uid ?? ''}
          isAssociation={true}
          onClose={() => setEditEnclos(null)}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}
