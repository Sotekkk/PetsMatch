'use client';
// Galerie partagée par le client à ses proches : consultation seule, aperçus
// toujours filigranés (servis par /api/galeries/proches), sans compte. Jamais
// indexée (layout : robots noindex ; API : X-Robots-Tag).
import { useCallback } from 'react';
import { useParams } from 'next/navigation';
import GalerieVue from '@/components/galeries/GalerieVue';
import { chargerGalerieProches } from '@/lib/galeries-client';

export default function GalerieProchesPage() {
  const { token } = useParams<{ token: string }>();
  const charger = useCallback(() => chargerGalerieProches(token), [token]);
  return <GalerieVue charger={charger} />;
}
