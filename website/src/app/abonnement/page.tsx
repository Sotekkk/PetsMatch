'use client';

import { useEffect, useState } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface PlanTarifaire {
  plan_code: string;
  label: string;
  prix_mensuel: number;
  prix_annuel: number;
  max_annonces: number;
  duree_annonce_jours: number;
  auto_publish: boolean;
  features: string[];
}

interface ProduitPonctuel {
  id: string;
  code: string;
  label: string;
  prix: number;
  duree_heures: number | null;
  description: string;
  stripe_price_id: string | null;
}

const PLAN_ICONS: Record<string, string> = { free: '🌱', pro: '⚡', premium: '👑' };
const PLAN_COLORS: Record<string, string> = {
  free:    'border-gray-200 bg-white',
  pro:     'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20',
  premium: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20',
};
const PLAN_BTN: Record<string, string> = {
  free:    'border border-gray-300 text-gray-600 hover:bg-gray-50',
  pro:     'bg-[#0C5C6C] text-white hover:bg-[#094F5D]',
  premium: 'bg-[#D97706] text-white hover:bg-[#B45309]',
};

export default function AbonnementPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const [plans, setPlans] = useState<PlanTarifaire[]>([]);
  const [boosts, setBoosts] = useState<ProduitPonctuel[]>([]);
  const [currentPlan, setCurrentPlan] = useState<string>('free');
  const [periodicite, setPeriodicite] = useState<'mensuel' | 'annuel'>('mensuel');
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [loadingPortal, setLoadingPortal] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'info'; text: string } | null>(null);

  useEffect(() => {
    if (searchParams.get('cancelled')) {
      setMessage({ type: 'info', text: 'Paiement annulé. Votre plan n\'a pas changé.' });
    }
    // Récupère le message de succès conservé après router.replace()
    const pending = sessionStorage.getItem('abonnement_success');
    if (pending) {
      setMessage({ type: 'success', text: pending });
      sessionStorage.removeItem('abonnement_success');
    }
  }, [searchParams]);

  useEffect(() => {
    supabase.from('plans_tarifaires').select('*').eq('profil_type', 'eleveur').eq('actif', true).order('prix_mensuel')
      .then(({ data }) => setPlans((data ?? []) as PlanTarifaire[]));
    supabase.from('produits_ponctuels').select('*').eq('actif', true).order('prix')
      .then(({ data }) => setBoosts((data ?? []) as ProduitPonctuel[]));
  }, []);

  // Charge le plan courant, et active directement via session Stripe si retour de paiement
  useEffect(() => {
    if (!user) return;
    const sessionId = searchParams.get('session_id');
    const isSuccess = !!searchParams.get('success');

    const fetchPlan = async () => {
      const { data } = await supabase
        .from('abonnements').select('plan_code').eq('uid', user.uid).eq('statut', 'actif')
        .order('created_at', { ascending: false }).limit(1).maybeSingle();
      return data?.plan_code ?? 'free';
    };

    if (!isSuccess) {
      fetchPlan().then(setCurrentPlan);
      return;
    }

    // Activation directe via session Stripe (ne dépend pas du webhook)
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
            sessionStorage.setItem('abonnement_success', `🎉 Abonnement ${label} activé !`);
            // Nettoie l'URL et force un refresh complet pour que usePlan + Header se mettent à jour
            router.replace('/abonnement');
            router.refresh();
            return;
          }
        } catch {
          // fallback : polling Supabase
        }
      }
      // Fallback polling au cas où le webhook a déjà mis à jour
      let attempts = 0;
      const poll = async () => {
        const plan = await fetchPlan();
        setCurrentPlan(plan);
        if (plan !== 'free' || attempts >= 4) {
          const label = plan.charAt(0).toUpperCase() + plan.slice(1);
          sessionStorage.setItem('abonnement_success', plan !== 'free' ? `🎉 Abonnement ${label} activé !` : '✅ Paiement reçu, activation en cours…');
          router.replace('/abonnement');
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
        body: JSON.stringify({ uid: user.uid, email: user.email, plan: planCode, periodicite }),
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
        body: JSON.stringify({ uid: user.uid }),
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
        <h1 className="font-['Galey'] font-bold text-3xl text-[#1F2A2E] mb-2">Plans & Abonnements</h1>
        <p className="text-gray-500">Choisissez le plan adapté à votre élevage</p>
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

      {/* Toggle mensuel / annuel */}
      <div className="flex justify-center mb-8">
        <div className="flex bg-gray-100 rounded-xl p-1 gap-1">
          {(['mensuel', 'annuel'] as const).map(p => (
            <button key={p} onClick={() => setPeriodicite(p)}
              className={`px-5 py-2 rounded-lg text-sm font-medium transition-colors ${periodicite === p ? 'bg-white shadow-sm text-[#1F2A2E]' : 'text-gray-500'}`}>
              {p === 'mensuel' ? 'Mensuel' : 'Annuel'}
              {p === 'annuel' && <span className="ml-1.5 text-[10px] bg-green-100 text-green-700 px-1.5 py-0.5 rounded-full font-semibold">-15%</span>}
            </button>
          ))}
        </div>
      </div>

      {/* Plans */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-5 mb-14">
        {plans.length === 0 ? (
          <div className="col-span-3 text-center text-gray-400 py-10">Chargement des plans…</div>
        ) : plans.map(plan => {
          const prix = periodicite === 'mensuel' ? plan.prix_mensuel : Math.round(plan.prix_annuel / 12 * 10) / 10;
          const prixAff = prix === 0 ? 'Gratuit' : `${prix} €/mois`;
          const isCurrent = currentPlan === plan.plan_code;
          const features: string[] = Array.isArray(plan.features) ? plan.features : JSON.parse(plan.features as unknown as string ?? '[]');

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
              <p className="text-xs text-gray-400 mb-4">
                {plan.max_annonces === -1 ? 'Annonces illimitées' : `${plan.max_annonces} annonces max`}
                {' · '}
                {plan.auto_publish ? 'Publication immédiate' : 'Validation admin'}
              </p>
              <ul className="flex-1 space-y-2 mb-6">
                {features.map((f, i) => (
                  <li key={i} className="flex items-start gap-2 text-sm text-gray-700">
                    <span className="text-[#6E9E57] mt-0.5 flex-shrink-0">✓</span>
                    {f}
                  </li>
                ))}
              </ul>
              {isCurrent ? (
                <div className="text-center text-sm font-semibold text-[#0C5C6C] bg-[#EEF5EA] py-2 rounded-xl">
                  Plan actuel
                </div>
              ) : plan.plan_code === 'free' ? (
                <div className="text-center text-sm text-gray-400 py-2">Plan par défaut</div>
              ) : (
                <button onClick={() => handleSubscribe(plan.plan_code)}
                  disabled={loadingPlan === plan.plan_code}
                  className={`w-full py-2.5 rounded-xl text-sm font-semibold transition-colors ${PLAN_BTN[plan.plan_code]}`}>
                  {loadingPlan === plan.plan_code ? (
                    <span className="inline-block w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin" />
                  ) : isCurrent ? 'Plan actuel' : `Passer en ${plan.label}`}
                </button>
              )}
            </div>
          );
        })}
      </div>

      {/* Gérer abonnement */}
      {currentPlan !== 'free' && user && (
        <div className="text-center mb-12">
          <button onClick={handlePortal} disabled={loadingPortal}
            className="text-sm text-gray-500 hover:text-[#0C5C6C] underline">
            {loadingPortal ? 'Chargement…' : 'Gérer mon abonnement (factures, annulation)'}
          </button>
        </div>
      )}

      {/* Boosts ponctuels */}
      <div>
        <h2 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-1">Boosts & options ponctuelles</h2>
        <p className="text-gray-500 text-sm mb-5">Donnez plus de visibilité à vos annonces sans abonnement</p>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {boosts.map(b => (
            <div key={b.id} className="bg-white border border-gray-100 rounded-2xl p-4 shadow-sm">
              <div className="flex items-start justify-between gap-2 mb-2">
                <p className="font-semibold text-[#1F2A2E] text-sm">{b.label}</p>
                <span className="text-[#0C5C6C] font-bold text-sm whitespace-nowrap">{b.prix} €</span>
              </div>
              <p className="text-gray-500 text-xs mb-3">{b.description}</p>
              <Link href="/mes-annonces"
                className="block text-center text-xs font-semibold border border-[#0C5C6C] text-[#0C5C6C] py-1.5 rounded-xl hover:bg-[#0C5C6C] hover:text-white transition-colors">
                Appliquer à une annonce
              </Link>
            </div>
          ))}
        </div>
        {boosts.length === 0 && (
          <p className="text-center text-gray-400 text-sm py-8">Boosts bientôt disponibles</p>
        )}
      </div>
    </div>
  );
}
