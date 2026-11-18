// Toiletteur — forfaits « carte de N séances » (18/11/2026), comme le
// pet-sitter / l'éducateur :
//   • catalogue : forfaits_toilettage (Mes prestations) — nom, nombre de
//     séances, prix, prestation couverte (vide = toutes), validité en mois ;
//   • forfait choisi à la réservation (rdv.forfait_id) ou vendu depuis le
//     dossier de la séance → forfaits_souscrits (forfait_toilettage_id),
//     facturé UNE fois (facture_id) ; chaque séance est décomptée
//     (rdv.forfait_souscrit_id) et n'est plus facturée.
// Miroir appli : lib/utils/forfait_toilettage.dart. Migration
// migration_toilettage_forfaits.sql (sans elle : rien ne change).
import { supabase } from '@/lib/supabase';

export interface ForfaitToilettage {
  id: string; pro_uid?: string; pro_profile_id?: string | null; nom: string; prestation_id: string | null;
  nb_seances: number; prix: number; validite_mois: number | null; description: string | null; actif?: boolean;
}

type Souscription = Record<string, unknown> & { id: string };

export interface ForfaitToilettageClient {
  souscription: Souscription;
  id: string; total: number; utilises: number; restants: number;
  nom: string; prix: number; facture: boolean; valideJusquAu: string | null;
}

const eur = (n: number) => `${Number.isInteger(n) ? n : n.toFixed(2).replace('.', ',')} €`;

/** « 5 séances · 200 € · Toilettage complet · valable 6 mois » */
export function resumeForfaitToilettage(f: Pick<ForfaitToilettage, 'nb_seances' | 'prix' | 'validite_mois'>, prestationNom?: string): string {
  const n = Number(f.nb_seances) || 0;
  return [
    `${n} séance${n > 1 ? 's' : ''}`, eur(Number(f.prix) || 0),
    prestationNom || 'toutes prestations',
    ...(f.validite_mois && f.validite_mois > 0 ? [`valable ${f.validite_mois} mois`] : []),
  ].join(' · ');
}

export function libelleForfaitClient(f: ForfaitToilettageClient): string {
  return `${f.nom} · ${f.restants} séance${f.restants > 1 ? 's' : ''} restante${f.restants > 1 ? 's' : ''} sur ${f.total}`;
}

export async function forfaitsToilettageCatalogue(proProfileId: string | null | undefined): Promise<ForfaitToilettage[]> {
  if (!proProfileId) return [];
  const { data, error } = await supabase.from('forfaits_toilettage').select('*')
    .eq('pro_profile_id', proProfileId).eq('actif', true).order('created_at');
  return error ? [] : (data ?? []) as ForfaitToilettage[];
}

async function recompter(fsId: string, total: number): Promise<number> {
  const { data } = await supabase.from('rdv').select('id').eq('forfait_souscrit_id', fsId).not('statut', 'in', '(annule,refuse)');
  const n = (data ?? []).length;
  await supabase.from('forfaits_souscrits').update({
    nb_seances_utilisees: n, statut: n >= total ? 'termine' : 'actif', termine_le: n >= total ? new Date().toISOString() : null,
  }).eq('id', fsId);
  return n;
}

type Rdv = {
  id: string; statut?: string; date_heure?: string; prestation_id?: string | null; forfait_id?: string | null;
  forfait_souscrit_id?: string | null; forfait_exclu?: boolean | null; client_uid?: string | null; client_profile_id?: string | null;
  pro_uid?: string; pro_profile_id?: string | null; animal_id?: string | null;
};

function couvre(fs: Souscription, rdv: Rdv): boolean {
  const p = String(fs.prestation_toilettage_id ?? '');
  if (p && p !== String(rdv.prestation_id ?? '')) return false;
  const fin = fs.valide_jusqu_au ? String(fs.valide_jusqu_au) : '';
  const jour = rdv.date_heure ? new Date(rdv.date_heure) : new Date();
  const j = `${jour.getFullYear()}-${String(jour.getMonth() + 1).padStart(2, '0')}-${String(jour.getDate()).padStart(2, '0')}`;
  return !fin || j <= fin;
}

function client(fs: Souscription, utilises: number): ForfaitToilettageClient {
  const total = Number(fs.nb_seances_total) || 0;
  return {
    souscription: fs, id: fs.id, total, utilises, restants: Math.max(0, total - utilises),
    nom: String(fs.nom_snapshot ?? 'Forfait'), prix: Number(fs.prix_snapshot) || 0,
    facture: !!fs.facture_id, valideJusquAu: fs.valide_jusqu_au ? String(fs.valide_jusqu_au) : null,
  };
}

