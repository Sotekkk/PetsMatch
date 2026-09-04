-- ─────────────────────────────────────────────────────────────────────────────
-- Correction manuelle des coordonnées de l'acquéreur (bouton « Coordonnées »)
-- Permet à l'éleveur de corriger nom/tél/email/adresse quand le propriétaire
-- n'a pas (ou plus) de compte PetsMatch actif et lui transmet un changement
-- autrement (téléphone, mail...).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS acquereur_contact_manuel JSONB;
