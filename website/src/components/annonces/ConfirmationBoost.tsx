'use client';
// Retour du paiement d'un boost choisi à la publication (?publiee=<id>) :
// confirmation de publication avec les dates de début et de fin du boost.
// Le webhook Stripe publie l'annonce : on attend sa confirmation quelques
// secondes avant d'afficher les dates réelles.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { Icone } from '@/components/dashboard/kit';

const fmt = (iso: string) => new Date(iso).toLocaleString('fr-FR', { dateStyle: 'long', timeStyle: 'short' });

export default function ConfirmationBoost({ annonceId, onFermer }: { annonceId: string; onFermer: () => void }) {
  const [etat, setEtat] = useState<{ statut: string; debut: string | null; fin: string } | null>(null);
  const [delaiDepasse, setDelaiDepasse] = useState(false);

  useEffect(() => {
    let essais = 0;
    let fini = false;
    const verifier = async () => {
      const { data: a } = await supabase.from('annonces').select('statut, boost_until').eq('id', annonceId).maybeSingle();
      if (a && a.statut !== 'brouillon' && a.boost_until) {
        const { data: achat } = await supabase.from('achats_ponctuels').select('created_at')
          .eq('annonce_id', annonceId).order('created_at', { ascending: false }).limit(1).maybeSingle();
        fini = true;
        setEtat({ statut: a.statut as string, debut: (achat?.created_at as string | undefined) ?? null, fin: a.boost_until as string });
        return;
      }
      if (++essais >= 15) { fini = true; setDelaiDepasse(true); return; }
      setTimeout(() => { if (!fini) verifier(); }, 2000);
    };
    verifier();
    return () => { fini = true; };
  }, [annonceId]);

  return (
    <div role="status" className="mb-5 rounded-2xl px-4 py-4 flex items-start gap-3 bg-[#EAF5EC] border border-[#BFE3C6]">
      <span className="text-[#2F7D3A] mt-0.5"><Icone nom="valide" taille={20} /></span>
      <div className="flex-1 text-sm text-[#1E2025]">
        {etat ? (
          <>
            <p className="font-semibold">{etat.statut === 'en_attente' ? 'Paiement confirmé : votre annonce est envoyée en validation.' : 'Paiement confirmé : votre annonce est publiée.'}</p>
            <p className="mt-0.5">Boost actif {etat.debut ? `du ${fmt(etat.debut)} ` : ''}jusqu’au {fmt(etat.fin)}.</p>
          </>
        ) : delaiDepasse ? (
          <p>Paiement reçu. La publication de votre annonce prend un peu plus de temps que prévu : elle apparaîtra ici dans quelques instants.</p>
        ) : (
          <p>Paiement reçu : publication de votre annonce en cours…</p>
        )}
      </div>
      <button onClick={onFermer} aria-label="Fermer" className="text-gray-500 hover:text-gray-700">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M6 6l12 12M18 6L6 18" /></svg>
      </button>
    </div>
  );
}
