'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import MarketplaceBanner from './MarketplaceBanner';

interface Animal {
  id: string;
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  photo_url?: string;
}

interface Alerte {
  id: string;
  nom_animal?: string;
  espece?: string;
  race?: string;
  derniere_localisation?: string;
  date_perte?: string;
  photo_url?: string;
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
  prix_min_portee?: number;
  ville_eleveur?: string;
}

const SPECIES_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

const SPECIES_COLOR: Record<string, string> = {
  chien: 'bg-blue-50 border-blue-200',
  chat: 'bg-purple-50 border-purple-200',
  cheval: 'bg-amber-50 border-amber-200',
  lapin: 'bg-green-50 border-green-200',
  oiseau: 'bg-orange-50 border-orange-200',
};

function formatDate(dateStr?: string) {
  if (!dateStr) return '';
  return new Date(dateStr).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: '2-digit' });
}

export default function ParticulierDashboard() {
  const { user, userData, loading: authLoading, activeProfileId } = useAuth();
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [mesAlertes, setMesAlertes] = useState<Alerte[]>([]);
  const [alertesPubliques, setAlertesPubliques] = useState<Alerte[]>([]);
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);

  const firstname = userData?.firstname ?? '';
  const ville = userData?.ville ?? '';
  const avatar = userData?.profilePictureUrl ?? null;

  useEffect(() => {
    if (!user || authLoading) return;
    const uid = user.uid;

    async function load() {
      // Récupérer les IDs des animaux présents pour ce profil
      let animalIds: string[] = [];
      if (activeProfileId) {
        const { data: check } = await supabase
          .from('animaux_proprietes').select('animal_id')
          .eq('uid_proprio', uid).not('profile_id_proprio', 'is', null).limit(1);
        if ((check ?? []).length > 0) {
          const { data: rows } = await supabase
            .from('animaux_proprietes').select('animal_id')
            .eq('uid_proprio', uid).eq('profile_id_proprio', activeProfileId).is('date_fin', null);
          animalIds = (rows ?? []).map(r => r.animal_id as string);
        } else {
          const { data: rows } = await supabase
            .from('animaux_proprietes').select('animal_id')
            .eq('uid_proprio', uid).is('date_fin', null);
          animalIds = (rows ?? []).map(r => r.animal_id as string);
        }
      } else {
        const { data: rows } = await supabase
          .from('animaux_proprietes').select('animal_id')
          .eq('uid_proprio', uid).is('date_fin', null);
        animalIds = (rows ?? []).map(r => r.animal_id as string);
      }

      const [animauxRes, alertesMesRes, alertesPubliquesRes, annoncesRes] = await Promise.all([
        animalIds.length > 0
          ? supabase.from('animaux').select('id, nom, espece, race, sexe, photo_url').in('id', animalIds)
          : Promise.resolve({ data: [] }),
        supabase.from('alertes_perdus').select()
          .eq('uid_proprietaire', uid).eq('statut', 'perdu'),
        supabase.from('alertes_perdus')
          .select('id, nom_animal, espece, race, derniere_localisation, date_perte, photo_url')
          .eq('statut', 'perdu').order('created_at', { ascending: false }).limit(6),
        supabase.from('annonces')
          .select('id, titre, espece, race, type, type_vente, photos, prix, prix_min_portee, ville_eleveur')
          .eq('statut', 'disponible').order('created_at', { ascending: false }).limit(8),
      ]);
      setAnimaux((animauxRes.data ?? []) as Animal[]);
      setMesAlertes((alertesMesRes.data ?? []) as Alerte[]);
      setAlertesPubliques((alertesPubliquesRes.data ?? []) as Alerte[]);
      setAnnonces((annoncesRes.data ?? []) as Annonce[]);
      setLoading(false);
    }

    load().catch(() => setLoading(false));
  }, [user, authLoading, activeProfileId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      {/* Header banner */}
      <div className="bg-gradient-to-br from-[#0C5C6C] to-[#5F9EAA] text-white">
        <div className="max-w-6xl mx-auto px-4 py-8">
          <div className="flex items-center gap-4 mb-5">
            <Link href="/profil" className="flex-shrink-0">
              <div className="w-14 h-14 rounded-full bg-[#5B9EAA] overflow-hidden flex items-center justify-center border-2 border-white/30">
                {avatar ? (
                  <Image src={avatar} alt="" width={56} height={56} className="object-cover w-full h-full" />
                ) : (
                  <span className="text-2xl">👤</span>
                )}
              </div>
            </Link>
            <div>
              <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
                Bonjour{firstname ? `, ${firstname}` : ''} !
              </h1>
              {ville && <p className="text-white/70 text-sm">📍 {ville}</p>}
            </div>
          </div>
          {/* Stats in header */}
          <div className="flex gap-3">
            <div className="flex items-center gap-2 bg-white/15 rounded-xl px-4 py-2.5">
              <span className="text-lg">🐾</span>
              <div>
                <p className="text-white font-bold text-lg leading-none" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {animaux.length}
                </p>
                <p className="text-white/70 text-xs">Animal{animaux.length > 1 ? 'x' : ''}</p>
              </div>
            </div>
            {mesAlertes.length > 0 && (
              <div className="flex items-center gap-2 bg-white/15 rounded-xl px-4 py-2.5">
                <span className="text-lg">🔍</span>
                <div>
                  <p className="text-amber-300 font-bold text-lg leading-none" style={{ fontFamily: 'Galey, sans-serif' }}>
                    {mesAlertes.length}
                  </p>
                  <p className="text-white/70 text-xs">Alerte{mesAlertes.length > 1 ? 's' : ''}</p>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="max-w-6xl mx-auto px-4 py-6 space-y-8">
        {/* Bannière partenaires marketplace */}
        <MarketplaceBanner />

        {/* Mes Animaux */}
        {animaux.length > 0 && (
          <div>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-[#1F2A2E] flex items-center gap-2" style={{ fontFamily: 'Galey, sans-serif' }}>
                🐾 Mes Animaux
              </h2>
              <Link href="/mes-animaux" className="text-sm text-[#0C5C6C] font-medium hover:underline">
                Voir tout →
              </Link>
            </div>
            <div className="flex gap-3 overflow-x-auto pb-2 -mx-1 px-1">
              {animaux.map((a) => {
                const isMale = a.sexe?.toLowerCase().startsWith('m');
                const isFemale = a.sexe?.toLowerCase().startsWith('f');
                return (
                  <Link key={a.id} href={`/mes-animaux/${a.id}`}
                    className="flex-shrink-0 w-32 bg-white rounded-2xl overflow-hidden shadow-sm hover:shadow-md transition-shadow">
                    <div className="relative aspect-square bg-[#EAF4EC]">
                      {a.photo_url ? (
                        <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-3xl">
                          {SPECIES_EMOJI[a.espece ?? ''] ?? '🐾'}
                        </div>
                      )}
                      {(isMale || isFemale) && (
                        <span className={`absolute top-1.5 right-1.5 text-xs w-5 h-5 rounded-full flex items-center justify-center
                          ${isMale ? 'bg-blue-100 text-blue-700' : 'bg-pink-100 text-pink-700'}`}>
                          {isMale ? '♂' : '♀'}
                        </span>
                      )}
                    </div>
                    <div className="p-2">
                      <p className="font-bold text-[#1F2A2E] text-xs truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {a.nom ?? 'Sans nom'}
                      </p>
                      <p className="text-gray-400 text-[10px] truncate">
                        {a.race || a.espece || ''}
                      </p>
                    </div>
                  </Link>
                );
              })}
            </div>
          </div>
        )}

        {/* Accès rapide */}
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Link href="/animaux-perdus"
              className="bg-white border border-gray-100 rounded-2xl p-4 flex items-center gap-3 shadow-sm hover:shadow-md transition-shadow">
              <div className="w-12 h-12 bg-amber-50 rounded-xl flex items-center justify-center text-2xl flex-shrink-0">🔍</div>
              <span className="font-semibold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Animaux perdus</span>
            </Link>
            <Link href="/annonces"
              className="bg-white border border-gray-100 rounded-2xl p-4 flex items-center gap-3 shadow-sm hover:shadow-md transition-shadow">
              <div className="w-12 h-12 bg-[#E8F4F6] rounded-xl flex items-center justify-center text-2xl flex-shrink-0">📋</div>
              <span className="font-semibold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Annonces</span>
            </Link>
            {animaux.length === 0 && (
              <Link href="/mes-animaux"
                className="bg-white border border-gray-100 rounded-2xl p-4 flex items-center gap-3 shadow-sm hover:shadow-md transition-shadow">
                <div className="w-12 h-12 bg-[#EEF5EA] rounded-xl flex items-center justify-center text-2xl flex-shrink-0">🐾</div>
                <span className="font-semibold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Mes Animaux</span>
              </Link>
            )}
          </div>
          {/* Fil d'actualité — bouton pleine largeur */}
          <Link href="/annonces/feed"
            className="flex items-center gap-3 bg-white border border-gray-100 rounded-2xl p-4 shadow-sm hover:shadow-md transition-shadow">
            <div className="w-12 h-12 bg-[#EEF5EA] rounded-xl flex items-center justify-center text-2xl flex-shrink-0">▶️</div>
            <div className="flex-1">
              <p className="font-semibold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Fil d&apos;actualité</p>
              <p className="text-gray-400 text-xs">Parcourez les annonces en mode feed</p>
            </div>
            <span className="text-[#6E9E57] text-xl font-bold">›</span>
          </Link>
        </div>

        {/* Alerte banner */}
        {mesAlertes.length > 0 && (
          <Link href="/mes-alertes"
            className="flex items-center gap-4 bg-amber-50 border border-amber-300 rounded-2xl p-4 hover:bg-amber-100 transition-colors">
            <div className="w-10 h-10 rounded-full bg-amber-100 flex items-center justify-center flex-shrink-0 text-lg">
              🔍
            </div>
            <div className="flex-1">
              <p className="font-bold text-amber-800 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
                {mesAlertes.length} alerte{mesAlertes.length > 1 ? 's' : ''} active{mesAlertes.length > 1 ? 's' : ''}
              </p>
              <p className="text-amber-600 text-xs">
                {mesAlertes.length === 1 ? 'Gérer votre alerte' : 'Gérer vos alertes'}
              </p>
            </div>
            <span className="text-amber-400 text-lg">›</span>
          </Link>
        )}

        {/* Trouver un compagnon */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-lg font-bold text-[#1F2A2E] flex items-center gap-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              🐾 Trouver un compagnon
            </h2>
            <div className="flex items-center gap-2">
              <Link href="/annonces/carte" className="text-sm text-gray-500 font-medium hover:underline">🗺️ Carte</Link>
              <Link href="/annonces" className="text-sm text-[#0C5C6C] font-medium hover:underline">Voir tout →</Link>
            </div>
          </div>
          {annonces.length === 0 ? (
            <div className="bg-white border border-gray-100 rounded-2xl p-6 text-center">
              <p className="text-gray-400 text-sm">Aucune annonce disponible</p>
            </div>
          ) : (
            <div className="flex gap-3 overflow-x-auto pb-2 -mx-1 px-1">
              {annonces.map((a) => {
                const photos = (a.photos as string[] | undefined) ?? [];
                const isSaillie = a.type_vente === 'saillie';
                const isPortee  = a.type === 'portee';
                const titre = a.titre || `${a.espece ?? ''} ${a.race ?? ''}`.trim();
                const prix = isPortee
                  ? (a.prix_min_portee != null ? `dès ${a.prix_min_portee} €` : null)
                  : (a.prix != null ? `${a.prix} €` : null);
                return (
                  <Link key={a.id} href={`/annonces/${a.id}`}
                    className="flex-shrink-0 w-36 bg-white rounded-2xl overflow-hidden shadow-sm hover:shadow-md transition-shadow border border-gray-100">
                    <div className="relative aspect-square bg-[#EEF5EA]">
                      {photos[0] ? (
                        <img src={photos[0]} alt={titre} className="w-full h-full object-cover" />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-3xl">🐾</div>
                      )}
                      <span className={`absolute top-1.5 left-1.5 text-[9px] font-bold px-1.5 py-0.5 rounded-full text-white ${
                        isSaillie ? 'bg-purple-500' : isPortee ? 'bg-amber-500' : 'bg-[#6E9E57]'
                      }`}>
                        {isSaillie ? 'Saillie' : isPortee ? 'Portée' : 'Compagnon'}
                      </span>
                    </div>
                    <div className="p-2 space-y-0.5">
                      <p className="font-bold text-[#1F2A2E] text-xs truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{titre}</p>
                      {prix && <p className="text-[#0C5C6C] font-bold text-xs">{prix}</p>}
                      {a.ville_eleveur && <p className="text-gray-400 text-[10px] truncate">📍 {a.ville_eleveur}</p>}
                    </div>
                  </Link>
                );
              })}
            </div>
          )}
        </div>

        {/* Animaux perdus récents */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-lg font-bold text-[#1F2A2E] flex items-center gap-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              🔍 Animaux perdus
            </h2>
            <Link href="/animaux-perdus" className="text-sm text-amber-700 font-medium hover:underline">
              Voir tout →
            </Link>
          </div>

          {alertesPubliques.length === 0 ? (
            <div className="bg-white border border-amber-100 rounded-2xl p-6 text-center">
              <p className="text-gray-400 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
                Aucun animal perdu signalé
              </p>
            </div>
          ) : (
            <div className="flex gap-3 overflow-x-auto pb-2 -mx-1 px-1">
              {alertesPubliques.map((a) => {
                const colorClass = SPECIES_COLOR[a.espece ?? ''] ?? 'bg-amber-50 border-amber-200';
                return (
                  <Link key={a.id} href="/animaux-perdus"
                    className={`flex-shrink-0 w-36 bg-white border rounded-2xl overflow-hidden shadow-sm hover:shadow-md transition-shadow ${colorClass}`}>
                    <div className="h-20 bg-amber-50 overflow-hidden">
                      {a.photo_url ? (
                        <img src={a.photo_url} alt={a.nom_animal} className="w-full h-full object-cover" />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-3xl">
                          {SPECIES_EMOJI[a.espece ?? ''] ?? '🐾'}
                        </div>
                      )}
                    </div>
                    <div className="p-2 space-y-0.5">
                      <p className="font-bold text-[#1F2A2E] text-xs truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {a.nom_animal ?? 'Inconnu'}
                      </p>
                      <p className="text-gray-500 text-[10px] truncate">
                        {[a.espece, a.derniere_localisation].filter(Boolean).join(' · ')}
                      </p>
                      {a.date_perte && (
                        <p className="text-amber-600 text-[10px]">{formatDate(a.date_perte)}</p>
                      )}
                    </div>
                  </Link>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
