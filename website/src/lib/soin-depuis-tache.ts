// Tâche « rappel du carnet » (functions/sante.js : « Antiparasitaire — 5 animaux »,
// « Vaccin — Tokyo »…) : on retrouve le soin, le produit et les animaux, on
// vérifie ce qui est déjà inscrit au carnet ; s'il reste des animaux, le
// formulaire de soin s'ouvre (PorteeSoinModal), sinon la tâche est simplement
// cochée. Miroir appli : lib/utils/soin_depuis_tache.dart.
import { supabase } from '@/lib/supabase';

export interface SoinTache {
  typeActe: 'vaccination' | 'vermifuge' | 'antiparasitaire';
  table: 'vaccinations' | 'vermifuges' | 'antiparasitaires';
  colNom: 'vaccin' | 'produit';
  label: string;
  produit: string;
  animalIds: string[];
}

const ACTES: Record<string, Omit<SoinTache, 'produit' | 'animalIds'>> = {
  vaccin: { typeActe: 'vaccination', table: 'vaccinations', colNom: 'vaccin', label: 'Vaccin' },
  vermifuge: { typeActe: 'vermifuge', table: 'vermifuges', colNom: 'produit', label: 'Vermifuge' },
  antiparasitaire: { typeActe: 'antiparasitaire', table: 'antiparasitaires', colNom: 'produit', label: 'Antiparasitaire' },
};

// Titre posé par functions/sante.js (pictogramme éventuel devant).
const RE_TITRE = /^[^A-Za-zÀ-ÿ]*(Vaccin|Vermifuge|Antiparasitaire) — /;

export const estTacheRappelSoin = (titre?: string | null) => RE_TITRE.test(titre ?? '');

export async function resoudreSoinTache(tacheId: string): Promise<SoinTache | null> {
  // select('*') : soin_rappel n'existe qu'après migration_taches_soin_rappel.sql.
  const { data } = await supabase.from('taches_elevage').select('*').eq('id', tacheId).maybeSingle();
  const t = data as { titre?: string; notes?: string | null; animal_id?: string | null; uid_eleveur?: string;
    soin_rappel?: { table?: string; produit?: string; animal_ids?: string[] } | null } | null;
  const m = RE_TITRE.exec(t?.titre ?? '');
  if (!t || !m) return null;
  const acte = ACTES[m[1].toLowerCase()];
  const sr = t.soin_rappel;
  if (sr?.animal_ids?.length) return { ...acte, produit: (sr.produit ?? '').trim(), animalIds: sr.animal_ids.map(String) };

  // Tâches créées avant la colonne : notes = « Produit — Animaux : A, B, C ».
  const notes = (t.notes ?? '').trim();
  const parts = notes.split(' — ');
  const produit = parts[0]?.startsWith('Animaux :') ? '' : (parts[0] ?? '').trim();
  if (t.animal_id) return { ...acte, produit, animalIds: [String(t.animal_id)] };
  const liste = parts.find(x => x.startsWith('Animaux :'));
  const noms = (liste ?? '').replace('Animaux :', '').split(',').map(x => x.trim()).filter(Boolean);
  if (!noms.length || !t.uid_eleveur) return null;
  const { data: a } = await supabase.from('animaux').select('id, nom, statut').eq('uid_eleveur', t.uid_eleveur).in('nom', noms);
  const parNom = new Map<string, string>();
  for (const x of (a ?? []) as { id: string; nom: string; statut?: string | null }[]) {
    // Homonymes : l'animal encore présent l'emporte.
    if (!parNom.has(x.nom) || !['sorti', 'decede', 'adopte', 'transfere', 'vendu'].includes(x.statut ?? '')) parNom.set(x.nom, String(x.id));
  }
  const ids = noms.map(n => parNom.get(n)).filter(Boolean) as string[];
  return ids.length ? { ...acte, produit, animalIds: ids } : null;
}

/** Animaux pour lesquels le soin est déjà au carnet : même produit (ou n'importe
 *  lequel si inconnu), donné le jour du rappel ou après, ou renouvelé avec un
 *  rappel plus lointain. */
export async function dejaAdministres(soin: SoinTache, jourRappel: string): Promise<Set<string>> {
  let q = supabase.from(soin.table).select(`animal_id, date, date_rappel, ${soin.colNom}`).in('animal_id', soin.animalIds);
  if (soin.produit) q = q.ilike(soin.colNom, soin.produit);
  const { data } = await q;
  const faits = new Set<string>();
  for (const r of (data ?? []) as unknown as { animal_id: string; date?: string | null; date_rappel?: string | null }[]) {
    const d = (r.date ?? '').slice(0, 10), dr = (r.date_rappel ?? '').slice(0, 10);
    if ((d && d >= jourRappel) || (dr && dr > jourRappel)) faits.add(String(r.animal_id));
  }
  return faits;
}
