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
  hasRegistres: boolean;
  color: string;
  bg: string;
  badge: string;
}

export const PLAN_CONFIG: Record<PlanCode, PlanConfig> = {
  free:    { label: 'Gratuit', maxAnnonces: 3,  dureeDays: 30, autoPublish: false, hasRegistres: false, color: '#6B7280', bg: '#F3F4F6', badge: '🌱' },
  pro:     { label: 'Pro',     maxAnnonces: 10, dureeDays: 45, autoPublish: true,  hasRegistres: true,  color: '#0C5C6C', bg: '#E8F4F6', badge: '⚡' },
  premium: { label: 'Premium', maxAnnonces: -1, dureeDays: 60, autoPublish: true,  hasRegistres: true,  color: '#D97706', bg: '#FEF3C7', badge: '👑' },
};

export interface UsePlanResult {
  plan: PlanCode;
  config: PlanConfig;
  activeAnnonces: number;
  loading: boolean;
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
