import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildCii, FACTURX_PROFILE_EN16931 } from './cii.js';
import { normalizeFacture } from '../normalize/from-facture.js';
import type { FactureSource } from '../model/facture-source.js';

/** Vérif légère de bonne formation : les balises ouvrantes/fermantes s'équilibrent. */
function tagsBalanced(xml: string): boolean {
  const body = xml.replace(/<\?xml[^>]*\?>/, '');
  const stack: string[] = [];
  const re = /<(\/?)([A-Za-z][\w:.-]*)([^>]*?)(\/?)>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(body))) {
    const [, closing, name, , selfClose] = m;
    if (selfClose) continue;
    if (closing) {
      if (stack.pop() !== name) return false;
    } else {
      stack.push(name!);
    }
  }
  return stack.length === 0;
}

const b2b: FactureSource = {
  id: 'f-100',
  numero_affichage: '2026-0042',
  date_facture: '2026-09-04',
  date_echeance: '2026-10-04',
  date_prestation: '2026-09-01',
  type_facture: null,
  nom_emetteur: 'Ostéo Animalier & Cie',
  rue_emetteur: '2 impasse du Pré',
  cp_emetteur: '35000',
  ville_emetteur: 'Rennes',
  pays_emetteur: 'France',
  siret_emetteur: '55210055400013',
  tva_emetteur: 'FR40552100554',
  nom_client: 'Clinique Véto SARL',
  rue_client: '9 bd Central',
  cp_client: '44000',
  ville_client: 'Nantes',
  pays_client: 'France',
  siret_client: '55210055400013',
  tva_client: 'FR40552100554',
  regime_tva: 'normal',
  mode_paiement: 'Virement bancaire',
  delai_paiement: '30',
  conditions_escompte: 'Escompte pour paiement anticipé : néant.',
  lignes: [
    { designation: 'Séance ostéopathie', quantite: 2, prixUnitaireHT: 60, tauxTVA: 20, totalHT: 120 },
  ],
  total_ht: 120,
  total_tva: 24,
  total_ttc: 144,
  statut: 'emise',
  profil_source: 'sante',
};

test('CII : XML bien formé, profil EN 16931, valeurs clés', () => {
  const xml = buildCii(normalizeFacture(b2b));
  assert.ok(xml.startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
  assert.ok(tagsBalanced(xml), 'balises déséquilibrées');
  assert.ok(xml.includes(`<ram:ID>${FACTURX_PROFILE_EN16931}</ram:ID>`));
  assert.ok(xml.includes('<ram:ID>2026-0042</ram:ID>'));
  assert.ok(xml.includes('<ram:TypeCode>380</ram:TypeCode>'));
  assert.ok(xml.includes('<udt:DateTimeString format="102">20260904</udt:DateTimeString>'));
  // SIREN vendeur (schéma 0002)
  assert.ok(xml.includes('<ram:ID schemeID="0002">552100554</ram:ID>'));
  // TVA (schéma VA)
  assert.ok(xml.includes('<ram:ID schemeID="VA">FR40552100554</ram:ID>'));
  // adresse électronique de routage (SIRET, schéma 0009)
  assert.ok(xml.includes('<ram:URIID schemeID="0009">55210055400013</ram:URIID>'));
  // ligne
  assert.ok(xml.includes('<ram:BilledQuantity unitCode="C62">2.00</ram:BilledQuantity>'));
  assert.ok(xml.includes('<ram:Name>Séance ostéopathie</ram:Name>'));
  // totaux
  assert.ok(xml.includes('<ram:TaxBasisTotalAmount>120.00</ram:TaxBasisTotalAmount>'));
  assert.ok(xml.includes('<ram:TaxTotalAmount currencyID="EUR">24.00</ram:TaxTotalAmount>'));
  assert.ok(xml.includes('<ram:GrandTotalAmount>144.00</ram:GrandTotalAmount>'));
  assert.ok(xml.includes('<ram:DuePayableAmount>144.00</ram:DuePayableAmount>'));
  // échéance
  assert.ok(xml.includes('<ram:DueDateDateTime>'));
});

test('CII : facture B2C franchise → ExemptionReason 293 B, pas de BuyerTradeParty', () => {
  const b2c: FactureSource = {
    id: 'f-101',
    numero_affichage: '2026-0043',
    date_facture: '2026-09-04',
    nom_emetteur: 'Comportementaliste Canin',
    rue_emetteur: '1 rue A',
    cp_emetteur: '67000',
    ville_emetteur: 'Strasbourg',
    pays_emetteur: 'France',
    siret_emetteur: '55210055400013',
    regime_tva: 'franchise',
    lignes: [{ designation: 'Bilan comportemental', quantite: 1, prixUnitaireHT: 80, tauxTVA: 0, totalHT: 80 }],
    total_ht: 80,
    total_tva: 0,
    total_ttc: 80,
    statut: 'emise',
    profil_source: 'education',
  };
  const xml = buildCii(normalizeFacture(b2c));
  assert.ok(tagsBalanced(xml));
  assert.ok(!xml.includes('BuyerTradeParty'));
  assert.ok(xml.includes('<ram:CategoryCode>E</ram:CategoryCode>'));
  assert.ok(xml.includes('<ram:ExemptionReason>TVA non applicable, art. 293 B du CGI</ram:ExemptionReason>'));
  assert.ok(xml.includes('<ram:GrandTotalAmount>80.00</ram:GrandTotalAmount>'));
});

test('CII : facture d\'avoir → TypeCode 381 + InvoiceReferencedDocument', () => {
  const avoir: FactureSource = {
    ...b2b,
    id: 'f-102',
    numero_affichage: '2026-0044',
    type_facture: 'avoir',
    facture_parente_id: 'f-100',
    lignes: [{ designation: 'Avoir — Séance ostéopathie', quantite: 1, prixUnitaireHT: -60, tauxTVA: 20, totalHT: -60 }],
    total_ht: -60,
    total_tva: -12,
    total_ttc: -72,
  };
  const xml = buildCii(normalizeFacture(avoir, { parentInvoiceNumber: '2026-0042' }));
  assert.ok(tagsBalanced(xml));
  assert.ok(xml.includes('<ram:TypeCode>381</ram:TypeCode>'));
  assert.ok(xml.includes('<ram:IssuerAssignedID>2026-0042</ram:IssuerAssignedID>'));
});
