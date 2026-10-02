'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

interface Achat {
  id: string;
  annonce_id: string | null;
  statut: string;
  date_achat: string;
  date_expiration: string | null;
  produits_ponctuels: { label: string; prix: number; description: string | null } | null;
}

const STATUT_LABEL: Record<string, { label: string; color: string }> = {
  paye:       { label: 'Payé',    color: 'text-[#6E9E57] bg-[#6E9E57]/10' },
  rembourse:  { label: 'Remboursé', color: 'text-red-600 bg-red-50' },
  en_attente: { label: 'En attente', color: 'text-amber-600 bg-amber-50' },
};

export default function MesAchatsPage() {
  const { user, loading: authLoading, activeProfileId } = useAuth();
  const [achats, setAchats] = useState<Achat[]>([]);
  const [loading, setLoading] = useState(true);
  // Crédits Pets Social : porte-monnaie global du compte (tous profils).
  const [solde, setSolde] = useState(0);
  const [packs, setPacks] = useState<{ motif: string | null; montant: number; created_at: string }[]>([]);
  // Lien « Mon abonnement » du profil, transmis par le menu (?abo=…).
  // window.location plutôt que useSearchParams (évite le Suspense requis au build).
  const [aboHref, setAboHref] = useState<string | null>(null);
  useEffect(() => {
    const abo = new URLSearchParams(window.location.search).get('abo');
    setAboHref(abo && /^\/[a-z-]*\/?abonnement$/.test(abo) ? abo : null);
  }, []);
  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('credit_wallets').select('solde').eq('uid', user.uid).maybeSingle(),
      supabase.from('credit_transactions').select('motif, montant, created_at')
        .eq('uid', user.uid).gt('montant', 0).order('created_at', { ascending: false }).limit(50),
    ]).then(([w, t]) => {
      setSolde((w.data?.solde as number | undefined) ?? 0);
      setPacks((t.data ?? []) as { motif: string | null; montant: number; created_at: string }[]);
    });
  }, [user]);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('achats_ponctuels')
      .select('id, annonce_id, statut, date_achat, date_expiration, produits_ponctuels(label, prix, description)')
      .eq('uid', user.uid)
      .order('date_achat', { ascending: false })
      .then(async ({ data }) => {
        // Multi-profil (miroir appli) : un boost appartient au profil de
        // l'annonce boostée — pas d'achats de l'élevage côté association.
        const achats = (data ?? []) as unknown as Achat[];
        const ids = [...new Set(achats.map(a => a.annonce_id).filter(Boolean))] as string[];
        const profilParAnnonce = new Map<string, string | null>();
        if (ids.length) {
          const { data: ann } = await supabase.from('annonces').select('id, profile_id').in('id', ids);
          (ann ?? []).forEach((r: { id: string; profile_id: string | null }) => profilParAnnonce.set(String(r.id), r.profile_id));
        }
        setAchats(achats.filter(a => {
          const pid = a.annonce_id ? profilParAnnonce.get(String(a.annonce_id)) : null;
          return !activeProfileId || !pid || pid === activeProfileId;
        }));
        setLoading(false);
      });
  }, [user, activeProfileId]);

  if (authLoading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }
  if (!user) {
    return <div className="text-center py-20 text-gray-400">Connectez-vous pour voir vos achats.</div>;
  }
  if (loading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => history.back()} className="text-gray-400 hover:text-[#0C5C6C] text-xl">←</button>
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Achats &amp; crédits</h1>
          <p className="text-xs text-gray-400">Tout ce que vous avez payé sur PetsMatch</p>
        </div>
      </div>

      {aboHref && (
        <>
          <h2 className="font-bold text-[#1F2A2E] text-sm mb-2">Abonnement</h2>
          <Link href={aboHref} className="mb-6 bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-3 hover:shadow-sm transition-shadow">
            <span className="text-xl">💳</span>
            <div className="flex-1">
              <p className="font-semibold text-[#1F2A2E] text-sm">Mon abonnement</p>
              <p className="text-xs text-gray-500">Formule, échéances et factures d&apos;abonnement</p>
            </div>
            <span className="text-[#0C5C6C]">→</span>
          </Link>
        </>
      )}

      <h2 className="font-bold text-[#1F2A2E] text-sm">Boosts et options d&apos;annonces</h2>
      <p className="text-xs text-gray-500 mb-2">Achats liés aux annonces de ce profil</p>

      {achats.length === 0 ? (
        <div className="bg-white rounded-2xl border border-gray-100 p-4 text-gray-400 text-sm">Aucun achat pour le moment.</div>
      ) : (
        <div className="space-y-3">
          {achats.map(a => {
            const statut = STATUT_LABEL[a.statut] ?? { label: a.statut, color: 'text-gray-500 bg-gray-100' };
            const dateStr = new Date(a.date_achat).toLocaleDateString('fr-FR', { dateStyle: 'medium' });
            return (
              <div key={a.id} className="bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <p className="font-semibold text-[#1F2A2E] text-sm truncate">
                      {a.produits_ponctuels?.label ?? 'Achat'}
                    </p>
                    <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${statut.color}`}>
                      {statut.label}
                    </span>
                  </div>
                  <p className="text-xs text-gray-400">{dateStr}</p>
                  {a.annonce_id && (
                    <Link href={`/annonces/${a.annonce_id}`} className="text-xs text-[#0C5C6C] hover:underline">
                      Voir l&apos;annonce concernée →
                    </Link>
                  )}
                </div>
                <p className="font-bold text-[#0C5C6C] text-sm whitespace-nowrap">
                  {a.produits_ponctuels?.prix != null ? `${a.produits_ponctuels.prix.toFixed(2)} €` : ''}
                </p>
              </div>
            );
          })}
        </div>
      )}

      <h2 className="font-bold text-[#1F2A2E] text-sm mt-6">Crédits Pets Social</h2>
      <p className="text-xs text-gray-500 mb-2">Partagés entre tous les profils de votre compte</p>
      <div className="bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-3 mb-3">
        <span className="text-xl">🪙</span>
        <p className="flex-1 text-sm text-[#1F2A2E]">Solde actuel</p>
        <p className="font-bold text-[#6E9E57] text-sm">{solde} crédit{solde > 1 ? 's' : ''}</p>
      </div>
      {packs.length === 0 ? (
        <div className="bg-white rounded-2xl border border-gray-100 p-4 text-gray-400 text-sm">Aucun achat de crédits.</div>
      ) : (
        <div className="space-y-3">
          {packs.map((t, i) => (
            <div key={i} className="bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-4">
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-[#1F2A2E] text-sm truncate">{t.motif ?? 'Achat de crédits'}</p>
                <p className="text-xs text-gray-400">{new Date(t.created_at).toLocaleDateString('fr-FR', { dateStyle: 'medium' })}</p>
              </div>
              <p className="font-bold text-[#6E9E57] text-sm">+{t.montant}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
