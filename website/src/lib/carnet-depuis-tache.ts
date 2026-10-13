// Tâche sanitaire d'un protocole validée (vermifuge, antiparasitaire,
// vaccination, traitement) → registre sanitaire + carnet de santé de
// l'animal, une seule entrée par traitement (date de début) même s'il dure
// plusieurs jours. Miroir appli : PlanningService.inscrireTacheAuCarnet
// (lib/services/planning_service.dart).

import { supabase } from '@/lib/supabase';

export const ACTES_CARNET = ['vermifuge', 'antiparasitaire', 'vaccination', 'traitement'];

const TABLES: Record<string, { table: string; nom: string; dose?: string }> = {
  vermifuge: { table: 'vermifuges', nom: 'produit', dose: 'dosage' },
  antiparasitaire: { table: 'antiparasitaires', nom: 'produit' },
  vaccination: { table: 'vaccinations', nom: 'vaccin' },
  traitement: { table: 'traitements', nom: 'nom', dose: 'posologie' },
};

export interface TacheSanitaire {
  id: string; animal_id?: string | null; type_acte?: string | null; etape_id?: string | null;
  label?: string | null; date_prevue: string; jour_traitement?: number | null; total_jours?: number | null;
}

const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export async function inscrireTacheAuCarnet(t: TacheSanitaire, uidEleveur: string, profileId?: string | null) {
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

    // Registre sanitaire (une ligne par prise validée, comme l'appli).
    const { data: a } = await supabase.from('animaux')
      .select('nom, espece, date_naissance, identification, sexe').eq('id', t.animal_id).maybeSingle();
    const animal = (a ?? {}) as { nom?: string; espece?: string; date_naissance?: string; identification?: string; sexe?: string };
    await supabase.from('registre_sanitaire').upsert({
      uid_eleveur: uidEleveur, ...(profileId ? { eleveur_profile_id: profileId } : {}),
      animal_id: t.animal_id, animal_nom: animal.nom ?? '', espece: animal.espece ?? '',
      date_naissance: animal.date_naissance ?? null, identification: animal.identification ?? '', sexe: animal.sexe ?? '',
      date_acte: t.date_prevue, type_acte: t.type_acte, intervenant: '', description: t.label ?? produit,
      ordonnance_num: '', profil_source: 'eleveur', source_table: 'plan_taches', source_id: t.id,
    }, { onConflict: 'source_table,source_id' });

    // Carnet : une entrée par traitement.
    const { data: deja } = await supabase.from(cible.table).select('id')
      .eq('animal_id', t.animal_id).eq('date', dateDebut).ilike(cible.nom, produit).limit(1);
    if (deja?.length) return;
    const ligne: Record<string, unknown> = {
      id: `${Date.now()}${Math.floor(Math.random() * 1000)}`,
      animal_id: t.animal_id, [cible.nom]: produit, date: dateDebut,
      notes: `Protocole${total > 1 ? ` — ${total} jours` : ''}`,
    };
    if (cible.dose && dosage) ligne[cible.dose] = dosage;
    if (t.type_acte === 'traitement' && total > 1) {
      const fin = new Date(debut); fin.setDate(fin.getDate() + total - 1);
      ligne.date_fin = ymd(fin);
    }
    const { error } = await supabase.from(cible.table).insert(
      t.type_acte === 'vermifuge' && total > 1 ? { ...ligne, duree_jours: total } : ligne);
    if (error) await supabase.from(cible.table).insert(ligne); // colonne duree_jours absente (migration)
  } catch { /* l'inscription au carnet ne bloque pas la validation */ }
}
