'use client';

// Moyens de paiement acceptés par le pro (+ RIB pour un client, si virement).
// Logique : lib/moyens-paiement.ts ; RIB : RPC pm_rib_pro (clients du pro seulement).
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { libelleMoyens, moyensPaiement } from '@/lib/moyens-paiement';

export default function MoyensPaiement({ moyens, proProfileId, avecRib = false, compact = false }: {
  moyens: unknown; proProfileId?: string | null; avecRib?: boolean; compact?: boolean;
}) {
  const libelle = libelleMoyens(moyens);
  const virement = moyensPaiement(moyens).includes('virement');
  const [rib, setRib] = useState<{ iban: string | null; bic: string | null; titulaire: string | null } | null>(null);

  useEffect(() => {
    if (!avecRib || !virement || !proProfileId) return;
    let annule = false;
    supabase.rpc('pm_rib_pro', { p_pro_profile_id: proProfileId }).then(({ data }) => {
      const r = (Array.isArray(data) ? data[0] : data) as { iban: string | null; bic: string | null; titulaire: string | null } | undefined;
      if (!annule && r?.iban) setRib(r);
    });
    return () => { annule = true; };
  }, [avecRib, virement, proProfileId]);

  if (!libelle) return null;
  if (compact) return <p className="text-sm text-gray-600"><span className="font-semibold">Paiement accepté :</span> {libelle}</p>;
  return (
    <div className="text-sm text-gray-700 space-y-1">
      <p><span className="font-semibold">Paiement accepté :</span> {libelle}</p>
      {rib && (
        <div className="bg-[#F7FAF8] rounded-lg px-3 py-2 text-xs">
          <p className="font-semibold text-[#1F2A2E]">RIB pour le virement{rib.titulaire ? ` — ${rib.titulaire}` : ''}</p>
          <p className="font-mono break-all">IBAN {rib.iban}</p>
          {rib.bic && <p className="font-mono">BIC {rib.bic}</p>}
        </div>
      )}
    </div>
  );
}

/** Variante pour le RDV d'un client : lit les moyens du pro puis affiche le RIB. */
export function MoyensPaiementDuPro({ proProfileId }: { proProfileId?: string | null }) {
  const [moyens, setMoyens] = useState<unknown>(null);
  useEffect(() => {
    if (!proProfileId) return;
    let annule = false;
    supabase.from('user_profiles_complet').select('moyens_paiement').eq('id', proProfileId).maybeSingle()
      .then(({ data }) => { if (!annule) setMoyens((data as { moyens_paiement?: unknown } | null)?.moyens_paiement ?? null); });
    return () => { annule = true; };
  }, [proProfileId]);
  if (!proProfileId || !moyensPaiement(moyens).length) return null;
  return <MoyensPaiement moyens={moyens} proProfileId={proProfileId} avecRib />;
}
