'use client';

import { useEffect, useState, use as usePromise } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useSanteAccess } from '@/hooks/useSanteAccess';
import MorphoSilhouette, { MorphoLegende } from '@/components/morpho/MorphoSilhouette';
import {
  TEAL, labelTypeSuivi, labelActivite, labelCategoriePoint, colorCategoriePoint,
  CATEGORIES_OBSERVATION_STATIQUE, labelsValeurObservation, colorValeurObservation,
  SOURCE_LABELS, MORPHO_AVERTISSEMENT, VUES_PHOTOS, NIVEAUX_ACTIVITE,
  morphoSpeciesKey, vuesDisponibles, type MorphoPoint,
} from '@/lib/morpho';
import { morphoSuiviPdfBlob } from '@/lib/morpho-pdf';

interface SuiviRow { [k: string]: unknown }

export default function SuiviDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = usePromise(params);
  const { user, userData, isSante, loading: authLoading } = useSanteAccess();
  const router = useRouter();

  const [loading, setLoading] = useState(true);
  const [suivi, setSuivi] = useState<SuiviRow | null>(null);
  const [animal, setAnimal] = useState<{ nom?: string; espece?: string; race?: string }>({});
  const [pro, setPro] = useState<{ nom?: string; adresse?: string; tel?: string; email?: string }>({});
  const [photos, setPhotos] = useState<{ vue: string; url: string }[]>([]);
  const [videos, setVideos] = useState<{ activite: string; commentaire: string | null; url: string }[]>([]);
  const [points, setPoints] = useState<MorphoPoint[]>([]);
  const [observations, setObservations] = useState<{ categorie: string; valeur: string; commentaire: string | null }[]>([]);
  const [mouvements, setMouvements] = useState<{ activite: string; observation: string | null; gene_observee: boolean | null; commentaire: string | null }[]>([]);
  const [vue, setVue] = useState('profil_d');
  const [exporting, setExporting] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isSante) { router.push('/'); return; }
  }, [user, userData, isSante, authLoading, router]);

  useEffect(() => {
    (async () => {
      const { data: s } = await supabase.from('suivis_morpho').select('*').eq('id', id).maybeSingle();
      if (!s) { setLoading(false); return; }
      setSuivi(s);
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

      if (s.animal_id) {
        const { data: a } = await supabase.from('animaux').select('nom, espece, race').eq('id', s.animal_id).maybeSingle();
        setAnimal(a ?? { nom: (s.animal_nom_libre as string) ?? 'Animal', espece: (s.espece_libre as string) ?? undefined });
      } else {
        setAnimal({ nom: (s.animal_nom_libre as string) ?? 'Animal', espece: (s.espece_libre as string) ?? undefined });
      }
      const proProfileId = s.pro_profile_id as string | null;
      if (proProfileId) {
        const { data: p } = await supabase.from('user_profiles').select('nom, firstname, lastname, adress, phone_number, email_contact').eq('id', proProfileId).maybeSingle();
        const nom = (p?.nom as string)?.trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim();
        setPro({ nom, adresse: p?.adress as string, tel: p?.phone_number as string, email: p?.email_contact as string });
      }
      setLoading(false);
    })();
  }, [id]);

  async function handleExport() {
    if (!suivi) return;
    setExporting(true);
    try {
      const blob = await morphoSuiviPdfBlob({ suivi, animal, pro, photos, points, observations, mouvements });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const nomAnimal = (animal.nom || 'animal').replace(/\s+/g, '_');
      const dateStr = String(suivi.date ?? '').slice(0, 10);
      a.href = url;
      a.download = `suivi_morpho_${nomAnimal}_${dateStr}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      alert(`Erreur export : ${e instanceof Error ? e.message : e}`);
    } finally {
      setExporting(false);
    }
  }

  if (!user || !userData) return null;
  if (loading) return <div className="flex justify-center py-24"><div className="animate-spin rounded-full h-10 w-10 border-b-2" style={{ borderColor: TEAL }} /></div>;
  if (!suivi) return <div className="text-center py-24 text-gray-400 font-galey">Suivi introuvable.</div>;

  const espece = morphoSpeciesKey((suivi.espece_libre as string) ?? animal.espece ?? '') ?? 'chien';
  const photoForVue = (v: string) => photos.find(p => p.vue === v);
  const extra = photos.filter(p => p.vue === 'autre');
  const pointsForVue = points.filter(p => p.vue === vue);
  const source = (suivi.source as string) ?? 'proprietaire';

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-bold font-galey" style={{ color: TEAL }}>{labelTypeSuivi(suivi.type_suivi as string)}</h1>
        <button disabled={exporting} onClick={handleExport}
          className="text-white px-4 py-2 rounded-full text-sm font-galey font-semibold disabled:opacity-50" style={{ background: TEAL }}>
          {exporting ? 'Export…' : '⬆ Exporter PDF'}
        </button>
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
        {suivi.motif ? <Line label="Motif" value={suivi.motif as string} /> : null}
        {suivi.poids ? <Line label="Poids" value={`${suivi.poids} kg`} /> : null}
        {suivi.taille ? <Line label="Taille" value={`${suivi.taille} cm`} /> : null}
        {suivi.niveau_activite && suivi.niveau_activite !== 'non_evalue' ? (
          <Line label="Niveau d'activité" value={NIVEAUX_ACTIVITE.find(n => n.key === suivi.niveau_activite)?.label ?? ''} />
        ) : null}
        {suivi.checkpoint_age ? <Line label="Étape" value={suivi.checkpoint_age as string} /> : null}
        {suivi.commentaires ? <p className="text-sm font-galey text-gray-700 mt-2 whitespace-pre-line">{suivi.commentaires as string}</p> : null}
        <span className="inline-block mt-2 px-2.5 py-1 rounded-full text-xs font-galey font-bold" style={{ background: `${TEAL}18`, color: TEAL }}>
          {SOURCE_LABELS[source] ?? source}
        </span>
      </Card>

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

      {points.length > 0 && (
        <div>
          <h2 className="text-sm font-bold font-galey text-gray-800 mb-2">Silhouette</h2>
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
            <div className="mt-3"><MorphoLegende /></div>
          </Card>
          {points.filter(p => p.note?.trim()).map((p, i) => (
            <div key={i} className="mt-2 bg-white rounded-xl border border-gray-100 p-3 flex items-start gap-2">
              <span className="w-2.5 h-2.5 rounded-full mt-1" style={{ background: colorCategoriePoint(p.categorie) }} />
              <div>
                <p className="text-sm font-bold font-galey text-gray-800">{labelCategoriePoint(p.categorie)}</p>
                <p className="text-xs text-gray-500 font-galey">{p.note}</p>
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
    </div>
  );
}

function Card({ children }: { children: React.ReactNode }) {
  return <div className="bg-white rounded-2xl border border-gray-100 p-4">{children}</div>;
}
function Line({ label, value }: { label: string; value: string }) {
  return <p className="text-sm font-galey text-gray-700"><span className="font-bold">{label} :</span> {value}</p>;
}
