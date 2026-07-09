'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// ── Types ──────────────────────────────────────────────────────────────────────

type Categorie = 'alimentation' | 'litiere' | 'medicament' | 'accessoire' | 'hygiene' | 'autre';
type Unite     = 'kg' | 'g' | 'L' | 'mL' | 'sac' | 'paquet' | 'boite' | 'unité';
type MvtType   = 'consommation' | 'restock' | 'correction';

interface Item {
  id: string;
  nom: string;
  categorie: Categorie;
  unite: Unite;
  quantite: number;
  quantite_alerte: number | null;
  alerte_active: boolean;
  notes: string | null;
}

interface Mouvement {
  id: string;
  item_id: string;
  uid_auteur: string;
  type: MvtType;
  quantite: number;
  note: string | null;
  created_at: string;
  auteur_nom?: string;
}

// ── Constantes ────────────────────────────────────────────────────────────────

const CATEGORIES: { value: Categorie; label: string; emoji: string; color: string }[] = [
  { value: 'alimentation', label: 'Alimentation',  emoji: '🍖', color: '#6E9E57' },
  { value: 'litiere',      label: 'Litière',        emoji: '🪣', color: '#8B6914' },
  { value: 'medicament',   label: 'Médicaments',    emoji: '💊', color: '#E53E3E' },
  { value: 'accessoire',   label: 'Accessoires',    emoji: '🎾', color: '#0C5C6C' },
  { value: 'hygiene',      label: 'Hygiène',        emoji: '🧴', color: '#8E24AA' },
  { value: 'autre',        label: 'Autre',          emoji: '📦', color: '#718096' },
];

const UNITES: Unite[] = ['kg', 'g', 'L', 'mL', 'sac', 'paquet', 'boite', 'unité'];

const CAT_MAP = Object.fromEntries(CATEGORIES.map(c => [c.value, c]));

function catInfo(c: string) { return CAT_MAP[c] ?? CAT_MAP['autre']; }

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

function pluralUnite(unite: string, qty: number): string {
  if (qty <= 1) return unite;
  const invariable = new Set(['kg', 'g', 'L', 'l', 'mL', 'ml', 'cl', 'dl', '%']);
  if (invariable.has(unite)) return unite;
  if (unite.endsWith('s') || unite.endsWith('x')) return unite;
  return unite + 's';
}

// ── Page principale ───────────────────────────────────────────────────────────

