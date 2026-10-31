// Éducateur / comportementaliste : « Prestations & tarifs » est la source
// unique des prix — catalogue `prestations_education` (cours, bilans),
// `forfaits_education`, et options tarifaires sur le profil
// (`tarifs_education.domicile_supplement`, `tarifs_education_extra`).
// Lus par la réservation, la fiche publique et le devis.
// Miroir appli : lib/utils/prestations_education.dart.

import { supabase } from '@/lib/supabase';

export interface PrestationEducation {
  id: string;
  nom: string;
  description: string | null;
  duree_minutes: number;
  prix: number | null;
  /** true = ce cours EST un bilan (proposé en premier aux nouveaux clients). */
  bilan_requis: boolean;
  domicile_ok: boolean;
  type: 'individuel' | 'collectif';
  capacite_max: number | null;
  lieu_adresse?: string | null;
  lieu_lat?: number | null;
  lieu_lng?: number | null;
  /** false = en pause (ni réservable ni affiché). */
  reservable: boolean;
  affiche_public: boolean;
  /** Réservable par un nouveau client même si le bilan est obligatoire. */
  sans_bilan_prealable: boolean;
  conditions: string | null;
}

export const COLS_PRESTATION_EDUCATION =
  'id, nom, description, duree_minutes, prix, bilan_requis, domicile_ok, type, capacite_max, lieu_adresse, lieu_lat, lieu_lng, reservable, affiche_public, sans_bilan_prealable, conditions';

export interface OptionTarifaire { label: string; prix: number; description?: string }

/** Libellé du mode de tarification affiché à côté du prix. */
export function uniteTarif(p: Pick<PrestationEducation, 'type'>): string {
  return p.type === 'collectif' ? 'par participant' : 'par séance';
}

export function typeAffiche(p: Pick<PrestationEducation, 'type' | 'bilan_requis'>): string {
  return p.bilan_requis ? 'Bilan' : p.type === 'collectif' ? 'Collectif' : 'Individuel';
}

/** Supplément à domicile (option tarifaire), 0 si aucun. */
export function supplementDomicile(tarifs: Record<string, number> | null | undefined): number {
  const v = Number(tarifs?.domicile_supplement ?? 0);
  return Number.isFinite(v) && v > 0 ? v : 0;
}

/** Prestations d'un pro (non supprimées), dans l'ordre du catalogue. */
export async function chargerPrestationsEducation(proUid: string, profileId?: string | null,
  opts: { reservablesSeulement?: boolean; publiquesSeulement?: boolean } = {}): Promise<PrestationEducation[]> {
  let q = supabase.from('prestations_education').select(COLS_PRESTATION_EDUCATION)
    .eq('pro_uid', proUid).eq('actif', true);
  if (profileId) q = q.eq('pro_profile_id', profileId);
  if (opts.reservablesSeulement || opts.publiquesSeulement) q = q.eq('reservable', true);
  if (opts.publiquesSeulement) q = q.eq('affiche_public', true);
  const { data } = await q.order('ordre').order('created_at');
  return (data ?? []) as PrestationEducation[];
}

/** Lignes de tarifs de la fiche publique : cours affichés + options. */
export function lignesTarifsPublics(prestations: PrestationEducation[], tarifs: Record<string, number> | null | undefined,
  extra: OptionTarifaire[] | null | undefined): { label: string; prix: string }[] {
  const sup = supplementDomicile(tarifs);
  return [
    ...prestations.filter(p => p.prix != null && p.prix > 0).map(p => ({
      label: `${p.nom} (${p.duree_minutes} min)`,
      prix: `${p.prix} € ${uniteTarif(p)}`,
    })),
    ...(sup > 0 ? [{ label: 'Supplément à domicile', prix: `${sup} €` }] : []),
    ...(extra ?? []).filter(e => e.label?.trim()).map(e => ({
      label: e.description?.trim() ? `${e.label.trim()} — ${e.description.trim()}` : e.label.trim(),
      prix: (e.prix ?? 0) > 0 ? `${e.prix} €` : '—',
    })),
  ];
}

/** Tarif d'une séance à facturer (sans forfait) : le prix figé à la
 *  réservation, sinon celui du cours du catalogue (par id, sinon par nom) +
 *  le supplément à domicile si la séance a lieu chez le client. */
export async function tarifSeanceRdv(rdv: {
  prix_calcule?: number | null; prestation_id?: string | null; motif?: string | null;
  lieu_lat?: number | null; pro_uid?: string | null; pro_profile_id?: string | null;
}, prestationId?: string | null): Promise<number> {
  if (!prestationId && rdv.prix_calcule != null) return Number(rdv.prix_calcule);
  const pid = prestationId ?? rdv.prestation_id;
  type Cours = { prix: number | null; lieu_lat: number | null };
  let p: Cours | null = null;
  if (pid) {
    const { data } = await supabase.from('prestations_education').select('prix, lieu_lat').eq('id', pid).maybeSingle();
    p = data as Cours | null;
  } else if (rdv.motif?.trim() && rdv.pro_uid) {
    let q = supabase.from('prestations_education').select('prix, lieu_lat').eq('pro_uid', rdv.pro_uid).eq('actif', true).eq('nom', rdv.motif.trim());
    if (rdv.pro_profile_id) q = q.eq('pro_profile_id', rdv.pro_profile_id);
    const { data } = await q.limit(1).maybeSingle();
    p = data as Cours | null;
  }
  if (!p?.prix) return 0;
  // À domicile : lieu du RDV = adresse du client (pas le lieu propre du cours).
  const domicile = rdv.lieu_lat != null && p.lieu_lat !== rdv.lieu_lat;
  let sup = 0;
  if (domicile && rdv.pro_profile_id) {
    const { data: pr } = await supabase.from('user_profiles').select('tarifs_education').eq('id', rdv.pro_profile_id).maybeSingle();
    sup = supplementDomicile((pr as { tarifs_education?: Record<string, number> } | null)?.tarifs_education);
  }
  return Number(p.prix) + sup;
}
