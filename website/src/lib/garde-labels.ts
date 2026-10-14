// Libellé d'affichage d'un motif de garde, adapté à l'espèce : pour un équidé,
// « Promenade … » devient « Sortie au paddock … ». AFFICHAGE UNIQUEMENT — la clé
// (`promenade_*`) et la valeur stockée dans `rdv.motif` ne changent pas.
// Miroir de `gardeMotifLabel` dans `lib/pages/pro/garde_facture_helper.dart`.

const FALLBACK: Record<string, string> = {
  promenade_30min: 'Promenade 30 min',
  promenade_1h: 'Promenade 1h',
  promenade_2h: 'Promenade 2h',
  visite_domicile: 'Visite à domicile',
  garde_journee: 'Garde journée',
};

export function gardeMotifLabel(keyOrLabel: string, espece?: string | null): string {
  const e = (espece ?? '').toLowerCase().trim();
  const isEquide = e === 'cheval' || e === 'poney' || e === 'ane' || e === 'âne';
  const base = FALLBACK[keyOrLabel] ?? keyOrLabel;
  if (!isEquide) return base;
  const s = base.toLowerCase();
  if (!s.includes('promenade') && !s.includes('balade')) return base;
  if (s.includes('30')) return 'Sortie au paddock (30 min)';
  if (s.includes('2')) return 'Sortie au paddock (2 h)';
  return 'Sortie au paddock (1 h)';
}

/** Accès au logement choisi par le client (rdv.acces_logement) — miroir appli
 *  kAccesLogement (garde_facture_helper.dart). Jamais de code de boîte à clés ici. */
export const ACCES_LOGEMENT: { key: string; label: string }[] = [
  { key: 'present', label: 'Je serai présent·e' },
  { key: 'remise_cles', label: 'Remise des clés au pet-sitter' },
  { key: 'boite_cles', label: 'Boîte à clés' },
  { key: 'cles_detenues', label: 'Le pet-sitter a déjà mes clés' },
];
export const accesLogementLabel = (k?: string | null) => ACCES_LOGEMENT.find(a => a.key === k)?.label ?? '';
