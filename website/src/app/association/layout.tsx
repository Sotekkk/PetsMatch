'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';

export default function AssociationLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const { id: activeProfileId, loaded: profileLoaded } = useActiveProfileState();
  const router = useRouter();
  const [isAssociation, setIsAssociation] = useState<boolean | null>(null);
  const [nomAsso, setNomAsso] = useState('');

  useEffect(() => {
    if (loading || !profileLoaded) return; // attendre que localStorage soit lu
    if (!user) { router.push('/connexion'); return; }

    Promise.all([
      supabase.from('users').select('is_association, name_elevage, firstname, lastname').eq('uid', user.uid).single(),
      activeProfileId
        ? supabase.from('user_profiles').select('profile_type, nom').eq('id', activeProfileId).single()
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
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
      </div>
    );
  }

  if (isAssociation === false) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-600 mb-4">Accès réservé aux associations.</p>
          <Link href="/" className="text-teal-700 underline">Retour à l&apos;accueil</Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-gradient-to-r from-teal-800 to-green-600 text-white shadow-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex items-center gap-3">
          <span className="text-2xl">🐾</span>
          <div>
            <p className="text-xs text-white/70 leading-none">Espace Association</p>
            <p className="font-bold font-galey text-lg leading-tight">{nomAsso || 'Mon Association'}</p>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <main>{children}</main>
      </div>
    </div>
  );
}
