// Équipe vétérinaire (ASV + praticiens) — miroir de l'appli
// (employes_page.dart : kRolesVeto, kDroitsParRoleVeto, controleFormuleVeto ;
// migration_clinique_equipe.sql). Tout est scopé au PROFIL clinique.
import { supabase } from '@/lib/supabase';

export const ROLES_VETO = [
  { key: 'asv', label: 'Assistant(e) vétérinaire', icon: '🧑‍⚕️' },
  { key: 'veterinaire', label: 'Vétérinaire praticien', icon: '🩺' },
] as const;
export type RoleVeto = typeof ROLES_VETO[number]['key'];

export const DROITS_PAR_ROLE_VETO: Record<RoleVeto, string[]> = {
  asv: ['vet_agenda', 'vet_patients', 'vet_cr_rediger'],
  veterinaire: ['vet_agenda', 'vet_patients', 'vet_cr_rediger', 'vet_cr_valider', 'vet_ordonnances'],
};

export const PERMS_VETO = [
  { key: 'vet_agenda', label: 'Agenda de la clinique', desc: 'Voir, prendre, déplacer et accepter les rendez-vous' },
  { key: 'vet_rdv_demandes', label: 'Demandes de RDV', desc: "Être notifié(e) de chaque nouvelle demande de rendez-vous (avec l'agenda pour l'accepter)" },
  { key: 'vet_patients', label: 'Patients', desc: 'Fiches et carnets de santé partagés avec la clinique' },
  { key: 'vet_cr_rediger', label: 'Rédiger des comptes rendus', desc: 'Brouillons, à valider par un vétérinaire' },
  { key: 'vet_cr_valider', label: 'Valider les comptes rendus', desc: 'Envoyer au propriétaire (vétérinaire uniquement)' },
  { key: 'vet_ordonnances', label: 'Ordonnances', desc: 'Prescrire (vétérinaire uniquement)' },
];

export function libelleRoleVeto(role?: string | null): string {
  return role === 'veterinaire' ? 'Vétérinaire' : role === 'asv' ? 'ASV' : 'Employé';
}

const MAX_PRATICIENS: Record<string, number> = { free: 1, avance: 1, clinique: 5 };

/** Formule vétérinaire active (plans gérés par profil_type). */
export async function planVeto(uid: string): Promise<string> {
  const { data } = await supabase.from('abonnements')
    .select('plan_code').eq('uid', uid).eq('profil_type', 'veterinaire').eq('statut', 'actif')
    .order('created_at', { ascending: false }).limit(1).maybeSingle();
  return (data?.plan_code as string | undefined) ?? 'free';
}

/** ASV dès « Avancé », praticiens en « Clinique » (gérant compris dans la
 *  limite). null = autorisé, sinon message à afficher. */
export async function controleFormuleVeto(uid: string, cliniqueProfileId: string, role: RoleVeto): Promise<string | null> {
  const code = await planVeto(uid);
  if (code === 'free') return "La gestion d'équipe est disponible à partir de la formule Avancé.";
  if (role === 'veterinaire') {
    if (code !== 'clinique') return 'Ajouter des vétérinaires praticiens nécessite la formule Clinique.';
    const max = MAX_PRATICIENS[code] ?? 5;
    const { count } = await supabase.from('employes').select('id', { count: 'exact', head: true })
      .eq('eleveur_profile_id', cliniqueProfileId).eq('actif', true).eq('role_pro', 'veterinaire');
    if ((count ?? 0) >= max - 1) return `Limite de ${max} praticiens (vous compris) atteinte pour votre formule.`;
  }
  return null;
}

/** Pose les droits par défaut du rôle (remplace les droits vet_*). */
export async function appliquerDroitsRoleVeto(cliniqueProfileId: string, employeProfileId: string, role: RoleVeto) {
  await supabase.from('employe_permissions').delete()
    .eq('eleveur_profile_id', cliniqueProfileId).eq('employe_profile_id', employeProfileId)
    .like('permission', 'vet_%');
  await supabase.from('employe_permissions').insert(
    DROITS_PAR_ROLE_VETO[role].map(permission => ({
      eleveur_profile_id: cliniqueProfileId, employe_profile_id: employeProfileId, permission,
    })),
  );
}
