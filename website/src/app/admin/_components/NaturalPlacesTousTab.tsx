'use client';
// Lieux naturels : TOUS les lieux (recherche, filtres) + fiche de modification
// complète. Les policies natural_places autorisent l'admin (is_admin_uid) en
// lecture / modification / suppression.
import React, { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { ActionBtn, Badge, fmtDate } from './ui';

interface Lieu {
  id: string; nom: string | null; categorie: string | null; statut: string | null;
  adresse: string | null; lat: number | null; lng: number | null;
  description: string | null; niveau_difficulte: string | null; distance: string | null; duree: string | null;
  photo_url: string | null; photos: string[] | null;
  has_eau: boolean | null; has_parking: boolean | null; has_poubelle: boolean | null;
  has_fontaine: boolean | null; parcours_ombre: boolean | null; baignade_possible: boolean | null;
  alerte_cyano: boolean | null; alerte_cyano_statut: string | null;
  nb_avis: number | null; note_moyenne: number | null; created_at: string;
}

const CATEGORIES: Record<string, string> = { plage: '🏖️ Plage', parc: '🌿 Parc', foret: '🌲 Forêt', lac: '💧 Lac', riviere: '🏞️ Rivière' };
const STATUTS: Record<string, { label: string; color: string }> = {
  valide: { label: 'Publié', color: '#16a34a' },
  en_attente: { label: 'En attente', color: '#d97706' },
  refuse: { label: 'Refusé', color: '#dc2626' },
};
const EQUIPEMENTS: [keyof Lieu, string][] = [
  ['has_parking', 'Parking'], ['has_eau', "Point d'eau"], ['has_fontaine', 'Fontaine'],
  ['has_poubelle', 'Poubelles'], ['parcours_ombre', 'Parcours ombragé'], ['baignade_possible', 'Baignade possible'],
];
const PAR_PAGE = 30;
const COLONNES = 'id, nom, categorie, statut, adresse, lat, lng, description, niveau_difficulte, distance, duree, photo_url, photos, has_eau, has_parking, has_poubelle, has_fontaine, parcours_ombre, baignade_possible, alerte_cyano, alerte_cyano_statut, nb_avis, note_moyenne, created_at';

export default function NaturalPlacesTousTab() {
  const [lieux, setLieux] = useState<Lieu[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [recherche, setRecherche] = useState('');
  const [categorie, setCategorie] = useState('');
  const [statut, setStatut] = useState('');
  const [loading, setLoading] = useState(true);
  const [edition, setEdition] = useState<Lieu | null>(null);
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    let q = supabase.from('natural_places').select(COLONNES, { count: 'exact' });
    const r = recherche.trim();
    if (r) q = q.or(`nom.ilike.%${r.replace(/[%,()]/g, ' ')}%,adresse.ilike.%${r.replace(/[%,()]/g, ' ')}%`);
    if (categorie) q = q.eq('categorie', categorie);
    if (statut) q = q.eq('statut', statut);
    const { data, count, error } = await q.order('nom', { ascending: true })
      .range(page * PAR_PAGE, page * PAR_PAGE + PAR_PAGE - 1);
    if (error) setErreur(error.message);
    setLieux((data ?? []) as Lieu[]);
    setTotal(count ?? 0);
    setLoading(false);
  }, [recherche, categorie, statut, page]);

  useEffect(() => { const t = setTimeout(() => { void load(); }, 250); return () => clearTimeout(t); }, [load]);

  const maj = (patch: Partial<Lieu>) => setEdition((e) => (e ? { ...e, ...patch } : e));

  async function enregistrer() {
    if (!edition) return;
    if (!edition.nom?.trim()) { setErreur('Le nom est requis'); return; }
    setSaving(true); setErreur(null);
    const { id, nb_avis: _a, note_moyenne: _n, created_at: _c, ...champs } = edition;
    const { error } = await supabase.from('natural_places').update({
      ...champs,
      nom: edition.nom.trim(),
      lat: edition.lat === null || Number.isNaN(Number(edition.lat)) ? null : Number(edition.lat),
      lng: edition.lng === null || Number.isNaN(Number(edition.lng)) ? null : Number(edition.lng),
      updated_at: new Date().toISOString(),
    }).eq('id', id);
    setSaving(false);
    if (error) { setErreur(error.message); return; }
    setEdition(null);
    void load();
  }

  async function supprimer(l: Lieu) {
    if (!confirm(`Supprimer définitivement « ${l.nom ?? ''} » (avis et photos compris) ?`)) return;
    const { error } = await supabase.from('natural_places').delete().eq('id', l.id);
    if (error) { alert(error.message); return; }
    setEdition(null);
    void load();
  }

  async function ajouterPhoto(file: File) {
    if (!edition) return;
    const ext = file.name.split('.').pop()?.toLowerCase() || 'jpg';
    const path = `natural_places/${edition.id}/admin_${Date.now()}.${ext}`;
    const { error } = await supabase.storage.from('media').upload(path, file, { contentType: file.type });
    if (error) { setErreur(error.message); return; }
    const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
    maj({ photos: [...(edition.photos ?? []), url], photo_url: edition.photo_url || url });
  }

  const pages = Math.max(1, Math.ceil(total / PAR_PAGE));
  const input = 'w-full mt-1 px-3 py-2 rounded-xl border text-sm';

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        <input value={recherche} onChange={(e) => { setRecherche(e.target.value); setPage(0); }}
          placeholder="Rechercher un nom ou une adresse…" className="flex-1 min-w-[200px] px-3 py-2 rounded-xl border text-sm" />
        <select value={categorie} onChange={(e) => { setCategorie(e.target.value); setPage(0); }} className="px-3 py-2 rounded-xl border text-sm">
          <option value="">Toutes catégories</option>
          {Object.entries(CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select value={statut} onChange={(e) => { setStatut(e.target.value); setPage(0); }} className="px-3 py-2 rounded-xl border text-sm">
          <option value="">Tous statuts</option>
          {Object.entries(STATUTS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select>
      </div>
      <p className="text-xs text-gray-400">{total} lieu{total > 1 ? 'x' : ''}</p>
      {erreur && !edition && <p className="text-sm text-red-600">{erreur}</p>}

      {loading ? <p className="text-sm text-gray-400">Chargement…</p> : (
        <div className="space-y-2">
          {lieux.map((l) => {
            const st = STATUTS[l.statut ?? ''] ?? { label: l.statut ?? '—', color: '#64748b' };
            return (
              <button key={l.id} onClick={() => { setErreur(null); setEdition({ ...l }); }}
                className="w-full bg-white rounded-2xl p-3 shadow-sm flex items-center gap-3 text-left hover:ring-2 hover:ring-[#0C5C6C33]">
                <div className="w-14 h-14 rounded-lg overflow-hidden bg-gray-100 shrink-0">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {(l.photo_url || l.photos?.[0]) && <img src={l.photo_url || l.photos![0]} alt="" className="w-full h-full object-cover" />}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-gray-800 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{l.nom ?? '—'}</p>
                  <p className="text-xs text-gray-500 truncate">{CATEGORIES[l.categorie ?? ''] ?? l.categorie} · {l.adresse ?? 'sans adresse'}</p>
                </div>
                {l.alerte_cyano && <Badge label="⚠️ Cyano" color="#d97706" />}
                <Badge label={st.label} color={st.color} />
              </button>
            );
          })}
        </div>
      )}

      {pages > 1 && (
        <div className="flex items-center justify-center gap-3">
          <ActionBtn label="← Précédent" color="#0C5C6C" onClick={() => setPage((p) => p - 1)} disabled={page === 0} />
          <span className="text-sm text-gray-500">Page {page + 1} / {pages}</span>
          <ActionBtn label="Suivant →" color="#0C5C6C" onClick={() => setPage((p) => p + 1)} disabled={page + 1 >= pages} />
        </div>
      )}

      {edition && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-start justify-center overflow-y-auto p-4" onClick={() => !saving && setEdition(null)}>
          <div className="bg-white rounded-2xl p-5 w-full max-w-2xl space-y-4 my-8" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <p className="font-bold text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>Modifier le lieu</p>
              <span className="text-xs text-gray-400">créé le {fmtDate(edition.created_at)} · {edition.nb_avis ?? 0} avis{edition.note_moyenne ? ` · ⭐ ${Number(edition.note_moyenne).toFixed(1)}` : ''}</span>
            </div>

            <label className="block"><span className="text-xs text-gray-500">Nom *</span>
              <input value={edition.nom ?? ''} onChange={(e) => maj({ nom: e.target.value })} className={input} /></label>
            <div className="grid grid-cols-2 gap-3">
              <label className="block"><span className="text-xs text-gray-500">Catégorie</span>
                <select value={edition.categorie ?? ''} onChange={(e) => maj({ categorie: e.target.value })} className={input}>
                  {Object.entries(CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select></label>
              <label className="block"><span className="text-xs text-gray-500">Statut</span>
                <select value={edition.statut ?? ''} onChange={(e) => maj({ statut: e.target.value })} className={input}>
                  {Object.entries(STATUTS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                </select></label>
            </div>
            <label className="block"><span className="text-xs text-gray-500">Adresse</span>
              <input value={edition.adresse ?? ''} onChange={(e) => maj({ adresse: e.target.value })} className={input} /></label>
            <div className="grid grid-cols-2 gap-3">
              <label className="block"><span className="text-xs text-gray-500">Latitude</span>
                <input type="number" step="any" value={edition.lat ?? ''} onChange={(e) => maj({ lat: e.target.value === '' ? null : Number(e.target.value) })} className={input} /></label>
              <label className="block"><span className="text-xs text-gray-500">Longitude</span>
                <input type="number" step="any" value={edition.lng ?? ''} onChange={(e) => maj({ lng: e.target.value === '' ? null : Number(e.target.value) })} className={input} /></label>
            </div>
            {edition.lat != null && edition.lng != null && (
              <a href={`https://www.google.com/maps?q=${edition.lat},${edition.lng}`} target="_blank" rel="noopener noreferrer"
                className="text-xs text-[#0C5C6C] underline">Voir sur la carte ↗</a>
            )}
            <label className="block"><span className="text-xs text-gray-500">Description</span>
              <textarea rows={4} value={edition.description ?? ''} onChange={(e) => maj({ description: e.target.value })} className={input} /></label>
            <div className="grid grid-cols-3 gap-3">
              <label className="block"><span className="text-xs text-gray-500">Difficulté</span>
                <select value={edition.niveau_difficulte ?? ''} onChange={(e) => maj({ niveau_difficulte: e.target.value || null })} className={input}>
                  <option value="">—</option><option value="facile">Facile</option><option value="moyen">Moyen</option><option value="difficile">Difficile</option>
                </select></label>
              <label className="block"><span className="text-xs text-gray-500">Distance</span>
                <input value={edition.distance ?? ''} onChange={(e) => maj({ distance: e.target.value || null })} placeholder="ex. 3 km" className={input} /></label>
              <label className="block"><span className="text-xs text-gray-500">Durée</span>
                <input value={edition.duree ?? ''} onChange={(e) => maj({ duree: e.target.value || null })} placeholder="ex. 1 h" className={input} /></label>
            </div>

            <div>
              <p className="text-xs text-gray-500 mb-1">Équipements</p>
              <div className="flex flex-wrap gap-2">
                {EQUIPEMENTS.map(([k, label]) => (
                  <label key={k} className={`px-3 py-1.5 rounded-xl border text-sm cursor-pointer ${edition[k] ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600'}`}>
                    <input type="checkbox" className="hidden" checked={!!edition[k]} onChange={(e) => maj({ [k]: e.target.checked } as Partial<Lieu>)} />
                    {label}
                  </label>
                ))}
              </div>
            </div>

            <div>
              <p className="text-xs text-gray-500 mb-1">Photos (cliquer sur ★ pour la photo principale)</p>
              <div className="flex flex-wrap gap-2">
                {(edition.photos ?? []).map((u) => (
                  <div key={u} className={`relative w-24 h-24 rounded-lg overflow-hidden border-2 ${edition.photo_url === u ? 'border-amber-500' : 'border-transparent'}`}>
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={u} alt="" className="w-full h-full object-cover" />
                    <button onClick={() => maj({ photo_url: u })} title="Photo principale"
                      className="absolute top-1 left-1 bg-white/90 rounded-full w-6 h-6 text-xs">★</button>
                    <button onClick={() => {
                      const photos = (edition.photos ?? []).filter((x) => x !== u);
                      maj({ photos, photo_url: edition.photo_url === u ? (photos[0] ?? null) : edition.photo_url });
                    }} title="Retirer" className="absolute top-1 right-1 bg-white/90 rounded-full w-6 h-6 text-xs text-red-600">✕</button>
                  </div>
                ))}
                <label className="w-24 h-24 rounded-lg border-2 border-dashed flex items-center justify-center text-gray-400 text-xs cursor-pointer text-center">
                  + Ajouter
                  <input type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) void ajouterPhoto(f); e.target.value = ''; }} />
                </label>
              </div>
            </div>

            {edition.alerte_cyano && (
              <div className="flex items-center justify-between bg-amber-50 rounded-xl p-3">
                <span className="text-sm text-amber-800">⚠️ Alerte cyanobactéries ({edition.alerte_cyano_statut ?? 'suspectée'})</span>
                <ActionBtn label="Lever l'alerte" color="#d97706" onClick={() => maj({ alerte_cyano: false, alerte_cyano_statut: null })} />
              </div>
            )}

            {erreur && <p className="text-sm text-red-600">{erreur}</p>}
            <div className="flex justify-between pt-2">
              <ActionBtn label="Supprimer le lieu" color="#dc2626" onClick={() => supprimer(edition)} disabled={saving} />
              <div className="flex gap-2">
                <ActionBtn label="Annuler" color="#64748b" onClick={() => setEdition(null)} disabled={saving} />
                <ActionBtn label={saving ? 'Enregistrement…' : 'Enregistrer'} color="#16a34a" onClick={enregistrer} disabled={saving} />
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
