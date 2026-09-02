'use client';

import { useEffect, useState, useRef, use } from 'react';
import dynamic from 'next/dynamic';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { useAuth } from '@/lib/auth-context';

const CyanoReportModal = dynamic(() => import('@/components/CyanoReportModal'), { ssr: false });

// ── Types ──────────────────────────────────────────────────────────────────────

interface NaturalPlace {
  id: string;
  nom: string;
  categorie: string;
  description?: string | null;
  lat: number | null;
  lng: number | null;
  photo_url?: string | null;
  photos?: string[] | null;
  alerte_cyano: boolean | null;
  alerte_cyano_lat?: number | null;
  alerte_cyano_lng?: number | null;
  alerte_cyano_statut?: string | null;
  alerte_cyano_photo_url?: string | null;
  alerte_cyano_date?: string | null;
  nb_avis: number | null;
  note_moyenne: number | null;
  niveau_difficulte?: string | null;
  has_parking?: boolean | null;
  has_eau?: boolean | null;
  has_fontaine?: boolean | null;
  has_poubelle?: boolean | null;
  parcours_ombre?: boolean | null;
  baignade_possible?: boolean | null;
  distance?: string | null;
  duree?: string | null;
}

interface Review {
  id: string;
  profile_id: string;
  note: number;
  commentaire: string | null;
  photos: string[] | null;
  created_at: string;
}

// ── Constantes ─────────────────────────────────────────────────────────────────

const CAT_EMOJI: Record<string, string> = {
  foret: '🌲', plage: '🏖️', parc: '🌿', lac: '💧', riviere: '🏞️',
};
const CAT_LABEL: Record<string, string> = {
  foret: 'Forêt', plage: 'Plage', parc: 'Parc', lac: 'Lac', riviere: 'Rivière',
};
const CAT_COLOR: Record<string, string> = {
  foret: '#2E7D32', plage: '#1565C0', parc: '#558B2F', lac: '#00838F', riviere: '#0277BD',
};
const CAT_PHOTO: Record<string, string> = {
  foret: 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=1200&q=80&fit=crop',
  plage: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1200&q=80&fit=crop',
  parc: 'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?w=1200&q=80&fit=crop',
  lac: 'https://images.unsplash.com/photo-1501854140801-50d01698950b?w=1200&q=80&fit=crop',
  riviere: 'https://images.unsplash.com/photo-1544198365-f5d60b6d8190?w=1200&q=80&fit=crop',
};

const AMENITIES: { field: keyof NaturalPlace; icon: string; label: string }[] = [
  { field: 'has_eau', icon: '💧', label: 'Eau potable' },
  { field: 'has_parking', icon: '🅿️', label: 'Parking' },
  { field: 'has_fontaine', icon: '⛲', label: 'Fontaine' },
  { field: 'has_poubelle', icon: '🗑️', label: 'Poubelles' },
  { field: 'parcours_ombre', icon: '🌳', label: 'Parcours ombragé' },
  { field: 'baignade_possible', icon: '🏊', label: 'Baignade' },
];

const DIFFICULTY = [
  { value: 'facile', label: '🟢 Facile', color: '#2E7D32' },
  { value: 'moyen', label: '🟡 Moyen', color: '#EF6C00' },
  { value: 'difficile', label: '🔴 Difficile', color: '#C62828' },
];

// ── Page ───────────────────────────────────────────────────────────────────────

