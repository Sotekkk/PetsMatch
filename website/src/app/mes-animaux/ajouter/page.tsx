'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { triggerAutoProtocoles } from '@/lib/planning-service';
import { useAuth } from '@/lib/auth-context';
import { loadBreeds } from '@/lib/breeds';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';

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

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function AjouterAnimalPage() {
  const { user, userData } = useAuth();
  const router = useRouter();

  const isEleveur = userData?.isElevage === true;

  const [espece,        setEspece]        = useState('chien');
  const [nom,           setNom]           = useState('');
  const [sexe,          setSexe]          = useState<'male' | 'femelle'>('male');
  const [race,          setRace]          = useState('');
  const [dateNaissance, setDateNaissance] = useState('');
  const [identification, setIdentification] = useState('');
  const [couleur,       setCouleur]       = useState('');
  const [typePoil,      setTypePoil]      = useState('');
  const [taille,        setTaille]        = useState('');
  const [poids,         setPoids]         = useState('');
  const [sterilise,     setSterilise]     = useState(false);
  const [passeport,     setPasseport]     = useState('');
  const [description,   setDescription]  = useState('');
  const [photoUrl,      setPhotoUrl]      = useState('');
  const [breeds,        setBreeds]        = useState<string[]>([]);

  const [saving,  setSaving]  = useState(false);
  const [error,   setError]   = useState('');

  const [cropSrc,        setCropSrc]        = useState<string | null>(null);
  const [photoUploading, setPhotoUploading] = useState(false);

  useEffect(() => {
    loadBreeds(espece).then(list => setBreeds([...list, 'Autre']));
  }, [espece]);

  function handlePhotoChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setCropSrc(URL.createObjectURL(file));
    e.target.value = '';
  }

  async function handleCropConfirm(blob: Blob) {
    if (!user) return;
    setCropSrc(null);
    setPhotoUploading(true);
    try {
      const url = await uploadBlob(blob, `animaux/${user.uid}/${Date.now()}.jpg`);
      setPhotoUrl(url);
    } catch { /* ignore */ }
    finally { setPhotoUploading(false); }
  }

  function handleCropCancel() {
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropSrc(null);
  }

  async function handleSave() {
    if (!user) return;
    setError('');
    setSaving(true);
    try {
      const id = `animal_${user.uid}_${Date.now()}`;
      const row: Record<string, unknown> = {
        id,
        espece,
        sexe,
        nom:                nom.trim()           || null,
        race:               race.trim()          || null,
        identification:     identification.trim() || null,
        couleur:            couleur.trim()        || null,
        type_poil:          typePoil             || null,
        taille:             taille               || null,
        poids:              poids                || null,
        sterilise,
        passeport_europeen: passeport.trim()     || null,
        description:        description.trim()   || null,
        photo_url:          photoUrl             || null,
        date_naissance:     dateNaissance        || null,
        statut:             'present',
        updated_at:         new Date().toISOString(),
      };

      if (isEleveur) {
        row.uid_eleveur = user.uid;
        row.provenance_qualite = 'naissance';
        row.provenance_nom = userData?.nameElevage ?? null;
      } else {
        // uid_eleveur est aussi renseigné pour satisfaire la politique RLS INSERT
        row.uid_eleveur      = user.uid;
        row.uid_proprietaire = user.uid;
        row.provenance_qualite = 'achat';
      }

      const { error: err } = await supabase.from('animaux').insert([row]);
      if (err) throw err;

      // Protocoles automatiques pour un nouvel animal entrant (éleveurs uniquement)
      if (isEleveur) {
        triggerAutoProtocoles({
          uid: user.uid, declencheur: 'entree',
          animalId: id,
          dateEvenement: new Date(), espece,
        }).catch(() => {});
      }

      router.push('/mes-animaux?added=1');
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur lors de la sauvegarde');
    } finally {
      setSaving(false);
    }
  }

  const iCls   = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
  const iSmCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';

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
            🐾 Ajouter un animal
          </h1>
          <p className="text-gray-400 text-sm">Créer une fiche individuelle</p>
        </div>
      </div>

      {error && (
        <div className="mb-4 bg-red-50 border border-red-200 text-red-700 rounded-xl px-4 py-3 text-sm">
          {error}
        </div>
      )}

      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-6 space-y-5">

        {/* ── Photo ── */}
        <div className="flex justify-center">
          <label className="relative cursor-pointer">
            <div className="w-24 h-24 rounded-2xl overflow-hidden bg-[#EEF5EA] flex items-center justify-center border-2 border-dashed border-[#6E9E57]/40 hover:border-[#6E9E57] transition-colors">
              {photoUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={photoUrl} alt="" className="w-full h-full object-cover" />
              ) : photoUploading ? (
                <div className="w-6 h-6 border-2 border-[#6E9E57] border-t-transparent rounded-full animate-spin" />
              ) : (
                <div className="text-center">
                  <span className="text-3xl block">📷</span>
                  <span className="text-xs text-[#6E9E57] font-medium mt-1 block">Photo</span>
                </div>
              )}
            </div>
            <input type="file" accept="image/*" className="hidden"
              onChange={handlePhotoChange} disabled={photoUploading} />
          </label>
        </div>

        {/* ── Espèce ── */}
        <div>
          <label className="block text-sm font-semibold text-gray-700 mb-2">Espèce</label>
          <div className="flex flex-wrap gap-2">
            {ESPECES.map(sp => (
              <button key={sp.value} type="button" onClick={() => { setEspece(sp.value); setRace(''); setTypePoil(''); }}
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

        {/* ── Nom ── */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Nom <span className="text-gray-400 font-normal">(optionnel)</span>
          </label>
          <input className={iCls} value={nom} onChange={e => setNom(e.target.value)}
            placeholder="Ex: Luna, Max…" />
        </div>

        {/* ── Sexe ── */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1.5">Sexe</label>
          <div className="flex gap-3">
            {([['male', '♂ Mâle'], ['femelle', '♀ Femelle']] as const).map(([v, l]) => (
              <button key={v} type="button" onClick={() => setSexe(v)}
                className={`flex-1 py-2.5 rounded-xl border-2 text-sm font-medium transition-colors ${
                  sexe === v
                    ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]'
                    : 'border-gray-200 text-gray-600 hover:border-gray-300'
                }`}>
                {l}
              </button>
            ))}
          </div>
        </div>

        {/* ── Race + Date de naissance ── */}
        <div className="flex gap-3">
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">Race</label>
            <input list="breeds-list" className={iCls} value={race}
              onChange={e => setRace(e.target.value)} placeholder="Race" />
            <datalist id="breeds-list">{breeds.map(b => <option key={b} value={b} />)}</datalist>
          </div>
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Date de naissance
            </label>
            <input type="date" className={iCls} value={dateNaissance}
              onChange={e => setDateNaissance(e.target.value)}
              max={new Date().toISOString().slice(0, 10)} />
          </div>
        </div>

        {/* ── Identification ── */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            N° identification <span className="text-gray-400 font-normal">(puce / tatouage)</span>
          </label>
          <input className={iCls} value={identification}
            onChange={e => setIdentification(e.target.value)}
            placeholder="Ex: 250268500001234" />
        </div>

        {/* ── Couleur + Passeport ── */}
        <div className="flex gap-3">
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">Couleur / Robe</label>
            <input className={iCls} value={couleur}
              onChange={e => setCouleur(e.target.value)}
              placeholder="Ex: Fauve, Tricolore…" />
          </div>
          {espece !== 'oiseau' && (
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Passeport européen</label>
              <input className={iCls} value={passeport}
                onChange={e => setPasseport(e.target.value)}
                placeholder="N° passeport" />
            </div>
          )}
        </div>

        {/* ── Type de poil (chien/chat) ── */}
        {['chien', 'chat'].includes(espece) && (
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Type de poil</label>
            <div className="flex flex-wrap gap-2">
              {TYPES_POIL.map(t => (
                <button key={t} type="button"
                  onClick={() => setTypePoil(typePoil === t ? '' : t)}
                  className={`px-3 py-1.5 rounded-full text-xs font-medium border transition-colors ${
                    typePoil === t
                      ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white'
                      : 'border-gray-200 text-gray-600 hover:border-gray-300'
                  }`}>
                  {t}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* ── Taille + Poids ── */}
        <div className="flex gap-3">
          {espece !== 'oiseau' && (
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {espece === 'cheval' ? 'Taille au garrot (cm)' : 'Taille (cm)'}
              </label>
              <input type="number" className={iSmCls} value={taille}
                onChange={e => setTaille(e.target.value)} placeholder="cm" />
            </div>
          )}
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">Poids (kg)</label>
            <input type="number" className={iSmCls} value={poids}
              onChange={e => setPoids(e.target.value)} placeholder="kg" />
          </div>
        </div>

        {/* ── Stérilisé ── */}
        <div className="flex items-center justify-between py-1 border border-gray-100 rounded-xl px-4">
          <span className="text-sm font-medium text-gray-700">Stérilisé(e)</span>
          <button type="button" onClick={() => setSterilise(v => !v)}
            className={`w-11 h-6 rounded-full transition-colors relative flex-shrink-0 ${sterilise ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
            <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${sterilise ? 'translate-x-5' : 'translate-x-0.5'}`} />
          </button>
        </div>

        {/* ── Description / Notes ── */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Notes <span className="text-gray-400 font-normal">(optionnel)</span>
          </label>
          <textarea rows={3} className={`${iCls} resize-none`} value={description}
            onChange={e => setDescription(e.target.value)}
            placeholder="Caractère, particularités, antécédents…" />
        </div>

        {/* ── Enregistrer ── */}
        <button type="button" onClick={handleSave} disabled={saving}
          className="w-full py-3 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold rounded-xl transition-colors text-sm">
          {saving ? 'Création en cours…' : 'Ajouter l\'animal'}
        </button>

      </div>

      {cropSrc && (
        <ImageCropModal src={cropSrc} aspect={1} maxDim={800}
          onConfirm={handleCropConfirm} onCancel={handleCropCancel} />
      )}
    </div>
  );
}
