// Offres de boost d'annonce (produits_ponctuels existants) : mêmes offres pour
// un boost choisi à la publication et pour un boost pris plus tard depuis
// « Mes annonces ». Miroir appli : lib/widgets/annonces/gestion_annonces_kit.dart.
import { supabase } from '@/lib/supabase';

export interface OffreBoost { code: string; label: string; prix: number; duree_heures: number | null; description: string | null }

export const CODES_BOOST = ['boost_48h', 'mise_une'];

export async function chargerOffresBoost(): Promise<OffreBoost[]> {
  const { data } = await supabase.from('produits_ponctuels')
    .select('code, label, prix, duree_heures, description')
    .eq('actif', true).not('duree_heures', 'is', null).in('code', CODES_BOOST).order('prix');
  return (data as OffreBoost[]) ?? [];
}

export const dureeOffre = (h: number | null) => h == null ? ''
  : h >= 24 ? `${Math.round(h / 24)} jour${Math.round(h / 24) > 1 ? 's' : ''}` : `${h} h`;

export const prixOffre = (p: number) => `${p.toFixed(2).replace('.', ',')} €`;

/** Page de récapitulatif et de paiement d'un boost. */
export type TableAnnonce = 'annonces' | 'annonces_objets';
export const urlPaiementBoost = (annonceId: string, code: string, statut?: string, table: TableAnnonce = 'annonces') =>
  `/annonces/paiement-boost?annonce=${annonceId}&offre=${code}${statut ? `&statut=${statut}` : ''}${table === 'annonces_objets' ? '&table=annonces_objets' : ''}`;
