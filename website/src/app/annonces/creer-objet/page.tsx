'use client';

import { Suspense, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { uploadPhoto } from '@/lib/upload-media';
import { fromPostalCode } from '@/lib/french-geo';
import {
  ANNONCE_OBJET_CATEGORIES, ANNONCE_OBJET_TRANSACTIONS, ANNONCE_OBJET_ETATS,
} from '@/lib/annonce-objet-categories';

const TEAL = '#0C5C6C';
const MAX_PHOTOS = 6;
const INTERDITS = ['chiot', 'chaton', 'à adopter', 'a adopter', 'portée de', 'portee de', 'lapereau'];

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
  const [existingPhotos, setExistingPhotos] = useState<string[]>([]);
  const [files, setFiles] = useState<File[]>([]);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');

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
      setExistingPhotos(data.photos ?? []);
    });
  }, [editId]);

  if (loading) return <div className="py-32 text-center text-gray-400">Chargement…</div>;
  if (!user) { router.push('/connexion'); return null; }

  const totalPhotos = existingPhotos.length + files.length;

  function addFiles(list: FileList | null) {
    if (!list) return;
    const room = MAX_PHOTOS - totalPhotos;
    setFiles(f => [...f, ...Array.from(list).slice(0, room)]);
  }

  async function submit() {
    setErr('');
    if (!titre.trim()) { setErr('Donnez un titre à votre annonce.'); return; }
    if (totalPhotos === 0) { setErr('Ajoutez au moins une photo.'); return; }
    const txt = `${titre} ${description}`.toLowerCase();
    if (INTERDITS.some(w => txt.includes(w))) {
      setErr('Cette rubrique est réservée au matériel. Pour un animal, utilisez « Trouver un compagnon ».');
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
        departement: geo?.departement ?? null,
        region: geo?.region ?? null,
        nom_vendeur: user!.displayName || 'Particulier',
        statut: 'disponible',
        updated_at: new Date().toISOString(),
      };
      if (editId) {
        const { error } = await supabase.from('annonces_objets').update(payload).eq('id', editId);
        if (error) throw error;
      } else {
        payload.created_at = new Date().toISOString();
        payload.expires_at = new Date(Date.now() + 60 * 86400_000).toISOString();
        const { error } = await supabase.from('annonces_objets').insert(payload);
        if (error) throw error;
      }
      router.push('/mes-annonces-materiel');
    } catch (e) {
      setSaving(false);
      setErr(e instanceof Error ? e.message : 'Erreur lors de l’enregistrement.');
    }
  }

  const cat = ANNONCE_OBJET_CATEGORIES.find(c => c.slug === categorie);

  return (
    <div className="max-w-xl mx-auto px-4 py-8 pb-24">
      <Link href="/mes-annonces-materiel" className="text-sm text-[#0C5C6C] hover:underline">← Mes annonces matériel</Link>
      <h1 className="text-2xl font-bold text-[#1F2A2E] mt-2 mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
        {editId ? 'Modifier l’annonce' : 'Publier une annonce'}
      </h1>
      <p className="text-sm text-gray-500 mb-5">
        Matériel lié aux animaux uniquement (cage, harnais, foin, location de prairie,
        matériel agricole…). La vente d’un animal n’est pas autorisée ici.
      </p>

      {/* Photos */}
      <label className="block text-sm font-semibold text-[#1F2A2E] mb-2">Photos ({totalPhotos}/{MAX_PHOTOS})</label>
      <div className="flex flex-wrap gap-2 mb-5">
        {existingPhotos.map((u, i) => (
          <div key={u} className="relative w-20 h-20">
            <img src={u} alt="" className="w-20 h-20 object-cover rounded-xl" />
            <button onClick={() => setExistingPhotos(p => p.filter((_, j) => j !== i))}
              className="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-black/60 text-white text-xs">×</button>
          </div>
        ))}
        {files.map((f, i) => (
          <div key={i} className="relative w-20 h-20">
            <img src={URL.createObjectURL(f)} alt="" className="w-20 h-20 object-cover rounded-xl" />
            <button onClick={() => setFiles(p => p.filter((_, j) => j !== i))}
              className="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-black/60 text-white text-xs">×</button>
          </div>
        ))}
        {totalPhotos < MAX_PHOTOS && (
          <label className="w-20 h-20 rounded-xl border-2 border-dashed border-gray-300 flex items-center justify-center text-2xl text-gray-400 cursor-pointer hover:border-[#0C5C6C]">
            +
            <input type="file" accept="image/*" multiple className="hidden" onChange={e => addFiles(e.target.files)} />
          </label>
        )}
      </div>

      <Field label="Titre">
        <input value={titre} onChange={e => setTitre(e.target.value)}
          placeholder="Ex : Cage à lapin XXL, Harnais taille L, Foin 2024…"
          className="w-full border border-gray-300 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
      </Field>

      <Field label="Catégorie">
        <select value={categorie} onChange={e => setCategorie(e.target.value)}
          className="w-full border border-gray-300 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
          {ANNONCE_OBJET_CATEGORIES.map(c => <option key={c.slug} value={c.slug}>{c.emoji} {c.label}</option>)}
        </select>
        {cat && <p className="text-xs text-gray-400 mt-1">{cat.exemples}</p>}
      </Field>

      <Field label="Type d’annonce">
        <div className="flex flex-wrap gap-2">
          {Object.entries(ANNONCE_OBJET_TRANSACTIONS).map(([k, v]) => (
            <button key={k} onClick={() => setTransaction(k)}
              className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-colors ${transaction === k ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'border-gray-300 text-gray-600 hover:border-[#0C5C6C]'}`}>
              {v}
            </button>
          ))}
        </div>
      </Field>

      {priced && (
        <>
          <Field label={transaction === 'location' ? 'Prix (par mois, €)' : 'Prix (€)'}>
            <input value={prix} onChange={e => setPrix(e.target.value.replace(/[^0-9.,]/g, ''))}
              inputMode="decimal"
              className="w-full border border-gray-300 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            <label className="flex items-center gap-2 mt-2 text-sm text-gray-600">
              <input type="checkbox" checked={negociable} onChange={e => setNegociable(e.target.checked)} className="accent-[#0C5C6C]" />
              Prix négociable
            </label>
          </Field>
          <Field label="État">
            <div className="flex flex-wrap gap-2">
              {Object.entries(ANNONCE_OBJET_ETATS).map(([k, v]) => (
                <button key={k} onClick={() => setEtat(etat === k ? '' : k)}
                  className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-colors ${etat === k ? 'bg-[#6E9E57] text-white border-[#6E9E57]' : 'border-gray-300 text-gray-600 hover:border-[#6E9E57]'}`}>
                  {v}
                </button>
              ))}
            </div>
          </Field>
        </>
      )}

      <Field label="Description">
        <textarea value={description} onChange={e => setDescription(e.target.value)} rows={5}
          placeholder="Dimensions, marque, état, retrait sur place / envoi…"
          className="w-full border border-gray-300 rounded-xl px-3 py-2.5 text-sm resize-none focus:outline-none focus:border-[#0C5C6C]" />
      </Field>

      <div className="grid grid-cols-3 gap-3">
        <div className="col-span-2">
          <Field label="Ville">
            <input value={ville} onChange={e => setVille(e.target.value)}
              className="w-full border border-gray-300 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
          </Field>
        </div>
        <Field label="Code postal">
          <input value={cp} onChange={e => setCp(e.target.value.replace(/\D/g, '').slice(0, 5))}
            inputMode="numeric"
            className="w-full border border-gray-300 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
        </Field>
      </div>

      {err && <p className="text-red-500 text-sm mt-2">{err}</p>}

      <button onClick={submit} disabled={saving}
        className="w-full mt-6 py-3.5 rounded-2xl text-white font-bold disabled:opacity-60"
        style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
        {saving ? 'Enregistrement…' : editId ? 'Enregistrer' : 'Publier gratuitement'}
      </button>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="mb-4">
      <label className="block text-sm font-semibold text-[#1F2A2E] mb-1.5">{label}</label>
      {children}
    </div>
  );
}

export default function CreerAnnonceObjetPage() {
  return (
    <Suspense fallback={<div className="py-32 text-center text-gray-400">Chargement…</div>}>
      <CreerObjetInner />
    </Suspense>
  );
}
