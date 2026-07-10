'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import Link from 'next/link';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { usePlanGarde } from '@/lib/use-plan';
import { sendNotification } from '@/lib/notifications';

interface Rdv {
  id: string;
  animal_id: string | null;
  client_uid: string | null;
  date_heure: string;
  statut: string;
  _animal_nom?: string;
  _client_nom?: string;
  _client_email?: string;
}

interface Doc {
  id: string;
  rdv_id: string;
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
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [docs, setDocs] = useState<Record<string, Doc>>({});
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState<string | null>(null);
  const [sendingEmail, setSendingEmail] = useState<string | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isGarde) { router.push('/'); return; }
  }, [user, userData, isGarde, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let q = supabase.from('rdv').select('id, animal_id, client_uid, date_heure, statut').eq('pro_uid', user.uid);
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId) as typeof q;
    const [{ data: rows }, { data: docsData }] = await Promise.all([
      q.in('statut', ['confirme', 'termine']).order('date_heure', { ascending: false }).limit(50),
      supabase.from('documents_animaux').select('id, rdv_id, token, statut').eq('uid_eleveur', user.uid).eq('type', 'contrat_garde'),
    ]);
    const rowsList = (rows ?? []) as Rdv[];
    const clientUids = [...new Set(rowsList.map(r => r.client_uid).filter((u): u is string => !!u))];
    const animalIds = [...new Set(rowsList.map(r => r.animal_id).filter((a): a is string => !!a))];
    const [{ data: clients }, { data: animaux }] = await Promise.all([
      clientUids.length
        ? supabase.from('user_profiles').select('uid, firstname, lastname, nom, email_contact').in('uid', clientUids).eq('is_main', true)
        : Promise.resolve({ data: [] as { uid: string; firstname: string | null; lastname: string | null; nom: string | null; email_contact: string | null }[] }),
      animalIds.length
        ? supabase.from('animaux').select('id, nom').in('id', animalIds)
        : Promise.resolve({ data: [] as { id: string; nom: string | null }[] }),
    ]);
    const clientNames = new Map((clients ?? []).map(c => {
      const nom = c.nom?.trim();
      const full = nom || `${c.firstname ?? ''} ${c.lastname ?? ''}`.trim();
      return [c.uid, full || 'Client'];
    }));
    const clientEmails = new Map((clients ?? []).map(c => [c.uid, c.email_contact ?? '']));
    const animalNames = new Map((animaux ?? []).map(a => [a.id, a.nom ?? '']));
    setRdvs(rowsList.map(r => ({
      ...r,
      _client_nom: r.client_uid ? clientNames.get(r.client_uid) ?? 'Client' : 'Client',
      _client_email: r.client_uid ? clientEmails.get(r.client_uid) ?? '' : '',
      _animal_nom: r.animal_id ? animalNames.get(r.animal_id) ?? '' : '',
    })));
    setDocs(Object.fromEntries(((docsData ?? []) as Doc[]).map(d => [d.rdv_id, d])));
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function genererContrat(r: Rdv) {
    if (!user) return;
    setGenerating(r.id);
    const { data } = await supabase.from('documents_animaux').insert({
      uid_eleveur: user.uid,
      animal_id: r.animal_id,
      rdv_id: r.id,
      type: 'contrat_garde',
      titre: `Contrat de prestation — ${r._animal_nom}`,
      statut: 'brouillon',
      metadata: {
        client_nom: r._client_nom,
        date_visite: r.date_heure,
      },
    }).select('id, token').single();
    setGenerating(null);
    if (data) load();
  }

  async function transmettre(r: Rdv) {
    const doc = docs[r.id];
    if (!user || !doc?.token) return;
    await supabase.from('documents_animaux').update({ statut: 'en_attente' }).eq('id', doc.id);
    const signingUrl = `${window.location.origin}/signer-contrat/${doc.token}`;
    if (r.client_uid) {
      const gardeNom = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Votre pet sitter';
      await sendNotification({
        uid: r.client_uid, type: 'contrat_invite',
        title: '📄 Contrat à signer',
        body: `${gardeNom} vous envoie le contrat de prestation de ${r._animal_nom} — vérifiez et signez`,
        data: { token: doc.token, url: signingUrl },
      });
    }
    await navigator.clipboard.writeText(signingUrl).catch(() => {});
    alert(`Contrat transmis ! Lien copié dans le presse-papiers :\n${signingUrl}`);
    load();
  }

  async function envoyerParEmail(r: Rdv) {
    const doc = docs[r.id];
    if (!doc?.token || !r._client_email) return;
    setSendingEmail(r.id);
    const signingUrl = `${window.location.origin}/signer-contrat/${doc.token}`;
    const gardeNom = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Votre pet sitter';
    try {
      const res = await fetch('/api/contrat/notify-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: r._client_email, client_nom: r._client_nom, pro_nom: gardeNom,
          titre: `Contrat de prestation — ${r._animal_nom}`, signing_url: signingUrl,
        }),
      });
      if (res.ok) alert('Email envoyé au client.');
      else alert('Erreur lors de l\'envoi de l\'email.');
    } finally {
      setSendingEmail(null);
    }
  }

  if (!user || !userData) return null;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
      <h1 className="text-2xl font-bold font-galey text-teal-800">Contrats de prestation</h1>
      <p className="text-sm text-gray-500 font-galey">
        Générez un contrat par visite/promenade, signable électroniquement.
      </p>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : rdvs.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📋</p>
          <p className="font-galey">Aucune visite enregistrée pour l&apos;instant</p>
        </div>
      ) : (
        <div className="space-y-3">
          {rdvs.map(r => {
            const doc = docs[r.id];
            const meta = doc ? STATUT_META[doc.statut] ?? STATUT_META.brouillon : null;
            return (
              <div key={r.id} className="bg-white rounded-2xl shadow-sm p-4 border border-gray-100 flex items-center justify-between gap-4">
                <div>
                  <p className="font-bold font-galey text-gray-900">{r._animal_nom} — {r._client_nom}</p>
                  <p className="text-xs text-gray-500 font-galey">
                    {new Date(r.date_heure).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                  </p>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  {meta && (
                    <span className={`text-xs font-galey font-bold px-2.5 py-1 rounded-full ${meta.cls}`}>{meta.label}</span>
                  )}
                  {!doc ? (
                    <button onClick={() => genererContrat(r)} disabled={generating === r.id}
                      className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
                      {generating === r.id ? '…' : 'Générer le contrat'}
                    </button>
                  ) : doc.statut === 'brouillon' ? (
                    <button onClick={() => transmettre(r)}
                      className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800">
                      Envoyer pour signature
                    </button>
                  ) : (
                    <a href={`/signer-contrat/${doc.token}`} target="_blank" rel="noopener noreferrer"
                      className="border border-teal-200 text-teal-700 px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-50">
                      Voir le contrat
                    </a>
                  )}
                  {doc && doc.statut !== 'brouillon' && r._client_email && (
                    gardePlan !== 'free' ? (
                      <button onClick={() => envoyerParEmail(r)} disabled={sendingEmail === r.id}
                        className="border border-gray-200 text-gray-600 px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-gray-50 disabled:opacity-50">
                        {sendingEmail === r.id ? '…' : '📧 Par email'}
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
