'use client';

import { bornesNaissanceAnimal, erreurNaissanceAnimal } from '@/lib/ages-plausibles';
import { enregistrerModificationAnnonce } from '@/lib/annonce-paiement';
import { Suspense, useCallback, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import {
  PageFormulaire, SectionFormulaire, Champ, Colonnes, CaseACocher, GrillePhotos, classeChamp, styleChamp,
} from '@/components/annonces/FormulaireAnnonce';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { uploadBlob, uploadRawFile } from '@/lib/upload-media';
import { fromPostalCode } from '@/lib/french-geo';
import ImageCropModal from '@/components/ImageCropModal';
import { apiFetch } from '@/lib/api-fetch';

type Formule = 'vente' | 'location' | 'demi_pension' | 'pension_complete' | 'valorisation';
type Cadence = 'total' | 'mois' | 'semaine' | 'convenir';

const FORMULES: [Formule, string][] = [
  ['vente', 'Vente'], ['location', 'Location'], ['demi_pension', 'Demi-pension'],
  ['pension_complete', 'Pension complète'], ['valorisation', 'Valorisation'],
];
const NIVEAUX = ['Débutant', 'Galops 1-4', 'Galops 5-7', 'Club', 'Amateur', 'Pro', 'Tous niveaux'];
const MAX_PHOTOS = 4;

function genId(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

interface MyHorse {
  id: string; nom: string | null; race: string | null; sexe: string | null; sterilise: boolean | null;
  couleur: string | null; couleur_yeux: string | null; date_naissance: string | null; num_sire: string | null; photo_url: string | null;
}

function CreerAnnonceChevalInner() {
  const { user, loading, activeProfileId } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const editId = searchParams.get('edit');

  const [formule, setFormule] = useState<Formule>('vente');
  const [prixUnite, setPrixUnite] = useState<Cadence>('total');
  const [titre, setTitre] = useState('');
  const [race, setRace] = useState('');
  const [breeds, setBreeds] = useState<string[]>([]);
  const [sexe, setSexe] = useState<'jument' | 'hongre' | 'entier'>('hongre');
  const [robe, setRobe] = useState('');
  const [couleurYeux, setCouleurYeux] = useState('');
  const [dateNaissance, setDateNaissance] = useState('');
  const [prix, setPrix] = useState('');
  const [prixNegociable, setPrixNegociable] = useState(false);
  const [numSIRE, setNumSIRE] = useState('');
  const [niveau, setNiveau] = useState('');
  const [palmares, setPalmares] = useState('');
  const [iso, setIso] = useState(''); const [idr, setIdr] = useState(''); const [icc, setIcc] = useState('');
  const [description, setDescription] = useState('');

  const [croppedBlobs, setCroppedBlobs] = useState<Blob[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [existingPhotos, setExistingPhotos] = useState<string[]>([]);
  const [cropQueue, setCropQueue] = useState<File[]>([]);
  const [cropSrc, setCropSrc] = useState<string | null>(null);

  const [videoMonteUrl, setVideoMonteUrl] = useState<string | null>(null);
  const [videoLibreUrl, setVideoLibreUrl] = useState<string | null>(null);
  const [uploadingVideo, setUploadingVideo] = useState<'monte' | 'libre' | null>(null);

  const [myHorses, setMyHorses] = useState<MyHorse[]>([]);
  const [showPicker, setShowPicker] = useState(false);
  const [linkedId, setLinkedId] = useState<string | null>(null);
  const [linkedNom, setLinkedNom] = useState<string | null>(null);

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [erreurs, setErreurs] = useState<Record<string, string>>({});
  // Statut de paiement de l'annonce en cours d'édition ('paye' = déjà publiée
  // et payée → édition simple ; sinon on (re)passe par le paiement).
  const [paiementStatut, setPaiementStatut] = useState<string | null>(null);


  useEffect(() => {
    fetch('/breeds/horse_breeds.json').then(r => r.json()).then(d => setBreeds(d as string[])).catch(() => setBreeds([]));
  }, []);

  const loadMyHorses = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.from('animaux')
      .select('id, nom, race, sexe, sterilise, couleur, couleur_yeux, date_naissance, num_sire, photo_url, espece')
      .or(`uid_eleveur.eq.${user.uid},uid_acquereur.eq.${user.uid}`);
    setMyHorses(((data ?? []) as Record<string, unknown>[])
      .filter(a => a.espece === 'cheval')
      .map(a => a as unknown as MyHorse));
  }, [user]);

  // Édition : recharger l'annonce
  useEffect(() => {
    if (!editId || !user) return;
    (async () => {
      const { data } = await supabase.from('annonces').select('*').eq('id', editId).maybeSingle();
      if (!data) return;
      setFormule((data.type_vente as Formule) ?? 'vente');
      setPrixUnite((data.prix_unite as Cadence) ?? 'total');
      setTitre(data.titre ?? '');
      setRace(data.race ?? '');
      setSexe((['jument', 'hongre', 'entier'].includes(data.sexe) ? data.sexe : 'hongre'));
      setRobe(data.couleur ?? '');
      setCouleurYeux(data.couleur_yeux ?? '');
      setDateNaissance(data.date_naissance_animal ? String(data.date_naissance_animal).slice(0, 10) : '');
      setPrix(data.prix != null ? String(data.prix) : '');
      setPrixNegociable(!!data.prix_negociable);
      setNumSIRE(data.num_sire ?? '');
      setNiveau(data.niveau_recommande ?? '');
      setPalmares(data.palmares ?? '');
      setIso(data.indice_iso != null ? String(data.indice_iso) : '');
      setIdr(data.indice_idr != null ? String(data.indice_idr) : '');
      setIcc(data.indice_icc != null ? String(data.indice_icc) : '');
      setDescription(data.description ?? '');
      setExistingPhotos((data.photos as string[]) ?? []);
      setVideoMonteUrl(data.video_monte_url ?? null);
      setVideoLibreUrl(data.video_libre_url ?? null);
      setLinkedId(data.animal_id ?? null);
      setPaiementStatut((data.paiement_statut as string | null) ?? null);
    })();
  }, [editId, user]);

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  if (!user) { router.push('/connexion'); return null; }

  function selectFormule(v: Formule) {
    setFormule(v);
    setPrixUnite(v === 'location' || v === 'demi_pension' || v === 'pension_complete' ? 'mois'
      : v === 'valorisation' ? 'convenir' : 'total');
  }

  function pickHorse(h: MyHorse) {
    setLinkedId(h.id); setLinkedNom(h.nom); setShowPicker(false);
    if (!race && h.race) setRace(h.race);
    if (!robe && h.couleur) setRobe(h.couleur);
    if (!couleurYeux && h.couleur_yeux) setCouleurYeux(h.couleur_yeux);
    if (!numSIRE && h.num_sire) setNumSIRE(h.num_sire);
    // La fiche animal générique ne connaît que 'male'/'femelle' (pas de
    // notion équine hongre/entier/jument) — on traduit à partir de ça + du
    // champ stérilisé déjà suivi pour la reproduction : un mâle non
    // stérilisé est entier, un mâle stérilisé est hongre.
    if (h.sexe === 'jument' || h.sexe === 'hongre' || h.sexe === 'entier') setSexe(h.sexe as typeof sexe);
    else if (h.sexe === 'femelle') setSexe('jument');
    else if (h.sexe === 'male') setSexe(h.sterilise ? 'hongre' : 'entier');
    if (!dateNaissance && h.date_naissance) setDateNaissance(String(h.date_naissance).slice(0, 10));
    if (!titre && h.nom) setTitre(h.nom);
  }

  function handlePhotos(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    e.target.value = '';
    const room = MAX_PHOTOS - (existingPhotos.length + croppedBlobs.length);
    if (room <= 0 || !files.length) return;
    const take = files.slice(0, room);
    setCropQueue(take.slice(1));
    setCropSrc(URL.createObjectURL(take[0]));
  }
  function handleCropConfirm(blob: Blob) {
    setCroppedBlobs(p => [...p, blob]);
    setPreviews(p => [...p, URL.createObjectURL(blob)]);
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropQueue(q => {
      if (q.length) { setCropSrc(URL.createObjectURL(q[0])); return q.slice(1); }
      setCropSrc(null); return [];
    });
  }

  async function handleVideo(e: React.ChangeEvent<HTMLInputElement>, which: 'monte' | 'libre') {
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
    } finally { setUploadingVideo(null); }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setError('');
    const priced = formule !== 'valorisation';
    const erreurDate = erreurNaissanceAnimal(dateNaissance, 'cheval');
    const ec: Record<string, string> = {};
    if (!titre.trim()) ec.titre = 'Un titre est requis.';
    if (erreurDate) ec.naissance = erreurDate;
    if (numSIRE.trim().length < 6) ec.sire = 'Le n° SIRE est obligatoire (Décret 2013-879).';
    if (existingPhotos.length + croppedBlobs.length === 0) ec.photos = 'Ajoutez au moins une photo.';
    if (priced && prixUnite !== 'convenir' && (!prix || isNaN(Number(prix)))) ec.prix = 'Indiquez un prix (ou passez en « à convenir »).';
    setErreurs(ec);
    const premiere = Object.values(ec)[0];
    if (premiere) { setError(premiere); return; }
    setSaving(true);
    try {
      const pid = activeProfileId || null;

      // Chaque annonce est payante → plafond souple à 10 actives.
      const dejaPayee = editId != null && paiementStatut === 'paye';
      if (!editId) {
        const { count } = await supabase.from('annonces')
          .select('id', { count: 'exact', head: true })
          .eq('uid_eleveur', user!.uid).eq('profil_source', 'particulier')
          .in('statut', ['disponible', 'reserve']);
        if ((count ?? 0) >= 10) { setError('Limite de 10 annonces actives atteinte.'); setSaving(false); return; }
      }

      // Profil particulier actif → géo + nom
      const q = supabase.from('user_profiles_complet')
        .select('firstname, lastname, nom, ville, code_postal, departement, region, pays');
      const { data: u } = pid
        ? await q.eq('id', pid).maybeSingle()
        : await q.eq('uid', user!.uid).eq('is_main', true).maybeSingle();
      const row = (u ?? {}) as Record<string, string | null>;
      const nom = `${row.firstname ?? ''} ${row.lastname ?? ''}`.trim() || (row.nom ?? 'Particulier');
      const cp = (row.code_postal as string) ?? '';
      const geo = fromPostalCode(cp);
      const dep = (row.departement as string) || geo?.departement || '';
      const region = (row.region as string) || geo?.region || '';

      const newUrls: string[] = [];
      for (const b of croppedBlobs) newUrls.push(await uploadBlob(b, `annonces/${user!.uid}/${Date.now()}_${newUrls.length}.jpg`));
      const photos = [...existingPhotos, ...newUrls];

      const prixNum = priced && prixUnite !== 'convenir' ? Number(prix) : null;
      const suspect: string[] = [];
      if (formule === 'vente') {
        if (prixNum && prixNum > 0 && prixNum < 800) suspect.push('prix_tres_bas');
        if (prixNum && prixNum > 150000) suspect.push('prix_tres_eleve');
        const txt = `${titre} ${description}`.toLowerCase();
        for (const w of ['bitcoin', 'crypto', 'western union', 'mandat cash', 'paypal friends'])
          if (txt.includes(w)) suspect.push(`mot_suspect:${w}`);
      }

      const payload = {
        uid_eleveur: user!.uid,
        ...(pid ? { profile_id: pid } : {}),
        nom_eleveur: nom,
        ville_eleveur: (row.ville as string) ?? '',
        departement_eleveur: dep, region_eleveur: region,
        pays_eleveur: (row.pays as string) ?? 'France',
        profil_source: 'particulier',
        type: 'animal',
        type_vente: formule,
        espece: 'cheval',
        race: race.trim(),
        titre: titre.trim(),
        description: description.trim(),
        photos,
        prix: prixNum,
        prix_unite: formule === 'vente' ? null : prixUnite,
        prix_negociable: prixNegociable,
        // Publiée seulement si déjà payée ; sinon brouillon jusqu'au paiement web.
        statut: dejaPayee ? 'disponible' : 'brouillon',
        paiement_statut: dejaPayee ? 'paye' : 'attente',
        sexe,
        couleur: robe.trim() || null,
        couleur_yeux: couleurYeux.trim() || null,
        date_naissance_animal: dateNaissance || null,
        num_sire: numSIRE.trim(),
        niveau_recommande: niveau || null,
        palmares: palmares.trim() || null,
        indice_iso: iso ? Number(iso) : null,
        indice_idr: idr ? Number(idr) : null,
        indice_icc: icc ? Number(icc) : null,
        video_monte_url: videoMonteUrl,
        video_libre_url: videoLibreUrl,
        animal_id: linkedId,
        is_suspect: suspect.length > 0,
        suspect_reasons: suspect,
        updated_at: new Date().toISOString(),
      };

      let annonceId = editId;
      if (editId) {
        // Brouillon : tout ; publiée : photos / disponibilité gratuites, le reste payant.
        const applique = await enregistrerModificationAnnonce('annonces', editId, JSON.parse(JSON.stringify(payload)));
        if (!applique) { setSaving(false); return; }
      } else {
        annonceId = genId();
        const { error: e2 } = await supabase.from('annonces').insert({
          ...payload,
          id: annonceId,
          created_at: new Date().toISOString(),
          expires_at: new Date(Date.now() + 60 * 86400000).toISOString(),
          vues: 0, contacts: 0,
        });
        if (e2) throw new Error(e2.message);
      }

      // Annonce déjà payée en édition → simple mise à jour, on reste sur place.
      if (dejaPayee) { router.push('/mes-annonces'); return; }

      // Sinon : paiement obligatoire pour publier (Stripe Checkout).
      const res = await apiFetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid: user!.uid, email: user!.email ?? '',
          produit_code: 'annonce_cheval_particulier',
          annonce_id: annonceId, returnPath: '/mes-annonces',
        }),
      });
      const json = await res.json();
      if (!res.ok || !json.url) {
        throw new Error(json.error ?? 'Paiement indisponible pour le moment.');
      }
      window.location.href = json.url as string;
      return;
    } catch (err) {
      setError(`Erreur : ${err instanceof Error ? err.message : String(err)}`);
    } finally { setSaving(false); }
  }

  const showCadence = formule === 'location' || formule === 'demi_pension' || formule === 'pension_complete';

  const choix = (actif: boolean) => `min-h-10 px-3.5 rounded-xl text-sm font-semibold border transition-colors ${actif ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-700 hover:border-[#0C5C6C]/50'}`;

  return (
    <>
    <PageFormulaire retourHref="/mes-annonces" titre={editId ? 'Modifier l’annonce' : 'Annonce cheval'}
      sousTitre="Les champs marqués d’un astérisque sont obligatoires."
      erreur={error} onSubmit={handleSubmit} annulerHref="/mes-annonces" enregistrement={saving}
      libelleEnregistrer={paiementStatut === 'paye' ? 'Enregistrer les modifications' : 'Payer et publier — 4,99 €'}>

      <SectionFormulaire titre="Informations principales">
        <Champ label="Formule">
          <div className="flex flex-wrap gap-2">
            {FORMULES.map(([v, l]) => (
              <button key={v} type="button" onClick={() => selectFormule(v)} aria-pressed={formule === v}
                className={choix(formule === v)} style={formule === v ? undefined : styleChamp}>{l}</button>
            ))}
          </div>
        </Champ>
        <div className="relative">
          <Champ label="Mon cheval" aide="Facultatif : relie l’annonce à la fiche de votre cheval.">
            <button type="button"
              onClick={async () => { if (!showPicker) await loadMyHorses(); setShowPicker(!showPicker); }}
              className="min-h-11 w-full rounded-xl text-sm font-semibold text-[#0C5C6C] bg-white hover:bg-[#E8F4F6] text-left px-3.5"
              style={{ border: '1px solid rgba(12,92,108,0.45)' }}>
              {linkedNom ? `Lié : ${linkedNom}` : 'Lier un de mes chevaux'}
            </button>
          </Champ>
          {showPicker && (
            <div className="absolute z-20 left-0 right-0 mt-1 bg-white rounded-xl shadow-lg max-h-56 overflow-y-auto" style={styleChamp}>
              {myHorses.length === 0
                ? <p className="text-sm text-gray-500 text-center py-4">Aucun cheval : saisie libre ci-dessous.</p>
                : myHorses.map(h => (
                  <button key={h.id} type="button" onClick={() => pickHorse(h)}
                    className="w-full text-left px-3.5 py-2.5 hover:bg-[#F3F6F5]">
                    <p className="text-sm font-semibold text-[#1E2025]">{h.nom || 'Sans nom'}</p>
                    {h.race && <p className="text-xs text-gray-500">{h.race}</p>}
                  </button>
                ))}
            </div>
          )}
        </div>
        <Champ label="Titre" requis htmlFor="titre" erreur={erreurs.titre}>
          <input id="titre" value={titre} onChange={e => setTitre(e.target.value)} placeholder="Ex : Jument PS, 8 ans, prête club 1" className={classeChamp} style={styleChamp} />
        </Champ>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Champ label="Race" htmlFor="race">
            <input id="race" value={race} onChange={e => setRace(e.target.value)} list="horse-breeds" placeholder="Selle Français, PS…" className={classeChamp} style={styleChamp} />
            <datalist id="horse-breeds">{breeds.map(b => <option key={b} value={b} />)}</datalist>
          </Champ>
          <Champ label="Sexe" htmlFor="sexe">
            <select id="sexe" value={sexe} onChange={e => setSexe(e.target.value as typeof sexe)} className={classeChamp} style={styleChamp}>
              <option value="jument">Jument</option>
              <option value="hongre">Hongre</option>
              <option value="entier">Entier</option>
            </select>
          </Champ>
          <Champ label="Date de naissance" htmlFor="naissance" erreur={erreurs.naissance}>
            <input id="naissance" type="date" value={dateNaissance} onChange={e => setDateNaissance(e.target.value)} className={classeChamp} style={styleChamp}
              min={bornesNaissanceAnimal('cheval').min} max={bornesNaissanceAnimal('cheval').max} />
          </Champ>
        </div>
      </SectionFormulaire>

      <SectionFormulaire titre="Photos et médias">
        <Champ label="Photos" requis erreur={erreurs.photos} aide={`Jusqu’à ${MAX_PHOTOS} photos, recadrées au format carré.`}>
          <GrillePhotos max={MAX_PHOTOS}
            photos={[...existingPhotos.map((u, i) => ({ url: u, cle: `e${i}${u}` })), ...previews.map((u, i) => ({ url: u, cle: `n${i}` }))]}
            onAjouter={handlePhotos}
            onRetirer={i => {
              if (i < existingPhotos.length) { setExistingPhotos(prev => prev.filter((_, j) => j !== i)); return; }
              const k = i - existingPhotos.length;
              setCroppedBlobs(prev => prev.filter((_, j) => j !== k));
              setPreviews(prev => prev.filter((_, j) => j !== k));
            }} />
        </Champ>
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
                    onChange={e => handleVideo(e, which)} />
                </label>
              )}
            </Champ>
          ))}
        </Colonnes>
      </SectionFormulaire>

      <SectionFormulaire titre="Description">
        <Champ label="Présentation" htmlFor="description">
          <textarea id="description" value={description} onChange={e => setDescription(e.target.value)} rows={5}
            placeholder="Caractère, aptitudes, conditions…" className={`${classeChamp} resize-y`} style={styleChamp} />
        </Champ>
      </SectionFormulaire>

      <SectionFormulaire titre="Caractéristiques et identification">
        <Colonnes>
          <Champ label="Robe" htmlFor="robe">
            <input id="robe" value={robe} onChange={e => setRobe(e.target.value)} placeholder="Bai, alezan…" className={classeChamp} style={styleChamp} />
          </Champ>
          <Champ label="Couleur des yeux" htmlFor="yeux">
            <input id="yeux" value={couleurYeux} onChange={e => setCouleurYeux(e.target.value)} placeholder="Marron, bleu…" className={classeChamp} style={styleChamp} />
          </Champ>
        </Colonnes>
        <Champ label="Numéro SIRE" requis htmlFor="sire" erreur={erreurs.sire} aide="Obligatoire pour tout équidé (décret n° 2013-879).">
          <input id="sire" value={numSIRE} onChange={e => setNumSIRE(e.target.value)} placeholder="250 00X XXX XXX XXX" className={classeChamp} style={styleChamp} />
        </Champ>
        <Champ label="Niveau recommandé">
          <div className="flex flex-wrap gap-2">
            {NIVEAUX.map(n => (
              <button key={n} type="button" onClick={() => setNiveau(niveau === n ? '' : n)} aria-pressed={niveau === n}
                className={choix(niveau === n)} style={niveau === n ? undefined : styleChamp}>{n}</button>
            ))}
          </div>
        </Champ>
        <Champ label="Palmarès / résultats" htmlFor="palmares" aide="Facultatif.">
          <textarea id="palmares" value={palmares} onChange={e => setPalmares(e.target.value)} rows={3} className={`${classeChamp} resize-y`} style={styleChamp} />
        </Champ>
        <div className="grid grid-cols-3 gap-3">
          <Champ label="ISO" htmlFor="iso"><input id="iso" type="number" value={iso} onChange={e => setIso(e.target.value)} className={classeChamp} style={styleChamp} /></Champ>
          <Champ label="IDR" htmlFor="idr"><input id="idr" type="number" value={idr} onChange={e => setIdr(e.target.value)} className={classeChamp} style={styleChamp} /></Champ>
          <Champ label="ICC" htmlFor="icc"><input id="icc" type="number" value={icc} onChange={e => setIcc(e.target.value)} className={classeChamp} style={styleChamp} /></Champ>
        </div>
      </SectionFormulaire>

      {formule !== 'valorisation' && (
        <SectionFormulaire titre="Prix et conditions">
          <Colonnes>
            <Champ label="Prix (€)" requis={prixUnite !== 'convenir'} htmlFor="prix" erreur={erreurs.prix}>
              <input id="prix" type="number" min="0" inputMode="decimal" value={prix} onChange={e => setPrix(e.target.value)}
                disabled={prixUnite === 'convenir'} placeholder={prixUnite === 'convenir' ? 'À convenir' : '800'} className={`${classeChamp} disabled:bg-gray-50`} style={styleChamp} />
            </Champ>
            {showCadence && (
              <Champ label="Cadence" htmlFor="cadence">
                <select id="cadence" value={prixUnite} onChange={e => setPrixUnite(e.target.value as Cadence)} className={classeChamp} style={styleChamp}>
                  <option value="mois">par mois</option>
                  <option value="semaine">par semaine</option>
                  <option value="convenir">à convenir</option>
                </select>
              </Champ>
            )}
          </Colonnes>
          <CaseACocher label="Prix négociable" checked={prixNegociable} onChange={setPrixNegociable} />
        </SectionFormulaire>
      )}

      {paiementStatut !== 'paye' && (
        <p className="text-sm text-[#92400E] bg-[#FFFBEB] rounded-xl px-4 py-3" style={{ border: '1px solid #FDE68A' }}>
          Publier une annonce cheval est payant : <b>4,99 €</b>, visible 60 jours. Le paiement sécurisé se fait juste après.
        </p>
      )}
    </PageFormulaire>

    {cropSrc && (
      <ImageCropModal src={cropSrc} aspect={1} title="Recadrer la photo"
        onConfirm={handleCropConfirm}
        onCancel={() => {
          if (cropSrc) URL.revokeObjectURL(cropSrc);
          setCropQueue(q => { if (q.length) { setCropSrc(URL.createObjectURL(q[0])); return q.slice(1); } setCropSrc(null); return []; });
        }} />
    )}
    </>
  );
}

export default function CreerAnnonceChevalPage() {
  return (
    <Suspense fallback={<div className="min-h-screen flex items-center justify-center"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>}>
      <CreerAnnonceChevalInner />
    </Suspense>
  );
}
