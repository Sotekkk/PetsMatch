'use client';

import { useEffect, useState, use as usePromise } from 'react';
import { useRouter } from 'next/navigation';
import { httpsCallable } from 'firebase/functions';
import { supabase } from '@/lib/supabase';
import { functions } from '@/lib/firebase';
import { useSanteAccess } from '@/hooks/useSanteAccess';
import MorphoSilhouette from '@/components/morpho/MorphoSilhouette';
import {
  TEAL, labelTypeSuivi, titreCompteRendu, labelActivite, type ExerciceSeance, labelCategoriePoint, colorPointEffectif,
  CATEGORIES_OBSERVATION_STATIQUE, labelsValeurObservation, colorValeurObservation,
  SOURCE_LABELS, MORPHO_AVERTISSEMENT, VUES_PHOTOS, NIVEAUX_ACTIVITE,
  morphoSpeciesKey, vuesDisponibles, type MorphoPoint,
} from '@/lib/morpho';
import { morphoSuiviPdfBlob } from '@/lib/morpho-pdf';
import { maSignaturePro, enregistrerSignaturePro } from '@/lib/signature-pro';
import SignatureProModal from '@/components/signature/SignatureProModal';
import FinConsultationModal from '@/components/rdv/FinConsultationModal';

interface SuiviRow { [k: string]: unknown }

