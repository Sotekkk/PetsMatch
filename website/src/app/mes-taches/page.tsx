'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useProfileSource, useActiveProfile } from '@/hooks/useActiveProfile';

interface Task {
  id: string;
  titre: string;
  date: string;
  statut: 'a_faire' | 'fait';
  uid_eleveur: string;
  assigne_a: string | null;
  notes: string | null;
  animal_nom?: string;
  eleveur_nom?: string;
}

export default function MesTachesPage() {
  const router = useRouter();
  const { user, loading: authLoading } = useAuth();
  const profilSource = useProfileSource();
  const profileId = useActiveProfile();
  const [taches, setTaches] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [showDone, setShowDone] = useState(false);
  const [toggling, setToggling] = useState<string | null>(null);

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    try {
      let q = supabase.from('taches_elevage').select('*').order('date');
      if (profileId) {
        q = q.eq('assigne_profile_id', profileId) as typeof q;
      } else {
        q = q.eq('assigne_a', user.uid) as typeof q;
      }
      const { data: rows } = await (profilSource === 'association'
        ? q.eq('profil_source', 'association')
        : q.or('profil_source.is.null,profil_source.eq.eleveur'));

      const result: Task[] = [];
      for (const t of (rows ?? [])) {
        let animalNom: string | undefined;
        let eleveurNom: string | undefined;

        if (t.animal_id) {
          const { data: a } = await supabase.from('animaux').select('nom').eq('id', t.animal_id).maybeSingle();
          animalNom = a?.nom ?? undefined;
        }
        const { data: u } = await supabase.from('users')
          .select('firstname, lastname, name_elevage, is_elevage')
          .eq('uid', t.uid_eleveur).maybeSingle();
        if (u) {
          eleveurNom = u.is_elevage ? (u.name_elevage ?? 'Élevage') : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
        }
        result.push({ ...t, animal_nom: animalNom, eleveur_nom: eleveurNom });
      }
      setTaches(result);
    } finally {
      setLoading(false);
    }
  }, [user, profilSource, profileId]);

  useEffect(() => { load(); }, [load]);

  async function toggleFait(t: Task) {
    if (toggling) return;
    const newStatut: 'a_faire' | 'fait' = t.statut === 'fait' ? 'a_faire' : 'fait';
    setToggling(t.id);

    // Mise à jour optimiste
    setTaches(prev => prev.map(x => x.id === t.id ? { ...x, statut: newStatut } : x));

    await supabase.from('taches_elevage').update({ statut: newStatut }).eq('id', t.id);

    // Notification à l'employeur quand l'employé valide
    if (newStatut === 'fait') {
      try {
        const { data: moi } = await supabase.from('users')
          .select('firstname, lastname, name_elevage, is_elevage')
          .eq('uid', user!.uid).maybeSingle();
        const nomEmploye = moi
          ? (moi.is_elevage ? (moi.name_elevage ?? 'Votre employé') : `${moi.firstname ?? ''} ${moi.lastname ?? ''}`.trim())
          : 'Votre employé';

        await supabase.from('notifications').insert({
          uid:   t.uid_eleveur,
          type:  'tache_validee',
          title: 'Tâche validée ✓',
          body:  `${nomEmploye} a terminé : ${t.titre}`,
          data:  { tacheId: t.id, eleveurUid: t.uid_eleveur },
          read:  false,
        });
      } catch (_) {}
    }

    setToggling(null);
  }

  if (authLoading || !user) {
    return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  }

  const affichees = taches.filter(t => showDone ? t.statut === 'fait' : t.statut !== 'fait');

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 pb-20">
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => router.back()} className="p-2 rounded-xl hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Mes tâches
        </h1>
      </div>

      {/* Filtres */}
      <div className="flex gap-2 mb-5">
        {([['a_faire', 'À faire', '#0C5C6C'], ['fait', 'Terminées', '#6E9E57']] as const).map(([v, l, c]) => {
          const active = showDone === (v === 'fait');
          return (
            <button key={v} onClick={() => setShowDone(v === 'fait')}
              className="px-4 py-2 rounded-full text-sm font-semibold border-2 transition-colors"
              style={{
                borderColor: c,
                backgroundColor: active ? c : 'white',
                color: active ? 'white' : '#6B7280',
              }}>
              {l}
            </button>
          );
        })}
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : taches.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <div className="text-5xl mb-3">✅</div>
          <p className="font-semibold text-base">Aucune tâche assignée</p>
          <p className="text-sm mt-1">Votre responsable n&apos;a pas encore créé de tâche pour vous.</p>
        </div>
      ) : affichees.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <div className="text-5xl mb-3">{showDone ? '🎉' : '✅'}</div>
          <p className="font-semibold">{showDone ? 'Aucune tâche terminée' : 'Toutes les tâches sont faites !'}</p>
        </div>
      ) : (
        <div className="space-y-3">
          {affichees.map(t => {
            const fait = t.statut === 'fait';
            const isToggling = toggling === t.id;
            return (
              <div key={t.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4">
                <div className="flex items-start gap-3">
                  {/* Checkbox validation */}
                  <button
                    onClick={() => toggleFait(t)}
                    disabled={isToggling}
                    className={`w-6 h-6 rounded-full border-2 flex items-center justify-center flex-shrink-0 mt-0.5 transition-all ${
                      fait
                        ? 'border-[#6E9E57] bg-[#6E9E57]'
                        : 'border-gray-300 hover:border-[#0C5C6C]'
                    } ${isToggling ? 'opacity-50' : ''}`}>
                    {fait && (
                      <svg className="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                      </svg>
                    )}
                  </button>

                  <div className="flex-1 min-w-0">
                    <p className={`font-semibold text-sm ${fait ? 'line-through text-gray-400' : 'text-[#1F2A2E]'}`}>
                      {t.titre}
                    </p>
                    <div className="flex flex-wrap gap-2 mt-1.5">
                      <span className="text-xs text-gray-400">
                        📅 {new Date(t.date).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })}
                      </span>
                      {t.eleveur_nom && (
                        <span className="text-xs text-[#0C5C6C] bg-[#E8F4F6] px-2 py-0.5 rounded-full">
                          👤 {t.eleveur_nom}
                        </span>
                      )}
                      {t.animal_nom && (
                        <span className="text-xs text-[#6E9E57] bg-[#EEF5EA] px-2 py-0.5 rounded-full">
                          🐾 {t.animal_nom}
                        </span>
                      )}
                    </div>
                    {t.notes && (
                      <p className="text-xs text-gray-400 mt-1.5 line-clamp-2">{t.notes}</p>
                    )}
                  </div>

                  {/* Badge statut */}
                  {!fait && (
                    <span className="text-xs font-semibold text-[#0C5C6C] bg-[#E8F4F6] px-2.5 py-1 rounded-full flex-shrink-0">
                      À faire
                    </span>
                  )}
                </div>

                {/* Bouton "Marquer comme fait" bien visible */}
                {!fait && (
                  <button
                    onClick={() => toggleFait(t)}
                    disabled={isToggling}
                    className="mt-3 w-full py-2.5 rounded-xl bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white text-sm font-semibold transition-colors">
                    {isToggling ? 'Validation…' : '✓ Marquer comme terminée'}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
