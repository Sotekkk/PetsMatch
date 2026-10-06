'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';

const inputCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
const labelCls = 'block text-sm font-semibold text-[#1F2A2E] mb-1';

export default function DemandeInfluenceurPage() {
  // La demande est rattachée au COMPTE (RLS : uid = jeton) — avant, un uid
  // fictif « web_<email> » faisait échouer l'envoi et le badge validé n'aurait
  // jamais atteint le vrai profil. Miroir appli (influencer_request_page).
  const { user, loading: authLoading } = useAuth();
  const [statutExistant, setStatutExistant] = useState<string | null>(null);
  const [chargement, setChargement] = useState(true);
  const [instagram, setInstagram] = useState('');
  const [tiktok, setTiktok]       = useState('');
  const [autre, setAutre]         = useState('');
  const [message, setMessage]     = useState('');
  const [email, setEmail]         = useState('');
  const [pseudo, setPseudo]       = useState('');
  const [files, setFiles]         = useState<File[]>([]);
  const [loading, setLoading]     = useState(false);
  const [sent, setSent]           = useState(false);
  const [error, setError]         = useState('');

  useEffect(() => {
    if (authLoading) return;
    if (!user) { setChargement(false); return; }
    if (user.email) setEmail(prev => prev || user.email!);
    supabase.from('influencer_requests').select('statut')
      .eq('uid', user.uid).order('created_at', { ascending: false }).limit(1).maybeSingle()
      .then(({ data }) => { setStatutExistant((data?.statut as string | undefined) ?? null); setChargement(false); });
  }, [user, authLoading]);

  function handleFiles(e: React.ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(e.target.files ?? []).slice(0, 3 - files.length);
    setFiles((prev) => [...prev, ...selected].slice(0, 3));
  }

  function removeFile(i: number) {
    setFiles((prev) => prev.filter((_, idx) => idx !== i));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!instagram.trim() && !tiktok.trim() && !autre.trim()) {
      setError('Ajoute au moins un lien (Instagram, TikTok ou autre).');
      return;
    }
    if (!message.trim()) { setError('Le message de motivation est requis.'); return; }
    if (!email.trim())   { setError('Ton adresse email est requise.'); return; }

    if (!user) { setError('Connecte-toi pour envoyer ta demande.'); return; }
    setLoading(true);
    setError('');
    try {
      // Upload screenshots to Supabase storage
      const preuveUrls: string[] = [];
      for (const file of files) {
        const path = `${user.uid}/${Date.now()}_${file.name}`;
        const { error: upErr } = await supabase.storage.from('influencer-proofs').upload(path, file, { upsert: true });
        if (upErr) throw upErr;
        const { data: urlData } = supabase.storage.from('influencer-proofs').getPublicUrl(path);
        preuveUrls.push(urlData.publicUrl);
      }

      // Insert in influencer_requests
      const { error: dbErr } = await supabase.from('influencer_requests').insert({
        uid: user.uid,
        pseudo: pseudo.trim() || email.trim(),
        lien_instagram: instagram.trim() || null,
        lien_tiktok:    tiktok.trim()    || null,
        lien_autre:     autre.trim()     || null,
        message:        message.trim(),
        preuves_urls:   preuveUrls,
        statut:         'pending',
        email_contact:  email.trim(),
      });
      if (dbErr) throw dbErr;

      // Send email notification
      await apiFetch('/api/influencer-request/notify-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pseudo: pseudo.trim() || email.trim(),
          instagram: instagram.trim(),
          tiktok: tiktok.trim(),
          autre: autre.trim(),
          message: message.trim(),
          preuves: preuveUrls,
        }),
      });

      setSent(true);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }

  if (authLoading || chargement) {
    return (
      <main className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </main>
    );
  }

  if (!user) {
    return (
      <main className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <div className="bg-white rounded-3xl shadow-sm p-10 max-w-md w-full text-center">
          <p className="text-3xl mb-4">⭐</p>
          <p className="text-gray-600 text-sm mb-5">Connecte-toi à ton compte PetsMatch pour demander le badge Influenceur.</p>
          <Link href="/connexion" className="inline-block bg-[#0C5C6C] text-white font-semibold px-6 py-2.5 rounded-xl text-sm">Se connecter</Link>
        </div>
      </main>
    );
  }

  // Demande existante : statut (comme l'appli) — refus = nouvelle demande possible.
  if (!sent && (statutExistant === 'pending' || statutExistant === 'approved')) {
    const ok = statutExistant === 'approved';
    return (
      <main className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <div className="bg-white rounded-3xl shadow-sm p-10 max-w-md w-full text-center">
          <p className="text-4xl mb-4">{ok ? '⭐' : '⏳'}</p>
          <h1 className="text-xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            {ok ? 'Badge Influenceur accordé' : 'Demande en cours d’examen'}
          </h1>
          <p className="text-gray-500 text-sm">
            {ok ? 'Ton badge apparaît sur ton profil Pets Social.' : 'Tu recevras une notification dès qu’elle sera traitée.'}
          </p>
        </div>
      </main>
    );
  }

  if (sent) {
    return (
      <main className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <div className="bg-white rounded-3xl shadow-sm p-10 max-w-md w-full text-center">
          <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-[#6E9E57] to-[#0C5C6C] flex items-center justify-center mx-auto mb-6">
            <span className="text-2xl">⭐</span>
          </div>
          <h1 className="text-2xl font-bold text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
            Demande envoyée !
          </h1>
          <p className="text-gray-500 text-sm leading-relaxed">
            Nous avons bien reçu ta demande et nous la traiterons sous 48 h.<br />
            Tu recevras une notification dès qu&apos;elle sera traitée.
          </p>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-gray-50 py-12 px-4">
      <div className="max-w-lg mx-auto">
        {/* Header */}
        <div className="rounded-3xl p-8 mb-8 bg-gradient-to-br from-[#6E9E57] to-[#0C5C6C] text-white">
          <div className="flex items-center gap-3 mb-3">
            <span className="text-2xl">⭐</span>
            <h1 className="text-2xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>Badge Influenceur</h1>
          </div>
          <p className="text-white/80 text-sm leading-relaxed">
            Tu crées du contenu autour des animaux ? Rejoins PetsMatch en tant qu&apos;influenceur.
            Badge visible sur ton profil, tes posts et tes commentaires.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="bg-white rounded-3xl shadow-sm p-8 space-y-6">
          <div>
            <label className={labelCls}>Ton pseudo / nom</label>
            <input className={inputCls} value={pseudo} onChange={(e) => setPseudo(e.target.value)} placeholder="Ex : Sophie & ses chats" />
          </div>
          <div>
            <label className={labelCls}>Ton email <span className="text-red-500">*</span></label>
            <input type="email" className={inputCls} value={email} onChange={(e) => setEmail(e.target.value)} placeholder="contact@ton-profil.com" required />
          </div>

          <div>
            <p className="text-sm font-semibold text-[#1F2A2E] mb-2">Tes liens <span className="text-gray-400 font-normal">(au moins un)</span></p>
            <div className="space-y-2">
              <input className={inputCls} value={instagram} onChange={(e) => setInstagram(e.target.value)} placeholder="Instagram : https://instagram.com/ton_compte" />
              <input className={inputCls} value={tiktok}    onChange={(e) => setTiktok(e.target.value)}    placeholder="TikTok : https://tiktok.com/@ton_compte" />
              <input className={inputCls} value={autre}     onChange={(e) => setAutre(e.target.value)}     placeholder="Autre (YouTube, blog…)" />
            </div>
          </div>

          <div>
            <label className={labelCls}>Message de motivation <span className="text-red-500">*</span></label>
            <textarea
              className={`${inputCls} min-h-[120px] resize-y`}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Parle-nous de ton contenu, ta communauté, tes stats…"
              required
            />
          </div>

          <div>
            <label className={labelCls}>Captures d&apos;écran <span className="text-gray-400 font-normal">(max 3)</span></label>
            <p className="text-xs text-gray-400 mb-3">Stats de ton compte, nombre d&apos;abonnés, engagements…</p>
            <div className="flex flex-wrap gap-3">
              {files.map((f, i) => (
                <div key={i} className="relative w-24 h-24">
                  <img src={URL.createObjectURL(f)} alt="" className="w-24 h-24 object-cover rounded-xl" />
                  <button type="button" onClick={() => removeFile(i)}
                    className="absolute -top-1 -right-1 w-5 h-5 bg-red-500 text-white rounded-full text-xs flex items-center justify-center">
                    ×
                  </button>
                </div>
              ))}
              {files.length < 3 && (
                <label className="w-24 h-24 border-2 border-dashed border-gray-200 rounded-xl flex items-center justify-center cursor-pointer hover:border-[#0C5C6C] transition-colors">
                  <span className="text-2xl text-gray-300">+</span>
                  <input type="file" accept="image/*" multiple className="hidden" onChange={handleFiles} />
                </label>
              )}
            </div>
          </div>

          {error && <p className="text-red-500 text-sm">{error}</p>}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3.5 rounded-xl font-bold text-white text-sm transition-opacity disabled:opacity-60 bg-gradient-to-r from-[#6E9E57] to-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            {loading ? 'Envoi en cours…' : '⭐ Envoyer ma demande'}
          </button>
        </form>
      </div>
    </main>
  );
}
