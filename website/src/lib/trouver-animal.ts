// « Trouver un animal » : destination unique de la recherche d'animaux,
// d'élevages et d'associations. Type d'annonce commun aux vues Liste / Fil /
// Carte, traduit vers les paramètres historiques (source, type) que lisent
// déjà /annonces, /annonces/feed et /annonces/carte — les anciens liens
// restent valides. Miroir appli : lib/pages/annonces/trouver_animal_page.dart.

export type TypeAnnonce = 'tous' | 'compagnie' | 'adoption' | 'saillie';
export type Source = 'eleveurs' | 'associations' | 'tous';

/** Types proposés : « Saillie » reste réservée aux éleveurs (règle du fil). */
export function typesAnnonce(estEleveur: boolean): { value: TypeAnnonce; label: string }[] {
  return [
    { value: 'tous', label: 'Tous' },
    { value: 'compagnie', label: 'Compagnie' },
    { value: 'adoption', label: 'Adoption' },
    ...(estEleveur ? [{ value: 'saillie' as const, label: 'Saillie' }] : []),
  ];
}

/** Type commun depuis l'URL : ?type=adoption… ou anciens ?source= / ?type=vente|saillie. */
export function typeDepuisParams(sp: URLSearchParams | null): TypeAnnonce {
  const t = sp?.get('type') ?? '';
  const source = sp?.get('source') ?? '';
  if (t === 'compagnie' || t === 'adoption' || t === 'saillie') return t;
  if (source === 'associations') return 'adoption';
  if (t === 'vente' || source === 'eleveurs') return 'compagnie';
  return 'tous';
}

export function sourceDe(type: TypeAnnonce): Source {
  return type === 'adoption' ? 'associations' : type === 'tous' ? 'tous' : 'eleveurs';
}

/** Valeur « type » historique (vente / saillie / tous) lue par le fil et la carte. */
export function typeVenteDe(type: TypeAnnonce): 'tous' | 'vente' | 'saillie' {
  return type === 'saillie' ? 'saillie' : type === 'compagnie' ? 'vente' : 'tous';
}

/** Une annonce correspond-elle au type ? « Adoption » n'affiche jamais de saillie. */
export function correspondType(a: { profil_source?: string | null; type_vente?: string | null }, type: TypeAnnonce, estEleveur: boolean): boolean {
  const asso = a.profil_source === 'association';
  const saillie = a.type_vente === 'saillie';
  if (type === 'adoption') return asso && !saillie;
  if (type === 'compagnie') return !asso && !saillie;
  if (type === 'saillie') return !asso && saillie;
  return !saillie || estEleveur;
}

export interface FiltresAnimaux {
  type: TypeAnnonce;
  espece?: string; race?: string; pays?: string; region?: string; dept?: string; ville?: string;
}

/** Paramètres d'URL communs (filtres compatibles conservés entre les vues). */
export function paramsAnimaux(f: FiltresAnimaux): string {
  const p = new URLSearchParams();
  p.set('type', f.type);
  p.set('source', sourceDe(f.type));
  for (const [k, v] of Object.entries({ espece: f.espece, race: f.race, pays: f.pays, region: f.region, dept: f.dept, ville: f.ville })) {
    if (v && v !== 'tous') p.set(k, v);
  }
  return p.toString();
}
