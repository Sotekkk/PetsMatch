'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

interface CogeranceRow {
  id: string;
  elevage_profile_id: string;
  uid_gerant: string;
  uid_cogerant: string;
  profile_id_cogerant: string | null;
  invite_par_profile_id: string | null;
  statut: string;
  date_debut: string | null;
  date_fin: string | null;
  _name?: string;
  _photo?: string | null;
  _elevageName?: string;
  _inviteurName?: string;
}

function nomFromProfile(p: { firstname?: string | null; lastname?: string | null; nom?: string | null } | null | undefined) {
  if (!p) return null;
  const n = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
  if (n) return n;
  return p.nom?.trim() || null;
}

function fmtDate(iso: string | null) {
  if (!iso) return '';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('fr-FR');
}

/**
 * Co-gérance d'un élevage — même modèle que l'appli (cogerance_page.dart) :
 * un second compte PetsMatch emprunte le profil élevage du gérant principal
 * (via le sélecteur de profil, auth-context.tsx::fetchCogerances), avec un
 * accès complet lecture/écriture partout. Cette page gère à la fois "mes
 * cogérants" (si j'ai un élevage) et "mes invitations reçues" (tous élevages
 * confondus) — un même compte peut être les deux.
 */
export default function CogerancePage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [myName, setMyName] = useState('Un utilisateur');
  const [elevageProfileId, setElevageProfileId] = useState<string | null>(null);
  const [cogerants, setCogerants] = useState<CogeranceRow[]>([]);
  const [invitationsRecues, setInvitationsRecues] = useState<CogeranceRow[]>([]);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [inviteQuery, setInviteQuery] = useState('');
  const [inviteResults, setInviteResults] = useState<{ uid: string; profileId: string | null; name: string; email: string }[]>([]);
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!user) router.push('/connexion');
  }, [user, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    try {
      const me = await supabase.from('user_profiles').select('id, firstname, lastname, nom')
        .eq('uid', user.uid).eq('profile_type', 'particulier').maybeSingle();
      const n = nomFromProfile(me.data);
      if (n) setMyName(n);

      const elevage = await supabase.from('user_profiles').select('id')
        .eq('uid', user.uid).eq('profile_type', 'eleveur').maybeSingle();
      const eid = (elevage.data?.id as string | undefined) ?? null;
      setElevageProfileId(eid);

      const [cogerantsRes, recuesRes] = await Promise.all([
        eid
          ? supabase.from('elevage_cogerants').select('*')
              .eq('elevage_profile_id', eid).is('date_fin', null).in('statut', ['actif', 'invite'])
          : Promise.resolve({ data: [] as CogeranceRow[] }),
        supabase.from('elevage_cogerants').select('*')
          .eq('uid_cogerant', user.uid).eq('statut', 'invite').is('date_fin', null),
      ]);

      const cogerantsList = (cogerantsRes.data ?? []) as CogeranceRow[];
      const recuesList = (recuesRes.data ?? []) as CogeranceRow[];

      const profileIds = Array.from(new Set([
        ...cogerantsList.map(r => r.profile_id_cogerant).filter(Boolean),
        ...recuesList.map(r => r.elevage_profile_id).filter(Boolean),
        ...recuesList.map(r => r.invite_par_profile_id).filter(Boolean),
      ])) as string[];

      const byId: Record<string, { firstname?: string | null; lastname?: string | null; nom?: string | null; avatar_url?: string | null }> = {};
      if (profileIds.length > 0) {
        const { data: profs } = await supabase.from('user_profiles')
          .select('id, firstname, lastname, nom, avatar_url').in('id', profileIds);
        for (const p of profs ?? []) byId[p.id as string] = p;
      }

      for (const r of cogerantsList) {
        const p = r.profile_id_cogerant ? byId[r.profile_id_cogerant] : null;
        r._name = nomFromProfile(p) ?? 'Utilisateur PetsMatch';
        r._photo = p?.avatar_url ?? null;
      }
      for (const r of recuesList) {
        r._elevageName = nomFromProfile(byId[r.elevage_profile_id]) ?? 'Un élevage';
        r._inviteurName = r.invite_par_profile_id ? (nomFromProfile(byId[r.invite_par_profile_id]) ?? 'Le gérant') : 'Le gérant';
      }

      setCogerants(cogerantsList);
      setInvitationsRecues(recuesList);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function notify(uid: string, profileId: string | null, type: string, title: string, body: string) {
    try {
      await supabase.from('notifications').insert({
        uid, type, title, body,
        ...(profileId ? { profile_id: profileId, recipient_profile_id: profileId } : {}),
        read: false,
        created_at: new Date().toISOString(),
      });
    } catch { /* best-effort */ }
  }

  async function run(action: () => Promise<void>) {
    if (busy) return;
    setBusy(true);
    try {
      await action();
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function searchUsers() {
    const q = inviteQuery.trim();
    if (q.length < 3) return;
    setSearching(true);
    setSearched(true);
    try {
      const usersRes = q.includes('@')
        ? await supabase.from('users').select('uid, firstname, lastname, email').eq('email', q.toLowerCase()).limit(5)
        : await supabase.from('users').select('uid, firstname, lastname, email')
            .or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%`).limit(15);
      const users = (usersRes.data ?? []).filter(u => u.uid !== user?.uid);
      const uids = users.map(u => u.uid as string);
      const profileByUid: Record<string, string> = {};
      if (uids.length > 0) {
        const { data: profs } = await supabase.from('user_profiles').select('uid, id')
          .in('uid', uids).eq('profile_type', 'particulier');
        for (const p of profs ?? []) profileByUid[p.uid as string] = p.id as string;
      }
      setInviteResults(users.map(u => ({
        uid: u.uid as string,
        profileId: profileByUid[u.uid as string] ?? null,
        name: `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || 'Utilisateur PetsMatch',
        email: (u.email as string | null) ?? '',
      })));
    } finally {
      setSearching(false);
    }
  }

  async function inviter(pick: { uid: string; profileId: string | null; name: string }) {
    if (!elevageProfileId) return;
    if (cogerants.some(c => c.uid_cogerant === pick.uid)) {
      alert('Cette personne est déjà cogérante ou invitée.');
      return;
    }
    setShowInviteModal(false);
    setInviteQuery('');
    setInviteResults([]);
    setSearched(false);
    await run(async () => {
      await supabase.from('elevage_cogerants').upsert({
        elevage_profile_id: elevageProfileId,
        uid_gerant: user!.uid,
        uid_cogerant: pick.uid,
        profile_id_cogerant: pick.profileId,
        statut: 'invite',
        invite_par_profile_id: elevageProfileId,
        invite_le: new Date().toISOString(),
      }, { onConflict: 'elevage_profile_id,uid_cogerant' });
      await notify(pick.uid, pick.profileId, 'cogerance_invitation',
        'Invitation de co-gérance', `${myName} vous invite à cogérer son élevage.`);
    });
  }

  async function annulerInvitation(row: CogeranceRow) {
    await run(async () => { await supabase.from('elevage_cogerants').delete().eq('id', row.id); });
  }

  async function resilier(row: CogeranceRow) {
    await run(async () => {
      await supabase.from('elevage_cogerants').update({ date_fin: new Date().toISOString().slice(0, 10) }).eq('id', row.id);
      await notify(row.uid_cogerant, row.profile_id_cogerant, 'cogerance_resiliee',
        'Co-gérance résiliée', `${myName} a mis fin à votre accès de co-gérance sur son élevage.`);
    });
  }

  async function accepter(row: CogeranceRow) {
    await run(async () => {
      const me = await supabase.from('user_profiles').select('id')
        .eq('uid', user!.uid).eq('profile_type', 'particulier').maybeSingle();
      await supabase.from('elevage_cogerants').update({
        statut: 'actif',
        profile_id_cogerant: me.data?.id ?? null,
        date_debut: new Date().toISOString().slice(0, 10),
        accepte_le: new Date().toISOString(),
      }).eq('id', row.id);
      await notify(row.uid_gerant, row.elevage_profile_id, 'cogerance_acceptee',
        'Invitation de co-gérance acceptée', `${myName} a accepté de cogérer votre élevage.`);
    });
  }

  async function refuser(row: CogeranceRow) {
    await run(async () => {
      await supabase.from('elevage_cogerants').update({
        statut: 'refuse', date_fin: new Date().toISOString().slice(0, 10),
      }).eq('id', row.id);
      await notify(row.uid_gerant, row.elevage_profile_id, 'cogerance_refusee',
        'Invitation de co-gérance refusée', `${myName} a refusé votre invitation de co-gérance.`);
    });
  }

  if (loading) return <div className="max-w-2xl mx-auto p-6 text-center text-gray-400">Chargement…</div>;

  return (
    <div className="max-w-2xl mx-auto p-4 sm:p-6">
      <h1 className="text-xl font-bold mb-1" style={{ color: TEAL }}>Co-gérance</h1>
      <p className="text-sm text-gray-500 mb-6">
        Un cogérant a un accès complet lecture/écriture sur tout l&apos;élevage — animaux, chaleurs, employés, agenda, tâches, annonces, signatures.
      </p>

      {invitationsRecues.length > 0 && (
        <div className="mb-8">
          <h2 className="text-base font-bold mb-3" style={{ color: TEAL }}>Invitations reçues</h2>
          <div className="space-y-3">
            {invitationsRecues.map(r => (
              <div key={r.id} className="border rounded-xl p-4 bg-white">
                <p className="text-sm font-semibold text-[#1F2A2E]">{r._inviteurName} vous invite à cogérer {r._elevageName}</p>
                <p className="text-xs text-gray-500 mt-1">Accès complet lecture/écriture sur cet élevage.</p>
                <div className="flex gap-2 mt-3">
                  <button onClick={() => refuser(r)} disabled={busy}
                    className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2 rounded-xl hover:bg-gray-50 disabled:opacity-50">
                    Refuser
                  </button>
                  <button onClick={() => accepter(r)} disabled={busy}
                    className="flex-1 text-white text-sm font-semibold py-2 rounded-xl disabled:opacity-50"
                    style={{ background: GREEN }}>
                    Accepter
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {elevageProfileId ? (
        <div>
          <div className="flex items-center justify-between mb-1">
            <h2 className="text-base font-bold" style={{ color: TEAL }}>Cogérants de mon élevage</h2>
            <button onClick={() => setShowInviteModal(true)}
              className="text-sm font-semibold px-3 py-1.5 rounded-lg text-white" style={{ background: TEAL }}>
              + Inviter
            </button>
          </div>
          {cogerants.length === 0 ? (
            <p className="text-sm text-gray-400 py-6 text-center">Aucun cogérant pour le moment.</p>
          ) : (
            <div className="space-y-2 mt-3">
              {cogerants.map(r => {
                const enAttente = r.statut === 'invite';
                return (
                  <div key={r.id} className="flex items-center gap-3 border rounded-xl p-3 bg-white">
                    <div className="w-10 h-10 rounded-full bg-[#DCEDD5] flex items-center justify-center flex-shrink-0 overflow-hidden">
                      {r._photo ? <img src={r._photo} alt="" className="w-full h-full object-cover" /> : <span>👤</span>}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-[#1F2A2E] truncate">{r._name}</p>
                      <p className={`text-xs ${enAttente ? 'text-orange-600' : 'text-gray-500'}`}>
                        {enAttente ? 'Invitation en attente' : `Cogérant depuis le ${fmtDate(r.date_debut)}`}
                      </p>
                    </div>
                    <button onClick={() => (enAttente ? annulerInvitation(r) : resilier(r))} disabled={busy}
                      title={enAttente ? "Annuler l'invitation" : 'Résilier la co-gérance'}
                      className="text-gray-400 hover:text-red-500 disabled:opacity-50">
                      {enAttente ? '✕' : '🔗✕'}
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      ) : invitationsRecues.length === 0 && (
        <p className="text-sm text-gray-400 text-center py-10">Vous n&apos;avez pas de profil élevage à cogérer.</p>
      )}

      {showInviteModal && (
        <div className="fixed inset-0 bg-black/40 flex items-end sm:items-center justify-center z-50"
          onClick={() => setShowInviteModal(false)}>
          <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md max-h-[90vh] overflow-y-auto p-5"
            onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-2">
              <h3 className="font-bold text-base text-[#1F2A2E]">Inviter un cogérant</h3>
              <button onClick={() => setShowInviteModal(false)} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
            </div>
            <p className="text-xs text-gray-500 mb-3">Saisissez l&apos;adresse e-mail exacte de la personne (ou son nom).</p>
            <div className="flex gap-2 mb-4">
              <input value={inviteQuery} onChange={e => setInviteQuery(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && searchUsers()}
                placeholder="E-mail ou nom" autoFocus
                className="flex-1 border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              <button onClick={searchUsers} disabled={searching}
                className="px-4 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
                OK
              </button>
            </div>
            {searching ? (
              <p className="text-center text-gray-400 py-6">Recherche…</p>
            ) : searched && inviteResults.length === 0 ? (
              <p className="text-center text-gray-400 py-6">Aucun compte PetsMatch trouvé.</p>
            ) : (
              <div className="space-y-1">
                {inviteResults.map(u => (
                  <button key={u.uid} onClick={() => inviter(u)}
                    className="w-full flex items-center gap-3 px-2 py-2.5 rounded-xl hover:bg-gray-50 text-left">
                    <div className="w-9 h-9 rounded-full bg-[#E4E7E2] flex items-center justify-center flex-shrink-0">👤</div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-[#1F2A2E] truncate">{u.name}</p>
                      <p className="text-xs text-gray-500 truncate">{u.email}</p>
                    </div>
                    <span style={{ color: GREEN }}>+</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
