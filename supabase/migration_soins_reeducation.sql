-- ════════════════════════════════════════════════════════════════════════
-- Soins & Rééducation — refonte du module « suivis morpho » (ostéopathie,
-- physiothérapie, rééducation, bilans morphologiques).
--
-- Principe : UNE séance = UNE ligne suivis_morpho = UN PDF. On étend la table
-- existante (aucune nouvelle table de séance, aucune donnée supprimée) :
--   • sections du compte rendu : observations / bilan, intervention,
--     suivi recommandé, orientation vétérinaire, lieu, intitulé court ;
--   • anatomie facultative (avec_anatomie) ;
--   • statut brouillon → finalise (+ finalise_a) ; le partage au propriétaire
--     reste notifie_a (RLS migration_morpho_brouillons_pro inchangée) ;
--   • exercices / conseils (table rattachée, même RLS que photos/vidéos) ;
--   • versions : toute modification d'un compte rendu FINALISÉ archive
--     d'abord la version précédente (trigger) — rien n'est écrasé.
-- Anciens bilans : statut NULL = ancien suivi (affiché tel quel, titre
-- d'après type_suivi, aucun champ nouveau rempli d'office).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.suivis_morpho
  ADD COLUMN IF NOT EXISTS intitule            TEXT,
  ADD COLUMN IF NOT EXISTS observations_bilan  TEXT,
  ADD COLUMN IF NOT EXISTS intervention        TEXT,
  ADD COLUMN IF NOT EXISTS suivi_recommande    TEXT,
  ADD COLUMN IF NOT EXISTS orientation_veto    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lieu                TEXT,      -- cabinet | exterieur
  ADD COLUMN IF NOT EXISTS avec_anatomie       BOOLEAN,   -- NULL = ancien suivi
  ADD COLUMN IF NOT EXISTS statut              TEXT,      -- brouillon | finalise (NULL = ancien suivi)
  ADD COLUMN IF NOT EXISTS finalise_a          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS version             INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS updated_at          TIMESTAMPTZ;

DO $$ BEGIN
  ALTER TABLE public.suivis_morpho
    ADD CONSTRAINT suivis_morpho_statut_chk CHECK (statut IS NULL OR statut IN ('brouillon', 'finalise'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.suivis_morpho
    ADD CONSTRAINT suivis_morpho_lieu_chk CHECK (lieu IS NULL OR lieu IN ('cabinet', 'exterieur'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_pro_statut ON public.suivis_morpho (pro_profile_id, statut);

-- ── Exercices / conseils (dans le même PDF) ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.suivis_morpho_exercices (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id    UUID NOT NULL REFERENCES public.suivis_morpho(id) ON DELETE CASCADE,
  ordre       INTEGER NOT NULL DEFAULT 0,
  nom         TEXT NOT NULL,
  description TEXT,
  consignes   TEXT,
  frequence   TEXT,
  duree       TEXT,
  precautions TEXT,
  photo_url   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_suivis_morpho_exercices_suivi ON public.suivis_morpho_exercices (suivi_id, ordre);

ALTER TABLE public.suivis_morpho_exercices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS suivis_morpho_exercices_related_select ON public.suivis_morpho_exercices;
CREATE POLICY suivis_morpho_exercices_related_select ON public.suivis_morpho_exercices
  FOR SELECT USING (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), false));
DROP POLICY IF EXISTS suivis_morpho_exercices_related_insert ON public.suivis_morpho_exercices;
CREATE POLICY suivis_morpho_exercices_related_insert ON public.suivis_morpho_exercices
  FOR INSERT WITH CHECK (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true));
DROP POLICY IF EXISTS suivis_morpho_exercices_related_update ON public.suivis_morpho_exercices;
CREATE POLICY suivis_morpho_exercices_related_update ON public.suivis_morpho_exercices
  FOR UPDATE USING (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true))
  WITH CHECK (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true));
DROP POLICY IF EXISTS suivis_morpho_exercices_related_delete ON public.suivis_morpho_exercices;
CREATE POLICY suivis_morpho_exercices_related_delete ON public.suivis_morpho_exercices
  FOR DELETE USING (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true));

-- ── Versions (traçabilité après finalisation) ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.suivis_morpho_versions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id    UUID NOT NULL REFERENCES public.suivis_morpho(id) ON DELETE CASCADE,
  version     INTEGER NOT NULL,
  snapshot    JSONB NOT NULL,        -- ligne suivis_morpho + exercices au moment de l'archivage
  modifie_par TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_suivis_morpho_versions_suivi ON public.suivis_morpho_versions (suivi_id, version);

ALTER TABLE public.suivis_morpho_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS suivis_morpho_versions_select ON public.suivis_morpho_versions;
CREATE POLICY suivis_morpho_versions_select ON public.suivis_morpho_versions
  FOR SELECT USING (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), false));
-- Écriture : uniquement par le trigger (SECURITY DEFINER) — ni insert, ni
-- update, ni delete côté client : l'historique ne peut pas être réécrit.

CREATE OR REPLACE FUNCTION public.suivis_morpho_archiver_version()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Seul un compte rendu FINALISÉ est versionné ; le brouillon se modifie librement.
  IF OLD.statut IS DISTINCT FROM 'finalise' THEN
    RETURN NEW;
  END IF;
  -- Partage seul (notifie_a) : pas une correction du contenu. L'appli
  -- renseigne updated_at à CHAQUE enregistrement d'un compte rendu finalisé
  -- (y compris quand seuls les exercices, table rattachée, changent) : la
  -- version précédente est alors toujours archivée.
  IF (to_jsonb(NEW) - 'notifie_a' - 'version')
     = (to_jsonb(OLD) - 'notifie_a' - 'version') THEN
    RETURN NEW;
  END IF;
  INSERT INTO suivis_morpho_versions (suivi_id, version, snapshot, modifie_par)
  VALUES (
    OLD.id, OLD.version,
    to_jsonb(OLD) || jsonb_build_object('exercices', COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY e.ordre) FROM suivis_morpho_exercices e WHERE e.suivi_id = OLD.id
    ), '[]'::jsonb)),
    auth.jwt() ->> 'sub'
  );
  NEW.version := OLD.version + 1;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_suivis_morpho_version ON public.suivis_morpho;
CREATE TRIGGER trg_suivis_morpho_version
  BEFORE UPDATE ON public.suivis_morpho
  FOR EACH ROW EXECUTE FUNCTION public.suivis_morpho_archiver_version();

COMMIT;

NOTIFY pgrst, 'reload schema';
