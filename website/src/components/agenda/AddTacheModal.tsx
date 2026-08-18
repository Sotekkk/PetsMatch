'use client';

import { useState } from 'react';
import { supabase } from '@/lib/supabase';

export interface AnimalOption { id: string; nom: string; espece?: string | null; portee_id?: string | null; nom_mere?: string | null; }
export interface MembreOption { uid: string; nom: string; type: 'employe' | 'benevole' | 'moi'; }

/**
 * Charge la liste des personnes assignables à une tâche : l'utilisateur
 * lui-même ("Moi") + les employés/bénévoles. Le nom d'un employé avec compte
 * PetsMatch est résolu depuis son propre profil (user_profiles), pas depuis
 * la fiche employé (qui ne contient prenom/nom que pour les employés
 * manuels, sans compte).
 */
export async function loadMembres(uid: string, profilSource: 'eleveur' | 'association' | 'pension'): Promise<MembreOption[]> {
  const [{ data: moi }, { data: employesRows }] = await Promise.all([
    supabase.from('user_profiles').select('firstname, lastname, nom, profile_type')
      .eq('uid', uid).eq('is_main', true).maybeSingle(),
    supabase.from('employes').select('uid_employe, employe_profile_id, type, prenom, nom')
      .eq('uid_eleveur', uid).eq('actif', true).eq('profil_source', profilSource),
  ]);

  const nomMoi = moi
    ? (moi.profile_type === 'eleveur' ? (moi.nom ?? 'Moi') : `${moi.firstname ?? ''} ${moi.lastname ?? ''}`.trim() || 'Moi')
    : 'Moi';
  const membres: MembreOption[] = [{ uid, nom: nomMoi, type: 'moi' }];

  const rows = (employesRows ?? []) as { uid_employe: string | null; employe_profile_id: string | null; type: string; prenom?: string | null; nom?: string | null }[];

  // Employés avec compte : résoudre le nom depuis leur propre profil.
  const accountRows = rows.filter(e => e.uid_employe);
  const accountUids = accountRows.map(e => e.uid_employe as string);
  const profilesByUid = new Map<string, { firstname?: string; lastname?: string; nom?: string; profile_type?: string }>();
  if (accountUids.length > 0) {
    const { data: profiles } = await supabase.from('user_profiles')
      .select('uid, firstname, lastname, nom, profile_type')
      .in('uid', accountUids).eq('is_main', true);
    for (const p of (profiles ?? [])) profilesByUid.set(p.uid as string, p);
  }
  for (const e of accountRows) {
    const p = profilesByUid.get(e.uid_employe as string);
    const nom = p
      ? (p.profile_type === 'eleveur' ? (p.nom ?? 'Sans nom') : `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || 'Sans nom')
      : (`${e.prenom ?? ''} ${e.nom ?? ''}`.trim() || 'Sans nom');
    membres.push({ uid: e.uid_employe as string, type: e.type === 'benevole' ? 'benevole' : 'employe', nom });
  }

  // Employés manuels (sans compte) : le prénom/nom saisi sert d'identifiant,
  // mais sans uid réel ils ne peuvent pas être assignés (pas de compte pour
  // recevoir la notification) — on ne les ajoute donc pas à cette liste.

  return membres;
}

export function AddTacheModal({ uid, profileId, profilSource, selectedDate, animaux, membres, onClose, onSaved, onEmployeCreated }: {
  uid: string;
  profileId: string | null;
  profilSource: 'eleveur' | 'association' | 'pension';
  selectedDate?: string;
  animaux: AnimalOption[];
  membres: MembreOption[];
  onClose: () => void;
  onSaved: () => void;
  onEmployeCreated: () => void;
}) {
  const today = new Date().toISOString().split('T')[0];
  const [titre, setTitre] = useState('');
  const [date, setDate] = useState(selectedDate ?? today);
  const [heure, setHeure] = useState('');
  const [selectedAnimalIds, setSelectedAnimalIds] = useState<string[]>([]);
  const [assigneUid, setAssigneUid] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [showAddEmploye, setShowAddEmploye] = useState(false);
  const [animalSearch, setAnimalSearch] = useState('');

  const filteredAnimaux = animalSearch.trim()
    ? animaux.filter(a => a.nom.toLowerCase().includes(animalSearch.trim().toLowerCase()))
    : animaux;

  const porteeGroups = new Map<string, AnimalOption[]>();
  if (profilSource === 'eleveur') {
    for (const a of animaux) {
      if (!a.portee_id) continue;
      if (!porteeGroups.has(a.portee_id)) porteeGroups.set(a.portee_id, []);
      porteeGroups.get(a.portee_id)!.push(a);
    }
  }

  function porteeLabel(membresPortee: AnimalOption[]): string {
    const nomMere = membresPortee.map(a => a.nom_mere).find(n => !!n);
    return nomMere ? `Portée de ${nomMere}` : 'Portée';
  }

  function toggleAnimal(id: string) {
    setSelectedAnimalIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  }

  // Bascule toute la portée : si tous ses membres sont déjà sélectionnés, on
  // les retire (permet de se rattraper après un clic par erreur), sinon on
  // les ajoute à la sélection existante.
  function togglePortee(membresPortee: AnimalOption[]) {
    const ids = membresPortee.map(a => a.id);
    const allSelected = ids.every(id => selectedAnimalIds.includes(id));
    setSelectedAnimalIds(prev => allSelected
      ? prev.filter(id => !ids.includes(id))
      : [...new Set([...prev, ...ids])]);
  }

  async function save() {
    if (!titre.trim() || !date) return;
    setSaving(true);

    const isSelf = assigneUid === uid;
    let assigneProfileId: string | null = null;
    if (assigneUid && !isSelf) {
      const { data } = await supabase.from('user_profiles')
        .select('id').eq('uid', assigneUid).eq('profile_type', 'particulier').maybeSingle();
      assigneProfileId = data?.id ?? null;
    } else if (isSelf) {
      assigneProfileId = profileId;
    }

    // Une ligne par animal sélectionné (ou une seule ligne sans animal si aucun choisi).
    const animalIds: (string | null)[] = selectedAnimalIds.length > 0 ? selectedAnimalIds : [null];
    let error: { message: string } | null = null;
    const insertedByAnimal: { animalId: string | null; tacheId: string }[] = [];
    for (const animalId of animalIds) {
      const { data: inserted, error: insertError } = await supabase.from('taches_elevage').insert({
        uid_eleveur: uid,
        titre: titre.trim(),
        date, heure: heure || null,
        notes: notes.trim() || null,
        statut: 'a_faire',
        profil_source: profilSource,
        ...(profileId ? { eleveur_profile_id: profileId, profile_id: profileId } : {}),
        animal_id: animalId,
        animal_nom: animalId ? (animaux.find(a => a.id === animalId)?.nom ?? null) : null,
        assigne_a: assigneUid || null,
        assignes_a: assigneUid ? [assigneUid] : null,
        ...(assigneProfileId ? { assigne_profile_id: assigneProfileId } : {}),
      }).select().single();
      if (insertError) { error = insertError; break; }
      const tacheId = (inserted as { id: string })?.id ?? null;
      if (tacheId) insertedByAnimal.push({ animalId, tacheId });
    }

    // Une notification par animal (portée entière = 1 tâche + 1 notif par chiot),
    // avec le nom du chiot et sa portée dans le corps pour éviter toute confusion
    // à l'employé qui décoche les tâches une par une. On envoie aussi une copie
    // à l'éleveur (créateur) pour qu'il puisse suivre quel chiot est assigné à
    // qui sans avoir à se connecter sur le compte de l'employé.
    if (!error && assigneUid && !isSelf) {
      try {
        const nomEmploye = membres.find(m => m.uid === assigneUid)?.nom ?? 'un employé';
        await Promise.all(insertedByAnimal.map(({ animalId, tacheId }) => {
          const animal = animalId ? animaux.find(a => a.id === animalId) : undefined;
          const groupePortee = animal?.portee_id ? porteeGroups.get(animal.portee_id) : undefined;
          const portee = groupePortee ? porteeLabel(groupePortee) : null;
          const suffix = animal ? ` — ${animal.nom}${portee ? ` (${portee})` : ''}` : '';
          return Promise.all([
            supabase.from('notifications').insert({
              uid: assigneUid, type: 'tache_assignee',
              title: 'Nouvelle tâche assignée 📋',
              body: `${titre.trim()}${suffix}`,
              data: { tacheId },
              read: false,
              ...(assigneProfileId ? { profile_id: assigneProfileId } : {}),
            }),
            supabase.from('notifications').insert({
              uid, type: 'tache_assignee',
              title: 'Tâche assignée 📋',
              body: `Assigné à ${nomEmploye} : ${titre.trim()}${suffix}`,
              data: { tacheId },
              read: false,
              ...(profileId ? { profile_id: profileId } : {}),
            }),
          ]);
        }));
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
              <label className="text-xs font-semibold text-gray-500 mb-1 block">
                Animaux concernés (optionnel){selectedAnimalIds.length > 0 ? ` — ${selectedAnimalIds.length} sélectionné(s)` : ''}
              </label>
              {porteeGroups.size > 0 && (
                <div className="flex flex-wrap gap-1.5 mb-1.5">
                  {[...porteeGroups.entries()].map(([porteeId, membresPortee]) => {
                    const allSelected = membresPortee.every(a => selectedAnimalIds.includes(a.id));
                    return (
                      <button key={porteeId} type="button" onClick={() => togglePortee(membresPortee)}
                        className={`text-xs font-semibold rounded-full px-2.5 py-1 border transition-colors ${
                          allSelected
                            ? 'text-white bg-teal-600 border-teal-600 hover:bg-teal-700'
                            : 'text-teal-700 bg-teal-50 border-teal-200 hover:bg-teal-100'
                        }`}>
                        {allSelected ? '✓ ' : ''}{porteeLabel(membresPortee)} ({membresPortee.length})
                      </button>
                    );
                  })}
                </div>
              )}
              {animaux.length > 5 && (
                <input
                  type="text"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm mb-1.5 focus:outline-none focus:ring-2 focus:ring-teal-400"
                  placeholder="Rechercher un animal…"
                  value={animalSearch}
                  onChange={e => setAnimalSearch(e.target.value)}
                />
              )}
              <div className="border border-gray-200 rounded-xl max-h-32 overflow-y-auto">
                {filteredAnimaux.length === 0 ? (
                  <p className="px-3 py-2 text-sm text-gray-400">Aucun animal pour « {animalSearch.trim()} »</p>
                ) : filteredAnimaux.map(a => {
                  const checked = selectedAnimalIds.includes(a.id);
                  return (
                    <label key={a.id} className={`flex items-center gap-2 px-3 py-2 text-sm cursor-pointer border-b border-gray-100 last:border-0 transition-colors ${
                      checked ? 'bg-teal-100 text-teal-900 font-semibold' : 'hover:bg-gray-50'
                    }`}>
                      <input type="checkbox" checked={checked} onChange={() => toggleAnimal(a.id)}
                        className="rounded text-teal-600 focus:ring-teal-400" />
                      <span>{a.nom}{a.espece ? ` (${a.espece})` : ''}</span>
                    </label>
                  );
                })}
              </div>
            </div>
          )}
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-xs font-semibold text-gray-500 block">Assigner à (optionnel)</label>
              <button type="button" onClick={() => setShowAddEmploye(v => !v)}
                className="text-xs font-semibold text-teal-700 hover:text-teal-800">
                + Nouvel employé
              </button>
            </div>
            <select
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400 bg-white"
              value={assigneUid}
              onChange={e => setAssigneUid(e.target.value)}
            >
              <option value="">— Personne —</option>
              {membres.map(m => (
                <option key={m.uid} value={m.uid}>
                  {m.nom} {m.type === 'moi' ? '(Vous)' : m.type === 'benevole' ? '(Bénévole)' : '(Employé)'}
                </option>
              ))}
            </select>
            {showAddEmploye && (
              <AddEmployeInline
                uid={uid} profileId={profileId} profilSource={profilSource}
                onClose={() => setShowAddEmploye(false)}
                onCreated={() => { setShowAddEmploye(false); onEmployeCreated(); }}
              />
            )}
          </div>
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

// ── Création rapide d'un employé/bénévole sans compte PetsMatch ─────────────
// Le prénom sert d'identifiant d'affichage. Cet employé n'a pas de compte, il
// n'est donc pas assignable tant qu'il n'en a pas créé un (comme sur "Mes
// employés"), mais il est immédiatement visible dans l'équipe.

function AddEmployeInline({ uid, profileId, profilSource, onClose, onCreated }: {
  uid: string;
  profileId: string | null;
  profilSource: 'eleveur' | 'association' | 'pension';
  onClose: () => void;
  onCreated: () => void;
}) {
  const [prenom, setPrenom] = useState('');
  const [nom, setNom] = useState('');
  const [email, setEmail] = useState('');
  const [telephone, setTelephone] = useState('');
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!prenom.trim() || !nom.trim()) return;
    setSaving(true);
    const { error } = await supabase.from('employes').insert({
      uid_eleveur: uid,
      ...(profileId ? { eleveur_profile_id: profileId } : {}),
      prenom: prenom.trim(),
      nom: nom.trim(),
      email: email.trim() || null,
      telephone: telephone.trim() || null,
      actif: true,
      type: 'employe',
      profil_source: profilSource,
    });
    setSaving(false);
    if (error) { alert(`Erreur: ${error.message}`); return; }
    onCreated();
  }

  return (
    <div className="mt-2 p-3 border border-teal-200 bg-teal-50/50 rounded-xl space-y-2">
      <div className="flex gap-2">
        <input
          className="flex-1 border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
          placeholder="Prénom *" value={prenom} onChange={e => setPrenom(e.target.value)} autoFocus
        />
        <input
          className="flex-1 border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
          placeholder="Nom *" value={nom} onChange={e => setNom(e.target.value)}
        />
      </div>
      <input
        className="w-full border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
        placeholder="Email (optionnel)" type="email" value={email} onChange={e => setEmail(e.target.value)}
      />
      <input
        className="w-full border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400"
        placeholder="Téléphone (optionnel)" type="tel" value={telephone} onChange={e => setTelephone(e.target.value)}
      />
      <div className="flex gap-2">
        <button type="button" onClick={onClose}
          className="flex-1 py-2 border border-gray-200 rounded-lg text-xs text-gray-600 hover:bg-white font-medium">
          Annuler
        </button>
        <button type="button" onClick={save} disabled={!prenom.trim() || !nom.trim() || saving}
          className="flex-1 py-2 bg-teal-600 hover:bg-teal-700 disabled:opacity-40 text-white rounded-lg text-xs font-semibold transition-colors">
          {saving ? 'Ajout…' : 'Ajouter l’employé'}
        </button>
      </div>
    </div>
  );
}
