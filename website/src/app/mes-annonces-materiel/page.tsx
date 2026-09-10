'use client';

import { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { categorieLabel } from '@/lib/annonce-objet-categories';

interface AnnonceObjet {
  id: string;
  titre: string;
  categorie: string;
  type_transaction: string;
  prix: number | null;
  prix_unite: string | null;
  photos: string[] | null;
  statut: string | null;
  boost_until: string | null;
  vues: number | null;
  contacts: number | null;
  created_at: string | null;
}

function prixLabel(a: AnnonceObjet): string {
  if (a.type_transaction === 'don') return 'Don';
  if (a.type_transaction === 'recherche') return 'Recherche';
  if (a.prix == null) return 'Prix à convenir';
  return `${Math.round(a.prix)} €${a.prix_unite ?? ''}`;
}
const boostActif = (s: string | null) => !!s && new Date(s) > new Date();

export default function MesAnnoncesMaterielPage() {
  const router = useRouter();
  const { user, loading, activeProfileId } = useAuth();
  const [rows, setRows] = useState<AnnonceObjet[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const { data: migrated } = await supabase.from('annonces_objets').select('id')
      .eq('uid', user.uid).not('profile_id', 'is', null).limit(1);
    let q = supabase.from('annonces_objets').select(
      'id, titre, categorie, type_transaction, prix, prix_unite, photos, statut, boost_until, vues, contacts, created_at',
    ).neq('statut', 'supprime').order('created_at', { ascending: false });
    q = migrated && migrated.length > 0 && activeProfileId
      ? q.eq('profile_id', activeProfileId)
      : q.eq('uid', user.uid);
    const { data } = await q;
    setRows((data ?? []) as AnnonceObjet[]);
  }, [user, activeProfileId]);

  useEffect(() => {
    if (!loading && !user) { router.push('/connexion'); return; }
    load();
  }, [loading, user, router, load]);

  async function togglePause(a: AnnonceObjet) {
    setBusy(a.id);
    const next = a.statut === 'pause' ? 'disponible' : 'pause';
    await supabase.from('annonces_objets').update({ statut: next }).eq('id', a.id);
    setRows(r => r.map(x => x.id === a.id ? { ...x, statut: next } : x));
    setBusy(null);
  }
  async function remove(a: AnnonceObjet) {
    if (!confirm('Supprimer définitivement cette annonce ?')) return;
    setBusy(a.id);
    await supabase.from('annonces_objets').update({ statut: 'supprime' }).eq('id', a.id);
    setRows(r => r.filter(x => x.id !== a.id));
    setBusy(null);
  }

  if (loading || !user) return <div className="py-32 text-center text-gray-400">Chargement…</div>;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 pb-20">
      <div className="flex items-center justify-between flex-wrap gap-3 mb-1">
        <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Mes annonces — matériel</h1>
        <div className="flex gap-2">
          <Link href="/annonces/objets" className="text-sm border border-[#0C5C6C] text-[#0C5C6C] px-3 py-2 rounded-xl hover:bg-[#E8F4F6] transition-colors">Fil public</Link>
          <Link href="/annonces/creer-objet" className="text-sm bg-[#0C5C6C] text-white px-4 py-2 rounded-xl hover:bg-[#094F5D] transition-colors">+ Publier</Link>
        </div>
      </div>
      <p className="text-sm text-gray-500 mb-5">Cage, harnais, foin, location de prairie, matériel agricole… Publication gratuite. Pas d’animaux.</p>

      {rows.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-4xl mb-2">📦</p>
          <p className="text-gray-500 text-sm">Aucune annonce matériel pour le moment.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map(a => (
            <div key={a.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
              <Link href={`/annonces/objets/${a.id}`} className="flex gap-3">
                <div className="w-24 h-24 bg-[#EEF3F0] flex-shrink-0">
                  {a.photos?.[0]
                    ? <img src={a.photos[0]} alt={a.titre} className="w-full h-full object-cover" />
                    : <div className="w-full h-full flex items-center justify-center text-2xl">📦</div>}
                </div>
                <div className="flex-1 min-w-0 py-2.5 pr-3">
                  <div className="flex flex-wrap gap-1.5 mb-1">
                    <span className={`text-[11px] font-semibold px-2 py-0.5 rounded ${a.statut === 'pause' ? 'bg-gray-100 text-gray-500' : 'bg-[#6E9E57]/12 text-[#6E9E57]'}`}>
                      {a.statut === 'pause' ? 'En pause' : 'En ligne'}
                    </span>
                    {boostActif(a.boost_until) && <span className="text-[11px] font-semibold px-2 py-0.5 rounded bg-[#FF8A00]/12 text-[#FF8A00]">⚡ Boostée</span>}
                    <span className="text-[11px] font-semibold px-2 py-0.5 rounded bg-[#0C5C6C]/10 text-[#0C5C6C]">{categorieLabel(a.categorie)}</span>
                  </div>
                  <p className="font-bold text-[#1F2A2E] text-sm truncate">{a.titre}</p>
                  <p className="text-[#0C5C6C] font-bold text-sm">{prixLabel(a)}</p>
                  <p className="text-gray-400 text-xs mt-0.5">👁 {a.vues ?? 0} · ✉️ {a.contacts ?? 0}</p>
                </div>
              </Link>
              <div className="flex gap-1.5 px-3 py-2 border-t border-gray-50">
                <Link href={`/annonces/creer-objet?edit=${a.id}`}
                  className="text-xs border border-[#0C5C6C] text-[#0C5C6C] px-3 py-1.5 rounded-lg hover:bg-[#E8F4F6] transition-colors">Modifier</Link>
                <button onClick={() => togglePause(a)} disabled={busy === a.id}
                  className="text-xs border border-gray-200 text-gray-500 px-3 py-1.5 rounded-lg hover:border-[#0C5C6C]/40 disabled:opacity-50">
                  {a.statut === 'pause' ? 'Activer' : 'Pause'}
                </button>
                <button onClick={() => remove(a)} disabled={busy === a.id}
                  className="ml-auto text-xs border border-red-100 text-red-400 px-3 py-1.5 rounded-lg hover:bg-red-50 disabled:opacity-50">🗑</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
