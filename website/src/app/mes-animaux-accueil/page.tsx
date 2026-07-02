'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface Animal {
  id: string;
  nom: string;
  espece?: string;
  race?: string;
  sexe?: string;
  statut?: string;
  photo_url?: string;
  description?: string;
  date_entree?: string;
  vaccines?: boolean;
  vermifuge?: boolean;
  identification?: boolean;
  sterilise?: boolean;
}

interface FaInfo {
  id: string;
  prenom: string;
  nom: string;
  capacite_max: number;
  association_uid: string;
}

export default function MesAnimauxAccueilPage() {
  const { user } = useAuth();
  const profileId = useActiveProfile();
  const [fa, setFa] = useState<FaInfo | null>(null);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const faQ = profileId
        ? supabase.from('familles_accueil').select('id, prenom, nom, capacite_max, association_uid').eq('fa_profile_id', profileId).eq('actif', true).limit(1)
        : supabase.from('familles_accueil').select('id, prenom, nom, capacite_max, association_uid').eq('fa_uid', user.uid).eq('actif', true).limit(1);
      const { data: faRows } = await faQ;
      if (!faRows || faRows.length === 0) { setLoading(false); return; }
      const faData = faRows[0] as FaInfo;
      setFa(faData);

      const { data: anim } = await supabase
        .from('animaux')
        .select('id, nom, espece, race, sexe, statut, photo_url, description, date_entree, vaccines, vermifuge, identification, sterilise')
        .eq('fa_id', faData.id);
      setAnimaux(anim ?? []);
      setLoading(false);
    })();
  }, [user, profileId]);

  if (loading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (!fa) {
    return (
      <div className="text-center py-24 text-gray-400 font-galey">
        <p className="text-5xl mb-4">🏡</p>
        <p className="text-lg">Vous n&apos;êtes pas famille d&apos;accueil</p>
        <p className="text-sm mt-2 text-gray-300">Si vous pensez que c&apos;est une erreur, contactez l&apos;association</p>
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
      {/* Bandeau FA */}
      <div className="bg-gradient-to-r from-teal-700 to-teal-600 rounded-2xl p-6 text-white">
        <p className="text-xs text-white/70 font-galey mb-1">Famille d&apos;accueil</p>
        <h1 className="text-2xl font-bold font-galey">{fa.prenom} {fa.nom}</h1>
        <p className="text-sm text-white/80 font-galey mt-1">
          {animaux.length} / {fa.capacite_max} animaux en accueil
        </p>
      </div>

      {animaux.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-2xl border border-gray-100 text-gray-400 font-galey">
          <p className="text-4xl mb-3">🐾</p>
          <p>Aucun animal en accueil pour le moment</p>
        </div>
      ) : (
        <div className="space-y-4">
          {animaux.map(a => (
            <div key={a.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
              {/* Photo */}
              {a.photo_url && (
                <div className="relative w-full h-48">
                  <Image src={a.photo_url} alt={a.nom} fill
                    className="object-cover" unoptimized />
                </div>
              )}
              <div className="p-5">
                <div className="flex items-start justify-between mb-2">
                  <div>
                    <h2 className="text-xl font-bold font-galey text-gray-900">{a.nom}</h2>
                    <p className="text-sm text-gray-500 font-galey capitalize">
                      {[a.espece, a.race, a.sexe].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                  {a.date_entree && (
                    <div className="bg-teal-50 text-teal-700 text-xs font-galey font-semibold px-3 py-1 rounded-full">
                      Depuis le {new Date(a.date_entree).toLocaleDateString('fr-FR')}
                    </div>
                  )}
                </div>

                {a.description && (
                  <p className="text-sm text-gray-700 font-galey leading-relaxed mb-4">
                    {a.description}
                  </p>
                )}

                {/* Santé */}
                <div className="flex flex-wrap gap-2">
                  {a.vaccines       && <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full font-galey font-semibold">Vacciné(e)</span>}
                  {a.vermifuge      && <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full font-galey font-semibold">Vermifugé(e)</span>}
                  {a.identification && <span className="text-xs bg-teal-100 text-teal-700 px-2 py-0.5 rounded-full font-galey font-semibold">Identifié(e)</span>}
                  {a.sterilise      && <span className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full font-galey font-semibold">Stérilisé(e)</span>}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
