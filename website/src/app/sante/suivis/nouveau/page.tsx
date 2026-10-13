'use client';

import { Suspense, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useSanteAccess } from '@/hooks/useSanteAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { uploadPhoto, uploadRawFile } from '@/lib/upload-media';
import MorphoSilhouette, { MorphoLegende } from '@/components/morpho/MorphoSilhouette';
import {
  TEAL, TYPES_SEANCE_PRO, typeSeanceParDefaut, type ExerciceSeance, NIVEAUX_ACTIVITE, VUES_PHOTOS, ACTIVITES_MOUVEMENT,
  CATEGORIES_OBSERVATION_STATIQUE, labelsValeurObservation, colorValeurObservation,
  CATEGORIES_OSTEO, colorCategoriePoint, PALETTE_COULEURS_POINTS, morphoSpeciesKey, vuesDisponibles, labelActivite,
  type MorphoPoint,
} from '@/lib/morpho';

const MAX_VIDEO_BYTES = 50 * 1024 * 1024;

interface VideoEntree { file?: File; existingUrl?: string; activite: string; commentaire: string }
interface Mouvement { activite: string; observation: string; geneObservee: boolean | null; commentaire: string }
interface ObsStatique { valeur: string; commentaire: string }
interface ExerciceEntree extends ExerciceSeance { photoFile?: File | null }
const EXERCICE_VIDE: ExerciceEntree = { nom: '', description: '', consignes: '', frequence: '', duree: '', precautions: '', photo_url: null };

