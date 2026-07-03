'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface PlanTarifaire {
  plan_code: string;
  label: string;
  prix_mensuel: number;
  prix_annuel: number;
  features: Record<string, boolean | number>;
}

const PLAN_ICONS: Record<string, string> = { free: '🌱', pro: '⚡', premium: '👑' };
const PLAN_COLORS: Record<string, string> = {
  free:    'border-gray-200 bg-white',
  pro:     'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20',
  premium: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20',
};

function featureLabels(f: Record<string, boolean | number>): string[] {
  const out: string[] = [];
  out.push(f.logementsIllimites ? 'Logements illimités' : '1 logement');
  if (f.hasEmployes) out.push(f.maxEmployes === -1 ? 'Employés illimités' : `Jusqu'à ${f.maxEmployes} employés`);
  if (f.hasInventaire) out.push('Inventaire');
  if (f.hasProtocoles) out.push('Protocoles / Tâches');
  if (f.hasContratSignature) out.push('Contrats — signature électronique');
  if (f.hasFactureExport) out.push('Export factures');
  if (f.hasBadgePremium) out.push('Badge premium + mise en avant annuaire');
  return out;
}

export default function PensionAbonnementPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [plans, setPlans] = useState<PlanTarifaire[]>([]);
  const [currentPlan, setCurrentPlan] = useState('free');
  const [periodicite, setPeriodicite] = useState<'mensuel' | 'annuel'>('mensuel');

  useEffect(() => {
    supabase.from('plans_tarifaires').select('*').eq('profil_type', 'pension').eq('actif', true).order('prix_mensuel')
      .then(({ data }) => setPlans((data ?? []) as PlanTarifaire[]));
  }, []);

  useEffect(() => {
    if (!user) return;
    supabase.from('abonnements').select('plan_code').eq('uid', user.uid).eq('profil_type', 'pension').eq('statut', 'actif')
      .order('created_at', { ascending: false }).limit(1).maybeSingle()
      .then(({ data }) => setCurrentPlan(data?.plan_code ?? 'free'));
  }, [user]);

  if (authLoading) return <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  return (
    <div className="max-w-5xl mx-auto px-4 py-12">
      <div className="text-center mb-10">
        <h1 className="font-['Galey'] font-bold text-3xl text-[#1F2A2E] mb-2">Formules Pension</h1>
        <p className="text-gray-500">Choisissez la formule adaptée à votre structure</p>
      </div>

      <div className="flex justify-center mb-8">
        <div className="flex bg-gray-100 rounded-xl p-1 gap-1">
          {(['mensuel', 'annuel'] as const).map(p => (
            <button key={p} onClick={() => setPeriodicite(p)}
              className={`px-5 py-2 rounded-lg text-sm font-medium transition-colors ${periodicite === p ? 'bg-white shadow-sm text-[#1F2A2E]' : 'text-gray-500'}`}>
              {p === 'mensuel' ? 'Mensuel' : 'Annuel'}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-5 mb-10">
        {plans.length === 0 ? (
          <div className="col-span-3 text-center text-gray-400 py-10">Chargement des formules…</div>
        ) : plans.map(plan => {
          const prix = periodicite === 'mensuel' ? plan.prix_mensuel : Math.round(plan.prix_annuel / 12 * 10) / 10;
          const prixAff = prix === 0 ? 'Gratuit' : `${prix} €/mois`;
          const isCurrent = currentPlan === plan.plan_code;

          return (
            <div key={plan.plan_code} className={`rounded-2xl border p-6 flex flex-col relative ${PLAN_COLORS[plan.plan_code] ?? 'border-gray-200 bg-white'}`}>
              {plan.plan_code === 'pro' && (
                <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-[#0C5C6C] text-white text-xs font-bold px-3 py-0.5 rounded-full">
                  Populaire
                </div>
              )}
              <div className="text-3xl mb-2">{PLAN_ICONS[plan.plan_code]}</div>
              <h2 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-1">{plan.label}</h2>
              <p className="text-2xl font-bold text-[#1F2A2E] mb-1">
                {prixAff}
                {prix > 0 && periodicite === 'annuel' && (
                  <span className="text-sm font-normal text-gray-400 ml-1">({plan.prix_annuel} €/an)</span>
                )}
              </p>
              <ul className="flex-1 space-y-2 mb-6 mt-4">
                {featureLabels(plan.features ?? {}).map((f, i) => (
                  <li key={i} className="flex items-start gap-2 text-sm text-gray-700">
                    <span className="text-[#6E9E57] mt-0.5 flex-shrink-0">✓</span>
                    {f}
                  </li>
                ))}
              </ul>
              {isCurrent ? (
                <div className="text-center text-sm font-semibold text-[#0C5C6C] bg-[#EEF5EA] py-2 rounded-xl">
                  Formule actuelle
                </div>
              ) : plan.plan_code === 'free' ? (
                <div className="text-center text-sm text-gray-400 py-2">Formule par défaut</div>
              ) : !user ? (
                <button onClick={() => router.push('/connexion')}
                  className="w-full py-2.5 rounded-xl text-sm font-semibold bg-[#0C5C6C] text-white hover:bg-[#094F5D] transition-colors">
                  Se connecter
                </button>
              ) : (
                <div className="text-center text-xs text-gray-400 border border-dashed border-gray-200 py-2.5 rounded-xl">
                  Paiement en ligne bientôt disponible
                </div>
              )}
            </div>
          );
        })}
      </div>

      <p className="text-center text-xs text-gray-400">
        Une question sur les formules pension ? Contactez-nous depuis votre espace pro.
      </p>
    </div>
  );
}
