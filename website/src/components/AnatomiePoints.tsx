'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// Catégories de points — mirror du légende "Points d'ostéopathie" des
// schémas anatomiques d'origine.
export const CATEGORIES_OSTEO: { key: string; label: string; color: string }[] = [
  { key: 'tension_cervicale',     label: 'Tension cervicale',     color: '#E67E22' },
  { key: 'tension_thoracique',    label: 'Tension thoracique',    color: '#F39C12' },
  { key: 'tension_lombaire',      label: 'Tension lombaire',      color: '#3498DB' },
  { key: 'tension_sacro_iliaque', label: 'Tension sacro-iliaque', color: '#9B59B6' },
  { key: 'trigger',               label: 'Point trigger',         color: '#795548' },
  { key: 'acupuncture',           label: 'Point d\'acupuncture',  color: '#8BC34A' },
  { key: 'autre',                 label: 'Autre',                 color: '#9E9E9E' },
];

function colorFor(cat: string) { return CATEGORIES_OSTEO.find(c => c.key === cat)?.color ?? '#9E9E9E'; }
function labelFor(cat: string) { return CATEGORIES_OSTEO.find(c => c.key === cat)?.label ?? cat; }

// Une seule vue par espèce (silhouette squelette pleine page, sans découpe).
const ASSETS: Record<string, { src: string; ratio: number }> = {
  chien:  { src: '/anatomie/chien_squelette.png', ratio: 1536 / 1024 },
  chat:   { src: '/anatomie/chat_squelette.png', ratio: 1402 / 1122 },
  cheval: { src: '/anatomie/cheval_squelette.png', ratio: 1536 / 1024 },
};

function speciesKey(espece: string): 'chien' | 'chat' | 'cheval' | null {
  const e = (espece || '').toLowerCase();
  if (e.includes('chien')) return 'chien';
  if (e.includes('chat')) return 'chat';
  if (e.includes('cheval')) return 'cheval';
  return null;
}

function fmtDate(iso: string) {
  const [y, m, d] = iso.slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
}

interface PointOsteo {
  id: string;
  espece: string;
  seance_id: string;
  x_pct: number;
  y_pct: number;
  categorie: string;
  note: string | null;
  created_at: string;
}

interface SeanceOsteo {
  id: string;
  animal_id: string;
  date_seance: string;
  note: string | null;
}