export default function InventairePage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const profileId = useActiveProfile();

  const [items,      setItems]      = useState<Item[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [catFilter,  setCatFilter]  = useState<Categorie | 'tous'>('tous');
  const [showForm,   setShowForm]   = useState(false);
  const [editItem,   setEditItem]   = useState<Item | null>(null);
  const [detailItem, setDetailItem] = useState<Item | null>(null);
  const [mouvements, setMouvements] = useState<Mouvement[]>([]);
  const [mvtLoading, setMvtLoading] = useState(false);
  const [taskToast,  setTaskToast]  = useState<string | null>(null);

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  const loadItems = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const pid = profileId || null;
    let q = supabase.from('inventaire_items').select('*').order('categorie').order('nom');
    if (pid) {
      q = q.eq('eleveur_profile_id', pid) as typeof q;
    } else {
      q = q.eq('uid_eleveur', user.uid) as typeof q;
    }
    const { data } = await q;
    setItems((data ?? []) as Item[]);
    setLoading(false);
  }, [user, profileId]);

  useEffect(() => { loadItems(); }, [loadItems]);

  async function loadMouvements(itemId: string) {
    setMvtLoading(true);
    const { data } = await supabase
      .from('inventaire_mouvements')
      .select('*')
      .eq('item_id', itemId)
      .order('created_at', { ascending: false })
      .limit(30);
    const rows = (data ?? []) as Mouvement[];
    // Résoudre les noms des auteurs
    const uids = [...new Set(rows.map(r => r.uid_auteur))];
    if (uids.length) {
      const { data: users } = await supabase
        .from('user_profiles')
        .select('uid, firstname, lastname, nom, profile_type')
        .in('uid', uids).eq('is_main', true);
      const map: Record<string, string> = {};
      (users ?? []).forEach(u => {
        map[u.uid] = u.profile_type === 'eleveur'
          ? (u.nom ?? 'Élevage')
          : `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
      });
      rows.forEach(r => { r.auteur_nom = map[r.uid_auteur] ?? 'Inconnu'; });
    }
    setMouvements(rows);
    setMvtLoading(false);
  }

  async function createCommandeTask(nom: string, uid: string, pid: string | null) {
    const label = `Commander : ${nom}`;
    const today = new Date().toISOString().split('T')[0];
    const { data: existing } = await supabase
      .from('plan_taches')
      .select('id')
      .eq('uid_eleveur', uid)
      .eq('label', label)
      .eq('statut', 'en_attente')
      .maybeSingle();
    if (existing) return;
    await supabase.from('plan_taches').insert({
      uid_eleveur: uid,
      ...(pid ? { eleveur_profile_id: pid } : {}),
      label,
      type_acte: 'commande',
      date_prevue: today,
      statut: 'en_attente',
      jour_traitement: 1,
      total_jours: 1,
    });
    setTaskToast(nom);
    setTimeout(() => setTaskToast(null), 4000);
  }

  async function openDetail(item: Item) {
    setDetailItem(item);
    await loadMouvements(item.id);
  }

  async function logMouvement(item: Item, type: MvtType, qte: number, note: string) {
    if (!user) return;
    const delta = type === 'consommation' ? -qte : qte;
    const newQte = Math.max(0, item.quantite + delta);

    const pid = profileId || null;
    await supabase.from('inventaire_mouvements').insert({
      item_id: item.id, uid_eleveur: user.uid, uid_auteur: user.uid,
      ...(pid ? { eleveur_profile_id: pid, auteur_profile_id: pid } : {}),
      type, quantite: qte, note: note || null,
    });
    await supabase.from('inventaire_items')
      .update({ quantite: newQte, updated_at: new Date().toISOString() })
      .eq('id', item.id);

    // Notification + tâche de commande si seuil atteint
    if (type === 'consommation' && item.alerte_active && item.quantite_alerte !== null
        && newQte <= item.quantite_alerte) {
      await supabase.from('notifications').insert({
        uid: user.uid, type: 'inventaire_alerte',
        title: `⚠️ Stock bas : ${item.nom}`,
        body: `Il ne reste que ${newQte} ${pluralUnite(item.unite, newQte)} de ${item.nom}.`,
        data: { itemId: item.id },
        read: false,
      });
      await createCommandeTask(item.nom, user.uid, pid);
    }

    loadItems();
    if (detailItem?.id === item.id) loadMouvements(item.id);
  }

  const displayed = catFilter === 'tous'
    ? items
    : items.filter(i => i.categorie === catFilter);

  const alertes = items.filter(i =>
    i.alerte_active && i.quantite_alerte !== null && i.quantite <= i.quantite_alerte
  );

  if (authLoading || loading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 pb-24">

      {/* Toast tâche créée */}
      {taskToast && (
        <div className="fixed bottom-24 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 bg-[#0C5C6C] text-white text-sm font-semibold px-5 py-3 rounded-2xl shadow-lg animate-fade-in">
          <span>📋 Tâche créée : commander {taskToast}</span>
          <a href="/elevage/planning" className="underline underline-offset-2 whitespace-nowrap">Voir</a>
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between mb-5">
        <div className="flex items-center gap-3">
          <button onClick={() => router.back()} className="p-2 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <div>
            <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
              📦 Inventaire
            </h1>
            <p className="text-xs text-gray-400">{items.length} article{items.length !== 1 ? 's' : ''} en stock</p>
          </div>
        </div>
        <button onClick={() => { setEditItem(null); setShowForm(true); }}
          className="bg-[#0C5C6C] text-white text-sm font-semibold px-4 py-2 rounded-xl hover:bg-[#094F5D] transition-colors">
          + Ajouter
        </button>
      </div>

      {/* Alertes stock bas */}
      {alertes.length > 0 && (
        <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 mb-5">
          <p className="text-sm font-bold text-amber-700 mb-2">⚠️ Stock bas ({alertes.length})</p>
          <div className="space-y-1">
            {alertes.map(a => (
              <p key={a.id} className="text-xs text-amber-700">
                <span className="font-semibold">{a.nom}</span> — {a.quantite} {pluralUnite(a.unite, a.quantite)} restant{a.quantite !== 1 ? 's' : ''}
              </p>
            ))}
          </div>
        </div>
      )}

      {/* Filtres catégorie */}
      <div className="flex gap-2 overflow-x-auto pb-2 mb-5 -mx-1 px-1">
        <button onClick={() => setCatFilter('tous')}
          className={`flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold border transition-all ${
            catFilter === 'tous' ? 'bg-[#1F2A2E] border-[#1F2A2E] text-white' : 'border-gray-300 text-gray-600 hover:border-gray-400'
          }`}>
          Tous ({items.length})
        </button>
        {CATEGORIES.map(c => {
          const count = items.filter(i => i.categorie === c.value).length;
          if (count === 0) return null;
          return (
            <button key={c.value} onClick={() => setCatFilter(c.value)}
              className={`flex-shrink-0 flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-semibold border transition-all ${
                catFilter === c.value
                  ? 'text-white border-transparent'
                  : 'border-gray-300 text-gray-600 hover:border-gray-400'
              }`}
              style={catFilter === c.value ? { backgroundColor: c.color, borderColor: c.color } : {}}>
              {c.emoji} {c.label} ({count})
            </button>
          );
        })}
      </div>

      {/* Liste articles */}
      {displayed.length === 0 ? (
        <div className="text-center py-16">
          <span className="text-5xl block mb-3">📦</span>
          <p className="font-semibold text-gray-500 mb-1">Aucun article</p>
          <p className="text-sm text-gray-400">Ajoutez vos premiers stocks avec le bouton +</p>
        </div>
      ) : (
        <div className="space-y-3">
          {displayed.map(item => {
            const cat = catInfo(item.categorie);
            const isLow = item.alerte_active && item.quantite_alerte !== null && item.quantite <= item.quantite_alerte;
            return (
              <div key={item.id}
                className={`bg-white rounded-2xl border shadow-sm overflow-hidden ${isLow ? 'border-amber-300' : 'border-gray-100'}`}>
                <div className="flex items-center gap-3 p-4">
                  {/* Icône catégorie */}
                  <div className="w-10 h-10 rounded-xl flex items-center justify-center text-xl flex-shrink-0"
                    style={{ backgroundColor: `${cat.color}15` }}>
                    {cat.emoji}
                  </div>

                  {/* Infos */}
                  <div className="flex-1 min-w-0" onClick={() => openDetail(item)} style={{ cursor: 'pointer' }}>
                    <div className="flex items-center gap-2">
                      <p className="font-bold text-[#1F2A2E] text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {item.nom}
                      </p>
                      {isLow && <span className="text-[10px] bg-amber-100 text-amber-700 px-1.5 py-0.5 rounded font-bold flex-shrink-0">⚠️ bas</span>}
                    </div>
                    <p className="text-sm font-semibold" style={{ color: isLow ? '#B45309' : cat.color }}>
                      {item.quantite} {pluralUnite(item.unite, item.quantite)}
                      {item.quantite_alerte !== null && (
                        <span className="text-xs text-gray-400 font-normal ml-1">
                          · seuil {item.quantite_alerte} {pluralUnite(item.unite, item.quantite_alerte)}
                        </span>
                      )}
                    </p>
                  </div>

                  {/* Actions rapides */}
                  <div className="flex gap-2 flex-shrink-0">
                    <QuickMvt item={item} type="consommation" onLog={logMouvement} />
                    <QuickMvt item={item} type="restock" onLog={logMouvement} />
                    <button onClick={() => { setEditItem(item); setShowForm(true); }}
                      className="w-8 h-8 rounded-lg bg-gray-100 flex items-center justify-center text-gray-500 hover:bg-gray-200 transition-colors text-xs">
                      ✏️
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Modal détail / historique */}
      {detailItem && (
        <div className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 px-4 pb-6"
          onClick={e => { if (e.target === e.currentTarget) setDetailItem(null); }}>
          <div className="bg-white rounded-2xl w-full max-w-lg max-h-[80vh] overflow-hidden flex flex-col">
            <div className="flex items-center justify-between p-4 border-b border-gray-100">
              <div>
                <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {catInfo(detailItem.categorie).emoji} {detailItem.nom}
                </p>
                <p className="text-xs text-gray-400">Historique des mouvements</p>
              </div>
              <button onClick={() => setDetailItem(null)} className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
            </div>
            <div className="overflow-y-auto flex-1 p-4">
              {mvtLoading ? (
                <div className="flex justify-center py-8">
                  <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
                </div>
              ) : mouvements.length === 0 ? (
                <p className="text-center text-sm text-gray-400 py-8">Aucun mouvement enregistré</p>
              ) : (
                <div className="space-y-2">
                  {mouvements.map(m => (
                    <div key={m.id} className="flex items-start gap-3 py-2 border-b border-gray-50 last:border-0">
                      <span className="text-lg flex-shrink-0 mt-0.5">
                        {m.type === 'consommation' ? '📉' : m.type === 'restock' ? '📦' : '🔧'}
                      </span>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className={`text-sm font-bold ${m.type === 'consommation' ? 'text-red-600' : 'text-green-600'}`}>
                            {m.type === 'consommation' ? '-' : '+'}{m.quantite} {pluralUnite(detailItem.unite, m.quantite)}
                          </span>
                          <span className="text-xs text-gray-400">{m.auteur_nom}</span>
                        </div>
                        {m.note && <p className="text-xs text-gray-500 mt-0.5">{m.note}</p>}
                        <p className="text-[10px] text-gray-400 mt-0.5">{fmtDate(m.created_at)}</p>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Modal ajout / édition */}
      {showForm && (
        <ItemFormModal
          item={editItem}
          uid={user!.uid}
          profileId={profileId || null}
          onClose={() => { setShowForm(false); setEditItem(null); }}
          onSaved={loadItems}
        />
      )}
    </div>
  );
}

// ── Bouton mouvement rapide ───────────────────────────────────────────────────

function QuickMvt({ item, type, onLog }: {
  item: Item;
  type: 'consommation' | 'restock';
  onLog: (item: Item, type: MvtType, qte: number, note: string) => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [qte, setQte]   = useState('1');
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);

  async function submit() {
    const q = parseFloat(qte);
    if (!q || q <= 0) return;
    setSaving(true);
    await onLog(item, type, q, note);
    setSaving(false);
    setOpen(false);
    setQte('1');
    setNote('');
  }

  const isConsomm = type === 'consommation';

  return (
    <>
      <button onClick={() => setOpen(true)}
        className={`w-8 h-8 rounded-lg flex items-center justify-center text-sm font-bold transition-colors ${
          isConsomm
            ? 'bg-red-50 text-red-500 hover:bg-red-100'
            : 'bg-green-50 text-green-600 hover:bg-green-100'
        }`}
        title={isConsomm ? 'Consommation' : 'Réappro'}>
        {isConsomm ? '−' : '+'}
      </button>

      {open && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 px-4 pb-6"
          onClick={e => { if (e.target === e.currentTarget) setOpen(false); }}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5">
            <p className="font-bold text-[#1F2A2E] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
              {isConsomm ? '📉 Consommation' : '📦 Réapprovisionnement'} — {item.nom}
            </p>
            <div className="flex gap-3 mb-3">
              <div className="flex-1">
                <label className="text-xs font-semibold text-gray-500 mb-1 block">Quantité ({item.unite})</label>
                <input type="number" min="0.1" step="0.1" value={qte} onChange={e => setQte(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]"
                  autoFocus />
              </div>
            </div>
            <div className="mb-4">
              <label className="text-xs font-semibold text-gray-500 mb-1 block">Note <span className="font-normal">(optionnel)</span></label>
              <input type="text" value={note} onChange={e => setNote(e.target.value)}
                placeholder={isConsomm ? 'ex : paquet de croquettes terminé' : 'ex : livraison reçue'}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            </div>
            <div className="flex gap-3">
              <button onClick={() => setOpen(false)}
                className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50">
                Annuler
              </button>
              <button onClick={submit} disabled={saving}
                className={`flex-1 py-2.5 rounded-xl text-sm font-semibold text-white transition-colors disabled:opacity-60 ${
                  isConsomm ? 'bg-red-500 hover:bg-red-600' : 'bg-[#6E9E57] hover:bg-[#5A8A45]'
                }`}>
                {saving ? '…' : 'Enregistrer'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

// ── Formulaire article ────────────────────────────────────────────────────────

function ItemFormModal({ item, uid, profileId, onClose, onSaved }: {
  item: Item | null;
  uid: string;
  profileId: string | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [nom,       setNom]       = useState(item?.nom        ?? '');
  const [cat,       setCat]       = useState<Categorie>(item?.categorie  ?? 'alimentation');
  const [unite,     setUnite]     = useState<Unite>(item?.unite      ?? 'kg');
  const [quantite,  setQuantite]  = useState(String(item?.quantite   ?? '0'));
  const [seuil,     setSeuil]     = useState(String(item?.quantite_alerte ?? ''));
  const [alerte,    setAlerte]    = useState(item?.alerte_active ?? true);
  const [notes,     setNotes]     = useState(item?.notes       ?? '');
  const [saving,    setSaving]    = useState(false);
  const [deleting,  setDeleting]  = useState(false);

  const iCls = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';

  async function save() {
    if (!nom.trim()) return;
    setSaving(true);
    const payload = {
      uid_eleveur: uid,
      ...(profileId ? { eleveur_profile_id: profileId } : {}),
      nom: nom.trim(),
      categorie: cat,
      unite,
      quantite: parseFloat(quantite) || 0,
      quantite_alerte: seuil ? parseFloat(seuil) : null,
      alerte_active: alerte,
      notes: notes.trim() || null,
      updated_at: new Date().toISOString(),
    };
    if (item) {
      await supabase.from('inventaire_items').update(payload).eq('id', item.id);
    } else {
      await supabase.from('inventaire_items').insert(payload);
    }
    setSaving(false);
    onSaved();
    onClose();
  }

  async function del() {
    if (!item) return;
    setDeleting(true);
    await supabase.from('inventaire_items').delete().eq('id', item.id);
    setDeleting(false);
    onSaved();
    onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 px-4 pb-6"
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-4 border-b border-gray-100 sticky top-0 bg-white">
          <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            {item ? 'Modifier l\'article' : 'Nouvel article'}
          </p>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
        </div>

        <div className="p-5 space-y-4">

          {/* Nom */}
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Nom de l&apos;article *</label>
            <input className={iCls} value={nom} onChange={e => setNom(e.target.value)}
              placeholder="ex : Croquettes Royal Canin, Litière silice…" autoFocus />
          </div>

          {/* Catégorie */}
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-2 block">Catégorie</label>
            <div className="flex flex-wrap gap-2">
              {CATEGORIES.map(c => (
                <button key={c.value} type="button" onClick={() => setCat(c.value)}
                  className={`flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-semibold border transition-all ${
                    cat === c.value ? 'text-white border-transparent' : 'border-gray-200 text-gray-600 hover:border-gray-300'
                  }`}
                  style={cat === c.value ? { backgroundColor: c.color } : {}}>
                  {c.emoji} {c.label}
                </button>
              ))}
            </div>
          </div>

          {/* Quantité + Unité */}
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="text-xs font-semibold text-gray-500 mb-1 block">Quantité actuelle</label>
              <input type="number" min="0" step="0.1" className={iCls} value={quantite}
                onChange={e => setQuantite(e.target.value)} />
            </div>
            <div className="flex-1">
              <label className="text-xs font-semibold text-gray-500 mb-1 block">Unité</label>
              <select className={iCls} value={unite} onChange={e => setUnite(e.target.value as Unite)}>
                {UNITES.map(u => <option key={u} value={u}>{u}</option>)}
              </select>
            </div>
          </div>

          {/* Seuil d'alerte */}
          <div className="bg-amber-50 rounded-xl p-4">
            <div className="flex items-center justify-between mb-3">
              <label className="text-sm font-semibold text-amber-800">⚠️ Alerte stock bas</label>
              <button type="button" onClick={() => setAlerte(v => !v)}
                className={`w-10 h-5 rounded-full transition-colors relative ${alerte ? 'bg-amber-500' : 'bg-gray-200'}`}>
                <div className={`w-4 h-4 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${alerte ? 'translate-x-5' : 'translate-x-0.5'}`} />
              </button>
            </div>
            {alerte && (
              <div>
                <label className="text-xs font-semibold text-amber-700 mb-1 block">
                  Notifier quand il reste moins de… ({unite})
                </label>
                <input type="number" min="0" step="0.1" className="w-full border border-amber-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-amber-400 bg-white"
                  placeholder={`ex : 2 ${unite}`} value={seuil} onChange={e => setSeuil(e.target.value)} />
              </div>
            )}
          </div>

          {/* Notes */}
          <div>
            <label className="text-xs font-semibold text-gray-500 mb-1 block">Notes <span className="font-normal">(optionnel)</span></label>
            <textarea rows={2} className={`${iCls} resize-none`} value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="Marque préférée, fournisseur, remarques…" />
          </div>

          {/* Boutons */}
          <div className="flex gap-3 pt-1">
            {item && (
              <button type="button" onClick={del} disabled={deleting}
                className="px-4 py-2.5 border border-red-200 text-red-500 rounded-xl text-sm font-semibold hover:bg-red-50 disabled:opacity-60">
                {deleting ? '…' : 'Supprimer'}
              </button>
            )}
            <button type="button" onClick={onClose}
              className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600 hover:bg-gray-50">
              Annuler
            </button>
            <button type="button" onClick={save} disabled={saving || !nom.trim()}
              className="flex-1 py-2.5 bg-[#0C5C6C] hover:bg-[#094F5D] text-white rounded-xl text-sm font-semibold disabled:opacity-60 transition-colors">
              {saving ? 'Enregistrement…' : item ? 'Enregistrer' : 'Ajouter'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
