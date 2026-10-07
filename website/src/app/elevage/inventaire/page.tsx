'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import { planVeto } from '@/lib/clinique';

// ── Types ──────────────────────────────────────────────────────────────────────

type Categorie = 'alimentation' | 'litiere' | 'medicament' | 'accessoire' | 'hygiene' | 'autre'
  | 'vaccin' | 'antiparasitaire' | 'consommable';
type Unite     = string;
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
  // Pharmacie vétérinaire (migration_inventaire_veto.sql)
  lot?: string | null;
  date_peremption?: string | null;
  prix_vente?: number | null;
  froid?: boolean | null;
  stupefiant?: boolean | null;
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
  stock_apres?: number | null;
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

// Pharmacie vétérinaire — miroir appli (inventaire_page.dart _categoriesVeto).
const CATEGORIES_VETO: { value: Categorie; label: string; emoji: string; color: string }[] = [
  { value: 'medicament',      label: 'Médicaments',           emoji: '💊', color: '#E53E3E' },
  { value: 'vaccin',          label: 'Vaccins',               emoji: '💉', color: '#2B6CB0' },
  { value: 'antiparasitaire', label: 'Antiparasitaires',      emoji: '🛡️', color: '#805AD5' },
  { value: 'alimentation',    label: 'Alimentation',          emoji: '🥣', color: '#6E9E57' },
  { value: 'consommable',     label: 'Consommables médicaux', emoji: '🩹', color: '#0C5C6C' },
  { value: 'hygiene',         label: 'Hygiène & soins',       emoji: '🧴', color: '#8E24AA' },
  { value: 'autre',           label: 'Autre',                 emoji: '📦', color: '#718096' },
];
const UNITES_VETO: Unite[] = ['boite', 'flacon', 'dose', 'comprimé', 'pipette', 'seringue', 'ampoule', 'sac', 'kg', 'mL', 'unité'];

/** Péremption : null = sans date ; < 0 = périmé ; sinon jours restants. */
function joursAvantPeremption(i: Item): number | null {
  if (!i.date_peremption) return null;
  const d = new Date(i.date_peremption + 'T00:00:00');
  const t = new Date(); t.setHours(0, 0, 0, 0);
  return Math.round((d.getTime() - t.getTime()) / 86400000);
}

