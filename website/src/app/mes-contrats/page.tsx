'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface DocRow {
  id: string;
  type: string;
  titre: string;
  statut: 'brouillon' | 'en_attente' | 'signe' | 'archive' | 'partiellement_signe' | 'annule' | 'expire' | 'refuse';
  token: string | null;
  signe_le: string | null;
  pdf_signe_url: string | null;
  rejection_reason: string | null;
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
  brouillon:          { label: 'Brouillon',                  cls: 'bg-gray-100 text-gray-500' },
  en_attente:         { label: '⏳ En attente de signature', cls: 'bg-amber-100 text-amber-700' },
  partiellement_signe:{ label: '✍️ Partiellement signé',    cls: 'bg-blue-100 text-blue-700' },
  signe:              { label: '✅ Signé',                   cls: 'bg-green-100 text-green-700' },
  archive:            { label: 'Archivé',                    cls: 'bg-gray-100 text-gray-400' },
  annule:             { label: '🚫 Annulé',                  cls: 'bg-red-100 text-red-500' },
  expire:             { label: '⏰ Expiré',                  cls: 'bg-orange-100 text-orange-600' },
  refuse:             { label: '❌ Refusé par vous',         cls: 'bg-red-100 text-red-700' },
};

export default function MesContratsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [docs, setDocs] = useState<DocRow[]>([]);
  const [fetching, setFetching] = useState(true);
  const [refuseModal, setRefuseModal] = useState<{ id: string; token: string | null } | null>(null);
  const [refuseReason, setRefuseReason] = useState('');
  const [refusing, setRefusing] = useState(false);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user?.email) return;
    supabase
      .from('documents_animaux')
      .select('id, type, titre, statut, token, signe_le, pdf_signe_url, rejection_reason, created_at, metadata, animaux(nom, espece)')
      .filter('metadata->>acquereur_email', 'eq', user.email)
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setDocs((data ?? []) as unknown as DocRow[]);
        setFetching(false);
      });
  }, [user?.email]);

  async function refuser() {
    if (!refuseModal) return;
    setRefusing(true);
    await fetch(`/api/contracts/${refuseModal.id}/refuse`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: refuseReason.trim() || null, actorEmail: user?.email }),
    });
    setDocs(prev => prev.map(d => d.id === refuseModal.id ? { ...d, statut: 'refuse' as const, rejection_reason: refuseReason.trim() || null } : d));
    setRefusing(false);
    setRefuseModal(null);
    setRefuseReason('');
  }

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
            const isFinal = ['signe', 'annule', 'expire', 'refuse'].includes(doc.statut);
            const canRefuse = !isFinal;

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
                      {doc.rejection_reason && (
                        <span className="text-xs text-red-400 italic">— {doc.rejection_reason}</span>
                      )}
                    </div>
                  </div>
                </div>

                <div className="flex gap-2">
                  {/* Consulter / Voir */}
                  {signingUrl && doc.statut !== 'annule' && (
                    <a href={signingUrl} target="_blank" rel="noopener noreferrer"
                      className={`flex-1 flex items-center justify-center gap-2 text-sm font-semibold py-2.5 rounded-xl transition-colors ${
                        doc.statut === 'signe'
                          ? 'border border-gray-200 text-gray-600 hover:bg-gray-50'
                          : doc.statut === 'refuse'
                          ? 'border border-red-200 text-red-500 hover:bg-red-50'
                          : 'bg-[#0C5C6C] hover:bg-[#0a4f5e] text-white'
                      }`}>
                      {doc.statut === 'signe' ? '👁 Voir' : doc.statut === 'refuse' ? '📄 Voir' : '✍️ Consulter et signer'}
                    </a>
                  )}
                  {/* PREP07 — Télécharger PDF signé */}
                  {doc.statut === 'signe' && doc.pdf_signe_url && (
                    <a href={doc.pdf_signe_url} download target="_blank" rel="noopener noreferrer"
                      className="flex items-center gap-1 border border-green-300 text-green-600 text-sm font-medium px-3 py-2.5 rounded-xl hover:bg-green-50">
                      📥
                    </a>
                  )}
                  {doc.statut === 'signe' && !doc.pdf_signe_url && signingUrl && (
                    <a href={signingUrl} target="_blank" rel="noopener noreferrer"
                      title="Imprimer / sauvegarder en PDF"
                      className="flex items-center gap-1 border border-gray-200 text-gray-500 text-sm font-medium px-3 py-2.5 rounded-xl hover:bg-gray-50">
                      🖨️
                    </a>
                  )}
                  {/* PREP08 — Refuser */}
                  {canRefuse && signingUrl && (
                    <button onClick={() => { setRefuseModal({ id: doc.id, token: doc.token }); setRefuseReason(''); }}
                      className="flex items-center gap-1 border border-red-200 text-red-400 text-sm font-medium px-3 py-2.5 rounded-xl hover:bg-red-50 hover:text-red-600">
                      ❌
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Modal refus */}
      {refuseModal && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/50 px-4"
          onClick={e => { if (e.target === e.currentTarget) setRefuseModal(null); }}>
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl space-y-4">
            <h3 className="font-bold text-[#1F2A2E] text-base font-galey">❌ Refuser ce contrat</h3>
            <p className="text-sm text-gray-500">Indiquez optionnellement la raison du refus. L&apos;éleveur en sera informé.</p>
            <textarea
              value={refuseReason}
              onChange={e => setRefuseReason(e.target.value)}
              placeholder="Motif du refus (facultatif)…"
              rows={3}
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-red-400 resize-none"
            />
            <div className="flex gap-2">
              <button onClick={() => setRefuseModal(null)} disabled={refusing}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 disabled:opacity-40">
                Annuler
              </button>
              <button onClick={refuser} disabled={refusing}
                className="flex-1 bg-red-500 hover:bg-red-600 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors disabled:opacity-60">
                {refusing ? '…' : 'Confirmer le refus'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
