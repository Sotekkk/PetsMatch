'use client';

import EmployesAvancesPage from '@/components/pro/EmployesAvancesPage';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { usePensionPlan } from '@/lib/use-plan';
import { PENSION_ESPECES } from '@/lib/pension-especes';

export default function PensionEmployesPage() {
  const { isPension, loading: guardLoading } = usePensionAccess();
  const { config, loading: planLoading } = usePensionPlan();

  return (
    <EmployesAvancesPage
      themeColor="#0C5C6C"
      title="Mes employés"
      competences={PENSION_ESPECES.map(e => ({ key: e.key, label: `${e.emoji} ${e.label}` }))}
      hasEmployes={config.hasEmployes}
      planLoading={planLoading}
      abonnementHref="/pension/abonnement"
      guardOk={isPension}
      guardLoading={guardLoading}
    />
  );
}
