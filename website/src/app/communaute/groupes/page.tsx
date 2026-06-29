'use client';

import Link from 'next/link';
import { useState, useEffect, useCallback } from 'react';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const TYPE_LABELS: Record<string, string> = {
  race: 'Race',
  region: 'Région',
  loisir: 'Loisir',
  autre: 'Autre',
};

const TYPE_COLORS: Record<string, string> = {
  race: '#6E9E57',
  region: '#1E88E5',
  loisir: '#EF6C00',
  autre: '#00ACC1',
};

interface Groupe {
  id: string;
  nom: string;
  description: string;
  type: string;
  prive: boolean;
  createur_uid: string;
  created_at: string;
  regles: string[];
}

interface CreateGroupeData {
  nom: string;
  description: string;
  type: string;
  prive: boolean;
  regles: string[];
}

export default function GroupesPage() {
  const { user } = useAuth();
  const profileId = useActiveProfile();
  const [groupes, setGroupes] = useState<Groupe[]>([]);
  const [mesGroupes, setMesGroupes] = useState<Set<string>>(new Set());
  const [pendingGroupes, setPendingGroupes] = useState<Set<string>>(new Set());
  const [friendCounts, setFriendCounts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'tous' | 'mes'>('tous');
  const [filterType, setFilterType] = useState<string>('');
  const [showCreate, setShowCreate] = useState(false);
  const [createData, setCreateData] = useState<CreateGroupeData>({
    nom: '', description: '', type: 'autre', prive: false, regles: [],
  });
  const [newRegle, setNewRegle] = useState('');
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data: gData } = await supabase
        .from('groupes')
        .select('*')
        .order('created_at', { ascending: false });

      let mes = new Set<string>();
      let pending = new Set<string>();
      let fCounts: Record<string, number> = {};

      if (user?.uid) {
        // Mes appartenances
        let memQuery = supabase.from('groupes_membres').select('groupe_id, statut');
        if (profileId) {
          memQuery = memQuery.eq('profile_id', profileId) as typeof memQuery;
        } else {
          memQuery = memQuery.eq('user_uid', user.uid) as typeof memQuery;
        }
        const { data: memData } = await memQuery;
        for (const m of memData ?? []) {
          if (m.statut === 'active') mes.add(m.groupe_id);
          if (m.statut === 'pending') pending.add(m.groupe_id);
        }

        // Mes amis
        const { data: friendsData } = await supabase
          .from('petfriends')
          .select('uid_demandeur, uid_recepteur')
          .or(`uid_demandeur.eq.${user.uid},uid_recepteur.eq.${user.uid}`)
          .eq('statut', 'accepte');

        const friendUids = (friendsData ?? []).map((f) =>
          f.uid_demandeur === user.uid ? f.uid_recepteur : f.uid_demandeur
        );

        if (friendUids.length > 0) {
          const { data: allMems } = await supabase
            .from('groupes_membres')
            .select('groupe_id, user_uid')
            .in('user_uid', friendUids)
            .eq('statut', 'active');
          for (const m of allMems ?? []) {
            fCounts[m.groupe_id] = (fCounts[m.groupe_id] ?? 0) + 1;
          }
        }
      }

      setGroupes((gData ?? []) as Groupe[]);
      setMesGroupes(mes);
      setPendingGroupes(pending);
      setFriendCounts(fCounts);
    } finally {
      setLoading(false);
    }
  }, [user?.uid, profileId]);

  useEffect(() => { load(); }, [load]);

  async function toggleMembership(groupe: Groupe) {
    if (!user?.uid) return;
    const isMembre = mesGroupes.has(groupe.id);
    const isPending = pendingGroupes.has(groupe.id);

    if (isMembre || isPending) {
      await supabase.from('groupes_membres').delete()
        .eq('groupe_id', groupe.id).eq('user_uid', user.uid);
      setMesGroupes(prev => { const s = new Set(prev); s.delete(groupe.id); return s; });
      setPendingGroupes(prev => { const s = new Set(prev); s.delete(groupe.id); return s; });
    } else {
      const statut = groupe.prive ? 'pending' : 'active';
      await supabase.from('groupes_membres').insert({
        groupe_id: groupe.id,
        user_uid: user.uid,
        ...(profileId ? { profile_id: profileId } : {}),
        role: 'membre',
        statut,
        rejoint_at: new Date().toISOString(),
      });
      if (groupe.prive) {
        setPendingGroupes(prev => new Set([...prev, groupe.id]));
      } else {
        setMesGroupes(prev => new Set([...prev, groupe.id]));
      }
    }
  }

  async function createGroupe() {
    if (!user?.uid || !createData.nom.trim()) return;
    setSaving(true);
    try {
      const { data: inserted } = await supabase.from('groupes').insert({
        createur_uid: user.uid,
        ...(profileId ? { createur_profile_id: profileId } : {}),
        nom: createData.nom.trim(),
        description: createData.description.trim(),
        type: createData.type,
        prive: createData.prive,
        regles: createData.regles,
        created_at: new Date().toISOString(),
      }).select().single();

      if (inserted) {
        await supabase.from('groupes_membres').insert({
          groupe_id: inserted.id,
          user_uid: user.uid,
          ...(profileId ? { profile_id: profileId } : {}),
          role: 'admin',
          statut: 'active',
          rejoint_at: new Date().toISOString(),
        });
        setMesGroupes(prev => new Set([...prev, inserted.id]));
      }
      setShowCreate(false);
      setCreateData({ nom: '', description: '', type: 'autre', prive: false, regles: [] });
      load();
    } finally {
      setSaving(false);
    }
  }

  const displayed = groupes.filter(g => {
    if (tab === 'mes' && !mesGroupes.has(g.id)) return false;
    if (filterType && g.type !== filterType) return false;
    return true;
  });

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Hero */}
      <div className="bg-[#0C5C6C] text-white px-4 py-10">
        <div className="max-w-2xl mx-auto text-center">
          <p className="text-4xl mb-3">👥</p>
          <h1 className="text-2xl font-bold mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Groupes communauté
          </h1>
          <p className="text-white/70 text-sm">
            Rejoignez des groupes par race, région, loisir… et échangez avec des passionnés.
          </p>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* Tabs */}
        <div className="flex gap-2 mb-5">
          {(['tous', 'mes'] as const).map(t => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`px-4 py-2 rounded-full text-sm font-semibold transition-colors ${
                tab === t ? 'bg-[#00ACC1] text-white' : 'bg-white text-gray-600 border border-gray-200'
              }`}
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              {t === 'tous' ? 'Tous les groupes' : 'Mes groupes'}
            </button>
          ))}
          <div className="flex-1" />
          {user && (
            <button
              onClick={() => setShowCreate(true)}
              className="px-4 py-2 rounded-full text-sm font-semibold bg-[#00ACC1] text-white flex items-center gap-1"
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              <span className="text-lg leading-none">+</span> Créer
            </button>
          )}
        </div>

        {/* Filtres par type */}
        <div className="flex gap-2 flex-wrap mb-5">
          <button
            onClick={() => setFilterType('')}
            className={`px-3 py-1 rounded-full text-xs font-semibold border transition-colors ${
              !filterType ? 'bg-[#00ACC1] text-white border-[#00ACC1]' : 'bg-white text-gray-600 border-gray-200'
            }`}
          >
            Tous
          </button>
          {Object.entries(TYPE_LABELS).map(([k, v]) => (
            <button
              key={k}
              onClick={() => setFilterType(filterType === k ? '' : k)}
              className={`px-3 py-1 rounded-full text-xs font-semibold border transition-colors ${
                filterType === k ? 'text-white border-transparent' : 'bg-white text-gray-600 border-gray-200'
              }`}
              style={filterType === k ? { backgroundColor: TYPE_COLORS[k] } : {}}
            >
              {v}
            </button>
          ))}
        </div>

        {/* Liste */}
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-2 border-[#00ACC1] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : displayed.length === 0 ? (
          <div className="text-center py-20">
            <p className="text-4xl mb-4">👥</p>
            <p className="text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
              {tab === 'mes' ? 'Vous n\'avez rejoint aucun groupe' : 'Aucun groupe pour l\'instant'}
            </p>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {displayed.map(g => {
              const isMembre = mesGroupes.has(g.id);
              const isPending = pendingGroupes.has(g.id);
              const fCount = friendCounts[g.id] ?? 0;
              const color = TYPE_COLORS[g.type] ?? '#00ACC1';

              return (
                <div key={g.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
                  <div className="p-4">
                    <div className="flex items-start gap-3">
                      <div className="w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0" style={{ backgroundColor: color + '20' }}>
                        <span className="text-2xl">
                          {g.type === 'race' ? '🐾' : g.type === 'region' ? '📍' : g.type === 'loisir' ? '🎯' : '💬'}
                        </span>
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <Link
                            href={`/communaute/groupes/${g.id}`}
                            className="font-bold text-[#1E2025] hover:text-[#00ACC1] transition-colors"
                            style={{ fontFamily: 'Galey, sans-serif' }}
                          >
                            {g.nom}
                          </Link>
                          {g.prive && <span className="text-xs text-gray-400">🔒 Privé</span>}
                        </div>
                        <span
                          className="inline-block text-xs font-semibold px-2 py-0.5 rounded-full mt-1"
                          style={{ backgroundColor: color + '20', color }}
                        >
                          {TYPE_LABELS[g.type] ?? g.type}
                        </span>
                        {g.description && (
                          <p className="text-sm text-gray-500 mt-2 line-clamp-2" style={{ fontFamily: 'Galey, sans-serif' }}>
                            {g.description}
                          </p>
                        )}
                        {fCount > 0 && (
                          <p className="text-xs text-[#00ACC1] font-semibold mt-2">
                            👤 {fCount === 1 ? '1 ami dans ce groupe' : `${fCount} amis dans ce groupe`}
                          </p>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-2 mt-3">
                      <Link
                        href={`/communaute/groupes/${g.id}`}
                        className="flex-1 text-center py-2 rounded-xl text-sm font-semibold border border-[#00ACC1] text-[#00ACC1] hover:bg-[#E0F7FA] transition-colors"
                        style={{ fontFamily: 'Galey, sans-serif' }}
                      >
                        Voir le groupe
                      </Link>
                      {user && (
                        <button
                          onClick={() => toggleMembership(g)}
                          className={`flex-1 py-2 rounded-xl text-sm font-semibold transition-colors ${
                            isMembre
                              ? 'bg-[#00ACC1] text-white'
                              : isPending
                              ? 'bg-orange-50 text-orange-600 border border-orange-200'
                              : 'bg-[#E0F7FA] text-[#00ACC1]'
                          }`}
                          style={{ fontFamily: 'Galey, sans-serif' }}
                        >
                          {isMembre ? 'Membre ✓' : isPending ? 'En attente…' : g.prive ? 'Demander' : 'Rejoindre'}
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Modal création */}
      {showCreate && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4">
          <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
            <div className="p-6">
              <div className="flex items-center justify-between mb-5">
                <h2 className="text-lg font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>Créer un groupe</h2>
                <button onClick={() => setShowCreate(false)} className="text-gray-400 hover:text-gray-600">✕</button>
              </div>

              <div className="flex flex-col gap-4">
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Nom du groupe *</label>
                  <input
                    value={createData.nom}
                    onChange={e => setCreateData(d => ({ ...d, nom: e.target.value }))}
                    placeholder="Ex : Bergers Australiens France"
                    className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#00ACC1]"
                    style={{ fontFamily: 'Galey, sans-serif' }}
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Type</label>
                  <select
                    value={createData.type}
                    onChange={e => setCreateData(d => ({ ...d, type: e.target.value }))}
                    className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#00ACC1]"
                    style={{ fontFamily: 'Galey, sans-serif' }}
                  >
                    {Object.entries(TYPE_LABELS).map(([k, v]) => (
                      <option key={k} value={k}>{v}</option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Description</label>
                  <textarea
                    value={createData.description}
                    onChange={e => setCreateData(d => ({ ...d, description: e.target.value }))}
                    placeholder="Thème, objectifs du groupe…"
                    rows={3}
                    className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#00ACC1] resize-none"
                    style={{ fontFamily: 'Galey, sans-serif' }}
                  />
                </div>

                {/* Règles */}
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Règles du groupe</label>
                  {createData.regles.length > 0 && (
                    <ul className="mb-2 flex flex-col gap-1">
                      {createData.regles.map((r, i) => (
                        <li key={i} className="flex items-center gap-2 text-sm">
                          <span className="w-5 h-5 rounded-full bg-[#00ACC1] text-white text-xs flex items-center justify-center font-bold flex-shrink-0">{i + 1}</span>
                          <span className="flex-1 text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>{r}</span>
                          <button onClick={() => setCreateData(d => ({ ...d, regles: d.regles.filter((_, j) => j !== i) }))} className="text-red-400 hover:text-red-600 text-xs">✕</button>
                        </li>
                      ))}
                    </ul>
                  )}
                  <div className="flex gap-2">
                    <input
                      value={newRegle}
                      onChange={e => setNewRegle(e.target.value)}
                      onKeyDown={e => {
                        if (e.key === 'Enter' && newRegle.trim()) {
                          setCreateData(d => ({ ...d, regles: [...d.regles, newRegle.trim()] }));
                          setNewRegle('');
                          e.preventDefault();
                        }
                      }}
                      placeholder="Ajouter une règle (Entrée pour valider)"
                      className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#00ACC1]"
                      style={{ fontFamily: 'Galey, sans-serif' }}
                    />
                    <button
                      onClick={() => {
                        if (newRegle.trim()) {
                          setCreateData(d => ({ ...d, regles: [...d.regles, newRegle.trim()] }));
                          setNewRegle('');
                        }
                      }}
                      className="px-3 py-2 bg-[#E0F7FA] text-[#00ACC1] rounded-xl font-bold text-sm"
                    >
                      +
                    </button>
                  </div>
                </div>

                {/* Privé */}
                <label className="flex items-center gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={createData.prive}
                    onChange={e => setCreateData(d => ({ ...d, prive: e.target.checked }))}
                    className="w-4 h-4 accent-[#00ACC1]"
                  />
                  <div>
                    <p className="text-sm font-semibold text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>Groupe privé</p>
                    <p className="text-xs text-gray-400">Membres approuvés uniquement</p>
                  </div>
                </label>

                <button
                  onClick={createGroupe}
                  disabled={saving || !createData.nom.trim()}
                  className="w-full py-3 bg-[#00ACC1] text-white rounded-xl font-bold text-sm disabled:opacity-50 transition-opacity"
                  style={{ fontFamily: 'Galey, sans-serif' }}
                >
                  {saving ? 'Création…' : 'Créer le groupe'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
