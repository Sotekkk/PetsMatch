// Éducateur — forfaits de séances (forfaits_education → forfaits_souscrits) :
// type de séances couvertes, décompte d'une séance par RDV
// (rdv.forfait_souscrit_id : pas de facture à la séance), facture du forfait
// préparée à l'attribution (payé d'avance). Miroir appli :
// lib/utils/forfait_education.dart.
import { supabase } from '@/lib/supabase';
import { animauxDetailRdv, type AnimalRdv } from '@/lib/rdv-animaux';

export type TypeSeances = 'individuel' | 'collectif' | 'mixte';

export const TYPES_SEANCES: { value: TypeSeances; label: string }[] = [
  { value: 'individuel', label: 'Séances individuelles' },
  { value: 'collectif', label: 'Séances collectives' },
  { value: 'mixte', label: 'Mixte (individuel et collectif)' },
];
export const libelleTypeSeances = (t?: string | null) => TYPES_SEANCES.find(x => x.value === t)?.label ?? 'Mixte (individuel et collectif)';

export interface ForfaitActif {
  id: string; nom_snapshot: string; nb_seances_total: number; nb_seances_utilisees: number;
  type_seances?: string | null; statut: string;
  /** Forfait mixte réparti : tant de séances individuelles + tant de collectives. */
  nb_indiv_total?: number | null; nb_coll_total?: number | null;
  nb_indiv_utilisees?: number | null; nb_coll_utilisees?: number | null;
  prix_snapshot?: number | null;
}

export const COLS_FORFAIT_SOUSCRIT =
  'id, nom_snapshot, nb_seances_total, nb_seances_utilisees, type_seances, statut, nb_indiv_total, nb_coll_total, nb_indiv_utilisees, nb_coll_utilisees, prix_snapshot';

/** Forfait mixte avec un nombre de séances par type. */
export const estReparti = (f: ForfaitActif) => f.nb_indiv_total != null || f.nb_coll_total != null;

export function resteParType(f: ForfaitActif, type: 'individuel' | 'collectif'): number {
  return type === 'collectif'
    ? Math.max(0, (f.nb_coll_total ?? 0) - (f.nb_coll_utilisees ?? 0))
    : Math.max(0, (f.nb_indiv_total ?? 0) - (f.nb_indiv_utilisees ?? 0));
}

const restantes = (n: number, total: number) => `${n} restante${n > 1 ? 's' : ''} sur ${total}`;

/** « 3 séances restantes sur 5 », ou par type pour un forfait mixte réparti. */
export function libelleCompteurs(f: ForfaitActif): string {
  if (estReparti(f)) {
    return [
      (f.nb_indiv_total ?? 0) > 0 ? `Individuelles : ${restantes(resteParType(f, 'individuel'), f.nb_indiv_total ?? 0)}` : '',
      (f.nb_coll_total ?? 0) > 0 ? `Collectives : ${restantes(resteParType(f, 'collectif'), f.nb_coll_total ?? 0)}` : '',
    ].filter(Boolean).join(' · ');
  }
  const r = Math.max(0, f.nb_seances_total - f.nb_seances_utilisees);
  return `${r} séance${r > 1 ? 's' : ''} restante${r > 1 ? 's' : ''} sur ${f.nb_seances_total}`;
}

/** Type du cours d'un RDV (catalogue) : collectif ou individuel (par défaut). */
export async function typeSeanceRdv(prestationId: string | null | undefined): Promise<'individuel' | 'collectif'> {
  if (!prestationId) return 'individuel';
  const { data } = await supabase.from('prestations_education').select('type').eq('id', prestationId).maybeSingle();
  return (data as { type?: string } | null)?.type === 'collectif' ? 'collectif' : 'individuel';
}

export const forfaitCouvre = (f: ForfaitActif, type: 'individuel' | 'collectif') =>
  estReparti(f) ? resteParType(f, type) > 0
    : !f.type_seances || f.type_seances === 'mixte' || f.type_seances === type;

export const seancesRestantes = (f: ForfaitActif) => Math.max(0, f.nb_seances_total - f.nb_seances_utilisees);

type MarqueForfait = { forfait_souscrit_id?: string | null; forfait_type_decompte?: string | null };

