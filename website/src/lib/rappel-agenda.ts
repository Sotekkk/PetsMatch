// Prochain rappel d'un soin (vaccin, vermifuge, antiparasitaire) dans l'agenda :
// un événement à 8 h le jour du rappel, un seul pour les animaux traités
// ensemble. Les rappels à une autre date sont retirés côté serveur (trigger
// trg_sante_rappel_a_jour). Miroir appli : _scheduleRappelAgenda (animal_fiche.dart).
import { supabase } from '@/lib/supabase';
import { profilPourAnimal } from '@/lib/cloisonnement-profils';

const LIBELLES: Record<string, string> = {
  vaccinations: 'vaccin', vermifuges: 'vermifuge', antiparasitaires: 'antiparasitaire',
};

/** Ne bloque jamais l'enregistrement du soin : un échec reste silencieux. */
export async function poserRappelAgenda(p: {
  table: string; uid: string | null | undefined; profilActif: string | null | undefined;
  animalId: string; autres?: string[]; nom: string | null | undefined; dateRappel: string | null | undefined;
}): Promise<void> {
  const libelle = LIBELLES[p.table];
  const nom = (p.nom ?? '').trim();
  const jour = (p.dateRappel ?? '').slice(0, 10);
  if (!libelle || !p.uid || !nom || !/^\d{4}-\d{2}-\d{2}$/.test(jour)) return;
  try {
    let titre = `Rappel ${libelle} — ${nom}`;
    const { data: animaux } = await supabase.from('animaux').select('nom').in('id', [p.animalId, ...(p.autres ?? [])]);
    const noms = ((animaux ?? []) as { nom: string | null }[]).map(a => a.nom ?? '').filter(Boolean);
    if (noms.length) titre += noms.length > 4 ? ` (${noms.slice(0, 4).join(', ')} +${noms.length - 4})` : ` (${noms.join(', ')})`;
    const [a, m, j] = jour.split('-').map(Number);
    const date = new Date(a, m - 1, j, 8, 0, 0).toISOString();
    const profil = await profilPourAnimal(p.animalId, p.uid, p.profilActif);
    // Même rappel déjà posé ce jour-là : pas de doublon.
    await supabase.from('agenda_events').delete()
      .eq('uid', p.uid).eq('animal_id', p.animalId).eq('titre', titre).eq('type', 'medication').eq('date_debut', date);
    await supabase.from('agenda_events').insert({
      uid: p.uid, titre, type: 'medication', date_debut: date, animal_id: p.animalId,
      ...(profil ? { pro_profile_id: profil, profile_id: profil } : {}),
    });
  } catch { /* le soin reste enregistré */ }
}
