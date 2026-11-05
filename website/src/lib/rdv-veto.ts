// Élevage : RDV vétérinaire à venir (cabinet hors PetsMatch). Une tâche d'agenda
// marquée rdv_veto_cabinet ; à la validation, la base crée une visite au carnet
// par animal et la ligne du registre (migration_rdv_veto_taches.sql).
// Miroir appli : lib/utils/rdv_veto.dart.
import { supabase } from '@/lib/supabase';

export const titreRdvVeto = (cabinet: string) => `RDV vétérinaire — ${cabinet.trim()}`;

/** Aujourd'hui, AAAA-MM-JJ en heure locale. */
export const aujourdhuiLocal = () => new Date().toLocaleDateString('sv-SE');

export interface NouveauRdvVeto {
  /** Propriétaire de l'élevage (employé ou cogérant : pas la personne connectée). */
  uid: string; myUid?: string | null; profileId?: string | null;
  animaux: { id: string; nom?: string | null }[];
  date: string; heure: string; cabinet: string; motif?: string; notes?: string;
}

/** Message d'erreur, ou null si tout est prêt. */
export function erreurRdvVeto(r: Pick<NouveauRdvVeto, 'animaux' | 'date' | 'heure' | 'cabinet'>): string | null {
  if (!r.cabinet.trim()) return 'Indiquez le nom du cabinet vétérinaire.';
  if (!r.animaux.length) return 'Sélectionnez au moins un animal.';
  if (!r.date || !r.heure) return 'Indiquez la date et l’heure du RDV.';
  if (new Date(`${r.date}T${r.heure}:00`).getTime() <= Date.now()) return 'Le RDV doit être dans le futur. Pour une visite déjà faite, utilisez « Visite vétérinaire ».';
  return null;
}

export async function creerRdvVeto(r: NouveauRdvVeto): Promise<string | null> {
  const err = erreurRdvVeto(r);
  if (err) return err;
  const employe = !!r.myUid && r.myUid !== r.uid;
  const { error } = await supabase.from('taches_elevage').insert({
    uid_eleveur: r.uid,
    titre: titreRdvVeto(r.cabinet),
    date: r.date, heure: r.heure, statut: 'a_faire', profil_source: 'eleveur',
    notes: r.notes?.trim() || null,
    ...(r.profileId ? { profile_id: r.profileId, eleveur_profile_id: r.profileId } : {}),
    animaux_ids: r.animaux.map(a => a.id),
    animal_id: r.animaux.length === 1 ? r.animaux[0].id : null,
    animal_nom: r.animaux.map(a => a.nom ?? '').filter(Boolean).join(', ') || null,
    rdv_veto_cabinet: r.cabinet.trim(),
    rdv_veto_motif: r.motif?.trim() || null,
    // Employé : la tâche lui est attribuée, il peut la voir et la valider.
    ...(employe ? { assigne_a: r.myUid, assignes_a: [r.myUid] } : {}),
  });
  return error ? `Enregistrement impossible : ${error.message}` : null;
}

export interface TacheRdvVeto {
  id: string | number; date: string; animal_id?: string | null; animal_nom?: string | null;
  animaux_ids?: string[] | null; rdv_veto_cabinet?: string | null; rdv_veto_motif?: string | null;
}

/** Valide le RDV : date réelle et animaux réellement vus ; la base écrit carnet et registre. */
export async function validerRdvVeto(t: TacheRdvVeto, date: string, animaux: { id: string; nom?: string | null }[], faitPar: string, faitParProfil?: string | null): Promise<string | null> {
  if (!animaux.length) return 'Cochez au moins un animal.';
  if (!date || date > aujourdhuiLocal()) return 'La date de la visite ne peut pas être dans le futur.';
  const { error } = await supabase.from('taches_elevage').update({
    statut: 'fait', date,
    animaux_ids: animaux.map(a => a.id),
    animal_id: animaux.length === 1 ? animaux[0].id : null,
    animal_nom: animaux.map(a => a.nom ?? '').filter(Boolean).join(', ') || null,
    fait_par: faitPar, fait_par_profile_id: faitParProfil ?? null, fait_a: new Date().toISOString(),
  }).eq('id', t.id);
  return error ? `Validation impossible : ${error.message}` : null;
}
