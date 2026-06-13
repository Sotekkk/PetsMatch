'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { updateProfile, EmailAuthProvider, reauthenticateWithCredential, deleteUser } from 'firebase/auth';
import { doc, updateDoc, deleteDoc, collection, getDocs, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { useAuth } from '@/lib/auth-context';
import { uploadPhoto } from '@/lib/upload-media';
import ReactCrop, { type Crop, type PixelCrop, centerCrop, makeAspectCrop } from 'react-image-crop';
import 'react-image-crop/dist/ReactCrop.css';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';
import { fromPostalCode } from '@/lib/french-geo';

// ── Species config ────────────────────────────────────────────────────────────

const ESPECES_CONFIG = [
  { value: 'chien',  label: 'Chien',   emoji: '🐕', breedFile: 'dog_breeds' },
  { value: 'chat',   label: 'Chat',    emoji: '🐈', breedFile: 'cat_breeds' },
  { value: 'cheval', label: 'Cheval',  emoji: '🐴', breedFile: 'horse_breeds' },
  { value: 'lapin',  label: 'Lapin',   emoji: '🐰', breedFile: 'rabbit_breeds' },
  { value: 'oiseau', label: 'Oiseau',  emoji: '🦜', breedFile: 'bird_breeds' },
  { value: 'ovin',   label: 'Ovin',    emoji: '🐑', breedFile: 'sheep_breeds' },
  { value: 'caprin', label: 'Caprin',  emoji: '🐐', breedFile: 'goat_breeds' },
  { value: 'porcin', label: 'Porcin',  emoji: '🐷', breedFile: 'pig_breeds' },
  { value: 'nac',    label: 'NAC',     emoji: '🐾', breedFile: 'nac_breeds' },
  { value: 'autre',  label: 'Autre',   emoji: '🐾', breedFile: null },
];

interface EspeceEntry { espece: string; races: string[] }

// ── Banner crop modal ─────────────────────────────────────────────────────────

async function getCroppedFile(img: HTMLImageElement, crop: PixelCrop): Promise<File> {
  const canvas = document.createElement('canvas');
  const scaleX = img.naturalWidth / img.width;
  const scaleY = img.naturalHeight / img.height;
  canvas.width = Math.floor(crop.width * scaleX);
  canvas.height = Math.floor(crop.height * scaleY);
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(img, crop.x * scaleX, crop.y * scaleY, crop.width * scaleX, crop.height * scaleY, 0, 0, canvas.width, canvas.height);
  return new Promise(res => canvas.toBlob(b => res(new File([b!], 'banner.jpg', { type: 'image/jpeg' })), 'image/jpeg', 0.92));
}

function BannerCropModal({ src, onConfirm, onCancel }: {
  src: string;
  onConfirm: (file: File, preview: string) => void;
  onCancel: () => void;
}) {
  const imgRef = useRef<HTMLImageElement>(null);
  const [crop, setCrop] = useState<Crop>();
  const [completedCrop, setCompletedCrop] = useState<PixelCrop>();

  function onImageLoad(e: React.SyntheticEvent<HTMLImageElement>) {
    const { width, height } = e.currentTarget;
    setCrop(centerCrop(makeAspectCrop({ unit: '%', width: 100 }, 16 / 9, width, height), width, height));
  }

  async function handleConfirm() {
    if (!imgRef.current || !completedCrop) return;
    const file = await getCroppedFile(imgRef.current, completedCrop);
    onConfirm(file, URL.createObjectURL(file));
  }

  return (
    <div className="fixed inset-0 bg-black/80 z-50 flex flex-col items-center justify-center p-4">
      <div className="bg-white rounded-2xl overflow-hidden w-full max-w-2xl shadow-2xl">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Recadrer la bannière
          </h3>
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
            aspect={16 / 9} className="max-h-[60vh]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img ref={imgRef} src={src} alt="Aperçu bannière" onLoad={onImageLoad}
              className="max-w-full max-h-[60vh] object-contain" />
          </ReactCrop>
        </div>
        <p className="text-center text-xs text-gray-400 py-2">Format 16:9 — déplacez et redimensionnez la sélection</p>
      </div>
    </div>
  );
}

// ── Breed picker modal ────────────────────────────────────────────────────────

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

        {/* Selected chips */}
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

        {/* Search */}
        <div className="px-4 pt-3 pb-2">
          <input value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher une race…"
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#6E9E57]" />
        </div>

        {/* List */}
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

// ── Read-only field ───────────────────────────────────────────────────────────

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

// ── Section card ──────────────────────────────────────────────────────────────

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

const inputCls = "w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#6E9E57] bg-white";

// ── Secondary pro profile edit ─────────────────────────────────────────────────

const ESPECES_PRO = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'NAC', 'Autre'];

const JOURS = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

const MOTIFS_LABELS: Record<string, Record<string, string>> = {
  veterinaire: { consultation: 'Consultation', vaccination: 'Vaccination', bilan: 'Bilan annuel', urgence: 'Urgence', chirurgie: 'Chirurgie', autre: 'Autre' },
  pension:     { visite: 'Visite', arrivee: 'Arrivée', depart: 'Départ', autre: 'Autre' },
  garde:       { promenade_30min: 'Promenade 30 min', promenade_1h: 'Promenade 1h', garde_journee: 'Garde journée', autre: 'Autre' },
  education:   { cours_individuel: 'Cours individuel', cours_collectif: 'Cours collectif', evaluation: 'Évaluation', autre: 'Autre' },
  toilettage:  { bain: 'Bain', toilettage_complet: 'Toilettage complet', coupe: 'Coupe', autre: 'Autre' },
  sante:       { consultation: 'Consultation', seance: 'Séance', autre: 'Autre' },
};

