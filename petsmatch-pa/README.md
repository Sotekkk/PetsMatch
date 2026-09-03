# petsmatch-pa

Service de **facturation électronique** de PetsMatch — le futur « PetsMatch PA »
(plateforme agréée), séparé du reste de l'application (cf. cahier des charges §2).

## Pourquoi séparé

- Périmètre **ISO 27001** réduit → audit moins cher.
- Un incident sur le réseau fiscal ne casse pas le reste de PetsMatch.
- C'est l'abstraction commune, que l'on passe par une PA tierce à titre provisoire
  ou que l'on obtienne l'immatriculation propre (décision T1 2027).

## État

**Phase « socle »** (T4 2026 → T1 2027) — indépendante de la décision PA tierce /
immatriculation :

| Brique | Fichier | Statut |
|---|---|---|
| Modèle sémantique EN 16931 | `src/model/en16931.ts` | ✅ v1 |
| Normalisation `factures` → EN 16931 | `src/normalize/from-facture.ts` | ✅ v1 |
| Validateur pré-émission | `src/validate/en16931.ts` | ✅ v1 |
| Schéma de données fiscales | `../supabase/migration_pa_01_schema.sql` | ✅ v1 (à exécuter) |
| XML CII (Factur-X, profil EN 16931) | `src/facturx/cii.ts` | ✅ v1 |
| Orchestration Factur-X (PDF/A-3) | `src/facturx/build.ts` | ✅ v1 (interface + impl HTTP + XML-only) |
| Micro-service PDF/A-3 (`factur-x` Python) | `facturx-service/` | ✅ v1 (scaffold) |
| Accès base fiscale (`service_role`, schéma `pa`) | `src/db/client.ts` | ✅ v1 |
| Ingestion `factures` → `pa.invoices` (+ lignes + ventilation) | `src/ingest/from-facture.ts` | ✅ v1 |
| Machine à états (11 statuts) + garde optimiste | `src/lifecycle/state-machine.ts`, `src/lifecycle/transition.ts` | ✅ v1 |
| Journal de preuve (append-only `pa.invoice_events`) | `src/audit/journal.ts` | ✅ v1 |
| E-reporting B2C + paiements (capture en file) | `src/ereporting/capture.ts` | ✅ v1 |
| Rendu PDF lisible de marque (serveur) | `src/pdf/invoice-pdf.ts` | ✅ v1 (jsPDF, alimenté par le modèle normalisé) |
| Transmission (PDP tierce / annuaire / immatriculation) | `src/transmit/` | à venir (décision T1 2027) |
| MFA comptes pro (§7) | — | à venir |

### Architecture Factur-X

```
En16931Invoice ─┬─► buildCii() ──────────► XML CII       (Node, src/facturx/cii.ts)
                └─► renderInvoicePdf() ──► PDF lisible   (Node, src/pdf/invoice-pdf.ts)
                          │
                          ▼
       FacturxBuilder.build()  ──HTTP──►  facturx-service (Python)
       (src/facturx/build.ts)             PDF lisible + XML → PDF/A-3
                          │
                          ▼
       { pdf: PDF/A-3, xml, sha256, profile }
```

Le XML **et** le PDF lisible (même source : le modèle normalisé) sont produits en
Node ; seul l'emballage PDF/A-3 est délégué au micro-service Python (lib de
référence `factur-x`), conformément au repli prévu §12. Sans PDF source, le
micro-service produit un rendu minimal de repli.

## Lancer

```
cd petsmatch-pa
npm install
npm run typecheck
npm test
```

## Écarts de données actuels (relevés par le validateur)

- **Unité de mesure** (BT-130) non stockée aujourd'hui → défaut `C62` (unité).
- **IBAN/BIC structurés** absents de `public.factures` (souvent dans la note) →
  à ajouter dans la capture fiscale.
- **Adresse électronique de routage** de l'acheteur (annuaire) inconnue → bloque
  l'émission B2B tant qu'on n'a pas l'annuaire ou une PA tierce.
- **Référence facture d'origine** (BT-25) : résolue à l'ingestion
  (`ingestFacture` lit `numero_affichage` de la facture parente).
- **Devise** non stockée → défaut `EUR`.

## Cycle de vie d'une facture

```
ingestFacture()  ─►  pa.invoices (statut « brouillon », lignes + ventilation + validation)
                                 │  journal : creation/update, validation
transitionInvoice(id, …)  ─────► brouillon → validee → emise → transmise
                                 → mise_a_disposition → acceptee → payee
                                 (+ rejetee / refusee / erreur_technique / annulee)
                                 chaque pas : contrôlé (state-machine) puis journalisé
captureB2cTransaction(id) ─────► pa.ereporting_queue (kind « transaction »)
capturePayment(id, {…})   ─────► pa.ereporting_queue (kind « paiement »)
```

Une facture figée (statut ≠ `brouillon`) n'est plus jamais réécrite par
l'ingestion — le contenu est inaltérable dès la validation.

## Base de données

Pour la phase socle, les tables vivent dans un **schéma `pa`** du projet Supabase
existant (`../supabase/migration_pa_*.sql`). Aucune clé étrangère vers
`public.*` : le lien vers une facture commerciale se fait par référence
(`source_facture_id`), pour que le schéma puisse **migrer vers une base dédiée**
(UE + SecNumCloud) quand la décision infra sera prise, sans réécriture.

## Stack

Node / TypeScript (aligné sur `website/`). XML CII construit à la main contre
EN 16931 ; PDF lisible via `jsPDF` (+ `jspdf-autotable`), même gabarit que l'app
Flutter et `/facture/[token]`. Emballage PDF/A-3 délégué au micro-service Python
`factur-x` (`facturx-service/`).

## Extraction

Ce dossier est un package autonome du monorepo. Il pourra être extrait dans son
propre dépôt Git sans douleur (pas de dépendance de code vers `../website` ou
`../lib`).
