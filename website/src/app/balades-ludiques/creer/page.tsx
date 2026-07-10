'use client';

import { useEffect, useState, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import dynamic from 'next/dynamic';
import { doc, getDoc } from 'firebase/firestore';
import { QRCodeSVG } from 'qrcode.react';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { uploadBlob } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';
import { ESPECES, DIFFICULTES, TYPES_DEFI, dureeLabel, especeLabel, difficulteLabel, typeDefiIcon } from '../shared';
import type { EditablePoint } from '@/components/BaladesLudiquesPointsEditor';

const PointsEditor = dynamic(() => import('@/components/BaladesLudiquesPointsEditor'), {
  ssr: false,
  loading: () => <div className="flex items-center justify-center h-full bg-gray-100">
    <div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" /></div>,
});

interface PointDraft extends EditablePoint {
  description?: string;
  rayon_validation_m: number;
  type_defi: string;
  question_texte?: string;
  question_reponse?: string;
  consigne_texte?: string;
  qr_code_value?: string;
  indice?: string;
}

function genQrCode() {
  return `BL-${Date.now()}`;
}

function CreerBaladeContent() {
  const { user } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const editId = params.get('edit');
  const [isAdmin, setIsAdmin] = useState(false);

  useEffect(() => {
    if (!user) { setIsAdmin(false); return; }
    getDoc(doc(db, 'users', user.uid)).then(snap => setIsAdmin(snap.exists() && snap.data()?.isAdmin === true));
  }, [user]);

  const [step, setStep] = useState(0);
  const [loadingEdit, setLoadingEdit] = useState(!!editId);
  const [publishing, setPublishing] = useState(false);

  const [titre, setTitre] = useState('');
  const [description, setDescription] = useState('');
  const [coverFile, setCoverFile] = useState<File | null>(null);
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [coverUrl, setCoverUrl] = useState<string | null>(null);
  const [espece, setEspece] = useState('tous');
  const [famille, setFamille] = useState(false);
  const [sportif, setSportif] = useState(false);
  const [pmr, setPmr] = useState(false);
  const [gratuit, setGratuit] = useState(true);
  const [prix, setPrix] = useState('');
  const [difficulte, setDifficulte] = useState('facile');
  const [duree, setDuree] = useState('');
  const [distance, setDistance] = useState('');
  const [typeEvenement, setTypeEvenement] = useState('communautaire');
  const [partenaireNom, setPartenaireNom] = useState('');
  const [eventDebut, setEventDebut] = useState('');
  const [eventFin, setEventFin] = useState('');

  const [points, setPoints] = useState<PointDraft[]>([]);
  const [editingPoint, setEditingPoint] = useState<number | null>(null);

  useEffect(() => {
    if (!editId || !user) return;
    (async () => {
      const { data: b } = await supabase.from('balades_ludiques').select('*').eq('id', editId).single();
      const { data: pts } = await supabase.from('balades_ludiques_points').select('*').eq('balade_id', editId).order('ordre');
      if (b) {
        setTitre(b.titre ?? ''); setDescription(b.description ?? ''); setCoverUrl(b.cover_url ?? null);
        setEspece(b.espece_cible ?? 'tous'); setFamille(!!b.famille); setSportif(!!b.sportif); setPmr(!!b.accessible_pmr);
        setGratuit(b.gratuit ?? true); setPrix(b.prix?.toString() ?? ''); setDifficulte(b.difficulte ?? 'facile');
        setDuree(b.duree_min?.toString() ?? ''); setDistance(b.distance_km?.toString() ?? '');
        setTypeEvenement(b.type_evenement ?? 'communautaire'); setPartenaireNom(b.partenaire_nom ?? '');
        setEventDebut(b.event_debut ? b.event_debut.slice(0, 10) : ''); setEventFin(b.event_fin ? b.event_fin.slice(0, 10) : '');
      }
      setPoints((pts ?? []).map((p: PointDraft) => ({ ...p })));
      setLoadingEdit(false);
    })();
  }, [editId, user]);

  function handleCoverFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) setCropSrc(URL.createObjectURL(file));
    e.target.value = '';
  }

  async function handleCropConfirm(blob: Blob) {
    setCropSrc(null);
    setCoverFile(new File([blob], 'cover.jpg', { type: 'image/jpeg' }));
  }

  function addPoint(lat: number, lng: number) {
    const nouveau: PointDraft = {
      lat, lng, titre: `Point ${points.length + 1}`, description: '', rayon_validation_m: 30, type_defi: 'photo',
    };
    setPoints(p => [...p, nouveau]);
    setEditingPoint(points.length);
  }

  function updatePoint(index: number, patch: Partial<PointDraft>) {
    setPoints(p => p.map((pt, i) => i === index ? { ...pt, ...patch } : pt));
  }

  function removePoint(index: number) {
    setPoints(p => p.filter((_, i) => i !== index));
    if (editingPoint === index) setEditingPoint(null);
  }

  function canNext() {
    if (step === 0) return titre.trim().length > 0;
    if (step === 1) return points.length > 0;
    return true;
  }

  async function publier() {
    if (!user || points.length === 0) return;
    setPublishing(true);
    try {
      let finalCoverUrl = coverUrl;
      if (coverFile) {
        finalCoverUrl = await uploadBlob(coverFile, `balades_ludiques/${editId ?? Date.now()}/cover.jpg`);
      }
      const row: Record<string, unknown> = {
        createur_uid: user.uid,
        titre: titre.trim(),
        description: description.trim() || null,
        cover_url: finalCoverUrl,
        statut: 'publie',
        espece_cible: espece,
        famille, sportif, accessible_pmr: pmr,
        gratuit, prix: gratuit ? null : Number(prix.replace(',', '.')) || null,
        difficulte,
        duree_min: duree ? Number(duree) : null,
        distance_km: distance ? Number(distance.replace(',', '.')) : null,
        lat_depart: points[0].lat,
        lng_depart: points[0].lng,
        type_evenement: isAdmin ? typeEvenement : 'communautaire',
        partenaire_nom: isAdmin && typeEvenement === 'officiel_partenaire' ? partenaireNom.trim() || null : null,
        event_debut: isAdmin && eventDebut ? new Date(eventDebut).toISOString() : null,
        event_fin: isAdmin && eventFin ? new Date(eventFin).toISOString() : null,
        updated_at: new Date().toISOString(),
      };

      let id = editId;
      if (editId) {
        const { error } = await supabase.from('balades_ludiques').update(row).eq('id', editId);
        if (error) throw error;
        await supabase.from('balades_ludiques_points').delete().eq('balade_id', editId);
      } else {
        row.published_at = new Date().toISOString();
        const { data: inserted, error } = await supabase.from('balades_ludiques').insert(row).select().single();
        if (error) throw error;
        id = inserted?.id;
      }

      let ordre = 1;
      for (const p of points) {
        await supabase.from('balades_ludiques_points').insert({
          balade_id: id, ordre: ordre++, titre: p.titre, description: p.description,
          lat: p.lat, lng: p.lng, rayon_validation_m: p.rayon_validation_m, type_defi: p.type_defi,
          question_texte: p.question_texte, question_reponse: p.question_reponse,
          consigne_texte: p.consigne_texte, qr_code_value: p.qr_code_value, indice: p.indice,
        });
      }

      if (!editId) {
        const { data: existing } = await supabase.from('joueurs_xp').select('*').eq('user_uid', user.uid).maybeSingle();
        const nouveauNbCrees = (existing?.nb_parcours_crees ?? 0) + 1;
        await supabase.from('joueurs_xp').upsert({
          user_uid: user.uid,
          xp_total: existing?.xp_total ?? 0,
          nb_parcours_completes: existing?.nb_parcours_completes ?? 0,
          nb_parcours_crees: nouveauNbCrees,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_uid' });

        if (nouveauNbCrees === 1) {
          const { data: badge } = await supabase.from('badges').select('*').eq('code', 'createur_premier').maybeSingle();
          if (badge) await supabase.from('badges_obtenus').insert({ user_uid: user.uid, badge_id: badge.id, balade_id: id });
        }
      }

      router.push(`/balades-ludiques/${id}`);
    } catch (err) {
      alert(`Erreur lors de la publication : ${err instanceof Error ? err.message : err}`);
      setPublishing(false);
    }
  }

  if (loadingEdit) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" /></div>;

  const pointEnCours = editingPoint != null ? points[editingPoint] : null;

  return (
    <div className="min-h-screen bg-[#F8F8F6]">
      <div className="bg-teal-700 text-white px-4 py-4">
        <div className="max-w-2xl mx-auto flex items-center gap-3">
          <button onClick={() => router.back()} className="text-xl">←</button>
          <h1 className="font-galey font-bold">{editId ? 'Modifier le parcours' : 'Nouveau parcours'}</h1>
        </div>
        <div className="max-w-2xl mx-auto flex gap-1 mt-3">
          {[0, 1, 2].map(i => <div key={i} className={`h-1.5 flex-1 rounded-full ${step >= i ? 'bg-white' : 'bg-white/30'}`} />)}
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6">
        {step === 0 && (
          <div className="space-y-4">
            <h2 className="font-galey font-bold text-lg">Infos générales</h2>
            <label className="block h-36 rounded-2xl bg-[#EEF5EA] border-2 border-dashed border-teal-300 flex items-center justify-center cursor-pointer overflow-hidden">
              {(coverFile || coverUrl) ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={coverFile ? URL.createObjectURL(coverFile) : coverUrl!} alt="" className="w-full h-full object-cover" />
              ) : <span className="font-galey text-teal-700 text-sm">📷 Photo de couverture</span>}
              <input type="file" accept="image/*" className="hidden" onChange={handleCoverFile} />
            </label>

            <div>
              <label className="text-xs font-galey font-semibold text-gray-500 mb-1 block">Titre *</label>
              <input value={titre} onChange={e => setTitre(e.target.value)} placeholder="Ex : La chasse aux écureuils du parc"
                className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400" />
            </div>
            <div>
              <label className="text-xs font-galey font-semibold text-gray-500 mb-1 block">Description</label>
              <textarea value={description} onChange={e => setDescription(e.target.value)} rows={3} placeholder="Présentez votre parcours..."
                className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey focus:outline-none focus:border-teal-400" />
            </div>
            <div>
              <label className="text-xs font-galey font-semibold text-gray-500 mb-2 block">Espèce ciblée</label>
              <div className="flex flex-wrap gap-2">
                {ESPECES.map(e => (
                  <button key={e.value} onClick={() => setEspece(e.value)}
                    className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border ${espece === e.value ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'}`}>
                    {e.emoji} {e.label}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="text-xs font-galey font-semibold text-gray-500 mb-2 block">Difficulté</label>
              <div className="flex flex-wrap gap-2">
                {DIFFICULTES.map(d => (
                  <button key={d.value} onClick={() => setDifficulte(d.value)}
                    style={difficulte === d.value ? { background: d.color, borderColor: d.color } : {}}
                    className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border ${difficulte === d.value ? 'text-white' : 'bg-white text-gray-600 border-gray-200'}`}>
                    {d.label}
                  </button>
                ))}
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-galey font-semibold text-gray-500 mb-1 block">Durée estimée (min)</label>
                <input value={duree} onChange={e => setDuree(e.target.value)} placeholder="45" type="number"
                  className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
              </div>
              <div>
                <label className="text-xs font-galey font-semibold text-gray-500 mb-1 block">Distance (km)</label>
                <input value={distance} onChange={e => setDistance(e.target.value)} placeholder="3.5"
                  className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
              </div>
            </div>
            <div className="flex flex-wrap gap-2">
              {([
                ['Famille', famille, setFamille], ['Sportif', sportif, setSportif], ['Accessible PMR', pmr, setPmr],
              ] as [string, boolean, (v: boolean) => void][]).map(([label, value, setter]) => (
                <button key={label} onClick={() => setter(!value)}
                  className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border ${value ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'}`}>
                  {label}
                </button>
              ))}
            </div>
            <label className="flex items-center gap-2">
              <input type="checkbox" checked={gratuit} onChange={e => setGratuit(e.target.checked)} />
              <span className="text-sm font-galey">Gratuit</span>
            </label>
            {!gratuit && (
              <input value={prix} onChange={e => setPrix(e.target.value)} placeholder="Prix en €"
                className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
            )}

            {isAdmin && (
              <div className="border-t border-gray-200 pt-4 mt-2 space-y-3">
                <p className="font-galey font-bold text-sm">🏆 Événement officiel (admin)</p>
                <div className="flex flex-wrap gap-2">
                  {[
                    ['communautaire', 'Communautaire'], ['officiel_petsmatch', 'Officiel PetsMatch'], ['officiel_partenaire', 'Officiel partenaire'],
                  ].map(([v, l]) => (
                    <button key={v} onClick={() => setTypeEvenement(v)}
                      className={`px-3 py-1.5 rounded-full text-xs font-galey border ${typeEvenement === v ? 'bg-orange-600 text-white border-orange-600' : 'bg-white text-gray-600 border-gray-200'}`}>
                      {l}
                    </button>
                  ))}
                </div>
                {typeEvenement === 'officiel_partenaire' && (
                  <input value={partenaireNom} onChange={e => setPartenaireNom(e.target.value)} placeholder="Nom du partenaire"
                    className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
                )}
                {typeEvenement !== 'communautaire' && (
                  <div className="grid grid-cols-2 gap-3">
                    <input type="date" value={eventDebut} onChange={e => setEventDebut(e.target.value)}
                      className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
                    <input type="date" value={eventFin} onChange={e => setEventFin(e.target.value)}
                      className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {step === 1 && (
          <div>
            <h2 className="font-galey font-bold text-lg mb-1">Placez vos points sur la carte</h2>
            <p className="text-xs font-galey text-gray-400 mb-3">Cliquez sur la carte pour ajouter une étape, puis configurez son défi.</p>
            <div className="h-72 rounded-2xl overflow-hidden border border-gray-100 mb-4">
              <PointsEditor points={points} onAddPoint={addPoint} onSelectPoint={setEditingPoint} />
            </div>
            {points.length === 0 ? (
              <p className="text-center text-gray-400 font-galey text-sm py-6">Aucun point pour l&apos;instant.</p>
            ) : (
              <div className="space-y-2">
                {points.map((p, i) => (
                  <div key={i} className="flex items-center gap-2 bg-white rounded-xl p-3 border border-gray-100">
                    <span className="w-7 h-7 rounded-full bg-teal-700 text-white text-xs flex items-center justify-center font-galey">{i + 1}</span>
                    <button onClick={() => setEditingPoint(i)} className="flex-1 text-left">
                      <p className="font-galey font-semibold text-sm">{p.titre}</p>
                      <p className="text-xs font-galey text-gray-400">{typeDefiIcon(p.type_defi)} {TYPES_DEFI.find(t => t.value === p.type_defi)?.label}</p>
                    </button>
                    <button onClick={() => removePoint(i)} className="text-red-500 text-xs font-galey">Supprimer</button>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {step === 2 && (
          <div>
            <h2 className="font-galey font-bold text-lg mb-3">Récapitulatif</h2>
            <div className="bg-white rounded-2xl p-5 border border-gray-100 space-y-1">
              <p className="font-galey font-bold text-base">{titre}</p>
              <p className="text-xs font-galey text-gray-500">Espèce : {especeLabel(espece)}</p>
              <p className="text-xs font-galey text-gray-500">Difficulté : {difficulteLabel(difficulte)}</p>
              <p className="text-xs font-galey text-gray-500">Durée : {duree ? dureeLabel(Number(duree)) : '—'}</p>
              <p className="text-xs font-galey text-gray-500">Tarif : {gratuit ? 'Gratuit' : `${prix} €`}</p>
              <p className="text-xs font-galey text-gray-500">Étapes : {points.length}</p>
            </div>
            <div className="mt-4 space-y-2">
              {points.map((p, i) => (
                <div key={i} className="flex items-center gap-2">
                  <span className="w-6 h-6 rounded-full bg-teal-50 text-teal-700 text-xs flex items-center justify-center font-galey">{i + 1}</span>
                  <span>{typeDefiIcon(p.type_defi)}</span>
                  <span className="text-sm font-galey">{p.titre}</span>
                </div>
              ))}
            </div>
            <div className="mt-4 bg-[#EEF5EA] rounded-xl p-3 text-xs font-galey text-gray-600">
              ℹ️ Votre parcours sera visible par tous les utilisateurs dès la publication.
            </div>
          </div>
        )}

        <div className="flex gap-3 mt-6">
          {step > 0 && <button onClick={() => setStep(s => s - 1)} className="flex-1 border border-gray-200 rounded-xl py-3 font-galey font-semibold text-gray-600">Précédent</button>}
          <button
            onClick={() => { if (!canNext()) return; if (step < 2) setStep(s => s + 1); else publier(); }}
            disabled={!canNext() || publishing}
            className="flex-[2] bg-orange-600 hover:bg-orange-700 text-white rounded-xl py-3 font-galey font-bold disabled:opacity-50">
            {publishing ? '...' : step < 2 ? 'Suivant' : (editId ? 'Enregistrer' : 'Publier')}
          </button>
        </div>
      </div>

      {pointEnCours && editingPoint != null && (
        <PointDefiModal
          point={pointEnCours}
          onSave={(patch) => { updatePoint(editingPoint, patch); setEditingPoint(null); }}
          onClose={() => setEditingPoint(null)}
        />
      )}
      {cropSrc && <ImageCropModal src={cropSrc} aspect={16 / 9} maxDim={1200} onConfirm={handleCropConfirm} onCancel={() => setCropSrc(null)} />}
    </div>
  );
}

function PointDefiModal({ point, onSave, onClose }: { point: PointDraft; onSave: (patch: Partial<PointDraft>) => void; onClose: () => void }) {
  const [titre, setTitre] = useState(point.titre);
  const [description, setDescription] = useState(point.description ?? '');
  const [rayon, setRayon] = useState(point.rayon_validation_m.toString());
  const [typeDefi, setTypeDefi] = useState(point.type_defi);
  const [question, setQuestion] = useState(point.question_texte ?? '');
  const [reponse, setReponse] = useState(point.question_reponse ?? '');
  const [consigne, setConsigne] = useState(point.consigne_texte ?? '');
  const [qrCode, setQrCode] = useState(point.qr_code_value ?? genQrCode());
  const [indice, setIndice] = useState(point.indice ?? '');

  function save() {
    if (!titre.trim()) return;
    onSave({
      titre: titre.trim(), description: description.trim(), rayon_validation_m: Number(rayon) || 30, type_defi: typeDefi,
      question_texte: typeDefi === 'question' ? question.trim() : undefined,
      question_reponse: typeDefi === 'question' ? reponse.trim() : undefined,
      consigne_texte: (typeDefi === 'objet_nature' || typeDefi === 'action_animal') ? consigne.trim() : undefined,
      qr_code_value: typeDefi === 'qr_code' ? qrCode.trim() : undefined,
      indice: indice.trim() || undefined,
    });
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-3xl w-full sm:max-w-md max-h-[85vh] overflow-y-auto p-6" onClick={e => e.stopPropagation()}>
        <div className="flex justify-between items-center mb-4">
          <h3 className="font-galey font-bold text-lg">Point d&apos;intérêt</h3>
          <button onClick={onClose} className="text-gray-400 text-xl">✕</button>
        </div>
        <div className="space-y-3">
          <input value={titre} onChange={e => setTitre(e.target.value)} placeholder="Titre de l'étape"
            className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
          <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2} placeholder="Description"
            className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
          <input value={rayon} onChange={e => setRayon(e.target.value)} type="number" placeholder="Rayon de validation GPS (m)"
            className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />

          <p className="text-xs font-galey font-semibold text-gray-500">Type de défi</p>
          <div className="flex flex-wrap gap-2">
            {TYPES_DEFI.map(t => (
              <button key={t.value} onClick={() => setTypeDefi(t.value)}
                className={`px-3 py-1.5 rounded-full text-xs font-galey border ${typeDefi === t.value ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'}`}>
                {t.icon} {t.label}
              </button>
            ))}
          </div>

          {typeDefi === 'question' && (
            <>
              <input value={question} onChange={e => setQuestion(e.target.value)} placeholder="Question posée"
                className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
              <input value={reponse} onChange={e => setReponse(e.target.value)} placeholder="Réponse attendue"
                className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
            </>
          )}
          {(typeDefi === 'objet_nature' || typeDefi === 'action_animal') && (
            <textarea value={consigne} onChange={e => setConsigne(e.target.value)} rows={2}
              placeholder={typeDefi === 'objet_nature' ? 'Objet / élément à trouver' : 'Action à réaliser avec son animal'}
              className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
          )}
          {typeDefi === 'qr_code' && (
            <>
              <input value={qrCode} onChange={e => setQrCode(e.target.value)} placeholder="Code du QR (à imprimer sur le terrain)"
                className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />
              <div className="flex justify-center py-2">
                <QRCodeSVG value={qrCode || 'BL'} size={140} />
              </div>
            </>
          )}
          {typeDefi === 'photo' && <p className="text-xs font-galey text-gray-400">Le joueur devra prendre une photo pour valider l&apos;étape.</p>}
          {typeDefi === 'gps_seul' && <p className="text-xs font-galey text-gray-400">Validation automatique par proximité GPS uniquement.</p>}

          <input value={indice} onChange={e => setIndice(e.target.value)} placeholder="Indice (optionnel)"
            className="w-full px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-galey" />

          <button onClick={save} className="w-full bg-teal-700 text-white font-galey font-bold py-3 rounded-xl mt-2">
            Enregistrer le point
          </button>
        </div>
      </div>
    </div>
  );
}

export default function CreerBaladePage() {
  return (
    <Suspense fallback={<div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" /></div>}>
      <CreerBaladeContent />
    </Suspense>
  );
}
