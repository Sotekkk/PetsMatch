'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const ESPECES = ['chien', 'chat', 'lapin', 'oiseau', 'cheval', 'nac', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'NAC', autre: 'Autre',
};

async function uploadPhoto(file: File, uid: string): Promise<string> {
  const ext = file.name.split('.').pop() ?? 'jpg';
  const path = `annonces/${uid}/${Date.now()}.${ext}`;
  const { error } = await supabase.storage.from('PetsMatch').upload(path, file, { upsert: true });
  if (error) throw error;
  const { data } = supabase.storage.from('PetsMatch').getPublicUrl(path);
  return data.publicUrl;
}

export default function CreerAnnonceAssoPage() {
  const { user } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const animalId = params.get('animalId');

  const [titre, setTitre] = useState('');
  const [espece, setEspece] = useState('');
  const [race, setRace] = useState('');
  const [sexe, setSexe] = useState('');
  const [description, setDescription] = useState('');
  const [vaccines, setVaccines] = useState(false);
  const [vermifuge, setVermifuge] = useState(false);
  const [identification, setIdentification] = useState(false);
  const [sterilise, setSterilise] = useState(false);
  const [contratAdoption, setContratAdoption] = useState(true);
  const [linkedAnimalId, setLinkedAnimalId] = useState<string | null>(animalId);
  const [photos, setPhotos] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  // Pré-remplir depuis l'animal si animalId fourni
  useEffect(() => {
    if (!animalId || !user) return;
    supabase.from('animaux')
      .select('nom, espece, race, sexe, vaccins, vermifuge, identification, sterilise, photo_url')
      .eq('id', animalId).single()
      .then(({ data }) => {
        if (!data) return;
        if (data.nom) setTitre(`${data.nom} cherche une famille`);
        if (data.espece) setEspece(data.espece);
        if (data.race) setRace(data.race);
        if (data.sexe) setSexe(data.sexe);
        if (data.vaccins != null) setVaccines(!!data.vaccins);
        if (data.vermifuge != null) setVermifuge(!!data.vermifuge);
        if (data.identification != null) setIdentification(!!data.identification);
        if (data.sterilise != null) setSterilise(!!data.sterilise);
      });
  }, [animalId, user]);

  const handleFiles = (files: FileList | null) => {
    if (!files) return;
    const arr = Array.from(files).slice(0, 6 - photos.length);
    setPhotos(prev => [...prev, ...arr]);
    arr.forEach(f => {
      const reader = new FileReader();
      reader.onload = e => setPreviews(prev => [...prev, e.target?.result as string]);
      reader.readAsDataURL(f);
    });
  };

  const removePhoto = (i: number) => {
    setPhotos(prev => prev.filter((_, idx) => idx !== i));
    setPreviews(prev => prev.filter((_, idx) => idx !== i));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    if (!espece) { setError('Veuillez choisir une espèce.'); return; }
    if (photos.length === 0) { setError('Ajoutez au moins une photo.'); return; }
    setLoading(true);
    setError('');
    try {
      // Upload photos
      const photoUrls = await Promise.all(photos.map(f => uploadPhoto(f, user.uid)));

      // Récupérer infos utilisateur
      const { data: userData } = await supabase.from('users')
        .select('name_elevage, firstname, lastname, ville_elevage, code_postal_elevage')
        .eq('uid', user.uid).single();
      const nomAsso = userData?.name_elevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim();
      const ville = userData?.ville_elevage ?? '';

      await supabase.from('annonces').insert({
        uid_eleveur: user.uid,
        nom_eleveur: nomAsso,
        ville_eleveur: ville,
        titre: titre || `${ESPECE_LABEL[espece] ?? espece} cherche une famille`,
        espece,
        race: race || null,
        sexe: sexe || null,
        type: 'animal',
        type_vente: 'adoption',
        profil_source: 'association',
        photos: photoUrls,
        description: description || null,
        statut: 'disponible',
        vaccines,
        vermifuge,
        identification,
        sterilise,
        contrat_adoption: contratAdoption,
        animal_id: linkedAnimalId ?? null,
        prix: null,
        created_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 60 * 86400000).toISOString(),
        vues: 0,
        contacts: 0,
      });

      router.push('/association/annonces');
    } catch (err: any) {
      setError(err.message ?? 'Erreur lors de la publication.');
    } finally {
      setLoading(false);
    }
  };

  const Toggle = ({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) => (
    <label className="flex items-center justify-between cursor-pointer py-2 border-b border-gray-100 last:border-0">
      <span className="text-sm font-galey text-gray-700">{label}</span>
      <button type="button" onClick={() => onChange(!value)}
        className={`w-11 h-6 rounded-full transition-colors ${value ? 'bg-teal-600' : 'bg-gray-300'} relative flex-shrink-0`}>
        <span className={`absolute top-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${value ? 'translate-x-5' : 'translate-x-0.5'}`} />
      </button>
    </label>
  );

  return (
    <div className="space-y-6 max-w-xl">
      <div className="flex items-center gap-3">
        <button onClick={() => router.back()} className="text-gray-400 hover:text-gray-600 text-xl">←</button>
        <h1 className="text-2xl font-bold font-galey text-teal-800">
          {linkedAnimalId ? 'Mettre en adoption' : 'Nouvelle annonce d\'adoption'}
        </h1>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">

        {/* Titre */}
        <div>
          <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Titre</label>
          <input value={titre} onChange={e => setTitre(e.target.value)} placeholder="Ex : Rex cherche une famille aimante"
            className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400" />
        </div>

        {/* Espèce */}
        <div>
          <label className="block text-sm font-galey font-semibold text-gray-700 mb-2">Espèce *</label>
          <div className="flex flex-wrap gap-2">
            {ESPECES.map(e => (
              <button key={e} type="button" onClick={() => setEspece(e)}
                className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
                  espece === e ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200 hover:border-teal-300'
                }`}>
                {ESPECE_LABEL[e]}
              </button>
            ))}
          </div>
        </div>

        {/* Race / Sexe */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Race</label>
            <input value={race} onChange={e => setRace(e.target.value)} placeholder="Race ou croisé"
              className="w-full px-3 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400" />
          </div>
          <div>
            <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Sexe</label>
            <select value={sexe} onChange={e => setSexe(e.target.value)}
              className="w-full px-3 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400 bg-white">
              <option value="">–</option>
              <option value="male">Mâle</option>
              <option value="femelle">Femelle</option>
            </select>
          </div>
        </div>

        {/* Description */}
        <div>
          <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Description</label>
          <textarea value={description} onChange={e => setDescription(e.target.value)} rows={4}
            placeholder="Décrivez le caractère, les besoins, l'histoire de l'animal…"
            className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400 resize-none" />
        </div>

        {/* Photos */}
        <div>
          <label className="block text-sm font-galey font-semibold text-gray-700 mb-2">Photos * (max 6)</label>
          <div className="flex flex-wrap gap-2">
            {previews.map((src, i) => (
              <div key={i} className="relative w-20 h-20 rounded-xl overflow-hidden border border-gray-200">
                <img src={src} alt="" className="w-full h-full object-cover" />
                <button type="button" onClick={() => removePhoto(i)}
                  className="absolute top-0.5 right-0.5 bg-black/50 text-white rounded-full w-5 h-5 text-xs flex items-center justify-center">✕</button>
              </div>
            ))}
            {photos.length < 6 && (
              <button type="button" onClick={() => fileRef.current?.click()}
                className="w-20 h-20 rounded-xl border-2 border-dashed border-teal-300 flex items-center justify-center text-teal-400 hover:bg-teal-50 transition-colors">
                <span className="text-2xl">+</span>
              </button>
            )}
          </div>
          <input ref={fileRef} type="file" accept="image/*" multiple className="hidden"
            onChange={e => handleFiles(e.target.files)} />
        </div>

        {/* Santé */}
        <div className="bg-white rounded-2xl border border-gray-100 p-4">
          <p className="text-sm font-galey font-semibold text-gray-700 mb-3">Santé</p>
          <Toggle label="Vacciné" value={vaccines} onChange={setVaccines} />
          <Toggle label="Vermifugé" value={vermifuge} onChange={setVermifuge} />
          <Toggle label="Identifié (puce/tatouage)" value={identification} onChange={setIdentification} />
          <Toggle label="Stérilisé" value={sterilise} onChange={setSterilise} />
        </div>

        {/* Conditions adoption */}
        <div className="bg-white rounded-2xl border border-gray-100 p-4">
          <p className="text-sm font-galey font-semibold text-gray-700 mb-3">Conditions d'adoption</p>
          <Toggle label="Contrat d'adoption obligatoire" value={contratAdoption} onChange={setContratAdoption} />
        </div>

        {error && <p className="text-red-500 text-sm font-galey">{error}</p>}

        <button type="submit" disabled={loading}
          className="w-full bg-teal-700 text-white py-3.5 rounded-xl font-galey font-bold text-base hover:bg-teal-800 transition-colors disabled:opacity-50">
          {loading ? 'Publication en cours…' : 'Publier l\'annonce'}
        </button>
      </form>
    </div>
  );
}
