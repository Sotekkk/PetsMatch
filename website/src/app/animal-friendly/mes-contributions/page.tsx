'use client';

// Mes contributions aux lieux pet-friendly : lieux recommandés (statut, motif
// de la modération, fiche à compléter), corrections proposées, revendications.
// Miroir appli : lib/pages/lieux/mes_contributions_lieux_page.dart.

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

type Ligne = Record<string, unknown> & { id: string; statut: string; created_at: string; place?: { id?: string; nom?: string } | null };

const STATUTS: Record<string, [string, string]> = {
  brouillon: ['Brouillon', 'text-gray-600 bg-gray-100'],
  en_attente_validation: ['En attente de validation', 'text-[#B45309] bg-[#FEF3C7]'],
  actif: ['Publié', 'text-[#166534] bg-[#DCFCE7]'],
  a_corriger: ['À compléter', 'text-[#1D4ED8] bg-[#DBEAFE]'],
  refuse: ['Non publié', 'text-[#B91C1C] bg-[#FEE2E2]'],
  masque: ['Masqué', 'text-gray-600 bg-gray-100'],
  suspendu: ['Suspendu', 'text-[#B91C1C] bg-[#FEE2E2]'],
  en_attente: ['En attente', 'text-[#B45309] bg-[#FEF3C7]'],
  appliquee: ['Appliquée', 'text-[#166534] bg-[#DCFCE7]'],
  refusee: ['Refusée', 'text-[#B91C1C] bg-[#FEE2E2]'],
  validee: ['Validée', 'text-[#166534] bg-[#DCFCE7]'],
};

export default function MesContributionsLieuxPage() {
  const { user, loading } = useAuth();
  const [lieux, setLieux] = useState<Ligne[]>([]);
  const [corrections, setCorrections] = useState<Ligne[]>([]);
  const [revendications, setRevendications] = useState<Ligne[]>([]);
  const [charge, setCharge] = useState(false);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('petfriendly_places').select('*').eq('ajoute_par_uid', user.uid).order('created_at', { ascending: false }),
      supabase.from('petfriendly_corrections').select('*, place:petfriendly_places(id, nom)').eq('uid', user.uid).order('created_at', { ascending: false }),
      supabase.from('petfriendly_revendications').select('*, place:petfriendly_places(id, nom)').eq('uid', user.uid).order('created_at', { ascending: false }),
    ]).then(([a, b, c]) => {
      setLieux((a.data ?? []) as Ligne[]); setCorrections((b.data ?? []) as Ligne[]); setRevendications((c.data ?? []) as Ligne[]);
      setCharge(true);
    });
  }, [user]);

  if (loading) return null;
  if (!user) {
    return (
      <div className="max-w-xl mx-auto px-4 py-16 text-center" style={{ fontFamily: 'Galey, sans-serif' }}>
        <Link href="/connexion?suite=/animal-friendly/mes-contributions" className="inline-block px-5 py-2.5 rounded-xl bg-[#0C5C6C] text-white font-semibold">Se connecter</Link>
      </div>
    );
  }

  const pastille = (st: string) => {
    const [l, c] = STATUTS[st] ?? [st, 'text-gray-600 bg-gray-100'];
    return <span className={`text-[11px] font-bold px-2 py-0.5 rounded-full ${c}`}>{l}</span>;
  };
  const date = (d: unknown) => (d ? new Date(String(d)).toLocaleDateString('fr-FR') : '');
  const carte = (titre: string, sous: string, st: string, motif: unknown, actions?: React.ReactNode) => (
    <div className="bg-white rounded-2xl shadow-sm p-4">
      <div className="flex items-start justify-between gap-3">
        <p className="font-bold text-[#1F2A2E]">{titre}</p>{pastille(st)}
      </div>
      <p className="text-xs text-gray-500 mt-0.5">{sous}</p>
      {motif ? <p className="text-sm text-gray-700 mt-2">Motif de la modération : {String(motif)}</p> : null}
      {actions && <div className="mt-3 flex gap-2 flex-wrap">{actions}</div>}
    </div>
  );

  return (
    <div className="bg-[#F4F7F6] min-h-screen pb-16" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="bg-[#0C5C6C] text-white"><div className="max-w-2xl mx-auto px-4 py-6"><h1 className="text-2xl font-bold">Mes contributions</h1>
        <p className="text-white/75 text-sm">Lieux pet-friendly recommandés, corrections et revendications.</p></div></div>
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-3">
        {!charge && <p className="text-sm text-gray-500">Chargement…</p>}
        <h2 className="text-lg font-bold text-[#1F2A2E] pt-2">Lieux recommandés</h2>
        {charge && lieux.length === 0 && <p className="text-sm text-gray-500">Vous n&apos;avez pas encore recommandé de lieu. <Link href="/animal-friendly/recommander" className="text-[#0C5C6C] font-semibold">Recommander un lieu</Link></p>}
        {lieux.map(l => <div key={l.id}>{carte(String(l.nom ?? ''), `${String(l.ville ?? '')} · proposé le ${date(l.created_at)}`, l.statut,
          ['a_corriger', 'refuse', 'masque'].includes(l.statut) ? l.motif_moderation : null,
          ['a_corriger', 'brouillon', 'en_attente_validation'].includes(l.statut)
            ? <Link href={`/animal-friendly/recommander?id=${l.id}`} className="px-4 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-bold">{l.statut === 'en_attente_validation' ? 'Modifier' : 'Compléter et renvoyer'}</Link>
            : l.statut === 'actif' ? <Link href={`/animal-friendly/${l.id}`} className="px-4 py-2 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-bold">Voir la fiche</Link> : undefined)}</div>)}
        <h2 className="text-lg font-bold text-[#1F2A2E] pt-4">Corrections proposées</h2>
        {charge && corrections.length === 0 && <p className="text-sm text-gray-500">Aucune correction proposée.</p>}
        {corrections.map(c => <div key={c.id}>{carte(c.place?.nom ?? 'Lieu', `Proposée le ${date(c.created_at)}`, c.statut, c.statut === 'refusee' ? c.motif : null)}</div>)}
        <h2 className="text-lg font-bold text-[#1F2A2E] pt-4">Revendications</h2>
        {charge && revendications.length === 0 && <p className="text-sm text-gray-500">Aucune revendication.</p>}
        {revendications.map(r => <div key={r.id}>{carte(r.place?.nom ?? 'Lieu', `Envoyée le ${date(r.created_at)}`, r.statut, r.statut === 'refusee' ? r.motif : null,
          r.statut === 'validee' && r.place?.id ? <Link href={`/animal-friendly/${r.place.id}`} className="px-4 py-2 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-bold">Voir ma fiche</Link> : undefined)}</div>)}
      </div>
    </div>
  );
}
