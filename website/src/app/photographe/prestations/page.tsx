'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const TEAL = '#90A4AE';

const TYPES_PRESTATION: Record<string, string> = {
  shooting_individuel: 'Shooting individuel',
  portee: 'Portée',
  elevage: 'Élevage',
  naissance: 'Naissance',
  concours: 'Concours',
  exposition: 'Exposition',
  commercial: 'Photos commerciales',
};

interface Prestation {
  id: string; type: string; nom: string; prix: number; duree_minutes: number;
  nb_photos: number | null; delai_livraison_jours: number;
  deplacement_inclus_km: number; prix_km_supp: number; acompte_pourcentage: number;
  description: string | null;
}

type FormState = {
  id?: string; type: string; nom: string; prix: string; duree_minutes: string;
  nb_photos: string; delai_livraison_jours: string; deplacement_inclus_km: string;
  prix_km_supp: string; acompte_pourcentage: string; description: string;
};

const EMPTY_FORM: FormState = {
  type: 'shooting_individuel', nom: '', prix: '', duree_minutes: '60',
  nb_photos: '', delai_livraison_jours: '7', deplacement_inclus_km: '0',
  prix_km_supp: '0', acompte_pourcentage: '30', description: '',
};

export default function PhotographePrestationsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [prestations, setPrestations] = useState<Prestation[]>([]);
  const [busy, setBusy] = useState(true);
  const [form, setForm] = useState<FormState | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!user?.uid) return;
    setBusy(true);
    let q = supabase.from('prestations_photographe').select('*').eq('pro_uid', user.uid).eq('actif', true);
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId);
    const { data } = await q.order('created_at');
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
        type: form.type,
        nom: form.nom.trim(),
        prix: Number(form.prix) || 0,
        duree_minutes: parseInt(form.duree_minutes, 10) || 60,
        nb_photos: form.nb_photos.trim() ? parseInt(form.nb_photos, 10) : null,
        delai_livraison_jours: parseInt(form.delai_livraison_jours, 10) || 7,
        deplacement_inclus_km: parseInt(form.deplacement_inclus_km, 10) || 0,
        prix_km_supp: Number(form.prix_km_supp) || 0,
        acompte_pourcentage: parseInt(form.acompte_pourcentage, 10) || 30,
        description: form.description.trim() || null,
      };
      if (form.id) {
        await supabase.from('prestations_photographe').update(payload).eq('id', form.id);
      } else {
        await supabase.from('prestations_photographe').insert({
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
    await supabase.from('prestations_photographe').update({ actif: false }).eq('id', id);
    await load();
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Mes prestations</h1>
        <button onClick={() => setForm({ ...EMPTY_FORM })}
          className="text-white rounded-xl px-3 py-2 text-sm font-semibold" style={{ background: TEAL }}>+ Prestation</button>
      </div>
      <p className="text-sm text-gray-500 mb-4">
        Définissez vos prestations (type, prix, durée) — le client les choisit directement lors de la réservation.
      </p>

      {form && (
        <div className="border rounded-2xl p-4 mb-4 space-y-3" style={{ borderColor: `${TEAL}55` }}>
          <select value={form.type} onChange={e => setForm({ ...form, type: e.target.value })}
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm">
            {Object.entries(TYPES_PRESTATION).map(([k, label]) => (
              <option key={k} value={k}>{label}</option>
            ))}
          </select>
          <input value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })}
            placeholder="Nom de la prestation"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          <div className="grid grid-cols-2 gap-3">
            <input type="number" value={form.prix} onChange={e => setForm({ ...form, prix: e.target.value })}
              placeholder="Prix (€)" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
            <input type="number" value={form.duree_minutes} onChange={e => setForm({ ...form, duree_minutes: e.target.value })}
              placeholder="Durée (min)" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <input type="number" value={form.nb_photos} onChange={e => setForm({ ...form, nb_photos: e.target.value })}
              placeholder="Nb de photos" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
            <input type="number" value={form.delai_livraison_jours} onChange={e => setForm({ ...form, delai_livraison_jours: e.target.value })}
              placeholder="Délai livraison (j)" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <input type="number" value={form.deplacement_inclus_km} onChange={e => setForm({ ...form, deplacement_inclus_km: e.target.value })}
              placeholder="Km inclus" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
            <input type="number" value={form.prix_km_supp} onChange={e => setForm({ ...form, prix_km_supp: e.target.value })}
              placeholder="Prix/km suppl. (€)" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          </div>
          <input type="number" value={form.acompte_pourcentage} onChange={e => setForm({ ...form, acompte_pourcentage: e.target.value })}
            placeholder="Acompte (%)" className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          <textarea value={form.description} onChange={e => setForm({ ...form, description: e.target.value })}
            rows={2} placeholder="Description (optionnel)"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
          <div className="flex gap-2">
            <button onClick={() => setForm(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
            <button onClick={save} disabled={saving || !form.nom.trim()}
              className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: TEAL }}>
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
          </div>
        </div>
      )}

      {busy ? (
        <p className="text-sm text-gray-400">Chargement…</p>
      ) : prestations.length === 0 ? (
        <p className="text-sm text-gray-400">Aucune prestation configurée. Ajoutez-en une avec le bouton « + Prestation ».</p>
      ) : (
        <div className="space-y-2">
          {prestations.map(p => (
            <div key={p.id} className="border border-gray-100 rounded-xl p-3 flex items-start gap-3">
              <button type="button"
                onClick={() => setForm({
                  id: p.id, type: p.type, nom: p.nom, prix: String(p.prix),
                  duree_minutes: String(p.duree_minutes), nb_photos: p.nb_photos != null ? String(p.nb_photos) : '',
                  delai_livraison_jours: String(p.delai_livraison_jours),
                  deplacement_inclus_km: String(p.deplacement_inclus_km), prix_km_supp: String(p.prix_km_supp),
                  acompte_pourcentage: String(p.acompte_pourcentage), description: p.description ?? '',
                })}
                className="flex-1 min-w-0 text-left">
                <p className="text-sm font-semibold text-[#1F2A2E]">📷 {p.nom}</p>
                <p className="text-xs text-gray-500">
                  {TYPES_PRESTATION[p.type] ?? p.type} · {p.prix.toFixed(0)} € · {p.duree_minutes} min
                </p>
                {p.description && <p className="text-xs text-gray-600 mt-0.5 line-clamp-2">{p.description}</p>}
              </button>
              <button onClick={() => remove(p.id)} className="text-gray-300 hover:text-red-400 shrink-0">🗑</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
