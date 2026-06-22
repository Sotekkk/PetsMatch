-- Fix employes table : uid_employe nullable + RLS permissive pour anon (Firebase Auth)
-- À exécuter dans Supabase Dashboard → SQL Editor

-- 1. Rendre uid_employe nullable (pour les bénévoles saisis manuellement sans compte PetsMatch)
ALTER TABLE employes ALTER COLUMN uid_employe DROP NOT NULL;

-- 2. Ajouter les colonnes manquantes pour les bénévoles manuels
ALTER TABLE employes
  ADD COLUMN IF NOT EXISTS prenom    TEXT,
  ADD COLUMN IF NOT EXISTS nom       TEXT,
  ADD COLUMN IF NOT EXISTS email     TEXT,
  ADD COLUMN IF NOT EXISTS telephone TEXT,
  ADD COLUMN IF NOT EXISTS notes     TEXT;

-- 3. RLS permissive pour le rôle anon (Firebase Auth, pas Supabase Auth)
ALTER TABLE employes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "employes_anon_select" ON employes;
DROP POLICY IF EXISTS "employes_anon_insert" ON employes;
DROP POLICY IF EXISTS "employes_anon_update" ON employes;
DROP POLICY IF EXISTS "employes_anon_delete" ON employes;

CREATE POLICY "employes_anon_select" ON employes FOR SELECT USING (true);
CREATE POLICY "employes_anon_insert" ON employes FOR INSERT WITH CHECK (true);
CREATE POLICY "employes_anon_update" ON employes FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "employes_anon_delete" ON employes FOR DELETE USING (true);

-- 4. Ajouter la colonne type (benevole / null = employé standard)
ALTER TABLE employes ADD COLUMN IF NOT EXISTS type TEXT;

-- 5. Index
CREATE INDEX IF NOT EXISTS idx_employes_type ON employes(uid_eleveur, type);
