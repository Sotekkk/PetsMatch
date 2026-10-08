'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';

export interface AnimalOption { id: string; nom: string; espece?: string | null; portee_id?: string | null; nom_mere?: string | null; }
export interface MembreOption { uid: string; nom: string; type: 'employe' | 'benevole' | 'moi'; }

/**
 * Charge la liste des personnes assignables à une tâche : l'utilisateur
 * lui-même ("Moi") + les employés/bénévoles. Le nom d'un employé avec compte
 * PetsMatch est résolu depuis son propre profil (user_profiles), pas depuis
 * la fiche employé (qui ne contient prenom/nom que pour les employés
 * manuels, sans compte).
 *
 * `uid` = propriétaire de l'élevage (sert à retrouver la liste d'employés,
 * `employes.uid_eleveur`) ; `myUid` (optionnel, sinon = `uid`) = identité
 * réelle de la personne connectée, utilisée pour "Moi". Distincts pour un
 * cogérant (elevage_cogerants) : son uid Firebase diffère de celui du
 * gérant, "Moi" doit rester lui-même, pas le gérant qu'il emprunte.
 */
export async function loadMembres(uid: string, profilSource: 'eleveur' | 'association' | 'pension', myUid?: string): Promise<MembreOption[]> {
  const moiUid = myUid ?? uid;
  const [{ data: moi }, { data: employesRows }] = await Promise.all([
    supabase.from('user_profiles_complet').select('firstname, lastname, nom, profile_type')
      .eq('uid', moiUid).eq('is_main', true).maybeSingle(),
    supabase.from('employes').select('uid_employe, employe_profile_id, type, prenom, nom')
      .eq('uid_eleveur', uid).eq('actif', true).eq('profil_source', profilSource),
  ]);

  const nomMoi = moi
    ? (moi.profile_type === 'eleveur' ? (moi.nom ?? 'Moi') : `${moi.firstname ?? ''} ${moi.lastname ?? ''}`.trim() || 'Moi')
    : 'Moi';
  const membres: MembreOption[] = [{ uid: moiUid, nom: nomMoi, type: 'moi' }];

  const rows = (employesRows ?? []) as { uid_employe: string | null; employe_profile_id: string | null; type: string; prenom?: string | null; nom?: string | null }[];

  // Employés avec compte : résoudre le nom depuis leur propre profil.
  const accountRows = rows.filter(e => e.uid_employe);
  const accountUids = accountRows.map(e => e.uid_employe as string);
  const profilesByUid = new Map<string, { firstname?: string; lastname?: string; nom?: string; profile_type?: string }>();
  if (accountUids.length > 0) {
    const { data: profiles } = await supabase.from('user_profiles_complet')
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

export function AddTacheModal({ uid, myUid, profileId, profilSource, selectedDate, animaux, membres, onClose, onSaved, onEmployeCreated }: {
  /** Propriétaire de l'élevage (uid_eleveur écrit sur la tâche/l'employé créé). */
  uid: string;
  /** Identité réelle de la personne connectée (défaut : `uid`) — sert
   * uniquement à détecter "assigné à Moi" ; distincte de `uid` pour un
   * cogérant (elevage_cogerants), dont l'uid Firebase diffère du gérant. */
  myUid?: string;
  profileId: string | null;
  profilSource: 'eleveur' | 'association' | 'pension';
  selectedDate?: string;
  /** Animaux de l'élevage ; absents = chargés au 1er choix « Animal » / « Portée ». */
  animaux?: AnimalOption[];
  membres: MembreOption[];
  onClose: () => void;
  onSaved: () => void;
  onEmployeCreated: () => void;
}) {
  const [animauxCharges, setAnimauxCharges] = useState<AnimalOption[] | null>(animaux ?? null);
  const [chargementAnimaux, setChargementAnimaux] = useState(false);
  const animauxDispo = animauxCharges ?? [];
  async function chargerAnimaux() {
    if (animauxCharges || chargementAnimaux) return;
    setChargementAnimaux(true);
    let q = supabase.from('animaux').select('id, nom, espece, portee_id, nom_mere')
      .eq('uid_eleveur', uid).not('statut', 'in', '(sorti,decede)');
    if (profileId) q = q.eq('profile_id', profileId);
    const { data } = await q.order('nom');
    setAnimauxCharges((data ?? []) as AnimalOption[]);
    setChargementAnimaux(false);
  }
  const today = new Date().toISOString().split('T')[0];
  const [titre, setTitre] = useState('');
  const [date, setDate] = useState(selectedDate ?? today);
  const [heure, setHeure] = useState('');
  const [assigneUid, setAssigneUid] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [showAddEmploye, setShowAddEmploye] = useState(false);
  // Rattachement choisi par l'utilisateur (jamais déduit du titre) :
  // aucun par défaut, sinon des animaux OU des portées — jamais mélangés.
  const [rattachement, setRattachement] = useState<'aucun' | 'animal' | 'portee'>('aucun');
  const [animalIds, setAnimalIds] = useState<string[]>([]);
  const [porteeIds, setPorteeIds] = useState<string[]>([]);

  const portees = useMemo(() => {
    const map = new Map<string, AnimalOption[]>();
    for (const a of animauxDispo) {
      if (!a.portee_id) continue;
      if (!map.has(a.portee_id)) map.set(a.portee_id, []);
      map.get(a.portee_id)!.push(a);
    }
    return [...map.entries()].map(([id, membres]) => ({ id, membres, label: porteeLabel(membres) }));
  }, [animauxDispo]);

  function porteeLabel(membresPortee: AnimalOption[]): string {
    const nomMere = membresPortee.map(a => a.nom_mere).find(n => !!n);
    return nomMere ? `Portée de ${nomMere}` : 'Portée';
  }

  // Animaux réellement concernés à l'enregistrement (portée = ses membres).
  const idsCibles: string[] = rattachement === 'animal'
    ? animalIds
    : rattachement === 'portee'
      ? [...new Set(portees.filter(p => porteeIds.includes(p.id)).flatMap(p => p.membres.map(a => a.id)))]
      : [];

  async function save() {
    if (!titre.trim() || !date) return;
    setSaving(true);

    const isSelf = assigneUid === (myUid ?? uid);
    let assigneProfileId: string | null = null;
    if (assigneUid && !isSelf) {
      const { data } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', assigneUid).eq('profile_type', 'particulier').maybeSingle();
      assigneProfileId = data?.id ?? null;
    } else if (isSelf) {
      assigneProfileId = profileId;
    }

    // Une ligne par animal concerné (ou une seule ligne sans animal).
    const lignes: (string | null)[] = idsCibles.length > 0 ? idsCibles : [null];
    let error: { message: string } | null = null;
    const insertedByAnimal: { animalId: string | null; tacheId: string }[] = [];
    for (const animalId of lignes) {
      const { data: inserted, error: insertError } = await supabase.from('taches_elevage').insert({
        uid_eleveur: uid,
        titre: titre.trim(),
        date, heure: heure || null,
        notes: notes.trim() || null,
        statut: 'a_faire',
        profil_source: profilSource,
        ...(profileId ? { eleveur_profile_id: profileId, profile_id: profileId } : {}),
        animal_id: animalId,
        animal_nom: animalId ? (animauxDispo.find(a => a.id === animalId)?.nom ?? null) : null,
        assigne_a: assigneUid || null,
        assignes_a: assigneUid ? [assigneUid] : null,
        ...(assigneProfileId ? { assigne_profile_id: assigneProfileId } : {}),
      }).select().single();
      if (insertError) { error = insertError; break; }
      const tacheId = (inserted as { id: string })?.id ?? null;
      if (tacheId) insertedByAnimal.push({ animalId, tacheId });
    }

    // Une notification par animal (portée entière = 1 tâche + 1 notif par chiot),
    // avec le nom du chiot et sa portée dans le corps, + copie à l'éleveur.
    if (!error && assigneUid && !isSelf) {
      try {
        const nomEmploye = membres.find(m => m.uid === assigneUid)?.nom ?? 'un employé';
        await Promise.all(insertedByAnimal.map(({ animalId, tacheId }) => {
          const animal = animalId ? animauxDispo.find(a => a.id === animalId) : undefined;
          const groupe = animal?.portee_id ? portees.find(p => p.id === animal.portee_id) : undefined;
          const suffix = animal ? ` — ${animal.nom}${groupe ? ` (${groupe.label})` : ''}` : '';
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

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-teal-400';
  const libelle = 'text-xs font-semibold text-gray-500 mb-1 block';
  const nbCibles = idsCibles.length;

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center sm:p-4" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md shadow-xl max-h-[92vh] flex flex-col" onClick={e => e.stopPropagation()}>
        {/* En-tête */}
        <div className="flex items-center justify-between px-5 pt-4 pb-3 border-b border-gray-100">
          <h2 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Nouvelle tâche</h2>
          <button onClick={onClose} aria-label="Fermer" className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
        </div>

        {/* Formulaire (défile seul ; le pied reste visible) */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">
          <div>
            <label className={libelle}>Titre *</label>
            <input className={champ} placeholder="Ex : Faire l'inventaire des croquettes"
              value={titre} onChange={e => setTitre(e.target.value)} autoFocus />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className={libelle}>Date *</label>
              <input type="date" className={champ} value={date} onChange={e => setDate(e.target.value)} />
            </div>
            <div>
              <label className={libelle}>Heure</label>
              <input type="time" className={champ} value={heure} onChange={e => setHeure(e.target.value)} />
            </div>
          </div>

          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-xs font-semibold text-gray-500">Attribuer à</label>
              <button type="button" onClick={() => setShowAddEmploye(v => !v)}
                className="text-xs font-semibold text-teal-700 hover:text-teal-800">+ Nouvel employé</button>
            </div>
            <select className={champ} value={assigneUid} onChange={e => setAssigneUid(e.target.value)}>
              <option value="">Personne</option>
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

          {/* Rattachement : Aucun / Animal / Portée — jamais mélangés */}
          <div>
            <label className={libelle}>Rattachement (optionnel)</label>
            <div className="grid grid-cols-3 gap-1 p-1 bg-gray-100 rounded-xl">
              {([['aucun', 'Aucun'], ['animal', 'Animal'], ['portee', 'Portée']] as const).map(([v, l]) => {
                const indispo = !!animauxCharges && ((v === 'animal' && animauxDispo.length === 0) || (v === 'portee' && portees.length === 0));
                return (
                  <button key={v} type="button" disabled={indispo} onClick={() => { setRattachement(v); if (v !== 'aucun') chargerAnimaux(); }}
                    title={indispo ? (v === 'portee' ? 'Aucune portée' : 'Aucun animal') : undefined}
                    className={`py-2 rounded-lg text-sm font-semibold transition-colors disabled:opacity-35 ${
                      rattachement === v ? 'bg-white text-[#0C5C6C] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
                    {l}
                  </button>
                );
              })}
            </div>
            {rattachement !== 'aucun' && chargementAnimaux && (
              <p className="text-xs text-gray-400 mt-2">Chargement…</p>
            )}
            {rattachement === 'animal' && !chargementAnimaux && (
              <MultiSelectRattachement
                placeholder="Choisir des animaux…"
                recherche="Rechercher un animal…"
                items={animauxDispo.map(a => ({ id: a.id, label: a.nom, detail: a.espece ?? undefined, filtre: a.espece ?? 'Autre' }))}
                filtreLabel="Espèce"
                unite={['animal', 'animaux']}
                value={animalIds} onChange={setAnimalIds}
              />
            )}
            {rattachement === 'portee' && !chargementAnimaux && (
              <MultiSelectRattachement
                placeholder="Choisir des portées…"
                recherche="Rechercher une portée (nom de la mère)…"
                items={portees.map(p => ({
                  id: p.id, label: p.label,
                  detail: `${p.membres.length} ${p.membres.length > 1 ? 'petits' : 'petit'}`,
                  filtre: p.membres[0]?.espece ?? 'Autre',
                }))}
                filtreLabel="Espèce"
                unite={['portée', 'portées']}
                value={porteeIds} onChange={setPorteeIds}
              />
            )}
            {rattachement === 'portee' && nbCibles > 0 && (
              <p className="text-[11px] text-gray-400 mt-1.5">Une tâche sera créée pour chacun des {nbCibles} petits.</p>
            )}
          </div>

          <div>
            <label className={libelle}>Note (optionnel)</label>
            <textarea className={`${champ} resize-none`} rows={3}
              placeholder="Consignes, détails… Ex : après réception de la commande, compter les sacs et mettre à jour les stocks."
              value={notes} onChange={e => setNotes(e.target.value)} />
          </div>
        </div>

        {/* Pied fixe */}
        <div className="flex gap-3 px-5 py-3 border-t border-gray-100">
          <button onClick={onClose}
            className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-medium">
            Annuler
          </button>
          <button onClick={save} disabled={!titre.trim() || !date || saving}
            className="flex-[1.4] py-2.5 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-40 text-white rounded-xl text-sm font-semibold transition-colors">
            {saving ? 'Création…' : nbCibles > 1 ? `Créer la tâche (×${nbCibles})` : 'Créer la tâche'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Menu déroulant multi-sélection (animaux OU portées) ──────────────────────
// Recherche + filtre (espèce) + cases à cocher, défilement interne. Fermé :
// étiquettes supprimables, ou un résumé au-delà de 6 éléments.

interface ItemRattachement { id: string; label: string; detail?: string; filtre: string }

function MultiSelectRattachement({ placeholder, recherche, items, filtreLabel, unite, value, onChange }: {
  placeholder: string;
  recherche: string;
  items: ItemRattachement[];
  filtreLabel: string;
  unite: [string, string];
  value: string[];
  onChange: (ids: string[]) => void;
}) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const [filtre, setFiltre] = useState('');
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const filtres = [...new Set(items.map(i => i.filtre))].sort();
  const visibles = items.filter(i =>
    (!filtre || i.filtre === filtre) &&
    (!q.trim() || i.label.toLowerCase().includes(q.trim().toLowerCase())));
  const toutVisibleCoche = visibles.length > 0 && visibles.every(i => value.includes(i.id));
  const toggle = (id: string) => onChange(value.includes(id) ? value.filter(x => x !== id) : [...value, id]);
  const choisis = items.filter(i => value.includes(i.id));
  const nom = (n: number) => `${n} ${n > 1 ? unite[1] : unite[0]}`;

  return (
    <div className="relative mt-2" ref={ref}>
      <button type="button" onClick={() => setOpen(o => !o)}
        className={`w-full flex items-center justify-between border rounded-xl px-3 py-2.5 text-sm bg-white ${open ? 'border-teal-400 ring-2 ring-teal-100' : 'border-gray-200'}`}>
        <span className={value.length ? 'text-[#1F2A2E] font-medium' : 'text-gray-400'}>
          {value.length ? `${nom(value.length)} sélectionné${value.length > 1 ? 's' : ''}` : placeholder}
        </span>
        <span className={`text-gray-400 text-xs transition-transform ${open ? 'rotate-180' : ''}`}>▼</span>
      </button>

      {open && (
        <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
          <div className="p-2 space-y-2 border-b border-gray-100">
            <input autoFocus value={q} onChange={e => setQ(e.target.value)} placeholder={recherche}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400" />
            {filtres.length > 1 && (
              <div className="flex flex-wrap gap-1.5" aria-label={filtreLabel}>
                {['', ...filtres].map(f => (
                  <button key={f || 'tous'} type="button" onClick={() => setFiltre(f)}
                    className={`text-xs font-semibold rounded-full px-2.5 py-1 border ${filtre === f ? 'bg-teal-600 text-white border-teal-600' : 'bg-white text-gray-600 border-gray-200'}`}>
                    {f || 'Toutes'}
                  </button>
                ))}
              </div>
            )}
          </div>
          <div className="max-h-56 overflow-y-auto overscroll-contain">
            {visibles.length === 0 ? (
              <p className="px-3 py-3 text-sm text-gray-400">Aucun résultat</p>
            ) : visibles.map(i => (
              <label key={i.id} className={`flex items-center gap-2.5 px-3 py-2 text-sm cursor-pointer border-b border-gray-50 last:border-0 ${value.includes(i.id) ? 'bg-teal-50' : 'hover:bg-gray-50'}`}>
                <input type="checkbox" checked={value.includes(i.id)} onChange={() => toggle(i.id)} className="w-4 h-4 accent-[#0C5C6C]" />
                <span className="flex-1 min-w-0 truncate">{i.label}</span>
                {i.detail && <span className="text-xs text-gray-400 flex-shrink-0">{i.detail}</span>}
              </label>
            ))}
          </div>
          <div className="flex items-center justify-between gap-2 p-2 border-t border-gray-100">
            <button type="button" disabled={visibles.length === 0}
              onClick={() => onChange(toutVisibleCoche
                ? value.filter(id => !visibles.some(v => v.id === id))
                : [...new Set([...value, ...visibles.map(v => v.id)])])}
              className="text-xs font-semibold text-teal-700 px-2 py-1.5 rounded-lg hover:bg-teal-50 disabled:opacity-40">
              {toutVisibleCoche ? 'Tout décocher' : 'Tout cocher'}
            </button>
            <button type="button" onClick={() => setOpen(false)}
              className="text-xs font-semibold text-white bg-[#0C5C6C] px-4 py-1.5 rounded-lg">
              Valider{value.length ? ` (${value.length})` : ''}
            </button>
          </div>
        </div>
      )}

      {!open && choisis.length > 0 && (
        choisis.length > 6 ? (
          <div className="flex items-center gap-2 mt-2 text-xs">
            <span className="font-semibold text-teal-700 bg-teal-50 rounded-full px-3 py-1">{nom(choisis.length)}</span>
            <button type="button" onClick={() => setOpen(true)} className="text-teal-700 underline">Modifier</button>
            <button type="button" onClick={() => onChange([])} className="text-gray-400 hover:text-gray-600">Tout retirer</button>
          </div>
        ) : (
          <div className="flex flex-wrap gap-1.5 mt-2">
            {choisis.map(i => (
              <span key={i.id} className="inline-flex items-center gap-1 text-xs font-semibold text-teal-800 bg-teal-50 border border-teal-200 rounded-full pl-2.5 pr-1 py-0.5">
                {i.label}
                <button type="button" aria-label={`Retirer ${i.label}`} onClick={() => toggle(i.id)}
                  className="w-4 h-4 rounded-full hover:bg-teal-100 leading-none">×</button>
              </span>
            ))}
          </div>
        )
      )}
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
