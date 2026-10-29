// Ostéo / kiné (profil « sante ») : séances (suivis_morpho) d'un RDV, PDF de
// la séance, facture préparée depuis les tarifs ostéo (tarifs_sante). Utilisé
// par la fin de séance (FinConsultationModal, metier « sante »).
// Miroir appli : lib/utils/fin_seance_osteo.dart.
import { supabase } from '@/lib/supabase';
import { morphoSuiviPdfBlob } from '@/lib/morpho-pdf';
import type { MorphoPoint, ExerciceSeance } from '@/lib/morpho';

export interface SeanceRdv { id: string; animal_id: string | null; type_suivi: string | null; lieu: string | null; statut: string | null; date: string | null }

/** Séances finalisées d'un RDV (rdv_id), à défaut celles de l'animal du RDV
 *  ce jour-là par ce profil (faites depuis la fiche). */
export async function seancesDuRdv(rdvId: string): Promise<SeanceRdv[]> {
  const cols = 'id, animal_id, type_suivi, lieu, statut, date, notifie_a';
  const { data: lies } = await supabase.from('suivis_morpho').select(cols).eq('rdv_id', rdvId).order('created_at');
  let res = (lies ?? []) as (SeanceRdv & { notifie_a?: string | null })[];
  if (res.length === 0) {
    const { data: r } = await supabase.from('rdv').select('animal_id, animaux_ids, date_heure, pro_profile_id').eq('id', rdvId).maybeSingle();
    if (r?.date_heure && r.pro_profile_id) {
      const ids = (Array.isArray(r.animaux_ids) && r.animaux_ids.length ? r.animaux_ids : [r.animal_id]).filter(Boolean).map(String);
      const jour = String(r.date_heure).slice(0, 10);
      const { data: libres } = ids.length ? await supabase.from('suivis_morpho').select(cols).in('animal_id', ids)
        .eq('pro_profile_id', r.pro_profile_id).is('rdv_id', null).eq('date', jour).order('created_at') : { data: [] };
      res = (libres ?? []) as typeof res;
    }
  }
  // Finalisées (ou anciennes séances déjà envoyées).
  return res.filter(s => s.statut === 'finalise' || (s.statut == null && !!s.notifie_a));
}

/** PDF du compte rendu de séance (même PDF que « Exporter » sur la séance). */
export async function pdfSeance(suiviId: string): Promise<{ blob: Blob; animalNom: string }> {
  const { data: s } = await supabase.from('suivis_morpho').select('*').eq('id', suiviId).maybeSingle();
  if (!s) throw new Error('Séance introuvable');
  const [ph, pt, ob, mv, ex] = await Promise.all([
    supabase.from('suivis_morpho_photos').select('vue, url').eq('suivi_id', suiviId),
    supabase.from('suivis_morpho_points').select('id, vue, x_pct, y_pct, categorie, note').eq('suivi_id', suiviId),
    supabase.from('suivis_morpho_observations').select('categorie, valeur, commentaire').eq('suivi_id', suiviId),
    supabase.from('suivis_morpho_mouvements').select('activite, observation, gene_observee, commentaire').eq('suivi_id', suiviId),
    supabase.from('suivis_morpho_exercices').select('*').eq('suivi_id', suiviId).order('ordre'),
  ]);
  const { data: a } = s.animal_id
    ? await supabase.from('animaux').select('nom, espece, race, sexe, date_naissance, identification').eq('id', s.animal_id).maybeSingle()
    : { data: null };
  const animal = a ?? { nom: (s.animal_nom_libre as string) ?? 'Animal', espece: (s.espece_libre as string) ?? undefined };
  let pro: { nom?: string; profession?: string; adresse?: string; tel?: string; email?: string } = {};
  if (s.pro_profile_id) {
    const { data: p } = await supabase.from('user_profiles_complet').select('nom, firstname, lastname, adress, phone_number, email_contact, profession_pro').eq('id', s.pro_profile_id).maybeSingle();
    pro = { nom: (p?.nom as string)?.trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim(), profession: p?.profession_pro as string,
      adresse: p?.adress as string, tel: p?.phone_number as string, email: p?.email_contact as string };
  }
  const blob = await morphoSuiviPdfBlob({
    suivi: s, animal: animal as Parameters<typeof morphoSuiviPdfBlob>[0]['animal'], pro,
    photos: (ph.data ?? []) as { vue: string; url: string }[],
    points: ((pt.data ?? []) as { id: string; vue: string; x_pct: number; y_pct: number; categorie: string; note: string | null }[]).map(p => ({ ...p, id: String(p.id) })) as unknown as MorphoPoint[],
    observations: (ob.data ?? []) as { categorie: string; valeur: string; commentaire: string | null }[],
    mouvements: (mv.data ?? []) as { activite: string; observation: string | null; gene_observee: boolean | null; commentaire: string | null }[],
    exercices: (ex.data ?? []) as ExerciceSeance[],
  });
  return { blob, animalNom: String(animal.nom ?? 'Animal') };
}

/** Lignes de facture des séances : « Séance » (tarif séance), « Consultation »
 *  pour un bilan, « Supplément déplacement » une fois si à domicile / extérieur ;
 *  nom de l'animal devant chaque ligne s'ils sont plusieurs. Prix TTC de la
 *  grille ostéo (franchise de TVA : TVA 0). */
export async function lignesFactureOsteo(proProfileId: string, seances: SeanceRdv[], noms: Record<string, string>) {
  const { data: p } = await supabase.from('user_profiles_complet').select('tarifs_sante, regime_tva_pro').eq('id', proProfileId).maybeSingle();
  const tarifs = (p?.tarifs_sante ?? {}) as Record<string, unknown>;
  const franchise = p?.regime_tva_pro === 'franchise';
  const tarif = (k: string) => { const v = parseFloat(String(tarifs[k] ?? '').replace(',', '.')); return isNaN(v) ? null : v; };
  const ligne = (d: string, ttc: number | null) => ({
    description: d, quantite: 1, tva: franchise ? 0 : 20,
    prixUnitaire: ttc == null ? 0 : franchise ? ttc : Math.round(ttc / 1.2 * 100) / 100,
  });
  const plusieurs = new Set(seances.map(s => s.animal_id)).size > 1;
  const lignes = seances.map(s => {
    const bilan = (s.type_suivi ?? '').startsWith('bilan');
    const pre = plusieurs && s.animal_id ? `${noms[s.animal_id] ?? 'Animal'} — ` : '';
    return ligne(`${pre}${bilan ? 'Consultation (bilan)' : 'Séance'}`, tarif(bilan ? 'consultation' : 'seance'));
  });
  if (seances.some(s => s.lieu === 'exterieur' || s.lieu === 'domicile')) lignes.push(ligne('Supplément déplacement', tarif('deplacement')));
  return lignes;
}
