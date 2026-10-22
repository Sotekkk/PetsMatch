'use client';

import { enregistrerModificationAnnonce } from '@/lib/annonce-paiement';
import { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { uploadBlob, uploadRawFile } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';
import {
  PageFormulaire, SectionFormulaire, Champ, Colonnes, CaseACocher, InfosVerrouillees, GrillePhotos, classeChamp, styleChamp,
} from '@/components/annonces/FormulaireAnnonce';

const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'Reptile', autre: 'Autre',
};
const TYPE_LABEL: Record<string, string> = {
  compagnon: 'Compagnon', portee: 'Portée', saillie: 'Saillie', retraite: "Retraité d'élevage",
};

function fmtDate(v?: string): string | undefined {
  if (!v) return undefined;
  const d = new Date(v);
  return isNaN(d.getTime()) ? undefined : d.toLocaleDateString('fr-FR', { dateStyle: 'long' });
}

interface RawBabe {
  animalId?: string;
  nom?: string;
  sexe?: string;
  couleur?: string;
  couleur_yeux?: string;
  prix?: number;
  statut?: string;
  photos?: string[];
  isLinked?: boolean;
}

interface AnnonceData {
  id: string;
  uid_eleveur: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  sexe?: string;
  titre?: string;
  description?: string;
  photos?: string[];
  prix?: number;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  couleur?: string;
  couleur_yeux?: string;
  vaccines?: boolean;
  vermifuge?: boolean;
  identification?: boolean;
  bilan_sante?: boolean;
  semaines?: number;
  club_pedigree?: string;
  numero_registre?: string;
  statut?: string;
  animaux_portee?: RawBabe[];
  mere_puce?: string;
  mere_nom?: string;
  pere_puce?: string;
  pere_nom?: string;
  date_naissance?: string;
  date_naissance_animal?: string;
}

interface BabyEdit {
  animalId?: string;
  nom?: string;
  sexe?: string;
  couleur: string;
  couleur_yeux: string;
  prix: string;
  statut: string;
  existingPhotos: string[];
  newBlobs: Blob[];
  newPreviews: string[];
}