export default function SuiviDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = usePromise(params);
  const { user, userData, isSante, loading: authLoading } = useSanteAccess();
  const [signer, setSigner] = useState(false);
  const router = useRouter();

  const [loading, setLoading] = useState(true);
  const [suivi, setSuivi] = useState<SuiviRow | null>(null);
  const [animal, setAnimal] = useState<{ nom?: string; espece?: string; race?: string; sexe?: string; date_naissance?: string; identification?: string }>({});
  const [pro, setPro] = useState<{ nom?: string; profession?: string; adresse?: string; tel?: string; email?: string }>({});
  const [photos, setPhotos] = useState<{ vue: string; url: string }[]>([]);
  const [videos, setVideos] = useState<{ activite: string; commentaire: string | null; url: string }[]>([]);
  const [points, setPoints] = useState<MorphoPoint[]>([]);
  const [observations, setObservations] = useState<{ categorie: string; valeur: string; commentaire: string | null }[]>([]);
  const [mouvements, setMouvements] = useState<{ activite: string; observation: string | null; gene_observee: boolean | null; commentaire: string | null }[]>([]);
  const [exercices, setExercices] = useState<ExerciceSeance[]>([]);
  const [finalisant, setFinalisant] = useState(false);
  const [vue, setVue] = useState('profil_d');
  const [exporting, setExporting] = useState(false);
  // Séance d'un RDV : fin de séance (envoi compte rendu + facture, facture acquittée).
  const [finSeance, setFinSeance] = useState(false);
  const [sendingNotif, setSendingNotif] = useState(false);
  // Accessible au pro qui a réalisé le suivi (isSante) OU au propriétaire
  // enregistré de l'animal (pour qu'il puisse consulter/imprimer son bilan
  // depuis la notification reçue) — déterminé une fois le suivi chargé.
  const [authorized, setAuthorized] = useState<boolean | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
  }, [user, authLoading, router]);

  useEffect(() => {
    if (authorized === false) router.push('/');
  }, [authorized, router]);

  useEffect(() => {
    if (authLoading || !user) return;
    (async () => {
      const { data: s } = await supabase.from('suivis_morpho').select('*').eq('id', id).maybeSingle();
      if (!s) { setLoading(false); setAuthorized(false); return; }
      setSuivi(s);

      if (isSante) {
        setAuthorized(true);
      } else if (s.animal_id && user) {
        const { data: propRow } = await supabase.from('animaux_proprietes')
          .select('id').eq('animal_id', s.animal_id as string).eq('uid_proprio', user.uid)
          .is('date_fin', null).maybeSingle();
        setAuthorized(!!propRow);
      } else {
        setAuthorized(false);
      }
      const espece = morphoSpeciesKey((s.espece_libre as string) ?? '') ?? 'chien';
      setVue(vuesDisponibles(espece)[0]?.key ?? 'profil_d');

      const [ph, vi, pt, ob, mv] = await Promise.all([
        supabase.from('suivis_morpho_photos').select('vue, url').eq('suivi_id', id),
        supabase.from('suivis_morpho_videos').select('activite, commentaire, url').eq('suivi_id', id),
        supabase.from('suivis_morpho_points').select('id, vue, x_pct, y_pct, categorie, note').eq('suivi_id', id),
        supabase.from('suivis_morpho_observations').select('categorie, valeur, commentaire').eq('suivi_id', id),
        supabase.from('suivis_morpho_mouvements').select('activite, observation, gene_observee, commentaire').eq('suivi_id', id),
      ]);
      setPhotos((ph.data ?? []) as { vue: string; url: string }[]);
      setVideos((vi.data ?? []) as { activite: string; commentaire: string | null; url: string }[]);
      setPoints(((pt.data ?? []) as { id: string; vue: string; x_pct: number; y_pct: number; categorie: string; note: string | null }[])
        .map(p => ({ ...p, id: String(p.id) })));
      setObservations((ob.data ?? []) as { categorie: string; valeur: string; commentaire: string | null }[]);
      setMouvements((mv.data ?? []) as { activite: string; observation: string | null; gene_observee: boolean | null; commentaire: string | null }[]);
      // Conseils et exercices (migration_soins_reeducation.sql ; absente → liste vide)
      const { data: ex } = await supabase.from('suivis_morpho_exercices').select('*').eq('suivi_id', id).order('ordre');
      setExercices((ex ?? []) as ExerciceSeance[]);

      if (s.animal_id) {
        const { data: a } = await supabase.from('animaux').select('nom, espece, race, sexe, date_naissance, identification').eq('id', s.animal_id).maybeSingle();
        setAnimal(a ?? { nom: (s.animal_nom_libre as string) ?? 'Animal', espece: (s.espece_libre as string) ?? undefined });
      } else {
        setAnimal({ nom: (s.animal_nom_libre as string) ?? 'Animal', espece: (s.espece_libre as string) ?? undefined });
      }
      const proProfileId = s.pro_profile_id as string | null;
      if (proProfileId) {
        const { data: p } = await supabase.from('user_profiles_complet').select('nom, firstname, lastname, adress, phone_number, email_contact, profession_pro').eq('id', proProfileId).maybeSingle();
        const nom = (p?.nom as string)?.trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim();
        setPro({ nom, profession: p?.profession_pro as string, adresse: p?.adress as string, tel: p?.phone_number as string, email: p?.email_contact as string });
      }
      setLoading(false);
    })();
  }, [id, authLoading, user, isSante]);

  /** Télécharge le PDF unique de la séance ; renvoie le nom du fichier. */
  async function telechargerPdf(): Promise<string | null> {
    if (!suivi) return null;
    // Signature du praticien : seulement sur ses propres séances.
    const signature = user && suivi.uid_auteur === user.uid ? await maSignaturePro(user.uid).catch(() => null) : null;
    const blob = await morphoSuiviPdfBlob({ suivi, animal, pro, photos, points, observations, mouvements, exercices, signature });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    const nomAnimal = (animal.nom || 'animal').replace(/\s+/g, '_');
    const nomPraticien = pro.nom?.trim() ? pro.nom.replace(/\s+/g, '_') : null;
    const dateStr = String(suivi.date ?? '').slice(0, 10);
    a.href = url;
    a.download = [suivi.source === 'professionnel' ? 'compte_rendu' : 'suivi_morpho', nomAnimal, nomPraticien, dateStr].filter(Boolean).join('_') + '.pdf';
    a.click();
    URL.revokeObjectURL(url);
    return a.download;
  }

  async function handleExport() {
    if (!suivi) return;
    setExporting(true);
    try {
      await telechargerPdf();
    } catch (e) {
      alert(`Erreur export : ${e instanceof Error ? e.message : e}`);
    } finally {
      setExporting(false);
    }
  }

  // Envoi manuel de la notification au(x) propriétaire(s) — décidé par le
  // pro (pas automatique à l'enregistrement), pour ne prévenir le client
  // qu'une fois le suivi réellement complet. Miroir de morpho_detail_page.dart (app).
  async function handleEnvoyerNotification() {
    if (!suivi || !user) return;
    if (!suivi.animal_id) return;
    setSendingNotif(true);
    try {
      // Tout se passe côté serveur (notifyOwnerMorphoBilan) : notification
      // in-app + push FCM — une simple ligne dans `notifications` ne
      // déclenche pas de push, il faut passer par la Cloud Function comme
      // pour les autres notifications du site.
      const call = httpsCallable(functions, 'notifyOwnerMorphoBilan');
      const result = await call({ suiviId: id });
      const sent = (result.data as { sent?: number } | undefined)?.sent ?? 0;
      const now = new Date().toISOString();
      setSuivi(prev => (prev ? { ...prev, notifie_a: now } : prev));
      if (sent === 0) {
        alert('Envoyé, mais aucun propriétaire distinct trouvé à notifier (peut-être le même compte que vous).');
      }
    } catch (e) {
      alert(`Erreur : ${e instanceof Error ? e.message : e}`);
    } finally {
      setSendingNotif(false);
    }
  }

  // Client sans application : PDF téléchargé + message prérempli (e-mail si
  // le contact en est un), puis compte rendu marqué « envoyé ». Miroir de
  // _envoyerHorsAppli (appli, menu de partage du téléphone).
  async function handleEnvoyerHorsAppli() {
    if (!suivi) return;
    setSendingNotif(true);
    try {
      const fichier = await telechargerPdf();
      const contact = String(suivi.client_contact_libre ?? '').trim();
      const nomAnimal = animal.nom || 'votre animal';
      const sujet = `${titreCompteRendu(suivi.type_suivi as string)} — ${nomAnimal}`;
      const corps = `Bonjour,

Vous trouverez ci-joint le compte rendu de la séance de ${nomAnimal}${fichier ? ` (${fichier})` : ''}.${pro.nom ? `

${pro.nom}` : ''}`;
      if (contact.includes('@')) {
        window.location.href = `mailto:${encodeURIComponent(contact)}?subject=${encodeURIComponent(sujet)}&body=${encodeURIComponent(corps)}`;
      } else {
        alert('PDF téléchargé : joignez-le à votre message au client (e-mail, WhatsApp…).');
      }
      const now = new Date().toISOString();
      await supabase.from('suivis_morpho').update({ notifie_a: now }).eq('id', id);
      setSuivi(prev => (prev ? { ...prev, notifie_a: now } : prev));
    } catch (e) {
      alert(`Envoi impossible : ${e instanceof Error ? e.message : e}`);
    } finally {
      setSendingNotif(false);
    }
  }

  // Brouillon → finalisé : partageable ensuite ; corrections tracées (versions).
  async function handleFinaliser() {
    if (!suivi) return;
    if (!confirm('Finaliser le compte rendu ? Il pourra ensuite être partagé. Une correction restera possible : la version précédente sera conservée.')) return;
    setFinalisant(true);
    const finalise_a = new Date().toISOString();
    const { error } = await supabase.from('suivis_morpho').update({ statut: 'finalise', finalise_a }).eq('id', id);
    setFinalisant(false);
    if (error) { alert(`Erreur : ${error.message}`); return; }
    setSuivi(prev => (prev ? { ...prev, statut: 'finalise', finalise_a } : prev));
  }

  async function handleDelete() {
    if (!suivi) return;
    if (!confirm('Supprimer ce suivi ? Cette action est définitive et supprime aussi ses photos, vidéos et points.')) return;
    await supabase.from('suivis_morpho').delete().eq('id', id);
    router.push('/sante/suivis');
  }

  if (!user || !userData) return null;
  if (loading || authorized === null) return <div className="flex justify-center py-24"><div className="animate-spin rounded-full h-10 w-10 border-b-2" style={{ borderColor: TEAL }} /></div>;
  if (!authorized) return null;
  if (!suivi) return <div className="text-center py-24 text-gray-400 font-galey">Suivi introuvable.</div>;

  const espece = morphoSpeciesKey((suivi.espece_libre as string) ?? animal.espece ?? '') ?? 'chien';
  const photoForVue = (v: string) => photos.find(p => p.vue === v);
  const extra = photos.filter(p => p.vue === 'autre');
  const pointsForVue = points.filter(p => p.vue === vue);
  const source = (suivi.source as string) ?? 'proprietaire';
  const statut = (suivi.statut as string | null) ?? null;
  const brouillon = statut === 'brouillon';
  const sansAnatomie = suivi.avec_anatomie === false;
  const texte = (k: string) => (typeof suivi[k] === 'string' && (suivi[k] as string).trim() ? (suivi[k] as string).trim() : null);

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold font-galey" style={{ color: TEAL }}>
            {source === 'professionnel' ? titreCompteRendu(suivi.type_suivi as string) : labelTypeSuivi(suivi.type_suivi as string)}
          </h1>
          {brouillon && <p className="text-xs font-semibold text-[#B45309]">Brouillon — non visible du client</p>}
        </div>
        <div className="flex items-center gap-2">
          {isSante && (
            <>
              <button onClick={() => router.push(`/sante/suivis/nouveau?suiviId=${id}${suivi.animal_id ? `&animalId=${suivi.animal_id}` : ''}&espece=${encodeURIComponent(espece)}`)}
                className="px-3 py-2 rounded-full text-sm font-galey font-semibold border" style={{ borderColor: TEAL, color: TEAL }}>
                {statut === 'finalise' ? 'Corriger' : 'Modifier'}
              </button>
              {/* Un compte rendu finalisé reste tracé : pas de suppression. */}
              {statut !== 'finalise' && (
                <button onClick={handleDelete}
                  className="px-3 py-2 rounded-full text-sm font-galey font-semibold border border-red-200 text-red-600">
                  Supprimer
                </button>
              )}
            </>
          )}
          {suivi.source === 'professionnel' && user && suivi.uid_auteur === user.uid && (
            <button onClick={() => setSigner(true)} title="Apposée sur vos comptes rendus de séance"
              className="px-3 py-2 rounded-full text-sm font-galey font-semibold border" style={{ borderColor: TEAL, color: TEAL }}>
              Ma signature
            </button>
          )}
          <button disabled={exporting} onClick={handleExport}
            className="text-white px-4 py-2 rounded-full text-sm font-galey font-semibold disabled:opacity-50" style={{ background: TEAL }}>
            {exporting ? 'Export…' : brouillon ? 'Aperçu PDF' : 'Exporter PDF'}
          </button>
        </div>
      </div>

      <div className="bg-gray-50 rounded-xl p-3 flex gap-2 items-start">
        <span>ℹ️</span>
        <p className="text-xs text-gray-600 font-galey">{MORPHO_AVERTISSEMENT}</p>
      </div>

      <Card>
        {suivi.date ? <Line label="Date" value={new Date(suivi.date as string).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })} /> : null}
        {!suivi.animal_id && suivi.animal_nom_libre ? <Line label="Animal" value={suivi.animal_nom_libre as string} /> : null}
        {suivi.client_nom_libre ? <Line label="Client" value={suivi.client_nom_libre as string} /> : null}
        {suivi.client_contact_libre ? <Line label="Contact" value={suivi.client_contact_libre as string} /> : null}
        {suivi.professionnel_nom ? <Line label="Professionnel" value={suivi.professionnel_nom as string} /> : null}
        {texte('intitule') ? <Line label="Intitulé" value={texte('intitule')!} /> : null}
        {suivi.lieu === 'cabinet' || suivi.lieu === 'exterieur'
          ? <Line label="Lieu" value={suivi.lieu === 'cabinet' ? 'Cabinet' : 'Intervention extérieure'} /> : null}
        {suivi.motif ? <Line label="Motif" value={suivi.motif as string} /> : null}
        {suivi.poids ? <Line label="Poids" value={`${suivi.poids} kg`} /> : null}
        {suivi.taille ? <Line label="Taille" value={`${suivi.taille} cm`} /> : null}
        {suivi.niveau_activite && suivi.niveau_activite !== 'non_evalue' ? (
          <Line label="Niveau d'activité" value={NIVEAUX_ACTIVITE.find(n => n.key === suivi.niveau_activite)?.label ?? ''} />
        ) : null}
        {suivi.checkpoint_age ? <Line label="Étape" value={suivi.checkpoint_age as string} /> : null}
        {suivi.commentaires ? <p className="text-sm font-galey text-gray-700 mt-2 whitespace-pre-line">{suivi.commentaires as string}</p> : null}
        {source === 'professionnel' && pro.nom ? (
          <div className="mt-2 rounded-xl p-3" style={{ background: `${TEAL}0F` }}>
            <p className="text-[10px] font-galey font-bold uppercase tracking-wide" style={{ color: `${TEAL}CC` }}>Réalisé par</p>
            <p className="text-sm font-galey font-bold text-gray-800 mt-0.5">{pro.nom}</p>
            {pro.profession && <p className="text-xs font-galey text-gray-500">{pro.profession}</p>}
            {[pro.adresse, pro.tel, pro.email].some(Boolean) && (
              <p className="text-[11px] font-galey text-gray-400 mt-0.5">{[pro.adresse, pro.tel, pro.email].filter(Boolean).join('  ·  ')}</p>
            )}
          </div>
        ) : (
          <span className="inline-block mt-2 px-2.5 py-1 rounded-full text-xs font-galey font-bold" style={{ background: `${TEAL}18`, color: TEAL }}>
            {SOURCE_LABELS[source] ?? source}
          </span>
        )}
      </Card>

      {isSante && brouillon && (
        <div className="rounded-2xl p-4 bg-white border border-gray-100 shadow-sm flex items-center justify-between gap-3">
          <div>
            <p className="text-sm font-bold font-galey text-gray-800">Brouillon</p>
            <p className="text-xs font-galey text-gray-400">Non visible du client. Finalisez-le pour pouvoir le partager.</p>
          </div>
          <button disabled={finalisant} onClick={handleFinaliser}
            className="text-white px-4 py-2 rounded-full text-sm font-galey font-semibold disabled:opacity-50 flex-shrink-0" style={{ background: TEAL }}>
            {finalisant ? 'Finalisation…' : 'Finaliser'}
          </button>
        </div>
      )}

      {isSante && !brouillon && !suivi.animal_id && (
        <div className="rounded-2xl p-4 bg-white border border-gray-100 shadow-sm flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-sm font-bold font-galey text-gray-800">
              {suivi.notifie_a
                ? `Envoyé au client le ${new Date(suivi.notifie_a as string).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}`
                : 'Client sans application'}
            </p>
            {(suivi.client_nom_libre || suivi.client_contact_libre) ? (
              <p className="text-xs font-galey text-gray-500 truncate">{[suivi.client_nom_libre, suivi.client_contact_libre].filter(Boolean).join('  ·  ') as string}</p>
            ) : null}
          </div>
          <button disabled={sendingNotif} onClick={handleEnvoyerHorsAppli}
            className="text-white px-4 py-2 rounded-full text-sm font-galey font-semibold disabled:opacity-50 flex-shrink-0" style={{ background: TEAL }}>
            {sendingNotif ? 'Envoi…' : suivi.notifie_a ? 'Renvoyer le compte rendu' : 'Envoyer le compte rendu'}
          </button>
        </div>
      )}

      {isSante && !brouillon && !!suivi.rdv_id && (
        <div className="rounded-2xl p-4 bg-white border border-gray-100 shadow-sm flex items-center justify-between gap-3">
          <div>
            <p className="text-sm font-bold font-galey text-gray-800">Fin de séance</p>
            <p className="text-xs font-galey text-gray-400">Facture, envoi du compte rendu et de la facture par e-mail, facture acquittée.</p>
          </div>
          <button onClick={() => setFinSeance(true)}
            className="text-white px-4 py-2 rounded-full text-sm font-galey font-semibold flex-shrink-0" style={{ background: TEAL }}>
            Fin de séance
          </button>
        </div>
      )}
      {finSeance && !!suivi.rdv_id && (
        <FinConsultationModal metier="sante" rdvId={String(suivi.rdv_id)} proProfileId={(suivi.pro_profile_id as string | null) ?? null}
          onClose={() => setFinSeance(false)} onDone={() => setFinSeance(false)} />
      )}

      {isSante && !brouillon && !!suivi.animal_id && (
        <div className="rounded-2xl p-4 bg-white border border-gray-100 shadow-sm">
          {suivi.notifie_a ? (
            <div className="flex items-center gap-2">
              <span style={{ color: TEAL }}>✓</span>
              <p className="text-xs font-galey text-gray-500">
                Envoyé au client le {new Date(suivi.notifie_a as string).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
              </p>
            </div>
          ) : (
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-bold font-galey text-gray-800">Le client ne voit pas encore ce bilan</p>
                <p className="text-xs font-galey text-gray-400">Envoyez-le une fois le suivi complet et vérifié.</p>
              </div>
              <button disabled={sendingNotif} onClick={handleEnvoyerNotification}
                className="text-white px-4 py-2 rounded-full text-sm font-galey font-semibold disabled:opacity-50 flex-shrink-0" style={{ background: TEAL }}>
                {sendingNotif ? 'Envoi…' : 'Envoyer'}
              </button>
            </div>
          )}
        </div>
      )}

      {texte('observations_bilan') && <Section titre="Observations et bilan" texte={texte('observations_bilan')!} />}
      {texte('intervention') && <Section titre="Intervention réalisée" texte={texte('intervention')!} />}

      {exercices.length > 0 && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Conseils et exercices</h2>
          <div className="space-y-2">
            {exercices.map((e, i) => (
              <Card key={i}>
                <div className="flex gap-3">
                  <div className="flex-1 min-w-0 space-y-1">
                    <p className="text-sm font-bold font-galey text-gray-800">{e.nom}</p>
                    {e.description && <p className="text-sm text-gray-700 whitespace-pre-line">{e.description}</p>}
                    {e.consignes && <Line label="Consignes" value={e.consignes} />}
                    {e.frequence && <Line label="Fréquence" value={e.frequence} />}
                    {e.duree && <Line label="Durée" value={e.duree} />}
                    {e.precautions && <Line label="Précautions" value={e.precautions} />}
                  </div>
                  {e.photo_url && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={e.photo_url} alt="" className="w-20 h-20 rounded-xl object-cover flex-shrink-0" />
                  )}
                </div>
              </Card>
            ))}
          </div>
        </div>
      )}

      {(!!texte('suivi_recommande') || suivi.orientation_veto === true || !!suivi.prochain_controle) && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Suivi recommandé</h2>
          <Card>
            {texte('suivi_recommande') && <p className="text-sm text-gray-700 whitespace-pre-line">{texte('suivi_recommande')}</p>}
            {suivi.orientation_veto === true && <Line label="Orientation" value="consultation vétérinaire conseillée" />}
            {suivi.prochain_controle
              ? <Line label="Contrôle conseillé" value={new Date(suivi.prochain_controle as string).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })} />
              : null}
          </Card>
        </div>
      )}

      {VUES_PHOTOS.some(v => photoForVue(v.key)) && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Photos de référence</h2>
          <div className="flex flex-wrap gap-3">
            {VUES_PHOTOS.map(v => {
              const p = photoForVue(v.key);
              if (!p) return null;
              return (
                <div key={v.key} className="flex flex-col items-center gap-1">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={p.url} alt={v.label} className="w-24 h-24 rounded-xl object-cover border border-gray-200" />
                  <span className="text-[11px] font-galey text-gray-500">{v.label}</span>
                </div>
              );
            })}
          </div>
          {extra.length > 0 && (
            <div className="flex flex-wrap gap-2 mt-3">
              {extra.map((p, i) => (
                // eslint-disable-next-line @next/next/no-img-element
                <img key={i} src={p.url} alt="" className="w-16 h-16 rounded-lg object-cover" />
              ))}
            </div>
          )}
        </div>
      )}

      {videos.length > 0 && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Vidéos</h2>
          <div className="space-y-3">
            {videos.map((v, i) => (
              <Card key={i}>
                <p className="font-bold font-galey text-sm text-gray-800">{labelActivite(v.activite)}</p>
                {v.commentaire && <p className="text-xs text-gray-500 font-galey mb-2">{v.commentaire}</p>}
                <video src={v.url} controls className="w-full rounded-xl" />
              </Card>
            ))}
          </div>
        </div>
      )}

      {points.length > 0 && !sansAnatomie && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Bilan anatomique</h2>
          <Card>
            <div className="flex flex-wrap gap-2 justify-center mb-3">
              {vuesDisponibles(espece).map(v => (
                <button key={v.key} onClick={() => setVue(v.key)}
                  className="px-3 py-1.5 rounded-full text-xs font-galey font-semibold"
                  style={vue === v.key ? { background: TEAL, color: 'white' } : { background: '#F1F5F4', color: '#374151' }}>
                  {v.label}
                </button>
              ))}
            </div>
            <MorphoSilhouette espece={espece} vue={vue} points={points} onVueChange={setVue} />
          </Card>
          {points.filter(p => p.note?.trim()).map((p, i) => (
            <div key={i} className="mt-2 bg-white rounded-xl border border-gray-100 p-3 flex items-start gap-2">
              <span className="w-3 h-3 rounded-full mt-0.5 flex-shrink-0" style={{ background: colorPointEffectif(p.categorie, p.couleur) }} />
              <div>
                <p className="text-sm font-bold font-galey text-gray-800">{p.note}</p>
                <p className="text-xs text-gray-400 font-galey">{labelCategoriePoint(p.categorie)}</p>
              </div>
            </div>
          ))}
          {pointsForVue.length === 0 && <p className="text-xs text-gray-400 font-galey mt-2">Aucun point sur cette vue.</p>}
        </div>
      )}

      {observations.length > 0 && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Observation statique</h2>
          <Card>
            {observations.map((o, i) => (
              <div key={i} className="flex items-center justify-between gap-3 py-1.5">
                <span className="text-sm font-galey font-semibold text-gray-700">
                  {CATEGORIES_OBSERVATION_STATIQUE.find(c => c.key === o.categorie)?.label ?? o.categorie}
                </span>
                <span className="px-2.5 py-1 rounded-full text-xs font-galey font-bold"
                  style={{ background: `${colorValeurObservation(o.valeur)}20`, color: colorValeurObservation(o.valeur) }}>
                  {labelsValeurObservation(o.categorie)[o.valeur] ?? o.valeur}
                </span>
              </div>
            ))}
          </Card>
        </div>
      )}

      {mouvements.length > 0 && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Observation en mouvement</h2>
          <div className="space-y-2">
            {mouvements.map((m, i) => (
              <Card key={i}>
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-bold font-galey text-gray-800">{labelActivite(m.activite)}</p>
                    {m.observation && <p className="text-xs text-gray-500 font-galey">{m.observation}</p>}
                  </div>
                  {m.gene_observee && <span>⚠️</span>}
                </div>
              </Card>
            ))}
          </div>
        </div>
      )}
      {signer && user && (
        <SignatureProModal onClose={() => setSigner(false)} onValider={async dataUrl => {
          if (await enregistrerSignaturePro(user.uid, dataUrl)) setSigner(false);
          else alert('Signature non enregistrée.');
        }} />
      )}
    </div>
  );
}

function Card({ children }: { children: React.ReactNode }) {
  return <div className="bg-white rounded-2xl border border-gray-100 p-4">{children}</div>;
}
function Section({ titre, texte }: { titre: string; texte: string }) {
  return (
    <div>
      <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">{titre}</h2>
      <Card><p className="text-sm text-gray-700 whitespace-pre-line leading-relaxed">{texte}</p></Card>
    </div>
  );
}
function Line({ label, value }: { label: string; value: string }) {
  return <p className="text-sm font-galey text-gray-700"><span className="font-bold">{label} :</span> {value}</p>;
}
