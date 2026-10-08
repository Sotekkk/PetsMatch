'use client';

import { Suspense, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';

// Ancienne page de résultats : la recherche est désormais sur /services
// (mêmes paramètres, y compris les anciens ?cat=&prof= / ?metier=).
function Redirection() {
  const router = useRouter();
  const sp = useSearchParams();
  useEffect(() => {
    const qs = sp.toString();
    router.replace(qs ? `/services?${qs}` : '/services');
  }, [router, sp]);
  return null;
}

export default function ServicesCarteRedirect() {
  return <Suspense><Redirection /></Suspense>;
}
