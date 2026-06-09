'use client';

import { useEffect, useState, useCallback } from 'react';
import { collection, getDocs, doc, getDoc, deleteDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ─── Types ────────────────────────────────────────────────────────────────────

interface FireUser {
  uid: string;
  firstname?: string;
  lastname?: string;
  email?: string;
  isAdmin?: boolean;
  isElevage?: boolean;
  isPro?: boolean;
  profilePictureUrl?: string;
  siret?: string;
  phone_number?: string;
}

/** Entrée unifiée : profil primaire ou secondaire */
interface ProfileEntry {
  // Identifiants
  uid: string;                  // Firebase UID (compte parent)
  isSecondary: boolean;
  profileTableId?: string;      // user_profiles.id pour les secondaires

  // Données affichage
  firstName: string;
  lastName: string;
  email: string;
  photoUrl: string;

  // Données pro
  catPro: string;
  statutPro: string;
  nameElevage: string;
  professionPro: string;
  especesAcceptees: string[];
  certifications: { nom?: string; organisme?: string }[];
  rayonIntervention?: number;

  // Rôles (primaires uniquement)
  isAdmin?: boolean;
  isElevage?: boolean;
}

type FilterType = 'tous' | 'eleveur' | 'particulier' | 'pro' | 'secondaire' | 'admin' | 'en_attente';

const CAT_LABELS: Record<string, string> = {
  sante:            'Santé',
  veterinaire:      'Vétérinaire',
  education:        'Éducation',
  garde:            'Pet sitter / Promeneur',
  pension:          'Pension pour animaux',
  toilettage:       'Toilettage',
  photographe:      'Photographe',
  marechal_ferrant: 'Maréchal-ferrant',
  referencement:    'Commerce / Animalerie',
  autre:            'Autre',
};

const STATUT_STYLE: Record<string, { label: string; color: string; bg: string }> = {
  actif:      { label: 'Actif',      color: '#16a34a', bg: '#dcfce7' },
  suspendu:   { label: 'Suspendu',   color: '#ea580c', bg: '#ffedd5' },
  refuse:     { label: 'Refusé',     color: '#dc2626', bg: '#fee2e2' },
  en_attente: { label: 'En attente', color: '#2563eb', bg: '#dbeafe' },
};

// ─── Page principale ──────────────────────────────────────────────────────────

export default function AdminPage() {
  const { user, loading: authLoading } = useAuth();

  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [entries, setEntries] = useState<ProfileEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<FilterType>('tous');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<ProfileEntry | null>(null);

  // Vérification admin
  useEffect(() => {
    if (!user) { setIsAdmin(false); return; }
    getDoc(doc(db, 'users', user.uid)).then(snap => {
      setIsAdmin(snap.exists() && snap.data()?.isAdmin === true);
    });
  }, [user]);

  // Chargement
  const loadAll = useCallback(async () => {
    setLoading(true);
    try {
      // 1. Firestore : tous les utilisateurs (pour nom/email/rôles)
      const snap = await getDocs(collection(db, 'users'));
      const fireMap: Record<string, FireUser> = {};
      snap.docs.forEach(d => { fireMap[d.id] = { uid: d.id, ...d.data() as object } as FireUser; });

      // 2. Supabase users : profils primaires pros + infos email/nom de secours
      const { data: primaryRows } = await supabase
        .from('users')
        .select('uid, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, name_elevage, profession_pro, profile_picture_url_elevage, profile_picture_url, firstname, lastname, email');

      // 3. Supabase user_profiles : profils secondaires
      const { data: secondaryRows } = await supabase
        .from('user_profiles')
        .select('id, uid, profile_type, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, name_elevage, profession_pro, avatar_url')
        .not('profile_type', 'is', null);

      const allEntries: ProfileEntry[] = [];

      // Construire les entrées primaires (depuis Firestore + Supabase users)
      snap.docs.forEach(d => {
        const fire = fireMap[d.id];
        const supaRow = (primaryRows ?? []).find(r => r.uid === d.id) ?? {};
        allEntries.push({
          uid: d.id,
          isSecondary: false,
          firstName: fire.firstname ?? '',
          lastName: fire.lastname ?? '',
          email: fire.email ?? '',
          photoUrl: (supaRow as Record<string, string>)['profile_picture_url_elevage'] ?? fire.profilePictureUrl ?? '',
          catPro: (supaRow as Record<string, string>)['cat_pro'] ?? '',
          statutPro: (supaRow as Record<string, string>)['statut_pro'] ?? 'actif',
          nameElevage: (supaRow as Record<string, string>)['name_elevage'] ?? '',
          professionPro: (supaRow as Record<string, string>)['profession_pro'] ?? '',
          especesAcceptees: ((supaRow as Record<string, unknown>)['especes_acceptees'] as string[]) ?? [],
          certifications: ((supaRow as Record<string, unknown>)['certifications'] as { nom?: string; organisme?: string }[]) ?? [],
          rayonIntervention: (supaRow as Record<string, number>)['rayon_intervention'],
          isAdmin: fire.isAdmin,
          isElevage: fire.isElevage,
        });
      });

      // Construire les entrées secondaires (depuis user_profiles)
      for (const row of (secondaryRows ?? [])) {
        const fire = fireMap[row.uid] ?? {};
        // Éviter les doublons : si un profil secondaire a le même uid+cat_pro qu'un primaire, skip
        const existsPrimary = allEntries.some(e => !e.isSecondary && e.uid === row.uid && e.catPro === (row.profile_type ?? row.cat_pro));
        if (existsPrimary) continue;

        allEntries.push({
          uid: row.uid,
          isSecondary: true,
          profileTableId: row.id,
          firstName: (fire as FireUser).firstname ?? '',
          lastName: (fire as FireUser).lastname ?? '',
          email: (fire as FireUser).email ?? '',
          photoUrl: row.avatar_url ?? (fire as FireUser).profilePictureUrl ?? '',
          catPro: row.profile_type ?? row.cat_pro ?? '',
          statutPro: row.statut_pro ?? 'en_attente',
          nameElevage: row.name_elevage ?? '',
          professionPro: row.profession_pro ?? '',
          especesAcceptees: (row.especes_acceptees as string[]) ?? [],
          certifications: (row.certifications as { nom?: string; organisme?: string }[]) ?? [],
          rayonIntervention: row.rayon_intervention,
        });
      }

      // Tri : en_attente en premier, puis par nom
      allEntries.sort((a, b) => {
        const aW = a.statutPro === 'en_attente' ? 0 : 1;
        const bW = b.statutPro === 'en_attente' ? 0 : 1;
        if (aW !== bW) return aW - bW;
        return `${a.firstName} ${a.lastName}`.localeCompare(`${b.firstName} ${b.lastName}`);
      });

      setEntries(allEntries);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isAdmin) loadAll();
  }, [isAdmin, loadAll]);

  // ── Filtres ────────────────────────────────────────────────────────────────

  const filtered = entries.filter(e => {
    if (filter === 'admin'      && !e.isAdmin) return false;
    if (filter === 'eleveur'    && (!e.isElevage || e.isAdmin || e.isSecondary)) return false;
    if (filter === 'pro'        && ((!e.catPro) || e.isAdmin || e.isSecondary)) return false;
    if (filter === 'secondaire' && !e.isSecondary) return false;
    if (filter === 'en_attente' && e.statutPro !== 'en_attente') return false;
    if (filter === 'particulier' && (e.isElevage || e.catPro || e.isAdmin || e.isSecondary)) return false;
    if (search) {
      const q = search.toLowerCase();
      const name = `${e.firstName} ${e.lastName}`.toLowerCase();
      if (!name.includes(q) && !e.email.toLowerCase().includes(q) && !e.nameElevage.toLowerCase().includes(q)) return false;
    }
    return true;
  });

  // ── Actions ────────────────────────────────────────────────────────────────

  async function setStatut(entry: ProfileEntry, statut: string) {
    if (entry.isSecondary && entry.profileTableId) {
      await supabase.from('user_profiles').update({ statut_pro: statut }).eq('id', entry.profileTableId);
    } else {
      await supabase.from('users').update({ statut_pro: statut }).eq('uid', entry.uid);
    }
    setEntries(prev => prev.map(e => {
      if (entry.isSecondary ? e.profileTableId === entry.profileTableId : (!e.isSecondary && e.uid === entry.uid)) {
        return { ...e, statutPro: statut };
      }
      return e;
    }));
    if (selected?.uid === entry.uid && selected?.profileTableId === entry.profileTableId) {
      setSelected(prev => prev ? { ...prev, statutPro: statut } : null);
    }
  }

  async function deleteEntry(entry: ProfileEntry) {
    if (entry.isSecondary && entry.profileTableId) {
      if (!confirm('Supprimer ce profil secondaire ? Le compte principal ne sera pas affecté.')) return;
      try {
        await supabase.from('user_profiles').delete().eq('id', entry.profileTableId);
        setEntries(prev => prev.filter(e => e.profileTableId !== entry.profileTableId));
        setSelected(null);
      } catch (e) { alert(`Erreur : ${e}`); }
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

  // ── Garde-fous auth ────────────────────────────────────────────────────────

  if (authLoading || isAdmin === null) {
    return <div className="flex items-center justify-center h-screen text-gray-500">Chargement…</div>;
  }
  if (!user || isAdmin === false) {
    return (
      <div className="flex flex-col items-center justify-center h-screen gap-4">
        <span className="text-4xl">🔒</span>
        <p className="text-gray-600 font-medium">Accès réservé aux administrateurs.</p>
      </div>
    );
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  const FILTERS: { key: FilterType; label: string }[] = [
    { key: 'tous',       label: 'Tous' },
    { key: 'en_attente', label: '⏳ En attente' },
    { key: 'secondaire', label: 'Profils secondaires' },
    { key: 'pro',        label: 'Pros (primaire)' },
    { key: 'eleveur',    label: 'Éleveurs' },
    { key: 'particulier',label: 'Particuliers' },
    { key: 'admin',      label: 'Admins' },
  ];

  return (
    <div className="min-h-screen bg-[#F8F8F6]">
      {/* Header */}
      <div className="bg-[#A7C79A] px-6 py-4 flex items-center gap-4">
        <span className="text-xl font-bold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
          Administration PetsMatch
        </span>
        <span className="ml-auto text-sm text-gray-600">{user.email}</span>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-6">
        {/* Search */}
        <input
          type="text"
          placeholder="Rechercher par nom, structure ou email…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="w-full px-4 py-2 rounded-full border border-gray-200 bg-white shadow-sm mb-4 outline-none focus:border-[#A7C79A]"
          style={{ fontFamily: 'Galey, sans-serif' }}
        />

        {/* Filter chips */}
        <div className="flex gap-2 flex-wrap mb-4">
          {FILTERS.map(f => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`px-4 py-1.5 rounded-full text-sm font-medium border transition-colors ${
                filter === f.key
                  ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                  : 'bg-white text-gray-700 border-gray-300 hover:border-[#0C5C6C]'
              }`}
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              {f.label}
            </button>
          ))}
          <span className="ml-auto text-sm text-gray-500 self-center">{filtered.length} résultat(s)</span>
        </div>

        {/* Liste */}
        {loading ? (
          <div className="flex justify-center py-12">
            <div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
          <p className="text-center text-gray-400 py-12" style={{ fontFamily: 'Galey, sans-serif' }}>
            Aucun résultat.
          </p>
        ) : (
          <div className="flex flex-col gap-3">
            {filtered.map((e, i) => (
              <ProfileCard key={`${e.uid}-${e.profileTableId ?? 'primary'}-${i}`} entry={e} onClick={() => setSelected(e)} />
            ))}
          </div>
        )}
      </div>

      {/* Modal détail */}
      {selected && (
        <ProfileModal
          entry={selected}
          onClose={() => setSelected(null)}
          onSetStatut={(statut) => setStatut(selected, statut)}
          onDelete={() => deleteEntry(selected)}
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
    <div
      onClick={onClick}
      className="bg-white rounded-2xl shadow-sm p-4 flex items-center gap-4 cursor-pointer hover:shadow-md transition-shadow"
    >
      {/* Avatar */}
      <div className="relative flex-shrink-0">
        <div className="w-12 h-12 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden">
          {entry.photoUrl ? (
            <img src={entry.photoUrl} alt={name} className="w-full h-full object-cover" />
          ) : (
            <span className="text-white text-lg">
              {entry.isAdmin ? '🛡️' : isPro ? '💼' : entry.isElevage ? '🌿' : '👤'}
            </span>
          )}
        </div>
        {entry.isSecondary && (
          <div className="absolute -bottom-0.5 -right-0.5 w-5 h-5 rounded-full bg-purple-500 border-2 border-white flex items-center justify-center">
            <span className="text-white text-[8px] font-bold">S</span>
          </div>
        )}
      </div>

      {/* Infos */}
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
            <span
              className="text-xs px-2 py-0.5 rounded-full font-medium"
              style={{ background: statutStyle.bg, color: statutStyle.color }}
            >
              {statutStyle.label}
            </span>
          )}
        </div>
      </div>

      <span className="text-gray-300 text-lg">›</span>
    </div>
  );
}

// ─── ProfileModal ─────────────────────────────────────────────────────────────

function ProfileModal({
  entry, onClose, onSetStatut, onDelete,
}: {
  entry: ProfileEntry;
  onClose: () => void;
  onSetStatut: (statut: string) => Promise<void>;
  onDelete: () => Promise<void>;
}) {
  const [saving, setSaving] = useState(false);
  const statut = entry.statutPro ?? 'actif';
  const name = [entry.firstName, entry.lastName].filter(Boolean).join(' ') || 'Nom inconnu';
  const certifs = (entry.certifications ?? []).map(c => [c.nom, c.organisme].filter(Boolean).join(' — ')).filter(Boolean);
  const isPro = !!entry.catPro;

  async function doStatut(s: string) {
    setSaving(true);
    try { await onSetStatut(s); } finally { setSaving(false); }
  }

  return (
    <div
      className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="bg-[#A7C79A] rounded-t-2xl px-6 py-4 flex items-center gap-4">
          <div className="relative">
            <div className="w-14 h-14 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden">
              {entry.photoUrl ? (
                <img src={entry.photoUrl} alt={name} className="w-full h-full object-cover" />
              ) : (
                <span className="text-white text-2xl">{isPro ? '💼' : entry.isElevage ? '🌿' : '👤'}</span>
              )}
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
            {entry.isSecondary && (
              <span className="inline-block mt-1 text-xs px-2 py-0.5 rounded-full bg-purple-100 text-purple-700 font-semibold">
                Profil secondaire
              </span>
            )}
          </div>
          <button onClick={onClose} className="text-gray-600 hover:text-gray-900 text-xl">✕</button>
        </div>

        <div className="p-6 space-y-5">

          {/* Statut + actions */}
          {(isPro || entry.isSecondary) && (
            <Section title="Statut professionnel">
              <div className="mb-3">
                {(() => {
                  const s = STATUT_STYLE[statut] ?? STATUT_STYLE.actif;
                  return (
                    <span className="text-sm font-bold px-3 py-1 rounded-full" style={{ background: s.bg, color: s.color }}>
                      {s.label}
                    </span>
                  );
                })()}
              </div>
              <div className="flex gap-2 flex-wrap">
                {statut !== 'actif' && (
                  <ActionBtn label="Activer" color="#16a34a" onClick={() => doStatut('actif')} disabled={saving} />
                )}
                {statut !== 'suspendu' && (
                  <ActionBtn label="Suspendre" color="#ea580c" onClick={() => doStatut('suspendu')} disabled={saving} />
                )}
                {statut !== 'refuse' && (
                  <ActionBtn label="Refuser" color="#dc2626" onClick={() => doStatut('refuse')} disabled={saving} />
                )}
                {statut !== 'en_attente' && (
                  <ActionBtn label="En attente" color="#2563eb" onClick={() => doStatut('en_attente')} disabled={saving} />
                )}
              </div>
            </Section>
          )}

          {/* Infos pro */}
          {isPro && (
            <Section title="Profil professionnel">
              {entry.catPro && <InfoRow label="Catégorie" value={CAT_LABELS[entry.catPro] ?? entry.catPro} />}
              {entry.professionPro && <InfoRow label="Profession" value={entry.professionPro} />}
              {entry.rayonIntervention != null && <InfoRow label="Rayon" value={`${entry.rayonIntervention} km`} />}
              {entry.especesAcceptees.length > 0 && (
                <div>
                  <p className="text-xs text-gray-400 mb-1">Espèces</p>
                  <div className="flex flex-wrap gap-1">
                    {entry.especesAcceptees.map(e => <Badge key={e} label={e} color="#0C5C6C" />)}
                  </div>
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

          {/* Infos compte */}
          <Section title="Informations du compte">
            <InfoRow label="Email" value={entry.email} />
            <InfoRow label="UID Firebase" value={entry.uid} mono />
            {entry.isSecondary && entry.profileTableId && (
              <InfoRow label="ID profil secondaire" value={entry.profileTableId} mono />
            )}
          </Section>

          {/* Rôles — profil primaire uniquement */}
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

          {/* Supprimer */}
          <button
            onClick={onDelete}
            className="w-full py-2 rounded-xl border border-red-300 text-red-600 text-sm font-semibold hover:bg-red-50 transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            {entry.isSecondary ? 'Supprimer ce profil secondaire' : 'Supprimer le compte'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function Badge({ label, color }: { label: string; color: string }) {
  return (
    <span
      className="text-xs px-2 py-0.5 rounded-full font-medium"
      style={{ background: `${color}1a`, color }}
    >
      {label}
    </span>
  );
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
      <p className={`text-sm text-gray-800 ${mono ? 'font-mono text-xs break-all' : 'font-medium'}`} style={{ fontFamily: mono ? undefined : 'Galey, sans-serif' }}>{value}</p>
    </div>
  );
}

function ActionBtn({ label, color, onClick, disabled }: { label: string; color: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="px-4 py-1.5 rounded-xl text-sm font-semibold border transition-colors disabled:opacity-50"
      style={{ borderColor: `${color}66`, color, background: `${color}18`, fontFamily: 'Galey, sans-serif' }}
    >
      {label}
    </button>
  );
}
