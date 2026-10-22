'use client';

import { useEffect, useState, useCallback } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import { Icone } from '@/components/dashboard/kit';
import { estHorsPriseEnCharge } from '@/lib/protocoles';
import { AddTacheModal, loadMembres, type AnimalOption, type MembreOption } from '@/components/agenda/AddTacheModal';

// Équipe de l'association active (employés + bénévoles). Miroir appli :
// _EquipeAssociationTab (employes_page.dart) — mêmes filtres, mêmes
// libellés, mêmes actions. Toutes les lectures / écritures passent par le
// profil d'association actif (eleveur_profile_id), jamais par le seul uid.

// ── Types ──────────────────────────────────────────────────────────────────────

interface Tache {
  id: string;
  label: string;
  date?: string;
  statut?: string;
  animal_nom?: string;
}

interface UserProfile {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  profile_picture_url: string | null;
  profile_picture_url_elevage: string | null;
  phone_number?: string | null;
}

interface MembreEquipe {
  id: string;
  uid_employe?: string;
  employe_profile_id?: string | null;
  type: 'employe' | 'benevole';
  nom: string;
  prenom: string;
  email?: string;
  telephone?: string;
  notes?: string;
  actif: boolean;
  photo?: string | null;
  taches?: Tache[];
}

type FiltreRole = 'tous' | 'employe' | 'benevole';
type FiltreStatut = 'actifs' | 'inactifs' | 'tous';

