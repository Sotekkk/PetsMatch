'use client';

import { Suspense, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useSanteAccess } from '@/hooks/useSanteAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { uploadPhoto, uploadRawFile } from '@/lib/upload-media';
import MorphoSilhouette, { MorphoLegende } from '@/components/morpho/MorphoSilhouette';
import {
  TEAL, TYPES_SUIVI, NIVEAUX_ACTIVITE, VUES_PHOTOS, ACTIVITES_MOUVEMENT,
  CATEGORIES_OBSERVATION_STATIQUE, labelsValeurObservation, colorValeurObservation,
  CATEGORIES_OSTEO, morphoSpeciesKey, vuesDisponibles, labelActivite,
  type MorphoPoint,
} from '@/lib/morpho';

const MAX_VIDEO_BYTES = 50 * 1024 * 1024;

interface VideoEntree { file: File; activite: string; commentaire: string }
interface Mouvement { activite: string; observation: string; geneObservee: boolean | null; commentaire: string }
interface ObsStatique { valeur: string; commentaire: string }

function NouveauSuiviContent() {
  const { user, userData, isSante, loading: authLoading } = useSanteAccess();
  const router = useRouter();
  const params = useSearchParams();
  const activeProfileId = useActiveProfile();
  const animalId = params.get('animalId');
  const especeParam = params.get('espece') ?? 'chien';
  const espece = morphoSpeciesKey(especeParam) ?? 'chien';
  const saisieLibre = !animalId;

  const [saving, setSaving] = useState(false);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [typeSuivi, setTypeSuivi] = useState('bilan_morphologique');
  const [professionnel, setProfessionnel] = useState('');
  const [motif, setMotif] = useState('');
  const [commentaires, setCommentaires] = useState('');
  const [poids, setPoids] = useState('');
  const [taille, setTaille] = useState('');
  const [niveauActivite, setNiveauActivite] = useState('non_evalue');
  const [activiteSportive, setActiviteSportive] = useState('');
  const [checkpoint, setCheckpoint] = useState('');
  const [animalNom, setAnimalNom] = useState('');
  const [clientNom, setClientNom] = useState('');
  const [clientContact, setClientContact] = useState('');

  const [photosVues, setPhotosVues] = useState<Record<string, File>>({});
  const [photosExtra, setPhotosExtra] = useState<File[]>([]);
  const [videos, setVideos] = useState<VideoEntree[]>([]);
  const [points, setPoints] = useState<MorphoPoint[]>([]);
  const [vueSilhouette, setVueSilhouette] = useState(() => vuesDisponibles(espece)[0]?.key ?? 'profil_d');
  const [observations, setObservations] = useState<Record<string, ObsStatique>>(
    Object.fromEntries(CATEGORIES_OBSERVATION_STATIQUE.map(c => [c.key, { valeur: 'non_evalue', commentaire: '' }])),
  );
  const [mouvements, setMouvements] = useState<Mouvement[]>([]);
  const [pointSheet, setPointSheet] = useState<{ point: MorphoPoint; isNew: boolean } | null>(null);
  const [videoSheetOpen, setVideoSheetOpen] = useState(false);
  const [mouvementSheetOpen, setMouvementSheetOpen] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isSante) { router.push('/'); return; }
  }, [user, userData, isSante, authLoading, router]);

  useEffect(() => {
    if (!animalId) return;
    supabase.from('animaux').select('poids, taille').eq('id', animalId).maybeSingle().then(({ data }) => {
      if (data?.poids) setPoids(String(data.poids));
      if (data?.taille) setTaille(String(data.taille));
    });
  }, [animalId]);

  function addPointAt(xPct: number, yPct: number) {
    setPointSheet({ point: { id: `new-${Date.now()}`, x_pct: xPct, y_pct: yPct, categorie: 'autre', note: '', vue: vueSilhouette }, isNew: true });
  }
  function editPoint(p: MorphoPoint) { setPointSheet({ point: p, isNew: false }); }
  function savePoint(p: MorphoPoint, deleted: boolean) {
    setPoints(prev => {
      if (deleted) return prev.filter(x => x.id !== p.id);
      const exists = prev.some(x => x.id === p.id);
      return exists ? prev.map(x => (x.id === p.id ? p : x)) : [...prev, p];
    });
    setPointSheet(null);
  }

  async function handleSave() {
    if (!user) return;
    setSaving(true);
    try {
      const source = activeProfileId ? 'professionnel' : 'proprietaire';
      const insertRow: Record<string, unknown> = {
        uid_auteur: user.uid,
        type_suivi: typeSuivi,
        date,
        niveau_activite: niveauActivite,
        source,
      };
      if (animalId) insertRow.animal_id = animalId;
      if (activeProfileId) insertRow.pro_profile_id = activeProfileId;
      if (professionnel.trim()) insertRow.professionnel_nom = professionnel.trim();
      if (motif.trim()) insertRow.motif = motif.trim();
      if (commentaires.trim()) insertRow.commentaires = commentaires.trim();
      const poidsN = parseFloat(poids.replace(',', '.'));
      if (!isNaN(poidsN)) insertRow.poids = poidsN;
      const tailleN = parseFloat(taille.replace(',', '.'));
      if (!isNaN(tailleN)) insertRow.taille = tailleN;
      if (activiteSportive.trim()) insertRow.activite_sportive = activiteSportive.trim();
      if (checkpoint.trim()) insertRow.checkpoint_age = checkpoint.trim();
      if (saisieLibre) {
        if (animalNom.trim()) insertRow.animal_nom_libre = animalNom.trim();
        insertRow.espece_libre = espece;
        if (clientNom.trim()) insertRow.client_nom_libre = clientNom.trim();
        if (clientContact.trim()) insertRow.client_contact_libre = clientContact.trim();
      }

      const { data: inserted, error } = await supabase.from('suivis_morpho').insert(insertRow).select('id').single();
      if (error || !inserted) throw error ?? new Error('Échec de la création');
      const suiviId = inserted.id as string;
      const base = `animaux/${animalId ?? 'libre'}/morpho/${suiviId}`;

      for (const [vue, file] of Object.entries(photosVues)) {
        const url = await uploadPhoto(file, `${base}/${vue}.jpg`);
        await supabase.from('suivis_morpho_photos').insert({ suivi_id: suiviId, vue, url });
      }
      for (let i = 0; i < photosExtra.length; i++) {
        const url = await uploadPhoto(photosExtra[i], `${base}/extra_${i}.jpg`);
        await supabase.from('suivis_morpho_photos').insert({ suivi_id: suiviId, vue: 'autre', url });
      }
      for (let i = 0; i < videos.length; i++) {
        const v = videos[i];
        const ext = v.file.name.split('.').pop() || 'mp4';
        const url = await uploadRawFile(v.file, `${base}/video_${i}.${ext}`);
        await supabase.from('suivis_morpho_videos').insert({
          suivi_id: suiviId, activite: v.activite,
          ...(v.commentaire.trim() ? { commentaire: v.commentaire.trim() } : {}),
          url,
        });
      }
      for (let i = 0; i < points.length; i++) {
        const p = points[i];
        const { data: row } = await supabase.from('suivis_morpho_points').insert({
          suivi_id: suiviId, vue: p.vue, x_pct: p.x_pct, y_pct: p.y_pct, categorie: p.categorie,
          ...(p.note?.trim() ? { note: p.note.trim() } : {}),
        }).select('id').single();
        void row;
      }
      for (const [categorie, o] of Object.entries(observations)) {
        if (o.valeur === 'non_evalue' && !o.commentaire.trim()) continue;
        await supabase.from('suivis_morpho_observations').insert({
          suivi_id: suiviId, categorie, valeur: o.valeur,
          ...(o.commentaire.trim() ? { commentaire: o.commentaire.trim() } : {}),
        });
      }
      for (const m of mouvements) {
        await supabase.from('suivis_morpho_mouvements').insert({
          suivi_id: suiviId, activite: m.activite,
          ...(m.observation.trim() ? { observation: m.observation.trim() } : {}),
          gene_observee: m.geneObservee,
          ...(m.commentaire.trim() ? { commentaire: m.commentaire.trim() } : {}),
        });
      }

      router.push(`/sante/suivis/${suiviId}`);
    } catch (e) {
      alert(`Erreur : ${e instanceof Error ? e.message : e}`);
    } finally {
      setSaving(false);
    }
  }

  if (!user || !userData) return null;

  const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-500/30';

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6 pb-24">
      <h1 className="text-2xl font-bold font-galey" style={{ color: TEAL }}>Nouveau suivi</h1>

      {saisieLibre && (
        <Card title="Client">
          <p className="text-xs text-gray-400 mb-3">Client occasionnel, sans fiche existante dans l&apos;application.</p>
          <Field label="Nom de l'animal"><input className={inputCls} value={animalNom} onChange={e => setAnimalNom(e.target.value)} /></Field>
          <Field label="Nom du client (facultatif)"><input className={inputCls} value={clientNom} onChange={e => setClientNom(e.target.value)} /></Field>
          <Field label="Contact — téléphone ou email (facultatif)"><input className={inputCls} value={clientContact} onChange={e => setClientContact(e.target.value)} /></Field>
        </Card>
      )}

      <Card title="Informations générales">
        <Field label="Date"><input type="date" className={inputCls} value={date} onChange={e => setDate(e.target.value)} /></Field>
        <Field label="Type de suivi">
          <select className={inputCls} value={typeSuivi} onChange={e => setTypeSuivi(e.target.value)}>
            {TYPES_SUIVI.map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
          </select>
        </Field>
        <Field label="Professionnel (si applicable)"><input className={inputCls} value={professionnel} onChange={e => setProfessionnel(e.target.value)} /></Field>
        <Field label="Motif / raison du suivi"><textarea rows={2} className={inputCls} value={motif} onChange={e => setMotif(e.target.value)} /></Field>
        <Field label="Commentaires généraux"><textarea rows={3} className={inputCls} value={commentaires} onChange={e => setCommentaires(e.target.value)} /></Field>
      </Card>

      <Card title="Données de l'animal">
        <div className="grid grid-cols-2 gap-3 mb-3">
          <Field label="Poids (kg)"><input className={inputCls} value={poids} onChange={e => setPoids(e.target.value)} /></Field>
          <Field label="Taille (cm)"><input className={inputCls} value={taille} onChange={e => setTaille(e.target.value)} /></Field>
        </div>
        <Field label="Niveau d'activité">
          <select className={inputCls} value={niveauActivite} onChange={e => setNiveauActivite(e.target.value)}>
            {NIVEAUX_ACTIVITE.map(n => <option key={n.key} value={n.key}>{n.label}</option>)}
          </select>
        </Field>
        <Field label="Activité sportive éventuelle"><input className={inputCls} value={activiteSportive} onChange={e => setActiviteSportive(e.target.value)} /></Field>
        <Field label='Étape (éleveur, optionnel — ex. "8 semaines")'><input className={inputCls} value={checkpoint} onChange={e => setCheckpoint(e.target.value)} /></Field>
      </Card>

      <Card title="Photos de référence">
        <PhotoGrid photos={photosVues} onChange={setPhotosVues} />
        <p className="text-xs font-semibold text-gray-600 mt-4 mb-2">Photos supplémentaires</p>
        <div className="flex flex-wrap gap-2">
          {photosExtra.map((f, i) => (
            // eslint-disable-next-line @next/next/no-img-element
            <img key={i} src={URL.createObjectURL(f)} alt="" className="w-16 h-16 rounded-lg object-cover" />
          ))}
          <label className="w-16 h-16 rounded-lg bg-gray-100 flex items-center justify-center cursor-pointer text-2xl text-gray-400" style={{ color: TEAL }}>
            +
            <input type="file" accept="image/*" className="hidden" onChange={e => { const f = e.target.files?.[0]; if (f) setPhotosExtra(p => [...p, f]); }} />
          </label>
        </div>
      </Card>

      <Card title="Vidéos">
        {videos.map((v, i) => (
          <div key={i} className="flex items-center gap-2 mb-2 text-sm font-galey">
            <span>🎥</span>
            <span className="flex-1">{labelActivite(v.activite)}</span>
            <button onClick={() => setVideos(vs => vs.filter((_, j) => j !== i))} className="text-gray-400 hover:text-red-500">✕</button>
          </div>
        ))}
        <button onClick={() => setVideoSheetOpen(true)} className="text-sm font-galey font-semibold" style={{ color: TEAL }}>+ Ajouter une vidéo</button>
      </Card>

      <Card title="Silhouette anatomique">
        <div className="flex flex-wrap gap-2 justify-center mb-3">
          {vuesDisponibles(espece).map(v => (
            <button key={v.key} onClick={() => setVueSilhouette(v.key)}
              className="px-3 py-1.5 rounded-full text-xs font-galey font-semibold"
              style={vueSilhouette === v.key ? { background: TEAL, color: 'white' } : { background: '#F1F5F4', color: '#374151' }}>
              {v.label}
            </button>
          ))}
        </div>
        <MorphoSilhouette espece={espece} vue={vueSilhouette} points={points} onTapEmpty={addPointAt} onTapPoint={editPoint} onVueChange={setVueSilhouette} />
        <div className="mt-3"><MorphoLegende /></div>
        <p className="text-xs text-gray-400 mt-2 text-center">Cliquez sur la silhouette pour poser un point</p>
      </Card>

      <Card title="Observation statique (posture)">
        {CATEGORIES_OBSERVATION_STATIQUE.map(c => (
          <ObservationRow key={c.key} categorie={c.key} label={c.label} state={observations[c.key]}
            onChange={(o) => setObservations(prev => ({ ...prev, [c.key]: o }))} inputCls={inputCls} />
        ))}
      </Card>

      <Card title="Observation en mouvement">
        {mouvements.map((m, i) => (
          <div key={i} className="flex items-center gap-2 mb-2 text-sm font-galey">
            <span className="flex-1">{labelActivite(m.activite)}{m.geneObservee ? ' ⚠️' : ''}</span>
            <button onClick={() => setMouvements(ms => ms.filter((_, j) => j !== i))} className="text-gray-400 hover:text-red-500">✕</button>
          </div>
        ))}
        <button onClick={() => setMouvementSheetOpen(true)} className="text-sm font-galey font-semibold" style={{ color: TEAL }}>+ Ajouter une observation</button>
      </Card>

      <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-100 p-4">
        <div className="max-w-2xl mx-auto">
          <button disabled={saving} onClick={handleSave}
            className="w-full py-3 rounded-xl text-sm font-galey font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>
            {saving ? 'Enregistrement…' : 'Enregistrer le suivi'}
          </button>
        </div>
      </div>

      {pointSheet && (
        <PointSheet point={pointSheet.point} allowDelete={!pointSheet.isNew}
          onSave={(p) => savePoint(p, false)} onDelete={() => savePoint(pointSheet.point, true)} onClose={() => setPointSheet(null)} />
      )}
      {videoSheetOpen && (
        <VideoSheet onClose={() => setVideoSheetOpen(false)} onSave={(v) => { setVideos(vs => [...vs, v]); setVideoSheetOpen(false); }} />
      )}
      {mouvementSheetOpen && (
        <MouvementSheet onClose={() => setMouvementSheetOpen(false)} onSave={(m) => { setMouvements(ms => [...ms, m]); setMouvementSheetOpen(false); }} />
      )}
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">{title}</h2>
      <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3">{children}</div>
    </div>
  );
}
function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><label className="block text-xs font-galey text-gray-500 mb-1">{label}</label>{children}</div>;
}

