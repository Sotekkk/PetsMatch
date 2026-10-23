'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { marquerAvertissementsVus } from '@/lib/avertissements';

// Avertissements : décisions de la modération sur le compte (miroir appli :
// Paramètres → Connexion et sécurité → Avertissements). La notification
// « moderation » ouvre cette page ; l'ouvrir retire la bulle rouge.

interface Sanction {
  id: string;
  type: 'suppression' | 'avertissement' | 'suspension' | 'blocage';
  regle: string;
  precisions: string | null;
  fin_le: string | null;
  leve_le: string | null;
  contenu: { extrait?: string } | null;
  created_at: string;
  vue_le?: string | null;
}

const dateFr = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) : '';

function libelle(s: Sanction): { titre: string; couleur: string; fond: string } {
  switch (s.type) {
    case 'suspension': {
      const terminee = !!s.leve_le || (!!s.fin_le && new Date(s.fin_le) < new Date());
      return { titre: terminee ? 'Suspension terminée' : `Compte suspendu jusqu’au ${dateFr(s.fin_le)}`, couleur: 'text-[#D97706]', fond: 'bg-[#FEF3C7]' };
    }
    case 'blocage': return { titre: 'Compte bloqué', couleur: 'text-red-600', fond: 'bg-red-50' };
    case 'suppression': return { titre: 'Contenu retiré', couleur: 'text-gray-500', fond: 'bg-gray-100' };
    default: return { titre: 'Avertissement', couleur: 'text-[#D97706]', fond: 'bg-[#FEF3C7]' };
  }
}

export default function AvertissementsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [sanctions, setSanctions] = useState<Sanction[]>([]);
  const [nouvelles, setNouvelles] = useState<Set<string>>(new Set());
  const [fetching, setFetching] = useState(true);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const champs = 'id, type, regle, precisions, fin_le, leve_le, contenu, created_at';
      const r = await supabase.from('sanctions_moderation').select(`${champs}, vue_le`)
        .eq('uid', user.uid).order('created_at', { ascending: false });
      // Sans la colonne vue_le (migration pas encore passée) : même liste, sans repère « Nouveau ».
      const data: unknown[] | null = r.error
        ? (await supabase.from('sanctions_moderation').select(champs)
            .eq('uid', user.uid).order('created_at', { ascending: false })).data
        : r.data;
      const liste = (data ?? []) as Sanction[];
      const nv = new Set(liste.filter(s => 'vue_le' in s && s.vue_le == null).map(s => s.id));
      setSanctions(liste);
      setNouvelles(nv);
      setFetching(false);
      if (nv.size) await marquerAvertissementsVus();
    })();
  }, [user]);

  if (loading || fetching) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="max-w-lg mx-auto px-4 py-8">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.back()} aria-label="Retour" className="p-2 rounded-full hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7"/>
          </svg>
        </button>
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Avertissements</h1>
      </div>

      <p className="text-sm text-[#0C5C6C] bg-[#E6F4F7] rounded-2xl px-4 py-3 mb-5">
        Les décisions de l’équipe de modération sur votre compte, avec la règle concernée.
        Pour contester une décision, utilisez « Poser une question » dans les paramètres.
      </p>

      {sanctions.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <p className="text-[#1F2A2E] font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun avertissement</p>
          <p className="text-gray-400 text-sm mt-1">Votre compte est en règle.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {sanctions.map(s => {
            const { titre, couleur, fond } = libelle(s);
            const nouveau = nouvelles.has(s.id);
            const extrait = s.contenu?.extrait?.trim();
            return (
              <div key={s.id} className={`bg-white rounded-2xl shadow-sm border px-4 py-4 ${nouveau ? 'border-red-200' : 'border-gray-100'}`}>
                <div className="flex items-center gap-3">
                  <div className={`w-9 h-9 rounded-xl ${fond} ${couleur} flex items-center justify-center flex-shrink-0`}>
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24" aria-hidden>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v4m0 4h.01M10.3 3.9L1.8 18a2 2 0 001.7 3h17a2 2 0 001.7-3L13.7 3.9a2 2 0 00-3.4 0z"/>
                    </svg>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-[#1F2A2E] text-[15px]" style={{ fontFamily: 'Galey, sans-serif' }}>{titre}</p>
                    <p className="text-xs text-gray-400">{dateFr(s.created_at)}</p>
                  </div>
                  {nouveau && <span className="text-[11px] font-bold text-white bg-red-500 rounded-full px-2 py-0.5">Nouveau</span>}
                </div>
                <p className="text-sm text-gray-600 mt-3"><strong className="text-[#1F2A2E]">Règle enfreinte : </strong>{s.regle}</p>
                {s.precisions && <p className="text-sm text-gray-600 mt-1.5">{s.precisions}</p>}
                {extrait && <p className="text-sm text-gray-500 italic bg-gray-50 rounded-xl px-3 py-2 mt-3 line-clamp-4">« {extrait} »</p>}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
