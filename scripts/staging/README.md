# Outils staging

Environnement de test iso-prod, pour vérifier une migration (RLS, policies
Storage…) **avant** de l'appliquer à la prod.

| | Prod | Staging |
|---|---|---|
| Firebase | `petsmatch-eb96d` | `petsmatch-staging` (forfait Spark : pas de Storage ni de Functions) |
| Supabase | `zyvpngcvzrkdytypjlyq` | `ozftswznayxzrbcfmher` |

Contenu du staging (copie du 30/09/2026) :
- la base Supabase (schémas `public` + `pa`), les buckets et les policies, mais **aucun fichier** ;
- les comptes Firebase Auth, avec les mêmes mots de passe qu'en prod ;
- Firestore, sans les jetons push : le staging ne peut pas notifier les vrais téléphones.

Le webhook `notify_push` n'existe pas sur le staging.

## Prérequis (une fois par poste)

Les secrets restent **hors du dépôt**, dans le dossier utilisateur :

- **`petsmatch-staging-sa.json`** : clé de compte de service Firebase staging.
  - Où la générer : console Firebase `petsmatch-staging` → Paramètres → Comptes de service → « Générer une nouvelle clé privée ».
  - Usage : obligatoire pour les tests.
- **`petsmatch-prod-sa.json`** : clé de compte de service Firebase prod.
  - Usage : seulement pour `fs_copy.js`.
  - À supprimer dans la console juste après la copie.
- **`petsmatch-db.env`** : URL Postgres de chaque base, `PROD_DB_URL=...` et `STAGING_DB_URL=...`.
  - Où les trouver : Supabase → bouton **Connect**.
  - Usage : pour `psql`.

Il faut aussi :
- **Node 20+** et les dépendances de `functions/` installées (`npm ci` dans `functions/`), car les scripts utilisent son `firebase-admin` ;
- **`psql`** (PostgreSQL 17 : `C:\Program Files\PostgreSQL\17\bin`).

Les chemins des clés peuvent être remplacés par les variables `PM_STAGING_SA` et `PM_PROD_SA`.

## Les outils

### `token.js`

Il fournit un jeton Firebase **staging** « en tant que » n'importe quel uid, sans son mot de passe.

```
node scripts/staging/token.js <uid>
```

Ce test de connexion affiche les claims, jamais le jeton.

### `sb.js`

Il appelle les vraies API REST et Storage du Supabase staging avec ce jeton :

```js
const { as } = require('./sb');
const nat = await as('<uid>');   // as(null) = visiteur non connecté
await nat.rest('animaux?select=id&limit=5');
await nat.upload('media', 'test_sec/x.jpg', /* upsert */ true);
await nat.list('media', 'test_sec');
await nat.remove('stories', ['<profileId>/x.txt']);
```

### `storage_test.js`

Il lance 24 tests Storage par rôle sur le staging : non connecté, propriétaire, employé, tiers et auteur d'une story.

```
node scripts/staging/storage_test.js
```

Il dépose des fichiers témoins sous `test_sec/<horodatage>/`, sur le staging uniquement.

### `storage_test_phase2.js`

Il teste la phase 2a sur le staging : chacun ne liste, ne remplace et ne supprime que **ses** fichiers.

```
node scripts/staging/storage_test_phase2.js <fichier_ancien>
```

- **Le fichier ancien** est un objet `media` sans `owner_id`, placé dans le dossier de Natacha. On le crée d'abord en SQL, par exemple `profiles/<uid Natacha>/legacy_1.jpg`. Il simule les fichiers déposés avant le 22/09.
- **La migration testée** est `supabase/migration_storage_policies_phase2a.sql`.

### `test_storage_prod.sql`

Ce sont les mêmes contrôles, en SQL. Chaque cas se déroule dans une transaction **annulée**, ce qui le rend utilisable sur la prod sans laisser de trace.

```
psql "<PROD_DB_URL>" -f scripts/staging/test_storage_prod.sql
```

### `fs_copy.js`

Il recopie Firestore de la prod (lecture seule) vers le staging.

```
node scripts/staging/fs_copy.js
```

## Méthode pour une migration RLS / Storage

1. **Appliquer la migration sur le staging**, avec `psql "<STAGING_DB_URL>" -f supabase/migration_xxx.sql`.
2. **Tester par rôle** :
   - avec `sb.js` / `storage_test.js`, qui passent par la vraie API ;
   - ou en SQL :
     ```sql
     BEGIN;
     SET LOCAL ROLE anon;
     SELECT set_config('request.jwt.claims', '{"sub":"<uid>"}', true);
     -- ...
     ROLLBACK;
     ```
3. **Couvrir tous les rôles** :
   - propriétaire ;
   - cogérant ;
   - employé **avec et sans** droit ;
   - autre profil du même compte (pas de mélange de profils) ;
   - tiers ;
   - non connecté.
4. **Garder en tête** :
   - les jetons Firebase arrivent en rôle `anon`, pas `authenticated`, donc il faut accorder les droits (GRANT) aux deux ;
   - un upload `x-upsert: true` exige SELECT **et** UPDATE, même pour un fichier neuf.
5. **Appliquer à la prod**, puis rejouer les tests en SQL, en transactions annulées.

Comptes utiles :

| uid | Rôle |
|---|---|
| `YF9kR7jSTObnnw9lVj8gCl031rS2` | Natacha (élevage, plusieurs profils) |
| `IfhRVwY55KUXW12lBG4D0bs0V383` | employé de Natacha (write_sante) |
| `RIOWjkshiibFwwJpkSzf2P4kDKH2` | employé sans droit chez Natacha |
| `2n7PqKsfsjMNNVwGCGgkqd9SGJW2` | cogérant |
| `PZltNeW1M4cmEmOdRlbvOVmUNyB2` | tiers |
