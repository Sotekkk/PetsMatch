-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : devis automatique
-- (Phase 2, item 3/5)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS devis (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  numero_devis      TEXT,
  date_devis        DATE NOT NULL DEFAULT CURRENT_DATE,
  date_validite     DATE,
  -- Client : soit un utilisateur PetsMatch existant (client_uid/client_profile_id),
  -- soit une saisie libre (nom/email/téléphone) — même logique que
  -- certificats_engagement pour les acquéreurs sans compte.
  client_uid        TEXT,
  client_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  nom_client        TEXT,
  prenom_client     TEXT,
  email_client      TEXT,
  telephone_client  TEXT,
  animal_id         TEXT,
  -- Lignes figées au moment de la création (comme cours_collectifs_participants.prix) :
  -- [{ "description": "...", "quantite": 1, "prix_unitaire": 45, "total": 45 }]
  lignes            JSONB NOT NULL DEFAULT '[]',
  total_ttc         NUMERIC(10,2) NOT NULL DEFAULT 0,
  note              TEXT,
  statut            TEXT NOT NULL DEFAULT 'brouillon', -- brouillon/envoye/accepte/refuse/expire
  token_acceptation TEXT UNIQUE,
  date_reponse      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devis_pro   ON devis(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_devis_token ON devis(token_acceptation);
CREATE INDEX IF NOT EXISTS idx_devis_client ON devis(client_uid);

ALTER TABLE devis ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select devis" ON devis;
CREATE POLICY "Select devis" ON devis FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert devis" ON devis;
CREATE POLICY "Insert devis" ON devis
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update devis" ON devis;
CREATE POLICY "Update devis" ON devis FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete devis" ON devis;
CREATE POLICY "Delete devis" ON devis FOR DELETE USING (true);
