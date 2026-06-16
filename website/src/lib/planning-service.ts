import { supabase } from './supabase';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Etape {
  id?: string;
  type_acte: string;
  produit?: string | null;
  dosage?: string | null;
  offset_direction: 'avant' | 'apres';
  jour_offset: number;
  age_min_semaines?: number | null;
  frequence: string;
  nb_fois_semaine: number;
  duree_semaines: number;
  duree_jours: number;
  is_recurrent?: boolean;
  lieu?: string | null;
  description?: string | null;
  tranche_horaire?: string | null;
}

interface Template {
  id: string;
  nom: string;
  type?: string;
  espece?: string | null;
  cible_type: string;
  reference_event: string;
  declencheur_auto?: string | null;
  plan_template_etapes?: Etape[];
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function toISODate(d: Date) { return d.toISOString().split('T')[0]; }
function addDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }

// ── Appliquer un template à un animal précis ──────────────────────────────────
// Crée plans_actifs + plan_taches pour (uid, template, animalId, dateBase).

export async function applyTemplateToAnimal(
  uid: string,
  template: Template,
  animalId: string,
  dateBase: Date,
): Promise<number> {
  const etapes = template.plan_template_etapes ?? [];
  if (etapes.length === 0) return 0;

  const isBebes = template.cible_type === 'bebes';

  // Récupérer le nom de l'animal
  const { data: animalRow } = await supabase
    .from('animaux').select('nom').eq('id', animalId).maybeSingle();
  const animalNom: string | null = (animalRow as { nom?: string } | null)?.nom ?? null;

  const { data: planRow } = await supabase.from('plans_actifs').insert({
    template_id:      template.id,
    uid_eleveur:      uid,
    type_declencheur: template.reference_event ?? 'manuel',
    date_reference:   toISODate(dateBase),
    reference_id:     animalId,
    reference_label:  animalNom,
  }).select('id').single();

  if (!planRow) return 0;
  const planId = (planRow as { id: string }).id;

  const taches: Record<string, unknown>[] = [];
  for (const etape of etapes) {
    const direction = etape.offset_direction === 'avant' ? -1 : 1;
    const ageSem    = etape.age_min_semaines;
    const startDate = (isBebes && ageSem != null)
      ? addDays(dateBase, ageSem * 7)
      : addDays(dateBase, direction * etape.jour_offset);

    const labelBase = [
      etape.type_acte,
      etape.produit ?? '',
      etape.dosage ? `(${etape.dosage})` : '',
    ].filter(Boolean).join(' ');

    const common: Record<string, unknown> = {
      plan_id:        planId,
      etape_id:       etape.id ?? null,
      uid_eleveur:    uid,
      animal_id:      animalId,
      animal_nom:     animalNom,
      type_acte:      etape.type_acte || null,
      lieu:           etape.lieu || null,
      tranche_horaire: etape.tranche_horaire ?? null,
    };

    if (etape.frequence === 'ponctuel') {
      const d = etape.duree_jours ?? 1;
      for (let j = 1; j <= d; j++) {
        taches.push({ ...common,
          label: d > 1 ? `${labelBase} — Jour ${j}/${d}` : (labelBase || etape.description || ''),
          date_prevue: toISODate(addDays(startDate, j - 1)), jour_traitement: j, total_jours: d });
      }
    } else if (etape.frequence === 'quotidien') {
      const total = (etape.duree_semaines ?? 1) * 7;
      for (let j = 1; j <= total; j++) {
        taches.push({ ...common, label: `${labelBase} — Jour ${j}/${total}`,
          date_prevue: toISODate(addDays(startDate, j - 1)), jour_traitement: j, total_jours: total });
      }
    } else if (etape.frequence === 'hebdomadaire') {
      const nbFois = etape.nb_fois_semaine ?? 1;
      const dureeS = etape.duree_semaines ?? 1;
      const offsets = nbFois === 1 ? [0] : nbFois === 2 ? [0, 3] : [0, 2, 4];
      const total = nbFois * dureeS;
      let occ = 1;
      for (let s = 0; s < dureeS; s++) {
        for (const off of offsets) {
          taches.push({ ...common, label: `${labelBase} (${occ}e/${total}e)`,
            date_prevue: toISODate(addDays(startDate, s * 7 + off)), jour_traitement: occ++, total_jours: total });
        }
      }
    } else if (etape.frequence === 'mensuel') {
      const dureeM = etape.duree_semaines ?? 1;
      for (let m = 0; m < dureeM; m++) {
        const d = new Date(startDate);
        d.setMonth(d.getMonth() + m);
        taches.push({ ...common, label: `${labelBase} (mois ${m + 1}/${dureeM})`,
          date_prevue: toISODate(d), jour_traitement: m + 1, total_jours: dureeM });
      }
    }
  }

  if (taches.length === 0) return 0;

  // Dedup : filtrer les tâches qui existent déjà (même etape_id + date_prevue + animal_id)
  try {
    const etapeIds = [...new Set(taches.map(t => t.etape_id as string).filter(Boolean))];
    const dates    = [...new Set(taches.map(t => t.date_prevue as string))];
    const { data: existing } = await supabase
      .from('plan_taches')
      .select('etape_id, date_prevue, animal_id')
      .eq('uid_eleveur', uid)
      .in('etape_id', etapeIds)
      .in('date_prevue', dates);

    const existingKeys = new Set(
      (existing ?? []).map((e: Record<string, unknown>) =>
        `${e.etape_id}_${e.date_prevue}_${e.animal_id ?? ''}`)
    );
    const toInsert = taches.filter(t => {
      const key = `${t.etape_id}_${t.date_prevue}_${t.animal_id ?? ''}`;
      return !existingKeys.has(key);
    });
    if (toInsert.length > 0) await supabase.from('plan_taches').insert(toInsert);
    return toInsert.length;
  } catch {
    await supabase.from('plan_taches').insert(taches);
    return taches.length;
  }
}

