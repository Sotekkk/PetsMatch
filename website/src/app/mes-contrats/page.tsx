'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface DocRow {
  id: string;
  type: string;
  titre: string;
  statut: 'brouillon' | 'en_attente' | 'signe' | 'archive';
  token: string | null;
  signe_le: string | null;
  created_at: string;
  metadata: Record<string, string | number | boolean | null>;
  animaux: { nom: string; espece: string } | null;
}

const TYPE_LABEL: Record<string, string> = {
  contrat_vente:       '🤝 Contrat de vente',
  contrat_reservation: '🐾 Contrat de réservation',
  certificat_cession:  '📋 Certificat de cession',
};

const STATUT: Record<string, { label: string; cls: string }> = {
  brouillon:  { label: 'Brouillon',             cls: 'bg-gray-100 text-gray-500' },
  en_attente: { label: '⏳ En attente de signature', cls: 'bg-amber-100 text-amber-700' },
  signe:      { label: '✅ Signé',              cls: 'bg-green-100 text-green-700' },
  archive:    { label: 'Archivé',               cls: 'bg-gray-100 text-gray-400' },
};

export default function MesContratsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [docs, setDocs] = useState<DocRow[]>([]);
  const [fetching, setFetching] = useState(true);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user?.email) return;
    supabase
      .from('documents_animaux')
      .select('id, type, titre, statut, token, signe_le, created_at, metadata, animaux(nom, espece)')
      .filter('metadata->>acquereur_email', 'eq', user.email)
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setDocs((data ?? []) as unknown as DocRow[]);
        setFetching(false);
      });
  }, [user?.email]);

  if (loading || fetching) return (
    <div className="flex justify-center items-center min-h-[60vh]">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1F2A2E] font-galey">📄 Mes Contrats</h1>
        <p className="text-sm text-gray-500 mt-0.5">Contrats et documents en attente de votre signature</p>
      </div>

      {docs.length === 0 ? (
        <div className="text-center py-16 border-2 border-dashed border-gray-200 rounded-2xl text-gray-400">
          <div className="text-5xl mb-3">📂</div>
          <p className="font-medium">Aucun contrat pour le moment</p>
          <p className="text-sm mt-1">Les contrats transmis par un éleveur apparaîtront ici</p>
        </div>
      ) : (
        <div className="space-y-3">
          {docs.map(doc => {
            const sm = STATUT[doc.statut] ?? STATUT.brouillon;
            const date = new Date(doc.created_at).toLocaleDateString('fr-FR');
            const animal = doc.animaux;
            const signingUrl = doc.token ? `/signer-contrat/${doc.token}` : null;

            return (
              <div key={doc.id} className="bg-white border border-gray-100 rounded-2xl p-4 shadow-sm space-y-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-[#1F2A2E] text-sm">
                      {TYPE_LABEL[doc.type] ?? '📄 Document'}
                    </p>
                    {animal && (
                      <p className="text-xs text-gray-500 mt-0.5">
                        {animal.nom} · {animal.espece}
                      </p>
                    )}
                    <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                      <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${sm.cls}`}>{sm.label}</span>
                      <span className="text-xs text-gray-400">{date}</span>
                      {doc.signe_le && (
                        <span className="text-xs text-green-600">
                          le {new Date(doc.signe_le).toLocaleDateString('fr-FR')}
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {signingUrl && doc.statut !== 'signe' && (
                  <a href={signingUrl} target="_blank" rel="noopener noreferrer"
                    className="flex items-center justify-center gap-2 w-full bg-[#0C5C6C] hover:bg-[#0a4f5e] text-white text-sm font-semibold py-2.5 rounded-xl transition-colors">
                    ✍️ Consulter et signer
                  </a>
                )}
                {signingUrl && doc.statut === 'signe' && (
                  <a href={signingUrl} target="_blank" rel="noopener noreferrer"
                    className="flex items-center justify-center gap-2 w-full border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
                    👁 Voir le contrat
                  </a>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
