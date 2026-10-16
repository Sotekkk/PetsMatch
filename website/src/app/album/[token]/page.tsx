'use client';
// Galerie privée ouverte par lien (album_partage) : le lien ne donne accès
// qu'à cette galerie, tant qu'il est actif et non expiré. Jamais indexée
// (layout : robots noindex ; API : X-Robots-Tag).
import { useCallback } from 'react';
import { useParams } from 'next/navigation';
import GalerieVue from '@/components/galeries/GalerieVue';
import { chargerGalerieParLien } from '@/lib/galeries-client';

export default function AlbumPartagePage() {
  const { token } = useParams<{ token: string }>();
  const charger = useCallback(() => chargerGalerieParLien(token), [token]);
  return <GalerieVue charger={charger} token={token} />;
}
