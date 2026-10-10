'use client';
// Point d'entrée unique « Publier une annonce » : l'utilisateur choisit le
// type, puis le formulaire existant correspondant s'ouvre (règles, champs et
// autorisations propres à chaque type inchangés).

import Link from 'next/link';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { useTypeProfilActif } from '@/hooks/useTypeProfilActif';
import { droitsAnnonces } from '@/lib/annonces-droits';
import { Icone, BORDURE, OMBRE } from '@/components/dashboard/kit';

export default function PublierAnnoncePage() {
  const router = useRouter();
  const { user, loading } = useAuth();
  const { type, pret } = useTypeProfilActif();
  const droits = droitsAnnonces(type);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  if (loading || !user || !pret) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  const carte = `group bg-white rounded-2xl p-5 flex items-start gap-4 text-left transition-shadow ${OMBRE}`;

  return (
    <div className="bg-[#F6F7F5] min-h-[70vh]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-2xl mx-auto px-4 py-8">
        <Link href={droits.mesAnnonces} className="text-sm text-[#0C5C6C] hover:underline">← Mes annonces</Link>
        <h1 className="text-2xl font-bold text-[#1E2025] mt-2">Publier une annonce</h1>
        <p className="text-sm text-gray-600 mb-6">Que souhaitez-vous publier ?</p>

        <div className="grid gap-3">
          {droits.animaux ? (
            <Link href={droits.animaux.creer} className={`${carte} hover:shadow-md`} style={{ border: `1px solid ${BORDURE}` }}>
              <span className="w-11 h-11 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center flex-shrink-0"><Icone nom="patte" /></span>
              <span className="flex-1 min-w-0">
                <span className="block font-bold text-[#1E2025]">Animal</span>
                <span className="block text-sm text-gray-600 mt-0.5">{droits.animaux.detail}</span>
              </span>
              <Icone nom="fleche" taille={18} className="text-gray-400 self-center" />
            </Link>
          ) : (
            <div className={`${carte} opacity-70`} style={{ border: `1px solid ${BORDURE}` }} aria-disabled>
              <span className="w-11 h-11 rounded-full bg-gray-100 text-gray-400 flex items-center justify-center flex-shrink-0"><Icone nom="patte" /></span>
              <span className="flex-1 min-w-0">
                <span className="block font-bold text-gray-500">Animal</span>
                <span className="block text-sm text-gray-500 mt-0.5">Non disponible pour ce profil : les annonces d’animaux sont réservées aux éleveurs, aux associations et aux particuliers (cheval).</span>
              </span>
            </div>
          )}

          <Link href="/annonces/creer-objet" className={`${carte} hover:shadow-md`} style={{ border: `1px solid ${BORDURE}` }}>
            <span className="w-11 h-11 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center flex-shrink-0"><Icone nom="caisse" /></span>
            <span className="flex-1 min-w-0">
              <span className="block font-bold text-[#1E2025]">Matériel & équipements</span>
              <span className="block text-sm text-gray-600 mt-0.5">Paniers, grilles de chenil, parcs, caisses de transport, équipements de mise bas… Jamais d’animal.</span>
            </span>
            <Icone nom="fleche" taille={18} className="text-gray-400 self-center" />
          </Link>
        </div>
      </div>
    </div>
  );
}
