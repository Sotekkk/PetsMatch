-- ─────────────────────────────────────────────────────────────────────────────
-- Cession : condition de stérilisation levée par le paiement des droits de
-- reproduction (la famille décide de ne pas stériliser).
-- Date : 2026-11-14
--
-- Le dossier est clos comme une stérilisation confirmée
-- (`sterilisation_validee = true` : plus aucun rappel, cf. Cloud Function
-- sendSterilisationReminders) mais `sterilise` reste à false.
-- `droits_repro_payes = true` distingue les deux issues.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS droits_repro_payes    BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS droits_repro_montant  NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS droits_repro_payes_le DATE;
