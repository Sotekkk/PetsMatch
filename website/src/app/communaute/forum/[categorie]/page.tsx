'use client';

import { useState, useEffect, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

const CAT_INFO: Record<string, { label: string; emoji: string }> = {
  sante:       { label: 'Santé',         emoji: '🏥' },
  alimentation:{ label: 'Alimentation',  emoji: '🍖' },
  education:   { label: 'Éducation',     emoji: '🎓' },
  elevage:     { label: 'Élevage',       emoji: '🐣' },
  bien_etre:   { label: 'Bien-être',     emoji: '💆' },
  general:     { label: 'Général',       emoji: '💬' },
};

interface Sujet {
  id: string; titre: string; contenu: string;
  auteur_uid: string; epingle: boolean; created_at: string;
}
interface Reponse {
  id: string; sujet_id: string; auteur_uid: string; contenu: string; created_at: string;
}

function fmtDate(iso: string) {
  try {
    const dt = new Date(iso);
    const diff = Math.floor((Date.now() - dt.getTime()) / 1000);
    if (diff < 3600) return `Il y a ${Math.floor(diff / 60)} min`;
    if (diff < 86400) return `Il y a ${Math.floor(diff / 3600)}h`;
    if (diff < 604800) return `Il y a ${Math.floor(diff / 86400)}j`;
    return dt.toLocaleDateString('fr-FR');
  } catch { return ''; }
}

export default function ForumCategoriePage() {
  const { categorie } = useParams<{ categorie: string }>();
  const router = useRouter();
  const { user } = useAuth();
  const cat = CAT_INFO[categorie] ?? { label: categorie, emoji: '💬' };

  const [sujets, setSujets] = useState<Sujet[]>([]);
  const [loading, setLoading] = useState(true);
  const [openSujet, setOpenSujet] = useState<Sujet | null>(null);
  const [reponses, setReponses] = useState<Reponse[]>([]);
  const [loadingReponses, setLoadingReponses] = useState(false);
  const [newReponse, setNewReponse] = useState('');
  const [sending, setSending] = useState(false);

  // Création
  const [showCreate, setShowCreate] = useState(false);
  const [newTitre, setNewTitre] = useState('');
  const [newContenu, setNewContenu] = useState('');
  const [saving, setSaving] = useState(false);

  const loadSujets = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase
      .from('forum_sujets')
      .select('*')
      .eq('categorie_slug', categorie)
      .order('epingle', { ascending: false })
      .order('created_at', { ascending: false });
    setSujets((data ?? []) as Sujet[]);
    setLoading(false);
  }, [categorie]);

  useEffect(() => { loadSujets(); }, [loadSujets]);

  async function openSujetDetail(sujet: Sujet) {
    setOpenSujet(sujet);
    setLoadingReponses(true);
    const { data } = await supabase.from('forum_reponses').select('*')
      .eq('sujet_id', sujet.id).order('created_at');
    setReponses((data ?? []) as Reponse[]);
    setLoadingReponses(false);
  }

  async function sendReponse() {
    if (!user?.uid || !newReponse.trim() || !openSujet) return;
    setSending(true);
    try {
      const { data } = await supabase.from('forum_reponses').insert({
        sujet_id: openSujet.id, auteur_uid: user.uid,
        contenu: newReponse.trim(), created_at: new Date().toISOString(),
      }).select().single();
      if (data) setReponses(prev => [...prev, data as Reponse]);
      setNewReponse('');
    } finally { setSending(false); }
  }

  async function createSujet() {
    if (!user?.uid || !newTitre.trim() || !newContenu.trim()) return;
    setSaving(true);
    try {
      const { data } = await supabase.from('forum_sujets').insert({
        categorie_slug: categorie, auteur_uid: user.uid,
        titre: newTitre.trim(), contenu: newContenu.trim(),
        created_at: new Date().toISOString(),
      }).select().single();
      if (data) setSujets(prev => [data as Sujet, ...prev]);
      setShowCreate(false);
      setNewTitre('');
      setNewContenu('');
    } finally { setSaving(false); }
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="bg-[#00ACC1] text-white px-4 py-8">
        <div className="max-w-2xl mx-auto">
          <button onClick={() => router.back()} className="text-white/70 hover:text-white text-sm mb-4 flex items-center gap-1">
            ← Forum
          </button>
          <div className="flex items-center gap-3">
            <span className="text-4xl">{cat.emoji}</span>
            <div>
              <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{cat.label}</h1>
              <p className="text-white/70 text-sm">{sujets.length} sujet{sujets.length !== 1 ? 's' : ''}</p>
            </div>
          </div>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6">
        {/* Bouton créer */}
        {user && (
          <button
            onClick={() => setShowCreate(true)}
            className="w-full mb-5 py-3 border-2 border-dashed border-[#00ACC1] text-[#00ACC1] rounded-2xl text-sm font-semibold hover:bg-[#E0F7FA] transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            ✏️ Créer un nouveau sujet
          </button>
        )}

        {/* Liste */}
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-2 border-[#00ACC1] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : sujets.length === 0 ? (
          <div className="text-center py-16 text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
            <p className="text-4xl mb-3">💬</p>
            <p>Aucun sujet pour l&apos;instant — lancez la discussion !</p>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {sujets.map(s => (
              <button
                key={s.id}
                onClick={() => openSujetDetail(s)}
                className={`w-full text-left bg-white rounded-2xl shadow-sm border p-4 hover:shadow-md transition-all ${s.epingle ? 'border-[#00ACC1]/40' : 'border-gray-100'}`}
              >
                <div className="flex items-start gap-2">
                  {s.epingle && <span className="text-[#00ACC1] mt-0.5">📌</span>}
                  <div className="flex-1">
                    <p className="font-bold text-[#1E2025] text-sm mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>{s.titre}</p>
                    <p className="text-xs text-gray-500 line-clamp-2" style={{ fontFamily: 'Galey, sans-serif' }}>{s.contenu}</p>
                    <p className="text-xs text-gray-400 mt-2">{fmtDate(s.created_at)}</p>
                  </div>
                  <svg className="w-4 h-4 text-gray-400 flex-shrink-0 mt-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
                  </svg>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Modal sujet + réponses */}
      {openSujet && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center">
          <div className="bg-white rounded-t-2xl w-full max-w-lg h-[85vh] flex flex-col">
            <div className="flex items-center gap-3 px-5 py-4 border-b border-gray-100">
              <button onClick={() => { setOpenSujet(null); setReponses([]); }} className="text-gray-400 hover:text-gray-600">←</button>
              <h3 className="font-bold text-[#1E2025] flex-1 text-sm line-clamp-1" style={{ fontFamily: 'Galey, sans-serif' }}>{openSujet.titre}</h3>
              <button onClick={() => { setOpenSujet(null); setReponses([]); }} className="text-gray-400 hover:text-gray-600">✕</button>
            </div>
            <div className="flex-1 overflow-y-auto p-4">
              {/* Message principal */}
              <div className="bg-[#E0F7FA] rounded-2xl p-4 mb-4">
                <p className="text-sm text-[#1E2025] leading-relaxed" style={{ fontFamily: 'Galey, sans-serif' }}>{openSujet.contenu}</p>
                <p className="text-xs text-gray-400 mt-2">{fmtDate(openSujet.created_at)}</p>
              </div>

              {/* Réponses */}
              {loadingReponses ? (
                <div className="flex justify-center py-8"><div className="w-6 h-6 border-2 border-[#00ACC1] border-t-transparent rounded-full animate-spin" /></div>
              ) : (
                <div className="flex flex-col gap-2">
                  {reponses.map(r => {
                    const isMe = r.auteur_uid === user?.uid;
                    return (
                      <div key={r.id} className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}>
                        <div className={`max-w-[78%] px-3 py-2 rounded-2xl text-sm ${isMe ? 'bg-[#E0F7FA]' : 'bg-gray-100'}`} style={{ fontFamily: 'Galey, sans-serif' }}>
                          <p className="text-[#1E2025]">{r.contenu}</p>
                          <p className="text-xs text-gray-400 mt-1">{fmtDate(r.created_at)}</p>
                        </div>
                      </div>
                    );
                  })}
                  {reponses.length === 0 && (
                    <p className="text-center text-gray-400 py-4 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
                      Soyez le premier à répondre !
                    </p>
                  )}
                </div>
              )}
            </div>
            {user && (
              <div className="border-t border-gray-100 p-3 flex gap-2">
                <input
                  value={newReponse}
                  onChange={e => setNewReponse(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && !e.shiftKey && sendReponse()}
                  placeholder="Votre réponse…"
                  className="flex-1 bg-gray-50 rounded-full px-4 py-2 text-sm focus:outline-none border border-gray-200 focus:border-[#00ACC1]"
                  style={{ fontFamily: 'Galey, sans-serif' }}
                />
                <button
                  onClick={sendReponse}
                  disabled={sending || !newReponse.trim()}
                  className="w-9 h-9 bg-[#00ACC1] rounded-full flex items-center justify-center text-white disabled:opacity-50"
                >
                  {sending ? '…' : '➤'}
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Modal créer sujet */}
      {showCreate && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4">
          <div className="bg-white rounded-2xl w-full max-w-lg">
            <div className="p-6">
              <div className="flex items-center justify-between mb-5">
                <h2 className="text-lg font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>Nouveau sujet</h2>
                <button onClick={() => setShowCreate(false)} className="text-gray-400 hover:text-gray-600">✕</button>
              </div>
              <div className="flex flex-col gap-4">
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Titre *</label>
                  <input
                    value={newTitre}
                    onChange={e => setNewTitre(e.target.value)}
                    placeholder="Titre de votre question ou discussion"
                    className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#00ACC1]"
                    style={{ fontFamily: 'Galey, sans-serif' }}
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Contenu *</label>
                  <textarea
                    value={newContenu}
                    onChange={e => setNewContenu(e.target.value)}
                    placeholder="Décrivez votre sujet en détail…"
                    rows={5}
                    className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#00ACC1] resize-none"
                    style={{ fontFamily: 'Galey, sans-serif' }}
                  />
                </div>
                <button
                  onClick={createSujet}
                  disabled={saving || !newTitre.trim() || !newContenu.trim()}
                  className="w-full py-3 bg-[#00ACC1] text-white rounded-xl font-bold text-sm disabled:opacity-50"
                  style={{ fontFamily: 'Galey, sans-serif' }}
                >
                  {saving ? 'Publication…' : 'Publier le sujet'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
