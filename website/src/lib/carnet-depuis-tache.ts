// Tâche sanitaire d'un protocole validée (vermifuge, antiparasitaire,
// vaccination, traitement) → registre sanitaire + carnet de santé de
// l'animal, une seule entrée par traitement (date de début) même s'il dure
// plusieurs jours. Miroir appli : PlanningService.inscrireTacheAuCarnet
// (lib/services/planning_service.dart).

import { supabase } from '@/lib/supabase';
import { poserRappelAgenda } from '@/lib/rappel-agenda';

export const ACTES_CARNET = ['vermifuge', 'antiparasitaire', 'vaccination', 'traitement'];

const TABLES: Record<string, { table: string; nom: string; dose?: string }> = {
  vermifuge: { table: 'vermifuges', nom: 'produit', dose: 'dosage' },
  antiparasitaire: { table: 'antiparasitaires', nom: 'produit' },
  vaccination: { table: 'vaccinations', nom: 'vaccin' },
  traitement: { table: 'traitements', nom: 'nom', dose: 'posologie' },
};

/** Soins dont le carnet a une date de rappel (pas les traitements). */
const AVEC_RAPPEL = ['vermifuge', 'antiparasitaire', 'vaccination'];

export interface TacheSanitaire {
  id: string; animal_id?: string | null; type_acte?: string | null; etape_id?: string | null;
  label?: string | null; date_prevue: string; jour_traitement?: number | null; total_jours?: number | null;
  eleveur_profile_id?: string | null;
}

const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** Tâches qui sont la DERNIÈRE prise de leur protocole (plus aucune tâche en
 *  attente après elles dans le même plan, pour le même animal) : on peut y
 *  poser le rappel suivant. */
export async function dernieresDuProtocole(ids: string[]): Promise<Set<string>> {
  const res = new Set<string>();
  if (!ids.length) return res;
  const { data } = await supabase.from('plan_taches').select('id, plan_id, animal_id, date_prevue, type_acte').in('id', ids);
  for (const t of (data ?? []) as { id: string; plan_id: string | null; animal_id: string | null; date_prevue: string; type_acte: string | null }[]) {
    if (!AVEC_RAPPEL.includes(t.type_acte ?? '')) continue;
    if (!t.plan_id) { res.add(t.id); continue; }
    let q = supabase.from('plan_taches').select('id', { count: 'exact', head: true })
      .eq('plan_id', t.plan_id).eq('statut', 'en_attente').neq('id', t.id).gte('date_prevue', t.date_prevue);
    if (t.animal_id) q = q.eq('animal_id', t.animal_id);
    const { count } = await q;
    if (!count) res.add(t.id);
  }
  return res;
}

export async function inscrireTacheAuCarnet(t: TacheSanitaire, uidEleveur: string, profileId?: string | null, intervenant = '', myUid?: string,
  /** Dernière prise du protocole : date du prochain rappel (AAAA-MM-JJ). */
  dateRappel?: string | null) {
  void intervenant; void myUid;
  const cible = TABLES[t.type_acte ?? ''];
  if (!t.animal_id || !cible) return;
  try {
    let produit = '', dosage = '';
    if (t.etape_id) {
      const { data: e } = await supabase.from('plan_template_etapes').select('produit, dosage').eq('id', t.etape_id).maybeSingle();
      produit = ((e as { produit?: string } | null)?.produit ?? '').trim();
      dosage = ((e as { dosage?: string } | null)?.dosage ?? '').trim();
    }
    if (!produit) produit = (t.label ?? '').split(' — ')[0].trim();
    const total = t.total_jours ?? 1;
    const debut = new Date(`${t.date_prevue}T00:00:00`);
    debut.setDate(debut.getDate() - ((t.jour_traitement ?? 1) - 1));
    const dateDebut = ymd(debut);

    // Registre sanitaire : inscrit par la base à partir du carnet (une ligne
    // par soin, migration_registre_depuis_carnet.sql) — plus d'écriture ici,
    // qui faisait une ligne en double.
    const rappel = dateRappel && AVEC_RAPPEL.includes(t.type_acte ?? '') ? dateRappel.slice(0, 10) : null;
    const poserRappel = async () => {
      if (!rappel) return;
      await poserRappelAgenda({ table: cible.table, uid: uidEleveur, profilActif: profileId ?? null,
        animalId: t.animal_id!, nom: produit, dateRappel: rappel }).catch(() => {});
    };

    // Carnet : une entrée par traitement.
    const { data: deja } = await supabase.from(cible.table).select('id')
      .eq('animal_id', t.animal_id).eq('date', dateDebut).ilike(cible.nom, produit).limit(1);
    if (deja?.length) {
      if (rappel) {
        await supabase.from(cible.table).update({ date_rappel: rappel }).eq('id', (deja[0] as { id: string }).id);
        await poserRappel();
      }
      return;
    }
    const ligne: Record<string, unknown> = {
      id: `${Date.now()}${Math.floor(Math.random() * 1000)}`,
      animal_id: t.animal_id, [cible.nom]: produit, date: dateDebut,
      notes: `Protocole${total > 1 ? ` — ${total} jours` : ''}`,
    };
    if (cible.dose && dosage) ligne[cible.dose] = dosage;
    if (rappel) ligne.date_rappel = rappel;
    if (t.type_acte === 'traitement' && total > 1) {
      const fin = new Date(debut); fin.setDate(fin.getDate() + total - 1);
      ligne.date_fin = ymd(fin);
    }
    const { error } = await supabase.from(cible.table).insert(
      t.type_acte === 'vermifuge' && total > 1 ? { ...ligne, duree_jours: total } : ligne);
    if (error) await supabase.from(cible.table).insert(ligne); // colonne duree_jours absente (migration)
    await poserRappel();
  } catch { /* l'inscription au carnet ne bloque pas la validation */ }
}

/** Valide des tâches de protocole (planning du jour, accueil éleveur) : tâche faite
 *  (auteur, notes) puis, pour un soin sanitaire et si demandé, carnet + registre
 *  de chaque animal. Une seule implémentation pour les deux écrans. */
export async function validerTachesProtocole(
  taches: (TacheSanitaire & { uid_eleveur?: string | null })[],
  o: { uid: string; profileId: string | null; notes?: string; inscrire: boolean; intervenant?: string;
    /** Rappel suivant, posé sur les tâches qui terminent leur protocole. */
    dateRappel?: string | null },
): Promise<void> {
  const dernieres = o.dateRappel ? await dernieresDuProtocole(taches.map(t => t.id)) : new Set<string>();
  for (const t of taches) {
    await supabase.from('plan_taches').update({
      statut: 'fait', valide_par: o.uid, valide_par_profile_id: o.profileId,
      valide_at: new Date().toISOString(), notes_validation: o.notes?.trim() || null,
    }).eq('id', t.id);
    if (o.inscrire && ACTES_CARNET.includes(t.type_acte ?? '')) {
      await inscrireTacheAuCarnet(t, t.uid_eleveur ?? o.uid, o.profileId, o.intervenant ?? '', o.uid, dernieres.has(t.id) ? o.dateRappel : null);
    }
  }
}