async function retirerSeance(f: ForfaitActif, type: 'individuel' | 'collectif', o: { animalId: string; animalNom: string; ownerUid?: string | null }) {
  const used = f.nb_seances_utilisees + 1;
  const termine = used >= f.nb_seances_total;
  const compteur = estReparti(f) ? (type === 'collectif'
    ? { nb_coll_utilisees: (f.nb_coll_utilisees ?? 0) + 1 } : { nb_indiv_utilisees: (f.nb_indiv_utilisees ?? 0) + 1 }) : {};
  const { error } = await supabase.from('forfaits_souscrits').update({
    nb_seances_utilisees: used, ...compteur,
    ...(termine ? { statut: 'termine', termine_le: new Date().toISOString() } : {}),
  }).eq('id', f.id);
  if (error) throw error;
  if (o.ownerUid && (used === f.nb_seances_total - 1 || termine)) {
    await supabase.from('notifications').insert({
      uid: o.ownerUid, type: 'education_forfait_bas',
      title: `Forfait ${termine ? 'terminé' : 'bientôt terminé'} — ${o.animalNom}`,
      body: termine ? `Toutes les séances du forfait « ${f.nom_snapshot} » ont été utilisées.`
        : `Il reste 1 séance sur le forfait « ${f.nom_snapshot} ».`,
      data: { animalId: o.animalId, url: `/mes-animaux/${o.animalId}?tab=education` },
    });
  }
}

/** Décompte la séance du RDV (une seule fois par RDV) et prévient la famille quand il ne
 *  reste qu'une séance ou plus aucune. Séance à plusieurs chiens : chacun sur son propre
 *  forfait, noté dans rdv.animaux_detail. Renvoie les chiens sans forfait actif. */
export async function decompterSeanceForfait(f: ForfaitActif, rdvId: string, o: {
  animalId: string; animalNom: string; ownerUid?: string | null;
  /** Type du cours du RDV : décompté du bon compteur d'un forfait mixte réparti. */
  typeCours?: 'individuel' | 'collectif';
}): Promise<string[]> {
  const { data } = await supabase.from('rdv').select('forfait_souscrit_id, animaux_detail, pro_profile_id').eq('id', rdvId).maybeSingle();
  const rdv = data as { forfait_souscrit_id?: string | null; animaux_detail?: unknown; pro_profile_id?: string | null } | null;
  if (rdv?.forfait_souscrit_id) return [];
  const type = o.typeCours ?? 'individuel';
  const detail = animauxDetailRdv(rdv ?? {}) as (AnimalRdv & MarqueForfait)[];
  if (detail.length < 2) {
    await retirerSeance(f, type, o);
    await supabase.from('rdv').update({ forfait_souscrit_id: f.id, forfait_type_decompte: estReparti(f) ? type : null }).eq('id', rdvId);
    return [];
  }
  const sansForfait: string[] = [];
  let premier: string | null = null;
  for (const a of detail) {
    let fa: ForfaitActif | null = a.id === o.animalId ? f : null;
    if (!fa) {
      let q = supabase.from('forfaits_souscrits').select(COLS_FORFAIT_SOUSCRIT).eq('animal_id', a.id).eq('statut', 'actif');
      if (rdv?.pro_profile_id) q = q.eq('pro_profile_id', rdv.pro_profile_id);
      const { data: l } = await q.order('souscrit_le', { ascending: false }).limit(1).maybeSingle();
      fa = (l as ForfaitActif | null) ?? null;
    }
    if (!fa) { sansForfait.push(a.nom); continue; }
    await retirerSeance(fa, type, { animalId: a.id, animalNom: a.nom, ownerUid: o.ownerUid });
    a.forfait_souscrit_id = fa.id;
    a.forfait_type_decompte = estReparti(fa) ? type : null;
    premier = premier ?? fa.id;
    // Enregistré chien par chien : une erreur en cours de route ne fausse pas les soldes.
    await supabase.from('rdv').update({
      animaux_detail: detail, forfait_souscrit_id: premier, forfait_type_decompte: a.forfait_type_decompte,
    }).eq('id', rdvId);
  }
  return sansForfait;
}

async function rendreSeance(fid: string, type?: string | null) {
  const { data: f } = await supabase.from('forfaits_souscrits').select('nb_seances_utilisees, nb_indiv_utilisees, nb_coll_utilisees').eq('id', fid).maybeSingle();
  const x = f as { nb_seances_utilisees?: number; nb_indiv_utilisees?: number; nb_coll_utilisees?: number } | null;
  const compteur = type === 'collectif' ? { nb_coll_utilisees: Math.max(0, (x?.nb_coll_utilisees ?? 1) - 1) }
    : type === 'individuel' ? { nb_indiv_utilisees: Math.max(0, (x?.nb_indiv_utilisees ?? 1) - 1) } : {};
  await supabase.from('forfaits_souscrits').update({
    nb_seances_utilisees: Math.max(0, (x?.nb_seances_utilisees ?? 1) - 1), ...compteur, statut: 'actif', termine_le: null,
  }).eq('id', fid);
}

