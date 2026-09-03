'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const CATEGORIES: Record<string, string> = {
  rappel: 'Rappel', laisse: 'Marche en laisse', proprete: 'Propreté', aboiements: 'Aboiements',
  destruction: 'Destruction', socialisation_chien: 'Socialisation chiens', socialisation_humain: 'Socialisation humains',
  manipulation: 'Manipulation / soins', solitude: 'Solitude', agressivite: 'Agressivité', peurs: 'Peurs', autre: 'Autre',
};
const ORANGE = '#EF6C00';

interface Exercice {
  id: string; titre: string; description: string | null;
  media: { type: string; url: string }[]; categorie: string | null;
}

export default function BibliothequeExercicesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [exercices, setExercices] = useState<Exercice[]>([]);
  const [busy, setBusy] = useState(true);
  const [form, setForm] = useState<{ id?: string; titre: string; description: string; categorie: string; media: { type: string; url: string }[] } | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!user?.uid) return;
    setBusy(true);
    const { data } = await supabase.from('exercices_bibliotheque')
      .select('id, titre, description, media, categorie')
      .eq('pro_uid', user.uid).eq('actif', true).order('created_at', { ascending: false });
    setExercices((data ?? []) as Exercice[]);
    setBusy(false);
  }, [user]);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => { load(); }, [load]);

  async function uploadFiles(files: FileList): Promise<{ type: string; url: string }[]> {
    const out: { type: string; url: string }[] = [];
    for (const f of Array.from(files)) {
      const isVideo = f.type.startsWith('video/');
      const ext = f.name.split('.').pop() ?? (isVideo ? 'mp4' : 'jpg');
      const path = `exercices/${user!.uid}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
      const { error } = await supabase.storage.from('petsmatch').upload(path, f, { upsert: true });
      if (!error) {
        const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
        out.push({ type: isVideo ? 'video' : 'image', url: pub.publicUrl });
      }
    }
    return out;
  }

  async function save() {
    if (!form || !form.titre.trim() || !user?.uid) return;
    setSaving(true);
    try {
      const payload = {
        titre: form.titre.trim(),
        description: form.description.trim() || null,
        categorie: form.categorie || null,
        media: form.media,
      };
      if (form.id) {
        await supabase.from('exercices_bibliotheque').update(payload).eq('id', form.id);
      } else {
        await supabase.from('exercices_bibliotheque').insert({
          ...payload, pro_uid: user.uid, pro_profile_id: activeProfileId || null,
        });
      }
      setForm(null);
      await load();
    } finally {
      setSaving(false);
    }
  }

  async function remove(id: string) {
    await supabase.from('exercices_bibliotheque').update({ actif: false }).eq('id', id);
    await load();
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Bibliothèque d&apos;exercices</h1>
        <button onClick={() => setForm({ titre: '', description: '', categorie: '', media: [] })}
          className="text-white rounded-xl px-3 py-2 text-sm font-semibold" style={{ background: ORANGE }}>+ Exercice</button>
      </div>
      <p className="text-sm text-gray-500 mb-4">Créez vos exercices une fois (texte + photos/vidéos), attribuez-les ensuite à vos familles depuis la fiche d&apos;un animal suivi.</p>

      {form && (
        <div className="border rounded-2xl p-4 mb-4 space-y-3" style={{ borderColor: `${ORANGE}55` }}>
          <input value={form.titre} onChange={e => setForm({ ...form, titre: e.target.value })}
            placeholder="Titre — ex : Le rappel au sifflet"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          <textarea value={form.description} onChange={e => setForm({ ...form, description: e.target.value })}
            rows={4} placeholder="Déroulé : comment faire l'exercice, matériel, durée, points d'attention…"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
          <div className="flex flex-wrap gap-1.5">
            {Object.entries(CATEGORIES).map(([k, v]) => (
              <button key={k} type="button" onClick={() => setForm({ ...form, categorie: form.categorie === k ? '' : k })}
                className={`text-xs px-2.5 py-1 rounded-full border ${form.categorie === k ? 'text-white' : 'border-gray-200 text-gray-500'}`}
                style={form.categorie === k ? { background: ORANGE, borderColor: ORANGE } : {}}>{v}</button>
            ))}
          </div>
          <div className="flex flex-wrap gap-2">
            {form.media.map((m, i) => (
              <div key={i} className="relative w-16 h-16 rounded-lg bg-gray-100 overflow-hidden">
                {m.type === 'video'
                  ? <div className="w-full h-full flex items-center justify-center text-gray-400">▶</div>
                  /* eslint-disable-next-line @next/next/no-img-element */
                  : <img src={m.url} alt="" className="w-full h-full object-cover" />}
                <button onClick={() => setForm({ ...form, media: form.media.filter((_, j) => j !== i) })}
                  className="absolute top-0 right-0 bg-black/50 text-white text-xs w-4 h-4 leading-none rounded-bl">×</button>
              </div>
            ))}
            <label className="w-16 h-16 rounded-lg border-2 border-dashed border-gray-200 flex items-center justify-center text-gray-400 cursor-pointer text-2xl">
              +
              <input type="file" accept="image/*,video/*" multiple className="hidden"
                onChange={async e => {
                  if (!e.target.files?.length) return;
                  const uploaded = await uploadFiles(e.target.files);
                  setForm(f => f ? { ...f, media: [...f.media, ...uploaded] } : f);
                  e.target.value = '';
                }} />
            </label>
          </div>
          <div className="flex gap-2">
            <button onClick={() => setForm(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
            <button onClick={save} disabled={saving || !form.titre.trim()}
              className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: ORANGE }}>
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
          </div>
        </div>
      )}

      {busy ? (
        <p className="text-sm text-gray-400">Chargement…</p>
      ) : exercices.length === 0 ? (
        <p className="text-sm text-gray-400">Bibliothèque vide.</p>
      ) : (
        <div className="space-y-2">
          {exercices.map(e => (
            <div key={e.id} className="border border-gray-100 rounded-xl p-3 flex items-start gap-3">
              {e.media[0] && (
                <div className="w-12 h-12 shrink-0 rounded-lg bg-gray-100 overflow-hidden">
                  {e.media[0].type === 'video'
                    ? <div className="w-full h-full flex items-center justify-center text-gray-400">▶</div>
                    /* eslint-disable-next-line @next/next/no-img-element */
                    : <img src={e.media[0].url} alt="" className="w-full h-full object-cover" />}
                </div>
              )}
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-[#1F2A2E]">{e.titre}</p>
                {e.categorie && CATEGORIES[e.categorie] && <p className="text-xs text-gray-500">{CATEGORIES[e.categorie]}</p>}
                {e.description && <p className="text-xs text-gray-600 mt-0.5 line-clamp-2">{e.description}</p>}
              </div>
              <div className="flex gap-1 shrink-0">
                <button onClick={() => setForm({ id: e.id, titre: e.titre, description: e.description ?? '', categorie: e.categorie ?? '', media: e.media })}
                  className="text-gray-300 hover:text-gray-500">✏️</button>
                <button onClick={() => remove(e.id)} className="text-gray-300 hover:text-red-400">🗑</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
