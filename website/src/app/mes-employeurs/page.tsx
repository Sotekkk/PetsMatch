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
  animal_portee?: string;
  source: 'manuel' | 'protocole';
}

interface InventaireItem {
  id: string;
  nom: string;
  categorie: string;
  unite: string;
  quantite: number;
  quantite_alerte: number | null;
  alerte_active: boolean;
}

interface Employer {
  uid: string;
  eleveur_profile_id: string | null;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  cat_pro: string | null;
  profile_picture_url: string | null;
  profile_picture_url_elevage: string | null;
  perms: string[];
  animaux: Animal[];
  taches: Tache[];
  inventaire: InventaireItem[];
}

function formatDate(d: string) {
  const dt = new Date(d);
  return dt.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
}

interface Comment {
  id: string;
  uid_auteur: string;
  contenu: string;
  created_at: string;
  auteur_nom?: string;
}

function TacheDetailModal({ tache, uid, activeProfileId, onClose }: {
  tache: Tache; uid: string; activeProfileId: string | null; onClose: () => void;
}) {
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);

  const loadComments = useCallback(async () => {
    setLoading(true);
    const { data: rows } = await supabase.from('tache_commentaires')
      .select().eq('tache_id', tache.id).order('created_at');
    const authorNames: Record<string, string> = {};
    for (const c of rows ?? []) {
      if (!authorNames[c.uid_auteur]) {
        const { data: u } = await supabase.from('user_profiles')
          .select('firstname, lastname, nom, profile_type')
          .eq('uid', c.uid_auteur).eq('is_main', true).maybeSingle();
        if (u) {
          authorNames[c.uid_auteur] = u.profile_type === 'eleveur'
            ? (u.nom ?? 'Élevage')
            : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
        }
      }
    }
    setComments((rows ?? []).map(c => ({ ...c, auteur_nom: authorNames[c.uid_auteur] ?? 'Utilisateur' })));
    setLoading(false);
  }, [tache.id]);

  useEffect(() => { loadComments(); }, [loadComments]);

  async function addComment() {
    if (!text.trim()) return;
    setSending(true);
    await supabase.from('tache_commentaires').insert({
      tache_id: tache.id,
      uid_auteur: uid,
      ...(activeProfileId ? { auteur_profile_id: activeProfileId } : {}),
      contenu: text.trim(),
    });
    setText('');
    await loadComments();
    setSending(false);
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-end sm:items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md max-h-[85vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="p-5">
          <div className="flex items-center justify-between mb-4">
            <h2 className="font-bold text-lg text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Détail de la tâche
            </h2>
            <button onClick={onClose} className="p-1.5 text-gray-400 hover:text-gray-600 rounded-lg hover:bg-gray-100">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <p className="font-semibold text-[#1F2A2E] mb-2">{tache.titre}</p>
          <div className={`flex flex-wrap gap-2 ${tache.animal_nom ? 'mb-2' : 'mb-5'}`}>
            <span className="text-xs text-gray-400">📅 {formatDate(tache.date)}</span>
            {tache.source === 'protocole' && (
              <span className="text-xs bg-[#F0F9FF] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium">
                protocole
              </span>
            )}
          </div>
          {tache.animal_nom && (
            <Link
              href={`/mes-animaux/${tache.animal_id}`}
              className="flex items-center justify-between bg-[#E8F4F6] hover:bg-[#DCEDF0] rounded-xl px-3 py-2.5 mb-5 transition-colors">
              <div>
                <p className="text-sm font-semibold text-[#0C5C6C]">🐾 {tache.animal_nom}</p>
                {tache.animal_portee && (
                  <p className="text-xs text-[#0C5C6C]/70 mt-0.5">{tache.animal_portee}</p>
                )}
              </div>
              <svg className="w-4 h-4 text-[#0C5C6C]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </Link>
          )}

          <div className="border-t border-gray-100 pt-4">
            <p className="text-xs font-semibold text-gray-400 uppercase mb-3">Commentaires</p>
            {loading ? (
              <div className="flex justify-center py-4">
                <div className="w-5 h-5 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
              </div>
            ) : comments.length === 0 ? (
              <p className="text-sm text-gray-400 mb-4">Aucun commentaire</p>
            ) : (
              <div className="space-y-2.5 mb-4">
                {comments.map(c => (
                  <div key={c.id} className="bg-gray-50 rounded-xl p-3">
                    <p className="text-xs font-semibold text-[#0C5C6C]">{c.auteur_nom}</p>
                    <p className="text-sm text-[#1F2A2E] mt-0.5">{c.contenu}</p>
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input
                value={text}
                onChange={e => setText(e.target.value)}
                placeholder="Ajouter un commentaire…"
                className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]"
                onKeyDown={e => { if (e.key === 'Enter') addComment(); }}
              />
              <button
                onClick={addComment}
                disabled={sending || !text.trim()}
                className="px-4 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold disabled:opacity-50 hover:bg-[#094F5D] transition-colors">
                Envoyer
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default function MesEmployeursPage() {
  const { user, loading: authLoading, activeProfileId } = useAuth();
  const router = useRouter();
  const [employers, setEmployers] = useState<Employer[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Record<string, 'animaux' | 'taches' | 'inventaire'>>({});
  const [selectedTache, setSelectedTache] = useState<Tache | null>(null);

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);

    // Les relations employé sont toujours rattachées au profil particulier de
    // la personne (jamais à un profil pro/éleveur/association actif) : on
    // résout ce profile_id avant d'interroger `employes`.
    const { data: particulierProfile } = await supabase.from('user_profiles')
      .select('id').eq('uid', user.uid).eq('profile_type', 'particulier').maybeSingle();
    const profileId = particulierProfile?.id as string | undefined;

    if (!profileId) { setLoading(false); return; }
    const { data: rows } = await supabase.from('employes')
      .select('uid_eleveur, eleveur_profile_id, type').eq('employe_profile_id', profileId).eq('actif', true);

    if (!rows || rows.length === 0) { setLoading(false); return; }

    // Une entrée par RELATION (uid_eleveur, eleveur_profile_id), pas par
    // uid_eleveur seul : un même employeur peut inviter depuis plusieurs de
    // ses profils (ex: éleveur ET association) — ce sont deux relations
    // distinctes avec leurs propres tâches/animaux/permissions. Les fusionner
    // faisait perdre l'une des deux et affichait un nom choisi arbitrairement.
    // On ne déduplique que les doublons exacts (même uid + même profil), en
    // préférant la ligne non-bénévole.
    type EmpRow = { uid_eleveur: string; eleveur_profile_id: string | null; type: string | null };
    const relMap = new Map<string, EmpRow>();
    for (const r of rows as EmpRow[]) {
      const key = `${r.uid_eleveur}|${r.eleveur_profile_id ?? ''}`;
      const existing = relMap.get(key);
      if (!existing || (r.type !== 'benevole' && existing.type === 'benevole')) relMap.set(key, r);
    }
    const relations = [...relMap.values()];
    if (relations.length === 0) { setLoading(false); return; }

    const uids = [...new Set(relations.map(r => r.uid_eleveur))];
    // Profile IDs non-bénévole uniquement → pour animaux_proprietes/permissions
    const emploiProfileIds = [...new Set(
      relations.filter(r => r.type !== 'benevole').map(r => r.eleveur_profile_id).filter((p): p is string => !!p)
    )];
    const allProfileIds = [...new Set(relations.map(r => r.eleveur_profile_id).filter((p): p is string => !!p))];

    // Charger les permissions granulaires depuis employe_permissions (déjà
    // scopées par eleveur_profile_id, donc déjà correctes par relation).
    const permsMap: Record<string, string[]> = {};
    if (allProfileIds.length > 0) {
      const { data: permsRows } = await supabase.from('employe_permissions')
        .select('eleveur_profile_id, permission')
        .eq('employe_profile_id', profileId)
        .in('eleveur_profile_id', allProfileIds);
      (permsRows ?? []).forEach(r => {
        const eid = r.eleveur_profile_id as string;
        if (!permsMap[eid]) permsMap[eid] = [];
        permsMap[eid].push(r.permission as string);
      });
    }

    // Dates pour plan_taches
    const past = new Date(); past.setDate(past.getDate() - 7);
    const future = new Date(); future.setDate(future.getDate() + 90);
    const pastStr   = past.toISOString().slice(0, 10);
    const futureStr = future.toISOString().slice(0, 10);

    type UserRow = { uid: string; firstname: string | null; lastname: string | null; name_elevage: string | null; is_elevage: boolean; cat_pro: string | null; profile_picture_url: string | null; profile_picture_url_elevage: string | null };
    type AnimalRow = { id: string; nom: string | null; espece: string | null; race: string | null; sexe: string | null; photo_url: string | null; uid_eleveur: string };
    type TacheRow = { id: string; titre: string; date: string; statut: string; animal_id: string | null; uid_eleveur: string; eleveur_profile_id: string | null };
    type PlanRow  = { id: string; label: string | null; date_prevue: string; statut: string; animal_id: string | null; uid_eleveur: string; eleveur_profile_id: string | null };
    type InvRow   = InventaireItem & { eleveur_profile_id: string };

    const [
      { data: users },
      { data: tachesRaw },
      { data: planTachesRaw },
    ] = await Promise.all([
      supabase.from('user_profiles')
        .select('uid, firstname, lastname, nom, profile_type, cat_pro, avatar_url, profile_picture_url_pro')
        .in('uid', uids).eq('is_main', true)
        .then(({ data }) => ({ data: (data ?? []).map(p => ({
          uid: p.uid, firstname: p.firstname, lastname: p.lastname,
          name_elevage: p.nom, is_elevage: p.profile_type === 'eleveur',
          cat_pro: p.cat_pro, profile_picture_url: p.avatar_url,
          profile_picture_url_elevage: p.profile_picture_url_pro,
        })) as UserRow[] })),
      supabase.from('taches_elevage').select('id, titre, date, statut, animal_id, uid_eleveur, eleveur_profile_id').in('uid_eleveur', uids).eq('assigne_profile_id', profileId).neq('statut', 'fait').order('date') as unknown as Promise<{ data: TacheRow[] | null }>,
      supabase.from('plan_taches').select('id, label, date_prevue, statut, animal_id, uid_eleveur, eleveur_profile_id').in('uid_eleveur', uids).eq('assigned_profile_id', profileId).neq('statut', 'fait').gte('date_prevue', pastStr).lte('date_prevue', futureStr).order('date_prevue') as unknown as Promise<{ data: PlanRow[] | null }>,
    ]);

    // Profils user_profiles précis utilisés à l'invitation (peut différer du
    // compte principal — ex : invité depuis un profil pension secondaire).
    type InvitingProfile = { id: string; nom: string | null; avatar_url: string | null };
    let invitingProfileById: Record<string, InvitingProfile> = {};
    if (allProfileIds.length > 0) {
      const { data: invitingProfiles } = await supabase.from('user_profiles')
        .select('id, nom, avatar_url')
        .in('id', allProfileIds) as unknown as { data: InvitingProfile[] | null };
      invitingProfileById = Object.fromEntries((invitingProfiles ?? []).map(p => [p.id, p]));
    }

    // Charger inventaire séparément pour éviter les problèmes de typage Promise.all
    let inventaireRaw: InvRow[] = [];
    if (allProfileIds.length > 0) {
      const { data: invData } = await supabase.from('inventaire_items')
        .select('id, nom, categorie, unite, quantite, quantite_alerte, alerte_active, eleveur_profile_id')
        .in('eleveur_profile_id', allProfileIds)
        .order('categorie').order('nom') as unknown as { data: InvRow[] | null };
      inventaireRaw = invData ?? [];
    }

    // Animaux en accueil via profile_id_proprio — bucketés par profil précis
    // (pas par uid) pour rester scopés à LA relation, pas à toutes celles du
    // même employeur — seulement profils employé (pas bénévole).
    type ApRow = { animal_id: string; profile_id_proprio: string };
    const assocAnimalsByProfileId: Record<string, AnimalRow[]> = {};
    if (emploiProfileIds.length > 0) {
      const { data: apRows } = await supabase.from('animaux_proprietes')
        .select('animal_id, profile_id_proprio')
        .in('profile_id_proprio', emploiProfileIds)
        .is('date_fin', null) as unknown as { data: ApRow[] | null };
      const assocIds = [...new Set((apRows ?? []).map(r => r.animal_id))];
      if (assocIds.length > 0) {
        const { data: assocAnimaux } = await supabase.from('animaux')
          .select('id, nom, espece, race, sexe, photo_url, uid_eleveur')
          .in('id', assocIds)
          .not('statut', 'in', '("sorti","decede")') as unknown as { data: AnimalRow[] | null };
        for (const a of assocAnimaux ?? []) {
          const ap = (apRows ?? []).find(r => r.animal_id === String(a.id));
          const pid = ap?.profile_id_proprio;
          if (pid) {
            if (!assocAnimalsByProfileId[pid]) assocAnimalsByProfileId[pid] = [];
            assocAnimalsByProfileId[pid].push(a);
          }
        }
      }
    }

    // Résoudre les noms d'animaux + nom de la portée (dérivé de nom_mere,
    // même convention que "Mes animaux") pour lever l'ambiguïté quand deux
    // portées différentes contiennent un animal du même nom.
    const animalIds = [
      ...(tachesRaw ?? []).map(t => t.animal_id),
      ...(planTachesRaw ?? []).map(t => t.animal_id),
    ].filter(Boolean) as string[];
    const uniqueIds = [...new Set(animalIds)];
    let animalNames: Record<string, string> = {};
    let animalPortees: Record<string, string> = {};
    if (uniqueIds.length > 0) {
      const { data: anNames } = await supabase.from('animaux').select('id, nom, nom_mere').in('id', uniqueIds);
      animalNames = Object.fromEntries((anNames ?? []).map((a: { id: string; nom: string | null }) => [a.id, a.nom ?? 'Animal']));
      animalPortees = Object.fromEntries(
        (anNames ?? [])
          .filter((a: { id: string; nom_mere: string | null }) => a.nom_mere?.trim())
          .map((a: { id: string; nom_mere: string | null }) => [a.id, `Portée de ${a.nom_mere!.trim()}`])
      );
    }

    const usersByUid = Object.fromEntries((users ?? []).map(u => [u.uid, u]));

    const list: Employer[] = [];
    for (const rel of relations) {
      const u = usersByUid[rel.uid_eleveur];
      if (!u) continue;
      const eleveurProfileId = rel.eleveur_profile_id;

      // Tâches/animaux/inventaire scopés au profil précis de CETTE relation,
      // jamais à tout ce qui porte le même uid_eleveur (un employeur avec
      // plusieurs profils a des données distinctes par profil).
      const manuel: Tache[] = (tachesRaw ?? [])
        .filter(t => t.uid_eleveur === rel.uid_eleveur && t.eleveur_profile_id === eleveurProfileId)
        .map(t => ({
          id: t.id, titre: t.titre, date: t.date, statut: t.statut,
          animal_id: t.animal_id, animal_nom: t.animal_id ? animalNames[t.animal_id] : undefined,
          animal_portee: t.animal_id ? animalPortees[t.animal_id] : undefined,
          source: 'manuel' as const,
        }));

      const protocoles: Tache[] = (planTachesRaw ?? [])
        .filter(t => t.uid_eleveur === rel.uid_eleveur && t.eleveur_profile_id === eleveurProfileId)
        .map(t => ({
          id: t.id, titre: t.label ?? 'Tâche protocole', date: t.date_prevue, statut: t.statut,
          animal_id: t.animal_id, animal_nom: t.animal_id ? animalNames[t.animal_id] : undefined,
          animal_portee: t.animal_id ? animalPortees[t.animal_id] : undefined,
          source: 'protocole' as const,
        }));

      const taches = [...manuel, ...protocoles].sort(
        (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime()
      );

      const perms = eleveurProfileId ? (permsMap[eleveurProfileId] ?? []) : [];
      const inventaire = eleveurProfileId ? inventaireRaw.filter(item => item.eleveur_profile_id === eleveurProfileId) : [];
      const allAnimaux = eleveurProfileId ? (assocAnimalsByProfileId[eleveurProfileId] ?? []) : [];

      // Affiche toujours le profil PRÉCIS qui a invité pour cette relation
      // (éleveur, association...), jamais celui du compte principal — sinon
      // deux relations du même employeur affichent le même nom.
      const invitingProfile = eleveurProfileId ? invitingProfileById[eleveurProfileId] : null;
      const invitingNom = invitingProfile?.nom || '';
      const nameOverride = invitingNom
        ? { name_elevage: invitingNom, is_elevage: true, profile_picture_url_elevage: invitingProfile?.avatar_url || u.profile_picture_url_elevage }
        : {};

      list.push({
        ...u,
        ...nameOverride,
        eleveur_profile_id: eleveurProfileId,
        perms,
        animaux: allAnimaux,
        taches,
        inventaire,
      });
    }

    setEmployers(list);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function marquerFait(tache: Tache, employerUid: string) {
    if (tache.source === 'manuel') {
      await supabase.from('taches_elevage').update({
        statut: 'fait', fait_par: user!.uid, fait_par_profile_id: activeProfileId, fait_a: new Date().toISOString(),
      }).eq('id', tache.id);
    } else {
      await supabase.from('plan_taches').update({
        statut: 'fait', valide_par: user!.uid, valide_par_profile_id: activeProfileId, valide_at: new Date().toISOString(),
      }).eq('id', tache.id);
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

  // Clé par relation (uid + profil), pas par uid seul : un même employeur peut
  // avoir 2 cartes (ex: éleveur + association) qui ne doivent pas partager
  // leur onglet actif.
  function relKey(emp: Employer): string {
    return `${emp.uid}|${emp.eleveur_profile_id ?? ''}`;
  }

  function getTab(emp: Employer): 'animaux' | 'taches' | 'inventaire' {
    return tab[relKey(emp)] ?? 'animaux';
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
            const activeTab = getTab(emp);
            const tachesEnCours = emp.taches.filter(t => t.statut !== 'fait');

            return (
              <div key={relKey(emp)} className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">

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
                  {emp.cat_pro === 'pension' && emp.perms.includes('read_planning_pension') && (
                    <Link href={`/pension/planning?employerUid=${emp.uid}`}
                      className="flex-shrink-0 text-xs font-semibold px-3 py-1.5 rounded-full bg-[#0C5C6C]/10 text-[#0C5C6C] hover:bg-[#0C5C6C]/20 transition-colors">
                      📅 Planning
                    </Link>
                  )}
                </div>

                {/* Onglets */}
                <div className="flex border-b border-gray-100">
                  {([
                    ['animaux',    `🐾 Animaux (${emp.animaux.length})`],
                    ['taches',     `✅ Tâches (${tachesEnCours.length})`],
                    ['inventaire', `🗃️ Inventaire`],
                  ] as const).map(([v, l]) => (
                    <button key={v}
                      onClick={() => setTab(prev => ({ ...prev, [relKey(emp)]: v }))}
                      className={`flex-1 py-2.5 text-xs font-semibold transition-colors ${
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
                            onClick={() => setSelectedTache(t)}
                            className="flex items-start gap-3 bg-gray-50 rounded-xl px-4 py-3 cursor-pointer hover:bg-gray-100 transition-colors">
                            <button
                              onClick={e => { e.stopPropagation(); marquerFait(t, emp.uid); }}
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

                {/* Onglet Inventaire */}
                {activeTab === 'inventaire' && (
                  <div className="p-4">
                    {emp.inventaire.length === 0 ? (
                      <p className="text-center text-sm text-gray-400 py-4">Inventaire vide</p>
                    ) : (
                      <div className="space-y-2">
                        {emp.inventaire.map(item => {
                          const isLow = item.alerte_active && item.quantite_alerte !== null && item.quantite <= item.quantite_alerte;
                          return (
                            <div key={item.id}
                              className={`flex items-center gap-3 rounded-xl px-4 py-3 ${isLow ? 'bg-amber-50 border border-amber-200' : 'bg-gray-50'}`}>
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2">
                                  <p className="font-semibold text-[#1F2A2E] text-sm truncate">{item.nom}</p>
                                  {isLow && <span className="text-[10px] bg-amber-100 text-amber-700 px-1.5 py-0.5 rounded font-medium flex-shrink-0">⚠️ bas</span>}
                                </div>
                                <p className="text-xs text-gray-400 mt-0.5">{item.categorie} · {item.quantite} {item.unite}</p>
                              </div>
                              {emp.perms.includes('write_inventaire') && (
                                <Link href={`/elevage/inventaire`}
                                  className="text-xs text-[#0C5C6C] font-semibold hover:underline flex-shrink-0">
                                  Gérer →
                                </Link>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {selectedTache && (
        <TacheDetailModal
          tache={selectedTache}
          uid={user!.uid}
          activeProfileId={activeProfileId}
          onClose={() => setSelectedTache(null)}
        />
      )}
    </div>
  );
}
