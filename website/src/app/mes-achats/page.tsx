'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

interface Achat {
  id: string;
  annonce_id: string | null;
  statut: string;
  date_achat: string;
  date_expiration: string | null;
  produits_ponctuels: { label: string; prix: number; description: string | null } | null;
}

const STATUT_LABEL: Record<string, { label: string; color: string }> = {
  paye:       { label: 'Payé',    color: 'text-[#6E9E57] bg-[#6E9E57]/10' },
  rembourse:  { label: 'Remboursé', color: 'text-red-600 bg-red-50' },
  en_attente: { label: 'En attente', color: 'text-amber-600 bg-amber-50' },
};

export default function MesAchatsPage() {
  const { user, loading: authLoading } = useAuth();
  const [achats, setAchats] = useState<Achat[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('achats_ponctuels')
      .select('id, annonce_id, statut, date_achat, date_expiration, produits_ponctuels(label, prix, description)')
      .eq('uid', user.uid)
      .order('date_achat', { ascending: false })
      .then(({ data }) => {
        setAchats((data ?? []) as unknown as Achat[]);
        setLoading(false);
      });
  }, [user]);

  if (authLoading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }
  if (!user) {
    return <div className="text-center py-20 text-gray-400">Connectez-vous pour voir vos achats.</div>;
  }
  if (loading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/mes-annonces" className="text-gray-400 hover:text-[#0C5C6C] text-xl">←</Link>
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Mes achats</h1>
          <p className="text-xs text-gray-400">{achats.length} achat{achats.length !== 1 ? 's' : ''} (boosts, annonces supplémentaires…)</p>
        </div>
      </div>

      {achats.length === 0 ? (
        <div className="text-center py-16 text-gray-400 text-sm">Aucun achat pour le moment.</div>
      ) : (
        <div className="space-y-3">
          {achats.map(a => {
            const statut = STATUT_LABEL[a.statut] ?? { label: a.statut, color: 'text-gray-500 bg-gray-100' };
            const dateStr = new Date(a.date_achat).toLocaleDateString('fr-FR', { dateStyle: 'medium' });
            return (
              <div key={a.id} className="bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <p className="font-semibold text-[#1F2A2E] text-sm truncate">
                      {a.produits_ponctuels?.label ?? 'Achat'}
                    </p>
                    <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${statut.color}`}>
                      {statut.label}
                    </span>
                  </div>
                  <p className="text-xs text-gray-400">{dateStr}</p>
                  {a.annonce_id && (
                    <Link href={`/annonces/${a.annonce_id}`} className="text-xs text-[#0C5C6C] hover:underline">
                      Voir l&apos;annonce concernée →
                    </Link>
                  )}
                </div>
                <p className="font-bold text-[#0C5C6C] text-sm whitespace-nowrap">
                  {a.produits_ponctuels?.prix != null ? `${a.produits_ponctuels.prix.toFixed(2)} €` : ''}
                </p>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
