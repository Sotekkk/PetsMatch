'use client';

import { useEffect, useState, Suspense } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface PlanTarifaire {
  plan_code: string;
  label: string;
  prix_mensuel: number;
  prix_annuel: number;
  features: Record<string, boolean | number>;
}

const PLAN_ICONS: Record<string, string> = { free: '🌱', essentiel: '⚡', pro: '👑' };
const PLAN_COLORS: Record<string, string> = {
  free:      'border-gray-200 bg-white',
  essentiel: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20',
  pro:       'border-[#D97706] bg-white ring-2 ring-[#D97706]/20',
};

function featureLabels(f: Record<string, boolean | number>): string[] {
  const out: string[] = [];
  out.push(f.hasAjoutSeances ? 'Ajout de séances au carnet santé' : 'Annuaire basique, token 72h');
  if (f.hasMultiIntervenants) out.push(f.maxIntervenants === -1 ? 'Multi-intervenants illimité' : `Jusqu'à ${f.maxIntervenants} intervenants`);
  if (f.hasFactureExport) out.push('Facturation clients + export CSV');
  return out;
}

function SanteAbonnementContent() {
  const { user, loading: authLoading } = useAuth();
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const searchParams = useSearchParams();
  const [plans, setPlans] = useState<PlanTarifaire[]>([]);
  const [currentPlan, setCurrentPlan] = useState('free');
  const [periodicite, setPeriodicite] = useState<'mensuel' | 'annuel'>('mensuel');
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [loadingPortal, setLoadingPortal] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'info'; text: string } | null>(null);

  useEffect(() => {
    supabase.from('plans_tarifaires').select('*').eq('profil_type', 'sante').eq('actif', true).order('prix_mensuel')
      .then(({ data }) => setPlans((data ?? []) as PlanTarifaire[]));
  }, []);

  useEffect(() => {
    if (searchParams.get('cancelled')) {
      setMessage({ type: 'info', text: 'Paiement annulé. Votre formule n\'a pas changé.' });
    }
    const pending = sessionStorage.getItem('sante_abonnement_success');
    if (pending) {
      setMessage({ type: 'success', text: pending });
      sessionStorage.removeItem('sante_abonnement_success');
    }
  }, [searchParams]);

  useEffect(() => {
    if (!user) return;
    const sessionId = searchParams.get('session_id');
    const isSuccess = !!searchParams.get('success');

    const fetchPlan = async () => {
      const { data } = await supabase
        .from('abonnements').select('plan_code').eq('uid', user.uid).eq('profil_type', 'sante').eq('statut', 'actif')
        .order('created_at', { ascending: false }).limit(1).maybeSingle();
      return data?.plan_code ?? 'free';
    };

    if (!isSuccess) {
      fetchPlan().then(setCurrentPlan);
      return;
    }

    const activate = async () => {
      if (sessionId) {
        try {
          const res = await fetch('/api/stripe/activate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ sessionId, uid: user.uid }),
          });
          const json = await res.json();
          if (json.ok && json.plan) {
            const label = json.plan.charAt(0).toUpperCase() + json.plan.slice(1);
            sessionStorage.setItem('sante_abonnement_success', `🎉 Formule ${label} activée !`);
            router.replace('/sante/abonnement');
            router.refresh();
            return;
          }
        } catch {
          // fallback : polling Supabase
        }
      }
      let attempts = 0;
      const poll = async () => {
        const plan = await fetchPlan();
        setCurrentPlan(plan);
        if (plan !== 'free' || attempts >= 4) {
          const label = plan.charAt(0).toUpperCase() + plan.slice(1);
          sessionStorage.setItem('sante_abonnement_success', plan !== 'free' ? `🎉 Formule ${label} activée !` : '✅ Paiement reçu, activation en cours…');
          router.replace('/sante/abonnement');
          router.refresh();
          return;
        }
        attempts++;
        setTimeout(poll, 2000);
      };
      poll();
    };

    activate();
  }, [user, searchParams]);

  const handleSubscribe = async (planCode: string) => {
    if (!user) { router.push('/connexion'); return; }
    if (planCode === 'free') return;
    setLoadingPlan(planCode);
    try {
      const res = await fetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid: user.uid, email: user.email, plan: planCode, periodicite,
          profil_type: 'sante', returnPath: '/sante/abonnement',
          ...(activeProfileId ? { profile_id: activeProfileId } : {}),
        }),
      });
      const data = await res.json();
      if (data.url) window.location.href = data.url;
      else setMessage({ type: 'info', text: data.error ?? 'Erreur lors de la création du paiement.' });
    } catch { setMessage({ type: 'info', text: 'Erreur réseau.' }); }
    finally { setLoadingPlan(null); }
  };

  const handlePortal = async () => {
    if (!user) return;
    setLoadingPortal(true);
    try {
      const res = await fetch('/api/stripe/portal', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ uid: user.uid, returnPath: '/sante/abonnement' }),
      });
      const data = await res.json();
      if (data.url) window.location.href = data.url;
      else setMessage({ type: 'info', text: data.error ?? 'Portail Stripe non disponible.' });
    } finally { setLoadingPortal(false); }
  };

  if (authLoading) return <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  return (
    <div className="max-w-5xl mx-auto px-4 py-12">
      <div className="text-center mb-10">
        <h1 className="font-['Galey'] font-bold text-3xl text-[#1F2A2E] mb-2">Formules Ostéopathe / Kinésithérapeute</h1>
        <p className="text-gray-500">Choisissez la formule adaptée à votre activité</p>
      </div>

      {message && (
        <div className={`mb-6 p-4 rounded-xl text-sm font-medium ${message.type === 'success' ? 'bg-green-50 text-green-700 border border-green-200' : 'bg-blue-50 text-blue-700 border border-blue-200'}`}>
          {message.text}
          {currentPlan !== 'free' && message.type === 'success' && (
            <button onClick={handlePortal} disabled={loadingPortal} className="ml-4 underline text-xs">
              Gérer mon abonnement
            </button>
          )}
        </div>
      )}

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
              {plan.plan_code === 'essentiel' && (
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
              ) : (
                <button onClick={() => handleSubscribe(plan.plan_code)}
                  disabled={loadingPlan === plan.plan_code}
                  className="w-full py-2.5 rounded-xl text-sm font-semibold bg-[#0C5C6C] text-white hover:bg-[#094F5D] disabled:opacity-50 transition-colors">
                  {loadingPlan === plan.plan_code ? (
                    <span className="inline-block w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin" />
                  ) : `Passer en ${plan.label}`}
                </button>
              )}
            </div>
          );
        })}
      </div>

      {currentPlan !== 'free' && user && (
        <div className="text-center mb-4">
          <button onClick={handlePortal} disabled={loadingPortal}
            className="text-sm text-gray-500 hover:text-[#0C5C6C] underline">
            {loadingPortal ? 'Chargement…' : 'Gérer mon abonnement (factures, annulation)'}
          </button>
        </div>
      )}

      <p className="text-center text-xs text-gray-400">
        Une question sur les formules ? Contactez-nous depuis votre espace pro.
      </p>
    </div>
  );
}

export default function SanteAbonnementPage() {
  return (
    <Suspense>
      <SanteAbonnementContent />
    </Suspense>
  );
}
