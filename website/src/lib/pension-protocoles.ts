// Pension — protocoles du séjour (reference_event = 'sejour',
// migration_pension_protocoles_sejour.sql). Appliqués AUTOMATIQUEMENT à
// l'enregistrement de l'arrivée : chaque étape se place pendant le séjour
// (chaque jour, jour de l'arrivée + n, jour du départ − n), pour les
// pensionnaires ciblés (espèce, races, logement / type de logement, séjour /
// essai, nouveau / habitué). Périmètre « locaux » : une tâche par logement
// occupé, sans doublon. Tâches rattachées au séjour (pension_entree_id) :
// les tâches non faites sont retirées si le séjour se termine plus tôt ou est
// annulé. Miroir appli : lib/utils/pension_protocoles.dart.
import type { SupabaseClient } from '@supabase/supabase-js';
import { acteLabel, eclaterTranches } from '@/lib/protocoles';
import { cleEspecePension, pensionGroupe, PENSION_ESPECES } from '@/lib/pension-especes';

export interface PensionCible {
  races?: string[]; logement_ids?: string[]; logement_types?: string[];
  /** Espèces concernées (clés pension) : pensionnaires de ces espèces, ou
   *  logements de ces espèces (protocoles « locaux »). Vide = toutes. */
  especes?: string[];
  /** Logements individuels (1 place) ou partagés seulement. */
  places?: 'tous' | 'individuel' | 'partage';
  sejour?: 'tous' | 'sejour' | 'essai'; nouveau?: 'tous' | 'nouveau' | 'habitue';
}
export type MomentSejour = 'chaque_jour' | 'arrivee' | 'depart';

export const MOMENTS_SEJOUR: { value: MomentSejour; label: string }[] = [
  { value: 'chaque_jour', label: 'Chaque jour du séjour' },
  { value: 'arrivee', label: "Jour de l'arrivée (+ jours)" },
  { value: 'depart', label: 'Avant le départ (jours)' },
];

export function momentLabel(m?: string | null, offset = 0): string {
  if (m === 'arrivee') return offset ? `${offset} j après l'arrivée` : "Jour de l'arrivée";
  if (m === 'depart') return offset ? `${offset} j avant le départ` : 'Jour du départ';
  return 'Chaque jour du séjour';
}

/** Résumé du ciblage (cartes, fiche du protocole). */
export function cibleLabel(c?: PensionCible | null): string {
  if (!c) return 'Tous les pensionnaires';
  const p: string[] = [];
  if (c.especes?.length) p.push(`espèces : ${c.especes.map(k => PENSION_ESPECES.find(x => x.key === k)?.label ?? k).join(', ')}`);
  if (c.races?.length) p.push(`races : ${c.races.join(', ')}`);
  if (c.logement_types?.length) p.push(`logements : ${c.logement_types.join(', ')}`);
  if (c.logement_ids?.length) p.push(`${c.logement_ids.length} logement(s) choisi(s)`);
  if (c.places === 'individuel') p.push('logements individuels');
  if (c.places === 'partage') p.push('logements partagés');
  if (c.sejour === 'essai') p.push('essais seulement');
  if (c.sejour === 'sejour') p.push('séjours (hors essai)');
  if (c.nouveau === 'nouveau') p.push('nouveaux pensionnaires');
  if (c.nouveau === 'habitue') p.push('habitués');
  return p.length ? p.join(' · ') : 'Tous les pensionnaires';
}

type Ligne = Record<string, unknown>;
const t = (v: unknown) => (v == null ? '' : String(v).trim());
const jour = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const decaler = (iso: string, n: number) => { const d = new Date(`${iso}T12:00:00`); d.setDate(d.getDate() + n); return jour(d); };

/** Jours du séjour (arrivée → départ prévu, inclus). */
function joursSejour(arrivee: string, depart: string | null): string[] {
  const fin = depart && depart >= arrivee ? depart : arrivee;
  const out: string[] = [];
  for (let d = arrivee; d <= fin && out.length < 400; d = decaler(d, 1)) out.push(d);
  return out;
}

