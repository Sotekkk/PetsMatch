// Facture de pension : tarif suggéré d'un séjour (prix par espèce ou ancien
// modèle par poids, réduction long séjour à part pour qu'elle apparaisse sur
// la facture) et séjours des autres animaux du même client sur la même
// période, à facturer ensemble (une section par animal).
// Miroir appli : lib/utils/pension_facture_groupee.dart.
import type { SupabaseClient } from '@supabase/supabase-js';
import { clientDuSejour } from '@/lib/client-pension';
import { pensionPrixNuit, pensionTarifKeyForEspece, pensionTarifPourKey, type TarifsPension } from '@/lib/pension-especes';

type Sejour = Record<string, unknown>;
const t = (v: unknown) => (v == null ? '' : String(v).trim());

/** Nuits du séjour : entrée → sortie effective, sinon prévue, sinon aujourd'hui. */
export function nuitsSejour(e: Sejour): number {
  const debut = t(e.date_entree) ? new Date(t(e.date_entree)) : null;
  if (!debut) return 1;
  const fin = new Date(t(e.date_sortie_effective) || t(e.date_sortie_prevue) || new Date().toISOString());
  return Math.max(1, Math.round((fin.getTime() - debut.getTime()) / 86400000));
}

/** Prix par nuit (plein tarif) et réduction long séjour (%) — null si aucun tarif configuré. */
export async function tarifPensionSuggere(sb: SupabaseClient, e: Sejour, config: TarifsPension | null, nuits: number)
  : Promise<{ prixNuit: number; reductionPct: number } | null> {
  if (!config || typeof config !== 'object') return null;
  const seul = e.seul_dans_logement !== false;
  let prixNuit = 0;
  if (Array.isArray(config.especes) && config.especes.length > 0) {
    const key = pensionTarifKeyForEspece(e.espece as string | null | undefined);
    if (!key) return null;
    const match = pensionTarifPourKey(config.especes, key);
    if (!match) return null;
    // Équidés : box ou pré selon le type du logement occupé.
    let typeLogement: string | null = null;
    if (t(e.logement_id)) {
      const { data: lg } = await sb.from('enclos_chenil').select('type').eq('id', t(e.logement_id)).maybeSingle();
      typeLogement = (lg as { type?: string | null } | null)?.type ?? null;
    }
    prixNuit = pensionPrixNuit(match, { seul, hebergement: typeLogement });
  } else if (Array.isArray(config.tranches_poids) && config.tranches_poids.length > 0) {
    // Rétro-compat : ancien modèle tranches de poids.
    const tranches = config.tranches_poids;
    let poids: number | undefined;
    if (t(e.animal_id)) {
      const { data: animal } = await sb.from('animaux').select('poids').eq('id', t(e.animal_id)).maybeSingle();
      poids = (animal as { poids?: number } | null)?.poids ?? undefined;
    }
    const tranche = tranches.find(x => poids == null || x.poids_max == null || poids <= x.poids_max) ?? tranches[tranches.length - 1];
    prixNuit = (seul ? tranche.prix_seul : tranche.prix_partage) ?? 0;
  } else return null;
  let reductionPct = 0;
  for (const r of (config.reductions_long_sejour ?? [])) {
    if (nuits >= (r.min_nuits ?? 0)) reductionPct = r.pourcentage ?? 0;
  }
  return { prixNuit, reductionPct };
}

/** Séjours déjà facturés (facture rattachée au séjour, ou ligne d'une facture
 *  groupée) ; `avecAcomptes` : une facture d'acompte compte aussi. */
export async function sejoursFactures(sb: SupabaseClient, proProfileId: string, avecAcomptes = true): Promise<Set<string>> {
  const { data } = await sb.from('factures').select('source_pension_entree_id, lignes, statut, type_facture')
    .eq('profile_id', proProfileId).not('source_pension_entree_id', 'is', null);
  const ids = new Set<string>();
  for (const f of (data ?? []) as Sejour[]) {
    if (f.statut === 'annulee' || f.type_facture === 'avoir' || (!avecAcomptes && f.type_facture === 'acompte')) continue;
    ids.add(t(f.source_pension_entree_id));
    for (const l of (Array.isArray(f.lignes) ? f.lignes : []) as Sejour[]) if (t(l.pensionEntreeId)) ids.add(t(l.pensionEntreeId));
  }
  return ids;
}

/**
 * Autres séjours du même client qui chevauchent celui-ci (même pension),
 * pas encore facturés : proposés pour une facture groupée.
 */
export async function sejoursMemeClient(sb: SupabaseClient, e: Sejour, proProfileId: string): Promise<Sejour[]> {
  const debut = t(e.date_entree).slice(0, 10);
  const fin = (t(e.date_sortie_effective) || t(e.date_sortie_prevue) || new Date().toISOString()).slice(0, 10);
  if (!debut) return [];
  const { data } = await sb.from('pension_entrees').select('*').eq('pro_profile_id', proProfileId).neq('id', t(e.id))
    .lte('date_entree', fin);
  const candidats = ((data ?? []) as Sejour[]).filter(x => {
    const xFin = (t(x.date_sortie_effective) || t(x.date_sortie_prevue) || new Date().toISOString()).slice(0, 10);
    return xFin >= debut;
  });
  if (candidats.length === 0) return [];
  const [client, factures] = await Promise.all([clientDuSejour(sb, e), sejoursFactures(sb, proProfileId, false)]);
  const nom = t(e.proprietaire_nom).toLowerCase();
  const res: Sejour[] = [];
  for (const x of candidats) {
    if (factures.has(t(x.id))) continue;
    const c = await clientDuSejour(sb, x);
    const meme = client.uid
      ? c.uid === client.uid && (!client.profileId || !c.profileId || c.profileId === client.profileId)
      : !c.uid && !!nom && t(x.proprietaire_nom).toLowerCase() === nom;
    if (meme) res.push(x);
  }
  return res;
}