const inp = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm font-galey bg-white focus:outline-none focus:border-[#0C5C6C]';
const btnContour = 'inline-flex items-center justify-center gap-1.5 h-10 px-4 rounded-lg border text-sm font-galey font-semibold transition-colors';

// Tâches en cours d'une personne POUR l'association active : plan_taches +
// taches_elevage, rattachées au profil (les anciennes tâches sans profil
// restent comptées via uid_eleveur + profil_source).
async function fetchTachesPersonne(uidEmploye: string, uidEleveur: string, profileId: string | null): Promise<Tache[]> {
  let planQ = supabase.from('plan_taches')
    .select('id, label, type_acte, date_prevue, statut, animal_nom')
    .eq('assigned_to', uidEmploye).eq('uid_eleveur', uidEleveur)
    .eq('profil_source', 'association').neq('statut', 'fait');
  let tacheQ = supabase.from('taches_elevage')
    .select('id, titre, date, statut, animal_nom')
    .eq('assigne_a', uidEmploye).eq('uid_eleveur', uidEleveur)
    .eq('profil_source', 'association').neq('statut', 'fait');
  if (profileId) {
    planQ = planQ.or(`eleveur_profile_id.eq.${profileId},eleveur_profile_id.is.null`);
    tacheQ = tacheQ.or(`eleveur_profile_id.eq.${profileId},eleveur_profile_id.is.null`);
  }
  const [planRes, tacheRes] = await Promise.all([planQ.order('date_prevue'), tacheQ.order('date')]);

  const planTaches: Tache[] = (planRes.data ?? []).map((t: { id: string; label?: string; type_acte?: string; date_prevue?: string; statut?: string; animal_nom?: string }) => ({
    id: `plan_${t.id}`, label: t.label || t.type_acte || 'Tâche',
    date: t.date_prevue, statut: t.statut, animal_nom: t.animal_nom,
  }));
  const tachesArr: Tache[] = (tacheRes.data ?? []).map((t: { id: string; titre?: string; date?: string; statut?: string; animal_nom?: string }) => ({
    id: `tache_${t.id}`, label: t.titre || 'Tâche',
    date: t.date, statut: t.statut, animal_nom: t.animal_nom ?? undefined,
  }));
  return [...planTaches, ...tachesArr];
}

const nomMembre = (m: MembreEquipe) =>
  `${m.prenom} ${m.nom}`.trim() || (m.type === 'benevole' ? 'Bénévole' : 'Employé');

const resumeTaches = (n: number) => n === 0 ? 'Aucune tâche' : `${n} tâche${n > 1 ? 's' : ''} en cours`;

// ── Page ──────────────────────────────────────────────────────────────────────

export default function EquipeWebPage() {
  const { user } = useAuth();
  const uid = user?.uid ?? '';
  const { id: profileId, loaded: profileLoaded } = useActiveProfileState();
  // key = profil : un changement de profil repart d'un état vide (aucun
  // résultat du profil précédent ne reste affiché).
  return profileLoaded && uid ? <EquipeUnifiee key={profileId ?? 'principal'} uid={uid} profileId={profileId} /> : null;
}

// ── Vue équipe ────────────────────────────────────────────────────────────────

function EquipeUnifiee({ uid, profileId }: { uid: string; profileId: string | null }) {
  const [membres, setMembres] = useState<MembreEquipe[]>([]);
  const [nomAsso, setNomAsso] = useState('');
  const [loading, setLoading] = useState(true);
  const [dbError, setDbError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [menuOuvert, setMenuOuvert] = useState<string | null>(null);
  const [ajout, setAjout] = useState(false);
  const [recherchePetsMatch, setRecherchePetsMatch] = useState<'employe' | 'benevole' | null>(null);
  const [editing, setEditing] = useState<MembreEquipe | null>(null);
  const [assigning, setAssigning] = useState<MembreEquipe | null>(null);
  const [congeFor, setCongeFor] = useState<MembreEquipe | null>(null);
  const [role, setRole] = useState<FiltreRole>('tous');
  const [statut, setStatut] = useState<FiltreStatut>('actifs');
  const [recherche, setRecherche] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setDbError(null);
    try {
      // Actifs ET inactifs (filtre « Statut ») de l'association active.
      let q = supabase.from('employes').select('*').eq('profil_source', 'association').order('created_at');
      q = profileId ? q.eq('eleveur_profile_id', profileId) : q.eq('uid_eleveur', uid);
      const [{ data: rows, error }, { data: asso }] = await Promise.all([
        q,
        profileId
          ? supabase.from('user_profiles_complet').select('nom').eq('id', profileId).maybeSingle()
          : Promise.resolve({ data: null }),
      ]);
      if (error) { setDbError(`${error.message} (${error.code})`); return; }
      setNomAsso(((asso as { nom?: string } | null)?.nom ?? '').trim());

      const result = await Promise.all((rows ?? []).map(async (row): Promise<MembreEquipe> => {
        const isBenevole = row.type === 'benevole';
        let nom = row.nom ?? '';
        let prenom = row.prenom ?? '';
        let photo: string | null = null;
        let taches: Tache[] = [];
        if (row.uid_employe) {
          const [{ data: p }, t] = await Promise.all([
            supabase.from('user_profiles_complet')
              .select('firstname, lastname, nom, profile_label, avatar_url, profile_picture_url_pro')
              .eq('uid', row.uid_employe).eq('profile_type', 'particulier').maybeSingle(),
            fetchTachesPersonne(row.uid_employe, uid, profileId),
          ]);
          const fullNom = p?.profile_label?.trim() || p?.nom?.trim()
            || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim()
            || (isBenevole ? 'Bénévole' : 'Employé');
          prenom = fullNom.split(' ')[0] ?? fullNom;
          nom = fullNom.split(' ').slice(1).join(' ') || '';
          photo = p?.avatar_url || p?.profile_picture_url_pro || null;
          taches = t;
        }
        return {
          id: row.id, uid_employe: row.uid_employe ?? undefined,
          employe_profile_id: row.employe_profile_id ?? null,
          type: isBenevole ? 'benevole' : 'employe',
          nom, prenom, email: row.email ?? undefined, telephone: row.telephone ?? undefined,
          notes: row.notes ?? undefined, actif: row.actif ?? true, photo, taches,
        };
      }));
      setMembres(result);
    } finally {
      setLoading(false);
    }
  }, [uid, profileId]);

  useEffect(() => { load(); }, [load]);

  // Menu « … » : fermé au clic extérieur ou avec Échap.
  useEffect(() => {
    if (!menuOuvert) return;
    const fermer = () => setMenuOuvert(null);
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') fermer(); };
    document.addEventListener('click', fermer);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('click', fermer); document.removeEventListener('keydown', onKey); };
  }, [menuOuvert]);

  // Désactiver : la personne perd l'accès à l'équipe (miroir appli), ses
  // tâches et congés restent dans l'historique. Réactiver la remet en place.
  const desactiver = async (m: MembreEquipe) => {
    if (!confirm(`Désactiver ${nomMembre(m)} ? La personne n'aura plus accès à l'équipe. Ses tâches et congés restent dans l'historique.`)) return;
    await supabase.from('employes').update({ actif: false }).eq('id', m.id);
    if (m.employe_profile_id) {
      await supabase.from('animaux')
        .update({ chaleurs_responsable_uid: null, chaleurs_responsable_profile_id: null })
        .eq('chaleurs_responsable_profile_id', m.employe_profile_id);
    }
    if (m.uid_employe) {
      await supabase.from('notifications').insert({
        uid: m.uid_employe, type: 'employee_revoked',
        title: 'Accès retiré',
        body: `Vous avez été retiré de l'équipe de ${nomAsso || "l'association"}`,
        ...(m.employe_profile_id ? { profile_id: m.employe_profile_id } : {}),
        data: { eleveurUid: uid },
        read: false,
      });
    }
    load();
  };

  const reactiver = async (m: MembreEquipe) => {
    await supabase.from('employes').update({ actif: true }).eq('id', m.id);
    load();
  };

  const supprimer = async (m: MembreEquipe) => {
    if (!confirm(`Supprimer ${nomMembre(m)} de l'équipe ? Cette action est définitive.`)) return;
    await supabase.from('employes').delete().eq('id', m.id);
    load();
  };

  // Filtres : statut + recherche d'abord (compteurs des onglets), puis rôle.
  const q = recherche.trim().toLowerCase();
  const visibles = membres.filter(m =>
    (statut === 'tous' || (statut === 'actifs' ? m.actif : !m.actif)) &&
    (!q || `${m.prenom} ${m.nom} ${m.email ?? ''} ${m.telephone ?? ''}`.toLowerCase().includes(q)));
  const compte = {
    tous: visibles.length,
    employe: visibles.filter(m => m.type === 'employe').length,
    benevole: visibles.filter(m => m.type === 'benevole').length,
  };
  const liste = role === 'tous' ? visibles : visibles.filter(m => m.type === role);

  const renderCard = (m: MembreEquipe) => {
    const displayName = nomMembre(m);
    const isOpen = expanded[m.id] ?? false;
    const taches = m.taches ?? [];
    return (
      <div key={m.id} className="bg-white rounded-xl border border-gray-200/80 shadow-[0_1px_3px_rgba(16,24,40,0.05)]">
        <div className="p-4 sm:p-5 flex flex-col sm:flex-row sm:items-center gap-4">
          <button type="button" onClick={() => setExpanded(prev => ({ ...prev, [m.id]: !isOpen }))}
            aria-expanded={isOpen}
            className="flex items-center gap-4 flex-1 min-w-0 text-left">
            <div className="w-14 h-14 rounded-full bg-[#E8F4F6] flex items-center justify-center flex-shrink-0 overflow-hidden">
              {m.photo
                ? <Image src={m.photo} alt={displayName} width={56} height={56} className="w-full h-full object-cover" unoptimized />
                : <span className="font-bold font-galey text-lg text-[#0C5C6C]">{displayName[0]?.toUpperCase() ?? '?'}</span>}
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <p className="font-semibold font-galey text-[#1F2A2E] text-base truncate">{displayName}</p>
                <span className="text-xs px-2 py-0.5 rounded-md font-galey font-semibold bg-[#E8F4F6] text-[#0C5C6C]">
                  {m.type === 'benevole' ? 'Bénévole' : 'Employé'}
                </span>
                {!m.actif && (
                  <span className="text-xs px-2 py-0.5 rounded-md font-galey font-semibold bg-gray-100 text-gray-600">Inactif</span>
                )}
              </div>
              {(m.telephone || m.email) && (
                <p className="text-sm text-gray-600 font-galey mt-0.5 truncate">
                  {[m.telephone, m.email].filter(Boolean).join(' · ')}
                </p>
              )}
              <p className="text-sm text-gray-500 font-galey mt-0.5">
                {m.uid_employe ? resumeTaches(taches.length) : 'Sans compte PetsMatch'}
              </p>
            </div>
            <Icone nom="fleche" taille={16} className={`text-gray-400 flex-shrink-0 transition-transform ${isOpen ? '-rotate-90' : 'rotate-90'}`} />
          </button>

          <div className="flex items-center gap-2 flex-wrap sm:flex-nowrap sm:flex-shrink-0">
            {m.uid_employe && m.actif && (
              <button type="button" onClick={() => setAssigning(m)}
                className={`${btnContour} border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#E8F4F6]`}>
                <Icone nom="plus" taille={15} /> Tâche
              </button>
            )}
            <button type="button" onClick={() => setCongeFor(m)}
              className={`${btnContour} border-gray-300 text-gray-700 hover:bg-gray-50`}>
              Congé
            </button>
            <button type="button" onClick={() => setEditing(m)} aria-label="Modifier" title="Modifier"
              className="w-10 h-10 inline-flex items-center justify-center rounded-lg text-gray-600 hover:bg-gray-100 hover:text-[#0C5C6C]">
              <Icone nom="crayon" taille={18} />
            </button>
            <div className="relative">
              <button type="button" aria-label="Plus d'actions" title="Plus d'actions" aria-haspopup="menu" aria-expanded={menuOuvert === m.id}
                onClick={e => { e.stopPropagation(); setMenuOuvert(menuOuvert === m.id ? null : m.id); }}
                className="w-10 h-10 inline-flex items-center justify-center rounded-lg text-gray-600 hover:bg-gray-100">
                <Icone nom="points" taille={18} />
              </button>
              {menuOuvert === m.id && (
                <div role="menu" onClick={e => e.stopPropagation()}
                  className="absolute right-0 top-11 z-20 w-48 bg-white border border-gray-200 rounded-xl shadow-lg py-1">
                  {m.actif ? (
                    <button role="menuitem" onClick={() => { setMenuOuvert(null); desactiver(m); }}
                      className="w-full text-left px-4 py-2.5 text-sm font-galey text-gray-700 hover:bg-gray-50">Désactiver</button>
                  ) : (
                    <button role="menuitem" onClick={() => { setMenuOuvert(null); reactiver(m); }}
                      className="w-full text-left px-4 py-2.5 text-sm font-galey text-gray-700 hover:bg-gray-50">Réactiver</button>
                  )}
                  <button role="menuitem" onClick={() => { setMenuOuvert(null); supprimer(m); }}
                    className="w-full text-left px-4 py-2.5 text-sm font-galey text-red-600 hover:bg-red-50">Supprimer</button>
                </div>
              )}
            </div>
          </div>
        </div>

        {isOpen && (
          <div className="border-t border-gray-100 bg-gray-50/70 px-4 sm:px-5 py-4 space-y-3 rounded-b-xl">
            <div className="grid sm:grid-cols-3 gap-3 text-sm font-galey">
              <div><p className="text-xs text-gray-500">Téléphone</p><p className="text-[#1F2A2E]">{m.telephone || 'Non renseigné'}</p></div>
              <div><p className="text-xs text-gray-500">Email</p><p className="text-[#1F2A2E] break-all">{m.email || 'Non renseigné'}</p></div>
              <div><p className="text-xs text-gray-500">Notes</p><p className="text-[#1F2A2E] whitespace-pre-line">{m.notes || 'Aucune note'}</p></div>
            </div>
            {m.uid_employe && (
              <div className="space-y-2">
                <p className="text-xs text-gray-500 font-galey">Tâches en cours</p>
                {taches.length === 0
                  ? <p className="text-sm text-gray-500 font-galey">Aucune tâche</p>
                  : taches.map(t => <TacheRow key={t.id} t={t} />)}
              </div>
            )}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="space-y-6">
      <nav aria-label="Fil d'Ariane" className="text-sm font-galey text-gray-500">
        <Link href="/association" className="hover:text-[#0C5C6C]">Mon association</Link>
        <span className="mx-2">/</span>
        <span className="text-[#1F2A2E]">Équipe</span>
      </nav>

      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold font-galey text-[#1F2A2E]">Équipe</h1>
          <p className="text-gray-600 font-galey mt-1">Gérez les employés et les bénévoles de votre association.</p>
        </div>
        <button type="button" onClick={() => setAjout(true)}
          className="inline-flex items-center justify-center gap-2 h-12 px-5 rounded-xl bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-galey font-semibold transition-colors w-full sm:w-auto">
          <Icone nom="plus" taille={18} /> Ajouter un membre
        </button>
      </div>

      {dbError && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-3 text-xs text-red-700 font-galey break-all">{dbError}</div>
      )}

      <div role="tablist" className="flex gap-1 border-b border-gray-200 overflow-x-auto">
        {([['tous', 'Tous'], ['employe', 'Employés'], ['benevole', 'Bénévoles']] as const).map(([v, l]) => (
          <button key={v} type="button" role="tab" aria-selected={role === v} onClick={() => setRole(v)}
            className={`-mb-px px-4 sm:px-6 py-3 font-galey text-[15px] whitespace-nowrap border-b-2 transition-colors ${
              role === v ? 'border-[#0C5C6C] text-[#0C5C6C] font-semibold' : 'border-transparent text-gray-600 hover:text-[#1F2A2E]'}`}>
            {l} ({compte[v]})
          </button>
        ))}
      </div>

      <div className="flex flex-col sm:flex-row gap-3">
        <label className="relative flex-1 sm:max-w-md">
          <span className="sr-only">Rechercher un membre</span>
          <Icone nom="recherche" taille={18} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-gray-400" />
          <input value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Rechercher un membre"
            className={`${inp} h-12 pl-11`} />
        </label>
        <label className="sm:w-56">
          <span className="sr-only">Statut</span>
          <select value={statut} onChange={e => setStatut(e.target.value as FiltreStatut)} className={`${inp} h-12`}>
            <option value="actifs">Actifs</option>
            <option value="inactifs">Inactifs</option>
            <option value="tous">Tous les statuts</option>
          </select>
        </label>
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
      ) : membres.length === 0 ? (
        <div className="bg-white rounded-xl border border-gray-200/80 p-10 text-center font-galey">
          <p className="font-semibold text-[#1F2A2E]">Aucun membre dans votre équipe</p>
          <p className="text-sm text-gray-500 mt-1">Ajoutez un employé ou un bénévole avec « Ajouter un membre ».</p>
        </div>
      ) : liste.length === 0 ? (
        <div className="bg-white rounded-xl border border-gray-200/80 p-10 text-center font-galey">
          <p className="font-semibold text-[#1F2A2E]">Aucun membre ne correspond à votre recherche</p>
          <p className="text-sm text-gray-500 mt-1">Modifiez la recherche ou les filtres.</p>
        </div>
      ) : (
        <div className="space-y-3">{liste.map(renderCard)}</div>
      )}

      {ajout && (
        <AjoutMembreModal uid={uid} profileId={profileId}
          onChercher={type => { setAjout(false); setRecherchePetsMatch(type); }}
          onClose={ajoute => { setAjout(false); if (ajoute) load(); }} />
      )}
      {recherchePetsMatch && (
        <AddPetsMatchModal uid={uid} eleveurProfileId={profileId} type={recherchePetsMatch}
          onClose={() => { setRecherchePetsMatch(null); load(); }} />
      )}
      {editing && <EditMembreModal membre={editing} onClose={() => { setEditing(null); load(); }} />}
      {assigning && assigning.uid_employe && (
        <AssignTaskModal uid={uid} assigneeUid={assigning.uid_employe}
          onClose={() => { setAssigning(null); load(); }} />
      )}
      {congeFor && <CongeModal membre={congeFor} myUid={uid} onClose={() => setCongeFor(null)} />}
    </div>
  );
}