const CAT_MAP = Object.fromEntries([...CATEGORIES_VETO, ...CATEGORIES].map(c => [c.value, c]));

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
  const { id: profileId, loaded: profileLoaded } = useActiveProfileState();

  const [items,      setItems]      = useState<Item[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [catFilter,  setCatFilter]  = useState<Categorie | 'tous'>('tous');
  const [showForm,   setShowForm]   = useState(false);
  const [editItem,   setEditItem]   = useState<Item | null>(null);
  const [detailItem, setDetailItem] = useState<Item | null>(null);
  const [mouvements, setMouvements] = useState<Mouvement[]>([]);
  const [mvtLoading, setMvtLoading] = useState(false);
  const [taskToast,  setTaskToast]  = useState<string | null>(null);
  // Pharmacie vétérinaire : profil actif vétérinaire (formules Avancé / Clinique).
  const [veto, setVeto] = useState(false);
  const [vetoBloque, setVetoBloque] = useState(false);
  const [showRegistre, setShowRegistre] = useState(false);
  const [registre, setRegistre] = useState<Mouvement[]>([]);

  useEffect(() => {
    if (!user || !profileLoaded || !profileId) return;
    supabase.from('user_profiles_complet').select('profile_type').eq('id', profileId).maybeSingle()
      .then(async ({ data }) => {
        const v = data?.profile_type === 'veterinaire';
        setVeto(v);
        if (v) {
          const code = await planVeto(user.uid);
          setVetoBloque(code === 'free');
        }
      });
  }, [user, profileId, profileLoaded]);

  async function ouvrirRegistre() {
    const ids = items.filter(i => i.stupefiant).map(i => i.id);
    setShowRegistre(true);
    if (!ids.length) { setRegistre([]); return; }
    const { data } = await supabase.from('inventaire_mouvements').select('*')
      .in('item_id', ids).order('created_at', { ascending: false });
    const rows = (data ?? []) as Mouvement[];
    const uids = [...new Set(rows.map(r => r.uid_auteur))];
    if (uids.length) {
      const { data: us } = await supabase.from('users_complet').select('uid, firstname, lastname').in('uid', uids);
      const m: Record<string, string> = {};
      (us ?? []).forEach(u => { m[u.uid as string] = `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim(); });
      rows.forEach(r => { r.auteur_nom = m[r.uid_auteur] ?? ''; });
    }
    setRegistre(rows);
  }

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  const loadItems = useCallback(async () => {
    // Attendre la résolution du profil actif (lecture localStorage) avant de
    // charger — sinon un repli sur uid_eleveur seul remonte les articles de
    // TOUS les profils du compte (ex: éleveur affiché sous association).
    if (!user || !profileLoaded) return;
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
  }, [user, profileId, profileLoaded]);

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
        .from('user_profiles_complet')
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
      ...(pid ? { eleveur_profile_id: pid, profile_id: pid } : {}),
      profil_source: 'eleveur',
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
      // Registre des stupéfiants : stock restant après le mouvement.
      ...(item.stupefiant ? { stock_apres: newQte } : {}),
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
        ...(pid ? { profile_id: pid } : {}),
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

  if (veto && vetoBloque) {
    return (
      <div className="max-w-md mx-auto px-4 py-16 text-center">
        <p className="text-4xl mb-3">💊</p>
        <h1 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Inventaire & pharmacie</h1>
        <p className="text-sm text-gray-500 mb-5">Lots, péremptions, chaîne du froid et registre des stupéfiants : disponible avec les formules Avancé et Clinique.</p>
        <a href="/veterinaire/abonnement" className="inline-block bg-[#0C5C6C] text-white font-semibold px-6 py-2.5 rounded-xl text-sm">Voir les formules</a>
      </div>
    );
  }

  const cats = veto ? CATEGORIES_VETO : CATEGORIES;
  const perimes = veto ? items.filter(i => (joursAvantPeremption(i) ?? 999) < 0) : [];
  const bientot = veto ? items.filter(i => { const j = joursAvantPeremption(i); return j !== null && j >= 0 && j <= 30; }) : [];

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
              {veto ? '💊 Inventaire & pharmacie' : '📦 Inventaire'}
            </h1>
            <p className="text-xs text-gray-400">{items.length} article{items.length !== 1 ? 's' : ''} en stock</p>
          </div>
        </div>
        <div className="flex gap-2">
          {veto && (
            <button onClick={ouvrirRegistre}
              className="border border-[#0C5C6C] text-[#0C5C6C] text-sm font-semibold px-3 py-2 rounded-xl hover:bg-[#0C5C6C]/5">
              📖 Registre des stupéfiants
            </button>
          )}
          <button onClick={() => { setEditItem(null); setShowForm(true); }}
            className="bg-[#0C5C6C] text-white text-sm font-semibold px-4 py-2 rounded-xl hover:bg-[#094F5D] transition-colors">
            + Ajouter
          </button>
        </div>
      </div>

      {/* Péremptions (pharmacie vétérinaire) */}
      {(perimes.length > 0 || bientot.length > 0) && (
        <div className="bg-red-50 border border-red-200 rounded-2xl p-4 mb-5">
          <p className="text-sm font-bold text-red-700 mb-2">⏳ Péremptions — {perimes.length} périmé(s), {bientot.length} sous 30 jours</p>
          <div className="space-y-1">
            {[...perimes, ...bientot].map(a => (
              <p key={a.id} className="text-xs text-red-700">
                <span className="font-semibold">{a.nom}</span>{a.lot ? ` (lot ${a.lot})` : ''} — {(joursAvantPeremption(a) ?? 0) < 0 ? 'périmé' : `expire dans ${joursAvantPeremption(a)} j`}
              </p>
            ))}
          </div>
        </div>
      )}

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
        {cats.map(c => {
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
                    {(item.stupefiant || item.froid || item.lot || item.date_peremption) && (
                      <div className="flex flex-wrap gap-2 text-[10px] mt-0.5">
                        {item.stupefiant && <span className="font-bold text-red-700">🔒 Stupéfiant</span>}
                        {item.froid && <span className="font-bold text-blue-700">❄️ +2/+8 °C</span>}
                        {item.lot && <span className="text-gray-500">Lot {item.lot}</span>}
                        {joursAvantPeremption(item) !== null && (
                          <span className={`font-bold ${(joursAvantPeremption(item) ?? 99) <= 30 ? 'text-red-600' : 'text-gray-500'}`}>
                            {(joursAvantPeremption(item) ?? 0) < 0 ? '⛔ Périmé' : `Exp. ${new Date(item.date_peremption + 'T00:00:00').toLocaleDateString('fr-FR')}`}
                          </span>
                        )}
                      </div>
                    )}
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
          veto={veto}
          onClose={() => { setShowForm(false); setEditItem(null); }}
          onSaved={loadItems}
        />
      )}

      {/* Registre des stupéfiants */}
      {showRegistre && (
        <div className="fixed inset-0 z-40 flex items-end sm:items-center justify-center bg-black/40 px-4 pb-6"
          onClick={e => { if (e.target === e.currentTarget) setShowRegistre(false); }}>
          <div className="bg-white rounded-2xl w-full max-w-lg max-h-[85vh] overflow-hidden flex flex-col">
            <div className="flex items-center justify-between p-4 border-b border-gray-100">
              <div>
                <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>📖 Registre des stupéfiants</p>
                <p className="text-xs text-gray-400">Entrées / sorties motivées, stock après mouvement — à conserver 10 ans</p>
              </div>
              <button onClick={() => setShowRegistre(false)} className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
            </div>
            <div className="overflow-y-auto flex-1 p-4 space-y-2">
              {items.filter(i => i.stupefiant).map(i => (
                <p key={i.id} className="text-sm font-semibold text-[#1F2A2E]">🔒 {i.nom} — stock actuel : {i.quantite} {pluralUnite(i.unite, i.quantite)}</p>
              ))}
              {items.every(i => !i.stupefiant) && <p className="text-sm text-gray-400">Aucun produit marqué « Stupéfiant ».</p>}
              <div className="border-t border-gray-100 pt-2" />
              {registre.map(m => {
                const it = items.find(i => i.id === m.item_id);
                return (
                  <div key={m.id} className="border border-gray-100 rounded-xl p-3 text-xs">
                    <div className="flex items-center gap-2">
                      <span className={`font-bold ${m.type === 'consommation' ? 'text-red-600' : 'text-green-700'}`}>
                        {m.type === 'consommation' ? '⬇️ Sortie' : '⬆️ Entrée'}
                      </span>
                      <span className="flex-1 truncate">{it?.nom}</span>
                      <span className="text-gray-400">{fmtDate(m.created_at)}</span>
                    </div>
                    <p>Quantité : {m.quantite}{m.stock_apres != null ? ` · stock après : ${m.stock_apres}` : ''}</p>
                    {m.note && <p>Motif : {m.note}</p>}
                    {m.auteur_nom && <p className="text-gray-400">Par {m.auteur_nom}</p>}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
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
    if (item.stupefiant && !note.trim()) {
      alert(type === 'consommation'
        ? 'Stupéfiant : indiquez le motif (animal, ordonnance…).'
        : "Stupéfiant : indiquez l'origine (fournisseur, bon de livraison…).");
      return;
    }
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
              <label className="text-xs font-semibold text-gray-500 mb-1 block">
                {item.stupefiant ? 'Motif / origine *' : <>Note <span className="font-normal">(optionnel)</span></>}
              </label>
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

function ItemFormModal({ item, uid, profileId, veto = false, onClose, onSaved }: {
  item: Item | null;
  uid: string;
  profileId: string | null;
  veto?: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [lot,        setLot]        = useState(item?.lot ?? '');
  const [peremption, setPeremption] = useState(item?.date_peremption ?? '');
  const [prixVente,  setPrixVente]  = useState(item?.prix_vente != null ? String(item.prix_vente) : '');
  const [froid,      setFroid]      = useState(!!item?.froid);
  const [stupefiant, setStupefiant] = useState(!!item?.stupefiant);
  const [nom,       setNom]       = useState(item?.nom        ?? '');
  const [cat,       setCat]       = useState<Categorie>(item?.categorie  ?? (veto ? 'medicament' : 'alimentation'));
  const [unite,     setUnite]     = useState<Unite>(item?.unite      ?? (veto ? 'boite' : 'kg'));
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
      ...(veto ? {
        lot: lot.trim() || null,
        date_peremption: peremption || null,
        prix_vente: prixVente ? parseFloat(prixVente.replace(',', '.')) : null,
        froid, stupefiant,
      } : {}),
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
              {(veto ? CATEGORIES_VETO : CATEGORIES).map(c => (
                <button key={c.value} type="button" onClick={() => { setCat(c.value); if (veto && c.value === 'vaccin') setFroid(true); }}
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
                {[...new Set([...(veto ? UNITES_VETO : UNITES), unite])].map(u => <option key={u} value={u}>{u}</option>)}
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

          {veto && (
            <div className="space-y-3">
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="text-xs font-semibold text-gray-500 mb-1 block">N° de lot</label>
                  <input className={iCls} value={lot} onChange={e => setLot(e.target.value)} />
                </div>
                <div className="flex-1">
                  <label className="text-xs font-semibold text-gray-500 mb-1 block">Péremption</label>
                  <input type="date" className={iCls} value={peremption} onChange={e => setPeremption(e.target.value)} />
                </div>
              </div>
              <div>
                <label className="text-xs font-semibold text-gray-500 mb-1 block">Prix de vente (€) <span className="font-normal">si vendu au comptoir</span></label>
                <input type="number" min="0" step="0.01" className={iCls} value={prixVente} onChange={e => setPrixVente(e.target.value)} />
              </div>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={froid} onChange={e => setFroid(e.target.checked)} /> ❄️ À conserver au froid (+2 / +8 °C)
              </label>
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" className="mt-1" checked={stupefiant} onChange={e => setStupefiant(e.target.checked)} />
                <span>🔒 Stupéfiant <span className="block text-xs text-gray-400">Chaque entrée / sortie est inscrite au registre, avec son motif.</span></span>
              </label>
            </div>
          )}

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