export default function NaturalPlaceDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const profileId = useActiveProfile();
  const { user } = useAuth();

  const [place, setPlace] = useState<NaturalPlace | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingReviews, setLoadingReviews] = useState(true);
  const [myNote, setMyNote] = useState(0);
  const [myComment, setMyComment] = useState('');
  const [myReviewPhotos, setMyReviewPhotos] = useState<string[]>([]); // déjà publiées
  const [newReviewPhotos, setNewReviewPhotos] = useState<File[]>([]);
  const [saving, setSaving] = useState(false);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [pendingAmenityFields, setPendingAmenityFields] = useState<Set<string>>(new Set());
  const [amenityUploading, setAmenityUploading] = useState<string | null>(null);

  async function loadPlace() {
    setLoading(true);
    try {
      const { data } = await supabase.from('natural_places').select().eq('id', id).single();
      setPlace(data as NaturalPlace);
    } finally {
      setLoading(false);
    }
  }

  async function loadReviews() {
    setLoadingReviews(true);
    try {
      const { data } = await supabase
        .from('natural_place_reviews')
        .select()
        .eq('place_id', id)
        .order('created_at', { ascending: false });
      const list = (data ?? []) as Review[];
      setReviews(list);
      const mine = profileId ? list.find(r => r.profile_id === profileId) : undefined;
      if (mine) {
        setMyNote(mine.note);
        setMyComment(mine.commentaire ?? '');
        setMyReviewPhotos(mine.photos ?? []);
      }
    } finally {
      setLoadingReviews(false);
    }
  }

  async function loadPendingAmenities() {
    const { data } = await supabase
      .from('natural_place_amenity_suggestions')
      .select('field')
      .eq('place_id', id)
      .eq('statut', 'en_attente');
    setPendingAmenityFields(new Set((data ?? []).map((r: { field: string }) => r.field)));
  }

  useEffect(() => { loadPlace(); loadReviews(); loadPendingAmenities(); }, [id, profileId]); // eslint-disable-line react-hooks/exhaustive-deps

  async function recalcStats() {
    const { data } = await supabase.from('natural_place_reviews').select('note').eq('place_id', id);
    const notes = (data ?? []).map((r: { note: number }) => r.note);
    if (!notes.length) return;
    const avg = notes.reduce((a: number, b: number) => a + b, 0) / notes.length;
    await supabase.from('natural_places').update({ nb_avis: notes.length, note_moyenne: avg }).eq('id', id);
  }

  async function submitReview() {
    if (myNote === 0 || !profileId) return;
    setSaving(true);
    try {
      const photos = [...myReviewPhotos];
      for (let i = 0; i < newReviewPhotos.length; i++) {
        const f = newReviewPhotos[i];
        const path = `natural_places/reviews/${id}_${Date.now()}_${i}.jpg`;
        const { error: upErr } = await supabase.storage.from('media').upload(path, f, {
          contentType: f.type || 'application/octet-stream', upsert: true,
        });
        if (!upErr) photos.push(supabase.storage.from('media').getPublicUrl(path).data.publicUrl);
      }
      await supabase.from('natural_place_reviews').upsert({
        place_id: id,
        profile_id: profileId,
        note: myNote,
        commentaire: myComment.trim(),
        // 'photos' seulement si présentes → avis sans photo possibles même
        // avant la migration natural_place_review_photos.
        ...(photos.length || myReviewPhotos.length ? { photos } : {}),
      }, { onConflict: 'place_id,profile_id' });
      setNewReviewPhotos([]);
      await recalcStats();
      await Promise.all([loadReviews(), loadPlace()]);
    } finally {
      setSaving(false);
    }
  }

  const [cyanoModal, setCyanoModal] = useState<false | 'new' | 'confirm'>(false);

  async function removeCyano() {
    await supabase.from('natural_places').update({
      alerte_cyano: false, alerte_cyano_date: null, alerte_cyano_profile_id: null,
      alerte_cyano_statut: null, alerte_cyano_lat: null, alerte_cyano_lng: null, alerte_cyano_photo_url: null,
    }).eq('id', id);
    loadPlace();
  }

  const amenityFileInput = useRef<HTMLInputElement>(null);
  const [amenityFieldPending, setAmenityFieldPending] = useState<{ field: string; value: boolean } | null>(null);

  function suggestAmenity(field: string, value: boolean) {
    if (!user) return;
    setAmenityFieldPending({ field, value });
    amenityFileInput.current?.click();
  }

  async function onAmenityPhotoSelected(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    const pending = amenityFieldPending;
    setAmenityFieldPending(null);
    if (!file || !pending || !user) return;

    setAmenityUploading(pending.field);
    try {
      const path = `natural_places/amenity_${Date.now()}_${user.uid}.jpg`;
      const { error: upErr } = await supabase.storage.from('media').upload(path, file, {
        contentType: file.type || 'application/octet-stream', upsert: true,
      });
      if (upErr) throw upErr;
      const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
      await supabase.from('natural_place_amenity_suggestions').insert({
        place_id: id,
        field: pending.field,
        value: pending.value,
        photo_url: url,
        submitted_by_uid: user.uid,
        submitted_by_profile_id: profileId || null,
      });
      setPendingAmenityFields(prev => new Set(prev).add(pending.field));
    } catch (e) {
      console.error(e);
    } finally {
      setAmenityUploading(null);
    }
  }

  async function updateDifficulty(value: string) {
    await supabase.from('natural_places').update({ niveau_difficulte: value }).eq('id', id);
    setPlace(p => p ? { ...p, niveau_difficulte: value } : p);
  }

  async function addPhoto(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !user) return;
    setUploadingPhoto(true);
    try {
      const path = `natural_places/${Date.now()}_${user.uid}.jpg`;
      const { error: upErr } = await supabase.storage.from('media').upload(path, file, {
        contentType: file.type || 'application/octet-stream', upsert: true,
      });
      if (upErr) throw upErr;
      const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
      await supabase.from('natural_place_photo_suggestions').insert({
        place_id: id,
        photo_url: url,
        submitted_by_uid: user.uid,
        submitted_by_profile_id: profileId || null,
      });
      alert('Merci ! Ta photo sera visible après validation par un admin.');
    } catch (e) {
      console.error(e);
    } finally {
      setUploadingPhoto(false);
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen flex justify-center items-center bg-[#F5F5F0]">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (!place) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-3 bg-[#F5F5F0]">
        <p className="font-bold text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>Lieu introuvable</p>
        <Link href="/lieux-naturels" className="text-[#0C5C6C] text-sm underline">Retour aux lieux naturels</Link>
      </div>
    );
  }

  const cat = place.categorie;
  const color = CAT_COLOR[cat] ?? '#0C5C6C';
  const cyano = place.alerte_cyano === true;
  const photoUrl = place.photo_url || CAT_PHOTO[cat];
  const mapsUrl = place.lat != null && place.lng != null
    ? `https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lng}`
    : null;

  return (
    <div className="min-h-screen bg-[#F5F5F0]">
      {/* Header photo */}
      <div className="relative h-64" style={{ backgroundColor: color }}>
        {photoUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={photoUrl} alt={place.nom} className="absolute inset-0 w-full h-full object-cover" />
        )}
        <div className="absolute inset-0" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.15), rgba(0,0,0,0.75))' }} />
        <Link
          href="/lieux-naturels"
          className="absolute top-4 left-4 w-9 h-9 rounded-full bg-black/30 text-white flex items-center justify-center hover:bg-black/45 transition-colors"
        >
          ←
        </Link>
        <h1 className="absolute bottom-4 left-5 right-5 text-white font-extrabold text-2xl drop-shadow" style={{ fontFamily: 'Galey, sans-serif' }}>
          {place.nom}
        </h1>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-5">
        {/* Alerte cyano */}
        {cyano && (
          <div className={`text-white rounded-xl px-4 py-3 mb-4 ${place.alerte_cyano_statut === 'confirme' ? 'bg-red-700' : 'bg-amber-500'}`}>
            <div className="flex items-start justify-between gap-3">
              <p className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
                {place.alerte_cyano_statut === 'confirme'
                  ? '⚠️ Cyanobactéries CONFIRMÉES — baignade et contact avec l’eau interdits.'
                  : '⚠️ Cyanobactéries suspectées — prudence, contact avec l’eau déconseillé.'}
                {place.alerte_cyano_date && (
                  <span className="block font-normal text-white/80 text-xs mt-0.5">
                    Signalée le {new Date(place.alerte_cyano_date).toLocaleDateString('fr-FR')}
                  </span>
                )}
              </p>
              {profileId && (
                <button onClick={removeCyano} className="text-sm font-bold underline flex-shrink-0">Lever</button>
              )}
            </div>
            {place.alerte_cyano_photo_url && (
              /* eslint-disable-next-line @next/next/no-img-element */
              <img src={place.alerte_cyano_photo_url} alt="" className="mt-2 rounded-lg w-40 h-24 object-cover" />
            )}
            {place.alerte_cyano_statut !== 'confirme' && profileId && (
              <button onClick={() => setCyanoModal('confirm')}
                className="mt-2 text-xs font-bold underline">
                Confirmer l’alerte (avec photo)
              </button>
            )}
          </div>
        )}

        {/* Catégorie + note */}
        <div className="flex items-center justify-between mb-4">
          <span
            className="text-sm font-semibold px-3 py-1 rounded-full"
            style={{ backgroundColor: color + '1F', color, border: `1px solid ${color}66`, fontFamily: 'Galey, sans-serif' }}
          >
            {CAT_EMOJI[cat]} {CAT_LABEL[cat] ?? cat}
          </span>
          {(place.nb_avis ?? 0) > 0 && (
            <span className="text-sm text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
              <span className="text-[#FDD835]">★</span> {(place.note_moyenne ?? 0).toFixed(1)} ({place.nb_avis} avis)
            </span>
          )}
        </div>

        {(place.distance || place.duree) && (
          <div className="flex items-center gap-2 mb-4 text-sm text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
            {place.distance && (
              <span className="flex items-center gap-1 font-semibold">
                🥾 {place.distance}
              </span>
            )}
            {place.distance && place.duree && <span className="text-gray-300">·</span>}
            {place.duree && (
              <span className="flex items-center gap-1 font-semibold">
                ⏱️ {place.duree}
              </span>
            )}
          </div>
        )}

        {place.description && (
          <p className="text-sm text-gray-700 leading-relaxed mb-5" style={{ fontFamily: 'Galey, sans-serif' }}>
            {place.description}
          </p>
        )}

        {/* Actions */}
        <div className="flex gap-2.5 mb-6">
          {mapsUrl && (
            <a
              href={mapsUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="flex-1 text-center py-3 rounded-xl text-sm font-semibold border transition-colors"
              style={{ borderColor: '#0C5C6C66', color: '#0C5C6C', backgroundColor: '#0C5C6C0F', fontFamily: 'Galey, sans-serif' }}
            >
              🧭 Itinéraire
            </a>
          )}
          {!cyano && (
            <button
              onClick={() => setCyanoModal('new')}
              disabled={!profileId}
              className="flex-1 text-center py-3 rounded-xl text-sm font-semibold border transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              style={{ borderColor: '#C6282866', color: '#C62828', backgroundColor: '#C628280F', fontFamily: 'Galey, sans-serif' }}
            >
              ⚠️ Signaler cyano
            </button>
          )}
        </div>

        {/* Équipements */}
        <h2 className="font-bold text-base text-[#1F2A2E] mb-2.5" style={{ fontFamily: 'Galey, sans-serif' }}>
          Équipements & caractéristiques
        </h2>
        <input ref={amenityFileInput} type="file" accept="image/*" className="hidden" onChange={onAmenityPhotoSelected} />
        <div className="grid grid-cols-2 gap-2 mb-6">
          {AMENITIES.map(({ field, icon, label }) => {
            const active = place[field] === true;
            const pending = pendingAmenityFields.has(field);
            const uploading = amenityUploading === field;
            return (
              <button
                key={field}
                onClick={(user && !pending && !uploading) ? () => suggestAmenity(field, !active) : undefined}
                disabled={!user || pending || uploading}
                className="flex items-center gap-2 px-3 py-2 rounded-lg border text-left transition-colors disabled:cursor-default"
                style={{
                  backgroundColor: pending ? '#EA580C1A' : active ? '#6E9E571F' : '#F9FAFB',
                  borderColor: pending ? '#EA580C80' : active ? '#6E9E5780' : '#E5E7EB',
                }}
              >
                <span className="text-sm">{icon}</span>
                <span
                  className="text-xs flex-1"
                  style={{ fontFamily: 'Galey, sans-serif', color: pending ? '#9A3412' : active ? '#1E2025' : '#9CA3AF', fontWeight: (active || pending) ? 600 : 400 }}
                >
                  {label}
                </span>
                {uploading ? (
                  <span className="text-xs">⏳</span>
                ) : pending ? (
                  <span className="text-xs" title="En attente de validation">⏳</span>
                ) : user ? (
                  <span className="text-xs">{active ? '✅' : '⚪'}</span>
                ) : null}
              </button>
            );
          })}
        </div>
        {user && (
          <p className="text-xs text-gray-400 -mt-4 mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>
            📷 Une photo est demandée pour confirmer un équipement — validé par un admin avant d&apos;apparaître pour tous.
          </p>
        )}

        {/* Difficulté */}
        <h2 className="font-bold text-base text-[#1F2A2E] mb-2.5" style={{ fontFamily: 'Galey, sans-serif' }}>
          Difficulté
        </h2>
        <div className="flex gap-2 mb-6">
          {DIFFICULTY.map(d => {
            const active = place.niveau_difficulte === d.value;
            return (
              <button
                key={d.value}
                onClick={profileId ? () => updateDifficulty(d.value) : undefined}
                disabled={!profileId}
                className="flex-1 py-2 rounded-lg border text-xs font-semibold transition-colors disabled:cursor-default"
                style={{
                  backgroundColor: active ? d.color + '26' : '#F9FAFB',
                  borderColor: active ? d.color : '#E5E7EB',
                  color: active ? d.color : '#9CA3AF',
                  fontFamily: 'Galey, sans-serif',
                }}
              >
                {d.label}
              </button>
            );
          })}
        </div>

        {/* Photos */}
        <div className="flex items-center justify-between mb-2.5">
          <h2 className="font-bold text-base text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Photos
          </h2>
          {user && (
            <label className="text-xs font-semibold text-[#0C5C6C] cursor-pointer hover:underline" style={{ fontFamily: 'Galey, sans-serif' }}>
              {uploadingPhoto ? 'Envoi…' : '📷 Ajouter'}
              <input type="file" accept="image/*" className="hidden" disabled={uploadingPhoto} onChange={addPhoto} />
            </label>
          )}
        </div>
        {(place.photos?.length ?? 0) === 0 ? (
          <div className="h-16 rounded-xl bg-gray-50 border border-gray-100 flex items-center justify-center mb-6">
            <p className="text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>Aucune photo pour le moment</p>
          </div>
        ) : (
          <div className="mb-6">
            <PhotoCarousel photos={place.photos!} alt={place.nom} />
          </div>
        )}

        {/* Avis */}
        <h2 className="font-bold text-base text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
          Avis
        </h2>

        {profileId && (
          <div className="bg-white rounded-2xl shadow-sm p-4 mb-4">
            <p className="font-bold text-sm mb-2.5" style={{ fontFamily: 'Galey, sans-serif' }}>Votre avis</p>
            <div className="flex gap-1 mb-2.5">
              {[1, 2, 3, 4, 5].map(n => (
                <button key={n} onClick={() => setMyNote(n)} className="text-2xl leading-none">
                  <span style={{ color: n <= myNote ? '#FDD835' : '#E5E7EB' }}>★</span>
                </button>
              ))}
            </div>
            <textarea
              value={myComment}
              onChange={e => setMyComment(e.target.value)}
              rows={3}
              placeholder="Partagez votre expérience..."
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm resize-none focus:outline-none focus:border-[#0C5C6C] mb-2.5"
              style={{ fontFamily: 'Galey, sans-serif', backgroundColor: '#F8F9FA' }}
            />
            <div className="flex flex-wrap gap-2 mb-2.5">
              {myReviewPhotos.map((src, i) => (
                <div key={`e${i}`} className="relative w-16 h-16 rounded-lg overflow-hidden">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={src} alt="" className="w-full h-full object-cover" />
                  <button onClick={() => setMyReviewPhotos(p => p.filter((_, j) => j !== i))}
                    className="absolute top-0.5 right-0.5 bg-black/55 text-white rounded-full w-5 h-5 flex items-center justify-center text-[10px]">✕</button>
                </div>
              ))}
              {newReviewPhotos.map((f, i) => (
                <div key={`n${i}`} className="relative w-16 h-16 rounded-lg overflow-hidden">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={URL.createObjectURL(f)} alt="" className="w-full h-full object-cover" />
                  <button onClick={() => setNewReviewPhotos(p => p.filter((_, j) => j !== i))}
                    className="absolute top-0.5 right-0.5 bg-black/55 text-white rounded-full w-5 h-5 flex items-center justify-center text-[10px]">✕</button>
                </div>
              ))}
              {myReviewPhotos.length + newReviewPhotos.length < 6 && (
                <label className="flex items-center justify-center w-16 h-16 rounded-lg border border-dashed border-gray-300 bg-white cursor-pointer hover:border-[#0C5C6C] text-lg">
                  📷
                  <input type="file" accept="image/*" multiple className="hidden"
                    onChange={e => {
                      const fs = Array.from(e.target.files ?? []);
                      if (fs.length) setNewReviewPhotos(p => [...p, ...fs].slice(0, 6));
                      e.target.value = '';
                    }} />
                </label>
              )}
            </div>
            <button
              onClick={submitReview}
              disabled={saving || myNote === 0}
              className="w-full bg-[#0C5C6C] text-white font-semibold py-2.5 rounded-lg disabled:opacity-50 transition-opacity"
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              {saving ? 'Envoi…' : 'Publier mon avis'}
            </button>
          </div>
        )}

        {loadingReviews ? (
          <div className="flex justify-center py-8">
            <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : reviews.length === 0 ? (
          <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
            Aucun avis pour le moment. Soyez le premier !
          </p>
        ) : (
          <div className="flex flex-col gap-2.5">
            {reviews.map(r => (
              <div key={r.id} className="bg-white rounded-xl shadow-sm p-3">
                <div className="flex items-center justify-between mb-1.5">
                  <div className="flex gap-0.5">
                    {[1, 2, 3, 4, 5].map(n => (
                      <span key={n} style={{ color: n <= r.note ? '#FDD835' : '#E5E7EB', fontSize: 13 }}>★</span>
                    ))}
                  </div>
                  <span className="text-[11px] text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                    {new Date(r.created_at).toLocaleDateString('fr-FR')}
                  </span>
                </div>
                {r.commentaire && (
                  <p className="text-sm text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{r.commentaire}</p>
                )}
                {(r.photos?.length ?? 0) > 0 && (
                  <div className="flex gap-1.5 mt-2 overflow-x-auto">
                    {r.photos!.map((src, i) => (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img key={i} src={src} alt="" onClick={() => window.open(src, '_blank')}
                        className="w-20 h-20 rounded-lg object-cover flex-shrink-0 cursor-pointer" />
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {cyanoModal && (
        <CyanoReportModal
          placeId={id}
          placeLat={place.lat ?? 46.6}
          placeLng={place.lng ?? 1.9}
          current={{
            lat: place.alerte_cyano_lat,
            lng: place.alerte_cyano_lng,
            statut: place.alerte_cyano_statut,
            photo_url: place.alerte_cyano_photo_url,
          }}
          profileId={profileId}
          forceConfirme={cyanoModal === 'confirm'}
          onClose={() => setCyanoModal(false)}
          onDone={() => { setCyanoModal(false); loadPlace(); }}
        />
      )}
    </div>
  );
}

// ── Carrousel photos (fiche détail) ─────────────────────────────────────────────

function PhotoCarousel({ photos, alt }: { photos: string[]; alt: string }) {
  const scrollerRef = useRef<HTMLDivElement>(null);
  const [index, setIndex] = useState(0);
  const [lightbox, setLightbox] = useState<number | null>(null);

  function onScroll() {
    const el = scrollerRef.current;
    if (!el || el.clientWidth === 0) return;
    setIndex(Math.round(el.scrollLeft / el.clientWidth));
  }

  return (
    <>
      <div className="relative rounded-2xl overflow-hidden" style={{ height: 220 }}>
        <div
          ref={scrollerRef}
          onScroll={onScroll}
          className="h-full w-full flex overflow-x-auto snap-x snap-mandatory scrollbar-hide"
        >
          {photos.map((url, i) => (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={i}
              src={url}
              alt={alt}
              onClick={() => setLightbox(i)}
              className="h-full w-full flex-shrink-0 object-cover snap-center cursor-pointer"
            />
          ))}
        </div>
        {photos.length > 1 && (
          <div className="absolute bottom-2.5 left-0 right-0 flex justify-center gap-1.5 pointer-events-none">
            {photos.map((_, i) => (
              <span
                key={i}
                className="w-1.5 h-1.5 rounded-full"
                style={{ backgroundColor: i === index ? 'rgba(255,255,255,0.95)' : 'rgba(255,255,255,0.5)' }}
              />
            ))}
          </div>
        )}
      </div>

      {lightbox !== null && (
        <div
          className="fixed inset-0 bg-black/85 z-50 flex items-center justify-center p-4"
          onClick={() => setLightbox(null)}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={photos[lightbox]} alt={alt} className="max-w-full max-h-full object-contain" />
        </div>
      )}
    </>
  );
}
