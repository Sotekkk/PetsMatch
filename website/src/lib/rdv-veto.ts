// Élevage : RDV vétérinaire à venir (cabinet hors PetsMatch). Une tâche d'agenda
// marquée rdv_veto_cabinet ; à la validation, la base crée une visite au carnet
// par animal et la ligne du registre (migration_rdv_veto_taches.sql).
// Miroir appli : lib/utils/rdv_veto.dart.
import { supabase } from '@/lib/supabase';
import { estHorsPriseEnCharge } from '@/lib/protocoles';

export const titreRdvVeto = (cabinet: string) => `RDV vétérinaire — ${cabinet.trim()}`;

export interface AnimalElevage { id: string; nom: string; espece?: string | null; portee_id?: string | null; nom_mere?: string | null }
export interface PorteeElevage { id: string; label: string; ids: string[] }

/** Animaux présents de CE profil élevage : propriété en cours (animaux_proprietes), ou fiche
 *  de ce profil sans propriété close ; ni adopté / cédé / décédé / sorti, ni fiche client d'un
 *  pro, ni animal d'un autre profil du compte (association…). Miroir appli : utils/rdv_veto.dart. */
export async function animauxPresentsElevage(profileId: string | null | undefined): Promise<AnimalElevage[]> {
  if (!profileId) return [];
  const cols = 'id, nom, espece, portee_id, nom_mere, statut';
  const [{ data: props }, { data: fiches }] = await Promise.all([
    supabase.from('animaux_proprietes').select('animal_id, date_fin, statut').eq('profile_id_proprio', profileId),
    supabase.from('animaux').select(cols).eq('profile_id', profileId),
  ]);
  const lignes = (props ?? []) as { animal_id: string; date_fin: string | null; statut: string | null }[];
  const ouverts = new Set(lignes.filter(p => !p.date_fin && p.statut === 'actif').map(p => String(p.animal_id)));
  const clos = new Set(lignes.filter(p => !!p.date_fin).map(p => String(p.animal_id)));
  type Ligne = AnimalElevage & { statut?: string | null };
  const liste = new Map<string, Ligne>();
  for (const a of (fiches ?? []) as Ligne[]) if (ouverts.has(String(a.id)) || !clos.has(String(a.id))) liste.set(String(a.id), a);
  const manquants = [...ouverts].filter(id => !liste.has(id));
  if (manquants.length) {
    const { data } = await supabase.from('animaux').select(cols).in('id', manquants);
    for (const a of (data ?? []) as Ligne[]) liste.set(String(a.id), a);
  }
  return [...liste.values()]
    .filter(a => !estHorsPriseEnCharge(a) && a.statut !== 'patient_clinique')
    .map(a => ({ ...a, id: String(a.id), nom: a.nom ?? 'Animal' }))
    .sort((a, b) => a.nom.localeCompare(b.nom, 'fr'));
}

/** Portées parmi ces animaux (seulement leurs membres présents). */
export function porteesElevage(animaux: AnimalElevage[]): PorteeElevage[] {
  const parPortee = new Map<string, AnimalElevage[]>();
  for (const a of animaux) if (a.portee_id) parPortee.set(a.portee_id, [...(parPortee.get(a.portee_id) ?? []), a]);
  return [...parPortee.entries()].map(([id, m]) => {
    const mere = m.map(a => a.nom_mere).find(n => !!n);
    return { id, label: mere ? `Portée de ${mere}` : 'Portée', ids: m.map(a => a.id) };
  }).sort((a, b) => a.label.localeCompare(b.label, 'fr'));
}

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
