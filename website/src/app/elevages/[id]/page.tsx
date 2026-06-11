'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import VerificationBadge, { getBadgeLevel } from '@/components/VerificationBadge';

// ─── Types ─────────────────────────────────────────────────────────────────────

interface EleveurData {
  uid: string;
  firstname?: string;
  lastname?: string;
  name_elevage?: string;
  desc_entreprise?: string;
  profile_picture_url?: string;
  profile_picture_url_elevage?: string;
  banner_url?: string;
  ville_elevage?: string;
  ville?: string;
  code_postal?: string;
  pays_elevage?: string;
  adresse_elevage?: string;
  especes_elevees?: { espece: string; races?: string[] }[];
  is_dog?: boolean;
  is_cat?: boolean;
  dog_breeds?: string[];
  cat_breeds?: string[];
  siret?: string;
  acaced?: string;
  statut_pro?: string;
  is_premium?: boolean;
  is_validate?: boolean;
  telephone?: string;
  site_web?: string;
  facebook?: string;
  instagram?: string;
}

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  prix?: number;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  statut?: string;
}

const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', cheval: 'Cheval', lapin: 'Lapin',
  oiseau: 'Oiseau', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin',
  porcin: 'Porcin', autre: 'Autre',
};

// ─── Page ───────────────────────────────────────────────────────────────────────