export default function ModifierAnnoncePage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const params = useParams();
  const id = params?.id as string;

  const [annonce, setAnnonce] = useState<AnnonceData | null>(null);
  const [fetching, setFetching] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Editable fields
  const [description, setDescription] = useState('');
  const [prix, setPrix] = useState('');
  const [sailliePrix, setSailliePrix] = useState('');
  const [prixMin, setPrixMin] = useState('');
  const [prixMax, setPrixMax] = useState('');
  const [couleur, setCouleur] = useState('');
  const [couleurYeux, setCouleurYeux] = useState('');
  const [vaccines, setVaccines] = useState(false);
  const [vermifuge, setVermifuge] = useState(false);
  const [identification, setIdentification] = useState(false);
  const [bilanSante, setBilanSante] = useState(false);
  const [semaines, setSemaines] = useState(8);
  const [clubPedigree, setClubPedigree] = useState('');
  const [numRegistre, setNumRegistre] = useState('');
  // Cheval — sport & vidéos
  const [prixUnite, setPrixUnite] = useState('total');
  const [niveauEquide, setNiveauEquide] = useState('');
  const [palmares, setPalmares] = useState('');
  const [iso, setIso] = useState(''); const [idr, setIdr] = useState(''); const [icc, setIcc] = useState('');
  const [videoMonteUrl, setVideoMonteUrl] = useState<string | null>(null);
  const [videoLibreUrl, setVideoLibreUrl] = useState<string | null>(null);
  const [uploadingVideo, setUploadingVideo] = useState<'monte' | 'libre' | null>(null);

  // Main annonce photos
  const [existingPhotos, setExistingPhotos] = useState<string[]>([]);
  const [newBlobs, setNewBlobs] = useState<Blob[]>([]);
  const [newPreviews, setNewPreviews] = useState<string[]>([]);

  // Babies (portée)
  const [babies, setBabies] = useState<BabyEdit[]>([]);

  // Crop — shared between main and baby
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [cropQueue, setCropQueue] = useState<File[]>([]);
  const [cropTarget, setCropTarget] = useState<{ type: 'main' | 'baby'; babyIdx?: number }>({ type: 'main' });

  useEffect(() => {
    if (!id) return;
    supabase.from('annonces').select('*').eq('id', id).maybeSingle()
      .then(({ data }) => {
        if (!data) { setFetching(false); return; }
        const a = data as AnnonceData;
        setAnnonce(a);
        setDescription(a.description ?? '');
        setPrix(a.prix != null ? String(a.prix) : '');
        setSailliePrix(a.saillie_prix != null ? String(a.saillie_prix) : '');
        setPrixMin(a.prix_min_portee != null ? String(a.prix_min_portee) : '');
        setPrixMax(a.prix_max_portee != null ? String(a.prix_max_portee) : '');
        setCouleur(a.couleur ?? '');
        setCouleurYeux(a.couleur_yeux ?? '');
        setVaccines(a.vaccines ?? false);
        setVermifuge(a.vermifuge ?? false);
        setIdentification(a.identification ?? false);
        setBilanSante(a.bilan_sante ?? false);
        setSemaines(a.semaines ?? 8);
        setClubPedigree(a.club_pedigree ?? '');
        setNumRegistre(a.numero_registre ?? '');
        setPrixUnite((a as unknown as Record<string, string>).prix_unite ?? 'total');
        setNiveauEquide((a as unknown as Record<string, string>).niveau_recommande ?? '');
        setPalmares((a as unknown as Record<string, string>).palmares ?? '');
        setIso((a as unknown as Record<string, number>).indice_iso != null ? String((a as unknown as Record<string, number>).indice_iso) : '');
        setIdr((a as unknown as Record<string, number>).indice_idr != null ? String((a as unknown as Record<string, number>).indice_idr) : '');
        setIcc((a as unknown as Record<string, number>).indice_icc != null ? String((a as unknown as Record<string, number>).indice_icc) : '');
        setVideoMonteUrl((a as unknown as Record<string, string>).video_monte_url ?? null);
        setVideoLibreUrl((a as unknown as Record<string, string>).video_libre_url ?? null);
        setExistingPhotos((a.photos as unknown as string[]) ?? []);
        if (a.animaux_portee) {
          setBabies(a.animaux_portee.map(b => ({
            animalId: b.animalId,
            nom: b.nom,
            sexe: b.sexe,
            couleur: b.couleur ?? '',
            couleur_yeux: b.couleur_yeux ?? '',
            prix: b.prix != null ? String(b.prix) : '',
            statut: b.statut ?? 'disponible',
            existingPhotos: (b.photos ?? []).filter(Boolean),
            newBlobs: [],
            newPreviews: [],
          })));
        }
        setFetching(false);
      });
  }, [id]);

  useEffect(() => {
    if (!authLoading && !user) router.push('/connexion');
  }, [authLoading, user, router]);

  // ── Photo handlers ──────────────────────────────────────────────────────────

  function startCrop(files: File[], target: typeof cropTarget) {
    if (!files.length) return;
    setCropTarget(target);
    setCropQueue(files.slice(1));
    setCropSrc(URL.createObjectURL(files[0]));
  }

  function handleMainPhotos(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    const remaining = 5 - existingPhotos.length - newBlobs.length;
    if (!files.length || remaining <= 0) return;
    startCrop(files.slice(0, remaining), { type: 'main' });
    e.target.value = '';
  }

  function handleBabyPhotos(babyIdx: number, e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    const b = babies[babyIdx];
    const remaining = 5 - b.existingPhotos.length - b.newBlobs.length;
    if (!files.length || remaining <= 0) return;
    startCrop(files.slice(0, remaining), { type: 'baby', babyIdx });
    e.target.value = '';
  }

  async function handleEquideVideo(e: React.ChangeEvent<HTMLInputElement>, which: 'monte' | 'libre') {
    const f = e.target.files?.[0]; e.target.value = '';
    if (!f || !user) return;
    if (f.size > 60 * 1024 * 1024) { setError('Vidéo trop lourde (max 60 Mo).'); return; }
    setUploadingVideo(which); setError('');
    try {
      const ext = (f.name.split('.').pop() ?? 'mp4').toLowerCase();
      const url = await uploadRawFile(f, `annonces/${user.uid}/video_${which}_${Date.now()}.${ext}`);
      if (which === 'monte') setVideoMonteUrl(url); else setVideoLibreUrl(url);
    } catch {
      setError('Échec de l\'envoi de la vidéo.');
    } finally { setUploadingVideo(null); }
  }

  function handleCropConfirm(blob: Blob) {
    const url = URL.createObjectURL(blob);
    if (cropSrc) URL.revokeObjectURL(cropSrc);

    if (cropTarget.type === 'baby' && cropTarget.babyIdx !== undefined) {
      const idx = cropTarget.babyIdx;
      setBabies(prev => prev.map((b, i) =>
        i === idx ? { ...b, newBlobs: [...b.newBlobs, blob], newPreviews: [...b.newPreviews, url] } : b
      ));
    } else {
      setNewBlobs(prev => [...prev, blob]);
      setNewPreviews(prev => [...prev, url]);
    }

    setCropQueue(prev => {
      if (prev.length > 0) {
        setCropSrc(URL.createObjectURL(prev[0]));
        return prev.slice(1);
      }
      setCropSrc(null);
      return [];
    });
  }

  function handleCropSkip() {
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropQueue(prev => {
      if (prev.length > 0) { setCropSrc(URL.createObjectURL(prev[0])); return prev.slice(1); }
      setCropSrc(null); return [];
    });
  }

  function removeBabyExistingPhoto(babyIdx: number, photoIdx: number) {
    setBabies(prev => prev.map((b, i) =>
      i === babyIdx ? { ...b, existingPhotos: b.existingPhotos.filter((_, j) => j !== photoIdx) } : b
    ));
  }

  function removeBabyNewPhoto(babyIdx: number, photoIdx: number) {
    setBabies(prev => prev.map((b, i) => {
      if (i !== babyIdx) return b;
      URL.revokeObjectURL(b.newPreviews[photoIdx]);
      return {
        ...b,
        newBlobs: b.newBlobs.filter((_, j) => j !== photoIdx),
        newPreviews: b.newPreviews.filter((_, j) => j !== photoIdx),
      };
    }));
  }

  // ── Submit ──────────────────────────────────────────────────────────────────

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!annonce || !user) return;
    if (annonce.uid_eleveur !== user.uid) { setError('Non autorisé'); return; }
    setSaving(true); setError('');
    try {
      // Upload main photos
      const uploadedMain: string[] = [];
      for (const blob of newBlobs)
        uploadedMain.push(await uploadBlob(blob, `annonces/${user.uid}/${Date.now()}.jpg`));
      const allPhotos = [...existingPhotos, ...uploadedMain];

      const isSaillie = annonce.type_vente === 'saillie';
      const isPortee  = annonce.type === 'portee';

      // Upload baby photos and build saved babies
      let savedBabies: RawBabe[] | undefined;
      if (isPortee) {
        savedBabies = [];
        for (const b of babies) {
          const uploadedBaby: string[] = [];
          for (const blob of b.newBlobs)
            uploadedBaby.push(await uploadBlob(blob, `annonces/${user.uid}/bebes/${Date.now()}.jpg`));
          savedBabies.push({
            animalId: b.animalId,
            nom: b.nom,
            sexe: b.sexe,
            couleur: b.couleur || undefined,
            couleur_yeux: b.couleur_yeux || undefined,
            prix: b.prix ? Number(b.prix) : undefined,
            statut: b.statut,
            photos: [...b.existingPhotos, ...uploadedBaby],
            isLinked: !!b.animalId,
          });
        }
      }

      const isEquide = annonce.espece === 'cheval';
      const isEquideFormule = ['location', 'demi_pension', 'pension_complete', 'valorisation'].includes(annonce.type_vente ?? '');

      // Gratuit : photos et disponibilité ; le reste est payant (4,99 €).
      const changementsAnnonce = {
        description: description || null,
        photos: allPhotos,
        couleur: !isPortee ? (couleur || null) : undefined,
        couleur_yeux: !isPortee ? (couleurYeux || null) : undefined,
        vaccines, vermifuge,
        identification, bilan_sante: bilanSante,
        semaines: !isSaillie ? semaines : undefined,
        club_pedigree: clubPedigree || null,
        numero_registre: numRegistre || null,
        ...(isEquide && {
          niveau_recommande: niveauEquide || null,
          palmares: palmares.trim() || null,
          indice_iso: iso ? Number(iso) : null,
          indice_idr: idr ? Number(idr) : null,
          indice_icc: icc ? Number(icc) : null,
          video_monte_url: videoMonteUrl,
          video_libre_url: videoLibreUrl,
        }),
        ...(isEquideFormule && { prix_unite: annonce.type_vente === 'vente' ? null : prixUnite }),
        ...(isSaillie  && { saillie_prix: sailliePrix ? parseFloat(sailliePrix) : null }),
        ...(!isSaillie && !isPortee && { prix: prix ? Number(prix) : null }),
        ...(isPortee   && {
          prix_min_portee: prixMin ? Number(prixMin) : null,
          prix_max_portee: prixMax ? Number(prixMax) : null,
          animaux_portee: savedBabies,
        }),
      };
      const applique = await enregistrerModificationAnnonce('annonces', id, JSON.parse(JSON.stringify(changementsAnnonce)));
      if (!applique) { setSaving(false); return; }

      router.push('/mes-annonces');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur lors de la sauvegarde');
    } finally { setSaving(false); }
  }

  if (authLoading || fetching) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }
  if (!annonce) {
    return <div className="text-center py-20 text-gray-400">Annonce introuvable.</div>;
  }
  if (annonce.uid_eleveur !== user?.uid) {
    return <div className="text-center py-20 text-gray-400">Accès non autorisé.</div>;
  }

  const isSaillie = annonce.type_vente === 'saillie';
  const isPortee  = annonce.type === 'portee';
  const isCheval = annonce.espece === 'cheval';
  const photosGrille = [
    ...existingPhotos.map((url, i) => ({ url, cle: `e${i}${url}` })),
    ...newPreviews.map((url, i) => ({ url, cle: `n${i}${url}` })),
  ];
  const majBebe = (idx: number, champ: Partial<BabyEdit>) =>
    setBabies(prev => prev.map((x, i) => i === idx ? { ...x, ...champ } : x));

  return (
    <>
    <PageFormulaire retourHref="/mes-annonces" titre="Modifier l’annonce"
      sousTitre="Les informations d’identité de l’annonce ne peuvent pas être modifiées."
      erreur={error} onSubmit={handleSubmit} annulerHref="/mes-annonces" enregistrement={saving}>

      {/* Informations principales (non modifiables) */}
      <InfosVerrouillees lignes={[
        { label: 'Type', valeur: TYPE_LABEL[annonce.type_vente ?? annonce.type ?? ''] ?? annonce.type_vente ?? annonce.type },
        { label: 'Titre', valeur: annonce.titre },
        { label: 'Espèce', valeur: ESPECE_LABEL[annonce.espece ?? ''] ?? annonce.espece },
        { label: 'Race', valeur: annonce.race },
        { label: 'Sexe', valeur: annonce.sexe ? (annonce.sexe === 'male' ? 'Mâle' : 'Femelle') : null },
        { label: 'Naissance', valeur: fmtDate(annonce.type === 'portee' ? annonce.date_naissance : annonce.date_naissance_animal) ?? 'non renseignée' },
      ]} />

      {/* Photos et médias */}
      <SectionFormulaire titre="Photos et médias" description="La première photo est la photo principale de l’annonce.">
        <GrillePhotos photos={photosGrille} max={5} onAjouter={handleMainPhotos}
          onRetirer={i => {
            if (i < existingPhotos.length) { setExistingPhotos(prev => prev.filter((_, j) => j !== i)); return; }
            const k = i - existingPhotos.length;
            URL.revokeObjectURL(newPreviews[k]);
            setNewBlobs(prev => prev.filter((_, j) => j !== k));
            setNewPreviews(prev => prev.filter((_, j) => j !== k));
          }} />
        {isCheval && (
          <Colonnes>
            {([['monte', 'Vidéo sous selle', videoMonteUrl] as const, ['libre', 'Vidéo en liberté', videoLibreUrl] as const]).map(([which, label, url]) => (
              <Champ key={which} label={label} aide="Fichier vidéo, 60 Mo maximum.">
                {url ? (
                  <div className="flex items-center gap-3">
                    <video src={url} controls className="w-48 rounded-xl" style={styleChamp} />
                    <button type="button" onClick={() => which === 'monte' ? setVideoMonteUrl(null) : setVideoLibreUrl(null)}
                      className="text-sm font-semibold text-[#B91C1C] hover:underline">Retirer</button>
                  </div>
                ) : (
                  <label className="min-h-11 inline-flex items-center gap-2 px-4 rounded-xl border border-dashed text-sm font-semibold text-gray-600 cursor-pointer hover:border-[#0C5C6C] hover:text-[#0C5C6C]" style={styleChamp}>
                    {uploadingVideo === which ? 'Envoi…' : 'Ajouter une vidéo'}
                    <input type="file" accept="video/*" className="hidden" disabled={uploadingVideo !== null}
                      onChange={e => handleEquideVideo(e, which)} />
                  </label>
                )}
              </Champ>
            ))}
          </Colonnes>
        )}
      </SectionFormulaire>

      {/* Description */}
      <SectionFormulaire titre="Description">
        <Champ label="Présentation" htmlFor="description">
          <textarea id="description" className={`${classeChamp} resize-y`} style={styleChamp} rows={5}
            value={description} onChange={e => setDescription(e.target.value)} placeholder="Présentez votre annonce…" />
        </Champ>
      </SectionFormulaire>

      {/* Caractéristiques et renseignements spécifiques */}
      <SectionFormulaire titre="Caractéristiques et santé">
        {!isPortee && (
          <Colonnes>
            <Champ label="Couleur / robe" htmlFor="couleur">
              <input id="couleur" className={classeChamp} style={styleChamp} value={couleur} onChange={e => setCouleur(e.target.value)} />
            </Champ>
            <Champ label="Couleur des yeux" htmlFor="yeux">
              <input id="yeux" className={classeChamp} style={styleChamp} value={couleurYeux} onChange={e => setCouleurYeux(e.target.value)} />
            </Champ>
          </Colonnes>
        )}
        <div>
          <p className="text-sm font-semibold text-[#1E2025] mb-1">Santé et conformité</p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6">
            <CaseACocher label="Vacciné(s)" checked={vaccines} onChange={setVaccines} />
            <CaseACocher label="Vermifugé(s)" checked={vermifuge} onChange={setVermifuge} />
            <CaseACocher label="Identifié(s)" checked={identification} onChange={setIdentification} />
            <CaseACocher label="Bilan de santé" checked={bilanSante} onChange={setBilanSante} />
          </div>
        </div>
        {!isSaillie && (
          <Champ label={`Âge au départ : ${semaines} semaines`} htmlFor="semaines" aide="Entre 8 et 26 semaines.">
            <input id="semaines" type="range" min={8} max={26} value={semaines} onChange={e => setSemaines(Number(e.target.value))}
              className="w-full accent-[#0C5C6C]" />
          </Champ>
        )}
        <Colonnes>
          <Champ label="Club / registre pedigree" htmlFor="club">
            <input id="club" className={classeChamp} style={styleChamp} value={clubPedigree} onChange={e => setClubPedigree(e.target.value)} />
          </Champ>
          <Champ label="N° registre / LOF" htmlFor="registre">
            <input id="registre" className={classeChamp} style={styleChamp} value={numRegistre} onChange={e => setNumRegistre(e.target.value)} />
          </Champ>
        </Colonnes>
        {isCheval && (
          <>
            <Champ label="Niveau recommandé">
              <div className="flex flex-wrap gap-2">
                {['Débutant', 'Galops 1-4', 'Galops 5-7', 'Club', 'Amateur', 'Pro', 'Tous niveaux'].map(n => (
                  <button key={n} type="button" onClick={() => setNiveauEquide(niveauEquide === n ? '' : n)} aria-pressed={niveauEquide === n}
                    className={`min-h-10 px-3.5 rounded-xl text-sm font-semibold border transition-colors ${niveauEquide === n ? 'border-[#0C5C6C] bg-[#0C5C6C] text-white' : 'bg-white text-gray-700 hover:border-[#0C5C6C]/50'}`}
                    style={niveauEquide === n ? undefined : styleChamp}>{n}</button>
                ))}
              </div>
            </Champ>
            <Champ label="Palmarès / résultats" htmlFor="palmares" aide="Facultatif.">
              <textarea id="palmares" className={`${classeChamp} resize-y`} style={styleChamp} rows={3} value={palmares} onChange={e => setPalmares(e.target.value)} />
            </Champ>
            <div className="grid grid-cols-3 gap-3">
              <Champ label="ISO" htmlFor="iso"><input id="iso" type="number" className={classeChamp} style={styleChamp} value={iso} onChange={e => setIso(e.target.value)} /></Champ>
              <Champ label="IDR" htmlFor="idr"><input id="idr" type="number" className={classeChamp} style={styleChamp} value={idr} onChange={e => setIdr(e.target.value)} /></Champ>
              <Champ label="ICC" htmlFor="icc"><input id="icc" type="number" className={classeChamp} style={styleChamp} value={icc} onChange={e => setIcc(e.target.value)} /></Champ>
            </div>
          </>
        )}
      </SectionFormulaire>

      {/* Prix et conditions */}
      <SectionFormulaire titre="Prix et conditions">
        {isSaillie && (
          <Champ label="Prix de saillie (€)" htmlFor="saillie">
            <input id="saillie" type="number" min="0" inputMode="decimal" className={classeChamp} style={styleChamp} value={sailliePrix} onChange={e => setSailliePrix(e.target.value)} />
          </Champ>
        )}
        {isPortee && (
          <Colonnes>
            <Champ label="Prix minimum (€)" htmlFor="pmin">
              <input id="pmin" type="number" min="0" inputMode="decimal" className={classeChamp} style={styleChamp} value={prixMin} onChange={e => setPrixMin(e.target.value)} />
            </Champ>
            <Champ label="Prix maximum (€)" htmlFor="pmax">
              <input id="pmax" type="number" min="0" inputMode="decimal" className={classeChamp} style={styleChamp} value={prixMax} onChange={e => setPrixMax(e.target.value)} />
            </Champ>
          </Colonnes>
        )}
        {!isSaillie && !isPortee && (
          <Colonnes>
            <Champ label="Prix (€)" htmlFor="prix">
              <input id="prix" type="number" min="0" inputMode="decimal" className={classeChamp} style={styleChamp} value={prix} onChange={e => setPrix(e.target.value)} />
            </Champ>
            {isCheval && ['location', 'demi_pension', 'pension_complete'].includes(annonce.type_vente ?? '') && (
              <Champ label="Cadence du prix" htmlFor="cadence">
                <select id="cadence" className={classeChamp} style={styleChamp} value={prixUnite} onChange={e => setPrixUnite(e.target.value)}>
                  <option value="mois">par mois</option>
                  <option value="semaine">par semaine</option>
                  <option value="convenir">à convenir</option>
                </select>
              </Champ>
            )}
          </Colonnes>
        )}
      </SectionFormulaire>

      {/* Bébés de la portée */}
      {isPortee && babies.length > 0 && (
        <SectionFormulaire titre="Bébés de la portée" description="Le nom et le sexe des bébés ne sont pas modifiables.">
          {babies.map((b, babyIdx) => (
            <div key={babyIdx} className="rounded-xl p-3 sm:p-4 space-y-3" style={{ border: `1px solid ${styleChamp.borderColor}` }}>
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-[15px] font-bold text-[#1E2025]">{b.nom || `Bébé ${babyIdx + 1}`}</span>
                {b.sexe && <span className="text-xs font-semibold text-gray-600 bg-[#F3F6F5] px-2 py-0.5 rounded-full">{b.sexe === 'male' ? 'Mâle' : 'Femelle'}</span>}
              </div>
              <GrillePhotos max={5}
                photos={[...b.existingPhotos.map((url, i) => ({ url, cle: `e${i}${url}` })), ...b.newPreviews.map((url, i) => ({ url, cle: `n${i}${url}` }))]}
                onAjouter={e => handleBabyPhotos(babyIdx, e)}
                onRetirer={i => i < b.existingPhotos.length ? removeBabyExistingPhoto(babyIdx, i) : removeBabyNewPhoto(babyIdx, i - b.existingPhotos.length)} />
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                <Champ label="Couleur"><input className={classeChamp} style={styleChamp} value={b.couleur} onChange={e => majBebe(babyIdx, { couleur: e.target.value })} placeholder="Ex : fauve" /></Champ>
                <Champ label="Couleur des yeux"><input className={classeChamp} style={styleChamp} value={b.couleur_yeux} onChange={e => majBebe(babyIdx, { couleur_yeux: e.target.value })} placeholder="Ex : marron" /></Champ>
                <Champ label="Prix (€)"><input type="number" min="0" inputMode="decimal" className={classeChamp} style={styleChamp} value={b.prix} onChange={e => majBebe(babyIdx, { prix: e.target.value })} /></Champ>
                <Champ label="Statut">
                  <select className={classeChamp} style={styleChamp} value={b.statut} onChange={e => majBebe(babyIdx, { statut: e.target.value })}>
                    <option value="disponible">Disponible</option>
                    <option value="reserve">Réservé</option>
                    <option value="vendu">Vendu</option>
                  </select>
                </Champ>
              </div>
            </div>
          ))}
        </SectionFormulaire>
      )}

      {/* Parents (renseignés à la création, non modifiables) */}
      {(annonce.mere_nom || annonce.mere_puce || annonce.pere_nom || annonce.pere_puce) && (
        <InfosVerrouillees titre="Parents" lignes={[
          { label: 'Père', valeur: annonce.pere_nom },
          { label: 'Puce du père', valeur: annonce.pere_puce },
          { label: 'Mère', valeur: annonce.mere_nom },
          { label: 'Puce de la mère', valeur: annonce.mere_puce },
        ]} />
      )}
    </PageFormulaire>

    {cropSrc && (
      <ImageCropModal
        src={cropSrc}
        onConfirm={handleCropConfirm}
        onCancel={handleCropSkip}
      />
    )}
    </>
  );
}
