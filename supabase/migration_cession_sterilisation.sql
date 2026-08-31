-- ─────────────────────────────────────────────────────────────────────────────
-- Cession : condition de stérilisation + suivi des chiots cédés + anniversaires
-- Date : 2026-08-29
-- ─────────────────────────────────────────────────────────────────────────────

-- ── cessions (workflow 2 signatures, créé côté appli) ───────────────────────
ALTER TABLE cessions
  ADD COLUMN IF NOT EXISTS prenom_acquereur         TEXT,
  ADD COLUMN IF NOT EXISTS sterilisation_requise    BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_age_mois   INTEGER,
  ADD COLUMN IF NOT EXISTS sterilisation_echeance   DATE,
  ADD COLUMN IF NOT EXISTS sterilisation_validee    BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_validee_at TIMESTAMPTZ;

-- ── animaux : colonnes miroir ──────────────────────────────────────────────
-- Le web ne crée pas de ligne `cessions`, et la fiche est transférée à
-- l'acquéreur à la confirmation : l'info de condition doit vivre sur `animaux`
-- pour la fiche acquéreur, l'onglet « Suivi cessions » et la Cloud Function.
-- `animaux.sterilise` (booléen existant, togglé par le propriétaire) sert de
-- « stérilisation déclarée faite ». `sterilisation_validee` = confirmée éleveur.
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS sterilisation_requise            BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_echeance           DATE,
  ADD COLUMN IF NOT EXISTS sterilisation_validee            BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_declaree_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sterilisation_eleveur_uid        TEXT,
  ADD COLUMN IF NOT EXISTS sterilisation_eleveur_profile_id UUID;

CREATE INDEX IF NOT EXISTS idx_animaux_sterilisation_suivi
  ON animaux(sterilisation_eleveur_uid)
  WHERE sterilisation_requise = TRUE;

-- ── user_profiles : envoi automatique du message d'anniversaire par élevage ──
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS cession_anniv_auto  BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS cession_anniv_texte TEXT;

-- Dédup des rappels : réutilise la table existante notifs_sent(key).
