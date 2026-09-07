'use client';

import { useMemo, useState } from 'react';
import { Badge, fmtDate } from './ui';

interface Plan { profil_type: string; plan_code: string; label: string; prix_mensuel: number; actif: boolean; }
interface Abo {
  id: string; profil_type: string; profile_id: string | null; plan_code: string;
  statut: string; periodicite: string; date_debut: string | null; date_fin: string | null;
  stripe_subscription_id: string | null; created_at: string | null;
}

export default function PlanEditor({ adminUid, targetUid, profilType, profileId, plans, abonnements, onChanged }: {
  adminUid: string;
  targetUid: string;
  profilType: string;
  profileId: string | null;
  plans: Plan[];
  abonnements: Abo[];
  onChanged: (abos: Abo[]) => void;
}) {
  const typePlans = useMemo(
    () => plans.filter(p => p.profil_type === profilType).sort((a, b) => a.prix_mensuel - b.prix_mensuel),
    [plans, profilType],
  );
  const current = abonnements.find(a => a.profil_type === profilType && a.statut === 'actif') ?? null;
  const history = abonnements.filter(a => a.profil_type === profilType);

  const [planCode, setPlanCode] = useState(current?.plan_code ?? typePlans.find(p => p.plan_code === 'premium')?.plan_code ?? typePlans[0]?.plan_code ?? 'free');
  const [periodicite, setPeriodicite] = useState(current?.periodicite ?? 'mensuel');
  const [dateFin, setDateFin] = useState<string>(current?.date_fin?.slice(0, 10) ?? '');
  const [statut, setStatut] = useState(current?.statut ?? 'actif');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const [ok, setOk] = useState(false);

  async function save() {
    setSaving(true); setErr(''); setOk(false);
    try {
      const res = await fetch('/api/admin/abonnement', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid: adminUid, targetUid, profileId, profil_type: profilType,
          plan_code: planCode, statut, periodicite,
          date_fin: dateFin ? new Date(dateFin).toISOString() : null,
        }),
      });
      const json = await res.json();
      if (!res.ok) { setErr(json.error ?? 'Erreur'); return; }
      onChanged(json.abonnements ?? []);
      setOk(true); setTimeout(() => setOk(false), 2500);
    } finally {
      setSaving(false);
    }
  }

  const sel = 'px-2.5 py-1.5 rounded-lg border border-gray-200 bg-white text-sm outline-none';

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 flex-wrap text-sm">
        <span className="text-gray-500">Abonnement actuel :</span>
        {current ? (
          <>
            <Badge label={current.plan_code} color={current.plan_code === 'premium' ? '#d97706' : '#0C5C6C'} />
            <span className="text-gray-400 text-xs">
              {current.periodicite ?? '—'} · {current.stripe_subscription_id ? 'Stripe' : 'manuel'}
              {current.date_fin
                ? ` · ${new Date(current.date_fin) < new Date() ? 'expiré le' : 'jusqu’au'} ${fmtDate(current.date_fin)}`
                : ' · sans échéance'}
            </span>
          </>
        ) : <span className="text-gray-400">aucun (free)</span>}
      </div>

      <div className="flex flex-wrap gap-2 items-end bg-gray-50 rounded-xl p-3">
        <label className="text-xs text-gray-500 flex flex-col gap-1">Plan
          <select className={sel} value={planCode} onChange={e => setPlanCode(e.target.value)}>
            {typePlans.length === 0 && <option value="premium">premium</option>}
            {typePlans.map(p => <option key={p.plan_code} value={p.plan_code}>{p.label} ({p.plan_code}) · {p.prix_mensuel}€</option>)}
          </select>
        </label>
        <label className="text-xs text-gray-500 flex flex-col gap-1">Période
          <select className={sel} value={periodicite} onChange={e => setPeriodicite(e.target.value)}>
            <option value="mensuel">mensuel</option>
            <option value="annuel">annuel</option>
          </select>
        </label>
        <label className="text-xs text-gray-500 flex flex-col gap-1">Statut
          <select className={sel} value={statut} onChange={e => setStatut(e.target.value)}>
            <option value="actif">actif</option>
            <option value="annule">annulé</option>
            <option value="grace">grace</option>
          </select>
        </label>
        <label className="text-xs text-gray-500 flex flex-col gap-1">Fin (option)
          <input type="date" className={sel} value={dateFin} onChange={e => setDateFin(e.target.value)} />
        </label>
        <button onClick={save} disabled={saving}
          className="px-4 py-1.5 rounded-lg bg-[#0C5C6C] text-white text-sm font-semibold disabled:opacity-50">
          {saving ? '…' : 'Appliquer'}
        </button>
        <button
          onClick={() => {
            setPlanCode('premium'); setStatut('actif'); setPeriodicite('annuel');
            const d = new Date(); d.setFullYear(d.getFullYear() + 1);
            setDateFin(d.toISOString().slice(0, 10));
          }}
          className="px-3 py-1.5 rounded-lg border border-amber-300 text-amber-700 text-xs font-medium">
          ★ Premium 1 an
        </button>
      </div>
      {err && <p className="text-xs text-red-600">{err}</p>}
      {ok && <p className="text-xs text-green-600">✓ Abonnement mis à jour + resync users / user_profiles</p>}

      {history.length > 0 && (
        <details className="text-xs text-gray-500">
          <summary className="cursor-pointer">Historique ({history.length})</summary>
          <ul className="mt-1 space-y-1">
            {history.map(h => (
              <li key={h.id} className="font-mono">
                {fmtDate(h.created_at)} · {h.plan_code} · {h.statut} · {h.periodicite}
                {h.stripe_subscription_id ? ' · Stripe' : ' · manuel'}
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}
