'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile, ACTIVE_PROFILE_TYPE_KEY } from '@/hooks/useActiveProfile';
import { useProfessionPlanCode } from '@/lib/use-plan';
import { supabase } from '@/lib/supabase';
import EmployesAvancesPage from '@/components/pro/EmployesAvancesPage';

const TYPES_PRESTATION_TOILETTAGE = [
  { key: 'bain',     label: 'Bain' },
  { key: 'coupe',    label: 'Coupe' },
  { key: 'tonte',    label: 'Tonte' },
  { key: 'demelage', label: 'Démêlage' },
  { key: 'griffes',  label: 'Griffes' },
  { key: 'oreilles', label: 'Oreilles' },
  { key: 'hygiene',  label: 'Hygiène' },
  { key: 'spa',      label: 'SPA' },
];

/** Pas de hook d'accès dédié pour toilettage (mirror usePensionAccess/useGardeAccess) — inline ici. */
function useToilettageAccess() {
  const { user, userData, loading, availableProfiles, activeProfileId } = useAuth();
  const activeProfile = availableProfiles.find(p => p.id === activeProfileId) ?? null;
  const cachedProfileType = typeof window !== 'undefined' ? localStorage.getItem(ACTIVE_PROFILE_TYPE_KEY) : null;
  const resolvedProfileType = activeProfile?.profile_type
    ?? (activeProfileId && !activeProfile ? cachedProfileType : null);
  const isToilettage = resolvedProfileType
    ? resolvedProfileType === 'toilettage'
    : (userData?.isPro === true && userData?.catPro === 'toilettage');
  return { user, isToilettage, loading };
}

export default function ToilettageEmployesPage() {
  const { isToilettage, loading: guardLoading } = useToilettageAccess();
  const { planCode, loading: planCodeLoading } = useProfessionPlanCode('toilettage');
  const activeProfileId = useActiveProfile();
  const [hasPlanningEmployes, setHasPlanningEmployes] = useState(false);
  const [featLoading, setFeatLoading] = useState(true);

  useEffect(() => {
    if (planCodeLoading) return;
    supabase.from('plans_tarifaires').select('features')
      .eq('profil_type', 'toilettage').eq('plan_code', planCode).maybeSingle()
      .then(({ data }) => {
        const f = (data?.features ?? {}) as Record<string, unknown>;
        setHasPlanningEmployes(Boolean(f.hasPlanningEmployes));
        setFeatLoading(false);
      });
  }, [planCode, planCodeLoading, activeProfileId]);

  return (
    <EmployesAvancesPage
      themeColor="#FFB74D"
      title="Mes employés"
      competences={TYPES_PRESTATION_TOILETTAGE}
      hasEmployes={hasPlanningEmployes}
      planLoading={planCodeLoading || featLoading}
      abonnementHref="/toilettage/abonnement"
      guardOk={isToilettage}
      guardLoading={guardLoading}
    />
  );
}
