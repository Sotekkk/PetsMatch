'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  animaux_portee?: { nom?: string; sexe?: string; photos?: string[]; statut?: string }[];
  prix?: number;
  ville_eleveur?: string;
  nom_eleveur?: string;
  uid_eleveur?: string;
  statut?: string;
  date_naissance_animal?: string;
}

const ESPECES = ['tous', 'chien', 'chat', 'lapin', 'oiseau', 'cheval', 'nac', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  tous: 'Toutes', chien: 'Chiens', chat: 'Chats', lapin: 'Lapins',
  oiseau: 'Oiseaux', cheval: 'Chevaux', nac: 'NAC', autre: 'Autres',
};
const ESPECE_EMOJI: Record<string, string> = {
  tous: '🐾', chien: '🐕', chat: '🐈', lapin: '🐇',
  oiseau: '🦜', cheval: '🐴', nac: '🦎', autre: '🐾',
};

function ageLabel(dateStr?: string) {
  if (!dateStr) return null;
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days < 0) return null;
  if (days < 91) return `${Math.floor(days / 7)} sem.`;
  const months = Math.floor(days / 30.44);
  if (months < 12) return `${months} mois`;
  return `${Math.floor(days / 365)} ans`;
}

interface FlatItem {
  annonceId: string;
  nom: string;
  espece?: string;
  race?: string;
  sexe?: string;
  photo?: string;
  age?: string | null;
  ville?: string;
  nomAsso?: string;
  uidAsso?: string;
}

function flattenAnnonce(a: Annonce): FlatItem[] {
  const bebes = a.animaux_portee ?? [];
  if (a.type === 'portee' && bebes.length > 0) {
    return bebes.map((b) => ({
      annonceId: a.id,
      nom: b.nom ?? 'Animal',
      espece: a.espece,
      race: a.race,
      sexe: b.sexe,
      photo: b.photos?.[0] ?? a.photos?.[0],
      age: ageLabel(a.date_naissance_animal),
      ville: a.ville_eleveur,
      nomAsso: a.nom_eleveur,
      uidAsso: a.uid_eleveur,
    }));
  }
  const titre = a.titre?.trim() || `${a.espece ?? ''} ${a.race ?? ''}`.trim() || 'Animal';
  return [{
    annonceId: a.id,
    nom: titre,
    espece: a.espece,
    race: a.race,
    photo: a.photos?.[0],
    age: ageLabel(a.date_naissance_animal),
    ville: a.ville_eleveur,
    nomAsso: a.nom_eleveur,
    uidAsso: a.uid_eleveur,
  }];
}

export default function AdoptionFeedPage() {
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);
  const [espece, setEspece] = useState('tous');
  const [search, setSearch] = useState('');

  useEffect(() => {
    supabase
      .from('annonces')
      .select('id, titre, espece, race, type, type_vente, photos, animaux_portee, prix, ville_eleveur, nom_eleveur, uid_eleveur, statut, date_naissance_animal')
      .eq('statut', 'disponible')
      .eq('profil_source', 'association')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setAnnonces((data ?? []) as Annonce[]);
        setLoading(false);
      });
  }, []);

  const items = annonces
    .flatMap(flattenAnnonce)
    .filter((item) => {
      if (espece !== 'tous' && item.espece !== espece) return false;
      if (search) {
        const q = search.toLowerCase();
        return (
          item.nom.toLowerCase().includes(q) ||
          (item.race ?? '').toLowerCase().includes(q) ||
          (item.nomAsso ?? '').toLowerCase().includes(q)
        );
      }
      return true;
    });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Fil d&apos;adoption</h1>
        <span className="text-sm text-gray-400 font-galey">{items.length} animal{items.length !== 1 ? 'x' : ''}</span>
      </div>

      {/* Recherche */}
      <input
        type="search"
        placeholder="Rechercher un animal, une race, une asso…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400"
      />

      {/* Filtres espèce */}
      <div className="flex gap-2 flex-wrap">
        {ESPECES.map((e) => (
          <button
            key={e}
            onClick={() => setEspece(e)}
            className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
              espece === e
                ? 'bg-teal-700 text-white border-teal-700'
                : 'bg-white text-gray-600 border-gray-200 hover:border-teal-300'
            }`}
          >
            {ESPECE_EMOJI[e]} {ESPECE_LABEL[e]}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : items.length === 0 ? (
        <div className="text-center py-16 text-gray-400 font-galey">
          <p className="text-4xl mb-3">🐾</p>
          <p>Aucun animal disponible à l&apos;adoption pour le moment.</p>
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {items.map((item, i) => (
            <Link
              key={`${item.annonceId}-${i}`}
              href={`/annonces/${item.annonceId}`}
              className="bg-white rounded-2xl overflow-hidden shadow-sm border border-gray-100 hover:border-teal-200 hover:shadow-md transition-all group"
            >
              {/* Photo */}
              <div className="aspect-square bg-gray-100 relative overflow-hidden">
                {item.photo ? (
                  <Image
                    src={item.photo}
                    alt={item.nom}
                    fill
                    className="object-cover group-hover:scale-105 transition-transform duration-300"
                    unoptimized
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-4xl">
                    {ESPECE_EMOJI[item.espece ?? 'autre'] ?? '🐾'}
                  </div>
                )}
                <div className="absolute top-2 left-2 bg-teal-700/90 text-white text-xs font-galey font-semibold px-2 py-0.5 rounded-full">
                  Adoption
                </div>
              </div>
              {/* Infos */}
              <div className="p-3">
                <p className="font-bold font-galey text-sm text-gray-900 truncate">{item.nom}</p>
                {item.race && (
                  <p className="text-xs text-gray-500 font-galey truncate">{item.race}</p>
                )}
                <div className="flex items-center justify-between mt-1.5">
                  {item.age ? (
                    <span className="text-xs text-teal-700 font-galey">{item.age}</span>
                  ) : <span />}
                  {item.ville && (
                    <span className="text-xs text-gray-400 font-galey truncate">📍 {item.ville}</span>
                  )}
                </div>
                {item.nomAsso && (
                  <p className="text-xs text-gray-400 font-galey mt-1 truncate">🏠 {item.nomAsso}</p>
                )}
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
