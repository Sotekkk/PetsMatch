// Liens sécurisés par document (migration_liens_documents.sql) — côté serveur
// uniquement (clé de service). Un lien n'ouvre que son document ; il expire
// (7 jours par défaut) et se révoque ; chaque ouverture est tracée.
// Droits : un membre de la clinique auteure du document (titulaire, cogérant
// actif, employé actif du profil) crée, liste et révoque les liens.

import { createHash, randomBytes } from 'crypto';
import { admin } from '@/lib/galeries-server';

/** Bucket + chemin d'une URL de stockage Supabase (…/object/public|sign/<bucket>/<chemin>). */
export function cibleStockage(url: string): { bucket: string; chemin: string } | null {
  const m = /\/storage\/v1\/object\/(?:public|sign|authenticated)\/([^/]+)\/([^?]+)/.exec(url);
  return m ? { bucket: m[1], chemin: decodeURIComponent(m[2]) } : null;
}

/** L'utilisateur travaille pour ce compte pro (titulaire, cogérant, employé actif du profil). */
export async function accesClinique(uid: string, proUid: string, profileId: string | null): Promise<boolean> {
  if (uid === proUid) return true;
  const [{ data: cog }, { data: emp }] = await Promise.all([
    admin.from('elevage_cogerants').select('elevage_profile_id').eq('uid_gerant', proUid).eq('uid_cogerant', uid)
      .eq('statut', 'actif').is('date_fin', null),
    admin.from('employes').select('eleveur_profile_id').eq('uid_eleveur', proUid).eq('uid_employe', uid).eq('actif', true),
  ]);
  const ok = (rows: { [k: string]: unknown }[] | null, col: string) =>
    (rows ?? []).some(r => !profileId || r[col] == null || String(r[col]) === profileId);
  return ok(cog as { [k: string]: unknown }[] | null, 'elevage_profile_id') || ok(emp as { [k: string]: unknown }[] | null, 'eleveur_profile_id');
}

/** Clinique auteure d'un document médical référencé par son URL (ordonnance,
 *  compte rendu, CR d'intervention, consignes), ou d'un PDF produit à la
 *  demande pour un compte rendu ([crId]) et déposé par l'utilisateur. */
export async function cliniqueDuDocument(url: string, uid: string, crId?: string | null):
  Promise<{ proUid: string; profileId: string | null; animalId: string | null } | null> {
  const [o, c, ch] = await Promise.all([
    admin.from('ordonnances').select('pro_uid, pro_profile_id, animal_id, statut').eq('doc_url', url).limit(1).maybeSingle(),
    admin.from('comptes_rendus').select('pro_uid, pro_profile_id, animal_id').eq('doc_url', url).limit(1).maybeSingle(),
    admin.from('chirurgies').select('pro_uid, pro_profile_id, animal_id')
      .or(`preop_doc_url.eq."${url}",operatoire_doc_url.eq."${url}",consignes_doc_url.eq."${url}"`).limit(1).maybeSingle(),
  ]);
  if (o.data && o.data.statut !== 'brouillon') return { proUid: String(o.data.pro_uid), profileId: o.data.pro_profile_id ?? null, animalId: o.data.animal_id ?? null };
  if (c.data) return { proUid: String(c.data.pro_uid), profileId: c.data.pro_profile_id ?? null, animalId: c.data.animal_id ?? null };
  if (ch.data?.pro_uid) return { proUid: String(ch.data.pro_uid), profileId: ch.data.pro_profile_id ?? null, animalId: ch.data.animal_id ?? null };
  if (crId) {
    // Compte rendu sans PDF stocké : PDF produit et déposé par l'utilisateur lui-même.
    const cible = cibleStockage(url);
    if (!cible) return null;
    const { data: proprio } = await admin.rpc('pm_proprio_fichier', { p_bucket: cible.bucket, p_nom: cible.chemin });
    if (proprio !== uid) return null;
    const { data: cr } = await admin.from('comptes_rendus').select('pro_uid, pro_profile_id, animal_id, statut').eq('id', crId).maybeSingle();
    if (cr && cr.statut !== 'brouillon') return { proUid: String(cr.pro_uid), profileId: cr.pro_profile_id ?? null, animalId: cr.animal_id ?? null };
  }
  return null;
}

export const nouveauJeton = () => randomBytes(24).toString('base64url');
export const empreinte = (x: string) => createHash('sha256').update(`pm-lien|${x}`).digest('hex').slice(0, 32);

/** Message par défaut (personnalisable par le professionnel). */
export function messageParDefaut(animal: string): string {
  return `Bonjour,\n\nVous trouverez les documents relatifs à la prise en charge de ${animal || 'votre animal'}.\n\n`
    + 'Ils comprennent les recommandations et les documents établis par votre vétérinaire.\n\n'
    + 'Nous vous invitons à les conserver et à contacter la clinique si vous avez des questions.\n\n'
    + 'Cordialement,\n\nL’équipe vétérinaire.';
}
