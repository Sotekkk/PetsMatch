'use client';

import { Suspense, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';

interface PlanRow {
  id: string;
  profil_type: string;
  plan_code: string;
  label: string;
  prix_mensuel: number;
  prix_annuel: number;
  max_annonces: number | null;
  auto_publish: boolean | null;
  features: unknown;
}

const METIERS: { key: string; label: string }[] = [
  { key: 'eleveur',          label: 'Éleveur' },
  { key: 'garde',            label: 'Garde / Pet-sitting' },
  { key: 'pension',          label: 'Pension' },
  { key: 'education',        label: 'Éducateur / Comportementaliste' },
  { key: 'toilettage',       label: 'Toiletteur' },
  { key: 'sante',            label: 'Ostéo / Kiné' },
  { key: 'veterinaire',      label: 'Vétérinaire' },
  { key: 'photographe',      label: 'Photographe animalier' },
  { key: 'marechal_ferrant', label: 'Maréchal-ferrant' },
];

// Mêmes couleurs que chaque page d'abonnement (website/src/app/<métier>/abonnement/page.tsx)
const PLAN_COLORS_BY_METIER: Record<string, Record<string, string>> = {
  eleveur:          { free: 'border-gray-200 bg-white', pro: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20', premium: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  garde:            { free: 'border-gray-200 bg-white', pro: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20', premium: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  pension:          { free: 'border-gray-200 bg-white', pro: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20', premium: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  toilettage:       { free: 'border-gray-200 bg-white', pro: 'border-[#FFB74D] bg-white ring-2 ring-[#FFB74D]/20', premium: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  education:        { free: 'border-gray-200 bg-white', pro: 'border-[#7B5EA7] bg-white ring-2 ring-[#7B5EA7]/20', premium: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  sante:            { free: 'border-gray-200 bg-white', essentiel: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20', pro: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  marechal_ferrant: { free: 'border-gray-200 bg-white', essentiel: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20', pro: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  veterinaire:      { free: 'border-gray-200 bg-white', avance: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20', clinique: 'border-[#D97706] bg-white ring-2 ring-[#D97706]/20' },
  photographe:      { free: 'border-gray-200 bg-white', essentiel: 'border-[#0C5C6C] bg-white ring-2 ring-[#0C5C6C]/20' },
};

// Palier mis en avant (ruban « Populaire ») par métier, + sa couleur.
const POPULAIRE_BY_METIER: Record<string, string> = {
  eleveur: 'pro', garde: 'pro', pension: 'pro', toilettage: 'pro', education: 'pro',
  sante: 'essentiel', marechal_ferrant: 'essentiel', veterinaire: 'avance', photographe: 'essentiel',
};
const POPULAIRE_COLOR: Record<string, string> = {
  eleveur: '#0C5C6C', garde: '#0C5C6C', pension: '#0C5C6C', education: '#7B5EA7',
  toilettage: '#FFB74D', sante: '#0C5C6C', marechal_ferrant: '#0C5C6C', veterinaire: '#0C5C6C',
  photographe: '#0C5C6C',
};

/**
 * Reprend mot pour mot les libellés déjà affichés sur chaque page
 * d'abonnement réelle (website/src/app/<métier>/abonnement/page.tsx) — ne
 * jamais reformuler, sous peine d'afficher un texte différent de ce que
 * voit un pro au moment de s'abonner pour de vrai.
 */
function featureLabels(profilType: string, raw: unknown): string[] {
  if (profilType === 'eleveur') {
    return Array.isArray(raw) ? (raw as string[]) : [];
  }
  const f = (raw ?? {}) as Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
  switch (profilType) {
    case 'education': {
      const out = ['Planning + cours individuels/collectifs', 'Tarification & suivi de progression', 'Réservation en ligne'];
      if (f.hasEmployes) out.push(f.maxEmployes === -1 ? 'Employés illimités' : `Jusqu'à ${f.maxEmployes} employés`);
      if (f.hasContratSignature) out.push('Contrats — signature électronique');
      if (f.hasFactureExport) out.push('Export factures');
      if (f.hasBadgePremium) out.push('Badge premium + mise en avant annuaire');
      if (f.hasAccesPrioritaire) out.push('Accès prioritaire support');
      return out;
    }
    case 'garde': {
      const out: string[] = [];
      if (f.hasEmployes) out.push(f.maxEmployes === -1 ? 'Employés illimités' : `Jusqu'à ${f.maxEmployes} employés`);
      if (f.hasInventaire) out.push('Inventaire');
      if (f.hasProtocoles) out.push('Protocoles / Tâches');
      if (f.hasContratSignature) out.push('Contrats — signature électronique');
      if (f.hasFactureExport) out.push('Export factures');
      if (f.hasBadgePremium) out.push('Badge premium + mise en avant annuaire');
      return out;
    }
    case 'marechal_ferrant':
    case 'sante': {
      const out = [f.hasAjoutSeances ? 'Ajout de séances au carnet santé' : 'Annuaire basique, token 72h'];
      if (f.hasMultiIntervenants) out.push(f.maxIntervenants === -1 ? 'Multi-intervenants illimité' : `Jusqu'à ${f.maxIntervenants} intervenants`);
      if (f.hasFactureExport) out.push('Facturation clients + export CSV');
      return out;
    }
    case 'pension': {
      const out = [f.logementsIllimites ? 'Logements illimités' : '1 logement'];
      if (f.hasEmployes) out.push(f.maxEmployes === -1 ? 'Employés illimités' : `Jusqu'à ${f.maxEmployes} employés`);
      if (f.hasInventaire) out.push('Inventaire');
      if (f.hasProtocoles) out.push('Protocoles / Tâches');
      if (f.hasContratSignature) out.push('Contrats — signature électronique');
      if (f.hasFactureExport) out.push('Export factures');
      if (f.hasBadgePremium) out.push('Badge premium + mise en avant annuaire');
      return out;
    }
    case 'photographe': {
      const out = [f.maxPhotosPortfolio === -1 ? 'Portfolio illimité' : `${f.maxPhotosPortfolio ?? 5} photos portfolio`];
      if (f.hasMiseEnAvant) out.push('Mis en avant dans l\'annuaire');
      if (f.hasStatistiques) out.push('Statistiques de profil');
      return out;
    }
    case 'toilettage': {
      const out = [f.hasEmployesIllimites ? 'Employés illimités' : `Jusqu'à ${f.maxEmployes} employé`];
      if (f.hasFacturation) out.push('Facturation');
      if (f.hasStatistiques) out.push('Statistiques');
      if (f.hasGalerie) out.push('Galerie');
      if (f.hasNotifications) out.push('Notifications');
      if (f.hasExport) out.push('Export');
      if (f.hasPlanningEmployes) out.push('Planning employés');
      if (f.hasContratSignature) out.push('Contrats + signature électronique');
      if (f.hasMiseEnAvant) out.push('Mise en avant');
      return out;
    }
    case 'veterinaire': {
      const out = [f.hasAccesPermanent ? 'Accès lecture permanent' : 'Lecture via token 72h'];
      if (f.hasEcritureCarnetSante) out.push('Écriture carnet santé');
      if (f.hasRappelsPush) out.push('Rappels push');
      if (f.hasMultiPraticiens) out.push(f.maxPraticiens === -1 ? 'Multi-praticiens illimité' : `Jusqu'à ${f.maxPraticiens} praticiens`);
      if (f.hasExportCsv) out.push('Export CSV logiciels vétérinaires');
      return out;
    }
    default:
      return [];
  }
}

function TarifsInner() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [plans, setPlans] = useState<PlanRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [periodicite, setPeriodicite] = useState<'mensuel' | 'annuel'>('mensuel');

  const metierParam = searchParams.get('metier');
  const metier = METIERS.some(m => m.key === metierParam) ? metierParam! : 'eleveur';

  useEffect(() => {
    supabase.from('plans_tarifaires').select('*').eq('actif', true)
      .order('profil_type').order('prix_mensuel')
      .then(({ data }) => { setPlans((data ?? []) as PlanRow[]); setLoading(false); });
  }, []);

  function setMetier(key: string) {
    router.replace(`/tarifs?metier=${key}`, { scroll: false });
  }

  const plansForMetier = plans.filter(p => p.profil_type === metier);

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      {/* Hero */}
      <div className="bg-gradient-to-b from-[#0C5C6C] to-[#0A4A56] text-white px-4 py-14 text-center">
        <h1 className="font-['Galey'] font-bold text-3xl sm:text-4xl mb-3">Nos tarifs</h1>
        <p className="text-white/85 max-w-xl mx-auto">
          100&nbsp;% gratuit pour les particuliers. Pour les professionnels, 30&nbsp;jours d&apos;essai
          offerts, puis une formule adaptée à votre activité.
        </p>
      </div>

      <div className="max-w-5xl mx-auto px-4 py-10">
        {/* Particulier & association — toujours gratuits */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-5 mb-14">
          <div className="rounded-2xl border-2 border-[#6E9E57] bg-white p-6">
            <h2 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-1">Particulier</h2>
            <p className="text-2xl font-bold text-[#6E9E57] mb-4">Gratuit à vie</p>
            <ul className="space-y-2 text-sm text-gray-700">
              {[
                'Carnet de santé de vos animaux',
                'Réseau social & messagerie',
                'Publier un animal perdu ou trouvé',
                'Communauté & groupes',
                'Déposer une petite annonce',
              ].map(f => (
                <li key={f} className="flex items-start gap-2">
                  <span className="text-[#6E9E57] mt-0.5 flex-shrink-0">✓</span>{f}
                </li>
              ))}
            </ul>
          </div>
          <div className="rounded-2xl border-2 border-[#6E9E57] bg-white p-6">
            <h2 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-1">Association</h2>
            <p className="text-2xl font-bold text-[#6E9E57] mb-4">Gratuit à vie</p>
            <ul className="space-y-2 text-sm text-gray-700">
              {[
                'Fiche association publique',
                'Publier vos animaux à l\'adoption',
                'Gestion des dossiers d\'adoption',
                'Suivi des dons & bénévoles',
              ].map(f => (
                <li key={f} className="flex items-start gap-2">
                  <span className="text-[#6E9E57] mt-0.5 flex-shrink-0">✓</span>{f}
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* Sélecteur métier */}
        <h2 className="font-['Galey'] font-bold text-2xl text-[#1F2A2E] text-center mb-2">Professionnels</h2>
        <p className="text-center text-[#D97706] font-semibold text-sm mb-6">
          30 jours d&apos;essai offerts sur toutes les formules payantes
        </p>
        <div className="flex flex-wrap justify-center gap-2 mb-8">
          {METIERS.map(m => (
            <button key={m.key} onClick={() => setMetier(m.key)}
              className={`px-4 py-2 rounded-full text-sm font-semibold border transition-colors ${
                metier === m.key
                  ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                  : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
              }`}>
              {m.label}
            </button>
          ))}
        </div>

        {/* Toggle mensuel / annuel — l'économie affichée est calculée depuis les
            vrais tarifs du métier sélectionné, pas une remise générique. */}
        {(() => {
          const payants = plansForMetier.filter(p => p.prix_mensuel > 0);
          const bestPct = payants.length > 0
            ? Math.max(...payants.map(p => Math.round((1 - p.prix_annuel / (p.prix_mensuel * 12)) * 100)))
            : 0;
          return (
            <div className="flex flex-col items-center gap-2 mb-8">
              <div className="flex bg-gray-100 rounded-xl p-1 gap-1">
                {(['mensuel', 'annuel'] as const).map(p => (
                  <button key={p} onClick={() => setPeriodicite(p)}
                    className={`px-5 py-2 rounded-lg text-sm font-medium transition-colors ${periodicite === p ? 'bg-white shadow-sm text-[#1F2A2E]' : 'text-gray-500'}`}>
                    {p === 'mensuel' ? 'Mensuel' : 'Annuel'}
                    {p === 'annuel' && bestPct > 0 && (
                      <span className="ml-1.5 text-[10px] bg-green-100 text-green-700 px-1.5 py-0.5 rounded-full font-semibold">
                        -{bestPct}%
                      </span>
                    )}
                  </button>
                ))}
              </div>
              {periodicite === 'mensuel' && bestPct > 0 && (
                <button onClick={() => setPeriodicite('annuel')}
                  className="text-xs text-[#6E9E57] font-semibold hover:underline">
                  Payez à l&apos;année et économisez jusqu&apos;à {bestPct}&nbsp;%
                </button>
              )}
            </div>
          );
        })()}

        {/* Cartes de plans */}
        {loading ? (
          <div className="text-center text-gray-400 py-10">Chargement…</div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5 mb-14">
            {plansForMetier.map(plan => {
              const prix = periodicite === 'mensuel' ? plan.prix_mensuel : Math.round(plan.prix_annuel / 12 * 10) / 10;
              const prixAff = prix === 0 ? 'Gratuit' : `${prix} €/mois`;
              const color = PLAN_COLORS_BY_METIER[metier]?.[plan.plan_code] ?? 'border-gray-200 bg-white';
              const isPopulaire = POPULAIRE_BY_METIER[metier] === plan.plan_code;
              const features = featureLabels(metier, plan.features);
              const isFree = plan.plan_code === 'free' || plan.plan_code === 'decouverte';

              return (
                <div key={plan.plan_code} className={`rounded-2xl border p-6 flex flex-col relative ${color}`}>
                  {isPopulaire && (
                    <div className="absolute -top-3 left-1/2 -translate-x-1/2 text-white text-xs font-bold px-3 py-0.5 rounded-full"
                      style={{ background: POPULAIRE_COLOR[metier] ?? '#0C5C6C' }}>
                      Populaire
                    </div>
                  )}
                  <h3 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-1 mt-1">{plan.label}</h3>
                  <p className="text-2xl font-bold text-[#1F2A2E] mb-1">
                    {prixAff}
                    {prix > 0 && periodicite === 'annuel' && (
                      <span className="text-sm font-normal text-gray-400 ml-1">({plan.prix_annuel} €/an)</span>
                    )}
                  </p>
                  {periodicite === 'annuel' && plan.prix_mensuel > 0 && (() => {
                    const economie = Math.round((plan.prix_mensuel * 12 - plan.prix_annuel) * 100) / 100;
                    if (economie <= 0) return null;
                    return (
                      <p className="text-xs font-semibold text-[#6E9E57] mb-1">
                        Économisez {economie}&nbsp;€/an vs mensuel
                      </p>
                    );
                  })()}
                  {metier === 'eleveur' && (
                    <p className="text-xs text-gray-400 mb-1">
                      {plan.max_annonces === -1 ? 'Annonces illimitées' : `${plan.max_annonces} annonces max`}
                      {' · '}
                      {plan.auto_publish ? 'Publication immédiate' : 'Validation admin'}
                    </p>
                  )}
                  {!isFree && (
                    <p className="text-xs text-[#D97706] font-semibold mb-3">30 jours d&apos;essai offerts</p>
                  )}
                  <ul className="flex-1 space-y-2 mb-6 mt-2">
                    {features.map((f, i) => (
                      <li key={i} className="flex items-start gap-2 text-sm text-gray-700">
                        <span className="text-[#6E9E57] mt-0.5 flex-shrink-0">✓</span>{f}
                      </li>
                    ))}
                  </ul>
                  <Link href="/inscription"
                    className="w-full text-center py-2.5 rounded-xl text-sm font-semibold transition-colors bg-[#0C5C6C] hover:bg-[#094F5D] text-white">
                    Commencer
                  </Link>
                </div>
              );
            })}
          </div>
        )}

        {/* Contact */}
        <div className="text-center border-t border-gray-200 pt-10">
          <p className="text-gray-600 mb-3">Une question sur nos formules ?</p>
          <Link href="/contact"
            className="inline-block px-6 py-3 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] font-semibold hover:bg-[#E8F4F6] transition-colors">
            Nous contacter
          </Link>
        </div>
      </div>
    </div>
  );
}

export default function TarifsPage() {
  return (
    <Suspense fallback={
      <div className="flex justify-center items-center min-h-screen">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    }>
      <TarifsInner />
    </Suspense>
  );
}
