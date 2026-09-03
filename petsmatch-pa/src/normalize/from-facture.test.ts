import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeFacture } from './from-facture.js';
import { validateEn16931 } from '../validate/en16931.js';
import type { FactureSource } from '../model/facture-source.js';

// Une facture B2B « propre » : SIRET valide des deux côtés, TVA cohérente.
const b2bOk: FactureSource = {
  id: 'f-001',
  numero_affichage: '2026-0007',
  date_facture: '2026-09-04',
  date_echeance: '2026-10-04',
  type_facture: null,
  nom_emetteur: 'Élevage du Domaine',
  rue_emetteur: '1 rue des Chiens',
  cp_emetteur: '69000',
  ville_emetteur: 'Lyon',
  pays_emetteur: 'France',
  siret_emetteur: '552 100 554 00013', // SIRET valide (Luhn)
  tva_emetteur: 'FR40552100554',
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
  lignes: [
    { designation: 'Chiot LOF', quantite: 1, prixUnitaireHT: 1000, tauxTVA: 20, totalHT: 1000 },
    { designation: 'Kit de départ', quantite: 2, prixUnitaireHT: 25, tauxTVA: 20, totalHT: 50 },
  ],
  total_ht: 1050,
  total_tva: 210,
  total_ttc: 1260,
  statut: 'emise',
  profil_source: 'eleveur',
};

test('B2B : normalisation + validation cohérentes', () => {
  const inv = normalizeFacture(b2bOk);
  assert.equal(inv.number, '2026-0007');
  assert.equal(inv.typeCode, '380');
  assert.equal(inv.source.isB2c, false);
  assert.equal(inv.seller.legalRegistrationId, '552100554'); // SIREN
  assert.equal(inv.lines.length, 2);
  assert.equal(inv.totals.taxExclusiveAmount, 1050);
  assert.equal(inv.totals.taxAmount, 210);
  assert.equal(inv.totals.taxInclusiveAmount, 1260);
  assert.equal(inv.vatBreakdown.length, 1);
  assert.equal(inv.vatBreakdown[0]!.taxableAmount, 1050);

  const r = validateEn16931(inv);
  // Seul reste un warning : pas d'adresse électronique de routage acheteur…
  const errors = r.issues.filter((i) => i.severity === 'error');
  assert.deepEqual(errors, [], `erreurs inattendues : ${JSON.stringify(errors)}`);
});

test('B2C : franchise en base → catégorie E + mention 293 B, pas d\'acheteur', () => {
  const b2c: FactureSource = {
    id: 'f-002',
    numero_affichage: '2026-0008',
    date_facture: '2026-09-04',
    nom_emetteur: 'Toilettage Pattes Douces',
    rue_emetteur: '3 rue Neuve',
    cp_emetteur: '31000',
    ville_emetteur: 'Toulouse',
    pays_emetteur: 'France',
    siret_emetteur: '552 100 554 00013',
    nom_client: 'Marie',
    prenom_client: 'Dupont',
    regime_tva: 'franchise',
    lignes: [{ designation: 'Toilettage complet', quantite: 1, prixUnitaireHT: 45, tauxTVA: 0, totalHT: 45 }],
    total_ht: 45,
    total_tva: 0,
    total_ttc: 45,
    statut: 'emise',
    profil_source: 'toilettage',
  };
  const inv = normalizeFacture(b2c);
  assert.equal(inv.source.isB2c, true);
  assert.equal(inv.buyer, undefined);
  assert.equal(inv.vatBreakdown[0]!.category, 'E');
  assert.equal(inv.vatBreakdown[0]!.exemptionReasonText, 'TVA non applicable, art. 293 B du CGI');
  assert.equal(inv.totals.taxAmount, 0);

  const r = validateEn16931(inv);
  assert.equal(r.ok, true, JSON.stringify(r.issues.filter((i) => i.severity === 'error')));
});

test('détecte un SIRET invalide et un total incohérent', () => {
  const bad: FactureSource = {
    ...b2bOk,
    id: 'f-003',
    siret_client: '111 111 111 11111', // invalide (Luhn)
    total_ttc: 9999, // incohérent
    lignes: [{ designation: 'X', quantite: 1, prixUnitaireHT: 100, tauxTVA: 20, totalHT: 100 }],
    total_ht: 100,
    total_tva: 20,
  };
  const inv = normalizeFacture(bad);
  // on force le total incohérent dans le modèle pour tester la règle
  inv.totals.taxInclusiveAmount = 9999;
  const r = validateEn16931(inv);
  assert.equal(r.ok, false);
  assert.ok(r.issues.some((i) => i.code === 'PM-SIRET-BUYER'));
  assert.ok(r.issues.some((i) => i.code === 'BR-CO-15'));
});
