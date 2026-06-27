'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { updateProfile } from 'firebase/auth';
import { doc, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { uploadPhoto } from '@/lib/upload-media';
import ReactCrop, { type Crop, type PixelCrop, centerCrop, makeAspectCrop } from 'react-image-crop';
import 'react-image-crop/dist/ReactCrop.css';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';
import { fromPostalCode } from '@/lib/french-geo';

// ── Species config ─────────────────────────────────────────────────────────────

const ESPECES_CONFIG = [
  { value: 'chien',  label: 'Chien',  emoji: '🐕', breedFile: 'dog_breeds' },
  { value: 'chat',   label: 'Chat',   emoji: '🐈', breedFile: 'cat_breeds' },
  { value: 'cheval', label: 'Cheval', emoji: '🐴', breedFile: 'horse_breeds' },
  { value: 'lapin',  label: 'Lapin',  emoji: '🐰', breedFile: 'rabbit_breeds' },
  { value: 'oiseau', label: 'Oiseau', emoji: '🦜', breedFile: 'bird_breeds' },
  { value: 'ovin',   label: 'Ovin',   emoji: '🐑', breedFile: 'sheep_breeds' },
  { value: 'caprin', label: 'Caprin', emoji: '🐐', breedFile: 'goat_breeds' },
  { value: 'porcin', label: 'Porcin', emoji: '🐷', breedFile: 'pig_breeds' },
  { value: 'nac',    label: 'NAC',    emoji: '🐾', breedFile: 'nac_breeds' },
  { value: 'autre',  label: 'Autre',  emoji: '🐾', breedFile: null },
];

interface EspeceEntry { espece: string; races: string[] }

// ── Crop helpers ───────────────────────────────────────────────────────────────

async function getCroppedFile(img: HTMLImageElement, crop: PixelCrop, filename = 'photo.jpg'): Promise<File> {
  const canvas = document.createElement('canvas');
  const scaleX = img.naturalWidth / img.width;
  const scaleY = img.naturalHeight / img.height;
  canvas.width = Math.floor(crop.width * scaleX);
  canvas.height = Math.floor(crop.height * scaleY);
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(img, crop.x * scaleX, crop.y * scaleY, crop.width * scaleX, crop.height * scaleY, 0, 0, canvas.width, canvas.height);
  return new Promise(res => canvas.toBlob(b => res(new File([b!], filename, { type: 'image/jpeg' })), 'image/jpeg', 0.92));
}

function CropModal({ src, onConfirm, onCancel, aspect = 16 / 9, title = 'Recadrer', hint, filename = 'photo.jpg' }: {
  src: string;
  onConfirm: (file: File, preview: string) => void;
  onCancel: () => void;
  aspect?: number;
  title?: string;
  hint?: string;
  filename?: string;
}) {
  const imgRef = useRef<HTMLImageElement>(null);
  const [crop, setCrop] = useState<Crop>();
  const [completedCrop, setCompletedCrop] = useState<PixelCrop>();

  function onImageLoad(e: React.SyntheticEvent<HTMLImageElement>) {
    const { width, height } = e.currentTarget;
    setCrop(centerCrop(makeAspectCrop({ unit: '%', width: aspect >= 1 ? 80 : 60 }, aspect, width, height), width, height));
  }

  async function handleConfirm() {
    if (!imgRef.current || !completedCrop) return;
    const file = await getCroppedFile(imgRef.current, completedCrop, filename);
    onConfirm(file, URL.createObjectURL(file));
  }

  return (
    <div className="fixed inset-0 bg-black/80 z-50 flex flex-col items-center justify-center p-4">
      <div className="bg-white rounded-2xl overflow-hidden w-full max-w-2xl shadow-2xl">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</h3>
          <div className="flex gap-2">
            <button onClick={onCancel}
              className="text-sm text-gray-500 hover:text-gray-700 px-4 py-2 rounded-xl border border-gray-200 hover:bg-gray-50 transition-colors">
              Annuler
            </button>
            <button onClick={handleConfirm}
              className="text-sm font-semibold text-white bg-[#0C5C6C] hover:bg-[#094F5D] px-4 py-2 rounded-xl transition-colors">
              Appliquer
            </button>
          </div>
        </div>
        <div className="bg-gray-900 p-4 flex items-center justify-center">
          <ReactCrop crop={crop} onChange={(_, pct) => setCrop(pct)} onComplete={c => setCompletedCrop(c)}
            aspect={aspect} className="max-h-[60vh]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img ref={imgRef} src={src} alt="Aperçu" onLoad={onImageLoad}
              className="max-w-full max-h-[60vh] object-contain" />
          </ReactCrop>
        </div>
        {hint && <p className="text-center text-xs text-gray-400 py-2">{hint}</p>}
      </div>
    </div>
  );
}

// ── Breed picker ───────────────────────────────────────────────────────────────

function BreedPicker({ espece, allBreeds, selected, onClose }: {
  espece: string; allBreeds: string[]; selected: string[];
  onClose: (result: string[] | null) => void;
}) {
  const cfg = ESPECES_CONFIG.find(e => e.value === espece);
  const [search, setSearch] = useState('');
  const [picks, setPicks] = useState<string[]>([...selected]);
  const [freeText, setFreeText] = useState('');

  const filtered = allBreeds.length > 0
    ? allBreeds.filter(b => b.toLowerCase().includes(search.toLowerCase()))
    : [];

  const toggle = (b: string) => setPicks(p => p.includes(b) ? p.filter(x => x !== b) : [...p, b]);

  function addFree() {
    const v = freeText.trim();
    if (v && !picks.includes(v)) setPicks(p => [...p, v]);
    setFreeText('');
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md max-h-[80vh] flex flex-col">
        <div className="flex items-center justify-between px-5 pt-5 pb-3 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E] text-base">
            {cfg?.emoji} Races — {cfg?.label}
          </h3>
          <button onClick={() => onClose(picks)}
            className="bg-[#6E9E57] text-white text-sm font-semibold px-4 py-1.5 rounded-full hover:bg-[#5A8A45]">
            Valider
          </button>
        </div>
        {picks.length > 0 && (
          <div className="px-4 pt-3 flex flex-wrap gap-1.5">
            {picks.map(b => (
              <span key={b} className="flex items-center gap-1 bg-[#EEF5EA] border border-[#6E9E57]/40 text-[#1F2A2E] text-xs px-2.5 py-1 rounded-full">
                {b}
                <button onClick={() => toggle(b)} className="text-gray-400 hover:text-red-400 ml-0.5">×</button>
              </span>
            ))}
          </div>
        )}
        <div className="px-4 pt-3 pb-2">
          <input value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher une race…"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#6E9E57]" />
        </div>
        <div className="flex-1 overflow-y-auto px-2 pb-3">
          {filtered.length > 0 ? filtered.map(b => {
            const sel = picks.includes(b);
            return (
              <button key={b} onClick={() => toggle(b)}
                className={`w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-sm text-left transition-colors ${
                  sel ? 'bg-[#EEF5EA] text-[#1F2A2E] font-medium' : 'hover:bg-gray-50 text-gray-700'
                }`}>
                {b}
                {sel && <span className="text-[#6E9E57] text-base">✓</span>}
              </button>
            );
          }) : (
            <div className="px-3 pt-3">
              <p className="text-xs text-gray-400 mb-2">Saisie libre</p>
              <div className="flex gap-2">
                <input value={freeText} onChange={e => setFreeText(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && addFree()}
                  placeholder="Nom de la race"
                  className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#6E9E57]" />
                <button onClick={addFree}
                  className="bg-[#6E9E57] text-white text-sm px-3 py-2 rounded-xl hover:bg-[#5A8A45]">+</button>
              </div>
            </div>
          )}
        </div>
        <button onClick={() => onClose(null)} className="pb-4 text-xs text-gray-400 hover:text-gray-600">Annuler</button>
      </div>
    </div>
  );
}

// ── UI helpers ─────────────────────────────────────────────────────────────────

function ReadOnly({ label, value, icon }: { label: string; value: string; icon?: string }) {
  return (
    <div className="flex items-center gap-3 px-3 py-2.5 bg-gray-50 border border-gray-200 rounded-xl">
      {icon && <span className="text-sm">{icon}</span>}
      <div className="flex-1 min-w-0">
        <p className="text-[10px] text-gray-400 uppercase tracking-wide">{label}</p>
        <p className="text-sm text-[#1F2A2E] font-medium truncate">{value}</p>
      </div>
      <span className="text-gray-300 text-xs">🔒</span>
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 mb-4">
      <h2 className="font-bold text-[#1F2A2E] text-sm mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</h2>
      {children}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  const hasRequired = label.endsWith(' *');
  const baseLabel = hasRequired ? label.slice(0, -2) : label;
  return (
    <div className="mb-3">
      <label className="block text-xs font-medium text-gray-500 mb-1">
        {baseLabel}{hasRequired && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      {children}
    </div>
  );
}

const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#6E9E57] bg-white';

// ── Main page ──────────────────────────────────────────────────────────────────

export default function EleveurProfilEditPage() {
  const { user, userData, loading, refreshUserData } = useAuth();
  const router = useRouter();

  // Identity
  const [firstname, setFirstname] = useState('');
  const [lastname, setLastname] = useState('');
  const [dob, setDob] = useState('');

  // Élevage
  const [nameElevage, setNameElevage] = useState('');
  const [phoneElevage, setPhoneElevage] = useState('');
  const [description, setDescription] = useState('');

  // Adresse élevage + autocomplete
  const [rue, setRue] = useState('');
  const [cp, setCp] = useState('');
  const [villeElevage, setVilleElevage] = useState('');
  const [pays, setPays] = useState('France');
  const [adresseElevSearch, setAdresseElevSearch] = useState('');
  const [adresseElevPredictions, setAdresseElevPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const autocompleteService = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesService = useRef<google.maps.places.PlacesService | null>(null);
  const adresseElevDebounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Espèces
  const [especesElevees, setEspecesElevees] = useState<EspeceEntry[]>([]);
  const [allBreeds, setAllBreeds] = useState<Record<string, string[]>>({});
  const [breedPickerEspece, setBreedPickerEspece] = useState<string | null>(null);

  // Réseaux sociaux
  const [instagram, setInstagram] = useState('');
  const [facebook, setFacebook] = useState('');
  const [siteWeb, setSiteWeb] = useState('');

  // Informations administratives
  const [siret, setSiret] = useState('');
  const [tva, setTva] = useState('');
  const [acacedNum, setAcacedNum] = useState('');
  const [acacedDateObtention, setAcacedDateObtention] = useState('');
  const [acacedDateRenewal, setAcacedDateRenewal] = useState('');

  // Documents
  const [siretDocFile, setSiretDocFile] = useState<File | null>(null);
  const [siretDocUrl, setSiretDocUrl] = useState<string | null>(null);
  const [acacedDocFile, setAcacedDocFile] = useState<File | null>(null);
  const [acacedDocUrl, setAcacedDocUrl] = useState<string | null>(null);
  const siretDocRef = useRef<HTMLInputElement>(null);
  const acacedDocRef = useRef<HTMLInputElement>(null);

  // Photos
  const [bannerFile, setBannerFile] = useState<File | null>(null);
  const [bannerPreview, setBannerPreview] = useState<string | null>(null);
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [cropAvatarSrc, setCropAvatarSrc] = useState<string | null>(null);
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const bannerInputRef = useRef<HTMLInputElement>(null);
  const avatarInputRef = useRef<HTMLInputElement>(null);

  // UI
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [formErrors, setFormErrors] = useState<string[]>([]);

  // ACACED expiry
  let acacedStatus: { color: string; label: string } | null = null;
  if (acacedDateObtention) {
    const base = new Date(acacedDateRenewal || acacedDateObtention);
    const exp = new Date(base.getFullYear() + 10, base.getMonth(), base.getDate());
    const now = new Date();
    const daysLeft = Math.floor((exp.getTime() - now.getTime()) / 86400000);
    if (daysLeft < 0) acacedStatus = { color: 'red', label: 'ACACED expiré — renouvellement requis' };
    else if (daysLeft < 180) acacedStatus = { color: 'orange', label: `Expire dans ${daysLeft} jours (${exp.toLocaleDateString('fr-FR')})` };
    else acacedStatus = { color: 'green', label: `Valide jusqu'au ${exp.toLocaleDateString('fr-FR')}` };
  }

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  // Initialize form from userData (once)
  const initialized = useRef(false);
  useEffect(() => {
    if (!userData || initialized.current) return;
    initialized.current = true;
    setFirstname(userData.firstname ?? '');
    setLastname(userData.lastname ?? '');
    setDob(userData.dob ?? '');
    setNameElevage(userData.nameElevage ?? '');
    setPhoneElevage(userData.numeroElevage ?? '');
    setDescription(userData.descriptionElevage ?? '');
    setRue(userData.rueElevage ?? '');
    setCp(userData.codePostalElevage ?? '');
    setVilleElevage(userData.villeElevage ?? '');
    setPays(userData.paysElevage ?? 'France');
    setSiret(userData.siret ?? '');
    setTva(userData.numeroTva ?? '');
    setAcacedNum(userData.acaced ?? '');
    setSiretDocUrl(userData.kbisUrl ?? null);
    setAcacedDocUrl(userData.acacedDocUrl ?? null);
    setAcacedDateObtention(userData.acacedDateObtention ?? '');
    setAcacedDateRenewal(userData.acacedDateRenewal ?? '');
    setInstagram(userData.instagram ?? '');
    setFacebook(userData.facebook ?? '');
    setSiteWeb(userData.siteWeb ?? '');
    const rawEsp = userData.especesElevees ?? [];
    if (rawEsp.length > 0) {
      setEspecesElevees(rawEsp.map((e: EspeceEntry) => ({ espece: e.espece, races: e.races ?? [] })));
    } else {
      const fallback: EspeceEntry[] = [];
      if (userData.isDog) fallback.push({ espece: 'chien', races: userData.dogBreeds ?? [] });
      if (userData.isCat) fallback.push({ espece: 'chat', races: userData.catBreeds ?? [] });
      setEspecesElevees(fallback);
    }
  }, [userData]);

  // Google Maps Places
  useEffect(() => {
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    if (!apiKey) return;
    setOptions({ key: apiKey, v: 'weekly', language: 'fr' });
    importLibrary('places').then(() => {
      autocompleteService.current = new window.google.maps.places.AutocompleteService();
      const dummyDiv = document.createElement('div');
      placesService.current = new window.google.maps.places.PlacesService(dummyDiv);
    }).catch(() => {});
  }, []);

  function onAdresseElevSearchChange(val: string) {
    setAdresseElevSearch(val);
    if (adresseElevDebounce.current) clearTimeout(adresseElevDebounce.current);
    if (val.trim().length < 3) { setAdresseElevPredictions([]); return; }
    adresseElevDebounce.current = setTimeout(() => {
      autocompleteService.current?.getPlacePredictions(
        { input: val, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu'] }, language: 'fr' } as google.maps.places.AutocompletionRequest,
        (preds, status) => {
          if (status === window.google.maps.places.PlacesServiceStatus.OK && preds) {
            setAdresseElevPredictions(preds);
          } else {
            setAdresseElevPredictions([]);
          }
        }
      );
    }, 400);
  }

  function selectAdresseElevPrediction(pred: google.maps.places.AutocompletePrediction) {
    setAdresseElevSearch(pred.description);
    setAdresseElevPredictions([]);
    placesService.current?.getDetails(
      { placeId: pred.place_id, fields: ['address_components'] },
      (place, status) => {
        if (status !== window.google.maps.places.PlacesServiceStatus.OK || !place?.address_components) return;
        let num = '', route = '', postalCode = '', city = '';
        for (const c of place.address_components) {
          if (c.types.includes('street_number')) num = c.long_name;
          if (c.types.includes('route')) route = c.long_name;
          if (c.types.includes('postal_code')) postalCode = c.long_name;
          if (c.types.includes('locality')) city = c.long_name;
          else if (c.types.includes('postal_town') && !city) city = c.long_name;
        }
        if (city) setVilleElevage(city);
        if (postalCode) setCp(postalCode);
        if (num || route) {
          setRue([num, route].filter(Boolean).join(' '));
          setAdresseElevSearch([num, route].filter(Boolean).join(' '));
        }
      }
    );
  }

  const loadBreeds = useCallback(async (espece: string) => {
    if (allBreeds[espece] !== undefined) return;
    const cfg = ESPECES_CONFIG.find(e => e.value === espece);
    if (!cfg?.breedFile) { setAllBreeds(prev => ({ ...prev, [espece]: [] })); return; }
    try {
      const res = await fetch(`/breeds/${cfg.breedFile}.json`);
      const data: string[] = await res.json();
      setAllBreeds(prev => ({ ...prev, [espece]: data }));
    } catch {
      setAllBreeds(prev => ({ ...prev, [espece]: [] }));
    }
  }, [allBreeds]);

  function toggleEspece(espece: string) {
    setEspecesElevees(prev => {
      const exists = prev.find(e => e.espece === espece);
      if (exists) return prev.filter(e => e.espece !== espece);
      loadBreeds(espece);
      return [...prev, { espece, races: [] }];
    });
  }

  function openBreedPicker(espece: string) {
    loadBreeds(espece);
    setBreedPickerEspece(espece);
  }

  function handleBreedPickerClose(result: string[] | null) {
    if (result !== null && breedPickerEspece) {
      setEspecesElevees(prev => prev.map(e =>
        e.espece === breedPickerEspece ? { ...e, races: result } : e
      ));
    }
    setBreedPickerEspece(null);
  }

  function handleBannerChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    e.target.value = '';
    setCropSrc(URL.createObjectURL(file));
  }

  function handleAvatarChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    e.target.value = '';
    setCropAvatarSrc(URL.createObjectURL(file));
  }

  function validateForm(): string[] {
    const errs: string[] = [];
    if (!firstname.trim()) errs.push('Prénom requis');
    if (!lastname.trim()) errs.push('Nom requis');
    if (!dob) errs.push('Date de naissance requise');
    if (!nameElevage.trim()) errs.push("Nom de l'élevage requis");
    if (!phoneElevage.trim()) errs.push("Téléphone de l'élevage requis");
    if (!rue.trim()) errs.push("Rue / voie de l'élevage requise");
    if (!cp.trim()) errs.push("Code postal de l'élevage requis");
    if (!villeElevage.trim()) errs.push("Ville de l'élevage requise");
    if (!pays.trim()) errs.push("Pays de l'élevage requis");
    if (!siret.trim()) errs.push('SIRET requis');
    if (!siretDocUrl && !siretDocFile) errs.push('Justificatif SIRET (KBIS ou attestation RNE) requis');
    if (!acacedNum.trim()) errs.push('Numéro ACACED requis');
    if (!acacedDateObtention) errs.push("Date d'obtention ACACED requise");
    if (!acacedDocUrl && !acacedDocFile) errs.push('Certificat ACACED requis');
    return errs;
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    const errs = validateForm();
    if (errs.length > 0) { setFormErrors(errs); return; }
    setFormErrors([]);
    setSaving(true);
    setSaved(false);
    try {
      const isDog = especesElevees.some(e => e.espece === 'chien');
      const isCat = especesElevees.some(e => e.espece === 'chat');
      const adresse = [rue, cp, villeElevage].filter(Boolean).join(', ');
      const geo = fromPostalCode(cp);

      const payload: Record<string, unknown> = {
        uid: user!.uid,
        firstname,
        lastname,
        date_of_birth: dob,
        name_elevage: nameElevage,
        numero_elevage: phoneElevage,
        desc_entreprise: description,
        rue_elevage: rue,
        code_postal_elevage: cp,
        ville_elevage: villeElevage,
        pays_elevage: pays,
        adress_elevage: adresse,
        siret: siret.trim(),
        numero_tva: tva.trim(),
        acaced: acacedNum.trim(),
        instagram: instagram.trim(),
        facebook: facebook.trim(),
        site_web: siteWeb.trim(),
        especes_elevees: especesElevees,
        is_dog: isDog,
        is_cat: isCat,
        dog_breeds: isDog ? (especesElevees.find(e => e.espece === 'chien')?.races ?? []) : [],
        cat_breeds: isCat ? (especesElevees.find(e => e.espece === 'chat')?.races ?? []) : [],
      };

      if (acacedDateObtention) payload.acaced_date_obtention = acacedDateObtention;
      if (acacedDateRenewal) payload.acaced_date_renewal = acacedDateRenewal;

      // Upload SIRET doc
      if (siretDocFile) {
        const ext = siretDocFile.name.split('.').pop() ?? 'jpg';
        const path = `documents/${user!.uid}/kbis.${ext}`;
        const { data: up } = await supabase.storage.from('petsmatch').upload(path, siretDocFile, { upsert: true });
        if (up) {
          const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
          payload.kbis_url = pub.publicUrl;
          setSiretDocUrl(pub.publicUrl);
        }
      }

      // Upload ACACED doc
      if (acacedDocFile) {
        const ext = acacedDocFile.name.split('.').pop() ?? 'jpg';
        const path = `documents/${user!.uid}/acaced.${ext}`;
        const { data: up } = await supabase.storage.from('petsmatch').upload(path, acacedDocFile, { upsert: true });
        if (up) {
          const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
          payload.acaced_doc_url = pub.publicUrl;
          setAcacedDocUrl(pub.publicUrl);
        }
      }

      // Upload bannière
      if (bannerFile) {
        payload.banner_url = await uploadPhoto(
          bannerFile,
          `profiles/${user!.uid}/banner.jpg`,
          { maxDim: 1920, quality: 0.85 },
        );
      }

      // Upload avatar
      if (avatarFile) {
        const avatarUrl = await uploadPhoto(
          avatarFile,
          `profiles/${user!.uid}/photo.jpg`,
          { maxDim: 800, quality: 0.85 },
        );
        payload.profile_picture_url = avatarUrl;
        payload.profile_picture_url_elevage = avatarUrl;
      }

      // Save to Supabase users
      const { error: usersErr } = await supabase.from('users').upsert(payload, { onConflict: 'uid' });
      if (usersErr) { setFormErrors([`[users] ${usersErr.message}`]); return; }

      // Sync to user_profiles
      const profileUpdate: Record<string, unknown> = {
        firstname,
        lastname,
        date_of_birth: dob,
        nom: nameElevage,
        phone_number: phoneElevage,
        desc_entreprise: description,
        rue_pro: rue,
        code_postal_pro: cp,
        ville_pro: villeElevage,
        pays_pro: pays,
        adresse: adresse,
        departement: geo?.departement ?? '',
        region: geo?.region ?? '',
        siret: siret.trim(),
        instagram: instagram.trim(),
        facebook: facebook.trim(),
        site_web: siteWeb.trim(),
      };
      if (payload.banner_url) profileUpdate.banner_url = payload.banner_url;
      if (payload.profile_picture_url_elevage) profileUpdate.profile_picture_url_pro = payload.profile_picture_url_elevage;

      await supabase.from('user_profiles')
        .update(profileUpdate)
        .eq('uid', user!.uid)
        .eq('is_main', true);

      // Sync to Firestore
      try {
        const firestoreUpdate: Record<string, unknown> = {
          firstname,
          lastname,
          dateofbirth: dob,
          nameElevage,
          descEntreprise: description,
          villeElevage,
          especesElevees,
          isDog,
          isCat,
          dogBreeds: isDog ? (especesElevees.find(e => e.espece === 'chien')?.races ?? []) : [],
          catBreeds: isCat ? (especesElevees.find(e => e.espece === 'chat')?.races ?? []) : [],
          instagram: instagram.trim(),
          facebook: facebook.trim(),
          siteWeb: siteWeb.trim(),
          numeroTVA: tva.trim(),
        };
        if (payload.banner_url) firestoreUpdate.bannerUrl = payload.banner_url as string;
        await updateDoc(doc(db, 'users', user!.uid), firestoreUpdate);
      } catch { /* doc may not exist yet */ }

      try {
        await updateProfile(user!, { displayName: nameElevage });
      } catch { /* non bloquant */ }

      await refreshUserData();
      setSaved(true);
      setTimeout(() => {
        setSaved(false);
        router.push('/elevage/profil');
      }, 1500);
    } finally {
      setSaving(false);
    }
  }

  if (loading || !user) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const avatar = userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl;
  const currentBanner = userData?.bannerUrl;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 pb-20">
      {/* Crop modals */}
      {cropSrc && (
        <CropModal
          src={cropSrc}
          aspect={16 / 9}
          title="Recadrer la bannière"
          hint="Format 16:9 — déplacez et redimensionnez la sélection"
          filename="banner.jpg"
          onConfirm={(file, preview) => { setBannerFile(file); setBannerPreview(preview); setCropSrc(null); }}
          onCancel={() => setCropSrc(null)}
        />
      )}
      {cropAvatarSrc && (
        <CropModal
          src={cropAvatarSrc}
          aspect={1}
          title="Recadrer la photo de profil"
          filename="avatar.jpg"
          onConfirm={(file, preview) => { setAvatarFile(file); setAvatarPreview(preview); setCropAvatarSrc(null); }}
          onCancel={() => setCropAvatarSrc(null)}
        />
      )}
      {breedPickerEspece && (
        <BreedPicker
          espece={breedPickerEspece}
          allBreeds={allBreeds[breedPickerEspece] ?? []}
          selected={especesElevees.find(e => e.espece === breedPickerEspece)?.races ?? []}
          onClose={handleBreedPickerClose}
        />
      )}

      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.back()}
          className="text-gray-400 hover:text-gray-600 transition-colors">
          <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h1 className="text-2xl font-bold text-[#1F2A2E] flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          Modifier mon profil
        </h1>
      </div>

      <form onSubmit={handleSave} className="space-y-4">

        {/* ── Bannière + Photo ── */}
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden mb-4">
          <button type="button" onClick={() => bannerInputRef.current?.click()}
            className="w-full h-52 bg-gradient-to-br from-[#0C5C6C] to-[#6E9E57] relative overflow-hidden block group">
            {(bannerPreview ?? currentBanner) && (
              <Image src={bannerPreview ?? currentBanner!} alt="Bannière" fill className="object-cover" />
            )}
            <div className="absolute inset-0 flex items-center justify-center bg-black/20 group-hover:bg-black/35 transition-colors">
              <div className="flex flex-col items-center gap-1 text-white">
                <svg className="w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
                <span className="text-xs font-medium">Modifier la bannière</span>
              </div>
            </div>
          </button>
          <input ref={bannerInputRef} type="file" accept="image/*" className="hidden" onChange={handleBannerChange} />
          <input ref={avatarInputRef} type="file" accept="image/*" className="hidden" onChange={handleAvatarChange} />
          <div className="flex flex-col items-center relative z-10 pb-4">
            <div className="-mt-10 w-20 h-20 rounded-full overflow-hidden bg-[#EEF5EA] flex items-center justify-center flex-shrink-0 border-4 border-white shadow-md cursor-pointer relative group"
              onClick={() => avatarInputRef.current?.click()}>
              {(avatarPreview ?? avatar)
                ? <Image src={avatarPreview ?? avatar!} alt="" width={80} height={80} className="object-cover w-full h-full" />
                : <span className="text-2xl font-bold text-[#0C5C6C]">{(nameElevage[0] ?? user.email?.[0] ?? '?').toUpperCase()}</span>
              }
              <div className="absolute inset-0 bg-black/30 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity rounded-full">
                <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"/>
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"/>
                </svg>
              </div>
            </div>
            <div className="mt-2 text-center px-4">
              <p className="font-bold text-[#1F2A2E] text-base leading-tight">{nameElevage || 'Mon élevage'}</p>
              <span className="text-xs bg-[#EEF5EA] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium mt-1 inline-block">
                {userData?.isValidate ? '✓ PRO Vérifié' : 'Éleveur'}
              </span>
            </div>
          </div>
        </div>

        {/* ── Identité de l'éleveur ── */}
        <Card title="Identité de l'éleveur">
          <ReadOnly label="Email" value={user.email ?? ''} icon="✉️" />
          <div className="grid grid-cols-2 gap-3 mt-3">
            <Field label="Prénom *">
              <input value={firstname} onChange={e => setFirstname(e.target.value)} required className={inputCls} />
            </Field>
            <Field label="Nom *">
              <input value={lastname} onChange={e => setLastname(e.target.value)} required className={inputCls} />
            </Field>
          </div>
          <Field label="Date de naissance *">
            <input type="date" value={dob} onChange={e => setDob(e.target.value)} required className={inputCls} />
          </Field>
        </Card>

        {/* ── Information de l'élevage ── */}
        <Card title="Information de l'élevage">
          <Field label="Nom de l'élevage *">
            <input value={nameElevage} onChange={e => setNameElevage(e.target.value)} required className={inputCls} />
          </Field>
          <Field label="Téléphone de l'élevage *">
            <input value={phoneElevage} onChange={e => setPhoneElevage(e.target.value)} placeholder="06 00 00 00 00" required className={inputCls} />
          </Field>
          <Field label="Description / présentation">
            <textarea value={description} onChange={e => setDescription(e.target.value)}
              rows={4} placeholder="Présentez votre élevage…"
              className={`${inputCls} resize-none`} />
          </Field>
        </Card>

        {/* ── Adresse de l'élevage ── */}
        <Card title="Adresse de l'élevage">
          <Field label="Rechercher une adresse">
            <div className="relative">
              <input
                value={adresseElevSearch}
                onChange={e => onAdresseElevSearchChange(e.target.value)}
                placeholder="Ex : 12 rue des Fleurs, Paris"
                className={inputCls}
                autoComplete="off"
              />
              {adresseElevPredictions.length > 0 && (
                <ul className="absolute z-20 left-0 right-0 top-full mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                  {adresseElevPredictions.map(p => (
                    <li key={p.place_id}
                      className="px-3 py-2 text-sm cursor-pointer hover:bg-gray-50 border-b border-gray-100 last:border-0"
                      onMouseDown={() => selectAdresseElevPrediction(p)}>
                      {p.description}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </Field>
          <Field label="Rue / Voie *">
            <input value={rue} onChange={e => setRue(e.target.value)} placeholder="12 rue des Fleurs" className={inputCls} />
          </Field>
          <div className="grid grid-cols-5 gap-3">
            <div className="col-span-2">
              <Field label="Code postal *">
                <input value={cp} onChange={e => setCp(e.target.value)} placeholder="75001" className={inputCls} />
              </Field>
            </div>
            <div className="col-span-3">
              <Field label="Ville *">
                <input value={villeElevage} onChange={e => setVilleElevage(e.target.value)} placeholder="Paris" required className={inputCls} />
              </Field>
            </div>
          </div>
          <Field label="Pays *">
            <input value={pays} onChange={e => setPays(e.target.value)} className={inputCls} />
          </Field>
        </Card>

        {/* ── Espèces élevées / races ── */}
        <Card title="Espèces élevées">
          <div className="flex flex-wrap gap-2 mb-4">
            {ESPECES_CONFIG.map(sp => {
              const active = especesElevees.some(e => e.espece === sp.value);
              return (
                <button key={sp.value} type="button" onClick={() => toggleEspece(sp.value)}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium border transition-all ${
                    active
                      ? 'bg-[#6E9E57] text-white border-[#6E9E57]'
                      : 'bg-white text-gray-600 border-gray-200 hover:border-[#6E9E57]'
                  }`}>
                  {sp.emoji} {sp.label}
                </button>
              );
            })}
          </div>
          {especesElevees.map(entry => {
            const cfg = ESPECES_CONFIG.find(e => e.value === entry.espece);
            return (
              <div key={entry.espece} className="border border-gray-100 rounded-xl p-3 mb-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-semibold text-[#1F2A2E]">
                    {cfg?.emoji} {cfg?.label}
                  </span>
                  <button type="button" onClick={() => openBreedPicker(entry.espece)}
                    className="flex items-center gap-1 text-xs text-[#6E9E57] hover:text-[#5A8A45] font-medium border border-[#6E9E57]/30 rounded-full px-2.5 py-1 hover:bg-[#EEF5EA]">
                    + Races
                  </button>
                </div>
                {entry.races.length > 0 ? (
                  <div className="flex flex-wrap gap-1.5">
                    {entry.races.map(r => (
                      <span key={r} className="flex items-center gap-1 bg-[#EEF5EA] border border-[#6E9E57]/30 text-[#1F2A2E] text-xs px-2.5 py-1 rounded-full">
                        {r}
                        <button type="button"
                          onClick={() => setEspecesElevees(prev => prev.map(e =>
                            e.espece === entry.espece ? { ...e, races: e.races.filter(x => x !== r) } : e
                          ))}
                          className="text-gray-400 hover:text-red-400 ml-0.5">×</button>
                      </span>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-gray-400">Aucune race renseignée</p>
                )}
              </div>
            );
          })}
        </Card>

        {/* ── Réseaux sociaux ── */}
        <Card title="Réseaux sociaux">
          <Field label="Instagram">
            <input value={instagram} onChange={e => setInstagram(e.target.value)}
              placeholder="@mon_elevage ou https://instagram.com/…"
              className={inputCls} />
          </Field>
          <Field label="Facebook">
            <input value={facebook} onChange={e => setFacebook(e.target.value)}
              placeholder="facebook.com/mon-elevage"
              className={inputCls} />
          </Field>
          <Field label="Site web">
            <input value={siteWeb} onChange={e => setSiteWeb(e.target.value)}
              placeholder="https://mon-elevage.fr"
              className={inputCls} />
          </Field>
        </Card>

        {/* ── Informations administratives ── */}
        <Card title="Informations administratives *">
          <input ref={siretDocRef} type="file" accept="image/*,application/pdf" className="hidden"
            onChange={e => { const f = e.target.files?.[0]; if (f) setSiretDocFile(f); e.target.value = ''; }} />
          <input ref={acacedDocRef} type="file" accept="image/*,application/pdf" className="hidden"
            onChange={e => { const f = e.target.files?.[0]; if (f) setAcacedDocFile(f); e.target.value = ''; }} />

          <Field label="SIRET *">
            <input value={siret} onChange={e => setSiret(e.target.value)} className={inputCls}
              placeholder="14 chiffres" maxLength={14} />
          </Field>
          <div className="mb-4">
            <p className="text-xs font-medium text-gray-500 mb-1">Justificatif SIRET (KBIS ou attestation RNE) *</p>
            {(siretDocUrl || siretDocFile) ? (
              <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-3 py-2">
                <span className="text-green-600 text-sm">✓</span>
                <span className="text-xs text-green-700 flex-1 truncate">
                  {siretDocFile ? siretDocFile.name : 'Document enregistré'}
                </span>
                <button type="button" onClick={() => siretDocRef.current?.click()}
                  className="text-xs text-[#0C5C6C] font-medium hover:underline">Changer</button>
              </div>
            ) : (
              <button type="button" onClick={() => siretDocRef.current?.click()}
                className="w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-3 text-sm text-gray-400 hover:text-[#0C5C6C] transition-colors">
                📎 Joindre le KBIS ou attestation RNE (image ou PDF)
              </button>
            )}
          </div>

          <Field label="N° TVA intracommunautaire (optionnel)">
            <input value={tva} onChange={e => setTva(e.target.value)} className={inputCls}
              placeholder="FR00000000000" />
          </Field>

          <div className="border-t border-gray-100 pt-4 mt-2">
            <Field label="N° ACACED *">
              <input value={acacedNum} onChange={e => setAcacedNum(e.target.value)} className={inputCls}
                placeholder="Ex : ACE-2023-XXXX" />
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Date d'obtention *">
                <input type="date" value={acacedDateObtention} onChange={e => setAcacedDateObtention(e.target.value)}
                  className={inputCls} />
              </Field>
              <Field label="Date de renouvellement">
                <div className="flex gap-1">
                  <input type="date" value={acacedDateRenewal} onChange={e => setAcacedDateRenewal(e.target.value)}
                    className={`${inputCls} flex-1`} />
                  {acacedDateRenewal && (
                    <button type="button" onClick={() => setAcacedDateRenewal('')}
                      className="text-gray-400 hover:text-gray-600 px-1 text-sm">×</button>
                  )}
                </div>
              </Field>
            </div>
            <div className="mb-3">
              <p className="text-xs font-medium text-gray-500 mb-1">Certificat ACACED *</p>
              {(acacedDocUrl || acacedDocFile) ? (
                <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-3 py-2">
                  <span className="text-green-600 text-sm">✓</span>
                  <span className="text-xs text-green-700 flex-1 truncate">
                    {acacedDocFile ? acacedDocFile.name : 'Document enregistré'}
                  </span>
                  <button type="button" onClick={() => acacedDocRef.current?.click()}
                    className="text-xs text-[#0C5C6C] font-medium hover:underline">Changer</button>
                </div>
              ) : (
                <button type="button" onClick={() => acacedDocRef.current?.click()}
                  className="w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-3 text-sm text-gray-400 hover:text-[#0C5C6C] transition-colors">
                  📎 Joindre le certificat ACACED (image ou PDF)
                </button>
              )}
            </div>
            {acacedStatus && (
              <div className={`flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-medium ${
                acacedStatus.color === 'red' ? 'bg-red-50 border border-red-200 text-red-700' :
                acacedStatus.color === 'orange' ? 'bg-orange-50 border border-orange-200 text-orange-700' :
                'bg-green-50 border border-green-200 text-green-700'
              }`}>
                <span>{acacedStatus.color === 'red' ? '⚠️' : acacedStatus.color === 'orange' ? '⏳' : '✓'}</span>
                {acacedStatus.label}
              </div>
            )}
          </div>
        </Card>

        {/* ── Erreurs ── */}
        {formErrors.length > 0 && (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4">
            <p className="text-sm font-semibold text-red-700 mb-2">Champs obligatoires manquants :</p>
            <ul className="list-disc list-inside space-y-1">
              {formErrors.map((err, i) => <li key={i} className="text-xs text-red-600">{err}</li>)}
            </ul>
          </div>
        )}

        {/* ── Submit ── */}
        <div className="flex items-center gap-3 pt-2">
          <button type="submit" disabled={saving}
            className="bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold px-6 py-3 rounded-xl transition-colors text-sm">
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </button>
          {saved && <span className="text-[#6E9E57] text-sm font-medium">✓ Profil mis à jour</span>}
        </div>
      </form>
    </div>
  );
}
