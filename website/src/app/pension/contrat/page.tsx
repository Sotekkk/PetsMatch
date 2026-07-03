'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { sendNotification } from '@/lib/notifications';

interface Entree {
  id: string;
  animal_nom: string;
  espece?: string | null;
  proprietaire_nom?: string | null;
  proprietaire_contact?: string | null;
  date_entree: string;
  date_sortie_prevue?: string | null;
  statut: string;
  logement_id?: string | null;
}

interface Doc {
  id: string;
  pension_entree_id: string;
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

export default function PensionContratPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const router = useRouter();
  const [entrees, setEntrees] = useState<Entree[]>([]);
  const [docs, setDocs] = useState<Record<string, Doc>>({});
  const [logements, setLogements] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState<string | null>(null);
  const [arrhesDefaut, setArrhesDefaut] = useState(0);


  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    const [{ data: ent }, { data: docsData }, { data: log }, { data: profil }] = await Promise.all([
      supabase.from('pension_entrees').select('*').eq('pro_uid', user.uid).order('date_entree', { ascending: false }).limit(50),
      supabase.from('documents_animaux').select('id, pension_entree_id, token, statut').eq('uid_eleveur', user.uid).eq('type', 'contrat_hebergement'),
      supabase.from('enclos_chenil').select('id, nom').eq('uid_eleveur', user.uid),
      supabase.from('users').select('arrhes_pourcentage').eq('uid', user.uid).maybeSingle(),
    ]);
    setEntrees(ent ?? []);
    setDocs(Object.fromEntries(((docsData ?? []) as Doc[]).map(d => [d.pension_entree_id, d])));
    setLogements(Object.fromEntries((log ?? []).map((l: { id: string; nom: string }) => [l.id, l.nom])));
    setArrhesDefaut((profil?.arrhes_pourcentage as number) ?? 0);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function genererContrat(e: Entree) {
    if (!user) return;
    setGenerating(e.id);
    const { data } = await supabase.from('documents_animaux').insert({
      uid_eleveur: user.uid,
      pension_entree_id: e.id,
      type: 'contrat_hebergement',
      titre: `Contrat d'hébergement — ${e.animal_nom}`,
      statut: 'brouillon',
      metadata: {
        arrhes_pourcentage: arrhesDefaut || null,
        logement_nom: e.logement_id ? logements[e.logement_id] : null,
      },
    }).select('id, token').single();
    setGenerating(null);
    if (data) load();
  }

  async function transmettre(entreeId: string) {
    const doc = docs[entreeId];
    const entree = entrees.find(e => e.id === entreeId);
    if (!user || !doc?.token || !entree) return;
    await supabase.from('documents_animaux').update({ statut: 'en_attente' }).eq('id', doc.id);
    const signingUrl = `${window.location.origin}/signer-contrat/${doc.token}`;
    const contact = entree.proprietaire_contact?.trim();
    if (contact?.includes('@')) {
      const { data: targetUser } = await supabase.from('users').select('uid').eq('email', contact).maybeSingle();
      if (targetUser?.uid) {
        const pensionNom = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'La pension';
        await sendNotification({
          uid: targetUser.uid, type: 'contrat_invite',
          title: '📄 Contrat à signer',
          body: `${pensionNom} vous envoie le contrat d'hébergement de ${entree.animal_nom} — vérifiez et signez`,
          data: { token: doc.token, url: signingUrl },
        });
      }
    }
    await navigator.clipboard.writeText(signingUrl).catch(() => {});
    alert(`Contrat transmis ! Lien copié dans le presse-papiers :\n${signingUrl}`);
    load();
  }

  if (!user || !userData) return null;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold font-galey text-teal-800">Contrats d&apos;hébergement</h1>
      <p className="text-sm text-gray-500 font-galey">
        Générez un contrat de pension par séjour, signable électroniquement (comme les contrats éleveur/association).
      </p>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : entrees.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📋</p>
          <p className="font-galey">Aucun séjour enregistré pour l&apos;instant</p>
        </div>
      ) : (
        <div className="space-y-3">
          {entrees.map(e => {
            const doc = docs[e.id];
            const meta = doc ? STATUT_META[doc.statut] ?? STATUT_META.brouillon : null;
            return (
              <div key={e.id} className="bg-white rounded-2xl shadow-sm p-4 border border-gray-100 flex items-center justify-between gap-4">
                <div>
                  <p className="font-bold font-galey text-gray-900">{e.animal_nom}</p>
                  <p className="text-xs text-gray-500 font-galey">
                    {e.proprietaire_nom ?? 'Propriétaire non renseigné'} · {new Date(e.date_entree).toLocaleDateString('fr-FR')}
                    {e.date_sortie_prevue ? ` → ${new Date(e.date_sortie_prevue).toLocaleDateString('fr-FR')}` : ''}
                  </p>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  {meta && (
                    <span className={`text-xs font-galey font-bold px-2.5 py-1 rounded-full ${meta.cls}`}>{meta.label}</span>
                  )}
                  {!doc ? (
                    <button onClick={() => genererContrat(e)} disabled={generating === e.id}
                      className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800 disabled:opacity-50">
                      {generating === e.id ? '…' : 'Générer le contrat'}
                    </button>
                  ) : doc.statut === 'brouillon' ? (
                    <button onClick={() => transmettre(e.id)}
                      className="bg-teal-700 text-white px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-800">
                      Envoyer pour signature
                    </button>
                  ) : (
                    <a href={`/signer-contrat/${doc.token}`} target="_blank" rel="noopener noreferrer"
                      className="border border-teal-200 text-teal-700 px-4 py-1.5 rounded-full text-xs font-galey font-semibold hover:bg-teal-50">
                      Voir le contrat
                    </a>
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
