'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';

interface AssoProfile {
  uid: string;
  nom: string;
  avatar: string;
  ville: string;
  description: string;
  telephone?: string;
  site_web?: string;
}

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  photos?: string[];
  ville_eleveur?: string;
}

interface Animal {
  id: string;
  nom: string;
  espece?: string;
  race?: string;
  statut?: string;
  photo_url?: string;
}

export default function AssociationProfilePage() {
  const { id } = useParams<{ id: string }>();
  const [profile, setProfile] = useState<AssoProfile | null>(null);
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!id) return;

    Promise.all([
      // Profil secondaire association
      supabase.from('user_profiles')
        .select('profile_label, name_elevage, avatar_url, ville, description, telephone, site_web')
        .eq('uid', id).eq('profile_type', 'association').maybeSingle(),
      // Fallback : users table
      supabase.from('users')
        .select('name_elevage, profile_picture_url_elevage, ville_elevage, description_elevage, phone')
        .eq('uid', id).maybeSingle(),
      // Annonces
      supabase.from('annonces')
        .select('id, titre, espece, race, photos, ville_eleveur')
        .eq('uid_eleveur', id).eq('profil_source', 'association').eq('statut', 'disponible')
        .order('created_at', { ascending: false }),
      // Animaux
      supabase.from('animaux')
        .select('id, nom, espece, race, statut, photo_url')
        .eq('uid_eleveur', id).eq('is_association', true).eq('statut', 'disponible')
        .order('nom'),
    ]).then(([{ data: secProfile }, { data: userRow }, { data: ann }, { data: anim }]) => {
      type SecProfile = { profile_label?: string; name_elevage?: string; avatar_url?: string; ville?: string; description?: string; telephone?: string; site_web?: string };
      const sp = secProfile as SecProfile | null;
      const nom = (sp?.name_elevage?.trim() || sp?.profile_label?.trim())
        ?? (userRow as { name_elevage?: string } | null)?.name_elevage ?? 'Association';
      const avatar = sp?.avatar_url
        ?? (userRow as { profile_picture_url_elevage?: string } | null)?.profile_picture_url_elevage ?? '';
      const ville = sp?.ville
        ?? (userRow as { ville_elevage?: string } | null)?.ville_elevage ?? '';
      const description = sp?.description
        ?? (userRow as { description_elevage?: string } | null)?.description_elevage ?? '';

      setProfile({ uid: id, nom, avatar, ville, description,
        telephone: sp?.telephone,
        site_web: sp?.site_web,
      });
      setAnnonces((ann ?? []) as Annonce[]);
      setAnimaux((anim ?? []) as Animal[]);
      setLoading(false);
    });
  }, [id]);

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
      </div>
    );
  }

  if (!profile) {
    return (
      <div className="text-center py-24 text-gray-400 font-galey">
        <p className="text-5xl mb-4">🏠</p>
        <p>Association introuvable</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
      {/* Header */}
      <div className="bg-gradient-to-r from-teal-700 to-green-600 rounded-2xl p-6 text-white">
        <div className="flex items-center gap-5">
          <div className="w-20 h-20 rounded-full overflow-hidden bg-white/20 flex-shrink-0 flex items-center justify-center">
            {profile.avatar ? (
              <Image src={profile.avatar} alt={profile.nom} width={80} height={80}
                className="w-full h-full object-cover" unoptimized />
            ) : (
              <span className="text-3xl">🏠</span>
            )}
          </div>
          <div className="flex-1">
            <h1 className="text-2xl font-bold font-galey">{profile.nom}</h1>
            <div className="flex items-center gap-2 mt-1">
              <span className="bg-white/20 px-2 py-0.5 rounded-full text-xs font-galey">Association / Refuge</span>
              {profile.ville && <span className="text-white/80 text-sm font-galey">📍 {profile.ville}</span>}
            </div>
            {profile.telephone && (
              <a href={`tel:${profile.telephone}`} className="text-white/80 text-sm font-galey mt-1 block hover:text-white">
                📞 {profile.telephone}
              </a>
            )}
          </div>
        </div>
        {profile.description && (
          <p className="mt-4 text-white/90 font-galey text-sm leading-relaxed">{profile.description}</p>
        )}
        {profile.site_web && (
          <a href={profile.site_web} target="_blank" rel="noopener noreferrer"
            className="mt-3 inline-block text-white/80 text-xs font-galey hover:text-white underline">
            🌐 {profile.site_web}
          </a>
        )}
      </div>

      {/* Annonces */}
      {annonces.length > 0 && (
        <section>
          <h2 className="text-xl font-bold font-galey text-teal-800 mb-4">
            Animaux à adopter <span className="text-sm font-normal text-gray-400 ml-2">{annonces.length}</span>
          </h2>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            {annonces.map((a) => (
              <Link key={a.id} href={`/annonces/${a.id}`}
                className="bg-white rounded-2xl overflow-hidden shadow-sm border border-gray-100 hover:border-teal-200 hover:shadow-md transition-all group">
                <div className="aspect-square bg-gray-100 relative overflow-hidden">
                  {a.photos?.[0] ? (
                    <Image src={a.photos[0]} alt={a.titre ?? 'Animal'} fill
                      className="object-cover group-hover:scale-105 transition-transform duration-300" unoptimized />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-3xl text-gray-300">🐾</div>
                  )}
                  <div className="absolute top-2 left-2 bg-teal-700/90 text-white text-xs font-galey font-semibold px-2 py-0.5 rounded-full">
                    Adoption
                  </div>
                </div>
                <div className="p-3">
                  <p className="font-bold font-galey text-sm text-gray-900 truncate">{a.titre ?? 'Animal à adopter'}</p>
                  {a.race && <p className="text-xs text-gray-500 font-galey">{a.race}</p>}
                  {a.ville_eleveur && <p className="text-xs text-gray-400 font-galey">📍 {a.ville_eleveur}</p>}
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* Animaux du refuge */}
      {animaux.length > 0 && (
        <section>
          <h2 className="text-xl font-bold font-galey text-teal-800 mb-4">
            Animaux au refuge <span className="text-sm font-normal text-gray-400 ml-2">{animaux.length}</span>
          </h2>
          <div className="grid grid-cols-3 md:grid-cols-4 gap-3">
            {animaux.map((a) => (
              <div key={a.id} className="bg-white rounded-xl overflow-hidden shadow-sm border border-gray-100">
                <div className="aspect-square bg-gray-100 relative overflow-hidden">
                  {a.photo_url ? (
                    <Image src={a.photo_url} alt={a.nom} fill className="object-cover" unoptimized />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-2xl text-gray-300">🐾</div>
                  )}
                </div>
                <div className="p-2">
                  <p className="font-bold font-galey text-xs text-gray-900 truncate">{a.nom}</p>
                  <p className="text-xs text-gray-400 font-galey truncate">{a.race ?? a.espece}</p>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {annonces.length === 0 && animaux.length === 0 && (
        <div className="text-center py-12 text-gray-400 font-galey">
          <p className="text-4xl mb-3">🐾</p>
          <p>Aucun animal disponible pour le moment</p>
        </div>
      )}

      <div className="text-center pt-4">
        <Link href="/adoptions" className="text-teal-600 font-galey text-sm hover:underline">
          ← Voir toutes les adoptions
        </Link>
      </div>
    </div>
  );
}