/** Annule le décompte de la séance du RDV (rend la séance au forfait de chaque chien). */
export async function annulerDecompteForfait(rdvId: string) {
  const { data: rdv } = await supabase.from('rdv').select('forfait_souscrit_id, forfait_type_decompte, animaux_detail').eq('id', rdvId).maybeSingle();
  const r = rdv as { forfait_souscrit_id?: string | null; forfait_type_decompte?: string | null; animaux_detail?: unknown } | null;
  if (!r?.forfait_souscrit_id) return;
  const detail = animauxDetailRdv(r) as (AnimalRdv & MarqueForfait)[];
  const marques = detail.filter(a => a.forfait_souscrit_id);
  if (marques.length === 0) {
    await rendreSeance(r.forfait_souscrit_id, r.forfait_type_decompte);
    await supabase.from('rdv').update({ forfait_souscrit_id: null, forfait_type_decompte: null }).eq('id', rdvId);
    return;
  }
  for (const a of marques) await rendreSeance(a.forfait_souscrit_id!, a.forfait_type_decompte);
  await supabase.from('rdv').update({
    animaux_detail: detail.map(({ forfait_souscrit_id: _f, forfait_type_decompte: _t, ...reste }) => reste),
    forfait_souscrit_id: null, forfait_type_decompte: null,
  }).eq('id', rdvId);
}

/** Séance sans facture : tous les chiens décomptés (RDV ancien sans détail : le forfait du RDV). */
export function seanceCouverte(r: { forfait_souscrit_id?: string | null; animaux_detail?: unknown }): boolean {
  if (!r.forfait_souscrit_id) return false;
  const detail = animauxDetailRdv(r) as (AnimalRdv & MarqueForfait)[];
  return !detail.some(a => a.forfait_souscrit_id) || detail.every(a => a.forfait_souscrit_id);
}

export interface CoordClient { prenom: string; nom: string; email: string; tel: string; rue: string; cp: string; ville: string }

/** Coordonnées du client pour la facture du forfait : celles du RDV (le RDV
 *  du dossier, sinon le dernier RDV de l'animal chez ce pro), comme la facture
 *  d'une séance (pm_contact_client_rdv) ; repli sur le propriétaire connu. */
export async function coordClientForfait(proUid: string, animalId: string, rdvId?: string | null,
  repli: Partial<CoordClient> = {}): Promise<CoordClient> {
  let id = rdvId ?? null;
  let manuel: { client_nom_manuel?: string | null; client_email_manuel?: string | null; client_telephone_manuel?: string | null } = {};
  if (!id) {
    const { data } = await supabase.from('rdv').select('id, client_nom_manuel, client_email_manuel, client_telephone_manuel')
      .eq('pro_uid', proUid).eq('animal_id', animalId).order('date_heure', { ascending: false }).limit(1).maybeSingle();
    id = (data as { id?: string } | null)?.id ?? null;
    manuel = (data ?? {}) as typeof manuel;
  }
  const { data: cc } = id ? await supabase.rpc('pm_contact_client_rdv', { p_rdv_id: id }) : { data: null };
  const c = (cc ?? {}) as Record<string, string | null>;
  const v = (...l: (string | null | undefined)[]) => l.find(x => x?.trim())?.trim() ?? '';
  return {
    prenom: v(c.prenom, repli.prenom), nom: v(c.nom, manuel.client_nom_manuel, repli.nom),
    email: v(c.email, manuel.client_email_manuel, repli.email), tel: v(c.telephone, manuel.client_telephone_manuel, repli.tel),
    rue: v(c.rue, repli.rue), cp: v(c.code_postal, repli.cp), ville: v(c.ville, repli.ville),
  };
}

/** Facture du forfait (payé d'avance) : pré-remplit /elevage/facturation. */
export function preparerFactureForfait(o: {
  nomForfait: string; nbSeances: number; prix: number; animalId: string; animalNom: string;
  clientUid?: string | null; clientProfileId?: string | null; client: CoordClient; retour?: string;
  /** Forfait du client : la facture émise y est reliée (forfaits_souscrits.facture_id). */
  forfaitSouscritId?: string | null;
}) {
  try {
    sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
      prenomClient: o.client.prenom || undefined, nomClient: o.client.nom || 'Client', emailClient: o.client.email || undefined,
      telClient: o.client.tel || undefined, rueClient: o.client.rue || undefined, cpClient: o.client.cp || undefined,
      villeClient: o.client.ville || undefined,
      sourceAnimalId: o.animalId, clientUid: o.clientUid ?? undefined, clientProfileId: o.clientProfileId ?? undefined,
      notes: `Forfait payé d'avance — ${o.animalNom}`,
      ...(o.retour ? { retour: o.retour } : {}),
      ...(o.forfaitSouscritId ? { forfaitSouscritId: o.forfaitSouscritId } : {}),
      lignes: [{ description: `Forfait ${o.nomForfait} (${o.nbSeances} séance${o.nbSeances > 1 ? 's' : ''}) — ${o.animalNom}`,
        quantite: 1, prixUnitaire: 0, prixTTC: o.prix, tva: 20 }],
    }));
  } catch { /* facture vierge */ }
}
