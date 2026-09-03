import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildInvoiceRecords } from './from-facture.js';
import type { FactureSource } from '../model/facture-source.js';

const base: FactureSource = {
  id: 'f-100',
  numero_affichage: '2026-0042',
  date_facture: '2026-09-04',
  date_echeance: '2026-10-04',
  date_prestation: '2026-09-01',
  type_facture: null,
  nom_emetteur: 'Éducateur Canin Pro',
  rue_emetteur: '1 rue du Dressage',
  cp_emetteur: '44000',
  ville_emetteur: 'Nantes',
  pays_emetteur: 'France',
  siret_emetteur: '552 100 554 00013',
  tva_emetteur: 'FR40552100554',
  nom_client: 'Distribution SARL',
  rue_client: '9 bd Central',
  cp_client: '75001',
  ville_client: 'Paris',
  pays_client: 'France',
  siret_client: '552 100 554 00013',
  tva_client: 'FR40552100554',
  regime_tva: 'normal',
  mode_paiement: 'Virement bancaire',
  delai_paiement: '30',
  lignes: [{ designation: 'Bilan comportemental', quantite: 2, prixUnitaireHT: 60, tauxTVA: 20, totalHT: 120 }],
  total_ht: 120,
  total_tva: 24,
  total_ttc: 144,
  statut: 'emise',
  profil_source: 'educateur',
};

test('buildInvoiceRecords : en-tête + lignes + ventilation cartographiés', () => {
  const { header, lines, vat, validation } = buildInvoiceRecords(base);

  assert.equal(header.source_facture_id, 'f-100');
  assert.equal(header.source_kind, 'factures');
  assert.equal(header.number, '2026-0042');
  assert.equal(header.type_code, '380');
  assert.equal(header.is_b2c, false);
  assert.equal(header.service_date, '2026-09-01');
  assert.equal(header.tax_exclusive_amount, 120);
  assert.equal(header.tax_amount, 24);
  assert.equal(header.tax_inclusive_amount, 144);
  assert.equal(header.amount_due, 144);
  assert.equal(header.validation_ok, true);
  assert.equal(header.buyer && (header.buyer as { name: string }).name, 'Distribution SARL');

  assert.equal(lines.length, 1);
  assert.equal(lines[0]!.line_no, 1);
  assert.equal(lines[0]!.net_amount, 120);
  assert.equal(lines[0]!.vat_category, 'S');
  assert.equal(lines[0]!.vat_rate, 20);

  assert.equal(vat.length, 1);
  assert.equal(vat[0]!.taxable_amount, 120);
  assert.equal(vat[0]!.tax_amount, 24);
  assert.equal(vat[0]!.exemption_reason_text, null);

  assert.equal(validation.ok, true);
});

test('buildInvoiceRecords : avoir → type 381 + numéro de facture d\'origine', () => {
  const avoir: FactureSource = {
    ...base,
    id: 'f-101',
    numero_affichage: '2026-0043',
    type_facture: 'avoir',
    facture_parente_id: 'f-100',
  };
  const { header } = buildInvoiceRecords(avoir, { parentInvoiceNumber: '2026-0042' });
  assert.equal(header.type_code, '381');
  assert.equal(header.preceding_invoice_number, '2026-0042');
});

test('buildInvoiceRecords : B2C franchise → is_b2c + pas d\'acheteur + motif 293 B', () => {
  const b2c: FactureSource = {
    ...base,
    id: 'f-102',
    nom_client: 'Léa',
    prenom_client: 'Martin',
    siret_client: null,
    tva_client: null,
    regime_tva: 'franchise',
    lignes: [{ designation: 'Séance individuelle', quantite: 1, prixUnitaireHT: 50, tauxTVA: 0, totalHT: 50 }],
    total_ht: 50,
    total_tva: 0,
    total_ttc: 50,
  };
  const { header, vat } = buildInvoiceRecords(b2c);
  assert.equal(header.is_b2c, true);
  assert.equal(header.buyer, null);
  assert.equal(vat[0]!.vat_category, 'E');
  assert.equal(vat[0]!.exemption_reason_text, 'TVA non applicable, art. 293 B du CGI');
});
