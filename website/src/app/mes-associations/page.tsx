'use client';

import { useState, useEffect, useCallback } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Animal {
  id: string;
  nom: string | null;
  espece: string | null;
  race: string | null;
  photo_url: string | null;
}

interface Tache {
  id: string;
  titre: string;
  date: string;
  statut: string;
  animal_id: string | null;
  animal_nom?: string;
  source: 'manuel' | 'protocole';
}

interface Asso {
  uid: string;
  nom: string;
  avatar: string | null;
  ville: string | null;
  animaux: Animal[];
  taches: Tache[];
}

function formatDate(d: string) {
  const dt = new Date(d);
  return dt.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
}

export default function MesAssociationsPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [assos, setAssos] = useState<Asso[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Record<string, 'animaux' | 'taches'>>({});

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);

    const { data: rows } = await supabase
      .from('employes')
      .select('uid_eleveur')
      .eq('uid_employe', user.uid)
      .eq('type', 'benevole')
      .eq('actif', true);

    if (!rows || rows.length === 0) { setLoading(false); return; }

    const uids = rows.map(r => r.uid_eleveur as string);

    const past = new Date(); past.setDate(past.getDate() - 7);
    const future = new Date(); future.setDate(future.getDate() + 90);
    const pastStr   = past.toISOString().slice(0, 10);
    const futureStr = future.toISOString().slice(0, 10);

    const [
      { data: secProfiles },
      { data: primaryUsers },
      { data: animaux },
      { data: tachesRaw },
      { data: planTachesRaw },
    ] = await Promise.all([
      supabase.from('user_profiles')
        .select('uid, name_elevage, profile_label, avatar_url, ville')
        .in('uid', uids).eq('profile_type', 'association'),
      supabase.from('users')
        .select('uid, name_elevage, firstname, lastname, profile_picture_url, ville')
        .in('uid', uids),
      supabase.from('animaux')
        .select('id, nom, espece, race, photo_url, uid_eleveur')
        .in('uid_eleveur', uids).eq('is_association', true).eq('statut', 'present').order('nom'),
      supabase.from('taches_elevage')
        .select('id, titre, date, statut, animal_id, uid_eleveur')
        .in('uid_eleveur', uids).eq('assigne_a', user.uid).neq('statut', 'fait').order('date'),
      supabase.from('plan_taches')
        .select('id, label, date_prevue, statut, animal_id, uid_eleveur')
        .in('uid_eleveur', uids).eq('assigned_to', user.uid).neq('statut', 'fait')
        .gte('date_prevue', pastStr).lte('date_prevue', futureStr).order('date_prevue'),
    ]);

    const animalIds = [
      ...(tachesRaw ?? []).map(t => t.animal_id),
      ...(planTachesRaw ?? []).map(t => t.animal_id),
    ].filter(Boolean) as string[];
    let animalNames: Record<string, string> = {};
    if (animalIds.length > 0) {
      const { data: anNames } = await supabase.from('animaux').select('id, nom').in('id', [...new Set(animalIds)]);
      animalNames = Object.fromEntries((anNames ?? []).map(a => [a.id, a.nom ?? 'Animal']));
    }

    const secMap: Record<string, { nom: string; avatar: string | null; ville: string | null }> = {};
    for (const p of (secProfiles ?? []) as Record<string, unknown>[]) {
      const uid = p['uid'] as string;
      const nom = ((p['name_elevage'] as string | undefined)?.trim() || (p['profile_label'] as string | undefined)?.trim()) || '';
      secMap[uid] = {
        nom: nom || 'Association',
        avatar: (p['avatar_url'] as string | null) ?? null,
        ville: (p['ville'] as string | null) ?? null,
      };
    }

    const list: Asso[] = uids.map(uid => {
      const sec = secMap[uid];
      const pu = (primaryUsers ?? []).find(u => u.uid === uid) as Record<string, unknown> | undefined;
      const nom = sec?.nom || (pu ? `${(pu['firstname'] as string) ?? ''} ${(pu['lastname'] as string) ?? ''}`.trim() : '') || 'Association';
      const avatar = sec?.avatar ?? (pu?.['profile_picture_url'] as string | null) ?? null;
      const ville = sec?.ville ?? (pu?.['ville'] as string | null) ?? null;

      const manuel: Tache[] = (tachesRaw ?? [])
        .filter(t => t.uid_eleveur === uid)
        .map(t => ({
          id: t.id, titre: t.titre, date: t.date, statut: t.statut,
          animal_id: t.animal_id, animal_nom: t.animal_id ? animalNames[t.animal_id] : undefined,
          source: 'manuel' as const,
        }));
      const protocoles: Tache[] = (planTachesRaw ?? [])
        .filter(t => t.uid_eleveur === uid)
        .map(t => ({
          id: t.id, titre: t.label ?? 'Tâche', date: t.date_prevue, statut: t.statut,
          animal_id: t.animal_id, animal_nom: t.animal_id ? animalNames[t.animal_id] : undefined,
          source: 'protocole' as const,
        }));
      const taches = [...manuel, ...protocoles].sort(
        (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime()
      );

      return {
        uid, nom, avatar, ville,
        animaux: (animaux ?? []).filter(a => a.uid_eleveur === uid),
        taches,
      };
    });

    setAssos(list);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function marquerFait(tache: Tache) {
    if (tache.source === 'manuel') {
      await supabase.from('taches_elevage').update({ statut: 'fait' }).eq('id', tache.id);
    } else {
      await supabase.from('plan_taches').update({ statut: 'fait' }).eq('id', tache.id);
    }
    load();
  }

  if (authLoading || loading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  function getTab(uid: string): 'animaux' | 'taches' {
    return tab[uid] ?? 'animaux';
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 pb-24">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.back()}
          className="p-2 rounded-xl hover:bg-gray-100 transition-colors">
          <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes associations
          </h1>
          <p className="text-sm text-gray-400">Associations où vous êtes bénévole</p>
        </div>
      </div>

      {assos.length === 0 ? (
        <div className="text-center py-24 text-gray-400">
          <p className="text-5xl mb-3">🏠</p>
          <p className="font-semibold text-gray-500">Aucune association</p>
          <p className="text-sm mt-1">Vous n'êtes bénévole dans aucune association active.</p>
        </div>
      ) : (
        <div className="space-y-6">
          {assos.map(asso => (
            <div key={asso.uid} className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
              {/* Header association */}
              <div className="flex items-center gap-3 p-4 border-b border-gray-50">
                <div className="w-12 h-12 rounded-full bg-teal-50 overflow-hidden flex-shrink-0 relative">
                  {asso.avatar ? (
                    <Image src={asso.avatar} alt={asso.nom} fill className="object-cover" sizes="48px" unoptimized />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-xl">🏠</div>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{asso.nom}</p>
                  {asso.ville && <p className="text-xs text-gray-400">📍 {asso.ville}</p>}
                </div>
                <Link href={`/associations/${asso.uid}`}
                  className="text-xs font-semibold text-teal-700 border border-teal-600 px-3 py-1.5 rounded-xl hover:bg-teal-700 hover:text-white transition-colors flex-shrink-0">
                  Voir le profil
                </Link>
              </div>

              {/* Tabs */}
              <div className="flex border-b border-gray-100">
                {(['animaux', 'taches'] as const).map(t => (
                  <button key={t} onClick={() => setTab(prev => ({ ...prev, [asso.uid]: t }))}
                    className={`flex-1 py-2.5 text-sm font-medium transition-colors ${
                      getTab(asso.uid) === t ? 'text-teal-700 border-b-2 border-teal-700' : 'text-gray-400 hover:text-gray-600'
                    }`}>
                    {t === 'animaux' ? `🐾 Animaux (${asso.animaux.length})` : `✅ Tâches (${asso.taches.length})`}
                  </button>
                ))}
              </div>

              {/* Tab content */}
              {getTab(asso.uid) === 'animaux' ? (
                <div className="p-4">
                  {asso.animaux.length === 0 ? (
                    <p className="text-sm text-gray-400 text-center py-4">Aucun animal à charge</p>
                  ) : (
                    <div className="grid grid-cols-3 gap-2">
                      {asso.animaux.map(a => (
                        <div key={a.id} className="bg-gray-50 rounded-xl overflow-hidden">
                          <div className="aspect-square relative bg-gray-100">
                            {a.photo_url ? (
                              <Image src={a.photo_url} alt={a.nom ?? ''} fill className="object-cover" sizes="120px" unoptimized />
                            ) : (
                              <div className="w-full h-full flex items-center justify-center text-2xl">🐾</div>
                            )}
                          </div>
                          <div className="p-1.5">
                            <p className="text-xs font-semibold text-[#1F2A2E] truncate">{a.nom ?? '—'}</p>
                            <p className="text-xs text-gray-400 truncate">{a.race ?? a.espece ?? ''}</p>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              ) : (
                <div className="p-4 space-y-2">
                  {asso.taches.length === 0 ? (
                    <p className="text-sm text-gray-400 text-center py-4">Aucune tâche assignée</p>
                  ) : (
                    asso.taches.map(t => (
                      <div key={t.id} className="flex items-start gap-3 p-3 bg-gray-50 rounded-xl">
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-[#1F2A2E] leading-tight">{t.titre}</p>
                          {t.animal_nom && <p className="text-xs text-gray-400 mt-0.5">🐾 {t.animal_nom}</p>}
                          <p className="text-xs text-gray-400 mt-0.5">📅 {formatDate(t.date)}</p>
                          {t.source === 'protocole' && (
                            <span className="text-xs bg-teal-50 text-teal-600 px-1.5 py-0.5 rounded-md mt-0.5 inline-block">protocole</span>
                          )}
                        </div>
                        <button
                          onClick={() => marquerFait(t)}
                          className="flex-shrink-0 w-8 h-8 rounded-full border-2 border-gray-200 hover:border-teal-500 hover:bg-teal-50 transition-colors flex items-center justify-center">
                          <svg className="w-4 h-4 text-gray-300 hover:text-teal-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                          </svg>
                        </button>
                      </div>
                    ))
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
