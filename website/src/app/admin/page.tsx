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

interface SupaProData {
  uid: string;
  cat_pro?: string;
  statut_pro?: string;
  rayon_intervention?: number;
  especes_acceptees?: string[];
  certifications?: { nom?: string; organisme?: string }[];
  name_elevage?: string;
  profession_pro?: string;
}

type FilterType = 'tous' | 'eleveur' | 'particulier' | 'pro' | 'admin';

const CAT_LABELS: Record<string, string> = {
  sante: 'Santé',
  veterinaire: 'Vétérinaire',
  education: 'Éducation',
  garde: 'Pension / Garde',
  referencement: 'Référencement',
  autre: 'Autre',
};

const STATUT_STYLE: Record<string, { label: string; color: string; bg: string }> = {
  actif:      { label: 'Actif',       color: '#16a34a', bg: '#dcfce7' },
  suspendu:   { label: 'Suspendu',    color: '#ea580c', bg: '#ffedd5' },
  refuse:     { label: 'Refusé',      color: '#dc2626', bg: '#fee2e2' },
  en_attente: { label: 'En attente',  color: '#2563eb', bg: '#dbeafe' },
};

// ─── Page principale ──────────────────────────────────────────────────────────

export default function AdminPage() {
  const { user, loading: authLoading } = useAuth();

  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [users, setUsers] = useState<FireUser[]>([]);
  const [supaMap, setSupaMap] = useState<Record<string, SupaProData>>({});
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<FilterType>('tous');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<{ fire: FireUser; supa: SupaProData } | null>(null);

  // Vérification admin
  useEffect(() => {
    if (!user) { setIsAdmin(false); return; }
    getDoc(doc(db, 'users', user.uid)).then(snap => {
      setIsAdmin(snap.exists() && snap.data()?.isAdmin === true);
    });
  }, [user]);

  // Chargement utilisateurs
  const loadUsers = useCallback(async () => {
    setLoading(true);
    try {
      const snap = await getDocs(collection(db, 'users'));
      const list: FireUser[] = snap.docs.map(d => ({ uid: d.id, ...d.data() as object } as FireUser));
      setUsers(list);

      // Données Supabase pros
      const { data } = await supabase
        .from('users')
        .select('uid, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, name_elevage, profession_pro');
      const map: Record<string, SupaProData> = {};
      for (const row of (data ?? [])) {
        if (row.uid) map[row.uid] = row as SupaProData;
      }
      setSupaMap(map);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isAdmin) loadUsers();
  }, [isAdmin, loadUsers]);

  // ── Filtres ────────────────────────────────────────────────────────────────

  const filtered = users.filter(u => {
    if (filter === 'admin'      && !u.isAdmin) return false;
    if (filter === 'eleveur'    && (!u.isElevage || u.isAdmin)) return false;
    if (filter === 'pro'        && (!u.isPro || u.isAdmin)) return false;
    if (filter === 'particulier' && (u.isElevage || u.isPro || u.isAdmin)) return false;
    if (search) {
      const q = search.toLowerCase();
      const name = `${u.firstname ?? ''} ${u.lastname ?? ''}`.toLowerCase();
      if (!name.includes(q) && !(u.email ?? '').toLowerCase().includes(q)) return false;
    }
    return true;
  });

  // ── Actions ────────────────────────────────────────────────────────────────

  async function setStatutPro(uid: string, statut: string) {
    await supabase.from('users').update({ statut_pro: statut }).eq('uid', uid);
    setSupaMap(prev => ({ ...prev, [uid]: { ...prev[uid], statut_pro: statut } }));
    if (selected?.fire.uid === uid) {
      setSelected(prev => prev ? { ...prev, supa: { ...prev.supa, statut_pro: statut } } : null);
    }
  }

  async function deleteUser(uid: string) {
    if (!confirm('Supprimer ce profil définitivement ?')) return;
    if (prompt('Tapez SUPPRIMER pour confirmer') !== 'SUPPRIMER') return;
    try {
      await supabase.functions.invoke('delete-user', { body: { uid } });
      await deleteDoc(doc(db, 'users', uid));
      setUsers(prev => prev.filter(u => u.uid !== uid));
      setSelected(null);
    } catch (e) {
      alert(`Erreur : ${e}`);
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
    { key: 'tous', label: 'Tous' },
    { key: 'eleveur', label: 'Éleveurs' },
    { key: 'particulier', label: 'Particuliers' },
    { key: 'pro', label: 'Pros' },
    { key: 'admin', label: 'Admins' },
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
          placeholder="Rechercher par nom ou email…"
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
            {filtered.map(u => {
              const supa = supaMap[u.uid] ?? {};
              const name = [u.firstname, u.lastname].filter(Boolean).join(' ') || 'Nom inconnu';
              const statut = supa.statut_pro ?? 'actif';
              const statutStyle = STATUT_STYLE[statut] ?? STATUT_STYLE.actif;
              return (
                <div
                  key={u.uid}
                  onClick={() => setSelected({ fire: u, supa })}
                  className="bg-white rounded-2xl shadow-sm p-4 flex items-center gap-4 cursor-pointer hover:shadow-md transition-shadow"
                >
                  {/* Avatar */}
                  <div className="w-12 h-12 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden flex-shrink-0">
                    {u.profilePictureUrl ? (
                      <img src={u.profilePictureUrl} alt={name} className="w-full h-full object-cover" />
                    ) : (
                      <span className="text-white text-lg">
                        {u.isAdmin ? '🛡️' : u.isPro ? '💼' : u.isElevage ? '🌿' : '👤'}
                      </span>
                    )}
                  </div>

                  {/* Infos */}
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-gray-800 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{name}</p>
                    {supa.name_elevage && <p className="text-xs text-[#0C5C6C] truncate">{supa.name_elevage}</p>}
                    <p className="text-xs text-gray-400 truncate">{u.email}</p>
                    <div className="flex gap-1.5 flex-wrap mt-1">
                      {u.isAdmin && <Badge label="Admin" color="#7c3aed" />}
                      {u.isElevage && <Badge label="Éleveur" color="#0C5C6C" />}
                      {u.isPro && <Badge label="Pro" color="#2563eb" />}
                      {!u.isAdmin && !u.isElevage && !u.isPro && <Badge label="Particulier" color="#0891b2" />}
                      {u.isPro && supa.cat_pro && <Badge label={CAT_LABELS[supa.cat_pro] ?? supa.cat_pro} color="#0C5C6C" />}
                      {u.isPro && <span className="text-xs px-2 py-0.5 rounded-full font-medium" style={{ background: statutStyle.bg, color: statutStyle.color }}>{statutStyle.label}</span>}
                    </div>
                  </div>

                  <span className="text-gray-300 text-lg">›</span>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Modal détail */}
      {selected && (
        <UserModal
          fire={selected.fire}
          supa={selected.supa}
          onClose={() => setSelected(null)}
          onSetStatut={setStatutPro}
          onDelete={deleteUser}
        />
      )}
    </div>
  );
}

// ─── Badge ────────────────────────────────────────────────────────────────────

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

// ─── Modal utilisateur ────────────────────────────────────────────────────────

function UserModal({
  fire, supa, onClose, onSetStatut, onDelete,
}: {
  fire: FireUser;
  supa: SupaProData;
  onClose: () => void;
  onSetStatut: (uid: string, statut: string) => Promise<void>;
  onDelete: (uid: string) => Promise<void>;
}) {
  const [saving, setSaving] = useState(false);
  const statut = supa.statut_pro ?? 'actif';
  const name = [fire.firstname, fire.lastname].filter(Boolean).join(' ') || 'Nom inconnu';
  const certifs = (supa.certifications ?? []).map(c => [c.nom, c.organisme].filter(Boolean).join(' — ')).filter(Boolean);

  async function doStatut(s: string) {
    setSaving(true);
    try { await onSetStatut(fire.uid, s); } finally { setSaving(false); }
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
          <div className="w-14 h-14 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden">
            {fire.profilePictureUrl ? (
              <img src={fire.profilePictureUrl} alt={name} className="w-full h-full object-cover" />
            ) : (
              <span className="text-white text-2xl">{fire.isPro ? '💼' : fire.isElevage ? '🌿' : '👤'}</span>
            )}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-lg font-bold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{name}</p>
            {supa.name_elevage && <p className="text-sm text-[#0C5C6C]">{supa.name_elevage}</p>}
            <p className="text-xs text-gray-600">{fire.email}</p>
          </div>
          <button onClick={onClose} className="text-gray-600 hover:text-gray-900 text-xl">✕</button>
        </div>

        <div className="p-6 space-y-5">
          {/* Statut pro + actions */}
          {fire.isPro && (
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
              </div>
            </Section>
          )}

          {/* Infos pro */}
          {fire.isPro && (
            <Section title="Profil pro">
              {supa.cat_pro && <InfoRow label="Catégorie" value={CAT_LABELS[supa.cat_pro] ?? supa.cat_pro} />}
              {supa.profession_pro && <InfoRow label="Profession" value={supa.profession_pro} />}
              {supa.rayon_intervention != null && <InfoRow label="Rayon" value={`${supa.rayon_intervention} km`} />}
              {(supa.especes_acceptees ?? []).length > 0 && (
                <div>
                  <p className="text-xs text-gray-400 mb-1">Espèces acceptées</p>
                  <div className="flex flex-wrap gap-1">
                    {(supa.especes_acceptees ?? []).map(e => <Badge key={e} label={e} color="#0C5C6C" />)}
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

          {/* Infos personnelles */}
          <Section title="Informations personnelles">
            {fire.phone_number && <InfoRow label="Téléphone" value={fire.phone_number} />}
            {fire.siret && <InfoRow label="SIRET" value={fire.siret} />}
            <InfoRow label="UID" value={fire.uid} mono />
          </Section>

          {/* Rôles */}
          <Section title="Rôles">
            <div className="flex flex-wrap gap-2">
              {fire.isAdmin && <Badge label="Admin" color="#7c3aed" />}
              {fire.isElevage && <Badge label="Éleveur" color="#0C5C6C" />}
              {fire.isPro && <Badge label="Pro" color="#2563eb" />}
              {!fire.isAdmin && !fire.isElevage && !fire.isPro && <Badge label="Particulier" color="#0891b2" />}
            </div>
          </Section>

          {/* Supprimer */}
          <button
            onClick={() => onDelete(fire.uid)}
            className="w-full py-2 rounded-xl border border-red-300 text-red-600 text-sm font-semibold hover:bg-red-50 transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            Supprimer ce profil
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

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
