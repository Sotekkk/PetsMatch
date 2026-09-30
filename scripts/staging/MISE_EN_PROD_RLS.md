# Mise en prod — sécurisation RLS et stockage

Ce document couvre les migrations préparées le 30/09/2026. Elles ont été répétées sur le staging, ramené à l'état exact de la prod puis migré dans l'ordre ci-dessous : **232 tests sur 232**.

## Ce que ça corrige

- **Messagerie** : sans compte, on lisait et modifiait tous les messages, y compris le texte, les images et les positions GPS.
- **Profils** : n'importe qui pouvait les modifier et s'attribuer premium, vérification ou badge. **L'essai gratuit** n'était jamais accordé.
- **Agenda, RDV, notifications, registre des mouvements** : ils étaient ouverts à tous.
- **Factures, devis, cessions, contrats, certificats** : ils étaient lisibles par tous. Ils sont désormais accessibles par **lien secret** (en-tête `x-pm-token`).
- **Partages par lien** : l'accès vétérinaire, les albums, le suivi, le partage et la réclamation d'un animal exposaient tous les tokens.
- **Données privées** : activité, signalements, statistiques d'annonces, inscrits aux événements, discussions de promenade, groupes privés.
- **Stockage (phase 2a)** : chacun ne liste, ne remplace ou ne supprime plus que ses propres fichiers.

**Pas encore couvert** (chantier suivant, option A) : les colonnes personnelles de `users` et de `user_profiles` (e-mail, téléphone, adresse, GPS, date de naissance), qui restent lisibles par tous.

## Pré-requis, dans cet ordre

1. **Le code est sur GitHub** (`main`).
2. **Le site est redéployé** depuis `main` par Nabil. Pour vérifier :
   - le JavaScript public de petsmatchapp.com doit contenir `accessToken`, c'est-à-dire que le client Supabase envoie le jeton Firebase ;
   - une page `/facture/<token>` doit toujours s'afficher.

   Le nouveau code fonctionne aussi avec les anciennes règles : on peut déployer d'abord et migrer ensuite.
3. **L'appli est à jour**, au moins sur les téléphones de l'équipe (build release).

   Les anciennes versions de l'appli perdent seulement :
   - la signature par lien dans l'appli ;
   - la vue vétérinaire par lien ;
   - le changement d'avatar d'un groupe par un autre modérateur.

## Étapes

### 1. Instantané de retour arrière

À faire **juste avant** d'appliquer :

```
psql "$PROD_DB_URL" -At -f scripts/staging/snapshot_policies.sql > rollback_rls_prod.sql
```

Sous Windows, lance cette commande depuis Bash, pas depuis PowerShell : PowerShell abîme les accents. Garde le fichier produit hors du dépôt.

### 2. Migrations, dans cet ordre

Les fonctions créées par une migration sont réutilisées par les suivantes, d'où l'ordre imposé.

```
supabase/migration_storage_policies_phase2a.sql
supabase/migration_rls_messagerie.sql
supabase/migration_rls_user_profiles.sql
supabase/migration_rls_agenda_rdv_notifs_registre.sql   # crée pm_acces_compte
supabase/migration_rls_documents_factures.sql           # crée pm_token_requete
supabase/migration_rls_partages_liens.sql
supabase/migration_rls_donnees_privees.sql
```

Lance chacune avec `psql "$PROD_DB_URL" -v ON_ERROR_STOP=1 -f <fichier>`. Chaque migration est une transaction : en cas d'erreur, rien n'est appliqué pour ce fichier.

### 3. Vérification en prod

Les tests SQL sont annulés à la fin et ne laissent aucune trace :

```
psql "$PROD_DB_URL" -f scripts/staging/test_rls_prod.sql
```

Chaque ligne affiche « attendu → obtenu ».

### 4. Essais manuels

Sur le téléphone et sur le site, vérifie :
- **Messagerie** : envoyer un message, envoyer une image, réagir à un message, quitter un groupe.
- **Profil** : modifier son profil.
- **Agenda** : créer un événement. Faire aussi l'essai en tant qu'**employé** (Mes Employeurs).
- **RDV** : prendre un RDV, puis l'annuler côté client.
- **Liens** :
  - ouvrir une facture et un devis par leur lien, **en navigation privée** ;
  - signer un contrat par son lien ;
  - ouvrir un album, un suivi et un accès vétérinaire par leur lien.
- **Élevage** :
  - faire une cession (registre des mouvements chez les deux parties) ;
  - ouvrir la fiche animal en tant qu'employé.
- **Stockage** : changer sa photo de profil, publier puis supprimer une story, déposer un PDF (facture, attestation).

### 5. Essai gratuit rétroactif (optionnel)

Voir d'abord la liste des profils concernés :

```
psql "$PROD_DB_URL" -f supabase/retro_essai_gratuit.sql
```

Puis accorder l'essai :

```
psql "$PROD_DB_URL" -v appliquer=1 -f supabase/retro_essai_gratuit.sql
```

## Retour arrière

```
psql "$PROD_DB_URL" -v ON_ERROR_STOP=1 -f rollback_rls_prod.sql
```

Ce script remet toutes les règles et les deux fonctions modifiées, ainsi que les réglages du bucket `media`.

Pour retirer aussi la protection des colonnes de `user_profiles` :

```
DROP TRIGGER trg_user_profiles_protege_colonnes ON public.user_profiles;
```
