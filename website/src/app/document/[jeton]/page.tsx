'use client';

// Document médical ouvert par lien sécurisé, sans compte (lot 6 des documents
// vétérinaires) : le lien n'ouvre que ce document ; il expire et peut être
// désactivé par la clinique ; chaque ouverture est tracée côté serveur.

import { use, useEffect, useState } from 'react';

const TEAL = '#0C5C6C';

interface Info { titre: string; animal: string | null; clinique: string | null; expire_le: string }

export default function DocumentPartagePage({ params }: { params: Promise<{ jeton: string }> }) {
  const { jeton } = use(params);
  const [info, setInfo] = useState<Info | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);

  useEffect(() => {
    fetch(`/api/document-partage/${encodeURIComponent(jeton)}?info=1`, { cache: 'no-store' })
      .then(async r => { const j = await r.json(); if (r.ok) setInfo(j as Info); else setErreur(j.error ?? 'Lien invalide'); })
      .catch(() => setErreur('Impossible de charger le document.'));
  }, [jeton]);

  async function ouvrir(telecharger: boolean) {
    setOccupe(true);
    try {
      const r = await fetch(`/api/document-partage/${encodeURIComponent(jeton)}${telecharger ? '?telecharger=1' : ''}`, { cache: 'no-store' });
      const j = await r.json();
      if (!r.ok || !j.url) { setErreur(j.error ?? 'Document introuvable'); return; }
      window.location.href = j.url;
    } catch { setErreur('Impossible d’ouvrir le document.'); }
    finally { setOccupe(false); }
  }

  return (
    <main className="min-h-screen bg-[#F5F7FA] flex items-center justify-center px-4 py-10">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-sm border border-gray-100 p-6 text-center space-y-4">
        <p className="text-lg font-bold" style={{ color: TEAL, fontFamily: 'Galey,sans-serif' }}>{info?.clinique || 'Votre vétérinaire'}</p>
        {erreur ? (
          <p className="text-sm text-gray-600">{erreur}</p>
        ) : !info ? (
          <div className="flex justify-center py-6"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
        ) : (
          <>
            <div>
              <p className="text-base font-semibold text-[#1F2A2E]">{info.titre}</p>
              {info.animal && <p className="text-sm text-gray-500">{info.animal}</p>}
            </div>
            <div className="flex flex-col gap-2">
              <button onClick={() => ouvrir(false)} disabled={occupe}
                className="w-full py-3 rounded-xl text-white text-sm font-semibold disabled:opacity-50" style={{ background: TEAL }}>
                {occupe ? 'Ouverture…' : 'Consulter le document'}
              </button>
              <button onClick={() => ouvrir(true)} disabled={occupe}
                className="w-full py-3 rounded-xl border text-sm font-semibold disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
                Télécharger le PDF
              </button>
            </div>
            <p className="text-xs text-gray-400">Lien personnel, valable jusqu’au {new Date(info.expire_le).toLocaleDateString('fr-FR')}. Aucun compte n’est nécessaire.</p>
          </>
        )}
        <p className="text-[11px] text-gray-400">Document transmis via PetsMatch.</p>
      </div>
    </main>
  );
}