// ── Déclencher automatiquement les protocoles sur un événement ────────────────
// Cherche tous les templates avec declencheur_auto == declencheur,
// filtre par espece, vérifie les doublons, puis applique.

export async function triggerAutoProtocoles({
  uid,
  declencheur,
  animalId,
  dateEvenement,
  espece,
}: {
  uid: string;
  declencheur: 'naissance' | 'chaleurs' | 'gestation' | 'entree';
  animalId: string;
  dateEvenement: Date;
  espece?: string | null;
}): Promise<number> {
  try {
    const { data: templates } = await supabase
      .from('plan_templates')
      .select('*, plan_template_etapes(*)')
      .eq('uid_eleveur', uid)
      .eq('declencheur_auto', declencheur);

    if (!templates || templates.length === 0) return 0;

    let total = 0;
    for (const tpl of templates as Template[]) {
      // Filtre espece : null/vide = toutes espèces
      if (tpl.espece && espece && tpl.espece !== espece) continue;

      // Déduplication
      const etapes = tpl.plan_template_etapes ?? [];
      if (etapes.length === 0) continue;
      const etapeIds = etapes.map(e => e.id).filter(Boolean) as string[];
      if (etapeIds.length === 0) continue;

      const windowDate = new Date(dateEvenement);
      windowDate.setDate(windowDate.getDate() - 30);
      const windowStr = toISODate(windowDate);

      const { data: existing } = await supabase
        .from('plan_taches')
        .select('id')
        .eq('uid_eleveur', uid)
        .eq('animal_id', animalId)
        .in('etape_id', etapeIds)
        .gte('date_prevue', windowStr)
        .limit(1);

      if (existing && existing.length > 0) continue; // déjà appliqué

      // Forcer cible individuelle
      const mod: Template = { ...tpl, cible_type: 'individuel' };
      total += await applyTemplateToAnimal(uid, mod, animalId, dateEvenement);
    }
    return total;
  } catch (e) {
    console.error('triggerAutoProtocoles:', e);
    return 0;
  }
}
