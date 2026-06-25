'use client';

import { useEffect, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';

const NAV_ITEMS = [
  { href: '/association',                            label: 'Tableau de bord',    icon: '🏠', exact: true },
  { href: '/association/animaux',                    label: 'Mes Animaux',        icon: '🐾' },
  { href: '/association/familles-accueil',           label: 'Familles d\'accueil',icon: '🏡' },
  { href: '/association/chenil',                     label: 'Chenil / Planning',  icon: '🗓️' },
  { href: '/association/planning',                   label: 'Protocoles',         icon: '📅' },
  { href: '/association/registre-sanitaire',         label: 'Suivi sanitaire',    icon: '🏥' },
  { href: '/association/inventaire',                 label: 'Inventaire',         icon: '📦' },
  { href: '/association/equipe',                      label: 'Équipe',             icon: '👥' },
  { href: '/association/registre-entree-sortie',     label: 'Entrées / Sorties',  icon: '📂' },
  { href: '/association/agenda',                     label: 'Agenda',             icon: '🗓️' },
  { href: '/mes-rdv',                               label: 'Mes RDV',            icon: '📅' },
  { href: '/association/annonces',                   label: 'Mes Annonces',       icon: '📣' },
  { href: '/adoptions',                               label: 'Fil d\'adoption',    icon: '💚' },
  { href: '/association/contrat',                    label: 'Contrats adoption',  icon: '📋' },
  { href: '/association/certificat-engagement',      label: 'Certificats',        icon: '✍️' },
  { href: '/association/facturation',                label: 'Facturation',        icon: '🧾' },
];

export default function AssociationLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const { id: activeProfileId, loaded: profileLoaded } = useActiveProfileState();
  const router = useRouter();
  const pathname = usePathname();
  const [isAssociation, setIsAssociation] = useState<boolean | null>(null);
  const [nomAsso, setNomAsso] = useState('');
  const [menuOpen, setMenuOpen] = useState(false);

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

  const isActive = (href: string, exact?: boolean) =>
    exact ? pathname === href : pathname === href || pathname.startsWith(href + '/');

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-gradient-to-r from-teal-800 to-green-600 text-white shadow-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="text-2xl">🐾</span>
            <div>
              <p className="text-xs text-white/70 leading-none">Espace Association</p>
              <p className="font-bold font-galey text-lg leading-tight">{nomAsso || 'Mon Association'}</p>
            </div>
          </div>
          {/* Mobile menu toggle */}
          <button className="md:hidden" onClick={() => setMenuOpen(!menuOpen)}>
            <span className="material-icons">{menuOpen ? '✕' : '☰'}</span>
          </button>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 flex gap-6">
        {/* Sidebar */}
        <aside className={`${menuOpen ? 'block' : 'hidden'} md:block w-full md:w-56 flex-shrink-0`}>
          <nav className="bg-white rounded-2xl shadow-sm p-3 sticky top-6">
            <p className="text-xs font-bold text-gray-400 uppercase tracking-wider px-3 py-2">Navigation</p>
            {NAV_ITEMS.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setMenuOpen(false)}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-galey transition-all mb-0.5 ${
                  isActive(item.href, item.exact)
                    ? 'bg-teal-50 text-teal-800 font-semibold'
                    : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900'
                }`}
              >
                <span>{item.icon}</span>
                <span>{item.label}</span>
              </Link>
            ))}
          </nav>
        </aside>

        {/* Main content */}
        <main className="flex-1 min-w-0">{children}</main>
      </div>
    </div>
  );
}
