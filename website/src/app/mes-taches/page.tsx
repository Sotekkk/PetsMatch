'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useProfileSource, useActiveProfileState } from '@/hooks/useActiveProfile';

interface Task {
  id: string;
  titre: string;
  date: string;
  statut: 'a_faire' | 'fait';
  uid_eleveur: string;
  eleveur_profile_id?: string | null;
  assigne_a: string | null;
  notes: string | null;
  animal_nom?: string;
  eleveur_nom?: string;
}

interface AnimalOption { id: string; nom: string; espece?: string | null; }
interface MembreOption { uid: string; nom: string; type: 'employe' | 'benevole'; }

export default function MesTachesPage() {
  const router = useRouter();
  const { user, loading: authLoading } = useAuth();
  const profilSource = useProfileSource();
  const { id: profileId, loaded: profileLoaded } = useActiveProfileState();
  const [taches, setTaches] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [showDone, setShowDone] = useState(false);
  const [toggling, setToggling] = useState<string | null>(null);
  const [showAddTache, setShowAddTache] = useState(false);
  const [animaux, setAnimaux] = useState<AnimalOption[]>([]);
  const [membres, setMembres] = useState<MembreOption[]>([]);

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  const load = useCallback(async () => {
    if (!user || !profileLoaded) return;
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
        const { data: u } = await supabase.from('user_profiles')
          .select('firstname, lastname, nom, profile_type')
          .eq('uid', t.uid_eleveur).eq('is_main', true).maybeSingle();
        if (u) {
          eleveurNom = u.profile_type === 'eleveur' ? (u.nom ?? 'Élevage') : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
        }
        result.push({ ...t, animal_nom: animalNom, eleveur_nom: eleveurNom });
      }
      setTaches(result);
    } finally {
      setLoading(false);
    }
  }, [user, profilSource, profileId, profileLoaded]);

  useEffect(() => { load(); }, [load]);

  // Charge les animaux et l'équipe (employés/bénévoles) pour la création de tâche côté association
  const loadEquipeEtAnimaux = useCallback(async () => {
    if (!user || profilSource !== 'association') return;
    // Un même uid Firebase peut porter plusieurs profils (élevage +
    // association) — ne garder que les animaux réellement de CE profil :
    // possédés en propre (is_association=true) + reçus par cession
    // (animaux_proprietes.profile_id_proprio), sinon un animal du profil
    // élevage apparaît aussi dans le picker de tâche association.
    const [ownedRes, employesRes] = await Promise.all([
      supabase.from('animaux').select('id, nom, espece')
        .eq('uid_eleveur', user.uid).eq('is_association', true).order('nom'),
      supabase.from('employes').select('uid_employe, type, prenom, nom')
        .eq('uid_eleveur', user.uid).eq('actif', true).eq('profil_source', 'association'),
    ]);
    const owned = (ownedRes.data ?? []) as AnimalOption[];
    const ownedIds = new Set(owned.map(a => a.id));
    let received: AnimalOption[] = [];
    if (profileId) {
      const { data: byProfile } = await supabase.from('animaux_proprietes')
        .select('animal_id').eq('uid_proprio', user.uid).eq('profile_id_proprio', profileId);
      const ids = [...new Set((byProfile ?? []).map(r => r.animal_id as string))].filter(id => !ownedIds.has(id));
      if (ids.length > 0) {
        const { data } = await supabase.from('animaux').select('id, nom, espece').in('id', ids).order('nom');
        received = (data ?? []) as AnimalOption[];
      }
    }
    setAnimaux([...owned, ...received]);
    setMembres((employesRes.data ?? [])
      .filter((e: { uid_employe?: string | null }) => !!e.uid_employe)
      .map((e: { uid_employe: string; type: string; prenom?: string; nom?: string }) => ({
        uid: e.uid_employe,
        type: e.type === 'benevole' ? 'benevole' : 'employe',
        nom: `${e.prenom ?? ''} ${e.nom ?? ''}`.trim() || 'Sans nom',
      })));
  }, [user, profilSource, profileId]);

  useEffect(() => { loadEquipeEtAnimaux(); }, [loadEquipeEtAnimaux]);

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
        const { data: moi } = await supabase.from('user_profiles')
          .select('firstname, lastname, nom, profile_type')
          .eq('uid', user!.uid).eq('is_main', true).maybeSingle();
        const nomEmploye = moi
          ? (moi.profile_type === 'eleveur' ? (moi.nom ?? 'Votre employé') : `${moi.firstname ?? ''} ${moi.lastname ?? ''}`.trim())
          : 'Votre employé';

        await supabase.from('notifications').insert({
          uid:   t.uid_eleveur,
          type:  'tache_validee',
          title: 'Tâche validée ✓',
          body:  `${nomEmploye} a terminé : ${t.titre}`,
          data:  { tacheId: t.id, eleveurUid: t.uid_eleveur },
          read:  false,
          ...(t.eleveur_profile_id ? { profile_id: t.eleveur_profile_id } : {}),
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
        <h1 className="text-xl font-bold text-[#1F2A2E] flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          Mes tâches
        </h1>
        {profilSource === 'association' && (
          <button onClick={() => setShowAddTache(true)}
            className="flex items-center gap-1.5 text-sm font-semibold text-white bg-[#0C5C6C] hover:bg-[#094F5D] rounded-xl px-3 py-2 transition-colors">
            <span className="text-base leading-none">+</span> Nouvelle tâche
          </button>
        )}
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

      {showAddTache && (
        <AddTacheModal
          uid={user.uid}
          profileId={profileId}
          animaux={animaux}
          membres={membres}
          onClose={() => setShowAddTache(false)}
          onSaved={() => { setShowAddTache(false); load(); }}
        />
      )}
    </div>
  );
}

