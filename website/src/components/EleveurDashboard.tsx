'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan, PLAN_CONFIG } from '@/lib/use-plan';
import MarketplaceBanner from './MarketplaceBanner';

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

const SPECIES_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

const QUICK_LINKS = [
  { href: '/mes-animaux',                    label: 'Mes Animaux',        icon: '🐾', bg: 'bg-[#EEF5EA]', border: 'border-[#6E9E57]/30', text: 'text-[#5A8A45]', pro: false },
  { href: '/mes-annonces',                   label: 'Mes Annonces',       icon: '📋', bg: 'bg-[#E8F4F6]', border: 'border-[#0C5C6C]/30', text: 'text-[#0C5C6C]', pro: false },
  { href: '/annonces/creer',                 label: 'Nouvelle annonce',   icon: '➕', bg: 'bg-[#EEF5EA]', border: 'border-[#6E9E57]/30', text: 'text-[#5A8A45]', pro: false },
  { href: '/animaux-perdus',                 label: 'Animaux perdus',     icon: '🔍', bg: 'bg-amber-50',  border: 'border-amber-200',    text: 'text-amber-700', pro: false },
  { href: '/elevage/profil',                  label: 'Mon profil élevage', icon: '🏡', bg: 'bg-[#EEF5EA]', border: 'border-[#6E9E57]/30', text: 'text-[#5A8A45]', pro: false },
  { href: '/elevage/agenda',                 label: 'Agenda du jour',     icon: '🗓️', bg: 'bg-[#E8F4F6]', border: 'border-[#0C5C6C]/30', text: 'text-[#0C5C6C]', pro: false },
  { href: '/elevage/planning',               label: 'Protocoles',         icon: '📅', bg: 'bg-[#EEF5EA]', border: 'border-[#6E9E57]/30', text: 'text-[#5A8A45]', pro: false },
  { href: '/elevage/registre-sanitaire',     label: 'Registre sanitaire', icon: '🏥', bg: 'bg-[#E8F4F6]', border: 'border-[#0C5C6C]/30', text: 'text-[#0C5C6C]', pro: true  },
  { href: '/elevage/registre-entree-sortie', label: 'Entrées / Sorties',  icon: '📂', bg: 'bg-[#E8F4F6]', border: 'border-[#0C5C6C]/30', text: 'text-[#0C5C6C]', pro: true  },
  { href: '/elevage/facturation',            label: 'Facturation',        icon: '🧾', bg: 'bg-[#EEF5EA]', border: 'border-[#6E9E57]/30', text: 'text-[#5A8A45]', pro: true  },
  { href: '/elevages',                       label: 'Élevages',           icon: '🏡', bg: 'bg-[#E8F4F6]', border: 'border-[#0C5C6C]/30', text: 'text-[#0C5C6C]', pro: false },
];

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

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      <div className="bg-gradient-to-br from-[#0C5C6C] to-[#5F9EAA] text-white">
        <div className="max-w-6xl mx-auto px-4 py-8 flex items-center gap-5">
          <Link href="/elevage/profil" className="flex-shrink-0">
            <div className="w-20 h-20 rounded-full bg-[#A7C79A] overflow-hidden flex items-center justify-center border-2 border-white/30">
              {avatar ? (
                <Image src={avatar} alt="" width={80} height={80} className="object-cover w-full h-full" />
              ) : (
                <span className="text-3xl">🐾</span>
              )}
            </div>
          </Link>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h1 className="text-xl font-bold truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                {displayName}
              </h1>
              {!planLoading && (
                <Link href="/abonnement"
                  className="flex items-center gap-1 text-xs font-bold px-2.5 py-0.5 rounded-full transition-opacity hover:opacity-80"
                  style={{ background: 'rgba(255,255,255,0.2)', color: 'white' }}>
                  {planConfig.badge} {planConfig.label}
                </Link>
              )}
            </div>
            {city && <p className="text-white/70 text-sm mt-0.5">📍 {city}</p>}
            <div className="mt-2 flex items-center gap-2 flex-wrap">
              <Link href="/elevage/profil"
                className="inline-flex items-center gap-1.5 text-xs border border-white/40 rounded-full px-3 py-1 hover:bg-white/10 transition-colors">
                🏡 Mon profil élevage
              </Link>
              {plan === 'free' && (
                <Link href="/abonnement"
                  className="inline-flex items-center gap-1.5 text-xs bg-white/20 rounded-full px-3 py-1 hover:bg-white/30 transition-colors font-semibold">
                  ⚡ Passer Pro
                </Link>
              )}
            </div>
          </div>
        </div>
      </div>

      <div className="max-w-6xl mx-auto px-4 py-6 space-y-8">
        {/* Bannière partenaires marketplace */}
        <MarketplaceBanner />

        <div className="grid grid-cols-3 gap-3">
          {[
            { value: animalCount, label: 'Animaux', icon: '🐾', href: '/mes-animaux' },
            { value: postCount,   label: 'Annonces', icon: '📋', href: '/mes-annonces' },
            { value: planConfig.badge + ' ' + planConfig.label, label: 'Plan', icon: null, href: '/abonnement' },
          ].map((s) => (
            <Link key={s.label} href={s.href} className="bg-white rounded-2xl p-4 flex flex-col items-center shadow-sm hover:shadow-md transition-shadow">
              {s.icon && <span className="text-xl mb-1">{s.icon}</span>}
              <span className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                {s.value}
              </span>
              <span className="text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>{s.label}</span>
            </Link>
          ))}
        </div>

        {/* Quota annonces */}
        {!planLoading && (
          <div className="bg-white rounded-2xl p-4 shadow-sm">
            <div className="flex items-center justify-between mb-2">
              <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Quota annonces
              </p>
              <Link href="/abonnement" className="text-xs text-[#0C5C6C] hover:underline">
                {plan === 'free' ? 'Augmenter ↗' : 'Gérer'}
              </Link>
            </div>
            {planConfig.maxAnnonces === -1 ? (
              <p className="text-sm text-[#6E9E57] font-semibold">✓ Illimité</p>
            ) : (
              <>
                <div className="flex items-center justify-between mb-1.5">
                  <span className="text-xs text-gray-500">{activeAnnonces} / {planConfig.maxAnnonces} annonces actives</span>
                  {activeAnnonces >= planConfig.maxAnnonces && (
                    <span className="text-xs font-semibold text-red-500">Limite atteinte</span>
                  )}
                </div>
                <div className="w-full bg-gray-100 rounded-full h-2">
                  <div
                    className={`h-2 rounded-full transition-all ${activeAnnonces >= planConfig.maxAnnonces ? 'bg-red-400' : 'bg-[#6E9E57]'}`}
                    style={{ width: `${Math.min(100, (activeAnnonces / planConfig.maxAnnonces) * 100)}%` }}
                  />
                </div>
                {plan === 'free' && activeAnnonces >= planConfig.maxAnnonces && (
                  <Link href="/abonnement"
                    className="mt-2 block text-center text-xs font-semibold bg-[#0C5C6C] text-white py-2 rounded-xl hover:bg-[#094F5D] transition-colors">
                    ⚡ Passer Pro pour plus d&apos;annonces
                  </Link>
                )}
              </>
            )}
          </div>
        )}

        {mesAlertes.length > 0 && (
          <Link href="/mes-alertes"
            className="flex items-center gap-4 bg-amber-50 border border-amber-300 rounded-2xl p-4 hover:bg-amber-100 transition-colors">
            <div className="w-10 h-10 rounded-full bg-amber-100 flex items-center justify-center flex-shrink-0">
              <span className="text-lg">🔍</span>
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

        <div>
          <h2 className="text-lg font-bold text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
            Accès rapide
          </h2>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {QUICK_LINKS.map((l) => {
              const locked = l.pro && !planConfig.hasRegistres;
              if (locked) {
                return (
                  <Link key={l.href} href="/abonnement"
                    className="relative bg-gray-50 border border-dashed border-gray-200 rounded-2xl p-4 flex flex-col gap-2 hover:border-[#0C5C6C]/30 transition-colors opacity-70">
                    <span className="text-2xl grayscale">{l.icon}</span>
                    <span className="text-sm font-semibold text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {l.label}
                    </span>
                    <span className="absolute top-2 right-2 text-xs bg-[#0C5C6C] text-white px-1.5 py-0.5 rounded-full font-bold">Pro</span>
                  </Link>
                );
              }
              return (
                <Link key={l.href} href={l.href}
                  className={`${l.bg} border ${l.border} rounded-2xl p-4 flex flex-col gap-2 hover:shadow-md transition-shadow`}>
                  <span className="text-2xl">{l.icon}</span>
                  <span className={`text-sm font-semibold ${l.text}`} style={{ fontFamily: 'Galey, sans-serif' }}>
                    {l.label}
                  </span>
                </Link>
              );
            })}
          </div>
        </div>

        <div>
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-lg font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Dernières annonces
            </h2>
            <Link href="/mes-annonces" className="text-sm text-[#0C5C6C] font-medium hover:underline">
              Voir tout →
            </Link>
          </div>

          {recentAnnonces.length === 0 ? (
            <div className="bg-white rounded-2xl p-8 flex flex-col items-center gap-3 shadow-sm">
              <span className="text-4xl text-gray-200">📋</span>
              <p className="text-gray-400 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Aucune annonce publiée</p>
              <Link href="/annonces/creer"
                className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-5 py-2.5 rounded-full transition-colors">
                Créer une annonce
              </Link>
            </div>
          ) : (
            <div className="space-y-2">
              {recentAnnonces.map((a) => {
                const title = a.titre || a.race || (a.espece ? (SPECIES_EMOJI[a.espece] + ' ' + a.espece) : 'Annonce');
                const photos = (a.photos as unknown as string[]) ?? [];
                const statut = a.statut ?? 'disponible';
                const statutLabel = statut === 'pause' ? 'En pause' : statut === 'reserve' ? 'Réservé' : 'En ligne';
                const statutColor = statut === 'pause' ? 'bg-gray-100 text-gray-500'
                  : statut === 'reserve' ? 'bg-amber-100 text-amber-700'
                  : 'bg-[#EEF5EA] text-[#5A8A45]';
                const dateStr = a.created_at ? new Date(a.created_at).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' }) : '';

                return (
                  <Link key={a.id} href={`/annonces/${a.id}`}
                    className="flex items-center gap-3 bg-white rounded-2xl p-3 shadow-sm hover:shadow-md transition-shadow">
                    <div className="w-14 h-14 rounded-xl overflow-hidden bg-[#EEF5EA] flex-shrink-0 flex items-center justify-center">
                      {photos[0] ? (
                        <img src={photos[0]} alt="" className="w-full h-full object-cover" />
                      ) : (
                        <span className="text-2xl">{SPECIES_EMOJI[a.espece ?? ''] ?? '🐾'}</span>
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold text-[#1F2A2E] text-sm truncate capitalize" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {title}
                      </p>
                      <div className="flex items-center gap-2 mt-1">
                        <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${statutColor}`}>
                          {statutLabel}
                        </span>
                        {(a.vues ?? 0) > 0 && (
                          <span className="text-xs text-gray-400">👁 {a.vues}</span>
                        )}
                      </div>
                    </div>
                    {dateStr && (
                      <span className="text-xs text-gray-400 flex-shrink-0">{dateStr}</span>
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