function especeOk(tplEspece: unknown, espece: unknown) {
  const a = cleEspecePension(t(tplEspece)), b = cleEspecePension(t(espece));
  return !a || !b || a === b || pensionGroupe(a) === pensionGroupe(b);
}

/** Ciblage par espèce : espèce du pensionnaire, ou à défaut espèces du logement. */
export function especeCibleOk(cibles: string[] | undefined, espece: unknown, especesLogement: unknown): boolean {
  if (!cibles?.length) return true;
  const proche = (a: string, b: string) => a === b || pensionGroupe(a) === pensionGroupe(b);
  const k = cleEspecePension(t(espece));
  if (k) return cibles.some(c => proche(cleEspecePension(c), k));
  const liste = Array.isArray(especesLogement) ? especesLogement.map(x => cleEspecePension(t(x))).filter(Boolean) : [];
  return !liste.length || liste.some(l => cibles.some(c => proche(cleEspecePension(c), l)));
}

/**
 * Applique les protocoles de séjour aux séjours donnés (arrivée enregistrée).
 * `templateIds` : limiter à certains protocoles ; `depuis` : ne créer que les
 * tâches à partir de ce jour (application à des pensionnaires déjà présents).
 */
export async function appliquerProtocolesSejour(sb: SupabaseClient, entreeIds: string[], o: { templateIds?: string[]; depuis?: string } = {}) {
  const res = { taches: 0, protocoles: [] as string[] };
  if (!entreeIds.length) return res;
  const { data: ens } = await sb.from('pension_entrees').select('*').in('id', entreeIds);
  const entrees = ((ens ?? []) as Ligne[]).filter(e => t(e.statut) === 'en_pension');
  if (!entrees.length) return res;
  const proUid = t(entrees[0].pro_uid), pid = t(entrees[0].pro_profile_id);
  let q = sb.from('plan_templates').select('*, plan_template_etapes(*)').eq('uid_eleveur', proUid)
    .eq('profil_source', 'pension').eq('reference_event', 'sejour');
  if (o.templateIds?.length) q = q.in('id', o.templateIds);
  const { data: tpls, error } = await q;
  if (error || !tpls?.length) return res;
  const templates = (tpls as Ligne[]).filter(tp => !pid || !t(tp.eleveur_profile_id) || t(tp.eleveur_profile_id) === pid);
  // Logements (nom, type) et demandes (nouveau pensionnaire).
  const { data: lgs } = await sb.from('enclos_chenil').select('id, nom, type, especes, capacite').eq('uid_eleveur', proUid);
  const logements = new Map(((lgs ?? []) as Ligne[]).map(l => [t(l.id), l]));
  const { data: dms } = await sb.from('pension_demandes').select('entree_id, essai_entree_id, nouveau_pensionnaire')
    .or(entreeIds.map(id => `entree_id.eq.${id},essai_entree_id.eq.${id}`).join(','));
  const nouveauDe = (id: string) => {
    const d = ((dms ?? []) as Ligne[]).find(x => t(x.entree_id) === id || t(x.essai_entree_id) === id);
    return d ? d.nouveau_pensionnaire === true : null;
  };

  for (const tp of templates) {
    const cible = (tp.pension_cible ?? null) as PensionCible | null;
    const etapes = (Array.isArray(tp.plan_template_etapes) ? tp.plan_template_etapes : []) as Ligne[];
    if (!etapes.length) continue;
    const locaux = t(tp.cible_type) === 'locaux';
    let applique = false;
    for (const e of entrees) {
      // Ciblage
      if (!locaux && !especeOk(tp.espece, e.espece)) continue;
      if (cible?.races?.length && !cible.races.some(r => r.trim().toLowerCase() === t(e.race).toLowerCase())) continue;
      const lg = logements.get(t(e.logement_id));
      if (cible?.logement_ids?.length && !cible.logement_ids.includes(t(e.logement_id))) continue;
      if (cible?.logement_types?.length && !cible.logement_types.includes(t(lg?.type))) continue;
      if (!especeCibleOk(cible?.especes, e.espece, lg?.especes)) continue;
      if (cible?.places === 'individuel' && (!lg || (Number(lg.capacite) || 1) > 1)) continue;
      if (cible?.places === 'partage' && (!lg || (Number(lg.capacite) || 1) <= 1)) continue;
      if (cible?.sejour === 'essai' && e.essai !== true) continue;
      if (cible?.sejour === 'sejour' && e.essai === true) continue;
      const nv = nouveauDe(t(e.id));
      if (cible?.nouveau === 'nouveau' && nv !== true) continue;
      if (cible?.nouveau === 'habitue' && nv === true) continue;
      if (locaux && !lg) continue;

      const jours = joursSejour(t(e.date_entree).slice(0, 10), t(e.date_sortie_prevue).slice(0, 10) || null);
      const etapeIds = etapes.map(x => t(x.id));
      // Doublons : déjà appliqué à ce séjour (animal) ou à ce logement ces jours-là (locaux).
      const { data: deja } = locaux
        ? await sb.from('plan_taches').select('etape_id, date_prevue').eq('box_id', t(e.logement_id)).in('etape_id', etapeIds)
            .gte('date_prevue', jours[0]).lte('date_prevue', jours[jours.length - 1])
        : await sb.from('plan_taches').select('etape_id, date_prevue').eq('pension_entree_id', t(e.id)).in('etape_id', etapeIds);
      const existe = new Set(((deja ?? []) as Ligne[]).map(x => `${t(x.etape_id)}|${t(x.date_prevue)}`));

      const taches: Ligne[] = [];
      for (const et of etapes) {
        const m = t(et.sejour_moment) || 'chaque_jour';
        const off = Number(et.jour_offset) || 0;
        const dates = m === 'arrivee' ? [decaler(jours[0], off)]
          : m === 'depart' ? [decaler(jours[jours.length - 1], -off)]
          : jours;
        const base = [acteLabel(t(et.type_acte)) || t(et.description), t(et.produit), t(et.dosage) ? `(${t(et.dosage)})` : ''].filter(Boolean).join(' ');
        const dansSejour = dates.filter(d => d >= jours[0] && d <= jours[jours.length - 1] && (!o.depuis || d >= o.depuis));
        dansSejour.forEach((d, i) => {
          if (existe.has(`${t(et.id)}|${d}`)) return;
          taches.push({
            etape_id: t(et.id), uid_eleveur: proUid, profile_id: pid || null, ...(pid ? { eleveur_profile_id: pid } : {}),
            animal_id: locaux ? null : t(e.animal_id) || null, animal_nom: locaux ? null : t(e.animal_nom) || null,
            type_acte: t(et.type_acte) || null, lieu: t(lg?.nom) || t(et.lieu) || null, tranche_horaire: t(et.tranche_horaire) || null,
            profil_source: 'pension', pension_entree_id: t(e.id), box_id: t(e.logement_id) || null,
            label: locaux ? `${base} — ${t(lg?.nom) || 'logement'}` : (dansSejour.length > 1 ? `${base} — Jour ${i + 1}/${dansSejour.length}` : base),
            date_prevue: d, jour_traitement: i + 1, total_jours: dansSejour.length,
          });
        });
      }
      if (!taches.length) continue;
      const { data: plan } = await sb.from('plans_actifs').insert({
        template_id: t(tp.id), uid_eleveur: proUid, ...(pid ? { eleveur_profile_id: pid } : {}),
        type_declencheur: 'sejour', date_reference: jours[0], reference_id: t(e.id),
        reference_label: locaux ? t(lg?.nom) || 'Logement' : t(e.animal_nom) || 'Pensionnaire', profil_source: 'pension',
      }).select('id').single();
      if (!plan) continue;
      // Plusieurs créneaux (matin et soir…) : une tâche par créneau.
      const parCreneau = eclaterTranches(taches);
      const { error: errT } = await sb.from('plan_taches').insert(parCreneau.map(x => ({ ...x, plan_id: (plan as { id: string }).id })));
      if (errT) continue;
      res.taches += parCreneau.length;
      applique = true;
    }
    if (applique) res.protocoles.push(t(tp.nom));
  }
  return res;
}