function PhotoGrid({ photos, onChange }: { photos: Record<string, File>; onChange: (p: Record<string, File>) => void }) {
  function Slot({ vueKey, label }: { vueKey: string; label: string }) {
    const file = photos[vueKey];
    return (
      <div className="flex flex-col items-center gap-1.5">
        <span className="text-[11px] font-bold font-galey text-gray-500">{label}</span>
        <label className="w-20 h-20 rounded-xl bg-gray-100 flex items-center justify-center cursor-pointer overflow-hidden border border-gray-200">
          {file ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={URL.createObjectURL(file)} alt={label} className="w-full h-full object-cover" />
          ) : (
            <span style={{ color: TEAL }}>📷</span>
          )}
          <input type="file" accept="image/*" className="hidden"
            onChange={e => { const f = e.target.files?.[0]; if (f) onChange({ ...photos, [vueKey]: f }); }} />
        </label>
      </div>
    );
  }
  return (
    <div className="flex flex-col items-center gap-4">
      <Slot vueKey="face" label="FACE" />
      <div className="flex gap-8"><Slot vueKey="profil_g" label="PROFIL G" /><Slot vueKey="profil_d" label="PROFIL D" /></div>
      <Slot vueKey="dos" label="ARRIÈRE / DOS" />
    </div>
  );
}

