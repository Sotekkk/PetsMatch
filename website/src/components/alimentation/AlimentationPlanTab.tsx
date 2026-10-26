'use client';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { auth } from '@/lib/firebase';
import {
  type AlimentPlan, type CalculRation, type PlanAlimentation, ACTIVITES, LIBELLES_ACTIVITE, LIBELLES_TYPE_ALIMENT,
  type EtatRepro, ajouterAliment, ageMois, basculer, detecterReproduction, erreursHoraires, kcalDe, libelleEstimation, calculerRation, changerNbRepas, colonnesHistoriques, ecartImportant, erreurEtape,
  estPersonnalise, formatQuantite, libellesRepas, lireNombre, nomAliment, planDepuisLigne, planNeuf, planVersJson,
  profilEspece, retirerAliment, revenirRecommandation, typeDepuisCatalogue,
} from '@/lib/plan-alimentation';
import PlanAlimentationLecture, { PlanAlimentationDepuisLigne } from './PlanAlimentationLecture';
import AjoutAlimentModal from './AjoutAlimentModal';

const ETAPES = ['Type', 'Besoins', 'Aliments', 'Repas', 'Ration', 'Résumé'];
const COLS = 'id, marque, gamme, type_aliment, age_categorie, densite_kcal_100g, kcal_estime, ajoute_par_uid, doses';

type Ligne = Record<string, unknown>;

const chip = (on: boolean) =>
  `h-11 px-4 rounded-full border text-[15px] font-bold transition-colors ${on ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'bg-white border-gray-300 text-[#1F2A2E] hover:border-[#0C5C6C]'}`;
const carteCase = (on: boolean) =>
  `w-full flex items-center gap-3 text-left min-h-[48px] px-3 py-2 rounded-[10px] border transition-colors ${on ? 'bg-[#E8F0F2] border-[#0C5C6C] border-2' : 'bg-white border-gray-200 hover:border-[#0C5C6C]/40'}`;
const encadre = 'p-3 rounded-xl text-[14.5px]';
const fr = (v: number) => String(Math.round(v * 100) / 100).replace('.', ',');

