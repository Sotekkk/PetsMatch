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
| Ingestion `factures` → `pa.invoices` | `src/ingest/` | à venir |
| Génération Factur-X (PDF/A-3 + XML CII) | `src/facturx/` | à venir |
| Machine à états (10 statuts) | `src/lifecycle/` | à venir |
| Journal de preuve | `src/audit/` | à venir |
| E-reporting B2C + paiements | `src/ereporting/` | à venir |

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
- **Référence facture d'origine** (BT-25) : on n'a que l'`id` interne, pas le
  numéro — à résoudre à l'ingestion.
- **Devise** non stockée → défaut `EUR`.

## Base de données

Pour la phase socle, les tables vivent dans un **schéma `pa`** du projet Supabase
existant (`../supabase/migration_pa_*.sql`). Aucune clé étrangère vers
`public.*` : le lien vers une facture commerciale se fait par référence
(`source_facture_id`), pour que le schéma puisse **migrer vers une base dédiée**
(UE + SecNumCloud) quand la décision infra sera prise, sans réécriture.

## Stack

Node / TypeScript (aligné sur `website/`). Génération PDF/A-3 : `pdf-lib` +
gabarit XML CII construit à la main contre EN 16931. Repli possible sur un
micro-service Python (`factur-x`) si la conformité PDF/A-3 se révèle trop
coûteuse en Node.

## Extraction

Ce dossier est un package autonome du monorepo. Il pourra être extrait dans son
propre dépôt Git sans douleur (pas de dépendance de code vers `../website` ou
`../lib`).