// ── Ajouter un membre : rôle, puis recherche PetsMatch ou saisie manuelle ────
// Miroir appli : _showAddChoiceSheet + AddEmployeManuelSheet (mêmes champs).

function AjoutMembreModal({ uid, profileId, onChercher, onClose }: {
  uid: string; profileId: string | null;
  onChercher: (type: 'employe' | 'benevole') => void;
  onClose: (ajoute: boolean) => void;
}) {
  const [type, setType] = useState<'employe' | 'benevole'>('employe');
  const [manuel, setManuel] = useState(false);
  const [form, setForm] = useState({ prenom: '', nom: '', email: '', telephone: '', notes: '' });
  const [saving, setSaving] = useState(false);

  const ajouter = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.prenom.trim() || !form.nom.trim()) return;
    setSaving(true);
    const { error } = await supabase.from('employes').insert({
      uid_eleveur: uid, prenom: form.prenom.trim(), nom: form.nom.trim(),
      email: form.email.trim() || null, telephone: form.telephone.trim() || null,
      notes: form.notes.trim() || null, actif: true, type, profil_source: 'association',
      ...(profileId ? { eleveur_profile_id: profileId } : {}),
    });
    setSaving(false);
    if (error) { alert(`Erreur : ${error.message}`); return; }
    onClose(true);
  };

  const roles = [['employe', 'Employé', 'personne'], ['benevole', 'Bénévole', 'coeur']] as const;

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center sm:p-4" onClick={() => onClose(false)}>
      <div className="bg-white w-full sm:max-w-md rounded-t-2xl sm:rounded-2xl shadow-xl max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-5 pt-4 pb-3 border-b border-gray-100">
          <h2 className="font-bold font-galey text-[#1F2A2E]">
            {manuel ? (type === 'benevole' ? 'Nouveau bénévole' : 'Nouvel employé') : 'Ajouter un membre'}
          </h2>
          <button onClick={() => onClose(false)} aria-label="Fermer" className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
        </div>

        {!manuel ? (
          <div className="p-5 space-y-4">
            <div className="grid grid-cols-2 gap-3">
              {roles.map(([v, l, ic]) => (
                <button key={v} type="button" onClick={() => setType(v)} aria-pressed={type === v}
                  className={`flex flex-col items-center gap-1.5 py-3 rounded-xl border font-galey font-semibold transition-colors ${
                    type === v ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#E8F4F6]'}`}>
                  <Icone nom={ic} taille={20} /> {l}
                </button>
              ))}
            </div>
            <button type="button" onClick={() => onChercher(type)}
              className="w-full inline-flex items-center justify-center gap-2 h-12 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] font-galey font-semibold hover:bg-[#E8F4F6]">
              <Icone nom="recherche" taille={18} /> Chercher sur PetsMatch
            </button>
            <button type="button" onClick={() => setManuel(true)}
              className="w-full inline-flex items-center justify-center gap-2 h-12 rounded-xl bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-galey font-semibold">
              <Icone nom="crayon" taille={18} /> Ajouter manuellement
            </button>
          </div>
        ) : (
          <form onSubmit={ajouter} className="p-5 space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <input placeholder="Prénom *" required value={form.prenom} onChange={e => setForm({ ...form, prenom: e.target.value })} className={inp} />
              <input placeholder="Nom *" required value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })} className={inp} />
            </div>
            <input placeholder="Email" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inp} />
            <input placeholder="Téléphone" value={form.telephone} onChange={e => setForm({ ...form, telephone: e.target.value })} className={inp} />
            <textarea placeholder="Notes" rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={`${inp} resize-none`} />
            <div className="flex gap-3 pt-1">
              <button type="button" onClick={() => setManuel(false)}
                className="flex-1 h-11 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-galey">Retour</button>
              <button type="submit" disabled={saving}
                className="flex-[1.4] h-11 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white rounded-xl text-sm font-galey font-semibold">
                {saving ? 'Enregistrement…' : 'Ajouter'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

// ── Modifier un membre ────────────────────────────────────────────────────────
// Prénom / nom modifiables pour un membre saisi à la main (ceux d'un compte
// PetsMatch viennent de son profil). Miroir appli : _EditMembreSheet.

function EditMembreModal({ membre, onClose }: { membre: MembreEquipe; onClose: () => void }) {
  const [form, setForm] = useState({
    prenom: membre.prenom, nom: membre.nom,
    email: membre.email ?? '', telephone: membre.telephone ?? '', notes: membre.notes ?? '',
  });
  const [saving, setSaving] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    await supabase.from('employes').update({
      ...(!membre.uid_employe ? { prenom: form.prenom.trim() || null, nom: form.nom.trim() || null } : {}),
      email: form.email.trim() || null,
      telephone: form.telephone.trim() || null,
      notes: form.notes.trim() || null,
    }).eq('id', membre.id);
    setSaving(false);
    onClose();
  }

  const libelle = 'text-xs font-semibold text-gray-500 mb-1 block font-galey';
  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center sm:p-4" onClick={onClose}>
      <div className="bg-white w-full sm:max-w-md rounded-t-2xl sm:rounded-2xl shadow-xl max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-5 pt-4 pb-3 border-b border-gray-100">
          <h2 className="font-bold font-galey text-[#1F2A2E] truncate">Modifier — {nomMembre(membre)}</h2>
          <button onClick={onClose} aria-label="Fermer" className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
        </div>
        <form onSubmit={save} className="p-5 space-y-3">
          {!membre.uid_employe && (
            <div className="grid grid-cols-2 gap-3">
              <div><label className={libelle}>Prénom</label><input value={form.prenom} onChange={e => setForm({ ...form, prenom: e.target.value })} className={inp} /></div>
              <div><label className={libelle}>Nom</label><input value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })} className={inp} /></div>
            </div>
          )}
          <div><label className={libelle}>Email</label><input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inp} /></div>
          <div><label className={libelle}>Téléphone</label><input value={form.telephone} onChange={e => setForm({ ...form, telephone: e.target.value })} className={inp} /></div>
          <div><label className={libelle}>Notes</label><textarea rows={3} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={`${inp} resize-none`} /></div>
          <div className="flex gap-3 pt-1">
            <button type="button" onClick={onClose}
              className="flex-1 h-11 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50 font-galey">Annuler</button>
            <button type="submit" disabled={saving}
              className="flex-[1.4] h-11 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white rounded-xl text-sm font-galey font-semibold">
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Modal : congés d'un membre (employé ou bénévole) ──────────────────────────
// membre.id identifie la RELATION précise (ligne employes) — jamais
// activeProfileId ni un profil "principal" : la même logique que les autres
// écrans congés (EmployesAvancesPage, elevage/employes, mes-employeurs).

