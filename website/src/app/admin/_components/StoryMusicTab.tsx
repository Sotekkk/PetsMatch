'use client';

import React, { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

// Bibliothèque musicale des Stories Pets Social — musique maison
// uniquement (pas d'import libre côté utilisateur), donc chaque morceau
// ajouté ici doit avoir été vérifié comme réellement libre de droits AVANT
// l'upload. Sources recommandées :
//  • Pixabay Music (pixabay.com/music) — licence "Content License",
//    gratuite, aucune attribution requise. Le plus simple.
//  • Incompetech / Kevin MacLeod (incompetech.com) — CC-BY, attribution
//    obligatoire : renseigner le champ Attribution ci-dessous.
// Jamais de morceau connu (radio, streaming, film…) même "juste pour tester".

interface Track {
  id: string;
  titre: string;
  artiste: string | null;
  url_audio: string;
  duree_secondes: number | null;
  licence: string;
  attribution: string | null;
  actif: boolean;
  created_at: string;
}

const LICENCES = ['CC0', 'CC-BY', 'libre_verifie'] as const;

export default function StoryMusicTab() {
  const [tracks, setTracks] = useState<Track[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [form, setForm] = useState({ titre: '', artiste: '', licence: 'CC0' as string, attribution: '' });
  const [file, setFile] = useState<File | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    const { data } = await supabase.from('story_music_tracks').select('*').order('created_at', { ascending: false });
    setTracks((data ?? []) as Track[]);
    setLoading(false);
  }
  useEffect(() => { load(); }, []);

  async function getAudioDuration(f: File): Promise<number | null> {
    return new Promise(resolve => {
      const audio = document.createElement('audio');
      audio.preload = 'metadata';
      audio.onloadedmetadata = () => { resolve(Math.round(audio.duration) || null); URL.revokeObjectURL(audio.src); };
      audio.onerror = () => resolve(null);
      audio.src = URL.createObjectURL(f);
    });
  }

  async function addTrack() {
    if (!file || !form.titre.trim()) { setError('Titre et fichier audio requis.'); return; }
    setUploading(true);
    setError(null);
    try {
      const duree = await getAudioDuration(file);
      const ext = file.name.split('.').pop() || 'mp3';
      const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
      const { error: upErr } = await supabase.storage.from('story_music').upload(path, file, { contentType: file.type || 'audio/mpeg' });
      if (upErr) throw upErr;
      const url = supabase.storage.from('story_music').getPublicUrl(path).data.publicUrl;
      const { error: insErr } = await supabase.from('story_music_tracks').insert({
        titre: form.titre.trim(),
        artiste: form.artiste.trim() || null,
        url_audio: url,
        duree_secondes: duree,
        licence: form.licence,
        attribution: form.attribution.trim() || null,
        actif: true,
      });
      if (insErr) throw insErr;
      setForm({ titre: '', artiste: '', licence: 'CC0', attribution: '' });
      setFile(null);
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erreur lors de l\'ajout.');
    } finally {
      setUploading(false);
    }
  }

  async function toggleActif(t: Track) {
    await supabase.from('story_music_tracks').update({ actif: !t.actif }).eq('id', t.id);
    load();
  }

  async function removeTrack(t: Track) {
    if (!confirm(`Supprimer « ${t.titre} » ? Les stories déjà publiées avec ce morceau garderont juste une référence cassée.`)) return;
    await supabase.from('story_music_tracks').delete().eq('id', t.id);
    load();
  }

  return (
    <div className="space-y-6">
      <section>
        <h2 className="font-bold text-[#1F2A2E] text-lg mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          🎵 Bibliothèque musicale — Stories Pets Social
        </h2>
        <p className="text-sm text-gray-500 mb-4">
          Musique maison uniquement : les utilisateurs choisissent dans cette liste, ils ne peuvent pas importer un morceau externe.
          Vérifiez la licence (Pixabay Music, Incompetech…) <strong>avant</strong> d&apos;ajouter un fichier.
        </p>

        <div className="bg-white rounded-2xl border border-gray-100 p-5 space-y-3 mb-6">
          <p className="font-bold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Ajouter un morceau</p>
          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="text-xs text-gray-400">Titre</span>
              <input className="w-full border border-gray-200 rounded-xl px-3 py-1.5 text-sm mt-0.5"
                value={form.titre} onChange={e => setForm({ ...form, titre: e.target.value })} />
            </label>
            <label className="block">
              <span className="text-xs text-gray-400">Artiste</span>
              <input className="w-full border border-gray-200 rounded-xl px-3 py-1.5 text-sm mt-0.5"
                value={form.artiste} onChange={e => setForm({ ...form, artiste: e.target.value })} />
            </label>
            <label className="block">
              <span className="text-xs text-gray-400">Licence</span>
              <select className="w-full border border-gray-200 rounded-xl px-3 py-1.5 text-sm mt-0.5"
                value={form.licence} onChange={e => setForm({ ...form, licence: e.target.value })}>
                {LICENCES.map(l => <option key={l} value={l}>{l}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs text-gray-400">Attribution (si CC-BY)</span>
              <input className="w-full border border-gray-200 rounded-xl px-3 py-1.5 text-sm mt-0.5"
                placeholder="Ex : Kevin MacLeod (incompetech.com)"
                value={form.attribution} onChange={e => setForm({ ...form, attribution: e.target.value })} />
            </label>
          </div>
          <label className="block">
            <span className="text-xs text-gray-400">Fichier audio (mp3)</span>
            <input type="file" accept="audio/*" className="w-full text-sm mt-0.5"
              onChange={e => setFile(e.target.files?.[0] ?? null)} />
          </label>
          {error && <p className="text-xs text-red-500">{error}</p>}
          <button onClick={addTrack} disabled={uploading}
            className="bg-[#2E7D5E] hover:bg-[#256b4f] disabled:opacity-50 text-white text-sm font-semibold px-5 py-2 rounded-xl transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {uploading ? 'Envoi…' : '➕ Ajouter'}
          </button>
        </div>

        {loading ? (
          <p className="text-center text-gray-400 py-6">Chargement…</p>
        ) : tracks.length === 0 ? (
          <p className="text-center text-gray-400 py-6">Aucun morceau pour le moment.</p>
        ) : (
          <div className="flex flex-col gap-3">
            {tracks.map(t => (
              <div key={t.id} className={`bg-white rounded-2xl border p-4 flex items-center gap-4 ${t.actif ? 'border-gray-100' : 'border-dashed border-gray-300 opacity-60'}`}>
                <audio controls src={t.url_audio} className="h-8 w-56 shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-[#1F2A2E] text-sm truncate">{t.titre}{t.artiste ? ` — ${t.artiste}` : ''}</p>
                  <p className="text-xs text-gray-400">
                    {t.licence}{t.attribution ? ` · ${t.attribution}` : ''}{t.duree_secondes ? ` · ${t.duree_secondes}s` : ''}
                  </p>
                </div>
                {!t.actif && <span className="text-xs bg-red-100 text-red-500 px-2 py-0.5 rounded-full shrink-0">Inactif</span>}
                <button onClick={() => toggleActif(t)}
                  className="px-3 py-1.5 border border-gray-200 text-gray-600 text-xs font-semibold rounded-xl hover:border-[#2E7D5E] hover:text-[#2E7D5E] transition-colors shrink-0">
                  {t.actif ? 'Désactiver' : 'Activer'}
                </button>
                <button onClick={() => removeTrack(t)}
                  className="px-3 py-1.5 border border-gray-200 text-red-500 text-xs font-semibold rounded-xl hover:border-red-400 transition-colors shrink-0">
                  🗑️
                </button>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
