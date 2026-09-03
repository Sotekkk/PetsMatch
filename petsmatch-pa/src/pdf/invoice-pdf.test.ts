import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderInvoicePdf } from './invoice-pdf.js';
import { normalizeFacture } from '../normalize/from-facture.js';
import type { FactureSource } from '../model/facture-source.js';

const b2b: FactureSource = {
  id: 'f-pdf-1',
  numero_affichage: '2026-0100',
  date_facture: '2026-09-04',
  date_echeance: '2026-10-04',
  type_facture: null,
  nom_emetteur: 'Élevage du Domaine',
  rue_emetteur: '1 rue des Chiens',
  cp_emetteur: '69000',
  ville_emetteur: 'Lyon',
  pays_emetteur: 'France',
  siret_emetteur: '552 100 554 00013',
  tva_emetteur: 'FR40552100554',
  forme_juridique_emetteur: 'SARL',
  capital_emetteur: '5 000 €',
  nom_client: 'Animalerie SA',
  rue_client: '5 avenue du Parc',
  cp_client: '75012',
  ville_client: 'Paris',
  pays_client: 'France',
  siret_client: '552 100 554 00013',
  tva_client: 'FR40552100554',
  regime_tva: 'normal',
  mode_paiement: 'Virement bancaire',
  delai_paiement: '30',
  lignes: [{ designation: 'Chiot LOF', quantite: 1, prixUnitaireHT: 1000, tauxTVA: 20, totalHT: 1000 }],
  total_ht: 1000,
  total_tva: 200,
  total_ttc: 1200,
  statut: 'emise',
  profil_source: 'eleveur',
};

test('renderInvoicePdf : produit un PDF non trivial (B2B avec TVA)', async () => {
  const pdf = await renderInvoicePdf(normalizeFacture(b2b));
  assert.ok(pdf.byteLength > 1000, `PDF trop court : ${pdf.byteLength} o`);
  // en-tête %PDF-
  assert.deepEqual([...pdf.slice(0, 5)], [0x25, 0x50, 0x44, 0x46, 0x2d]);
});

test('renderInvoicePdf : facture B2C franchise (colonnes sans TVA)', async () => {
  const b2c: FactureSource = {
    ...b2b,
    id: 'f-pdf-2',
    nom_client: 'Léa',
    prenom_client: 'Martin',
    siret_client: null,
    tva_client: null,
    regime_tva: 'franchise',
    lignes: [{ designation: 'Toilettage', quantite: 1, prixUnitaireHT: 45, tauxTVA: 0, totalHT: 45 }],
    total_ht: 45,
    total_tva: 0,
    total_ttc: 45,
  };
  const pdf = await renderInvoicePdf(normalizeFacture(b2c));
  assert.ok(pdf.byteLength > 1000);
});

test('renderInvoicePdf : avoir (type 381)', async () => {
  const avoir: FactureSource = {
    ...b2b,
    id: 'f-pdf-3',
    numero_affichage: '2026-0101',
    type_facture: 'avoir',
    facture_parente_id: 'f-pdf-1',
  };
  const pdf = await renderInvoicePdf(normalizeFacture(avoir, { parentInvoiceNumber: '2026-0100' }));
  assert.ok(pdf.byteLength > 1000);
});
