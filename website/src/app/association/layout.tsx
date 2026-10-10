'use client';

import { useEffect, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';

export default function AssociationLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const { id: activeProfileId, loaded: profileLoaded } = useActiveProfileState();
  const router = useRouter();
  const pathname = usePathname();
  const [isAssociation, setIsAssociation] = useState<boolean | null>(null);
  const [nomAsso, setNomAsso] = useState('');

  useEffect(() => {
    if (loading || !profileLoaded) return; // attendre que localStorage soit lu
    if (!user) { router.push('/connexion'); return; }

    Promise.all([
      supabase.from('users_complet').select('is_association, name_elevage, firstname, lastname').eq('uid', user.uid).single(),
      activeProfileId
        ? supabase.from('user_profiles_complet').select('profile_type, nom').eq('id', activeProfileId).single()
        : Promise.resolve({ data: null }),
    ]).then(([{ data }, { data: secProfile }]) => {
      // Accès autorisé si compte primaire association OU profil actif de type association
      const secIsAsso = secProfile && (secProfile as { profile_type: string }).profile_type === 'association';
      if (!data?.is_association && !secIsAsso) {
        setIsAssociation(false);
        return;
      }
      setIsAssociation(true);
      const label = secIsAsso
        ? ((secProfile as { nom?: string }).nom ?? '')
        : '';
      setNomAsso(label || (data as { name_elevage?: string; firstname?: string; lastname?: string } | null)?.name_elevage || `${(data as { firstname?: string } | null)?.firstname ?? ''} ${(data as { lastname?: string } | null)?.lastname ?? ''}`.trim());
    });
  }, [user, loading, router, activeProfileId, profileLoaded]);

  if (loading || !profileLoaded || isAssociation === null) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (isAssociation === false) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-600 mb-4">Accès réservé aux associations.</p>
          <Link href="/" className="text-[#0C5C6C] underline">Retour à l&apos;accueil</Link>
        </div>
      </div>
    );
  }

  // Accueil : même présentation que l'accueil éleveur (identité dans la carte,
  // fond et largeur identiques) — pas de bandeau ni de conteneur propre.
  if (pathname === '/association') return <>{children}</>;

  return (
    <div className="min-h-screen bg-[#F6F7F5]">
      <div className="max-w-6xl mx-auto px-4 py-8">
        <main>{children}</main>
      </div>
    </div>
  );
}
