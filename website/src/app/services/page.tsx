'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';

// ── Types ──────────────────────────────────────────────────────────────────────

interface AnnuaireCategory {
  slug: string;
  label: string;
  icon: string;
  color: string;
  catValues?: string;
  hasSubcats: boolean;
}

interface VerifiedPro {
  id: string;
  uid: string;
  nom: string;
  profile_type: string;
  avatar_url?: string;
  ville_pro?: string;
  accept_new_clients?: boolean;
}

// ── Données statiques ──────────────────────────────────────────────────────────

const CATEGORIES: AnnuaireCategory[] = [
  { slug: 'sante',        label: 'Santé\n& bien-être',         icon: '🏥', color: '#2E7D5E', hasSubcats: true },
  { slug: 'education',    label: 'Éducation\n& comportement',  icon: '🎓', color: '#E65100', hasSubcats: true },
  { slug: 'garde',        label: 'Garde\n& hébergement',       icon: '🏠', color: '#F57C00', hasSubcats: true },
  { slug: 'toilettage',   label: 'Toilettage\n& soins',        icon: '✂️', color: '#C62828', catValues: 'toilettage', hasSubcats: false },
  { slug: 'alimentation', label: 'Alimentation',               icon: '🥩', color: '#1565C0', hasSubcats: true },
  { slug: 'transport',    label: 'Transport',                  icon: '🚗', color: '#00838F', hasSubcats: true },
  { slug: 'photographes', label: 'Photographes',               icon: '📷', color: '#AD1457', catValues: 'photographe', hasSubcats: false },
  { slug: 'boutiques',    label: 'Boutiques\n& Créateurs',     icon: '🛍️', color: '#6A1B9A', hasSubcats: true },
  { slug: 'assurances',   label: 'Assurances\n& juridique',    icon: '🛡️', color: '#1E3A5F', catValues: 'assurance', hasSubcats: false },
];

// ── Helpers ────────────────────────────────────────────────────────────────────

function labelForType(type: string): string {
  switch (type) {
    case 'sante': case 'veterinaire': return 'Santé & bien-être';
    case 'osteo':                     return 'Ostéopathe';
    case 'kine':                      return 'Kinésithérapeute';
    case 'marechal_ferrant':          return 'Maréchal-ferrant';
    case 'dentiste_equin':            return 'Dentiste équin';
    case 'education': case 'educateur': return 'Éducateur';
    case 'comportementaliste':        return 'Comportementaliste';
    case 'pension':                   return 'Pension';
    case 'pet_sitter': case 'garde':  return 'Pet-sitter';
    case 'promeneur':                 return 'Promeneur';
    case 'toilettage': case 'toiletteur': return 'Toilettage & soins';
    case 'alimentation': case 'animalerie': return 'Animalerie';
    case 'nutrition': case 'nutritionniste': return 'Nutritionniste';
    case 'transport': case 'taxi_animalier': case 'vtc': return 'Transport';
    case 'ambulance_vet':             return 'Ambulance vétérinaire';
    case 'photographe':               return 'Photographe';
    case 'boutique':                  return 'Boutique';
    case 'artisan': case 'createur':  return 'Créateur & artisan';
    case 'assurance':                 return 'Assurance';
    case 'juridique':                 return 'Juridique';
    default:                          return 'Professionnel';
  }
}

function colorForType(type: string): string {
  switch (type) {
    case 'sante': case 'veterinaire': case 'osteo': case 'kine': return '#2E7D5E';
    case 'marechal_ferrant': case 'dentiste_equin':               return '#558B2F';
    case 'education': case 'educateur':                           return '#E65100';
    case 'comportementaliste':                                    return '#BF360C';
    case 'pension': case 'pet_sitter': case 'garde': case 'promeneur': return '#F57C00';
    case 'toilettage': case 'toiletteur':                         return '#C62828';
    case 'alimentation': case 'animalerie': case 'nutrition':     return '#1565C0';
    case 'transport': case 'taxi_animalier': case 'vtc':          return '#00838F';
    case 'ambulance_vet':                                         return '#C62828';
    case 'photographe':                                           return '#AD1457';
    case 'boutique': case 'artisan': case 'createur':             return '#6A1B9A';
    case 'assurance': case 'juridique':                           return '#1E3A5F';
    default:                                                      return '#0C5C6C';
  }
}

// ── Composants ─────────────────────────────────────────────────────────────────

function CategoryTile({ cat, onClick }: { cat: AnnuaireCategory; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="bg-white rounded-2xl shadow-sm border border-gray-100 p-3 flex flex-col items-center gap-2 hover:shadow-md hover:border-gray-200 transition-all text-center"
    >
      <div
        className="w-12 h-12 rounded-xl flex items-center justify-center text-2xl relative"
        style={{ backgroundColor: cat.color + '18' }}
      >
        <span>{cat.icon}</span>
        {cat.hasSubcats && (
          <span
            className="absolute top-0.5 right-0.5 w-3 h-3 rounded-full flex items-center justify-center text-white text-[6px] font-bold"
            style={{ backgroundColor: cat.color }}
          >
            ›
          </span>
        )}
      </div>
      <span
        className="text-[11px] font-semibold text-[#1E2025] leading-tight whitespace-pre-line"
        style={{ fontFamily: 'Galey, sans-serif' }}
      >
        {cat.label}
      </span>
    </button>
  );
}

