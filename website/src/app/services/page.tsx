'use client';

import Link from 'next/link';

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

// ── Données ────────────────────────────────────────────────────────────────────

const SECTIONS: ServiceSection[] = [
  {
    id: 'sante',
    title: 'Santé & Bien-être',
    icon: '🏥',
    color: '#0C5C6C',
    colorLight: '#E0F2FE',
    items: [
      { id: 'vet',       label: 'Vétérinaires',           icon: '🩺', href: '/services/veterinaires' },
      { id: 'urgence',   label: 'Urgences vétérinaires',  icon: '🚨', href: '/services/urgences' },
      { id: 'educ',      label: 'Éducateurs / Behaviouriste', icon: '🎓', href: '/services/educateurs' },
      { id: 'petsit',    label: 'Pet sitter',             icon: '🏠', href: '/services/pet-sitters' },
      { id: 'pension',   label: 'Pension animaux',        icon: '🏡', href: '/services/pensions' },
    ],
  },
  {
    id: 'soins',
    title: 'Soins & Beauté',
    icon: '✂️',
    color: '#7C3AED',
    colorLight: '#F5F3FF',
    items: [
      { id: 'toiletteur', label: 'Toiletteurs',             icon: '✂️', soon: true },
      { id: 'pharmacie',  label: 'Pharmacies vétérinaires', icon: '💊', soon: true },
      { id: 'labo',       label: 'Laboratoires',            icon: '🔬', soon: true },
      { id: 'spec',       label: 'Spécialistes',            icon: '🏆', soon: true },
    ],
  },
  {
    id: 'friendly',
    title: 'Animal Friendly',
    icon: '🐾',
    color: '#16A34A',
    colorLight: '#F0FDF4',
    items: [
      { id: 'hotels',      label: 'Hôtels & Hébergements', icon: '🏨', soon: true },
      { id: 'restau',      label: 'Restaurants',           icon: '🍽️', soon: true },
      { id: 'plages',      label: 'Plages & Baignades',    icon: '🏖️', soon: true },
      { id: 'parcs',       label: 'Parcs & Espaces verts', icon: '🌳', soon: true },
    ],
  },
  {
    id: 'communaute',
    title: 'Communauté',
    icon: '👥',
    color: '#EA580C',
    colorLight: '#FFF7ED',
    items: [
      { id: 'evenements',  label: 'Événements',            icon: '📅', soon: true },
      { id: 'promenades',  label: 'Promenades collectives',icon: '🦮', soon: true },
      { id: 'forum',       label: 'Forum communauté',      icon: '💬', soon: true },
      { id: 'groupes',     label: 'Groupes',               icon: '👥', soon: true },
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
