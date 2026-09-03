/**
 * Modèle sémantique EN 16931 (facture électronique — norme socle).
 *
 * Représentation neutre d'une facture, indépendante de la syntaxe de sortie
 * (Factur-X / CII, UBL, PEPPOL BIS). Les modules `normalize/` produisent ce
 * modèle à partir des données PetsMatch ; les modules `facturx/` et `validate/`
 * le consomment.
 *
 * Les références `BT-xx` / `BG-xx` renvoient aux « business terms » et
 * « business groups » de la norme EN 16931-1.
 */

// ── Listes de codes (sous-ensembles utiles à PetsMatch) ──────────────────────

/** BT-3 — Type de document (UNCL1001). */
export const INVOICE_TYPE = {
  COMMERCIAL: '380', // facture commerciale
  CREDIT_NOTE: '381', // facture d'avoir
  CORRECTED: '384', // facture rectificative
  PREPAYMENT: '386', // facture d'acompte
} as const;
export type InvoiceTypeCode = (typeof INVOICE_TYPE)[keyof typeof INVOICE_TYPE];

/** BT-118 / BT-151 — Catégorie de TVA (UNCL5305). */
export const VAT_CATEGORY = {
  STANDARD: 'S', // taux normal / réduit
  ZERO: 'Z', // taux zéro
  EXEMPT: 'E', // exonéré (dont franchise en base, art. 293 B)
  REVERSE_CHARGE: 'AE', // autoliquidation
  INTRA_COMMUNITY: 'K', // livraison intracommunautaire exonérée
  EXPORT: 'G', // exportation hors UE exonérée
  OUT_OF_SCOPE: 'O', // hors champ de la TVA
} as const;
export type VatCategoryCode = (typeof VAT_CATEGORY)[keyof typeof VAT_CATEGORY];

/** BT-130 — Unité de mesure (UN/ECE Rec 20). */
export const UNIT = {
  UNIT: 'C62', // unité (défaut)
  PIECE: 'H87', // pièce
  HOUR: 'HUR', // heure
  DAY: 'DAY', // jour / nuitée
  KILOMETRE: 'KMT', // kilomètre (taxi animalier)
  LUMP_SUM: 'LS', // forfait
} as const;
export type UnitCode = (typeof UNIT)[keyof typeof UNIT];

/** BT-81 — Moyen de paiement (UNCL4461). */
export const PAYMENT_MEANS = {
  CASH: '10',
  CHEQUE: '20',
  CREDIT_TRANSFER: '30',
  SEPA_CREDIT_TRANSFER: '58',
  BANK_CARD: '48',
  ONLINE_PAYMENT_SERVICE: '68', // PayPal, Stripe…
} as const;
export type PaymentMeansCode = (typeof PAYMENT_MEANS)[keyof typeof PAYMENT_MEANS];

/**
 * BT-121 — Code du motif d'exonération de TVA.
 * ⚠️ Le code exact pour la franchise en base française (art. 293 B du CGI) est
 * à confirmer avec le cabinet spécialisé (liste VATEX du CEF). En attendant on
 * fournit systématiquement le texte BT-120.
 */
export const VAT_EXEMPTION_REASON_TEXT = {
  FRANCHISE_293B: 'TVA non applicable, art. 293 B du CGI',
  REVERSE_CHARGE: 'Autoliquidation',
  INTRA_COMMUNITY: 'Exonération TVA, art. 262 ter I du CGI',
  EXPORT: 'Exonération TVA, art. 262 I du CGI',
} as const;

// ── Structures ──────────────────────────────────────────────────────────────

/** BG-5 / BG-8 — Adresse postale. */
export interface PostalAddress {
  line1?: string; // BT-35 / BT-50
  line2?: string; // BT-36 / BT-51
  city?: string; // BT-37 / BT-52
  postCode?: string; // BT-38 / BT-53
  countryCode: string; // BT-40 / BT-55 — ISO 3166-1 alpha-2 (obligatoire)
}

/** Identifiant électronique de routage (BT-34 / BT-49) + son schéma (EAS). */
export interface ElectronicAddress {
  value: string;
  /** Schéma d'identifiant (code EAS) — ex. '0009' SIRET, '0225' SIREN. */
  scheme: string;
}

