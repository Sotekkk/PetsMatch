'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// uid Firebase RÉEL du propriétaire du profil actif — jamais forcément
// user.uid (presque toujours "mon propre compte") : un cogérant
// (elevage_cogerants) a un uid différent du gérant, mais la ligne
// user_profiles du profil emprunté (activeProfileId) reste celle du
// gérant. Centralisé ici une fois plutôt que dans chaque hook : tous les
// use*Plan()/useProfessionPlanCode() en dépendent, donc toute vérification
// de forfait reflète l'abonnement de l'élevage cogéré, pas celui du compte
// du cogérant. Miroir de PlanService._resolveOwnerUid côté appli.
async function resolveOwnerUid(fallbackUid: string, activeProfileId: string): Promise<string> {
  if (!activeProfileId) return fallbackUid;
  try {
    const { data } = await supabase.from('user_profiles').select('uid').eq('id', activeProfileId).maybeSingle();
    return (data?.uid as string | undefined) ?? fallbackUid;
  } catch {
    return fallbackUid;
  }
}

export type PlanCode = 'free' | 'pro' | 'premium';

export interface PlanConfig {
  label: string;
  maxAnnonces: number;
  dureeDays: number;
  autoPublish: boolean;
  hasRegistres: boolean;       // Pro + Premium : suivi sanitaire, entrées/sorties
  hasPlanning: boolean;        // Premium uniquement : planning, routines, agenda
  hasPremiumFeatures: boolean; // Premium uniquement : facturation, contrats
  color: string;
  bg: string;
  badge: string;
}

export const PLAN_CONFIG: Record<PlanCode, PlanConfig> = {
  free:    { label: 'Gratuit', maxAnnonces: 0, dureeDays: 30, autoPublish: false, hasRegistres: false, hasPlanning: false, hasPremiumFeatures: false, color: '#6B7280', bg: '#F3F4F6', badge: '🌱' },
  pro:     { label: 'Pro',     maxAnnonces: 1, dureeDays: 45, autoPublish: true,  hasRegistres: true,  hasPlanning: false, hasPremiumFeatures: false, color: '#0C5C6C', bg: '#E8F4F6', badge: '⚡' },
  premium: { label: 'Premium', maxAnnonces: 3, dureeDays: 60, autoPublish: true,  hasRegistres: true,  hasPlanning: true,  hasPremiumFeatures: true,  color: '#D97706', bg: '#FEF3C7', badge: '👑' },
};

export interface UsePlanResult {
  plan: PlanCode;
  config: PlanConfig;
  activeAnnonces: number;
  loading: boolean;
}

export interface PensionPlanConfig {
  label: string;
  hasInventaire: boolean;
  hasEmployes: boolean;
  maxEmployes: number; // -1 = illimité
  logementsIllimites: boolean;
  hasProtocoles: boolean;
  hasContratSignature: boolean;
  hasFactureExport: boolean;
  hasBadgePremium: boolean;
  prixMensuel: number;
  prixAnnuel: number;
}

// Fallback si plans_tarifaires est indisponible — usePensionPlan() charge
// toujours les prix/labels réels depuis la BDD (éditables depuis /admin).
export const PENSION_PLAN_FALLBACK: Record<PlanCode, PensionPlanConfig> = {
  free:    { label: 'Découverte', hasInventaire: false, hasEmployes: false, maxEmployes: 0, logementsIllimites: false, hasProtocoles: false, hasContratSignature: false, hasFactureExport: false, hasBadgePremium: false, prixMensuel: 0, prixAnnuel: 0 },
  pro:     { label: 'Pro', hasInventaire: true, hasEmployes: true, maxEmployes: 3, logementsIllimites: true, hasProtocoles: true, hasContratSignature: true, hasFactureExport: true, hasBadgePremium: false, prixMensuel: 14, prixAnnuel: 140 },
  premium: { label: 'Premium', hasInventaire: true, hasEmployes: true, maxEmployes: -1, logementsIllimites: true, hasProtocoles: true, hasContratSignature: true, hasFactureExport: true, hasBadgePremium: true, prixMensuel: 24, prixAnnuel: 240 },
};

