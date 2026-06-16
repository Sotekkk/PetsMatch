'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { triggerAutoProtocoles } from '@/lib/planning-service';
import { useAuth } from '@/lib/auth-context';
import { loadBreeds } from '@/lib/breeds';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';

// ─── Types ────────────────────────────────────────────────────────────────────

interface ExistingAnimal {
  id: string;
  nom?: string | null;
  sexe?: string | null;
  espece?: string | null;
  race?: string | null;
  identification?: string | null;
  date_naissance?: string | null;
  photo_url?: string | null;
}

interface AnimalRow {
  nom: string;
  sexe: 'male' | 'femelle';
  identification: string;
  couleur: string;
  type_poil: string;
  taille: string;
  poids: string;
  sterilise: boolean;
  passeport_europeen: string;
  notes: string;
  photo_url: string;
}

// ─── Constantes ───────────────────────────────────────────────────────────────

const TYPES_POIL = ['Court', 'Mi-long', 'Long', 'Frisé', 'Fil de soie', 'Ras'];

const ESPECES = [
  { value: 'chien',  label: 'Chiens',  emoji: '🐕' },
  { value: 'chat',   label: 'Chats',   emoji: '🐈' },
  { value: 'cheval', label: 'Chevaux', emoji: '🐴' },
  { value: 'lapin',  label: 'Lapins',  emoji: '🐰' },
  { value: 'ovin',   label: 'Ovins',   emoji: '🐑' },
  { value: 'caprin', label: 'Caprins', emoji: '🐐' },
  { value: 'porcin', label: 'Porcins', emoji: '🐷' },
  { value: 'nac',    label: 'NAC',     emoji: '🦎' },
  { value: 'oiseau', label: 'Oiseaux', emoji: '🦜' },
  { value: 'autre',  label: 'Autres',  emoji: '🐾' },
];

function newRow(): AnimalRow {
  return { nom: '', sexe: 'male', identification: '', couleur: '', type_poil: '', taille: '', poids: '', sterilise: false, passeport_europeen: '', notes: '', photo_url: '' };
}

