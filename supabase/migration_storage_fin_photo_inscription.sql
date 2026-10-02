-- ════════════════════════════════════════════════════════════════════════
-- Stockage : fin de l'exception « photo d'inscription sans compte ».
--
-- Depuis la phase 2b lot 3, l'appli dépose la photo choisie à l'inscription
-- APRÈS la création du compte, dans profiles/<uid>/ (PhotosInscription).
-- L'exception anonyme de migration_storage_inscription_photo.sql
-- (media/profiles/<13 chiffres>.jpg, sans jeton) n'a donc plus d'usage.
--
-- ⚠ À lancer seulement quand plus personne n'utilise une version de
--   l'appli antérieure au 02/10/2026 (sinon ces versions perdent la photo
--   d'inscription — non bloquant : l'inscription aboutit quand même).
-- ════════════════════════════════════════════════════════════════════════
BEGIN;
DROP POLICY IF EXISTS storage_insert_photo_inscription ON storage.objects;
DROP POLICY IF EXISTS storage_update_photo_inscription_recente ON storage.objects;
DROP POLICY IF EXISTS storage_select_photo_inscription_recente ON storage.objects;
COMMIT;
