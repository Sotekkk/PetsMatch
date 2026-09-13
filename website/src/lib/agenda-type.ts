// Déduit la catégorie d'agenda (voir TYPE_COLOR dans app/agenda/page.tsx) à
// partir du motif texte saisi par le client à la réservation (ex.
// "Promenade 1h", "Visite à domicile", "Cours individuel") — pour que les
// points RDV créés depuis le profil public du pro héritent de la bonne
// couleur au lieu du bleu générique "RDV". Repli 'rdv' si le motif ne
// correspond à rien de connu (ex. garde-journée, consultation véto…).
// Miroir de lib/pages/pro/pro_agenda.dart _typeFromMotif.
export function typeFromMotif(motif: string | null | undefined): string {
  const m = (motif ?? '').toLowerCase();
  if (m.includes('cours') && m.includes('collectif')) return 'cours_collectif';
  if (m.includes('cours') && m.includes('individuel')) return 'cours_individuel';
  if (m.includes('visite') && m.includes('domicile')) return 'visite_domicile';
  if (m.includes('promenade')) return 'promenade';
  return 'rdv';
}
