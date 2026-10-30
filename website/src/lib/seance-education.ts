// Éducateur — séances d'un RDV (education_progression.rdv_id) et PDF de fin de
// séance : compte rendu (ou bilan), exercices à faire et programme de travail,
// avec la signature enregistrée du pro. Même gabarit que le compte rendu du
// vétérinaire (pdfCompteRendu). Miroir appli : lib/utils/fin_seance_education.dart.
import { supabase } from '@/lib/supabase';
import { pdfCompteRendu } from '@/lib/fin-consultation';
import { richTextToPlain } from '@/lib/rich-text';

export interface SeanceEducation {
  id: string; animal_id: string | null; type: string | null; statut?: string | null; contenu: string | null;
  exercices_conseilles: string | null; bilan_motif: string | null; bilan_recommandation: string | null;
  bilan_nb_seances_estime: number | null; created_at: string; date_seance: string | null;
}

const STATUT_OBJECTIF: Record<string, string> = { a_travailler: 'à travailler', en_cours: 'en cours', acquis: 'acquis' };

/** Comptes rendus finalisés (ou anciens sans statut) d'un RDV. */
export async function seancesEducationDuRdv(rdvId: string): Promise<SeanceEducation[]> {
  const { data } = await supabase.from('education_progression').select('*').eq('rdv_id', rdvId).order('created_at');
  return ((data ?? []) as SeanceEducation[]).filter(s => s.statut !== 'brouillon');
}

/** Texte du PDF : paragraphes « Titre : … » (titres en gras), puis listes. */
async function contenuSeance(s: SeanceEducation, proProfileId: string | null): Promise<string> {
  const p = (t: string | null | undefined) => richTextToPlain(t ?? '').trim();
  const lignes: string[] = [];
  if (s.type === 'bilan') {
    if (p(s.bilan_motif)) lignes.push(`Motif : ${p(s.bilan_motif)}`, '');
    if (p(s.contenu)) lignes.push(`Observations : ${p(s.contenu)}`, '');
    if (p(s.bilan_recommandation)) lignes.push(`Recommandation : ${p(s.bilan_recommandation)}`, '');
    if (s.bilan_nb_seances_estime) lignes.push(`Nombre de séances estimé : ${s.bilan_nb_seances_estime}`, '');
  } else {
    if (p(s.contenu)) lignes.push(`Compte rendu : ${p(s.contenu)}`, '');
    if (p(s.exercices_conseilles)) lignes.push(`Exercices conseillés : ${p(s.exercices_conseilles)}`, '');
  }
  const [{ data: ex }, { data: ob }] = await Promise.all([
    supabase.from('exercices_attribues').select('titre_snapshot, cadence, statut, progression_id, animal_id')
      .or(`progression_id.eq.${s.id}${s.animal_id ? `,and(animal_id.eq.${s.animal_id},statut.in.(a_faire,en_cours))` : ''}`),
    s.animal_id
      ? (() => {
          let q = supabase.from('education_objectifs').select('libelle, statut, pro_profile_id').eq('animal_id', s.animal_id).order('ordre');
          if (proProfileId) q = q.eq('pro_profile_id', proProfileId);
          return q;
        })()
      : Promise.resolve({ data: [] }),
  ]);
  const exercices = (ex ?? []) as { titre_snapshot: string | null; cadence: string | null }[];
  if (exercices.length) {
    lignes.push(`Exercices à faire : ${exercices.length}`);
    for (const e of exercices) lignes.push(`- ${e.titre_snapshot ?? 'Exercice'}${e.cadence ? ` (${e.cadence})` : ''}`);
    lignes.push('');
  }
  const objectifs = (ob ?? []) as { libelle: string; statut: string | null }[];
  if (objectifs.length) {
    lignes.push(`Programme de travail : ${objectifs.length} objectif${objectifs.length > 1 ? 's' : ''}`);
    for (const o of objectifs) lignes.push(`- ${o.libelle}${o.statut ? ` (${STATUT_OBJECTIF[o.statut] ?? o.statut})` : ''}`);
  }
  return lignes.join('\n');
}

/** PDF de fin de séance (compte rendu + exercices + programme), signé. */
export async function pdfSeanceEducation(s: SeanceEducation, o: {
  proProfileId: string | null; praticien: string; signature?: string | null; emailCompte?: string | null; proprietaire?: string | null;
}): Promise<Blob> {
  return pdfCompteRendu(
    { id: s.id, animal_id: s.animal_id ?? '', contenu: await contenuSeance(s, o.proProfileId), created_at: s.date_seance ?? s.created_at },
    { ...o, titre: s.type === 'bilan' ? 'BILAN COMPORTEMENTAL' : 'COMPTE RENDU DE SÉANCE', prefixePraticien: '',
      libelleAnimal: 'Animal', nomParDefaut: 'Éducateur canin' },
  );
}
