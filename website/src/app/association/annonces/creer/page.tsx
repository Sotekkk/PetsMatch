'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { loadBreeds } from '@/lib/breeds';

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
  const animalIdParam = params.get('animalId');
  const editId = params.get('edit'); // ID annonce à modifier

  const [titre, setTitre] = useState('');
  const [espece, setEspece] = useState('');
  const [race, setRace] = useState('');
  const [raceQuery, setRaceQuery] = useState('');
  const [breeds, setBreeds] = useState<string[]>([]);
  const [sexe, setSexe] = useState('');
  const [description, setDescription] = useState('');
  const [vaccines, setVaccines] = useState(false);
  const [vermifuge, setVermifuge] = useState(false);
  const [identification, setIdentification] = useState(false);
  const [sterilise, setSterilise] = useState(false);
  const [contratAdoption, setContratAdoption] = useState(true);
  const [linkedAnimalId, setLinkedAnimalId] = useState<string | null>(animalIdParam);
  const [linkedAnimalNom, setLinkedAnimalNom] = useState<string | null>(null);
  const [photos, setPhotos] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [existingPhotoUrls, setExistingPhotoUrls] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadingEdit, setLoadingEdit] = useState(!!editId);
  const [error, setError] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  const [mesAnimaux, setMesAnimaux] = useState<any[]>([]);
  const [showPicker, setShowPicker] = useState(false);

  // Charger les animaux de l'association
  useEffect(() => {
    if (!user) return;
    supabase.from('animaux')
      .select('id, nom, espece, race, sexe, statut, photo_url')
      .eq('uid_eleveur', user.uid)
      .eq('is_association', true)
      .in('statut', ['disponible', 'en_soin'])
      .order('nom')
      .then(({ data }) => setMesAnimaux(data ?? []));
  }, [user]);

  // Charger l'annonce existante pour édition
  useEffect(() => {
    if (!editId || !user) return;
    setLoadingEdit(true);
    supabase.from('annonces')
      .select('*')
      .eq('id', editId)
      .eq('uid_eleveur', user.uid)
      .single()
      .then(({ data }) => {
        if (data) {
          setTitre(data.titre ?? '');
          setEspece(data.espece ?? '');
          setRace(data.race ?? '');
          setRaceQuery(data.race ?? '');
          setSexe(data.sexe ?? '');
          setDescription(data.description ?? '');
          setVaccines(data.vaccines ?? false);
          setVermifuge(data.vermifuge ?? false);
          setIdentification(data.identification ?? false);
          setSterilise(data.sterilise ?? false);
          setContratAdoption(data.contrat_adoption ?? true);
          if (data.animal_id) setLinkedAnimalId(data.animal_id);
          const existingPhotos = (data.photos as string[]) ?? [];
          setExistingPhotoUrls(existingPhotos);
        }
        setLoadingEdit(false);
      });
  }, [editId, user]);

  // Pré-remplir depuis un animal si animalId en param
  useEffect(() => {
    if (!animalIdParam || !user || editId) return;
    supabase.from('animaux')
      .select('nom, espece, race, sexe, photo_url')
      .eq('id', animalIdParam).single()
      .then(({ data }) => { if (data) prefillAnimal(data, animalIdParam); });
  }, [animalIdParam, user]);

  // Charger les races quand l'espèce change
  useEffect(() => {
    if (!espece) return;
    loadBreeds(espece).then(setBreeds);
    if (!editId) { setRace(''); setRaceQuery(''); }
  }, [espece]);

  function prefillAnimal(data: any, id: string) {
    setLinkedAnimalId(id);
    setLinkedAnimalNom(data.nom ?? null);
    if (data.nom && !editId) setTitre(`${data.nom} cherche une famille`);
    if (data.espece) setEspece(data.espece);
    if (data.race) { setRace(data.race); setRaceQuery(data.race); }
    if (data.sexe) setSexe(data.sexe);
    if (data.photo_url && !editId) setExistingPhotoUrls([data.photo_url]);
  }

  function selectAnimal(a: any) {
    prefillAnimal(a, a.id);
    setShowPicker(false);
  }

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

  const removeExistingPhoto = (url: string) => {
    setExistingPhotoUrls(prev => prev.filter(u => u !== url));
  };

  const filteredBreeds = breeds.filter(b =>
    b.toLowerCase().includes(raceQuery.toLowerCase())
  ).slice(0, 8);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    if (!espece) { setError('Veuillez choisir une espèce.'); return; }
    if (photos.length === 0 && existingPhotoUrls.length === 0) { setError('Ajoutez au moins une photo.'); return; }
    setLoading(true);
    setError('');
    try {
      const uploaded = await Promise.all(photos.map(f => uploadPhoto(f, user.uid)));
      const finalPhotos = [...existingPhotoUrls, ...uploaded];

      if (editId) {
        // Mode édition — UPDATE
        await supabase.from('annonces').update({
          titre: titre || `${ESPECE_LABEL[espece] ?? espece} cherche une famille`,
          espece,
          race: race || null,
          sexe: sexe || null,
          description: description || null,
          photos: finalPhotos,
          vaccines,
          vermifuge,
          identification,
          sterilise,
          contrat_adoption: contratAdoption,
          animal_id: linkedAnimalId && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(linkedAnimalId) ? linkedAnimalId : null,
        }).eq('id', editId).eq('uid_eleveur', user.uid);
      } else {
        // Mode création — INSERT
        const [{ data: userData }, { data: assoProfile }] = await Promise.all([
          supabase.from('users')
            .select('name_elevage, firstname, lastname, ville_elevage, departement_elevage, region_elevage, pays_elevage')
            .eq('uid', user.uid).single(),
          supabase.from('user_profiles')
            .select('profile_label')
            .eq('uid', user.uid).eq('profile_type', 'association').maybeSingle(),
        ]);
        const nomAsso = assoProfile?.profile_label
          || userData?.name_elevage
          || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim();

        await supabase.from('annonces').insert({
          uid_eleveur: user.uid,
          nom_eleveur: nomAsso,
          ville_eleveur: userData?.ville_elevage ?? '',
          departement_eleveur: userData?.departement_elevage ?? '',
          region_eleveur: userData?.region_elevage ?? '',
          pays_eleveur: userData?.pays_elevage ?? 'France',
          titre: titre || `${ESPECE_LABEL[espece] ?? espece} cherche une famille`,
          espece,
          race: race || null,
          sexe: sexe || null,
          type: 'animal',
          type_vente: 'adoption',
          profil_source: 'association',
          photos: finalPhotos,
          description: description || null,
          statut: 'disponible',
          vaccines,
          vermifuge,
          identification,
          sterilise,
          contrat_adoption: contratAdoption,
          animal_id: linkedAnimalId && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(linkedAnimalId) ? linkedAnimalId : null,
          prix: null,
          created_at: new Date().toISOString(),
          expires_at: new Date(Date.now() + 60 * 86400000).toISOString(),
          vues: 0,
          contacts: 0,
        });
      }

      router.push('/association/annonces');
    } catch (err: any) {
      setError(err.message ?? 'Erreur lors de la sauvegarde.');
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

  if (loadingEdit) {
    return (
      <div className="flex justify-center py-24">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-xl">
      <div className="flex items-center gap-3">
        <button onClick={() => router.back()} className="text-gray-400 hover:text-gray-600 text-xl">←</button>
        <h1 className="text-2xl font-bold font-galey text-teal-800">
          {editId ? 'Modifier l\'annonce' : linkedAnimalNom ? `Adoption — ${linkedAnimalNom}` : 'Nouvelle annonce d\'adoption'}
        </h1>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">

        {/* Sélecteur d'animal */}
        <div className="bg-teal-50 border border-teal-200 rounded-2xl p-4">
          <p className="text-sm font-galey font-semibold text-teal-800 mb-2">Lier à un animal</p>
          {linkedAnimalId ? (
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-sm font-galey font-semibold text-teal-800">
                  {linkedAnimalNom ?? linkedAnimalId}
                </span>
              </div>
              <button type="button" onClick={() => { setLinkedAnimalId(null); setLinkedAnimalNom(null); }}
                className="text-xs text-gray-400 hover:text-gray-600">Retirer</button>
            </div>
          ) : (
            <button type="button" onClick={() => setShowPicker(!showPicker)}
              className="w-full text-sm text-teal-700 border border-teal-300 bg-white rounded-xl py-2 font-galey hover:bg-teal-50 transition-colors">
              🐾 Sélectionner un animal disponible
            </button>
          )}
          {showPicker && (
            <div className="mt-3 space-y-2 max-h-48 overflow-y-auto">
              {mesAnimaux.length === 0 && (
                <p className="text-xs text-gray-400 text-center py-4">Aucun animal disponible</p>
              )}
              {mesAnimaux.map(a => (
                <button key={a.id} type="button" onClick={() => selectAnimal(a)}
                  className="w-full flex items-center gap-3 p-2 rounded-xl hover:bg-teal-100 text-left transition-colors">
                  {a.photo_url ? (
                    <img src={a.photo_url} alt={a.nom} className="w-10 h-10 rounded-lg object-cover flex-shrink-0" />
                  ) : (
                    <div className="w-10 h-10 rounded-lg bg-gray-100 flex items-center justify-center text-lg flex-shrink-0">🐾</div>
                  )}
                  <div>
                    <p className="text-sm font-galey font-semibold text-gray-800">{a.nom}</p>
                    <p className="text-xs text-gray-500">{a.race || a.espece}</p>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>

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
          <div className="relative">
            <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Race</label>
            <input value={raceQuery}
              onChange={e => { setRaceQuery(e.target.value); setRace(e.target.value); }}
              placeholder={espece ? 'Rechercher…' : 'Choisir une espèce d\'abord'}
              disabled={!espece}
              className="w-full px-3 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400 disabled:bg-gray-50" />
            {raceQuery.length >= 1 && filteredBreeds.length > 0 && (
              <div className="absolute z-10 mt-1 w-full bg-white rounded-xl border border-gray-200 shadow-lg max-h-48 overflow-y-auto">
                {filteredBreeds.map(b => (
                  <button key={b} type="button" onClick={() => { setRace(b); setRaceQuery(b); }}
                    className="w-full text-left px-3 py-2 text-sm font-galey hover:bg-teal-50 transition-colors">
                    {b}
                  </button>
                ))}
              </div>
            )}
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
            {existingPhotoUrls.map((url, i) => (
              <div key={`existing-${i}`} className="relative w-20 h-20 rounded-xl overflow-hidden border-2 border-teal-200">
                <img src={url} alt="" className="w-full h-full object-cover" />
                <button type="button" onClick={() => removeExistingPhoto(url)}
                  className="absolute top-0.5 right-0.5 bg-black/50 text-white rounded-full w-5 h-5 text-xs flex items-center justify-center">✕</button>
              </div>
            ))}
            {previews.map((src, i) => (
              <div key={`new-${i}`} className="relative w-20 h-20 rounded-xl overflow-hidden border border-gray-200">
                <img src={src} alt="" className="w-full h-full object-cover" />
                <button type="button" onClick={() => removePhoto(i)}
                  className="absolute top-0.5 right-0.5 bg-black/50 text-white rounded-full w-5 h-5 text-xs flex items-center justify-center">✕</button>
              </div>
            ))}
            {(existingPhotoUrls.length + photos.length) < 6 && (
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
          <Toggle label="Vacciné(e)" value={vaccines} onChange={setVaccines} />
          <Toggle label="Vermifugé(e)" value={vermifuge} onChange={setVermifuge} />
          <Toggle label="Identifié(e) (puce/tatouage)" value={identification} onChange={setIdentification} />
          <Toggle label="Stérilisé(e)" value={sterilise} onChange={setSterilise} />
        </div>

        {/* Conditions */}
        <div className="bg-white rounded-2xl border border-gray-100 p-4">
          <p className="text-sm font-galey font-semibold text-gray-700 mb-3">Conditions d'adoption</p>
          <Toggle label="Contrat d'adoption obligatoire" value={contratAdoption} onChange={setContratAdoption} />
        </div>

        {error && <p className="text-red-500 text-sm font-galey">{error}</p>}

        <button type="submit" disabled={loading}
          className="w-full bg-teal-700 text-white py-3.5 rounded-xl font-galey font-bold text-base hover:bg-teal-800 transition-colors disabled:opacity-50">
          {loading ? (editId ? 'Sauvegarde…' : 'Publication…') : (editId ? 'Sauvegarder les modifications' : 'Publier l\'annonce')}
        </button>
      </form>
    </div>
  );
}
