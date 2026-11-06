// Cocher / décocher une tâche — une seule implémentation, utilisée par
// l'agenda de l'élevage (app/elevage/agenda/page.tsx) et par le tableau de
// bord éleveur (components/EleveurDashboard.tsx). Une tâche cochée reste
// visible (statut « fait »), elle n'est jamais masquée ni supprimée.
// Les RDV vétérinaires (taches_elevage.rdv_veto_cabinet) et les soins des
// protocoles (inscription au carnet) ont leur propre circuit : ne pas les
// valider par ces fonctions.
import { supabase } from '@/lib/supabase';

async function nomAffiche(uid: string, repli: string): Promise<string> {
  const { data } = await supabase.from('user_profiles_complet')
    .select('firstname,lastname,nom,profile_type').eq('uid', uid).eq('is_main', true).maybeSingle();
  if (!data) return repli;
  return data.profile_type === 'eleveur'
    ? (data.nom || repli)
    : (`${data.firstname ?? ''} ${data.lastname ?? ''}`.trim() || repli);
}

/** Tâche manuelle (taches_elevage) : statut a_faire ↔ fait, auteur de la validation, notification au gérant si un autre que lui valide. */
export async function basculerTacheManuelle(
  t: { id: string; titre: string; statut: string; uid_eleveur?: string | null; eleveur_profile_id?: string | null },
  qui: { uid: string; profileId: string | null },
): Promise<'fait' | 'a_faire'> {
  const nouveau = t.statut === 'fait' ? 'a_faire' : 'fait';
  const maj: Record<string, unknown> = nouveau === 'fait'
    ? { statut: nouveau, fait_par: qui.uid, fait_par_profile_id: qui.profileId, fait_a: new Date().toISOString() }
    : { statut: nouveau, fait_par: null, fait_par_profile_id: null, fait_a: null };
  const { error } = await supabase.from('taches_elevage').update(maj).eq('id', t.id);
  if (error) throw error;

  // Notifier l'éleveur quand un employé (ou un cogérant) valide la tâche.
  if (nouveau === 'fait' && t.uid_eleveur && t.uid_eleveur !== qui.uid) {
    try {
      const nomEmploye = await nomAffiche(qui.uid, 'Votre employé');
      await supabase.from('notifications').insert({
        uid: t.uid_eleveur,
        type: 'tache_validee',
        title: 'Tâche validée ✓',
        body: `${nomEmploye} a terminé : ${t.titre}`,
        data: { tacheId: t.id, eleveurUid: t.uid_eleveur },
        read: false,
        ...(t.eleveur_profile_id ? { profile_id: t.eleveur_profile_id } : {}),
      });
    } catch { /* la tâche reste validée */ }
  }
  return nouveau;
}

/** Tâche d'un protocole (plan_taches) : statut en_attente ↔ fait, avec l'auteur de la validation. */
export async function basculerRoutine(
  r: { id: string; statut: string },
  qui: { uid: string; profileId: string | null },
): Promise<'fait' | 'en_attente'> {
  const nouveau = r.statut === 'fait' ? 'en_attente' : 'fait';
  const maj: Record<string, unknown> = nouveau === 'fait'
    ? { statut: nouveau, valide_par: qui.uid, valide_par_profile_id: qui.profileId, valide_at: new Date().toISOString() }
    : { statut: nouveau, valide_par: null, valide_par_profile_id: null, valide_at: null };
  const { error } = await supabase.from('plan_taches').update(maj).eq('id', r.id);
  if (error) throw error;
  return nouveau;
}