function NouveauSuiviContent() {
  const { user, userData, isSante, loading: authLoading } = useSanteAccess();
  const router = useRouter();
  const params = useSearchParams();
  const activeProfileId = useActiveProfile();
  const animalId = params.get('animalId');
  const especeParam = params.get('espece') ?? 'chien';
  const espece = morphoSpeciesKey(especeParam) ?? 'chien';
  const saisieLibre = !animalId;
  const suiviIdParam = params.get('suiviId');
  const isEditing = !!suiviIdParam;
  /** RDV de la séance (agenda → « Rédiger le compte rendu »). */
  const rdvIdParam = params.get('rdvId');

  const [saving, setSaving] = useState(false);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [typeSuivi, setTypeSuivi] = useState('autre');
  const [professionnel, setProfessionnel] = useState('');
  const [motif, setMotif] = useState('');
  const [commentaires, setCommentaires] = useState('');
  const [poids, setPoids] = useState('');
  const [taille, setTaille] = useState('');
  const [niveauActivite, setNiveauActivite] = useState('non_evalue');
  const [activiteSportive, setActiviteSportive] = useState('');
  const [checkpoint, setCheckpoint] = useState('');
  // Contrôle conseillé par le professionnel (alimente « Suivis à prévoir »).
  const [prochainControle, setProchainControle] = useState('');
  const [animalNom, setAnimalNom] = useState('');
  const [clientNom, setClientNom] = useState('');
  const [clientContact, setClientContact] = useState('');
  // ── Compte rendu de séance — Soins & Rééducation (miroir appli) ──────────
  const [intitule, setIntitule] = useState('');
  const [observationsBilan, setObservationsBilan] = useState('');
  const [intervention, setIntervention] = useState('');
  const [suiviRecommande, setSuiviRecommande] = useState('');
  const [orientationVeto, setOrientationVeto] = useState(false);
  const [lieu, setLieu] = useState<'' | 'cabinet' | 'exterieur'>('');
  /** « Ajouter un bilan anatomique » — facultatif ; désactivé, les points
   *  déjà posés sont conservés mais absents du compte rendu. */
  const [avecAnatomie, setAvecAnatomie] = useState(false);
  const [exercices, setExercices] = useState<ExerciceEntree[]>([]);
  const [exerciceEdit, setExerciceEdit] = useState<{ index: number | null; ex: ExerciceEntree } | null>(null);
  /** null = nouveau / ancien suivi ; brouillon | finalise */
  const [statut, setStatut] = useState<string | null>(null);
  const dejaFinalise = statut === 'finalise';

  const [photosVues, setPhotosVues] = useState<Record<string, File>>({});
  const [photosVuesExistantes, setPhotosVuesExistantes] = useState<Record<string, string>>({});
  const [photosExtra, setPhotosExtra] = useState<File[]>([]);
  const [photosExtraExistantes, setPhotosExtraExistantes] = useState<string[]>([]);
  const [videos, setVideos] = useState<VideoEntree[]>([]);
  const [loadingExisting, setLoadingExisting] = useState(false);
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
    if (isEditing || !activeProfileId) return;
    supabase.from('user_profiles_complet').select('nom, firstname, lastname, profession_pro').eq('id', activeProfileId).maybeSingle()
      .then(({ data }) => {
        if (!data) return;
        setTypeSuivi(typeSeanceParDefaut(data.profession_pro as string | null));
        const nom = ((data.nom as string | null) ?? '').trim() || `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim();
        if (nom) setProfessionnel(p => p || nom);
      });
  }, [activeProfileId, isEditing]);

  useEffect(() => {
    if (!animalId || isEditing) return;
    supabase.from('animaux').select('poids, taille').eq('id', animalId).maybeSingle().then(({ data }) => {
      if (data?.poids) setPoids(String(data.poids));
      if (data?.taille) setTaille(String(data.taille));
    });
  }, [animalId, isEditing]);

  // Édition (pro uniquement) : pré-remplit tout le formulaire depuis le
  // suivi existant — l'enregistrement met à jour la même ligne (pas de
  // nouvelle notification au propriétaire), les photos/vidéos non
  // remplacées sont conservées sans nouvel upload.
  useEffect(() => {
    if (!suiviIdParam) return;
    (async () => {
      setLoadingExisting(true);
      const { data: s } = await supabase.from('suivis_morpho').select('*').eq('id', suiviIdParam).maybeSingle();
      if (!s) { setLoadingExisting(false); return; }
      setTypeSuivi(s.type_suivi as string ?? 'bilan_morphologique');
      setDate(String(s.date ?? '').slice(0, 10) || new Date().toISOString().slice(0, 10));
      setProfessionnel((s.professionnel_nom as string) ?? '');
      setMotif((s.motif as string) ?? '');
      setCommentaires((s.commentaires as string) ?? '');
      setPoids(s.poids != null ? String(s.poids) : '');
      setTaille(s.taille != null ? String(s.taille) : '');
      setNiveauActivite((s.niveau_activite as string) ?? 'non_evalue');
      setActiviteSportive((s.activite_sportive as string) ?? '');
      setCheckpoint((s.checkpoint_age as string) ?? '');
      setProchainControle(((s.prochain_controle as string) ?? '').slice(0, 10));
      setAnimalNom((s.animal_nom_libre as string) ?? '');
      setClientNom((s.client_nom_libre as string) ?? '');
      setClientContact((s.client_contact_libre as string) ?? '');
      setIntitule((s.intitule as string) ?? '');
      setObservationsBilan((s.observations_bilan as string) ?? '');
      setIntervention((s.intervention as string) ?? '');
      setSuiviRecommande((s.suivi_recommande as string) ?? '');
      setOrientationVeto(s.orientation_veto === true);
      setLieu(s.lieu === 'cabinet' || s.lieu === 'exterieur' ? s.lieu : '');
      // Ancien suivi déjà envoyé au client : traité comme finalisé (corrections tracées).
      setStatut((s.statut as string | null) ?? (s.notifie_a ? 'finalise' : null));

      const [ph, vi, pt, ob, mv] = await Promise.all([
        supabase.from('suivis_morpho_photos').select('vue, url').eq('suivi_id', suiviIdParam),
        supabase.from('suivis_morpho_videos').select('id, activite, commentaire, url').eq('suivi_id', suiviIdParam),
        supabase.from('suivis_morpho_points').select('id, vue, x_pct, y_pct, categorie, note, couleur').eq('suivi_id', suiviIdParam),
        supabase.from('suivis_morpho_observations').select('categorie, valeur, commentaire').eq('suivi_id', suiviIdParam),
        supabase.from('suivis_morpho_mouvements').select('activite, observation, gene_observee, commentaire').eq('suivi_id', suiviIdParam),
      ]);

      const vuesExistantes: Record<string, string> = {};
      const extraExistantes: string[] = [];
      for (const p of (ph.data ?? []) as { vue: string; url: string }[]) {
        if (VUES_PHOTOS.some(v => v.key === p.vue)) vuesExistantes[p.vue] = p.url;
        else if (p.vue === 'autre') extraExistantes.push(p.url);
      }
      setPhotosVuesExistantes(vuesExistantes);
      setPhotosExtraExistantes(extraExistantes);

      const videoRows = (vi.data ?? []) as { id: string; activite: string; commentaire: string | null; url: string }[];
      setVideos(videoRows.map(v => ({ existingUrl: v.url, activite: v.activite, commentaire: v.commentaire ?? '' })));

      const nbPoints = (pt.data ?? []).length;
      setAvecAnatomie(s.avec_anatomie === true || (s.avec_anatomie == null && nbPoints > 0));
      const { data: ex } = await supabase.from('suivis_morpho_exercices').select('*').eq('suivi_id', suiviIdParam).order('ordre');
      setExercices(((ex ?? []) as ExerciceSeance[]).map(e => ({
        nom: e.nom ?? '', description: e.description ?? '', consignes: e.consignes ?? '', frequence: e.frequence ?? '',
        duree: e.duree ?? '', precautions: e.precautions ?? '', photo_url: e.photo_url ?? null,
      })));
      setPoints(((pt.data ?? []) as { id: string; vue: string; x_pct: number; y_pct: number; categorie: string; note: string | null; couleur: string | null }[])
        .map(p => ({ id: String(p.id), vue: p.vue, x_pct: p.x_pct, y_pct: p.y_pct, categorie: p.categorie, note: p.note ?? '', couleur: p.couleur })));

      const obsData = Object.fromEntries(CATEGORIES_OBSERVATION_STATIQUE.map(c => [c.key, { valeur: 'non_evalue', commentaire: '' }])) as Record<string, ObsStatique>;
      for (const o of (ob.data ?? []) as { categorie: string; valeur: string; commentaire: string | null }[]) {
        if (obsData[o.categorie]) obsData[o.categorie] = { valeur: o.valeur, commentaire: o.commentaire ?? '' };
      }
      setObservations(obsData);

      setMouvements(((mv.data ?? []) as { activite: string; observation: string | null; gene_observee: boolean | null; commentaire: string | null }[])
        .map(m => ({
          activite: m.activite, observation: m.observation ?? '', geneObservee: m.gene_observee, commentaire: m.commentaire ?? '',
        })));

      setLoadingExisting(false);
    })();
  }, [suiviIdParam]);

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

  async function handleSave(finaliser = false) {
    if (!user) return;
    if (finaliser && !dejaFinalise && !confirm('Finaliser le compte rendu ? Il pourra ensuite être partagé. Une correction restera possible : la version précédente sera conservée.')) return;
    setSaving(true);
    try {
      const source = activeProfileId ? 'professionnel' : 'proprietaire';
      const headerRow: Record<string, unknown> = {
        type_suivi: typeSuivi,
        date,
        niveau_activite: niveauActivite,
        professionnel_nom: professionnel.trim() || null,
        motif: motif.trim() || null,
        commentaires: commentaires.trim() || null,
        activite_sportive: activiteSportive.trim() || null,
        checkpoint_age: checkpoint.trim() || null,
        // Seulement si renseigné : sans migration_suivis_prochain_controle.sql la colonne n'existe pas.
        ...(activeProfileId && prochainControle ? { prochain_controle: prochainControle } : {}),
      };
      const poidsN = parseFloat(poids.replace(',', '.'));
      headerRow.poids = isNaN(poidsN) ? null : poidsN;
      const tailleN = parseFloat(taille.replace(',', '.'));
      headerRow.taille = isNaN(tailleN) ? null : tailleN;
      if (activeProfileId) {
        // Compte rendu de séance (colonnes migration_soins_reeducation.sql).
        Object.assign(headerRow, {
          intitule: intitule.trim() || null,
          observations_bilan: observationsBilan.trim() || null,
          intervention: intervention.trim() || null,
          suivi_recommande: suiviRecommande.trim() || null,
          orientation_veto: orientationVeto,
          lieu: lieu || null,
          avec_anatomie: avecAnatomie,
          statut: finaliser || dejaFinalise ? 'finalise' : 'brouillon',
          ...(finaliser && !dejaFinalise ? { finalise_a: new Date().toISOString() } : {}),
          // Correction d'un CR finalisé : updated_at change toujours → le
          // trigger archive la version précédente (exercices compris).
          ...(dejaFinalise ? { updated_at: new Date().toISOString() } : {}),
        });
      }
      if (saisieLibre) {
        headerRow.animal_nom_libre = animalNom.trim() || null;
        headerRow.espece_libre = espece;
        headerRow.client_nom_libre = clientNom.trim() || null;
        headerRow.client_contact_libre = clientContact.trim() || null;
      }

      let suiviId: string;
      if (isEditing && suiviIdParam) {
        suiviId = suiviIdParam;
        const { error } = await supabase.from('suivis_morpho').update(headerRow).eq('id', suiviId);
        if (error) throw error;
        // Les enfants sont entièrement recréés à chaque enregistrement (plus
        // simple et sûr qu'un diff champ par champ) ; les fichiers déjà
        // uploadés (photos/vidéos non remplacées) sont réutilisés tels quels
        // ci-dessous, sans nouvel upload.
        await Promise.all([
          supabase.from('suivis_morpho_photos').delete().eq('suivi_id', suiviId),
          supabase.from('suivis_morpho_videos').delete().eq('suivi_id', suiviId),
          supabase.from('suivis_morpho_points').delete().eq('suivi_id', suiviId),
          supabase.from('suivis_morpho_observations').delete().eq('suivi_id', suiviId),
          supabase.from('suivis_morpho_mouvements').delete().eq('suivi_id', suiviId),
          ...(activeProfileId ? [supabase.from('suivis_morpho_exercices').delete().eq('suivi_id', suiviId)] : []),
        ]);
      } else {
        const insertRow: Record<string, unknown> = { uid_auteur: user.uid, source, ...headerRow };
        if (animalId) insertRow.animal_id = animalId;
        if (activeProfileId) insertRow.pro_profile_id = activeProfileId;
        if (rdvIdParam) insertRow.rdv_id = rdvIdParam;
        const { data: inserted, error } = await supabase.from('suivis_morpho').insert(insertRow).select('id').single();
        if (error || !inserted) throw error ?? new Error('Échec de la création');
        suiviId = inserted.id as string;
      }
      const base = `animaux/${animalId ?? 'libre'}/morpho/${suiviId}`;

      for (const vue of new Set([...Object.keys(photosVues), ...Object.keys(photosVuesExistantes)])) {
        const url = photosVues[vue] ? await uploadPhoto(photosVues[vue], `${base}/${vue}.jpg`) : photosVuesExistantes[vue];
        if (url) await supabase.from('suivis_morpho_photos').insert({ suivi_id: suiviId, vue, url });
      }
      for (let i = 0; i < photosExtra.length; i++) {
        const url = await uploadPhoto(photosExtra[i], `${base}/extra_${i}.jpg`);
        await supabase.from('suivis_morpho_photos').insert({ suivi_id: suiviId, vue: 'autre', url });
      }
      for (const url of photosExtraExistantes) {
        await supabase.from('suivis_morpho_photos').insert({ suivi_id: suiviId, vue: 'autre', url });
      }
      for (let i = 0; i < videos.length; i++) {
        const v = videos[i];
        let url: string;
        if (v.file) {
          const ext = v.file.name.split('.').pop() || 'mp4';
          url = await uploadRawFile(v.file, `${base}/video_${i}.${ext}`);
        } else {
          url = v.existingUrl!;
        }
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
          ...(p.couleur ? { couleur: p.couleur } : {}),
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

      // Conseils et exercices (même compte rendu, même PDF)
      if (activeProfileId) {
        const stamp = Date.now();
        for (let i = 0; i < exercices.length; i++) {
          const e = exercices[i];
          const photoUrl = e.photoFile ? await uploadPhoto(e.photoFile, `${base}/exercice_${i}_${stamp}.jpg`) : (e.photo_url ?? null);
          const row: Record<string, unknown> = { suivi_id: suiviId, ordre: i, nom: e.nom.trim() };
          for (const k of ['description', 'consignes', 'frequence', 'duree', 'precautions'] as const) {
            if (e[k].trim()) row[k] = e[k].trim();
          }
          if (photoUrl) row.photo_url = photoUrl;
          const { error: errEx } = await supabase.from('suivis_morpho_exercices').insert(row);
          if (errEx) throw errEx;
        }
      }

      // Pas de notification automatique ici : le pro décide lui-même quand
      // le suivi est prêt à être transmis, via le bouton "Envoyer au
      // client" sur la fiche du suivi (/sante/suivis/[id]).

      router.push(`/sante/suivis/${suiviId}`);
    } catch (e) {
      alert(`Erreur : ${e instanceof Error ? e.message : e}`);
    } finally {
      setSaving(false);
    }
  }

  if (!user || !userData) return null;

  const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-500/30';

  if (loadingExisting) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-24 flex justify-center">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2" style={{ borderColor: TEAL }} />
      </div>
    );
  }

  const sections: [string, string][] = [
    ['seance', 'Séance'], ...(saisieLibre ? [['client', 'Client'] as [string, string]] : []),
    ['motif', 'Motif'], ['observations', 'Observations et bilan'], ['intervention', 'Intervention'],
    ['exercices', 'Conseils et exercices'], ['suivi', 'Suivi recommandé'], ['anatomie', 'Bilan anatomique'],
    ['medias', 'Photos et vidéos'], ['notes', 'Notes'],
  ];

  return (
    <div className="max-w-5xl mx-auto px-4 py-8 pb-28">
      <h1 className="text-2xl font-bold font-galey mb-1" style={{ color: TEAL }}>{isEditing ? 'Modifier la consultation' : 'Nouvelle consultation'}</h1>
      <p className="text-sm text-gray-500 mb-6">Un compte rendu unique par séance ; toutes les sections sont facultatives.</p>
      {dejaFinalise && (
        <p className="mb-5 rounded-xl bg-[#F1F5F4] px-4 py-3 text-sm text-gray-700">
          Compte rendu finalisé : la correction sera enregistrée comme nouvelle version, la précédente est conservée.
        </p>
      )}

      <div className="lg:grid lg:grid-cols-[190px_1fr] lg:gap-8">
        {/* Navigation entre les sections (grand écran) */}
        <nav className="hidden lg:block">
          <ul className="sticky top-24 space-y-1 text-sm">
            {sections.map(([id, label]) => (
              <li key={id}><a href={`#${id}`} className="block rounded-lg px-3 py-1.5 text-gray-600 hover:bg-gray-100 hover:text-gray-900">{label}</a></li>
            ))}
          </ul>
        </nav>

        <div className="space-y-6 min-w-0">
          <Card id="seance" title="Séance">
            <div className="grid sm:grid-cols-2 gap-3">
              <Field label="Date"><input type="date" className={inputCls} value={date} onChange={e => setDate(e.target.value)} /></Field>
              <Field label="Type de séance">
                <select className={inputCls} value={TYPES_SEANCE_PRO.some(t => t.key === typeSuivi) ? typeSuivi : 'autre'} onChange={e => setTypeSuivi(e.target.value)}>
                  {TYPES_SEANCE_PRO.map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
                </select>
              </Field>
            </div>
            <Field label="Lieu">
              <div className="flex flex-wrap gap-2">
                {([['cabinet', 'Cabinet'], ['exterieur', 'Intervention extérieure']] as const).map(([k, l]) => (
                  <button key={k} type="button" onClick={() => setLieu(v => v === k ? '' : k)}
                    className="px-3 py-1.5 rounded-full text-xs font-semibold"
                    style={lieu === k ? { background: TEAL, color: 'white' } : { background: '#F1F5F4', color: '#374151' }}>{l}</button>
                ))}
              </div>
            </Field>
            <div className="grid sm:grid-cols-2 gap-3">
              <Field label="Intitulé court (facultatif)"><input className={inputCls} value={intitule} onChange={e => setIntitule(e.target.value)} /></Field>
              <Field label="Professionnel"><input className={inputCls} value={professionnel} onChange={e => setProfessionnel(e.target.value)} /></Field>
            </div>
          </Card>

          {saisieLibre && (
            <Card id="client" title="Client sans application">
              <p className="text-xs text-gray-400">Animal sans fiche dans PetsMatch : le compte rendu PDF pourra être envoyé au client.</p>
              <Field label="Nom de l'animal"><input className={inputCls} value={animalNom} onChange={e => setAnimalNom(e.target.value)} /></Field>
              <div className="grid sm:grid-cols-2 gap-3">
                <Field label="Nom du client (facultatif)"><input className={inputCls} value={clientNom} onChange={e => setClientNom(e.target.value)} /></Field>
                <Field label="Contact — téléphone ou e-mail (facultatif)"><input className={inputCls} value={clientContact} onChange={e => setClientContact(e.target.value)} /></Field>
              </div>
            </Card>
          )}

          <Card id="motif" title="Motif de consultation">
            <textarea rows={4} className={inputCls} placeholder="Motif, demande du propriétaire, contexte, informations utiles"
              value={motif} onChange={e => setMotif(e.target.value)} />
          </Card>

          <Card id="observations" title="Observations et bilan">
            <textarea rows={6} className={inputCls} placeholder="Observations générales, posture, mobilité, locomotion, zones évaluées…"
              value={observationsBilan} onChange={e => setObservationsBilan(e.target.value)} />
            <div className="grid sm:grid-cols-4 gap-3">
              <Field label="Poids (kg)"><input className={inputCls} value={poids} onChange={e => setPoids(e.target.value)} /></Field>
              <Field label="Taille (cm)"><input className={inputCls} value={taille} onChange={e => setTaille(e.target.value)} /></Field>
              <Field label="Niveau d'activité">
                <select className={inputCls} value={niveauActivite} onChange={e => setNiveauActivite(e.target.value)}>
                  {NIVEAUX_ACTIVITE.map(n => <option key={n.key} value={n.key}>{n.label}</option>)}
                </select>
              </Field>
              <Field label="Activité sportive"><input className={inputCls} value={activiteSportive} onChange={e => setActiviteSportive(e.target.value)} /></Field>
            </div>
            <details className="rounded-xl border border-gray-100 px-3 py-2">
              <summary className="cursor-pointer text-sm font-semibold text-gray-700">Posture (facultatif)</summary>
              <div className="space-y-3 mt-3">
                {CATEGORIES_OBSERVATION_STATIQUE.map(c => (
                  <ObservationRow key={c.key} categorie={c.key} label={c.label} state={observations[c.key]}
                    onChange={(o) => setObservations(prev => ({ ...prev, [c.key]: o }))} inputCls={inputCls} />
                ))}
              </div>
            </details>
            <div>
              <p className="text-sm font-semibold text-gray-700 mb-2">En mouvement (facultatif)</p>
              {mouvements.map((m, i) => (
                <div key={i} className="flex items-center gap-2 mb-2 text-sm">
                  <span className="flex-1">{labelActivite(m.activite)}{m.geneObservee ? ' — gêne observée' : ''}</span>
                  <button onClick={() => setMouvements(ms => ms.filter((_, j) => j !== i))} className="text-gray-400 hover:text-red-500" aria-label="Retirer">✕</button>
                </div>
              ))}
              <button onClick={() => setMouvementSheetOpen(true)} className="text-sm font-semibold" style={{ color: TEAL }}>+ Ajouter une observation en mouvement</button>
            </div>
          </Card>

          <Card id="intervention" title="Intervention réalisée">
            <textarea rows={6} className={inputCls} placeholder="Zones travaillées, techniques utilisées, déroulement, observations après la séance, précautions…"
              value={intervention} onChange={e => setIntervention(e.target.value)} />
          </Card>

          <Card id="exercices" title={`Conseils et exercices${exercices.length ? ` (${exercices.length})` : ''}`}>
            <p className="text-xs text-gray-400">Recommandations à réaliser par le propriétaire (ce ne sont pas des ordonnances).</p>
            {exercices.map((e, i) => (
              <button key={i} type="button" onClick={() => setExerciceEdit({ index: i, ex: e })}
                className="w-full text-left rounded-xl border border-gray-200 bg-[#F7F9F9] px-4 py-3 hover:border-gray-300">
                <span className="block text-sm font-semibold text-gray-900">{e.nom}</span>
                {(e.frequence || e.duree) && <span className="block text-xs text-gray-500">{[e.frequence, e.duree].filter(Boolean).join(' · ')}</span>}
              </button>
            ))}
            <button onClick={() => setExerciceEdit({ index: null, ex: { ...EXERCICE_VIDE } })} className="text-sm font-semibold" style={{ color: TEAL }}>+ Ajouter un conseil ou un exercice</button>
          </Card>

          <Card id="suivi" title="Suivi recommandé">
            <textarea rows={4} className={inputCls} placeholder="Évolution à surveiller, recommandations complémentaires…"
              value={suiviRecommande} onChange={e => setSuiviRecommande(e.target.value)} />
            <label className="flex items-center gap-2 text-sm text-gray-700">
              <input type="checkbox" checked={orientationVeto} onChange={e => setOrientationVeto(e.target.checked)} className="w-4 h-4" style={{ accentColor: TEAL }} />
              Orientation vers un vétérinaire conseillée
            </label>
            <Field label="Contrôle conseillé (facultatif)">
              <input type="date" className={`${inputCls} sm:max-w-xs`} value={prochainControle} onChange={e => setProchainControle(e.target.value)} />
            </Field>
          </Card>

          <Card id="anatomie" title="Bilan anatomique">
            <label className="flex items-center gap-2 text-sm font-semibold text-gray-800">
              <input type="checkbox" checked={avecAnatomie} onChange={e => setAvecAnatomie(e.target.checked)} className="w-4 h-4" style={{ accentColor: TEAL }} />
              Ajouter un bilan anatomique
            </label>
            {avecAnatomie ? (
              <>
                <div className="flex flex-wrap gap-2 justify-center">
                  {vuesDisponibles(espece).map(v => (
                    <button key={v.key} onClick={() => setVueSilhouette(v.key)}
                      className="px-3 py-1.5 rounded-full text-xs font-semibold"
                      style={vueSilhouette === v.key ? { background: TEAL, color: 'white' } : { background: '#F1F5F4', color: '#374151' }}>
                      {v.label}
                    </button>
                  ))}
                </div>
                <MorphoSilhouette espece={espece} vue={vueSilhouette} points={points} onTapEmpty={addPointAt} onTapPoint={editPoint} onVueChange={setVueSilhouette} />
                <MorphoLegende />
                <p className="text-xs text-gray-400 text-center">Cliquez sur la silhouette pour poser un point</p>
              </>
            ) : points.length > 0 ? (
              <p className="text-xs text-gray-400">{points.length} point{points.length > 1 ? 's' : ''} déjà posé{points.length > 1 ? 's' : ''}, conservé{points.length > 1 ? 's' : ''} mais absent{points.length > 1 ? 's' : ''} du compte rendu.</p>
            ) : (
              <p className="text-xs text-gray-400">Silhouettes et points de repérage, intégrés au compte rendu.</p>
            )}
          </Card>

          <Card id="medias" title="Photos et vidéos">
            <p className="text-xs text-gray-400">Facultatif : posture, démarche, positionnement…</p>
            <PhotoGrid photos={photosVues} existingUrls={photosVuesExistantes}
              onChange={setPhotosVues} onReplaceExisting={vue => setPhotosVuesExistantes(p => { const n = { ...p }; delete n[vue]; return n; })} />
            <p className="text-xs font-semibold text-gray-600 mt-2">Autres photos</p>
            <div className="flex flex-wrap gap-2">
              {photosExtraExistantes.map((url, i) => (
                <div key={`existing-${i}`} className="relative">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={url} alt="" className="w-16 h-16 rounded-lg object-cover" />
                  <button onClick={() => setPhotosExtraExistantes(p => p.filter((_, j) => j !== i))}
                    className="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-black/60 text-white text-xs flex items-center justify-center" aria-label="Retirer">✕</button>
                </div>
              ))}
              {photosExtra.map((f, i) => (
                <div key={i} className="relative">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={URL.createObjectURL(f)} alt="" className="w-16 h-16 rounded-lg object-cover" />
                  <button onClick={() => setPhotosExtra(p => p.filter((_, j) => j !== i))}
                    className="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-black/60 text-white text-xs flex items-center justify-center" aria-label="Retirer">✕</button>
                </div>
              ))}
              <label className="w-16 h-16 rounded-lg bg-gray-100 flex items-center justify-center cursor-pointer text-2xl" style={{ color: TEAL }}>
                +
                <input type="file" accept="image/*" className="hidden" onChange={e => { const f = e.target.files?.[0]; if (f) setPhotosExtra(p => [...p, f]); }} />
              </label>
            </div>
            <p className="text-xs font-semibold text-gray-600 mt-2">Vidéos</p>
            {videos.map((v, i) => (
              <div key={i} className="flex items-center gap-2 text-sm">
                <span className="flex-1">Vidéo — {labelActivite(v.activite)}</span>
                <button onClick={() => setVideos(vs => vs.filter((_, j) => j !== i))} className="text-gray-400 hover:text-red-500" aria-label="Retirer">✕</button>
              </div>
            ))}
            <button onClick={() => setVideoSheetOpen(true)} className="text-sm font-semibold" style={{ color: TEAL }}>+ Ajouter une vidéo</button>
          </Card>

          <Card id="notes" title="Notes complémentaires">
            <textarea rows={3} className={inputCls} placeholder="Commentaires généraux" value={commentaires} onChange={e => setCommentaires(e.target.value)} />
          </Card>
        </div>
      </div>

      <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-100 p-4 z-30">
        <div className="max-w-5xl mx-auto flex gap-3 justify-end">
          {dejaFinalise ? (
            <button disabled={saving} onClick={() => handleSave()}
              className="px-6 py-3 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>
              {saving ? 'Enregistrement…' : 'Enregistrer la correction'}
            </button>
          ) : (
            <>
              <button disabled={saving} onClick={() => handleSave()}
                className="px-6 py-3 rounded-xl text-sm font-bold border disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
                Enregistrer le brouillon
              </button>
              <button disabled={saving} onClick={() => handleSave(true)}
                className="px-6 py-3 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>
                {saving ? 'Enregistrement…' : 'Finaliser'}
              </button>
            </>
          )}
        </div>
      </div>

      {exerciceEdit && (
        <ExerciceSheet initial={exerciceEdit.ex} allowDelete={exerciceEdit.index !== null}
          onClose={() => setExerciceEdit(null)}
          onDelete={() => { const i = exerciceEdit.index; setExercices(l => l.filter((_, j) => j !== i)); setExerciceEdit(null); }}
          onSave={(ex) => {
            const i = exerciceEdit.index;
            setExercices(l => i === null ? [...l, ex] : l.map((x, j) => (j === i ? ex : x)));
            setExerciceEdit(null);
          }} />
      )}
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

function Card({ id, title, children }: { id?: string; title: string; children: React.ReactNode }) {
  return (
    <div id={id} className="scroll-mt-24">
      <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">{title}</h2>
      <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3">{children}</div>
    </div>
  );
}
function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><label className="block text-xs font-galey text-gray-500 mb-1">{label}</label>{children}</div>;
}

