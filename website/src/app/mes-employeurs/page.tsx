'use client';

import { useState, useEffect, useCallback } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const SPECIES_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  ovin: '🐑', caprin: '🐐', porcin: '🐷', nac: '🦎', oiseau: '🦜',
};

interface Animal {
  id: string;
  nom: string | null;
  espece: string | null;
  race: string | null;
  sexe: string | null;
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

interface Employer {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  profile_picture_url: string | null;
  profile_picture_url_elevage: string | null;
  permissions: Record<string, boolean>;
  animaux: Animal[];
  taches: Tache[];
}

function formatDate(d: string) {
  const dt = new Date(d);
  return dt.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
}

export default function MesEmployeursPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [employers, setEmployers] = useState<Employer[]>([]);
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
      .select('uid_eleveur, permissions, type')
      .eq('uid_employe', user.uid)
      .eq('actif', true);

    if (!rows || rows.length === 0) { setLoading(false); return; }

    // Exclut les bénévoles, déduplique par uid_eleveur
    const seenUids = new Set<string>();
    const filteredRows = rows.filter(r => {
      if (r.type === 'benevole') return false;
      if (seenUids.has(r.uid_eleveur)) return false;
      seenUids.add(r.uid_eleveur);
      return true;
    });
    if (filteredRows.length === 0) { setLoading(false); return; }

    const uids = filteredRows.map(r => r.uid_eleveur as string);
    const permMap: Record<string, Record<string, boolean>> = {};
    filteredRows.forEach(r => { permMap[r.uid_eleveur] = (r.permissions as Record<string, boolean>) ?? {}; });

    // Dates pour plan_taches
    const past = new Date(); past.setDate(past.getDate() - 7);
    const future = new Date(); future.setDate(future.getDate() + 90);
    const pastStr   = past.toISOString().slice(0, 10);
    const futureStr = future.toISOString().slice(0, 10);

    const [{ data: users }, { data: animaux }, { data: tachesRaw }, { data: planTachesRaw }] = await Promise.all([
      supabase.from('users')
        .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, profile_picture_url_elevage')
        .in('uid', uids),
      supabase.from('animaux')
        .select('id, nom, espece, race, sexe, photo_url, uid_eleveur')
        .in('uid_eleveur', uids)
        .eq('statut', 'present')
        .or('is_association.is.null,is_association.eq.false')
        .order('nom'),
      supabase.from('taches_elevage')
        .select('id, titre, date, statut, animal_id, uid_eleveur')
        .in('uid_eleveur', uids)
        .eq('assigne_a', user.uid)
        .neq('statut', 'fait')
        .order('date'),
      supabase.from('plan_taches')
        .select('id, label, date_prevue, statut, animal_id, uid_eleveur')
        .in('uid_eleveur', uids)
        .eq('assigned_to', user.uid)
        .neq('statut', 'fait')
        .gte('date_prevue', pastStr)
        .lte('date_prevue', futureStr)
        .order('date_prevue'),
    ]);

    // Résoudre les noms d'animaux
    const animalIds = [
      ...(tachesRaw ?? []).map(t => t.animal_id),
      ...(planTachesRaw ?? []).map(t => t.animal_id),
    ].filter(Boolean) as string[];
    const uniqueIds = [...new Set(animalIds)];
    let animalNames: Record<string, string> = {};
    if (uniqueIds.length > 0) {
      const { data: anNames } = await supabase.from('animaux').select('id, nom').in('id', uniqueIds);
      animalNames = Object.fromEntries((anNames ?? []).map(a => [a.id, a.nom ?? 'Animal']));
    }

