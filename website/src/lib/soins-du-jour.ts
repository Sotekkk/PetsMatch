// Soins inscrits au carnet d'un animal un jour donné (intervention) : repris
// dans le CR opératoire — « Soins administrés » (vaccins, vermifuges,
// antiparasitaires, traitements donnés sur place) et « Traitements prescrits »
// (traitements à poursuivre : date de fin après le jour, ou rappels de prise),
// qui servent aussi à préparer l'ordonnance et les consignes postopératoires.
// Miroir appli : lib/utils/soins_du_jour.dart.
import { supabase } from '@/lib/supabase';

export interface TraitementPrescrit { nom: string; posologie: string; duree: string }
export interface SoinsDuJour { administres: string[]; prescrits: TraitementPrescrit[] }

const fr = (d: string) => new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' });

export async function soinsDuJour(animalId: string, jour: string): Promise<SoinsDuJour> {
  const j = jour.slice(0, 10);
  const [{ data: tr }, { data: va }, { data: ve }, { data: ap }] = await Promise.all([
    supabase.from('traitements').select('nom, posologie, date, date_fin, rappel_actif, rappel_fin').eq('animal_id', animalId).eq('date', j),
    supabase.from('vaccinations').select('vaccin, lot').eq('animal_id', animalId).eq('date', j),
    supabase.from('vermifuges').select('produit, dosage').eq('animal_id', animalId).eq('date', j),
    supabase.from('antiparasitaires').select('produit').eq('animal_id', animalId).eq('date', j),
  ]);
  const administres: string[] = [];
  const prescrits: TraitementPrescrit[] = [];
  for (const t of (tr ?? []) as { nom: string | null; posologie: string | null; date_fin: string | null; rappel_actif: boolean | null; rappel_fin: string | null }[]) {
    const nom = (t.nom ?? '').trim();
    if (!nom) continue;
    const fin = t.date_fin ?? t.rappel_fin;
    const aPoursuivre = (fin && fin.slice(0, 10) > j) || t.rappel_actif;
    if (aPoursuivre) {
      const jours = fin ? Math.round((Date.parse(`${fin.slice(0, 10)}T12:00:00`) - Date.parse(`${j}T12:00:00`)) / 86400000) + 1 : 0;
      prescrits.push({ nom, posologie: (t.posologie ?? '').trim(), duree: fin ? `${jours} jours (jusqu’au ${fr(fin)})` : '' });
    } else {
      administres.push(`${nom}${t.posologie?.trim() ? ` — ${t.posologie.trim()}` : ''}`);
    }
  }
  for (const v of (va ?? []) as { vaccin: string | null; lot: string | null }[]) {
    if (v.vaccin?.trim()) administres.push(`Vaccin ${v.vaccin.trim()}${v.lot?.trim() ? ` (lot ${v.lot.trim()})` : ''}`);
  }
  for (const v of (ve ?? []) as { produit: string | null; dosage: string | null }[]) {
    if (v.produit?.trim()) administres.push(`Vermifuge ${v.produit.trim()}${v.dosage?.trim() ? ` — ${v.dosage.trim()}` : ''}`);
  }
  for (const a of (ap ?? []) as { produit: string | null }[]) {
    if (a.produit?.trim()) administres.push(`Antiparasitaire ${a.produit.trim()}`);
  }
  return { administres, prescrits };
}

export const lignePrescrit = (t: TraitementPrescrit) => [t.nom, t.posologie, t.duree].filter(Boolean).join(' — ');

/** Ajoute des lignes à un texte sans doublon (une ligne déjà présente n'est pas recopiée). */
export function ajouterLignes(texte: string, lignes: string[]): string {
  const existantes = new Set(texte.split('\n').map(l => l.trim().toLowerCase()).filter(Boolean));
  const nouvelles = lignes.filter(l => !existantes.has(l.trim().toLowerCase()));
  return [texte.trim(), ...nouvelles].filter(Boolean).join('\n');
}