/** Séjour terminé plus tôt / annulé : tâches non faites après `apres` retirées. */
export async function retirerTachesSejour(sb: SupabaseClient, entreeIds: string[], apres: string) {
  if (!entreeIds.length) return;
  await sb.from('plan_taches').delete().in('pension_entree_id', entreeIds).neq('statut', 'fait').gt('date_prevue', apres);
}

/**
 * Départ enregistré : les tâches « au départ » se recalent sur le vrai jour du
 * départ (départ avancé ou retardé) ; une tâche de logement (nettoyage,
 * désinfection) dont le logement reste occupé par un autre pensionnaire passe
 * au départ de celui-ci ; les autres tâches non faites après le départ sont
 * retirées.
 */
export async function terminerTachesSejour(sb: SupabaseClient, entreeIds: string[], dateDepart: string) {
  if (!entreeIds.length) return;
  const { data: tts } = await sb.from('plan_taches')
    .select('id, etape_id, date_prevue, box_id, plan_template_etapes(sejour_moment, jour_offset), plans_actifs(plan_templates(cible_type))')
    .in('pension_entree_id', entreeIds).neq('statut', 'fait');
  const estLocaux = (x: Ligne) => t(((x.plans_actifs as Ligne | null)?.plan_templates as Ligne | null)?.cible_type) === 'locaux';
  const estDepart = (x: Ligne) => t((x.plan_template_etapes as Ligne | null)?.sejour_moment) === 'depart';
  const toutes = (tts ?? []) as Ligne[];
  const taches = toutes.filter(estDepart);
  // Tâches quotidiennes d'un logement encore occupé : elles continuent pour l'autre pensionnaire.
  const quotidiennes = toutes.filter(x => !estDepart(x) && estLocaux(x) && t(x.date_prevue) > dateDepart);
  const boxes = [...new Set([...taches, ...quotidiennes].map(x => t(x.box_id)).filter(Boolean))];
  const { data: autres } = boxes.length
    ? await sb.from('pension_entrees').select('id, logement_id, date_sortie_prevue').eq('statut', 'en_pension').in('logement_id', boxes)
    : { data: [] };
  const restants = ((autres ?? []) as Ligne[]).filter(o => !entreeIds.includes(t(o.id)));
  for (const x of quotidiennes) {
    const reste = restants.find(o => t(o.logement_id) === t(x.box_id) && t(x.date_prevue) <= (t(o.date_sortie_prevue).slice(0, 10) || t(x.date_prevue)));
    if (reste) await sb.from('plan_taches').update({ pension_entree_id: t(reste.id) }).eq('id', t(x.id));
  }
  for (const x of taches) {
    const off = Number((x.plan_template_etapes as Ligne).jour_offset) || 0;
    const locaux = estLocaux(x);
    const reste = locaux ? restants.filter(o => t(o.logement_id) === t(x.box_id))
      .sort((a, b) => t(b.date_sortie_prevue).localeCompare(t(a.date_sortie_prevue)))[0] : undefined;
    if (reste) {
      // Logement encore occupé : la tâche suit le dernier pensionnaire qui part.
      const fin = t(reste.date_sortie_prevue).slice(0, 10) || dateDepart;
      const date = decaler(fin, -off);
      const { data: dbl } = await sb.from('plan_taches').select('id').eq('box_id', t(x.box_id)).eq('etape_id', t(x.etape_id)).eq('date_prevue', date).neq('id', t(x.id)).limit(1);
      if (dbl?.length) await sb.from('plan_taches').delete().eq('id', t(x.id));
      else await sb.from('plan_taches').update({ pension_entree_id: t(reste.id), date_prevue: date }).eq('id', t(x.id));
    } else {
      const date = decaler(dateDepart, -off);
      if (t(x.date_prevue) !== date) await sb.from('plan_taches').update({ date_prevue: date }).eq('id', t(x.id));
    }
  }
  await sb.from('plan_taches').delete().in('pension_entree_id', entreeIds).neq('statut', 'fait').gt('date_prevue', dateDepart);
}

export const aujourdhuiIso = () => jour(new Date());
