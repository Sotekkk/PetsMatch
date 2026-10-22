'use client';
/* eslint-disable @next/next/no-img-element */

// « Recommander un lieu » (particulier) : recherche préalable (pas de doublon),
// informations, conditions d'accueil (oui / non / je ne sais pas), expérience,
// vérification → fiche « en attente de validation » (modération admin).
// Miroir appli : lib/pages/lieux/recommander_lieu_page.dart.

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { uploadPhoto } from '@/lib/upload-media';
import AddressAutocomplete from '@/components/AddressAutocomplete';
import { ESPECES_LIEUX } from '@/lib/especes-lieux';
import { TYPES_LIEU, referencementLieu, LIBELLE_REFERENCEMENT } from '@/lib/lieux-categories';

type Trouve = { id: string; nom: string; ville?: string | null; adresse?: string | null; uid_pro?: string | null; plan?: string | null; verification?: string | null; lat?: number | null; lng?: number | null };
type TroisEtats = boolean | null;

const TITRES = ['Recommander un lieu', 'Le lieu', "Conditions d'accueil", 'Votre expérience', 'Vérification'];
const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]';

function distance(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const r = Math.PI / 180, dLat = (b.lat - a.lat) * r, dLng = (b.lng - a.lng) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(h));
}

export default function RecommanderLieuPage() {
  const { user, loading, activeProfileId } = useAuth();
  const router = useRouter();
  const [etape, setEtape] = useState(0);
  const [erreur, setErreur] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [envoye, setEnvoye] = useState(false);

  // Étape 1
  const [q, setQ] = useState('');
  const [trouves, setTrouves] = useState<Trouve[]>([]);
  const [cherche, setCherche] = useState(false);
  // Étape 2
  const [nom, setNom] = useState('');
  const [type, setType] = useState('');
  const [adresse, setAdresse] = useState('');
  const [lieu, setLieu] = useState<{ rue: string; codePostal: string; ville: string; lat: number; lng: number } | null>(null);
  const [site, setSite] = useState('');
  const [tel, setTel] = useState('');
  // Étape 3
  const [especes, setEspeces] = useState<string[]>([]);
  const [interieur, setInterieur] = useState<TroisEtats>(null);
  const [terrasse, setTerrasse] = useState<TroisEtats>(null);
  const [taille, setTaille] = useState<TroisEtats>(null);
  const [supplement, setSupplement] = useState<TroisEtats>(null);
  const [nb, setNb] = useState('');
  const [conditions, setConditions] = useState('');
  const [visite, setVisite] = useState('');
  // Étape 4
  const [pourquoi, setPourquoi] = useState('');
  const [photos, setPhotos] = useState<File[]>([]);
  // Fiche existante à compléter (?id=) : préremplie, mise à jour, renvoyée en validation.
  const [existantId, setExistantId] = useState<string | null>(null);
  const [photosExistantes, setPhotosExistantes] = useState<string[]>([]);

  useEffect(() => {
    const idEdit = new URLSearchParams(window.location.search).get('id');
    if (!idEdit || !user) return;
    supabase.from('petfriendly_places').select('*').eq('id', idEdit).eq('ajoute_par_uid', user.uid).maybeSingle()
      .then(({ data }) => {
        if (!data) return;
        const e = data as Record<string, unknown>;
        setExistantId(idEdit); setEtape(1);
        setNom(String(e.nom ?? '')); setType(String(e.sous_categorie ?? ''));
        const rue = String(e.adresse ?? ''), cp = String(e.code_postal ?? ''), ville = String(e.ville ?? '');
        setAdresse([rue, cp, ville].filter(Boolean).join(' '));
        if (e.lat != null && e.lng != null) setLieu({ rue, codePostal: cp, ville, lat: Number(e.lat), lng: Number(e.lng) });
        setSite(String(e.site_web ?? '')); setTel(String(e.telephone ?? ''));
        setEspeces((e.especes_acceptees as string[] | null) ?? []);
        setInterieur((e.animaux_en_salle as boolean | null) ?? null); setTerrasse((e.terrasse as boolean | null) ?? null);
        setTaille((e.restriction_taille as boolean | null) ?? null); setSupplement((e.supplement_animal as boolean | null) ?? null);
        setNb(e.nb_animaux_max != null ? String(e.nb_animaux_max) : ''); setConditions(String(e.conditions_particulieres ?? ''));
        setVisite(String(e.derniere_confirmation_le ?? '')); setPourquoi(String(e.recommandation ?? ''));
        setPhotosExistantes((e.photos as string[] | null) ?? []); setConfirme(true);
      });
  }, [user]);
  const [confirme, setConfirme] = useState(false);
  // Doublons probables avant envoi
  const [proches, setProches] = useState<Trouve[]>([]);

  const cols = 'id, nom, ville, adresse, uid_pro, plan, verification, lat, lng';

  useEffect(() => {
    const t = q.trim();
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (t.length < 2) { setTrouves([]); return; }
    const h = setTimeout(async () => {
      setCherche(true);
      const motif = `%${t.replace(/[%,()]/g, '')}%`;
      const { data } = await supabase.from('petfriendly_places').select(cols).eq('statut', 'actif')
        .or(`nom.ilike.${motif},ville.ilike.${motif},adresse.ilike.${motif}`).limit(20);
      setTrouves((data ?? []) as Trouve[]);
      setCherche(false);
    }, 350);
    return () => clearTimeout(h);
  }, [q]);

  function autourDeMoi() {
    if (!navigator.geolocation) { setErreur('Localisation indisponible : recherchez par nom ou par ville.'); return; }
    setCherche(true);
    navigator.geolocation.getCurrentPosition(async pos => {
      const d = 0.02, { latitude: la, longitude: lo } = pos.coords;
      const { data } = await supabase.from('petfriendly_places').select(cols).eq('statut', 'actif')
        .gte('lat', la - d).lte('lat', la + d).gte('lng', lo - d * 1.5).lte('lng', lo + d * 1.5).limit(30);
      setTrouves((data ?? []) as Trouve[]);
      setCherche(false);
    }, () => { setCherche(false); setErreur('Localisation refusée : recherchez par nom ou par ville.'); });
  }

  function valider(): string {
    if (etape === 1) {
      if (!nom.trim()) return 'Indiquez le nom du lieu.';
      if (!type) return 'Choisissez une catégorie.';
      if (!lieu) return "Choisissez l'adresse dans la liste pour placer le lieu sur la carte.";
    }
    if (etape === 2) {
      if (!especes.length) return 'Indiquez au moins une espèce accueillie.';
      if (!visite) return 'Indiquez la date de votre dernière visite.';
    }
    if (etape === 3) {
      if (pourquoi.trim().length < 10) return 'Dites en quelques mots pourquoi vous recommandez ce lieu.';
      if (!confirme) return 'Merci de cocher la confirmation.';
    }
    return '';
  }

  async function suivant() {
    const e = valider();
    setErreur(e);
    if (e) return;
    if (etape === 3 && lieu) {
      const d = 0.003;
      const { data } = await supabase.from('petfriendly_places').select(cols).eq('statut', 'actif')
        .gte('lat', lieu.lat - d).lte('lat', lieu.lat + d).gte('lng', lieu.lng - d).lte('lng', lieu.lng + d);
      setProches(((data ?? []) as Trouve[]).filter(p => p.lat != null && p.lng != null && distance(lieu, { lat: p.lat, lng: p.lng }) < 150));
    }
    setEtape(x => x + 1);
  }

  async function envoyer() {
    if (!user || !lieu) return;
    setEnvoi(true); setErreur('');
    try {
      const t = TYPES_LIEU.find(x => x.value === type)!;
      const dossier = `${user.uid}_${Date.now()}`;
      const urls: string[] = [];
      for (let i = 0; i < photos.length; i++) urls.push(await uploadPhoto(photos[i], `lieux/communaute/${dossier}/photo_${i}.jpg`));
      const donnees = {
        nom: nom.trim(), categorie: t.categorie, sous_categorie: t.value,
        adresse: lieu.rue, code_postal: lieu.codePostal || null, ville: lieu.ville, lat: lieu.lat, lng: lieu.lng,
        site_web: site.trim() || null, telephone: tel.trim() || null,
        especes_acceptees: especes,
        // Je ne sais pas = null : jamais transformé en « oui ».
        animaux_en_salle: interieur, terrasse, restriction_taille: taille, supplement_animal: supplement,
        nb_animaux_max: nb.trim() ? Number(nb) : null,
        conditions_particulieres: conditions.trim() || null,
        derniere_confirmation_le: visite,
        recommandation: pourquoi.trim(), photos: [...photosExistantes, ...urls],
        statut: 'en_attente_validation',
      };
      const { error } = existantId
        ? await supabase.from('petfriendly_places').update(donnees).eq('id', existantId)
        : await supabase.from('petfriendly_places').insert({
            ...donnees, origine: 'communaute', source_conditions: 'communaute', ajoute_par_uid: user.uid,
            ...(activeProfileId ? { ajoute_par_profile_id: activeProfileId } : {}),
          });
      if (error) throw error;
      setEnvoye(true);
    } catch (e) {
      setErreur(`Envoi impossible : ${(e as Error).message}`);
    } finally { setEnvoi(false); }
  }

  if (loading) return null;
  if (!user) {
    return (
      <div className="max-w-xl mx-auto px-4 py-16 text-center space-y-3" style={{ fontFamily: 'Galey, sans-serif' }}>
        <h1 className="text-2xl font-bold text-[#1F2A2E]">Recommander un lieu</h1>
        <p className="text-gray-600">Connectez-vous pour recommander un lieu qui accueille les animaux.</p>
        <Link href="/connexion?suite=/animal-friendly/recommander" className="inline-block px-5 py-2.5 rounded-xl bg-[#0C5C6C] text-white font-semibold">Se connecter</Link>
      </div>
    );
  }
  if (envoye) {
    return (
      <div className="max-w-xl mx-auto px-4 py-16 text-center space-y-3" style={{ fontFamily: 'Galey, sans-serif' }}>
        <h1 className="text-2xl font-bold text-[#1F2A2E]">{existantId ? 'Fiche renvoyée en validation' : 'Merci pour votre recommandation'}</h1>
        <p className="text-gray-600">Votre proposition est en attente de validation. Vous serez prévenu(e) dès qu&apos;elle sera publiée, ou si des précisions sont nécessaires.</p>
        <Link href="/animal-friendly" className="inline-block px-5 py-2.5 rounded-xl bg-[#0C5C6C] text-white font-semibold">Retour aux lieux</Link>
      </div>
    );
  }

  const troisEtats = (libelle: string, valeur: TroisEtats, set: (v: TroisEtats) => void) => (
    <fieldset className="py-3 border-b border-gray-100 last:border-0">
      <legend className="text-sm font-bold text-[#1F2A2E] mb-2">{libelle}</legend>
      <div className="grid grid-cols-3 gap-2">
        {([['Oui', true], ['Non', false], ['Je ne sais pas', null]] as [string, TroisEtats][]).map(([t, v]) => (
          <button key={t} type="button" onClick={() => set(v)} aria-pressed={valeur === v}
            className={`py-2 rounded-xl border text-sm ${valeur === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C] font-bold' : 'border-gray-200 bg-white text-gray-700'}`}>
            {t}
          </button>
        ))}
      </div>
    </fieldset>
  );
  const etat = (v: TroisEtats) => (v === true ? 'Oui' : v === false ? 'Non' : 'Non renseigné');

  return (
    <div className="bg-[#F4F7F6] min-h-screen pb-16" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="bg-[#0C5C6C] text-white">
        <div className="max-w-2xl mx-auto px-4 py-6">
          <p className="text-xs text-white/70">Étape {etape + 1} sur 5</p>
          <h1 className="text-2xl font-bold">{TITRES[etape]}</h1>
          <div className="mt-3 h-1 rounded-full bg-white/25"><div className="h-1 rounded-full bg-white" style={{ width: `${(etape + 1) * 20}%` }} /></div>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">
        {etape === 0 && (<>
          <p className="text-sm text-gray-700">Vérifions d&apos;abord que le lieu n&apos;est pas déjà sur PetsMatch.</p>
          <label htmlFor="q" className="sr-only">Nom, adresse ou ville</label>
          <input id="q" value={q} onChange={e => setQ(e.target.value)} placeholder="Nom, adresse ou ville" className={inputCls} />
          <button type="button" onClick={autourDeMoi} className="w-full py-2.5 rounded-xl border border-gray-200 bg-white text-sm font-bold text-[#0C5C6C]">Autour de moi</button>
          {cherche && <p className="text-sm text-gray-500">Recherche…</p>}
          {trouves.length > 0 && (
            <div className="space-y-2">
              <p className="text-xs font-bold uppercase tracking-wide text-gray-500">Déjà sur PetsMatch</p>
              {trouves.map(t => (
                <div key={t.id} className="bg-white rounded-2xl p-4 shadow-sm">
                  <p className="font-bold text-[#1F2A2E]">{t.nom}</p>
                  <p className="text-xs text-gray-500">{[t.adresse, t.ville, LIBELLE_REFERENCEMENT[referencementLieu(t)]].filter(Boolean).join(' · ')}</p>
                  <p className="text-sm text-gray-700 mt-2">Ce lieu est déjà référencé. Souhaitez-vous partager votre expérience ou proposer une modification ?</p>
                  <Link href={`/animal-friendly/${t.id}`} className="inline-block mt-2 px-4 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-bold">Voir la fiche</Link>
                </div>
              ))}
            </div>
          )}
          <div className="pt-4 text-center space-y-2">
            <p className="text-sm text-gray-500">Le lieu n&apos;apparaît pas dans la liste ?</p>
            <button type="button" onClick={() => { if (!nom) setNom(q.trim()); setEtape(1); }}
              className="w-full py-3 rounded-xl bg-[#0C5C6C] text-white font-bold">Ajouter ce lieu</button>
          </div>
        </>)}

        {etape === 1 && (<>
          <div><label htmlFor="nom" className="text-sm font-bold block mb-1">Nom de l&apos;établissement *</label>
            <input id="nom" value={nom} onChange={e => setNom(e.target.value)} className={inputCls} /></div>
          <div><label htmlFor="type" className="text-sm font-bold block mb-1">Catégorie *</label>
            <select id="type" value={type} onChange={e => setType(e.target.value)} className={inputCls}>
              <option value="">Choisir…</option>
              {TYPES_LIEU.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select></div>
          <div><p className="text-sm font-bold mb-1">Adresse *</p>
            <AddressAutocomplete value={adresse} onChange={setAdresse} placeholder="Commencez à taper puis choisissez" className={inputCls}
              onSelectDetails={d => setLieu(d)} />
            {lieu && <p className="text-xs text-[#0C5C6C] mt-1">Lieu placé sur la carte : {lieu.rue}, {lieu.codePostal} {lieu.ville}</p>}</div>
          <div><label htmlFor="site" className="text-sm font-bold block mb-1">Site internet (facultatif)</label>
            <input id="site" value={site} onChange={e => setSite(e.target.value)} className={inputCls} /></div>
          <div><label htmlFor="tel" className="text-sm font-bold block mb-1">Téléphone public (facultatif)</label>
            <input id="tel" value={tel} onChange={e => setTel(e.target.value)} className={inputCls} /></div>
        </>)}

        {etape === 2 && (<>
          <p className="text-sm text-gray-600">Répondez selon ce que vous avez constaté. « Je ne sais pas » restera affiché comme non renseigné.</p>
          <div>
            <p className="text-sm font-bold mb-1">Espèces accueillies (une ou plusieurs) *</p>
            <details className="group border border-gray-200 rounded-xl bg-white">
              <summary className="list-none cursor-pointer flex items-center justify-between px-3 py-2.5 text-sm">
                <span className={especes.length ? 'text-[#1F2A2E]' : 'text-gray-400'}>
                  {especes.length === 0 ? 'Choisir les espèces' : especes.length === ESPECES_LIEUX.length ? 'Toutes les espèces'
                    : ESPECES_LIEUX.filter(e => especes.includes(e.value)).map(e => e.label).join(', ')}
                </span>
                <svg className="w-4 h-4 text-gray-400 transition-transform group-open:rotate-180" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" /></svg>
              </summary>
              <div className="border-t border-gray-100 py-1">
                <label className="flex items-center gap-3 px-3 py-2 text-sm font-semibold"><input type="checkbox" className="w-4 h-4 accent-[#0C5C6C]"
                  checked={especes.length === ESPECES_LIEUX.length} onChange={e => setEspeces(e.target.checked ? ESPECES_LIEUX.map(x => x.value) : [])} />Tout cocher</label>
                {ESPECES_LIEUX.map(e => (
                  <label key={e.value} className="flex items-center gap-3 px-3 py-2 text-sm"><input type="checkbox" className="w-4 h-4 accent-[#0C5C6C]"
                    checked={especes.includes(e.value)} onChange={() => setEspeces(p => p.includes(e.value) ? p.filter(x => x !== e.value) : [...p, e.value])} />{e.label}</label>
                ))}
              </div>
            </details>
          </div>
          <div className="bg-white rounded-2xl px-4">
            {troisEtats("Accès à l'intérieur", interieur, setInterieur)}
            {troisEtats('Terrasse ou extérieur', terrasse, setTerrasse)}
            {troisEtats('Restriction de taille constatée', taille, setTaille)}
            {troisEtats('Supplément tarifaire', supplement, setSupplement)}
          </div>
          <div><label htmlFor="nb" className="text-sm font-bold block mb-1">Nombre d&apos;animaux autorisés (si connu)</label>
            <input id="nb" type="number" min={1} value={nb} onChange={e => setNb(e.target.value)} className={inputCls} /></div>
          <div><label htmlFor="cond" className="text-sm font-bold block mb-1">Conditions particulières</label>
            <textarea id="cond" rows={2} value={conditions} onChange={e => setConditions(e.target.value)} placeholder="Ex. laisse obligatoire en salle" className={inputCls} /></div>
          <div><label htmlFor="visite" className="text-sm font-bold block mb-1">Date de votre dernière visite *</label>
            <input id="visite" type="date" max={new Date().toISOString().slice(0, 10)} value={visite} onChange={e => setVisite(e.target.value)} className={inputCls} /></div>
        </>)}

        {etape === 3 && (<>
          <div><label htmlFor="pourquoi" className="text-sm font-bold block mb-1">Pourquoi recommandez-vous ce lieu ? *</label>
            <textarea id="pourquoi" rows={5} maxLength={1500} value={pourquoi} onChange={e => setPourquoi(e.target.value)}
              placeholder="Votre expérience avec votre animal" className={inputCls} /></div>
          <div>
            <p className="text-sm font-bold mb-1">Photos (facultatif, prises par vous)</p>
            <div className="flex flex-wrap gap-2">
              {photos.map((f, i) => (
                <div key={i} className="relative">
                  <img src={URL.createObjectURL(f)} alt="" className="w-20 h-20 object-cover rounded-xl" />
                  <button type="button" aria-label="Retirer la photo" onClick={() => setPhotos(p => p.filter((_, j) => j !== i))}
                    className="absolute top-0.5 right-0.5 w-6 h-6 rounded-full bg-black/60 text-white text-xs">✕</button>
                </div>
              ))}
              {photos.length < 6 && (
                <label className="w-20 h-20 rounded-xl border border-dashed border-gray-300 flex items-center justify-center text-[#0C5C6C] text-xs font-bold cursor-pointer bg-white">
                  Ajouter
                  <input type="file" accept="image/*" multiple className="hidden"
                    onChange={e => setPhotos(p => [...p, ...Array.from(e.target.files ?? [])].slice(0, 6))} />
                </label>
              )}
            </div>
          </div>
          <label className="flex items-start gap-3 text-sm text-gray-700">
            <input type="checkbox" checked={confirme} onChange={e => setConfirme(e.target.checked)} className="mt-1 w-4 h-4 accent-[#0C5C6C]" />
            Je confirme que les informations communiquées correspondent à mon expérience ou à des éléments que je peux raisonnablement vérifier, et que les photos ont été prises par moi.
          </label>
        </>)}

        {etape === 4 && (<>
          {proches.length > 0 && (
            <div className="bg-[#FDF6EC] border border-[#F1D9B5] rounded-xl p-3 text-sm text-[#6B4A12]">
              <p className="font-bold">Un lieu très proche existe déjà. S&apos;agit-il du même ?</p>
              {proches.map(p => <Link key={p.id} href={`/animal-friendly/${p.id}`} className="block mt-1 font-semibold underline">Oui, voir « {p.nom} »</Link>)}
            </div>
          )}
          <div className="bg-white rounded-2xl p-5 space-y-1 text-sm">
            <p className="text-lg font-bold text-[#1F2A2E]">{nom}</p>
            <p className="text-gray-600">{TYPES_LIEU.find(t => t.value === type)?.label} · {lieu?.rue}, {lieu?.codePostal} {lieu?.ville}</p>
            <p className="pt-2">Espèces : {ESPECES_LIEUX.filter(e => especes.includes(e.value)).map(e => e.label).join(', ')}</p>
            <p>Intérieur : {etat(interieur)} · Terrasse : {etat(terrasse)}</p>
            <p>Taille : {etat(taille)} · Supplément : {etat(supplement)}</p>
            {visite && <p>Dernière visite : {new Date(visite).toLocaleDateString('fr-FR')}</p>}
            <p className="pt-2 italic text-gray-700">« {pourquoi.trim()} »</p>
          </div>
          <p className="text-xs text-gray-500">Votre recommandation sera vérifiée par l&apos;équipe PetsMatch avant d&apos;apparaître sur la carte, avec la mention « Recommandé par la communauté ». Votre nom n&apos;est pas affiché publiquement avec la fiche.</p>
        </>)}

        {erreur && <p className="text-sm text-red-600">{erreur}</p>}

        {etape > 0 && (
          <div className="flex gap-3 pt-2">
            <button type="button" disabled={envoi} onClick={() => { setErreur(''); setEtape(x => x - 1); }}
              className="flex-1 py-3 rounded-xl border border-gray-200 bg-white font-bold text-gray-700">Retour</button>
            <button type="button" disabled={envoi} onClick={etape === 4 ? envoyer : suivant}
              className="flex-[2] py-3 rounded-xl bg-[#0C5C6C] text-white font-bold disabled:opacity-50">
              {envoi ? 'Envoi…' : etape === 4 ? (existantId ? 'Renvoyer en validation' : 'Envoyer ma recommandation') : 'Continuer'}
            </button>
          </div>
        )}
        {etape === 0 && <button type="button" onClick={() => router.back()} className="text-sm text-gray-500 underline">Annuler</button>}
      </div>
    </div>
  );
}
