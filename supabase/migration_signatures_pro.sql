-- ============================================================
-- PetsMatch — Signature manuscrite du professionnel (vétérinaire…), dessinée
-- une fois dans l'appli ou sur le site (comme pour les contrats) et apposée
-- sur ses comptes rendus et ordonnances (PDF générés de son côté).
-- Table à part, lisible et modifiable par son seul propriétaire : jamais dans
-- user_profiles (lisible publiquement) — une signature ne doit pas fuiter.
-- Les requêtes au jeton Firebase arrivent en rôle anon : droits anon + authenticated.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.signatures_pro (
  uid        text PRIMARY KEY,
  signature  text NOT NULL,          -- data-URL PNG (data:image/png;base64,…)
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.signatures_pro ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS signatures_pro_select ON public.signatures_pro;
DROP POLICY IF EXISTS signatures_pro_insert ON public.signatures_pro;
DROP POLICY IF EXISTS signatures_pro_update ON public.signatures_pro;
DROP POLICY IF EXISTS signatures_pro_delete ON public.signatures_pro;

CREATE POLICY signatures_pro_select ON public.signatures_pro
  FOR SELECT USING (uid = (auth.jwt() ->> 'sub'));
CREATE POLICY signatures_pro_insert ON public.signatures_pro
  FOR INSERT WITH CHECK (uid = (auth.jwt() ->> 'sub'));
CREATE POLICY signatures_pro_update ON public.signatures_pro
  FOR UPDATE USING (uid = (auth.jwt() ->> 'sub')) WITH CHECK (uid = (auth.jwt() ->> 'sub'));
CREATE POLICY signatures_pro_delete ON public.signatures_pro
  FOR DELETE USING (uid = (auth.jwt() ->> 'sub'));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.signatures_pro TO anon, authenticated;
