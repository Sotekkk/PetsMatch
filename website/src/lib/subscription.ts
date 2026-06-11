import { createClient } from '@supabase/supabase-js';

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export type PlanCode = 'free' | 'pro' | 'premium';

export interface PlanInfo {
  plan: PlanCode;
  maxAnnonces: number;
  dureeDays: number;
  autoPublish: boolean;
}

const FALLBACK: Record<PlanCode, PlanInfo> = {
  free:    { plan: 'free',    maxAnnonces: 3,  dureeDays: 30, autoPublish: false },
  pro:     { plan: 'pro',     maxAnnonces: 10, dureeDays: 45, autoPublish: true  },
  premium: { plan: 'premium', maxAnnonces: -1, dureeDays: 60, autoPublish: true  },
};

export async function getUserPlan(uid: string): Promise<PlanInfo> {
  try {
    const { data } = await supabaseAdmin
      .from('abonnements')
      .select('plan_code')
      .eq('uid', uid)
      .eq('statut', 'actif')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    const code = (data?.plan_code ?? 'free') as PlanCode;
    return FALLBACK[code] ?? FALLBACK.free;
  } catch {
    return FALLBACK.free;
  }
}

export async function countActiveAnnonces(uid: string): Promise<number> {
  try {
    const { count } = await supabaseAdmin
      .from('annonces')
      .select('id', { count: 'exact', head: true })
      .eq('uid_eleveur', uid)
      .in('statut', ['disponible', 'en_attente']);
    return count ?? 0;
  } catch {
    return 0;
  }
}
