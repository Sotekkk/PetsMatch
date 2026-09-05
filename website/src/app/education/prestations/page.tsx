'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const PURPLE = '#7B5EA7';

interface Prestation {
  id: string; nom: string; description: string | null;
  duree_minutes: number; prix: number | null;
  bilan_requis: boolean; domicile_ok: boolean;
  type: 'individuel' | 'collectif'; capacite_max: number | null;
}

// Interrupteur toujours visible (fond coloré à l'état actif) — remplace les
// cases à cocher trop discrètes signalées par l'utilisatrice.
function Toggle({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <div className="flex items-center justify-between gap-4 rounded-xl border p-3"
      style={{ borderColor: checked ? PURPLE : '#E5E7EB', background: checked ? `${PURPLE}0D` : 'white' }}>
      <div>
        <p className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif', color: checked ? PURPLE : '#374151' }}>{label}</p>
        {hint && <p className="text-xs text-gray-500 mt-0.5">{hint}</p>}
      </div>
      <button type="button" onClick={() => onChange(!checked)}
        className="relative w-12 h-7 rounded-full transition-colors flex-shrink-0"
        style={{ backgroundColor: checked ? PURPLE : '#D1D5DB' }}>
        <span className="absolute top-0.5 left-0.5 w-6 h-6 bg-white rounded-full shadow transition-transform"
          style={{ transform: checked ? 'translateX(20px)' : 'translateX(0)' }} />
      </button>
    </div>
  );
}

function Badge({ active, activeLabel, inactiveLabel }: { active: boolean; activeLabel: string; inactiveLabel: string }) {
  return (
    <span className="text-xs font-semibold px-2 py-0.5 rounded-full"
      style={active ? { background: `${PURPLE}1A`, color: PURPLE } : { background: '#F3F4F6', color: '#9CA3AF' }}>
      {active ? activeLabel : inactiveLabel}
    </span>
  );
}

