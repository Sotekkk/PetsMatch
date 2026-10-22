'use client';
// Récapitulatif et paiement d'un boost : même parcours et mêmes offres
// (produits_ponctuels) pour un boost choisi à la publication d'une annonce
// (elle attend alors en brouillon, paiement_statut « attente_boost ») et pour
// un boost pris plus tard depuis le menu « … » de « Mes annonces ».
// Ouverte aussi depuis l'appli (paiement interdit dans l'appli).

import { Suspense, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { apiFetch } from '@/lib/api-fetch';
import { Icone, BORDURE } from '@/components/dashboard/kit';
import { dureeOffre, prixOffre, CODES_BOOST, type OffreBoost as Offre } from '@/lib/boost-offres';

interface AnnonceBoost { id: string; titre: string | null; race: string | null; statut: string | null; paiement_statut: string | null; boost_until: string | null }


function Inner() {
  const params = useSearchParams();
  const router = useRouter();
  const { user, loading } = useAuth();
  const annonceId = params.get('annonce');
  const code = params.get('offre');
  const statutCible = params.get('statut') === 'en_attente' ? 'en_attente' : 'disponible';
  const [annonce, setAnnonce] = useState<AnnonceBoost | null | undefined>(undefined);
  const [offre, setOffre] = useState<Offre | null | undefined>(undefined);
  const [envoi, setEnvoi] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!annonceId || !code) { setAnnonce(null); setOffre(null); return; }
    supabase.from('annonces').select('id, titre, race, statut, paiement_statut, boost_until').eq('id', annonceId).maybeSingle()
      .then(({ data }) => setAnnonce((data as AnnonceBoost) ?? null));
    supabase.from('produits_ponctuels').select('code, label, prix, duree_heures, description')
      .eq('code', code).eq('actif', true).in('code', CODES_BOOST).maybeSingle()
      .then(({ data }) => setOffre((data as Offre) ?? null));
  }, [annonceId, code]);

  // Publication en attente de ce paiement (boost choisi à la création).
  const publication = annonce?.statut === 'brouillon' && annonce.paiement_statut === 'attente_boost';
  const dejaPubliee = !!annonce && !publication && annonce.statut === 'brouillon';
  const retourChoix = `/annonces/creer?brouillon=${annonceId}&paiement=annule`;

  async function payer() {
    if (!user || !annonce || !offre || envoi) return;
    setEnvoi(true); setErreur(null);
    try {
      const res = await apiFetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid: user.uid, email: user.email ?? '',
          produit_code: offre.code, annonce_id: annonce.id,
          ...(publication ? { publier_statut: statutCible } : {}),
        }),
      });
      const json = await res.json();
      if (!res.ok || !json.url) throw new Error(json.error ?? 'Paiement indisponible pour le moment.');
      window.location.assign(json.url as string);
    } catch (e) {
      setErreur(e instanceof Error ? e.message : 'Paiement indisponible pour le moment.');
      setEnvoi(false);
    }
  }

  if (annonce === undefined || offre === undefined) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  const titre = annonce?.titre || annonce?.race || 'Votre annonce';
  const ligne = (k: string, v: React.ReactNode) => (
    <div className="flex items-start justify-between gap-4 py-2.5" style={{ borderTop: `1px solid ${BORDURE}` }}>
      <dt className="text-gray-500">{k}</dt><dd className="text-right text-[#1E2025] font-semibold">{v}</dd>
    </div>
  );

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-lg mx-auto px-4 py-8">
        <Link href={publication ? retourChoix : '/mes-annonces'} className="inline-flex items-center gap-1.5 text-sm font-semibold text-[#0C5C6C] hover:underline">
          <span className="rotate-180 inline-flex"><Icone nom="fleche" taille={16} /></span>
          {publication ? 'Modifier mon choix' : 'Retour à mes annonces'}
        </Link>
        <h1 className="text-2xl font-bold text-[#1E2025] mt-2">Récapitulatif du boost</h1>

        {!annonce || !offre ? (
          <div className="bg-white rounded-2xl p-6 mt-5 text-sm text-gray-600" style={{ border: `1px solid ${BORDURE}` }}>
            Annonce ou offre introuvable. Retournez dans « Mes annonces » pour choisir un boost.
          </div>
        ) : dejaPubliee ? (
          <div className="bg-white rounded-2xl p-6 mt-5 text-sm text-gray-600" style={{ border: `1px solid ${BORDURE}` }}>
            Cette annonce est un brouillon : terminez-la et publiez-la avant de la booster.
          </div>
        ) : (
          <>
            <section className="bg-white rounded-2xl p-5 mt-5" style={{ border: `1px solid ${BORDURE}` }}>
              <p className="flex items-center gap-2 font-bold text-lg text-[#1E2025]">
                <span className="text-[#B45309]"><Icone nom="eclair" taille={20} /></span>{offre.label}
              </p>
              {offre.description && <p className="text-sm text-gray-600 mt-1">{offre.description}</p>}
              <dl className="mt-4 text-[15px]">
                {ligne('Annonce', titre)}
                {ligne('Durée', dureeOffre(offre.duree_heures))}
                {ligne('Début', 'dès la confirmation du paiement')}
                {ligne('Montant à payer', <span className="text-xl tabular-nums">{prixOffre(offre.prix)}</span>)}
              </dl>
            </section>

            <p className="text-sm text-gray-600 mt-4 rounded-xl px-4 py-3 bg-white" style={{ border: `1px solid ${BORDURE}` }}>
              {publication
                ? (statutCible === 'disponible'
                    ? 'Votre annonce sera publiée et boostée dès la confirmation du paiement. Si le paiement est annulé, elle reste en brouillon avec toutes ses informations et photos.'
                    : 'Votre annonce sera envoyée en validation et boostée dès la confirmation du paiement. Si le paiement est annulé, elle reste en brouillon avec toutes ses informations et photos.')
                : 'Le boost démarre dès la confirmation du paiement. Paiement sécurisé via Stripe.'}
            </p>

            {erreur && <p role="alert" className="mt-4 rounded-xl px-4 py-3 text-sm text-[#B91C1C] bg-[#FEF2F2]" style={{ border: '1px solid #FECACA' }}>{erreur}</p>}

            <div className="mt-5 grid gap-2">
              <button onClick={payer} disabled={envoi}
                className="min-h-12 rounded-xl bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold disabled:opacity-60 inline-flex items-center justify-center gap-2">
                {envoi && <span className="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin" />}
                {envoi ? 'Redirection vers le paiement…' : `Payer ${prixOffre(offre.prix)}`}
              </button>
              {publication && (
                <Link href={retourChoix} className="min-h-12 rounded-xl bg-white text-[#1E2025] font-semibold inline-flex items-center justify-center hover:bg-gray-50"
                  style={{ border: `1px solid ${BORDURE}` }}>
                  Revenir au choix « Publier sans boost »
                </Link>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

export default function PaiementBoostPage() {
  return <Suspense fallback={null}><Inner /></Suspense>;
}