function Case({ on }: { on: boolean }) {
  return (
    <span aria-hidden="true" className={`w-[22px] h-[22px] flex-shrink-0 rounded-md border-2 border-[#0C5C6C] flex items-center justify-center ${on ? 'bg-[#0C5C6C]' : 'bg-white'}`}>
      {on && <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12l5 5 9-10" /></svg>}
    </span>
  );
}

/** Onglet Alimentation d'une fiche animal (particulier, éleveur,
 *  association), toutes espèces. Synthèse une fois configuré, parcours en 6
 *  étapes pour le premier paramétrage ou une modification (chaque étape est
 *  accessible directement). Miroir de alimentation_plan_tab.dart (appli). */
export default function AlimentationPlanTab({ animalId, espece, race = '', sexe = '', sterilise = false, dateNaissance, nom = '', poidsFiche, lectureSeule = false }: {
  animalId: string; espece: string; race?: string; sexe?: string; sterilise?: boolean;
  dateNaissance?: string | null; nom?: string; poidsFiche?: number | string | null; lectureSeule?: boolean;
}) {
  const profil = useMemo(() => profilEspece(espece), [espece]);
  const kg = profil.uniteKg;
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [row, setRow] = useState<Ligne | null>(null);
  const [plan, setPlan] = useState<PlanAlimentation>(() => planNeuf(espece));
  const [parcours, setParcours] = useState(false);
  const [etape, setEtape] = useState(1);
  const [erreur, setErreur] = useState<string | null>(null);
  const [ecartOk, setEcartOk] = useState(false);
  const [qte, setQte] = useState<Record<string, string>>({});
  const [partsTxt, setPartsTxt] = useState<Record<number, string>>({});
  const [invalides, setInvalides] = useState<Record<string, string>>({});
  const [objectif, setObjectif] = useState('');
  const [poidsAdulte, setPoidsAdulte] = useState('');
  const [nbPetitsTxt, setNbPetitsTxt] = useState('');
  const [consignes, setConsignes] = useState('');
  const [recherche, setRecherche] = useState('');
  const [catalogue, setCatalogue] = useState<Ligne[] | null>(null);
  const [poids, setPoids] = useState<number | null>(null);
  const [repro, setRepro] = useState<EtatRepro>({ etat: 'normal' });
  const [ajout, setAjout] = useState(false);
  /** Aliment saisi par le membre en cours de modification. */
  const [modif, setModif] = useState<{ ligne?: Ligne; index?: number } | null>(null);
  const [confirmReco, setConfirmReco] = useState<null | 'synthese' | 'parcours'>(null);
  const [apercuPro, setApercuPro] = useState(false);

  const animal = useMemo(() => ({
    espece, nom, sexe, sterilise, dateNaissance, poidsKg: poids, etatRepro: repro.etat, semaineLactation: repro.semaine ?? null,
  }), [espece, nom, sexe, sterilise, dateNaissance, poids, repro]);
  const calc: CalculRation = useMemo(() => calculerRation(plan, animal, lireNombre(objectif).v ?? null), [plan, animal, objectif]);
  const cle = (i: number, a: number) => `${i}-${a}`;

  /** Textes des quantités alignés sur le plan (kg pour les grands animaux). */
  const textesQuantites = useCallback((p: PlanAlimentation) => {
    const t: Record<string, string> = {};
    p.repas.forEach((r, i) => r.items.forEach(it => { t[cle(i, it.a)] = it.g != null ? fr(kg ? it.g / 1000 : it.g) : ''; }));
    return t;
  }, [kg]);

  // ── Chargement ─────────────────────────────────────────────────────────

  useEffect(() => {
    if (!animalId) { setLoading(false); return; }
    let annule = false;
    (async () => {
      const { data: r } = await supabase.from('alimentations').select('*').eq('animal_id', animalId).maybeSingle();
      let p = planDepuisLigne(r as Ligne | null, espece);
      if (p) {
        const ids = p.aliments.map(a => a.id).filter((x): x is string => !!x);
        if (ids.length) {
          let det = await supabase.from('marques_aliments').select('id, doses, tableau_croissance').in('id', ids);
          if (det.error) det = await supabase.from('marques_aliments').select('id, doses').in('id', ids) as typeof det;
          const parId = new Map((det.data ?? []).map((d: Ligne) => [String(d.id), d]));
          p = { ...p, aliments: p.aliments.map(a => {
            const d = a.id ? parId.get(a.id) : undefined;
            return d ? { ...a, doses: (d.doses as unknown[]) ?? [], tableauCroissance: (d.tableau_croissance as unknown[]) ?? [] } : a;
          }) };
        }
      }
      const { data: pz } = await supabase.from('poids').select('valeur').eq('animal_id', animalId).order('date', { ascending: false }).limit(1);
      const dernier = pz && pz.length ? parseFloat(String(pz[0].valeur).replace(',', '.')) : NaN;
      const fiche = poidsFiche != null ? parseFloat(String(poidsFiche).replace(',', '.')) : NaN;
      // Gestation / lactation : dernière gestation de l'onglet Repro + portées
      // dont la femelle est la mère (fiches des petits reliées par la puce,
      // sinon le nom de la mère).
      let rep: EtatRepro = { etat: 'normal' };
      if (sexe === 'femelle' && !sterilise) {
        const { data: g } = await supabase.from('gestations').select('date, date_naissance, nb_nes')
          .eq('animal_id', animalId).order('date', { ascending: false }).limit(1).maybeSingle();
        const { data: mere } = await supabase.from('animaux').select('identification, nom, nom_pedigree, uid_eleveur').eq('id', animalId).maybeSingle();
        const cols = 'portee_id, date_naissance, statut';
        let portees: Ligne[] = [];
        const puce = String(mere?.identification ?? '').replace(/\s/g, '');
        if (puce) portees = ((await supabase.from('animaux').select(cols).eq('puce_mere', puce).not('portee_id', 'is', null)).data ?? []) as Ligne[];
        for (const n of [mere?.nom_pedigree, mere?.nom]) {
          const nomMere = String(n ?? '').trim();
          if (portees.length || !nomMere || !mere?.uid_eleveur) continue;
          portees = ((await supabase.from('animaux').select(cols).ilike('nom_mere', nomMere)
            .eq('uid_eleveur', String(mere.uid_eleveur)).not('portee_id', 'is', null)).data ?? []) as Ligne[];
        }
        rep = detecterReproduction({ espece, gestation: g as Ligne | null, portees });
      }
      if (annule) return;
      setRow((r as Ligne) ?? null);
      if (p) {
        // Saisie de l'éleveur conservée pour la même portée ; une nouvelle
        // portée reprend le nombre détecté.
        if (rep.etat === 'lactation' && (p.nbPetits == null || p.nbPetitsMiseBas !== rep.miseBas)) {
          p = { ...p, nbPetits: rep.nbPetits ?? null, nbPetitsMiseBas: rep.miseBas ?? null };
        }
        setPlan(p);
        setQte(textesQuantites(p));
        setConsignes(String((r as Ligne | null)?.consignes ?? ''));
        const obj = (r as Ligne | null)?.poids_objectif;
        setObjectif(typeof obj === 'number' ? fr(obj) : '');
        setPoidsAdulte(p.poidsAdulte != null ? fr(p.poidsAdulte) : '');
        setNbPetitsTxt(p.nbPetits != null ? String(p.nbPetits) : '');
      } else {
        setParcours(!lectureSeule);
        if (rep.etat === 'lactation' && rep.nbPetits) {
          setPlan(pl => ({ ...pl, nbPetits: rep.nbPetits, nbPetitsMiseBas: rep.miseBas ?? null }));
          setNbPetitsTxt(String(rep.nbPetits));
        }
      }
      setPoids(!isNaN(dernier) && dernier > 0 ? dernier : !isNaN(fiche) && fiche > 0 ? fiche : null);
      setRepro(rep);
      setLoading(false);
    })();
    return () => { annule = true; };
  }, [animalId, espece, sexe, sterilise, poidsFiche, lectureSeule, textesQuantites]);

  /** force : relit le catalogue (après l'ajout ou la modification d'un aliment). */
  async function chargerCatalogue(force = false) {
    if (catalogue && !force) return;
    let r = await supabase.from('marques_aliments').select(`${COLS}, tableau_croissance, repris_admin_le`).eq('espece', espece).order('marque').limit(1000);
    if (r.error) r = await supabase.from('marques_aliments').select(COLS).eq('espece', espece).order('marque').limit(1000) as typeof r;
    setCatalogue((r.data ?? []) as Ligne[]);
  }

  const depuisCatalogue = (r: Ligne): AlimentPlan => {
    const k = typeof r.densite_kcal_100g === 'number' ? r.densite_kcal_100g : parseFloat(String(r.densite_kcal_100g ?? ''));
    const ok = isFinite(k) && k > 0;
    return {
      id: String(r.id), marque: String(r.marque ?? ''), gamme: String(r.gamme ?? ''),
      type: typeDepuisCatalogue(r.type_aliment as string, espece),
      kcal: ok ? k : null, source: ok ? (r.kcal_estime ? 'composition' : 'fabricant') : null,
      doses: (r.doses as unknown[]) ?? [], tableauCroissance: (r.tableau_croissance as unknown[]) ?? [],
    };
  };

  /** Aliment du catalogue ajouté par ce membre et pas encore repris par l'équipe. */
  const modifiable = (r?: Ligne | null) =>
    !!r && !!auth.currentUser && r.ajoute_par_uid === auth.currentUser.uid && !r.repris_admin_le;
  const ligneCatalogue = (id?: string | null) => (id ? (catalogue ?? []).find(r => String(r.id) === id) : undefined);

  /** Modifier un aliment saisi : du catalogue (id) ou préparation maison du plan (index). */
  async function modifierAliment(id: string | null, index?: number) {
    if (!id) { setModif({ index }); return; }
    const { data } = await supabase.from('marques_aliments').select('*').eq('id', id).maybeSingle();
    if (!data || !modifiable(data as Ligne)) {
      setErreur('Cet aliment a été repris par l’équipe PetsMatch : il n’est plus modifiable.');
      return;
    }
    setModif({ ligne: data as Ligne, index });
  }

  // ── Actions ────────────────────────────────────────────────────────────

  const majPlan = (p: PlanAlimentation) => { setPlan(p); setErreur(null); setEcartOk(false); };

  const erreurDe = (e: number) => erreurEtape(e, plan, calc, {
    objectifTexte: objectif, poidsAdulteTexte: poidsAdulte, ecartConfirme: ecartOk, saisiesInvalides: invalides,
  });

  function allerEtape(n: number) {
    setQte(q => ({ ...textesQuantites(plan), ...Object.fromEntries(Object.entries(q).filter(([k]) => invalides[k])) }));
    setEtape(n); setErreur(null);
    if (n === 3) chargerCatalogue();
  }

  function suivant() {
    const e = erreurDe(etape);
    if (e) { setErreur(e); return; }
    if (etape < 6) allerEtape(etape + 1);
    else enregistrer();
  }

  /** Part de l'énergie d'un aliment : la première saisie fige les parts
   *  actuelles de tous les aliments, puis seule celle-ci change. */
  function saisirPart(a: number, texte: string) {
    setPartsTxt(t => ({ ...t, [a]: texte }));
    setEcartOk(false); setErreur(null);
    const l = lireNombre(texte, true);
    const err = l.err ?? ((l.v ?? 0) > 100 ? 'Une part est comprise entre 0 et 100 %.' : null);
    setInvalides(inv => { const n = { ...inv }; if (err) n[`part-${a}`] = err; else delete n[`part-${a}`]; return n; });
    if (err) return;
    const n = plan.aliments.length;
    const parts = plan.parts && plan.parts.length === n ? [...plan.parts]
      : plan.aliments.map((_, i) => Math.round(calc.partEnergie[i] ?? 100 / n));
    parts[a] = l.v ?? 0;
    setPlan(p => ({ ...p, parts }));
    setPartsTxt(t => Object.fromEntries(parts.map((v, i) => [i, i === a ? texte : (invalides[`part-${i}`] ? t[i] ?? '' : fr(v))])));
  }

  function saisirQuantite(i: number, a: number, texte: string) {
    const k = cle(i, a);
    setQte(q => ({ ...q, [k]: texte }));
    setEcartOk(false); setErreur(null);
    const l = lireNombre(texte);
    const g = l.v == null ? null : kg ? l.v * 1000 : l.v;
    const err = l.err ?? (g != null && g > 20000 ? 'Quantité trop élevée pour un repas (20 kg au plus).' : null);
    setInvalides(inv => { const n = { ...inv }; if (err) n[k] = err; else delete n[k]; return n; });
    if (err) return;
    setPlan(p => ({ ...p, repas: p.repas.map((r, ri) => (ri !== i ? r : { ...r, items: r.items.map(it => (it.a === a ? { ...it, g } : it)) })) }));
  }

  async function enregistrer(planAEnregistrer: PlanAlimentation = plan) {
    if (!animalId) return;
    const c = calculerRation(planAEnregistrer, animal, lireNombre(objectif).v ?? null);
    for (let e = 1; e <= 5; e++) {
      const err = erreurEtape(e, planAEnregistrer, c, { objectifTexte: objectif, poidsAdulteTexte: poidsAdulte, ecartConfirme: ecartOk, saisiesInvalides: invalides });
      if (err) { setParcours(true); setEtape(e); setErreur(err); if (e === 3) chargerCatalogue(); return; }
    }
    setSaving(true);
    try {
      const payload = {
        plan: planVersJson(planAEnregistrer, c),
        consignes: consignes.trim() || null,
        poids_objectif: lireNombre(objectif).v ?? null,
        ...colonnesHistoriques(planAEnregistrer, c),
        updated_at: new Date().toISOString(),
      };
      const res = row?.id
        ? await supabase.from('alimentations').update(payload).eq('id', String(row.id)).select().single()
        : await supabase.from('alimentations').insert({ ...payload, id: crypto.randomUUID(), animal_id: animalId, uid_eleveur: auth.currentUser?.uid ?? null }).select().single();
      if (res.error || !res.data) {
        setErreur(res.error?.code === '23514' ? res.error.message
          : res.error?.code === 'PGRST204' ? 'Enregistrement impossible : la base de données doit être mise à jour (migration alimentation).'
          : 'Enregistrement impossible, réessayez.');
        setParcours(true);
        return;
      }
      setRow(res.data as Ligne);
      setPlan({ ...planAEnregistrer, repris: false });
      setParcours(false); setErreur(null);
    } finally { setSaving(false); }
  }

  function retourReco(depuis: 'synthese' | 'parcours') {
    const p = revenirRecommandation(plan);
    setPlan(p); setQte(textesQuantites(p)); setInvalides({}); setEcartOk(false); setConfirmReco(null);
    if (depuis === 'synthese') enregistrer(p);
  }

  const indexDe = (cand: AlimentPlan) => plan.aliments.findIndex(a => (cand.id
    ? a.id === cand.id
    : !a.id && a.marque === cand.marque && a.gamme === cand.gamme && a.type === cand.type));

  function basculerAliment(cand: AlimentPlan) {
    const i = indexDe(cand);
    const p = i >= 0 ? retirerAliment(plan, i) : ajouterAliment(plan, cand, profil);
    majPlan(p);
    setQte(textesQuantites(p));
  }

  // ── Rendu ──────────────────────────────────────────────────────────────

  if (loading) {
    return <div className="flex justify-center py-16"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }
  if (lectureSeule) {
    return <div className="max-w-5xl"><PlanAlimentationDepuisLigne row={row} espece={espece} nomAnimal={nom} large /></div>;
  }

  const perso = profil.methode === 'aucune' || estPersonnalise(plan) || !calc.recoDisponible;
  const badge = profil.methode === 'aucune' ? 'Quantités saisies' : perso ? 'Ration personnalisée' : 'Ration recommandée PetsMatch';
  const badgeCls = perso ? 'bg-[#FFF4E0] text-[#6B4100]' : 'bg-[#EAF3E5] text-[#2F5A1F]';
  const boutonPrincipal = 'h-12 px-6 rounded-[10px] bg-[#0C5C6C] text-white text-[15px] font-extrabold hover:bg-[#0a4f5d] disabled:opacity-50';
  const boutonSecondaire = 'h-12 px-5 rounded-[10px] border border-[#0C5C6C] bg-white text-[#0C5C6C] text-[15px] font-extrabold hover:bg-[#E8F0F2]';
  const peutRevenir = calc.recoDisponible && estPersonnalise(plan);

  const besoinBloc = () => {
    const b = calc.besoin;
    if (b.manque) return <div className={`${encadre} bg-[#FFF4E0] border border-[#E9C27A]`}>{b.manque}</div>;
    const valeur = b.kcal != null ? `${Math.round(b.kcal)} kcal/jour` : b.totalG != null ? `${formatQuantite(b.totalG, true)}/jour` : null;
    return (
      <div className={`${encadre} bg-[#E8F0F2] border border-[#B9CDD3]`}>
        {valeur && <p>Besoin estimé : <b>{valeur}</b></p>}
        <p className="text-[13.5px] text-gray-700">{b.detail}</p>
      </div>
    );
  };

  const confirmation = confirmReco && (
    <div className={`${encadre} bg-[#FFF4E0] border border-[#E9C27A] flex flex-wrap items-center justify-between gap-3`}>
      <span>Les quantités que vous avez modifiées seront remplacées par la ration recommandée par PetsMatch. Les aliments, les repas et les horaires sont conservés.</span>
      <span className="flex gap-2">
        <button type="button" onClick={() => setConfirmReco(null)} className="h-10 px-4 rounded-[10px] border border-gray-300 bg-white font-bold">Annuler</button>
        <button type="button" onClick={() => retourReco(confirmReco)} className="h-10 px-4 rounded-[10px] bg-[#0C5C6C] text-white font-extrabold">Remplacer</button>
      </span>
    </div>
  );

  // ── Synthèse ───────────────────────────────────────────────────────────
  if (!parcours) {
    return (
      <div className="max-w-5xl space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <h2 className="text-[22px] font-extrabold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Alimentation{nom ? ` de ${nom}` : ''}</h2>
            <span className={`px-3 py-1 rounded-full text-[13px] font-extrabold ${badgeCls}`}>{badge}</span>
          </div>
          <div className="flex flex-wrap gap-2">
            {peutRevenir && <button type="button" onClick={() => setConfirmReco('synthese')} className={boutonSecondaire}>Revenir à la ration recommandée</button>}
            <button type="button" onClick={() => { setParcours(true); setEtape(1); setErreur(null); setConfirmReco(null); }} className={boutonPrincipal}>Modifier l&apos;alimentation</button>
          </div>
        </div>
        {confirmation}
        {plan.repris && <div className={`${encadre} bg-[#E8F0F2] border border-[#B9CDD3]`}>Plan repris de l&apos;ancienne version de l&apos;onglet. Vérifiez-le, puis enregistrez-le.</div>}
        {calc.besoin.manque && <div className={`${encadre} bg-[#FFF4E0] border border-[#E9C27A]`}>{calc.besoin.manque}</div>}
        {calc.avertissements.map(a => <div key={a} className={`${encadre} bg-[#FFF4E0] border border-[#E9C27A]`}>{a}</div>)}
        <PlanAlimentationLecture plan={plan} calcul={calc} espece={espece} consignes={consignes} large />
        {row && (
          <button type="button" onClick={() => setApercuPro(true)} className="h-10 text-[14.5px] font-bold text-[#0C5C6C] underline">
            Voir comme un professionnel (pension, pet-sitter)
          </button>
        )}
        {apercuPro && (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40" onClick={() => setApercuPro(false)}>
            <div className="bg-[#F4F7F8] w-full max-w-3xl rounded-t-2xl sm:rounded-2xl max-h-[90vh] overflow-y-auto p-5" onClick={e => e.stopPropagation()}>
              <div className="flex justify-between items-center mb-3">
                <h2 className="text-[18px] font-extrabold">Vue professionnel</h2>
                <button type="button" onClick={() => setApercuPro(false)} className="h-10 px-4 rounded-[10px] border border-gray-300 bg-white font-bold">Fermer</button>
              </div>
              <PlanAlimentationDepuisLigne row={row} espece={espece} nomAnimal={nom} />
            </div>
          </div>
        )}
      </div>
    );
  }

  // ── Parcours ───────────────────────────────────────────────────────────
  const labels = libellesRepas(plan.repas.length);
  const horaires = erreursHoraires(plan);
  const age = ageMois(animal);
  const croissancePossible = profil.methode === 'energie' && age != null && age < (espece === 'chien' ? 18 : 12);
  const q = recherche.trim().toLowerCase();
  const resultats = (catalogue ?? []).filter(r => {
    const t = typeDepuisCatalogue(r.type_aliment as string, espece);
    if (plan.categories.length && !plan.categories.includes(t)) return false;
    return !q || `${r.marque} ${r.gamme} ${LIBELLES_TYPE_ALIMENT[t]}`.toLowerCase().includes(q);
  }).slice(0, 60);
  const sansMarque = (plan.categories.length ? plan.categories : profil.types).filter(t => ['foin', 'paturage', 'legumes'].includes(t));
  const sousTitreAliment = (a: AlimentPlan) => {
    const t = LIBELLES_TYPE_ALIMENT[a.type] ?? a.type;
    if (profil.methode !== 'energie') return t;
    const est = kcalDe(a);
    if (a.kcal == null && est != null) return `${t} · ≈ ${Math.round(est)} kcal/100 g (${libelleEstimation(a)})`;
    return a.kcal == null ? `${t} · valeur énergétique non renseignée` : `${t} · ${Math.round(a.kcal)} kcal/100 g${a.source === 'composition' ? ' (estimation)' : ''}`;
  };
  const fabricant = plan.aliments.map((a, i) => (calc.fabricant[i] != null ? `${nomAliment(a)} : ${formatQuantite(calc.fabricant[i]!, kg)}/jour` : null)).filter(Boolean);
  let ecartMsg: string | null = null;
  if (calc.ecartPct != null && (estPersonnalise(plan) || Math.abs(calc.ecartPct) > 1)) {
    const p = Math.round(calc.ecartPct);
    ecartMsg = ecartImportant(calc)
      ? `Écart de ${p > 0 ? '+' : ''}${p} % avec l’estimation PetsMatch. Cette ration est très différente de l’estimation PetsMatch : vérifiez les quantités avant de confirmer.`
      : `Écart de ${p > 0 ? '+' : ''}${p} % avec l’estimation PetsMatch : la ration correspond aux besoins.`;
  }
  const sousTitre = 'text-[15px] font-bold mt-4 mb-2';

  return (
    <div className="max-w-6xl space-y-4 text-[#1F2A2E]">
      <div className="flex flex-wrap gap-2">
        {ETAPES.map((l, i) => (
          <button key={l} type="button" onClick={() => allerEtape(i + 1)}
            className={`h-11 px-4 rounded-full border text-[14.5px] font-extrabold ${i + 1 === etape ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : i + 1 < etape ? 'bg-[#E8F0F2] border-[#0C5C6C] text-[#1F2A2E]' : 'bg-white border-gray-300'}`}>
            {i + 1}. {l}
          </button>
        ))}
      </div>
      <div className="flex flex-wrap gap-5 items-start">
        <div className="flex-[999_1_560px] min-w-0 bg-white border border-gray-200 rounded-2xl p-5 sm:p-6 space-y-3">

          {etape === 1 && (
            <div>
              <h2 className="text-[21px] font-extrabold mb-3">1. Type d&apos;alimentation</h2>
              <div className="grid gap-3 sm:grid-cols-2">
                {([['unique', 'Alimentation unique', 'Un seul aliment'], ['mixte', 'Alimentation mixte', 'Deux aliments ou plus']] as const).map(([m, t, s]) => (
                  <button key={m} type="button" onClick={() => {
                    let p: PlanAlimentation = { ...plan, mode: m };
                    if (m === 'unique') {
                      p = { ...p, categories: p.categories.slice(0, 1) };
                      while (p.aliments.length > 1) p = retirerAliment(p, p.aliments.length - 1);
                    }
                    majPlan(p);
                  }} className={`text-left min-h-[68px] p-3 rounded-xl border-2 ${plan.mode === m ? 'border-[#0C5C6C] bg-[#E8F0F2]' : 'border-gray-200 bg-white hover:border-[#0C5C6C]/40'}`}>
                    <b className="block text-[16px]">{t}</b><span className="text-[13.5px] text-gray-600">{s}</span>
                  </button>
                ))}
              </div>
              <p className="text-[15px] text-gray-600 mt-4 mb-2">
                {plan.mode === 'unique' ? 'Quel type d’aliment ?' : 'Quels types d’aliments ? Plusieurs choix possibles, ou deux fois le même type (deux marques de croquettes par exemple).'}
              </p>
              <div className="flex flex-wrap gap-2">
                {profil.types.map(t => (
                  <button key={t} type="button" className={chip(plan.categories.includes(t))} onClick={() => {
                    const categories = plan.mode === 'unique' ? [t] : plan.categories.includes(t) ? plan.categories.filter(x => x !== t) : [...plan.categories, t];
                    let p: PlanAlimentation = { ...plan, categories };
                    // Aliments d'un type non retenu (ex. croquettes alors que
                    // seul le BARF est choisi) : retirés du plan.
                    for (let i = p.aliments.length - 1; i >= 0; i--) {
                      if (categories.length && !categories.includes(p.aliments[i].type)) p = retirerAliment(p, i);
                    }
                    majPlan(p);
                  }}>{LIBELLES_TYPE_ALIMENT[t]}</button>
                ))}
              </div>
              {profil.methode === 'energie' && (
                <p className="text-[14px] text-gray-600 mt-3">BARF et ration ménagère peuvent être des produits du commerce prêts à servir (Easy BARF, Dogfy Diet…) ou des préparations maison.</p>
              )}
            </div>
          )}

          {etape === 2 && (
            <div>
              <h2 className="text-[21px] font-extrabold mb-3">2. Besoins{nom ? ` de ${nom}` : ''}</h2>
              <div className="p-3 rounded-xl bg-[#F4F7F8] text-[15px]">
                <p className="text-[12.5px] font-extrabold text-gray-600">REPRIS DE LA FICHE IDENTITÉ</p>
                <p>
                  {[espece ? espece[0].toUpperCase() + espece.slice(1) : '', race.trim(), sexe,
                    age == null ? 'date de naissance non renseignée' : age < 24 ? `${Math.floor(age)} mois` : `${Math.floor(age / 12)} ans`].filter(Boolean).join(' · ')}
                </p>
                <p>Poids : {poids != null ? `${fr(poids)} kg` : 'non renseigné'} · Stérilisé(e) : {sterilise ? 'oui' : 'non'}</p>
                {repro.etat !== 'normal' && (
                  <p>{repro.etat === 'lactation' ? `Lactation en cours (semaine ${repro.semaine ?? 1} après la mise bas)` : repro.etat === 'gestation_fin' ? 'Gestation en cours (dernières semaines)' : 'Gestation en cours'}</p>
                )}
              </div>
              <div className="grid gap-x-6 sm:grid-cols-2">
                <div>
                  <p className={sousTitre}>Niveau d&apos;activité</p>
                  <div className="flex flex-wrap gap-2">
                    {ACTIVITES.map(a => <button key={a} type="button" className={chip(plan.activite === a)} onClick={() => majPlan({ ...plan, activite: a })}>{LIBELLES_ACTIVITE[a]}</button>)}
                  </div>
                </div>
                <div>
                  <p className={sousTitre}>Nombre de repas par jour</p>
                  <div className="flex flex-wrap gap-2">
                    {[1, 2, 3, 4].map(n => (
                      <button key={n} type="button" className={`${chip(plan.repas.length === n)} w-14`}
                        onClick={() => { const p = changerNbRepas(plan, n, profil); majPlan(p); setQte(textesQuantites(p)); }}>{n}</button>
                    ))}
                  </div>
                </div>
                <div>
                  <p className={sousTitre}>Horaires (facultatif)</p>
                  {plan.repas.map((r, i) => (
                    <div key={i} className="mb-2">
                      <label className="flex items-center justify-between gap-3 text-[15px]">
                        <span>{labels[i]}</span>
                        <input type="time" value={r.heure ?? ''} onChange={e => majPlan({ ...plan, repas: plan.repas.map((x, j) => (j === i ? { ...x, heure: e.target.value || null } : x)) })}
                          className={`h-11 w-36 px-2 rounded-[10px] border ${horaires[i] ? 'border-red-600' : 'border-gray-300'}`} />
                      </label>
                      {horaires[i] && <p className="text-[13.5px] text-red-700 mt-1">{horaires[i]}</p>}
                    </div>
                  ))}
                </div>
                <div>
                  {profil.methode !== 'aucune' && (
                    <>
                      <label className={`${sousTitre} block`} htmlFor="alim-objectif">Objectif de poids (facultatif)</label>
                      <div className="flex h-12 rounded-[10px] border border-gray-300 overflow-hidden">
                        <input id="alim-objectif" inputMode="decimal" value={objectif} onChange={e => { setObjectif(e.target.value); setErreur(null); }}
                          placeholder="Ex. 17,5" className="flex-1 min-w-0 px-3 outline-none text-[15px]" />
                        <span className="px-3 flex items-center bg-gray-100 border-l border-gray-300 font-bold">kg</span>
                      </div>
                      {lireNombre(objectif).err && <p className="text-[13.5px] text-red-700 mt-1">{lireNombre(objectif).err}</p>}
                    </>
                  )}
                  {repro.etat === 'lactation' && profil.methode === 'energie' && (
                    <>
                      <label className={`${sousTitre} block`} htmlFor="alim-petits">Nombre de petits allaités</label>
                      <input id="alim-petits" inputMode="numeric" value={nbPetitsTxt} placeholder="Ex. 6"
                        onChange={e => {
                          setNbPetitsTxt(e.target.value);
                          const l = lireNombre(e.target.value);
                          majPlan({ ...plan, nbPetits: l.v != null && Number.isInteger(l.v) ? l.v : null, nbPetitsMiseBas: repro.miseBas ?? null });
                        }}
                        className="w-full h-12 px-3 rounded-[10px] border border-gray-300 outline-none text-[15px]" />
                      <p className="text-[13px] text-gray-600 mt-1">
                        {repro.source ? `${repro.source} : corrigez si certains petits ne tètent plus.` : 'Les besoins de lactation dépendent du nombre de petits.'}
                      </p>
                      {(lireNombre(nbPetitsTxt).err || (nbPetitsTxt.trim() && plan.nbPetits == null)) && (
                        <p className="text-[13.5px] text-red-700">{lireNombre(nbPetitsTxt).err ?? 'Nombre entier attendu (ex. 6).'}</p>
                      )}
                    </>
                  )}
                  {croissancePossible && (
                    <>
                      <label className={`${sousTitre} block`} htmlFor="alim-adulte">Poids adulte estimé</label>
                      <div className="flex h-12 rounded-[10px] border border-gray-300 overflow-hidden">
                        <input id="alim-adulte" inputMode="decimal" value={poidsAdulte} placeholder="Ex. 25"
                          onChange={e => { setPoidsAdulte(e.target.value); majPlan({ ...plan, poidsAdulte: lireNombre(e.target.value).v ?? null }); }}
                          className="flex-1 min-w-0 px-3 outline-none text-[15px]" />
                        <span className="px-3 flex items-center bg-gray-100 border-l border-gray-300 font-bold">kg</span>
                      </div>
                      <p className="text-[13px] text-gray-600 mt-1">Nécessaire au calcul pendant la croissance (demandez à l&apos;éleveur ou au vétérinaire).</p>
                      {lireNombre(poidsAdulte).err && <p className="text-[13.5px] text-red-700">{lireNombre(poidsAdulte).err}</p>}
                    </>
                  )}
                </div>
              </div>
              <div className="mt-4">{besoinBloc()}</div>
            </div>
          )}

          {etape === 3 && (
            <div>
              <h2 className="text-[21px] font-extrabold mb-2">3. Aliments</h2>
              <p className="text-[14.5px] text-gray-600 mb-3">{plan.mode === 'unique' ? 'Choisissez l’aliment.' : 'Choisissez au moins deux aliments (même catégorie possible).'}</p>
              {plan.aliments.length > 0 && (
                <div className="mb-3 space-y-2">
                  <p className="text-sm font-bold">Sélectionnés</p>
                  {plan.aliments.map((a, i) => {
                    const peutModifier = a.id
                      ? modifiable(ligneCatalogue(a.id))
                      : !(['foin', 'paturage', 'legumes'].includes(a.type) && a.marque === 'Sans marque');
                    return (
                      <div key={i} className="flex items-stretch gap-2">
                        <button type="button" className={`${carteCase(true)} flex-1`} onClick={() => { const p = retirerAliment(plan, i); majPlan(p); setQte(textesQuantites(p)); }}>
                          <Case on /><span><b className="block text-[15px]">{nomAliment(a)}</b><span className="text-[13px] text-gray-600">{sousTitreAliment(a)}</span></span>
                        </button>
                        {peutModifier && (
                          <button type="button" onClick={() => modifierAliment(a.id ?? null, i)}
                            className="px-3 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-bold">Modifier</button>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
              <div className="flex flex-wrap gap-2 items-center">
                <input aria-label="Rechercher un aliment" value={recherche} onChange={e => setRecherche(e.target.value)}
                  placeholder="Marque, produit ou catégorie" className="flex-[1_1_280px] h-12 px-4 rounded-full border border-gray-300 outline-none focus:border-[#0C5C6C]" />
                <button type="button" onClick={() => setAjout(true)}
                  className="h-12 px-4 rounded-xl border-2 border-dashed border-[#0C5C6C] text-[#0C5C6C] font-extrabold">Mon aliment n&apos;est pas dans la liste</button>
              </div>
              {!catalogue && <div className="h-0.5 bg-[#0C5C6C] mt-3 animate-pulse rounded-full" />}
              <div className="grid gap-2 sm:grid-cols-2 mt-3">
                {resultats.map(r => {
                  const a = depuisCatalogue(r);
                  if (indexDe(a) >= 0) return null;
                  const mien = modifiable(r);
                  return (
                    <div key={String(r.id)} className="flex items-stretch gap-2">
                      <button type="button" className={`${carteCase(false)} flex-1`} onClick={() => basculerAliment(a)}>
                        <Case on={false} />
                        <span><b className="block text-[15px]">{nomAliment(a)}</b>
                          <span className="text-[13px] text-gray-600">{sousTitreAliment(a)}{mien ? ' · ajouté par vous' : r.ajoute_par_uid ? ' · ajouté par un membre' : ''}</span></span>
                      </button>
                      {mien && (
                        <button type="button" onClick={() => modifierAliment(String(r.id))}
                          className="px-3 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-bold">Modifier</button>
                      )}
                    </div>
                  );
                })}
              </div>
              {catalogue && !resultats.length && (
                <p className="text-[14px] text-gray-600 mt-2">{q ? `Aucun résultat pour « ${recherche.trim()} ».` : 'Aucun aliment de ce type dans le catalogue.'}</p>
              )}
              <div className="flex flex-wrap gap-2 mt-3">
                {sansMarque.filter(t => !plan.aliments.some(a => a.type === t && !a.id)).map(t => (
                  <button key={t} type="button" onClick={() => basculerAliment({ marque: 'Sans marque', gamme: LIBELLES_TYPE_ALIMENT[t], type: t })}
                    className="h-11 px-4 rounded-[10px] border border-[#0C5C6C] text-[#0C5C6C] font-bold">Ajouter : {LIBELLES_TYPE_ALIMENT[t]} (sans marque)</button>
                ))}
              </div>
            </div>
          )}

          {etape === 4 && (
            <div>
              <h2 className="text-[21px] font-extrabold mb-2">4. Répartition par repas</h2>
              <p className="text-[14.5px] text-gray-600 mb-3">Cochez les aliments servis à chaque repas. Un repas peut en contenir un seul ou plusieurs.</p>
              <div className="grid gap-3 md:grid-cols-2">
                {plan.repas.map((r, i) => (
                  <div key={i} className="border border-gray-200 rounded-xl p-3 space-y-2">
                    <div className="flex justify-between"><b className="text-[16px]">{labels[i]}</b>{r.heure && <span className="text-[14px] text-gray-600">{r.heure.replace(':', ' h ')}</span>}</div>
                    {plan.aliments.map((a, ai) => {
                      const it = r.items.find(x => x.a === ai);
                      return (
                        <div key={ai}>
                          <button type="button" className={carteCase(!!it)} onClick={() => { const p = basculer(plan, i, ai, profil); majPlan(p); setQte(textesQuantites(p)); }}>
                            <Case on={!!it} /><span className="text-[15px]">{nomAliment(a)}</span>
                          </button>
                          {it && profil.typesLibres.includes(a.type) && (
                            <label className="flex items-center gap-2 mt-1 ml-3 text-[14px] min-h-[40px]">
                              <input type="checkbox" checked={!!it.libre} className="w-5 h-5"
                                onChange={e => {
                                  const p = { ...plan, repas: plan.repas.map((x, j) => (j !== i ? x : { ...x, items: x.items.map(y => (y.a === ai ? { ...y, libre: e.target.checked, g: e.target.checked ? null : y.g } : y)) })) };
                                  majPlan(p); setQte(textesQuantites(p));
                                }} />
                              À volonté (sans quantité)
                            </label>
                          )}
                        </div>
                      );
                    })}
                  </div>
                ))}
              </div>
            </div>
          )}

          {etape === 5 && (
            <div className="space-y-3">
              <h2 className="text-[21px] font-extrabold">5. Ration</h2>
              {profil.methode !== 'aucune' && <p className="text-[12.5px] font-extrabold text-gray-600">RATION RECOMMANDÉE PAR PETSMATCH</p>}
              {besoinBloc()}
              {calc.avertissements.map(a => <div key={a} className={`${encadre} bg-[#FFF4E0] border border-[#E9C27A]`}>{a}</div>)}
              {profil.methode === 'energie' && calc.alimentLibre.filter(l => !l).length >= 2 && (
                <div className="border border-gray-200 rounded-xl p-3 space-y-2">
                  <p className="font-bold text-[15px]">Part de chaque aliment dans l&apos;énergie du jour</p>
                  <p className="text-[13.5px] text-gray-600">
                    {plan.parts ? 'Les quantités recommandées suivent ces parts.' : 'Partage égal à chaque repas. Indiquez une part pour l\u2019ajuster (ex. 70 % croquettes, 30 % ménagère).'}
                  </p>
                  <div className="grid gap-2 sm:grid-cols-2">
                    {plan.aliments.map((a, i) => calc.alimentLibre[i] ? null : (
                      <div key={i}>
                        <label className="block text-[14px] font-bold mb-1" htmlFor={`part-${i}`}>{nomAliment(a)}</label>
                        <div className={`flex h-11 rounded-[10px] border overflow-hidden ${invalides[`part-${i}`] ? 'border-red-600' : 'border-gray-300'}`}>
                          <input id={`part-${i}`} inputMode="decimal" value={partsTxt[i] ?? (plan.parts ? fr(plan.parts[i]) : '')}
                            placeholder={calc.partEnergie[i] != null ? String(Math.round(calc.partEnergie[i]!)) : ''}
                            onChange={e => saisirPart(i, e.target.value)} className="flex-1 min-w-0 px-3 outline-none font-bold" />
                          <span className="px-3 flex items-center bg-gray-100 border-l border-gray-300 font-bold">%</span>
                        </div>
                        {invalides[`part-${i}`] && <p className="text-[13px] text-red-700">{invalides[`part-${i}`]}</p>}
                      </div>
                    ))}
                  </div>
                  {plan.parts && (
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className={`text-[14px] font-bold ${Math.abs(plan.parts.reduce((s, x) => s + x, 0) - 100) > 1 ? 'text-red-700' : ''}`}>
                        Total : {Math.round(plan.parts.reduce((s, x) => s + x, 0))} %
                      </span>
                      <button type="button" className="h-10 text-[#0C5C6C] font-extrabold"
                        onClick={() => { majPlan({ ...plan, parts: null }); setPartsTxt({}); setInvalides(inv => Object.fromEntries(Object.entries(inv).filter(([k]) => !k.startsWith('part-')))); }}>
                        Revenir au partage égal
                      </button>
                    </div>
                  )}
                </div>
              )}
              {fabricant.length > 0 && (
                <div className={`${encadre} bg-white border border-gray-200`}>
                  <p className="font-bold">Recommandation du fabricant (pour une alimentation 100 % avec cet aliment)</p>
                  {fabricant.map(f => <p key={f!}>{f}</p>)}
                </div>
              )}
              <div className="grid gap-3 md:grid-cols-2">
                {plan.repas.map((r, i) => (
                  <div key={i} className="border border-gray-200 rounded-xl p-3 space-y-3">
                    <div className="flex justify-between gap-2">
                      <b className="text-[16px]">{labels[i]}{r.heure ? ` · ${r.heure.replace(':', ' h ')}` : ''}</b>
                      <span className="text-[14px] text-gray-600">Total {formatQuantite(calc.lignes[i].reduce((s, x) => s + (x.eff ?? 0), 0), kg)}</span>
                    </div>
                    {r.items.map((it, j) => {
                      const x = calc.lignes[i][j];
                      const a = plan.aliments[it.a];
                      if (it.libre) return <p key={j} className="text-[15px] font-bold">{nomAliment(a)} : à volonté</p>;
                      const k = cle(i, it.a);
                      return (
                        <div key={j}>
                          <label className="block text-[14.5px] font-bold mb-1" htmlFor={`qte-${k}`}>{nomAliment(a)}</label>
                          <div className={`flex h-12 rounded-[10px] border overflow-hidden ${invalides[k] ? 'border-red-600' : 'border-gray-300'} focus-within:ring-1 focus-within:ring-[#0C5C6C]`}>
                            <input id={`qte-${k}`} inputMode="decimal" value={qte[k] ?? ''} onChange={e => saisirQuantite(i, it.a, e.target.value)}
                              placeholder={x.reco != null ? fr(kg ? Math.round(x.reco / 100) / 10 : Math.round(x.reco)) : 'Quantité'}
                              className="flex-1 min-w-0 px-3 outline-none text-base font-bold" />
                            <span className="px-3 flex items-center bg-gray-100 border-l border-gray-300 font-bold text-[14px]">{kg ? 'kg/repas' : 'g/repas'}</span>
                          </div>
                          <p className="text-[13px] text-gray-700 mt-1">
                            {x.reco != null
                              ? `Recommandé par PetsMatch : ${formatQuantite(x.reco, kg)}${it.g != null ? ` · vous avez choisi ${formatQuantite(it.g, kg)}` : ''}`
                              : profil.methode === 'energie' && kcalDe(a) == null ? 'Valeur énergétique non renseignée — ration personnalisée' : 'Quantité à indiquer'}
                          </p>
                          {invalides[k] && <p className="text-[13.5px] text-red-700">{invalides[k]}</p>}
                        </div>
                      );
                    })}
                  </div>
                ))}
              </div>
              {ecartMsg && (
                <div className={`${encadre} ${ecartImportant(calc) ? 'bg-[#FFF4E0] border border-[#E9C27A]' : 'bg-[#EAF3E5] border border-[#B8D3A8]'}`}>
                  <p>{ecartMsg}</p>
                  {ecartImportant(calc) && (
                    <label className="flex items-center gap-2 font-bold min-h-[44px]">
                      <input type="checkbox" checked={ecartOk} onChange={e => { setEcartOk(e.target.checked); setErreur(null); }} className="w-5 h-5" />
                      J&apos;ai vérifié, cette ration est voulue
                    </label>
                  )}
                </div>
              )}
              {confirmation}
              {peutRevenir && !confirmReco && (
                <button type="button" onClick={() => setConfirmReco('parcours')} className={boutonSecondaire}>Revenir à la ration recommandée</button>
              )}
            </div>
          )}

          {etape === 6 && (
            <div className="space-y-3">
              <h2 className="text-[21px] font-extrabold">6. Résumé et enregistrement</h2>
              <label className="block text-[16px] font-extrabold" htmlFor="alim-consignes">Consignes alimentaires (facultatif)</label>
              <textarea id="alim-consignes" rows={4} value={consignes} onChange={e => setConsignes(e.target.value)}
                placeholder="Humidifier les croquettes, servir à température ambiante, pas de friandises…"
                className="w-full px-3 py-2.5 rounded-[10px] border border-gray-300 outline-none focus:border-[#0C5C6C] text-[15px]" />
              <p className="text-[13.5px] text-gray-700">Visibles en lecture seule par les professionnels à qui vous avez ouvert l&apos;accès (pension, pet-sitter).</p>
            </div>
          )}

          {erreur && <div className={`${encadre} bg-red-50 border border-red-200 text-red-800`}>{erreur}</div>}
          <div className="flex flex-wrap justify-end gap-3 pt-4 border-t border-gray-100">
            <button type="button" onClick={() => (etape > 1 ? allerEtape(etape - 1) : row && setParcours(false))}
              className="h-12 px-6 rounded-[10px] border border-gray-300 bg-white font-bold">{etape > 1 ? 'Retour' : 'Annuler'}</button>
            <button type="button" onClick={suivant} disabled={saving} className={boutonPrincipal}>
              {etape === 6 ? (saving ? 'Enregistrement…' : 'Enregistrer') : 'Continuer'}
            </button>
          </div>
        </div>

        {/* Aperçu permanent : mêmes informations que la synthèse */}
        <aside className="flex-[1_1_320px] min-w-0 bg-white border border-gray-200 rounded-2xl p-4">
          <div className="flex flex-wrap justify-between items-center gap-2 mb-3">
            <b className="text-[17px]">Aperçu de la ration</b>
            <span className={`px-2.5 py-1 rounded-full text-[12px] font-extrabold ${badgeCls}`}>{badge}</span>
          </div>
          {plan.aliments.length
            ? <PlanAlimentationLecture plan={plan} calcul={calc} espece={espece} consignes={consignes} />
            : <p className="text-[14px] text-gray-600">Aucun aliment sélectionné pour l&apos;instant.</p>}
        </aside>
      </div>

      {ajout && (
        <AjoutAlimentModal espece={espece} marqueInitiale={recherche.trim()}
          typeInitial={(plan.categories.length ? plan.categories : profil.types)[0]}
          types={plan.categories}
          onClose={() => setAjout(false)}
          onCreated={a => {
            const p = ajouterAliment(plan, a, profil);
            majPlan({ ...p, categories: p.categories.includes(a.type) ? p.categories : [...p.categories, a.type] });
            setQte(textesQuantites(p));
            setRecherche(''); setAjout(false);
            // Le nouvel aliment rejoint la liste (même si on le désélectionne).
            if (a.id) chargerCatalogue(true);
          }} />
      )}
      {modif && (
        <AjoutAlimentModal espece={espece}
          types={[...new Set([...(plan.categories.length ? plan.categories : profil.types),
            ...(modif.index != null && plan.aliments[modif.index] ? [plan.aliments[modif.index].type] : [])])]}
          ligne={modif.ligne ?? null}
          aliment={!modif.ligne && modif.index != null ? plan.aliments[modif.index] : null}
          onClose={() => setModif(null)}
          onCreated={a => {
            const idModif = modif.ligne ? String(modif.ligne.id) : null;
            const aliments = plan.aliments.map((x, i) => (i === modif.index || (idModif && x.id === idModif)
              ? { ...x, id: a.id ?? null, marque: a.marque, gamme: a.gamme, type: a.type, kcal: a.kcal ?? null,
                  source: a.source ?? null, repartition: a.repartition ?? null, tableauCroissance: a.tableauCroissance ?? [] }
              : x));
            const p = { ...plan, aliments, categories: plan.categories.includes(a.type) ? plan.categories : [...plan.categories, a.type] };
            majPlan(p);
            setQte(textesQuantites(p));
            setModif(null);
            if (idModif || a.id) chargerCatalogue(true);
          }} />
      )}
    </div>
  );
}
