'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useEducationAccess } from '@/hooks/useEducationAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface DocRow {
  id: string;
  token: string | null;
  statut: string;
  animal_id: string | null;
  titre: string | null;
  created_at: string;
  metadata: Record<string, unknown> | null;
  _animal_nom?: string;
}

interface Paire {
  client_uid: string;
  client_profile_id: string | null;
  animal_id: string | null;
  _client_nom: string;
  _client_email: string;
  _animal_nom: string;
}

const STATUT_META: Record<string, { label: string; cls: string }> = {
  brouillon:           { label: 'Brouillon',            cls: 'bg-gray-100 text-gray-500' },
  en_attente:          { label: '⏳ Attente signature',  cls: 'bg-amber-100 text-amber-700' },
  partiellement_signe: { label: '✍️ Partiel',            cls: 'bg-blue-100 text-blue-700' },
  signe:               { label: '✅ Signé',              cls: 'bg-green-100 text-green-700' },
  annule:              { label: '🚫 Annulé',             cls: 'bg-red-100 text-red-500' },
  refuse:              { label: '❌ Refusé',             cls: 'bg-red-100 text-red-700' },
};

export default function EducationContratPage() {
  const { user, userData, isEducation, loading: authLoading } = useEducationAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [docs, setDocs] = useState<DocRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [picker, setPicker] = useState<Paire[] | null>(null);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isEducation) { router.push('/'); return; }
  }, [user, userData, isEducation, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let q = supabase.from('documents_animaux').select('id, token, statut, animal_id, titre, created_at, metadata')
      .eq('uid_eleveur', user.uid).eq('type', 'contrat_education');
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId) as typeof q;
    const { data } = await q.order('created_at', { ascending: false });
    const rows = (data ?? []) as DocRow[];
    const animalIds = [...new Set(rows.map(r => r.animal_id).filter((a): a is string => !!a))];
    if (animalIds.length) {
      const { data: anims } = await supabase.from('animaux').select('id, nom').in('id', animalIds);
      const names = new Map((anims ?? []).map(a => [a.id, a.nom ?? '']));
      rows.forEach(r => { r._animal_nom = r.animal_id ? names.get(r.animal_id) ?? '' : ''; });
    }
    setDocs(rows);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function ouvrirPicker() {
    if (!user) return;
    let rq = supabase.from('rdv').select('animal_id, client_uid, client_profile_id, date_heure').eq('pro_uid', user.uid);
    if (activeProfileId) rq = rq.eq('pro_profile_id', activeProfileId) as typeof rq;
    const { data: rdvs } = await rq.in('statut', ['confirme', 'termine']).order('date_heure', { ascending: false });
    const seen = new Set<string>();
    const paires = ((rdvs ?? []) as { animal_id: string | null; client_uid: string | null; client_profile_id: string | null }[])
      .filter(r => {
        if (!r.client_uid) return false;
        const k = `${r.client_uid}|${r.animal_id}`;
        return seen.has(k) ? false : (seen.add(k), true);
      });
    const dejaContrat = new Set(docs.map(d => d.animal_id).filter(Boolean));
    const candidats = paires.filter(p => !p.animal_id || !dejaContrat.has(p.animal_id));
    if (candidats.length === 0) {
      alert('Aucun nouveau client / animal à contractualiser. Les contrats se créent depuis vos RDV confirmés.');
      return;
    }
    const clientUids = [...new Set(candidats.map(p => p.client_uid as string))];
    const animalIds = [...new Set(candidats.map(p => p.animal_id).filter((a): a is string => !!a))];
    const [{ data: clients }, { data: anims }] = await Promise.all([
      supabase.from('user_profiles').select('uid, firstname, lastname, nom, email_contact').in('uid', clientUids).eq('is_main', true),
      animalIds.length ? supabase.from('animaux').select('id, nom').in('id', animalIds) : Promise.resolve({ data: [] as { id: string; nom: string | null }[] }),
    ]);
    const cInfo = new Map((clients ?? []).map(c => {
      const nom = (c.nom as string | null)?.trim();
      const full = nom || `${c.firstname ?? ''} ${c.lastname ?? ''}`.trim();
      return [c.uid, { nom: full || 'Client', email: (c.email_contact as string | null) ?? '' }];
    }));
    const aNames = new Map((anims ?? []).map(a => [a.id, a.nom ?? '']));
    setPicker(candidats.map(p => ({
      client_uid: p.client_uid as string,
      client_profile_id: p.client_profile_id,
      animal_id: p.animal_id,
      _client_nom: cInfo.get(p.client_uid as string)?.nom ?? 'Client',
      _client_email: cInfo.get(p.client_uid as string)?.email ?? '',
      _animal_nom: p.animal_id ? aNames.get(p.animal_id) ?? '' : '',
    })));
  }

  async function creerContrat(p: Paire) {
    if (!user) return;
    setCreating(true);
    try {
      const { data } = await supabase.from('documents_animaux').insert({
        animal_id: p.animal_id,
        uid_eleveur: user.uid,
        pro_profile_id: activeProfileId || null,
        type: 'contrat_education',
        titre: `Contrat de prestation d'éducation — ${p._client_nom}`,
        statut: 'brouillon',
        metadata: {
          acquereur_nom: p._client_nom,
          ...(p._client_email ? { acquereur_email: p._client_email } : {}),
          prestation: 'Prestation d\'éducation canine',
        },
      }).select('token').single();
      setPicker(null);
      if (data?.token) window.open(`/signer-contrat/${data.token}`, '_blank');
      load();
    } finally {
      setCreating(false);
    }
  }

  if (!user || !userData) return null;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Mes Contrats</h1>
        <button onClick={ouvrirPicker}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800">
          + Nouveau contrat
        </button>
      </div>
      <p className="text-sm text-gray-500 font-galey">
        Un contrat par client + animal. Un devis accepté devient automatiquement un contrat rattaché.
      </p>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : docs.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📄</p>
          <p className="font-galey">Aucun contrat pour l&apos;instant</p>
        </div>
      ) : (
        <div className="space-y-3">
          {docs.map(d => {
            const meta = STATUT_META[d.statut] ?? STATUT_META.brouillon;
            const issuDevis = !!d.metadata?.devis_id;
            return (
              <a key={d.id} href={`/signer-contrat/${d.token}`} target="_blank" rel="noopener noreferrer"
                className="block bg-white rounded-2xl shadow-sm p-4 border border-gray-100 hover:border-teal-200 transition-colors">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="font-bold font-galey text-gray-900">{String(d.metadata?.acquereur_nom ?? 'Client')}</p>
                    <p className="text-xs text-gray-500 font-galey">
                      {[
                        d._animal_nom ? `Animal : ${d._animal_nom}` : null,
                        new Date(d.created_at).toLocaleDateString('fr-FR'),
                        issuDevis ? 'issu d\'un devis' : null,
                      ].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                  <span className={`text-xs font-galey font-bold px-2.5 py-1 rounded-full ${meta.cls}`}>{meta.label}</span>
                </div>
              </a>
            );
          })}
        </div>
      )}

      {picker && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setPicker(null)}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[80vh] overflow-y-auto p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-bold font-galey text-gray-900">Nouveau contrat — choisir le client</h3>
              <button onClick={() => setPicker(null)} className="text-gray-400 hover:text-gray-600">✕</button>
            </div>
            <div className="flex flex-col gap-2">
              {picker.map((p, i) => (
                <button key={i} disabled={creating} onClick={() => creerContrat(p)}
                  className="text-left p-3 rounded-xl border border-gray-200 hover:bg-teal-50 disabled:opacity-50">
                  <p className="font-semibold font-galey text-gray-900 text-sm">{p._client_nom}</p>
                  <p className="text-xs text-gray-500 font-galey">{p._animal_nom ? `Animal : ${p._animal_nom}` : 'Sans animal spécifié'}</p>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