function ObservationRow({ categorie, label, state, onChange, inputCls }: {
  categorie: string; label: string; state: ObsStatique; onChange: (o: ObsStatique) => void; inputCls: string;
}) {
  const labels = labelsValeurObservation(categorie);
  return (
    <div>
      <p className="text-sm font-semibold font-galey text-gray-800 mb-1.5">{label}</p>
      <div className="flex flex-wrap gap-1.5 mb-2">
        {Object.entries(labels).map(([k, l]) => (
          <button key={k} onClick={() => onChange({ ...state, valeur: k })}
            className="px-2.5 py-1 rounded-full text-xs font-galey"
            style={state.valeur === k ? { background: `${colorValeurObservation(k)}30`, color: colorValeurObservation(k), fontWeight: 700 } : { background: '#F3F4F6', color: '#6B7280' }}>
            {l}
          </button>
        ))}
      </div>
      <input className={inputCls} placeholder="Commentaire (facultatif)" value={state.commentaire} onChange={e => onChange({ ...state, commentaire: e.target.value })} />
    </div>
  );
}

function SheetShell({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-bold font-galey text-gray-900">{title}</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}

function PointSheet({ point, allowDelete, onSave, onDelete, onClose }: {
  point: MorphoPoint; allowDelete: boolean; onSave: (p: MorphoPoint) => void; onDelete: () => void; onClose: () => void;
}) {
  const [categorie, setCategorie] = useState(point.categorie);
  const [note, setNote] = useState(point.note ?? '');
  const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey';
  return (
    <SheetShell title="Point" onClose={onClose}>
      <p className="text-xs font-galey font-semibold text-gray-600 mb-1.5">Catégorie</p>
      <div className="flex flex-wrap gap-1.5 mb-3">
        {CATEGORIES_OSTEO.map(c => (
          <button key={c.key} onClick={() => setCategorie(c.key)}
            className="px-2.5 py-1 rounded-full text-xs font-galey"
            style={categorie === c.key ? { background: `${c.color}40`, fontWeight: 700 } : { background: '#F3F4F6', color: '#6B7280' }}>
            {c.label}
          </button>
        ))}
      </div>
      <textarea className={inputCls} rows={2} placeholder="Note (facultatif)" value={note} onChange={e => setNote(e.target.value)} />
      <div className="flex gap-2 mt-4">
        {allowDelete && (
          <button onClick={onDelete} className="text-red-500 text-sm font-galey font-semibold px-3">Supprimer</button>
        )}
        <button onClick={() => onSave({ ...point, categorie, note })}
          className="flex-1 py-2.5 rounded-xl text-sm font-galey font-bold text-white" style={{ background: TEAL }}>
          Valider
        </button>
      </div>
    </SheetShell>
  );
}

function VideoSheet({ onClose, onSave }: { onClose: () => void; onSave: (v: VideoEntree) => void }) {
  const [file, setFile] = useState<File | null>(null);
  const [activite, setActivite] = useState(ACTIVITES_MOUVEMENT[0].key);
  const [commentaire, setCommentaire] = useState('');
  const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey';
  return (
    <SheetShell title="Ajouter une vidéo" onClose={onClose}>
      <input type="file" accept="video/*" className="mb-3 text-sm font-galey"
        onChange={e => {
          const f = e.target.files?.[0];
          if (f && f.size > MAX_VIDEO_BYTES) { alert('Vidéo trop lourde (max 50 Mo).'); return; }
          setFile(f ?? null);
        }} />
      <p className="text-xs font-galey font-semibold text-gray-600 mb-1.5">Activité filmée</p>
      <select className={inputCls} value={activite} onChange={e => setActivite(e.target.value)}>
        {ACTIVITES_MOUVEMENT.map(a => <option key={a.key} value={a.key}>{a.label}</option>)}
      </select>
      <textarea className={`${inputCls} mt-3`} rows={2} placeholder="Commentaire (facultatif)" value={commentaire} onChange={e => setCommentaire(e.target.value)} />
      <button disabled={!file} onClick={() => file && onSave({ file, activite, commentaire })}
        className="w-full mt-4 py-2.5 rounded-xl text-sm font-galey font-bold text-white disabled:opacity-40" style={{ background: TEAL }}>
        Ajouter
      </button>
    </SheetShell>
  );
}

function MouvementSheet({ onClose, onSave }: { onClose: () => void; onSave: (m: Mouvement) => void }) {
  const [activite, setActivite] = useState(ACTIVITES_MOUVEMENT[0].key);
  const [observation, setObservation] = useState('');
  const [gene, setGene] = useState<boolean | null>(null);
  const [commentaire, setCommentaire] = useState('');
  const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey';
  return (
    <SheetShell title="Observation en mouvement" onClose={onClose}>
      <p className="text-xs font-galey font-semibold text-gray-600 mb-1.5">Activité</p>
      <select className={inputCls} value={activite} onChange={e => setActivite(e.target.value)}>
        {ACTIVITES_MOUVEMENT.map(a => <option key={a.key} value={a.key}>{a.label}</option>)}
      </select>
      <textarea className={`${inputCls} mt-3`} rows={2} placeholder="Observation" value={observation} onChange={e => setObservation(e.target.value)} />
      <p className="text-xs font-galey font-semibold text-gray-600 mt-3 mb-1.5">Gêne observée ?</p>
      <div className="flex gap-2 mb-3">
        <button onClick={() => setGene(false)} className="px-3 py-1 rounded-full text-xs font-galey" style={gene === false ? { background: '#F3F4F6', fontWeight: 700 } : { background: '#F3F4F6', color: '#6B7280' }}>Non</button>
        <button onClick={() => setGene(true)} className="px-3 py-1 rounded-full text-xs font-galey" style={gene === true ? { background: '#D9770630', color: '#D97706', fontWeight: 700 } : { background: '#F3F4F6', color: '#6B7280' }}>Oui</button>
      </div>
      <textarea className={inputCls} rows={2} placeholder="Commentaire" value={commentaire} onChange={e => setCommentaire(e.target.value)} />
      <button onClick={() => onSave({ activite, observation, geneObservee: gene, commentaire })}
        className="w-full mt-4 py-2.5 rounded-xl text-sm font-galey font-bold text-white" style={{ background: TEAL }}>
        Ajouter
      </button>
    </SheetShell>
  );
}

export default function NouveauSuiviPage() {
  return (
    <Suspense fallback={null}>
      <NouveauSuiviContent />
    </Suspense>
  );
}
