'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { Kpi, TitreRubrique, Icone, EnteteAccueil, BoutonPilule, Puce, BORDURE, OMBRE } from '@/components/dashboard/kit';

interface Stats {
  total: number;
  enSoin: number;
  disponible: number;
  enFa: number;
  adopte: number;
  benevoles: number;
}

// Couleurs de statut existantes, en accents discrets (texte / fond clair).
const STATUT_CONFIG: Record<string, { label: string; fg: string; bg: string }> = {
  en_soin:    { label: 'En soin',    fg: '#C2410C', bg: '#FFEDD5' },
  disponible: { label: 'Disponible', fg: '#15803D', bg: '#DCFCE7' },
  en_fa:      { label: 'En FA',      fg: '#7E22CE', bg: '#F3E8FF' },
  adopte:     { label: 'Adopté',     fg: '#0F766E', bg: '#CCFBF1' },
  transfere:  { label: 'Transféré',  fg: '#1D4ED8', bg: '#DBEAFE' },
  decede:     { label: 'Décédé',     fg: '#B91C1C', bg: '#FEE2E2' },
};

interface Identite { nom: string; avatar: string | null; ville: string }

export default function AssociationDashboard() {
  const { user, activeProfileId } = useAuth();
  const [stats, setStats] = useState<Stats>({ total: 0, enSoin: 0, disponible: 0, enFa: 0, adopte: 0, benevoles: 0 });
  const [recentAnimaux, setRecentAnimaux] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [identite, setIdentite] = useState<Identite>({ nom: '', avatar: null, ville: '' });

  // Identité de l'association (profil actif, sinon compte principal).
  useEffect(() => {
    if (!user) return;
    if (activeProfileId) {
      supabase.from('user_profiles_complet').select('nom, avatar_url, ville, ville_pro').eq('id', activeProfileId).maybeSingle()
        .then(({ data }) => setIdentite({
          nom: (data?.nom as string) || '',
          avatar: (data?.avatar_url as string) || null,
          ville: ((data?.ville_pro ?? data?.ville) as string) || '',
        }));
    } else {
      supabase.from('users_complet').select('name_elevage, firstname, lastname, profile_picture_url_elevage, profile_picture_url, ville_elevage, ville').eq('uid', user.uid).maybeSingle()
        .then(({ data }) => setIdentite({
          nom: (data?.name_elevage as string) || `${data?.firstname ?? ''} ${data?.lastname ?? ''}`.trim(),
          avatar: ((data?.profile_picture_url_elevage || data?.profile_picture_url) as string) || null,
          ville: ((data?.ville_elevage || data?.ville) as string) || '',
        }));
    }
  }, [user, activeProfileId]);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('animaux').select('statut, fa_id').eq('uid_eleveur', user.uid).eq('is_association', true),
      // Équipe (miroir appli) : employés + bénévoles actifs du profil association.
      (activeProfileId
        ? supabase.from('employes').select('id').eq('eleveur_profile_id', activeProfileId)
        : supabase.from('employes').select('id').eq('uid_eleveur', user.uid))
        .eq('actif', true).eq('profil_source', 'association'),
      supabase.from('animaux').select('id, nom, espece, photo_url, statut')
        .eq('uid_eleveur', user.uid).eq('is_association', true).order('created_at', { ascending: false }).limit(6),
    ]).then(([{ data: animaux }, { data: benvl }, { data: recent }]) => {
      const list = animaux ?? [];
      setStats({
        total: list.length,
        enSoin: list.filter((a: { statut: string }) => a.statut === 'en_soin').length,
        disponible: list.filter((a: { statut: string }) => a.statut === 'disponible').length,
        enFa: list.filter((a: { fa_id: string | null }) => !!a.fa_id).length,
        adopte: list.filter((a: { statut: string }) => a.statut === 'adopte').length,
        benevoles: (benvl ?? []).length,
      });
      setRecentAnimaux(recent ?? []);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, [user, activeProfileId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const carte = `bg-white rounded-2xl ${OMBRE}`;

  return (
    <div className="bg-[#F6F7F5] min-h-screen" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 sm:py-8 space-y-6">
        <EnteteAccueil
          nom={identite.nom || 'Mon association'}
          avatar={identite.avatar}
          avatarHref="/profil"
          sousTitre="Association / Refuge"
          lieu={identite.ville || undefined}
          actions={<BoutonPilule href="/profil" icone="reglages">Modifier mon profil</BoutonPilule>}
        />

        <div className="grid grid-cols-3 gap-3 sm:gap-4">
          <Kpi label="Animaux total" valeur={stats.total} icone="patte" teinte="#0C5C6C" href="/association/animaux" />
          <Kpi label="Disponibles" valeur={stats.disponible} icone="coeur" teinte="#15803D" href="/association/animaux?statut=disponible" />
          <Kpi label="En soin" valeur={stats.enSoin} icone="soin" teinte="#C2410C" href="/association/animaux?statut=en_soin" />
          <Kpi label="En famille d'accueil" valeur={stats.enFa} icone="maison" teinte="#7E22CE" href="/association/animaux?statut=en_fa" />
          <Kpi label="Adoptés" valeur={stats.adopte} icone="valide" teinte="#0F766E" href="/association/animaux?statut=adopte" />
          <Kpi label="Équipe" valeur={stats.benevoles} icone="equipe" teinte="#0C5C6C" href="/association/equipe" />
        </div>

        <div>
          <TitreRubrique titre="Animaux récents" lien="/association/animaux" libelleLien="Voir tous" />
          {recentAnimaux.length === 0 ? (
            <div className={`${carte} p-8 flex flex-col items-center gap-3`} style={{ border: `1px solid ${BORDURE}` }}>
              <span className="w-12 h-12 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom="patte" taille={22} /></span>
              <p className="text-gray-500 text-sm">Aucun animal enregistré</p>
            </div>
          ) : (
            <div className="space-y-2.5">
              {recentAnimaux.map((a) => {
                const sc = STATUT_CONFIG[a.statut] ?? { label: a.statut ?? '', fg: '#6B7280', bg: '#F3F4F6' };
                return (
                  <Link key={a.id} href={`/association/animaux/${a.id}`}
                    className={`${carte} flex items-center gap-3 sm:gap-4 p-3 hover:shadow-md transition-shadow`}
                    style={{ border: `1px solid ${BORDURE}` }}>
                    <div className="w-14 h-14 sm:w-16 sm:h-16 rounded-xl overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex-shrink-0 flex items-center justify-center">
                      {a.photo_url
                        // eslint-disable-next-line @next/next/no-img-element
                        ? <img src={a.photo_url} alt="" className="w-full h-full object-cover" />
                        : <Icone nom="patte" taille={24} />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold text-[#1E2025] text-[15px] truncate">{a.nom}</p>
                      <div className="flex items-center gap-3 mt-1.5 min-w-0">
                        {sc.label && <Puce texte={sc.label} fg={sc.fg} bg={sc.bg} point />}
                        {a.espece && <span className="text-xs text-gray-500 capitalize truncate">{a.espece}</span>}
                      </div>
                    </div>
                    <Icone nom="fleche" taille={18} className="text-gray-400 flex-shrink-0" />
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
