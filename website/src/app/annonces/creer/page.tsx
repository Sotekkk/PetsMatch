'use client';

import { useState, useEffect, useCallback, useRef, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { apiFetch } from '@/lib/api-fetch';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { uploadBlob, uploadRawFile } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';

const PLAN_CONFIG: Record<string, { maxAnnonces: number; dureeDays: number; autoPublish: boolean }> = {
  free:    { maxAnnonces: 0, dureeDays: 30, autoPublish: false },
  pro:     { maxAnnonces: 1, dureeDays: 45, autoPublish: true  },
  premium: { maxAnnonces: 3, dureeDays: 60, autoPublish: true  },
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
  couleur_yeux: string;
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
  couleur_yeux: string | null;
  description: string | null;
  identification: string | null;
  photo_url: string | null;
  pedigree_lof?: string | null;
  club_registre?: string | null;
}

/** Reproducteur proposé publiquement par un autre éleveur (annonce de saillie active). */
interface ReseauEtalon {
  id: string; titre: string | null; race: string | null; nom_eleveur: string | null;
  pere_nom: string | null; pere_puce: string | null; pere_race: string | null; pere_couleur: string | null;
  pere_couleur_yeux: string | null; pere_registre: string | null; pere_photo_url: string | null;
  photos: string[] | null; etalon_animal_id: string | null;
}

const DB_TO_ESPECE: Record<string, string> = {
  'chien': 'Chien', 'chat': 'Chat', 'lapin': 'Lapin', 'oiseau': 'Oiseau',
  'cheval': 'Cheval', 'nac': 'Reptile', 'autre': 'Autre',
};

function CreerAnnoncePageInner() {
  const { user, userData, loading, activeProfileId } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();

  // ── Type
  const [type, setType] = useState<'compagnon' | 'portee' | 'saillie' | 'retraite'>('compagnon');
  const [cession, setCession] = useState<'vente' | 'adoption' | 'don'>('vente');
  // Brouillon : annonce enregistrée (statut « brouillon ») reprise via ?brouillon=<id>
  const [brouillonId, setBrouillonId] = useState<string | null>(null);
  const [photosExistantes, setPhotosExistantes] = useState<string[]>([]);
  const [planCode, setPlanCode] = useState<string>('free');
  const [autoSaveA, setAutoSaveA] = useState<string | null>(null);
  const [brouillonLocal, setBrouillonLocal] = useState<{ savedAt: string; data: Record<string, unknown> } | null>(null);
  const raceRestauree = useRef<string | null>(null);
  // Père : source (mes animaux / réseau PetsMatch / saisie manuelle)
  const [pereSource, setPereSource] = useState<'mien' | 'reseau' | 'manuel'>('mien');
  const [pereEleveurReseau, setPereEleveurReseau] = useState<string | null>(null);
  const [reseauQuery, setReseauQuery] = useState('');
  const [reseauResults, setReseauResults] = useState<ReseauEtalon[]>([]);
  const [loadingReseau, setLoadingReseau] = useState(false);

  // ── Infos communes
  const [titre, setTitre] = useState('');
  const [espece, setEspece] = useState('Chien');
  const [especeAutre, setEspeceAutre] = useState('');
  const [race, setRace] = useState('');
  const [breeds, setBreeds] = useState<string[]>([]);
  const [description, setDescription] = useState('');

  // ── Photos annonce
  const [croppedBlobs, setCroppedBlobs] = useState<Blob[]>([]);
  const [etape, setEtape] = useState(1);
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
  const [couleurYeuxAnimal, setCouleurYeuxAnimal] = useState('');
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
  const [saillieGenetique, setSaillieGenetique] = useState('');

  // ── Identification légale (champs obligatoires selon Code rural)
  const [numSIRE, setNumSIRE] = useState('');
  const [numPasseportEquin, setNumPasseportEquin] = useState('');
  const [numIdentification, setNumIdentification] = useState('');

  // ── Cheval : formule (type_vente équin) + prix cadencé + sport
  const [formuleEquine, setFormuleEquine] = useState<'vente' | 'location' | 'demi_pension' | 'pension_complete' | 'valorisation'>('vente');
  const [prixUnite, setPrixUnite] = useState<'total' | 'mois' | 'semaine' | 'convenir'>('total');
  const [niveauEquide, setNiveauEquide] = useState('');
  const [palmares, setPalmares] = useState('');
  const [indiceIso, setIndiceIso] = useState('');
  const [indiceIdr, setIndiceIdr] = useState('');
  const [indiceIcc, setIndiceIcc] = useState('');
  const [videoMonteUrl, setVideoMonteUrl] = useState<string | null>(null);
  const [videoLibreUrl, setVideoLibreUrl] = useState<string | null>(null);
  const [uploadingVideo, setUploadingVideo] = useState<'monte' | 'libre' | null>(null);

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
  const [mereCouleurYeux, setMereCouleurYeux] = useState('');
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
  const [pereCouleurYeux, setPereCouleurYeux] = useState('');
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
    if (raceRestauree.current !== null) { setRace(raceRestauree.current); raceRestauree.current = null; }
    else setRace('');
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
        .select('id, nom, sexe, espece, race, couleur, couleur_yeux, identification, date_naissance, photo_url, nom_pere, puce_pere, nom_mere, puce_mere, race_mere, pedigree_lof')
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
        couleur_yeux: (m.couleur_yeux as string) ?? '',
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
          .select('id, nom, sexe, race, couleur, couleur_yeux, identification, photo_url, pedigree_lof')
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
          setPereCouleurYeux((pere.couleur_yeux as string) ?? '');
          setPereRegistre((pere.pedigree_lof as string) ?? '');
          if (pere.photo_url) setPerePhotoPreview(pere.photo_url as string);
        } else {
          setPereNom(nomPere);
          setPerePuce(pucePere);
        }
      }

      if (nomMere || puceMere) {
        const { data: mereRows } = await supabase.from('animaux')
          .select('id, nom, sexe, race, couleur, couleur_yeux, identification, photo_url, pedigree_lof')
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
          setMereCouleurYeux((mere.couleur_yeux as string) ?? '');
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

  // ── Durée de publication (selon l'abonnement)
  useEffect(() => {
    if (!user) return;
    getUserPlanClient(user.uid).then(c => setPlanCode(c));
  }, [user]);

  // ── Champs sérialisables (brouillon local + restauration)
  const champsBrouillon = {
    type, cession, titre, espece, especeAutre, race, description,
    sexeAnimal, couleurAnimal, couleurYeuxAnimal, sterilise, prix,
    dateNaissance, nombreBebes, prixMin, prixMax, animauxPortee,
    vaccines, vermifuge, identificationSante, bilanSante, semaines, clubPedigree, numRegistre,
    sailliePrix, saillieConditions, saillieGenetique,
    numSIRE, numPasseportEquin, numIdentification,
    formuleEquine, prixUnite, niveauEquide, palmares, indiceIso, indiceIdr, indiceIcc, videoMonteUrl, videoLibreUrl,
    retraiteAnimalId, retraiteAnimalNom,
    mereAnimalId, mereNom, merePuce, mereRace, mereCouleur, mereCouleurYeux, mereDescription, mereRegistre, merePhotoPreview: merePhotoPreview?.startsWith('blob:') ? null : merePhotoPreview,
    pereAnimalId, pereNom, perePuce, pereRace, pereCouleur, pereCouleurYeux, pereDescription, pereRegistre, perePhotoPreview: perePhotoPreview?.startsWith('blob:') ? null : perePhotoPreview,
    pereSource, pereEleveurReseau, photosExistantes, etape,
  };
  const cleBrouillon = user ? `pm_annonce_brouillon_${user.uid}` : null;

  function restaurer(d: Record<string, unknown>) {
    const g = <T,>(k: string, def: T): T => (d[k] === undefined || d[k] === null ? def : d[k] as T);
    const esp = g('espece', 'Chien');
    if (esp !== espece) raceRestauree.current = g('race', ''); else setRace(g('race', ''));
    setEspece(esp);
    setType(g('type', 'compagnon')); setCession(g('cession', 'vente')); setTitre(g('titre', ''));
    setEspeceAutre(g('especeAutre', '')); setDescription(g('description', ''));
    setSexeAnimal(g('sexeAnimal', 'male')); setCouleurAnimal(g('couleurAnimal', '')); setCouleurYeuxAnimal(g('couleurYeuxAnimal', ''));
    setSterilise(g('sterilise', false)); setPrix(g('prix', ''));
    setDateNaissance(g('dateNaissance', '')); setNombreBebes(g('nombreBebes', 1)); setPrixMin(g('prixMin', '')); setPrixMax(g('prixMax', ''));
    const bebes = g<AnimalPortee[]>('animauxPortee', []);
    setAnimauxPortee(bebes);
    const bp: Record<string, { blobs: Blob[]; previews: string[] }> = {};
    bebes.forEach(bb => { if (bb.photos?.length) bp[bb.id] = { blobs: [], previews: [...bb.photos] }; });
    setBabyPhotos(bp);
    setVaccines(g('vaccines', false)); setVermifuge(g('vermifuge', false)); setIdentificationSante(g('identificationSante', false));
    setBilanSante(g('bilanSante', false)); setSemaines(g('semaines', 8)); setClubPedigree(g('clubPedigree', '')); setNumRegistre(g('numRegistre', ''));
    setSailliePrix(g('sailliePrix', '')); setSaillieConditions(g('saillieConditions', '')); setSaillieGenetique(g('saillieGenetique', ''));
    setNumSIRE(g('numSIRE', '')); setNumPasseportEquin(g('numPasseportEquin', '')); setNumIdentification(g('numIdentification', ''));
    setFormuleEquine(g('formuleEquine', 'vente')); setPrixUnite(g('prixUnite', 'total')); setNiveauEquide(g('niveauEquide', ''));
    setPalmares(g('palmares', '')); setIndiceIso(g('indiceIso', '')); setIndiceIdr(g('indiceIdr', '')); setIndiceIcc(g('indiceIcc', ''));
    setVideoMonteUrl(g('videoMonteUrl', null)); setVideoLibreUrl(g('videoLibreUrl', null));
    setRetraiteAnimalId(g('retraiteAnimalId', null)); setRetraiteAnimalNom(g('retraiteAnimalNom', null));
    setMereAnimalId(g('mereAnimalId', null)); setMereNom(g('mereNom', '')); setMerePuce(g('merePuce', '')); setMereRace(g('mereRace', ''));
    setMereCouleur(g('mereCouleur', '')); setMereCouleurYeux(g('mereCouleurYeux', '')); setMereDescription(g('mereDescription', ''));
    setMereRegistre(g('mereRegistre', '')); setMerePhotoPreview(g('merePhotoPreview', null));
    setPereAnimalId(g('pereAnimalId', null)); setPereNom(g('pereNom', '')); setPerePuce(g('perePuce', '')); setPereRace(g('pereRace', ''));
    setPereCouleur(g('pereCouleur', '')); setPereCouleurYeux(g('pereCouleurYeux', '')); setPereDescription(g('pereDescription', ''));
    setPereRegistre(g('pereRegistre', '')); setPerePhotoPreview(g('perePhotoPreview', null));
    setPereSource(g('pereSource', 'mien')); setPereEleveurReseau(g('pereEleveurReseau', null));
    setPhotosExistantes(g('photosExistantes', []));
    setEtape(g('etape', 1));
  }

  // ── Reprise d'un brouillon enregistré (?brouillon=<id>)
  useEffect(() => {
    const id = searchParams.get('brouillon');
    if (!id || !user) return;
    (async () => {
      const { data: a } = await supabase.from('annonces').select('*').eq('id', id).maybeSingle();
      if (!a || a.statut !== 'brouillon') return;
      const tv = (a.type_vente as string) ?? 'vente';
      const equin = ['location', 'demi_pension', 'pension_complete', 'valorisation'].includes(tv);
      const bebes = ((a.animaux_portee as Record<string, unknown>[] | null) ?? []).map(bb => ({ ...bb, id: genId() })) as unknown as AnimalPortee[];
      restaurer({
        type: a.type === 'portee' ? 'portee' : tv === 'saillie' ? 'saillie' : tv === 'retraite' ? 'retraite' : 'compagnon',
        cession: ['vente', 'adoption', 'don'].includes(tv) ? tv : 'vente',
        titre: a.titre, espece: DB_TO_ESPECE[a.espece as string] ?? 'Chien', especeAutre: a.espece_autre, race: a.race, description: a.description,
        sexeAnimal: a.sexe, couleurAnimal: a.couleur, couleurYeuxAnimal: a.couleur_yeux, sterilise: a.sterilise,
        prix: a.prix != null ? String(a.prix) : '',
        dateNaissance: a.date_naissance ? String(a.date_naissance).substring(0, 10) : '', nombreBebes: a.nombre_bebes ?? 1,
        prixMin: a.prix_min_portee != null ? String(a.prix_min_portee) : '', prixMax: a.prix_max_portee != null ? String(a.prix_max_portee) : '',
        animauxPortee: bebes,
        vaccines: a.vaccines, vermifuge: a.vermifuge, identificationSante: a.identification, bilanSante: a.bilan_sante,
        semaines: a.semaines ?? 8, clubPedigree: a.club_pedigree, numRegistre: a.numero_registre,
        sailliePrix: a.saillie_prix != null ? String(a.saillie_prix) : '', saillieConditions: a.saillie_conditions, saillieGenetique: a.saillie_genetique,
        numSIRE: a.num_sire, numPasseportEquin: a.num_passeport_equin, numIdentification: a.num_identification,
        formuleEquine: equin ? tv : 'vente', prixUnite: a.prix_unite ?? 'total', niveauEquide: a.niveau_recommande, palmares: a.palmares,
        indiceIso: a.indice_iso != null ? String(a.indice_iso) : '', indiceIdr: a.indice_idr != null ? String(a.indice_idr) : '', indiceIcc: a.indice_icc != null ? String(a.indice_icc) : '',
        videoMonteUrl: a.video_monte_url, videoLibreUrl: a.video_libre_url,
        retraiteAnimalId: tv === 'retraite' ? a.etalon_animal_id : null,
        mereAnimalId: a.mere_animal_id, mereNom: a.mere_nom, merePuce: a.mere_puce, mereRace: a.mere_race, mereCouleur: a.mere_couleur,
        mereCouleurYeux: a.mere_couleur_yeux, mereDescription: a.mere_description, mereRegistre: a.mere_registre, merePhotoPreview: a.mere_photo_url,
        pereAnimalId: a.pere_animal_id ?? (tv === 'saillie' ? a.etalon_animal_id : null), pereNom: a.pere_nom, perePuce: a.pere_puce, pereRace: a.pere_race,
        pereCouleur: a.pere_couleur, pereCouleurYeux: a.pere_couleur_yeux, pereDescription: a.pere_description, pereRegistre: a.pere_registre,
        perePhotoPreview: a.pere_photo_url, pereSource: 'mien',
        photosExistantes: (a.photos as string[] | null) ?? [], etape: 1,
      });
      setBrouillonId(id);
    })();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams, user]);

  // ── Brouillon local non terminé : proposé à la reprise
  useEffect(() => {
    if (!cleBrouillon || searchParams.get('brouillon') || searchParams.get('portee_id')) return;
    try {
      const raw = localStorage.getItem(cleBrouillon);
      if (raw) setBrouillonLocal(JSON.parse(raw));
    } catch { /* stockage indisponible */ }
  }, [cleBrouillon, searchParams]);

  // ── Sauvegarde automatique pendant la saisie (sur cet appareil)
  const champsJson = JSON.stringify(champsBrouillon);
  const premiereSaisie = useRef(true);
  useEffect(() => {
    if (!cleBrouillon || brouillonLocal) return;
    if (premiereSaisie.current) { premiereSaisie.current = false; return; }
    const t = setTimeout(() => {
      try {
        const savedAt = new Date().toISOString();
        localStorage.setItem(cleBrouillon, JSON.stringify({ savedAt, data: JSON.parse(champsJson) }));
        setAutoSaveA(new Date(savedAt).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }));
      } catch { /* stockage indisponible */ }
    }, 1200);
    return () => clearTimeout(t);
  }, [champsJson, cleBrouillon, brouillonLocal]);

  function oublierBrouillonLocal() {
    try { if (cleBrouillon) localStorage.removeItem(cleBrouillon); } catch { /* */ }
  }

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

  const iCls = 'w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] focus:ring-2 focus:ring-[#0C5C6C]/10 bg-white';
  const iSmCls = 'w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] focus:ring-2 focus:ring-[#0C5C6C]/10 bg-white';
  const sCls = 'border border-gray-200 rounded-lg p-4 space-y-3';
  const ETAPES = ['Annonce et animal', 'Santé et origines', 'Publication'];

  function thumbUrl(url: string) {
    // Add-on de transformation d'image Supabase non activé sur ce projet
    // (403 FeatureNotEnabled) — image d'origine, redimensionnée en CSS.
    return url;
  }

  // ── My animals loaders
  async function loadFemelles() {
    setLoadingFemelles(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, race, couleur, couleur_yeux, description, identification, photo_url')
      .eq('uid_eleveur', user!.uid)
      .eq('espece', ESPECE_DB[espece] ?? espece.toLowerCase())
      .eq('sexe', 'femelle').order('nom');
    setMyFemelles((data ?? []) as MyAnimal[]);
    setLoadingFemelles(false);
  }

  async function loadMales() {
    setLoadingMales(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, couleur, couleur_yeux, description, identification, photo_url, pedigree_lof, club_registre')
      .eq('uid_eleveur', user!.uid)
      .eq('espece', ESPECE_DB[espece] ?? espece.toLowerCase())
      .eq('sexe', 'male').order('nom');
    setMyMales((data ?? []) as MyAnimal[]);
    setLoadingMales(false);
  }

  async function loadAllAnimals() {
    setLoadingRetraite(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, couleur, couleur_yeux, description, identification, photo_url, pedigree_lof, club_registre')
      .eq('uid_eleveur', user!.uid).order('nom');
    setMyAnimalsAll((data ?? []) as MyAnimal[]);
    setLoadingRetraite(false);
  }

  async function loadAllMales() {
    setLoadingAllMales(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, couleur, couleur_yeux, description, identification, photo_url, pedigree_lof, club_registre')
      .eq('uid_eleveur', user!.uid).eq('sexe', 'male').order('nom');
    setMyAllMales((data ?? []) as MyAnimal[]);
    setLoadingAllMales(false);
  }

  function selectEtalon(a: MyAnimal) {
    // Remplit la section père (= étalon)
    setPereAnimalId(a.id); setPereNom(a.nom ?? ''); setPerePuce(a.identification ?? '');
    setNumIdentification(a.identification ?? '');
    setPereRace(a.race ?? ''); setPereCouleur(a.couleur ?? ''); setPereCouleurYeux(a.couleur_yeux ?? ''); setPereDescription(a.description ?? '');
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
      .select('id, nom, sexe, race, couleur, couleur_yeux, description, identification, photo_url')
      .eq('uid_eleveur', user!.uid)
      .eq('espece', ESPECE_DB[espece] ?? espece.toLowerCase())
      .order('nom');
    setBabyPickerAnimals((data ?? []) as MyAnimal[]);
    setLoadingBabyPicker(false);
  }

  // ── Parent selectors
  function selectMere(a: MyAnimal) {
    setMereAnimalId(a.id); setMereNom(a.nom ?? ''); setMerePuce(a.identification ?? '');
    setMereRace(a.race ?? ''); setMereCouleur(a.couleur ?? ''); setMereCouleurYeux(a.couleur_yeux ?? ''); setMereDescription(a.description ?? '');
    setMerePhotoPreview(a.photo_url ?? null);
    setMerePhotoBlob(null); setShowMerePicker(false);
  }
  function clearMere() {
    setMereAnimalId(null); setMereNom(''); setMerePuce(''); setMereRace('');
    setMereCouleur(''); setMereCouleurYeux(''); setMereDescription(''); setMereRegistre('');
    setMerePhotoPreview(null); setMerePhotoBlob(null);
  }

  function selectPere(a: MyAnimal) {
    setPereAnimalId(a.id); setPereNom(a.nom ?? ''); setPerePuce(a.identification ?? '');
    setPereRace(a.race ?? ''); setPereCouleur(a.couleur ?? ''); setPereCouleurYeux(a.couleur_yeux ?? ''); setPereDescription(a.description ?? '');
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
    setCouleurAnimal(a.couleur ?? ''); setCouleurYeuxAnimal(a.couleur_yeux ?? '');
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
    setPereEleveurReseau(null);
    setPereAnimalId(null); setPereNom(''); setPerePuce(''); setPereRace('');
    setPereCouleur(''); setPereCouleurYeux(''); setPereDescription(''); setPereRegistre('');
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
    setEditingBaby({ id: crypto.randomUUID(), nom: '', sexe: 'male', couleur: '', couleur_yeux: '', prix: '', statut: 'disponible', description: '' });
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
      couleur_yeux: a.couleur_yeux ?? '',
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

  // ── Vidéo cheval (sous selle / en liberté)
  async function handleEquideVideo(e: React.ChangeEvent<HTMLInputElement>, which: 'monte' | 'libre') {
    const f = e.target.files?.[0]; e.target.value = '';
    if (!f) return;
    if (f.size > 60 * 1024 * 1024) { setError('Vidéo trop lourde (max 60 Mo).'); return; }
    setUploadingVideo(which); setError('');
    try {
      const ext = (f.name.split('.').pop() ?? 'mp4').toLowerCase();
      const url = await uploadRawFile(f, `annonces/${user!.uid}/video_${which}_${Date.now()}.${ext}`);
      if (which === 'monte') setVideoMonteUrl(url); else setVideoLibreUrl(url);
    } catch {
      setError('Échec de l\'envoi de la vidéo.');
    } finally {
      setUploadingVideo(null);
    }
  }

  function selectFormuleEquine(v: typeof formuleEquine) {
    setFormuleEquine(v);
    setPrixUnite(v === 'location' || v === 'demi_pension' || v === 'pension_complete' ? 'mois'
      : v === 'valorisation' ? 'convenir' : 'total');
  }

  // ── Main photos
  function handlePhotos(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []).slice(0, Math.max(0, 5 - photosExistantes.length));
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
      const res = await apiFetch('/api/stripe/checkout', {
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

  // ── Réseau PetsMatch : reproducteurs proposés publiquement (annonce de saillie active),
  // jamais une fiche privée. L'annonce garde un lien (pere_animal_id), sans copie de fiche.
  async function chercherReseau(q: string) {
    setReseauQuery(q);
    if (!user) return;
    setLoadingReseau(true);
    try {
      const { data } = await supabase.from('annonces')
        .select('id, titre, race, nom_eleveur, pere_nom, pere_puce, pere_race, pere_couleur, pere_couleur_yeux, pere_registre, pere_photo_url, photos, etalon_animal_id')
        .eq('type_vente', 'saillie').eq('statut', 'disponible')
        .eq('espece', ESPECE_DB[espece] ?? espece.toLowerCase())
        .neq('uid_eleveur', user.uid)
        .order('created_at', { ascending: false }).limit(40);
      const t = q.trim().toLowerCase();
      setReseauResults(((data ?? []) as ReseauEtalon[]).filter(a => !t ||
        [a.pere_nom, a.titre, a.nom_eleveur, a.pere_puce, a.pere_race, a.race].some(v => (v ?? '').toLowerCase().includes(t))).slice(0, 12));
    } finally { setLoadingReseau(false); }
  }
  function choisirReseau(a: ReseauEtalon) {
    setPereAnimalId(a.etalon_animal_id ?? null);
    setPereNom(a.pere_nom || a.titre || '');
    setPerePuce(a.pere_puce ?? ''); setPereRace(a.pere_race ?? a.race ?? '');
    setPereCouleur(a.pere_couleur ?? ''); setPereCouleurYeux(a.pere_couleur_yeux ?? ''); setPereRegistre(a.pere_registre ?? '');
    setPerePhotoBlob(null); setPerePhotoPreview(a.pere_photo_url ?? a.photos?.[0] ?? null);
    setPereEleveurReseau(a.nom_eleveur ?? 'Éleveur PetsMatch');
    setReseauResults([]);
  }

  // ── Étapes : validation progressive (mêmes règles légales qu'à la publication)
  function erreurEtape(n: number): string | null {
    const chienChat = espece === 'Chien' || espece === 'Chat';
    if (n === 1) {
      if (espece === 'Autre' && !especeAutre.trim()) return 'Précisez l’espèce.';
      if (chienChat && type === 'portee' && !dateNaissance) return 'Obligatoire : date de naissance de la portée.';
    }
    if (n === 2) {
      if (espece === 'Cheval' && !numSIRE.trim()) return 'Obligatoire : numéro SIRE pour tout équidé mis en vente — Décret n°2013-879.';
      if (chienChat && type !== 'portee' && !numIdentification.trim()) return 'Obligatoire : numéro d’identification de l’animal (puce électronique ou tatouage) — art. L212-10 Code rural.';
      if (chienChat && type === 'portee' && !merePuce.trim()) return 'Obligatoire : numéro d’identification (puce ICAD ou tatouage) de la mère — art. L214-8 Code rural.';
    }
    return null;
  }
  function suivant() {
    const err = erreurEtape(etape);
    if (err) { setError(err); return; }
    setError(''); setEtape(Math.min(3, etape + 1)); window.scrollTo({ top: 0 });
  }
  function allerA(n: number) {
    // Retour libre ; avancer seulement si les étapes intermédiaires sont complètes
    for (let k = etape; k < n; k++) {
      const err = erreurEtape(k);
      if (err) { setEtape(k); setError(err); return; }
    }
    setError(''); setEtape(n); window.scrollTo({ top: 0 });
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    // Entrée dans un champ avant la dernière étape : passer à l'étape suivante
    if (etape < 3) { suivant(); return; }
    await enregistrer('publier');
  }

  async function enregistrer(mode: 'publier' | 'brouillon') {
    const brouillon = mode === 'brouillon';
    setError(''); setSaving(true);
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

      if (!brouillon && planCfg.maxAnnonces !== -1) {
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
      if (!brouillon && type === 'portee') {
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
      if (!brouillon && croppedBlobs.length + photosExistantes.length === 0) {
        setError('Au moins une photo est obligatoire pour publier une annonce.');
        setSaving(false); return;
      }
      if (!brouillon && (espece === 'Chien' || espece === 'Chat') && type === 'portee') {
        if (!merePuce.trim()) {
          setError('⚠ Obligatoire : numéro d\'identification (puce ICAD ou tatouage) de la mère — art. L214-8 Code rural.');
          setSaving(false); return;
        }
        if (!dateNaissance) {
          setError('⚠ Obligatoire : date de naissance de la portée.');
          setSaving(false); return;
        }
      }
      if (!brouillon && espece === 'Cheval' && !numSIRE.trim()) {
        setError('⚠ Obligatoire : numéro SIRE pour tout équidé mis en vente — Décret n°2013-879.');
        setSaving(false); return;
      }
      if (!brouillon && (espece === 'Chien' || espece === 'Chat') && type !== 'portee' && !numIdentification.trim()) {
        setError('⚠ Obligatoire : numéro d\'identification de l\'animal (puce électronique ou tatouage) — art. L212-10 Code rural.');
        setSaving(false); return;
      }

      const annonceStatut = brouillon ? 'brouillon' : planCfg.autoPublish ? 'disponible' : 'en_attente';
      const expireAt = new Date(Date.now() + planCfg.dureeDays * 86_400_000).toISOString();
      const photoUrls: string[] = [...photosExistantes];
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
        // (et celles d'un brouillon repris)
        const uploadedUrls: string[] = [...(baby.photos ?? [])];
        if (photos) {
          for (const blob of photos.blobs)
            uploadedUrls.push(await uploadBlob(blob, `annonces/animaux/${user!.uid}/${Date.now()}.jpg`));
        }
        const { id: _id, ...rest } = baby;
        animauxSaved.push({ ...rest, photos: uploadedUrls });
      }

      const nomEleveur = (userData?.nameElevage ?? `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim()) || '';
      const villeEleveur = userData?.villeElevage ?? userData?.ville ?? '';

      // ── Détection mots interdits / annonce suspecte ────────────────────────
      const PRIX_MIN: Record<string, number> = { chien: 150, chat: 100, cheval: 800, lapin: 20, oiseau: 30 };
      const PRIX_MAX: Record<string, number> = { chien: 20000, chat: 6000, cheval: 150000, lapin: 1000, oiseau: 5000, nac: 3000 };
      const BLACKLIST = ['bitcoin', 'crypto', 'western union', 'mandat cash', 'arnaque', 'don gratuit', 'livraison longue distance', 'visa gift', 'paypal friends'];
      const espDb = (ESPECE_DB[espece] ?? espece).toLowerCase();
      // Formule équine (cheval « compagnon ») : vente ferme sinon location / demi-pension / valo
      const isEquideFormule = espece === 'Cheval' && type === 'compagnon';
      const effectiveTypeVente = type === 'saillie' ? 'saillie'
        : type === 'retraite' ? 'retraite'
        : isEquideFormule ? formuleEquine
        : cession;
      // Les bornes de prix ne valent que pour une vente ferme / une portée.
      const checkPriceBand = !isEquideFormule || formuleEquine === 'vente';
      const suspectReasons: string[] = [];
      const fullText = `${titre} ${description}`.toLowerCase();
      const prixNum = prix ? Number(prix) : null;
      const prixMinPorteeNum = prixMin ? Number(prixMin) : null;
      if (checkPriceBand && prixNum && prixNum > 0 && PRIX_MIN[espDb] && prixNum < PRIX_MIN[espDb]) suspectReasons.push('prix_tres_bas');
      if (checkPriceBand && prixNum && PRIX_MAX[espDb] && prixNum > PRIX_MAX[espDb]) suspectReasons.push('prix_tres_eleve');
      if (prixMinPorteeNum && prixMinPorteeNum > 0 && PRIX_MIN[espDb] && prixMinPorteeNum < PRIX_MIN[espDb]) suspectReasons.push('prix_portee_bas');
      for (const w of BLACKLIST) { if (fullText.includes(w)) suspectReasons.push(`mot_suspect:${w}`); }

      // uid Firebase RÉEL du propriétaire de l'élevage actif — jamais
      // forcément user.uid : un cogérant (elevage_cogerants) a un uid
      // différent du gérant, mais la ligne user_profiles du profil emprunté
      // (activeProfileId) reste celle du gérant.
      let ownerUid = user!.uid;
      if (activeProfileId) {
        const { data: ownerProf } = await supabase.from('user_profiles_complet').select('uid').eq('id', activeProfileId).maybeSingle();
        ownerUid = (ownerProf?.uid as string | undefined) ?? user!.uid;
      }

      const payload = {
        uid_eleveur: ownerUid,
        ...(activeProfileId ? { profile_id: activeProfileId } : {}),
        nom_eleveur: nomEleveur, ville_eleveur: villeEleveur,
        is_suspect: suspectReasons.length > 0,
        suspect_reasons: suspectReasons,
        titre: titre || `${espece} ${race}`.trim(),
        espece: ESPECE_DB[espece] ?? espece.toLowerCase(), race,
        espece_autre: espece === 'Autre' ? (especeAutre.trim() || null) : null,
        type: type === 'portee' ? 'portee' : 'animal',
        type_vente: effectiveTypeVente,
        photos: photoUrls, statut: annonceStatut, expire_at: expireAt, description,
        ...(isEquideFormule && {
          prix_unite: formuleEquine === 'vente' ? null : prixUnite,
          niveau_recommande: niveauEquide || null,
          palmares: palmares.trim() || null,
          indice_iso: indiceIso ? Number(indiceIso) : null,
          indice_idr: indiceIdr ? Number(indiceIdr) : null,
          indice_icc: indiceIcc ? Number(indiceIcc) : null,
          video_monte_url: videoMonteUrl,
          video_libre_url: videoLibreUrl,
        }),
        ...(type === 'compagnon' && { prix: prix && cession !== 'don' ? Number(prix) : null, sexe: sexeAnimal, couleur: couleurAnimal || null, couleur_yeux: couleurYeuxAnimal || null, sterilise }),
        ...(type === 'retraite' && { prix: prix && cession !== 'don' ? Number(prix) : null, sexe: sexeAnimal, couleur: couleurAnimal || null, couleur_yeux: couleurYeuxAnimal || null, etalon_animal_id: retraiteAnimalId }),
        ...(type === 'portee' && {
          date_naissance: dateNaissance || null,
          nombre_bebes: nombreBebes,
          prix_min_portee: prixMin && cession !== 'don' ? Number(prixMin) : null,
          prix_max_portee: prixMax && cession !== 'don' ? Number(prixMax) : null,
          animaux_portee: animauxSaved.length > 0 ? animauxSaved : null,
        }),
        ...(type === 'saillie' && {
          saillie_prix: sailliePrix ? parseFloat(sailliePrix) : null,
          saillie_conditions: saillieConditions || null,
          saillie_genetique: saillieGenetique.trim() || null,
          etalon_animal_id: pereAnimalId,
        }),
        vaccines, vermifuge, identification: identificationSante, bilan_sante: bilanSante,
        semaines: type !== 'saillie' ? semaines : null,
        club_pedigree: clubPedigree || null, numero_registre: numRegistre || null,
        ...(type !== 'saillie' && {
          mere_animal_id: mereAnimalId, mere_photo_url: merePhotoUrl,
          mere_nom: mereNom || null, mere_puce: merePuce || null, mere_identification: merePuce || null,
          mere_race: mereRace || null, mere_couleur: mereCouleur || null, mere_couleur_yeux: mereCouleurYeux || null,
          mere_description: mereDescription || null, mere_registre: mereRegistre || null,
        }),
        pere_animal_id: pereAnimalId, pere_photo_url: perePhotoUrl,
        pere_nom: pereNom || null, pere_puce: perePuce || null, pere_identification: perePuce || null,
        pere_race: pereRace || null, pere_couleur: pereCouleur || null, pere_couleur_yeux: pereCouleurYeux || null,
        pere_description: pereDescription || null, pere_registre: pereRegistre || null,
        // Champs légaux
        num_identification: (espece === 'Chien' || espece === 'Chat') && type !== 'portee' ? numIdentification || null : null,
        num_sire: espece === 'Cheval' ? numSIRE || null : null,
        num_passeport_equin: espece === 'Cheval' ? numPasseportEquin || null : null,
      };
      const { error: insertError } = brouillonId
        ? await supabase.from('annonces').update(payload).eq('id', brouillonId)
        : await supabase.from('annonces').insert({ id: genId(), ...payload });
      if (insertError) throw new Error(insertError.message);
      oublierBrouillonLocal();
      if (brouillon) { router.push('/mes-annonces?brouillon=1'); return; }

      // ── Déclencher la validation auto du profil si encore en attente ────────
      if (activeProfileId) {
        const { data: profil } = await supabase
          .from('user_profiles_complet').select('validation_status, profile_type')
          .eq('id', activeProfileId).maybeSingle();
        if (profil && profil.profile_type !== 'particulier' && profil.validation_status === 'pending') {
          // Fire-and-forget : ne bloque pas la redirection
          apiFetch('/api/admin/validate-profile', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ profileId: activeProfileId }),
          }).catch(() => {});
        }
      }

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
      <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg max-h-52 overflow-y-auto">
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
                <svg className="w-5 h-5 text-gray-300" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15.75l5.16-5.16a2.25 2.25 0 013.18 0l5.16 5.16m-1.5-1.5l1.41-1.41a2.25 2.25 0 013.18 0l2.91 2.91M3.75 21h16.5A1.5 1.5 0 0021.75 19.5V4.5A1.5 1.5 0 0020.25 3H3.75A1.5 1.5 0 002.25 4.5v15A1.5 1.5 0 003.75 21z" /></svg>
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
        <div className={`w-16 h-16 rounded-lg overflow-hidden flex items-center justify-center relative ${preview ? 'border border-gray-200' : 'border border-dashed border-gray-200 bg-gray-50'}`}>
          {preview ? (
            <>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={preview} alt="" className="w-full h-full object-contain bg-gray-50" />
              <div className="absolute inset-0 bg-black/30 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                <span className="text-white text-xs font-medium">Modifier</span>
              </div>
            </>
          ) : (
            <svg className="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M6.8 6.2A2.3 2.3 0 015 7.2c-.4.1-.8.1-1.1.2C2.8 7.5 2 8.4 2 9.5V18a2.3 2.3 0 002.3 2.3h15.4A2.3 2.3 0 0022 18V9.5c0-1.1-.8-2-1.9-2.2l-1.1-.1a2.3 2.3 0 01-1.8-1.1l-.8-1.3a2.2 2.2 0 00-1.8-1H9.4a2.2 2.2 0 00-1.8 1l-.8 1.4zM16.5 12.8a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0z" /></svg>
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
      <div className="flex items-center gap-3 p-3 border border-gray-100 rounded-lg bg-gray-50/50">
        <div className="w-12 h-12 rounded-lg overflow-hidden flex-shrink-0 bg-gray-100 flex items-center justify-center">
          {firstPreview ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={firstPreview} alt="" className="w-full h-full object-cover" />
          ) : (
            <svg className="w-5 h-5 text-gray-300" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15.75l5.16-5.16a2.25 2.25 0 013.18 0l5.16 5.16m-1.5-1.5l1.41-1.41a2.25 2.25 0 013.18 0l2.91 2.91M3.75 21h16.5A1.5 1.5 0 0021.75 19.5V4.5A1.5 1.5 0 0020.25 3H3.75A1.5 1.5 0 002.25 4.5v15A1.5 1.5 0 003.75 21z" /></svg>
          )}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-gray-800 truncate">{baby.nom || `Bébé ${index + 1}`}</p>
          <p className="text-xs text-gray-400">{baby.sexe === 'male' ? 'Mâle' : 'Femelle'}{baby.couleur ? ` · ${baby.couleur}` : ''}{baby.couleur_yeux ? ` · yeux ${baby.couleur_yeux}` : ''}</p>
        </div>
        <span className={`text-xs font-semibold px-2 py-1 rounded-lg ${statusColor}`}>{statusLabel}</span>
        <button type="button" onClick={() => openEditBaby(baby)}
          className="text-[#0C5C6C] hover:bg-[#E8F4F6] p-1.5 rounded-lg transition-colors text-sm font-semibold">Modifier</button>
        <button type="button" onClick={() => removeBaby(baby.id)}
          className="text-red-400 hover:text-red-600 p-1.5 rounded-lg transition-colors text-lg leading-none">×</button>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-10">
      <div className="flex items-end justify-between gap-3 flex-wrap mb-6">
        <div>
          <Link href="/mes-annonces" className="text-sm text-[#0C5C6C] hover:underline">Mes annonces</Link>
          <h1 className="text-2xl font-bold text-[#1F2A2E] mt-1">{brouillonId ? 'Reprendre le brouillon' : 'Nouvelle annonce'}</h1>
        </div>
        {autoSaveA && (
          <p className="text-xs text-gray-500 flex items-center gap-1.5" aria-live="polite">
            <span className="w-1.5 h-1.5 rounded-full bg-[#6E9E57]" />Enregistré automatiquement à {autoSaveA}
          </p>
        )}
      </div>

      {brouillonLocal && (
        <div className="mb-4 flex flex-col sm:flex-row sm:items-center gap-3 border border-gray-200 bg-white rounded-lg p-4">
          <p className="flex-1 text-sm text-gray-700">
            Une annonce non terminée du {new Date(brouillonLocal.savedAt).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })} a été retrouvée sur cet appareil.
          </p>
          <div className="flex gap-2">
            <button type="button" onClick={() => { oublierBrouillonLocal(); setBrouillonLocal(null); }}
              className="h-9 px-3 rounded-lg border border-gray-300 text-sm font-semibold text-gray-700 hover:bg-gray-50">Ignorer</button>
            <button type="button" onClick={() => { restaurer(brouillonLocal.data); setBrouillonLocal(null); }}
              className="h-9 px-3 rounded-lg bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D]">Reprendre</button>
          </div>
        </div>
      )}

      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <form onSubmit={handleSubmit} className="space-y-5">

          {/* ── Étapes ── */}
          <nav aria-label="Étapes" className="grid grid-cols-3 border-b border-gray-200 -mx-6 -mt-6 mb-2 rounded-t-xl">
            {ETAPES.map((t, i) => {
              const n = i + 1;
              const actif = etape === n, fait = etape > n;
              return (
                <button key={t} type="button" onClick={() => allerA(n)} aria-current={actif ? 'step' : undefined}
                  className={`flex items-center justify-center sm:justify-start gap-2 px-3 sm:px-5 py-3.5 text-sm font-semibold border-b-2 -mb-px transition-colors ${
                    actif ? 'border-[#0C5C6C] text-[#0C5C6C]' : fait ? 'border-transparent text-gray-600 hover:text-[#0C5C6C]' : 'border-transparent text-gray-400 hover:text-gray-600'}`}>
                  <span className={`w-6 h-6 rounded-full text-xs flex items-center justify-center flex-shrink-0 ${
                    actif ? 'bg-[#0C5C6C] text-white' : fait ? 'bg-[#E8F4F6] text-[#0C5C6C]' : 'border border-gray-300'}`}>{n}</span>
                  <span className={actif ? 'inline' : 'hidden sm:inline'}>{t}</span>
                </button>
              );
            })}
          </nav>

          <div hidden={etape !== 1} className="space-y-5">
            <div>
              <h2 className="text-base font-bold text-[#1F2A2E]">Annonce et animal</h2>
              <p className="text-sm text-gray-500">Type d’annonce et identité de l’animal.</p>
            </div>
          {/* ── Type de cession ── */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">Type d&apos;annonce</label>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
              {([
                ['vente', 'Vente', 'Proposer un animal à la vente', 'M9.6 3H4.5A1.5 1.5 0 003 4.5v5.1c0 .4.16.78.44 1.06l9.26 9.26a1.5 1.5 0 002.12 0l5.12-5.12a1.5 1.5 0 000-2.12L10.66 3.44A1.5 1.5 0 009.6 3zM7.5 7.5h.01'],
                ['adoption', 'Adoption', 'Frais d’adoption et conditions', 'M21 8.25c0-2.49-2.1-4.5-4.69-4.5-1.94 0-3.6 1.13-4.31 2.73-.71-1.6-2.37-2.73-4.31-2.73C5.1 3.75 3 5.76 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12z'],
                ['don', 'Don', 'Céder gratuitement', 'M20.25 11.25v8.25a1.5 1.5 0 01-1.5 1.5H5.25a1.5 1.5 0 01-1.5-1.5v-8.25M12 4.88A2.63 2.63 0 109.38 7.5H12m0-2.62V7.5m0-2.62a2.63 2.63 0 112.63 2.62H12M3.38 11.25h17.25c.62 0 1.12-.5 1.12-1.12v-1.5c0-.63-.5-1.13-1.12-1.13H3.38c-.63 0-1.13.5-1.13 1.13v1.5c0 .62.5 1.12 1.13 1.12zM12 7.5v13.5'],
              ] as const).map(([v, l, d, path]) => {
                const actif = cession === v && type !== 'saillie';
                return (
                  <button key={v} type="button" disabled={type === 'saillie'} onClick={() => setCession(v)} aria-pressed={actif}
                    className={`flex items-start gap-3 text-left p-3 rounded-lg border transition-colors ${
                      actif ? 'border-[#0C5C6C] ring-1 ring-[#0C5C6C] bg-[#E8F4F6]/60' : 'border-gray-200 hover:border-gray-300'
                    } ${type === 'saillie' ? 'opacity-40 cursor-not-allowed' : ''}`}>
                    <svg className={`w-5 h-5 flex-shrink-0 mt-0.5 ${actif ? 'text-[#0C5C6C]' : 'text-gray-500'}`} fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d={path} /></svg>
                    <span><span className="block text-sm font-semibold text-[#1F2A2E]">{l}</span><span className="block text-xs text-gray-500">{d}</span></span>
                  </button>
                );
              })}
            </div>
            {type === 'saillie' && <p className="text-xs text-gray-500 mt-1.5">Une saillie n’est ni une vente, ni une adoption : son prix se règle à l’étape Publication.</p>}
          </div>

          {/* ── Type d'annonce ── */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">Objet de l&apos;annonce</label>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {([['compagnon', 'Animal individuel'], ['portee', 'Portée complète'], ['saillie', 'Saillie'], ['retraite', 'Retraité d\'élevage']] as [string, string][]).map(([v, l]) => (
                <button key={v} type="button" onClick={() => setType(v as typeof type)}
                  className={`py-2.5 rounded-lg text-sm font-medium border transition-colors ${
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
                  className="w-full flex items-center gap-2 px-4 py-3 border border-[#0C5C6C] text-[#0C5C6C] rounded-lg text-sm font-semibold hover:bg-[#E8F4F6] transition-colors">
                  <span>{pereAnimalId ? `${pereNom || 'Étalon sélectionné'} — changer` : 'Sélectionner l\'étalon / reproducteur (espèce & race auto-remplies)'}</span>
                </button>
                {!pereAnimalId && <p className="text-xs text-gray-400 mt-1">L&apos;espèce, la race et le pedigree seront pré-remplis automatiquement.</p>}
                {pereAnimalId && <p className="text-xs text-[#4A7C39] mt-1">Espèce, race et pedigree pré-remplis</p>}
                {showEtalonPicker && <AnimalPickerList animals={myAllMales} isLoading={loadingAllMales} onSelect={selectEtalon} />}
              </div>
            )}
            {/* Retraité : picker AVANT espèce pour auto-remplissage */}
            {type === 'retraite' && (
              <div className="mt-3 relative">
                <button type="button"
                  onClick={async () => { if (!showRetraitePicker) await loadAllAnimals(); setShowRetraitePicker(!showRetraitePicker); }}
                  className="w-full flex items-center gap-2 px-4 py-3 border border-[#0C5C6C] text-[#0C5C6C] rounded-lg text-sm font-semibold hover:bg-[#E8F4F6] transition-colors">
                  <span>{retraiteAnimalId ? `${retraiteAnimalNom} — changer` : 'Sélectionner l\'animal retraité (espèce & race auto-remplies)'}</span>
                </button>
                {!retraiteAnimalId && <p className="text-xs text-gray-400 mt-1">L&apos;espèce, la race et les infos seront pré-remplies automatiquement.</p>}
                {showRetraitePicker && <AnimalPickerList animals={myAnimalsAll} isLoading={loadingRetraite} onSelect={selectRetraite} />}
              </div>
            )}
          </div>

          {/* ── Espèce + Race ── */}
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Espèce</label>
              <select value={espece} onChange={e => setEspece(e.target.value)} className={iCls}>
                {ESPECES.map(e => <option key={e}>{e}</option>)}
              </select>
              {espece === 'Autre' && (
                <input value={especeAutre} onChange={e => setEspeceAutre(e.target.value)}
                  placeholder="Préciser l'espèce (ex: Furet, Tortue...)" className={`${iCls} mt-2`} />
              )}
            </div>
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Race</label>
              <input value={race} onChange={e => setRace(e.target.value)} list="breed-list"
                placeholder={breeds.length ? 'Sélectionner ou saisir une race…' : 'Ex: Labrador…'} className={iCls} />
              <datalist id="breed-list">{breeds.map(b => <option key={b} value={b} />)}</datalist>
            </div>
          </div>

          {/* ── Compagnon / Retraité ── */}
          {(type === 'compagnon' || type === 'retraite') && (
            <>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Sexe</label>
                <div className="flex gap-2">
                  {([['male', 'Mâle'], ['femelle', 'Femelle']] as const).map(([v, l]) => (
                    <button key={v} type="button" onClick={() => setSexeAnimal(v)}
                      className={`flex-1 py-2 rounded-lg border text-sm font-medium transition-colors ${sexeAnimal === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>{l}</button>
                  ))}
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Couleur / Robe <span className="text-gray-400 font-normal">(optionnel)</span></label>
                <input value={couleurAnimal} onChange={e => setCouleurAnimal(e.target.value)} placeholder="Ex: Fauve, Tricolore…" className={iCls} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Couleur des yeux <span className="text-gray-400 font-normal">(optionnel)</span></label>
                <input value={couleurYeuxAnimal} onChange={e => setCouleurYeuxAnimal(e.target.value)} placeholder="Ex: marron, bleu…" className={iCls} />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-700">Stérilisé(e)</span>
                <button type="button" onClick={() => setSterilise(!sterilise)}
                  className={`w-12 h-6 rounded-full transition-colors relative ${sterilise ? 'bg-[#6E9E57]' : 'bg-gray-400'}`}>
                  <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform ${sterilise ? 'translate-x-6' : 'translate-x-0.5'}`} />
                </button>
              </div>
            </>
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
                      className="w-9 h-9 rounded-lg border border-gray-300 text-[#0C5C6C] text-lg font-bold flex items-center justify-center hover:bg-[#d0eaf0]">−</button>
                    <span className="text-xl font-bold text-[#1F2A2E] w-8 text-center">{nombreBebes}</span>
                    <button type="button" onClick={() => setNombreBebes(n => Math.min(20, n + 1))}
                      className="w-9 h-9 rounded-lg border border-gray-300 text-[#0C5C6C] text-lg font-bold flex items-center justify-center hover:bg-[#d0eaf0]">+</button>
                  </div>
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
                    className="text-xs font-semibold text-white bg-[#0C5C6C] hover:bg-[#094F5D] px-3 py-1.5 rounded-lg transition-colors">
                    + Ajouter un bébé
                  </button>
                </div>
                {animauxPortee.length === 0 && (
                  <p className="text-sm text-gray-400 text-center py-6 border border-dashed border-gray-100 rounded-lg">
                    Détaillez chaque bébé individuellement avec ses photos
                  </p>
                )}
                <div className="space-y-2">
                  {animauxPortee.map((a, i) => <BabyCard key={a.id} baby={a} index={i} />)}
                </div>
              </div>
            </>
          )}

          {/* ── Description ── */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={4}
              placeholder="Décrivez votre annonce…" className={`${iCls} resize-none`} />
          </div>

          </div>
          <div hidden={etape !== 2} className="space-y-5">
            <div>
              <h2 className="text-base font-bold text-[#1F2A2E]">Santé et origines</h2>
              <p className="text-sm text-gray-500">Identification, santé, mère et père.</p>
            </div>
          {/* ── Identification légale équidé ── */}
          {espece === 'Cheval' && (
            <div className="border border-gray-200 rounded-lg p-4 space-y-3">
              <p className="text-sm font-semibold text-gray-700">Identification équidé <span className="text-red-500">*</span></p>
              <p className="text-xs text-gray-500">Obligatoire pour tout équidé (Décret n°2013-879)</p>
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

          {(type === 'compagnon' || type === 'retraite') && (
            <>
              {(espece === 'Chien' || espece === 'Chat') && (
                <div className="border border-gray-200 rounded-lg p-4 space-y-2">
                  <p className="text-sm font-semibold text-gray-700">
                    Identification de l&apos;animal <span className="text-red-500">*</span>
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
            <div className="border border-gray-200 rounded-lg p-4 space-y-2">
              <p className="text-sm font-semibold text-gray-700">
                Identification de l&apos;étalon <span className="text-red-500">*</span>
                <span className="font-normal ml-1">— obligatoire (art. L212-10 Code rural)</span>
              </p>
              <input value={numIdentification} onChange={e => setNumIdentification(e.target.value)}
                placeholder="Numéro de puce électronique ou tatouage"
                className={`${iCls} text-sm ${!numIdentification.trim() ? 'border-amber-300 focus:border-amber-500' : 'border-[#6E9E57]'}`} />
            </div>
          )}

          {/* ── Santé & Conformité ── */}
          <div className={sCls}>
            <p className="text-sm font-semibold text-gray-700">Santé</p>
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
                    className="w-9 h-9 rounded-lg border border-gray-300 text-[#0C5C6C] text-lg font-bold flex items-center justify-center hover:bg-[#d0eaf0]">−</button>
                  <span className="text-base font-bold text-[#1F2A2E] min-w-[90px] text-center">{semaines} semaines</span>
                  <button type="button" onClick={() => setSemaines(s => Math.min(52, s + 1))}
                    className="w-9 h-9 rounded-lg border border-gray-300 text-[#0C5C6C] text-lg font-bold flex items-center justify-center hover:bg-[#d0eaf0]">+</button>
                  {semaines < 8 && <span className="text-xs text-amber-600 font-medium">minimum légal : 8 semaines</span>}
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
                Mère
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
                    className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-lg text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                    <svg className="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" d="M21 21l-5.2-5.2m0 0A7.5 7.5 0 105.2 5.2a7.5 7.5 0 0010.6 10.6z" /></svg>
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
              <div className="flex gap-2">
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Couleur des yeux</label>
                  <input value={mereCouleurYeux} onChange={e => setMereCouleurYeux(e.target.value)} placeholder="Ex: marron…" className={iSmCls} /></div>
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Registre</label>
                  <input value={mereRegistre} onChange={e => setMereRegistre(e.target.value)} placeholder="LOF, LOOF, Non inscrite…" className={iSmCls} /></div>
              </div>
              <div><label className="block text-xs font-medium text-gray-600 mb-1">Description</label>
                <textarea value={mereDescription} onChange={e => setMereDescription(e.target.value)} rows={2}
                  placeholder="Caractère, morphologie…" className={`${iSmCls} resize-none`} /></div>
            </div>
          )}

          {/* ── Père / Étalon — masqué pour retraité ── */}
          {type !== 'retraite' && <div className={sCls}>
            <div className="flex items-center justify-between gap-3 flex-wrap">
              <p className="text-sm font-semibold text-gray-700">
                {type === 'saillie' ? 'Étalon / Reproducteur' : 'Père'} <span className="text-gray-400 font-normal">(optionnel)</span>
              </p>
              {type !== 'saillie' && (
                <div className="inline-flex rounded-lg border border-gray-300 overflow-hidden text-xs font-semibold" role="group" aria-label="Origine du père">
                  {([['mien', 'Mes animaux'], ['reseau', 'Réseau PetsMatch'], ['manuel', 'Saisie manuelle']] as const).map(([v, l], i) => (
                    <button key={v} type="button" aria-pressed={pereSource === v}
                      onClick={() => { setPereSource(v); setShowPerePicker(false); if (v === 'reseau' && reseauResults.length === 0) chercherReseau(reseauQuery); if (v === 'manuel') { setPereAnimalId(null); setPereEleveurReseau(null); } }}
                      className={`px-3 py-2 ${i > 0 ? 'border-l border-gray-300' : ''} ${pereSource === v ? 'bg-[#0C5C6C] text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>
                      {l}
                    </button>
                  ))}
                </div>
              )}
            </div>
            {(pereSource === 'mien' || type === 'saillie') && (
              <div className="flex items-start gap-3">
                <ParentPhotoBox preview={perePhotoPreview} onFileChange={handlePerePhotoFile} />
                <div className="flex-1 relative">
                  <button type="button"
                    onClick={async () => { if (!showPerePicker) await loadMales(); setShowPerePicker(!showPerePicker); setShowMerePicker(false); }}
                    className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-lg text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                    <svg className="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" d="M21 21l-5.2-5.2m0 0A7.5 7.5 0 105.2 5.2a7.5 7.5 0 0010.6 10.6z" /></svg>
                    <span>{pereAnimalId ? 'Changer d\'animal' : 'Chercher parmi mes animaux'}</span>
                  </button>
                  {showPerePicker && <AnimalPickerList animals={myMales} isLoading={loadingMales} onSelect={selectPere} />}
                </div>
              </div>
            )}
            {pereSource === 'reseau' && type !== 'saillie' && (
              <div className="space-y-2">
                <label className="relative block">
                  <span className="sr-only">Rechercher un reproducteur</span>
                  <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" d="M21 21l-5.2-5.2m0 0A7.5 7.5 0 105.2 5.2a7.5 7.5 0 0010.6 10.6z" /></svg>
                  <input value={reseauQuery} onChange={e => chercherReseau(e.target.value)}
                    placeholder="Nom de l’animal, n° d’identification ou élevage" className={`${iSmCls} pl-9`} />
                </label>
                {pereEleveurReseau && pereNom && (
                  <div className="flex items-center gap-3 p-2.5 border border-gray-200 rounded-lg">
                    {perePhotoPreview
                      // eslint-disable-next-line @next/next/no-img-element
                      ? <img src={perePhotoPreview} alt="" className="w-11 h-11 rounded-md object-cover flex-shrink-0" />
                      : <span className="w-11 h-11 rounded-md bg-gray-100 flex-shrink-0" />}
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-semibold text-[#1F2A2E] truncate">{pereNom}</p>
                      <p className="text-xs text-gray-500 truncate">{[pereRace, perePuce].filter(Boolean).join(' · ')}</p>
                      <p className="text-xs text-[#0C5C6C]">Fiche liée — {pereEleveurReseau}</p>
                    </div>
                    <button type="button" onClick={clearPere} className="text-xs text-gray-500 hover:text-red-600 font-medium">Retirer</button>
                  </div>
                )}
                {loadingReseau ? (
                  <p className="text-xs text-gray-400 py-2">Recherche…</p>
                ) : reseauResults.length > 0 ? (
                  <div className="border border-gray-200 rounded-lg divide-y divide-gray-100 max-h-64 overflow-y-auto">
                    {reseauResults.map(a => {
                      const ph = a.pere_photo_url ?? a.photos?.[0];
                      return (
                        <div key={a.id} className="flex items-center gap-3 p-2.5">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          {ph ? <img src={thumbUrl(ph)} alt="" className="w-10 h-10 rounded-md object-cover flex-shrink-0" /> : <span className="w-10 h-10 rounded-md bg-gray-100 flex-shrink-0" />}
                          <div className="min-w-0 flex-1">
                            <p className="text-sm font-semibold text-[#1F2A2E] truncate">{a.pere_nom || a.titre}</p>
                            <p className="text-xs text-gray-500 truncate">{[a.pere_race ?? a.race, a.pere_registre, a.nom_eleveur].filter(Boolean).join(' · ')}</p>
                          </div>
                          <button type="button" onClick={() => choisirReseau(a)}
                            className="h-8 px-3 rounded-md bg-[#0C5C6C] text-white text-xs font-semibold hover:bg-[#094F5D]">Sélectionner</button>
                        </div>
                      );
                    })}
                  </div>
                ) : (
                  <p className="text-xs text-gray-500">Aucun reproducteur trouvé. Seuls les reproducteurs proposés publiquement en saillie sur PetsMatch apparaissent.</p>
                )}
              </div>
            )}
            {pereSource === 'manuel' && type !== 'saillie' && (
              <p className="text-xs text-gray-500">Reproducteur extérieur : il n’est pas ajouté à votre cheptel.</p>
            )}
            {(pereSource !== 'reseau' || type === 'saillie') && (<>
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
            <div className="flex gap-2">
              <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Couleur des yeux</label>
                <input value={pereCouleurYeux} onChange={e => setPereCouleurYeux(e.target.value)} placeholder="Ex: marron…" className={iSmCls} /></div>
              <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">Registre</label>
                <input value={pereRegistre} onChange={e => setPereRegistre(e.target.value)} placeholder="LOF, LOOF, Non inscrit…" className={iSmCls} /></div>
            </div>
            <div><label className="block text-xs font-medium text-gray-600 mb-1">Description</label>
              <textarea value={pereDescription} onChange={e => setPereDescription(e.target.value)} rows={2}
                placeholder="Caractère, morphologie…" className={`${iSmCls} resize-none`} /></div>
            </>)}
          </div>}

          {type === 'saillie' && (
            <>
              {espece === 'Cheval' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Statut génétique de l&apos;étalon <span className="text-gray-400 font-normal">(optionnel)</span>
                  </label>
                  <textarea value={saillieGenetique} onChange={e => setSaillieGenetique(e.target.value)} rows={3}
                    placeholder="Ex: WFFS N/N, PSSM1 N/N, profil ADN établi — si l'étalon n'est pas fiché dans PetsMatch"
                    className={`${iCls} resize-none`} />
                  {pereAnimalId && (
                    <p className="text-xs text-gray-400 mt-1">Les tests fichés sur cet étalon s&apos;afficheront automatiquement.</p>
                  )}
                </div>
              )}
            </>
          )}
          </div>
          <div hidden={etape !== 3} className="space-y-5">
            <div>
              <h2 className="text-base font-bold text-[#1F2A2E]">Publication</h2>
              <p className="text-sm text-gray-500">Photos, prix et conditions.</p>
            </div>
          {/* ── Photos annonce ── */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Photos <span className="text-gray-400 font-normal">1 obligatoire · 5 maximum · la première est la photo principale</span></label>
            {photosExistantes.length > 0 && (
              <div className="flex gap-2 mb-3 flex-wrap">
                {photosExistantes.map((u, i) => (
                  <div key={u} className="relative w-16 h-16 rounded-lg overflow-hidden border border-gray-200 flex-shrink-0">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={thumbUrl(u)} alt="" className="w-full h-full object-cover" />
                    {i === 0 && <span className="absolute left-0.5 bottom-0.5 text-[9px] font-bold bg-[#0C5C6C] text-white px-1 rounded">Principale</span>}
                    <button type="button" onClick={() => setPhotosExistantes(p => p.filter(x => x !== u))} aria-label="Retirer la photo"
                      className="absolute top-0.5 right-0.5 w-5 h-5 rounded bg-black/55 text-white text-xs leading-none">×</button>
                  </div>
                ))}
              </div>
            )}
            <label className="flex items-center justify-center gap-2 w-full border border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-lg py-6 cursor-pointer transition-colors text-gray-400 hover:text-[#0C5C6C]">
              <svg className="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M6.8 6.2A2.3 2.3 0 015 7.2c-.4.1-.8.1-1.1.2C2.8 7.5 2 8.4 2 9.5V18a2.3 2.3 0 002.3 2.3h15.4A2.3 2.3 0 0022 18V9.5c0-1.1-.8-2-1.9-2.2l-1.1-.1a2.3 2.3 0 01-1.8-1.1l-.8-1.3a2.2 2.2 0 00-1.8-1H9.4a2.2 2.2 0 00-1.8 1l-.8 1.4zM16.5 12.8a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0z" /></svg>
              <span className="text-sm font-medium">Choisir des photos</span>
              <input type="file" accept="image/*" multiple onChange={handlePhotos} className="hidden" />
            </label>
            {previews.length > 0 && (
              <div className="flex gap-2 mt-3 flex-wrap">
                {previews.map((p, i) => (
                  <div key={i} className="relative w-16 h-16 rounded-lg overflow-hidden border border-gray-200 flex-shrink-0">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={p} alt="" className="w-full h-full object-cover" />
                    {i === 0 && photosExistantes.length === 0 && <span className="absolute left-0.5 bottom-0.5 text-[9px] font-bold bg-[#0C5C6C] text-white px-1 rounded">Principale</span>}
                    <button type="button" aria-label="Retirer la photo"
                      onClick={() => { setPreviews(v => v.filter((_, k) => k !== i)); setCroppedBlobs(v => v.filter((_, k) => k !== i)); }}
                      className="absolute top-0.5 right-0.5 w-5 h-5 rounded bg-black/55 text-white text-xs leading-none">×</button>
                  </div>
                ))}
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

          {(type === 'compagnon' || type === 'retraite') && (
            <>
              {cession !== 'don' ? (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">{cession === 'adoption' ? 'Frais d’adoption (€)' : 'Prix (€)'}</label>
                  <input type="number" min="0" value={prix} onChange={e => setPrix(e.target.value)} placeholder={cession === 'adoption' ? '250' : '800'} className={iCls} />
                </div>
              ) : (
                <p className="text-sm text-gray-600 border border-gray-200 rounded-lg px-3 py-2.5">Don : aucun prix n’est demandé.</p>
              )}
            </>
          )}
          {type === 'portee' && cession !== 'don' && (
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-1">{cession === 'adoption' ? 'Frais min / bébé (€)' : 'Prix min / bébé (€)'}</label>
                  <input type="number" min="0" value={prixMin} onChange={e => setPrixMin(e.target.value)} placeholder="500" className={iCls} />
                </div>
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-1">{cession === 'adoption' ? 'Frais max / bébé (€)' : 'Prix max / bébé (€)'}</label>
                  <input type="number" min="0" value={prixMax} onChange={e => setPrixMax(e.target.value)} placeholder="1200" className={iCls} />
                </div>
              </div>
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

          {/* ── Cheval : formule + sport & vidéos ── */}
          {espece === 'Cheval' && type === 'compagnon' && (
            <div className="border border-gray-100 rounded-lg p-4 space-y-3">
              <p className="text-sm font-semibold text-gray-700">Formule</p>
              <div className="grid grid-cols-2 gap-2">
                {([
                  ['vente', 'Vente'], ['location', 'Location'], ['demi_pension', 'Demi-pension'],
                  ['pension_complete', 'Pension complète'], ['valorisation', 'Valorisation'],
                ] as [typeof formuleEquine, string][]).map(([v, l]) => (
                  <button key={v} type="button" onClick={() => selectFormuleEquine(v)}
                    className={`py-2 rounded-lg text-sm font-medium border transition-colors ${
                      formuleEquine === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'
                    }`}>{l}</button>
                ))}
              </div>
              {formuleEquine !== 'vente' && formuleEquine !== 'valorisation' && (
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Cadence du prix</label>
                  <select value={prixUnite} onChange={e => setPrixUnite(e.target.value as typeof prixUnite)} className={iSmCls}>
                    <option value="mois">par mois</option>
                    <option value="semaine">par semaine</option>
                    <option value="convenir">à convenir</option>
                  </select>
                </div>
              )}
              {formuleEquine === 'valorisation' && (
                <p className="text-xs text-gray-500">Valorisation : le prix (rémunération) est optionnel et « à convenir » par défaut.</p>
              )}

              <p className="text-sm font-semibold text-gray-700 pt-2">Niveau et résultats</p>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Niveau recommandé</label>
                <div className="flex flex-wrap gap-2">
                  {['Débutant', 'Galops 1-4', 'Galops 5-7', 'Club', 'Amateur', 'Pro', 'Tous niveaux'].map(n => (
                    <button key={n} type="button" onClick={() => setNiveauEquide(niveauEquide === n ? '' : n)}
                      className={`px-3 py-1.5 rounded-md text-xs font-medium border transition-colors ${
                        niveauEquide === n ? 'border-[#0C5C6C] bg-[#0C5C6C] text-white' : 'border-gray-200 text-gray-600 hover:border-gray-300'
                      }`}>{n}</button>
                  ))}
                </div>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Palmarès / résultats <span className="text-gray-400 font-normal">(optionnel)</span></label>
                <textarea value={palmares} onChange={e => setPalmares(e.target.value)} rows={3}
                  placeholder="Ex : 2e Amateur Elite GP Fontainebleau 2025…" className={`${iSmCls} resize-none`} />
              </div>
              <div className="flex gap-3">
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">ISO</label>
                  <input type="number" value={indiceIso} onChange={e => setIndiceIso(e.target.value)} className={iSmCls} /></div>
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">IDR</label>
                  <input type="number" value={indiceIdr} onChange={e => setIndiceIdr(e.target.value)} className={iSmCls} /></div>
                <div className="flex-1"><label className="block text-xs font-medium text-gray-600 mb-1">ICC</label>
                  <input type="number" value={indiceIcc} onChange={e => setIndiceIcc(e.target.value)} className={iSmCls} /></div>
              </div>

              <p className="text-sm font-semibold text-gray-700 pt-2">Vidéos</p>
              {([['monte', 'Vidéo sous selle', videoMonteUrl] as const, ['libre', 'Vidéo en liberté', videoLibreUrl] as const]).map(([which, label, url]) => (
                <div key={which}>
                  <label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
                  {url ? (
                    <div className="flex items-center gap-2">
                      <video src={url} controls className="w-40 rounded-lg border border-gray-200" />
                      <button type="button" onClick={() => which === 'monte' ? setVideoMonteUrl(null) : setVideoLibreUrl(null)}
                        className="text-xs text-red-500 hover:text-red-700 font-medium">Retirer</button>
                    </div>
                  ) : (
                    <label className="inline-flex items-center gap-2 px-3 py-2 border border-dashed border-gray-300 rounded-lg text-sm text-gray-500 cursor-pointer hover:border-[#0C5C6C] hover:text-[#0C5C6C]">
                      {uploadingVideo === which ? 'Envoi…' : '+ Ajouter une vidéo'}
                      <input type="file" accept="video/*" className="hidden"
                        disabled={uploadingVideo !== null}
                        onChange={e => handleEquideVideo(e, which)} />
                    </label>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* ── Récapitulatif ── */}
          <div className="border border-gray-200 rounded-lg p-4">
            <p className="text-sm font-semibold text-[#1F2A2E] mb-2">Récapitulatif</p>
            <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1.5 text-sm">
              {[
                ['Annonce', type === 'saillie' ? 'Saillie' : `${cession === 'vente' ? 'Vente' : 'Adoption / don'} · ${type === 'portee' ? 'Portée complète' : type === 'retraite' ? 'Retraité d’élevage' : 'Animal individuel'}`],
                ['Animal', [espece === 'Autre' ? especeAutre : espece, race].filter(Boolean).join(' · ') || '—'],
                ['Identification', espece === 'Cheval' ? (numSIRE || '—') : type === 'portee' ? (merePuce ? `Mère : ${merePuce}` : '—') : (numIdentification || '—')],
                ['Prix', type === 'saillie' ? (sailliePrix ? `${sailliePrix} €` : 'Gratuite') : cession === 'don' ? 'Don' : type === 'portee' ? ([prixMin, prixMax].filter(Boolean).join(' – ') || '—') + (prixMin || prixMax ? ' €' : '') : (prix ? `${prix} €` : '—')],
                ['Photos', `${photosExistantes.length + previews.length} / 5`],
                ['Durée de publication', `${(PLAN_CONFIG[planCode] ?? PLAN_CONFIG.free).dureeDays} jours (selon votre abonnement)`],
                ['Mise en avant', 'Depuis Mes annonces, après publication'],
              ].map(([k, v]) => (
                <div key={k} className="flex justify-between gap-3 border-b border-gray-100 py-1">
                  <dt className="text-gray-500">{k}</dt><dd className="font-medium text-[#1F2A2E] text-right truncate">{v}</dd>
                </div>
              ))}
            </dl>
          </div>
          </div>
          {error && <p className="text-red-500 text-sm">{error}</p>}

          <div className="flex items-center justify-between gap-3 pt-4 border-t border-gray-200">
            {etape > 1 ? (
              <button type="button" onClick={() => { setError(''); setEtape(etape - 1); window.scrollTo({ top: 0 }); }}
                className="h-10 px-4 rounded-lg border border-gray-300 text-sm font-semibold text-gray-700 hover:bg-gray-50">
                Précédent
              </button>
            ) : (
              <Link href="/mes-annonces" className="h-10 px-4 rounded-lg border border-gray-300 text-sm font-semibold text-gray-700 hover:bg-gray-50 inline-flex items-center">
                Annuler
              </Link>
            )}
            <div className="flex items-center gap-2">
            <button type="button" onClick={() => enregistrer('brouillon')} disabled={saving}
              className="hidden sm:inline-flex h-10 px-4 items-center rounded-lg border border-[#0C5C6C] text-[#0C5C6C] text-sm font-semibold hover:bg-[#E8F4F6] disabled:opacity-60">
              Enregistrer comme brouillon
            </button>
            {etape < 3 ? (
              <button type="button" onClick={suivant}
                className="h-10 px-5 rounded-lg bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold">
                Suivant
              </button>
            ) : (
              <button type="submit" disabled={saving}
                className="h-10 px-5 rounded-lg bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white text-sm font-semibold">
                {saving ? 'Publication en cours…' : "Publier l'annonce"}
              </button>
            )}
            </div>
          </div>
          <button type="button" onClick={() => enregistrer('brouillon')} disabled={saving}
            className="sm:hidden w-full h-10 rounded-lg border border-[#0C5C6C] text-[#0C5C6C] text-sm font-semibold disabled:opacity-60">
            Enregistrer comme brouillon
          </button>
        </form>
      </div>

      {/* ── Baby edit modal ── */}
      {editingBaby && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 overflow-y-auto py-6 px-4"
          onClick={e => { if (e.target === e.currentTarget) { setEditingBaby(null); setShowBabyPicker(false); } }}>
          <div className="bg-white rounded-xl w-full max-w-lg shadow-xl">
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
                    <label className="cursor-pointer w-20 h-20 border border-dashed border-gray-200 rounded-xl flex flex-col items-center justify-center gap-1 hover:border-[#0C5C6C] hover:text-[#0C5C6C] text-gray-300 transition-colors">
                      <svg className="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" /></svg>
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
                  <svg className="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" d="M21 21l-5.2-5.2m0 0A7.5 7.5 0 105.2 5.2a7.5 7.5 0 0010.6 10.6z" /></svg>
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
                            <span className="text-gray-300 text-xs">—</span>
                          )}
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-gray-800 truncate">{a.nom || 'Sans nom'}</p>
                          <p className="text-xs text-gray-400">{a.sexe === 'femelle' ? 'Femelle' : 'Mâle'}{a.race ? ` · ${a.race}` : ''}</p>
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
                      className={`flex-1 py-2 rounded-lg border text-sm font-medium transition-colors ${editingBaby.sexe === s ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>
                      {s === 'male' ? 'Mâle' : 'Femelle'}
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
                <div className="flex-1"><label className="block text-sm font-medium text-gray-700 mb-1">Couleur des yeux</label>
                  <input value={editingBaby.couleur_yeux}
                    onChange={e => setEditingBaby(p => p ? { ...p, couleur_yeux: e.target.value } : null)}
                    placeholder="Ex: marron…" className={iCls} /></div>
              </div>
              <div className="flex gap-3">
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
                      className={`flex-1 py-2 rounded-lg border text-xs font-semibold transition-colors`}
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
          <div className="bg-white rounded-xl p-6 max-w-sm w-full shadow-xl">
            <div className="text-center mb-5">
              
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
                {quotaBuying ? '…' : 'Annonce supplémentaire — 2,99 €'}
              </button>
              <button
                onClick={() => { setShowQuotaModal(false); router.push('/abonnement'); }}
                className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-3 rounded-xl transition-colors text-sm">
                Passer au plan Pro
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
