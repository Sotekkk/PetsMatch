'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface Contest {
  id: string;
  avis_id: string;
  pro_uid: string;
  motif: string;
  explication: string | null;
  statut: 'en_attente' | 'acceptee' | 'refusee';
  decision_admin: string | null;
  decide_par: string | null;
  decide_at: string | null;
  created_at: string;
  avis_pro: { note: number; commentaire: string | null; client_uid: string; created_at: string } | null;
}

type Filter = 'en_attente' | 'acceptee' | 'refusee';

export default function AvisContestesTab({ adminUid }: { adminUid: string }) {
  const [filter, setFilter] = useState<Filter>('en_attente');
  const [contests, setContests] = useState<Contest[]>([]);
  const [proNames, setProNames] = useState<Record<string, string>>({});
  const [clientNames, setClientNames] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] = useState<string | null>(null);

  const load = useCallback(async (f: Filter) => {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('avis_pro_contests')
        .select('*, avis_pro(note, commentaire, client_uid, created_at)')
        .eq('statut', f)
        .order('created_at', { ascending: f !== 'en_attente' });
      const list = (data ?? []) as unknown as Contest[];
      setContests(list);

      const uids = Array.from(new Set([
        ...list.map(c => c.pro_uid),
        ...list.map(c => c.avis_pro?.client_uid).filter((v): v is string => !!v),
      ]));
      if (uids.length > 0) {
        const { data: profiles } = await supabase
          .from('user_profiles').select('uid, nom, firstname, lastname, profile_type')
          .in('uid', uids).eq('is_main', true);
        const proMap: Record<string, string> = {};
        const clientMap: Record<string, string> = {};
        for (const p of profiles ?? []) {
          const name = (p.profile_type === 'eleveur' && p.nom) ? p.nom : `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
          proMap[p.uid] = name || p.uid;
          clientMap[p.uid] = name || p.uid;
        }
        setProNames(proMap);
        setClientNames(clientMap);
      }
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => { load(filter); }, [filter, load]);

  async function handleDecision(c: Contest, decision: 'acceptee' | 'refusee') {
    setSavingId(c.id);
    try {
      if (decision === 'acceptee') {
        // L'avis est jugé abusif/infondé : on le supprime réellement.
        await supabase.from('avis_pro').delete().eq('id', c.avis_id);
      }
      await supabase.from('avis_pro_contests').update({
        statut: decision,
        decide_par: adminUid,
        decide_at: new Date().toISOString(),
      }).eq('id', c.id);
      setContests(prev => prev.filter(x => x.id !== c.id));
    } finally {
      setSavingId(null);
    }
  }

  return (
    <div className="max-w-4xl mx-auto">
      <h2 className="font-bold text-[#1F2A2E] text-lg mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
        🚩 Avis contestés
      </h2>
      <p className="text-sm text-gray-500 mb-4">
        Signalements déposés par un pro sur un avis client (avis_pro_contests). Accepter la contestation supprime l&apos;avis.
      </p>

      <div className="flex gap-2 mb-5">
        {(['en_attente', 'acceptee', 'refusee'] as Filter[]).map(s => (
          <button key={s} onClick={() => setFilter(s)}
            className={`px-4 py-1.5 rounded-full text-sm font-semibold border transition-colors ${
              filter === s ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
            }`}
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {s === 'en_attente' ? '⏳ En attente' : s === 'acceptee' ? '🗑️ Avis supprimés' : '❌ Rejetées'}
          </button>
        ))}
        <button onClick={() => load(filter)}
          className="ml-auto px-3 py-1.5 text-sm text-gray-500 border border-gray-200 rounded-full hover:bg-gray-50 bg-white"
          title="Rafraîchir">↺</button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : contests.length === 0 ? (
        <div className="bg-white rounded-2xl p-12 text-center shadow-sm border border-gray-100">
          <div className="text-3xl mb-2">{filter === 'en_attente' ? '🎉' : '📭'}</div>
          <p className="text-gray-500">
            {filter === 'en_attente' ? 'Aucune contestation en attente.' : 'Aucune contestation dans cette catégorie.'}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {contests.map(c => (
            <div key={c.id} className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
              <div className="flex items-center justify-between flex-wrap gap-2">
                <span className="text-sm font-bold text-[#1F2A2E]">
                  Pro : {proNames[c.pro_uid] ?? c.pro_uid}
                </span>
                <span className="text-xs text-gray-400">
                  Contesté le {new Date(c.created_at).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' })}
                </span>
              </div>
              <p className="text-xs text-red-600 font-semibold mt-2">Motif : {c.motif}</p>
              {c.explication && <p className="text-xs text-gray-500 mt-0.5">{c.explication}</p>}

              <div className="mt-3 bg-gray-50 rounded-xl p-3 border border-gray-100">
                <p className="text-xs text-gray-400 mb-1">Avis contesté — {clientNames[c.avis_pro?.client_uid ?? ''] ?? c.avis_pro?.client_uid ?? '—'}</p>
                <span className="text-[#FFA000] text-sm">
                  {'★'.repeat(c.avis_pro?.note ?? 0)}
                  <span className="text-gray-200">{'★'.repeat(5 - (c.avis_pro?.note ?? 0))}</span>
                </span>
                {c.avis_pro?.commentaire && <p className="text-sm text-gray-700 mt-1">{c.avis_pro.commentaire}</p>}
                {!c.avis_pro && <p className="text-xs text-gray-400 italic mt-1">Avis déjà supprimé.</p>}
              </div>

              {c.statut === 'en_attente' && (
                <div className="flex gap-2 mt-3">
                  <button onClick={() => handleDecision(c, 'acceptee')} disabled={savingId === c.id}
                    className="text-xs font-semibold px-3 py-1.5 rounded-xl bg-red-500 text-white hover:bg-red-600 disabled:opacity-50 transition-colors">
                    🗑️ Supprimer l&apos;avis
                  </button>
                  <button onClick={() => handleDecision(c, 'refusee')} disabled={savingId === c.id}
                    className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-gray-200 text-gray-600 hover:bg-gray-50 disabled:opacity-50 transition-colors">
                    Rejeter (garder l&apos;avis)
                  </button>
                </div>
              )}
              {c.statut !== 'en_attente' && (
                <p className="text-xs text-gray-400 mt-2">
                  {c.statut === 'acceptee' ? '✅ Avis supprimé' : '❌ Contestation rejetée'}
                  {c.decide_at ? ` — ${new Date(c.decide_at).toLocaleDateString('fr-FR')}` : ''}
                </p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