export interface UsePensionPlanResult {
  plan: PlanCode;
  config: PensionPlanConfig;
  loading: boolean;
}

/** Plan pension actif — distinct du plan éleveur (abonnements est scopé
 * par profil_type, un même compte peut avoir les deux simultanément). */
export function usePensionPlan(): UsePensionPlanResult {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [plan, setPlan] = useState<PlanCode>('free');
  const [config, setConfig] = useState<PensionPlanConfig>(PENSION_PLAN_FALLBACK.free);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    (async () => {
      try {
        const ownerUid = await resolveOwnerUid(user.uid, activeProfileId);
        const abo = await supabase
          .from('abonnements')
          .select('plan_code')
          .eq('uid', ownerUid)
          .eq('profil_type', 'pension')
          .eq('statut', 'actif')
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        const code = (abo.data?.plan_code ?? 'free') as PlanCode;
        setPlan(code);
        const { data: planRow } = await supabase
          .from('plans_tarifaires')
          .select('label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', 'pension')
          .eq('plan_code', code)
          .maybeSingle();
        const fallback = PENSION_PLAN_FALLBACK[code];
        if (planRow) {
          const f = (planRow.features ?? {}) as Record<string, unknown>;
          setConfig({
            label: planRow.label ?? fallback.label,
            prixMensuel: planRow.prix_mensuel ?? fallback.prixMensuel,
            prixAnnuel: planRow.prix_annuel ?? fallback.prixAnnuel,
            hasInventaire: Boolean(f.hasInventaire),
            hasEmployes: Boolean(f.hasEmployes),
            maxEmployes: typeof f.maxEmployes === 'number' ? f.maxEmployes : fallback.maxEmployes,
            logementsIllimites: Boolean(f.logementsIllimites),
            hasProtocoles: Boolean(f.hasProtocoles),
            hasContratSignature: Boolean(f.hasContratSignature),
            hasFactureExport: Boolean(f.hasFactureExport),
            hasBadgePremium: Boolean(f.hasBadgePremium),
          });
        } else {
          setConfig(fallback);
        }
        setLoading(false);
      } catch {
        setLoading(false);
      }
    })();
  }, [user, activeProfileId]);

  return { plan, config, loading };
}

export interface GardePlanConfig {
  label: string;
  hasInventaire: boolean;
  hasEmployes: boolean;
  maxEmployes: number; // -1 = illimité
  hasProtocoles: boolean;
  hasFactureExport: boolean;
  hasBadgePremium: boolean;
  prixMensuel: number;
  prixAnnuel: number;
}

// Fallback si plans_tarifaires est indisponible — usePlanGarde() charge
// toujours les prix/labels réels depuis la BDD (éditables depuis /admin).
export const GARDE_PLAN_FALLBACK: Record<PlanCode, GardePlanConfig> = {
  free:    { label: 'Découverte', hasInventaire: false, hasEmployes: false, maxEmployes: 0, hasProtocoles: false, hasFactureExport: false, hasBadgePremium: false, prixMensuel: 0, prixAnnuel: 0 },
  pro:     { label: 'Pro', hasInventaire: true, hasEmployes: true, maxEmployes: 3, hasProtocoles: true, hasFactureExport: true, hasBadgePremium: false, prixMensuel: 14, prixAnnuel: 140 },
  premium: { label: 'Premium', hasInventaire: true, hasEmployes: true, maxEmployes: -1, hasProtocoles: true, hasFactureExport: true, hasBadgePremium: true, prixMensuel: 24, prixAnnuel: 240 },
};

export interface UseGardePlanResult {
  plan: PlanCode;
  config: GardePlanConfig;
  loading: boolean;
}

/** Plan garde (petsitter/promeneur) actif — distinct du plan éleveur/pension/
 * éducateur (abonnements est scopé par profil_type). */
