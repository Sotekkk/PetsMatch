'use client';

import Link from 'next/link';

const CATEGORIES = [
  { slug: 'sante', label: 'Santé', emoji: '🏥', desc: 'Maladies, traitements, conseils vétérinaires' },
  { slug: 'alimentation', label: 'Alimentation', emoji: '🍖', desc: 'Nutrition, régimes, marques' },
  { slug: 'education', label: 'Éducation', emoji: '🎓', desc: 'Dressage, comportement, astuces' },
  { slug: 'elevage', label: 'Élevage', emoji: '🐣', desc: 'Reproduction, portées, naissances' },
  { slug: 'bien_etre', label: 'Bien-être', emoji: '💆', desc: 'Grooming, confort, bien-être animal' },
  { slug: 'general', label: 'Général', emoji: '💬', desc: 'Discussions libres entre passionnés' },
];

export default function ForumPage() {
  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Hero */}
      <div className="bg-[#0C5C6C] text-white px-4 py-10">
        <div className="max-w-2xl mx-auto text-center">
          <p className="text-4xl mb-3">💬</p>
          <h1 className="text-2xl font-bold mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Forum communauté
          </h1>
          <p className="text-white/70 text-sm">
            Posez vos questions, partagez vos expériences et échangez avec la communauté.
          </p>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-8">
        <div className="flex flex-col gap-3">
          {CATEGORIES.map(cat => (
            <Link
              key={cat.slug}
              href={`/communaute/forum/${cat.slug}`}
              className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5 flex items-center gap-4 hover:shadow-md hover:border-[#0C5C6C]/20 transition-all group"
            >
              <div className="w-14 h-14 rounded-2xl bg-[#E0F7FA] flex items-center justify-center flex-shrink-0 text-3xl group-hover:scale-105 transition-transform">
                {cat.emoji}
              </div>
              <div className="flex-1">
                <p className="font-bold text-[#1E2025] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {cat.label}
                </p>
                <p className="text-sm text-gray-500 mt-0.5" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {cat.desc}
                </p>
              </div>
              <svg className="w-5 h-5 text-gray-400 group-hover:text-[#0C5C6C] group-hover:translate-x-0.5 transition-all flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
              </svg>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
