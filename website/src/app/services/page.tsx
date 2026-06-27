'use client';

import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface ServiceSection {
  id: string;
  title: string;
  icon: string;
  color: string;
  colorLight: string;
  items: ServiceItem[];
}

interface ServiceItem {
  id: string;
  label: string;
  icon: string;
  href?: string;
  soon?: boolean;
}

// ── Données statiques ──────────────────────────────────────────────────────────

const SECTIONS_BASE: ServiceSection[] = [
  {
    id: 'pole-sante',
    title: 'Pôle Santé',
    icon: '🏥',
    color: '#6E9E57',
    colorLight: '#E8F5E9',
    items: [
      { id: 'vet',      label: 'Vétérinaires',          icon: '🩺', href: '/services/carte?cat=veterinaire&view=list' },
      { id: 'urgence',  label: 'Urgences vétérinaires', icon: '🚨', href: '/services/carte?cat=veterinaire&view=list' },
      { id: 'osteo',    label: 'Ostéopathes',           icon: '🖐️', href: '/services/carte?cat=sante&view=list' },
      { id: 'kine',     label: 'Kinésithérapeutes',     icon: '💪', href: '/services/carte?cat=sante&view=list' },
      { id: 'naturo',   label: 'Naturopathes',          icon: '🌿', href: '/services/carte?cat=sante&view=list' },
      { id: 'assurance',label: 'Assurances animaux',    icon: '🛡️', soon: true },
    ],
  },
  {
    id: 'education-garde',
    title: 'Éducation & Garde',
    icon: '🎓',
    color: '#EF6C00',
    colorLight: '#FFF3E0',
    items: [
      { id: 'educ',    label: 'Éducateurs / Comportementalistes', icon: '🎓', href: '/services/carte?cat=education&view=list' },
      { id: 'petsit',  label: 'Pet sitter / Promeneurs',         icon: '🏠', href: '/services/carte?cat=garde&view=list' },
      { id: 'pension', label: 'Pension pour animaux',            icon: '🏡', href: '/services/carte?cat=garde&view=list' },
    ],
  },
  {
    id: 'sorties',
    title: 'Sorties & Voyages',
    icon: '🧭',
    color: '#1E88E5',
    colorLight: '#E3F2FD',
    items: [
      { id: 'all',        label: 'Tous les lieux',         icon: '🗺️', href: '/animal-friendly' },
      { id: 'hotels',     label: 'Hôtels & Hébergements', icon: '🏨', href: '/animal-friendly' },
      { id: 'restau',     label: 'Restaurants & Cafés',   icon: '🍽️', href: '/animal-friendly' },
      { id: 'parcs',      label: 'Parcs & Espaces verts', icon: '🌳', href: '/animal-friendly' },
      { id: 'evenements', label: 'Événements',            icon: '📅', soon: true },
      { id: 'promenades', label: 'Promenades collectives',icon: '🦮', href: '/promenades' },
    ],
  },
  {
    id: 'marketplace',
    title: 'Marketplace',
    icon: '🛍️',
    color: '#8E24AA',
    colorLight: '#F3E5F5',
    items: [
      { id: 'boutiques', label: 'Boutiques & Accessoires', icon: '🏪', href: '/services/carte?cat=referencement&view=list' },
      { id: 'petfood',   label: 'Petfood & Alimentation',  icon: '🥩', href: '/services/carte?cat=referencement&view=list' },
      { id: 'createurs', label: 'Créateurs pour animaux',  icon: '🎨', href: '/services/carte?cat=referencement&view=list' },
      { id: 'promos',    label: 'Bons plans & Promos',     icon: '🏷️', soon: true },
    ],
  },
];

// ── Composants ─────────────────────────────────────────────────────────────────

