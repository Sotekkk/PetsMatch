'use client';

import EmployesAvancesPage from '@/components/pro/EmployesAvancesPage';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { usePlanGarde } from '@/lib/use-plan';

// Mêmes motifs que la réservation garde (rdv_booking_page.dart côté appli) —
// utilisés ici comme "compétences" pour restreindre les missions confiées.
const TYPES_SERVICE_GARDE = [
  { key: 'promenade_30min', label: 'Promenade 30 min' },
  { key: 'promenade_1h',    label: 'Promenade 1h' },
  { key: 'promenade_2h',    label: 'Promenade 2h' },
  { key: 'visite_domicile', label: 'Visite à domicile' },
  { key: 'garde_journee',   label: 'Garde journée' },
];

export default function GardeEmployesPage() {
  const { isGarde, loading: guardLoading } = useGardeAccess();
  const { config, loading: planLoading } = usePlanGarde();

  return (
    <EmployesAvancesPage
      themeColor="#6E9E57"
      title="Mes employés"
      competences={TYPES_SERVICE_GARDE}
      hasEmployes={config.hasEmployes}
      planLoading={planLoading}
      abonnementHref="/garde/abonnement"
      guardOk={isGarde}
      guardLoading={guardLoading}
    />
  );
}
