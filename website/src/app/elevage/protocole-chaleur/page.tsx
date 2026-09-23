'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const GREEN = '#6E9E57';

const ESPECES = ['chien', 'chat', 'lapin', 'oiseau', 'nac', 'cheval', 'ovin', 'caprin', 'porcin', 'autre'];

function capitalize(s: string) {
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}

interface ProtocoleRow {
  id: string;
  espece: string;
  race: string;
  intervalle_jours: number;
}

/**
 * Protocole de chaleur par race — même fonctionnalité que côté app
 * (protocole_chaleur_page.dart) : permet à l'éleveur de définir un
 * intervalle de chaleurs propre à chaque race qu'il élève (ex. Pomsky =
 * 120j) plutôt que de dépendre uniquement de la moyenne par espèce.
 */
export default function ProtocoleChaleurPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();

  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<ProtocoleRow[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<ProtocoleRow | null>(null);

  async function load() {
    if (!user) return;
    setLoading(true);
    const { data } = await supabase.from('protocoles_chaleur_race')
      .select('id, espece, race, intervalle_jours')
      .eq('uid_eleveur', user.uid)
      .order('espece').order('race');
    setRows((data ?? []) as ProtocoleRow[]);
    setLoading(false);
  }

  useEffect(() => { if (!authLoading && user) load(); }, [authLoading, user]);

  async function deleteRow(id: string) {
    if (!confirm('Supprimer ce protocole ?')) return;
    await supabase.from('protocoles_chaleur_race').delete().eq('id', id);
    setRows(rows.filter(r => r.id !== id));
  }

  if (authLoading || loading) return <div className="max-w-2xl mx-auto p-6 text-center text-gray-400">Chargement…</div>;

  return (
    <div className="max-w-2xl mx-auto p-4 sm:p-6">
      <div className="flex items-center gap-3 mb-1">
        <button onClick={() => router.back()} className="p-2 rounded-xl hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h1 className="text-xl font-bold" style={{ color: GREEN }}>🌸 Protocole chaleur</h1>
      </div>
      <p className="text-sm text-gray-500 mb-6 ml-12">
        Définissez un intervalle de chaleurs propre à chaque race que vous élevez, plutôt que de dépendre
        uniquement de la moyenne par espèce (ex. 6 mois pour un chien).
      </p>

      <div className="flex justify-end mb-4">
        <button
          onClick={() => { setEditing(null); setShowForm(true); }}
          className="px-4 py-2 rounded-xl text-white text-sm font-semibold hover:opacity-90"
          style={{ background: GREEN }}>
          + Nouveau
        </button>
      </div>

      {rows.length === 0 ? (
        <div className="text-center py-16 text-gray-400 text-sm">
          Aucun protocole personnalisé.<br />
          Par défaut, l&apos;intervalle moyen par espèce est utilisé. Ajoutez une race pour affiner (ex. Pomsky = 120j).
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map(r => (
            <div key={r.id} className="border border-gray-200 rounded-xl p-4 flex items-center justify-between bg-white">
              <div>
                <p className="text-sm font-semibold text-[#1F2A2E]">{r.race} ({capitalize(r.espece)})</p>
                <p className="text-xs text-gray-500 mt-0.5">{r.intervalle_jours} jours</p>
              </div>
              <div className="flex gap-2">
                <button onClick={() => { setEditing(r); setShowForm(true); }}
                  className="p-2 rounded-lg hover:bg-gray-100" style={{ color: GREEN }} title="Modifier">
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                  </svg>
                </button>
                <button onClick={() => deleteRow(r.id)}
                  className="p-2 rounded-lg hover:bg-red-50 text-red-400" title="Supprimer">
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {showForm && (
        <ProtocoleForm
          uidEleveur={user!.uid}
          existing={editing}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load(); }}
        />
      )}
    </div>
  );
}

function ProtocoleForm({ uidEleveur, existing, onClose, onSaved }: {
  uidEleveur: string; existing: ProtocoleRow | null; onClose: () => void; onSaved: () => void;
}) {
  const [espece, setEspece] = useState(existing?.espece ?? ESPECES[0]);
  const [race, setRace] = useState(existing?.race ?? '');
  const [jours, setJours] = useState(existing?.intervalle_jours?.toString() ?? '');
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    supabase.from('animaux').select('race').eq('uid_eleveur', uidEleveur).eq('espece', espece).not('race', 'is', null)
      .then(({ data }) => {
        if (cancelled) return;
        const set = new Set<string>();
        for (const r of data ?? []) { const v = (r.race as string | null)?.trim(); if (v) set.add(v); }
        setSuggestions([...set].sort());
      });
    return () => { cancelled = true; };
  }, [uidEleveur, espece]);

  const filteredSuggestions = race.trim()
    ? suggestions.filter(s => s.toLowerCase().includes(race.trim().toLowerCase()) && s.toLowerCase() !== race.trim().toLowerCase())
    : [];

  async function save() {
    const r = race.trim();
    const j = parseInt(jours, 10);
    if (!r) { setError('Indiquez une race.'); return; }
    if (!j || j <= 0) { setError('Indiquez un nombre de jours valide.'); return; }
    setSaving(true);
    setError(null);
    try {
      if (existing) {
        const { error: err } = await supabase.from('protocoles_chaleur_race')
          .update({ race: r, intervalle_jours: j }).eq('id', existing.id);
        if (err) throw err;
      } else {
        const { error: err } = await supabase.from('protocoles_chaleur_race')
          .upsert({ uid_eleveur: uidEleveur, espece, race: r, intervalle_jours: j }, { onConflict: 'uid_eleveur,espece,race' });
        if (err) throw err;
      }
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Une erreur est survenue.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-end sm:items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-md p-6 max-h-[85vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <h2 className="text-lg font-bold text-gray-800 mb-4">{existing ? 'Modifier le protocole' : 'Nouveau protocole chaleur'}</h2>

        <label className="block text-sm font-semibold text-gray-700 mb-1">Espèce</label>
        <select value={espece} disabled={!!existing}
          onChange={e => setEspece(e.target.value)}
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm mb-4 disabled:bg-gray-100 disabled:text-gray-400">
          {ESPECES.map(e => <option key={e} value={e}>{capitalize(e)}</option>)}
        </select>

        <label className="block text-sm font-semibold text-gray-700 mb-1">Race</label>
        <input
          type="text" value={race} onChange={e => setRace(e.target.value)}
          placeholder="Ex. Pomsky, Spitz…"
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm mb-2 focus:outline-none focus:ring-2 focus:ring-[#6E9E57]/30"
        />
        {filteredSuggestions.length > 0 && (
          <div className="flex flex-wrap gap-2 mb-4">
            {filteredSuggestions.map(s => (
              <button key={s} type="button" onClick={() => setRace(s)}
                className="px-3 py-1 rounded-full bg-gray-100 text-xs text-gray-600 hover:bg-gray-200">
                {s}
              </button>
            ))}
          </div>
        )}

        <label className="block text-sm font-semibold text-gray-700 mb-1">Intervalle (jours)</label>
        <input
          type="number" min="1" value={jours} onChange={e => setJours(e.target.value)}
          placeholder="Ex. 120"
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm mb-4 focus:outline-none focus:ring-2 focus:ring-[#6E9E57]/30"
        />

        {error && <p className="text-sm text-red-600 mb-4">{error}</p>}

        <div className="flex gap-2">
          <button onClick={onClose} disabled={saving}
            className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 disabled:opacity-50">
            Annuler
          </button>
          <button onClick={save} disabled={saving}
            className="flex-1 text-white text-sm font-semibold py-2.5 rounded-xl disabled:opacity-50"
            style={{ background: GREEN }}>
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}
