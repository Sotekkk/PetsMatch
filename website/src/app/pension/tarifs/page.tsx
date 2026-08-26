'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';

interface Tranche {
  poidsMax: string;
  prixSeul: string;
  prixPartage: string;
}

interface Reduction {
  minNuits: string;
  pourcentage: string;
}

const num = (s: string) => {
  const n = parseFloat(s.replace(',', '.'));
  return Number.isFinite(n) ? n : null;
};

export default function PensionTarifsPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const activeProfileId = useActiveProfile();
  const router = useRouter();

  const [profileId, setProfileId] = useState<string | null>(null);
  const [tranches, setTranches] = useState<Tranche[]>([]);
  const [reductions, setReductions] = useState<Reduction[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let pid = activeProfileId || null;
    if (!pid) {
      const { data: mainProfile } = await supabase.from('user_profiles')
        .select('id').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      pid = mainProfile?.id ?? null;
    }
    setProfileId(pid);
    if (!pid) { setLoading(false); return; }

    const { data } = await supabase.from('user_profiles').select('tarifs_pension').eq('id', pid).maybeSingle();
    const t = (data?.tarifs_pension ?? null) as { tranches_poids?: unknown[]; reductions_long_sejour?: unknown[] } | null;

    const loadedTranches = (t?.tranches_poids ?? []).map((raw) => {
      const m = raw as { poids_max?: number | null; prix_seul?: number; prix_partage?: number };
      return {
        poidsMax: m.poids_max != null ? String(m.poids_max) : '',
        prixSeul: m.prix_seul != null ? String(m.prix_seul) : '',
        prixPartage: m.prix_partage != null ? String(m.prix_partage) : '',
      };
    });
    const loadedReductions = (t?.reductions_long_sejour ?? []).map((raw) => {
      const m = raw as { min_nuits?: number; pourcentage?: number };
      return {
        minNuits: m.min_nuits != null ? String(m.min_nuits) : '',
        pourcentage: m.pourcentage != null ? String(m.pourcentage) : '',
      };
    });

    setTranches(loadedTranches.length > 0 ? loadedTranches : [{ poidsMax: '', prixSeul: '', prixPartage: '' }]);
    setReductions(loadedReductions);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  const save = async () => {
    if (!profileId) return;
    setSaving(true);
    setSaved(false);

    const tranches_poids = tranches
      .filter(t => t.prixSeul.trim() !== '')
      .map(t => ({
        poids_max: num(t.poidsMax),
        prix_seul: num(t.prixSeul) ?? 0,
        prix_partage: num(t.prixPartage) ?? num(t.prixSeul) ?? 0,
      }))
      .sort((a, b) => {
        if (a.poids_max == null) return 1;
        if (b.poids_max == null) return -1;
        return a.poids_max - b.poids_max;
      });

    const reductions_long_sejour = reductions
      .filter(r => r.minNuits.trim() !== '')
      .map(r => ({
        min_nuits: Math.round(num(r.minNuits) ?? 0),
        pourcentage: num(r.pourcentage) ?? 0,
      }))
      .sort((a, b) => a.min_nuits - b.min_nuits);

    await supabase.from('user_profiles')
      .update({ tarifs_pension: { tranches_poids, reductions_long_sejour } })
      .eq('id', profileId);

    setSaving(false);
    setSaved(true);
    setTimeout(() => setSaved(false), 3000);
  };

  if (!user || !userData || loading) {
    return <div className="max-w-4xl mx-auto px-4 py-10 text-center text-gray-400 font-galey">Chargement…</div>;
  }

  const inputCls = "w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300";

  return (
    <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Tarification</h1>
        <button onClick={save} disabled={saving}
          className="bg-teal-700 disabled:opacity-60 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>
      </div>
      {saved && <p className="text-sm font-galey text-[#6E9E57]">✓ Tarifs enregistrés.</p>}

      <div className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
        <div>
          <h2 className="font-bold font-galey text-teal-800">Tranches de poids</h2>
          <p className="text-xs font-galey text-gray-500 mt-1">
            Le tarif suggéré à la facturation dépend du poids de l&apos;animal et de s&apos;il est seul ou partage
            son logement. Laisser le dernier poids max vide = « et plus ».
          </p>
        </div>
        <div className="space-y-3">
          {tranches.map((t, i) => (
            <div key={i} className="flex flex-wrap items-center gap-2">
              <input placeholder="Poids max (kg)" value={t.poidsMax} inputMode="decimal"
                onChange={e => setTranches(ts => ts.map((x, j) => j === i ? { ...x, poidsMax: e.target.value } : x))}
                className={`${inputCls} flex-1 min-w-[120px]`} />
              <input placeholder="Prix seul (€/nuit)" value={t.prixSeul} inputMode="decimal"
                onChange={e => setTranches(ts => ts.map((x, j) => j === i ? { ...x, prixSeul: e.target.value } : x))}
                className={`${inputCls} flex-1 min-w-[140px]`} />
              <input placeholder="Prix partagé (€/nuit)" value={t.prixPartage} inputMode="decimal"
                onChange={e => setTranches(ts => ts.map((x, j) => j === i ? { ...x, prixPartage: e.target.value } : x))}
                className={`${inputCls} flex-1 min-w-[140px]`} />
              <button onClick={() => setTranches(ts => ts.filter((_, j) => j !== i))}
                className="text-red-500 hover:text-red-600 text-sm font-galey px-2">✕</button>
            </div>
          ))}
        </div>
        <button onClick={() => setTranches(ts => [...ts, { poidsMax: '', prixSeul: '', prixPartage: '' }])}
          className="text-sm font-galey font-semibold text-teal-700 border border-teal-200 rounded-full px-4 py-1.5 hover:bg-teal-50 transition-colors">
          + Ajouter une tranche
        </button>
      </div>

      <div className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
        <div>
          <h2 className="font-bold font-galey text-teal-800">Réductions séjour long</h2>
          <p className="text-xs font-galey text-gray-500 mt-1">
            Réduction appliquée sur le tarif total à partir d&apos;un nombre de nuits.
          </p>
        </div>
        <div className="space-y-3">
          {reductions.map((r, i) => (
            <div key={i} className="flex flex-wrap items-center gap-2">
              <input placeholder="À partir de (nuits)" value={r.minNuits} inputMode="numeric"
                onChange={e => setReductions(rs => rs.map((x, j) => j === i ? { ...x, minNuits: e.target.value } : x))}
                className={`${inputCls} flex-1 min-w-[160px]`} />
              <input placeholder="Réduction (%)" value={r.pourcentage} inputMode="decimal"
                onChange={e => setReductions(rs => rs.map((x, j) => j === i ? { ...x, pourcentage: e.target.value } : x))}
                className={`${inputCls} flex-1 min-w-[140px]`} />
              <button onClick={() => setReductions(rs => rs.filter((_, j) => j !== i))}
                className="text-red-500 hover:text-red-600 text-sm font-galey px-2">✕</button>
            </div>
          ))}
        </div>
        <button onClick={() => setReductions(rs => [...rs, { minNuits: '', pourcentage: '' }])}
          className="text-sm font-galey font-semibold text-teal-700 border border-teal-200 rounded-full px-4 py-1.5 hover:bg-teal-50 transition-colors">
          + Ajouter une réduction
        </button>
      </div>
    </div>
  );
}
