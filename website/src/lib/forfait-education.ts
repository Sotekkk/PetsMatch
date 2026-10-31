// Éducateur — forfaits de séances (forfaits_education → forfaits_souscrits) :
// type de séances couvertes, décompte d'une séance par RDV
// (rdv.forfait_souscrit_id : pas de facture à la séance), facture du forfait
// préparée à l'attribution (payé d'avance). Miroir appli :
// lib/utils/forfait_education.dart.
import { supabase } from '@/lib/supabase';

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
}

/** Type du cours d'un RDV (catalogue) : collectif ou individuel (par défaut). */
export async function typeSeanceRdv(prestationId: string | null | undefined): Promise<'individuel' | 'collectif'> {
  if (!prestationId) return 'individuel';
  const { data } = await supabase.from('prestations_education').select('type').eq('id', prestationId).maybeSingle();
  return (data as { type?: string } | null)?.type === 'collectif' ? 'collectif' : 'individuel';
}

export const forfaitCouvre = (f: Pick<ForfaitActif, 'type_seances'>, type: 'individuel' | 'collectif') =>
  !f.type_seances || f.type_seances === 'mixte' || f.type_seances === type;

export const seancesRestantes = (f: ForfaitActif) => Math.max(0, f.nb_seances_total - f.nb_seances_utilisees);

/** Décompte la séance du RDV de ce forfait (une seule fois par RDV) et prévient
 *  la famille quand il ne reste qu'une séance ou plus aucune. */
export async function decompterSeanceForfait(f: ForfaitActif, rdvId: string, o: { animalId: string; animalNom: string; ownerUid?: string | null }) {
  const { data: rdv } = await supabase.from('rdv').select('forfait_souscrit_id').eq('id', rdvId).maybeSingle();
  if ((rdv as { forfait_souscrit_id?: string | null } | null)?.forfait_souscrit_id) return;
  const used = f.nb_seances_utilisees + 1;
  const termine = used >= f.nb_seances_total;
  const { error } = await supabase.from('forfaits_souscrits').update({
    nb_seances_utilisees: used,
    ...(termine ? { statut: 'termine', termine_le: new Date().toISOString() } : {}),
  }).eq('id', f.id);
  if (error) throw error;
  await supabase.from('rdv').update({ forfait_souscrit_id: f.id }).eq('id', rdvId);
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

/** Annule le décompte de la séance du RDV (rend la séance au forfait). */
export async function annulerDecompteForfait(rdvId: string) {
  const { data: rdv } = await supabase.from('rdv').select('forfait_souscrit_id').eq('id', rdvId).maybeSingle();
  const fid = (rdv as { forfait_souscrit_id?: string | null } | null)?.forfait_souscrit_id;
  if (!fid) return;
  const { data: f } = await supabase.from('forfaits_souscrits').select('nb_seances_utilisees').eq('id', fid).maybeSingle();
  const used = Math.max(0, ((f as { nb_seances_utilisees?: number } | null)?.nb_seances_utilisees ?? 1) - 1);
  await supabase.from('forfaits_souscrits').update({ nb_seances_utilisees: used, statut: 'actif', termine_le: null }).eq('id', fid);
  await supabase.from('rdv').update({ forfait_souscrit_id: null }).eq('id', rdvId);
}

/** Facture du forfait (payé d'avance) : pré-remplit /elevage/facturation. */
export function preparerFactureForfait(o: {
  nomForfait: string; nbSeances: number; prix: number; animalId: string; animalNom: string;
  clientUid?: string | null; clientProfileId?: string | null; prenom?: string; nom?: string; email?: string; retour?: string;
}) {
  try {
    sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
      prenomClient: o.prenom || undefined, nomClient: o.nom || 'Client', emailClient: o.email || undefined,
      sourceAnimalId: o.animalId, clientUid: o.clientUid ?? undefined, clientProfileId: o.clientProfileId ?? undefined,
      notes: `Forfait payé d'avance — ${o.animalNom}`,
      ...(o.retour ? { retour: o.retour } : {}),
      lignes: [{ description: `Forfait ${o.nomForfait} (${o.nbSeances} séance${o.nbSeances > 1 ? 's' : ''}) — ${o.animalNom}`,
        quantite: 1, prixUnitaire: 0, prixTTC: o.prix, tva: 20 }],
    }));
  } catch { /* facture vierge */ }
}