const DEFAULT_DUREES: Record<string, Record<string, number>> = {
  veterinaire: { consultation: 30, vaccination: 20, bilan: 45, urgence: 60, chirurgie: 120, autre: 30 },
  pension:     { visite: 30, arrivee: 60, depart: 30, autre: 30 },
  garde:       { promenade_30min: 30, promenade_1h: 60, garde_journee: 480, autre: 60 },
  education:   { cours_individuel: 60, cours_collectif: 90, evaluation: 45, autre: 60 },
  toilettage:  { bain: 45, toilettage_complet: 90, coupe: 60, autre: 60 },
  sante:       { consultation: 45, seance: 60, autre: 60 },
};

interface ProProfileData {
  id: string;
  profile_type: string;
  cat_pro: string;
  profile_label: string;
  name_elevage: string;
  profession_pro: string;
  desc_entreprise: string;
  tarifs: string;
  site_web: string;
  instagram: string;
  facebook: string;
  rayon_intervention: number;
  accept_new_clients: boolean;
  siret: string;
  ordre_veterinaire: string;
  rue: string;
  ville: string;
  code_postal: string;
  pays: string;
  latitude: number | null;
  longitude: number | null;
  especes_acceptees: string[];
  horaires: Record<string, string>;
  certifications: { nom: string; numero: string }[];
  durees_motifs: Record<string, number>;
  avatar_url: string;
  phone: string;
}