// ── Liste des séances (pro) — remplace l'ancien canvas unique par un
// historique de comptes rendus datés ────────────────────────────────────────
export function AnatomieSeances({ animalId, espece, profilType }: { animalId: string; espece: string; profilType: string }) {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const species = speciesKey(espece);

  const [seances, setSeances] = useState<SeanceOsteo[]>([]);
  const [pointCounts, setPointCounts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [openSeance, setOpenSeance] = useState<SeanceOsteo | null>(null);
  const [hasAjoutSeances, setHasAjoutSeances] = useState(false);
  const [showUpgrade, setShowUpgrade] = useState(false);

  useEffect(() => {
    if (!user) return;
    supabase.from('abonnements').select('plan_code').eq('uid', user.uid).eq('profil_type', profilType).eq('statut', 'actif')
      .order('created_at', { ascending: false }).limit(1).maybeSingle()
      .then(({ data }) => setHasAjoutSeances((data?.plan_code ?? 'free') !== 'free'));
  }, [user, profilType]);

  const load = useCallback(async () => {
    if (!animalId) return;
    const { data } = await supabase.from('seances_osteo').select('*')
      .eq('animal_id', animalId).order('date_seance', { ascending: false });
    const rows = (data ?? []) as SeanceOsteo[];
    setSeances(rows);
    const ids = rows.map(r => r.id);
    if (ids.length > 0) {
      const { data: pts } = await supabase.from('points_osteo').select('seance_id').in('seance_id', ids);
      const counts: Record<string, number> = {};
      for (const p of (pts ?? []) as { seance_id: string }[]) counts[p.seance_id] = (counts[p.seance_id] ?? 0) + 1;
      setPointCounts(counts);
    }
    setLoading(false);
  }, [animalId]);

  useEffect(() => { load(); }, [load]);

  async function nouvelleSeance() {
    if (!user || !species) return;
    if (!hasAjoutSeances) { setShowUpgrade(true); return; }
    setCreating(true);
    const { data } = await supabase.from('seances_osteo').insert({
      animal_id: animalId,
      pro_uid: user.uid,
      ...(activeProfileId ? { pro_profile_id: activeProfileId } : {}),
      date_seance: new Date().toISOString().slice(0, 10),
    }).select().single();
    setCreating(false);
    if (data) setOpenSeance(data as SeanceOsteo);
  }

  if (!species) {
    return (
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-8 text-center text-gray-400 text-sm">
        Schéma anatomique non disponible pour cette espèce.<br />(chien, chat et cheval uniquement)
      </div>
    );
  }
  if (loading) return <div className="flex justify-center py-16 text-gray-400">Chargement…</div>;

  if (openSeance) {
    return (
      <SeanceDetail
        seance={openSeance}
        espece={espece}
        readOnly={false}
        onBack={() => { setOpenSeance(null); load(); }}
      />
    );
  }

  return (
    <div className="space-y-3">
      <button onClick={nouvelleSeance} disabled={creating}
        className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white font-semibold py-3 rounded-xl text-sm transition-colors flex items-center justify-center gap-2"
        style={{ fontFamily: 'Galey, sans-serif' }}>
        {creating ? '…' : '+ Nouvelle séance'}
      </button>

      {showUpgrade && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" onClick={() => setShowUpgrade(false)}>
          <div className="bg-white rounded-2xl p-6 max-w-sm w-full" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Formule Essentiel requise</p>
            <p className="text-sm text-gray-600 mb-4">
              L&apos;ajout de séances au carnet santé (schéma anatomique) est réservé aux formules Essentiel et Pro.
            </p>
            <div className="flex gap-2 justify-end">
              <button onClick={() => setShowUpgrade(false)} className="px-4 py-2 text-sm text-gray-500">Annuler</button>
              <Link href={profilType === 'marechal_ferrant' ? '/marechal-ferrant/abonnement' : '/sante/abonnement'}
                className="px-4 py-2 text-sm font-semibold text-white bg-[#0C5C6C] rounded-xl hover:bg-[#094F5D]">
                Voir les formules
              </Link>
            </div>
          </div>
        </div>
      )}

      {seances.length === 0 ? (
        <p className="text-center py-10 text-gray-400 text-sm">Aucune séance enregistrée pour l&apos;instant.</p>
      ) : (
        <div className="space-y-2">
          {seances.map(s => (
            <button key={s.id} onClick={() => setOpenSeance(s)}
              className="w-full text-left bg-white border border-gray-100 rounded-xl p-3.5 flex items-center gap-3 hover:bg-gray-50 transition-colors">
              <div className="w-10 h-10 rounded-full bg-[#0C5C6C]/8 flex items-center justify-center flex-shrink-0">
                <span className="text-lg">🦴</span>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{fmtDate(s.date_seance)}</p>
                <p className="text-xs text-gray-500">
                  {(pointCounts[s.id] ?? 0) === 0 ? 'Aucun point noté' : `${pointCounts[s.id]} point${pointCounts[s.id] > 1 ? 's' : ''} noté${pointCounts[s.id] > 1 ? 's' : ''}`}
                </p>
                {s.note && <p className="text-xs text-gray-600 truncate mt-0.5">{s.note}</p>}
              </div>
              <span className="text-gray-300">›</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Section lecture seule (propriétaire) — embarquée dans la fiche animal ────
export function AnatomieOwnerSection({ animalId, espece }: { animalId: string; espece: string }) {
  const [seances, setSeances] = useState<SeanceOsteo[]>([]);
  const [loading, setLoading] = useState(true);
  const [openSeance, setOpenSeance] = useState<SeanceOsteo | null>(null);

  useEffect(() => {
    if (!animalId) return;
    supabase.from('seances_osteo').select('*').eq('animal_id', animalId).order('date_seance', { ascending: false })
      .then(({ data }) => { setSeances((data ?? []) as SeanceOsteo[]); setLoading(false); });
  }, [animalId]);

  if (loading || seances.length === 0) return null;

  if (openSeance) {
    return (
      <SeanceDetail
        seance={openSeance}
        espece={espece}
        readOnly={true}
        onBack={() => setOpenSeance(null)}
      />
    );
  }

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
      <h3 className="font-bold text-sm text-[#1F2A2E] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
        🦴 Séances d&apos;ostéopathie / kiné
      </h3>
      <div className="space-y-2">
        {seances.map(s => (
          <button key={s.id} onClick={() => setOpenSeance(s)}
            className="w-full text-left bg-gray-50 rounded-xl p-3 flex items-center gap-3 hover:bg-gray-100 transition-colors">
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{fmtDate(s.date_seance)}</p>
              {s.note && <p className="text-xs text-gray-500 truncate">{s.note}</p>}
            </div>
            <span className="text-gray-300">›</span>
          </button>
        ))}
      </div>
    </div>
  );
}

// ── Détail d'une séance — schéma interactif + note ───────────────────────────
function SeanceDetail({ seance, espece, readOnly, onBack }: {
  seance: SeanceOsteo; espece: string; readOnly: boolean; onBack: () => void;
}) {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const species = speciesKey(espece);

  const [points, setPoints] = useState<PointOsteo[]>([]);
  const [loading, setLoading] = useState(true);
  const [note, setNote] = useState(seance.note ?? '');
  const [dateSeance, setDateSeance] = useState(seance.date_seance);
  const [deleting, setDeleting] = useState(false);
  const [pendingPos, setPendingPos] = useState<{ x: number; y: number } | null>(null);
  const [pendingCat, setPendingCat] = useState<string | null>(null);
  const [pendingNote, setPendingNote] = useState('');
  const [selected, setSelected] = useState<PointOsteo | null>(null);
  const [editing, setEditing] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    supabase.from('points_osteo').select('*').eq('seance_id', seance.id).order('created_at', { ascending: false })
      .then(({ data }) => { setPoints((data ?? []) as PointOsteo[]); setLoading(false); });
  }, [seance.id]);

  async function saveNote() {
    await supabase.from('seances_osteo').update({ note: note.trim() || null }).eq('id', seance.id);
  }

  async function updateDate(newDate: string) {
    setDateSeance(newDate);
    await supabase.from('seances_osteo').update({ date_seance: newDate }).eq('id', seance.id);
  }

  async function deleteSeance() {
    if (!confirm('Supprimer cette séance et tous ses points ?')) return;
    setDeleting(true);
    await supabase.from('seances_osteo').delete().eq('id', seance.id);
    onBack();
  }

  function handleClick(e: React.MouseEvent<HTMLDivElement>) {
    if (readOnly) return;
    const box = containerRef.current?.getBoundingClientRect();
    if (!box) return;
    const xPct = Math.min(100, Math.max(0, ((e.clientX - box.left) / box.width) * 100));
    const yPct = Math.min(100, Math.max(0, ((e.clientY - box.top) / box.height) * 100));
    setPendingPos({ x: xPct, y: yPct });
    setPendingCat(null);
    setPendingNote('');
  }

  async function savePoint() {
    if (!pendingPos || !pendingCat || !user) return;
    const { data } = await supabase.from('points_osteo').insert({
      animal_id: seance.animal_id,
      seance_id: seance.id,
      pro_uid: user.uid,
      ...(activeProfileId ? { pro_profile_id: activeProfileId } : {}),
      espece: species,
      vue: 'squelette',
      x_pct: pendingPos.x,
      y_pct: pendingPos.y,
      categorie: pendingCat,
      note: pendingNote.trim() || null,
    }).select().single();
    if (data) setPoints(prev => [data as PointOsteo, ...prev]);
    setPendingPos(null);
  }

  async function saveEditPoint() {
    if (!selected || !pendingCat) return;
    const { data } = await supabase.from('points_osteo').update({
      categorie: pendingCat,
      note: pendingNote.trim() || null,
    }).eq('id', selected.id).select().single();
    if (data) setPoints(prev => prev.map(p => p.id === selected.id ? data as PointOsteo : p));
    setEditing(false);
    setSelected(null);
  }

  async function deletePoint(id: string) {
    await supabase.from('points_osteo').delete().eq('id', id);
    setPoints(prev => prev.filter(p => p.id !== id));
    setSelected(null);
  }

  // Côté pro : le point s'ouvre directement en édition (catégorie + note
  // modifiables, plus suppression) — pas d'étape de consultation intermédiaire.
  function openPoint(p: PointOsteo) {
    setSelected(p);
    if (!readOnly) {
      setPendingCat(p.categorie);
      setPendingNote(p.note ?? '');
      setEditing(true);
    } else {
      setEditing(false);
    }
  }

  if (!species) return null;

  const asset = ASSETS[species];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <button onClick={onBack} className="text-sm text-[#0C5C6C] hover:underline flex items-center gap-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          ← {fmtDate(dateSeance)}
        </button>
        {!readOnly && (
          <div className="flex items-center gap-2">
            <input type="date" value={dateSeance} onChange={e => e.target.value && updateDate(e.target.value)}
              className="text-xs border border-gray-200 rounded-lg px-2 py-1" style={{ fontFamily: 'Galey, sans-serif' }} />
            <button onClick={deleteSeance} disabled={deleting}
              className="text-xs text-red-500 border border-red-200 hover:bg-red-50 disabled:opacity-50 rounded-lg px-2.5 py-1 font-medium"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {deleting ? '…' : 'Supprimer'}
            </button>
          </div>
        )}
      </div>

      {loading ? <div className="flex justify-center py-16 text-gray-400">Chargement…</div> : (
        <>
          {!readOnly ? (
            <textarea value={note} onChange={e => setNote(e.target.value)} onBlur={saveNote} rows={2}
              placeholder="Notes sur la séance (optionnel)"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
          ) : note ? (
            <div className="bg-white border border-gray-100 rounded-xl p-3 text-sm text-gray-700">{note}</div>
          ) : null}

          <p className="text-center text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
            {readOnly ? 'Points travaillés lors de cette séance' : 'Cliquez sur le schéma pour noter un point travaillé'}
          </p>

          <div
            ref={containerRef}
            onClick={handleClick}
            className={`relative mx-auto rounded-2xl overflow-hidden border border-gray-100 bg-[#FAF9F6] select-none ${readOnly ? '' : 'cursor-crosshair'}`}
            style={{ aspectRatio: asset.ratio, maxWidth: 560 }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={asset.src} alt={`Schéma ${species}`} className="w-full h-full object-contain pointer-events-none" draggable={false} />
            {points.map(p => (
              <button key={p.id}
                onClick={(e) => { e.stopPropagation(); openPoint(p); }}
                className="absolute rounded-full border-2 border-white shadow"
                style={{
                  left: `calc(${p.x_pct}% - 9px)`, top: `calc(${p.y_pct}% - 9px)`,
                  width: 18, height: 18, background: colorFor(p.categorie),
                }}
              />
            ))}
          </div>

          <div className="flex flex-wrap gap-x-4 gap-y-1.5 justify-center">
            {CATEGORIES_OSTEO.map(c => (
              <div key={c.key} className="flex items-center gap-1.5">
                <span className="w-2.5 h-2.5 rounded-full" style={{ background: c.color }} />
                <span className="text-[11px] text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>{c.label}</span>
              </div>
            ))}
          </div>

          {points.length > 0 && (
            <div className="space-y-2">
              <h4 className="font-bold text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Points de cette séance</h4>
              {points.map(p => (
                <button key={p.id} onClick={() => openPoint(p)}
                  className="w-full text-left bg-white border border-gray-100 rounded-xl p-3 flex items-center gap-3 hover:bg-gray-50">
                  <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: colorFor(p.categorie) }} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{labelFor(p.categorie)}</p>
                    {p.note && <p className="text-xs text-gray-500 truncate">{p.note}</p>}
                  </div>
                  <span className="text-gray-300">›</span>
                </button>
              ))}
            </div>
          )}
        </>
      )}

      {/* Modale nouveau point */}
      {pendingPos && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setPendingPos(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5 space-y-4" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-base text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Nouveau point</h3>
            <div className="flex flex-wrap gap-2">
              {CATEGORIES_OSTEO.map(c => (
                <button key={c.key} onClick={() => setPendingCat(c.key)}
                  className="px-3 py-1.5 rounded-full text-xs font-medium border transition-colors"
                  style={{
                    fontFamily: 'Galey, sans-serif',
                    background: pendingCat === c.key ? c.color : `${c.color}1F`,
                    color: pendingCat === c.key ? 'white' : '#374151',
                    borderColor: c.color,
                  }}>
                  {c.label}
                </button>
              ))}
            </div>
            <textarea value={pendingNote} onChange={e => setPendingNote(e.target.value)} rows={3}
              placeholder="Note (optionnel)"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-gray-50" />
            <button onClick={savePoint} disabled={!pendingCat}
              className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-40 text-white font-semibold py-3 rounded-xl text-sm transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Enregistrer
            </button>
          </div>
        </div>
      )}

      {/* Modale détail (lecture seule — propriétaire) */}
      {selected && !editing && readOnly && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setSelected(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5 space-y-4" onClick={e => e.stopPropagation()}>
            <div className="flex items-center gap-2">
              <span className="w-3.5 h-3.5 rounded-full" style={{ background: colorFor(selected.categorie) }} />
              <h3 className="font-bold text-base text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{labelFor(selected.categorie)}</h3>
            </div>
            <p className="text-xs text-gray-400">{new Date(selected.created_at).toLocaleString('fr-FR')}</p>
            {selected.note ? (
              <p className="text-sm text-gray-700">{selected.note}</p>
            ) : (
              <p className="text-sm text-gray-400">Aucune note</p>
            )}
          </div>
        </div>
      )}

      {/* Modale édition point */}
      {selected && editing && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setEditing(false)}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5 space-y-4" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-base text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Modifier le point</h3>
            <div className="flex flex-wrap gap-2">
              {CATEGORIES_OSTEO.map(c => (
                <button key={c.key} onClick={() => setPendingCat(c.key)}
                  className="px-3 py-1.5 rounded-full text-xs font-medium border transition-colors"
                  style={{
                    fontFamily: 'Galey, sans-serif',
                    background: pendingCat === c.key ? c.color : `${c.color}1F`,
                    color: pendingCat === c.key ? 'white' : '#374151',
                    borderColor: c.color,
                  }}>
                  {c.label}
                </button>
              ))}
            </div>
            <textarea value={pendingNote} onChange={e => setPendingNote(e.target.value)} rows={3}
              placeholder="Note (optionnel)"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-gray-50" />
            <button onClick={saveEditPoint} disabled={!pendingCat}
              className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-40 text-white font-semibold py-3 rounded-xl text-sm transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Enregistrer
            </button>
            <button onClick={() => deletePoint(selected.id)}
              className="w-full border border-red-200 text-red-500 hover:bg-red-50 font-semibold py-2.5 rounded-xl text-sm transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Supprimer ce point
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
