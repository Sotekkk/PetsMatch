// Reproducteurs éligibles à une NOUVELLE saillie / portée.
// Miroir appli : lib/utils/reproducteurs.dart — garder les deux synchronisés.
// Contrôle serveur : supabase/migration_saillies_reproducteurs_eligibles.sql.
//
// Règle : sexe demandé + case « Reproducteur » cochée sur la fiche + présent
// dans le cheptel (non cédé, non décédé, pas en cours de cession) + ni
// retraité, ni stérilisé. Le statut commercial (réservé…) n'entre pas en jeu.
// Les historiques (saillies passées) gardent leurs reproducteurs tels quels.

import { supabase } from './supabase';

export const STATUTS_HORS_CHEPTEL = ['sorti', 'decede', 'en_attente_cession', 'cession_en_cours', 'adopte', 'transfere'];

type AnimalRepro = { reproducteur?: boolean | null; is_retraite?: boolean | null; sterilise?: boolean | null; statut?: string | null };

export function estReproducteurEligible(a: AnimalRepro): boolean {
  return a.reproducteur === true && a.is_retraite !== true && a.sterilise !== true
    && !STATUTS_HORS_CHEPTEL.includes(a.statut ?? '');
}

/** Raison lisible de l'inéligibilité (null si éligible). */
export function raisonNonEligible(a: AnimalRepro): string | null {
  const statut = a.statut ?? '';
  if (statut === 'decede') return 'animal décédé';
  if (STATUTS_HORS_CHEPTEL.includes(statut)) return 'animal cédé ou en cours de cession';
  if (a.is_retraite === true) return 'reproducteur retraité';
  if (a.sterilise === true) return 'animal stérilisé';
  if (a.reproducteur !== true) return 'case « Reproducteur » non cochée sur la fiche';
  return null;
}

export interface Reproducteur {
  id: string | null;           // null pour un reproducteur extérieur saisi
  nom: string;
  race?: string | null;
  identification?: string | null;
  source: 'elevage' | 'historique' | 'reseau';
}

export const SELECT_REPRO = 'id, nom, nom_pedigree, race, identification, statut, reproducteur, is_retraite, sterilise, uid_eleveur';

/** Reproducteurs actifs de l'élevage (filtrés à la source, puis règle complète). */
export async function chargerReproducteurs({ uidEleveur, sexe, espece, exclureId }: {
  uidEleveur: string; sexe: 'male' | 'femelle'; espece?: string | null; exclureId?: string | null;
}): Promise<Reproducteur[]> {
  let q = supabase.from('animaux').select(SELECT_REPRO)
    .eq('uid_eleveur', uidEleveur).eq('sexe', sexe).eq('reproducteur', true);
  if (espece) q = q.eq('espece', espece);
  const { data } = await q.order('nom');
  return ((data ?? []) as (AnimalRepro & Record<string, string | null>)[])
    .filter(a => a.id !== exclureId && estReproducteurEligible(a))
    .map(a => ({ id: a.id, nom: a.nom || a.nom_pedigree || 'Sans nom', race: a.race, identification: a.identification, source: 'elevage' as const }));
}

/** Reproducteurs extérieurs déjà enregistrés : partenaires extérieurs de vos
 *  saillies passées + reproducteurs publiés par d'autres élevages PetsMatch.
 *  Ils ne sont jamais ajoutés au cheptel. */
export async function chargerReproducteursExterieurs({ uidEleveur, sexe, espece }: {
  uidEleveur: string; sexe: 'male' | 'femelle'; espece?: string | null;
}): Promise<Reproducteur[]> {
  const out: Reproducteur[] = [];
  const vus = new Set<string>();
  try {
    let qa = supabase.from('animaux').select('id').eq('uid_eleveur', uidEleveur).neq('sexe', sexe);
    if (espece) qa = qa.eq('espece', espece);
    const { data: mine } = await qa;
    const ids = (mine ?? []).map(r => (r as { id: string }).id);
    if (ids.length) {
      const { data: sa } = await supabase.from('saillies').select('nom_partenaire, ident_partenaire')
        .in('animal_id', ids).is('partenaire_animal_id', null).order('date', { ascending: false });
      for (const s of (sa ?? []) as { nom_partenaire?: string; ident_partenaire?: string }[]) {
        const nom = (s.nom_partenaire ?? '').trim();
        if (!nom) continue;
        const ident = (s.ident_partenaire ?? '').trim();
        const k = `${nom.toLowerCase()}|${ident}`;
        if (vus.has(k)) continue;
        vus.add(k);
        out.push({ id: null, nom, identification: ident || null, source: 'historique' });
      }
    }
  } catch { /* historique indisponible */ }
  try {
    let qr = supabase.from('animaux').select(SELECT_REPRO)
      .eq('reproducteur_public', true).eq('sexe', sexe).neq('uid_eleveur', uidEleveur);
    if (espece) qr = qr.eq('espece', espece);
    const { data } = await qr.limit(80);
    for (const a of (data ?? []) as (AnimalRepro & Record<string, string | null>)[]) {
      if (!estReproducteurEligible(a)) continue;
      const nom = a.nom_pedigree || a.nom || '';
      const ident = a.identification ?? '';
      const k = `${nom.toLowerCase()}|${ident}`;
      if (!nom || vus.has(k)) continue;
      vus.add(k);
      out.push({ id: null, nom, race: a.race, identification: ident || null, source: 'reseau' });
    }
  } catch { /* réseau indisponible */ }
  return out;
}
