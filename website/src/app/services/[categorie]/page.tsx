'use client';

import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';

// ── Sous-catégories par slug ───────────────────────────────────────────────────

interface SubItem {
  label: string;
  subtitle: string;
  icon: string;
  catValues: string; // query param pour /services/carte
}

interface CategoryDef {
  title: string;
  icon: string;
  color: string;
  allCatValues: string;
  items: SubItem[];
}

const CATEGORIES: Record<string, CategoryDef> = {
  sante: {
    title: 'Santé & bien-être',
    icon: '🏥',
    color: '#2E7D5E',
    allCatValues: 'sante,veterinaire,osteo,kine,marechal_ferrant,dentiste_equin',
    items: [
      { label: 'Vétérinaires',      subtitle: 'Consultations, urgences, chirurgie',              icon: '🩺', catValues: 'veterinaire,sante' },
      { label: 'Ostéopathes',       subtitle: 'Manipulations ostéopathiques pour animaux',       icon: '🖐️', catValues: 'osteo,sante' },
      { label: 'Kinésithérapeutes', subtitle: 'Rééducation fonctionnelle animale',               icon: '💪', catValues: 'kine,sante' },
      { label: 'Maréchal-ferrant',  subtitle: 'Soins des sabots et ferrure',                    icon: '🔨', catValues: 'marechal_ferrant' },
      { label: 'Dentiste équin',    subtitle: 'Soins dentaires pour chevaux',                   icon: '🦷', catValues: 'dentiste_equin,sante' },
    ],
  },
  education: {
    title: 'Éducation & comportement',
    icon: '🎓',
    color: '#E65100',
    allCatValues: 'education,educateur,comportementaliste',
    items: [
      { label: 'Éducateurs',           subtitle: 'Apprentissage, obéissance et socialisation',         icon: '🎓', catValues: 'education,educateur' },
      { label: 'Comportementalistes',  subtitle: 'Troubles du comportement, anxiété, agressivité',     icon: '🧠', catValues: 'comportementaliste' },
    ],
  },
  garde: {
    title: 'Garde & hébergement',
    icon: '🏠',
    color: '#F57C00',
    allCatValues: 'garde,pet_sitter,promeneur,pension',
    items: [
      { label: 'Pet-sitters',  subtitle: 'Garde à domicile chez vous ou chez eux',   icon: '🏠', catValues: 'pet_sitter,garde' },
      { label: 'Promeneurs',   subtitle: 'Sorties quotidiennes et balades',           icon: '🦮', catValues: 'promeneur' },
      { label: 'Pensions',     subtitle: 'Hébergement gardé en établissement',       icon: '🏡', catValues: 'pension' },
    ],
  },
  alimentation: {
    title: 'Alimentation',
    icon: '🥩',
    color: '#1565C0',
    allCatValues: 'alimentation,animalerie,nutrition,nutritionniste',
    items: [
      { label: 'Animaleries',              subtitle: 'Magasins spécialisés alimentation & accessoires', icon: '🏪', catValues: 'animalerie,alimentation' },
      { label: 'Nutritionnistes animaliers', subtitle: 'Conseils en alimentation adaptée & régimes',    icon: '🥗', catValues: 'nutrition,nutritionniste' },
    ],
  },
  transport: {
    title: 'Transport',
    icon: '🚗',
    color: '#00838F',
    allCatValues: 'transport,taxi_animalier,vtc,ambulance_vet',
    items: [
      { label: 'Taxi animalier',              subtitle: 'Transport spécialisé pour vos animaux',          icon: '🚕', catValues: 'taxi_animalier,transport' },
      { label: 'VTC & Taxi avec animaux',     subtitle: 'Chauffeurs qui acceptent vos compagnons',        icon: '🚗', catValues: 'transport,vtc' },
      { label: 'Ambulance vétérinaire',       subtitle: 'Transport médicalisé pour urgences',             icon: '🚑', catValues: 'ambulance_vet,transport' },
    ],
  },
  boutiques: {
    title: 'Boutiques & Créateurs',
    icon: '🛍️',
    color: '#6A1B9A',
    allCatValues: 'boutique,artisan,createur',
    items: [
      { label: 'Boutiques spécialisées', subtitle: 'Petites boutiques professionnelles vérifiées', icon: '🛍️', catValues: 'boutique' },
      { label: 'Créateurs & artisans',   subtitle: 'Accessoires faits main, personnalisation',    icon: '🎨', catValues: 'artisan,createur' },
    ],
  },
};

// ── Page ───────────────────────────────────────────────────────────────────────

export default function SousCategoriesPage() {
  const { categorie } = useParams<{ categorie: string }>();
  const router = useRouter();
  const cat = CATEGORIES[categorie];

  if (!cat) {
    router.replace('/services');
    return null;
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">

      {/* ── En-tête coloré ────────────────────────────────────────────────── */}
      <div className="text-white px-4 py-5" style={{ backgroundColor: cat.color }}>
        <div className="max-w-2xl mx-auto flex items-center gap-3">
          <button
            onClick={() => router.back()}
            className="w-8 h-8 flex items-center justify-center rounded-full bg-white/20 text-white text-sm"
          >
            ‹
          </button>
          <div className="flex items-center gap-2">
            <span className="text-2xl">{cat.icon}</span>
            <h1 className="text-[17px] font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
              {cat.title}
            </h1>
          </div>
        </div>
      </div>

      {/* ── Liste sous-catégories ─────────────────────────────────────────── */}
      <div className="max-w-2xl mx-auto px-4 py-5 flex flex-col gap-3">
        {cat.items.map((item) => (
          <Link
            key={item.label}
            href={`/services/carte?cat=${encodeURIComponent(item.catValues)}&view=list`}
            className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-4 flex items-center gap-4 hover:shadow-md hover:border-gray-200 transition-all"
          >
            {/* Icône */}
            <div
              className="w-12 h-12 flex-shrink-0 rounded-xl flex items-center justify-center text-2xl"
              style={{ backgroundColor: cat.color + '18' }}
            >
              {item.icon}
            </div>
            {/* Texte */}
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
                {item.label}
              </p>
              <p className="text-[12px] text-gray-400 mt-0.5" style={{ fontFamily: 'Galey, sans-serif' }}>
                {item.subtitle}
              </p>
            </div>
            <span className="text-gray-300 text-sm">›</span>
          </Link>
        ))}

        {/* ── Voir tous ──────────────────────────────────────────────────── */}
        <Link
          href={`/services/carte?cat=${encodeURIComponent(cat.allCatValues)}&view=list`}
          className="rounded-2xl px-4 py-4 flex items-center justify-center gap-2 hover:opacity-90 transition-opacity"
          style={{
            backgroundColor: cat.color + '12',
            border: `1px solid ${cat.color}33`,
          }}
        >
          <span className="text-lg">📋</span>
          <span
            className="text-[14px] font-semibold"
            style={{ fontFamily: 'Galey, sans-serif', color: cat.color }}
          >
            Voir tous les professionnels
          </span>
        </Link>
      </div>
    </div>
  );
}
