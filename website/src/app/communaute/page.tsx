'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';

// ── Items communauté ───────────────────────────────────────────────────────────

interface CommunauteItem {
  label: string;
  subtitle: string;
  icon: string;
  color: string;
  href: string;
  authRequired: boolean;
}

const ITEMS: CommunauteItem[] = [
  {
    label: 'Balades canines',
    subtitle: 'Organisez ou rejoignez des balades collectives',
    icon: '🦮',
    color: '#2E7D5E',
    href: '/promenades',
    authRequired: false,
  },
  {
    label: 'Balades ludiques',
    subtitle: 'Chasses au trésor et parcours à défis avec votre animal',
    icon: '🧭',
    color: '#C2410C',
    href: '/balades-ludiques',
    authRequired: false,
  },
  {
    label: 'Forum',
    subtitle: 'Échangez avec la communauté sur tous les sujets',
    icon: '💬',
    color: '#1565C0',
    href: '/communaute/forum',
    authRequired: false,
  },
  {
    label: 'Groupes',
    subtitle: 'Rejoignez des groupes par espèce, race ou région',
    icon: '👥',
    color: '#6A1B9A',
    href: '/communaute/groupes',
    authRequired: false,
  },
  {
    label: 'Lieux Pet-Friendly',
    subtitle: 'Restaurants, hôtels, parcs acceptant les animaux',
    icon: '🗺️',
    color: '#00838F',
    href: '/animal-friendly',
    authRequired: false,
  },
  {
    label: 'Lieux Naturels',
    subtitle: 'Plages, lacs, parcs & forêts accessibles avec vos animaux',
    icon: '🌲',
    color: '#2E7D32',
    href: '/lieux-naturels',
    authRequired: false,
  },
  {
    label: 'PetsFriends',
    subtitle: 'Rencontrez d\'autres propriétaires près de chez vous',
    icon: '🐾',
    color: '#AD1457',
    href: '/petfriends',
    authRequired: true,
  },
];

// ── Page ───────────────────────────────────────────────────────────────────────

export default function CommunautePage() {
  const { user } = useAuth();
  const router = useRouter();

  function handleClick(item: CommunauteItem, e: React.MouseEvent) {
    if (item.authRequired && !user) {
      e.preventDefault();
      router.push('/connexion');
    }
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">

      {/* ── En-tête teal ────────────────────────────────────────────────── */}
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-2xl mx-auto">
          <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
            Communauté
          </h1>
          <p className="text-white/70 text-sm mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            Rejoignez la communauté des passionnés d&apos;animaux
          </p>
        </div>
      </div>

      {/* ── Items ─────────────────────────────────────────────────────────── */}
      <div className="max-w-2xl mx-auto px-4 py-6 flex flex-col gap-3">
        {ITEMS.map((item) => {
          const needsAuth = item.authRequired && !user;
          return (
            <Link
              key={item.label}
              href={item.href}
              onClick={(e) => handleClick(item, e)}
              className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-4 flex items-center gap-4 hover:shadow-md hover:border-gray-200 transition-all"
            >
              {/* Icône */}
              <div
                className="w-12 h-12 flex-shrink-0 rounded-xl flex items-center justify-center text-2xl"
                style={{ backgroundColor: item.color + '18' }}
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
              {/* Badges */}
              <div className="flex items-center gap-2 flex-shrink-0">
                {needsAuth && (
                  <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-gray-100 text-gray-400">
                    Connexion requise
                  </span>
                )}
                <span className="text-gray-300">›</span>
              </div>
            </Link>
          );
        })}

        {/* ── SOS Maltraitance ───────────────────────────────────────────── */}
        <div
          className="rounded-2xl overflow-hidden"
          style={{ border: '1px solid rgba(198,40,40,0.25)', backgroundColor: '#FCE4EC' }}
        >
          {/* En-tête */}
          <div
            className="px-4 py-2.5 flex items-center gap-2"
            style={{ backgroundColor: 'rgba(198,40,40,0.09)' }}
          >
            <span className="text-base">⚠️</span>
            <p className="text-[13px] font-bold" style={{ fontFamily: 'Galey, sans-serif', color: '#C62828' }}>
              Signalement maltraitance animale
            </p>
          </div>

          {/* Numéro 3677 */}
          <div className="px-4 pt-3 pb-2 flex items-center gap-3">
            <div className="flex-1 flex items-center gap-2">
              <span className="text-base">📞</span>
              <span className="text-[18px] font-bold" style={{ fontFamily: 'Galey, sans-serif', color: '#C62828' }}>
                3677
              </span>
              <span className="text-[12px] text-gray-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                — SOS Maltraitance Animale
              </span>
            </div>
            <a
              href="tel:3677"
              className="text-[11px] font-bold text-white px-3 py-1.5 rounded-full flex-shrink-0"
              style={{ backgroundColor: '#C62828', fontFamily: 'Galey, sans-serif' }}
            >
              Appeler
            </a>
          </div>

          {/* Lien formulaire */}
          <div className="px-4 pb-3">
            <a
              href="https://3677.fr/formulaire-de-signalement"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[12px] font-semibold flex items-center gap-1.5"
              style={{ fontFamily: 'Galey, sans-serif', color: '#0C5C6C', textDecoration: 'underline' }}
            >
              <span className="text-[11px]">↗</span>
              Formulaire de signalement en ligne
            </a>
          </div>
        </div>

      </div>

    </div>
  );
}
