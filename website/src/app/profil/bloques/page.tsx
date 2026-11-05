'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { debloquer, mesBloques } from '@/lib/blocages';
import { useAuth } from '@/lib/auth-context';

interface BlockedUser {
  id: string;
  name: string;
  avatar?: string;
}

export default function BloquesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [users, setUsers] = useState<BlockedUser[]>([]);
  const [fetching, setFetching] = useState(true);
  const [confirming, setConfirming] = useState<string | null>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    (async () => {
      // Blocages de la messagerie (Supabase) + ancienne liste du fil (Firestore).
      const ids = await mesBloques(user.uid);
      const list: BlockedUser[] = [];
      type Profil = { nom: string | null; firstname: string | null; lastname: string | null; avatar_url: string | null; profile_type: string | null };
      const cols = 'nom, firstname, lastname, avatar_url, profile_type';
      for (const id of ids) {
        // Le profil de la dernière conversation avec cette personne, sinon son profil
        // principal. Compte introuvable : affiché quand même, pour pouvoir le débloquer.
        const { data: conv } = await supabase.from('conversations').select('pro_profile_id, consumer_profile_id')
          .contains('participants', [user.uid, id]).order('updated_at', { ascending: false }).limit(1).maybeSingle();
        const c = conv as { pro_profile_id?: string | null; consumer_profile_id?: string | null } | null;
        const pids = [c?.pro_profile_id, c?.consumer_profile_id].filter((x): x is string => !!x);
        const { data: duConv } = pids.length
          ? await supabase.from('user_profiles_complet').select(cols).in('id', pids).eq('uid', id).limit(1).maybeSingle()
          : { data: null };
        const { data: principal } = duConv ? { data: null }
          : await supabase.from('user_profiles_complet').select(cols).eq('uid', id).eq('is_main', true).limit(1).maybeSingle();
        const p = (duConv ?? principal) as Profil | null;
        const personne = `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim();
        const structure = p?.profile_type && p.profile_type !== 'particulier' ? p.nom?.trim() : '';
        const avatar = p?.avatar_url ?? '';
        list.push({ id, name: structure || personne || p?.nom?.trim() || 'Utilisateur', avatar: avatar.startsWith('http') ? avatar : undefined });
      }
      setUsers(list);
      setFetching(false);
    })();
  }, [user]);

  async function unblock(otherId: string) {
    if (!user) return;
    try {
      await debloquer(user.uid, otherId);
    } catch {
      alert('Déblocage impossible, réessayez.');
      return;
    }
    setUsers(prev => prev.filter(u => u.id !== otherId));
    setConfirming(null);
  }

  if (loading || fetching) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="max-w-lg mx-auto px-4 py-8">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.back()} className="p-2 rounded-full hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7"/>
          </svg>
        </button>
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Utilisateurs bloqués
        </h1>
      </div>

      {users.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <p className="text-5xl mb-4">🚫</p>
          <p className="text-gray-500 font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun utilisateur bloqué</p>
          <p className="text-gray-400 text-sm mt-1">Les utilisateurs que vous bloquez apparaîtront ici.</p>
        </div>
      ) : (
        <div className="space-y-3">
          <p className="text-sm text-gray-400 mb-4">{users.length} utilisateur{users.length > 1 ? 's' : ''} bloqué{users.length > 1 ? 's' : ''}</p>
          {users.map(u => (
            <div key={u.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-3 flex items-center gap-3">
              <div className="w-11 h-11 rounded-full bg-[#6E9E57] flex-shrink-0 flex items-center justify-center overflow-hidden relative">
                {u.avatar ? (
                  <Image src={u.avatar} alt="" fill className="object-cover" />
                ) : (
                  <span className="text-white font-bold">{(u.name[0] ?? '?').toUpperCase()}</span>
                )}
              </div>
              <span className="flex-1 font-semibold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
                {u.name}
              </span>
              <button
                onClick={() => setConfirming(u.id)}
                className="px-4 py-1.5 bg-[#E6F4F7] text-[#0C5C6C] text-sm font-semibold rounded-full hover:bg-[#CCE8F0] transition-colors"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Débloquer
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Modal confirmation */}
      {confirming && (() => {
        const u = users.find(x => x.id === confirming);
        if (!u) return null;
        return (
          <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl shadow-xl p-6 max-w-sm w-full">
              <h2 className="font-bold text-lg mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Débloquer {u.name} ?</h2>
              <p className="text-gray-500 text-sm mb-5">Vous recevrez à nouveau ses messages et il pourra voir votre profil.</p>
              <div className="flex gap-3">
                <button
                  onClick={() => setConfirming(null)}
                  className="flex-1 py-2.5 rounded-xl border border-gray-200 text-gray-600 font-medium text-sm hover:bg-gray-50">
                  Annuler
                </button>
                <button
                  onClick={() => unblock(u.id)}
                  className="flex-1 py-2.5 rounded-xl bg-[#0C5C6C] text-white font-semibold text-sm hover:bg-[#094F5D]">
                  Débloquer
                </button>
              </div>
            </div>
          </div>
        );
      })()}
    </div>
  );
}
