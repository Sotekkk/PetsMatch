'use client';

import { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';
import Link from 'next/link';

const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'Reptile', autre: 'Autre',
};
const TYPE_LABEL: Record<string, string> = {
  compagnon: 'Compagnon', portee: 'Portée', saillie: 'Saillie', retraite: "Retraité d'élevage",
};

interface RawBabe {
  animalId?: string;
  nom?: string;
  sexe?: string;
  couleur?: string;
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
}

interface BabyEdit {
  animalId?: string;
  nom?: string;
  sexe?: string;
  couleur: string;
  prix: string;
  statut: string;
  existingPhotos: string[];
  newBlobs: Blob[];
  newPreviews: string[];
}

function LockedField({ label, value }: { label: string; value?: string }) {
  return (
    <div>
      <label className="text-xs text-gray-400 block mb-1">{label}</label>
      <div className="flex items-center gap-2 w-full border border-gray-100 rounded-xl px-4 py-2.5 text-sm bg-gray-50 text-gray-500">
        <span className="flex-1">{value || '—'}</span>
        <span className="text-gray-300 text-xs" title="Non modifiable après publication">🔒</span>
      </div>
    </div>
  );
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
  const [vaccines, setVaccines] = useState(false);
  const [vermifuge, setVermifuge] = useState(false);
  const [identification, setIdentification] = useState(false);
  const [bilanSante, setBilanSante] = useState(false);
  const [semaines, setSemaines] = useState(8);
  const [clubPedigree, setClubPedigree] = useState('');
  const [numRegistre, setNumRegistre] = useState('');

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
        setVaccines(a.vaccines ?? false);
        setVermifuge(a.vermifuge ?? false);
        setIdentification(a.identification ?? false);
        setBilanSante(a.bilan_sante ?? false);
        setSemaines(a.semaines ?? 8);
        setClubPedigree(a.club_pedigree ?? '');
        setNumRegistre(a.numero_registre ?? '');
        setExistingPhotos((a.photos as unknown as string[]) ?? []);
        if (a.animaux_portee) {
          setBabies(a.animaux_portee.map(b => ({
            animalId: b.animalId,
            nom: b.nom,
            sexe: b.sexe,
            couleur: b.couleur ?? '',
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
            prix: b.prix ? Number(b.prix) : undefined,
            statut: b.statut,
            photos: [...b.existingPhotos, ...uploadedBaby],
            isLinked: !!b.animalId,
          });
        }
      }

      const { error: err } = await supabase.from('annonces').update({
        description: description || null,
        photos: allPhotos,
        couleur: !isPortee ? (couleur || null) : undefined,
        vaccines, vermifuge,
        identification, bilan_sante: bilanSante,
        semaines: !isSaillie ? semaines : undefined,
        club_pedigree: clubPedigree || null,
        numero_registre: numRegistre || null,
        ...(isSaillie  && { saillie_prix: sailliePrix ? parseFloat(sailliePrix) : null }),
        ...(!isSaillie && !isPortee && { prix: prix ? Number(prix) : null }),
        ...(isPortee   && {
          prix_min_portee: prixMin ? Number(prixMin) : null,
          prix_max_portee: prixMax ? Number(prixMax) : null,
          animaux_portee: savedBabies,
        }),
      }).eq('id', annonce.id);

      if (err) throw new Error(err.message);
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
  const iCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
  const totalMainPhotos = existingPhotos.length + newBlobs.length;

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/mes-annonces" className="text-gray-400 hover:text-[#0C5C6C] text-xl">←</Link>
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Modifier l&apos;annonce</h1>
          <p className="text-xs text-gray-400">Les champs identitaires ne peuvent pas être modifiés</p>
        </div>
      </div>

      {error && <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700">{error}</div>}

      <form onSubmit={handleSubmit} className="space-y-5">

        {/* Champs verrouillés */}
        <div className="bg-gray-50 rounded-2xl p-4 space-y-3 border border-gray-100">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide flex items-center gap-1.5">
            🔒 Identité — non modifiable
          </p>
          <div className="grid grid-cols-2 gap-3">
            <LockedField label="Type d'annonce" value={TYPE_LABEL[annonce.type_vente ?? annonce.type ?? ''] ?? annonce.type_vente ?? annonce.type} />
            <LockedField label="Espèce" value={ESPECE_LABEL[annonce.espece ?? ''] ?? annonce.espece} />
            <LockedField label="Race" value={annonce.race} />
            {annonce.sexe && <LockedField label="Sexe" value={annonce.sexe === 'male' ? 'Mâle' : 'Femelle'} />}
            {annonce.titre && <LockedField label="Titre" value={annonce.titre} />}
            {annonce.mere_puce && <LockedField label="Puce mère" value={annonce.mere_puce} />}
            {annonce.pere_puce && <LockedField label="Puce père" value={annonce.pere_puce} />}
          </div>
        </div>

        {/* Description */}
        <div>
          <label className="text-xs text-gray-400 block mb-1">Description</label>
          <textarea className={iCls + ' resize-none'} rows={4} value={description} onChange={e => setDescription(e.target.value)} placeholder="Présentez votre annonce…" />
        </div>

        {/* Prix */}
        {isSaillie && (
          <div>
            <label className="text-xs text-gray-400 block mb-1">Prix de saillie (€)</label>
            <input type="number" min="0" className={iCls} value={sailliePrix} onChange={e => setSailliePrix(e.target.value)} />
          </div>
        )}
        {isPortee && (
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs text-gray-400 block mb-1">Prix min (€)</label>
              <input type="number" min="0" className={iCls} value={prixMin} onChange={e => setPrixMin(e.target.value)} />
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">Prix max (€)</label>
              <input type="number" min="0" className={iCls} value={prixMax} onChange={e => setPrixMax(e.target.value)} />
            </div>
          </div>
        )}
        {!isSaillie && !isPortee && (
          <div>
            <label className="text-xs text-gray-400 block mb-1">Prix (€)</label>
            <input type="number" min="0" className={iCls} value={prix} onChange={e => setPrix(e.target.value)} />
          </div>
        )}

        {/* Couleur */}
        {!isPortee && (
          <div>
            <label className="text-xs text-gray-400 block mb-1">Couleur / robe</label>
            <input className={iCls} value={couleur} onChange={e => setCouleur(e.target.value)} />
          </div>
        )}

        {/* Santé */}
        <div className="border border-gray-100 rounded-xl p-4 space-y-3">
          <p className="text-xs font-semibold text-gray-500">Santé & conformité</p>
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'Vacciné(s)',       value: vaccines,       set: setVaccines },
              { label: 'Vermifugé(s)',     value: vermifuge,      set: setVermifuge },
              { label: 'Identifié(s)',     value: identification, set: setIdentification },
              { label: 'Bilan de santé',   value: bilanSante,     set: setBilanSante },
            ].map(({ label, value, set }) => (
              <label key={label} className="flex items-center gap-2 cursor-pointer select-none">
                <div onClick={() => set(!value)}
                  className={`w-5 h-5 rounded flex items-center justify-center flex-shrink-0 border-2 transition-colors cursor-pointer ${value ? 'bg-[#6E9E57] border-[#6E9E57]' : 'border-gray-300'}`}>
                  {value && <span className="text-white text-xs">✓</span>}
                </div>
                <span className="text-sm text-gray-700">{label}</span>
              </label>
            ))}
          </div>
          {!isSaillie && (
            <div>
              <label className="text-xs text-gray-400 block mb-1">
                Âge au départ : <strong>{semaines} semaines</strong>
              </label>
              <input type="range" min={8} max={26} value={semaines} onChange={e => setSemaines(Number(e.target.value))}
                className="w-full accent-[#6E9E57]" />
            </div>
          )}
        </div>

        {/* Pedigree */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs text-gray-400 block mb-1">Club / registre pedigree</label>
            <input className={iCls} value={clubPedigree} onChange={e => setClubPedigree(e.target.value)} />
          </div>
          <div>
            <label className="text-xs text-gray-400 block mb-1">N° registre / LOF</label>
            <input className={iCls} value={numRegistre} onChange={e => setNumRegistre(e.target.value)} />
          </div>
        </div>

        {/* Photos principales de l'annonce */}
        <div>
          <label className="text-xs text-gray-400 block mb-2">
            Photos de l&apos;annonce ({totalMainPhotos}/5)
          </label>
          <div className="flex flex-wrap gap-2 mb-2">
            {existingPhotos.map((url, i) => (
              <div key={url} className="relative w-20 h-20 rounded-xl overflow-hidden bg-gray-100 group">
                <img src={url} alt="" className="w-full h-full object-cover" />
                <button type="button"
                  onClick={() => setExistingPhotos(prev => prev.filter((_, j) => j !== i))}
                  className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center text-white text-lg transition-opacity">
                  ✕
                </button>
              </div>
            ))}
            {newPreviews.map((url, i) => (
              <div key={url} className="relative w-20 h-20 rounded-xl overflow-hidden bg-gray-100 group">
                <img src={url} alt="" className="w-full h-full object-cover" />
                <button type="button"
                  onClick={() => {
                    URL.revokeObjectURL(url);
                    setNewBlobs(prev => prev.filter((_, j) => j !== i));
                    setNewPreviews(prev => prev.filter((_, j) => j !== i));
                  }}
                  className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center text-white text-lg transition-opacity">
                  ✕
                </button>
              </div>
            ))}
            {totalMainPhotos < 5 && (
              <label className="w-20 h-20 rounded-xl border-2 border-dashed border-gray-200 flex items-center justify-center cursor-pointer hover:border-[#0C5C6C]/40 transition-colors">
                <span className="text-2xl text-gray-300">+</span>
                <input type="file" accept="image/*" multiple className="hidden" onChange={handleMainPhotos} />
              </label>
            )}
          </div>
        </div>

        {/* Section bébés (portée uniquement) */}
        {isPortee && babies.length > 0 && (
          <div className="border border-[#0C5C6C]/20 rounded-2xl p-4 space-y-4">
            <p className="text-xs font-semibold text-[#0C5C6C] uppercase tracking-wide">
              🐾 Bébés de la portée
            </p>
            {babies.map((b, babyIdx) => {
              const totalBabyPhotos = b.existingPhotos.length + b.newBlobs.length;
              return (
                <div key={babyIdx} className="border border-gray-100 rounded-xl p-3 space-y-3">
                  {/* Nom + sexe (locked) */}
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-bold text-[#1F2A2E]">
                      {b.nom || `Bébé ${babyIdx + 1}`}
                    </span>
                    {b.sexe && (
                      <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${b.sexe === 'male' ? 'bg-blue-50 text-blue-600' : 'bg-pink-50 text-pink-600'}`}>
                        {b.sexe === 'male' ? '♂ Mâle' : '♀ Femelle'}
                      </span>
                    )}
                    <span className="ml-auto text-xs text-gray-300 flex items-center gap-1">🔒 nom/sexe</span>
                  </div>

                  {/* Photos du bébé */}
                  <div>
                    <label className="text-xs text-gray-400 block mb-1.5">
                      Photos ({totalBabyPhotos}/5)
                    </label>
                    <div className="flex flex-wrap gap-2">
                      {b.existingPhotos.map((url, pi) => (
                        <div key={pi} className="relative w-16 h-16 rounded-lg overflow-hidden bg-gray-100 group">
                          <img src={url} alt="" className="w-full h-full object-cover" />
                          <button type="button"
                            onClick={() => removeBabyExistingPhoto(babyIdx, pi)}
                            className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center text-white text-base transition-opacity">
                            ✕
                          </button>
                        </div>
                      ))}
                      {b.newPreviews.map((url, pi) => (
                        <div key={pi} className="relative w-16 h-16 rounded-lg overflow-hidden bg-gray-100 group">
                          <img src={url} alt="" className="w-full h-full object-cover" />
                          <button type="button"
                            onClick={() => removeBabyNewPhoto(babyIdx, pi)}
                            className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center text-white text-base transition-opacity">
                            ✕
                          </button>
                        </div>
                      ))}
                      {totalBabyPhotos < 5 && (
                        <label className="w-16 h-16 rounded-lg border-2 border-dashed border-gray-200 flex items-center justify-center cursor-pointer hover:border-[#0C5C6C]/40 transition-colors">
                          <span className="text-xl text-gray-300">+</span>
                          <input type="file" accept="image/*" multiple className="hidden"
                            onChange={e => handleBabyPhotos(babyIdx, e)} />
                        </label>
                      )}
                    </div>
                  </div>

                  {/* Couleur, prix, statut */}
                  <div className="grid grid-cols-3 gap-2">
                    <div>
                      <label className="text-xs text-gray-400 block mb-1">Couleur</label>
                      <input className={iCls + ' text-xs'} value={b.couleur}
                        onChange={e => setBabies(prev => prev.map((x, i) => i === babyIdx ? { ...x, couleur: e.target.value } : x))}
                        placeholder="Ex: fauve" />
                    </div>
                    <div>
                      <label className="text-xs text-gray-400 block mb-1">Prix (€)</label>
                      <input type="number" min="0" className={iCls + ' text-xs'} value={b.prix}
                        onChange={e => setBabies(prev => prev.map((x, i) => i === babyIdx ? { ...x, prix: e.target.value } : x))} />
                    </div>
                    <div>
                      <label className="text-xs text-gray-400 block mb-1">Statut</label>
                      <select className={iCls + ' text-xs'} value={b.statut}
                        onChange={e => setBabies(prev => prev.map((x, i) => i === babyIdx ? { ...x, statut: e.target.value } : x))}>
                        <option value="disponible">Disponible</option>
                        <option value="reserve">Réservé</option>
                        <option value="vendu">Vendu</option>
                      </select>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Submit */}
        <div className="flex gap-3 pt-2">
          <Link href="/mes-annonces"
            className="flex-1 text-center border border-gray-200 text-gray-600 py-3 rounded-xl text-sm font-semibold hover:bg-gray-50 transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            Annuler
          </Link>
          <button type="submit" disabled={saving}
            className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white py-3 rounded-xl text-sm font-semibold transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {saving ? (
              <span className="inline-flex items-center gap-2 justify-center">
                <span className="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin" />
                Enregistrement…
              </span>
            ) : '💾 Enregistrer les modifications'}
          </button>
        </div>
      </form>

      {cropSrc && (
        <ImageCropModal
          src={cropSrc}
          onConfirm={handleCropConfirm}
          onCancel={handleCropSkip}
        />
      )}
    </div>
  );
}
