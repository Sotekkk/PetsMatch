'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';
import { PENSION_ESPECES, type TarifsPension } from '@/lib/pension-especes';

interface EspeceRow {
  key: string;
  label: string;
  emoji: string;
  accepte: boolean;
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
  const [especes, setEspeces] = useState<EspeceRow[]>([]);
  const [reductions, setReductions] = useState<Reduction[]>([]);
  const [afficherPublic, setAfficherPublic] = useState(false);
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

    const { data } = await supabase.from('user_profiles')
      .select('tarifs_pension, especes_acceptees').eq('id', pid).maybeSingle();
    const t = (data?.tarifs_pension ?? null) as (TarifsPension & { afficher_public?: boolean }) | null;
    const acceptees = new Set((data?.especes_acceptees as string[] | undefined) ?? []);
    setAfficherPublic(t?.afficher_public === true);

    // Prix déjà saisis, par key.
    const prixByKey: Record<string, { seul: string; partage: string }> = {};
    if (Array.isArray(t?.especes)) {
      for (const e of t.especes) {
        prixByKey[e.espece] = {
          seul: e.prix_seul != null ? String(e.prix_seul) : '',
          partage: e.prix_partage != null ? String(e.prix_partage) : '',
        };
      }
    } else if (Array.isArray(t?.tranches_poids) && t.tranches_poids.length > 0) {
      // Rétro-compat : reprend le prix de la 1re tranche comme défaut pour
      // les espèces acceptées.
      const first = t.tranches_poids[0];
      const seul = first.prix_seul != null ? String(first.prix_seul) : '';
      const partage = first.prix_partage != null ? String(first.prix_partage) : '';
      for (const sp of PENSION_ESPECES) {
        if (acceptees.has(sp.label)) prixByKey[sp.key] = { seul, partage };
      }
    }

    const rows: EspeceRow[] = PENSION_ESPECES.map(sp => ({
      key: sp.key,
      label: sp.label,
      emoji: sp.emoji,
      accepte: acceptees.has(sp.label),
      prixSeul: prixByKey[sp.key]?.seul ?? '',
      prixPartage: prixByKey[sp.key]?.partage ?? '',
    })).sort((a, b) => (a.accepte === b.accepte ? 0 : a.accepte ? -1 : 1));

    setEspeces(rows);
    setReductions(((t?.reductions_long_sejour ?? []) as { min_nuits?: number; pourcentage?: number }[]).map(m => ({
      minNuits: m.min_nuits != null ? String(m.min_nuits) : '',
      pourcentage: m.pourcentage != null ? String(m.pourcentage) : '',
    })));
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  const save = async () => {
    if (!profileId) return;
    setSaving(true);
    setSaved(false);

    const especesOut = especes
      .filter(e => e.prixSeul.trim() !== '')
      .map(e => {
        const seul = num(e.prixSeul) ?? 0;
        return { espece: e.key, prix_seul: seul, prix_partage: num(e.prixPartage) ?? seul };
      });

    const reductions_long_sejour = reductions
      .filter(r => r.minNuits.trim() !== '')
      .map(r => ({
        min_nuits: Math.round(num(r.minNuits) ?? 0),
        pourcentage: num(r.pourcentage) ?? 0,
      }))
      .sort((a, b) => a.min_nuits - b.min_nuits);

    await supabase.from('user_profiles')
      .update({ tarifs_pension: { especes: especesOut, reductions_long_sejour, afficher_public: afficherPublic } })
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

      <label className={`flex items-start gap-3 bg-white rounded-2xl shadow-sm p-4 border cursor-pointer ${afficherPublic ? 'border-[#6E9E57]/40' : 'border-gray-100'}`}>
        <input type="checkbox" className="mt-1" checked={afficherPublic}
          onChange={e => setAfficherPublic(e.target.checked)} />
        <span>
          <span className="block font-galey font-semibold text-sm text-[#1E2025]">Afficher mes tarifs sur ma fiche publique</span>
          <span className="block font-galey text-xs text-gray-500 mt-0.5">
            Les clients verront le prix par nuit et par espèce dans l&apos;annuaire des pros.
          </span>
        </span>
      </label>

      <div className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
        <div>
          <h2 className="font-bold font-galey text-teal-800">Prix par espèce</h2>
          <p className="text-xs font-galey text-gray-500 mt-1">
            Tarif par nuit selon l&apos;espèce et selon que l&apos;animal est seul ou partage son logement.
            Le tarif est ensuite suggéré automatiquement à la facturation. Les espèces acceptées par votre
            pension apparaissent en premier.
          </p>
        </div>
        <div className="space-y-3">
          {especes.map((e, i) => (
            <div key={e.key} className="border border-gray-100 rounded-xl p-3">
              <div className="flex items-center gap-2 mb-2">
                <span className="text-lg">{e.emoji}</span>
                <span className="font-galey font-bold text-sm text-[#1E2025]">{e.label}</span>
                {e.accepte && (
                  <span className="text-[10px] font-galey font-bold px-2 py-0.5 rounded-full bg-[#6E9E57]/12 text-[#6E9E57]">
                    Accepté
                  </span>
                )}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <input placeholder="Prix seul (€/nuit)" value={e.prixSeul} inputMode="decimal"
                  onChange={ev => setEspeces(rows => rows.map((x, j) => j === i ? { ...x, prixSeul: ev.target.value } : x))}
                  className={`${inputCls} flex-1 min-w-[140px]`} />
                <input placeholder="Prix partagé (€/nuit)" value={e.prixPartage} inputMode="decimal"
                  onChange={ev => setEspeces(rows => rows.map((x, j) => j === i ? { ...x, prixPartage: ev.target.value } : x))}
                  className={`${inputCls} flex-1 min-w-[140px]`} />
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
        <div>
          <h2 className="font-bold font-galey text-teal-800">Réductions séjour long</h2>
          <p className="text-xs font-galey text-gray-500 mt-1">
            Réduction appliquée sur le tarif total à partir d&apos;un nombre de nuits (toutes espèces).
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
