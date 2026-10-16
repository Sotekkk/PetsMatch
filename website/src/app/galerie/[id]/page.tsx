'use client';
// Galerie privée du client connecté (galerie partagée sur son compte) ou
// aperçu par le photographe. Contrôle d'accès côté serveur (/api/galeries/[id]).
import { useCallback } from 'react';
import { useParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import GalerieVue from '@/components/galeries/GalerieVue';
import { chargerGalerie } from '@/lib/galeries-client';

export default function GaleriePage() {
  const { id } = useParams<{ id: string }>();
  const { user, loading } = useAuth();
  const charger = useCallback(() => chargerGalerie(id), [id]);
  if (loading) return null;
  if (!user) return <p className="text-center py-24 text-sm text-gray-500">Connectez-vous pour voir cette galerie.</p>;
  return <GalerieVue charger={charger} />;
}
