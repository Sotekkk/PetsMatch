'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan, PLAN_CONFIG } from '@/lib/use-plan';

const TYPE_LABELS: Record<string, string> = {
  restaurant: 'Restaurant',
  hotel: 'Hôtel pet-friendly',
  cafe: 'Café / Salon de thé',
  bar: 'Bar / Brasserie',
  fast_food: 'Restauration rapide',
  boulangerie: 'Boulangerie / Pâtisserie',
  gite: 'Gîte / Chambre d\'hôtes',
  hebergement_insolite: 'Hébergement insolite',
  camping: 'Camping',
  villa_location: 'Location saisonnière',
};

interface Place {
  id: string;
  nom?: string;
  vue_count?: number;
  nb_avis?: number;
  note_moyenne?: number;
  statut?: string;
}

interface Avis {
  id: string;
  note?: number;
  commentaire?: string;
  created_at?: string;
}

interface Profile {
  nom?: string;
  ville_pro?: string;
  type_restauration?: string;
  avatar_url?: string;
  banner_url?: string;
  verification_status?: string;
}

const QUICK_LINKS = [
  { href: '/mes-etablissements',          label: 'Mes établissements',    icon: '🏪' },
  { href: '/restauration/profil',         label: 'Mon profil',            icon: '🏡' },
  { href: '/abonnement',                  label: 'Mon abonnement',        icon: '⭐' },
  { href: '/notifications',               label: 'Notifications',         icon: '🔔' },
];

