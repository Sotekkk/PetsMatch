'use client';

import Link from 'next/link';
import { useState, useEffect } from 'react';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import EleveurDashboard from './EleveurDashboard';
import ParticulierDashboard from './ParticulierDashboard';
import ProDashboard from './ProDashboard';

const features = [
  {
    icon: '🐾',
    title: 'Trouver un compagnon',
    desc: "Parcourez les annonces d'éleveurs certifiés pour trouver votre animal idéal.",
    href: '/annonces',
    cta: 'Voir les annonces',
    bg: 'bg-[#EEF5EA]',
    border: 'border-[#6E9E57]/30',
  },
  {
    icon: '🏡',
    title: 'Élevages certifiés',
    desc: 'Découvrez les éleveurs passionnés près de chez vous avec leurs profils complets.',
    href: '/elevages',
    cta: 'Voir les élevages',
    bg: 'bg-[#E8F4F6]',
    border: 'border-[#0C5C6C]/30',
  },
  {
    icon: '🔍',
    title: 'Animaux perdus',
    desc: 'Signalez ou retrouvez un animal perdu grâce à la communauté PetsMatch.',
    href: '/animaux-perdus',
    cta: 'Voir les alertes',
    bg: 'bg-amber-50',
    border: 'border-amber-200',
  },
  {
    icon: '🩺',
    title: 'Services professionnels',
    desc: 'Vétérinaires, éducateurs, pension, toilettage… trouvez le bon professionnel près de chez vous.',
    href: '/services',
    cta: 'Trouver un pro',
    bg: 'bg-[#E3F2FD]',
    border: 'border-[#2196F3]/30',
  },
  {
    icon: '🛍️',
    title: 'Marketplace',
    desc: 'Boutiques, alimentation, artisans… des partenaires sélectionnés pour vos animaux.',
    href: '/marketplace',
    cta: 'Découvrir',
    bg: 'bg-[#F3E5F5]',
    border: 'border-[#8E24AA]/30',
  },
];

function GuestHome() {
  return (
    <>
      <section className="bg-[#0C5C6C] text-white">
        <div className="max-w-6xl mx-auto px-4 py-16 md:py-24 flex flex-col items-center text-center gap-6">
          <h1 className="text-4xl md:text-5xl font-bold leading-tight max-w-2xl">
            Connecter · Prendre soin · Partager
          </h1>
          <p className="text-white/80 text-lg max-w-xl">
            La plateforme dédiée aux passionnés d'animaux. Trouvez votre compagnon, suivez sa santé et rejoignez une communauté bienveillante.
          </p>
          <div className="flex flex-col sm:flex-row gap-3">
            <Link href="/annonces"
              className="bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold px-6 py-3 rounded-full transition-colors text-center">
              Voir les annonces
            </Link>
            <Link href="/inscription"
              className="border border-white/40 hover:bg-white/10 text-white font-medium px-6 py-3 rounded-full transition-colors text-center">
              Créer un compte
            </Link>
          </div>
        </div>
      </section>

      <section className="max-w-6xl mx-auto px-4 py-16">
        <h2 className="text-2xl md:text-3xl font-bold text-center text-[#1F2A2E] mb-2">
          Tout ce dont vous avez besoin
        </h2>
        <p className="text-center text-gray-500 mb-10">
          Des outils pensés pour les amoureux des animaux
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((f) => (
            <div key={f.href} className={`${f.bg} border ${f.border} rounded-2xl p-6 flex flex-col gap-3 hover:shadow-md transition-shadow`}>
              <span className="text-4xl">{f.icon}</span>
              <h3 className="text-lg font-bold text-[#1F2A2E]">{f.title}</h3>
              <p className="text-gray-600 text-sm flex-1">{f.desc}</p>
              <Link href={f.href} className="text-[#0C5C6C] font-semibold text-sm hover:underline">
                {f.cta} →
              </Link>
            </div>
          ))}
        </div>
      </section>

      <section className="bg-[#1F2A2E] text-white py-14">
        <div className="max-w-6xl mx-auto px-4 flex flex-col md:flex-row items-center justify-between gap-6 text-center md:text-left">
          <div>
            <h2 className="text-2xl font-bold mb-2">Disponible sur Android & iOS</h2>
            <p className="text-white/60">Gérez vos animaux, suivez leur santé et chattez avec la communauté depuis votre téléphone.</p>
          </div>
          <div className="flex gap-3">
            <a href="#" className="bg-white/10 hover:bg-white/20 border border-white/20 text-white text-sm font-medium px-5 py-3 rounded-xl transition-colors">
              📱 Google Play
            </a>
            <a href="#" className="bg-white/10 hover:bg-white/20 border border-white/20 text-white text-sm font-medium px-5 py-3 rounded-xl transition-colors">
              🍎 App Store
            </a>
          </div>
        </div>
      </section>
    </>
  );
}

export default function HomeDashboard() {
  const { user, userData, loading } = useAuth();
  const activeProfileId = useActiveProfile();
  const [activeProfile, setActiveProfile] = useState<{
    id: string; profile_type: string; name_elevage: string; avatar_url: string | null; cat_pro: string;
  } | null>(null);
  const [profileLoading, setProfileLoading] = useState(true);

  useEffect(() => {
    if (!activeProfileId) {
      setActiveProfile(null);
      setProfileLoading(false);
      return;
    }
    supabase.from('user_profiles')
      .select('id, profile_type, name_elevage, avatar_url, cat_pro')
      .eq('id', activeProfileId).single()
      .then(({ data }) => {
        setActiveProfile(data as typeof activeProfile);
        setProfileLoading(false);
      });
  }, [activeProfileId]);

  if (loading || profileLoading) {
    return (
      <div className="flex items-center justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (!user) return <GuestHome />;

  if (activeProfile) return <ProDashboard profile={activeProfile} profileId={activeProfileId} />;

  if (userData?.isElevage === true) return <EleveurDashboard />;

  return <ParticulierDashboard />;
}
