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

### `rls_messagerie_test.js`

Il lance 27 tests RLS de la messagerie (conversations, messages, réactions), rôle par rôle : participant, tiers, employé, admin, non connecté.

```
node scripts/staging/rls_messagerie_test.js
```

### `rls_user_profiles_test.js`

Il lance 20 tests sur `user_profiles` :
- qui peut modifier quel profil (propriétaire, tiers, non connecté, admin) ;
- le cogérant limité à son profil élevage ;
- les colonnes réservées (abonnement, statut de vérification, badge) ;
- l'essai gratuit accordé à la création d'un profil pro.

```
node scripts/staging/rls_user_profiles_test.js
```

Avant de le relancer, supprime la ligne d'essai qu'il laisse : la requête SQL à utiliser est dans l'en-tête du fichier.

**Comptes administrateurs** (`users.is_admin`) : `plih…`, `PZlt…`, `xoRH…`, `YF9k…` (Natacha) et `zWCe…`. N'utilise jamais l'un d'eux comme « propriétaire ordinaire » ou « tiers » : un admin passe outre la plupart des règles. Comptes ordinaires utiles : `G59E…` (association), `RIOW…` (employé) et `2n7P…` (cogérant).

### `rls_agenda_rdv_test.js`

Il lance 37 tests sur l'agenda, les RDV, les notifications et le registre des mouvements. Il couvre :
- le scoping par profil des employés et du cogérant ;
- les droits d'écriture des employés ;
- le client d'un RDV ;
- les deux parties d'une cession ;
- un tiers et un visiteur non connecté.

```
node scripts/staging/rls_agenda_rdv_test.js
```

Après chaque passage, fais le ménage avec les requêtes SQL indiquées dans l'en-tête du fichier.

**Pièges appris en écrivant ces tests :**
- Une suppression ou une modification exige aussi le droit de **lire** la ligne.
- Une insertion avec relecture (`return=representation`) exige de pouvoir lire la ligne créée. Pour une ligne destinée à quelqu'un d'autre, utilise `insertMin`.
- `auth.uid()` convertit l'identifiant en uuid, ce qui provoque une erreur 22P02 avec un identifiant Firebase. Utilise toujours `auth.jwt() ->> 'sub'`.

### `rls_documents_factures_test.js`

Il lance 37 tests de lecture sur les factures, devis, cessions, certificats et contrats : émetteur, destinataire, lien secret, mauvais lien, tiers et non connecté.

```
node scripts/staging/rls_documents_factures_test.js
```

### `rls_partages_test.js` et `fixtures_partages.sql`

Il lance 33 tests sur les partages par lien :
- l'accès vétérinaire au carnet de santé, y compris avec un lien **expiré** ;
- l'album partagé ;
- le suivi d'éducation ;
- le partage et la réclamation d'un animal ;
- les blocages et les likes.

Il crée d'abord des données de test marquées `test_rls`, puis il faut les supprimer après usage :

```
psql "<STAGING_DB_URL>" -v action=creer -f scripts/staging/fixtures_partages.sql
node scripts/staging/rls_partages_test.js
psql "<STAGING_DB_URL>" -v action=supprimer -f scripts/staging/fixtures_partages.sql
```

**Le lien secret** : le token d'un lien est envoyé dans l'en-tête HTTP `x-pm-token`, que la fonction SQL `pm_token_requete()` lit.
- Dans le code, on utilise `.setHeader('x-pm-token', token)` sur une requête, ou le client `supabaseLien(token)` sur le site.
- Dans les tests, on écrit `as(null).rest(chemin, { 'x-pm-token': token })`.

### `url_exposure_test.js`

Il montre qui peut lire les colonnes contenant des liens vers des fichiers sensibles.

```
node scripts/staging/url_exposure_test.js
```

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
