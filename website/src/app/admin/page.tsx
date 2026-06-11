'use client';

import { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { collection, getDocs, doc, getDoc, deleteDoc, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ─── Types ────────────────────────────────────────────────────────────────────

interface FireUser {
  uid: string; firstname?: string; lastname?: string; email?: string;
  isAdmin?: boolean; isElevage?: boolean; isPro?: boolean;
  profilePictureUrl?: string; siret?: string; phone_number?: string;
}

interface ProfileEntry {
  uid: string; isSecondary: boolean; profileTableId?: string;
  firstName: string; lastName: string; email: string; photoUrl: string;
  catPro: string; statutPro: string; nameElevage: string; professionPro: string;
  especesAcceptees: string[]; certifications: { nom?: string; organisme?: string }[];
  rayonIntervention?: number; isAdmin?: boolean; isElevage?: boolean;
  isPremium?: boolean; siret?: string;
}

interface Stats {
  utilisateurs: number; animaux: number; annonces: number;
  annoncesActives: number; signalementsEnAttente: number; profilsEnAttente: number;
  particuliers: number; eleveurs: number;
  parEspece: Record<string, number>;
}

interface Signalement {
  id: string; reporter_uid: string;
  target_type: 'user' | 'annonce' | 'profil_pro';
  target_id: string; raison: string; description?: string;
  statut: 'en_attente' | 'traite' | 'rejete';
  admin_note?: string; created_at: string; handled_at?: string; handled_by?: string;
}

interface SignalementAlerte {
  target_type: string; target_id: string;
  nb_signalements: number; premier_signalement: string; dernier_signalement: string;
}

interface DossierEntry {
  uid: string;
  firstname: string; lastname: string; email: string;
  siret: string | null;
  kbisUrl: string | null; acacedDocUrl: string | null; acaced: string | null;
  catPro: string | null; professionPro: string | null;
  certifications: { nom?: string; organisme?: string; numero?: string }[] | null;
  isElevage: boolean; isPro: boolean;
  nameElevage: string | null;
  createdAt: string | null;
  rejectionReason: string | null;
  isSecondary?: boolean; profileTableId?: string;
}

type AdminTab = 'dashboard' | 'signalements' | 'dossiers' | 'utilisateurs';
type FilterType = 'tous' | 'eleveur' | 'particulier' | 'pro' | 'secondaire' | 'admin' | 'en_attente';
type SigFilter = 'en_attente' | 'traite' | 'rejete';

// ─── Constantes ───────────────────────────────────────────────────────────────

const CAT_LABELS: Record<string, string> = {
  sante: 'Santé', veterinaire: 'Vétérinaire', education: 'Éducation',
  garde: 'Pet sitter / Promeneur', pension: 'Pension', toilettage: 'Toilettage',
  photographe: 'Photographe', marechal_ferrant: 'Maréchal-ferrant',
  referencement: 'Commerce / Animalerie', autre: 'Autre',
};

const STATUT_STYLE: Record<string, { label: string; color: string; bg: string }> = {
  actif:      { label: 'Actif',      color: '#16a34a', bg: '#dcfce7' },
  suspendu:   { label: 'Suspendu',   color: '#ea580c', bg: '#ffedd5' },
  refuse:     { label: 'Refusé',     color: '#dc2626', bg: '#fee2e2' },
  en_attente: { label: 'En attente', color: '#2563eb', bg: '#dbeafe' },
};

const RAISON_LABELS: Record<string, string> = {
  contenu_inapproprie: 'Contenu inapproprié',
  spam:               'Spam / Arnaque',
  faux_profil:        'Faux profil',
  maltraitance:       'Maltraitance animale',
  autre:              'Autre',
};

const TARGET_LABELS: Record<string, string> = {
  user: 'Utilisateur', annonce: 'Annonce', profil_pro: 'Profil pro',
};

// ─── Page principale ──────────────────────────────────────────────────────────

export default function AdminPage() {
  const { user, loading: authLoading } = useAuth();
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [tab, setTab] = useState<AdminTab>('dashboard');

  // Dashboard
  const [stats, setStats] = useState<Stats | null>(null);
  const [alertes, setAlertes] = useState<SignalementAlerte[]>([]);

  // Signalements
  const [signalements, setSignalements] = useState<Signalement[]>([]);
  const [sigFilter, setSigFilter] = useState<SigFilter>('en_attente');
  const [sigLoading, setSigLoading] = useState(false);
  const [selectedSig, setSelectedSig] = useState<Signalement | null>(null);
  const [adminNote, setAdminNote] = useState('');
  const [sigSaving, setSigSaving] = useState(false);

  // Dossiers
  const [dossiers, setDossiers] = useState<DossierEntry[]>([]);
  const [refusedDossiers, setRefusedDossiers] = useState<DossierEntry[]>([]);
  const [dossierTab, setDossierTab] = useState<'en_attente' | 'refuse'>('en_attente');
  const [dossiersLoading, setDossiersLoading] = useState(false);
  const [dossierSaving, setDossierSaving] = useState<string | null>(null);
  const [selectedDossier, setSelectedDossier] = useState<DossierEntry | null>(null);
  const [showRefusModal, setShowRefusModal] = useState(false);
  const [refusMotif, setRefusMotif] = useState('');

  // Utilisateurs
  const [entries, setEntries] = useState<ProfileEntry[]>([]);
  const [usersLoading, setUsersLoading] = useState(false);
  const [filter, setFilter] = useState<FilterType>('tous');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<ProfileEntry | null>(null);

  // ── Admin check ──────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!user) { setIsAdmin(false); return; }
    getDoc(doc(db, 'users', user.uid)).then(snap => {
      setIsAdmin(snap.exists() && snap.data()?.isAdmin === true);
    });
  }, [user]);

  // ── Stats (RPC SECURITY DEFINER — bypasse les RLS) ───────────────────────────
  const loadStats = useCallback(async () => {
    const { data: rpc } = await supabase.rpc('get_admin_stats');
    const r = (rpc ?? {}) as Record<string, unknown>;
    setStats({
      utilisateurs:          Number(r['total_profils']               ?? 0),
      animaux:               Number(r['total_animaux']               ?? 0),
      annonces:              Number(r['total_annonces']              ?? 0),
      annoncesActives:       Number(r['annonces_actives']            ?? 0),
      signalementsEnAttente: Number(r['total_signalements_en_attente'] ?? 0),
      profilsEnAttente:      Number(r['profils_en_attente']          ?? 0),
      particuliers:          Number(r['particuliers']                ?? 0),
      eleveurs:              Number(r['eleveurs']                    ?? 0),
      parEspece:             (r['par_espece'] as Record<string, number>) ?? {},
    });

    const { data: alertesData } = await supabase.from('signalements_alertes').select('*');
    setAlertes((alertesData ?? []) as SignalementAlerte[]);
  }, []);

  // ── Signalements ─────────────────────────────────────────────────────────────
  const loadSignalements = useCallback(async (statut: SigFilter) => {
    setSigLoading(true);
    try {
      const { data } = await supabase
        .from('signalements').select('*')
        .eq('statut', statut)
        .order('created_at', { ascending: statut !== 'en_attente' });
      setSignalements((data ?? []) as Signalement[]);
    } finally {
      setSigLoading(false);
    }
  }, []);

  async function handleSigAction(sig: Signalement, newStatut: 'traite' | 'rejete') {
    setSigSaving(true);
    try {
      await supabase.from('signalements').update({
        statut: newStatut,
        admin_note: adminNote.trim() || null,
        handled_at: new Date().toISOString(),
        handled_by: user?.uid,
      }).eq('id', sig.id);
      setSignalements(prev => prev.filter(s => s.id !== sig.id));
      if (stats) setStats(prev => prev ? { ...prev, signalementsEnAttente: Math.max(0, prev.signalementsEnAttente - 1) } : prev);
      setSelectedSig(null);
      setAdminNote('');
      // Rafraîchir les alertes
      const { data } = await supabase.from('signalements_alertes').select('*');
      setAlertes((data ?? []) as SignalementAlerte[]);
    } finally {
      setSigSaving(false);
    }
  }

  // ── Utilisateurs ─────────────────────────────────────────────────────────────
  const loadUsers = useCallback(async () => {
    setUsersLoading(true);
    try {
      const snap = await getDocs(collection(db, 'users'));
      const fireMap: Record<string, FireUser> = {};
      snap.docs.forEach(d => { fireMap[d.id] = { uid: d.id, ...d.data() as object } as FireUser; });

      const { data: primaryRows } = await supabase.from('users').select(
        'uid, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, name_elevage, profession_pro, profile_picture_url_elevage, profile_picture_url, firstname, lastname, email, is_premium, siret'
      );
      const { data: secondaryRows } = await supabase.from('user_profiles').select(
        'id, uid, profile_type, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, name_elevage, profession_pro, avatar_url'
      ).not('profile_type', 'is', null);

      const allEntries: ProfileEntry[] = [];

      snap.docs.forEach(d => {
        const fire = fireMap[d.id];
        const supaRow = (primaryRows ?? []).find(r => r.uid === d.id) ?? {};
        allEntries.push({
          uid: d.id, isSecondary: false,
          firstName: fire.firstname ?? '', lastName: fire.lastname ?? '', email: fire.email ?? '',
          photoUrl: (supaRow as Record<string, string>)['profile_picture_url_elevage'] ?? fire.profilePictureUrl ?? '',
          catPro: (supaRow as Record<string, string>)['cat_pro'] ?? '',
          statutPro: (supaRow as Record<string, string>)['statut_pro'] ?? 'actif',
          nameElevage: (supaRow as Record<string, string>)['name_elevage'] ?? '',
          professionPro: (supaRow as Record<string, string>)['profession_pro'] ?? '',
          especesAcceptees: ((supaRow as Record<string, unknown>)['especes_acceptees'] as string[]) ?? [],
          certifications: ((supaRow as Record<string, unknown>)['certifications'] as { nom?: string; organisme?: string }[]) ?? [],
          rayonIntervention: (supaRow as Record<string, number>)['rayon_intervention'],
          isAdmin: fire.isAdmin, isElevage: fire.isElevage,
          isPremium: (supaRow as Record<string, boolean>)['is_premium'] ?? false,
          siret: (supaRow as Record<string, string>)['siret'] ?? '',
        });
      });

      for (const row of (secondaryRows ?? [])) {
        const fire = fireMap[row.uid] ?? {};
        const existsPrimary = allEntries.some(e => !e.isSecondary && e.uid === row.uid && e.catPro === (row.profile_type ?? row.cat_pro));
        if (existsPrimary) continue;
        allEntries.push({
          uid: row.uid, isSecondary: true, profileTableId: row.id,
          firstName: (fire as FireUser).firstname ?? '', lastName: (fire as FireUser).lastname ?? '',
          email: (fire as FireUser).email ?? '', photoUrl: row.avatar_url ?? (fire as FireUser).profilePictureUrl ?? '',
          catPro: row.profile_type ?? row.cat_pro ?? '', statutPro: row.statut_pro ?? 'en_attente',
          nameElevage: row.name_elevage ?? '', professionPro: row.profession_pro ?? '',
          especesAcceptees: (row.especes_acceptees as string[]) ?? [],
          certifications: (row.certifications as { nom?: string; organisme?: string }[]) ?? [],
          rayonIntervention: row.rayon_intervention,
        });
      }
      allEntries.sort((a, b) => {
        const aW = a.statutPro === 'en_attente' ? 0 : 1;
        const bW = b.statutPro === 'en_attente' ? 0 : 1;
        if (aW !== bW) return aW - bW;
        return `${a.firstName} ${a.lastName}`.localeCompare(`${b.firstName} ${b.lastName}`);
      });
      setEntries(allEntries);
    } finally {
      setUsersLoading(false);
    }
  }, []);

  async function setStatut(entry: ProfileEntry, statut: string) {
    if (entry.isSecondary && entry.profileTableId) {
      await supabase.from('user_profiles').update({ statut_pro: statut }).eq('id', entry.profileTableId);
    } else {
      await supabase.from('users').update({ statut_pro: statut }).eq('uid', entry.uid);
    }
    setEntries(prev => prev.map(e => {
      if (entry.isSecondary ? e.profileTableId === entry.profileTableId : (!e.isSecondary && e.uid === entry.uid))
        return { ...e, statutPro: statut };
      return e;
    }));
    if (selected?.uid === entry.uid && selected?.profileTableId === entry.profileTableId)
      setSelected(prev => prev ? { ...prev, statutPro: statut } : null);
    // Refresh stats via RPC
    const { data: rpc } = await supabase.rpc('get_admin_stats');
    const r = (rpc ?? {}) as Record<string, unknown>;
    setStats(prev => prev ? { ...prev, profilsEnAttente: Number(r['profils_en_attente'] ?? prev.profilsEnAttente) } : prev);
  }

  async function togglePremium(entry: ProfileEntry) {
    const newVal = !entry.isPremium;
    await supabase.from('users').update({ is_premium: newVal }).eq('uid', entry.uid);
    setEntries(prev => prev.map(e => (!e.isSecondary && e.uid === entry.uid) ? { ...e, isPremium: newVal } : e));
    if (selected?.uid === entry.uid) setSelected(prev => prev ? { ...prev, isPremium: newVal } : null);
  }

  async function deleteEntry(entry: ProfileEntry) {
    if (entry.isSecondary && entry.profileTableId) {
      if (!confirm('Supprimer ce profil secondaire ?')) return;
      await supabase.from('user_profiles').delete().eq('id', entry.profileTableId);
      setEntries(prev => prev.filter(e => e.profileTableId !== entry.profileTableId));
      setSelected(null);
    } else {
      if (!confirm('Supprimer ce compte définitivement ?')) return;
      if (prompt('Tapez SUPPRIMER pour confirmer') !== 'SUPPRIMER') return;
      try {
        await supabase.functions.invoke('delete-user', { body: { uid: entry.uid } });
        await deleteDoc(doc(db, 'users', entry.uid));
        setEntries(prev => prev.filter(e => e.uid !== entry.uid));
        setSelected(null);
      } catch (e) { alert(`Erreur : ${e}`); }
    }
  }

  // ── Dossiers ─────────────────────────────────────────────────────────────────
  function mapPrimaryRows(rows: Record<string, unknown>[]): DossierEntry[] {
    return rows.map((r) => ({
      uid:            r['uid'] as string,
      firstname:      (r['firstname'] as string) ?? '',
      lastname:       (r['lastname'] as string) ?? '',
      email:          (r['email'] as string) ?? '',
      siret:          (r['siret'] as string) ?? null,
      kbisUrl:        (r['kbis_url'] as string) ?? null,
      acacedDocUrl:   (r['acaced_doc_url'] as string) ?? null,
      acaced:         (r['acaced'] as string) ?? null,
      catPro:         (r['cat_pro'] as string) ?? null,
      professionPro:  (r['profession_pro'] as string) ?? null,
      certifications: (r['certifications'] as DossierEntry['certifications']) ?? null,
      isElevage:      (r['is_elevage'] as boolean) ?? false,
      isPro:          (r['is_pro'] as boolean) ?? false,
      nameElevage:    (r['name_elevage'] as string) ?? null,
      createdAt:      (r['created_at'] as string) ?? null,
      rejectionReason:(r['rejection_reason'] as string) ?? null,
      isSecondary:    false,
    }));
  }

  function mapSecondaryRows(rows: Record<string, unknown>[], fireMap: Record<string, FireUser>): DossierEntry[] {
    return rows.map((r) => {
      const fire = fireMap[r['uid'] as string] ?? {};
      return {
        uid:            r['uid'] as string,
        profileTableId: r['id'] as string,
        firstname:      (fire as FireUser).firstname ?? '',
        lastname:       (fire as FireUser).lastname ?? '',
        email:          (fire as FireUser).email ?? '',
        siret:          null,
        kbisUrl:        null,
        acacedDocUrl:   null,
        acaced:         null,
        catPro:         (r['cat_pro'] as string) ?? (r['profile_type'] as string) ?? null,
        professionPro:  (r['profession_pro'] as string) ?? null,
        certifications: (r['certifications'] as DossierEntry['certifications']) ?? null,
        isElevage:      r['profile_type'] === 'eleveur',
        isPro:          true,
        nameElevage:    (r['name_elevage'] as string) ?? null,
        createdAt:      (r['created_at'] as string) ?? null,
        rejectionReason:null,
        isSecondary:    true,
      };
    });
  }

  const loadDossiers = useCallback(async () => {
    setDossiersLoading(true);
    try {
      const [
        { data: pendingPrimary },
        { data: pendingSecondary },
        { data: refusedPrimary },
      ] = await Promise.all([
        supabase
          .from('users')
          .select('uid, firstname, lastname, email, siret, kbis_url, acaced_doc_url, acaced, cat_pro, profession_pro, certifications, is_elevage, is_pro, name_elevage, created_at, rejection_reason')
          .eq('statut_pro', 'en_attente')
          .order('created_at', { ascending: true }),
        supabase
          .from('user_profiles')
          .select('id, uid, profile_type, cat_pro, profession_pro, certifications, name_elevage, created_at')
          .eq('statut_pro', 'en_attente')
          .order('created_at', { ascending: true }),
        supabase
          .from('users')
          .select('uid, firstname, lastname, email, siret, kbis_url, acaced_doc_url, acaced, cat_pro, profession_pro, certifications, is_elevage, is_pro, name_elevage, created_at, rejection_reason')
          .eq('statut_pro', 'refuse')
          .order('created_at', { ascending: false }),
      ]);

      const snap = await getDocs(collection(db, 'users'));
      const fireMap: Record<string, FireUser> = {};
      snap.docs.forEach(d => { fireMap[d.id] = { uid: d.id, ...d.data() as object } as FireUser; });

      setDossiers([
        ...mapPrimaryRows((pendingPrimary ?? []) as Record<string, unknown>[]),
        ...mapSecondaryRows((pendingSecondary ?? []) as Record<string, unknown>[], fireMap),
      ]);
      setRefusedDossiers(mapPrimaryRows((refusedPrimary ?? []) as Record<string, unknown>[]));
    } finally {
      setDossiersLoading(false);
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  async function approveDossier(d: DossierEntry) {
    const saveKey = d.isSecondary ? (d.profileTableId ?? d.uid) : d.uid;
    setDossierSaving(saveKey);
    try {
      if (d.isSecondary && d.profileTableId) {
        await supabase.from('user_profiles').update({ statut_pro: 'actif' }).eq('id', d.profileTableId);
      } else {
        await supabase.from('users').update({
          is_validate: true, statut_pro: 'actif', rejection_reason: null,
        }).eq('uid', d.uid);
        await updateDoc(doc(db, 'users', d.uid), { isValidate: true, verificationStatus: 'approved' });
      }
      setDossiers(prev => prev.filter(x =>
        d.isSecondary ? x.profileTableId !== d.profileTableId : (x.isSecondary || x.uid !== d.uid)
      ));
      setStats(prev => prev ? { ...prev, profilsEnAttente: Math.max(0, prev.profilsEnAttente - 1) } : prev);
      setSelectedDossier(null);
    } finally {
      setDossierSaving(null);
    }
  }

  async function refuseDossier(d: DossierEntry, motif: string) {
    const saveKey = d.isSecondary ? (d.profileTableId ?? d.uid) : d.uid;
    setDossierSaving(saveKey);
    try {
      if (d.isSecondary && d.profileTableId) {
        await supabase.from('user_profiles').update({ statut_pro: 'refuse' }).eq('id', d.profileTableId);
      } else {
        await supabase.from('users').update({
          is_validate: false, statut_pro: 'refuse', rejection_reason: motif.trim() || null,
        }).eq('uid', d.uid);
        await updateDoc(doc(db, 'users', d.uid), { isValidate: false, verificationStatus: 'rejected' });
      }
      setDossiers(prev => prev.filter(x =>
        d.isSecondary ? x.profileTableId !== d.profileTableId : (x.isSecondary || x.uid !== d.uid)
      ));
      setStats(prev => prev ? { ...prev, profilsEnAttente: Math.max(0, prev.profilsEnAttente - 1) } : prev);
      setSelectedDossier(null);
      setShowRefusModal(false);
      setRefusMotif('');
    } finally {
      setDossierSaving(null);
    }
  }

  async function reconsiderDossier(d: DossierEntry) {
    const saveKey = d.isSecondary ? (d.profileTableId ?? d.uid) : d.uid;
    setDossierSaving(saveKey);
    try {
      await supabase.from('users').update({
        statut_pro: 'en_attente', rejection_reason: null,
      }).eq('uid', d.uid);
      await updateDoc(doc(db, 'users', d.uid), { verificationStatus: 'pending' });
      setRefusedDossiers(prev => prev.filter(x => x.uid !== d.uid));
      setStats(prev => prev ? { ...prev, profilsEnAttente: prev.profilsEnAttente + 1 } : prev);
      setSelectedDossier(null);
    } finally {
      setDossierSaving(null);
    }
  }

  // ── Chargement par onglet ────────────────────────────────────────────────────
  useEffect(() => {
    if (!isAdmin) return;
    if (tab === 'dashboard') loadStats();
    if (tab === 'signalements') loadSignalements(sigFilter);
    if (tab === 'dossiers' && dossiers.length === 0 && refusedDossiers.length === 0) loadDossiers();
    if (tab === 'utilisateurs' && entries.length === 0) loadUsers();
  }, [isAdmin, tab]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (isAdmin && tab === 'signalements') loadSignalements(sigFilter);
  }, [sigFilter]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Filtres utilisateurs ─────────────────────────────────────────────────────
  const filtered = entries.filter(e => {
    if (filter === 'admin'       && !e.isAdmin) return false;
    if (filter === 'eleveur'     && (!e.isElevage || e.isAdmin || e.isSecondary)) return false;
    if (filter === 'pro'         && (!e.catPro || e.isAdmin || e.isSecondary)) return false;
    if (filter === 'secondaire'  && !e.isSecondary) return false;
    if (filter === 'en_attente'  && e.statutPro !== 'en_attente') return false;
    if (filter === 'particulier' && (e.isElevage || e.catPro || e.isAdmin || e.isSecondary)) return false;
    if (search) {
      const q = search.toLowerCase();
      const name = `${e.firstName} ${e.lastName}`.toLowerCase();
      if (!name.includes(q) && !e.email.toLowerCase().includes(q) && !e.nameElevage.toLowerCase().includes(q)) return false;
    }
    return true;
  });

  // ── Auth guard ───────────────────────────────────────────────────────────────
  if (authLoading || isAdmin === null)
    return <div className="flex items-center justify-center h-screen text-gray-500">Chargement…</div>;
  if (!user || isAdmin === false)
    return (
      <div className="flex flex-col items-center justify-center h-screen gap-4">
        <span className="text-4xl">🔒</span>
        <p className="text-gray-600 font-medium">Accès réservé aux administrateurs.</p>
      </div>
    );

  // ── Render ───────────────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen bg-[#F4F6F8] flex flex-col">

      {/* Header */}
      <header className="bg-[#0C5C6C] text-white px-6 py-3 flex items-center gap-4 shadow-md flex-shrink-0">
        <span className="text-lg font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
          🛡️ Administration PetsMatch
        </span>
        <span className="ml-auto text-sm opacity-70">{user.email}</span>
      </header>

      {/* Tabs */}
      <div className="bg-white border-b border-gray-200 px-6 flex gap-1 flex-shrink-0">
        {([
          { key: 'dashboard',     label: 'Dashboard',     icon: '📊' },
          { key: 'signalements',  label: 'Signalements',  icon: '🚨', badge: stats?.signalementsEnAttente },
          { key: 'dossiers',      label: 'Dossiers',      icon: '📂', badge: stats?.profilsEnAttente },
          { key: 'utilisateurs',  label: 'Utilisateurs',  icon: '👥' },
        ] as { key: AdminTab; label: string; icon: string; badge?: number }[]).map(t => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`relative px-5 py-3 text-sm font-semibold border-b-2 transition-colors flex items-center gap-2 ${
              tab === t.key
                ? 'border-[#0C5C6C] text-[#0C5C6C]'
                : 'border-transparent text-gray-500 hover:text-[#0C5C6C]'
            }`}
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            <span>{t.icon}</span>
            <span>{t.label}</span>
            {!!t.badge && (
              <span className="bg-red-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full leading-none">
                {t.badge}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Contenu */}
      <main className="flex-1 overflow-auto p-6">

        {/* ─── Dashboard ─────────────────────────────────────────────────── */}
        {tab === 'dashboard' && (
          <div className="max-w-5xl mx-auto space-y-6">

            {/* Stats cards */}
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
              {[
                { label: 'Utilisateurs',       value: stats?.utilisateurs,          icon: '👥', color: '#0C5C6C' },
                { label: 'Annonces actives',    value: stats?.annoncesActives,       icon: '📋', color: '#A7C79A' },
                { label: 'Signalements',        value: stats?.signalementsEnAttente, icon: '🚨', color: stats?.signalementsEnAttente ? '#dc2626' : '#6E9E57', alert: !!(stats?.signalementsEnAttente) },
                { label: 'Profils en attente',  value: stats?.profilsEnAttente,      icon: '⏳', color: stats?.profilsEnAttente ? '#ea580c' : '#6E9E57', alert: !!(stats?.profilsEnAttente) },
              ].map(s => (
                <div key={s.label}
                  className={`bg-white rounded-2xl p-4 shadow-sm border ${(s as {alert?:boolean}).alert ? 'border-red-200' : 'border-gray-100'}`}>
                  <div className="text-2xl mb-1">{s.icon}</div>
                  <div className="text-2xl font-bold" style={{ color: s.color, fontFamily: 'Galey, sans-serif' }}>
                    {stats === null ? '…' : (s.value ?? 0)}
                  </div>
                  <div className="text-xs text-gray-500 mt-0.5">{s.label}</div>
                </div>
              ))}
            </div>

            {/* Bloc animaux — total + particuliers/éleveurs + par espèce */}
            <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
              <div className="flex items-center gap-2 mb-4">
                <span className="text-lg">🐾</span>
                <h2 className="font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  Animaux enregistrés
                </h2>
                <button onClick={loadStats} className="ml-auto text-xs text-gray-400 hover:text-[#0C5C6C]">↺ Rafraîchir</button>
              </div>
              <div className="grid grid-cols-3 gap-3 mb-4">
                {[
                  { label: 'Total',        value: stats?.animaux,      color: '#0C5C6C' },
                  { label: 'Particuliers', value: stats?.particuliers,  color: '#2563eb' },
                  { label: 'Éleveurs',     value: stats?.eleveurs,      color: '#ea580c' },
                ].map(s => (
                  <div key={s.label} className="text-center p-3 bg-gray-50 rounded-xl">
                    <div className="text-xl font-bold" style={{ color: s.color, fontFamily: 'Galey, sans-serif' }}>
                      {stats === null ? '…' : (s.value ?? 0)}
                    </div>
                    <div className="text-xs text-gray-500">{s.label}</div>
                  </div>
                ))}
              </div>
              {stats && Object.keys(stats.parEspece).length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {[
                    { key: 'chien',  label: '🐕 Chiens',  color: '#1E88E5' },
                    { key: 'chat',   label: '🐈 Chats',   color: '#8E24AA' },
                    { key: 'equide', label: '🐴 Équidés', color: '#795548' },
                    { key: 'autre',  label: '🐾 Autres',  color: '#6B7280' },
                  ].map(e => (
                    <div key={e.key}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold"
                      style={{ background: `${e.color}18`, color: e.color }}>
                      {e.label} : {stats.parEspece[e.key] ?? 0}
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Alertes signalements */}
            {alertes.length > 0 && (
              <div className="bg-white rounded-2xl shadow-sm border border-red-100 p-5">
                <div className="flex items-center gap-2 mb-4">
                  <span className="text-lg">🚨</span>
                  <h2 className="font-bold text-red-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                    Ressources signalées ≥ 3 fois
                  </h2>
                </div>
                <div className="space-y-2">
                  {alertes.map(a => (
                    <div key={`${a.target_type}-${a.target_id}`}
                      className="flex items-center justify-between bg-red-50 rounded-xl px-4 py-3">
                      <div>
                        <span className="text-sm font-semibold text-red-700">
                          {TARGET_LABELS[a.target_type] ?? a.target_type}
                        </span>
                        <span className="text-xs text-gray-500 ml-2 font-mono">{a.target_id.slice(0, 12)}…</span>
                      </div>
                      <div className="flex items-center gap-3">
                        <span className="bg-red-500 text-white text-xs font-bold px-2 py-0.5 rounded-full">
                          {a.nb_signalements} signalements
                        </span>
                        <button
                          onClick={() => { setTab('signalements'); setSigFilter('en_attente'); }}
                          className="text-xs text-[#0C5C6C] hover:underline font-semibold"
                        >
                          Voir →
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Profils en attente */}
            {(stats?.profilsEnAttente ?? 0) > 0 && (
              <div className="bg-white rounded-2xl shadow-sm border border-orange-100 p-5">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="text-lg">⏳</span>
                    <div>
                      <h2 className="font-bold text-orange-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {stats?.profilsEnAttente} profil(s) en attente de validation
                      </h2>
                      <p className="text-xs text-gray-500">Éleveurs et pros attendant vérification</p>
                    </div>
                  </div>
                  <button
                    onClick={() => { setTab('dossiers'); if (dossiers.length === 0) loadDossiers(); }}
                    className="text-sm font-semibold text-[#0C5C6C] bg-[#0C5C6C10] px-4 py-2 rounded-xl hover:bg-[#0C5C6C20] transition-colors"
                  >
                    Gérer →
                  </button>
                </div>
              </div>
            )}

            {alertes.length === 0 && (stats?.signalementsEnAttente ?? 0) === 0 && (stats?.profilsEnAttente ?? 0) === 0 && stats !== null && (
              <div className="bg-white rounded-2xl shadow-sm border border-green-100 p-6 text-center">
                <div className="text-3xl mb-2">✅</div>
                <p className="font-semibold text-[#6E9E57]" style={{ fontFamily: 'Galey, sans-serif' }}>Tout est en ordre</p>
                <p className="text-sm text-gray-400">Aucun signalement ni profil en attente.</p>
              </div>
            )}
          </div>
        )}

        {/* ─── Signalements (SIG04) ──────────────────────────────────────── */}
        {tab === 'signalements' && (
          <div className="max-w-4xl mx-auto">

            {/* Filtres */}
            <div className="flex gap-2 mb-5">
              {(['en_attente', 'traite', 'rejete'] as SigFilter[]).map(s => (
                <button key={s}
                  onClick={() => setSigFilter(s)}
                  className={`px-4 py-1.5 rounded-full text-sm font-semibold border transition-colors ${
                    sigFilter === s
                      ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                      : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
                  }`}
                  style={{ fontFamily: 'Galey, sans-serif' }}
                >
                  {s === 'en_attente' ? '⏳ En attente' : s === 'traite' ? '✅ Traités' : '❌ Rejetés'}
                  {s === 'en_attente' && stats?.signalementsEnAttente ? (
                    <span className="ml-2 bg-red-500 text-white text-[10px] px-1.5 py-0.5 rounded-full">
                      {stats.signalementsEnAttente}
                    </span>
                  ) : null}
                </button>
              ))}
              <button
                onClick={() => loadSignalements(sigFilter)}
                className="ml-auto px-3 py-1.5 text-sm text-gray-500 border border-gray-200 rounded-full hover:bg-gray-50 bg-white"
                title="Rafraîchir"
              >
                ↺
              </button>
            </div>

            {sigLoading ? (
              <div className="flex justify-center py-16">
                <div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" />
              </div>
            ) : signalements.length === 0 ? (
              <div className="bg-white rounded-2xl p-12 text-center shadow-sm border border-gray-100">
                <div className="text-3xl mb-2">
                  {sigFilter === 'en_attente' ? '🎉' : '📭'}
                </div>
                <p className="text-gray-500">
                  {sigFilter === 'en_attente' ? 'Aucun signalement en attente.' : 'Aucun signalement dans cette catégorie.'}
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                {signalements.map(sig => (
                  <div key={sig.id}
                    onClick={() => { setSelectedSig(sig); setAdminNote(sig.admin_note ?? ''); }}
                    className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100 cursor-pointer hover:shadow-md transition-shadow flex items-start gap-4"
                  >
                    <div className="flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center text-lg"
                      style={{ background: '#fee2e2' }}>
                      {sig.target_type === 'annonce' ? '📋' : sig.target_type === 'user' ? '👤' : '💼'}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-sm font-bold text-[#1F2A2E]">
                          {TARGET_LABELS[sig.target_type] ?? sig.target_type}
                        </span>
                        <span className="text-xs px-2 py-0.5 rounded-full font-semibold"
                          style={{ background: '#fee2e2', color: '#dc2626' }}>
                          {RAISON_LABELS[sig.raison] ?? sig.raison}
                        </span>
                        {sig.target_type === 'annonce' && (
                          <Link href={`/annonces/${sig.target_id}`} target="_blank"
                            onClick={e => e.stopPropagation()}
                            className="text-xs text-[#0C5C6C] hover:underline">
                            Voir l'annonce ↗
                          </Link>
                        )}
                      </div>
                      {sig.description && (
                        <p className="text-xs text-gray-500 mt-1 line-clamp-2">{sig.description}</p>
                      )}
                      <p className="text-xs text-gray-400 mt-1">
                        {new Date(sig.created_at).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
                      </p>
                    </div>
                    {sig.statut === 'en_attente' && (
                      <div className="flex gap-2 flex-shrink-0" onClick={e => e.stopPropagation()}>
                        <button
                          onClick={() => { setSelectedSig(sig); setAdminNote(''); }}
                          className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-[#6E9E57] text-[#6E9E57] hover:bg-[#6E9E5710] transition-colors"
                        >
                          Traiter
                        </button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* ─── Dossiers (VALID04) ────────────────────────────────────────── */}
        {tab === 'dossiers' && (
          <div className="max-w-4xl mx-auto">
            <div className="flex items-center justify-between mb-4">
              <h2 className="font-bold text-[#1F2A2E] text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>
                Dossiers professionnels
              </h2>
              <button onClick={loadDossiers}
                className="text-sm text-gray-400 hover:text-[#0C5C6C] border border-gray-200 bg-white rounded-xl px-3 py-1.5">
                ↺ Rafraîchir
              </button>
            </div>

            {/* Sous-onglets */}
            <div className="flex gap-2 mb-5">
              <button
                onClick={() => setDossierTab('en_attente')}
                className={`px-4 py-1.5 rounded-full text-sm font-semibold border transition-colors ${
                  dossierTab === 'en_attente'
                    ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                    : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
                }`}
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                ⏳ En attente
                {dossiers.length > 0 && (
                  <span className="ml-2 bg-orange-400 text-white text-[10px] px-1.5 py-0.5 rounded-full">{dossiers.length}</span>
                )}
              </button>
              <button
                onClick={() => setDossierTab('refuse')}
                className={`px-4 py-1.5 rounded-full text-sm font-semibold border transition-colors ${
                  dossierTab === 'refuse'
                    ? 'bg-red-600 text-white border-red-600'
                    : 'bg-white text-gray-600 border-gray-200 hover:border-red-400'
                }`}
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                ❌ Rejetés
                {refusedDossiers.length > 0 && (
                  <span className="ml-2 bg-red-500 text-white text-[10px] px-1.5 py-0.5 rounded-full">{refusedDossiers.length}</span>
                )}
              </button>
            </div>

            {dossiersLoading ? (
              <div className="flex justify-center py-16">
                <div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" />
              </div>
            ) : dossierTab === 'en_attente' ? (
              dossiers.length === 0 ? (
                <div className="bg-white rounded-2xl p-12 text-center shadow-sm border border-gray-100">
                  <div className="text-3xl mb-2">🎉</div>
                  <p className="font-semibold text-[#6E9E57]" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun dossier en attente</p>
                  <p className="text-sm text-gray-400 mt-1">Tous les dossiers ont été traités.</p>
                </div>
              ) : (
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                  {dossiers.map(d => (
                    <div key={d.isSecondary ? d.profileTableId : d.uid}
                      onClick={() => setSelectedDossier(d)}
                      className="bg-white rounded-2xl shadow-sm border border-orange-100 p-5 cursor-pointer hover:shadow-md transition-shadow">
                      <div className="flex items-start gap-3 mb-3">
                        <div className="w-10 h-10 rounded-full bg-[#0C5C6C] flex items-center justify-center flex-shrink-0">
                          <span className="text-white text-base">{d.isElevage ? '🌿' : '💼'}</span>
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="font-semibold text-[#1F2A2E] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                            {[d.firstname, d.lastname].filter(Boolean).join(' ') || 'Nom inconnu'}
                          </p>
                          {d.nameElevage && <p className="text-xs text-[#0C5C6C] truncate">{d.nameElevage}</p>}
                          <p className="text-xs text-gray-400 truncate">{d.email}</p>
                        </div>
                      </div>
                      <div className="flex gap-1.5 flex-wrap mb-3">
                        <span className="text-xs px-2 py-0.5 rounded-full font-medium" style={{ background: '#dbeafe', color: '#2563eb' }}>
                          {d.isElevage ? 'Éleveur' : 'Pro'}
                        </span>
                        {d.catPro && (
                          <span className="text-xs px-2 py-0.5 rounded-full font-medium bg-gray-100 text-gray-600">
                            {CAT_LABELS[d.catPro] ?? d.catPro}
                          </span>
                        )}
                        {d.isSecondary && (
                          <span className="text-xs px-2 py-0.5 rounded-full font-medium bg-purple-100 text-purple-600">Secondaire</span>
                        )}
                      </div>
                      {d.siret && <p className="text-xs text-gray-500 font-mono mb-2">SIRET : {d.siret}</p>}
                      {d.acaced && <p className="text-xs text-gray-500 font-mono mb-2">ACACED : {d.acaced}</p>}
                      {d.createdAt && (
                        <p className="text-xs text-gray-400 mb-3">Déposé le {new Date(d.createdAt).toLocaleDateString('fr-FR')}</p>
                      )}
                      <div className="flex gap-2">
                        <button
                          onClick={e => { e.stopPropagation(); approveDossier(d); }}
                          disabled={dossierSaving === (d.isSecondary ? d.profileTableId : d.uid)}
                          className="flex-1 bg-[#6E9E57] hover:bg-[#5A8A45] disabled:opacity-50 text-white text-xs font-semibold py-2 rounded-xl transition-colors"
                          style={{ fontFamily: 'Galey, sans-serif' }}>
                          {dossierSaving === (d.isSecondary ? d.profileTableId : d.uid) ? '…' : '✅ Valider'}
                        </button>
                        <button
                          onClick={e => { e.stopPropagation(); setSelectedDossier(d); setShowRefusModal(true); }}
                          disabled={dossierSaving === (d.isSecondary ? d.profileTableId : d.uid)}
                          className="flex-1 border border-red-200 text-red-600 hover:bg-red-50 disabled:opacity-50 text-xs font-semibold py-2 rounded-xl transition-colors"
                          style={{ fontFamily: 'Galey, sans-serif' }}>
                          ❌ Refuser
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )
            ) : (
              refusedDossiers.length === 0 ? (
                <div className="bg-white rounded-2xl p-12 text-center shadow-sm border border-gray-100">
                  <div className="text-3xl mb-2">📭</div>
                  <p className="font-semibold text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun dossier rejeté</p>
                </div>
              ) : (
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                  {refusedDossiers.map(d => (
                    <div key={d.uid}
                      onClick={() => setSelectedDossier(d)}
                      className="bg-white rounded-2xl shadow-sm border border-red-100 p-5 cursor-pointer hover:shadow-md transition-shadow">
                      <div className="flex items-start gap-3 mb-3">
                        <div className="w-10 h-10 rounded-full bg-red-400 flex items-center justify-center flex-shrink-0">
                          <span className="text-white text-base">{d.isElevage ? '🌿' : '💼'}</span>
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="font-semibold text-[#1F2A2E] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                            {[d.firstname, d.lastname].filter(Boolean).join(' ') || 'Nom inconnu'}
                          </p>
                          {d.nameElevage && <p className="text-xs text-red-400 truncate">{d.nameElevage}</p>}
                          <p className="text-xs text-gray-400 truncate">{d.email}</p>
                        </div>
                      </div>
                      {d.rejectionReason && (
                        <div className="bg-red-50 rounded-xl px-3 py-2 mb-3">
                          <p className="text-xs text-red-500 font-medium mb-0.5">Motif de refus :</p>
                          <p className="text-xs text-red-600 line-clamp-2">{d.rejectionReason}</p>
                        </div>
                      )}
                      {d.createdAt && (
                        <p className="text-xs text-gray-400 mb-3">Déposé le {new Date(d.createdAt).toLocaleDateString('fr-FR')}</p>
                      )}
                      <button
                        onClick={e => { e.stopPropagation(); reconsiderDossier(d); }}
                        disabled={dossierSaving === d.uid}
                        className="w-full border border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#0C5C6C10] disabled:opacity-50 text-xs font-semibold py-2 rounded-xl transition-colors"
                        style={{ fontFamily: 'Galey, sans-serif' }}>
                        {dossierSaving === d.uid ? '…' : '↩ Reconsidérer'}
                      </button>
                    </div>
                  ))}
                </div>
              )
            )}
          </div>
        )}

        {/* ─── Utilisateurs ──────────────────────────────────────────────── */}
        {tab === 'utilisateurs' && (
          <div className="max-w-4xl mx-auto">
            {entries.length === 0 && !usersLoading && (
              <div className="flex justify-center mb-4">
                <button onClick={loadUsers}
                  className="px-5 py-2 bg-[#0C5C6C] text-white rounded-xl text-sm font-semibold hover:bg-[#094F5D]"
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  Charger les utilisateurs
                </button>
              </div>
            )}
            <input
              type="text" placeholder="Rechercher par nom, structure ou email…"
              value={search} onChange={e => setSearch(e.target.value)}
              className="w-full px-4 py-2.5 rounded-2xl border border-gray-200 bg-white shadow-sm mb-4 outline-none focus:border-[#A7C79A] text-sm"
              style={{ fontFamily: 'Galey, sans-serif' }}
            />
            <div className="flex gap-2 flex-wrap mb-4">
              {([
                { key: 'tous',       label: 'Tous' },
                { key: 'en_attente', label: '⏳ En attente' },
                { key: 'secondaire', label: 'Profils secondaires' },
                { key: 'pro',        label: 'Pros' },
                { key: 'eleveur',    label: 'Éleveurs' },
                { key: 'particulier',label: 'Particuliers' },
                { key: 'admin',      label: 'Admins' },
              ] as { key: FilterType; label: string }[]).map(f => (
                <button key={f.key} onClick={() => setFilter(f.key)}
                  className={`px-4 py-1.5 rounded-full text-sm font-semibold border transition-colors ${
                    filter === f.key
                      ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                      : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'
                  }`}
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  {f.label}
                </button>
              ))}
              <span className="ml-auto text-sm text-gray-400 self-center">
                {filtered.length} résultat(s)
              </span>
            </div>

            {usersLoading ? (
              <div className="flex justify-center py-16">
                <div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" />
              </div>
            ) : filtered.length === 0 ? (
              <p className="text-center text-gray-400 py-12" style={{ fontFamily: 'Galey, sans-serif' }}>
                Aucun résultat.
              </p>
            ) : (
              <div className="flex flex-col gap-3">
                {filtered.map((e, i) => (
                  <ProfileCard key={`${e.uid}-${e.profileTableId ?? 'p'}-${i}`} entry={e} onClick={() => setSelected(e)} />
                ))}
              </div>
            )}
          </div>
        )}

      </main>

      {/* ── Modal signalement ─────────────────────────────────────────────── */}
      {selectedSig && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
          onClick={() => setSelectedSig(null)}>
          <div className="bg-white rounded-2xl w-full max-w-lg shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="bg-[#fee2e2] rounded-t-2xl px-6 py-4 flex items-center justify-between">
              <div>
                <p className="font-bold text-red-700" style={{ fontFamily: 'Galey, sans-serif' }}>
                  Signalement — {TARGET_LABELS[selectedSig.target_type]}
                </p>
                <p className="text-xs text-red-500 font-mono mt-0.5">{selectedSig.target_id}</p>
              </div>
              <button onClick={() => setSelectedSig(null)} className="text-gray-500 hover:text-gray-800 text-xl">✕</button>
            </div>
            <div className="p-6 space-y-4">
              <InfoRow label="Raison" value={RAISON_LABELS[selectedSig.raison] ?? selectedSig.raison} />
              {selectedSig.description && <InfoRow label="Description" value={selectedSig.description} />}
              <InfoRow label="Signalé par (uid)" value={selectedSig.reporter_uid} mono />
              <InfoRow label="Date" value={new Date(selectedSig.created_at).toLocaleString('fr-FR')} />
              {selectedSig.target_type === 'annonce' && (
                <Link href={`/annonces/${selectedSig.target_id}`} target="_blank"
                  className="inline-block text-sm text-[#0C5C6C] hover:underline font-semibold">
                  Voir l'annonce ↗
                </Link>
              )}
              {selectedSig.statut === 'en_attente' && (
                <>
                  <div>
                    <label className="text-xs text-gray-400 block mb-1">Note admin (optionnel)</label>
                    <textarea
                      value={adminNote}
                      onChange={e => setAdminNote(e.target.value)}
                      rows={2}
                      placeholder="Raison de la décision…"
                      className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#6E9E57] resize-none"
                    />
                  </div>
                  <div className="flex gap-3 pt-2">
                    <button
                      onClick={() => handleSigAction(selectedSig, 'rejete')}
                      disabled={sigSaving}
                      className="flex-1 border border-gray-200 text-gray-600 text-sm font-semibold py-2.5 rounded-xl hover:bg-gray-50 disabled:opacity-50 transition-colors"
                      style={{ fontFamily: 'Galey, sans-serif' }}>
                      ❌ Rejeter
                    </button>
                    <button
                      onClick={() => handleSigAction(selectedSig, 'traite')}
                      disabled={sigSaving}
                      className="flex-1 bg-[#6E9E57] hover:bg-[#5A8A45] disabled:opacity-50 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors"
                      style={{ fontFamily: 'Galey, sans-serif' }}>
                      {sigSaving ? '…' : '✅ Marquer traité'}
                    </button>
                  </div>
                </>
              )}
              {selectedSig.statut !== 'en_attente' && (
                <div className="bg-gray-50 rounded-xl p-3 text-sm text-gray-600">
                  <p>Traité le {selectedSig.handled_at ? new Date(selectedSig.handled_at).toLocaleDateString('fr-FR') : '—'}</p>
                  {selectedSig.admin_note && <p className="mt-1 italic">"{selectedSig.admin_note}"</p>}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ── Modal dossier détail ─────────────────────────────────────────── */}
      {selectedDossier && !showRefusModal && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
          onClick={() => setSelectedDossier(null)}>
          <div className="bg-white rounded-2xl w-full max-w-lg shadow-2xl max-h-[90vh] overflow-y-auto"
            onClick={e => e.stopPropagation()}>
            <div className="bg-[#A7C79A] rounded-t-2xl px-6 py-4 flex items-center gap-4">
              <div className="w-12 h-12 rounded-full bg-[#0C5C6C] flex items-center justify-center flex-shrink-0">
                <span className="text-white text-xl">{selectedDossier.isElevage ? '🌿' : '💼'}</span>
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {[selectedDossier.firstname, selectedDossier.lastname].filter(Boolean).join(' ') || 'Nom inconnu'}
                </p>
                {selectedDossier.nameElevage && <p className="text-sm text-[#0C5C6C]">{selectedDossier.nameElevage}</p>}
                <p className="text-xs text-gray-600">{selectedDossier.email}</p>
              </div>
              <button onClick={() => setSelectedDossier(null)} className="text-gray-600 hover:text-gray-900 text-xl">✕</button>
            </div>
            <div className="p-6 space-y-4">
              <Section title="Informations">
                <InfoRow label="Rôle" value={selectedDossier.isElevage ? 'Éleveur' : 'Professionnel'} />
                {selectedDossier.siret && <InfoRow label="SIRET/SIREN" value={selectedDossier.siret} mono />}
                {selectedDossier.acaced && <InfoRow label="ACACED" value={selectedDossier.acaced} mono />}
                {selectedDossier.catPro && <InfoRow label="Catégorie" value={CAT_LABELS[selectedDossier.catPro] ?? selectedDossier.catPro} />}
                {selectedDossier.professionPro && <InfoRow label="Profession" value={selectedDossier.professionPro} />}
                {selectedDossier.createdAt && (
                  <InfoRow label="Dossier déposé" value={new Date(selectedDossier.createdAt).toLocaleString('fr-FR')} />
                )}
                {selectedDossier.rejectionReason && (
                  <div className="bg-red-50 border border-red-200 rounded-xl px-3 py-2">
                    <p className="text-xs text-red-500 font-medium mb-1">Motif de refus</p>
                    <p className="text-sm text-red-700">{selectedDossier.rejectionReason}</p>
                  </div>
                )}
              </Section>

              <Section title="Documents">
                {selectedDossier.kbisUrl ? (
                  <a href={selectedDossier.kbisUrl} target="_blank" rel="noopener noreferrer"
                    className="flex items-center gap-2 text-sm text-[#0C5C6C] hover:underline font-semibold">
                    📄 Kbis / Justificatif SIRET ↗
                  </a>
                ) : (
                  <p className="text-sm text-gray-400 italic">Aucun Kbis fourni</p>
                )}
                {selectedDossier.acacedDocUrl && (
                  <a href={selectedDossier.acacedDocUrl} target="_blank" rel="noopener noreferrer"
                    className="flex items-center gap-2 text-sm text-[#0C5C6C] hover:underline font-semibold mt-2">
                    📄 Document ACACED ↗
                  </a>
                )}
                {selectedDossier.certifications && selectedDossier.certifications.length > 0 && (
                  <div className="mt-3">
                    <p className="text-xs text-gray-400 mb-1">Certifications déclarées</p>
                    {selectedDossier.certifications.map((c, i) => (
                      <p key={i} className="text-sm text-gray-700">
                        • {[c.nom, c.organisme, c.numero].filter(Boolean).join(' — ')}
                      </p>
                    ))}
                  </div>
                )}
              </Section>

              {selectedDossier.rejectionReason ? (
                <button
                  onClick={() => reconsiderDossier(selectedDossier)}
                  disabled={dossierSaving === selectedDossier.uid}
                  className="w-full border border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#0C5C6C10] disabled:opacity-50 text-sm font-semibold py-2.5 rounded-xl transition-colors"
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  {dossierSaving === selectedDossier.uid ? '…' : '↩ Reconsidérer le dossier'}
                </button>
              ) : (
                <div className="flex gap-3 pt-2">
                  <button
                    onClick={() => approveDossier(selectedDossier)}
                    disabled={dossierSaving === (selectedDossier.isSecondary ? selectedDossier.profileTableId : selectedDossier.uid)}
                    className="flex-1 bg-[#6E9E57] hover:bg-[#5A8A45] disabled:opacity-50 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors"
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    {dossierSaving === (selectedDossier.isSecondary ? selectedDossier.profileTableId : selectedDossier.uid) ? '…' : '✅ Valider le dossier'}
                  </button>
                  <button
                    onClick={() => setShowRefusModal(true)}
                    disabled={dossierSaving === (selectedDossier.isSecondary ? selectedDossier.profileTableId : selectedDossier.uid)}
                    className="flex-1 border border-red-200 text-red-600 hover:bg-red-50 disabled:opacity-50 text-sm font-semibold py-2.5 rounded-xl transition-colors"
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    ❌ Refuser
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ── Modal refus dossier ───────────────────────────────────────────── */}
      {selectedDossier && showRefusModal && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
          onClick={() => { setShowRefusModal(false); setRefusMotif(''); }}>
          <div className="bg-white rounded-2xl w-full max-w-md shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="bg-red-50 rounded-t-2xl px-6 py-4 flex items-center justify-between">
              <p className="font-bold text-red-700" style={{ fontFamily: 'Galey, sans-serif' }}>
                Refuser le dossier
              </p>
              <button onClick={() => { setShowRefusModal(false); setRefusMotif(''); }}
                className="text-gray-500 hover:text-gray-800 text-xl">✕</button>
            </div>
            <div className="p-6 space-y-4">
              <p className="text-sm text-gray-600">
                Dossier de <strong>{[selectedDossier.firstname, selectedDossier.lastname].filter(Boolean).join(' ')}</strong>
              </p>
              <div>
                <label className="text-xs text-gray-400 block mb-1">Motif de refus *</label>
                <textarea
                  value={refusMotif}
                  onChange={e => setRefusMotif(e.target.value)}
                  rows={3}
                  placeholder="Ex : Documents manquants, SIRET invalide, activité non conforme…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-red-300 resize-none"
                />
              </div>
              <div className="flex gap-3 pt-1">
                <button
                  onClick={() => { setShowRefusModal(false); setRefusMotif(''); }}
                  className="flex-1 border border-gray-200 text-gray-600 text-sm font-semibold py-2.5 rounded-xl hover:bg-gray-50 transition-colors"
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  Annuler
                </button>
                <button
                  onClick={() => refuseDossier(selectedDossier, refusMotif)}
                  disabled={!refusMotif.trim() || dossierSaving === (selectedDossier.isSecondary ? selectedDossier.profileTableId : selectedDossier.uid)}
                  className="flex-1 bg-red-600 hover:bg-red-700 disabled:opacity-50 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors"
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  {dossierSaving === (selectedDossier.isSecondary ? selectedDossier.profileTableId : selectedDossier.uid) ? '…' : 'Confirmer le refus'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Modal utilisateur ────────────────────────────────────────────── */}
      {selected && (
        <ProfileModal
          entry={selected}
          onClose={() => setSelected(null)}
          onSetStatut={s => setStatut(selected, s)}
          onDelete={() => deleteEntry(selected)}
          onTogglePremium={() => togglePremium(selected)}
        />
      )}
    </div>
  );
}

// ─── ProfileCard ──────────────────────────────────────────────────────────────

function ProfileCard({ entry, onClick }: { entry: ProfileEntry; onClick: () => void }) {
  const name = [entry.firstName, entry.lastName].filter(Boolean).join(' ') || 'Nom inconnu';
  const statutStyle = STATUT_STYLE[entry.statutPro] ?? STATUT_STYLE.actif;
  const isPro = !!entry.catPro;
  return (
    <div onClick={onClick}
      className="bg-white rounded-2xl shadow-sm p-4 flex items-center gap-4 cursor-pointer hover:shadow-md transition-shadow border border-gray-100">
      <div className="relative flex-shrink-0">
        <div className="w-12 h-12 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden">
          {entry.photoUrl
            ? <img src={entry.photoUrl} alt={name} className="w-full h-full object-cover" />
            : <span className="text-white text-lg">{entry.isAdmin ? '🛡️' : isPro ? '💼' : entry.isElevage ? '🌿' : '👤'}</span>
          }
        </div>
        {entry.isSecondary && (
          <div className="absolute -bottom-0.5 -right-0.5 w-5 h-5 rounded-full bg-purple-500 border-2 border-white flex items-center justify-center">
            <span className="text-white text-[8px] font-bold">S</span>
          </div>
        )}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold text-gray-800 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{name}</p>
        {entry.nameElevage && <p className="text-xs text-[#0C5C6C] truncate">{entry.nameElevage}</p>}
        <p className="text-xs text-gray-400 truncate">{entry.email}</p>
        <div className="flex gap-1.5 flex-wrap mt-1">
          {entry.isSecondary && <Badge label="Secondaire" color="#7c3aed" />}
          {entry.isAdmin && <Badge label="Admin" color="#7c3aed" />}
          {!entry.isSecondary && entry.isElevage && <Badge label="Éleveur" color="#0C5C6C" />}
          {entry.catPro && <Badge label={CAT_LABELS[entry.catPro] ?? entry.catPro} color="#0C5C6C" />}
          {(isPro || entry.isSecondary) && (
            <span className="text-xs px-2 py-0.5 rounded-full font-medium"
              style={{ background: statutStyle.bg, color: statutStyle.color }}>
              {statutStyle.label}
            </span>
          )}
        </div>
      </div>
      <span className="text-gray-300 text-lg flex-shrink-0">›</span>
    </div>
  );
}

// ─── ProfileModal ─────────────────────────────────────────────────────────────

function ProfileModal({ entry, onClose, onSetStatut, onDelete, onTogglePremium }: {
  entry: ProfileEntry; onClose: () => void;
  onSetStatut: (s: string) => Promise<void>; onDelete: () => Promise<void>;
  onTogglePremium: () => Promise<void>;
}) {
  const [saving, setSaving] = useState(false);
  const [premiumSaving, setPremiumSaving] = useState(false);
  const statut = entry.statutPro ?? 'actif';
  const name = [entry.firstName, entry.lastName].filter(Boolean).join(' ') || 'Nom inconnu';
  const certifs = (entry.certifications ?? []).map(c => [c.nom, c.organisme].filter(Boolean).join(' — ')).filter(Boolean);
  const isPro = !!entry.catPro;
  async function doStatut(s: string) { setSaving(true); try { await onSetStatut(s); } finally { setSaving(false); } }
  async function doPremium() { setPremiumSaving(true); try { await onTogglePremium(); } finally { setPremiumSaving(false); } }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}>
        <div className="bg-[#A7C79A] rounded-t-2xl px-6 py-4 flex items-center gap-4">
          <div className="relative">
            <div className="w-14 h-14 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden">
              {entry.photoUrl
                ? <img src={entry.photoUrl} alt={name} className="w-full h-full object-cover" />
                : <span className="text-white text-2xl">{isPro ? '💼' : entry.isElevage ? '🌿' : '👤'}</span>
              }
            </div>
            {entry.isSecondary && (
              <div className="absolute -bottom-1 -right-1 w-6 h-6 rounded-full bg-purple-500 border-2 border-white flex items-center justify-center">
                <span className="text-white text-[9px] font-bold">S</span>
              </div>
            )}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-lg font-bold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{name}</p>
            {entry.nameElevage && <p className="text-sm text-[#0C5C6C]">{entry.nameElevage}</p>}
            <p className="text-xs text-gray-600">{entry.email}</p>
          </div>
          <button onClick={onClose} className="text-gray-600 hover:text-gray-900 text-xl">✕</button>
        </div>
        <div className="p-6 space-y-5">
          {(isPro || entry.isSecondary || entry.isElevage) && (
            <Section title="Statut professionnel">
              <div className="mb-3 flex items-center gap-2 flex-wrap">
                {(() => { const s = STATUT_STYLE[statut] ?? STATUT_STYLE.actif; return (
                  <span className="text-sm font-bold px-3 py-1 rounded-full" style={{ background: s.bg, color: s.color }}>{s.label}</span>
                ); })()}
                {entry.isPremium && (
                  <span className="text-sm font-bold px-3 py-1 rounded-full" style={{ background: '#fef3c7', color: '#d97706' }}>★ Premium</span>
                )}
                {!entry.isPremium && statut === 'actif' && entry.siret && (
                  <span className="text-sm font-bold px-3 py-1 rounded-full" style={{ background: '#dbeafe', color: '#2563eb' }}>✓ Vérifié</span>
                )}
              </div>
              <div className="flex gap-2 flex-wrap">
                {statut !== 'actif'      && <ActionBtn label="✅ Activer"     color="#16a34a" onClick={() => doStatut('actif')}      disabled={saving} />}
                {statut !== 'suspendu'   && <ActionBtn label="⏸ Suspendre"   color="#ea580c" onClick={() => doStatut('suspendu')}   disabled={saving} />}
                {statut !== 'refuse'     && <ActionBtn label="❌ Refuser"     color="#dc2626" onClick={() => doStatut('refuse')}     disabled={saving} />}
                {statut !== 'en_attente' && <ActionBtn label="⏳ En attente" color="#2563eb" onClick={() => doStatut('en_attente')} disabled={saving} />}
                {!entry.isSecondary && (
                  <ActionBtn
                    label={entry.isPremium ? '★ Retirer Premium' : '★ Passer Premium'}
                    color="#d97706"
                    onClick={doPremium}
                    disabled={premiumSaving}
                  />
                )}
              </div>
            </Section>
          )}
          {isPro && (
            <Section title="Profil professionnel">
              {entry.catPro && <InfoRow label="Catégorie" value={CAT_LABELS[entry.catPro] ?? entry.catPro} />}
              {entry.professionPro && <InfoRow label="Profession" value={entry.professionPro} />}
              {entry.rayonIntervention != null && <InfoRow label="Rayon" value={`${entry.rayonIntervention} km`} />}
              {entry.especesAcceptees.length > 0 && (
                <div>
                  <p className="text-xs text-gray-400 mb-1">Espèces</p>
                  <div className="flex flex-wrap gap-1">{entry.especesAcceptees.map(e => <Badge key={e} label={e} color="#0C5C6C" />)}</div>
                </div>
              )}
              {certifs.length > 0 && (
                <div>
                  <p className="text-xs text-gray-400 mb-1">Certifications</p>
                  {certifs.map((c, i) => <p key={i} className="text-sm text-gray-700">• {c}</p>)}
                </div>
              )}
            </Section>
          )}
          <Section title="Informations du compte">
            <InfoRow label="Email" value={entry.email} />
            <InfoRow label="UID Firebase" value={entry.uid} mono />
            {entry.isSecondary && entry.profileTableId && <InfoRow label="ID profil secondaire" value={entry.profileTableId} mono />}
          </Section>
          {!entry.isSecondary && (
            <Section title="Rôles">
              <div className="flex flex-wrap gap-2">
                {entry.isAdmin && <Badge label="Admin" color="#7c3aed" />}
                {entry.isElevage && <Badge label="Éleveur" color="#0C5C6C" />}
                {isPro && <Badge label="Pro" color="#2563eb" />}
                {!entry.isAdmin && !entry.isElevage && !isPro && <Badge label="Particulier" color="#0891b2" />}
              </div>
            </Section>
          )}
          <button onClick={onDelete}
            className="w-full py-2 rounded-xl border border-red-300 text-red-600 text-sm font-semibold hover:bg-red-50 transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {entry.isSecondary ? 'Supprimer ce profil secondaire' : 'Supprimer le compte'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function Badge({ label, color }: { label: string; color: string }) {
  return <span className="text-xs px-2 py-0.5 rounded-full font-medium" style={{ background: `${color}1a`, color }}>{label}</span>;
}
function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-sm font-semibold text-[#6E9E57] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</p>
      <div className="space-y-2">{children}</div>
    </div>
  );
}
function InfoRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <p className="text-xs text-gray-400">{label}</p>
      <p className={`text-sm text-gray-800 ${mono ? 'font-mono text-xs break-all' : 'font-medium'}`}
        style={{ fontFamily: mono ? undefined : 'Galey, sans-serif' }}>{value}</p>
    </div>
  );
}
function ActionBtn({ label, color, onClick, disabled }: { label: string; color: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="px-4 py-1.5 rounded-xl text-sm font-semibold border transition-colors disabled:opacity-50"
      style={{ borderColor: `${color}66`, color, background: `${color}18`, fontFamily: 'Galey, sans-serif' }}>
      {label}
    </button>
  );
}
