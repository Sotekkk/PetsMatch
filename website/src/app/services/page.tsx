'use client';

import { Suspense } from 'react';
import AnnuaireRecherche from '@/components/annuaire/AnnuaireRecherche';

// Annuaire des professionnels — même page pour tous les profils (lien
// « Annuaire » du menu). Toute la logique : AnnuaireRecherche.
export default function ServicesPage() {
  return (
    <Suspense>
      <AnnuaireRecherche />
    </Suspense>
  );
}
