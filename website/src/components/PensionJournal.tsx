'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface Update {
  id: string;
  photo_url?: string | null;
  note?: string | null;
  created_at: string;
}

export function PensionJournal({ animalId, pensionEntreeId, animalNom, proUid, readOnly = false, onClose }: {
  animalId?: string | null;
  pensionEntreeId?: string | null;
  animalNom: string;
  proUid?: string;
  readOnly?: boolean;
  onClose: () => void;
}) {
  const [updates, setUpdates] = useState<Update[]>([]);
  const [loading, setLoading] = useState(true);
  const [note, setNote] = useState('');
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [posting, setPosting] = useState(false);

  async function load() {
    setLoading(true);
    let q = supabase.from('pension_updates').select('id, photo_url, note, created_at');
    q = pensionEntreeId ? q.eq('pension_entree_id', pensionEntreeId) : q.eq('animal_id', animalId ?? '');
    const { data } = await q.order('created_at', { ascending: false });
    setUpdates((data ?? []) as Update[]);
    setLoading(false);
  }

  useEffect(() => { load(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  async function post() {
    if (!proUid || (!note.trim() && !photoFile)) return;
    setPosting(true);
    try {
      let photoUrl: string | null = null;
      if (photoFile) {
        const path = `pension_updates/${proUid}_${Date.now()}.jpg`;
        const { error: upErr } = await supabase.storage.from('media').upload(path, photoFile, { upsert: true });
        if (!upErr) {
          photoUrl = supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
        }
      }
      await supabase.from('pension_updates').insert({
        pension_entree_id: pensionEntreeId ?? null,
        animal_id: animalId ?? null,
        pro_uid: proUid,
        photo_url: photoUrl,
        note: note.trim() || null,
      });
      setNote('');
      setPhotoFile(null);
      await load();
    } finally {
      setPosting(false);
    }
  }

  async function del(id: string) {
    await supabase.from('pension_updates').delete().eq('id', id);
    load();
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end md:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[85vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between p-5 border-b border-gray-100">
          <h3 className="font-bold font-galey text-[#0C5C6C]">Journal — {animalNom}</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
        </div>

        <div className="overflow-y-auto flex-1 p-4">
          {loading ? (
            <div className="flex justify-center py-10">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-700" />
            </div>
          ) : updates.length === 0 ? (
            <p className="text-center text-gray-400 font-galey py-10">
              {readOnly ? 'Aucune nouvelle pour l\'instant' : 'Partagez une première nouvelle'}
            </p>
          ) : (
            <div className="space-y-3">
              {updates.map(u => (
                <div key={u.id} className="rounded-xl border border-gray-100 overflow-hidden shadow-sm">
                  {u.photo_url && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={u.photo_url} alt="" className="w-full h-48 object-cover" />
                  )}
                  <div className="p-3">
                    {u.note && <p className="text-sm font-galey text-gray-800 mb-1">{u.note}</p>}
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-galey text-gray-400">
                        {new Date(u.created_at).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}
                      </span>
                      {!readOnly && (
                        <button onClick={() => del(u.id)} className="text-xs text-red-400 hover:text-red-600">Supprimer</button>
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {!readOnly && (
          <div className="border-t border-gray-100 p-4">
            {photoFile && (
              <div className="mb-2 flex items-center gap-2">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={URL.createObjectURL(photoFile)} alt="" className="w-14 h-14 rounded-lg object-cover" />
                <button onClick={() => setPhotoFile(null)} className="text-xs text-red-500">Retirer</button>
              </div>
            )}
            <div className="flex items-center gap-2">
              <label className="cursor-pointer text-[#0C5C6C]">
                📷
                <input type="file" accept="image/*" className="hidden"
                  onChange={e => setPhotoFile(e.target.files?.[0] ?? null)} />
              </label>
              <input value={note} onChange={e => setNote(e.target.value)}
                placeholder="Une petite note pour le propriétaire…"
                className="flex-1 px-3 py-2 border border-gray-200 rounded-full text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
              <button onClick={post} disabled={posting || (!note.trim() && !photoFile)}
                className="text-[#6E9E57] disabled:opacity-40 disabled:cursor-not-allowed">
                {posting ? '…' : '➤'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
