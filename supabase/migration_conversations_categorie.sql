-- ============================================================
-- PetsMatch — colonne "categorie" manquante sur conversations
-- Le code (MessagingHelper.openOrCreateConversation, lib/pages/message.dart)
-- lit/écrit conversations.categorie depuis longtemps (filtre par type de
-- conversation : Annonce / Animal perdu / Contact élevage / Discussion
-- libre / Service professionnel) mais la colonne n'a jamais été créée en
-- base — toute création de NOUVELLE conversation avec une catégorie
-- échouait silencieusement (PGRST204 : colonne introuvable), masqué tant
-- qu'une conversation existante entre les deux participants existait déjà.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS categorie TEXT;

CREATE INDEX IF NOT EXISTS idx_conversations_categorie ON conversations(categorie);
