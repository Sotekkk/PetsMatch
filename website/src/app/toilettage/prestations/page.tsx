'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import CartesSeances from '@/components/toilettage/CartesSeances';

const ORANGE = '#FFB74D';

const TYPES_PRESTATION: Record<string, string> = {
  bain: 'Bain',
  coupe: 'Coupe',
  tonte: 'Tonte',
  demelage: 'Démêlage',
  griffes: 'Griffes',
  oreilles: 'Oreilles',
  hygiene: 'Hygiène',
  spa: 'SPA',
};

const ESPECES = ['chien', 'chat', 'nac'];
const LIB_ESPECE: Record<string, string> = { chien: 'Chien', chat: 'Chat', nac: 'NAC' };

/** Grille lisible : « Chien jusqu'à 10 kg : 35 € », « Chien de 10 à 20 kg : 45 € »,
 *  « Chien plus de 20 kg : 45 € » (au-delà : prix de la dernière tranche).
 *  Miroir appli : lignesGrillePrix (toilettage_prestations_page.dart). */
function lignesGrille(grille: Tranche[]): string[] {
  const out: string[] = [];
  for (const esp of ESPECES) {
    const ts = grille.filter(t => t.espece === esp && Number(t.poids_max_kg) > 0).sort((a, b) => a.poids_max_kg - b.poids_max_kg);
    let min = 0;
    for (const t of ts) {
      out.push(`${LIB_ESPECE[esp]} ${min ? `de ${min} à ${t.poids_max_kg} kg` : `jusqu'à ${t.poids_max_kg} kg`} : ${Number(t.prix) || 0} €`);
      min = t.poids_max_kg;
    }
    if (ts.length) out.push(`${LIB_ESPECE[esp]} plus de ${min} kg : ${Number(ts[ts.length - 1].prix) || 0} €`);
  }
  return out;
}

interface Tranche { espece: string; poids_max_kg: number; prix: number }

interface Prestation {
  id: string; type: string; nom: string; especes: string[]; prix_base: number;
  duree_minutes: number; grille_prix: Tranche[]; description: string | null;
}

type FormState = {
  id?: string; type: string; nom: string; especes: string[]; prix_base: string;
  duree_minutes: string; grille_prix: Tranche[]; description: string;
};

const EMPTY_FORM: FormState = {
  type: 'bain', nom: '', especes: ['chien'], prix_base: '', duree_minutes: '60',
  grille_prix: [], description: '',
};

export default function ToilettagePrestationsPage() {
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
    let q = supabase.from('prestations_toilettage').select('*').eq('pro_uid', user.uid).eq('actif', true);
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
        especes: form.especes,
        prix_base: Number(form.prix_base) || 0,
        duree_minutes: parseInt(form.duree_minutes, 10) || 60,
        grille_prix: form.grille_prix,
        description: form.description.trim() || null,
      };
      if (form.id) {
        await supabase.from('prestations_toilettage').update(payload).eq('id', form.id);
      } else {
        await supabase.from('prestations_toilettage').insert({
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
    await supabase.from('prestations_toilettage').update({ actif: false }).eq('id', id);
    await load();
  }

  function toggleEspece(e: string) {
    if (!form) return;
    const has = form.especes.includes(e);
    setForm({ ...form, especes: has ? form.especes.filter(x => x !== e) : [...form.especes, e] });
  }

  function addTranche() {
    if (!form) return;
    setForm({ ...form, grille_prix: [...form.grille_prix, { espece: form.especes[0] ?? 'chien', poids_max_kg: 10, prix: 0 }] });
  }

  function updateTranche(i: number, patch: Partial<Tranche>) {
    if (!form) return;
    const grille = form.grille_prix.map((t, idx) => idx === i ? { ...t, ...patch } : t);
    setForm({ ...form, grille_prix: grille });
  }

  function removeTranche(i: number) {
    if (!form) return;
    setForm({ ...form, grille_prix: form.grille_prix.filter((_, idx) => idx !== i) });
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Mes prestations</h1>
        <button onClick={() => setForm({ ...EMPTY_FORM })}
          className="text-white rounded-xl px-3 py-2 text-sm font-semibold" style={{ background: ORANGE }}>+ Prestation</button>
      </div>
      <p className="text-sm text-gray-500 mb-4">
        Définissez vos prestations (type, prix, durée) — le client les choisit directement lors de la réservation. Le prix peut varier par tranche de poids.
      </p>

      {form && (
        <div className="border rounded-2xl p-4 mb-4 space-y-3" style={{ borderColor: `${ORANGE}55` }}>
          <select value={form.type} onChange={e => setForm({ ...form, type: e.target.value })}
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm">
            {Object.entries(TYPES_PRESTATION).map(([k, label]) => (
              <option key={k} value={k}>{label}</option>
            ))}
          </select>
          <input value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })}
            placeholder="Nom de la prestation"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />

          <div>
            <p className="text-xs text-gray-500 mb-1.5">Espèces concernées</p>
            <div className="flex gap-2">
              {ESPECES.map(e => (
                <button key={e} type="button" onClick={() => toggleEspece(e)}
                  className="px-3 py-1.5 rounded-full text-xs font-semibold border transition-colors capitalize"
                  style={{
                    background: form.especes.includes(e) ? `${ORANGE}33` : 'white',
                    borderColor: form.especes.includes(e) ? ORANGE : '#e5e7eb',
                    color: form.especes.includes(e) ? '#92400e' : '#6B7280',
                  }}>{e}</button>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <label className="text-xs font-medium text-gray-500">Prix de base (€)
              <input type="number" value={form.prix_base} onChange={e => setForm({ ...form, prix_base: e.target.value })}
                placeholder="Prix de base (€)" className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm text-gray-900" />
            </label>
            <label className="text-xs font-medium text-gray-500">Durée (min)
              <input type="number" min={5} step={5} value={form.duree_minutes} onChange={e => setForm({ ...form, duree_minutes: e.target.value })}
                placeholder="Durée (min)" className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm text-gray-900" />
            </label>
          </div>
          <p className="text-xs text-gray-400 -mt-1">La durée sert à calculer les créneaux proposés à vos clients.</p>

          <div>
            <div className="flex items-center justify-between mb-1.5">
              <p className="text-xs font-semibold text-gray-700">Grille de prix par poids (optionnel)</p>
              <button type="button" onClick={addTranche} className="text-xs font-semibold" style={{ color: ORANGE }}>+ Ajouter une tranche</button>
            </div>
            <p className="text-xs text-gray-500 mb-2">
              Pour un prix selon la taille de l&apos;animal : une ligne par tranche, avec le poids maximum et le prix jusqu&apos;à ce poids.
              Le prix est calculé à la réservation d&apos;après le poids de la fiche de l&apos;animal ; sans poids connu, c&apos;est le prix de base.
            </p>
            {form.grille_prix.length > 0 && (
              <div className="flex gap-1.5 mb-1 text-[11px] font-semibold text-gray-500">
                <span className="flex-[1.2]">Espèce</span>
                <span className="flex-1">Jusqu&apos;à (kg)</span>
                <span className="flex-1">Prix (€ TTC)</span>
                <span className="w-6" />
              </div>
            )}
            {form.grille_prix.map((t, i) => (
              <div key={i} className="flex gap-1.5 mb-1.5 items-center">
                <select value={t.espece} onChange={e => updateTranche(i, { espece: e.target.value })}
                  className="flex-[1.2] border border-gray-200 rounded-lg px-2 py-1.5 text-xs">
                  {ESPECES.map(e => <option key={e} value={e}>{LIB_ESPECE[e]}</option>)}
                </select>
                <input type="number" min={0} value={t.poids_max_kg} onChange={e => updateTranche(i, { poids_max_kg: Number(e.target.value) })}
                  placeholder="kg" aria-label="Poids maximum (kg)" className="flex-1 border border-gray-200 rounded-lg px-2 py-1.5 text-xs" />
                <input type="number" min={0} value={t.prix} onChange={e => updateTranche(i, { prix: Number(e.target.value) })}
                  placeholder="€" aria-label="Prix (€ TTC)" className="flex-1 border border-gray-200 rounded-lg px-2 py-1.5 text-xs" />
                <button type="button" onClick={() => removeTranche(i)} aria-label="Retirer la tranche" className="w-6 text-gray-300 hover:text-red-400">✕</button>
              </div>
            ))}
            {lignesGrille(form.grille_prix).length > 0 && (
              <div className="mt-2 rounded-xl bg-[#FFF6EA] px-3 py-2">
                <p className="text-[11px] font-semibold text-gray-500 mb-0.5">Récapitulatif de la grille</p>
                {lignesGrille(form.grille_prix).map(l => <p key={l} className="text-xs text-gray-800">{l}</p>)}
              </div>
            )}
          </div>

          <textarea value={form.description} onChange={e => setForm({ ...form, description: e.target.value })}
            rows={2} placeholder="Description (optionnel)"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
          <div className="flex gap-2">
            <button onClick={() => setForm(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
            <button onClick={save} disabled={saving || !form.nom.trim()}
              className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: ORANGE }}>
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
                  id: p.id, type: p.type, nom: p.nom, especes: p.especes ?? ['chien'],
                  prix_base: String(p.prix_base), duree_minutes: String(p.duree_minutes),
                  grille_prix: p.grille_prix ?? [], description: p.description ?? '',
                })}
                className="flex-1 min-w-0 text-left">
                <p className="text-sm font-semibold text-[#1F2A2E]">✂️ {p.nom}</p>
                <p className="text-xs text-gray-500">
                  {TYPES_PRESTATION[p.type] ?? p.type} · {p.grille_prix?.length ? 'prix selon le poids' : `à partir de ${p.prix_base.toFixed(0)} €`} · {p.duree_minutes} min
                </p>
                {lignesGrille(p.grille_prix ?? []).map(l => <p key={l} className="text-xs text-gray-600">{l}</p>)}
                {p.description && <p className="text-xs text-gray-600 mt-0.5 line-clamp-2">{p.description}</p>}
              </button>
              <button onClick={() => remove(p.id)} className="text-gray-300 hover:text-red-400 shrink-0">🗑</button>
            </div>
          ))}
        </div>
      )}

      {user?.uid && activeProfileId && <CartesSeances proUid={user.uid} profileId={activeProfileId} prestations={prestations} />}
    </div>
  );
}
