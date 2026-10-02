'use client';
// Publicités intercalées dans les stories (ex-onglet « Pubs stories » de l'appli).
import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { supabase } from '@/lib/supabase';
import { ActionBtn, Badge, fmtDate } from './ui';

interface Pub {
  id: string; annonceur_nom: string; media_url: string; media_type: string;
  cta_label: string; lien_url: string | null; actif: boolean; date_debut: string;
  date_fin: string | null; poids: number; impressions: number; clics: number; created_at: string;
}
const VIDE = { annonceur_nom: '', cta_label: 'En savoir plus', lien_url: '', poids: '1', date_fin: '' };

export default function PubsStoriesTab() {
  const [pubs, setPubs] = useState<Pub[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const [edition, setEdition] = useState<Pub | 'nouvelle' | null>(null);
  const [form, setForm] = useState(VIDE);
  const [fichier, setFichier] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setErreur(null);
    const r = await apiFetch('/api/admin/moderation?type=pubs');
    const j = await r.json().catch(() => ({}));
    if (!r.ok) setErreur(j.error ?? 'Erreur de chargement');
    setPubs(j.items ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function post(body: Record<string, unknown>) {
    const r = await apiFetch('/api/admin/moderation', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error ?? 'Erreur');
  }

  function ouvrir(p: Pub | 'nouvelle') {
    setEdition(p); setFichier(null); setErreur(null);
    setForm(p === 'nouvelle' ? VIDE : {
      annonceur_nom: p.annonceur_nom, cta_label: p.cta_label, lien_url: p.lien_url ?? '',
      poids: String(p.poids ?? 1), date_fin: p.date_fin ? p.date_fin.slice(0, 10) : '',
    });
  }

  async function enregistrer() {
    if (!form.annonceur_nom.trim()) { setErreur("Nom de l'annonceur requis"); return; }
    const existante = edition !== 'nouvelle' ? edition : null;
    if (!fichier && !existante?.media_url) { setErreur('Ajoutez une image ou une vidéo'); return; }
    setSaving(true); setErreur(null);
    try {
      let media_url = existante?.media_url ?? '';
      let media_type = existante?.media_type ?? 'photo';
      if (fichier) {
        media_type = fichier.type.startsWith('video/') ? 'video' : 'photo';
        const ext = fichier.name.split('.').pop()?.toLowerCase() || (media_type === 'video' ? 'mp4' : 'jpg');
        const path = `ads/${Date.now()}.${ext}`;
        const { error } = await supabase.storage.from('media').upload(path, fichier, { contentType: fichier.type });
        if (error) throw new Error(error.message);
        media_url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
      }
      await post({
        action: 'pub_enregistrer', id: existante?.id,
        data: {
          annonceur_nom: form.annonceur_nom.trim(), media_url, media_type,
          cta_label: form.cta_label.trim() || 'En savoir plus',
          lien_url: form.lien_url.trim() || null,
          poids: parseInt(form.poids, 10) || 1,
          date_fin: form.date_fin ? new Date(`${form.date_fin}T23:59:59`).toISOString() : null,
        },
      });
      setEdition(null);
      void load();
    } catch (e) {
      setErreur((e as Error).message);
    } finally {
      setSaving(false);
    }
  }

  const champ = (label: string, cle: keyof typeof VIDE, type = 'text') => (
    <label className="block">
      <span className="text-xs text-gray-500">{label}</span>
      <input type={type} value={form[cle]} onChange={(e) => setForm({ ...form, [cle]: e.target.value })}
        className="w-full mt-1 px-3 py-2 rounded-xl border text-sm" />
    </label>
  );

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-500">Une pub est intercalée toutes les 5 stories, tirée au sort selon son poids.</p>
        <ActionBtn label="+ Nouvelle pub" color="#0C5C6C" onClick={() => ouvrir('nouvelle')} />
      </div>
      {erreur && !edition && <p className="text-sm text-red-600">{erreur}</p>}

      {edition && (
        <div className="bg-white rounded-2xl p-4 shadow-sm space-y-3 border-2 border-[#0C5C6C33]">
          <p className="font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            {edition === 'nouvelle' ? 'Nouvelle pub' : `Modifier — ${edition.annonceur_nom}`}
          </p>
          {champ("Nom de l'annonceur *", 'annonceur_nom')}
          <label className="block">
            <span className="text-xs text-gray-500">Image ou vidéo {edition !== 'nouvelle' && '(laisser vide pour garder l\'actuelle)'}</span>
            <input type="file" accept="image/*,video/mp4,video/quicktime,video/webm"
              onChange={(e) => setFichier(e.target.files?.[0] ?? null)} className="block mt-1 text-sm" />
          </label>
          <div className="grid grid-cols-2 gap-3">
            {champ('Texte du bouton', 'cta_label')}
            {champ('Lien (https://…)', 'lien_url')}
            {champ('Poids (fréquence relative)', 'poids', 'number')}
            {champ('Date de fin (vide = sans fin)', 'date_fin', 'date')}
          </div>
          {erreur && <p className="text-sm text-red-600">{erreur}</p>}
          <div className="flex gap-2">
            <ActionBtn label={saving ? 'Enregistrement…' : 'Enregistrer'} color="#16a34a" onClick={enregistrer} disabled={saving} />
            <ActionBtn label="Annuler" color="#64748b" onClick={() => setEdition(null)} disabled={saving} />
          </div>
        </div>
      )}

      {loading ? <p className="text-sm text-gray-400">Chargement…</p>
        : pubs.length === 0 ? <p className="text-sm text-gray-400">Aucune pub.</p>
        : pubs.map((p) => (
          <div key={p.id} className="bg-white rounded-2xl p-4 shadow-sm flex gap-4">
            <div className="w-20 h-28 rounded-lg overflow-hidden bg-gray-100 shrink-0">
              {p.media_type === 'video'
                ? <video src={p.media_url} className="w-full h-full object-cover" muted />
                // eslint-disable-next-line @next/next/no-img-element
                : <img src={p.media_url} alt="" className="w-full h-full object-cover" />}
            </div>
            <div className="flex-1 space-y-1">
              <div className="flex items-center gap-2">
                <p className="font-semibold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{p.annonceur_nom}</p>
                <Badge label={p.actif ? 'Active' : 'Inactive'} color={p.actif ? '#16a34a' : '#64748b'} />
              </div>
              <p className="text-xs text-gray-500">
                « {p.cta_label} »{p.lien_url ? ` → ${p.lien_url}` : ''} · poids {p.poids}
                · du {fmtDate(p.date_debut)}{p.date_fin ? ` au ${fmtDate(p.date_fin)}` : ' (sans fin)'}
              </p>
              <p className="text-xs text-gray-500">{p.impressions} impressions · {p.clics} clics
                {p.impressions > 0 ? ` · ${((p.clics / p.impressions) * 100).toFixed(1)} % de clics` : ''}</p>
              <div className="flex gap-2 pt-1">
                <ActionBtn label={p.actif ? 'Désactiver' : 'Activer'} color={p.actif ? '#ea580c' : '#16a34a'}
                  onClick={() => post({ action: 'pub_activer', id: p.id, actif: !p.actif }).then(load, (e) => alert(e.message))} />
                <ActionBtn label="Modifier" color="#0C5C6C" onClick={() => ouvrir(p)} />
                <ActionBtn label="Supprimer" color="#dc2626" onClick={() => {
                  if (confirm(`Supprimer la pub « ${p.annonceur_nom} » ?`)) post({ action: 'pub_supprimer', id: p.id }).then(load, (e) => alert(e.message));
                }} />
              </div>
            </div>
          </div>
        ))}
    </div>
  );
}
