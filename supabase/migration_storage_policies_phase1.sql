-- ════════════════════════════════════════════════════════════════════════
-- Stockage — phase 1 : plus d'accès anonyme aux fichiers via l'API.
--
-- Avant : les 28 policies de storage.objects ne testaient que bucket_id →
-- n'importe qui (sans compte) pouvait lister tous les buckets, déposer /
-- remplacer des fichiers, et supprimer dans documents, petsmatch, stories,
-- promenades-photos.
--
-- Après :
--   • lister / déposer / remplacer : utilisateur connecté (jeton Firebase,
--     qui arrive en rôle anon → identité = auth.jwt()->>'sub') ;
--   • supprimer : seulement les stories, et seulement par leur auteur
--     (1er dossier = un de SES profils, ou son uid pour les anciennes) ;
--     aucune autre suppression côté client n'existe dans l'appli / le site
--     (media et social n'avaient déjà aucune policy DELETE) ;
--   • contrats : la fenêtre « Finaliser » des contrats HTML du site
--     (lib/contrat-vente.ts, aussi via /signer-contrat où l'acquéreur peut
--     ne pas avoir de compte) dépose SANS jeton (clé publique seule).
--     En attendant la phase 2 (jeton / route serveur) : dépôt anonyme
--     toléré mais limité à ces noms de fichiers ; plus de liste,
--     remplacement ni suppression ;
--   • les URL publiques (buckets public = true) ne passent pas par la RLS :
--     l'affichage des images est inchangé.
-- Les fonctions serveur (service_role / sb_secret) contournent la RLS.
--
-- Phase 2 (code) : chemins rangés par uid, écriture limitée à ses fichiers,
-- documents / contrats en privé + liens signés.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Suppression des 28 anciennes policies (doublons compris).
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'storage' AND tablename = 'objects'
  LOOP
    EXECUTE format('DROP POLICY %I ON storage.objects', p.policyname);
  END LOOP;
END $$;

-- 2. Lecture via l'API (liste, upsert, remove) : connecté.
CREATE POLICY storage_select_connecte ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (
    bucket_id IN ('documents', 'media', 'petsmatch', 'promenades-photos',
                  'social', 'stories', 'story_music')
    AND auth.jwt() ->> 'sub' IS NOT NULL
  );

-- 3. Dépôt : connecté (mêmes buckets qu'avant, hors contrats).
CREATE POLICY storage_insert_connecte ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    bucket_id IN ('documents', 'media', 'petsmatch', 'promenades-photos',
                  'social', 'stories', 'story_music')
    AND auth.jwt() ->> 'sub' IS NOT NULL
  );

-- 3 bis. contrats : dépôt de la fenêtre « Finaliser » uniquement.
--   Elle envoie x-upsert: true, et un upsert exige AUSSI SELECT + UPDATE
--   (vérifié sur le staging, même pour un fichier neuf). Pour ne pas
--   rouvrir la liste des contrats existants, SELECT / UPDATE anonymes ne
--   portent que sur les fichiers créés dans la dernière minute.
CREATE POLICY storage_insert_contrat_html ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    bucket_id = 'contrats'
    AND name ~ '^(contrat|certificat_cession)_[A-Za-z0-9-]+_[0-9]{13}\.html$'
  );
CREATE POLICY storage_select_contrat_recent ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (
    bucket_id = 'contrats'
    AND name ~ '^(contrat|certificat_cession)_[A-Za-z0-9-]+_[0-9]{13}\.html$'
    AND created_at > now() - interval '1 minute'
  );
CREATE POLICY storage_update_contrat_recent ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (
    bucket_id = 'contrats'
    AND name ~ '^(contrat|certificat_cession)_[A-Za-z0-9-]+_[0-9]{13}\.html$'
    AND created_at > now() - interval '1 minute'
  )
  WITH CHECK (
    bucket_id = 'contrats'
    AND name ~ '^(contrat|certificat_cession)_[A-Za-z0-9-]+_[0-9]{13}\.html$'
  );

-- 4. Remplacement (upsert) : connecté, buckets qui l'autorisaient déjà.
CREATE POLICY storage_update_connecte ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (
    bucket_id IN ('documents', 'media', 'petsmatch', 'social')
    AND auth.jwt() ->> 'sub' IS NOT NULL
  )
  WITH CHECK (
    bucket_id IN ('documents', 'media', 'petsmatch', 'social')
    AND auth.jwt() ->> 'sub' IS NOT NULL
  );

-- 5. Suppression d'une story : son auteur uniquement.
--    Chemin = <user_profiles.id>/<horodatage>.<ext> (story_upload_service).
CREATE POLICY storage_delete_story_auteur ON storage.objects
  FOR DELETE TO anon, authenticated
  USING (
    bucket_id = 'stories'
    AND auth.jwt() ->> 'sub' IS NOT NULL
    AND (
      (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
      OR (storage.foldername(name))[1] IN (
        SELECT up.id::text FROM public.user_profiles up
        WHERE up.uid = auth.jwt() ->> 'sub'
      )
    )
  );

COMMIT;
