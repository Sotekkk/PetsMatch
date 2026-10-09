'use client';

// Fonction vétérinaire réservée à une formule (Avancé / Clinique) : affiche le
// contenu si la formule active du cabinet l'inclut, sinon un encart vers les
// formules. Miroir appli : verrous du menu (eleveur_nav.dart) et du planning
// (pro_agenda.dart). La base reste le vrai contrôle (ex. ajout d'employés).

import Link from 'next/link';
import { useProfessionPlanCode, vetFormuleOk, VET_FORMULE_LABEL } from '@/lib/use-plan';

export default function FormuleVetRequise({ requise, fonction, children }: {
  requise: 'avance' | 'clinique'; fonction: string; children: React.ReactNode;
}) {
  const { planCode, loading } = useProfessionPlanCode('veterinaire');
  if (loading) return (
    <div className="flex justify-center items-center min-h-[40vh]">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );
  if (vetFormuleOk(planCode, requise)) return <>{children}</>;
  return (
    <div className="max-w-lg mx-auto px-4 py-16 text-center" style={{ fontFamily: 'Galey, sans-serif' }}>
      <p className="text-xs font-bold uppercase tracking-wider text-[#D97706]">Formule {VET_FORMULE_LABEL[requise]}</p>
      <h1 className="text-xl font-bold text-[#1F2A2E] mt-1">{fonction}</h1>
      <p className="text-sm text-gray-500 mt-2">
        Cette fonctionnalité est incluse dans la formule {VET_FORMULE_LABEL[requise]}
        {requise === 'avance' ? ' et Clinique' : ''}.
      </p>
      <Link href="/veterinaire/abonnement" className="inline-block mt-5 px-5 py-2.5 rounded-xl text-sm font-semibold text-white bg-[#0C5C6C]">
        Voir les formules
      </Link>
    </div>
  );
}