function ProCard({ pro }: { pro: VerifiedPro }) {
  const typeColor = colorForType(pro.profile_type);
  const label = labelForType(pro.profile_type);
  const acceptNew = pro.accept_new_clients !== false;

  return (
    <Link
      href={`/profil/${pro.uid}`}
      className="flex-shrink-0 w-40 bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow block"
    >
      {/* Photo */}
      <div
        className="relative w-full overflow-hidden"
        style={{ height: 108, backgroundColor: typeColor + '18' }}
      >
        {pro.avatar_url ? (
          <Image src={pro.avatar_url} alt={pro.nom || label} fill className="object-cover" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-3xl" style={{ opacity: 0.3 }}>
            🏪
          </div>
        )}
        <div className="absolute bottom-2 left-2">
          <span
            className="text-[10px] font-bold px-2 py-0.5 rounded-full"
            style={{
              backgroundColor: acceptNew ? '#2E7D5E22' : '#F5730022',
              color: acceptNew ? '#2E7D5E' : '#E65100',
            }}
          >
            {acceptNew ? 'Ouvert' : 'Sur RDV'}
          </span>
        </div>
      </div>
      {/* Infos */}
      <div className="p-2.5">
        <p
          className="text-[13px] font-bold text-[#1E2025] truncate"
          style={{ fontFamily: 'Galey, sans-serif' }}
        >
          {pro.nom || label}
        </p>
        <p className="text-[11px] text-gray-400 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
          {label}
        </p>
        {pro.ville_pro && (
          <div className="flex items-center gap-1 mt-1">
            <span className="text-[10px] text-gray-300">📍</span>
            <span className="text-[10px] text-gray-400 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
              {pro.ville_pro}
            </span>
          </div>
        )}
      </div>
    </Link>
  );
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function ServicesPage() {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [pros, setPros] = useState<VerifiedPro[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const { data: profilesData } = await supabase
          .from('user_profiles')
          .select('id, uid, nom, profile_type, avatar_url, ville_pro, accept_new_clients')
          .in('statut_pro', ['actif', 'validated'])
          .not('profile_type', 'in', '(eleveur,association)')
          .order('updated_at', { ascending: false })
          .limit(12);

        setPros((profilesData ?? []) as VerifiedPro[]);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    const q = query.trim();
    router.push(
      q ? `/services/carte?q=${encodeURIComponent(q)}&view=list` : '/services/carte?view=list'
    );
  }

  function handleCategoryClick(cat: AnnuaireCategory) {
    if (cat.hasSubcats) {
      router.push(`/services/${cat.slug}`);
    } else {
      router.push(`/services/carte?cat=${cat.catValues}&view=list`);
    }
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">

      {/* ── En-tête teal ──────────────────────────────────────────────────── */}
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-3xl mx-auto">
          <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
            Annuaire des professionnels
          </h1>
          <p className="text-white/70 text-sm mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            Trouvez le professionnel idéal pour votre animal
          </p>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4">

        {/* ── Barre de recherche ─────────────────────────────────────────── */}
        <div className="-mt-5 mb-6">
          <form onSubmit={handleSearch}>
            <div className="bg-white rounded-2xl shadow-md flex items-center px-4 gap-3 h-12">
              <span className="text-gray-400">🔍</span>
              <input
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Rechercher un professionnel…"
                className="flex-1 outline-none text-sm text-gray-700 bg-transparent placeholder-gray-400"
                style={{ fontFamily: 'Galey, sans-serif' }}
              />
              {query && (
                <button
                  type="submit"
                  className="text-[#0C5C6C] text-sm font-semibold"
                  style={{ fontFamily: 'Galey, sans-serif' }}
                >
                  Rechercher
                </button>
              )}
            </div>
          </form>
        </div>

        {/* ── Catégories ─────────────────────────────────────────────────── */}
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-[17px] font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Catégories
          </h2>
          <button
            onClick={() => router.push('/services/carte?view=list')}
            className="text-[13px] text-gray-400 font-semibold flex items-center gap-1"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            Voir tout <span>›</span>
          </button>
        </div>

        <div className="grid grid-cols-3 gap-2.5 mb-8">
          {CATEGORIES.map((cat) => (
            <CategoryTile key={cat.slug} cat={cat} onClick={() => handleCategoryClick(cat)} />
          ))}
        </div>

        {/* ── Professionnels vérifiés ────────────────────────────────────── */}
        <h2 className="text-[17px] font-bold text-[#1E2025] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
          Professionnels vérifiés
        </h2>

        {loading ? (
          <div className="h-48 flex items-center justify-center">
            <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : pros.length === 0 ? (
          <p className="text-sm text-gray-400 mb-8" style={{ fontFamily: 'Galey, sans-serif' }}>
            Aucun professionnel disponible pour le moment.
          </p>
        ) : (
          <div
            className="flex gap-3 pb-3 mb-6"
            style={{ overflowX: 'auto', scrollbarWidth: 'none' }}
          >
            {pros.map((pro) => (
              <ProCard key={pro.id} pro={pro} />
            ))}
          </div>
        )}

        {/* ── Bannière vérification ──────────────────────────────────────── */}
        <div
          className="mb-10 rounded-2xl px-4 py-4 flex items-start gap-3"
          style={{
            backgroundColor: 'rgba(12,92,108,0.07)',
            border: '1px solid rgba(12,92,108,0.15)',
          }}
        >
          <div
            className="w-11 h-11 flex-shrink-0 rounded-full flex items-center justify-center text-xl"
            style={{ backgroundColor: 'rgba(12,92,108,0.10)' }}
          >
            ✅
          </div>
          <div>
            <p className="text-sm font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Des professionnels vérifiés
            </p>
            <p className="text-xs text-gray-600 mt-0.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Tous les professionnels de notre annuaire sont vérifiés par notre équipe.
            </p>
          </div>
        </div>

      </div>
    </div>
  );
}