function tUrl(url: string) {
  if (!url.includes('/storage/v1/object/public/')) return url;
  return url.replace('/storage/v1/object/', '/storage/v1/render/image/') + '?width=80&quality=70&resize=contain';
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function PorteePage() {
  const { user, userData } = useAuth();
  const router   = useRouter();

  // Champs communs
  const [espece,        setEspece]        = useState('chien');
  const [race,          setRace]          = useState('');
  const [dateNaissance, setDateNaissance] = useState('');
  const [description,   setDescription]  = useState('');
  const [breeds,        setBreeds]        = useState<string[]>([]);

  // Pedigree & registre
  const [pedigree,     setPedigree]     = useState(false);
  const [clubRegistre, setClubRegistre] = useState('');
  const [pedigreeLof,  setPedigreeLof]  = useState('');

  // Père
  const [pereSelected,  setPereSelected]  = useState<ExistingAnimal | null>(null);
  const [nomPere,        setNomPere]       = useState('');
  const [pucePere,       setPucePere]      = useState('');
  const [showPerePicker, setShowPerePicker] = useState(false);
  const [myMales,        setMyMales]        = useState<ExistingAnimal[]>([]);
  const [loadingMales,   setLoadingMales]   = useState(false);

  // Mère
  const [mereSelected,     setMereSelected]     = useState<ExistingAnimal | null>(null);
  const [nomMere,           setNomMere]           = useState('');
  const [puceMere,          setPuceMere]          = useState('');
  const [raceMere,          setRaceMere]          = useState('');
  const [dateNaissanceMere, setDateNaissanceMere] = useState('');
  const [showMerePicker,    setShowMerePicker]    = useState(false);
  const [myFemelles,        setMyFemelles]        = useState<ExistingAnimal[]>([]);
  const [loadingFemelles,   setLoadingFemelles]   = useState(false);

  // Animaux de la portée
  const [animaux, setAnimaux] = useState<AnimalRow[]>([newRow()]);

  const [saving, setSaving] = useState(false);
  const [error,  setError]  = useState('');

  // Photo crop
  const [cropSrc,    setCropSrc]    = useState<string | null>(null);
  const [cropRowIdx, setCropRowIdx] = useState<number | null>(null);
  const [photoUploading, setPhotoUploading] = useState<number | null>(null);

  useEffect(() => {
    loadBreeds(espece).then(list => setBreeds([...list, 'Autre']));
  }, [espece]);

  function onEspeceChange(val: string) {
    setEspece(val);
    clearPere();
    clearMere();
  }

  async function loadMaleAnimals() {
    if (!user) return;
    setLoadingMales(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
      .eq('uid_eleveur', user.uid)
      .eq('espece', espece)
      .eq('sexe', 'male')
      .or('statut.is.null,statut.eq.present')
      .order('nom');
    setMyMales((data ?? []) as ExistingAnimal[]);
    setLoadingMales(false);
  }

  async function loadFemelleAnimals() {
    if (!user) return;
    setLoadingFemelles(true);
    const { data } = await supabase.from('animaux')
      .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
      .eq('uid_eleveur', user.uid)
      .eq('espece', espece)
      .eq('sexe', 'femelle')
      .or('statut.is.null,statut.eq.present')
      .order('nom');
    setMyFemelles((data ?? []) as ExistingAnimal[]);
    setLoadingFemelles(false);
  }

  function selectPere(a: ExistingAnimal) {
    setPereSelected(a);
    setNomPere(a.nom ?? '');
    setPucePere(a.identification ?? '');
    setShowPerePicker(false);
  }

  function clearPere() {
    setPereSelected(null); setNomPere(''); setPucePere('');
    setShowPerePicker(false);
  }

  function selectMere(a: ExistingAnimal) {
    setMereSelected(a);
    setNomMere(a.nom ?? '');
    setPuceMere(a.identification ?? '');
    setRaceMere(a.race ?? '');
    setDateNaissanceMere(a.date_naissance?.slice(0, 10) ?? '');
    if (!race && a.race) setRace(a.race);
    setShowMerePicker(false);
  }

  function clearMere() {
    setMereSelected(null); setNomMere(''); setPuceMere(''); setRaceMere(''); setDateNaissanceMere('');
    setShowMerePicker(false);
  }

  function updateRow(i: number, field: keyof AnimalRow, value: string | boolean) {
    setAnimaux(prev => prev.map((r, idx) => idx === i ? { ...r, [field]: value } : r));
  }

  function addRow()       { setAnimaux(prev => [...prev, newRow()]); }
  function removeRow(i: number) {
    if (animaux.length <= 1) return;
    setAnimaux(prev => prev.filter((_, idx) => idx !== i));
  }

  function handlePhotoChange(e: React.ChangeEvent<HTMLInputElement>, idx: number) {
    const file = e.target.files?.[0];
    if (!file) return;
    setCropSrc(URL.createObjectURL(file));
    setCropRowIdx(idx);
    e.target.value = '';
  }

  async function handleCropConfirm(blob: Blob) {
    if (!user || cropRowIdx === null) return;
    const idx = cropRowIdx;
    setCropSrc(null); setCropRowIdx(null);
    setPhotoUploading(idx);
    try {
      const url = await uploadBlob(blob, `animaux/${user.uid}/${Date.now()}_${idx}.jpg`);
      updateRow(idx, 'photo_url', url);
    } catch { /* ignore */ }
    finally { setPhotoUploading(null); }
  }

  function handleCropCancel() {
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropSrc(null); setCropRowIdx(null);
  }

  async function handleSave() {
    if (!dateNaissance) { setError('La date de naissance est obligatoire'); return; }
    if (!user) return;
    setError('');
    setSaving(true);
    try {
      const porteeId = `portee_${Date.now()}`;
      const rows = animaux.map((a, i) => ({
        id:                  `${porteeId}_${i}`,
        uid_eleveur:         user.uid,
        portee_id:           porteeId,
        espece,
        race,
        sexe:                a.sexe,
        nom:                 a.nom?.trim()                   || null,
        identification:      a.identification?.trim()        || null,
        couleur:             a.couleur?.trim()               || null,
        type_poil:           a.type_poil?.trim()             || null,
        taille:              a.taille?.trim()                || null,
        poids:               a.poids?.trim()                 || null,
        sterilise:           a.sterilise ?? false,
        passeport_europeen:  a.passeport_europeen?.trim()    || null,
        notes:               a.notes?.trim()                 || null,
        photo_url:           a.photo_url                    || null,
        date_naissance:      dateNaissance                  || null,
        date_entree:         dateNaissance            || null,
        provenance_qualite:  'naissance',
        provenance_nom:      userData?.nameElevage    || null,
        provenance_adresse:  [userData?.rueElevage, userData?.villeElevage].filter(Boolean).join(', ') || null,
        statut:              'present',
        description:         description.trim()      || null,
        pedigree,
        club_registre:       clubRegistre.trim()     || null,
        pedigree_lof:        pedigreeLof.trim()      || null,
        nom_pere:            nomPere.trim()           || null,
        puce_pere:           pucePere.trim()          || null,
        nom_mere:            nomMere.trim()           || null,
        puce_mere:           puceMere.trim()          || null,
        race_mere:           raceMere.trim()          || null,
        date_naissance_mere: dateNaissanceMere        || null,
        updated_at:          new Date().toISOString(),
      }));

      const { error: err } = await supabase.from('animaux').upsert(rows);
      if (err) throw err;

      // Protocoles automatiques pour chaque nouveau-né
      const dateNaissanceDate = new Date(dateNaissance);
      for (let i = 0; i < animaux.length; i++) {
        triggerAutoProtocoles({
          uid: user.uid, declencheur: 'naissance',
          animalId: `${porteeId}_${i}`,
          dateEvenement: dateNaissanceDate, espece,
        }).catch(() => {});
      }

      router.push('/mes-animaux?portee=1');
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur lors de la sauvegarde');
    } finally {
      setSaving(false);
    }
  }

  const iCls   = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white disabled:bg-gray-50 disabled:text-gray-400';
  const iSmCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white disabled:bg-gray-50 disabled:text-gray-400';
  const sCls   = 'border border-gray-100 rounded-xl p-4 space-y-3';

  return (
    <div className="max-w-2xl mx-auto px-4 py-10">

      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <button type="button" onClick={() => router.back()}
          className="text-gray-400 hover:text-gray-600 transition-colors">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            🐣 Nouvelle portée
          </h1>
          <p className="text-gray-400 text-sm">Créer plusieurs animaux d&apos;un coup</p>
        </div>
      </div>

      {error && (
        <div className="mb-4 bg-red-50 border border-red-200 text-red-700 rounded-xl px-4 py-3 text-sm">
          {error}
        </div>
      )}

      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-6 space-y-5">

        {/* ── Espèce ── */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-2">Espèce</label>
          <div className="flex flex-wrap gap-2">
            {ESPECES.map(sp => (
              <button key={sp.value} type="button" onClick={() => onEspeceChange(sp.value)}
                className={`flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-medium border transition-all ${
                  espece === sp.value
                    ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white'
                    : 'border-gray-200 text-gray-600 hover:border-[#0C5C6C]'
                }`}>
                {sp.emoji} {sp.label}
              </button>
            ))}
          </div>
        </div>

        {/* ── Race + Date de naissance ── */}
        <div className="flex gap-3">
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">Race</label>
            <input list="breeds-portee" className={iCls} value={race}
              onChange={e => setRace(e.target.value)}
              placeholder="Race commune à tous" />
            <datalist id="breeds-portee">{breeds.map(b => <option key={b} value={b} />)}</datalist>
          </div>
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Date de naissance <span className="text-red-400">*</span>
            </label>
            <input type="date" className={iCls} value={dateNaissance}
              onChange={e => setDateNaissance(e.target.value)}
              max={new Date().toISOString().slice(0, 10)} />
          </div>
        </div>

        {/* ── Description ── */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Description <span className="text-gray-400 font-normal">(optionnel)</span>
          </label>
          <textarea rows={3} className={`${iCls} resize-none`} value={description}
            onChange={e => setDescription(e.target.value)}
            placeholder="Caractère, particularités de la portée…" />
        </div>

        {/* ── Pedigree & Registre ── */}
        <div className={sCls}>
          <p className="text-sm font-semibold text-gray-700">🏅 Pedigree &amp; Registre</p>
          <div className="flex items-center justify-between py-1">
            <span className="text-sm text-gray-700">Inscrit au registre (LOF / LOOF…)</span>
            <button type="button" onClick={() => setPedigree(!pedigree)}
              className={`w-11 h-6 rounded-full transition-colors relative flex-shrink-0 ${pedigree ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
              <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${pedigree ? 'translate-x-5' : 'translate-x-0.5'}`} />
            </button>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">
              Club de race / Association pedigree <span className="text-gray-400 font-normal">(optionnel)</span>
            </label>
            <input className={iSmCls} value={clubRegistre}
              onChange={e => setClubRegistre(e.target.value)}
              placeholder="Ex: SCC, Club du Berger Australien…" />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">
              N° d&apos;inscription au registre <span className="text-gray-400 font-normal">(optionnel)</span>
            </label>
            <input className={iSmCls} value={pedigreeLof}
              onChange={e => setPedigreeLof(e.target.value)}
              placeholder="Ex: LOF 12345/00, LOOF 67890…" />
          </div>
        </div>

        {/* ── Père ── */}
        <div className={sCls}>
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold text-gray-700">
              ♂ Père <span className="text-gray-400 font-normal">(optionnel)</span>
            </p>
            {pereSelected && (
              <button type="button" onClick={clearPere}
                className="text-xs text-red-400 hover:text-red-600 font-medium">Effacer</button>
            )}
          </div>

          {pereSelected && <ParentChip animal={pereSelected} onClear={clearPere} />}

          <div className="relative">
            <button type="button"
              onClick={async () => {
                if (!showPerePicker) await loadMaleAnimals();
                setShowPerePicker(v => !v);
                setShowMerePicker(false);
              }}
              className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
              <span>🔍</span>
              <span>{pereSelected ? "Changer d'animal" : 'Chercher parmi mes animaux'}</span>
            </button>
            {showPerePicker && (
              <AnimalPickerList animals={myMales} isLoading={loadingMales} onSelect={selectPere} />
            )}
          </div>

          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">Nom du père</label>
              <input className={iSmCls} value={nomPere} disabled={!!pereSelected}
                onChange={e => setNomPere(e.target.value)} placeholder="Nom" />
            </div>
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">N° identification</label>
              <input className={iSmCls} value={pucePere} disabled={!!pereSelected}
                onChange={e => setPucePere(e.target.value)} placeholder="Puce / tatouage" />
            </div>
          </div>
        </div>

        {/* ── Mère ── */}
        <div className={sCls}>
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold text-gray-700">
              ♀ Mère <span className="text-gray-400 font-normal">(optionnel)</span>
            </p>
            {mereSelected && (
              <button type="button" onClick={clearMere}
                className="text-xs text-red-400 hover:text-red-600 font-medium">Effacer</button>
            )}
          </div>

          {mereSelected && <ParentChip animal={mereSelected} onClear={clearMere} />}

          <div className="relative">
            <button type="button"
              onClick={async () => {
                if (!showMerePicker) await loadFemelleAnimals();
                setShowMerePicker(v => !v);
                setShowPerePicker(false);
              }}
              className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
              <span>🔍</span>
              <span>{mereSelected ? "Changer d'animal" : 'Chercher parmi mes animaux'}</span>
            </button>
            {showMerePicker && (
              <AnimalPickerList animals={myFemelles} isLoading={loadingFemelles} onSelect={selectMere} />
            )}
          </div>

          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">Nom de la mère</label>
              <input className={iSmCls} value={nomMere} disabled={!!mereSelected}
                onChange={e => setNomMere(e.target.value)} placeholder="Nom" />
            </div>
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">N° identification</label>
              <input className={iSmCls} value={puceMere} disabled={!!mereSelected}
                onChange={e => setPuceMere(e.target.value)} placeholder="Puce / tatouage" />
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">Race de la mère</label>
              <input list="breeds-mere" className={iSmCls} value={raceMere} disabled={!!mereSelected}
                onChange={e => setRaceMere(e.target.value)} placeholder="Race" />
              {!mereSelected && <datalist id="breeds-mere">{breeds.map(b => <option key={b} value={b} />)}</datalist>}
            </div>
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">Date de naissance</label>
              <input type="date" className={iSmCls} value={dateNaissanceMere} disabled={!!mereSelected}
                onChange={e => setDateNaissanceMere(e.target.value)}
                max={new Date().toISOString().slice(0, 10)} />
            </div>
          </div>
        </div>

        {/* ── Animaux de la portée ── */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <p className="text-sm font-semibold text-gray-700">Animaux de la portée</p>
            <span className="text-xs font-bold text-[#6E9E57] bg-[#6E9E57]/10 px-2.5 py-0.5 rounded-full">
              {animaux.length}
            </span>
          </div>

          <div className="space-y-3">
            {animaux.map((row, i) => (
              <div key={i} className="border border-gray-100 rounded-xl p-4 space-y-3">
                <div className="flex items-center gap-3">
                  {/* Photo */}
                  <label className="relative cursor-pointer flex-shrink-0">
                    <div className="w-14 h-14 rounded-xl overflow-hidden bg-[#EEF5EA] flex items-center justify-center">
                      {row.photo_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={row.photo_url} alt="" className="w-full h-full object-cover" />
                      ) : (
                        <span className="text-2xl">📷</span>
                      )}
                      {photoUploading === i && (
                        <div className="absolute inset-0 bg-black/40 flex items-center justify-center rounded-xl">
                          <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                        </div>
                      )}
                    </div>
                    <input type="file" accept="image/*" className="hidden"
                      onChange={e => handlePhotoChange(e, i)} disabled={photoUploading !== null} />
                  </label>
                  <div className="flex-1 flex items-center justify-between">
                    <div className="w-6 h-6 rounded-full bg-[#0C5C6C]/10 flex items-center justify-center">
                      <span className="text-xs font-bold text-[#0C5C6C]">{i + 1}</span>
                    </div>
                    {animaux.length > 1 && (
                      <button type="button" onClick={() => removeRow(i)}
                        className="text-gray-300 hover:text-red-400 transition-colors">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>
                    )}
                  </div>
                </div>
                {/* Nom + Identification */}
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Nom (optionnel)</label>
                    <input className={iSmCls} value={row.nom}
                      onChange={e => updateRow(i, 'nom', e.target.value)} placeholder="Nom" />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">N° identification</label>
                    <input className={iSmCls} value={row.identification}
                      onChange={e => updateRow(i, 'identification', e.target.value)}
                      placeholder="Puce / tatouage" />
                  </div>
                </div>
                {/* Sexe */}
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1.5">Sexe</label>
                  <div className="flex gap-2">
                    {([['male', '♂ Mâle'], ['femelle', '♀ Femelle']] as const).map(([v, l]) => (
                      <button key={v} type="button" onClick={() => updateRow(i, 'sexe', v)}
                        className={`flex-1 py-2 rounded-xl border-2 text-xs font-medium transition-colors ${row.sexe === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>
                        {l}
                      </button>
                    ))}
                  </div>
                </div>
                {/* Couleur + Passeport */}
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Couleur / Robe</label>
                    <input className={iSmCls} value={row.couleur}
                      onChange={e => updateRow(i, 'couleur', e.target.value)}
                      placeholder="Ex: Fauve, Tricolore…" />
                  </div>
                  {espece !== 'oiseau' && (
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Passeport européen</label>
                      <input className={iSmCls} value={row.passeport_europeen}
                        onChange={e => updateRow(i, 'passeport_europeen', e.target.value)}
                        placeholder="N° passeport" />
                    </div>
                  )}
                </div>
                {/* Type de poil (chien/chat) */}
                {['chien', 'chat'].includes(espece) && (
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1.5">Type de poil</label>
                    <div className="flex flex-wrap gap-1.5">
                      {TYPES_POIL.map(t => (
                        <button key={t} type="button" onClick={() => updateRow(i, 'type_poil', row.type_poil === t ? '' : t)}
                          className={`px-3 py-1 rounded-full text-xs font-medium border transition-colors ${row.type_poil === t ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>
                          {t}
                        </button>
                      ))}
                    </div>
                  </div>
                )}
                {/* Taille + Poids */}
                <div className="grid grid-cols-2 gap-3">
                  {espece !== 'oiseau' && (
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">
                        {espece === 'cheval' ? 'Taille au garrot (cm)' : 'Taille (cm)'}
                      </label>
                      <input type="number" className={iSmCls} value={row.taille ?? ''}
                        onChange={e => updateRow(i, 'taille', e.target.value)} placeholder="cm" />
                    </div>
                  )}
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Poids (kg)</label>
                    <input type="number" className={iSmCls} value={row.poids ?? ''}
                      onChange={e => updateRow(i, 'poids', e.target.value)} placeholder="kg" />
                  </div>
                </div>
                {/* Stérilisé */}
                <div className="flex items-center justify-between py-0.5">
                  <span className="text-xs font-medium text-gray-600">Stérilisé(e)</span>
                  <button type="button" onClick={() => updateRow(i, 'sterilise', !row.sterilise)}
                    className={`w-10 h-5 rounded-full transition-colors relative ${row.sterilise ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
                    <div className={`w-4 h-4 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${row.sterilise ? 'translate-x-5' : 'translate-x-0.5'}`} />
                  </button>
                </div>
                {/* Notes */}
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Notes (optionnel)</label>
                  <textarea rows={2} className={`${iSmCls} resize-none`} value={row.notes}
                    onChange={e => updateRow(i, 'notes', e.target.value)}
                    placeholder="Particularités, remarques…" />
                </div>
              </div>
            ))}
          </div>

          <button type="button" onClick={addRow}
            className="mt-3 w-full py-3 border-2 border-dashed border-[#0C5C6C]/30 rounded-xl text-sm font-medium text-[#0C5C6C] hover:border-[#0C5C6C]/60 hover:bg-[#0C5C6C]/5 transition-all">
            + Ajouter un animal
          </button>
        </div>

        {/* ── Enregistrer ── */}
        <button type="button" onClick={handleSave} disabled={saving}
          className="w-full py-3 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold rounded-xl transition-colors text-sm">
          {saving ? 'Création en cours…' : `Créer ${animaux.length} animal${animaux.length > 1 ? 'aux' : ''}`}
        </button>

      </div>

      {cropSrc && (
        <ImageCropModal src={cropSrc} aspect={1} maxDim={800}
          onConfirm={handleCropConfirm} onCancel={handleCropCancel} />
      )}
    </div>
  );
}

// ─── Composants ───────────────────────────────────────────────────────────────

function AnimalPickerList({ animals, isLoading, onSelect }: {
  animals: ExistingAnimal[];
  isLoading: boolean;
  onSelect: (a: ExistingAnimal) => void;
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
              <img src={tUrl(a.photo_url)} alt="" className="w-full h-full object-contain" />
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

function ParentChip({ animal, onClear }: { animal: ExistingAnimal; onClear: () => void }) {
  return (
    <div className="flex items-center gap-2 px-3 py-2 bg-[#0C5C6C]/10 rounded-xl border border-[#0C5C6C]/20">
      <span className="text-sm">🔗</span>
      <span className="text-sm font-semibold text-[#0C5C6C] flex-1 truncate">{animal.nom || 'Sans nom'}</span>
      {animal.race && <span className="text-xs text-[#0C5C6C]/60 truncate">{animal.race}</span>}
      <button type="button" onClick={onClear}
        className="text-[#0C5C6C]/50 hover:text-red-500 transition-colors ml-1 flex-shrink-0">
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
}
