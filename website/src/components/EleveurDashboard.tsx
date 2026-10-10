'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';
import { Kpi, EnteteAccueil, Puce, BoutonPilule, TitreRubrique, Icone, BORDURE, OMBRE } from '@/components/dashboard/kit';

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  photos?: string[];
  statut?: string;
  vues?: number;
  created_at?: string;
}

export default function EleveurDashboard() {
  const { user, userData, loading: authLoading, activeProfileId } = useAuth();
  const { plan, config: planConfig, activeAnnonces, loading: planLoading } = usePlan();
  const [animalCount, setAnimalCount] = useState(0);
  const [mesAlertes, setMesAlertes] = useState<{ id: string }[]>([]);
  const [postCount, setPostCount] = useState(0);
  const [recentAnnonces, setRecentAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);

  const displayName = userData?.nameElevage ?? userData?.firstname ?? 'Mon élevage';
  const city = userData?.villeElevage ?? userData?.ville ?? '';
  const avatar = userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl ?? null;

  useEffect(() => {
    if (!user || authLoading) return;
    const uid = user.uid;

    async function loadCount() {
      let count = 0;
      if (activeProfileId) {
        const { data: check } = await supabase
          .from('animaux_proprietes').select('animal_id')
          .eq('uid_proprio', uid).not('profile_id_proprio', 'is', null).limit(1);
        if ((check ?? []).length > 0) {
          const { count: c } = await supabase
            .from('animaux_proprietes')
            .select('animal_id', { count: 'exact', head: true })
            .eq('uid_proprio', uid).eq('profile_id_proprio', activeProfileId).is('date_fin', null);
          count = c ?? 0;
        } else {
          const { count: c } = await supabase
            .from('animaux_proprietes')
            .select('animal_id', { count: 'exact', head: true })
            .eq('uid_proprio', uid).is('date_fin', null);
          count = c ?? 0;
        }
      } else {
        const { count: c } = await supabase
          .from('animaux_proprietes')
          .select('animal_id', { count: 'exact', head: true })
          .eq('uid_proprio', uid).is('date_fin', null);
        count = c ?? 0;
      }
      const { data: alertes } = await supabase
        .from('alertes_perdus').select('id').eq('uid_proprietaire', uid).eq('statut', 'perdu');
      setAnimalCount(count);
      setMesAlertes((alertes ?? []) as { id: string }[]);
      setLoading(false);
    }

    loadCount().catch(() => setLoading(false));
  }, [user, authLoading, activeProfileId]);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('annonces')
      .select('id, titre, espece, race, photos, statut, vues, created_at')
      .eq('uid_eleveur', user.uid)
      .in('statut', ['disponible', 'reserve', 'pause'])
      .order('created_at', { ascending: false })
      .limit(10)
      .then(({ data }) => {
        const docs = (data ?? []) as Annonce[];
        setPostCount(docs.filter(d => ['disponible', 'reserve'].includes(d.statut ?? '')).length);
        setRecentAnnonces(docs.slice(0, 3));
      });
  }, [user]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <div className="w-8 h-8 border-2 border-[#6E9E57] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const planIcone = plan === 'premium' ? 'couronne' : plan === 'pro' ? 'etoile' : 'valide';
  const carte = `bg-white rounded-2xl ${OMBRE}`;

  return (
    <div className="bg-[#F6F7F5] min-h-screen" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 sm:py-8 space-y-6">
        <EnteteAccueil
          nom={displayName}
          avatar={avatar}
          avatarHref="/elevage/profil"
          lieu={city || undefined}
          statut={!planLoading && (
            <Puce texte={planConfig.label} fg={planConfig.color} bg={planConfig.bg} icone={planIcone} href="/abonnement" />
          )}
          actions={<>
            <BoutonPilule href="/elevage/profil" icone="reglages">Mon profil élevage</BoutonPilule>
            {plan === 'free' && <BoutonPilule href="/abonnement" contour>Passer Pro</BoutonPilule>}
          </>}
        />

        <div className="grid grid-cols-3 gap-3 sm:gap-4">
          <Kpi valeur={animalCount} label="Animaux" icone="patte" href="/mes-animaux" />
          <Kpi valeur={postCount} label="Annonces" icone="document" href="/mes-annonces" />
          <Kpi valeur={planConfig.label} label="Plan" icone={planIcone} teinte={planConfig.color} href="/abonnement" />
        </div>

        {mesAlertes.length > 0 && (
          <Link href="/mes-alertes"
            className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md transition-shadow"
            style={{ border: '1px solid #F3D9A4' }}>
            <span className="w-10 h-10 rounded-full bg-amber-50 text-amber-700 flex items-center justify-center flex-shrink-0">
              <Icone nom="recherche" />
            </span>
            <div className="flex-1 min-w-0">
              <p className="font-bold text-[#1E2025] text-sm">
                {mesAlertes.length} alerte{mesAlertes.length > 1 ? 's' : ''} active{mesAlertes.length > 1 ? 's' : ''}
              </p>
              <p className="text-gray-600 text-xs">
                {mesAlertes.length === 1 ? 'Gérer votre alerte' : 'Gérer vos alertes'}
              </p>
            </div>
            <Icone nom="fleche" taille={18} className="text-gray-400" />
          </Link>
        )}

        <div>
          <TitreRubrique titre="Dernières annonces" lien="/mes-annonces" />

          {recentAnnonces.length === 0 ? (
            <div className={`${carte} p-8 flex flex-col items-center gap-3`} style={{ border: `1px solid ${BORDURE}` }}>
              <span className="w-12 h-12 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom="document" taille={22} /></span>
              <p className="text-gray-500 text-sm">Aucune annonce publiée</p>
              <Link href="/annonces/creer"
                className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-5 py-2.5 rounded-full transition-colors">
                Créer une annonce
              </Link>
            </div>
          ) : (
            <div className="space-y-2.5">
              {recentAnnonces.map((a) => {
                const title = a.titre || a.race || a.espece || 'Annonce';
                const photos = (a.photos as unknown as string[]) ?? [];
                const statut = a.statut ?? 'disponible';
                const statutLabel = statut === 'pause' ? 'En pause' : statut === 'reserve' ? 'Réservé' : 'En ligne';
                const [fg, bg] = statut === 'pause' ? ['#6B7280', '#F3F4F6']
                  : statut === 'reserve' ? ['#B45309', '#FEF3C7']
                  : ['#2F7D3A', '#EAF5EC'];
                const dateStr = a.created_at ? new Date(a.created_at).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' }) : '';

                return (
                  <Link key={a.id} href={`/annonces/${a.id}`}
                    className={`${carte} flex items-center gap-3 sm:gap-4 p-3 hover:shadow-md transition-shadow`}
                    style={{ border: `1px solid ${BORDURE}` }}>
                    <div className="w-14 h-14 sm:w-16 sm:h-16 rounded-xl overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex-shrink-0 flex items-center justify-center">
                      {photos[0] ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={photos[0]} alt="" className="w-full h-full object-cover" />
                      ) : (
                        <Icone nom="patte" taille={24} />
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold text-[#1E2025] text-[15px] truncate capitalize">{title}</p>
                      <div className="flex items-center gap-3 mt-1.5">
                        <Puce texte={statutLabel} fg={fg} bg={bg} point />
                        {(a.vues ?? 0) > 0 && (
                          <span className="inline-flex items-center gap-1 text-xs text-gray-500 tabular-nums">
                            <Icone nom="oeil" taille={14} />{a.vues}
                          </span>
                        )}
                      </div>
                    </div>
                    {dateStr && (
                      <span className="text-xs text-gray-500 tabular-nums flex-shrink-0 self-center">{dateStr}</span>
                    )}
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
