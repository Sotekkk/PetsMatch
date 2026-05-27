'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';

// ── Types ─────────────────────────────────────────────────────────────────────

interface UserAnimal {
  id: string;
  nom: string;
  espece: string;
  race?: string;
  sexe?: string;
  couleur?: string;
  photo_url?: string;
  identification?: string;
  contacts_urgence?: { nom?: string; tel?: string }[];
}

const ESPECES = ['chien', 'chat', 'lapin', 'oiseau', 'nac', 'cheval', 'ovin', 'caprin', 'porcin', 'autre'];

const BREED_FILES: Record<string, string> = {
  chien: 'dog_breeds', chat: 'cat_breeds', cheval: 'horse_breeds',
  lapin: 'rabbit_breeds', oiseau: 'bird_breeds', nac: 'nac_breeds',
  ovin: 'sheep_breeds', caprin: 'goat_breeds', porcin: 'pig_breeds',
};

function genNumero() {
  const now = new Date();
  const d = now.toISOString().slice(0, 10).replace(/-/g, '');
  const r = Math.floor(1000 + Math.random() * 9000);
  return `A${d}-${r}`;
}

function isValidContact(c: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c) || /^[\+\d][\d\s.\-]{6,}$/.test(c);
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function DeclarerPerduPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);

  // Form fields
  const [nom, setNom] = useState('');
  const [identification, setIdentification] = useState('');
  const [espece, setEspece] = useState('chien');
  const [race, setRace] = useState('');
  const [sexe, setSexe] = useState('');
  const [couleur, setCouleur] = useState('');
  const [datePerte, setDatePerte] = useState(new Date().toISOString().slice(0, 10));
  const [dateDerniereLoc, setDateDerniereLoc] = useState(new Date().toISOString().slice(0, 10));
  const [rue, setRue] = useState('');
  const [cp, setCp] = useState('');
  const [ville, setVille] = useState('');
  const [description, setDescription] = useState('');
  const [contact, setContact] = useState('');
  const [photoBlob, setPhotoBlob] = useState<Blob | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const [photoCropSrc, setPhotoCropSrc] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [numeroAlerte] = useState(genNumero);

  // Breeds
  const [breeds, setBreeds] = useState<string[]>([]);
  const [breedSuggestions, setBreedSuggestions] = useState<string[]>([]);
  const [showBreedSugg, setShowBreedSugg] = useState(false);

  // Animal picker
  const [userAnimaux, setUserAnimaux] = useState<UserAnimal[]>([]);
  const [showPicker, setShowPicker] = useState(false);

  // ── Init ──────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (user?.email) setContact(user.email);
  }, [user]);

  // Load breeds when espece changes
  useEffect(() => {
    const file = BREED_FILES[espece];
    if (!file) { setBreeds([]); return; }
    fetch(`/breeds/${file}.json`)
      .then(r => r.json())
      .then((list: string[]) => setBreeds(list))
      .catch(() => setBreeds([]));
  }, [espece]);

  // Load user's animals
  useEffect(() => {
    if (!user) return;
    supabase
      .from('animaux')
      .select('id, nom, espece, race, sexe, couleur, photo_url, identification, contacts_urgence')
      .eq('uid_proprietaire', user.uid)
      .order('nom')
      .then(({ data }) => setUserAnimaux((data as UserAnimal[]) ?? []));
  }, [user]);

  // ── Breed autocomplete ─────────────────────────────────────────────────────

  function onRaceChange(val: string) {
    setRace(val);
    if (!val) { setBreedSuggestions([]); setShowBreedSugg(false); return; }
    const q = val.toLowerCase();
    const matches = breeds.filter(b => b.toLowerCase().includes(q)).slice(0, 6);
    setBreedSuggestions(matches);
    setShowBreedSugg(matches.length > 0);
  }

  // ── Animal picker ──────────────────────────────────────────────────────────

  function fillFromAnimal(a: UserAnimal) {
    setNom(a.nom ?? '');
    setIdentification(a.identification ?? '');
    setEspece(a.espece ?? 'chien');
    setRace(a.race ?? '');
    setSexe(a.sexe ?? '');
    setCouleur(a.couleur ?? '');
    if (a.photo_url) setPhotoPreview(a.photo_url);
    // Pre-fill contact from urgence contacts
    const contacts = a.contacts_urgence ?? [];
    if (contacts.length > 0) {
      const first = contacts[0];
      setContact(first.tel || first.nom || user?.email || '');
    }
    setShowPicker(false);
  }

  // ── Photo ──────────────────────────────────────────────────────────────────

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setPhotoCropSrc(URL.createObjectURL(f));
    e.target.value = '';
  }

  function handleCropConfirm(blob: Blob) {
    if (photoPreview?.startsWith('blob:')) URL.revokeObjectURL(photoPreview);
    if (photoCropSrc) URL.revokeObjectURL(photoCropSrc);
    setPhotoBlob(blob);
    setPhotoPreview(URL.createObjectURL(blob));
    setPhotoCropSrc(null);
  }

  async function uploadAlertPhoto(): Promise<string | null> {
    if (!photoBlob) return photoPreview;
    try {
      return await uploadBlob(photoBlob, `alertes/${Date.now()}.jpg`);
    } catch {
      return photoPreview;
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const errs: string[] = [];
    if (!nom.trim())    errs.push('Nom de l\'animal');
    if (!race.trim())   errs.push('Race');
    if (!sexe)          errs.push('Sexe');
    if (!datePerte)     errs.push('Date de disparition');
    if (!ville.trim())  errs.push('Ville');
    if (!contact.trim()) errs.push('Contact');
    else if (!isValidContact(contact.trim())) errs.push('Contact invalide (email ou téléphone)');
    setErrors(errs);
    if (errs.length > 0) return;

    setSaving(true);
    try {
      const photoUrl = await uploadAlertPhoto();
      const localisation = [rue.trim(), cp.trim(), ville.trim()].filter(Boolean).join(', ');
      await supabase.from('alertes_perdus').insert({
        id: `${Date.now()}`,
        uid_proprietaire: user!.uid,
        nom_animal: nom.trim(),
        identification: identification.trim() || null,
        espece,
        race: race.trim() || null,
        sexe: sexe || null,
        couleur: couleur.trim() || null,
        photo_url: photoUrl,
        description: description.trim() || null,
        date_perte: datePerte,
        date_derniere_localisation: dateDerniereLoc || datePerte,
        derniere_localisation: localisation || null,
        contact: contact.trim(),
        numero_alerte: numeroAlerte,
        statut: 'perdu',
      });
      router.push('/mes-alertes?success=1');
    } catch (err) {
      setErrors([`Erreur : ${err}`]);
      setSaving(false);
    }
  }

  if (loading || !user) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  return (
    <div className="max-w-2xl mx-auto px-4 py-10">

      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <Link href="/animaux-perdus" className="text-gray-400 hover:text-gray-600 transition-colors">
          ← Retour
        </Link>
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Déclarer un animal perdu
          </h1>
          {numeroAlerte && (
            <span className="text-xs bg-orange-50 text-orange-700 border border-orange-200 rounded-full px-2 py-0.5">
              N° {numeroAlerte}
            </span>
          )}
        </div>
      </div>

      {/* Bannière */}
      <div className="bg-orange-50 border border-orange-200 rounded-xl p-4 mb-6 text-sm text-orange-800 flex items-start gap-2">
        <span>ℹ️</span>
        <span>Votre alerte sera visible sur la carte publique et partageable.</span>
      </div>

      {/* Erreurs */}
      {errors.length > 0 && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-6 text-sm text-red-700">
          <strong>Champs requis :</strong> {errors.join(' · ')}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5">

        {/* Photo */}
        <div className="flex flex-col items-center gap-2">
          <button type="button" onClick={() => fileRef.current?.click()}
            className="relative w-28 h-28 rounded-2xl overflow-hidden bg-orange-50 border-2 border-dashed border-orange-200 hover:border-orange-400 transition-colors flex items-center justify-center">
            {photoPreview
              ? <Image src={photoPreview} alt="" fill className="object-cover" />
              : <span className="text-4xl">🐾</span>}
            <div className="absolute inset-0 bg-black/0 hover:bg-black/10 transition-colors" />
          </button>
          <p className="text-xs text-gray-400">Cliquer pour ajouter une photo</p>
          <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={onFileChange} />
        </div>

        {/* Nom + picker */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <label className="block text-sm font-semibold text-gray-700">Nom de l&apos;animal *</label>
            {userAnimaux.length > 0 && (
              <button type="button" onClick={() => setShowPicker(true)}
                className="text-xs text-orange-600 font-semibold hover:text-orange-800 flex items-center gap-1">
                🐾 Mes animaux
              </button>
            )}
          </div>
          <input value={nom} onChange={e => setNom(e.target.value)}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
            placeholder="Ex : Rex" />
        </div>

        {/* Identification */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-1">Identification (puce / tatouage)</label>
          <input value={identification} onChange={e => setIdentification(e.target.value)}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
            placeholder="N° de puce ou tatouage" />
        </div>

        {/* Espèce */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-1">Espèce *</label>
          <select value={espece} onChange={e => { setEspece(e.target.value); setRace(''); }}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white capitalize">
            {ESPECES.map(e => <option key={e} value={e} className="capitalize">{e.charAt(0).toUpperCase() + e.slice(1)}</option>)}
          </select>
        </div>

        {/* Race */}
        <div className="relative">
          <label className="block text-sm font-semibold text-gray-700 mb-1">Race *</label>
          <input value={race} onChange={e => onRaceChange(e.target.value)}
            onFocus={() => race && setShowBreedSugg(breedSuggestions.length > 0)}
            onBlur={() => setTimeout(() => setShowBreedSugg(false), 150)}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
            placeholder={breeds.length ? 'Rechercher une race…' : 'Ex : Labrador, Européen…'} />
          {showBreedSugg && (
            <div className="absolute z-10 top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
              {breedSuggestions.map(b => (
                <button key={b} type="button"
                  onMouseDown={() => { setRace(b); setShowBreedSugg(false); }}
                  className="w-full text-left px-4 py-2.5 text-sm hover:bg-orange-50 flex items-center gap-2">
                  <span className="text-gray-400 text-xs">🐾</span> {b}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Sexe */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-2">Sexe *</label>
          <div className="flex gap-2">
            {[['male', '♂ Mâle'], ['femelle', '♀ Femelle'], ['inconnu', 'Inconnu']].map(([v, label]) => (
              <button key={v} type="button" onClick={() => setSexe(sexe === v ? '' : v)}
                className={`px-4 py-2 rounded-full text-sm font-semibold border transition-colors ${
                  sexe === v ? 'bg-orange-600 text-white border-orange-600' : 'bg-white text-gray-600 border-gray-200 hover:border-orange-400'
                }`}>
                {label}
              </button>
            ))}
          </div>
        </div>

        {/* Couleur */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-1">Couleur / signes particuliers</label>
          <input value={couleur} onChange={e => setCouleur(e.target.value)}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
            placeholder="Ex : robe fauve, tache blanche sur le front…" />
        </div>

        {/* Dates */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">Date de disparition *</label>
            <input type="date" value={datePerte}
              onChange={e => { setDatePerte(e.target.value); if (!dateDerniereLoc) setDateDerniereLoc(e.target.value); }}
              max={new Date().toISOString().slice(0, 10)}
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white" />
          </div>
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">Dernière localisation vue</label>
            <p className="text-xs text-gray-400 mb-1">Si différente de la date de disparition</p>
            <input type="date" value={dateDerniereLoc || datePerte}
              onChange={e => setDateDerniereLoc(e.target.value)}
              max={new Date().toISOString().slice(0, 10)}
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white" />
          </div>
        </div>

        {/* Localisation */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-1">Dernière localisation *</label>
          <div className="space-y-2">
            <input value={rue} onChange={e => setRue(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
              placeholder="Rue / Voie (optionnel)" />
            <div className="flex gap-2">
              <input value={cp} onChange={e => setCp(e.target.value)}
                className="w-28 border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
                placeholder="Code postal" />
              <input value={ville} onChange={e => setVille(e.target.value)}
                className="flex-1 border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
                placeholder="Ville *" />
            </div>
          </div>
        </div>

        {/* Description */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-1">Description</label>
          <textarea value={description} onChange={e => setDescription(e.target.value)}
            rows={3} placeholder="Circonstances de la disparition, comportement…"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white resize-none" />
        </div>

        {/* Contact */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-1">Contact *</label>
          <p className="text-xs text-gray-400 mb-1">Email ou téléphone — visible par les personnes qui trouvent l&apos;alerte</p>
          <input value={contact} onChange={e => setContact(e.target.value)}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white"
            placeholder="email@exemple.com ou 06 00 00 00 00" />
        </div>

        {/* Submit */}
        <button type="submit" disabled={saving}
          className="w-full bg-orange-600 hover:bg-orange-700 disabled:opacity-60 text-white font-bold py-3 rounded-xl transition-colors flex items-center justify-center gap-2">
          {saving ? (
            <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> Publication…</>
          ) : (
            <>📍 Publier l&apos;alerte</>
          )}
        </button>

      </form>

      {/* Animal picker modal */}
      {showPicker && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4"
          onClick={() => setShowPicker(false)}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[70vh] overflow-hidden shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="p-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Choisir un animal
              </h3>
            </div>
            <div className="overflow-y-auto max-h-[55vh]">
              {userAnimaux.map(a => (
                <button key={a.id} type="button" onClick={() => fillFromAnimal(a)}
                  className="w-full flex items-center gap-3 px-4 py-3 hover:bg-orange-50 transition-colors text-left border-b border-gray-50">
                  <div className="w-10 h-10 rounded-xl overflow-hidden bg-orange-50 flex-shrink-0">
                    {a.photo_url
                      ? <Image src={a.photo_url} alt="" width={40} height={40} className="object-cover w-full h-full" />
                      : <span className="flex items-center justify-center w-full h-full text-lg">🐾</span>}
                  </div>
                  <div>
                    <p className="font-semibold text-sm text-[#1F2A2E]">{a.nom}</p>
                    <p className="text-xs text-gray-400 capitalize">{a.espece}{a.race ? ` · ${a.race}` : ''}</p>
                  </div>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {photoCropSrc && (
        <ImageCropModal src={photoCropSrc} aspect={1} maxDim={800}
          onConfirm={handleCropConfirm}
          onCancel={() => { URL.revokeObjectURL(photoCropSrc); setPhotoCropSrc(null); }} />
      )}
    </div>
  );
}
