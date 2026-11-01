// Ligne `factures` → données du PDF (facture-pdf.ts), avec la mention
// « ACQUITTÉE » si elle est payée. Utilisé côté navigateur (Mes factures) et
// côté serveur (facture acquittée jointe à l'e-mail de livraison photo).
import { lignePdfDepuisJson, type FacturePdfData } from '@/lib/facture-pdf';

export function factureVersPdfData(f: Record<string, unknown>, acquittee = f.statut === 'payee'): FacturePdfData {
  const t = (k: string) => (f[k] as string | null | undefined) ?? null;
  const n = (k: string) => Number(f[k] ?? 0) || 0;
  const lignes = ((f.lignes ?? []) as Record<string, unknown>[]).map(lignePdfDepuisJson);
  return {
    numero: t('numero_affichage') ?? String(f.numero_facture ?? ''),
    typeFacture: t('type_facture'),
    dateFacture: t('date_facture'), datePrestation: t('date_prestation'), dateEcheance: t('date_echeance'),
    nomEmetteur: t('nom_emetteur'), rueEmetteur: t('rue_emetteur'), cpEmetteur: t('cp_emetteur'), villeEmetteur: t('ville_emetteur'),
    paysEmetteur: t('pays_emetteur'), telEmetteur: t('tel_emetteur'), emailEmetteur: t('email_emetteur'), siretEmetteur: t('siret_emetteur'),
    tvaEmetteur: t('tva_emetteur'), formeJuridiqueEmetteur: t('forme_juridique_emetteur'), capitalEmetteur: t('capital_emetteur'),
    rcsEmetteur: t('rcs_emetteur'), rmEmetteur: t('rm_emetteur'),
    prenomClient: t('prenom_client'), nomClient: t('nom_client'), rueClient: t('rue_client'), cpClient: t('cp_client'),
    villeClient: t('ville_client'), paysClient: t('pays_client'), emailClient: t('email_client'),
    siretClient: t('siret_client'), tvaClient: t('tva_client'), conditionsEscompte: t('conditions_escompte'),
    lignes, totalHT: n('total_ht'), totalTVA: n('total_tva'), totalTTC: n('total_ttc'),
    franchise: t('regime_tva') === 'franchise', modePaiement: t('mode_paiement'), delaiPaiement: t('delai_paiement'),
    noteComplementaire: t('note_complementaire'),
    acquittee: acquittee ? { date: t('date_paiement'), mode: t('mode_paiement') } : null,
  };
}
