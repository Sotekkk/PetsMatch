'use client';

import { enregistrerModificationAnnonce } from '@/lib/annonce-paiement';
import { Suspense, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import {
  PageFormulaire, SectionFormulaire, Champ, Colonnes, CaseACocher, GrillePhotos, classeChamp, styleChamp,
} from '@/components/annonces/FormulaireAnnonce';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { uploadPhoto } from '@/lib/upload-media';
import { fromPostalCode, REGIONS_BY_PAYS, departmentsInRegion } from '@/lib/french-geo';
import {
  ANNONCE_OBJET_CATEGORIES, ANNONCE_OBJET_TRANSACTIONS, ANNONCE_OBJET_ETATS,
} from '@/lib/annonce-objet-categories';

const MAX_PHOTOS = 6;
const INTERDITS = ['chiot', 'chaton', 'à adopter', 'a adopter', 'portée de', 'portee de', 'lapereau'];

const apercusCache = new WeakMap<File, string>();
function apercuDe(f: File): string {
  let u = apercusCache.get(f);
  if (!u) { u = URL.createObjectURL(f); apercusCache.set(f, u); }
  return u;
}

function CreerObjetInner() {
  const router = useRouter();
  const params = useSearchParams();
  const editId = params.get('edit');
  const { user, loading, activeProfileId } = useAuth();

  const [titre, setTitre] = useState('');
  const [description, setDescription] = useState('');
  const [categorie, setCategorie] = useState(ANNONCE_OBJET_CATEGORIES[0].slug);
  const [transaction, setTransaction] = useState('vente');
  const [prix, setPrix] = useState('');
  const [negociable, setNegociable] = useState(false);
  const [etat, setEtat] = useState('');
  const [ville, setVille] = useState('');
  const [cp, setCp] = useState('');
  const [communes, setCommunes] = useState<string[]>([]);
  const [loadingCommunes, setLoadingCommunes] = useState(false);
  const [region, setRegion] = useState('');
  const [departement, setDepartement] = useState('');
  const [existingPhotos, setExistingPhotos] = useState<string[]>([]);
  const [files, setFiles] = useState<File[]>([]);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const [erreurs, setErreurs] = useState<Record<string, string>>({});
  const [avisPhotos, setAvisPhotos] = useState<string | null>(null);

  const priced = transaction === 'vente' || transaction === 'location';

  useEffect(() => {
    if (!editId) return;
    supabase.from('annonces_objets').select('*').eq('id', editId).maybeSingle().then(({ data }) => {
      if (!data) return;
      setTitre(data.titre ?? '');
      setDescription(data.description ?? '');
      setCategorie(data.categorie ?? ANNONCE_OBJET_CATEGORIES[0].slug);
      setTransaction(data.type_transaction ?? 'vente');
      setPrix(data.prix != null ? String(data.prix) : '');
      setNegociable(!!data.prix_negociable);
      setEtat(data.etat ?? '');
      setVille(data.ville ?? '');
      setCp(data.code_postal ?? '');
      setRegion(data.region ?? '');
      setDepartement(data.departement ?? '');
      if (data.ville) setCommunes([data.ville]);
      setExistingPhotos(data.photos ?? []);
    });
  }, [editId]);

  // Code postal → communes + région/département
  useEffect(() => {
    if (cp.length !== 5) { setCommunes([]); return; }
    const geo = fromPostalCode(cp);
    if (geo) { setRegion(geo.region); setDepartement(geo.departement); }
    setLoadingCommunes(true);
    fetch(`https://geo.api.gouv.fr/communes?codePostal=${cp}&fields=nom&format=json`)
      .then(r => r.json())
      .then((list: { nom: string }[]) => {
        const names = [...new Set((list ?? []).map(c => c.nom))].sort();
        setCommunes(names);
        setVille(v => (names.includes(v) ? v : names.length === 1 ? names[0] : ''));
      })
      .catch(() => setCommunes([]))
      .finally(() => setLoadingCommunes(false));
  }, [cp]);

  if (loading) return <div className="py-32 text-center text-gray-400">Chargement…</div>;
  if (!user) { router.push('/connexion'); return null; }

  const totalPhotos = existingPhotos.length + files.length;

  // Une ou plusieurs photos à chaque sélection, ajoutées à la suite des
  // précédentes (jamais en remplacement). Les fichiers sont copiés tout de
  // suite : le champ est vidé juste après pour permettre une nouvelle sélection.
  function addFiles(list: FileList | null) {
    const choisis = list ? Array.from(list) : [];
    if (!choisis.length) return;
    const room = Math.max(0, MAX_PHOTOS - totalPhotos);
    setAvisPhotos(choisis.length > room
      ? `Maximum ${MAX_PHOTOS} photos : ${choisis.length - room} photo${choisis.length - room > 1 ? 's n’ont' : ' n’a'} pas été ajoutée${choisis.length - room > 1 ? 's' : ''}.`
      : null);
    setFiles(f => [...f, ...choisis.slice(0, room)]);
  }

  async function submit() {
    setErr('');
    const e: Record<string, string> = {};
    if (!titre.trim()) e.titre = 'Donnez un titre à votre annonce.';
    if (totalPhotos === 0) e.photos = 'Ajoutez au moins une photo.';
    if (cp.trim().length !== 5) e.cp = 'Indiquez un code postal.';
    else if (!ville.trim()) e.ville = 'Sélectionnez votre commune.';
    setErreurs(e);
    const premiere = Object.values(e)[0];
    if (premiere) { setErr(premiere); return; }
    const txt = `${titre} ${description}`.toLowerCase();
    if (INTERDITS.some(w => txt.includes(w))) {
      setErr('Cette rubrique est réservée au matériel et aux équipements. Pour un animal, choisissez « Animal » dans « Publier une annonce ».');
      return;
    }
    setSaving(true);
    try {
      const uploaded: string[] = [];
      for (const f of files) {
        uploaded.push(await uploadPhoto(f, `annonces_objets/${user!.uid}/${Date.now()}_${uploaded.length}.jpg`));
      }
      const geo = fromPostalCode(cp.trim());
      const payload: Record<string, unknown> = {
        uid: user!.uid,
        ...(activeProfileId ? { profile_id: activeProfileId } : {}),
        titre: titre.trim(),
        categorie,
        type_transaction: transaction,
        prix: priced && prix.trim() ? Number(prix.replace(',', '.')) : null,
        prix_unite: transaction === 'location' ? '/mois' : null,
        prix_negociable: negociable,
        etat: priced && etat ? etat : null,
        description: description.trim(),
        photos: [...existingPhotos, ...uploaded],
        ville: ville.trim(),
        code_postal: cp.trim(),
        departement: departement || geo?.departement || null,
        region: region || geo?.region || null,
        nom_vendeur: user!.displayName || 'Particulier',
        statut: 'disponible',
        updated_at: new Date().toISOString(),
      };
      if (editId) {
        // Photos / disponibilité gratuites, le reste payant (4,99 €).
        const { statut: _statut, ...sansStatut } = payload; void _statut;
        const applique = await enregistrerModificationAnnonce('annonces_objets', editId, JSON.parse(JSON.stringify(sansStatut)));
        if (!applique) { setSaving(false); return; }
      } else {
        payload.created_at = new Date().toISOString();
        payload.expires_at = new Date(Date.now() + 60 * 86400_000).toISOString();
        const { error } = await supabase.from('annonces_objets').insert(payload);
        if (error) throw error;
      }
      router.push('/mes-annonces?type=materiel');
    } catch (e) {
      setSaving(false);
      setErr(e instanceof Error ? e.message : 'Erreur lors de l’enregistrement.');
    }
  }

  const cat = ANNONCE_OBJET_CATEGORIES.find(c => c.slug === categorie);

  const apercus = files.map(f => apercuDe(f));
  const choix = (actif: boolean) => `min-h-10 px-3.5 rounded-xl text-sm font-semibold border transition-colors ${actif ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-700 hover:border-[#0C5C6C]/50'}`;
  const retour = editId ? '/mes-annonces?type=materiel' : '/annonces/publier';

  return (
    <PageFormulaire retourHref={retour} retourLabel={editId ? 'Retour à mes annonces' : 'Publier une annonce'}
      titre={editId ? 'Modifier l’annonce' : 'Matériel & équipements'}
      sousTitre="Matériel destiné aux animaux et aux activités professionnelles : paniers, grilles de chenil, parcs, caisses de transport, équipements de mise bas… La vente d’un animal n’est pas autorisée ici."
      erreur={err} onSubmit={ev => { ev.preventDefault(); submit(); }} annulerHref={retour} enregistrement={saving}
      libelleEnregistrer={editId ? 'Enregistrer les modifications' : 'Publier gratuitement'}>

      <SectionFormulaire titre="Informations principales">
        <Champ label="Titre" requis htmlFor="titre" erreur={erreurs.titre}>
          <input id="titre" value={titre} onChange={e => setTitre(e.target.value)}
            placeholder="Ex : Cage à lapin XXL, Harnais taille L, Foin 2024…" className={classeChamp} style={styleChamp} />
        </Champ>
        <Colonnes>
          <Champ label="Catégorie" htmlFor="categorie" aide={cat?.exemples}>
            <select id="categorie" value={categorie} onChange={e => setCategorie(e.target.value)} className={classeChamp} style={styleChamp}>
              {ANNONCE_OBJET_CATEGORIES.map(c => <option key={c.slug} value={c.slug}>{c.label}</option>)}
            </select>
          </Champ>
          <Champ label="Type d’annonce">
            <div className="flex flex-wrap gap-2">
              {Object.entries(ANNONCE_OBJET_TRANSACTIONS).map(([k, v]) => (
                <button key={k} type="button" onClick={() => setTransaction(k)} aria-pressed={transaction === k}
                  className={choix(transaction === k)} style={transaction === k ? undefined : styleChamp}>{v}</button>
              ))}
            </div>
          </Champ>
        </Colonnes>
      </SectionFormulaire>

      <SectionFormulaire titre="Photos et médias">
        <Champ label="Photos" requis erreur={erreurs.photos} aide={`Jusqu’à ${MAX_PHOTOS} photos ; la première est la photo principale.`}>
          <GrillePhotos max={MAX_PHOTOS}
            photos={[...existingPhotos.map((u, i) => ({ url: u, cle: `e${i}${u}` })), ...apercus.map((u, i) => ({ url: u, cle: `n${i}` }))]}
            onAjouter={e => { addFiles(e.target.files); e.target.value = ''; }}
            onRetirer={i => i < existingPhotos.length
              ? setExistingPhotos(p => p.filter((_, j) => j !== i))
              : setFiles(p => p.filter((_, j) => j !== i - existingPhotos.length))} />
          {avisPhotos && <p role="status" className="text-xs font-semibold text-[#B45309] mt-2">{avisPhotos}</p>}
        </Champ>
      </SectionFormulaire>

      <SectionFormulaire titre="Description">
        <Champ label="Présentation" htmlFor="description">
          <textarea id="description" value={description} onChange={e => setDescription(e.target.value)} rows={5}
            placeholder="Dimensions, marque, état, retrait sur place / envoi…" className={`${classeChamp} resize-y`} style={styleChamp} />
        </Champ>
      </SectionFormulaire>

      {priced && (
        <SectionFormulaire titre="Prix et état">
          <Colonnes>
            <Champ label={transaction === 'location' ? 'Prix (par mois, €)' : 'Prix (€)'} htmlFor="prix">
              <input id="prix" value={prix} onChange={e => setPrix(e.target.value.replace(/[^0-9.,]/g, ''))} inputMode="decimal"
                className={classeChamp} style={styleChamp} />
            </Champ>
            <div className="sm:pt-7"><CaseACocher label="Prix négociable" checked={negociable} onChange={setNegociable} /></div>
          </Colonnes>
          <Champ label="État">
            <div className="flex flex-wrap gap-2">
              {Object.entries(ANNONCE_OBJET_ETATS).map(([k, v]) => (
                <button key={k} type="button" onClick={() => setEtat(etat === k ? '' : k)} aria-pressed={etat === k}
                  className={choix(etat === k)} style={etat === k ? undefined : styleChamp}>{v}</button>
              ))}
            </div>
          </Champ>
        </SectionFormulaire>
      )}

      <SectionFormulaire titre="Localisation">
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Champ label="Code postal" requis htmlFor="cp" erreur={erreurs.cp}>
            <input id="cp" value={cp} onChange={e => setCp(e.target.value.replace(/\D/g, '').slice(0, 5))}
              inputMode="numeric" placeholder="5 chiffres" className={classeChamp} style={styleChamp} />
          </Champ>
          <div className="sm:col-span-2">
            <Champ label="Commune" requis htmlFor="commune" erreur={erreurs.ville}>
              {loadingCommunes ? (
                <p className="text-sm text-gray-500 min-h-11 flex items-center">Recherche des communes…</p>
              ) : communes.length === 0 ? (
                <p className="text-sm text-gray-500 min-h-11 flex items-center">
                  {cp.length === 5 ? 'Aucune commune pour ce code postal.' : 'Saisissez d’abord le code postal.'}
                </p>
              ) : communes.length === 1 ? (
                <div className={`${classeChamp} bg-[#F3F6F5] flex items-center`} style={styleChamp}>{communes[0]}</div>
              ) : (
                <select id="commune" value={ville} onChange={e => setVille(e.target.value)} className={classeChamp} style={styleChamp}>
                  <option value="">Sélectionnez votre commune</option>
                  {communes.map(c => <option key={c} value={c}>{c}</option>)}
                </select>
              )}
            </Champ>
          </div>
        </div>
        <Colonnes>
          <Champ label="Région" htmlFor="region">
            <select id="region" value={region} onChange={e => { setRegion(e.target.value); setDepartement(''); }} className={classeChamp} style={styleChamp}>
              <option value="">Région</option>
              {REGIONS_BY_PAYS.France.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </Champ>
          <Champ label="Département" htmlFor="departement">
            <select id="departement" value={departement} onChange={e => setDepartement(e.target.value)} disabled={!region}
              className={`${classeChamp} disabled:bg-gray-50 disabled:text-gray-400`} style={styleChamp}>
              <option value="">{region ? 'Département' : 'Choisissez une région'}</option>
              {region && departmentsInRegion(region).map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </Champ>
        </Colonnes>
      </SectionFormulaire>
    </PageFormulaire>
  );
}

export default function CreerAnnonceObjetPage() {
  return (
    <Suspense fallback={<div className="py-32 text-center text-gray-400">Chargement…</div>}>
      <CreerObjetInner />
    </Suspense>
  );
}
