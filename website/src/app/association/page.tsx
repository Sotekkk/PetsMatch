'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

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
  const { user } = useAuth();
  const [stats, setStats] = useState<Stats>({ total: 0, enSoin: 0, disponible: 0, enFa: 0, adopte: 0, benevoles: 0 });
  const [recentAnimaux, setRecentAnimaux] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('animaux').select('statut').eq('uid_eleveur', user.uid).eq('is_association', true),
      supabase.from('employes').select('id').eq('uid_eleveur', user.uid).eq('actif', true),
      supabase.from('animaux').select('id, nom, espece, photo_url, statut, date_entree')
        .eq('uid_eleveur', user.uid).eq('is_association', true).order('date_entree', { ascending: false }).limit(6),
    ]).then(([{ data: animaux }, { data: benvl }, { data: recent }]) => {
      const list = animaux ?? [];
      setStats({
        total: list.length,
        enSoin: list.filter(a => a.statut === 'en_soin').length,
        disponible: list.filter(a => a.statut === 'disponible').length,
        enFa: list.filter(a => a.statut === 'en_fa').length,
        adopte: list.filter(a => a.statut === 'adopte').length,
        benevoles: (benvl ?? []).length,
      });
      setRecentAnimaux(recent ?? []);
      setLoading(false);
    });
  }, [user]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold font-galey text-teal-800">Tableau de bord</h1>

      {/* Stats grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <StatCard label="Animaux total" value={stats.total} color="teal" icon="🐾" />
        <StatCard label="Disponibles" value={stats.disponible} color="green" icon="💚" />
        <StatCard label="En soin" value={stats.enSoin} color="orange" icon="🏥" />
        <StatCard label="En famille d'accueil" value={stats.enFa} color="purple" icon="🏡" />
        <StatCard label="Adoptés" value={stats.adopte} color="blue" icon="🎉" />
        <StatCard label="Bénévoles actifs" value={stats.benevoles} color="teal" icon="🤝" />
      </div>

      {/* Animaux récents */}
      <div className="bg-white rounded-2xl shadow-sm p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold font-galey text-teal-800">Animaux récents</h2>
          <Link href="/association/animaux" className="text-sm text-teal-600 hover:underline">Voir tous →</Link>
        </div>
        {recentAnimaux.length === 0 ? (
          <p className="text-gray-400 text-sm text-center py-8">Aucun animal enregistré</p>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {recentAnimaux.map((a) => {
              const sc = STATUT_CONFIG[a.statut] ?? { label: a.statut, color: 'bg-gray-100 text-gray-600' };
              return (
                <Link key={a.id} href={`/association/animaux/${a.id}`}
                  className="flex items-center gap-3 p-3 rounded-xl border border-gray-100 hover:border-teal-200 hover:bg-teal-50/30 transition-all">
                  <div className="w-10 h-10 rounded-full overflow-hidden bg-gray-100 flex-shrink-0">
                    {a.photo_url ? (
                      <img src={a.photo_url} alt={a.nom} className="w-full h-full object-cover" />
                    ) : (
                      <span className="w-full h-full flex items-center justify-center text-lg">🐾</span>
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="font-semibold font-galey text-sm truncate">{a.nom}</p>
                    <span className={`text-xs px-2 py-0.5 rounded-full ${sc.color}`}>{sc.label}</span>
                  </div>
                </Link>
              );
            })}
          </div>
        )}
      </div>

      {/* Raccourcis */}
      <div className="bg-white rounded-2xl shadow-sm p-5">
        <h2 className="font-bold font-galey text-teal-800 mb-4">Actions rapides</h2>
        <div className="flex flex-wrap gap-3">
          <QuickLink href="/association/animaux" icon="🐾" label="Ajouter un animal" />
          <QuickLink href="/association/familles-accueil" icon="🏡" label="Gérer les FA" />
          <QuickLink href="/association/annonces" icon="📣" label="Déposer une annonce" />
          <QuickLink href="/association/certificat-engagement" icon="📋" label="Créer un certificat" />
          <QuickLink href="/association/chenil" icon="🗓️" label="Planning chenil" />
        </div>
      </div>
    </div>
  );
}

function StatCard({ label, value, color, icon }: { label: string; value: number; color: string; icon: string }) {
  const colorMap: Record<string, string> = {
    teal: 'bg-teal-50 border-teal-100',
    green: 'bg-green-50 border-green-100',
    orange: 'bg-orange-50 border-orange-100',
    purple: 'bg-purple-50 border-purple-100',
    blue: 'bg-blue-50 border-blue-100',
  };
  const valColor: Record<string, string> = {
    teal: 'text-teal-700', green: 'text-green-700', orange: 'text-orange-600',
    purple: 'text-purple-700', blue: 'text-blue-700',
  };
  return (
    <div className={`rounded-2xl p-4 border ${colorMap[color] ?? 'bg-gray-50 border-gray-100'}`}>
      <div className="flex items-center gap-2 mb-1">
        <span className="text-xl">{icon}</span>
        <p className="text-xs text-gray-500 font-galey">{label}</p>
      </div>
      <p className={`text-3xl font-bold font-galey ${valColor[color] ?? 'text-gray-700'}`}>{value}</p>
    </div>
  );
}

function QuickLink({ href, icon, label }: { href: string; icon: string; label: string }) {
  return (
    <Link href={href}
      className="flex items-center gap-2 px-4 py-2 bg-teal-50 text-teal-800 rounded-full text-sm font-galey font-semibold hover:bg-teal-100 transition-colors border border-teal-200">
      <span>{icon}</span>
      <span>{label}</span>
    </Link>
  );
}
