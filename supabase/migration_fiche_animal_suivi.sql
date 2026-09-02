-- Fiche animal (particulier) — onglets Documents / Éducation / Pension & Garde
-- ----------------------------------------------------------------------------
-- 1. Checklist d'exercices cochable côté propriétaire, dans les comptes rendus
--    de séance de l'éducateur / comportementaliste.
ALTER TABLE education_progression
  ADD COLUMN IF NOT EXISTS exercices_coches JSONB DEFAULT '[]'::jsonb;

-- 2. Les documents libres du propriétaire (contrat d'achat scanné, pédigrée
--    numérique, passeport, attestation d'assurance, factures…) sont stockés
--    dans animaux.documents (déjà JSONB, alimenté côté éleveur / site). Chaque
--    entrée : { nom, url, categorie, type, ajoute_le, date_expiration? }.
--    Aucun changement de schéma nécessaire — bloc conservé pour mémoire.
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS documents JSONB DEFAULT '[]'::jsonb;
