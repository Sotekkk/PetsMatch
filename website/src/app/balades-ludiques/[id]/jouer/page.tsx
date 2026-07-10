'use client';

import { useEffect, useState, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';
import { typeDefiIcon } from '../../shared';

interface Balade { id: string; titre: string; xp_recompense?: number; }
interface Point {
  id: string; ordre: number; titre: string; description?: string; lat: number; lng: number;
  rayon_validation_m?: number; type_defi: string; question_texte?: string; question_reponse?: string;
  consigne_texte?: string; qr_code_value?: string; indice?: string;
}
interface Progression { id: string; nb_points_valides: number; }

function distanceMetres(lat1: number, lng1: number, lat2: number, lng2: number) {
  const R = 6371000;
  const toRad = (v: number) => (v * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export default function JouerPage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuth();
  const router = useRouter();

  const [balade, setBalade] = useState<Balade | null>(null);
  const [points, setPoints] = useState<Point[]>([]);
  const [progression, setProgression] = useState<Progression | null>(null);
  const [loading, setLoading] = useState(true);
  const [showIndice, setShowIndice] = useState(false);
  const [reponse, setReponse] = useState('');
  const [erreurReponse, setErreurReponse] = useState(false);
  const [codeQr, setCodeQr] = useState('');
  const [erreurQr, setErreurQr] = useState(false);
  const [gpsMessage, setGpsMessage] = useState<string | null>(null);
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [termine, setTermine] = useState<{ xp: number; badges: string[] } | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const { data: b } = await supabase.from('balades_ludiques').select('*').eq('id', id).single();
    const { data: pts } = await supabase.from('balades_ludiques_points').select('*').eq('balade_id', id).order('ordre');
    let { data: prog } = await supabase.from('balades_ludiques_progressions').select('*').eq('balade_id', id).eq('joueur_uid', user.uid).maybeSingle();
    if (!prog) {
      const { data: inserted } = await supabase.from('balades_ludiques_progressions').insert({ balade_id: id, joueur_uid: user.uid }).select().single();
      prog = inserted;
    }
    setBalade(b as Balade);
    setPoints((pts ?? []) as Point[]);
    setProgression(prog as Progression);
    setShowIndice(false);
    setReponse(''); setErreurReponse(false); setCodeQr(''); setErreurQr(false); setGpsMessage(null);
    setLoading(false);
  }, [id, user]);

  useEffect(() => { load(); }, [load]);

  const idx = progression?.nb_points_valides ?? 0;
  const currentPoint = idx < points.length ? points[idx] : null;

  async function onCompletion() {
    if (!user || !balade) return;
    const xp = balade.xp_recompense ?? 0;

    const { count } = await supabase.from('balades_ludiques_progressions').select('*', { count: 'exact', head: true }).eq('balade_id', id).eq('statut', 'termine');
    await supabase.from('balades_ludiques').update({ nb_completions: count ?? 0 }).eq('id', id);

    const { data: existingXp } = await supabase.from('joueurs_xp').select('*').eq('user_uid', user.uid).maybeSingle();
    const nouveauXp = (existingXp?.xp_total ?? 0) + xp;
    const nouveauNb = (existingXp?.nb_parcours_completes ?? 0) + 1;
    await supabase.from('joueurs_xp').upsert({
      user_uid: user.uid, xp_total: nouveauXp, nb_parcours_completes: nouveauNb, updated_at: new Date().toISOString(),
    }, { onConflict: 'user_uid' });

    const badgesDebloquees: string[] = [];
    const { data: catalogue } = await supabase.from('badges').select('*').eq('actif', true);
    const { data: deja } = await supabase.from('badges_obtenus').select('badge_id').eq('user_uid', user.uid);
    const dejaIds = new Set((deja ?? []).map((r: { badge_id: string }) => r.badge_id));
    for (const badge of catalogue ?? []) {
      if (dejaIds.has(badge.id)) continue;
      let obtenu = false;
      if (badge.condition_type === 'nb_parcours_completes') obtenu = nouveauNb >= (badge.condition_valeur?.seuil ?? Infinity);
      if (badge.condition_type === 'nb_xp') obtenu = nouveauXp >= (badge.condition_valeur?.seuil ?? Infinity);
      if (obtenu) {
        await supabase.from('badges_obtenus').insert({ user_uid: user.uid, badge_id: badge.id, balade_id: id });
        badgesDebloquees.push(`${badge.icone_url ?? '🏅'} ${badge.nom}`);
      }
    }

    await supabase.from('notifications').insert({
      uid: user.uid, type: 'balade_ludique_xp', data: { balade_id: id, xp, titre: balade.titre }, read: false,
    });

    setTermine({ xp, badges: badgesDebloquees });
  }

  async function validerEtape(payload: Partial<{
    type_preuve: string; preuve_photo_url: string; preuve_texte: string; preuve_lat: number; preuve_lng: number; distance_calculee_m: number;
  }>) {
    if (!user || !progression || !currentPoint) return;
    setBusy(true);
    try {
      await supabase.from('balades_ludiques_validations').insert({
        progression_id: progression.id, point_id: currentPoint.id, joueur_uid: user.uid, ...payload,
      });
    } catch { /* déjà validée */ }

    const nouveauNb = (progression.nb_points_valides ?? 0) + 1;
    const estTermine = nouveauNb >= points.length;
    const update: Record<string, unknown> = { nb_points_valides: nouveauNb };
    if (estTermine) { update.statut = 'termine'; update.completed_at = new Date().toISOString(); }
    const { data: updated } = await supabase.from('balades_ludiques_progressions').update(update).eq('id', progression.id).select().single();
    setProgression(updated as Progression);
    setShowIndice(false); setReponse(''); setErreurReponse(false); setCodeQr(''); setErreurQr(false); setGpsMessage(null);
    setBusy(false);
    if (estTermine) await onCompletion();
  }

  function validerReponse() {
    if (!currentPoint) return;
    const saisie = reponse.trim().toLowerCase();
    const attendu = (currentPoint.question_reponse ?? '').trim().toLowerCase();
    if (saisie !== attendu) { setErreurReponse(true); return; }
    validerEtape({ type_preuve: 'texte', preuve_texte: reponse.trim() });
  }

  function validerQr() {
    if (!currentPoint) return;
    if (codeQr.trim() !== (currentPoint.qr_code_value ?? '').trim()) { setErreurQr(true); return; }
    validerEtape({ type_preuve: 'qr_code', preuve_texte: codeQr.trim() });
  }

  function validerGps() {
    if (!currentPoint) return;
    if (!navigator.geolocation) { setGpsMessage('Géolocalisation non disponible sur ce navigateur.'); return; }
    navigator.geolocation.getCurrentPosition((pos) => {
      const dist = distanceMetres(pos.coords.latitude, pos.coords.longitude, currentPoint.lat, currentPoint.lng);
      if (dist <= (currentPoint.rayon_validation_m ?? 30)) {
        validerEtape({ type_preuve: 'gps', preuve_lat: pos.coords.latitude, preuve_lng: pos.coords.longitude, distance_calculee_m: dist });
      } else {
        setGpsMessage(`Vous êtes à ${Math.round(dist)} m du point (max ${currentPoint.rayon_validation_m ?? 30} m).`);
      }
    }, () => setGpsMessage('Impossible de récupérer votre position.'));
  }

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) setCropSrc(URL.createObjectURL(file));
    e.target.value = '';
  }

  async function handleCropConfirm(blob: Blob) {
    if (!progression || !currentPoint) return;
    setCropSrc(null);
    setBusy(true);
    try {
      const url = await uploadBlob(blob, `balades_ludiques/preuves/${progression.id}/${currentPoint.id}.jpg`);
      await validerEtape({ type_preuve: 'photo', preuve_photo_url: url });
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" /></div>;

  if (termine) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#F8F8F6] px-4">
        <div className="text-center max-w-sm">
          <p className="text-6xl mb-4">🎉</p>
          <h1 className="text-2xl font-bold font-galey text-gray-900">Parcours terminé !</h1>
          <p className="text-orange-600 font-galey font-bold text-lg mt-2">+{termine.xp} XP</p>
          {termine.badges.length > 0 && (
            <div className="mt-4">
              <p className="font-galey font-semibold text-sm text-gray-700">Badges débloqués :</p>
              {termine.badges.map(b => <p key={b} className="font-galey text-sm">{b}</p>)}
            </div>
          )}
          <button onClick={() => router.push(`/balades-ludiques/${id}`)}
            className="mt-6 bg-teal-700 text-white font-galey font-bold px-8 py-3 rounded-xl">
            Retour au parcours
          </button>
        </div>
      </div>
    );
  }

  if (!currentPoint) return null;

  return (
    <div className="min-h-screen bg-[#F8F8F6] pb-12">
      <div className="bg-teal-700 text-white px-4 py-4">
        <div className="max-w-xl mx-auto flex items-center gap-3">
          <button onClick={() => router.back()} className="text-xl">←</button>
          <p className="font-galey font-bold">{balade?.titre}</p>
        </div>
      </div>
      <div className="max-w-xl mx-auto px-4 py-6">
        <p className="text-xs font-galey text-gray-400 mb-1">Étape {idx + 1} / {points.length}</p>
        <h2 className="text-xl font-bold font-galey text-gray-900">{currentPoint.titre}</h2>
        {currentPoint.description && <p className="text-sm font-galey text-gray-500 mt-1">{currentPoint.description}</p>}

        <div className="bg-white rounded-2xl shadow-sm p-5 mt-4">
          <p className="text-xs font-galey font-semibold text-gray-500 mb-3">{typeDefiIcon(currentPoint.type_defi)} Défi à réaliser</p>

          {(currentPoint.type_defi === 'photo' || currentPoint.type_defi === 'objet_nature' || currentPoint.type_defi === 'action_animal') && (
            <div>
              <p className="text-sm font-galey text-gray-700 mb-3">
                {currentPoint.type_defi === 'photo' ? (currentPoint.question_texte || 'Prenez une photo pour valider cette étape.') : (currentPoint.consigne_texte || 'Prenez une photo pour prouver votre réussite.')}
              </p>
              <label className="block w-full h-40 rounded-xl bg-[#EEF5EA] border-2 border-dashed border-teal-300 flex items-center justify-center cursor-pointer">
                <span className="font-galey text-teal-700 text-sm">📷 Choisir une photo</span>
                <input type="file" accept="image/*" className="hidden" onChange={handleFile} disabled={busy} />
              </label>
            </div>
          )}

          {currentPoint.type_defi === 'question' && (
            <div>
              <p className="text-sm font-galey font-semibold text-gray-700 mb-3">{currentPoint.question_texte}</p>
              <input value={reponse} onChange={e => { setReponse(e.target.value); setErreurReponse(false); }}
                placeholder="Votre réponse" className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
              {erreurReponse && <p className="text-red-500 text-xs font-galey mt-1">Ce n&apos;est pas la bonne réponse, réessayez.</p>}
              <button onClick={validerReponse} disabled={busy || !reponse.trim()}
                className="mt-3 w-full bg-orange-600 text-white font-galey font-bold py-3 rounded-xl disabled:opacity-50">
                Valider l&apos;étape
              </button>
            </div>
          )}

          {currentPoint.type_defi === 'qr_code' && (
            <div>
              <p className="text-sm font-galey text-gray-700 mb-3">Saisissez le code affiché sous le QR code trouvé sur le terrain.</p>
              <input value={codeQr} onChange={e => { setCodeQr(e.target.value); setErreurQr(false); }}
                placeholder="Code" className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
              {erreurQr && <p className="text-red-500 text-xs font-galey mt-1">Ce code ne correspond pas à cette étape.</p>}
              <button onClick={validerQr} disabled={busy || !codeQr.trim()}
                className="mt-3 w-full bg-orange-600 text-white font-galey font-bold py-3 rounded-xl disabled:opacity-50">
                Valider l&apos;étape
              </button>
            </div>
          )}

          {currentPoint.type_defi === 'gps_seul' && (
            <div>
              <p className="text-sm font-galey text-gray-700 mb-3">Rendez-vous sur place puis validez votre position.</p>
              {gpsMessage && <p className="text-red-500 text-xs font-galey mb-2">{gpsMessage}</p>}
              <button onClick={validerGps} disabled={busy}
                className="w-full bg-orange-600 text-white font-galey font-bold py-3 rounded-xl disabled:opacity-50">
                📍 Je suis arrivé(e)
              </button>
            </div>
          )}
        </div>

        {currentPoint.indice && (
          <div className="mt-3">
            {showIndice
              ? <p className="text-sm font-galey italic text-gray-600">💡 {currentPoint.indice}</p>
              : <button onClick={() => setShowIndice(true)} className="text-teal-700 text-sm font-galey underline">Afficher un indice</button>}
          </div>
        )}
      </div>

      {cropSrc && <ImageCropModal src={cropSrc} aspect={1} maxDim={800} onConfirm={handleCropConfirm} onCancel={() => setCropSrc(null)} />}
    </div>
  );
}