function PhotoGrid({ photos, existingUrls = {}, onChange, onReplaceExisting }: {
  photos: Record<string, File>; existingUrls?: Record<string, string>;
  onChange: (p: Record<string, File>) => void; onReplaceExisting?: (vue: string) => void;
}) {
  function Slot({ vueKey, label }: { vueKey: string; label: string }) {
    const file = photos[vueKey];
    const existingUrl = existingUrls[vueKey];
    return (
      <div className="flex flex-col items-center gap-1.5">
        <span className="text-[11px] font-bold font-galey text-gray-500">{label}</span>
        <label className="w-20 h-20 rounded-xl bg-gray-100 flex items-center justify-center cursor-pointer overflow-hidden border border-gray-200">
          {file ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={URL.createObjectURL(file)} alt={label} className="w-full h-full object-cover" />
          ) : existingUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={existingUrl} alt={label} className="w-full h-full object-cover" />
          ) : (
            <span style={{ color: TEAL }}>📷</span>
          )}
          <input type="file" accept="image/*" className="hidden"
            onChange={e => { const f = e.target.files?.[0]; if (f) { onChange({ ...photos, [vueKey]: f }); onReplaceExisting?.(vueKey); } }} />
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
  const [couleur, setCouleur] = useState((point.couleur ?? colorCategoriePoint(point.categorie)).replace('#', ''));
  const [note, setNote] = useState(point.note ?? '');
  const [labelError, setLabelError] = useState(false);
  const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey';
  return (
    <SheetShell title="Point" onClose={onClose}>
      <p className="text-xs font-galey font-semibold text-gray-600 mb-1.5">Couleur</p>
      <div className="flex flex-wrap gap-2.5 mb-3">
        {PALETTE_COULEURS_POINTS.map(c => {
          const hex = c.replace('#', '');
          const selected = couleur === hex;
          return (
            <button key={c} onClick={() => setCouleur(hex)}
              className="w-8 h-8 rounded-full flex items-center justify-center"
              style={{ background: c, border: selected ? '2.5px solid #1F2A2E' : '2.5px solid transparent' }}>
              {selected && <span className="text-white text-xs">✓</span>}
            </button>
          );
        })}
      </div>
      <p className="text-xs font-galey font-semibold text-gray-600 mb-1.5">Catégorie (optionnel, pour classer le point)</p>
      <div className="flex flex-wrap gap-1.5 mb-3">
        {CATEGORIES_OSTEO.map(c => (
          <button key={c.key} onClick={() => setCategorie(c.key)}
            className="px-2.5 py-1 rounded-full text-xs font-galey"
            style={categorie === c.key ? { background: `${c.color}40`, fontWeight: 700 } : { background: '#F3F4F6', color: '#6B7280' }}>
            {c.label}
          </button>
        ))}
      </div>
      <p className="text-xs font-galey font-semibold mb-1.5" style={{ color: labelError ? '#DC2626' : '#4B5563' }}>Ce qui a été travaillé *</p>
      <textarea className={inputCls} rows={2} placeholder="Ex. « Point tendu », « Zone travaillée en profondeur »"
        value={note} onChange={e => { setNote(e.target.value); if (labelError) setLabelError(false); }} />
      {labelError && <p className="text-xs font-galey text-red-600 mt-1">Décrivez ce point pour la légende</p>}
      <div className="flex gap-2 mt-4">
        {allowDelete && (
          <button onClick={onDelete} className="text-red-500 text-sm font-galey font-semibold px-3">Supprimer</button>
        )}
        <button onClick={() => { if (!note.trim()) { setLabelError(true); return; } onSave({ ...point, categorie, note: note.trim(), couleur }); }}
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

function ExerciceSheet({ initial, allowDelete, onSave, onDelete, onClose }: {
  initial: ExerciceEntree; allowDelete: boolean; onSave: (e: ExerciceEntree) => void; onDelete: () => void; onClose: () => void;
}) {
  const [e, setE] = useState<ExerciceEntree>(initial);
  const [erreurNom, setErreurNom] = useState(false);
  const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey';
  const champ = (k: 'description' | 'consignes' | 'frequence' | 'duree' | 'precautions') =>
    (v: string) => setE(x => ({ ...x, [k]: v }));
  const apercu = e.photoFile ? URL.createObjectURL(e.photoFile) : e.photo_url;
  return (
    <SheetShell title={allowDelete ? "Modifier le conseil ou l'exercice" : 'Conseil ou exercice'} onClose={onClose}>
      <div className="space-y-2.5 max-h-[70vh] overflow-y-auto">
        <input className={inputCls} placeholder="Nom *" value={e.nom}
          onChange={ev => { setE(x => ({ ...x, nom: ev.target.value })); setErreurNom(false); }} />
        {erreurNom && <p className="text-xs text-red-600">Indiquez un nom</p>}
        <textarea rows={2} className={inputCls} placeholder="Description" value={e.description} onChange={ev => champ('description')(ev.target.value)} />
        <textarea rows={2} className={inputCls} placeholder="Consignes de réalisation" value={e.consignes} onChange={ev => champ('consignes')(ev.target.value)} />
        <div className="grid grid-cols-2 gap-2">
          <input className={inputCls} placeholder="Fréquence" value={e.frequence} onChange={ev => champ('frequence')(ev.target.value)} />
          <input className={inputCls} placeholder="Durée" value={e.duree} onChange={ev => champ('duree')(ev.target.value)} />
        </div>
        <textarea rows={2} className={inputCls} placeholder="Précautions particulières" value={e.precautions} onChange={ev => champ('precautions')(ev.target.value)} />
        <div className="flex items-center gap-3">
          {apercu && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={apercu} alt="" className="w-14 h-14 rounded-lg object-cover" />
          )}
          <label className="text-sm font-semibold cursor-pointer" style={{ color: TEAL }}>
            {apercu ? 'Changer la photo' : '+ Photo ou illustration'}
            <input type="file" accept="image/*" className="hidden" onChange={ev => { const f = ev.target.files?.[0]; if (f) setE(x => ({ ...x, photoFile: f })); }} />
          </label>
          {apercu && <button type="button" onClick={() => setE(x => ({ ...x, photoFile: null, photo_url: null }))} className="text-xs text-gray-400">Retirer</button>}
        </div>
      </div>
      <div className="flex gap-2 mt-4">
        {allowDelete && <button onClick={onDelete} className="text-red-500 text-sm font-galey font-semibold px-3">Supprimer</button>}
        <button onClick={() => { if (!e.nom.trim()) { setErreurNom(true); return; } onSave({ ...e, nom: e.nom.trim() }); }}
          className="flex-1 py-2.5 rounded-xl text-sm font-galey font-bold text-white" style={{ background: TEAL }}>
          Valider
        </button>
      </div>
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