function SecondaryProEdit({ profileId, uid }: { profileId: string; uid: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [data, setData] = useState<ProProfileData | null>(null);

  // Form state
  const [nomStructure, setNomStructure] = useState('');
  const [profileLabel, setProfileLabel] = useState('');
  const [profession, setProfession] = useState('');
  const [description, setDescription] = useState('');
  const [tarifs, setTarifs] = useState('');
  const [siteWeb, setSiteWeb] = useState('');
  const [instagram, setInstagram] = useState('');
  const [facebook, setFacebook] = useState('');
  const [phone, setPhone] = useState('');
  const [rayon, setRayon] = useState(20);
  const [acceptNewClients, setAcceptNewClients] = useState(true);
  const [siret, setSiret] = useState('');
  const [rue, setRue] = useState('');
  const [ville, setVille] = useState('');
  const [cp, setCp] = useState('');
  const [pays, setPays] = useState('France');
  const [especes, setEspeces] = useState<Set<string>>(new Set());
  const [horaires, setHoraires] = useState<Record<string, string>>({});
  const [certifications, setCertifications] = useState<{ nom: string; numero: string }[]>([]);
  const [durees, setDurees] = useState<Record<string, number>>({});
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const avatarRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.from('user_profiles').select('*').eq('id', profileId).single()
      .then(({ data: row }) => {
        if (!row) { setLoading(false); return; }
        const r = row as Record<string, unknown>;
        setData(r as unknown as ProProfileData);
        setNomStructure((r.name_elevage as string) ?? '');
        setProfileLabel((r.profile_label as string) ?? '');
        setProfession((r.profession_pro as string) ?? '');
        setDescription(((r.desc_entreprise ?? r.description) as string) ?? '');
        setTarifs((r.tarifs as string) ?? '');
        setSiteWeb((r.site_web as string) ?? '');
        setInstagram((r.instagram as string) ?? '');
        setFacebook((r.facebook as string) ?? '');
        setPhone((r.phone as string) ?? '');
        setRayon(((r.rayon_intervention as number) ?? 20));
        setAcceptNewClients((r.accept_new_clients as boolean) ?? true);
        setSiret((r.siret as string) ?? '');
        setRue((r.rue as string) ?? '');
        setVille((r.ville as string) ?? '');
        setCp((r.code_postal as string) ?? '');
        setPays(((r.pays as string) || 'France'));
        setAvatarPreview((r.avatar_url as string) ?? null);
        if (Array.isArray(r.especes_acceptees)) {
          setEspeces(new Set(r.especes_acceptees as string[]));
        }
        if (r.horaires && typeof r.horaires === 'object') {
          const h: Record<string, string> = {};
          for (const j of JOURS) h[j] = ((r.horaires as Record<string, string>)[j]) ?? '';
          setHoraires(h);
        } else {
          setHoraires(Object.fromEntries(JOURS.map(j => [j, ''])));
        }
        if (Array.isArray(r.certifications)) {
          setCertifications((r.certifications as { nom: string; numero: string }[]));
        }
        const cat = ((r.profile_type ?? r.cat_pro) as string) ?? '';
        if (r.durees_motifs && typeof r.durees_motifs === 'object') {
          setDurees(r.durees_motifs as Record<string, number>);
        } else {
          setDurees(DEFAULT_DUREES[cat] ?? { autre: 30 });
        }
        setLoading(false);
      });
  }, [profileId]);

  async function handleSave() {
    setSaving(true);
    const payload: Record<string, unknown> = {
      name_elevage: nomStructure.trim(),
      profile_label: profileLabel.trim(),
      profession_pro: profession.trim(),
      desc_entreprise: description.trim(),
      tarifs: tarifs.trim(),
      site_web: siteWeb.trim(),
      instagram: instagram.trim(),
      facebook: facebook.trim(),
      phone: phone.trim(),
      rayon_intervention: rayon,
      accept_new_clients: acceptNewClients,
      siret: siret.trim(),
      rue: rue.trim(),
      ville: ville.trim(),
      code_postal: cp.trim(),
      pays: pays.trim() || 'France',
      especes_acceptees: Array.from(especes),
      horaires,
      certifications,
      durees_motifs: durees,
    };

    if (avatarFile) {
      const path = `profiles/${uid}/pro_${profileId}_avatar.jpg`;
      const { data: uploaded } = await supabase.storage.from('petsmatch').upload(path, avatarFile, { upsert: true });
      if (uploaded) {
        const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
        payload.avatar_url = pub.publicUrl;
      }
    }

    await supabase.from('user_profiles').update(payload).eq('id', profileId);
    setSaving(false);
    setSaved(true);
    setTimeout(() => setSaved(false), 3000);
  }

  const catPro = data?.profile_type ?? data?.cat_pro ?? '';
  const motifs = MOTIFS_LABELS[catPro] ?? {};

  if (loading) return (
    <div className="flex justify-center py-32">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!data) return (
    <div className="max-w-2xl mx-auto px-4 py-8 text-center text-gray-400">Profil introuvable.</div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 pb-20">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.back()} className="text-[#0C5C6C] hover:underline text-sm font-medium">← Retour</button>
        <h1 className="text-2xl font-bold text-[#1F2A2E] flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          Mon profil pro
        </h1>
      </div>

      {/* Avatar */}
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 mb-4 flex items-center gap-4">
        <input ref={avatarRef} type="file" accept="image/*" className="hidden"
          onChange={e => {
            const f = e.target.files?.[0];
            if (f) { setAvatarFile(f); setAvatarPreview(URL.createObjectURL(f)); }
            e.target.value = '';
          }} />
        <div className="w-16 h-16 rounded-full overflow-hidden bg-[#E3F2FD] flex items-center justify-center flex-shrink-0 cursor-pointer relative group border-2 border-[#2196F3]/30"
          onClick={() => avatarRef.current?.click()}>
          {avatarPreview
            ? <Image src={avatarPreview} alt="" width={64} height={64} className="object-cover w-full h-full" />
            : <span className="text-xl font-bold text-[#0C5C6C]">{(nomStructure[0] ?? '?').toUpperCase()}</span>
          }
          <div className="absolute inset-0 bg-black/30 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity rounded-full">
            <span className="text-white text-xs">📷</span>
          </div>
        </div>
        <div>
          <p className="font-semibold text-[#1F2A2E]">{nomStructure || profileLabel || 'Mon profil pro'}</p>
          <span className="text-xs bg-[#E3F2FD] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium">
            {data.profile_type}
          </span>
        </div>
      </div>

      <div className="space-y-4">
        {/* Infos générales */}
        <Card title="Informations générales">
          <Field label="Libellé du profil">
            <input value={profileLabel} onChange={e => setProfileLabel(e.target.value)} className={inputCls} placeholder="Ex : Mon cabinet vétérinaire" />
          </Field>
          <Field label="Nom de la structure / cabinet">
            <input value={nomStructure} onChange={e => setNomStructure(e.target.value)} className={inputCls} placeholder="Ex : Cabinet Dupont" />
          </Field>
          <Field label="Profession">
            <input value={profession} onChange={e => setProfession(e.target.value)} className={inputCls} placeholder="Ex : Vétérinaire, Éducateur canin…" />
          </Field>
          <Field label="Téléphone professionnel">
            <input value={phone} onChange={e => setPhone(e.target.value)} className={inputCls} placeholder="06 12 34 56 78" />
          </Field>
          <Field label="Description / présentation">
            <textarea value={description} onChange={e => setDescription(e.target.value)}
              rows={4} placeholder="Présentez votre activité…" className={`${inputCls} resize-none`} />
          </Field>
          <Field label="Tarifs">
            <textarea value={tarifs} onChange={e => setTarifs(e.target.value)}
              rows={3} placeholder="Ex : Consultation 60€, Vaccination 35€…" className={`${inputCls} resize-none`} />
          </Field>
          <div className="flex items-center justify-between py-2">
            <div>
              <p className="text-sm font-medium text-[#1F2A2E]">Accepte de nouveaux clients</p>
              <p className="text-xs text-gray-400">Affiché sur votre fiche publique</p>
            </div>
            <button type="button" onClick={() => setAcceptNewClients(v => !v)}
              className={`relative w-11 h-6 rounded-full transition-colors ${acceptNewClients ? 'bg-[#0C5C6C]' : 'bg-gray-200'}`}>
              <span className={`absolute top-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${acceptNewClients ? 'left-5' : 'left-0.5'}`} />
            </button>
          </div>
        </Card>

        {/* Adresse */}
        <Card title="Adresse professionnelle">
          <Field label="Rue / numéro">
            <input value={rue} onChange={e => setRue(e.target.value)} className={inputCls} placeholder="12 rue des Fleurs" />
          </Field>
          <div className="grid grid-cols-5 gap-3">
            <div className="col-span-2">
              <Field label="Code postal">
                <input value={cp} onChange={e => setCp(e.target.value)} className={inputCls} placeholder="75001" />
              </Field>
            </div>
            <div className="col-span-3">
              <Field label="Ville">
                <input value={ville} onChange={e => setVille(e.target.value)} className={inputCls} placeholder="Paris" />
              </Field>
            </div>
          </div>
          <Field label="Pays">
            <input value={pays} onChange={e => setPays(e.target.value)} className={inputCls} />
          </Field>
          {['garde', 'toilettage', 'education', 'photographe', 'marechal_ferrant'].includes(catPro) && (
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">
                Rayon d&apos;intervention : {rayon} km
              </label>
              <input type="range" min={5} max={200} step={5} value={rayon}
                onChange={e => setRayon(Number(e.target.value))}
                className="w-full accent-[#6E9E57]" />
            </div>
          )}
        </Card>

        {/* Espèces */}
        <Card title="Espèces acceptées">
          <div className="flex flex-wrap gap-2">
            {ESPECES_PRO.map(e => {
              const active = especes.has(e);
              return (
                <button key={e} type="button"
                  onClick={() => setEspeces(prev => { const n = new Set(prev); active ? n.delete(e) : n.add(e); return n; })}
                  className={`px-3 py-1.5 rounded-full text-xs font-medium border transition-all ${active ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'}`}>
                  {e}
                </button>
              );
            })}
          </div>
        </Card>

        {/* Horaires */}
        <Card title="Horaires">
          <p className="text-xs text-gray-400 mb-3">Format : HH:MM-HH:MM (ex : 09:00-12:00 14:00-18:00). Laisser vide si fermé.</p>
          <div className="space-y-2">
            {JOURS.map(j => (
              <div key={j} className="flex items-center gap-3">
                <span className="text-xs font-semibold text-gray-500 w-16 flex-shrink-0">{j.slice(0, 3)}</span>
                <input value={horaires[j] ?? ''} onChange={e => setHoraires(h => ({ ...h, [j]: e.target.value }))}
                  className="flex-1 border border-gray-200 rounded-xl px-3 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]"
                  placeholder="ex : 09:00-12:00 14:00-18:00" />
                {horaires[j] ? (
                  <button type="button" onClick={() => setHoraires(h => ({ ...h, [j]: '' }))}
                    className="text-gray-300 hover:text-red-400 text-lg flex-shrink-0">×</button>
                ) : (
                  <span className="text-xs text-gray-300 w-5 flex-shrink-0">—</span>
                )}
              </div>
            ))}
          </div>
        </Card>

        {/* Durées des prestations */}
        {Object.keys(motifs).length > 0 && (
          <Card title="Durées des prestations (minutes)">
            <div className="grid grid-cols-2 gap-3">
              {Object.entries(motifs).map(([key, label]) => (
                <div key={key}>
                  <label className="text-xs font-medium text-gray-500 block mb-1">{label}</label>
                  <input type="number" min={5} max={480} step={5}
                    value={durees[key] ?? 30}
                    onChange={e => setDurees(d => ({ ...d, [key]: Number(e.target.value) }))}
                    className={inputCls} />
                </div>
              ))}
            </div>
          </Card>
        )}

        {/* Certifications */}
        <Card title="Certifications & diplômes">
          {certifications.map((c, i) => (
            <div key={i} className="flex gap-2 mb-2 items-center">
              <input value={c.nom} placeholder="Nom" onChange={e => setCertifications(prev => prev.map((x, j) => j === i ? { ...x, nom: e.target.value } : x))}
                className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
              <input value={c.numero} placeholder="N°" onChange={e => setCertifications(prev => prev.map((x, j) => j === i ? { ...x, numero: e.target.value } : x))}
                className="w-24 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
              <button type="button" onClick={() => setCertifications(prev => prev.filter((_, j) => j !== i))}
                className="text-gray-300 hover:text-red-400 text-lg">×</button>
            </div>
          ))}
          <button type="button" onClick={() => setCertifications(prev => [...prev, { nom: '', numero: '' }])}
            className="text-xs text-[#0C5C6C] font-medium hover:underline mt-1">
            + Ajouter une certification
          </button>
        </Card>

        {/* Réseaux sociaux */}
        <Card title="Présence en ligne">
          {siret && (
            <div className="mb-3"><ReadOnly label="SIRET" value={siret} icon="🏢" /></div>
          )}
          <Field label="Site web">
            <input value={siteWeb} onChange={e => setSiteWeb(e.target.value)} className={inputCls} placeholder="https://monsite.fr" />
          </Field>
          <Field label="Instagram">
            <input value={instagram} onChange={e => setInstagram(e.target.value)} className={inputCls} placeholder="@moncompte" />
          </Field>
          <Field label="Facebook">
            <input value={facebook} onChange={e => setFacebook(e.target.value)} className={inputCls} placeholder="facebook.com/monpage" />
          </Field>
        </Card>

        {/* Submit */}
        <div className="flex items-center gap-3 pt-2">
          <button type="button" onClick={handleSave} disabled={saving}
            className="bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold px-6 py-3 rounded-xl transition-colors text-sm">
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </button>
          {saved && <span className="text-[#6E9E57] text-sm font-medium">✓ Profil mis à jour</span>}
        </div>
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function ProfilPage() {
  const { user, userData, loading, refreshUserData } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  // Identity
  const [firstname, setFirstname] = useState('');
  const [lastname, setLastname] = useState('');
  const [dob, setDob] = useState('');
  const [phone, setPhone] = useState('');
  const [ville, setVille] = useState('');
  const [cpParticulier, setCpParticulier] = useState('');

  // Address autocomplete (particulier)
  const [adressePredictions, setAdressePredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const [adresseSearch, setAdresseSearch] = useState('');
  // Address autocomplete (éleveur)
  const [adresseElevPredictions, setAdresseElevPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const [adresseElevSearch, setAdresseElevSearch] = useState('');
  const autocompleteService = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesService = useRef<google.maps.places.PlacesService | null>(null);
  const adresseDebounce = useRef<ReturnType<typeof setTimeout> | null>(null);
  const adresseElevDebounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Elevage
  const [nameElevage, setNameElevage] = useState('');
  const [phoneElevage, setPhoneElevage] = useState('');
  const [description, setDescription] = useState('');
  const [rue, setRue] = useState('');
  const [cp, setCp] = useState('');
  const [villeElevage, setVilleElevage] = useState('');
  const [pays, setPays] = useState('France');

  // Species
  const [especesElevees, setEspecesElevees] = useState<EspeceEntry[]>([]);
  const [allBreeds, setAllBreeds] = useState<Record<string, string[]>>({});
  const [breedPickerEspece, setBreedPickerEspece] = useState<string | null>(null);

  // Admin
  const [siret, setSiret] = useState('');
  const [acacedNum, setAcacedNum] = useState('');
  const [acacedDateObtention, setAcacedDateObtention] = useState('');
  const [acacedDateRenewal, setAcacedDateRenewal] = useState('');

  // Documents justificatifs
  const [siretDocFile, setSiretDocFile] = useState<File | null>(null);
  const [siretDocUrl, setSiretDocUrl] = useState<string | null>(null);
  const [acacedDocFile, setAcacedDocFile] = useState<File | null>(null);
  const [acacedDocUrl, setAcacedDocUrl] = useState<string | null>(null);
  const siretDocRef = useRef<HTMLInputElement>(null);
  const acacedDocRef = useRef<HTMLInputElement>(null);

  // Errors
  const [formErrors, setFormErrors] = useState<string[]>([]);

  // Photos
  const [bannerFile, setBannerFile] = useState<File | null>(null);
  const [bannerPreview, setBannerPreview] = useState<string | null>(null);
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const bannerInputRef = useRef<HTMLInputElement>(null);
  const avatarInputRef = useRef<HTMLInputElement>(null);

  // UI
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  // RGPD — export + suppression
  const [exporting, setExporting] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deletePassword, setDeletePassword] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState('');

  const isEleveur = userData?.isElevage === true;

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!userData) return;
    setFirstname(userData.firstname ?? '');
    setLastname(userData.lastname ?? '');
    setPhone(userData.phone ?? '');
    setVille(userData.ville ?? '');
    setCpParticulier(userData.codePostal ?? '');
    setDob(userData.dob ?? '');
    if (isEleveur) {
      setNameElevage(userData.nameElevage ?? '');
      setPhoneElevage(userData.numeroElevage ?? '');
      setDescription(userData.descriptionElevage ?? '');
      setRue(userData.rueElevage ?? '');
      setCp(userData.codePostalElevage ?? '');
      setVilleElevage(userData.villeElevage ?? '');
      setPays(userData.paysElevage ?? 'France');
      setSiret(userData.siret ?? '');
      setAcacedNum(userData.acaced ?? '');
      setSiretDocUrl(userData.kbisUrl ?? null);
      setAcacedDocUrl(userData.acacedDocUrl ?? null);
      const rawEsp = userData.especesElevees ?? [];
      if (rawEsp.length > 0) {
        setEspecesElevees(rawEsp.map(e => ({ espece: e.espece, races: e.races ?? [] })));
      } else {
        const fallback: EspeceEntry[] = [];
        if (userData.isDog) fallback.push({ espece: 'chien', races: userData.dogBreeds ?? [] });
        if (userData.isCat) fallback.push({ espece: 'chat', races: userData.catBreeds ?? [] });
        setEspecesElevees(fallback);
      }
      setAcacedDateObtention(userData.acacedDateObtention ?? '');
      setAcacedDateRenewal(userData.acacedDateRenewal ?? '');
    }
  }, [userData, isEleveur]);

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

  function onAdresseSearchChange(val: string) {
    setAdresseSearch(val);
    if (adresseDebounce.current) clearTimeout(adresseDebounce.current);
    if (val.trim().length < 3) { setAdressePredictions([]); return; }
    adresseDebounce.current = setTimeout(() => {
      autocompleteService.current?.getPlacePredictions(
        { input: val, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu'] }, language: 'fr' } as google.maps.places.AutocompletionRequest,
        (preds, status) => {
          if (status === window.google.maps.places.PlacesServiceStatus.OK && preds) {
            setAdressePredictions(preds);
          } else {
            setAdressePredictions([]);
          }
        }
      );
    }, 400);
  }

  function selectAdressePrediction(pred: google.maps.places.AutocompletePrediction) {
    setAdresseSearch(pred.description);
    setAdressePredictions([]);
    placesService.current?.getDetails(
      { placeId: pred.place_id, fields: ['address_components'] },
      (place, status) => {
        if (status !== window.google.maps.places.PlacesServiceStatus.OK || !place?.address_components) return;
        let num = '', route = '', cp = '', city = '';
        for (const c of place.address_components) {
          if (c.types.includes('street_number')) num = c.long_name;
          if (c.types.includes('route')) route = c.long_name;
          if (c.types.includes('postal_code')) cp = c.long_name;
          if (c.types.includes('locality')) city = c.long_name;
          else if (c.types.includes('postal_town') && !city) city = c.long_name;
        }
        if (city) setVille(city);
        if (cp) setCpParticulier(cp);
        if (num || route) setAdresseSearch([num, route].filter(Boolean).join(' '));
      }
    );
  }

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
        if (num || route) setRue([num, route].filter(Boolean).join(' '));
        if (num || route) setAdresseElevSearch([num, route, postalCode, city].filter(Boolean).join(', '));
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

  // Si un profil pro secondaire est actif, afficher l'édition de ce profil
  // Ce return doit être APRÈS tous les hooks pour respecter les règles de React
  if (activeProfileId && !loading && user) {
    return <SecondaryProEdit profileId={activeProfileId} uid={user.uid} />;
  }

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
    setAvatarFile(file);
    setAvatarPreview(URL.createObjectURL(file));
  }

  function validateForm(): string[] {
    const errs: string[] = [];
    if (!firstname.trim()) errs.push('Prénom requis');
    if (!lastname.trim()) errs.push('Nom requis');
    if (!dob) errs.push('Date de naissance requise');
    if (isEleveur) {
      if (!nameElevage.trim()) errs.push("Nom de l'élevage requis");
      if (!phoneElevage.trim()) errs.push("Téléphone de l'élevage requis");
      if (!rue.trim()) errs.push("Rue / voie de l'élevage requise");
      if (!cp.trim()) errs.push("Code postal de l'élevage requis");
      if (!villeElevage.trim()) errs.push("Ville de l'élevage requise");
      if (!pays.trim()) errs.push("Pays de l'élevage requis");
      if (!siret.trim()) errs.push('SIRET requis');
      if (!siretDocUrl && !siretDocFile) errs.push('Justificatif SIRET (KBIS) requis');
      if (!acacedNum.trim()) errs.push('Numéro ACACED requis');
      if (!acacedDateObtention) errs.push("Date d'obtention ACACED requise");
      if (!acacedDocUrl && !acacedDocFile) errs.push('Certificat ACACED requis');
    }
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
      const geo = fromPostalCode(cpParticulier);
      const payload: Record<string, unknown> = {
        uid: user!.uid,
        firstname,
        lastname,
        phone_number: phone,
        ville,
        code_postal: cpParticulier,
        departement: geo?.departement ?? '',
        region: geo?.region ?? '',
        date_of_birth: dob,
      };

      if (isEleveur) {
        const isDog = especesElevees.some(e => e.espece === 'chien');
        const isCat = especesElevees.some(e => e.espece === 'chat');
        const adresse = [rue, cp, villeElevage].filter(Boolean).join(', ');

        payload.name_elevage = nameElevage;
        payload.numero_elevage = phoneElevage;
        payload.siret = siret.trim();
        payload.acaced = acacedNum.trim();
        payload.desc_entreprise = description;

        // Upload document SIRET (KBIS)
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
        // Upload document ACACED
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
        payload.rue_elevage = rue;
        payload.code_postal_elevage = cp;
        payload.ville_elevage = villeElevage;
        payload.pays_elevage = pays;
        payload.adress_elevage = adresse;
        payload.especes_elevees = especesElevees;
        payload.is_dog = isDog;
        payload.is_cat = isCat;
        payload.dog_breeds = isDog ? (especesElevees.find(e => e.espece === 'chien')?.races ?? []) : [];
        payload.cat_breeds = isCat ? (especesElevees.find(e => e.espece === 'chat')?.races ?? []) : [];
        if (acacedDateObtention) payload.acaced_date_obtention = acacedDateObtention;
        if (acacedDateRenewal) payload.acaced_date_renewal = acacedDateRenewal;

        if (bannerFile) {
          payload.banner_url = await uploadPhoto(
            bannerFile,
            `profiles/${user!.uid}/banner.jpg`,
            { maxDim: 1920, quality: 0.85 },
          );
        }
      }

      if (avatarFile) {
        const avatarUrl = await uploadPhoto(
          avatarFile,
          `profiles/${user!.uid}/photo.jpg`,
          { maxDim: 800, quality: 0.85 },
        );
        payload.profile_picture_url = avatarUrl;
        if (isEleveur) payload.profile_picture_url_elevage = avatarUrl;
      }

      await supabase.from('users').upsert(payload, { onConflict: 'uid' });

      // Sync all profile fields to Firestore so the Flutter app can read them
      try {
        const firestoreUpdate: Record<string, unknown> = { firstname, lastname, dateofbirth: dob };
        if (isEleveur) {
          const isDog = especesElevees.some(e => e.espece === 'chien');
          const isCat = especesElevees.some(e => e.espece === 'chat');
          Object.assign(firestoreUpdate, {
            nameElevage,
            descEntreprise: description,
            villeElevage,
            especesElevees,
            isDog,
            isCat,
            dogBreeds: isDog ? (especesElevees.find(e => e.espece === 'chien')?.races ?? []) : [],
            catBreeds: isCat ? (especesElevees.find(e => e.espece === 'chat')?.races ?? []) : [],
          });
        }
        if (payload.banner_url) firestoreUpdate.bannerUrl = payload.banner_url as string;
        await updateDoc(doc(db, 'users', user!.uid), firestoreUpdate);
      } catch { /* doc may not exist yet, ignore */ }
      await updateProfile(user!, {
        displayName: isEleveur ? nameElevage : `${firstname} ${lastname}`.trim(),
      });
      await refreshUserData();
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } finally {
      setSaving(false);
    }
  }

  async function handleExportData() {
    if (!user) return;
    setExporting(true);
    try {
      const uid = user.uid;
      const [profileRes, animauxRes, annoncesRes, abosRes, alertesRes] = await Promise.all([
        supabase.from('users').select('*').eq('uid', uid).maybeSingle(),
        supabase.from('animaux').select('*').eq('uid_eleveur', uid),
        supabase.from('annonces').select('*').eq('uid_eleveur', uid),
        supabase.from('abonnements').select('plan_code,periodicite,statut,date_debut,date_fin').eq('uid', uid),
        supabase.from('alertes_perdus').select('*').eq('uid_declarant', uid),
      ]);
      const exportData = {
        exported_at: new Date().toISOString(),
        uid,
        email: user.email,
        profil: profileRes.data,
        animaux: animauxRes.data ?? [],
        annonces: annoncesRes.data ?? [],
        abonnements: abosRes.data ?? [],
        alertes_perdus: alertesRes.data ?? [],
      };
      const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `mes_donnees_petsmatch_${Date.now()}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } finally {
      setExporting(false);
    }
  }

  async function handleDeleteAccount() {
    if (!user || !deletePassword) return;
    setDeleting(true);
    setDeleteError('');
    try {
      const credential = EmailAuthProvider.credential(user.email!, deletePassword);
      await reauthenticateWithCredential(user, credential);
      const uid = user.uid;

      // Supprimer les données Firestore (conversations, notifications, doc utilisateur)
      const batch = writeBatch(db);
      const collections = ['notifications'];
      for (const col of collections) {
        const snap = await getDocs(collection(db, 'users', uid, col));
        snap.forEach(d => batch.delete(d.ref));
      }
      batch.delete(doc(db, 'users', uid));
      await batch.commit();

      // Cascade-delete toutes les données Supabase (ON DELETE CASCADE)
      await supabase.from('users').delete().eq('uid', uid);
      // Supprimer le compte Firebase Auth
      await deleteUser(user);
      router.push('/');
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Erreur inconnue';
      setDeleteError(
        msg.includes('wrong-password') || msg.includes('invalid-credential')
          ? 'Mot de passe incorrect'
          : msg,
      );
    } finally {
      setDeleting(false);
    }
  }

  if (loading || !user) {
    return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  }

  const avatar = userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl;
  const currentBanner = userData?.bannerUrl;

  // ACACED expiry
  let acacedStatus: { color: string; label: string } | null = null;
  if (acacedDateObtention) {
    const base = new Date(acacedDateRenewal || acacedDateObtention);
    const exp = new Date(base.getFullYear() + 10, base.getMonth(), base.getDate());
    const now = new Date();
    const daysLeft = Math.floor((exp.getTime() - now.getTime()) / 86400000);
    if (daysLeft < 0) acacedStatus = { color: 'red', label: 'ACACED expiré — renouvellement requis' };
    else if (daysLeft < 180) acacedStatus = { color: 'orange', label: `Expire dans ${daysLeft} jours (${exp.toLocaleDateString('fr-FR')})` };
    else acacedStatus = { color: 'green', label: `Valide jusqu\'au ${exp.toLocaleDateString('fr-FR')}` };
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 pb-20">
      <h1 className="text-2xl font-bold text-[#1F2A2E] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>Mon profil</h1>

      {/* Accès rapide */}
      <div className="flex gap-3 mb-5 flex-wrap">
        <Link href="/favoris"
          className="flex items-center gap-2 bg-white border border-gray-100 shadow-sm rounded-2xl px-4 py-3 hover:shadow-md transition-shadow">
          <span className="text-xl">❤️</span>
          <div>
            <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Mes favoris</p>
            <p className="text-xs text-gray-400">Animaux aimés</p>
          </div>
        </Link>
        {isEleveur ? (
          <Link href="/annonces/creer"
            className="flex items-center gap-2 bg-white border border-gray-100 shadow-sm rounded-2xl px-4 py-3 hover:shadow-md transition-shadow">
            <span className="text-xl">➕</span>
            <div>
              <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Nouvelle annonce</p>
              <p className="text-xs text-gray-400">Publier</p>
            </div>
          </Link>
        ) : (
          <Link href="/mes-annonces"
            className="flex items-center gap-2 bg-white border border-gray-100 shadow-sm rounded-2xl px-4 py-3 hover:shadow-md transition-shadow">
            <span className="text-xl">📋</span>
            <div>
              <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Mes annonces</p>
              <p className="text-xs text-gray-400">Gérer</p>
            </div>
          </Link>
        )}
      </div>

      {/* Employés — visible pour éleveurs, pros et associations */}
      {(isEleveur || userData?.isPro || userData?.isAssociation) && (
        <Link href="/employes"
          className="flex items-center gap-4 bg-white border border-gray-100 shadow-sm rounded-2xl px-5 py-4 hover:shadow-md transition-shadow mb-5">
          <div className="w-10 h-10 rounded-xl bg-[#E8F4F6] flex items-center justify-center flex-shrink-0">
            <svg className="w-5 h-5 text-[#0C5C6C]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
            </svg>
          </div>
          <div className="flex-1">
            <p className="font-semibold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>Gestion des employés</p>
            <p className="text-xs text-gray-400">Ajouter, révoquer et gérer les accès de votre équipe</p>
          </div>
          <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </Link>
      )}

      <form onSubmit={handleSave} className="space-y-4">

        {/* ── Bannière + photo (éleveur) ── */}
        {isEleveur && (
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
            <div className="px-5 -mt-10 mb-4 flex items-end gap-3 relative z-10">
              <div className="w-20 h-20 rounded-full overflow-hidden bg-[#EEF5EA] flex items-center justify-center flex-shrink-0 border-4 border-white shadow-md cursor-pointer relative group" onClick={() => avatarInputRef.current?.click()}>
                {(avatarPreview ?? avatar)
                  ? <Image src={avatarPreview ?? avatar!} alt="" width={80} height={80} className="object-cover w-full h-full" />
                  : <span className="text-2xl font-bold text-[#0C5C6C]">{(nameElevage[0] ?? user.email?.[0] ?? '?').toUpperCase()}</span>
                }
                <div className="absolute inset-0 bg-black/30 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity rounded-full">
                  <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"/><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
                </div>
              </div>
              <div className="pb-1">
                <p className="font-bold text-[#1F2A2E] text-sm">{nameElevage || 'Mon élevage'}</p>
                <span className="text-xs bg-[#EEF5EA] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium">
                  {userData?.isValidate ? '✓ PRO Vérifié' : 'Éleveur'}
                </span>
              </div>
            </div>
          </div>
        )}

        {/* ── Photo profil particulier ── */}
        {!isEleveur && (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 mb-4 flex items-center gap-4">
            <input ref={avatarInputRef} type="file" accept="image/*" className="hidden" onChange={handleAvatarChange} />
            <div className="w-14 h-14 rounded-2xl overflow-hidden bg-[#EEF5EA] flex items-center justify-center flex-shrink-0 cursor-pointer relative group" onClick={() => avatarInputRef.current?.click()}>
              {(avatarPreview ?? avatar)
                ? <Image src={avatarPreview ?? avatar!} alt="" width={56} height={56} className="object-cover w-full h-full" />
                : <span className="text-xl font-bold text-[#0C5C6C]">{(firstname[0] ?? user.email?.[0] ?? '?').toUpperCase()}</span>
              }
              <div className="absolute inset-0 bg-black/30 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"/><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
              </div>
            </div>
            <div>
              <p className="font-semibold text-[#1F2A2E]">{`${firstname} ${lastname}`.trim() || user.email}</p>
              <p className="text-xs text-gray-400">{user.email}</p>
              <span className="text-xs bg-[#EEF5EA] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium mt-1 inline-block">
                {userData?.isPro ? 'Professionnel' : 'Particulier'}
              </span>
            </div>
          </div>
        )}

        {/* ── Identité ── */}
        <Card title="Identité *">
          <ReadOnly label="Email" value={user.email ?? ''} icon="✉️" />
          <div className="grid grid-cols-2 gap-3 mt-3">
            <Field label="Prénom *">
              <input value={firstname} onChange={e => setFirstname(e.target.value)} required className={inputCls} />
            </Field>
            <Field label="Nom *">
              <input value={lastname} onChange={e => setLastname(e.target.value)} required className={inputCls} />
            </Field>
          </div>
          {!isEleveur && (
            <>
              <Field label="Téléphone">
                <input value={phone} onChange={e => setPhone(e.target.value)} placeholder="06 00 00 00 00" className={inputCls} />
              </Field>
              <Field label="Rechercher une adresse">
                <div className="relative">
                  <input
                    value={adresseSearch}
                    onChange={e => onAdresseSearchChange(e.target.value)}
                    placeholder="Ex : 12 rue des Fleurs, Paris"
                    className={inputCls}
                    autoComplete="off"
                  />
                  {adressePredictions.length > 0 && (
                    <ul className="absolute z-20 left-0 right-0 top-full mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                      {adressePredictions.map(p => (
                        <li key={p.place_id}
                          className="px-3 py-2 text-sm cursor-pointer hover:bg-gray-50 border-b border-gray-100 last:border-0"
                          onMouseDown={() => selectAdressePrediction(p)}>
                          {p.description}
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </Field>
              <div className="grid grid-cols-5 gap-3">
                <div className="col-span-2">
                  <Field label="Code postal">
                    <input value={cpParticulier} onChange={e => setCpParticulier(e.target.value)} placeholder="75001" className={inputCls} />
                  </Field>
                </div>
                <div className="col-span-3">
                  <Field label="Ville">
                    <input value={ville} onChange={e => setVille(e.target.value)} placeholder="Paris" className={inputCls} />
                  </Field>
                </div>
              </div>
            </>
          )}
          <Field label="Date de naissance *">
            <input type="date" value={dob} onChange={e => setDob(e.target.value)}
              required className={inputCls} />
          </Field>
        </Card>

        {/* ── Élevage info ── */}
        {isEleveur && (
          <Card title="Mon élevage">
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
        )}

        {/* ── Adresse élevage ── */}
        {isEleveur && (
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
        )}

        {/* ── Espèces élevées ── */}
        {isEleveur && (
          <Card title={
            userData?.isPro
              ? (userData.catPro === 'sante' || userData.catPro === 'veterinaire' ? 'Espèces soignées'
                : userData.catPro === 'pension' || userData.catPro === 'garde' ? 'Espèces gardées'
                : userData.catPro === 'education' || userData.catPro === 'comportement' || userData.catPro === 'educateur' ? 'Espèces prises en charge'
                : 'Espèces acceptées')
              : 'Espèces élevées'
          }>
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
        )}

        {/* ── Informations administratives ── */}
        {isEleveur && (
          <Card title="Informations administratives *">
            {/* Hidden file inputs */}
            <input ref={siretDocRef} type="file" accept="image/*,application/pdf" className="hidden"
              onChange={e => { const f = e.target.files?.[0]; if (f) setSiretDocFile(f); e.target.value = ''; }} />
            <input ref={acacedDocRef} type="file" accept="image/*,application/pdf" className="hidden"
              onChange={e => { const f = e.target.files?.[0]; if (f) setAcacedDocFile(f); e.target.value = ''; }} />

            {/* SIRET */}
            <Field label="SIRET *">
              <input value={siret} onChange={e => setSiret(e.target.value)} className={inputCls}
                placeholder="14 chiffres" maxLength={14} />
            </Field>
            <div className="mb-4">
              <p className="text-xs font-medium text-gray-500 mb-1">Justificatif SIRET / KBIS *</p>
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
                  📎 Joindre le KBIS ou extrait SIRET (image ou PDF)
                </button>
              )}
            </div>

            <div className="border-t border-gray-100 pt-4 mt-2">
              {/* ACACED */}
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
        )}

        {/* ── Erreurs de validation ── */}
        {formErrors.length > 0 && (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4">
            <p className="text-sm font-semibold text-red-700 mb-2">Champs obligatoires manquants :</p>
            <ul className="list-disc list-inside space-y-1">
              {formErrors.map((e, i) => <li key={i} className="text-xs text-red-600">{e}</li>)}
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

      {/* ── Données personnelles (RGPD) ── */}
      <div className="mt-8 bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
        <h2 className="text-base font-bold text-[#1F2A2E] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
          Mes données personnelles
        </h2>

        <div className="flex items-start justify-between py-3">
          <div>
            <p className="text-sm font-semibold text-[#1F2A2E]">Télécharger mes données</p>
            <p className="text-xs text-gray-400 mt-0.5">Export JSON de vos données (RGPD art. 20)</p>
          </div>
          <button
            type="button"
            onClick={handleExportData}
            disabled={exporting}
            className="text-sm font-semibold text-[#0C5C6C] border border-[#0C5C6C] hover:bg-[#0C5C6C] hover:text-white px-4 py-2 rounded-xl transition-colors disabled:opacity-60 whitespace-nowrap"
          >
            {exporting ? 'Export…' : 'Télécharger'}
          </button>
        </div>

        <div className="flex items-start justify-between pt-3 border-t border-gray-100">
          <div>
            <p className="text-sm font-semibold text-red-600">Supprimer mon compte</p>
            <p className="text-xs text-gray-400 mt-0.5">Suppression définitive et irréversible (RGPD art. 17)</p>
          </div>
          <button
            type="button"
            onClick={() => { setShowDeleteModal(true); setDeletePassword(''); setDeleteError(''); }}
            className="text-sm font-semibold text-red-600 border border-red-200 hover:bg-red-50 px-4 py-2 rounded-xl transition-colors whitespace-nowrap"
          >
            Supprimer
          </button>
        </div>
      </div>

      {/* Modal suppression compte */}
      {showDeleteModal && (
        <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl w-full max-w-sm p-6 shadow-2xl">
            <h3 className="font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              Supprimer mon compte
            </h3>
            <p className="text-sm text-gray-500 mb-4">
              Cette action est irréversible. Toutes vos données (profil, animaux, annonces) seront supprimées.
              Entrez votre mot de passe pour confirmer.
            </p>
            <input
              type="password"
              value={deletePassword}
              onChange={e => setDeletePassword(e.target.value)}
              placeholder="Mot de passe"
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm mb-3 focus:outline-none focus:border-red-300"
            />
            {deleteError && <p className="text-xs text-red-500 mb-3">{deleteError}</p>}
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setShowDeleteModal(false)}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors"
              >
                Annuler
              </button>
              <button
                type="button"
                onClick={handleDeleteAccount}
                disabled={deleting || !deletePassword}
                className="flex-1 bg-red-600 hover:bg-red-700 disabled:opacity-60 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors"
              >
                {deleting ? 'Suppression…' : 'Confirmer'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Banner crop modal */}
      {cropSrc && (
        <BannerCropModal
          src={cropSrc}
          onConfirm={(file, preview) => { setBannerFile(file); setBannerPreview(preview); setCropSrc(null); }}
          onCancel={() => setCropSrc(null)}
        />
      )}

      {/* Breed picker modal */}
      {breedPickerEspece && (
        <BreedPicker
          espece={breedPickerEspece}
          allBreeds={allBreeds[breedPickerEspece] ?? []}
          selected={especesElevees.find(e => e.espece === breedPickerEspece)?.races ?? []}
          onClose={handleBreedPickerClose}
        />
      )}
    </div>
  );
}