interface CongeRow {
  id: string; date_debut: string; date_fin: string;
  statut: 'en_attente' | 'approuve' | 'refuse'; motif: string | null;
}

function fmtDateConge(iso: string) {
  const d = new Date(iso + 'T12:00:00');
  return d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });
}

function CongeModal({ membre, myUid, onClose }: { membre: MembreEquipe; myUid: string; onClose: () => void }) {
  const [conges, setConges] = useState<CongeRow[]>([]);
  const [loadingConges, setLoadingConges] = useState(true);
  const [debut, setDebut] = useState('');
  const [fin, setFin] = useState('');

  const load = useCallback(async () => {
    const { data } = await supabase.from('employe_conges').select('id, date_debut, date_fin, statut, motif')
      .eq('employe_id', membre.id).order('date_debut', { ascending: false });
    setConges((data ?? []) as CongeRow[]);
    setLoadingConges(false);
  }, [membre.id]);

  useEffect(() => { load(); }, [load]);

  const displayName = `${membre.prenom} ${membre.nom}`.trim() || (membre.type === 'benevole' ? 'Bénévole' : 'Employé');

  const notifierEmploye = async (c: CongeRow, approuve: boolean) => {
    if (!membre.uid_employe) return;
    await supabase.from('notifications').insert({
      uid: membre.uid_employe,
      type: 'conge_reponse',
      title: approuve ? 'Congé approuvé' : 'Congé refusé',
      body: approuve
        ? `Votre demande de congé du ${fmtDateConge(c.date_debut)} au ${fmtDateConge(c.date_fin)} a été approuvée.`
        : `Votre demande de congé du ${fmtDateConge(c.date_debut)} au ${fmtDateConge(c.date_fin)} a été refusée.`,
      ...(membre.employe_profile_id ? { profile_id: membre.employe_profile_id } : {}),
      data: { congeId: c.id, approved: approuve },
      read: false,
    });
  };

  const repondre = async (c: CongeRow, approuve: boolean) => {
    await supabase.from('employe_conges').update({ statut: approuve ? 'approuve' : 'refuse' }).eq('id', c.id);
    await notifierEmploye(c, approuve);
    load();
  };

  const ajouter = async () => {
    if (!debut || !fin) return;
    await supabase.from('employe_conges').insert({
      employe_id: membre.id, date_debut: debut, date_fin: fin,
      statut: 'approuve', demande_par_uid: myUid,
    });
    setDebut(''); setFin('');
    load();
  };

  const supprimer = async (id: string) => {
    await supabase.from('employe_conges').delete().eq('id', id);
    load();
  };

  return (
    <div className="fixed inset-0 bg-black/40 flex items-end sm:items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md max-h-[90vh] overflow-y-auto p-5"
        onClick={e => e.stopPropagation()}>
        <h2 className="font-bold font-galey text-lg mb-4">Congés — {displayName}</h2>

        <div className="flex items-center gap-2 mb-4">
          <input type="date" value={debut} onChange={e => setDebut(e.target.value)} className="border rounded-lg px-2 py-1.5 text-xs flex-1" />
          <span className="text-gray-400 text-xs">→</span>
          <input type="date" value={fin} onChange={e => setFin(e.target.value)} className="border rounded-lg px-2 py-1.5 text-xs flex-1" />
          <button onClick={ajouter} className="text-xs px-3 py-1.5 rounded-lg font-semibold text-white bg-[#0C5C6C] hover:bg-[#094F5D]">
            Ajouter
          </button>
        </div>

        {loadingConges ? null : conges.length === 0 ? (
          <p className="text-xs text-gray-400 text-center py-4">Aucun congé enregistré.</p>
        ) : (
          <div className="space-y-2 mb-2">
            {conges.map(c => {
              const style = c.statut === 'en_attente'
                ? { label: 'En attente', bg: 'bg-orange-50', color: 'text-orange-700' }
                : c.statut === 'refuse'
                ? { label: 'Refusé', bg: 'bg-red-50', color: 'text-red-700' }
                : { label: 'Approuvé', bg: 'bg-green-50', color: 'text-green-700' };
              return (
                <div key={c.id} className="border rounded-lg p-2 text-xs">
                  <div className="flex items-center justify-between gap-2">
                    <span>{fmtDateConge(c.date_debut)} → {fmtDateConge(c.date_fin)}</span>
                    <div className="flex items-center gap-2">
                      <span className={`px-2 py-0.5 rounded-full font-semibold ${style.bg} ${style.color}`}>{style.label}</span>
                      <button onClick={() => supprimer(c.id)} className="text-gray-400 hover:text-red-500">×</button>
                    </div>
                  </div>
                  {c.motif && <p className="text-gray-500 mt-1">{c.motif}</p>}
                  {c.statut === 'en_attente' && (
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => repondre(c, false)}
                        className="flex-1 py-1 rounded border border-red-300 text-red-600 font-semibold">Refuser</button>
                      <button onClick={() => repondre(c, true)}
                        className="flex-1 py-1 rounded text-white font-semibold bg-[#0C5C6C]">Approuver</button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        <button onClick={onClose} className="w-full mt-3 py-2.5 rounded-lg border font-semibold text-sm">Fermer</button>
      </div>
    </div>
  );
}

// ── Ligne tâche ───────────────────────────────────────────────────────────────

function TacheRow({ t }: { t: Tache }) {
  const icon = <Icone nom={t.statut === 'en_cours' ? 'renouveler' : t.statut === 'en_retard' ? 'horloge' : 'presse'} taille={14} />;
  return (
    <div className="flex items-start gap-2 bg-white rounded-xl px-3 py-2 shadow-sm">
      <span className="mt-0.5 text-gray-500">{icon}</span>
      <div className="flex-1 min-w-0">
        <p className="text-xs font-semibold text-gray-700 font-galey truncate">{t.label}</p>
        <div className="flex items-center gap-2 mt-0.5">
          {t.date && (
            <span className="text-xs text-gray-400 font-galey">
              {new Date(t.date).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })}
            </span>
          )}
          {t.animal_nom && <span className="text-xs text-[#0C5C6C] font-galey">{t.animal_nom}</span>}
        </div>
      </div>
    </div>
  );
}

// ── Assignation de tâche : même fenêtre « Nouvelle tâche » que l'appli ─────
// (AddTacheSheet, miroir AddTacheModal), personne pré-sélectionnée.

function AssignTaskModal({ uid, assigneeUid, onClose }: {
  uid: string; assigneeUid: string; assigneeName?: string; onClose: () => void;
}) {
  const { user } = useAuth();
  const { id: activeProfileId } = useActiveProfileState();
  const [animaux, setAnimaux] = useState<AnimalOption[] | null>(null);
  const [membres, setMembres] = useState<MembreOption[] | null>(null);

  // Animaux encore pris en charge par CE profil d'association (au refuge ou
  // en famille d'accueil). Un même uid Firebase peut porter plusieurs profils
  // (élevage + association) : possédés en propre (is_association=true) + reçus
  // par cession encore en cours (animaux_proprietes.profile_id_proprio, sans
  // date_fin). Adoptés / transférés / décédés écartés, historique intact.
  // La fenêtre revérifie l'animal à l'enregistrement (adopté entre-temps).
  const chargerAnimauxEligibles = useCallback(async (): Promise<AnimalOption[]> => {
    const { data: ownedData } = await supabase.from('animaux').select('id, nom, espece, portee_id, nom_mere, statut')
      .eq('uid_eleveur', uid).eq('is_association', true).eq('profile_id', activeProfileId).order('nom');
    const owned = ((ownedData ?? []) as (AnimalOption & { statut?: string | null })[]).filter(a => !estHorsPriseEnCharge(a));
    const ownedIds = new Set(owned.map(a => a.id));

    let received: AnimalOption[] = [];
    if (activeProfileId) {
      const { data: byProfile } = await supabase.from('animaux_proprietes')
        .select('animal_id').eq('uid_proprio', uid).eq('profile_id_proprio', activeProfileId).is('date_fin', null);
      const ids = [...new Set((byProfile ?? []).map(r => r.animal_id as string))].filter(id => !ownedIds.has(id));
      if (ids.length > 0) {
        const { data } = await supabase.from('animaux').select('id, nom, espece, portee_id, nom_mere').in('id', ids).order('nom');
        received = (data ?? []) as AnimalOption[];
      }
    }
    return [...owned, ...received];
  }, [uid, activeProfileId]);

  const chargerMembres = useCallback(() => {
    loadMembres(uid, 'association', user?.uid).then(setMembres);
  }, [uid, user?.uid]);

  useEffect(() => {
    chargerAnimauxEligibles().then(setAnimaux);
    chargerMembres();
  }, [chargerAnimauxEligibles, chargerMembres]);

  if (!animaux || !membres) return null;
  return (
    <AddTacheModal
      uid={uid}
      myUid={user?.uid}
      profileId={activeProfileId}
      profilSource="association"
      animaux={animaux}
      membres={membres}
      assigneInitial={assigneeUid}
      onClose={onClose}
      onSaved={onClose}
      onEmployeCreated={chargerMembres}
    />
  );
}

// ── Modal recherche PetsMatch (employé ou bénévole) ───────────────────────────

function AddPetsMatchModal({ uid, eleveurProfileId, type, onClose }: { uid: string; eleveurProfileId: string | null; type: 'employe' | 'benevole'; onClose: () => void }) {
  const [query, setQuery] = useState('');
  const [allUsers, setAllUsers] = useState<UserProfile[]>([]);
  const [results, setResults] = useState<UserProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [adding, setAdding] = useState<string | null>(null);

  useEffect(() => {
    supabase.from('user_profiles_complet')
      .select('uid, firstname, lastname, nom, profile_type, avatar_url, profile_picture_url_pro, phone_number')
      .neq('uid', uid).eq('profile_type', 'particulier').limit(2000)
      .then(({ data }) => {
        setAllUsers((data ?? []).map(p => ({
          uid: p.uid, firstname: p.firstname, lastname: p.lastname,
          name_elevage: p.nom, is_elevage: p.profile_type === 'eleveur',
          profile_picture_url: p.avatar_url, profile_picture_url_elevage: p.profile_picture_url_pro,
          phone_number: p.phone_number,
        })));
        setLoading(false);
      });
  }, [uid]);

  function search(q: string) {
    setQuery(q);
    if (q.trim().length < 2) { setResults([]); return; }
    const lq = q.toLowerCase();
    setResults(allUsers.filter(u =>
      `${u.firstname ?? ''} ${u.lastname ?? ''} ${u.name_elevage ?? ''}`.toLowerCase().includes(lq)
    ).slice(0, 15));
  }

  async function ajouter(u: UserProfile) {
    setAdding(u.uid);
    try {
      // Déjà membre de CETTE association (profil actif), pas d'une autre
      // structure de la même personne.
      let existingQ = supabase.from('employes')
        .select('id, actif').eq('uid_employe', u.uid).eq('profil_source', 'association');
      existingQ = eleveurProfileId ? existingQ.eq('eleveur_profile_id', eleveurProfileId) : existingQ.eq('uid_eleveur', uid);
      const { data: existing } = await existingQ.maybeSingle();
      if (existing) {
        if ((existing as { actif: boolean }).actif) { alert('Cette personne est déjà dans votre équipe.'); setAdding(null); return; }
        await supabase.from('employes').update({ actif: true }).eq('id', (existing as { id: string }).id);
      } else {
        await supabase.from('employes').insert({
          uid_employe: u.uid, uid_eleveur: uid, actif: true,
          profil_source: 'association',
          type: type === 'benevole' ? 'benevole' : null,
          telephone: u.phone_number || null,
          ...(eleveurProfileId ? { eleveur_profile_id: eleveurProfileId } : {}),
        });
      }
      const { data: targetParticulier } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', u.uid).eq('profile_type', 'particulier').maybeSingle();
      await supabase.from('notifications').insert({
        uid: u.uid, type: 'employee_invite',
        title: type === 'benevole' ? 'Invitation bénévole' : 'Invitation à rejoindre une équipe',
        body: type === 'benevole'
          ? 'Vous avez été ajouté comme bénévole dans une association'
          : 'Vous avez été ajouté à l\'équipe d\'une association',
        ...(targetParticulier?.id ? { profile_id: targetParticulier.id } : {}),
        data: { assoUid: uid },
        read: false,
      });
      onClose();
    } finally {
      setAdding(null);
    }
  }

  const nomUser   = (u: UserProfile) => u.is_elevage ? (u.name_elevage?.trim() || 'Élevage') : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || 'Utilisateur';
  const photoUser = (u: UserProfile) => u.is_elevage ? u.profile_picture_url_elevage : u.profile_picture_url;

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={onClose}>
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[85vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold font-galey text-gray-800">
            {type === 'benevole' ? 'Inviter un bénévole' : 'Inviter un employé'}
          </h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
        </div>
        <div className="p-4">
          <input type="text" placeholder="Rechercher par prénom ou nom…" value={query}
            onChange={e => search(e.target.value)} autoFocus
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm font-galey focus:outline-none focus:outline-none focus:border-[#0C5C6C]" />
        </div>
        <div className="flex-1 overflow-y-auto px-4 pb-4 space-y-1">
          {loading ? (
            <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-b-2 border-[#0C5C6C]" /></div>
          ) : query.length < 2 ? (
            <p className="text-sm text-gray-400 font-galey text-center py-4">Tapez au moins 2 lettres pour rechercher</p>
          ) : results.length === 0 ? (
            <p className="text-sm text-gray-400 font-galey text-center py-4">Aucun utilisateur trouvé</p>
          ) : results.map(u => {
            const nom   = nomUser(u);
            const photo = photoUser(u);
            return (
              <button key={u.uid} onClick={() => ajouter(u)} disabled={adding === u.uid}
                className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-[#E8F4F6] transition-colors text-left disabled:opacity-50">
                <div className="w-9 h-9 rounded-full bg-[#E8F4F6] flex items-center justify-center flex-shrink-0 overflow-hidden">
                  {photo
                    ? <Image src={photo} alt={nom} width={36} height={36} className="w-full h-full object-cover" unoptimized />
                    : <span className="text-[#0C5C6C] font-bold text-sm">{nom[0]?.toUpperCase()}</span>}
                </div>
                <div className="flex-1">
                  <p className="font-galey font-semibold text-sm text-gray-800">{nom}</p>
                  {u.phone_number && <p className="text-xs text-gray-400 font-galey">{u.phone_number}</p>}
                </div>
                <span className="text-[#0C5C6C] text-xl">{adding === u.uid ? '…' : '+'}</span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

