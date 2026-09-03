/**
 * Machine à états des factures (cahier des charges §18).
 *
 * Chaque changement d'état est contrôlé (transitions autorisées) puis
 * journalisé (`src/audit/journal.ts`). Une transition interdite lève une erreur
 * lisible — on ne « force » jamais un état.
 */

export const STATUSES = [
  'brouillon',
  'validee',
  'emise',
  'transmise',
  'mise_a_disposition',
  'acceptee',
  'payee',
  'rejetee',
  'refusee',
  'erreur_technique',
  'annulee',
] as const;

export type InvoiceStatus = (typeof STATUSES)[number];

/** Transitions autorisées : état courant → états atteignables. */
export const TRANSITIONS: Record<InvoiceStatus, InvoiceStatus[]> = {
  brouillon: ['validee', 'annulee'],
  validee: ['emise', 'brouillon', 'annulee'],
  emise: ['transmise', 'erreur_technique', 'annulee'],
  transmise: ['mise_a_disposition', 'rejetee', 'erreur_technique'],
  mise_a_disposition: ['acceptee', 'refusee', 'payee'],
  acceptee: ['payee', 'refusee'],
  payee: ['annulee'], // via facture d'avoir
  rejetee: ['validee', 'annulee'], // correction puis nouvelle émission
  refusee: ['annulee'], // clôture par avoir
  erreur_technique: ['emise', 'transmise', 'annulee'], // reprise
  annulee: [],
};

/** États terminaux (plus aucune transition sortante utile). */
export const TERMINAL: ReadonlySet<InvoiceStatus> = new Set(['annulee']);

/** État à partir duquel le contenu de la facture est figé (inaltérable). */
export function isLocked(status: InvoiceStatus): boolean {
  return status !== 'brouillon';
}

export class InvalidTransitionError extends Error {
  constructor(
    readonly from: InvoiceStatus,
    readonly to: InvoiceStatus,
  ) {
    super(
      `Transition interdite : « ${from} » → « ${to} ». ` +
        `Transitions possibles depuis « ${from} » : ${TRANSITIONS[from].join(', ') || 'aucune'}.`,
    );
    this.name = 'InvalidTransitionError';
  }
}

export function canTransition(from: InvoiceStatus, to: InvoiceStatus): boolean {
  return TRANSITIONS[from]?.includes(to) ?? false;
}

/** Vérifie la transition ; lève `InvalidTransitionError` si interdite. */
export function assertTransition(from: InvoiceStatus, to: InvoiceStatus): void {
  if (!canTransition(from, to)) throw new InvalidTransitionError(from, to);
}
