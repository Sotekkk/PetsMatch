'use client';
// Boost d'une annonce : offres (produits_ponctuels boost_48h / mise_une) et
// paiement Stripe. Point d'entrée unique : menu « … » de « Mes annonces »
// (et ?boost=<id>, ouvert depuis l'appli). Offres, paiement et durées
// inchangés (anciennement dans la fiche de l'annonce).

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Icone, BORDURE } from '@/components/dashboard/kit';
import { chargerOffresBoost, dureeOffre, prixOffre, urlPaiementBoost, type OffreBoost as Produit } from '@/lib/boost-offres';

/** `returnPath` : conservé pour les appels existants (le retour du paiement
 *  se fait sur « Mes annonces »). */
export default function BoostAnnonceModal({ annonceId, boostUntil, onClose, table = 'annonces' }: {
  annonceId: string; boostUntil?: string | null; returnPath?: string; onClose: () => void;
  /** Annonce de matériel & équipements : annonces_objets. */
  table?: 'annonces' | 'annonces_objets';
}) {
  const router = useRouter();
  const [produits, setProduits] = useState<Produit[] | null>(null);
  const [boosting, setBoosting] = useState(false);
  const actif = !!boostUntil && new Date(boostUntil) > new Date();

  useEffect(() => { chargerOffresBoost().then(setProduits); }, []);

  useEffect(() => {
    const touche = (e: KeyboardEvent) => { if (e.key === 'Escape' && !boosting) onClose(); };
    document.addEventListener('keydown', touche);
    return () => document.removeEventListener('keydown', touche);
  }, [onClose, boosting]);

  // Même parcours qu'à la publication : récapitulatif puis paiement.
  function booster(code: string) {
    setBoosting(true);
    router.push(urlPaiementBoost(annonceId, code, undefined, table));
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
                <span className="block text-xs text-gray-500">{dureeOffre(p.duree_heures)} de mise en avant{p.description ? ` · ${p.description}` : ''}</span>
              </span>
              <span className="text-sm font-bold text-[#B45309] tabular-nums whitespace-nowrap">{prixOffre(p.prix)}</span>
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