export default function EleveurProfilePage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuth();

  const [eleveur, setEleveur] = useState<EleveurData | null>(null);
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    if (!id) return;
    supabase
      .from('users')
      .select('uid, firstname, lastname, name_elevage, desc_entreprise, profile_picture_url, profile_picture_url_elevage, banner_url, ville_elevage, ville, code_postal, pays_elevage, adresse_elevage, especes_elevees, is_dog, is_cat, dog_breeds, cat_breeds, siret, acaced, statut_pro, is_premium, is_validate, telephone, site_web, facebook, instagram')
      .eq('uid', id)
      .maybeSingle()
      .then(({ data }) => {
        if (!data) { setNotFound(true); setLoading(false); return; }
        setEleveur(data as EleveurData);
        setLoading(false);
      });

    supabase
      .from('annonces')
      .select('id, titre, espece, race, type, type_vente, photos, prix, saillie_prix, prix_min_portee, prix_max_portee, ville_eleveur, statut')
      .eq('uid_eleveur', id)
      .eq('statut', 'disponible')
      .order('created_at', { ascending: false })
      .then(({ data }) => setAnnonces((data ?? []) as Annonce[]));
  }, [id]);

  if (loading) return (
    <div className="flex justify-center items-center min-h-screen">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (notFound || !eleveur) return (
    <div className="max-w-2xl mx-auto px-4 py-20 text-center">
      <p className="text-gray-400 text-lg mb-4">Éleveur introuvable.</p>
      <Link href="/elevages" className="text-[#0C5C6C] font-semibold hover:underline">← Retour à la liste</Link>
    </div>
  );

  const rawName = (eleveur.name_elevage ?? `${eleveur.firstname ?? ''} ${eleveur.lastname ?? ''}`.trim());
  const name = rawName || 'Éleveur';
  const photo = eleveur.profile_picture_url_elevage ?? eleveur.profile_picture_url;
  const banner = eleveur.banner_url;
  const ville = eleveur.ville_elevage ?? eleveur.ville ?? '';
  const badgeLevel = getBadgeLevel({ statutPro: eleveur.statut_pro, siret: eleveur.siret, isPremium: eleveur.is_premium });

  const especesList: { espece: string; races: string[] }[] = (() => {
    if (eleveur.especes_elevees && eleveur.especes_elevees.length > 0)
      return eleveur.especes_elevees.map(e => ({ espece: e.espece, races: e.races ?? [] }));
    const list: { espece: string; races: string[] }[] = [];
    if (eleveur.is_dog) list.push({ espece: 'chien', races: eleveur.dog_breeds ?? [] });
    if (eleveur.is_cat) list.push({ espece: 'chat', races: eleveur.cat_breeds ?? [] });
    return list;
  })();

  const isOwnProfile = user?.uid === eleveur.uid;

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      {/* Banner + photo */}
      <div className="relative">
        <div className="h-52 sm:h-64 bg-[#EEF5EA] overflow-hidden">
          {banner ? (
            <Image src={banner} alt={name} fill className="object-cover" />
          ) : photo ? (
            <Image src={photo} alt={name} fill className="object-cover brightness-75" />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-8xl">🏡</div>
          )}
          <div className="absolute inset-0 bg-gradient-to-b from-transparent to-black/40" />
        </div>

        {/* Photo profil en overlay */}
        <div className="absolute -bottom-10 left-5 sm:left-8 w-20 h-20 sm:w-24 sm:h-24 rounded-full border-4 border-white shadow-md bg-[#EEF5EA] overflow-hidden">
          {photo ? (
            <Image src={photo} alt={name} fill className="object-cover" />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-4xl">🏡</div>
          )}
        </div>

        {/* Bouton retour */}
        <Link href="/elevages"
          className="absolute top-4 left-4 bg-white/80 backdrop-blur-sm text-[#1F2A2E] rounded-full p-2 shadow hover:bg-white transition-colors">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </Link>
      </div>

      {/* Contenu */}
      <div className="max-w-3xl mx-auto px-4 pt-14 pb-16">

        {/* Header nom + badge */}
        <div className="bg-white rounded-2xl shadow-sm p-5 mb-4">
          <div className="flex items-start justify-between gap-3 flex-wrap">
            <div>
              <div className="flex items-center gap-2 flex-wrap">
                <h1 className="font-['Galey'] font-bold text-2xl text-[#1F2A2E]">{name}</h1>
                <VerificationBadge level={badgeLevel} size="md" />
              </div>
              {ville && <p className="text-gray-500 text-sm mt-0.5">📍 {ville}{eleveur.pays_elevage && eleveur.pays_elevage !== 'France' ? `, ${eleveur.pays_elevage}` : ''}</p>}
            </div>
            {isOwnProfile && (
              <Link href="/profil/modifier"
                className="text-sm border border-gray-200 text-gray-600 px-4 py-1.5 rounded-xl hover:bg-gray-50 transition-colors">
                Modifier le profil
              </Link>
            )}
          </div>

          {/* Espèces + races */}
          {especesList.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-1.5">
              {especesList.map(({ espece, races }) => (
                <span key={espece}>
                  <span className="inline-flex items-center bg-[#EEF5EA] text-[#0C5C6C] text-xs font-semibold px-2.5 py-1 rounded-full capitalize">
                    {ESPECE_LABEL[espece] ?? espece}
                  </span>
                  {races.slice(0, 3).map(r => (
                    <span key={r} className="inline-flex items-center bg-gray-100 text-gray-600 text-xs px-2 py-0.5 rounded-full ml-1">
                      {r}
                    </span>
                  ))}
                  {races.length > 3 && (
                    <span className="inline-flex items-center bg-gray-100 text-gray-500 text-xs px-2 py-0.5 rounded-full ml-1">
                      +{races.length - 3}
                    </span>
                  )}
                </span>
              ))}
            </div>
          )}

          {/* Description */}
          {eleveur.desc_entreprise && (
            <p className="text-gray-600 text-sm mt-3 leading-relaxed">{eleveur.desc_entreprise}</p>
          )}

          {/* Liens sociaux */}
          {(eleveur.site_web || eleveur.instagram || eleveur.facebook) && (
            <div className="flex gap-3 mt-3 flex-wrap">
              {eleveur.site_web && (
                <a href={eleveur.site_web} target="_blank" rel="noopener noreferrer"
                  className="text-xs text-[#0C5C6C] hover:underline">🌐 Site web</a>
              )}
              {eleveur.instagram && (
                <a href={`https://instagram.com/${eleveur.instagram.replace('@', '')}`} target="_blank" rel="noopener noreferrer"
                  className="text-xs text-[#0C5C6C] hover:underline">📷 Instagram</a>
              )}
              {eleveur.facebook && (
                <a href={eleveur.facebook} target="_blank" rel="noopener noreferrer"
                  className="text-xs text-[#0C5C6C] hover:underline">👍 Facebook</a>
              )}
            </div>
          )}
        </div>

        {/* Annonces disponibles */}
        <div>
          <h2 className="font-['Galey'] font-bold text-lg text-[#1F2A2E] mb-3">
            Annonces disponibles
            {annonces.length > 0 && <span className="ml-2 text-sm font-normal text-gray-400">({annonces.length})</span>}
          </h2>
          {annonces.length === 0 ? (
            <p className="text-gray-400 text-sm text-center py-8 bg-white rounded-2xl shadow-sm">
              Aucune annonce disponible pour le moment.
            </p>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {annonces.map(a => <AnnonceCard key={a.id} annonce={a} />)}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Card annonce mini ───────────────────────────────────────────────────────────

function AnnonceCard({ annonce: a }: { annonce: Annonce }) {
  const photos = (a.photos as unknown as string[]) ?? [];
  const photo = photos[0];
  const isSaillie = a.type_vente === 'saillie';
  const isPortee = a.type === 'portee';

  let prix: string | null = null;
  if (isSaillie) {
    const sp = a.saillie_prix != null ? Number(a.saillie_prix) : null;
    prix = sp != null ? `${Math.round(sp)} €` : null;
  } else if (isPortee) {
    const parts = [a.prix_min_portee, a.prix_max_portee].filter((v): v is number => v != null);
    if (parts.length === 2 && parts[0] !== parts[1]) prix = `${parts[0]} – ${parts[1]} €`;
    else if (parts.length > 0) prix = `${parts[0]} €`;
  } else {
    prix = a.prix != null ? `${a.prix} €` : null;
  }

  return (
    <Link href={`/annonces/${a.id}`}
      className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow block">
      <div className="aspect-square bg-[#F5F5F0] relative">
        {photo ? (
          <Image src={photo} alt={a.titre ?? ''} fill className="object-contain" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-4xl">🐾</div>
        )}
        <span className={`absolute top-1.5 left-1.5 text-white text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${isSaillie ? 'bg-purple-500' : isPortee ? 'bg-amber-500' : 'bg-[#6E9E57]'}`}>
          {isSaillie ? 'Saillie' : isPortee ? 'Portée' : 'Compagnon'}
        </span>
      </div>
      <div className="p-2.5">
        <p className="font-semibold text-[#1F2A2E] text-xs truncate capitalize">
          {a.titre ?? `${a.espece ?? ''} ${a.race ?? ''}`}
        </p>
        <p className="text-gray-400 text-[11px] capitalize">{a.espece}{a.race ? ` · ${a.race}` : ''}</p>
        {prix && <p className="text-[#0C5C6C] font-bold text-xs mt-0.5">{prix}</p>}
      </div>
    </Link>
  );
}
