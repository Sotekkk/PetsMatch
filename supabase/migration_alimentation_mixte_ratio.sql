-- Ajout de la colonne mixte_ratio_croq à la table alimentations
-- Stocke le % de croquettes dans une ration mixte chien/chat (0-100, défaut 70)
ALTER TABLE alimentations
  ADD COLUMN IF NOT EXISTS mixte_ratio_croq INTEGER DEFAULT 70;
