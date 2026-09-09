'use client';

import { Suspense, useCallback, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { uploadBlob, uploadRawFile } from '@/lib/upload-media';
import { fromPostalCode } from '@/lib/french-geo';
import ImageCropModal from '@/components/ImageCropModal';

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
  id: string; nom: string | null; race: string | null; sexe: string | null;
  couleur: string | null; date_naissance: string | null; num_sire: string | null; photo_url: string | null;
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

  const iCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
  const iSm = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';

  useEffect(() => {
    fetch('/breeds/horse_breeds.json').then(r => r.json()).then(d => setBreeds(d as string[])).catch(() => setBreeds([]));
  }, []);

  const loadMyHorses = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.from('animaux')
      .select('id, nom, race, sexe, couleur, date_naissance, num_sire, photo_url, espece')
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
    if (!numSIRE && h.num_sire) setNumSIRE(h.num_sire);
    if (h.sexe && ['jument', 'hongre', 'entier'].includes(h.sexe)) setSexe(h.sexe as typeof sexe);
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
    if (!titre.trim()) { setError('Un titre est requis.'); return; }
    if (numSIRE.trim().length < 6) { setError('Le n° SIRE est obligatoire (Décret 2013-879).'); return; }
    if (existingPhotos.length + croppedBlobs.length === 0) { setError('Ajoutez au moins une photo.'); return; }
    if (priced && prixUnite !== 'convenir' && (!prix || isNaN(Number(prix)))) {
      setError('Indiquez un prix (ou passez en « à convenir »).'); return;
    }
    setSaving(true);
    try {
      const pid = activeProfileId || null;

      if (!editId) {
        const { count } = await supabase.from('annonces')
          .select('id', { count: 'exact', head: true })
          .eq('uid_eleveur', user!.uid).eq('profil_source', 'particulier')
          .in('statut', ['disponible', 'reserve']);
        if ((count ?? 0) >= 5) { setError('Limite de 5 annonces actives atteinte.'); setSaving(false); return; }
      }

      // Profil particulier actif → géo + nom
      const q = supabase.from('user_profiles')
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
        statut: 'disponible',
        sexe,
        couleur: robe.trim() || null,
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

      if (editId) {
        const { error: e2 } = await supabase.from('annonces').update(payload).eq('id', editId);
        if (e2) throw new Error(e2.message);
      } else {
        const { error: e2 } = await supabase.from('annonces').insert({
          ...payload,
          id: genId(),
          created_at: new Date().toISOString(),
          expires_at: new Date(Date.now() + 60 * 86400000).toISOString(),
          vues: 0, contacts: 0,
        });
        if (e2) throw new Error(e2.message);
      }
      router.push('/mes-annonces');
    } catch (err) {
      setError(`Erreur : ${err instanceof Error ? err.message : String(err)}`);
    } finally { setSaving(false); }
  }

  const showCadence = formule === 'location' || formule === 'demi_pension' || formule === 'pension_complete';
  const allPreviews = [...existingPhotos, ...previews];

  return (
    <div className="max-w-2xl mx-auto px-4 py-10">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/mes-annonces" className="text-sm text-[#0C5C6C] hover:underline">← Mes annonces</Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-xl font-bold text-[#1F2A2E]">{editId ? 'Modifier l\'annonce' : 'Annonce cheval'}</h1>
      </div>

      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
        <form onSubmit={handleSubmit} className="space-y-5">

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">Formule</label>
            <div className="grid grid-cols-2 gap-2">
              {FORMULES.map(([v, l]) => (
                <button key={v} type="button" onClick={() => selectFormule(v)}
                  className={`py-2 rounded-xl text-sm font-medium border-2 transition-colors ${
                    formule === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-gray-300'
                  }`}>{l}</button>
              ))}
            </div>
          </div>

          <div className="relative">
            <label className="block text-sm font-medium text-gray-700 mb-1">Mon cheval <span className="text-gray-400 font-normal">(optionnel)</span></label>
            <button type="button"
              onClick={async () => { if (!showPicker) await loadMyHorses(); setShowPicker(!showPicker); }}
              className="w-full flex items-center gap-2 px-3 py-2.5 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6]">
              <span>🐴</span><span>{linkedNom ? `Lié : ${linkedNom}` : 'Lier un de mes chevaux'}</span>
            </button>
            {showPicker && (
              <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg max-h-56 overflow-y-auto">
                {myHorses.length === 0
                  ? <p className="text-sm text-gray-400 text-center py-4">Aucun cheval — saisie libre ci-dessous.</p>
                  : myHorses.map(h => (
                    <button key={h.id} type="button" onClick={() => pickHorse(h)}
                      className="w-full text-left px-3 py-2.5 hover:bg-[#E8F4F6] border-b border-gray-50 last:border-0">
                      <p className="text-sm font-semibold text-gray-800">{h.nom || 'Sans nom'}</p>
                      {h.race && <p className="text-xs text-gray-400">{h.race}</p>}
                    </button>
                  ))}
              </div>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Titre</label>
            <input value={titre} onChange={e => setTitre(e.target.value)} placeholder="Ex : Jument PS, 8 ans, prête club 1" className={iCls} />
          </div>

          {formule !== 'valorisation' && (
            <div className="flex gap-3 items-end">
              <div className="flex-1">
                <label className="block text-sm font-medium text-gray-700 mb-1">Prix (€)</label>
                <input type="number" min="0" value={prix} onChange={e => setPrix(e.target.value)}
                  disabled={prixUnite === 'convenir'} placeholder={prixUnite === 'convenir' ? 'À convenir' : '800'} className={iCls} />
              </div>
              {showCadence && (
                <select value={prixUnite} onChange={e => setPrixUnite(e.target.value as Cadence)} className={iSm + ' w-32'}>
                  <option value="mois">/ mois</option>
                  <option value="semaine">/ semaine</option>
                  <option value="convenir">à convenir</option>
                </select>
              )}
            </div>
          )}
          {formule !== 'valorisation' && (
            <label className="flex items-center gap-2 text-sm text-gray-700">
              <input type="checkbox" checked={prixNegociable} onChange={e => setPrixNegociable(e.target.checked)} />
              Prix négociable
            </label>
          )}

          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Race</label>
              <input value={race} onChange={e => setRace(e.target.value)} list="horse-breeds" placeholder="Selle Français, PS…" className={iCls} />
              <datalist id="horse-breeds">{breeds.map(b => <option key={b} value={b} />)}</datalist>
            </div>
            <div className="w-36">
              <label className="block text-sm font-medium text-gray-700 mb-1">Sexe</label>
              <select value={sexe} onChange={e => setSexe(e.target.value as typeof sexe)} className={iCls}>
                <option value="jument">Jument</option>
                <option value="hongre">Hongre</option>
                <option value="entier">Entier</option>
              </select>
            </div>
          </div>

          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Robe</label>
              <input value={robe} onChange={e => setRobe(e.target.value)} placeholder="Bai, alezan…" className={iCls} />
            </div>
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Date de naissance</label>
              <input type="date" value={dateNaissance} onChange={e => setDateNaissance(e.target.value)} className={iCls} />
            </div>
          </div>

          <div className="border border-amber-200 bg-amber-50 rounded-xl p-4">
            <label className="block text-xs font-semibold text-amber-800 mb-1">Numéro SIRE <span className="text-red-500">*</span></label>
            <input value={numSIRE} onChange={e => setNumSIRE(e.target.value)} placeholder="250 00X XXX XXX XXX"
              className={`${iCls} ${numSIRE.trim().length < 6 ? 'border-amber-300' : 'border-[#6E9E57]'}`} />
            <p className="text-xs text-amber-700 mt-1">Obligatoire pour tout équidé (Décret n°2013-879).</p>
          </div>

          <div className="border border-gray-100 rounded-xl p-4 space-y-3">
            <p className="text-sm font-semibold text-gray-700">🏆 Niveau &amp; résultats</p>
            <div className="flex flex-wrap gap-2">
              {NIVEAUX.map(n => (
                <button key={n} type="button" onClick={() => setNiveau(niveau === n ? '' : n)}
                  className={`px-3 py-1.5 rounded-full text-xs font-medium border transition-colors ${
                    niveau === n ? 'border-[#0C5C6C] bg-[#0C5C6C] text-white' : 'border-gray-200 text-gray-600 hover:border-gray-300'
                  }`}>{n}</button>
              ))}
            </div>
            <textarea value={palmares} onChange={e => setPalmares(e.target.value)} rows={3}
              placeholder="Palmarès / résultats (optionnel)" className={`${iSm} resize-none`} />
            <div className="flex gap-3">
              <input type="number" value={iso} onChange={e => setIso(e.target.value)} placeholder="ISO" className={iSm} />
              <input type="number" value={idr} onChange={e => setIdr(e.target.value)} placeholder="IDR" className={iSm} />
              <input type="number" value={icc} onChange={e => setIcc(e.target.value)} placeholder="ICC" className={iSm} />
            </div>
          </div>

          <div className="border border-gray-100 rounded-xl p-4 space-y-3">
            <p className="text-sm font-semibold text-gray-700">🎬 Vidéos</p>
            {([['monte', 'Sous selle', videoMonteUrl] as const, ['libre', 'En liberté', videoLibreUrl] as const]).map(([which, label, url]) => (
              <div key={which}>
                <label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
                {url ? (
                  <div className="flex items-center gap-2">
                    <video src={url} controls className="w-40 rounded-lg border border-gray-200" />
                    <button type="button" onClick={() => which === 'monte' ? setVideoMonteUrl(null) : setVideoLibreUrl(null)}
                      className="text-xs text-red-500 hover:text-red-700 font-medium">Retirer</button>
                  </div>
                ) : (
                  <label className="inline-flex items-center gap-2 px-3 py-2 border border-dashed border-gray-300 rounded-xl text-sm text-gray-500 cursor-pointer hover:border-[#0C5C6C] hover:text-[#0C5C6C]">
                    {uploadingVideo === which ? 'Envoi…' : '＋ Ajouter une vidéo'}
                    <input type="file" accept="video/*" className="hidden" disabled={uploadingVideo !== null}
                      onChange={e => handleVideo(e, which)} />
                  </label>
                )}
              </div>
            ))}
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Photos <span className="text-gray-400 font-normal">(max {MAX_PHOTOS})</span></label>
            <label className="flex items-center justify-center gap-2 w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-6 cursor-pointer text-gray-400 hover:text-[#0C5C6C]">
              <span className="text-2xl">📷</span><span className="text-sm font-medium">Choisir des photos</span>
              <input type="file" accept="image/*" multiple onChange={handlePhotos} className="hidden" />
            </label>
            {allPreviews.length > 0 && (
              <div className="flex gap-2 mt-3 flex-wrap">
                {allPreviews.map((p, i) => (
                  <div key={i} className="relative w-16 h-16 rounded-xl overflow-hidden border border-gray-200">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={p} alt="" className="w-full h-full object-cover" />
                    <button type="button"
                      onClick={() => {
                        if (i < existingPhotos.length) setExistingPhotos(prev => prev.filter((_, j) => j !== i));
                        else {
                          const k = i - existingPhotos.length;
                          setCroppedBlobs(prev => prev.filter((_, j) => j !== k));
                          setPreviews(prev => prev.filter((_, j) => j !== k));
                        }
                      }}
                      className="absolute top-0.5 right-0.5 w-4 h-4 bg-black/60 rounded-full text-white text-xs leading-none">×</button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={4}
              placeholder="Caractère, aptitudes, conditions…" className={`${iCls} resize-none`} />
          </div>

          {error && <p className="text-red-500 text-sm">{error}</p>}

          <button type="submit" disabled={saving}
            className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors">
            {saving ? 'Publication…' : editId ? 'Enregistrer' : 'Publier l\'annonce'}
          </button>
        </form>
      </div>

      {cropSrc && (
        <ImageCropModal src={cropSrc} aspect={1} title="Recadrer la photo"
          onConfirm={handleCropConfirm}
          onCancel={() => {
            if (cropSrc) URL.revokeObjectURL(cropSrc);
            setCropQueue(q => { if (q.length) { setCropSrc(URL.createObjectURL(q[0])); return q.slice(1); } setCropSrc(null); return []; });
          }} />
      )}
    </div>
  );
}

export default function CreerAnnonceChevalPage() {
  return (
    <Suspense fallback={<div className="min-h-screen flex items-center justify-center"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>}>
      <CreerAnnonceChevalInner />
    </Suspense>
  );
}