// ── Modal création de tâche (côté association) ──────────────────────────────

function AddTacheModal({ uid, profileId, animaux, membres, onClose, onSaved }: {
  uid: string;
  profileId: string | null;
  animaux: AnimalOption[];
  membres: MembreOption[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const today = new Date().toISOString().split('T')[0];
  const [titre, setTitre] = useState('');
  const [date, setDate] = useState(today);
  const [heure, setHeure] = useState('');
  const [animalId, setAnimalId] = useState('');
  const [assigneUid, setAssigneUid] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!titre.trim() || !date) return;
    setSaving(true);

    let assigneProfileId: string | null = null;
    if (assigneUid) {
      const { data } = await supabase.from('user_profiles')
        .select('id').eq('uid', assigneUid).eq('profile_type', 'particulier').maybeSingle();
      assigneProfileId = data?.id ?? null;
    }

    const { data: inserted, error } = await supabase.from('taches_elevage').insert({
      uid_eleveur: uid,
      titre: titre.trim(),
      date, heure: heure || null,
      notes: notes.trim() || null,
      statut: 'a_faire',
      profil_source: 'association',
      ...(profileId ? { eleveur_profile_id: profileId, profile_id: profileId } : {}),
      animal_id: animalId || null,
      assigne_a: assigneUid || null,
      assignes_a: assigneUid ? [assigneUid] : null,
      ...(assigneProfileId ? { assigne_profile_id: assigneProfileId } : {}),
    }).select().single();

    if (!error && assigneUid) {
      try {
        await supabase.from('notifications').insert({
          uid: assigneUid, type: 'tache_assignee',
          title: 'Nouvelle tâche assignée 📋',
          body: titre.trim(),
          data: { tacheId: (inserted as { id: string })?.id },
          read: false,
          ...(assigneProfileId ? { profile_id: assigneProfileId } : {}),
        });
      } catch (_) {}
    }

    setSaving(false);
    if (error) { alert(`Erreur: ${error.message}`); return; }
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-gray-800 mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
          Nouvelle tâche
        </h2>
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Titre *</label>
            <input
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
              placeholder="Ex: Nettoyage cage, Promenade…"
              value={titre}
              onChange={e => setTitre(e.target.value)}
              autoFocus
            />
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="text-xs font-semibold text-gray-500 mb-1 block">Date *</label>
              <input
                type="date"
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
                value={date}
                onChange={e => setDate(e.target.value)}
              />
            </div>
            <div className="flex-1">
              <label className="text-xs font-semibold text-gray-500 mb-1 block">Heure</label>
              <input
                type="time"
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
                value={heure}
                onChange={e => setHeure(e.target.value)}
              />
            </div>
          </div>
          {animaux.length > 0 && (
            <div>
              <label className="text-xs font-semibold text-gray-500 mb-1 block">Animal (optionnel)</label>
              <select
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400 bg-white"
                value={animalId}
                onChange={e => setAnimalId(e.target.value)}
              >
                <option value="">— Sélectionner —</option>
                {animaux.map(a => (
                  <option key={a.id} value={a.id}>{a.nom}{a.espece ? ` (${a.espece})` : ''}</option>
                ))}
              </select>
            </div>
          )}
          {membres.length > 0 && (
            <div>
              <label className="text-xs font-semibold text-gray-500 mb-1 block">Assigner à un bénévole ou employé (optionnel)</label>
              <select
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400 bg-white"
                value={assigneUid}
                onChange={e => setAssigneUid(e.target.value)}
              >
                <option value="">— Personne —</option>
                {membres.map(m => (
                  <option key={m.uid} value={m.uid}>{m.nom} {m.type === 'benevole' ? '(Bénévole)' : '(Employé)'}</option>
                ))}
              </select>
            </div>
          )}
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Notes (optionnel)</label>
            <textarea
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400 resize-none"
              placeholder="Informations complémentaires…"
              rows={2}
              value={notes}
              onChange={e => setNotes(e.target.value)}
            />
          </div>
        </div>
        <div className="flex gap-3 mt-5">
          <button onClick={onClose}
            className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
            Annuler
          </button>
          <button onClick={save} disabled={!titre.trim() || !date || saving}
            className="flex-1 py-2.5 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-40 text-white rounded-xl text-sm font-semibold transition-colors">
            {saving ? 'Ajout…' : 'Ajouter'}
          </button>
        </div>
      </div>
    </div>
  );
}
