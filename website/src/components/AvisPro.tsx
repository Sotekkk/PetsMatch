'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';

// Système d'avis générique (`avis_pro`) — réutilisé sur les fiches pro de
// service (véto, garde, pension, toilettage…) ET sur la fiche publique
// éleveur. Un avis n'est proposé qu'à un client ayant eu une interaction
// réelle avec ce pro précis (RDV confirmé/terminé, compte-rendu, ou pour
// un éleveur une cession confirmée) — vérifié côté RLS (can_review_pro),
// ce check ne sert qu'à ne pas afficher un formulaire qui échouerait.
export default function AvisPro({ proUid, proProfileId, clientUid, autoOpen = false }: { proUid: string; proProfileId?: string; clientUid: string | null; autoOpen?: boolean }) {
  const [avis, setAvis] = useState<{ id: string; note: number; commentaire: string | null; created_at: string; client_uid: string }[]>([]);
  const [reviewers, setReviewers] = useState<Record<string, { name: string; photo: string | null }>>({});
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const sectionRef = useRef<HTMLDivElement>(null);
  const autoOpenDone = useRef(false);
  const [note, setNote] = useState(0);
  const [comment, setComment] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [eligible, setEligible] = useState(false);
  const isPro = clientUid != null && clientUid === proUid;

  const reload = useCallback(async () => {
    let q = supabase.from('avis_pro').select('id, note, commentaire, created_at, client_uid').eq('pro_uid', proUid);
    if (proProfileId) q = q.eq('pro_profile_id', proProfileId);
    const { data } = await q.order('created_at', { ascending: false });
    const list = (data ?? []) as typeof avis;
    setAvis(list);
    setLoading(false);

    // Résout le nom + photo de chaque auteur d'avis (profil principal).
    const uids = Array.from(new Set(list.map(a => a.client_uid)));
    if (uids.length > 0) {
      const { data: profs } = await supabase.from('user_profiles')
        .select('uid, firstname, lastname, nom, avatar_url, profile_type')
        .in('uid', uids).eq('is_main', true);
      const map: Record<string, { name: string; photo: string | null }> = {};
      for (const p of profs ?? []) {
        const isElevage = p.profile_type === 'eleveur';
        const name = (isElevage && p.nom) ? p.nom : `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
        map[p.uid] = { name: name || 'Utilisateur PetsMatch', photo: p.avatar_url ?? null };
      }
      setReviewers(map);
    }

    if (clientUid && clientUid !== proUid) {
      const { data: myProf } = await supabase.from('user_profiles')
        .select('id').eq('uid', clientUid).eq('profile_type', 'particulier').maybeSingle();
      // Éligibilité résolue par PROFIL précis dans les deux sens (celui qui
      // laisse l'avis ET celui qui le reçoit), pas seulement par compte —
      // un RDV/une cession pris avec un AUTRE profil du même compte ne
      // doit pas rendre ce profil-ci éligible.
      const { data: ok } = await supabase.rpc('can_review_pro', {
        p_pro_uid: proUid, p_client_uid: clientUid, p_client_profile_id: myProf?.id ?? null,
        p_pro_profile_id: proProfileId ?? null,
      });
      setEligible(!!ok);
    }
  }, [proUid, proProfileId, clientUid]);
  useEffect(() => { reload(); }, [reload]);

  const dejaNote = clientUid != null && avis.some(a => a.client_uid === clientUid);

  async function contester(avisId: string) {
    if (!isPro) return;
    const motif = window.prompt('Motif du signalement :');
    if (motif == null) return;
    try {
      await supabase.from('avis_pro_contests').insert({
        avis_id: avisId, pro_uid: proUid, motif: motif.trim() || 'Non précisé',
      });
      window.alert("Signalement envoyé — notre équipe va l'examiner.");
    } catch (e) {
      window.alert(`Erreur : ${e}`);
    }
  }

  // Arrivée depuis la notif « Donnez votre avis » : ouvre le formulaire + scroll.
  useEffect(() => {
    if (!autoOpen || autoOpenDone.current || loading) return;
    autoOpenDone.current = true;
    if (clientUid && !dejaNote) setShowForm(true);
    sectionRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, [autoOpen, loading, clientUid, dejaNote]);
  const moyenne = avis.length ? avis.reduce((s, a) => s + a.note, 0) / avis.length : 0;

  async function submit() {
    if (note === 0 || !clientUid) return;
    setSaving(true);
    setError(null);
    try {
      const { data: prof } = await supabase.from('user_profiles').select('id').eq('uid', clientUid).eq('profile_type', 'particulier').maybeSingle();
      const { error: err } = await supabase.from('avis_pro').insert({
        pro_uid: proUid, ...(proProfileId ? { pro_profile_id: proProfileId } : {}),
        client_uid: clientUid, ...(prof?.id ? { client_profile_id: prof.id } : {}),
        note, commentaire: comment.trim() || null,
      });
      if (err) {
        setError(
          err.code === '23505' ? 'Vous avez déjà laissé un avis.'
          : err.code === '42501' ? "Vous ne pouvez pas laisser d'avis : aucune interaction avec ce professionnel n'est enregistrée (rendez-vous ou prestation)."
          : `Erreur : ${err.message}`
        );
        return;
      }
      setShowForm(false); setNote(0); setComment(''); setError(null);
      reload();
    } finally { setSaving(false); }
  }

  if (loading) return null;
  return (
    <div ref={sectionRef} className="bg-white rounded-2xl p-4 shadow-sm">
      <div className="flex items-center justify-between mb-2">
        <p className="font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Avis {avis.length > 0 && <span className="text-sm text-gray-500 font-normal">⭐ {moyenne.toFixed(1)} ({avis.length})</span>}
        </p>
        {clientUid && !dejaNote && eligible && (
          <button onClick={() => setShowForm(v => !v)} className="text-xs font-semibold text-[#0C5C6C]">Laisser un avis</button>
        )}
      </div>
      {showForm && (
        <div className="border border-gray-100 rounded-xl p-3 mb-3 space-y-2">
          <div className="flex gap-1">
            {[1, 2, 3, 4, 5].map(n => (
              <button key={n} onClick={() => setNote(n)} className="text-2xl leading-none">{n <= note ? '★' : '☆'}</button>
            ))}
          </div>
          <textarea value={comment} onChange={e => setComment(e.target.value)} rows={3} maxLength={500}
            placeholder="Votre commentaire (optionnel)…" className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
          {error && <p className="text-xs text-red-600">{error}</p>}
          <button onClick={submit} disabled={saving || note === 0}
            className="w-full bg-[#0C5C6C] text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50">Publier l&apos;avis</button>
        </div>
      )}
      {avis.length === 0 ? (
        <p className="text-sm text-gray-400">Aucun avis pour l&apos;instant.</p>
      ) : (
        <div className="space-y-2">
          {avis.map(a => {
            const rev = reviewers[a.client_uid];
            return (
            <div key={a.id} className="border border-gray-100 rounded-xl p-2.5">
              <div className="flex items-center gap-2">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                {rev?.photo ? (
                  <img src={rev.photo} alt={rev.name} className="w-7 h-7 rounded-full object-cover shrink-0" />
                ) : (
                  <div className="w-7 h-7 rounded-full bg-[#E8F4F6] text-[#0C5C6C] text-xs font-bold flex items-center justify-center shrink-0">
                    {(rev?.name ?? '?').charAt(0).toUpperCase()}
                  </div>
                )}
                <span className="text-sm font-semibold text-[#1E2025] truncate flex-1">{rev?.name ?? 'Utilisateur PetsMatch'}</span>
                <span className="text-[11px] text-gray-400 shrink-0">{new Date(a.created_at).toLocaleDateString('fr-FR')}</span>
              </div>
              <div className="mt-1">
                <span className="text-[#FFA000] text-sm">{'★'.repeat(a.note)}<span className="text-gray-200">{'★'.repeat(5 - a.note)}</span></span>
              </div>
              {a.commentaire && <p className="text-sm text-gray-700 mt-1">{a.commentaire}</p>}
              {isPro && (
                <button onClick={() => contester(a.id)} className="text-[11px] text-gray-400 hover:text-gray-600 mt-1">🚩 Signaler</button>
              )}
            </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
