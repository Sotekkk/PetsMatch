'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

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
  free:    { label: 'Gratuit', maxAnnonces: 3,  dureeDays: 30, autoPublish: false, hasRegistres: false, hasPlanning: false, hasPremiumFeatures: false, color: '#6B7280', bg: '#F3F4F6', badge: '🌱' },
  pro:     { label: 'Pro',     maxAnnonces: 10, dureeDays: 45, autoPublish: true,  hasRegistres: true,  hasPlanning: false, hasPremiumFeatures: false, color: '#0C5C6C', bg: '#E8F4F6', badge: '⚡' },
  premium: { label: 'Premium', maxAnnonces: -1, dureeDays: 60, autoPublish: true,  hasRegistres: true,  hasPlanning: true,  hasPremiumFeatures: true,  color: '#D97706', bg: '#FEF3C7', badge: '👑' },
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
  const [plan, setPlan] = useState<PlanCode>('free');
  const [config, setConfig] = useState<PensionPlanConfig>(PENSION_PLAN_FALLBACK.free);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    (async () => {
      try {
        const abo = await supabase
          .from('abonnements')
          .select('plan_code')
          .eq('uid', user.uid)
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
  }, [user]);

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
  const [plan, setPlan] = useState<PlanCode>('free');
  const [config, setConfig] = useState<GardePlanConfig>(GARDE_PLAN_FALLBACK.free);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    (async () => {
      try {
        const abo = await supabase
          .from('abonnements')
          .select('plan_code')
          .eq('uid', user.uid)
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
  }, [user]);

  return { plan, config, loading };
}

export function usePlan(): UsePlanResult {
  const { user } = useAuth();
  const [plan, setPlan] = useState<PlanCode>('free');
  const [activeAnnonces, setActiveAnnonces] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    Promise.all([
      supabase
        .from('abonnements')
        .select('plan_code')
        .eq('uid', user.uid)
        .eq('statut', 'actif')
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from('annonces')
        .select('id', { count: 'exact', head: true })
        .eq('uid_eleveur', user.uid)
        .in('statut', ['disponible', 'en_attente', 'pause', 'reserve']),
    ]).then(([abo, ann]) => {
      setPlan((abo.data?.plan_code ?? 'free') as PlanCode);
      setActiveAnnonces(ann.count ?? 0);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, [user]);

  return { plan, config: PLAN_CONFIG[plan], activeAnnonces, loading };
}
