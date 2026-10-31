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
