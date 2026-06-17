import Link from 'next/link';

export const metadata = { title: 'À propos — PetsMatch' };

const INFO_CARDS = [
  {
    title: '🏢 Éditeur',
    items: [
      ['Dénomination', 'PETSMATCH (PM)'],
      ['Forme juridique', 'SAS'],
      ['Siège social', '15 La Ville Marchand, 22210 Plumieux, France'],
      ['SIREN', '931 344 816'],
      ['SIRET', '931 344 816 00018'],
      ['TVA intracommunautaire', 'FR94 931 344 816'],
      ['Date de création', '20 juillet 2024'],
      ['Email', 'petsmatch.contact@gmail.com'],
      ['Téléphone', '07 81 03 49 84'],
    ],
  },
  {
    title: '👤 Responsables de la publication',
    items: [
      ['Présidente', 'Natacha Loisiel'],
      ['Directeur général', 'Nabil Ksouri'],
    ],
  },
  {
    title: '☁️ Hébergement',
    items: [
      ['Base de données', 'Supabase (Supabase Inc.)'],
      ['Auth & stockage', 'Google Firebase (Google LLC)'],
      ['Données Firebase', '1600 Amphitheatre Parkway, Mountain View, CA 94043, USA'],
    ],
  },
];

const TEXT_CARDS = [
  {
    title: '⚖️ Propriété intellectuelle',
    body: "Tous les éléments de l'application PetsMatch (textes, graphismes, logos, images, vidéos) sont protégés par des droits d'auteur et appartiennent exclusivement à PETSMATCH SAS. Toute reproduction sans autorisation écrite préalable est strictement interdite.",
  },
  {
    title: '🔒 Données personnelles',
    body: "Vos données sont traitées conformément au RGPD. Vous disposez de droits d'accès, de rectification, de suppression et d'opposition.\n\nContact : petsmatch.contact@gmail.com",
  },
  {
    title: '🏛️ Litiges et juridiction',
    body: "En cas de litige, les parties s'efforceront de trouver une solution à l'amiable. La juridiction compétente est celle des tribunaux de Rennes, France.",
  },
];

export default function AProposPage() {
  return (
    <div className="max-w-2xl mx-auto px-4 py-10">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/profil" className="p-2 rounded-full hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7"/>
          </svg>
        </Link>
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          À propos de PetsMatch
        </h1>
      </div>

      <div className="space-y-4">
        {INFO_CARDS.map(card => (
          <div key={card.title} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
            <p className="font-bold text-[#0C5C6C] text-sm mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>{card.title}</p>
            <div className="space-y-2">
              {card.items.map(([label, value]) => (
                <div key={label} className="flex gap-3 text-sm">
                  <span className="text-gray-400 w-44 flex-shrink-0" style={{ fontFamily: 'Galey, sans-serif' }}>{label}</span>
                  <span className="text-[#1F2A2E] font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>{value}</span>
                </div>
              ))}
            </div>
          </div>
        ))}

        {TEXT_CARDS.map(card => (
          <div key={card.title} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
            <p className="font-bold text-[#0C5C6C] text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>{card.title}</p>
            <p className="text-sm text-gray-500 leading-relaxed whitespace-pre-line" style={{ fontFamily: 'Galey, sans-serif' }}>{card.body}</p>
          </div>
        ))}

        <Link href="https://www.petsmatchapp.com/cgu" target="_blank" rel="noopener noreferrer"
          className="flex items-center justify-center gap-2 w-full py-3.5 rounded-2xl border border-[#0C5C6C] text-[#0C5C6C] font-semibold text-sm hover:bg-[#E6F4F7] transition-colors"
          style={{ fontFamily: 'Galey, sans-serif' }}>
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
          </svg>
          Politique de confidentialité complète
        </Link>
      </div>
    </div>
  );
}
