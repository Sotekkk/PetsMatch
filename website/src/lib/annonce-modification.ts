// Modification / renouvellement d'annonce publiée (serveur uniquement).
// Règles (migration_annonces_modif_payante.sql) :
//   • gratuit : photos, statut, statut et photos des chiots ;
//   • verrouillé (annonces) : espèce, race, sexe, type, parents, naissance ;
//   • payant (4,99 €) : tout le reste — 1 modification = 1 paiement — et le
//     renouvellement (+30 jours).
// Utilisé par /api/annonces/modifier (tri + paiement) et le webhook Stripe
// (application au paiement).

import { createClient } from '@supabase/supabase-js';

export const supabaseService = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

export type TableAnnonce = 'annonces' | 'annonces_objets';

/** Jamais modifiés via une modification (techniques, gérés ailleurs). */
const TECHNIQUES = new Set([
  'id', 'uid', 'uid_eleveur', 'profile_id', 'profil_source', 'created_at', 'updated_at', 'vues', 'contacts',
  'is_suspect', 'suspect_reasons', 'boost_until', 'paiement_statut', 'expires_at', 'lat', 'lng', 'latitude', 'longitude',
]);
/** Verrouillés après publication (annonces d'animaux). */
const VERROUILLES = new Set([
  'espece', 'espece_autre', 'race', 'sexe', 'type', 'type_vente', 'date_naissance',
  'mere_animal_id', 'mere_nom', 'mere_puce', 'mere_photo_url', 'mere_race', 'mere_lof',
  'pere_animal_id', 'pere_nom', 'pere_puce', 'pere_photo_url', 'pere_race', 'pere_lof',
  'etalon_animal_id',
]);
const LIBRES = new Set(['statut', 'photos']);
const CHIOT_VERROUILLES = ['sexe', 'race', 'espece', 'animalId', 'id'];

const expiree = (a: Record<string, unknown>) => !!a.expires_at && new Date(String(a.expires_at)).getTime() < Date.now();
/** Valeur comparable : '' = null, nombre en texte = nombre (pas de paiement
 *  pour « 350 » vs 350). Même règle que l'appli (annonce_paiement.dart). */
function norm(v: unknown): unknown {
  if (v === null || v === undefined) return null;
  if (typeof v === 'string') {
    const t = v.trim();
    if (!t) return null;
    const n = Number(t.replace(',', '.'));
    return Number.isFinite(n) ? n : t;
  }
  if (Array.isArray(v)) return v.map(norm);
  if (typeof v === 'object') {
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(v as object).sort()) {
      const x = norm((v as Record<string, unknown>)[k]);
      if (x !== null) out[k] = x;
    }
    return out;
  }
  return v;
}
const egal = (a: unknown, b: unknown) => JSON.stringify(norm(a)) === JSON.stringify(norm(b));
const sansLibres = (portee: unknown) => Array.isArray(portee)
  ? portee.map(e => { const { statut: _s, photos: _p, ...r } = (e ?? {}) as Record<string, unknown>; void _s; void _p; return r; })
  : [];

/** Chiots : sexe / race / espèce / lien fiche repris de l'annonce publiée. */
function verrouillerChiots(nouveau: unknown, ancien: unknown): unknown {
  if (!Array.isArray(nouveau)) return nouveau;
  const old = Array.isArray(ancien) ? ancien as Record<string, unknown>[] : [];
  return nouveau.map((e, i) => {
    const n = { ...(e as Record<string, unknown>) };
    const o = old.find(x => (n.animalId && x.animalId === n.animalId) || (n.id && x.id === n.id)) ?? old[i];
    if (o) for (const k of CHIOT_VERROUILLES) if (k in o) n[k] = o[k];
    return n;
  });
}

/** Tri des changements demandés par rapport à l'annonce actuelle. */
export function trierChangements(table: TableAnnonce, actuel: Record<string, unknown>, demande: Record<string, unknown>) {
  const libres: Record<string, unknown> = {};
  const payants: Record<string, unknown> = {};
  for (const [k, v0] of Object.entries(demande)) {
    if (TECHNIQUES.has(k) || k.endsWith('_eleveur')) continue;
    if (table === 'annonces' && VERROUILLES.has(k)) continue;
    const v = k === 'animaux_portee' ? verrouillerChiots(v0, actuel[k]) : v0;
    if (egal(v, actuel[k])) continue;
    // Une annonce expirée ne revient en ligne que par un renouvellement.
    if (k === 'statut' && expiree(actuel) && ['disponible', 'reserve'].includes(String(v))) continue;
    if (LIBRES.has(k) || (k === 'animaux_portee' && egal(sansLibres(v), sansLibres(actuel[k])))) libres[k] = v;
    else payants[k] = v;
  }
  return { libres, payants };
}

/** Propriétaire de l'annonce (ou cogérant actif de l'élevage). */
export async function estProprietaire(table: TableAnnonce, row: Record<string, unknown>, uid: string) {
  const owner = String((table === 'annonces' ? row.uid_eleveur : row.uid) ?? '');
  if (owner === uid) return true;
  if (table !== 'annonces' || !owner) return false;
  const { data } = await supabaseService.from('elevage_cogerants').select('id')
    .eq('uid_gerant', owner).eq('uid_cogerant', uid).eq('statut', 'actif').is('date_fin', null).limit(1).maybeSingle();
  return !!data;
}

/** Applique une modification payée (webhook). Idempotent. */
export async function appliquerModification(modificationId: string, sessionId?: string | null) {
  const { data: m } = await supabaseService.from('annonces_modifications').select('*')
    .eq('id', modificationId).maybeSingle();
  if (!m || m.statut !== 'attente') return;
  const table = m.table_source as TableAnnonce;
  if (m.action === 'renouvellement') {
    const { data: a } = await supabaseService.from(table).select('expires_at, statut').eq('id', m.annonce_id).maybeSingle();
    const base = Math.max(Date.now(), a?.expires_at ? new Date(a.expires_at as string).getTime() : 0);
    const maj: Record<string, unknown> = { expires_at: new Date(base + 30 * 86400000).toISOString() };
    if (!a?.statut || ['expire', 'expiree', 'pause'].includes(String(a.statut)) || (a?.expires_at && new Date(a.expires_at as string).getTime() < Date.now())) {
      if (!['vendu', 'supprime'].includes(String(a?.statut ?? ''))) maj.statut = 'disponible';
    }
    await supabaseService.from(table).update(maj).eq('id', m.annonce_id);
  } else {
    // Re-filtre au moment de l'application (jamais de champ verrouillé).
    const { data: a } = await supabaseService.from(table).select('*').eq('id', m.annonce_id).maybeSingle();
    if (a) {
      const { libres, payants } = trierChangements(table, a, m.changements as Record<string, unknown>);
      const maj = { ...libres, ...payants };
      if (Object.keys(maj).length) await supabaseService.from(table).update(maj).eq('id', m.annonce_id);
    }
  }
  await supabaseService.from('annonces_modifications').update({
    statut: 'appliquee', appliquee_le: new Date().toISOString(), ...(sessionId ? { stripe_session_id: sessionId } : {}),
  }).eq('id', modificationId);
}
