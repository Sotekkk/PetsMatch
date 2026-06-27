'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';

// ── Constants ─────────────────────────────────────────────────────────────────

const ESPECES = ['chien', 'chat', 'lapin', 'oiseau', 'nac', 'cheval', 'ovin', 'caprin', 'porcin', 'autre'];
const TAILLES = ['petit', 'moyen', 'grand'];
const SEXES   = ['male', 'femelle', 'inconnu'];

const BREED_FILES: Record<string, string> = {
  chien: 'dog_breeds', chat: 'cat_breeds', cheval: 'horse_breeds',
  lapin: 'rabbit_breeds', oiseau: 'bird_breeds', nac: 'nac_breeds',
  ovin: 'sheep_breeds', caprin: 'goat_breeds', porcin: 'pig_breeds',
};

// ── Page ──────────────────────────────────────────────────────────────────────

export default function DeclarerTrouvePage() {
  const { user, loading } = useAuth();
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);

  const [espece, setEspece]       = useState('chien');
  const [race, setRace]           = useState('');
  const [sexe, setSexe]           = useState('');
  const [taille, setTaille]       = useState('');
  const [couleur, setCouleur]     = useState('');
  const [numeroPuce, setNumeroPuce] = useState('');
  const [dateTrouve, setDateTrouve] = useState(new Date().toISOString().slice(0, 10));
  const [etatSante, setEtatSante] = useState('');
  const [comportement, setComportement] = useState('');
  const [description, setDescription]   = useState('');
  const [locSearch, setLocSearch] = useState('');
  const [rue, setRue]     = useState('');
  const [cp, setCp]       = useState('');
  const [ville, setVille] = useState('');
  const [pays, setPays]   = useState('France');
  const [region, setRegion] = useState('');
  const [lat, setLat]     = useState<number | null>(null);
  const [lng, setLng]     = useState<number | null>(null);
  const [contactEmail, setContactEmail]   = useState('');
  const [contactTel, setContactTel]       = useState('');
  const [contactMsg, setContactMsg]       = useState(true);

  // Photos: list of {blob, preview}
  const [photos, setPhotos]         = useState<{ blob: Blob; preview: string }[]>([]);
  const [cropSrc, setCropSrc]       = useState<string | null>(null);

  const [saving, setSaving]         = useState(false);
  const [errors, setErrors]         = useState<string[]>([]);

  // Breeds autocomplete
  const [breeds, setBreeds]               = useState<string[]>([]);
  const [breedSuggestions, setBreedSuggestions] = useState<string[]>([]);
  const [showBreedSugg, setShowBreedSugg] = useState(false);

  // Maps
  const [locPredictions, setLocPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const autocompleteService = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesService       = useRef<google.maps.places.PlacesService | null>(null);
  const locDebounce         = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [geolocating, setGeolocating] = useState(false);

  // ── Init ──────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (user?.email) setContactEmail(user.email);
  }, [user]);

  useEffect(() => {
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    if (!apiKey) return;
    setOptions({ key: apiKey, v: 'weekly', language: 'fr' });
    importLibrary('places').then(() => {
      autocompleteService.current = new window.google.maps.places.AutocompleteService();
      const div = document.createElement('div');
      placesService.current = new window.google.maps.places.PlacesService(div);
    }).catch(() => {});
  }, []);

  useEffect(() => {
    const file = BREED_FILES[espece];
    if (!file) { setBreeds([]); return; }
    fetch(`/breeds/${file}.json`)
      .then(r => r.json())
      .then((list: string[]) => setBreeds(list))
      .catch(() => setBreeds([]));
  }, [espece]);

  // ── Location ──────────────────────────────────────────────────────────────

  function onLocChange(val: string) {
    setLocSearch(val);
    setLat(null); setLng(null);
    if (locDebounce.current) clearTimeout(locDebounce.current);
    if (val.trim().length < 3) { setLocPredictions([]); return; }
    locDebounce.current = setTimeout(() => {
      autocompleteService.current?.getPlacePredictions(
        { input: val, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu'] }, language: 'fr' } as google.maps.places.AutocompletionRequest,
        (preds, status) => {
          if (status === window.google.maps.places.PlacesServiceStatus.OK && preds) setLocPredictions(preds);
          else setLocPredictions([]);
        }
      );
    }, 400);
  }

  function selectLocPrediction(pred: google.maps.places.AutocompletePrediction) {
    setLocPredictions([]);
    placesService.current?.getDetails(
      { placeId: pred.place_id, fields: ['address_components', 'geometry'] },
      (place, status) => {
        if (status !== window.google.maps.places.PlacesServiceStatus.OK || !place?.address_components) {
          setLocSearch(pred.description); return;
        }
        let num = '', route = '', postalCode = '', city = '', country = '', reg = '';
        for (const c of place.address_components) {
          if (c.types.includes('street_number')) num = c.long_name;
          if (c.types.includes('route')) route = c.long_name;
          if (c.types.includes('postal_code')) postalCode = c.long_name;
          if (c.types.includes('locality')) city = c.long_name;
          else if (c.types.includes('postal_town') && !city) city = c.long_name;
          if (c.types.includes('country')) country = c.long_name;
          if (c.types.includes('administrative_area_level_1')) reg = c.long_name;
        }
        if (num || route) setRue([num, route].filter(Boolean).join(' '));
        if (city) setVille(city);
        if (postalCode) setCp(postalCode);
        if (country) setPays(country);
        if (reg) setRegion(reg);
        if (place.geometry?.location) {
          setLat(place.geometry.location.lat());
          setLng(place.geometry.location.lng());
        }
        setLocSearch(pred.description);
      }
    );
  }

  async function geolocate() {
    setGeolocating(true);
    setLat(null); setLng(null);
    try {
      const pos = await new Promise<GeolocationPosition>((res, rej) =>
        navigator.geolocation.getCurrentPosition(res, rej, { timeout: 8000 }));
      setLat(pos.coords.latitude); setLng(pos.coords.longitude);
      const r = await fetch(
        `https://maps.googleapis.com/maps/api/geocode/json?latlng=${pos.coords.latitude},${pos.coords.longitude}&key=${process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY}&language=fr`
      );
      const data = await r.json();
      if (data.results?.[0]) {
        const comps = data.results[0].address_components as google.maps.GeocoderAddressComponent[];
        let c = '', p = '', ct = '', rg = '', st = '';
        for (const comp of comps) {
          if (comp.types.includes('route')) st = comp.long_name;
          if (comp.types.includes('postal_code')) c = comp.long_name;
          if (comp.types.includes('locality')) ct = comp.long_name;
          if (comp.types.includes('country')) p = comp.long_name;
          if (comp.types.includes('administrative_area_level_1')) rg = comp.long_name;
        }
        if (st) setRue(st); if (c) setCp(c); if (ct) setVille(ct); if (p) setPays(p); if (rg) setRegion(rg);
        setLocSearch([st, c, ct].filter(Boolean).join(', '));
      }
    } catch {
      alert('Géolocalisation impossible. Entrez la ville manuellement.');
    } finally {
      setGeolocating(false);
    }
  }

  // ── Breed autocomplete ─────────────────────────────────────────────────────

  function onRaceChange(val: string) {
    setRace(val);
    if (!val) { setBreedSuggestions([]); setShowBreedSugg(false); return; }
    const q = val.toLowerCase();
    const matches = breeds.filter(b => b.toLowerCase().includes(q)).slice(0, 6);
    setBreedSuggestions(matches);
    setShowBreedSugg(matches.length > 0);
  }

  // ── Photos ─────────────────────────────────────────────────────────────────

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setCropSrc(URL.createObjectURL(f));
    e.target.value = '';
  }

  function handleCropConfirm(blob: Blob) {
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropSrc(null);
    setPhotos(prev => [...prev, { blob, preview: URL.createObjectURL(blob) }]);
  }

  function removePhoto(idx: number) {
    setPhotos(prev => {
      URL.revokeObjectURL(prev[idx].preview);
      return prev.filter((_, i) => i !== idx);
    });
  }

  async function uploadPhotos(): Promise<string[]> {
    return Promise.all(
      photos.map((p, i) => uploadBlob(p.blob, `animaux_trouves/${user!.uid}/${Date.now()}_${i}.jpg`))
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const errs: string[] = [];
    if (photos.length === 0) errs.push('Au moins une photo');
    if (!ville.trim())       errs.push('Ville de découverte');
    if (!contactEmail.trim() && !contactTel.trim() && !contactMsg) errs.push('Au moins un moyen de contact');
    if (contactEmail.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail.trim())) errs.push('Email invalide');
    setErrors(errs);
    if (errs.length > 0) return;

    setSaving(true);
    try {
      const photoUrls = await uploadPhotos();
      await supabase.from('animaux_trouves').insert({
        user_uid:                   user!.uid,
        espece,
        race:                       race.trim() || null,
        sexe:                       sexe || null,
        taille:                     taille || null,
        couleur:                    couleur.trim() || null,
        numero_puce:                numeroPuce.trim() || null,
        date_trouve:                dateTrouve,
        etat_sante:                 etatSante.trim() || null,
        comportement:               comportement.trim() || null,
        description:                description.trim() || null,
        localisation_ville:         ville.trim(),
        localisation_code_postal:   cp.trim() || null,
        localisation_adresse:       [rue.trim(), cp.trim(), ville.trim()].filter(Boolean).join(', ') || null,
        pays:                       pays.trim() || 'France',
        region:                     region.trim() || null,
        lat:                        lat,
        lng:                        lng,
        photos:                     photoUrls,
        contact_email:              contactEmail.trim() || null,
        contact_telephone:          contactTel.trim() || null,
        contact_messagerie:         contactMsg,
        statut:                     'trouve',
        ...(activeProfileId ? { profile_id: activeProfileId } : {}),
      });
      router.push('/animaux-perdus?tab=trouves');
    } catch (err) {
      console.error(err);
      setErrors(['Une erreur est survenue. Veuillez réessayer.']);
      setSaving(false);
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  if (loading) {
    return (
      <div className="min-h-screen bg-[#F5F5F0] flex items-center justify-center">
        <div className="w-8 h-8 border-4 border-[#0C5C6C]/20 border-t-[#0C5C6C] rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#F5F5F0]">
      {/* AppBar */}
      <div className="bg-[#0C5C6C] px-4 py-4 sticky top-16 z-40">
        <div className="max-w-xl mx-auto flex items-center gap-3">
          <Link href="/animaux-perdus" className="text-white/70 hover:text-white">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7"/>
            </svg>
          </Link>
          <h1 className="text-white font-bold text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>
            Déclarer un animal trouvé
          </h1>
        </div>
      </div>

      <div className="max-w-xl mx-auto px-4 py-6">
        {/* Info banner */}
        <div className="bg-[#E8F4F6] border border-[#9ECFDA] rounded-xl p-4 mb-6">
          <p className="text-[#0C5C6C] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
            Votre déclaration sera visible publiquement et rapprochée des alertes d&apos;animaux perdus.
          </p>
        </div>

        {errors.length > 0 && (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-5">
            <ul className="list-disc list-inside text-red-600 text-sm">
              {errors.map((e, i) => <li key={i}>{e}</li>)}
            </ul>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-6">

          {/* Photos */}
          <div>
            <label className="block font-semibold text-sm mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
              Photos * <span className="text-gray-400 font-normal">(min. 1, max. 6)</span>
            </label>
            <p className="text-xs text-gray-400 mb-3">Ajoutez des photos claires de l&apos;animal trouvé.</p>
            <div className="flex flex-wrap gap-2">
              {photos.map((p, i) => (
                <div key={i} className="relative w-20 h-20">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={p.preview} alt="" className="w-full h-full object-cover rounded-xl" />
                  <button type="button" onClick={() => removePhoto(i)}
                    className="absolute top-0.5 right-0.5 w-5 h-5 bg-black/50 rounded-full flex items-center justify-center hover:bg-black/70">
                    <svg className="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12"/>
                    </svg>
                  </button>
                </div>
              ))}
              {photos.length < 6 && (
                <button type="button" onClick={() => fileRef.current?.click()}
                  className="w-20 h-20 rounded-xl border-2 border-dashed border-[#9ECFDA] bg-[#E8F4F6] flex flex-col items-center justify-center hover:bg-[#d4eef4] transition-colors">
                  <svg className="w-6 h-6 text-[#0C5C6C] mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4"/>
                  </svg>
                  <span className="text-[10px] text-[#0C5C6C] font-medium">Ajouter</span>
                </button>
              )}
              <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={onFileChange} />
            </div>
          </div>

          {/* Espèce */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Espèce *</label>
            <select value={espece} onChange={e => { setEspece(e.target.value); setRace(''); setBreedSuggestions([]); }}
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {ESPECES.map(es => (
                <option key={es} value={es}>{es.charAt(0).toUpperCase() + es.slice(1)}</option>
              ))}
            </select>
          </div>

          {/* Race autocomplete */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Race estimée</label>
            <div className="relative">
              <input value={race} onChange={e => onRaceChange(e.target.value)}
                onBlur={() => setTimeout(() => setShowBreedSugg(false), 150)}
                placeholder={breeds.length > 0 ? 'Rechercher une race…' : 'Ex : Labrador, Européen…'}
                className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
              {showBreedSugg && (
                <div className="absolute z-10 mt-1 w-full bg-white rounded-xl shadow-lg overflow-hidden">
                  {breedSuggestions.map(b => (
                    <button key={b} type="button" onMouseDown={() => { setRace(b); setShowBreedSugg(false); }}
                      className="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 flex items-center gap-2"
                      style={{ fontFamily: 'Galey, sans-serif' }}>
                      <span className="text-gray-400">🐾</span>{b}
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Sexe */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Sexe</label>
            <div className="flex gap-2 flex-wrap">
              {SEXES.map(s => (
                <button key={s} type="button" onClick={() => setSexe(sexe === s ? '' : s)}
                  className={`px-4 py-2 rounded-full text-sm font-semibold transition-colors ${
                    sexe === s ? 'bg-[#0C5C6C] text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                  }`} style={{ fontFamily: 'Galey, sans-serif' }}>
                  {s === 'male' ? 'Mâle' : s === 'femelle' ? 'Femelle' : 'Inconnu'}
                </button>
              ))}
            </div>
          </div>

          {/* Taille */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Taille</label>
            <div className="flex gap-2 flex-wrap">
              {TAILLES.map(t => (
                <button key={t} type="button" onClick={() => setTaille(taille === t ? '' : t)}
                  className={`px-4 py-2 rounded-full text-sm font-semibold transition-colors ${
                    taille === t ? 'bg-[#0C5C6C] text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                  }`} style={{ fontFamily: 'Galey, sans-serif' }}>
                  {t.charAt(0).toUpperCase() + t.slice(1)}
                </button>
              ))}
            </div>
          </div>

          {/* Couleur */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Couleur / signes particuliers</label>
            <input value={couleur} onChange={e => setCouleur(e.target.value)}
              placeholder="Ex : robe fauve, collier rouge…"
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
              style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>

          {/* Numéro de puce */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Numéro de puce (si visible)</label>
            <input value={numeroPuce} onChange={e => setNumeroPuce(e.target.value)}
              placeholder="Ex : 250269802345678" type="tel"
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
              style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>

          {/* Date */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Date de découverte *</label>
            <input type="date" value={dateTrouve} onChange={e => setDateTrouve(e.target.value)}
              max={new Date().toISOString().slice(0, 10)}
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
              style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>

          {/* État de santé */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>État de santé</label>
            <input value={etatSante} onChange={e => setEtatSante(e.target.value)}
              placeholder="Ex : bon état, blessé à la patte…"
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
              style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>

          {/* Comportement */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Comportement</label>
            <input value={comportement} onChange={e => setComportement(e.target.value)}
              placeholder="Ex : calme, craintif, agressif…"
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
              style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>

          {/* Localisation */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Lieu de découverte *</label>
            <div className="relative mb-2">
              <input value={locSearch} onChange={e => onLocChange(e.target.value)}
                placeholder="Rechercher une adresse ou entrez la ville…"
                className="w-full bg-white rounded-xl pl-10 pr-12 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
              <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
              </svg>
              <button type="button" onClick={geolocate} disabled={geolocating}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-[#0C5C6C] hover:text-[#094F5D] disabled:opacity-40">
                {geolocating
                  ? <div className="w-4 h-4 border-2 border-[#0C5C6C]/30 border-t-[#0C5C6C] rounded-full animate-spin" />
                  : <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
                    </svg>
                }
              </button>
              {locPredictions.length > 0 && (
                <div className="absolute z-10 mt-1 w-full bg-white rounded-xl shadow-lg overflow-hidden top-full left-0">
                  {locPredictions.slice(0, 5).map(p => (
                    <button key={p.place_id} type="button" onMouseDown={() => selectLocPrediction(p)}
                      className="w-full text-left px-4 py-3 text-sm hover:bg-gray-50 flex items-center gap-2 border-b border-gray-50 last:border-0"
                      style={{ fontFamily: 'Galey, sans-serif' }}>
                      <svg className="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                      </svg>
                      <span className="truncate">{p.description}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
            {lat !== null && (
              <div className="flex items-center gap-1.5 mb-2 text-green-600 text-xs">
                <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd"/>
                </svg>
                Coordonnées GPS enregistrées
              </div>
            )}
            <input value={rue} onChange={e => setRue(e.target.value)} placeholder="Rue / voie (optionnel)"
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30 mb-2"
              style={{ fontFamily: 'Galey, sans-serif' }} />
            <div className="flex gap-2 mb-2">
              <input value={cp} onChange={e => setCp(e.target.value)} placeholder="Code postal"
                className="w-32 bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
              <input value={ville} onChange={e => setVille(e.target.value)} placeholder="Ville *"
                className="flex-1 bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
            </div>
            <div className="flex gap-2">
              <input value={pays} onChange={e => setPays(e.target.value)} placeholder="Pays"
                className="flex-1 bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
              <input value={region} onChange={e => setRegion(e.target.value)} placeholder="Région"
                className="flex-1 bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
            </div>
          </div>

          {/* Description */}
          <div>
            <label className="block font-semibold text-sm mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Description complémentaire</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={4}
              placeholder="Circonstances de la découverte, lieu précis…"
              className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30 resize-none"
              style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>

          {/* Contact */}
          <div>
            <label className="block font-semibold text-sm mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Contact *</label>
            <p className="text-xs text-gray-400 mb-3">Au moins un moyen de contact requis.</p>
            <div className="space-y-2">
              <input value={contactEmail} onChange={e => setContactEmail(e.target.value)}
                type="email" placeholder="Email"
                className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
              <input value={contactTel} onChange={e => setContactTel(e.target.value)}
                type="tel" placeholder="Téléphone"
                className="w-full bg-white rounded-xl px-4 py-3.5 text-sm border-0 shadow-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                style={{ fontFamily: 'Galey, sans-serif' }} />
              <div className="bg-white rounded-xl px-4 py-3.5 shadow-sm flex items-center justify-between">
                <div>
                  <p className="font-semibold text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Messagerie PetsMatch</p>
                  <p className="text-xs text-gray-400">Permettre aux utilisateurs de vous contacter via l&apos;app</p>
                </div>
                <button type="button" onClick={() => setContactMsg(m => !m)}
                  className={`relative w-11 h-6 rounded-full transition-colors ${contactMsg ? 'bg-[#0C5C6C]' : 'bg-gray-200'}`}>
                  <span className={`absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${contactMsg ? 'translate-x-5' : ''}`} />
                </button>
              </div>
            </div>
          </div>

          {/* Submit */}
          <button type="submit" disabled={saving}
            className="w-full bg-[#0C5C6C] text-white py-4 rounded-xl font-bold text-base hover:bg-[#094F5D] transition-colors disabled:opacity-60 flex items-center justify-center gap-2"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {saving
              ? <><div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" /> Publication…</>
              : <><span>🐾</span> Publier la déclaration</>
            }
          </button>

        </form>
      </div>

      {/* Image crop modal */}
      {cropSrc && (
        <ImageCropModal
          src={cropSrc}
          onConfirm={handleCropConfirm}
          onCancel={() => { URL.revokeObjectURL(cropSrc); setCropSrc(null); }}
        />
      )}
    </div>
  );
}