export function usePlanGarde(): UseGardePlanResult {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [plan, setPlan] = useState<PlanCode>('free');
  const [config, setConfig] = useState<GardePlanConfig>(GARDE_PLAN_FALLBACK.free);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    (async () => {
      try {
        const ownerUid = await resolveOwnerUid(user.uid, activeProfileId);
        const abo = await supabase
          .from('abonnements')
          .select('plan_code')
          .eq('uid', ownerUid)
          .eq('profil_type', 'garde')
          .eq('statut', 'actif')
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        const code = (abo.data?.plan_code ?? 'free') as PlanCode;
        setPlan(code);
        const { data: planRow } = await supabase
          .from('plans_tarifaires')
          .select('label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', 'garde')
          .eq('plan_code', code)
          .maybeSingle();
        const fallback = GARDE_PLAN_FALLBACK[code];
        if (planRow) {
          const f = (planRow.features ?? {}) as Record<string, unknown>;
          setConfig({
            label: planRow.label ?? fallback.label,
            prixMensuel: planRow.prix_mensuel ?? fallback.prixMensuel,
            prixAnnuel: planRow.prix_annuel ?? fallback.prixAnnuel,
            hasInventaire: Boolean(f.hasInventaire),
            hasEmployes: Boolean(f.hasEmployes),
            maxEmployes: typeof f.maxEmployes === 'number' ? f.maxEmployes : fallback.maxEmployes,
            hasProtocoles: Boolean(f.hasProtocoles),
            hasFactureExport: Boolean(f.hasFactureExport),
            hasBadgePremium: Boolean(f.hasBadgePremium),
          });
        } else {
          setConfig(fallback);
        }
        setLoading(false);
      } catch {
        setLoading(false);
      }
    })();
  }, [user, activeProfileId]);

  return { plan, config, loading };
}

export interface EducationPlanConfig {
  label: string;
  hasEmployes: boolean;
  maxEmployes: number; // -1 = illimité
  hasBadgePremium: boolean;
  hasFactureExport: boolean;
  hasAccesPrioritaire: boolean;
  prixMensuel: number;
  prixAnnuel: number;
}

// Fallback si plans_tarifaires est indisponible — useEducationPlan() charge
// toujours les prix/labels réels depuis la BDD (éditables depuis /admin).
export const EDUCATION_PLAN_FALLBACK: Record<PlanCode, EducationPlanConfig> = {
  free:    { label: 'Découverte', hasEmployes: false, maxEmployes: 0, hasBadgePremium: false, hasFactureExport: false, hasAccesPrioritaire: false, prixMensuel: 0, prixAnnuel: 0 },
  pro:     { label: 'Pro', hasEmployes: true, maxEmployes: 3, hasBadgePremium: false, hasFactureExport: true, hasAccesPrioritaire: false, prixMensuel: 15, prixAnnuel: 150 },
  premium: { label: 'Premium', hasEmployes: true, maxEmployes: -1, hasBadgePremium: true, hasFactureExport: true, hasAccesPrioritaire: true, prixMensuel: 25, prixAnnuel: 249.98 },
};

export interface UseEducationPlanResult {
  plan: PlanCode;
  config: EducationPlanConfig;
  loading: boolean;
}

/** Plan éducateur/comportementaliste actif — distinct du plan éleveur/
 * pension/garde (abonnements est scopé par profil_type). */
