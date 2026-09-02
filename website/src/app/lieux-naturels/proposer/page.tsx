'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const NaturalPlacePicker = dynamic(() => import('@/components/NaturalPlacePicker'), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-full bg-gray-100 rounded-2xl">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  ),
});

const CAT_EMOJI: Record<string, string> = {
  foret: '🌲', plage: '🏖️', parc: '🌿', lac: '💧', riviere: '🏞️',
};
const CAT_LABEL: Record<string, string> = {
  foret: 'Forêt', plage: 'Plage', parc: 'Parc', lac: 'Lac', riviere: 'Rivière',
};
const CATEGORIES = Object.keys(CAT_LABEL);

export default function ProposerLieuPage() {
  const router = useRouter();
  const { user } = useAuth();
  const profileId = useActiveProfile();

  const [nom, setNom] = useState('');
  const [categorie, setCategorie] = useState('plage');
  const [adresse, setAdresse] = useState('');
  const [description, setDescription] = useState('');
  const [photos, setPhotos] = useState<File[]>([]);
  const [photoPreviews, setPhotoPreviews] = useState<string[]>([]);
  const [pos, setPos] = useState<{ lat: number; lng: number }>({ lat: 46.603354, lng: 1.888334 });
  const [posSet, setPosSet] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [geocoding, setGeocoding] = useState(false);
  const geocodeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (geocodeTimer.current) clearTimeout(geocodeTimer.current);
    const val = adresse.trim();
    if (val.length < 4) return;
    geocodeTimer.current = setTimeout(async () => {
      setGeocoding(true);
      try {
        const res = await fetch(`https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(val)}&limit=1`);
        const json = await res.json();
        const coords = json?.features?.[0]?.geometry?.coordinates;
        if (coords) {
          setPos({ lat: coords[1], lng: coords[0] });
          setPosSet(true);
        }
      } catch {
        /* ignore */
      } finally {
        setGeocoding(false);
      }
    }, 700);
    return () => { if (geocodeTimer.current) clearTimeout(geocodeTimer.current); };
  }, [adresse]);

  function selectPhoto(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    if (!files.length) return;
    setPhotos(prev => [...prev, ...files].slice(0, 8));
    setPhotoPreviews(prev => [...prev, ...files.map(f => URL.createObjectURL(f))].slice(0, 8));
    e.target.value = '';
  }

  function removePhoto(i: number) {
    setPhotos(prev => prev.filter((_, j) => j !== i));
    setPhotoPreviews(prev => prev.filter((_, j) => j !== i));
  }

  function useMyPosition() {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (p) => { setPos({ lat: p.coords.latitude, lng: p.coords.longitude }); setPosSet(true); },
      () => {},
      { enableHighAccuracy: false, timeout: 8000 },
    );
  }

  async function submit() {
    if (!user) { setError('Connecte-toi pour proposer un lieu.'); return; }
    if (!nom.trim()) { setError('Le nom du lieu est obligatoire.'); return; }
    if (!posSet) { setError('Place le repère sur la carte à l\'emplacement du lieu.'); return; }

    setSaving(true);
    setError(null);
    try {
      const photoUrls: string[] = [];
      for (let i = 0; i < photos.length; i++) {
        const f = photos[i];
        const path = `natural_places/${Date.now()}_${i}_${user.uid}.jpg`;
        const { error: upErr } = await supabase.storage.from('media').upload(path, f, {
          contentType: f.type || 'application/octet-stream', upsert: true,
        });
        if (upErr) throw upErr;
        photoUrls.push(supabase.storage.from('media').getPublicUrl(path).data.publicUrl);
      }

      const { error: insErr } = await supabase.from('natural_places').insert({
        nom: nom.trim(),
        categorie,
        lat: pos.lat,
        lng: pos.lng,
        adresse: adresse.trim() || null,
        description: description.trim() || null,
        photos: photoUrls,
        photo_url: photoUrls[0] ?? null,
        statut: 'en_attente',
        submitted_by_uid: user.uid,
        submitted_by_profile_id: profileId || null,
      });
      if (insErr) throw insErr;

      router.push('/lieux-naturels?propose=1');
    } catch (e) {
      console.error(e);
      setError('Erreur lors de l\'envoi, réessaie.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#F5F5F0]">
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-2xl mx-auto">
          <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
            📍 Proposer un lieu
          </h1>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6">
        <div className="bg-[#0C5C6C]/8 rounded-xl p-3 mb-6 text-sm text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
          ℹ️ Ton lieu sera vérifié par un administrateur avant d&apos;apparaître pour tout le monde.
        </div>

        {error && (
          <div className="bg-red-50 text-red-600 rounded-xl p-3 mb-4 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
            {error}
          </div>
        )}

        <div className="space-y-5">
          <div>
            <label className="block text-sm font-bold mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Nom du lieu *
            </label>
            <input
              value={nom}
              onChange={(e) => setNom(e.target.value)}
              placeholder="Ex: Plage du Grand Travers"
              className="w-full rounded-lg border border-gray-200 px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]"
              style={{ fontFamily: 'Galey, sans-serif' }}
            />
          </div>

          <div>
            <label className="block text-sm font-bold mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Catégorie *
            </label>
            <div className="flex flex-wrap gap-2">
              {CATEGORIES.map((cat) => (
                <button
                  key={cat}
                  onClick={() => setCategorie(cat)}
                  className="px-3.5 py-1.5 rounded-full text-xs font-semibold border transition-colors"
                  style={{
                    fontFamily: 'Galey, sans-serif',
                    backgroundColor: categorie === cat ? '#0C5C6C' : 'white',
                    color: categorie === cat ? 'white' : '#1E2025',
                    borderColor: categorie === cat ? '#0C5C6C' : '#E5E7EB',
                  }}
                >
                  {CAT_EMOJI[cat]} {CAT_LABEL[cat]}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="flex items-center gap-2 text-sm font-bold mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Adresse / ville
              {geocoding && (
                <span className="w-3 h-3 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
              )}
            </label>
            <input
              value={adresse}
              onChange={(e) => setAdresse(e.target.value)}
              placeholder="Ex: Carnon, Hérault"
              className="w-full rounded-lg border border-gray-200 px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]"
              style={{ fontFamily: 'Galey, sans-serif' }}
            />
            <p className="text-xs text-gray-400 mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>
              La carte se positionne automatiquement sur l&apos;adresse tapée
            </p>
          </div>

          <div>
            <label className="block text-sm font-bold mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Description
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Règles chiens, accès, équipements..."
              rows={4}
              className="w-full rounded-lg border border-gray-200 px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none"
              style={{ fontFamily: 'Galey, sans-serif' }}
            />
          </div>

          <div>
            <label className="block text-sm font-bold mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Photos
            </label>
            <div className="flex flex-wrap gap-2">
              {photoPreviews.map((src, i) => (
                <div key={i} className="relative w-24 h-24 rounded-xl overflow-hidden">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={src} alt="" className="w-full h-full object-cover" />
                  <button
                    onClick={() => removePhoto(i)}
                    className="absolute top-1 right-1 bg-black/55 text-white rounded-full w-6 h-6 flex items-center justify-center text-xs"
                  >
                    ✕
                  </button>
                </div>
              ))}
              {photos.length < 8 && (
                <label className="flex flex-col items-center justify-center w-24 h-24 rounded-xl border border-dashed border-gray-300 bg-white cursor-pointer hover:border-[#0C5C6C] transition-colors">
                  <span className="text-xl">📷</span>
                  <span className="text-[10px] text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>Ajouter</span>
                  <input type="file" accept="image/*" multiple className="hidden" onChange={selectPhoto} />
                </label>
              )}
            </div>
            {photoPreviews.length === 0 && (
              <p className="text-xs text-gray-400 mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>Optionnel — plusieurs photos possibles</p>
            )}
          </div>

          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="block text-sm font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>
                Position sur la carte *
              </label>
              <button
                onClick={useMyPosition}
                className="text-xs font-semibold text-[#0C5C6C] hover:underline"
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                📍 Utiliser ma position
              </button>
            </div>
            <p className="text-xs text-gray-400 mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              Clique sur la carte ou déplace le repère à l&apos;endroit exact du lieu
            </p>
            <div className="rounded-2xl overflow-hidden border border-gray-200" style={{ height: 260 }}>
              <NaturalPlacePicker
                lat={pos.lat}
                lng={pos.lng}
                onChange={(lat, lng) => { setPos({ lat, lng }); setPosSet(true); }}
              />
            </div>
          </div>

          <button
            onClick={submit}
            disabled={saving}
            className="w-full bg-[#0C5C6C] text-white rounded-xl py-3 font-bold text-sm disabled:opacity-50 transition-opacity"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            {saving ? 'Envoi...' : 'Envoyer pour validation'}
          </button>
        </div>
      </div>
    </div>
  );
}
