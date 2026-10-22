'use client';
// Boost d'une annonce : offres (produits_ponctuels boost_48h / mise_une) et
// paiement Stripe. Point d'entrée unique : menu « … » de « Mes annonces »
// (et ?boost=<id>, ouvert depuis l'appli). Offres, paiement et durées
// inchangés (anciennement dans la fiche de l'annonce).

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { apiFetch } from '@/lib/api-fetch';
import { Icone, BORDURE } from '@/components/dashboard/kit';

interface Produit { code: string; label: string; prix: number; duree_heures: number | null }

export default function BoostAnnonceModal({ annonceId, boostUntil, returnPath, onClose }: {
  annonceId: string; boostUntil?: string | null; returnPath: string; onClose: () => void;
}) {
  const { user } = useAuth();
  const [produits, setProduits] = useState<Produit[] | null>(null);
  const [boosting, setBoosting] = useState(false);
  const actif = !!boostUntil && new Date(boostUntil) > new Date();

  useEffect(() => {
    supabase.from('produits_ponctuels')
      .select('code, label, prix, duree_heures')
      .eq('actif', true)
      .not('duree_heures', 'is', null)
      .in('code', ['boost_48h', 'mise_une'])
      .then(({ data }) => setProduits((data as Produit[]) ?? []));
  }, []);

  useEffect(() => {
    const touche = (e: KeyboardEvent) => { if (e.key === 'Escape' && !boosting) onClose(); };
    document.addEventListener('keydown', touche);
    return () => document.removeEventListener('keydown', touche);
  }, [onClose, boosting]);

  async function booster(code: string) {
    if (!user) return;
    setBoosting(true);
    try {
      const res = await apiFetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid: user.uid, email: user.email ?? '',
          produit_code: code, annonce_id: annonceId,
          returnPath,
        }),
      });
      const json = await res.json();
      if (!res.ok || !json.url) throw new Error(json.error ?? 'Boost indisponible pour le moment.');
      window.location.assign(json.url as string);
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Boost indisponible pour le moment.');
      setBoosting(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center sm:p-4" onClick={() => !boosting && onClose()}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full max-w-sm p-6 shadow-2xl" style={{ fontFamily: 'Galey, sans-serif' }}
        onClick={e => e.stopPropagation()} role="dialog" aria-modal="true" aria-label="Booster l’annonce">
        <h3 className="font-bold text-lg text-[#1E2025] flex items-center gap-2">
          <span className="text-[#B45309]"><Icone nom="eclair" taille={20} /></span>
          {actif ? 'Prolonger le boost' : 'Booster l’annonce'}
        </h3>
        <p className="text-sm text-gray-500 mt-1">
          {actif
            ? `Annonce mise en avant jusqu’au ${new Date(boostUntil!).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}.`
            : 'Un boost place votre annonce en tête des résultats de recherche et du fil.'}
        </p>
        <p className="text-xs text-gray-400 mt-1 mb-4">Paiement sécurisé via Stripe. Le boost démarre dès le paiement confirmé.</p>
        <div className="space-y-2 mb-4">
          {produits === null && <p className="text-sm text-gray-400 py-2">Chargement des offres…</p>}
          {produits?.length === 0 && <p className="text-sm text-gray-500 py-2">Aucune offre disponible pour le moment.</p>}
          {produits?.map(p => (
            <button key={p.code} disabled={boosting} onClick={() => booster(p.code)}
              className="w-full flex items-center justify-between rounded-xl px-4 py-3 text-left hover:border-[#B45309] hover:bg-amber-50 transition-colors disabled:opacity-60"
              style={{ border: `1px solid ${BORDURE}` }}>
              <span>
                <span className="block text-sm font-semibold text-[#1E2025]">{p.label}</span>
                {p.duree_heures != null && (
                  <span className="block text-xs text-gray-500">
                    {p.duree_heures >= 24 ? `${Math.round(p.duree_heures / 24)} j` : `${p.duree_heures} h`} de mise en avant
                  </span>
                )}
              </span>
              <span className="text-sm font-bold text-[#B45309] tabular-nums">{p.prix.toFixed(2)} €</span>
            </button>
          ))}
        </div>
        <button type="button" onClick={onClose} disabled={boosting}
          className="w-full text-gray-600 text-sm font-semibold py-2.5 rounded-xl hover:bg-gray-50 transition-colors disabled:opacity-60"
          style={{ border: `1px solid ${BORDURE}` }}>
          {boosting ? 'Redirection…' : 'Annuler'}
        </button>
      </div>
    </div>
  );
}