/** BG-4 — Vendeur. */
export interface Seller {
  name: string; // BT-27 (obligatoire)
  tradingName?: string; // BT-28
  vatIdentifier?: string; // BT-31 — n° TVA intracommunautaire
  legalRegistrationId?: string; // BT-30 — SIREN (schéma 0002)
  siret?: string; // identifiant établissement (schéma 0009)
  address: PostalAddress; // BG-5 (obligatoire)
  electronicAddress?: ElectronicAddress; // BT-34
  contactEmail?: string; // BT-43
  contactPhone?: string; // BT-42
  // Mentions légales françaises (portées en note si pas de champ dédié)
  legalForm?: string;
  shareCapital?: string;
  rcs?: string;
  rm?: string;
}

/** BG-7 — Acheteur (uniquement B2B ; en B2C on fait de l'e-reporting). */
export interface Buyer {
  name: string; // BT-44
  vatIdentifier?: string; // BT-48
  legalRegistrationId?: string; // BT-47 — SIREN
  siret?: string;
  address: PostalAddress; // BG-8
  electronicAddress?: ElectronicAddress; // BT-49
  reference?: string; // BT-10 — référence acheteur
  contactEmail?: string;
}

/** BG-30 / BG-31 — TVA d'une ligne. */
export interface LineVat {
  category: VatCategoryCode; // BT-151
  rate: number; // BT-152 — en pourcentage (ex. 20 ; 0 pour exonéré)
}

/** BG-25 — Ligne de facture. */
export interface InvoiceLine {
  id: string; // BT-126 — identifiant de ligne (ordinal)
  name: string; // BT-153 — nom de l'article/prestation
  description?: string; // BT-154
  quantity: number; // BT-129
  unit: UnitCode; // BT-130
  netPrice: number; // BT-146 — prix unitaire net HT
  netAmount: number; // BT-131 — montant net HT de la ligne (quantité × prix)
  vat: LineVat;
}

/** BG-23 — Ventilation de la TVA par catégorie + taux. */
export interface VatBreakdown {
  category: VatCategoryCode; // BT-118
  rate: number; // BT-119
  taxableAmount: number; // BT-116 — base HT
  taxAmount: number; // BT-117 — montant de TVA
  exemptionReasonCode?: string; // BT-121
  exemptionReasonText?: string; // BT-120
}

/** BG-22 — Totaux du document. */
export interface DocumentTotals {
  lineNetTotal: number; // BT-106 — somme des montants nets de lignes
  taxExclusiveAmount: number; // BT-109 — total HT
  taxAmount: number; // BT-110 — total TVA
  taxInclusiveAmount: number; // BT-112 — total TTC
  paidAmount?: number; // BT-113 — déjà payé (acomptes)
  amountDueForPayment: number; // BT-115 — reste à payer
}

/** BG-16 — Instructions de paiement. */
export interface PaymentInstructions {
  meansCode: PaymentMeansCode; // BT-81
  iban?: string; // BT-84
  bic?: string; // BT-86
  remittanceInformation?: string; // BT-83 — référence de virement
  termsText?: string; // BT-20 — conditions de paiement en clair
}

/** Facture au sens EN 16931. */
export interface En16931Invoice {
  number: string; // BT-1
  issueDate: string; // BT-2 — ISO yyyy-mm-dd
  typeCode: InvoiceTypeCode; // BT-3
  currencyCode: string; // BT-5 — ISO 4217 (EUR)
  dueDate?: string; // BT-9
  buyerReference?: string; // BT-10
  /** BT-25/26 — facture d'origine référencée (avoir, rectificative). */
  precedingInvoiceReference?: { number: string; issueDate?: string };
  /** BT-72 — date de la prestation / livraison. */
  serviceDate?: string;

  seller: Seller;
  /** Absent = facture B2C → traitée en e-reporting, pas en e-invoicing. */
  buyer?: Buyer;

  lines: InvoiceLine[]; // BG-25 (1..n)
  vatBreakdown: VatBreakdown[]; // BG-23 (1..n)
  totals: DocumentTotals; // BG-22
  payment?: PaymentInstructions; // BG-16

  note?: string; // BT-22 — note libre (mentions légales complémentaires)

  /** Métadonnées PetsMatch (hors norme) — traçabilité de la source. */
  source: {
    factureId: string;
    profilSource: string | null;
    isB2c: boolean;
  };
}
