-- ════════════════════════════════════════════════════════════════════════
-- Correctif phase 1 stockage : photo de profil pendant l'inscription.
--
-- L'appli dépose la photo AVANT la création du compte Firebase, donc sans
-- jeton : particulier/first_page.dart, eleveur/first_page.dart,
-- association/inscription_association_page.dart →
-- media/profiles/<horodatage 13 chiffres>.jpg, upsert: true.
-- La phase 1 (dépôt réservé aux connectés) la bloquait : l'erreur est
-- avalée et le nouvel inscrit restait sans photo.
--
-- Toléré sans connexion : CE format de nom uniquement, dans media (images
-- seules). Un upsert exigeant SELECT + UPDATE, ceux-ci ne portent que sur
-- les fichiers de ce format créés dans la dernière minute : pas de liste
-- ni d'écrasement des photos existantes.
-- Phase 2 (code) : déposer la photo après la création du compte.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE POLICY storage_insert_photo_inscription ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    bucket_id = 'media'
    AND name ~ '^profiles/[0-9]{13}\.jpg$'
  );

CREATE POLICY storage_select_photo_inscription_recente ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (
    bucket_id = 'media'
    AND name ~ '^profiles/[0-9]{13}\.jpg$'
    AND created_at > now() - interval '1 minute'
  );

CREATE POLICY storage_update_photo_inscription_recente ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (
    bucket_id = 'media'
    AND name ~ '^profiles/[0-9]{13}\.jpg$'
    AND created_at > now() - interval '1 minute'
  )
  WITH CHECK (
    bucket_id = 'media'
    AND name ~ '^profiles/[0-9]{13}\.jpg$'
  );

COMMIT;
