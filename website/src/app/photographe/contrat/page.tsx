'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// Contrats de prestation photo — un contrat par RDV (type='contrat_prestation_photo'),
// généré depuis l'agenda (RDV). Cette page ne fait que lister/rouvrir ce qui
// existe déjà, pas de création manuelle ici — même principe que côté appli
// (lib/pages/pro/photographe_contrats_page.dart).

interface DocContrat {
  id: string;
  type: string;
  titre: string;
  statut: 'brouillon' | 'en_attente' | 'signe' | 'archive' | 'partiellement_signe' | 'annule' | 'expire' | 'refuse';
  token: string | null;
  created_at: string;
  metadata: Record<string, string | number | null>;
  animaux: { nom: string; espece: string } | null;
}

const STATUT: Record<string, { label: string; cls: string }> = {
  brouillon:          { label: 'Brouillon',             cls: 'bg-gray-100 text-gray-500' },
  en_attente:         { label: '⏳ En attente',         cls: 'bg-amber-100 text-amber-700' },
  partiellement_signe:{ label: '✍️ Partiel',            cls: 'bg-blue-100 text-blue-700' },
  signe:              { label: '✅ Signé',              cls: 'bg-green-100 text-green-700' },
  archive:            { label: 'Archivé',               cls: 'bg-gray-100 text-gray-400' },
  annule:             { label: '🚫 Annulé',             cls: 'bg-red-100 text-red-500' },
  expire:             { label: '⏰ Expiré',             cls: 'bg-orange-100 text-orange-600' },
  refuse:             { label: '❌ Refusé',             cls: 'bg-red-100 text-red-700' },
};

export default function PhotographeContratPage() {
  const { user, loading } = useAuth();
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const [docs, setDocs] = useState<DocContrat[]>([]);
  const [fetching, setFetching] = useState(true);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setFetching(true);
    let q = supabase.from('documents_animaux')
      .select('id, type, titre, statut, token, created_at, metadata, animaux(nom, espece)')
      .eq('uid_eleveur', user.uid).eq('type', 'contrat_prestation_photo');
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId);
    const { data } = await q.order('created_at', { ascending: false });
    setDocs((data ?? []) as unknown as DocContrat[]);
    setFetching(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  if (loading || fetching) return (
    <div className="flex justify-center items-center min-h-[60vh]">
      <div className="w-8 h-8 border-2 border-[#90A4AE] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1F2A2E] font-galey">📄 Mes Contrats</h1>
        <p className="text-sm text-gray-500 mt-0.5">Contrats de prestation photo générés depuis vos RDV</p>
      </div>

      {docs.length === 0 ? (
        <div className="text-center py-16 border-2 border-dashed border-gray-200 rounded-2xl text-gray-400">
          <div className="text-5xl mb-3">📂</div>
          <p className="font-medium">Aucun contrat pour le moment</p>
          <p className="text-sm mt-1">Un contrat se génère depuis un RDV, dans l&apos;agenda.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {docs.map(doc => {
            const sm = STATUT[doc.statut] ?? STATUT.brouillon;
            const date = new Date(doc.created_at).toLocaleDateString('fr-FR');
            const clientNom = (doc.metadata?.client_nom as string | undefined) ?? 'Client';
            const signingUrl = doc.token ? `/signer-contrat/${doc.token}` : null;

            return (
              <a key={doc.id} href={signingUrl ?? '#'} target="_blank" rel="noopener noreferrer"
                className="block bg-white border border-gray-100 rounded-2xl p-4 shadow-sm space-y-2 hover:border-gray-200 transition-colors">
                <div className="flex items-start justify-between gap-3">
                  <p className="font-semibold text-[#1F2A2E] text-sm">{clientNom}</p>
                  <span className={`text-xs px-2 py-0.5 rounded-full font-medium shrink-0 ${sm.cls}`}>{sm.label}</span>
                </div>
                <div className="flex items-center gap-2 flex-wrap">
                  {doc.animaux && (
                    <span className="text-xs text-gray-500">{doc.animaux.nom} · {doc.animaux.espece}</span>
                  )}
                  <span className="text-xs text-gray-400">{date}</span>
                </div>
              </a>
            );
          })}
        </div>
      )}
    </div>
  );
}
