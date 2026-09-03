/**
 * Forme d'une ligne de `public.factures` (moteur commun) telle que produite
 * aujourd'hui par l'app Flutter et le site. Sert d'entrée à la normalisation
 * EN 16931. À ne pas confondre avec le futur schéma `pa.*`.
 */

export interface FactureLigneSource {
  designation?: string | null;
  description?: string | null;
  quantite?: number | string | null;
  prixUnitaireHT?: number | string | null;
  tauxTVA?: number | string | null;
  totalHT?: number | string | null;
  montantTVA?: number | string | null;
  totalTTC?: number | string | null;
}

export interface FactureSource {
  id: string;
  numero_affichage?: string | null;
  numero_facture?: number | null;

  type_facture?: 'acompte' | 'avoir' | null;
  acompte_pct?: number | null;
  facture_parente_id?: string | null;

  date_facture?: string | null; // ISO yyyy-mm-dd
  date_prestation?: string | null;
  date_echeance?: string | null;

  // Émetteur (identité figée sur la facture)
  nom_emetteur?: string | null;
  rue_emetteur?: string | null;
  cp_emetteur?: string | null;
  ville_emetteur?: string | null;
  pays_emetteur?: string | null;
  tel_emetteur?: string | null;
  email_emetteur?: string | null;
  siret_emetteur?: string | null;
  tva_emetteur?: string | null;
  forme_juridique_emetteur?: string | null;
  capital_emetteur?: string | null;
  rcs_emetteur?: string | null;
  rm_emetteur?: string | null;

  // Client
  nom_client?: string | null;
  prenom_client?: string | null;
  email_client?: string | null;
  telephone_client?: string | null;
  rue_client?: string | null;
  cp_client?: string | null;
  ville_client?: string | null;
  pays_client?: string | null;
  siret_client?: string | null;
  tva_client?: string | null;

  lignes?: FactureLigneSource[] | null;
  total_ht?: number | null;
  total_tva?: number | null;
  total_ttc?: number | null;
  regime_tva?: 'franchise' | 'normal' | null;

  mode_paiement?: string | null;
  delai_paiement?: string | null;
  conditions_escompte?: string | null;
  note_complementaire?: string | null;

  statut?: 'emise' | 'payee' | 'annulee' | null;
  profil_source?: string | null;
  profile_id?: string | null;
  uid_eleveur?: string | null;
}
