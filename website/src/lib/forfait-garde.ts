// Pet-sitter — forfaits achetés (packs de visites, promenades ou jours de
// garde) et acomptes (13/11/2026), comme le comportementaliste :
//   • forfait choisi à la réservation → forfaits_souscrits (forfait_garde_id),
//     facturé UNE fois à l'achat (facture_id) ; chaque passage est décompté
//     (rdv.forfait_souscrit_id) et n'est plus facturé ; les gardes suivantes
//     du client puisent dans le forfait tant qu'il en reste ;
//   • acompte rattaché à la garde (factures.acompte_rdv_id), déduit de la
//     facture finale.
// Miroir appli : lib/utils/forfait_garde.dart. Migration
// migration_garde_acompte_forfaits.sql (sans elle : comportement d'avant).
import { supabase } from '@/lib/supabase';

export function typeGardeRdv(motif?: string | null): string {
  const m = (motif ?? '').toLowerCase();
  if (m.includes('promenade') || m.includes('balade')) return 'promenade';
  if (m.includes('garde') && m.includes('journ')) return 'garde_journee';
  return 'visite';
}

export function uniteForfaitGarde(type?: string | null, pluriel = true): string {
  if (type === 'promenade') return pluriel ? 'promenades' : 'promenade';
  if (type === 'garde_journee') return pluriel ? 'jours de garde' : 'jour de garde';
  return pluriel ? 'visites' : 'visite';
}

type Souscription = Record<string, unknown> & { id: string };

export interface ForfaitGardeClient {
  souscription: Souscription;
  total: number; utilises: number;
  /** À facturer (vient d'être acheté ou pas encore facturé). */
  aFacturer: boolean;
  couverts: string[];
  nom: string; prix: number; type: string; factureId: string | null;
}

async function recompter(fsId: string, total: number): Promise<number> {
  const { data } = await supabase.from('rdv').select('id').eq('forfait_souscrit_id', fsId).not('statut', 'in', '(annule,refuse)');
  const n = (data ?? []).length;
  await supabase.from('forfaits_souscrits').update({
    nb_seances_utilisees: n, statut: n >= total ? 'termine' : 'actif',
    ...(n >= total ? { termine_le: new Date().toISOString() } : {}),
  }).eq('id', fsId);
  return n;
}

/** Rattache les passages de la garde au forfait du client (en cours du même
 *  type, sinon celui choisi à la réservation, créé). Idempotent. */
export async function rattacherForfaitGarde(ids: string[]): Promise<ForfaitGardeClient | null> {
  if (!ids.length) return null;
  try {
    const { data: rows, error } = await supabase.from('rdv')
      .select('id, statut, motif, forfait_id, forfait_souscrit_id, est_essai, client_uid, client_profile_id, pro_uid, pro_profile_id, animal_id')
      .in('id', ids).order('date_heure');
    if (error || !rows?.length) return null;
    type R = { id: string; statut?: string; motif?: string | null; forfait_id?: string | null; forfait_souscrit_id?: string | null;
      est_essai?: boolean | null; client_uid?: string | null; client_profile_id?: string | null; pro_uid?: string; pro_profile_id?: string | null; animal_id?: string | null };
    const rdvs = rows as R[];
    const first = rdvs[0];
    const pid = first.pro_profile_id ?? '';
    const cpid = first.client_profile_id ?? '';
    const cuid = first.client_uid ?? '';
    if (!pid || (!cpid && !cuid)) return null;
    const type = typeGardeRdv(first.motif);

    const souscriptions = async (id?: string): Promise<Souscription[]> => {
      let q = supabase.from('forfaits_souscrits').select('*').eq('pro_profile_id', pid).not('forfait_garde_id', 'is', null);
      q = id ? q.eq('id', id) : cpid ? q.eq('client_profile_id', cpid) : q.eq('client_uid', cuid);
      const { data, error: e } = await q.order('souscrit_le');
      if (e) throw e;
      return (data ?? []) as Souscription[];
    };

    const deja = rdvs.map(r => r.forfait_souscrit_id ?? '').find(Boolean) ?? '';
    let fs: Souscription | null = null;
    let nouveau = false;
    if (deja) fs = (await souscriptions(deja))[0] ?? null;
    else {
      for (const s of await souscriptions()) {
        if (s.statut !== 'actif' || ((s.type_prestation_garde as string | null) ?? 'visite') !== type) continue;
        const total = Number(s.nb_seances_total) || 0;
        if (await recompter(s.id, total) < total) { fs = s; break; }
      }
      if (!fs && first.forfait_id) {
        const { data: f } = await supabase.from('forfaits_garde').select('*').eq('id', first.forfait_id).maybeSingle();
        if (f) {
          const { data: cree, error: e } = await supabase.from('forfaits_souscrits').insert({
            forfait_garde_id: first.forfait_id, type_prestation_garde: (f.type_prestation as string | null) ?? type,
            pro_uid: first.pro_uid, pro_profile_id: pid,
            ...(cuid ? { client_uid: cuid } : {}), ...(cpid ? { client_profile_id: cpid } : {}),
            ...(first.animal_id ? { animal_id: String(first.animal_id) } : {}),
            nom_snapshot: f.nom ?? 'Forfait', nb_seances_total: Number(f.nb_visites) || 1, prix_snapshot: f.prix,
          }).select().single();
          if (e) throw e;
          fs = cree as Souscription;
          nouveau = true;
        }
      }
    }
    if (!fs) return null;
    const total = Number(fs.nb_seances_total) || 0;
    let utilises = await recompter(fs.id, total);
    const aRattacher: string[] = [];
    for (const r of rdvs) {
      if (r.forfait_souscrit_id || r.est_essai || r.statut === 'annule' || r.statut === 'refuse') continue;
      if (utilises + aRattacher.length >= total) break;
      aRattacher.push(r.id);
    }
    if (aRattacher.length) {
      await supabase.from('rdv').update({ forfait_souscrit_id: fs.id }).in('id', aRattacher);
      utilises = await recompter(fs.id, total);
    }
    const fsId = fs.id;
    const factureId = (fs.facture_id as string | null) ?? null;
    return {
      souscription: fs, total, utilises, aFacturer: nouveau || !factureId,
      couverts: rdvs.filter(r => r.forfait_souscrit_id === fsId || aRattacher.includes(r.id)).map(r => r.id),
      nom: String(fs.nom_snapshot ?? 'Forfait'), prix: Number(fs.prix_snapshot) || 0,
      type: (fs.type_prestation_garde as string | null) ?? 'visite', factureId,
    };
  } catch {
    return null; // migration pas encore passée
  }
}

/** Acomptes (non annulés) demandés pour cette garde. */
export async function acomptesGarde(ids: string[]): Promise<{ id: string; numero_affichage?: string | null; total_ttc?: number | null; statut?: string }[]> {
  if (!ids.length) return [];
  const { data, error } = await supabase.from('factures').select('id, numero_affichage, total_ttc, statut')
    .in('acompte_rdv_id', ids).eq('type_facture', 'acompte').neq('statut', 'annulee').order('created_at');
  return error ? [] : (data ?? []) as { id: string; numero_affichage?: string | null; total_ttc?: number | null; statut?: string }[];
}

/** Lignes de déduction (TTC négatif) des acomptes de la garde. */
export async function deductionsAcompteGarde(ids: string[]) {
  return (await acomptesGarde(ids)).map(a => ({
    description: `Acompte versé — facture ${a.numero_affichage ?? ''}`.trim(),
    quantite: 1, prixUnitaire: 0, prixTTC: -(Number(a.total_ttc) || 0), tva: 20, commune: true,
  }));
}