function ServiceCard({ item, color }: { item: ServiceItem; color: string }) {
  const content = (
    <div className="flex items-center gap-3 px-4 py-3.5 bg-white rounded-xl border border-gray-100 hover:border-gray-200 hover:shadow-sm transition-all group cursor-pointer">
      <span className="text-2xl w-8 flex-shrink-0 text-center">{item.icon}</span>
      <span className="text-sm font-medium text-gray-800 flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>
        {item.label}
      </span>
      {item.soon ? (
        <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-gray-100 text-gray-400 flex-shrink-0">
          Bientôt
        </span>
      ) : (
        <svg className="w-4 h-4 text-gray-400 group-hover:translate-x-0.5 transition-transform flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
        </svg>
      )}
    </div>
  );

  if (item.href && !item.soon) {
    return <Link href={item.href}>{content}</Link>;
  }
  return <div onClick={item.soon ? undefined : undefined}>{content}</div>;
}

function SectionBlock({ section }: { section: ServiceSection }) {
  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
      {/* Header */}
      <div className="px-5 py-4 flex items-center gap-3" style={{ backgroundColor: section.colorLight }}>
        <span className="text-2xl">{section.icon}</span>
        <h2 className="font-bold text-base" style={{ fontFamily: 'Galey, sans-serif', color: section.color }}>
          {section.title}
        </h2>
      </div>
      {/* Items */}
      <div className="p-4 flex flex-col gap-2">
        {section.items.map((item) => (
          <ServiceCard key={item.id} item={item} color={section.color} />
        ))}
      </div>
    </div>
  );
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function ServicesPage() {
  const { userData } = useAuth();
  const isParticulier = userData?.profileType === 'particulier' || (!userData?.profileType && !userData?.isElevage && !userData?.isAssociation && !userData?.isPro);

  const communauteSection: ServiceSection = {
    id: 'communaute',
    title: 'Communauté',
    icon: '👥',
    color: '#00ACC1',
    colorLight: '#E0F7FA',
    items: [
      ...(isParticulier ? [{ id: 'petsfriends', label: 'PetsFriends', icon: '🐾', href: '/petfriends' }] : []),
      { id: 'forum',      label: 'Forum communauté',  icon: '💬', href: '/communaute/forum' },
      { id: 'groupes',    label: 'Groupes',           icon: '👥', href: '/communaute/groupes' },
      { id: 'evenements', label: 'Événements locaux', icon: '📅', soon: true },
    ],
  };

  const SECTIONS = [...SECTIONS_BASE, communauteSection];

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Hero */}
      <div className="bg-[#0C5C6C] text-white px-4 py-10">
        <div className="max-w-2xl mx-auto text-center">
          <p className="text-4xl mb-3">🐾</p>
          <h1 className="text-2xl font-bold mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Services pour vos animaux
          </h1>
          <p className="text-white/70 text-sm">
            Trouvez vétérinaires, éducateurs, pet sitters et bien plus près de chez vous.
          </p>
        </div>
      </div>

      {/* Accès carte */}
      <div className="max-w-3xl mx-auto px-4 pt-6 pb-0">
        <Link href="/services/carte"
          className="flex items-center gap-3 bg-white rounded-xl border border-[#0C5C6C]/20 px-5 py-3.5 hover:shadow-md transition-shadow group">
          <span className="text-2xl">🗺️</span>
          <div className="flex-1">
            <p className="font-bold text-sm text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>Carte des professionnels</p>
            <p className="text-xs text-gray-400">Vétérinaires, éducateurs, garderies… près de chez vous</p>
          </div>
          <svg className="w-4 h-4 text-gray-400 group-hover:translate-x-0.5 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
          </svg>
        </Link>
      </div>

      {/* Grid sections */}
      <div className="max-w-3xl mx-auto px-4 py-8 grid grid-cols-1 md:grid-cols-2 gap-6">
        {SECTIONS.map((section) => (
          <SectionBlock key={section.id} section={section} />
        ))}
      </div>

      {/* Footer note */}
      <div className="max-w-3xl mx-auto px-4 pb-12">
        <div className="bg-[#E0F2FE] rounded-xl px-5 py-4 flex items-start gap-3">
          <span className="text-lg flex-shrink-0">ℹ️</span>
          <p className="text-sm text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Vous êtes un professionnel ? Créez votre profil pro dans les paramètres de l&apos;application pour apparaître dans l&apos;annuaire.
          </p>
        </div>
      </div>
    </div>
  );
}
