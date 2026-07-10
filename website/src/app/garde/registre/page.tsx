'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { PensionJournal } from '@/components/PensionJournal';

const TEAL = '#0C5C6C';

interface Rdv {
  id: string;
  animal_id: string | null;
  client_uid: string | null;
  date_heure: string;
  statut: string;
  _animal_nom?: string;
  _client_nom?: string;
}

function fmtDate(iso: string) {
  try {
    return new Date(iso).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  } catch { return iso; }
}

export default function RegistreVisitesPage() {
  const { user, userData, isGarde, loading: authLoading } = useGardeAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [tab, setTab] = useState<'a_venir' | 'passees'>('a_venir');
  const [visites, setVisites] = useState<Rdv[]>([]);
  const [loading, setLoading] = useState(true);
  const [journalFor, setJournalFor] = useState<Rdv | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isGarde) { router.push('/'); return; }
  }, [user, userData, isGarde, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    let q = supabase.from('rdv').select('id, animal_id, client_uid, date_heure, statut').eq('pro_uid', user.uid);
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId) as typeof q;
    const { data } = await q.in('statut', ['confirme', 'termine']).order('date_heure', { ascending: true });
    const rows = (data ?? []) as Rdv[];

    const clientUids = [...new Set(rows.map(r => r.client_uid).filter((u): u is string => !!u))];
    const animalIds = [...new Set(rows.map(r => r.animal_id).filter((a): a is string => !!a))];

    const [{ data: clients }, { data: animaux }] = await Promise.all([
      clientUids.length
        ? supabase.from('user_profiles').select('uid, firstname, lastname, nom').in('uid', clientUids).eq('is_main', true)
        : Promise.resolve({ data: [] as { uid: string; firstname: string | null; lastname: string | null; nom: string | null }[] }),
      animalIds.length
        ? supabase.from('animaux').select('id, nom').in('id', animalIds)
        : Promise.resolve({ data: [] as { id: string; nom: string | null }[] }),
    ]);

    const clientNames = new Map((clients ?? []).map(c => {
      const nom = c.nom?.trim();
      const full = nom || `${c.firstname ?? ''} ${c.lastname ?? ''}`.trim();
      return [c.uid, full || 'Client'];
    }));
    const animalNames = new Map((animaux ?? []).map(a => [a.id, a.nom ?? '']));

    setVisites(rows.map(r => ({
      ...r,
      _client_nom: r.client_uid ? clientNames.get(r.client_uid) ?? 'Client' : 'Client',
      _animal_nom: r.animal_id ? animalNames.get(r.animal_id) ?? '' : '',
    })));
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function marquerTermine(rdv: Rdv) {
    await supabase.from('rdv').update({ statut: 'termine' }).eq('id', rdv.id);
    load();
  }

  if (authLoading || loading) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  const now = new Date();
  const aVenir = visites.filter(r => r.statut !== 'termine' && new Date(r.date_heure) >= now);
  const passees = visites.filter(r => !aVenir.includes(r)).slice().reverse();
  const displayed = tab === 'a_venir' ? aVenir : passees;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold font-galey mb-6" style={{ color: TEAL }}>Registre visites</h1>

      <div className="flex bg-gray-100 rounded-xl p-1 mb-6 max-w-sm">
        {(['a_venir', 'passees'] as const).map(t => (
          <button key={t} onClick={() => setTab(t)}
            className={`flex-1 py-2 rounded-lg text-sm font-medium font-galey transition-colors ${tab === t ? 'bg-white shadow-sm text-[#1F2A2E]' : 'text-gray-500'}`}>
            {t === 'a_venir' ? `À venir (${aVenir.length})` : `Passées (${passees.length})`}
          </button>
        ))}
      </div>

      {displayed.length === 0 ? (
        <p className="text-center text-gray-400 font-galey py-16">
          {tab === 'a_venir' ? 'Aucune visite à venir' : 'Aucune visite passée'}
        </p>
      ) : (
        <div className="space-y-3">
          {displayed.map(rdv => {
            const isTermine = rdv.statut === 'termine';
            return (
              <div key={rdv.id} className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <p className="font-bold font-galey text-sm text-[#1F2A2E]">{rdv._animal_nom} — {rdv._client_nom}</p>
                    <p className="text-xs text-gray-400 font-galey">{fmtDate(rdv.date_heure)}</p>
                  </div>
                  <span className={`text-xs font-semibold font-galey px-2 py-1 rounded-full ${isTermine ? 'bg-[#EEF5EA] text-[#6E9E57]' : 'bg-[#E8F4F6] text-[#0C5C6C]'}`}>
                    {isTermine ? 'Terminée' : 'Confirmée'}
                  </span>
                </div>
                <div className="flex gap-2">
                  {!isTermine && (
                    <button onClick={() => marquerTermine(rdv)}
                      className="flex-1 text-xs font-medium font-galey border border-gray-200 rounded-xl py-2 hover:bg-gray-50">
                      Marquer terminée
                    </button>
                  )}
                  <button onClick={() => setJournalFor(rdv)}
                    className="flex-1 text-xs font-medium font-galey text-white rounded-xl py-2"
                    style={{ backgroundColor: TEAL }}>
                    Rapport de visite
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {journalFor && (
        <PensionJournal
          animalId={journalFor.animal_id}
          animalNom={journalFor._animal_nom || 'Animal'}
          proUid={user?.uid}
          onClose={() => setJournalFor(null)}
        />
      )}
    </div>
  );
}
