// Portfolio public du photographe (user_profiles.photos_galerie, jsonb).
// Miroir appli : lib/pages/pro/photographe_portfolio_page.dart.
// `legende` = titre (compatibilité avec l'ancienne galerie {url, legende}).

export interface ItemPortfolio {
  url: string; legende: string; description?: string; categorie?: string;
  couverture?: boolean; masquee?: boolean; personne_identifiable?: boolean; autorisation?: boolean;
}

export const CATEGORIES_PORTFOLIO = [
  'Portraits canins', 'Portraits félins', 'Photographie équine', 'Studio',
  'Extérieur', 'Élevages', 'Concours et événements', 'Autres animaux',
];

export function itemsPortfolio(raw: unknown): ItemPortfolio[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((e): ItemPortfolio | null => {
    if (typeof e === 'string' && e) return { url: e, legende: '' };
    if (e && typeof e === 'object' && typeof (e as { url?: unknown }).url === 'string' && (e as { url: string }).url) {
      const o = e as ItemPortfolio;
      return { ...o, legende: o.legende ?? '' };
    }
    return null;
  }).filter((x): x is ItemPortfolio => !!x);
}

/** Publiable : non masquée, autorisation obtenue si une personne est
 *  identifiable ; la couverture en tête. */
export function portfolioPublic(raw: unknown): ItemPortfolio[] {
  const l = itemsPortfolio(raw).filter(p => !p.masquee && !(p.personne_identifiable && !p.autorisation));
  const i = l.findIndex(p => p.couverture);
  if (i > 0) l.unshift(...l.splice(i, 1));
  return l;
}
