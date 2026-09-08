'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import Link from 'next/link';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { usePlanGarde } from '@/lib/use-plan';
import { sendNotification } from '@/lib/notifications';

interface Client {
  uid: string;
  nom: string;
  email: string;
  profileId: string | null;
  doc?: Doc;
}

interface Doc {
  id: string;
  token: string | null;
  statut: string;
}

const STATUT_META: Record<string, { label: string; cls: string }> = {
  brouillon:           { label: 'Brouillon',            cls: 'bg-gray-100 text-gray-500' },
  en_attente:          { label: '⏳ Attente signature',  cls: 'bg-amber-100 text-amber-700' },
  partiellement_signe: { label: '✍️ Partiel',            cls: 'bg-blue-100 text-blue-700' },
  signe:               { label: '✅ Signé',              cls: 'bg-green-100 text-green-700' },
  annule:              { label: '🚫 Annulé',             cls: 'bg-red-100 text-red-500' },
  refuse:              { label: '❌ Refusé',             cls: 'bg-red-100 text-red-700' },
};

export default function GardeContratPage() {
  const { user, userData, isGarde, loading: authLoading } = useGardeAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const { plan: gardePlan } = usePlanGarde();
  const [clients, setClients] = useState<Client[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isGarde) { router.push('/'); return; }
  }, [user, userData, isGarde, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let rdvQ = supabase.from('rdv').select('client_uid, client_profile_id').eq('pro_uid', user.uid);
    if (activeProfileId) rdvQ = rdvQ.eq('pro_profile_id', activeProfileId) as typeof rdvQ;
    let docQ = supabase.from('documents_animaux').select('id, token, statut, metadata')
      .eq('uid_eleveur', user.uid).eq('type', 'contrat_garde');
    if (activeProfileId) docQ = docQ.eq('pro_profile_id', activeProfileId) as typeof docQ;

    const [{ data: rows }, { data: docsData }] = await Promise.all([
      rdvQ.in('statut', ['confirme', 'termine']),
      docQ,
    ]);
    const rowsList = (rows ?? []) as { client_uid: string | null; client_profile_id: string | null }[];
    // client_uid → client_profile_id (le profil qui a réservé — jamais is_main,
    // qui renverrait le profil éleveur d'un compte multi-profils).
    const uniq = new Map<string, string | null>();
    for (const r of rowsList) if (r.client_uid) uniq.set(r.client_uid, r.client_profile_id ?? uniq.get(r.client_uid) ?? null);
    const clientUids = [...uniq.keys()];
    const clientPids = [...new Set([...uniq.values()].filter((p): p is string => !!p))];
    const uidsNoPid = clientUids.filter(u => !uniq.get(u));

    type Prof = { id: string; uid: string; firstname: string | null; lastname: string | null; nom: string | null; email_contact: string | null };
    const [{ data: byPid }, { data: byUid }] = await Promise.all([
      clientPids.length
        ? supabase.from('user_profiles').select('id, uid, firstname, lastname, nom, email_contact').in('id', clientPids)
        : Promise.resolve({ data: [] as Prof[] }),
      uidsNoPid.length
        ? supabase.from('user_profiles').select('id, uid, firstname, lastname, nom, email_contact').in('uid', uidsNoPid).eq('is_main', true)
        : Promise.resolve({ data: [] as Prof[] }),
    ]);
    const nomOf = (c: Prof) => c.nom?.trim() || `${c.firstname ?? ''} ${c.lastname ?? ''}`.trim() || 'Client';
    const nameByPid = new Map((byPid ?? []).map(c => [c.id, nomOf(c)]));
    const emailByPid = new Map((byPid ?? []).map(c => [c.id, c.email_contact ?? '']));
    const nameByUid = new Map((byUid ?? []).map(c => [c.uid, nomOf(c)]));
    const emailByUid = new Map((byUid ?? []).map(c => [c.uid, c.email_contact ?? '']));

    const docByClient = new Map<string, Doc>();
    for (const d of (docsData ?? []) as (Doc & { metadata: Record<string, unknown> })[]) {
      const cu = (d.metadata?.client_uid as string | undefined) ?? '';
      if (cu) docByClient.set(cu, { id: d.id, token: d.token, statut: d.statut });
    }

    setClients(clientUids.map(uid => {
      const pid = uniq.get(uid) ?? null;
      return {
        uid,
        nom: (pid && nameByPid.get(pid)) || nameByUid.get(uid) || 'Client',
        email: (pid && emailByPid.get(pid)) || emailByUid.get(uid) || '',
        profileId: pid,
        doc: docByClient.get(uid),
      };
    }).sort((a, b) => a.nom.localeCompare(b.nom)));
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function ouvrirContrat(c: Client) {
    if (!user) return;
    setBusy(c.uid);
    try {
      let token = c.doc?.token ?? null;
      if (!token) {
        const { data } = await supabase.from('documents_animaux').insert({
          uid_eleveur: user.uid,
          ...(activeProfileId ? { pro_profile_id: activeProfileId } : {}),
          type: 'contrat_garde',
          titre: `Contrat de prestation — ${c.nom}`,
          statut: 'brouillon',
          metadata: {
            client_nom: c.nom,
            client_uid: c.uid,
            ...(c.profileId ? { client_profile_id: c.profileId } : {}),
            ...(c.email ? { client_email: c.email } : {}),
          },
        }).select('token').single();
        token = (data?.token as string | null) ?? null;
      }
      if (token) window.open(`/signer-contrat/${token}`, '_blank');
      await load();
    } finally {
      setBusy(null);
    }
  }

  async function transmettre(c: Client) {
    if (!user || !c.doc?.token) return;
    setBusy(c.uid);
    try {
      await supabase.from('documents_animaux').update({ statut: 'en_attente' }).eq('id', c.doc.id);
      const signingUrl = `${window.location.origin}/signer-contrat/${c.doc.token}`;
      const gardeNom = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Votre pet sitter';
      await sendNotification({
        uid: c.uid, type: 'contrat_invite',
        title: '📄 Contrat à signer',
        body: `${gardeNom} vous envoie le contrat de prestation — vérifiez et signez. Il couvre toutes vos gardes.`,
        data: { token: c.doc.token, url: signingUrl },
      });
      await navigator.clipboard.writeText(signingUrl).catch(() => {});
      alert(`Contrat transmis ! Lien copié :\n${signingUrl}`);
      await load();
    } finally {
      setBusy(null);
    }
  }

  async function envoyerParEmail(c: Client) {
    if (!c.doc?.token || !c.email) return;
    setBusy(c.uid);
    const signingUrl = `${window.location.origin}/signer-contrat/${c.doc.token}`;
    const gardeNom = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Votre pet sitter';
    try {
      const res = await fetch('/api/contrat/notify-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: c.email, client_nom: c.nom, pro_nom: gardeNom,
          titre: 'Contrat de prestation', signing_url: signingUrl,
        }),
      });
      alert(res.ok ? 'Email envoyé au client.' : 'Erreur lors de l\'envoi de l\'email.');
    } finally {
      setBusy(null);
    }
  }

  if (!user || !userData) return null;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
      <h1 className="text-2xl font-bold font-galey text-teal-800">Contrats de prestation</h1>
      <p className="text-sm text-gray-500 font-galey">
        Un seul contrat par client — signé une fois, il couvre toutes ses gardes.
      </p>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : clients.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📋</p>
          <p className="font-galey">Aucun client — un RDV confirmé est requis.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {clients.map(c => {
            const meta = c.doc ? STATUT_META[c.doc.statut] ?? STATUT_META.brouillon : null;
            const isDraft = !c.doc || c.doc.statut === 'brouillon';
            return (
              <div key={c.uid} className="bg-white rounded-2xl shadow-sm p-4 border border-gray-100 flex items-center justify-between gap-4">
                <p className="font-bold font-galey text-gray-900">{c.nom}</p>
                <div className="flex items-center gap-2 flex-shrink-0">
                  {meta && (
                    <span className={`text-xs font-galey font-bold px-2.5 py-1 rounded-full ${meta.cls}`}>{meta.label}</span>
                  )}
                  {!c.doc ? (
                    <button onClick={() => ouvrirContrat(c)} disabled={busy === c.uid}
                      className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
                      {busy === c.uid ? '…' : 'Générer le contrat'}
                    </button>
                  ) : isDraft ? (
                    <button onClick={() => transmettre(c)} disabled={busy === c.uid}
                      className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
                      Envoyer pour signature
                    </button>
                  ) : (
                    <a href={`/signer-contrat/${c.doc.token}`} target="_blank" rel="noopener noreferrer"
                      className="border border-teal-200 text-teal-700 px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-50">
                      Voir le contrat
                    </a>
                  )}
                  {c.doc && c.doc.statut !== 'brouillon' && c.doc.statut !== 'signe' && c.email && (
                    gardePlan !== 'free' ? (
                      <button onClick={() => envoyerParEmail(c)} disabled={busy === c.uid}
                        className="border border-gray-200 text-gray-600 px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-gray-50 disabled:opacity-50">
                        {busy === c.uid ? '…' : '📧 Par email'}
                      </button>
                    ) : (
                      <Link href="/garde/abonnement"
                        className="text-xs font-galey text-amber-600 hover:underline whitespace-nowrap">
                        🔒 Email (Pro)
                      </Link>
                    )
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
