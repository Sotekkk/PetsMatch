'use client';

// Mon profil → Notifications : choisir les notifications du forum (réponses,
// citations). Table preferences_notifications, lue par les triggers du forum
// (migration_forum_notifs_preferences.sql) : une notification refusée n'est
// ni créée ni envoyée en push.
// Miroir appli : lib/pages/settings/preferences_notifications_page.dart.

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

function Interrupteur({ titre, detail, valeur, onChange }: { titre: string; detail: string; valeur: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="flex items-center gap-4 px-5 py-4 cursor-pointer">
      <div className="flex-1">
        <p className="font-semibold text-sm text-[#1F2A2E]">{titre}</p>
        <p className="text-xs text-gray-500">{detail}</p>
      </div>
      <input type="checkbox" role="switch" checked={valeur} onChange={e => onChange(e.target.checked)}
        className="w-10 h-5 accent-[#0C5C6C] cursor-pointer" />
    </label>
  );
}

export default function PreferencesNotificationsPage() {
  const { user, loading } = useAuth();
  const [charge, setCharge] = useState(false);
  const [prefs, setPrefs] = useState({ forum_reponses: true, forum_mentions: true });
  const [sujetsMuets, setSujetsMuets] = useState(0);
  const [erreur, setErreur] = useState('');

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('preferences_notifications').select('forum_reponses, forum_mentions').eq('uid', user.uid).maybeSingle(),
      supabase.from('forum_sujets_muets').select('sujet_id').eq('uid', user.uid),
    ]).then(([p, m]) => {
      if (p.data) setPrefs({ forum_reponses: p.data.forum_reponses !== false, forum_mentions: p.data.forum_mentions !== false });
      setSujetsMuets((m.data ?? []).length);
      setCharge(true);
    });
  }, [user]);

  async function changer(patch: Partial<typeof prefs>) {
    if (!user) return;
    const avant = prefs;
    const suivant = { ...prefs, ...patch };
    setPrefs(suivant); setErreur('');
    const { error } = await supabase.from('preferences_notifications')
      .upsert({ uid: user.uid, ...suivant, updated_at: new Date().toISOString() });
    if (error) { setPrefs(avant); setErreur(`Enregistrement impossible : ${error.message}`); }
  }

  async function reactiverSujets() {
    if (!user) return;
    await supabase.from('forum_sujets_muets').delete().eq('uid', user.uid);
    setSujetsMuets(0);
  }

  if (loading) return null;
  if (!user) {
    return (
      <div className="max-w-xl mx-auto px-4 py-16 text-center" style={{ fontFamily: 'Galey, sans-serif' }}>
        <Link href="/connexion?suite=/profil/notifications" className="inline-block px-5 py-2.5 rounded-xl bg-[#0C5C6C] text-white font-semibold">Se connecter</Link>
      </div>
    );
  }

  return (
    <div className="bg-[#F4F7F6] min-h-screen pb-16" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="bg-[#0C5C6C] text-white"><div className="max-w-2xl mx-auto px-4 py-6">
        <Link href="/profil" className="text-white/75 text-sm hover:underline">← Mon profil</Link>
        <h1 className="text-2xl font-bold mt-1">Notifications</h1>
        <p className="text-white/75 text-sm">Choisissez les notifications que vous recevez.</p>
      </div></div>
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-3">
        {!charge ? <p className="text-sm text-gray-500">Chargement…</p> : (<>
          <h2 className="text-lg font-bold text-[#1F2A2E]">Forum</h2>
          <div className="bg-white rounded-2xl shadow-sm divide-y">
            <Interrupteur titre="Réponses" detail="Quand quelqu’un répond à un sujet que vous avez créé ou auquel vous avez participé"
              valeur={prefs.forum_reponses} onChange={v => changer({ forum_reponses: v })} />
            <Interrupteur titre="Citations" detail="Quand quelqu’un vous cite (@votre nom) dans un sujet ou une réponse"
              valeur={prefs.forum_mentions} onChange={v => changer({ forum_mentions: v })} />
          </div>
          {erreur && <p className="text-sm text-red-600">{erreur}</p>}
          <p className="text-xs text-gray-500 px-1">Vous pouvez aussi couper les notifications d’un seul sujet depuis la discussion.</p>
          {sujetsMuets > 0 && (
            <div className="flex items-center justify-between px-1">
              <p className="text-sm text-gray-700">{sujetsMuets} sujet{sujetsMuets > 1 ? 's' : ''} sans notification</p>
              <button type="button" onClick={reactiverSujets} className="text-sm font-bold text-[#0C5C6C] hover:underline">Tout réactiver</button>
            </div>
          )}
        </>)}
      </div>
    </div>
  );
}