    const list: Employer[] = (users ?? []).map(u => {
      const manuel: Tache[] = (tachesRaw ?? [])
        .filter(t => t.uid_eleveur === u.uid)
        .map(t => ({
          id: t.id, titre: t.titre, date: t.date, statut: t.statut,
          animal_id: t.animal_id, animal_nom: t.animal_id ? animalNames[t.animal_id] : undefined,
          source: 'manuel' as const,
        }));

      const protocoles: Tache[] = (planTachesRaw ?? [])
        .filter(t => t.uid_eleveur === u.uid)
        .map(t => ({
          id: t.id, titre: t.label ?? 'Tâche protocole', date: t.date_prevue, statut: t.statut,
          animal_id: t.animal_id, animal_nom: t.animal_id ? animalNames[t.animal_id] : undefined,
          source: 'protocole' as const,
        }));

      const taches = [...manuel, ...protocoles].sort(
        (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime()
      );

      return {
        ...u,
        permissions: permMap[u.uid] ?? {},
        animaux: (animaux ?? []).filter(a => a.uid_eleveur === u.uid),
        taches,
      };
    });

    setEmployers(list);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function marquerFait(tache: Tache, employerUid: string) {
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
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
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
            Mes employeurs
          </h1>
          <p className="text-xs text-gray-400">Élevages pour lesquels vous travaillez</p>
        </div>
      </div>

      {employers.length === 0 ? (
        <div className="text-center py-20">
          <span className="text-5xl block mb-4">🏡</span>
          <p className="font-semibold text-gray-600 mb-1">Aucun employeur</p>
          <p className="text-sm text-gray-400">Vous n&apos;êtes rattaché à aucun élevage pour le moment.</p>
        </div>
      ) : (
        <div className="space-y-6">
          {employers.map(emp => {
            const name = emp.is_elevage
              ? (emp.name_elevage ?? 'Élevage')
              : `${emp.firstname ?? ''} ${emp.lastname ?? ''}`.trim();
            const photo = emp.is_elevage
              ? emp.profile_picture_url_elevage
              : emp.profile_picture_url;
            const activeTab = getTab(emp.uid);
            const tachesEnCours = emp.taches.filter(t => t.statut !== 'fait');

            return (
              <div key={emp.uid} className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">

                {/* Header employeur */}
                <div className="flex items-center gap-4 p-4 bg-[#F8FBFC]">
                  {photo ? (
                    <Image src={photo} alt={name} width={52} height={52}
                      className="rounded-xl object-cover flex-shrink-0" style={{ width: 52, height: 52 }} />
                  ) : (
                    <div className="w-[52px] h-[52px] rounded-xl bg-[#0C5C6C] flex items-center justify-center text-white font-bold text-xl flex-shrink-0">
                      {name[0]?.toUpperCase() ?? '?'}
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {name}
                    </p>
                    <div className="flex gap-3 mt-0.5">
                      <span className="text-xs text-gray-400">
                        {emp.animaux.length} animal{emp.animaux.length !== 1 ? 'aux' : ''}
                      </span>
                      {tachesEnCours.length > 0 && (
                        <span className="text-xs text-[#0C5C6C] font-semibold">
                          {tachesEnCours.length} tâche{tachesEnCours.length !== 1 ? 's' : ''} à faire
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {/* Onglets */}
                <div className="flex border-b border-gray-100">
                  {([
                    ['animaux', `🐾 Animaux (${emp.animaux.length})`],
                    ['taches',  `✅ Tâches (${tachesEnCours.length})`],
                  ] as const).map(([v, l]) => (
                    <button key={v}
                      onClick={() => setTab(prev => ({ ...prev, [emp.uid]: v }))}
                      className={`flex-1 py-2.5 text-sm font-semibold transition-colors ${
                        activeTab === v
                          ? 'text-[#0C5C6C] border-b-2 border-[#0C5C6C]'
                          : 'text-gray-400 hover:text-gray-600'
                      }`}>
                      {l}
                    </button>
                  ))}
                </div>

                {/* Onglet Animaux */}
                {activeTab === 'animaux' && (
                  <div className="p-4">
                    {emp.animaux.length === 0 ? (
                      <p className="text-center text-sm text-gray-400 py-4">Aucun animal présent</p>
                    ) : (
                      <div className="grid grid-cols-3 sm:grid-cols-4 gap-3">
                        {emp.animaux.map(a => {
                          const isMale   = a.sexe?.toLowerCase().startsWith('m');
                          const isFemale = a.sexe?.toLowerCase().startsWith('f');
                          return (
                            <Link key={a.id} href={`/mes-animaux/${a.id}`}
                              className="bg-gray-50 rounded-xl overflow-hidden hover:shadow-md transition-shadow">
                              <div className="relative aspect-square bg-[#EAF4EC] flex items-center justify-center overflow-hidden">
                                {a.photo_url ? (
                                  // eslint-disable-next-line @next/next/no-img-element
                                  <img src={a.photo_url} alt={a.nom ?? ''} className="w-full h-full object-cover" />
                                ) : (
                                  <span className="text-3xl">{SPECIES_EMOJI[a.espece ?? ''] ?? '🐾'}</span>
                                )}
                                {(isMale || isFemale) && (
                                  <span className={`absolute top-1.5 right-1.5 text-[10px] w-5 h-5 rounded-full flex items-center justify-center font-bold
                                    ${isMale ? 'bg-blue-100 text-blue-700' : 'bg-pink-100 text-pink-700'}`}>
                                    {isMale ? '♂' : '♀'}
                                  </span>
                                )}
                              </div>
                              <div className="p-2">
                                <p className="font-bold text-[#1F2A2E] text-xs truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                                  {a.nom ?? 'Sans nom'}
                                </p>
                                <p className="text-gray-400 text-[10px] truncate">{a.race || a.espece || ''}</p>
                              </div>
                            </Link>
                          );
                        })}
                      </div>
                    )}
                  </div>
                )}

                {/* Onglet Tâches */}
                {activeTab === 'taches' && (
                  <div className="p-4">
                    {tachesEnCours.length === 0 ? (
                      <p className="text-center text-sm text-gray-400 py-4">Aucune tâche assignée</p>
                    ) : (
                      <div className="space-y-2">
                        {tachesEnCours.map(t => (
                          <div key={t.id}
                            className="flex items-start gap-3 bg-gray-50 rounded-xl px-4 py-3">
                            <button
                              onClick={() => marquerFait(t, emp.uid)}
                              className="mt-0.5 w-5 h-5 rounded border-2 border-gray-300 flex-shrink-0 hover:border-[#6E9E57] transition-colors"
                              title="Marquer comme fait"
                            />
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2">
                                <p className="font-semibold text-[#1F2A2E] text-sm truncate">{t.titre}</p>
                                {t.source === 'protocole' && (
                                  <span className="text-[10px] bg-[#F0F9FF] text-[#0C5C6C] px-1.5 py-0.5 rounded font-medium flex-shrink-0">
                                    protocole
                                  </span>
                                )}
                              </div>
                              <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                                <span className="text-xs text-gray-400">{formatDate(t.date)}</span>
                                {t.animal_nom && (
                                  <span className="text-xs bg-[#E8F4F6] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium">
                                    🐾 {t.animal_nom}
                                  </span>
                                )}
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
