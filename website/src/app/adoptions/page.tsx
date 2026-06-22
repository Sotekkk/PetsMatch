'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';

const ESPECES = ['tous', 'chien', 'chat', 'lapin', 'oiseau', 'cheval', 'nac', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  tous: 'Toutes', chien: 'Chiens', chat: 'Chats', lapin: 'Lapins',
  oiseau: 'Oiseaux', cheval: 'Chevaux', nac: 'NAC', autre: 'Autres',
};
const ESPECE_EMOJI: Record<string, string> = {
  tous: '🐾', chien: '🐕', chat: '🐈', lapin: '🐇',
  oiseau: '🦜', cheval: '🐴', nac: '🦎', autre: '🐾',
};

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  photos?: string[];
  ville_eleveur?: string;
  nom_eleveur?: string;
  date_naissance_animal?: string;
}

function ageLabel(dateStr?: string) {
  if (!dateStr) return null;
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days < 0) return null;
  if (days < 91) return `${Math.floor(days / 7)} sem.`;
  const months = Math.floor(days / 30.44);
  if (months < 12) return `${months} mois`;
  return `${Math.floor(days / 365)} ans`;
}

export default function AdoptionsPage() {
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);
  const [espece, setEspece] = useState('tous');
  const [search, setSearch] = useState('');

  useEffect(() => {
    supabase
      .from('annonces')
      .select('id, titre, espece, race, sexe, photos, ville_eleveur, nom_eleveur, date_naissance_animal')
      .eq('statut', 'disponible')
      .eq('profil_source', 'association')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setAnnonces((data ?? []) as Annonce[]);
        setLoading(false);
      });
  }, []);

  const filtered = annonces.filter((a) => {
    if (espece !== 'tous' && a.espece !== espece) return false;
    if (search) {
      const q = search.toLowerCase();
      return (
        (a.titre ?? '').toLowerCase().includes(q) ||
        (a.race ?? '').toLowerCase().includes(q) ||
        (a.nom_eleveur ?? '').toLowerCase().includes(q)
      );
    }
    return true;
  });

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* En-tête */}
      <div className="text-center space-y-2">
        <h1 className="text-3xl font-bold font-galey text-teal-800">💚 Animaux à adopter</h1>
        <p className="text-gray-500 font-galey">Annonces publiées par les associations &amp; refuges</p>
      </div>

      {/* Recherche */}
      <input
        type="search"
        placeholder="Rechercher un animal, une race, une association…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="w-full px-4 py-3 rounded-2xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400 shadow-sm"
      />

      {/* Filtres espèce */}
      <div className="flex gap-2 flex-wrap justify-center">
        {ESPECES.map((e) => (
          <button
            key={e}
            onClick={() => setEspece(e)}
            className={`px-4 py-1.5 rounded-full text-sm font-galey font-semibold border transition-all ${
              espece === e
                ? 'bg-teal-700 text-white border-teal-700'
                : 'bg-white text-gray-600 border-gray-200 hover:border-teal-300'
            }`}
          >
            {ESPECE_EMOJI[e]} {ESPECE_LABEL[e]}
          </button>
        ))}
      </div>

      {/* Résultats */}
      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 text-gray-400 font-galey">
          <p className="text-5xl mb-4">🐾</p>
          <p className="text-lg">Aucun animal disponible à l&apos;adoption pour le moment.</p>
        </div>
      ) : (
        <>
          <p className="text-sm text-gray-400 font-galey text-center">
            {filtered.length} animal{filtered.length !== 1 ? 'x' : ''} disponible{filtered.length !== 1 ? 's' : ''}
          </p>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {filtered.map((a) => (
              <Link
                key={a.id}
                href={`/annonces/${a.id}`}
                className="bg-white rounded-2xl overflow-hidden shadow-sm border border-gray-100 hover:border-teal-200 hover:shadow-md transition-all group"
              >
                {/* Photo */}
                <div className="aspect-square bg-gray-100 relative overflow-hidden">
                  {a.photos?.[0] ? (
                    <Image
                      src={a.photos[0]}
                      alt={a.titre ?? 'Animal'}
                      fill
                      className="object-cover group-hover:scale-105 transition-transform duration-300"
                      unoptimized
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-4xl">
                      {ESPECE_EMOJI[a.espece ?? 'autre'] ?? '🐾'}
                    </div>
                  )}
                  <div className="absolute top-2 left-2 bg-teal-700/90 text-white text-xs font-galey font-semibold px-2 py-0.5 rounded-full">
                    Adoption
                  </div>
                  {(a.sexe === 'male' || a.sexe === 'femelle') && (
                    <div className="absolute top-2 right-2 bg-white/80 rounded-full p-1 text-xs">
                      {a.sexe === 'male' ? '♂' : '♀'}
                    </div>
                  )}
                </div>
                {/* Infos */}
                <div className="p-3">
                  <p className="font-bold font-galey text-sm text-gray-900 truncate">
                    {a.titre ?? `${a.espece ?? ''} à adopter`}
                  </p>
                  {a.race && (
                    <p className="text-xs text-gray-500 font-galey truncate">{a.race}</p>
                  )}
                  <div className="flex items-center justify-between mt-1.5">
                    {ageLabel(a.date_naissance_animal) ? (
                      <span className="text-xs text-teal-700 font-galey">{ageLabel(a.date_naissance_animal)}</span>
                    ) : <span />}
                    {a.ville_eleveur && (
                      <span className="text-xs text-gray-400 font-galey truncate">📍 {a.ville_eleveur}</span>
                    )}
                  </div>
                  {a.nom_eleveur && (
                    <p className="text-xs text-teal-600 font-galey mt-1 truncate">🏠 {a.nom_eleveur}</p>
                  )}
                </div>
              </Link>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
