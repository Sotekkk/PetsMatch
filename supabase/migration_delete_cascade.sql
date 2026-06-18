-- ──────────────────────────────────────────────────────────────────────────────
-- Migration : ajoute ON DELETE CASCADE sur les FK manquantes vers users(uid)
-- À exécuter dans l'éditeur SQL Supabase (Settings > SQL Editor)
-- ──────────────────────────────────────────────────────────────────────────────

-- animaux.uid_proprietaire (particuliers)
DO $$ BEGIN
  ALTER TABLE animaux
    DROP CONSTRAINT IF EXISTS animaux_uid_proprietaire_fkey;
  ALTER TABLE animaux
    ADD CONSTRAINT animaux_uid_proprietaire_fkey
      FOREIGN KEY (uid_proprietaire) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- alertes_perdus.uid_proprietaire
DO $$ BEGIN
  ALTER TABLE alertes_perdus
    DROP CONSTRAINT IF EXISTS alertes_perdus_uid_proprietaire_fkey;
  ALTER TABLE alertes_perdus
    ADD CONSTRAINT alertes_perdus_uid_proprietaire_fkey
      FOREIGN KEY (uid_proprietaire) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- animaux_perdus (uid_declarant ou uid_proprietaire selon la colonne réelle)
DO $$ BEGIN
  ALTER TABLE animaux_perdus
    DROP CONSTRAINT IF EXISTS animaux_perdus_uid_declarant_fkey;
  ALTER TABLE animaux_perdus
    ADD CONSTRAINT animaux_perdus_uid_declarant_fkey
      FOREIGN KEY (uid_declarant) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE animaux_perdus
    DROP CONSTRAINT IF EXISTS animaux_perdus_uid_proprietaire_fkey;
  ALTER TABLE animaux_perdus
    ADD CONSTRAINT animaux_perdus_uid_proprietaire_fkey
      FOREIGN KEY (uid_proprietaire) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- animaux_trouves (uid_declarant)
DO $$ BEGIN
  ALTER TABLE animaux_trouves
    DROP CONSTRAINT IF EXISTS animaux_trouves_uid_declarant_fkey;
  ALTER TABLE animaux_trouves
    ADD CONSTRAINT animaux_trouves_uid_declarant_fkey
      FOREIGN KEY (uid_declarant) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- signalements_alertes (uid_signaleur)
DO $$ BEGIN
  ALTER TABLE signalements_alertes
    DROP CONSTRAINT IF EXISTS signalements_alertes_uid_signaleur_fkey;
  ALTER TABLE signalements_alertes
    ADD CONSTRAINT signalements_alertes_uid_signaleur_fkey
      FOREIGN KEY (uid_signaleur) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- signalements (uid_signaleur)
DO $$ BEGIN
  ALTER TABLE signalements
    DROP CONSTRAINT IF EXISTS signalements_uid_signaleur_fkey;
  ALTER TABLE signalements
    ADD CONSTRAINT signalements_uid_signaleur_fkey
      FOREIGN KEY (uid_signaleur) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- likes (user_uid)
DO $$ BEGIN
  ALTER TABLE likes
    DROP CONSTRAINT IF EXISTS likes_user_uid_fkey;
  ALTER TABLE likes
    ADD CONSTRAINT likes_user_uid_fkey
      FOREIGN KEY (user_uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- favoris (uid)
DO $$ BEGIN
  ALTER TABLE favoris
    DROP CONSTRAINT IF EXISTS favoris_uid_fkey;
  ALTER TABLE favoris
    ADD CONSTRAINT favoris_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- employes (uid_employe et uid_eleveur)
DO $$ BEGIN
  ALTER TABLE employes
    DROP CONSTRAINT IF EXISTS employes_uid_employe_fkey;
  ALTER TABLE employes
    ADD CONSTRAINT employes_uid_employe_fkey
      FOREIGN KEY (uid_employe) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE employes
    DROP CONSTRAINT IF EXISTS employes_uid_eleveur_fkey;
  ALTER TABLE employes
    ADD CONSTRAINT employes_uid_eleveur_fkey
      FOREIGN KEY (uid_eleveur) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- taches_elevage (uid_eleveur, assigne_a)
DO $$ BEGIN
  ALTER TABLE taches_elevage
    DROP CONSTRAINT IF EXISTS taches_elevage_uid_eleveur_fkey;
  ALTER TABLE taches_elevage
    ADD CONSTRAINT taches_elevage_uid_eleveur_fkey
      FOREIGN KEY (uid_eleveur) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- certificats_engagement (uid)
DO $$ BEGIN
  ALTER TABLE certificats_engagement
    DROP CONSTRAINT IF EXISTS certificats_engagement_uid_fkey;
  ALTER TABLE certificats_engagement
    ADD CONSTRAINT certificats_engagement_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- partage_animal (uid)
DO $$ BEGIN
  ALTER TABLE partage_animal
    DROP CONSTRAINT IF EXISTS partage_animal_uid_fkey;
  ALTER TABLE partage_animal
    ADD CONSTRAINT partage_animal_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- vet_access_grants (uid)
DO $$ BEGIN
  ALTER TABLE vet_access_grants
    DROP CONSTRAINT IF EXISTS vet_access_grants_uid_fkey;
  ALTER TABLE vet_access_grants
    ADD CONSTRAINT vet_access_grants_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- pension_acces (uid)
DO $$ BEGIN
  ALTER TABLE pension_acces
    DROP CONSTRAINT IF EXISTS pension_acces_uid_fkey;
  ALTER TABLE pension_acces
    ADD CONSTRAINT pension_acces_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- abonnements (uid)
DO $$ BEGIN
  ALTER TABLE abonnements
    DROP CONSTRAINT IF EXISTS abonnements_uid_fkey;
  ALTER TABLE abonnements
    ADD CONSTRAINT abonnements_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- notifications (uid)
DO $$ BEGIN
  ALTER TABLE notifications
    DROP CONSTRAINT IF EXISTS notifications_uid_fkey;
  ALTER TABLE notifications
    ADD CONSTRAINT notifications_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- user_profiles (uid)
DO $$ BEGIN
  ALTER TABLE user_profiles
    DROP CONSTRAINT IF EXISTS user_profiles_uid_fkey;
  ALTER TABLE user_profiles
    ADD CONSTRAINT user_profiles_uid_fkey
      FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;
