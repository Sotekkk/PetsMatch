'use client';

import { useState, useEffect, useCallback, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';

const PLAN_CONFIG: Record<string, { maxAnnonces: number; dureeDays: number; autoPublish: boolean }> = {
  free:    { maxAnnonces: 3,  dureeDays: 30, autoPublish: false },
  pro:     { maxAnnonces: 10, dureeDays: 45, autoPublish: true  },
  premium: { maxAnnonces: -1, dureeDays: 60, autoPublish: true  },
};

async function getUserPlanClient(uid: string): Promise<keyof typeof PLAN_CONFIG> {
  try {
    const { data } = await supabase.from('abonnements').select('plan_code').eq('uid', uid).eq('statut', 'actif').order('created_at', { ascending: false }).limit(1).maybeSingle();
    return (data?.plan_code ?? 'free') as keyof typeof PLAN_CONFIG;
  } catch { return 'free'; }
}

const ESPECES = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Cheval', 'Reptile', 'Autre'];

function genId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
}

const ESPECE_DB: Record<string, string> = {
  'Chien': 'chien', 'Chat': 'chat', 'Lapin': 'lapin', 'Oiseau': 'oiseau',
  'Cheval': 'cheval', 'Reptile': 'nac', 'Autre': 'autre',
};

const BREED_FILE: Record<string, string> = {
  'Chien':   '/breeds/dog_breeds.json',
  'Chat':    '/breeds/cat_breeds.json',
  'Lapin':   '/breeds/rabbit_breeds.json',
  'Oiseau':  '/breeds/bird_breeds.json',
  'Cheval':  '/breeds/horse_breeds.json',
  'Reptile': '/breeds/nac_breeds.json',
};

interface AnimalPortee {
  id: string;
  animalId?: string;
  nom: string;
  sexe: 'male' | 'femelle';
  couleur: string;
  prix: string;
  statut: 'disponible' | 'reserve' | 'vendu';
  description: string;
  photos?: string[];
  isLinked?: boolean;
}

interface MyAnimal {
  id: string;
  nom: string | null;
  sexe?: string | null;
  espece?: string | null;
  race: string | null;
  couleur: string | null;
  description: string | null;
  identification: string | null;
  photo_url: string | null;
  pedigree_lof?: string | null;
  club_registre?: string | null;
}

const DB_TO_ESPECE: Record<string, string> = {
  'chien': 'Chien', 'chat': 'Chat', 'lapin': 'Lapin', 'oiseau': 'Oiseau',
  'cheval': 'Cheval', 'nac': 'Reptile', 'autre': 'Autre',
};