export default function EducationPrestationsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [prestations, setPrestations] = useState<Prestation[]>([]);
  const [busy, setBusy] = useState(true);
  const [form, setForm] = useState<{ id?: string; nom: string; description: string; duree_minutes: string; prix: string; bilan_requis: boolean; domicile_ok: boolean; type: 'individuel' | 'collectif'; capacite_max: string } | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!user?.uid) return;
    setBusy(true);
    let q = supabase.from('prestations_education')
      .select('id, nom, description, duree_minutes, prix, bilan_requis, domicile_ok, type, capacite_max')
      .eq('pro_uid', user.uid).eq('actif', true);
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId);
    const { data } = await q.order('ordre').order('created_at');
    setPrestations((data ?? []) as Prestation[]);
    setBusy(false);
  }, [user, activeProfileId]);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => { load(); }, [load]);

  async function save() {
    if (!form || !form.nom.trim() || !user?.uid) return;
    setSaving(true);
    try {
      const payload = {
        nom: form.nom.trim(),
        type: form.type,
        description: form.description.trim() || null,
        duree_minutes: parseInt(form.duree_minutes, 10) || 60,
        prix: form.prix.trim() ? Number(form.prix) : null,
        bilan_requis: form.bilan_requis,
        domicile_ok: form.domicile_ok,
        ...(form.type === 'collectif' ? { capacite_max: parseInt(form.capacite_max, 10) || 6 } : {}),
      };
      if (form.id) {
        await supabase.from('prestations_education').update(payload).eq('id', form.id);
      } else {
        await supabase.from('prestations_education').insert({
          ...payload, pro_uid: user.uid, pro_profile_id: activeProfileId || null,
        });
      }
      setForm(null);
      await load();
    } finally {
      setSaving(false);
    }
  }

  async function remove(id: string) {
    await supabase.from('prestations_education').update({ actif: false }).eq('id', id);
    await load();
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Mes cours</h1>
        <button onClick={() => setForm({ nom: '', description: '', duree_minutes: '60', prix: '', bilan_requis: false, domicile_ok: true, type: 'individuel', capacite_max: '6' })}
          className="text-white rounded-xl px-3 py-2 text-sm font-semibold" style={{ background: PURPLE }}>+ Cours</button>
      </div>
      <p className="text-sm text-gray-500 mb-4">
        Définissez vos types de cours (nom, durée, prix) — la famille les choisit directement dans le calendrier de réservation de votre fiche.
      </p>

      {form && (
        <div className="border rounded-2xl p-4 mb-4 space-y-3" style={{ borderColor: `${PURPLE}55` }}>
          <div className="flex gap-2">
            {(['individuel', 'collectif'] as const).map(t => (
              <button key={t} type="button" onClick={() => setForm({ ...form, type: t })}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold border-2 transition-all"
                style={{
                  background: form.type === t ? `${PURPLE}18` : 'white',
                  borderColor: form.type === t ? PURPLE : '#e5e7eb',
                  color: form.type === t ? PURPLE : '#6B7280',
                }}>
                {t === 'individuel' ? '🎓 Individuel' : '👥 Collectif'}
              </button>
            ))}
          </div>
          <input value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })}
            placeholder="Nom du cours — ex : Rappel chiot"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          <div className="grid grid-cols-2 gap-3">
            <input type="number" value={form.duree_minutes} onChange={e => setForm({ ...form, duree_minutes: e.target.value })}
              placeholder="Durée (min)" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
            <input type="number" value={form.prix} onChange={e => setForm({ ...form, prix: e.target.value })}
              placeholder="Prix (€, optionnel)" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          </div>
          {form.type === 'collectif' && (
            <input type="number" value={form.capacite_max} onChange={e => setForm({ ...form, capacite_max: e.target.value })}
              placeholder="Capacité max" className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          )}
          <textarea value={form.description} onChange={e => setForm({ ...form, description: e.target.value })}
            rows={2} placeholder="Description (optionnel)"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
          <Toggle checked={form.bilan_requis} onChange={v => setForm({ ...form, bilan_requis: v })}
            label="Nécessite un bilan préalable"
            hint="Proposé en priorité aux nouvelles familles si l'option « Bilan obligatoire » est activée" />
          <Toggle checked={form.domicile_ok} onChange={v => setForm({ ...form, domicile_ok: v })}
            label="Peut être proposé à domicile"
            hint="La famille pourra le demander à domicile sur les créneaux que vous autorisez" />
          <div className="flex gap-2">
            <button onClick={() => setForm(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
            <button onClick={save} disabled={saving || !form.nom.trim()}
              className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: PURPLE }}>
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
          </div>
        </div>
      )}

      {busy ? (
        <p className="text-sm text-gray-400">Chargement…</p>
      ) : prestations.length === 0 ? (
        <p className="text-sm text-gray-400">Aucun cours configuré. Ajoutez-en un avec le bouton « + Cours ».</p>
      ) : (
        <div className="space-y-2">
          {prestations.map(p => (
            <div key={p.id} className="border border-gray-100 rounded-xl p-3 flex items-start gap-3">
              <button type="button"
                onClick={() => setForm({
                  id: p.id, nom: p.nom, description: p.description ?? '',
                  duree_minutes: String(p.duree_minutes), prix: p.prix != null ? String(p.prix) : '',
                  bilan_requis: p.bilan_requis, domicile_ok: p.domicile_ok,
                  type: p.type ?? 'individuel', capacite_max: p.capacite_max != null ? String(p.capacite_max) : '6',
                })}
                className="flex-1 min-w-0 text-left">
                <p className="text-sm font-semibold text-[#1F2A2E] flex items-center gap-1.5">
                  <span>{p.type === 'collectif' ? '👥' : '🎓'}</span> {p.nom}
                </p>
                <p className="text-xs text-gray-500">
                  {p.type === 'collectif' ? `Collectif (max ${p.capacite_max ?? 6})` : 'Individuel'} · {p.duree_minutes} min{p.prix != null ? ` · ${p.prix.toFixed(0)} €` : ''}
                </p>
                {p.description && <p className="text-xs text-gray-600 mt-0.5 line-clamp-2">{p.description}</p>}
                <div className="flex gap-1.5 mt-1.5">
                  <Badge active={p.bilan_requis} activeLabel="Bilan requis" inactiveLabel="Sans bilan" />
                  <Badge active={p.domicile_ok} activeLabel="À domicile possible" inactiveLabel="Chez le pro uniquement" />
                </div>
              </button>
              <button onClick={() => remove(p.id)} className="text-gray-300 hover:text-red-400 shrink-0">🗑</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
