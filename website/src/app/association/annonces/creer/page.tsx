'use client';

import { Suspense, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { loadBreeds } from '@/lib/breeds';
import { Icone } from '@/components/dashboard/kit';
import {
  PageFormulaire, SectionFormulaire, Champ, Colonnes, CaseACocher, GrillePhotos, classeChamp, styleChamp,
} from '@/components/annonces/FormulaireAnnonce';

const ESPECES = ['chien', 'chat', 'lapin', 'oiseau', 'cheval', 'nac', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'NAC', autre: 'Autre',
};

async function uploadPhoto(file: File, uid: string): Promise<string> {
  const ext = file.name.split('.').pop() ?? 'jpg';
  const path = `annonces/${uid}/${Date.now()}.${ext}`;
  const { error } = await supabase.storage.from('petsmatch').upload(path, file, { upsert: true });
  if (error) throw error;
  const { data } = supabase.storage.from('petsmatch').getPublicUrl(path);
  return data.publicUrl;
}

function CreerAnnonceAssoPageInner() {
  const { user, activeProfileId } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const animalIdParam = params.get('animalId');
  const editId = params.get('edit'); // ID annonce à modifier

  const [titre, setTitre] = useState('');
  const [espece, setEspece] = useState('');
  const [especeAutre, setEspeceAutre] = useState('');
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
  const [linkedAnimalDateNaissance, setLinkedAnimalDateNaissance] = useState<string | null>(null);
  const [linkedAnimalAgeEstime, setLinkedAnimalAgeEstime] = useState(false);
  const [photos, setPhotos] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [existingPhotoUrls, setExistingPhotoUrls] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadingEdit, setLoadingEdit] = useState(!!editId);
  const [error, setError] = useState('');
  const [erreursChamps, setErreursChamps] = useState<{ espece?: string; photos?: string }>({});

  const [mesAnimaux, setMesAnimaux] = useState<any[]>([]);
  const [showPicker, setShowPicker] = useState(false);

  // Charger les animaux de l'association
  useEffect(() => {
    if (!user) return;
    supabase.from('animaux')
      .select('id, nom, espece, espece_autre, race, sexe, statut, photo_url, date_naissance, age_estime')
      .eq('uid_eleveur', user.uid)
      .eq('is_association', true)
      .eq('profile_id', activeProfileId)
      .in('statut', ['disponible', 'en_soin'])
      .order('nom')
      .then(({ data }) => setMesAnimaux(data ?? []));
  }, [user, activeProfileId]);

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
          setEspeceAutre(data.espece_autre ?? '');
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
          setLinkedAnimalDateNaissance(data.date_naissance_animal ?? null);
          setLinkedAnimalAgeEstime(data.age_estime ?? false);
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
      .select('nom, espece, espece_autre, race, sexe, photo_url, date_naissance, age_estime')
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
    setLinkedAnimalDateNaissance(data.date_naissance ?? null);
    setLinkedAnimalAgeEstime(data.age_estime ?? false);
    if (data.nom && !editId) setTitre(`${data.nom} cherche une famille`);
    if (data.espece) setEspece(data.espece);
    setEspeceAutre(data.espece_autre ?? '');
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
    // Ajoute à la suite des photos déjà présentes (6 au total).
    const arr = Array.from(files).slice(0, Math.max(0, 6 - photos.length - existingPhotoUrls.length));
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
    const erreurs = {
      espece: !espece ? 'Veuillez choisir une espèce.' : undefined,
      photos: photos.length === 0 && existingPhotoUrls.length === 0 ? 'Ajoutez au moins une photo.' : undefined,
    };
    setErreursChamps(erreurs);
    if (erreurs.espece || erreurs.photos) { setError(erreurs.espece ?? erreurs.photos ?? ''); return; }
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
          espece_autre: espece === 'autre' ? (especeAutre.trim() || null) : null,
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
          date_naissance_animal: linkedAnimalDateNaissance,
          age_estime: linkedAnimalAgeEstime,
        }).eq('id', editId).eq('uid_eleveur', user.uid);
      } else {
        // Mode création — INSERT
        const [{ data: userData }, { data: assoProfile }] = await Promise.all([
          supabase.from('user_profiles_complet')
            .select('nom, firstname, lastname, ville_pro, departement_pro, region_pro, pays_pro')
            .eq('uid', user.uid).eq('is_main', true).single(),
          supabase.from('user_profiles_complet')
            .select('profile_label')
            .eq('uid', user.uid).eq('profile_type', 'association').maybeSingle(),
        ]);
        const nomAsso = assoProfile?.profile_label
          || userData?.nom
          || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim();

        await supabase.from('annonces').insert({
          uid_eleveur: user.uid,
          ...(activeProfileId ? { profile_id: activeProfileId } : {}),
          nom_eleveur: nomAsso,
          ville_eleveur: userData?.ville_pro ?? '',
          departement_eleveur: userData?.departement_pro ?? '',
          region_eleveur: userData?.region_pro ?? '',
          pays_eleveur: userData?.pays_pro ?? 'France',
          titre: titre || `${ESPECE_LABEL[espece] ?? espece} cherche une famille`,
          espece,
          espece_autre: espece === 'autre' ? (especeAutre.trim() || null) : null,
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
          date_naissance_animal: linkedAnimalDateNaissance,
          age_estime: linkedAnimalAgeEstime,
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

  if (loadingEdit) {
    return (
      <div className="flex justify-center py-24">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const photosGrille = [
    ...existingPhotoUrls.map((url, i) => ({ url, cle: `e${i}${url}` })),
    ...previews.map((url, i) => ({ url, cle: `n${i}` })),
  ];

  return (
    <PageFormulaire retourHref="/association/annonces"
      titre={editId ? 'Modifier l’annonce' : linkedAnimalNom ? `Adoption · ${linkedAnimalNom}` : 'Nouvelle annonce d’adoption'}
      sousTitre="Les champs marqués d’un astérisque sont obligatoires."
      erreur={error} onSubmit={handleSubmit} annulerHref="/association/annonces" enregistrement={loading}
      libelleEnregistrer={editId ? 'Enregistrer les modifications' : 'Publier l’annonce'}>

      {/* Informations principales */}
      <SectionFormulaire titre="Informations principales">
        <Champ label="Animal de l’association" aide="Facultatif : relie l’annonce à la fiche de l’animal.">
          {linkedAnimalId ? (
            <div className="flex items-center justify-between gap-3 rounded-xl px-3.5 min-h-11 bg-[#F3F6F5]" style={styleChamp}>
              <span className="text-[15px] font-semibold text-[#1E2025]">{linkedAnimalNom ?? 'Animal lié'}</span>
              <button type="button" onClick={() => { setLinkedAnimalId(null); setLinkedAnimalNom(null); }}
                className="text-sm font-semibold text-[#B91C1C] hover:underline">Retirer</button>
            </div>
          ) : (
            <button type="button" onClick={() => setShowPicker(!showPicker)}
              className="min-h-11 w-full rounded-xl text-sm font-semibold text-[#0C5C6C] bg-white hover:bg-[#E8F4F6]" style={{ border: '1px solid rgba(12,92,108,0.45)' }}>
              Sélectionner un animal disponible
            </button>
          )}
          {showPicker && (
            <div className="mt-2 space-y-1 max-h-56 overflow-y-auto rounded-xl p-1.5" style={styleChamp}>
              {mesAnimaux.length === 0 && <p className="text-sm text-gray-500 text-center py-4">Aucun animal disponible</p>}
              {mesAnimaux.map(a => (
                <button key={a.id} type="button" onClick={() => selectAnimal(a)}
                  className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-[#F3F6F5] text-left transition-colors">
                  {a.photo_url
                    // eslint-disable-next-line @next/next/no-img-element
                    ? <img src={a.photo_url} alt={a.nom} className="w-10 h-10 rounded-lg object-cover flex-shrink-0" />
                    : <div className="w-10 h-10 rounded-lg bg-[#EEF1EF] text-[#0C5C6C] flex items-center justify-center flex-shrink-0"><Icone nom="patte" taille={18} /></div>}
                  <div>
                    <p className="text-sm font-semibold text-[#1E2025]">{a.nom}</p>
                    <p className="text-xs text-gray-500">{a.race || a.espece}</p>
                  </div>
                </button>
              ))}
            </div>
          )}
        </Champ>
        <Champ label="Titre" htmlFor="titre" aide="Par défaut : « [espèce] cherche une famille ».">
          <input id="titre" value={titre} onChange={e => setTitre(e.target.value)} placeholder="Ex : Rex cherche une famille aimante"
            className={classeChamp} style={styleChamp} />
        </Champ>
        <Champ label="Espèce" requis erreur={erreursChamps.espece}>
          <div className="flex flex-wrap gap-2">
            {ESPECES.map(e => (
              <button key={e} type="button" onClick={() => setEspece(e)} aria-pressed={espece === e}
                className={`min-h-10 px-3.5 rounded-xl text-sm font-semibold border transition-colors ${espece === e ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-700 hover:border-[#0C5C6C]/50'}`}
                style={espece === e ? undefined : styleChamp}>
                {ESPECE_LABEL[e]}
              </button>
            ))}
          </div>
          {espece === 'autre' && (
            <input value={especeAutre} onChange={e => setEspeceAutre(e.target.value)} aria-label="Préciser l’espèce"
              placeholder="Préciser l'espèce (ex : furet, tortue…)" className={`${classeChamp} mt-2`} style={styleChamp} />
          )}
        </Champ>
        <Colonnes>
          <div className="relative">
            <Champ label="Race" htmlFor="race">
              <input id="race" value={raceQuery}
                onChange={e => { setRaceQuery(e.target.value); setRace(e.target.value); }}
                placeholder={espece ? 'Rechercher…' : 'Choisir une espèce d’abord'} disabled={!espece}
                className={`${classeChamp} disabled:bg-gray-50`} style={styleChamp} />
            </Champ>
            {raceQuery.length >= 1 && filteredBreeds.length > 0 && filteredBreeds[0] !== race && (
              <div className="absolute z-10 mt-1 w-full bg-white rounded-xl shadow-lg max-h-48 overflow-y-auto" style={styleChamp}>
                {filteredBreeds.map(b => (
                  <button key={b} type="button" onClick={() => { setRace(b); setRaceQuery(b); }}
                    className="w-full text-left px-3.5 py-2.5 text-sm hover:bg-[#F3F6F5] transition-colors">{b}</button>
                ))}
              </div>
            )}
          </div>
          <Champ label="Sexe" htmlFor="sexe">
            <select id="sexe" value={sexe} onChange={e => setSexe(e.target.value)} className={classeChamp} style={styleChamp}>
              <option value="">Non précisé</option>
              <option value="male">Mâle</option>
              <option value="femelle">Femelle</option>
            </select>
          </Champ>
        </Colonnes>
      </SectionFormulaire>

      {/* Photos */}
      <SectionFormulaire titre="Photos et médias">
        <Champ label="Photos" requis erreur={erreursChamps.photos} aide="Jusqu’à 6 photos ; la première est la photo principale.">
          <GrillePhotos photos={photosGrille} max={6}
            onAjouter={e => { handleFiles(e.target.files); e.target.value = ''; }}
            onRetirer={i => i < existingPhotoUrls.length ? removeExistingPhoto(existingPhotoUrls[i]) : removePhoto(i - existingPhotoUrls.length)} />
        </Champ>
      </SectionFormulaire>

      {/* Description */}
      <SectionFormulaire titre="Description">
        <Champ label="Présentation" htmlFor="description">
          <textarea id="description" value={description} onChange={e => setDescription(e.target.value)} rows={5}
            placeholder="Décrivez le caractère, les besoins, l'histoire de l'animal…" className={`${classeChamp} resize-y`} style={styleChamp} />
        </Champ>
      </SectionFormulaire>

      {/* Santé */}
      <SectionFormulaire titre="Santé">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6">
          <CaseACocher label="Vacciné(e)" checked={vaccines} onChange={setVaccines} />
          <CaseACocher label="Vermifugé(e)" checked={vermifuge} onChange={setVermifuge} />
          <CaseACocher label="Identifié(e) (puce / tatouage)" checked={identification} onChange={setIdentification} />
          <CaseACocher label="Stérilisé(e)" checked={sterilise} onChange={setSterilise} />
        </div>
      </SectionFormulaire>

      {/* Conditions */}
      <SectionFormulaire titre="Conditions d’adoption">
        <CaseACocher label="Contrat d’adoption obligatoire" checked={contratAdoption} onChange={setContratAdoption} />
      </SectionFormulaire>
    </PageFormulaire>
  );
}

export default function CreerAnnonceAssoPage() {
  return (
    <Suspense fallback={null}>
      <CreerAnnonceAssoPageInner />
    </Suspense>
  );
}
