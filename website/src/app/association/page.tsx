'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { Kpi, TitreRubrique, Icone, BORDURE, OMBRE } from '@/components/dashboard/kit';

interface Stats {
  total: number;
  enSoin: number;
  disponible: number;
  enFa: number;
  adopte: number;
  benevoles: number;
}

const STATUT_CONFIG: Record<string, { label: string; color: string }> = {
  en_soin:    { label: 'En soin',    color: 'bg-orange-100 text-orange-700' },
  disponible: { label: 'Disponible', color: 'bg-green-100 text-green-700' },
  en_fa:      { label: 'En FA',      color: 'bg-purple-100 text-purple-700' },
  adopte:     { label: 'Adopté',     color: 'bg-teal-100 text-teal-700' },
  transfere:  { label: 'Transféré',  color: 'bg-blue-100 text-blue-700' },
  decede:     { label: 'Décédé',     color: 'bg-red-100 text-red-700' },
};

export default function AssociationDashboard() {
  const { user, activeProfileId } = useAuth();
  const [stats, setStats] = useState<Stats>({ total: 0, enSoin: 0, disponible: 0, enFa: 0, adopte: 0, benevoles: 0 });
  const [recentAnimaux, setRecentAnimaux] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

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
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
      </div>
    );
  }

  return (
    <div className="space-y-6 font-galey">
      <h1 className="text-2xl font-bold text-[#1E2025]">Tableau de bord</h1>

      {/* Stats grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <Kpi label="Animaux total" valeur={stats.total} icone="patte" teinte="#0C5C6C" href="/association/animaux" />
        <Kpi label="Disponibles" valeur={stats.disponible} icone="coeur" teinte="#2F7D3A" href="/association/animaux?statut=disponible" />
        <Kpi label="En soin" valeur={stats.enSoin} icone="soin" teinte="#C2410C" href="/association/animaux?statut=en_soin" />
        <Kpi label="En famille d'accueil" valeur={stats.enFa} icone="maison" teinte="#7B5EA7" href="/association/animaux?statut=en_fa" />
        <Kpi label="Adoptés" valeur={stats.adopte} icone="valide" teinte="#2563EB" href="/association/animaux?statut=adopte" />
        <Kpi label="Équipe" valeur={stats.benevoles} icone="equipe" teinte="#0C5C6C" href="/association/equipe" />
      </div>

      {/* Animaux récents */}
      <div className={`bg-white rounded-2xl p-5 ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
        <TitreRubrique titre="Animaux récents" lien="/association/animaux" libelleLien="Voir tous" />
        {recentAnimaux.length === 0 ? (
          <p className="text-gray-400 text-sm text-center py-8">Aucun animal enregistré</p>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {recentAnimaux.map((a) => {
              const sc = STATUT_CONFIG[a.statut] ?? { label: a.statut, color: 'bg-gray-100 text-gray-600' };
              return (
                <Link key={a.id} href={`/association/animaux/${a.id}`}
                  className="flex items-center gap-3 p-3 rounded-xl border border-[#E5E8E6] hover:border-[#0C5C6C]/30 hover:bg-[#F4F9FA] transition-all">
                  <div className="w-11 h-11 rounded-full overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex-shrink-0">
                    {a.photo_url ? (
                      <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                    ) : (
                      <span className="w-full h-full flex items-center justify-center"><Icone nom="patte" taille={18} /></span>
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="font-semibold text-sm text-[#1E2025] truncate">{a.nom}</p>
                    <span className={`inline-block mt-1 text-xs font-semibold px-2 py-0.5 rounded-full ${sc.color}`}>{sc.label}</span>
                  </div>
                </Link>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
