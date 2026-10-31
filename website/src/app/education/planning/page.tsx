'use client';

// Le planning des cours est maintenant l'onglet « Agenda » de Gérer mes RDV :
// l'ancienne adresse y renvoie (liens des notifications ?coursId=… compris).

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

export default function EducationPlanningPage() {
  const router = useRouter();
  useEffect(() => {
    const coursId = new URLSearchParams(window.location.search).get('coursId');
    router.replace(`/mes-rdv?onglet=agenda${coursId ? `&coursId=${encodeURIComponent(coursId)}` : ''}`);
  }, [router]);
  return null;
}
