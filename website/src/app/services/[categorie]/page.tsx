'use client';

import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';

// ── Sous-catégories par slug ───────────────────────────────────────────────────

interface SubItem {
  /** Clé de métier de la recherche (src/lib/annuaire-filtres.ts) */
  metier: string;
  label: string;
  subtitle: string;
  icon: string;
  catValues: string; // query param `cat` pour /services/carte
  profValues?: string; // query param `prof` pour /services/carte (filtre profession_pro)
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
    allCatValues: 'sante,veterinaire,marechal_ferrant',
    items: [
      { metier: 'veterinaire', label: 'Vétérinaires',      subtitle: 'Consultations, urgences, chirurgie',              icon: '🩺', catValues: 'veterinaire' },
      { metier: 'osteopathe', label: 'Ostéopathes',       subtitle: 'Manipulations ostéopathiques pour animaux',       icon: '🖐️', catValues: 'sante', profValues: 'Ostéopathe' },
      { metier: 'kine', label: 'Kinésithérapeutes', subtitle: 'Rééducation fonctionnelle animale',               icon: '💪', catValues: 'sante', profValues: 'Kinésithérapeute' },
      { metier: 'marechal', label: 'Maréchal-ferrant',  subtitle: 'Soins des sabots et ferrure',                    icon: '🔨', catValues: 'marechal_ferrant,sante', profValues: 'Maréchal-ferrant,Maréchal-ferrant traditionnel,Parage naturel' },
    ],
  },
  education: {
    title: 'Éducation & comportement',
    icon: '🎓',
    color: '#E65100',
    allCatValues: 'education',
    items: [
      { metier: 'educateur', label: 'Éducateurs',           subtitle: 'Apprentissage, obéissance et socialisation',         icon: '🎓', catValues: 'education', profValues: 'Éducateur canin,Dresseur' },
      { metier: 'comportementaliste', label: 'Comportementalistes',  subtitle: 'Troubles du comportement, anxiété, agressivité',     icon: '🧠', catValues: 'education', profValues: 'Comportementaliste' },
    ],
  },
  garde: {
    title: 'Garde & hébergement',
    icon: '🏠',
    color: '#F57C00',
    allCatValues: 'garde,pension',
    items: [
      { metier: 'petsitter', label: 'Pet-sitters',  subtitle: 'Garde à domicile chez vous ou chez eux',   icon: '🏠', catValues: 'garde', profValues: 'Pet sitter' },
      { metier: 'promeneur', label: 'Promeneurs',   subtitle: 'Sorties quotidiennes et balades',           icon: '🦮', catValues: 'garde', profValues: 'Promeneur de chiens' },
      { metier: 'pension', label: 'Pensions',     subtitle: 'Hébergement gardé en établissement',       icon: '🏡', catValues: 'pension' },
    ],
  },
  transport: {
    title: 'Transport',
    icon: '🚗',
    color: '#00838F',
    allCatValues: 'taxi_animalier',
    items: [
      { metier: 'taxi', label: 'Taxi animalier', subtitle: 'Transport spécialisé pour vos animaux', icon: '🚕', catValues: 'taxi_animalier' },
    ],
  },
  // Alimentation + Boutiques & Créateurs fusionnées (même liste `referencement`)
  boutiques: {
    title: 'Alimentation & Boutiques',
    icon: '🛍️',
    color: '#6A1B9A',
    allCatValues: 'referencement',
    items: [
      { metier: 'boutiques', label: 'Animaleries, boutiques & créateurs', subtitle: 'Alimentation, accessoires et créations — boutiques vérifiées', icon: '🏪', catValues: 'referencement' },
    ],
  },
};

// ── Page ───────────────────────────────────────────────────────────────────────

export default function SousCategoriesPage() {
  const { categorie } = useParams<{ categorie: string }>();
  const router = useRouter();
  // Anciens liens /services/alimentation → tuile fusionnée
  const cat = CATEGORIES[categorie === 'alimentation' ? 'boutiques' : categorie];

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
            href={`/services/carte?metier=${item.metier}`}
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

        {/* ── Bannière urgences vétérinaires (Santé uniquement) ─────────── */}
        {categorie === 'sante' && (
          <div
            className="rounded-2xl overflow-hidden"
            style={{ border: '1px solid rgba(230,81,0,0.25)', backgroundColor: '#FFF3E0' }}
          >
            <div className="px-4 py-2.5 flex items-center gap-2" style={{ backgroundColor: 'rgba(230,81,0,0.09)' }}>
              <span className="text-base">🚨</span>
              <p className="text-[13px] font-bold" style={{ fontFamily: 'Galey, sans-serif', color: '#E65100' }}>
                Urgences vétérinaires 24h/24
              </p>
            </div>
            <div className="px-4 pt-3 pb-2 flex items-center gap-3">
              <div className="flex-1 flex items-center gap-2">
                <span className="text-base">📞</span>
                <span className="text-[18px] font-bold" style={{ fontFamily: 'Galey, sans-serif', color: '#E65100' }}>3115</span>
                <span className="text-[12px] text-gray-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                  — Vétérinaire de garde national
                </span>
              </div>
              <a
                href="tel:3115"
                className="text-[11px] font-bold text-white px-3 py-1.5 rounded-full flex-shrink-0"
                style={{ backgroundColor: '#E65100', fontFamily: 'Galey, sans-serif' }}
              >
                Appeler
              </a>
            </div>
            <div className="px-4 pb-3">
              <a
                href="https://www.veterinaire-de-garde-paris.fr"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[12px] font-semibold flex items-center gap-1.5"
                style={{ fontFamily: 'Galey, sans-serif', color: '#0C5C6C', textDecoration: 'underline' }}
              >
                <span className="text-[11px]">↗</span>
                Vétérinaire de garde Paris
              </a>
            </div>
          </div>
        )}

      </div>
    </div>
  );
}