export default function RestaurationDashboard() {
  const { user, loading: authLoading } = useAuth();
  const { config: planConfig, loading: planLoading } = usePlan();

  const [profile, setProfile]         = useState<Profile | null>(null);
  const [places, setPlaces]           = useState<Place[]>([]);
  const [recentAvis, setRecentAvis]   = useState<Avis[]>([]);
  const [loading, setLoading]         = useState(true);

  useEffect(() => {
    if (!user || authLoading) return;

    async function load() {
      const uid = user!.uid;

      const [profileRes, placesRes] = await Promise.all([
        supabase
          .from('user_profiles')
          .select('nom, ville_pro, type_restauration, avatar_url, banner_url, verification_status')
          .eq('uid', uid)
          .eq('cat_pro', 'restauration')
          .maybeSingle(),
        supabase
          .from('petfriendly_places')
          .select('id, nom, vue_count, nb_avis, note_moyenne, statut')
          .eq('uid_pro', uid),
      ]);

      setProfile(profileRes.data as Profile | null);
      const placesList = (placesRes.data ?? []) as Place[];
      setPlaces(placesList);

      if (placesList.length > 0) {
        const ids = placesList.map(p => p.id);
        const { data: avisData } = await supabase
          .from('petfriendly_reviews')
          .select('id, note, commentaire, created_at')
          .in('place_id', ids)
          .order('created_at', { ascending: false })
          .limit(3);
        setRecentAvis((avisData ?? []) as Avis[]);
      }

      setLoading(false);
    }

    load().catch(() => setLoading(false));
  }, [user, authLoading]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const vuesTotales  = places.reduce((s, p) => s + (p.vue_count ?? 0), 0);
  const nbAvis       = places.reduce((s, p) => s + (p.nb_avis ?? 0), 0);
  const noteMoyenne  = nbAvis > 0
    ? places.reduce((s, p) => s + ((p.note_moyenne ?? 0) * (p.nb_avis ?? 0)), 0) / nbAvis
    : 0;
  const verifStatus  = profile?.verification_status ?? 'none';
  const nomEtabl     = profile?.nom ?? 'Mon établissement';
  const typeLabel    = TYPE_LABELS[profile?.type_restauration ?? ''] ?? 'Hébergement / Restauration';
  const avatar       = profile?.avatar_url ?? null;
  const banner       = profile?.banner_url ?? null;

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      {/* Header */}
      <div className="relative bg-gradient-to-br from-[#0C5C6C] to-[#5F9EAA] text-white">
        {banner && (
          <div className="absolute inset-0">
            <Image src={banner} alt="" fill className="object-cover opacity-30" />
          </div>
        )}
        <div className="relative max-w-4xl mx-auto px-4 py-8 flex items-center gap-5">
          <div className="w-20 h-20 rounded-full bg-[#A7C79A] overflow-hidden flex-shrink-0 flex items-center justify-center border-2 border-white/30">
            {avatar ? (
              <Image src={avatar} alt="" width={80} height={80} className="object-cover w-full h-full" />
            ) : (
              <span className="text-3xl">🏡</span>
            )}
          </div>
          <div className="flex-1 min-w-0">
            <h1 className="text-xl font-bold truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
              {nomEtabl}
            </h1>
            <p className="text-white/70 text-sm">{typeLabel}</p>
            {profile?.ville_pro && (
              <p className="text-white/60 text-xs mt-0.5">📍 {profile.ville_pro}</p>
            )}
            <div className="mt-2 flex gap-2 flex-wrap">
              {!planLoading && (
                <Link href="/abonnement"
                  className="inline-flex items-center gap-1 text-xs font-bold px-2.5 py-0.5 rounded-full hover:opacity-80 transition-opacity"
                  style={{ background: 'rgba(255,255,255,0.2)' }}>
                  {planConfig.badge} {planConfig.label}
                </Link>
              )}
              <Link href="/restauration/profil"
                className="inline-flex items-center gap-1.5 text-xs border border-white/40 rounded-full px-3 py-1 hover:bg-white/10 transition-colors">
                ✏️ Mon profil
              </Link>
            </div>
          </div>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">
        {/* Bannière validation */}
        <ValidationBanner status={verifStatus} />

        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          {[
            { value: places.length, label: 'Établissements', icon: '🏪', href: '/mes-etablissements' },
            { value: vuesTotales,   label: 'Vues totales',   icon: '👀', href: null },
            { value: nbAvis > 0 ? `${noteMoyenne.toFixed(1)} ⭐` : '–',
              label: `${nbAvis} avis`, icon: null, href: null },
          ].map((s) => (
            <StatCard key={s.label} {...s} />
          ))}
        </div>

        {/* Accès rapide */}
        <div>
          <h2 className="text-lg font-bold text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
            Accès rapide
          </h2>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {QUICK_LINKS.map((l) => (
              <Link key={l.href} href={l.href}
                className="bg-white rounded-2xl p-4 flex flex-col items-center gap-2 shadow-sm hover:shadow-md transition-shadow">
                <span className="text-2xl">{l.icon}</span>
                <span className="text-xs font-semibold text-[#0C5C6C] text-center"
                  style={{ fontFamily: 'Galey, sans-serif' }}>{l.label}</span>
              </Link>
            ))}
          </div>
        </div>

        {/* Mes établissements */}
        {places.length > 0 && (
          <div>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Mes établissements
              </h2>
              <Link href="/mes-etablissements" className="text-sm text-[#0C5C6C] hover:underline">
                Voir tout →
              </Link>
            </div>
            <div className="space-y-2">
              {places.slice(0, 3).map(p => (
                <Link key={p.id} href={`/lieux/${p.id}`}
                  className="flex items-center gap-3 bg-white rounded-2xl p-3 shadow-sm hover:shadow-md transition-shadow">
                  <div className="w-10 h-10 rounded-xl bg-[#E8F4F6] flex items-center justify-center flex-shrink-0">
                    <span className="text-xl">🏪</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-[#1F2A2E] text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {p.nom ?? 'Établissement'}
                    </p>
                    <p className="text-xs text-gray-400">
                      {p.vue_count ?? 0} vues · {p.nb_avis ?? 0} avis
                      {p.nb_avis ? ` · ${(p.note_moyenne ?? 0).toFixed(1)} ⭐` : ''}
                    </p>
                  </div>
                  <StatusBadge statut={p.statut} />
                </Link>
              ))}
            </div>
          </div>
        )}

        {/* Avis récents */}
        {recentAvis.length > 0 && (
          <div>
            <h2 className="text-lg font-bold text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
              Avis récents
            </h2>
            <div className="space-y-2">
              {recentAvis.map(a => (
                <div key={a.id} className="bg-white rounded-2xl p-4 shadow-sm">
                  <div className="flex items-center justify-between mb-1">
                    <div className="flex gap-0.5">
                      {Array.from({ length: 5 }, (_, i) => (
                        <span key={i} className={`text-sm ${i < (a.note ?? 0) ? 'text-amber-400' : 'text-gray-200'}`}>★</span>
                      ))}
                    </div>
                    {a.created_at && (
                      <span className="text-xs text-gray-400">
                        {new Date(a.created_at).toLocaleDateString('fr-FR')}
                      </span>
                    )}
                  </div>
                  {a.commentaire && (
                    <p className="text-sm text-gray-600 line-clamp-2">{a.commentaire}</p>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* CTA premier établissement */}
        {places.length === 0 && verifStatus === 'approved' && (
          <div className="bg-white rounded-2xl p-8 flex flex-col items-center gap-3 shadow-sm">
            <span className="text-4xl">🏪</span>
            <p className="text-[#1F2A2E] font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
              Créez votre premier établissement
            </p>
            <p className="text-gray-400 text-sm text-center">
              Ajoutez votre restaurant, hôtel ou café pour être visible par la communauté PetsMatch.
            </p>
            <Link href="/mes-etablissements/creer"
              className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-5 py-2.5 rounded-full transition-colors">
              Créer un établissement
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}

// ── Sous-composants ──────────────────────────────────────────────────────────

function ValidationBanner({ status }: { status: string }) {
  if (status === 'approved') return null;

  const configs: Record<string, { bg: string; text: string; icon: string; titre: string; sub: string; href?: string }> = {
    none: {
      bg: 'bg-amber-50 border border-amber-200',
      text: 'text-amber-800',
      icon: '📝',
      titre: 'Complétez votre profil',
      sub: 'Ajoutez vos informations pour soumettre votre dossier à l\'équipe PetsMatch.',
      href: '/restauration/profil',
    },
    pending: {
      bg: 'bg-blue-50 border border-blue-200',
      text: 'text-blue-800',
      icon: '⏳',
      titre: 'Dossier en cours d\'examen',
      sub: 'Notre équipe vérifie votre profil (SIRET, activité…). Vous serez notifié sous 48h.',
    },
    rejected: {
      bg: 'bg-red-50 border border-red-200',
      text: 'text-red-800',
      icon: '❌',
      titre: 'Profil refusé',
      sub: 'Contactez support@petsmatch.fr pour comprendre la raison du refus.',
    },
  };

  const c = configs[status] ?? configs.pending;

  const inner = (
    <div className={`rounded-2xl p-4 flex items-start gap-3 ${c.bg}`}>
      <span className="text-2xl flex-shrink-0">{c.icon}</span>
      <div>
        <p className={`font-bold text-sm ${c.text}`} style={{ fontFamily: 'Galey, sans-serif' }}>{c.titre}</p>
        <p className={`text-xs mt-0.5 ${c.text} opacity-80`}>{c.sub}</p>
      </div>
      {c.href && <span className={`ml-auto ${c.text} text-sm`}>›</span>}
    </div>
  );

  return c.href
    ? <Link href={c.href}>{inner}</Link>
    : inner;
}

function StatCard({ value, label, icon, href }: { value: string | number; label: string; icon: string | null; href: string | null }) {
  const inner = (
    <div className="bg-white rounded-2xl p-4 flex flex-col items-center shadow-sm hover:shadow-md transition-shadow h-full">
      {icon && <span className="text-xl mb-1">{icon}</span>}
      <span className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
        {value}
      </span>
      <span className="text-xs text-gray-400 text-center" style={{ fontFamily: 'Galey, sans-serif' }}>{label}</span>
    </div>
  );
  return href
    ? <Link href={href} className="block">{inner}</Link>
    : <div>{inner}</div>;
}

function StatusBadge({ statut }: { statut?: string }) {
  const m: Record<string, { label: string; cls: string }> = {
    actif:                { label: 'En ligne',    cls: 'bg-[#EEF5EA] text-[#5A8A45]' },
    en_attente_validation:{ label: 'En attente',  cls: 'bg-amber-100 text-amber-700' },
    ferme:                { label: 'Fermé',       cls: 'bg-gray-100 text-gray-500' },
    suspendu:             { label: 'Suspendu',    cls: 'bg-red-100 text-red-600' },
  };
  const cfg = m[statut ?? ''] ?? { label: statut ?? '', cls: 'bg-gray-100 text-gray-500' };
  return (
    <span className={`text-xs font-semibold px-2 py-0.5 rounded-full flex-shrink-0 ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}