async function souscrire(f: ForfaitToilettage, rdv: Rdv): Promise<Souscription> {
  const debut = rdv.date_heure ? new Date(rdv.date_heure) : new Date();
  const fin = f.validite_mois && f.validite_mois > 0 ? new Date(debut.getFullYear(), debut.getMonth() + f.validite_mois, debut.getDate()) : null;
  const { data, error } = await supabase.from('forfaits_souscrits').insert({
    forfait_toilettage_id: f.id,
    ...(f.prestation_id ? { prestation_toilettage_id: f.prestation_id } : {}),
    pro_uid: rdv.pro_uid, pro_profile_id: rdv.pro_profile_id,
    ...(rdv.client_uid ? { client_uid: rdv.client_uid } : {}),
    ...(rdv.client_profile_id ? { client_profile_id: rdv.client_profile_id } : {}),
    ...(rdv.animal_id ? { animal_id: rdv.animal_id } : {}),
    nom_snapshot: f.nom || 'Forfait', nb_seances_total: Number(f.nb_seances) || 1, prix_snapshot: f.prix,
    ...(fin ? { valide_jusqu_au: `${fin.getFullYear()}-${String(fin.getMonth() + 1).padStart(2, '0')}-${String(fin.getDate()).padStart(2, '0')}` } : {}),
  }).select().single();
  if (error) throw new Error(error.message);
  return data as Souscription;
}

const COLS = 'id, statut, date_heure, prestation_id, forfait_id, forfait_souscrit_id, forfait_exclu, client_uid, client_profile_id, pro_uid, pro_profile_id, animal_id';

/** Carte du client pour ce RDV : celle déjà rattachée, sinon une carte en cours
 *  qui couvre la séance, sinon celle choisie à la réservation (achetée
 *  maintenant). Idempotent : appelé à l'ouverture du dossier. */
export async function rattacherForfaitToilettage(rdvId: string): Promise<ForfaitToilettageClient | null> {
  try {
    const { data: x, error } = await supabase.from('rdv').select(COLS).eq('id', rdvId).maybeSingle();
    if (error || !x) return null;
    const rdv = x as Rdv;
    let fs: Souscription | null = null;
    if (rdv.forfait_souscrit_id) {
      const { data } = await supabase.from('forfaits_souscrits').select('*').eq('id', rdv.forfait_souscrit_id)
        .not('forfait_toilettage_id', 'is', null).maybeSingle();
      if (!data) return null; // forfait d'un autre métier
      fs = data as Souscription;
    } else {
      const pid = rdv.pro_profile_id ?? '';
      if (!pid || (!rdv.client_profile_id && !rdv.client_uid)) return null;
      if (rdv.statut === 'annule' || rdv.statut === 'refuse' || rdv.forfait_exclu) return null;
      let q = supabase.from('forfaits_souscrits').select('*').eq('pro_profile_id', pid).not('forfait_toilettage_id', 'is', null).eq('statut', 'actif');
      q = rdv.client_profile_id ? q.eq('client_profile_id', rdv.client_profile_id) : q.eq('client_uid', rdv.client_uid as string);
      const { data: ss } = await q.order('souscrit_le');
      for (const s of (ss ?? []) as Souscription[]) {
        if (!couvre(s, rdv)) continue;
        const total = Number(s.nb_seances_total) || 0;
        if (await recompter(s.id, total) < total) { fs = s; break; }
      }
      if (!fs && rdv.forfait_id) {
        const { data: f } = await supabase.from('forfaits_toilettage').select('*').eq('id', rdv.forfait_id).maybeSingle();
        if (f) fs = await souscrire(f as ForfaitToilettage, rdv);
      }
      if (!fs) return null;
      await supabase.from('rdv').update({ forfait_souscrit_id: fs.id }).eq('id', rdv.id);
    }
    return client(fs, await recompter(fs.id, Number(fs.nb_seances_total) || 0));
  } catch {
    // Migration pas encore passée : rien à décompter.
    return null;
  }
}

/** Vend une carte depuis le dossier : la séance du RDV est la première décomptée. */
export async function vendreForfaitToilettage(rdvId: string, f: ForfaitToilettage): Promise<ForfaitToilettageClient> {
  const { data: x, error } = await supabase.from('rdv').select(COLS).eq('id', rdvId).single();
  if (error || !x) throw new Error(error?.message ?? 'Rendez-vous introuvable');
  const fs = await souscrire(f, x as Rdv);
  await supabase.from('rdv').update({ forfait_souscrit_id: fs.id, forfait_id: f.id, forfait_exclu: false }).eq('id', rdvId);
  return client(fs, await recompter(fs.id, Number(fs.nb_seances_total) || 0));
}

/** La séance n'est plus décomptée de la carte (facturée à part). */
export async function detacherForfaitToilettage(rdvId: string, f: ForfaitToilettageClient): Promise<void> {
  await supabase.from('rdv').update({ forfait_souscrit_id: null, forfait_id: null, forfait_exclu: true }).eq('id', rdvId);
  await recompter(f.id, f.total);
}