function CreerAnnoncePageInner() {
  const { user, userData, loading } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();

  // ── Type
  const [type, setType] = useState<'compagnon' | 'portee' | 'saillie' | 'retraite'>('compagnon');
  const [cession, setCession] = useState<'vente' | 'adoption'>('vente');

  // ── Infos communes
  const [titre, setTitre] = useState('');
  const [espece, setEspece] = useState('Chien');
  const [race, setRace] = useState('');
  const [breeds, setBreeds] = useState<string[]>([]);
  const [description, setDescription] = useState('');

  // ── Photos annonce
  const [croppedBlobs, setCroppedBlobs] = useState<Blob[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [cropQueue, setCropQueue] = useState<File[]>([]);
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [showQuotaModal, setShowQuotaModal] = useState(false);
  const [quotaBuying, setQuotaBuying] = useState(false);

  // ── Compagnon
  const [sexeAnimal, setSexeAnimal] = useState<'male' | 'femelle'>('male');
  const [couleurAnimal, setCouleurAnimal] = useState('');
  const [sterilise, setSterilise] = useState(false);
  const [prix, setPrix] = useState('');

  // ── Portée
  const [dateNaissance, setDateNaissance] = useState('');
  const [nombreBebes, setNombreBebes] = useState(1);
  const [prixMin, setPrixMin] = useState('');
  const [prixMax, setPrixMax] = useState('');
  const [animauxPortee, setAnimauxPortee] = useState<AnimalPortee[]>([]);

  // ── Portée — photos & modal bébé
  const [babyPhotos, setBabyPhotos] = useState<Record<string, { blobs: Blob[]; previews: string[] }>>({});
  const [editingBaby, setEditingBaby] = useState<AnimalPortee | null>(null);
  const [babyCropSrc, setBabyCropSrc] = useState<string | null>(null);
  const [babyCropTargetId, setBabyCropTargetId] = useState<string | null>(null);
  const [babyCropQueue, setBabyCropQueue] = useState<File[]>([]);
  const [showBabyPicker, setShowBabyPicker] = useState(false);
  const [babyPickerAnimals, setBabyPickerAnimals] = useState<MyAnimal[]>([]);
  const [loadingBabyPicker, setLoadingBabyPicker] = useState(false);

  // ── Santé & Conformité
  const [vaccines, setVaccines] = useState(false);
  const [vermifuge, setVermifuge] = useState(false);
  const [identificationSante, setIdentificationSante] = useState(false);
  const [bilanSante, setBilanSante] = useState(false);
  const [semaines, setSemaines] = useState(8);
  const [clubPedigree, setClubPedigree] = useState('');
  const [numRegistre, setNumRegistre] = useState('');

  // ── Saillie
  const [sailliePrix, setSailliePrix] = useState('');
  const [saillieConditions, setSaillieConditions] = useState('');

  // ── Identification légale (champs obligatoires selon Code rural)
  const [numSIRE, setNumSIRE] = useState('');
  const [numPasseportEquin, setNumPasseportEquin] = useState('');
  const [numIdentification, setNumIdentification] = useState('');

  // ── Retraité d'élevage
  const [retraiteAnimalId, setRetraiteAnimalId] = useState<string | null>(null);
  const [retraiteAnimalNom, setRetraiteAnimalNom] = useState<string | null>(null);
  const [showRetraitePicker, setShowRetraitePicker] = useState(false);
  const [myAnimalsAll, setMyAnimalsAll] = useState<MyAnimal[]>([]);
  const [loadingRetraite, setLoadingRetraite] = useState(false);

  // ── Saillie : picker étalon (avant espèce)
  const [showEtalonPicker, setShowEtalonPicker] = useState(false);
  const [myAllMales, setMyAllMales] = useState<MyAnimal[]>([]);
  const [loadingAllMales, setLoadingAllMales] = useState(false);

  // ── Mère
  const [mereAnimalId, setMereAnimalId] = useState<string | null>(null);
  const [mereNom, setMereNom] = useState('');
  const [merePuce, setMerePuce] = useState('');
  const [mereRace, setMereRace] = useState('');
  const [mereCouleur, setMereCouleur] = useState('');
  const [mereDescription, setMereDescription] = useState('');
  const [mereRegistre, setMereRegistre] = useState('');
  const [merePhotoBlob, setMerePhotoBlob] = useState<Blob | null>(null);
  const [merePhotoPreview, setMerePhotoPreview] = useState<string | null>(null);
  const [mereCropSrc, setMereCropSrc] = useState<string | null>(null);
  const [showMerePicker, setShowMerePicker] = useState(false);
  const [myFemelles, setMyFemelles] = useState<MyAnimal[]>([]);
  const [loadingFemelles, setLoadingFemelles] = useState(false);

  // ── Père
  const [pereAnimalId, setPereAnimalId] = useState<string | null>(null);
  const [pereNom, setPereNom] = useState('');
  const [perePuce, setPerePuce] = useState('');
  const [pereRace, setPereRace] = useState('');
  const [pereCouleur, setPereCouleur] = useState('');
  const [pereDescription, setPereDescription] = useState('');
  const [pereRegistre, setPereRegistre] = useState('');
  const [perePhotoBlob, setPerePhotoBlob] = useState<Blob | null>(null);
  const [perePhotoPreview, setPerePhotoPreview] = useState<string | null>(null);
  const [pereCropSrc, setPereCropSrc] = useState<string | null>(null);
  const [showPerePicker, setShowPerePicker] = useState(false);
  const [myMales, setMyMales] = useState<MyAnimal[]>([]);
  const [loadingMales, setLoadingMales] = useState(false);

  // ── Breeds: reload when espece changes
  useEffect(() => {
    const file = BREED_FILE[espece];
    setRace('');
    if (!file) { setBreeds([]); return; }
    fetch(file)
      .then(r => r.json())
      .then(data => setBreeds(data as string[]))
      .catch(() => setBreeds([]));
  }, [espece]);

  // ── Pré-remplissage depuis une portée existante (param ?portee_id=...)
  useEffect(() => {
    const porteeId = searchParams.get('portee_id');
    if (!porteeId || !user) return;
    (async () => {
      const { data: members } = await supabase
        .from('animaux')
        .select('id, nom, sexe, espece, race, couleur, identification, date_naissance, photo_url, nom_pere, puce_pere, nom_mere, puce_mere, race_mere, pedigree_lof')
        .eq('portee_id', porteeId)
        .eq('uid_eleveur', user.uid);
      if (!members || members.length === 0) return;
      const first = members[0];

      // Espèce / Race / Date
      const especeDb: string = first.espece ?? 'chien';
      setEspece(DB_TO_ESPECE[especeDb] ?? 'Chien');
      setRace(first.race ?? '');
      setDateNaissance(first.date_naissance ? first.date_naissance.substring(0, 10) : '');
      setNombreBebes(members.length);
      setType('portee');

      // Chiots — générer les IDs avant pour pré-charger les photos
      const porteeAnimaux = members.map((m: Record<string, unknown>) => ({
        id: crypto.randomUUID(),
        animalId: m.id as string,
        nom: (m.nom as string) ?? '',
        sexe: ((m.sexe as string) ?? 'male') as 'male' | 'femelle',
        couleur: (m.couleur as string) ?? '',
        prix: '',
        statut: 'disponible' as const,
        description: '',
        photos: m.photo_url ? [m.photo_url as string] : [],
        isLinked: true,
      }));
      setAnimauxPortee(porteeAnimaux);

      // Pré-charger les photos existantes dans babyPhotos (pour l'affichage dans les cartes)
      const initBabyPhotos: Record<string, { blobs: Blob[]; previews: string[] }> = {};
      porteeAnimaux.forEach(baby => {
        const url = (baby.photos as string[])[0];
        if (url) initBabyPhotos[baby.id] = { blobs: [], previews: [url] };
      });
      if (Object.keys(initBabyPhotos).length > 0) setBabyPhotos(initBabyPhotos);

      // Chercher père et mère dans les animaux de l'éleveur
      const nomPere = (first.nom_pere as string) ?? '';
      const pucePere = (first.puce_pere as string) ?? '';
      const nomMere = (first.nom_mere as string) ?? '';
      const puceMere = (first.puce_mere as string) ?? '';

      if (nomPere || pucePere) {
        const { data: pereRows } = await supabase.from('animaux')
          .select('id, nom, sexe, race, couleur, identification, photo_url, pedigree_lof')
          .eq('uid_eleveur', user.uid)
          .eq('espece', especeDb)
          .limit(100);
        const pere = (pereRows ?? []).find((a: Record<string, unknown>) =>
          (nomPere && a.nom === nomPere) || (pucePere && a.identification === pucePere));
        if (pere) {
          setPereAnimalId(pere.id as string);
          setPereNom((pere.nom as string) ?? nomPere);
          setPerePuce((pere.identification as string) ?? pucePere);
          setPereRace((pere.race as string) ?? '');
          setPereCouleur((pere.couleur as string) ?? '');
          setPereRegistre((pere.pedigree_lof as string) ?? '');
          if (pere.photo_url) setPerePhotoPreview(pere.photo_url as string);
        } else {
          setPereNom(nomPere);
          setPerePuce(pucePere);
        }
      }

      if (nomMere || puceMere) {
        const { data: mereRows } = await supabase.from('animaux')
          .select('id, nom, sexe, race, couleur, identification, photo_url, pedigree_lof')
          .eq('uid_eleveur', user.uid)
          .eq('espece', especeDb)
          .limit(100);
        const mere = (mereRows ?? []).find((a: Record<string, unknown>) =>
          (nomMere && a.nom === nomMere) || (puceMere && a.identification === puceMere));
        if (mere) {
          setMereAnimalId(mere.id as string);
          setMereNom((mere.nom as string) ?? nomMere);
          setMerePuce((mere.identification as string) ?? puceMere);
          setMereRace((mere.race as string) ?? (first.race_mere as string ?? ''));
          setMereCouleur((mere.couleur as string) ?? '');
          setMereRegistre((mere.pedigree_lof as string) ?? '');
          if (mere.photo_url) setMerePhotoPreview(mere.photo_url as string);
        } else {
          setMereNom(nomMere);
          setMerePuce(puceMere);
          setMereRace((first.race_mere as string) ?? '');
        }
      }
    })();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams, user]);

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  if (!user) { router.push('/connexion'); return null; }
  if (!userData?.isElevage) {
    return (
      <div className="min-h-[60vh] flex flex-col items-center justify-center gap-4 px-4 text-center">
        <span className="text-4xl">🔒</span>
        <p className="font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Réservé aux éleveurs certifiés
        </p>
        <p className="text-sm text-gray-500">
          La publication d&apos;annonces est réservée aux éleveurs disposant d&apos;un numéro SIRET valide et d&apos;un dossier validé.
        </p>
      </div>
    );
  }

  const iCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
  const iSmCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
  const sCls = 'border border-gray-100 rounded-xl p-4 space-y-3';

  function thumbUrl(url: string) {
    if (!url.includes('/storage/v1/object/public/')) return url;
    return url.replace('/storage/v1/object/', '/storage/v1/render/image/') + '?width=80&quality=70&resize=contain';
  }

  // ── My animals loaders
  async function loadFemelles() {
    setLoadingFemelles(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, race, couleur, description, identification, photo_url')
      .eq('uid_eleveur', user!.uid)
      .eq('espece', ESPECE_DB[espece] ?? espece.toLowerCase())
      .eq('sexe', 'femelle').order('nom');
    setMyFemelles((data ?? []) as MyAnimal[]);
    setLoadingFemelles(false);
  }

  async function loadMales() {
    setLoadingMales(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, couleur, description, identification, photo_url, pedigree_lof, club_registre')
      .eq('uid_eleveur', user!.uid)
      .eq('espece', ESPECE_DB[espece] ?? espece.toLowerCase())
      .eq('sexe', 'male').order('nom');
    setMyMales((data ?? []) as MyAnimal[]);
    setLoadingMales(false);
  }

  async function loadAllAnimals() {
    setLoadingRetraite(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, couleur, description, identification, photo_url, pedigree_lof, club_registre')
      .eq('uid_eleveur', user!.uid).order('nom');
    setMyAnimalsAll((data ?? []) as MyAnimal[]);
    setLoadingRetraite(false);
  }

  async function loadAllMales() {
    setLoadingAllMales(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, couleur, description, identification, photo_url, pedigree_lof, club_registre')
      .eq('uid_eleveur', user!.uid).eq('sexe', 'male').order('nom');
    setMyAllMales((data ?? []) as MyAnimal[]);
    setLoadingAllMales(false);
  }

  function selectEtalon(a: MyAnimal) {
    // Remplit la section père (= étalon)
    setPereAnimalId(a.id); setPereNom(a.nom ?? ''); setPerePuce(a.identification ?? '');
    setNumIdentification(a.identification ?? '');
    setPereRace(a.race ?? ''); setPereCouleur(a.couleur ?? ''); setPereDescription(a.description ?? '');
    setPerePhotoPreview(a.photo_url ?? null); setPerePhotoBlob(null);
    if (a.pedigree_lof) setPereRegistre(a.pedigree_lof);
    if (a.club_registre) setClubPedigree(a.club_registre);
    // Auto-fill espèce + race
    if (a.espece) {
      const especeDisplay = DB_TO_ESPECE[a.espece];
      if (especeDisplay) setEspece(especeDisplay);
    }
    if (a.race) setRace(a.race);
    if (!titre && a.nom) setTitre(`${a.nom} — Saillie`);
    setShowEtalonPicker(false);
  }

  async function loadBabyPickerAnimals() {
    setLoadingBabyPicker(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, race, couleur, description, identification, photo_url')
      .eq('uid_eleveur', user!.uid)
      .eq('espece', ESPECE_DB[espece] ?? espece.toLowerCase())
      .order('nom');
    setBabyPickerAnimals((data ?? []) as MyAnimal[]);
    setLoadingBabyPicker(false);
  }

  // ── Parent selectors
  function selectMere(a: MyAnimal) {
    setMereAnimalId(a.id); setMereNom(a.nom ?? ''); setMerePuce(a.identification ?? '');
    setMereRace(a.race ?? ''); setMereCouleur(a.couleur ?? ''); setMereDescription(a.description ?? '');
    setMerePhotoPreview(a.photo_url ?? null);
    setMerePhotoBlob(null); setShowMerePicker(false);
  }
  function clearMere() {
    setMereAnimalId(null); setMereNom(''); setMerePuce(''); setMereRace('');
    setMereCouleur(''); setMereDescription(''); setMereRegistre('');
    setMerePhotoPreview(null); setMerePhotoBlob(null);
  }

  function selectPere(a: MyAnimal) {
    setPereAnimalId(a.id); setPereNom(a.nom ?? ''); setPerePuce(a.identification ?? '');
    setPereRace(a.race ?? ''); setPereCouleur(a.couleur ?? ''); setPereDescription(a.description ?? '');
    setPerePhotoPreview(a.photo_url ?? null);
    // Pré-remplir pedigree étalon/père
    if (a.pedigree_lof) setPereRegistre(a.pedigree_lof);
    if (a.club_registre) setClubPedigree(a.club_registre);
    setPerePhotoBlob(null); setShowPerePicker(false);
  }

  function selectRetraite(a: MyAnimal) {
    setRetraiteAnimalId(a.id);
    setRetraiteAnimalNom(a.nom);
    setSexeAnimal((a.sexe === 'femelle' ? 'femelle' : 'male') as 'male' | 'femelle');
    setCouleurAnimal(a.couleur ?? '');
    setRace(a.race ?? '');
    setNumIdentification(a.identification ?? '');
    if (a.description) setDescription(a.description);
    // Auto-fill espèce (valeur DB → label affichage)
    if (a.espece) {
      const especeDisplay = DB_TO_ESPECE[a.espece];
      if (especeDisplay) setEspece(especeDisplay);
    }
    if (!titre && a.nom) setTitre(`${a.nom} — Retraité d'élevage`);
    // Pedigree
    if (a.pedigree_lof) setNumRegistre(a.pedigree_lof);
    if (a.club_registre) setClubPedigree(a.club_registre);
    setShowRetraitePicker(false);
  }
  function clearPere() {
    setPereAnimalId(null); setPereNom(''); setPerePuce(''); setPereRace('');
    setPereCouleur(''); setPereDescription(''); setPereRegistre('');
    setPerePhotoPreview(null); setPerePhotoBlob(null);
  }

  // ── Parent photo handlers
  function handleMerePhotoFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0]; if (!f) return;
    setMereCropSrc(URL.createObjectURL(f)); e.target.value = '';
  }
  function handleMereCropConfirm(blob: Blob) {
    setMerePhotoBlob(blob);
    if (merePhotoPreview?.startsWith('blob:')) URL.revokeObjectURL(merePhotoPreview);
    setMerePhotoPreview(URL.createObjectURL(blob));
    if (mereCropSrc) URL.revokeObjectURL(mereCropSrc); setMereCropSrc(null);
  }
  function handlePerePhotoFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0]; if (!f) return;
    setPereCropSrc(URL.createObjectURL(f)); e.target.value = '';
  }
  function handlePereCropConfirm(blob: Blob) {
    setPerePhotoBlob(blob);
    if (perePhotoPreview?.startsWith('blob:')) URL.revokeObjectURL(perePhotoPreview);
    setPerePhotoPreview(URL.createObjectURL(blob));
    if (pereCropSrc) URL.revokeObjectURL(pereCropSrc); setPereCropSrc(null);
  }

  // ── Baby modal
  function openAddBaby() {
    setEditingBaby({ id: crypto.randomUUID(), nom: '', sexe: 'male', couleur: '', prix: '', statut: 'disponible', description: '' });
    setShowBabyPicker(false);
  }
  function openEditBaby(baby: AnimalPortee) {
    setEditingBaby({ ...baby }); setShowBabyPicker(false);
  }
  function saveBaby() {
    if (!editingBaby) return;
    setAnimauxPortee(prev => {
      const idx = prev.findIndex(a => a.id === editingBaby.id);
      if (idx >= 0) { const u = [...prev]; u[idx] = editingBaby; return u; }
      return [...prev, editingBaby];
    });
    setEditingBaby(null); setShowBabyPicker(false);
  }
  function removeBaby(id: string) {
    setAnimauxPortee(prev => prev.filter(a => a.id !== id));
    setBabyPhotos(prev => { const n = { ...prev }; delete n[id]; return n; });
  }

  // ── Baby animal picker (info only, no photo)
  function selectBabyAnimal(a: MyAnimal) {
    if (!editingBaby) return;
    setEditingBaby(prev => prev ? {
      ...prev,
      nom: a.nom ?? '',
      couleur: a.couleur ?? '',
      description: a.description ?? '',
      sexe: (a.sexe === 'femelle' ? 'femelle' : 'male') as 'male' | 'femelle',
    } : null);
    setShowBabyPicker(false);
  }

  // ── Baby photo handlers
  function handleBabyPhotoFiles(e: React.ChangeEvent<HTMLInputElement>) {
    if (!editingBaby) return;
    const files = Array.from(e.target.files ?? []);
    if (!files.length) return;
    const currentCount = babyPhotos[editingBaby.id]?.previews.length ?? 0;
    const available = 4 - currentCount;
    if (available <= 0) return;
    const toProcess = files.slice(0, available);
    setBabyCropTargetId(editingBaby.id);
    setBabyCropQueue(toProcess.slice(1));
    setBabyCropSrc(URL.createObjectURL(toProcess[0]));
    e.target.value = '';
  }
  function handleBabyCropConfirm(blob: Blob) {
    if (!babyCropTargetId) return;
    const url = URL.createObjectURL(blob);
    setBabyPhotos(prev => {
      const cur = prev[babyCropTargetId] ?? { blobs: [], previews: [] };
      return { ...prev, [babyCropTargetId]: { blobs: [...cur.blobs, blob], previews: [...cur.previews, url] } };
    });
    if (babyCropSrc) URL.revokeObjectURL(babyCropSrc);
    setBabyCropQueue(prev => {
      if (prev.length > 0) { setBabyCropSrc(URL.createObjectURL(prev[0])); return prev.slice(1); }
      setBabyCropSrc(null); return [];
    });
  }
  function removeBabyPhoto(babyId: string, index: number) {
    setBabyPhotos(prev => {
      const cur = prev[babyId]; if (!cur) return prev;
      const removedUrl = cur.previews[index];
      // Ne pas revoker les URLs https:// (déjà hébergées)
      if (removedUrl?.startsWith('blob:')) URL.revokeObjectURL(removedUrl);

      // Compter combien de previews avant ce point sont des URLs https (pré-chargées)
      const httpCount = cur.previews.slice(0, index).filter(p => !p.startsWith('blob:')).length;
      const blobIdx = index - httpCount;

      return {
        ...prev,
        [babyId]: {
          blobs: blobIdx >= 0 && blobIdx < cur.blobs.length
            ? cur.blobs.filter((_, i) => i !== blobIdx)
            : cur.blobs,
          previews: cur.previews.filter((_, i) => i !== index),
        },
      };
    });
    // Si c'est une URL existante (http), la retirer aussi de animauxPortee
    setAnimauxPortee(prev => prev.map(a => {
      if (a.id !== babyId) return a;
      const photos = ((a as any).photos as string[] | undefined) ?? [];
      const preview = (babyPhotos[babyId]?.previews ?? [])[index];
      if (preview && !preview.startsWith('blob:')) {
        return { ...a, photos: photos.filter((p: string) => p !== preview) };
      }
      return a;
    }));
  }

  // ── Main photos
  function handlePhotos(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []).slice(0, 5);
    if (!files.length) return;
    setCroppedBlobs([]); setPreviews([]);
    setCropQueue(files.slice(1));
    setCropSrc(URL.createObjectURL(files[0]));
    e.target.value = '';
  }
  function handleCropConfirm(blob: Blob) {
    const url = URL.createObjectURL(blob);
    setCroppedBlobs(prev => [...prev, blob]);
    setPreviews(prev => [...prev, url]);
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropQueue(prev => {
      if (prev.length > 0) { setCropSrc(URL.createObjectURL(prev[0])); return prev.slice(1); }
      setCropSrc(null); return [];
    });
  }
  function handleCropSkip() {
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropQueue(prev => {
      if (prev.length > 0) { setCropSrc(URL.createObjectURL(prev[0])); return prev.slice(1); }
      setCropSrc(null); return [];
    });
  }

  // ── Submit
  async function handleBuyExtra() {
    setQuotaBuying(true);
    try {
      const res = await fetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ uid: user!.uid, email: user!.email ?? '', produit_code: 'annonce_sup' }),
      });
      const json = await res.json() as { url?: string; error?: string };
      if (json.url) window.location.href = json.url;
      else setError(json.error ?? 'Erreur lors du paiement');
    } catch {
      setError('Erreur réseau');
    } finally {
      setQuotaBuying(false);
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setError(''); setSaving(true);
    try {
      // Seuls les éleveurs validés peuvent publier
      if (!userData?.isElevage || !userData.isValidate) {
        setError('Seuls les éleveurs certifiés et validés peuvent publier des annonces.');
        setSaving(false);
        return;
      }

      // ── Vérification quota plan ────────────────────────────────────────────
      const planCode = await getUserPlanClient(user!.uid);
      const planCfg  = PLAN_CONFIG[planCode] ?? PLAN_CONFIG.free;

      if (planCfg.maxAnnonces !== -1) {
        const { count: activeCount } = await supabase
          .from('annonces')
          .select('id', { count: 'exact', head: true })
          .eq('uid_eleveur', user!.uid)
          .in('statut', ['disponible', 'en_attente']);
        if ((activeCount ?? 0) >= planCfg.maxAnnonces) {
          setShowQuotaModal(true);
          setSaving(false);
          return;
        }
      }

      // ANTI02 : limite portées actives (plan-aware)
      if (type === 'portee') {
        const maxPortees = planCode === 'premium' ? -1 : planCode === 'pro' ? 5 : 2;
        if (maxPortees !== -1) {
          const { count } = await supabase
            .from('annonces')
            .select('id', { count: 'exact', head: true })
            .eq('uid_eleveur', user!.uid)
            .eq('type', 'portee')
            .neq('statut', 'archivée');
          if ((count ?? 0) >= maxPortees) {
            setError(`Limite atteinte : ${maxPortees} portée${maxPortees > 1 ? 's' : ''} active${maxPortees > 1 ? 's' : ''} maximum sur votre plan. Archivez une portée existante ou passez à Premium pour des portées illimitées.`);
            setSaving(false);
            return;
          }
        }
      }

      // ── Champs légaux obligatoires (Code rural français) ──────────────────
      if (croppedBlobs.length === 0) {
        setError('Au moins une photo est obligatoire pour publier une annonce.');
        setSaving(false); return;
      }
      if ((espece === 'Chien' || espece === 'Chat') && type === 'portee') {
        if (!merePuce.trim()) {
          setError('⚠ Obligatoire : numéro d\'identification (puce ICAD ou tatouage) de la mère — art. L214-8 Code rural.');
          setSaving(false); return;
        }
        if (!dateNaissance) {
          setError('⚠ Obligatoire : date de naissance de la portée.');
          setSaving(false); return;
        }
      }
      if (espece === 'Cheval' && !numSIRE.trim()) {
        setError('⚠ Obligatoire : numéro SIRE pour tout équidé mis en vente — Décret n°2013-879.');
        setSaving(false); return;
      }
      if ((espece === 'Chien' || espece === 'Chat') && type !== 'portee' && !numIdentification.trim()) {
        setError('⚠ Obligatoire : numéro d\'identification de l\'animal (puce électronique ou tatouage) — art. L212-10 Code rural.');
        setSaving(false); return;
      }

      const annonceStatut = planCfg.autoPublish ? 'disponible' : 'en_attente';
      const expireAt = new Date(Date.now() + planCfg.dureeDays * 86_400_000).toISOString();
      const photoUrls: string[] = [];
      for (const blob of croppedBlobs)
        photoUrls.push(await uploadBlob(blob, `annonces/${user!.uid}/${Date.now()}.jpg`));

      let merePhotoUrl: string | null = null;
      if (merePhotoBlob) merePhotoUrl = await uploadBlob(merePhotoBlob, `annonces/parents/${user!.uid}/${Date.now()}_mere.jpg`);
      else if (merePhotoPreview && !merePhotoPreview.startsWith('blob:')) merePhotoUrl = merePhotoPreview;

      let perePhotoUrl: string | null = null;
      if (perePhotoBlob) perePhotoUrl = await uploadBlob(perePhotoBlob, `annonces/parents/${user!.uid}/${Date.now()}_pere.jpg`);
      else if (perePhotoPreview && !perePhotoPreview.startsWith('blob:')) perePhotoUrl = perePhotoPreview;

      // Upload baby photos
      const animauxSaved: object[] = [];
      for (const baby of animauxPortee) {
        const photos = babyPhotos[baby.id];
        // Pour les animaux liés (isLinked), conserver leurs photos existantes
        const uploadedUrls: string[] = baby.isLinked ? [...(baby.photos ?? [])] : [];
        if (photos) {
          for (const blob of photos.blobs)
            uploadedUrls.push(await uploadBlob(blob, `annonces/animaux/${user!.uid}/${Date.now()}.jpg`));
        }
        const { id: _id, ...rest } = baby;
        animauxSaved.push({ ...rest, photos: uploadedUrls });
      }

      const nomEleveur = (userData?.nameElevage ?? `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim()) || '';
      const villeEleveur = userData?.villeElevage ?? userData?.ville ?? '';

      const { error: insertError } = await supabase.from('annonces').insert({
        id: genId(),
        uid_eleveur: user!.uid, nom_eleveur: nomEleveur, ville_eleveur: villeEleveur,
        titre: titre || `${espece} ${race}`.trim(),
        espece: ESPECE_DB[espece] ?? espece.toLowerCase(), race,
        type: type === 'portee' ? 'portee' : 'animal',
        type_vente: type === 'saillie' ? 'saillie' : type === 'retraite' ? 'retraite' : cession,
        photos: photoUrls, statut: annonceStatut, expire_at: expireAt, description,
        ...(type === 'compagnon' && { prix: prix ? Number(prix) : null, sexe: sexeAnimal, couleur: couleurAnimal || null, sterilise }),
        ...(type === 'retraite' && { prix: prix ? Number(prix) : null, sexe: sexeAnimal, couleur: couleurAnimal || null, etalon_animal_id: retraiteAnimalId }),
        ...(type === 'portee' && {
          date_naissance: dateNaissance || null,
          nombre_bebes: nombreBebes,
          prix_min_portee: prixMin ? Number(prixMin) : null,
          prix_max_portee: prixMax ? Number(prixMax) : null,
          animaux_portee: animauxSaved.length > 0 ? animauxSaved : null,
        }),
        ...(type === 'saillie' && { saillie_prix: sailliePrix ? parseFloat(sailliePrix) : null, saillie_conditions: saillieConditions || null }),
        vaccines, vermifuge, identification: identificationSante, bilan_sante: bilanSante,
        semaines: type !== 'saillie' ? semaines : null,
        club_pedigree: clubPedigree || null, numero_registre: numRegistre || null,
        ...(type !== 'saillie' && {
          mere_animal_id: mereAnimalId, mere_photo_url: merePhotoUrl,
          mere_nom: mereNom || null, mere_puce: merePuce || null, mere_identification: merePuce || null,
          mere_race: mereRace || null, mere_couleur: mereCouleur || null,
          mere_description: mereDescription || null, mere_registre: mereRegistre || null,
        }),
        pere_animal_id: pereAnimalId, pere_photo_url: perePhotoUrl,
        pere_nom: pereNom || null, pere_puce: perePuce || null, pere_identification: perePuce || null,
        pere_race: pereRace || null, pere_couleur: pereCouleur || null,
        pere_description: pereDescription || null, pere_registre: pereRegistre || null,
        // Champs légaux
        num_identification: (espece === 'Chien' || espece === 'Chat') && type !== 'portee' ? numIdentification || null : null,
        num_sire: espece === 'Cheval' ? numSIRE || null : null,
        num_passeport_equin: espece === 'Cheval' ? numPasseportEquin || null : null,
      });
      if (insertError) throw new Error(insertError.message);
      router.push(annonceStatut === 'en_attente' ? '/mes-annonces?pending=1' : '/mes-annonces');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setError(`Erreur : ${msg}`);
    } finally { setSaving(false); }
  }

  // ── Reusable animal picker list
  function AnimalPickerList({ animals, isLoading, onSelect }: {
    animals: MyAnimal[]; isLoading: boolean; onSelect: (a: MyAnimal) => void;
  }) {
    return (
      <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg max-h-52 overflow-y-auto">
        {isLoading ? (
          <p className="text-sm text-gray-400 text-center py-4">Chargement…</p>
        ) : animals.length === 0 ? (
          <p className="text-sm text-gray-400 text-center py-4">Aucun animal trouvé</p>
        ) : animals.map(a => (
          <button key={a.id} type="button" onClick={() => onSelect(a)}
            className="w-full flex items-center gap-3 px-3 py-2.5 hover:bg-[#E8F4F6] text-left border-b border-gray-50 last:border-0 transition-colors">
            <div className="w-10 h-10 rounded-lg overflow-hidden flex-shrink-0 bg-gray-100 flex items-center justify-center">
              {a.photo_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={thumbUrl(a.photo_url)} alt="" className="w-full h-full object-contain" />
              ) : (
                <span className="text-gray-300 text-lg">🐾</span>
              )}
            </div>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-gray-800 truncate">{a.nom || 'Sans nom'}</p>
              {a.race && <p className="text-xs text-gray-400 truncate">{a.race}</p>}
            </div>
          </button>
        ))}
      </div>
    );
  }

  // ── Parent photo box
  function ParentPhotoBox({ preview, onFileChange }: {
    preview: string | null; onFileChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
  }) {
    return (
      <label className="cursor-pointer flex-shrink-0 group">
        <div className={`w-16 h-16 rounded-xl overflow-hidden flex items-center justify-center relative ${preview ? 'border border-gray-200' : 'border-2 border-dashed border-gray-200 bg-gray-50'}`}>
          {preview ? (
            <>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={preview} alt="" className="w-full h-full object-contain bg-gray-50" />
              <div className="absolute inset-0 bg-black/30 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                <span className="text-white text-xs font-medium">Modifier</span>
              </div>
            </>
          ) : (
            <span className="text-2xl text-gray-300">📷</span>
          )}
        </div>
        <input type="file" accept="image/*" className="hidden" onChange={onFileChange} />
      </label>
    );
  }

  // ── Baby card in the portée list
  function BabyCard({ baby, index }: { baby: AnimalPortee; index: number }) {
    const photos = babyPhotos[baby.id];
    const firstPreview = photos?.previews[0];
    const statut = baby.statut;
    const statusColor = statut === 'disponible' ? 'text-[#6E9E57] bg-[#6E9E57]/10' : statut === 'reserve' ? 'text-amber-600 bg-amber-50' : 'text-gray-500 bg-gray-100';
    const statusLabel = statut === 'disponible' ? 'Dispo' : statut === 'reserve' ? 'Réservé' : 'Vendu';
    return (
      <div className="flex items-center gap-3 p-3 border border-gray-100 rounded-xl bg-gray-50/50">
        <div className="w-12 h-12 rounded-lg overflow-hidden flex-shrink-0 bg-gray-100 flex items-center justify-center">
          {firstPreview ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={firstPreview} alt="" className="w-full h-full object-cover" />
          ) : (
            <span className="text-gray-300 text-lg">🐾</span>
          )}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-gray-800 truncate">{baby.nom || `Bébé ${index + 1}`}</p>
          <p className="text-xs text-gray-400">{baby.sexe === 'male' ? '♂ Mâle' : '♀ Femelle'}{baby.couleur ? ` · ${baby.couleur}` : ''}</p>
        </div>
        <span className={`text-xs font-semibold px-2 py-1 rounded-lg ${statusColor}`}>{statusLabel}</span>
        <button type="button" onClick={() => openEditBaby(baby)}
          className="text-[#0C5C6C] hover:bg-[#E8F4F6] p-1.5 rounded-lg transition-colors text-sm">✏️</button>
        <button type="button" onClick={() => removeBaby(baby.id)}
          className="text-red-400 hover:text-red-600 p-1.5 rounded-lg transition-colors text-lg leading-none">×</button>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-10">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/mes-annonces" className="text-sm text-[#0C5C6C] hover:underline">← Mes annonces</Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-xl font-bold text-[#1F2A2E]">Nouvelle annonce</h1>
      </div>

      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
        <form onSubmit={handleSubmit} className="space-y-5">

          {/* ── Type de cession ── */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">Type de cession</label>
            <div className="flex gap-2">
              {([['vente', '💰 Vente'], ['adoption', '❤️ Adoption / Don']] as const).map(([v, l]) => (
                <button key={v} type="button" disabled={type === 'saillie'} onClick={() => setCession(v)}
                  className={`flex-1 py-2 rounded-xl text-sm font-medium border-2 transition-colors ${
                    cession === v && type !== 'saillie' ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-400'
                  } ${type === 'saillie' ? 'opacity-40 cursor-not-allowed' : 'cursor-pointer hover:border-gray-300'}`}>
                  {l}
                </button>
              ))}
            </div>
          </div>

          {/* ── Type d'annonce ── */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">Type d&apos;annonce</label>
            <div className="grid grid-cols-2 gap-2">
              {([['compagnon', '🐾 Animal individuel'], ['portee', '🐣 Portée complète'], ['saillie', '💜 Saillie'], ['retraite', '🏅 Retraité d\'élevage']] as [string, string][]).map(([v, l]) => (
                <button key={v} type="button" onClick={() => setType(v as typeof type)}
                  className={`py-2.5 rounded-xl text-sm font-medium border-2 transition-colors ${
                    type === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'
                  }`}>
                  {l}
                </button>
              ))}
            </div>
            {/* Saillie : picker étalon AVANT espèce pour auto-remplissage */}
            {type === 'saillie' && (
              <div className="mt-3 relative">
                <button type="button"
                  onClick={async () => { if (!showEtalonPicker) await loadAllMales(); setShowEtalonPicker(!showEtalonPicker); }}
                  className="w-full flex items-center gap-2 px-4 py-3 border-2 border-[#7C3AED] text-[#7C3AED] rounded-xl text-sm font-semibold hover:bg-purple-50 transition-colors">
                  <span>💜</span>
                  <span>{pereAnimalId ? `${pereNom || 'Étalon sélectionné'} — changer` : 'Sélectionner l\'étalon / reproducteur (espèce & race auto-remplies)'}</span>
                </button>
                {!pereAnimalId && <p className="text-xs text-gray-400 mt-1">L&apos;espèce, la race et le pedigree seront pré-remplis automatiquement.</p>}
                {pereAnimalId && <p className="text-xs text-green-600 mt-1">✓ Espèce, race et pedigree pré-remplis</p>}
                {showEtalonPicker && <AnimalPickerList animals={myAllMales} isLoading={loadingAllMales} onSelect={selectEtalon} />}
              </div>
            )}
            {/* Retraité : picker AVANT espèce pour auto-remplissage */}
            {type === 'retraite' && (
              <div className="mt-3 relative">
                <button type="button"
                  onClick={async () => { if (!showRetraitePicker) await loadAllAnimals(); setShowRetraitePicker(!showRetraitePicker); }}
                  className="w-full flex items-center gap-2 px-4 py-3 border-2 border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-semibold hover:bg-[#E8F4F6] transition-colors">
                  <span>🐾</span>
                  <span>{retraiteAnimalId ? `${retraiteAnimalNom} — changer` : 'Sélectionner l\'animal retraité (espèce & race auto-remplies)'}</span>
                </button>
                {!retraiteAnimalId && <p className="text-xs text-gray-400 mt-1">L&apos;espèce, la race et les infos seront pré-remplies automatiquement.</p>}
                {showRetraitePicker && <AnimalPickerList animals={myAnimalsAll} isLoading={loadingRetraite} onSelect={selectRetraite} />}
              </div>
            )}
          </div>

          {/* ── Titre ── */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Titre <span className="text-gray-400 font-normal">(optionnel)</span></label>
            <input value={titre} onChange={e => setTitre(e.target.value)}
              placeholder={type === 'portee' ? 'Ex: Portée Labrador disponible…' : type === 'saillie' ? 'Ex: Étalon Berger Australien disponible…' : 'Ex: Chiot Labrador disponible…'}
              className={iCls} />
          </div>

          {/* ── Espèce + Race ── */}
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Espèce</label>
              <select value={espece} onChange={e => setEspece(e.target.value)} className={iCls}>
                {ESPECES.map(e => <option key={e}>{e}</option>)}
              </select>
            </div>
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Race</label>
              <input value={race} onChange={e => setRace(e.target.value)} list="breed-list"
                placeholder={breeds.length ? 'Sélectionner ou saisir une race…' : 'Ex: Labrador…'} className={iCls} />
              <datalist id="breed-list">{breeds.map(b => <option key={b} value={b} />)}</datalist>
            </div>
          </div>

          {/* ── Identification légale équidé ── */}
          {espece === 'Cheval' && (
            <div className="border border-amber-200 bg-amber-50 rounded-xl p-4 space-y-3">
              <p className="text-sm font-semibold text-amber-800">🐴 Identification équidé <span className="text-red-500">*</span></p>
              <p className="text-xs text-amber-700">Obligatoire pour tout équidé (Décret n°2013-879)</p>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Numéro SIRE <span className="text-red-500">*</span></label>
                <input value={numSIRE} onChange={e => setNumSIRE(e.target.value)}
                  placeholder="Ex: 008FR12345678901 (15 chiffres)"
                  className={`${iCls} ${!numSIRE.trim() ? 'border-amber-300 focus:border-amber-500' : 'border-[#6E9E57]'}`} />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Numéro de passeport équin <span className="text-gray-400 font-normal">(optionnel)</span></label>
                <input value={numPasseportEquin} onChange={e => setNumPasseportEquin(e.target.value)}
                  placeholder="Ex: FR123456789" className={iCls} />
              </div>
            </div>
          )}

          {/* ── Compagnon / Retraité ── */}
          {(type === 'compagnon' || type === 'retraite') && (
            <>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Sexe</label>
                <div className="flex gap-2">
                  {([['male', '♂ Mâle'], ['femelle', '♀ Femelle']] as const).map(([v, l]) => (
                    <button key={v} type="button" onClick={() => setSexeAnimal(v)}
                      className={`flex-1 py-2 rounded-xl border-2 text-sm font-medium transition-colors ${sexeAnimal === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>{l}</button>
                  ))}
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Couleur / Robe <span className="text-gray-400 font-normal">(optionnel)</span></label>
                <input value={couleurAnimal} onChange={e => setCouleurAnimal(e.target.value)} placeholder="Ex: Fauve, Tricolore…" className={iCls} />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-700">Stérilisé(e)</span>
                <button type="button" onClick={() => setSterilise(!sterilise)}
                  className={`w-12 h-6 rounded-full transition-colors relative ${sterilise ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
                  <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform ${sterilise ? 'translate-x-6' : 'translate-x-0.5'}`} />
                </button>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Prix (€)</label>
                <input type="number" min="0" value={prix} onChange={e => setPrix(e.target.value)} placeholder="800" className={iCls} />
              </div>
              {(espece === 'Chien' || espece === 'Chat') && (
                <div className="border border-amber-200 bg-amber-50 rounded-xl p-3 space-y-2">
                  <p className="text-xs font-semibold text-amber-800">
                    🔖 Identification de l&apos;animal <span className="text-red-500">*</span>
                    <span className="font-normal ml-1">— obligatoire (art. L212-10 Code rural)</span>
                  </p>
                  <input value={numIdentification} onChange={e => setNumIdentification(e.target.value)}
                    placeholder="Numéro de puce électronique ou tatouage"
                    className={`${iCls} text-sm ${!numIdentification.trim() ? 'border-amber-300 focus:border-amber-500' : 'border-[#6E9E57]'}`} />
                </div>
              )}
            </>
          )}

          {/* ── Identification étalon (saillie, chien/chat) ── */}
          {type === 'saillie' && (espece === 'Chien' || espece === 'Chat') && (
            <div className="border border-amber-200 bg-amber-50 rounded-xl p-3 space-y-2">
              <p className="text-xs font-semibold text-amber-800">
                🔖 Identification de l&apos;étalon <span className="text-red-500">*</span>
                <span className="font-normal ml-1">— obligatoire (art. L212-10 Code rural)</span>
              </p>
              <input value={numIdentification} onChange={e => setNumIdentification(e.target.value)}
                placeholder="Numéro de puce électronique ou tatouage"
                className={`${iCls} text-sm ${!numIdentification.trim() ? 'border-amber-300 focus:border-amber-500' : 'border-[#6E9E57]'}`} />
            </div>
          )}

          {/* ── Portée ── */}
          {type === 'portee' && (
            <>
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Date de naissance
                    {(espece === 'Chien' || espece === 'Chat') ? <span className="text-red-500 ml-1">*</span> : <span className="text-gray-400 font-normal ml-1">(optionnel)</span>}
                  </label>
                  <input type="date" value={dateNaissance} onChange={e => setDateNaissance(e.target.value)} className={iCls} />
                </div>
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-2">Nombre de bébés</label>
                  <div className="flex items-center gap-3 mt-1">
                    <button type="button" onClick={() => setNombreBebes(n => Math.max(1, n - 1))}
                      className="w-9 h-9 rounded-full bg-[#E8F4F6] text-[#0C5C6C] text-xl font-bold flex items-center justify-center hover:bg-[#d0eaf0]">−</button>
                    <span className="text-xl font-bold text-[#1F2A2E] w-8 text-center">{nombreBebes}</span>
                    <button type="button" onClick={() => setNombreBebes(n => Math.min(20, n + 1))}
                      className="w-9 h-9 rounded-full bg-[#E8F4F6] text-[#0C5C6C] text-xl font-bold flex items-center justify-center hover:bg-[#d0eaf0]">+</button>
                  </div>
                </div>
              </div>
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-1">Prix min / bébé (€)</label>
                  <input type="number" min="0" value={prixMin} onChange={e => setPrixMin(e.target.value)} placeholder="500" className={iCls} />
                </div>
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-1">Prix max / bébé (€)</label>
                  <input type="number" min="0" value={prixMax} onChange={e => setPrixMax(e.target.value)} placeholder="1200" className={iCls} />
                </div>
              </div>

              {/* ── Animaux de la portée ── */}
              <div>
                <div className="flex items-center justify-between mb-3">
                  <div>
                    <span className="text-sm font-semibold text-gray-700">Animaux de la portée</span>
                    <span className="text-gray-400 font-normal text-sm ml-1">(optionnel)</span>
                  </div>
                  <button type="button" onClick={openAddBaby}
                    className="text-xs font-semibold text-white bg-[#0C5C6C] hover:bg-[#094F5D] px-3 py-1.5 rounded-full transition-colors">
                    + Ajouter un bébé
                  </button>
                </div>
                {animauxPortee.length === 0 && (
                  <p className="text-sm text-gray-400 text-center py-6 border-2 border-dashed border-gray-100 rounded-xl">
                    Détaillez chaque bébé individuellement avec ses photos
                  </p>
                )}
                <div className="space-y-2">
                  {animauxPortee.map((a, i) => <BabyCard key={a.id} baby={a} index={i} />)}
                </div>
              </div>
            </>
          )}

          {/* ── Saillie ── */}
          {type === 'saillie' && (
            <>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Prix de la saillie (€) <span className="text-gray-400 font-normal">(laisser vide si gratuit)</span></label>
                <input type="number" min="0" value={sailliePrix} onChange={e => setSailliePrix(e.target.value)} placeholder="0" className={iCls} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Conditions &amp; informations complémentaires</label>
                <textarea value={saillieConditions} onChange={e => setSaillieConditions(e.target.value)} rows={3}
                  placeholder="Ex: Droit au chiot, contrat de saillie, tests génétiques requis…" className={`${iCls} resize-none`} />
              </div>
            </>
          )}

          {/* ── Description ── */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={4}
              placeholder="Décrivez votre annonce…" className={`${iCls} resize-none`} />
          </div>

          {/* ── Santé & Conformité ── */}
          <div className={sCls}>
            <p className="text-sm font-semibold text-gray-700">🏥 Santé &amp; Conformité</p>
            {[
              ['Vacciné(e)', vaccines, setVaccines] as const,
              ['Vermifugé(e)', vermifuge, setVermifuge] as const,
              ['Pucé(e) / Tatoué(e)', identificationSante, setIdentificationSante] as const,
              ['Bilan de santé vétérinaire', bilanSante, setBilanSante] as const,
            ].map(([label, val, setter]) => (
              <div key={label} className="flex items-center justify-between py-1.5">
                <span className="text-sm text-gray-700">{label}</span>
                <button type="button" onClick={() => setter(!val)}
                  className={`w-11 h-6 rounded-full transition-colors relative flex-shrink-0 ${val ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
                  <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${val ? 'translate-x-5' : 'translate-x-0.5'}`} />
                </button>
              </div>
            ))}
            {type !== 'saillie' && (
              <div className="pt-1">
                <label className="block text-sm font-medium text-gray-700 mb-2">Âge minimum à la cession</label>
                <div className="flex items-center gap-4">
                  <button type="button" onClick={() => setSemaines(s => Math.max(4, s - 1))}
                    className="w-9 h-9 rounded-full bg-[#E8F4F6] text-[#0C5C6C] text-xl font-bold flex items-center justify-center hover:bg-[#d0eaf0]">−</button>
                  <span className="text-base font-bold text-[#1F2A2E] min-w-[90px] text-center">{semaines} semaines</span>
                  <button type="button" onClick={() => setSemaines(s => Math.min(52, s + 1))}
                    className="w-9 h-9 rounded-full bg-[#E8F4F6] text-[#0C5C6C] text-xl font-bold flex items-center justify-center hover:bg-[#d0eaf0]">+</button>
                  {semaines < 8 && <span className="text-xs text-amber-600 font-medium">⚠ min. légal : 8 sem.</span>}
                </div>
              </div>
            )}
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Club de race / Association pedigree <span className="text-gray-400 font-normal">(optionnel)</span></label>
              <input value={clubPedigree} onChange={e => setClubPedigree(e.target.value)}
                placeholder="Ex: SCC, Club du Berger Australien…" className={iSmCls} />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Numéro d&apos;inscription au registre <span className="text-gray-400 font-normal">(optionnel)</span></label>
              <input value={numRegistre} onChange={e => setNumRegistre(e.target.value)}
                placeholder="Ex: 12345/00, FR•012345•00…" className={iSmCls} />
            </div>
          </div>

          {/* ── Mère ── */}
          {type !== 'saillie' && type !== 'retraite' && (
            <div className={sCls}>
              <div className="flex items-center justify-between">
                <p className="text-sm font-semibold text-gray-700">
                ♀ Mère
                {(espece === 'Chien' || espece === 'Chat') && type === 'portee'
                  ? <span className="text-red-500 ml-1">*</span>
                  : <span className="text-gray-400 font-normal ml-1">(optionnel)</span>}
              </p>
                {mereAnimalId && <button type="button" onClick={clearMere} className="text-xs text-red-400 hover:text-red-600 font-medium">Effacer</button>}
              </div>
              <div className="flex items-start gap-3">
                <ParentPhotoBox preview={merePhotoPreview} onFileChange={handleMerePhotoFile} />
                <div className="flex-1 relative">
                  <button type="button"
                    onClick={async () => { if (!showMerePicker) await loadFemelles(); setShowMerePicker(!showMerePicker); setShowPerePicker(false); }}
                    className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                    <span>🔍</span>
                    <span>{mereAnimalId ? 'Changer d\'animal' : 'Chercher parmi mes animaux'}</span>
                  </button>
                  {showMerePicker && <AnimalPickerList animals={myFemelles} isLoading={loadingFemelles} onSelect={selectMere} />}
                </div>
              </div>
              <div className="flex gap-3">
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Nom</label>
                  <input value={mereNom} onChange={e => setMereNom(e.target.value)} placeholder="Nom de la mère" className={iSmCls} /></div>
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Race</label>
                  <input value={mereRace} onChange={e => setMereRace(e.target.value)} list="mere-breed-list" placeholder="Race" className={iSmCls} />
                  <datalist id="mere-breed-list">{breeds.map(b => <option key={b} value={b} />)}</datalist></div>
              </div>
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="block text-xs font-medium text-gray-600 mb-1">
                    Identification (puce / tatouage)
                    {(espece === 'Chien' || espece === 'Chat') && type === 'portee' && <span className="text-red-500 ml-1">*</span>}
                  </label>
                  <input value={merePuce} onChange={e => setMerePuce(e.target.value)} placeholder="Numéro de puce ICAD ou tatouage"
                    className={`${iSmCls} ${(espece === 'Chien' || espece === 'Chat') && type === 'portee' && !merePuce.trim() ? 'border-amber-300' : ''}`} />
                  {(espece === 'Chien' || espece === 'Chat') && type === 'portee' && (
                    <p className="text-xs text-amber-700 mt-1">Obligatoire (art. L214-8 Code rural)</p>
                  )}
                </div>
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Couleur / Robe</label>
                  <input value={mereCouleur} onChange={e => setMereCouleur(e.target.value)} placeholder="Ex: Fauve…" className={iSmCls} /></div>
              </div>
              <div><label className="block text-xs font-medium text-gray-600 mb-1">Registre</label>
                <input value={mereRegistre} onChange={e => setMereRegistre(e.target.value)} placeholder="LOF, LOOF, Non inscrite…" className={iSmCls} /></div>
              <div><label className="block text-xs font-medium text-gray-600 mb-1">Description</label>
                <textarea value={mereDescription} onChange={e => setMereDescription(e.target.value)} rows={2}
                  placeholder="Caractère, morphologie…" className={`${iSmCls} resize-none`} /></div>
            </div>
          )}

          {/* ── Père / Étalon — masqué pour retraité ── */}
          {type !== 'retraite' && <div className={sCls}>
            <div className="flex items-center justify-between">
              <p className="text-sm font-semibold text-gray-700">
                ♂ {type === 'saillie' ? 'Étalon / Reproducteur' : 'Père'} <span className="text-gray-400 font-normal">(optionnel)</span>
              </p>
              {pereAnimalId && <button type="button" onClick={clearPere} className="text-xs text-red-400 hover:text-red-600 font-medium">Effacer</button>}
            </div>
            <div className="flex items-start gap-3">
              <ParentPhotoBox preview={perePhotoPreview} onFileChange={handlePerePhotoFile} />
              <div className="flex-1 relative">
                <button type="button"
                  onClick={async () => { if (!showPerePicker) await loadMales(); setShowPerePicker(!showPerePicker); setShowMerePicker(false); }}
                  className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                  <span>🔍</span>
                  <span>{pereAnimalId ? 'Changer d\'animal' : 'Chercher parmi mes animaux'}</span>
                </button>
                {showPerePicker && <AnimalPickerList animals={myMales} isLoading={loadingMales} onSelect={selectPere} />}
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Nom</label>
                <input value={pereNom} onChange={e => setPereNom(e.target.value)}
                  placeholder={type === 'saillie' ? "Nom de l'étalon" : 'Nom du père'} className={iSmCls} /></div>
              <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Race</label>
                <input value={pereRace} onChange={e => setPereRace(e.target.value)} list="pere-breed-list" placeholder="Race" className={iSmCls} />
                <datalist id="pere-breed-list">{breeds.map(b => <option key={b} value={b} />)}</datalist></div>
            </div>
            <div className="flex gap-3">
              <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Identification (puce / tatouage)</label>
                <input value={perePuce} onChange={e => setPerePuce(e.target.value)} placeholder="Numéro de puce" className={iSmCls} /></div>
              <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Couleur / Robe</label>
                <input value={pereCouleur} onChange={e => setPereCouleur(e.target.value)} placeholder="Ex: Fauve…" className={iSmCls} /></div>
            </div>
            <div><label className="block text-xs font-medium text-gray-600 mb-1">Registre</label>
              <input value={pereRegistre} onChange={e => setPereRegistre(e.target.value)} placeholder="LOF, LOOF, Non inscrit…" className={iSmCls} /></div>
            <div><label className="block text-xs font-medium text-gray-600 mb-1">Description</label>
              <textarea value={pereDescription} onChange={e => setPereDescription(e.target.value)} rows={2}
                placeholder="Caractère, morphologie…" className={`${iSmCls} resize-none`} /></div>
          </div>}

          {/* ── Photos annonce ── */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Photos <span className="text-gray-400 font-normal">(max 5)</span></label>
            <label className="flex items-center justify-center gap-2 w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-6 cursor-pointer transition-colors text-gray-400 hover:text-[#0C5C6C]">
              <span className="text-2xl">📷</span>
              <span className="text-sm font-medium">Choisir des photos</span>
              <input type="file" accept="image/*" multiple onChange={handlePhotos} className="hidden" />
            </label>
            {previews.length > 0 && (
              <div className="flex gap-2 mt-3 flex-wrap">
                {previews.map((p, i) => (
                  <div key={i} className="w-16 h-16 rounded-xl overflow-hidden border border-gray-200 flex-shrink-0">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={p} alt="" className="w-full h-full object-cover" />
                  </div>
                ))}
              </div>
            )}
          </div>

          {error && <p className="text-red-500 text-sm">{error}</p>}

          <button type="submit" disabled={saving}
            className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors">
            {saving ? 'Publication en cours…' : "Publier l'annonce"}
          </button>
        </form>
      </div>

      {/* ── Baby edit modal ── */}
      {editingBaby && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 overflow-y-auto py-6 px-4"
          onClick={e => { if (e.target === e.currentTarget) { setEditingBaby(null); setShowBabyPicker(false); } }}>
          <div className="bg-white rounded-2xl w-full max-w-lg shadow-xl">
            {/* Header */}
            <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
              <h2 className="font-bold text-[#1F2A2E]">
                {animauxPortee.find(a => a.id === editingBaby.id) ? 'Modifier le bébé' : 'Ajouter un bébé'}
              </h2>
              <div className="flex items-center gap-3">
                <button type="button" onClick={() => { setEditingBaby(null); setShowBabyPicker(false); }}
                  className="text-sm text-gray-400 hover:text-gray-600">Annuler</button>
                <button type="button" onClick={saveBaby}
                  className="bg-[#0C5C6C] text-white px-4 py-1.5 rounded-xl text-sm font-semibold hover:bg-[#094F5D]">
                  Enregistrer
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4">
              {/* Photos */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Photos (max. 4)</p>
                <div className="flex gap-2 flex-wrap">
                  {(babyPhotos[editingBaby.id]?.previews ?? []).map((p, i) => (
                    <div key={i} className="relative w-20 h-20">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={p} alt="" className="w-full h-full object-cover rounded-xl border border-gray-200" />
                      <button type="button" onClick={() => removeBabyPhoto(editingBaby.id, i)}
                        className="absolute -top-1.5 -right-1.5 w-5 h-5 bg-black/60 rounded-full flex items-center justify-center text-white text-xs">×</button>
                    </div>
                  ))}
                  {(babyPhotos[editingBaby.id]?.previews.length ?? 0) < 4 && (
                    <label className="cursor-pointer w-20 h-20 border-2 border-dashed border-gray-200 rounded-xl flex flex-col items-center justify-center gap-1 hover:border-[#0C5C6C] hover:text-[#0C5C6C] text-gray-300 transition-colors">
                      <span className="text-2xl">📷</span>
                      <span className="text-xs font-medium">Ajouter</span>
                      <input type="file" accept="image/*" multiple className="hidden" onChange={handleBabyPhotoFiles} />
                    </label>
                  )}
                </div>
              </div>

              {/* Récupérer infos d'un animal */}
              <div className="relative">
                <button type="button"
                  onClick={async () => { if (!showBabyPicker) await loadBabyPickerAnimals(); setShowBabyPicker(!showBabyPicker); }}
                  className="w-full flex items-center gap-2 px-3 py-2.5 border border-[#6E9E57] text-[#6E9E57] rounded-xl text-sm font-medium hover:bg-[#6E9E57]/10 transition-colors">
                  <span>🔍</span>
                  <span>Récupérer les infos d&apos;un de mes animaux</span>
                  <span className="ml-auto text-xs text-gray-400 font-normal">(sans photo)</span>
                </button>
                {showBabyPicker && (
                  <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg max-h-52 overflow-y-auto">
                    {loadingBabyPicker ? (
                      <p className="text-sm text-gray-400 text-center py-4">Chargement…</p>
                    ) : babyPickerAnimals.length === 0 ? (
                      <p className="text-sm text-gray-400 text-center py-4">Aucun animal trouvé</p>
                    ) : babyPickerAnimals.map(a => (
                      <button key={a.id} type="button" onClick={() => selectBabyAnimal(a)}
                        className="w-full flex items-center gap-3 px-3 py-2.5 hover:bg-[#E8F4F6] text-left border-b border-gray-50 last:border-0 transition-colors">
                        <div className="w-10 h-10 rounded-lg overflow-hidden flex-shrink-0 bg-gray-100 flex items-center justify-center">
                          {a.photo_url ? (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img src={thumbUrl(a.photo_url)} alt="" className="w-full h-full object-contain" />
                          ) : (
                            <span className="text-gray-300 text-sm">🐾</span>
                          )}
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-gray-800 truncate">{a.nom || 'Sans nom'}</p>
                          <p className="text-xs text-gray-400">{a.sexe === 'femelle' ? '♀' : '♂'}{a.race ? ` · ${a.race}` : ''}</p>
                        </div>
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Nom */}
              <div><label className="block text-sm font-medium text-gray-700 mb-1">Nom <span className="text-gray-400 font-normal">(optionnel)</span></label>
                <input value={editingBaby.nom}
                  onChange={e => setEditingBaby(p => p ? { ...p, nom: e.target.value } : null)}
                  placeholder="Nom du bébé" className={iCls} /></div>

              {/* Sexe */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Sexe</label>
                <div className="flex gap-2">
                  {(['male', 'femelle'] as const).map(s => (
                    <button key={s} type="button" onClick={() => setEditingBaby(p => p ? { ...p, sexe: s } : null)}
                      className={`flex-1 py-2 rounded-xl border-2 text-sm font-medium transition-colors ${editingBaby.sexe === s ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>
                      {s === 'male' ? '♂ Mâle' : '♀ Femelle'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Couleur + Prix */}
              <div className="flex gap-3">
                <div className="flex-1"><label className="block text-sm font-medium text-gray-700 mb-1">Couleur / Robe</label>
                  <input value={editingBaby.couleur}
                    onChange={e => setEditingBaby(p => p ? { ...p, couleur: e.target.value } : null)}
                    placeholder="Ex: Tricolore…" className={iCls} /></div>
                <div className="flex-1"><label className="block text-sm font-medium text-gray-700 mb-1">Prix (€)</label>
                  <input type="number" min="0" value={editingBaby.prix}
                    onChange={e => setEditingBaby(p => p ? { ...p, prix: e.target.value } : null)}
                    placeholder="800" className={iCls} /></div>
              </div>

              {/* Description */}
              <div><label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
                <textarea value={editingBaby.description}
                  onChange={e => setEditingBaby(p => p ? { ...p, description: e.target.value } : null)}
                  rows={3} placeholder="Caractère, particularités…" className={`${iCls} resize-none`} /></div>

              {/* Statut */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Disponibilité</label>
                <div className="flex gap-2">
                  {([['disponible', 'Disponible', '#6E9E57'], ['reserve', 'Réservé', '#F59E0B'], ['vendu', 'Vendu', '#9CA3AF']] as const).map(([s, l, c]) => (
                    <button key={s} type="button" onClick={() => setEditingBaby(p => p ? { ...p, statut: s } : null)}
                      className={`flex-1 py-2 rounded-xl border-2 text-xs font-semibold transition-colors`}
                      style={editingBaby.statut === s
                        ? { borderColor: c, backgroundColor: c + '20', color: c }
                        : { borderColor: '#E5E7EB', color: '#6B7280' }}>
                      {l}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Crop modals ── */}
      {cropSrc && (
        <ImageCropModal src={cropSrc} aspect={1}
          title={`Photo ${previews.length + 1} / ${previews.length + 1 + cropQueue.length}`}
          onConfirm={handleCropConfirm} onCancel={handleCropSkip} />
      )}
      {mereCropSrc && (
        <ImageCropModal src={mereCropSrc} aspect={1} title="Photo de la mère"
          onConfirm={handleMereCropConfirm}
          onCancel={() => { if (mereCropSrc) URL.revokeObjectURL(mereCropSrc); setMereCropSrc(null); }} />
      )}
      {pereCropSrc && (
        <ImageCropModal src={pereCropSrc} aspect={1} title="Photo du père"
          onConfirm={handlePereCropConfirm}
          onCancel={() => { if (pereCropSrc) URL.revokeObjectURL(pereCropSrc); setPereCropSrc(null); }} />
      )}
      {babyCropSrc && (
        <ImageCropModal src={babyCropSrc} aspect={1} title="Photo du bébé"
          onConfirm={handleBabyCropConfirm}
          onCancel={() => { if (babyCropSrc) URL.revokeObjectURL(babyCropSrc); setBabyCropSrc(null); setBabyCropQueue([]); }} />
      )}

      {/* ── Quota modal ── */}
      {showQuotaModal && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 px-4"
          onClick={e => { if (e.target === e.currentTarget) setShowQuotaModal(false); }}>
          <div className="bg-white rounded-2xl p-6 max-w-sm w-full shadow-xl">
            <div className="text-center mb-5">
              <span className="text-4xl">🚫</span>
              <h2 className="mt-3 font-bold text-[#1F2A2E] text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>
                Quota atteint
              </h2>
              <p className="text-sm text-gray-500 mt-1">
                Vous avez atteint la limite d'annonces de votre plan actuel. Choisissez comment continuer :
              </p>
            </div>
            <div className="space-y-3">
              <button
                onClick={handleBuyExtra}
                disabled={quotaBuying}
                className="w-full bg-[#6E9E57] hover:bg-[#5A8A45] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors text-sm flex items-center justify-center gap-2">
                {quotaBuying ? '…' : '➕ Annonce supplémentaire — 2,99 €'}
              </button>
              <button
                onClick={() => { setShowQuotaModal(false); router.push('/abonnement'); }}
                className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-3 rounded-xl transition-colors text-sm">
                ⚡ Passer au plan Pro
              </button>
              <button
                onClick={() => setShowQuotaModal(false)}
                className="w-full text-gray-400 text-sm py-2 hover:text-gray-600 transition-colors">
                Annuler
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function CreerAnnoncePage() {
  return (
    <Suspense fallback={<div className="min-h-screen flex items-center justify-center"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>}>
      <CreerAnnoncePageInner />
    </Suspense>
  );
}