export function useEducationPlan(): UseEducationPlanResult {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [plan, setPlan] = useState<PlanCode>('free');
  const [config, setConfig] = useState<EducationPlanConfig>(EDUCATION_PLAN_FALLBACK.free);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    (async () => {
      try {
        const ownerUid = await resolveOwnerUid(user.uid, activeProfileId);
        const abo = await supabase
          .from('abonnements')
          .select('plan_code')
          .eq('uid', ownerUid)
          .eq('profil_type', 'education')
          .eq('statut', 'actif')
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        const code = (abo.data?.plan_code ?? 'free') as PlanCode;
        setPlan(code);
        const { data: planRow } = await supabase
          .from('plans_tarifaires')
          .select('label, prix_mensuel, prix_annuel, features')
          .eq('profil_type', 'education')
          .eq('plan_code', code)
          .maybeSingle();
        const fallback = EDUCATION_PLAN_FALLBACK[code];
        if (planRow) {
          const f = (planRow.features ?? {}) as Record<string, unknown>;
          setConfig({
            label: planRow.label ?? fallback.label,
            prixMensuel: planRow.prix_mensuel ?? fallback.prixMensuel,
            prixAnnuel: planRow.prix_annuel ?? fallback.prixAnnuel,
            hasEmployes: Boolean(f.hasEmployes),
            maxEmployes: typeof f.maxEmployes === 'number' ? f.maxEmployes : fallback.maxEmployes,
            hasBadgePremium: Boolean(f.hasBadgePremium),
            hasFactureExport: Boolean(f.hasFactureExport),
            hasAccesPrioritaire: Boolean(f.hasAccesPrioritaire),
          });
        } else {
          setConfig(fallback);
        }
        setLoading(false);
      } catch {
        setLoading(false);
      }
    })();
  }, [user, activeProfileId]);

  return { plan, config, loading };
}

// Palier le plus haut (= fonctionnalités premium débloquées) par métier —
// diffère de 'premium' pour plusieurs d'entre eux (grilles tarifaires
// distinctes, cf. plans_tarifaires / chaque page <métier>/abonnement).
// Partagé entre Header.tsx (badge « Premium » dans le drawer) et
// elevage/facturation/page.tsx (verrou d'accès réel) — ne pas dupliquer.
export const PROFESSION_TOP_TIER: Record<string, string> = {
  education: 'premium',
  toilettage: 'premium',
  veterinaire: 'clinique',
  sante: 'pro',
  marechal_ferrant: 'pro',
  photographe: 'essentiel',
};

/**
 * Code du plan actif pour un métier quelconque — générique, contrairement à
 * usePensionPlan()/usePlanGarde()/useEducationPlan() : ne renvoie que le
 * plan_code, pas de config enrichie (features). Utile pour un verrou ponctuel
 * partagé entre plusieurs métiers sans hook dédié (véto/santé/toilettage/
 * maréchal-ferrant/photographe) plutôt que de dupliquer 5 hooks quasi
 * identiques pour un seul point d'usage. Passer `profilType: ''` désactive
 * la requête (utile pour appeler ce hook conditionnellement en respectant les
 * règles des Hooks).
 */
export function useProfessionPlanCode(profilType: string): { planCode: PlanCode; loading: boolean } {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [planCode, setPlanCode] = useState<PlanCode>('free');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user || !profilType) { setLoading(false); return; }
    setLoading(true);
    resolveOwnerUid(user.uid, activeProfileId).then(ownerUid =>
      supabase.from('abonnements')
        .select('plan_code')
        .eq('uid', ownerUid)
        .eq('profil_type', profilType)
        .eq('statut', 'actif')
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()
        .then(({ data }) => {
          setPlanCode((data?.plan_code ?? 'free') as PlanCode);
          setLoading(false);
        })
    );
  }, [user, profilType, activeProfileId]);

  return { planCode, loading };
}

export function usePlan(): UsePlanResult {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [plan, setPlan] = useState<PlanCode>('free');
  const [activeAnnonces, setActiveAnnonces] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    (async () => {
      const ownerUid = await resolveOwnerUid(user.uid, activeProfileId);
      const [abo, ann] = await Promise.all([
        supabase
          .from('abonnements')
          .select('plan_code')
          .eq('uid', ownerUid)
          .eq('profil_type', 'eleveur')
          .eq('statut', 'actif')
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle(),
        supabase
          .from('annonces')
          .select('id', { count: 'exact', head: true })
          .eq('uid_eleveur', ownerUid)
          .in('statut', ['disponible', 'en_attente', 'pause', 'reserve']),
      ]);
      setPlan((abo.data?.plan_code ?? 'free') as PlanCode);
      setActiveAnnonces(ann.count ?? 0);
      setLoading(false);
    })().catch(() => setLoading(false));
  }, [user, activeProfileId]);

  return { plan, config: PLAN_CONFIG[plan], activeAnnonces, loading };
}
