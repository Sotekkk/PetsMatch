'use client';
// Annonces « Matériel & équipements » du profil actif, intégrées à la page
// « Mes annonces » (site). Mêmes données, statuts et actions qu'auparavant
// (modifier, pause / activer, supprimer).

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { categorieLabel, ANNONCE_OBJET_TRANSACTIONS } from '@/lib/annonce-objet-categories';
import { Icone, Puce, BORDURE, OMBRE } from '@/components/dashboard/kit';

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

/** `statut` : filtre de statut commun de la page ('toutes', 'disponible', 'pause'…). */
export default function MesAnnoncesMateriel({ statut = 'toutes', onCompte }: { statut?: string; onCompte?: (n: number) => void }) {
  const { user, activeProfileId } = useAuth();
  const [rows, setRows] = useState<AnnonceObjet[] | null>(null);
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

  useEffect(() => { load(); }, [load]);
  useEffect(() => { if (rows) onCompte?.(rows.length); }, [rows, onCompte]);

  async function togglePause(a: AnnonceObjet) {
    setBusy(a.id);
    const next = a.statut === 'pause' ? 'disponible' : 'pause';
    await supabase.from('annonces_objets').update({ statut: next }).eq('id', a.id);
    setRows(r => (r ?? []).map(x => x.id === a.id ? { ...x, statut: next } : x));
    setBusy(null);
  }
  async function remove(a: AnnonceObjet) {
    if (!confirm('Supprimer définitivement cette annonce ?')) return;
    setBusy(a.id);
    await supabase.from('annonces_objets').update({ statut: 'supprime' }).eq('id', a.id);
    setRows(r => (r ?? []).filter(x => x.id !== a.id));
    setBusy(null);
  }

  if (rows === null) {
    return <div className="flex justify-center py-10"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }
  const liste = statut === 'toutes' ? rows : rows.filter(a => (a.statut ?? 'disponible') === statut);

  if (liste.length === 0) {
    return (
      <div className={`bg-white rounded-2xl p-8 text-center ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
        <span className="w-11 h-11 mx-auto mb-2 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom="caisse" /></span>
        <p className="text-sm text-gray-500 mb-3">
          {statut === 'toutes' ? 'Aucune annonce de matériel ou d’équipement pour le moment.' : 'Aucune annonce de matériel avec ce statut.'}
        </p>
        {statut === 'toutes' && (
          <Link href="/annonces/creer-objet" className="inline-block bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-5 py-2.5 rounded-full transition-colors">
            Publier du matériel
          </Link>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-2.5">
      {liste.map(a => (
        <div key={a.id} className={`bg-white rounded-2xl ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
          <Link href={`/annonces/objets/${a.id}`} className="flex items-center gap-3 sm:gap-4 p-3">
            <div className="w-16 h-16 rounded-xl overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex-shrink-0 flex items-center justify-center">
              {a.photos?.[0]
                // eslint-disable-next-line @next/next/no-img-element
                ? <img src={a.photos[0]} alt="" className="w-full h-full object-cover" />
                : <Icone nom="caisse" taille={24} />}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-[#1E2025] text-[15px] truncate">{a.titre}</p>
              <p className="text-xs text-gray-500 truncate">
                {categorieLabel(a.categorie)} · {ANNONCE_OBJET_TRANSACTIONS[a.type_transaction] ?? 'Vente'}
              </p>
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1.5">
                {a.statut === 'pause'
                  ? <Puce texte="En pause" fg="#6B7280" bg="#F3F4F6" point />
                  : <Puce texte="En ligne" fg="#2F7D3A" bg="#EAF5EC" point />}
                {boostActif(a.boost_until) && <Puce texte="Boostée" fg="#B45309" bg="#FEF3C7" icone="eclair" />}
                <span className="inline-flex items-center gap-1 text-xs text-gray-500 tabular-nums"><Icone nom="oeil" taille={14} />{a.vues ?? 0}</span>
                <span className="inline-flex items-center gap-1 text-xs text-gray-500 tabular-nums"><Icone nom="enveloppe" taille={14} />{a.contacts ?? 0}</span>
              </div>
            </div>
            <span className="text-sm font-bold text-[#0C5C6C] whitespace-nowrap self-start sm:self-center">{prixLabel(a)}</span>
          </Link>
          <div className="flex items-center gap-2 px-3 py-2 border-t border-[#EEF0EE]">
            <Link href={`/annonces/creer-objet?edit=${a.id}`}
              className="text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1.5 rounded-lg hover:bg-[#E8F4F6] transition-colors">Modifier</Link>
            <button onClick={() => togglePause(a)} disabled={busy === a.id}
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-gray-600 border border-gray-200 px-3 py-1.5 rounded-lg hover:border-[#0C5C6C]/40 disabled:opacity-50">
              <Icone nom={a.statut === 'pause' ? 'lecture' : 'pause'} taille={13} />{a.statut === 'pause' ? 'Activer' : 'Mettre en pause'}
            </button>
            <button onClick={() => remove(a)} disabled={busy === a.id} aria-label="Supprimer" title="Supprimer"
              className="ml-auto inline-flex items-center gap-1.5 text-xs font-semibold text-red-600 border border-red-100 px-3 py-1.5 rounded-lg hover:bg-red-50 disabled:opacity-50">
              <Icone nom="corbeille" taille={13} />Supprimer
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
