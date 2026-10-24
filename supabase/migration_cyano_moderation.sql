-- ════════════════════════════════════════════════════════════════════════
-- Alertes cyanobactéries : auteur, retrait, validation par l'équipe.
--
--  • alerte_cyano_uid : compte qui a signalé l'alerte (posé par le serveur,
--    impossible à usurper). Avant, seul alerte_cyano_profile_id (profil actif)
--    était noté : « mes » alertes, tous profils confondus, n'apparaissaient
--    pas dans Mes contributions.
--  • alerte_cyano_validee / _validee_at : une alerte avec photo est vérifiée
--    par l'équipe PetsMatch (onglet admin Lieux naturels → Alertes cyano).
--  • Lever une alerte : son auteur tant qu'elle n'est pas vérifiée, sinon
--    l'équipe PetsMatch uniquement. Avant, n'importe quel compte pouvait lever
--    n'importe quelle alerte, même confirmée.
--
-- Idempotent. Remplace pm_natural_places_garde (migration_lieux_contributions_auteur.sql).
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.natural_places
  ADD COLUMN IF NOT EXISTS alerte_cyano_uid        TEXT,
  ADD COLUMN IF NOT EXISTS alerte_cyano_validee    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS alerte_cyano_validee_at TIMESTAMPTZ;

-- Alertes en cours : auteur retrouvé depuis alerte_cyano_profile_id
-- (id de profil ; uid sur d'anciennes lignes).
UPDATE public.natural_places np
   SET alerte_cyano_uid = coalesce(
         (SELECT up.uid FROM public.user_profiles up WHERE up.id::text = np.alerte_cyano_profile_id LIMIT 1),
         (SELECT up.uid FROM public.user_profiles up WHERE up.uid = np.alerte_cyano_profile_id LIMIT 1))
 WHERE np.alerte_cyano = true AND np.alerte_cyano_uid IS NULL AND np.alerte_cyano_profile_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_natural_places_cyano_uid
  ON public.natural_places (alerte_cyano_uid) WHERE alerte_cyano = true;

CREATE OR REPLACE FUNCTION public.pm_natural_places_garde()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_cyano text[] := ARRAY['alerte_cyano', 'alerte_cyano_date', 'alerte_cyano_profile_id',
                          'alerte_cyano_lat', 'alerte_cyano_lng', 'alerte_cyano_statut',
                          'alerte_cyano_photo_url', 'alerte_cyano_uid',
                          'alerte_cyano_validee', 'alerte_cyano_validee_at'];
  v_libres text[] := v_cyano || ARRAY['niveau_difficulte', 'nb_avis', 'note_moyenne', 'updated_at'];
  v_cyano_change boolean;
BEGIN
  -- Appels service / éditeur SQL (sans jeton) et administrateurs : libres.
  IF v_sub IS NULL OR is_admin_uid(v_sub) THEN
    -- Un admin qui signale lui-même une alerte (nouvelle date) en est l'auteur.
    IF v_sub IS NOT NULL AND NEW.alerte_cyano = true
       AND NEW.alerte_cyano_date IS DISTINCT FROM OLD.alerte_cyano_date
       AND NEW.alerte_cyano_uid IS NOT DISTINCT FROM OLD.alerte_cyano_uid THEN
      NEW.alerte_cyano_uid := v_sub;
      NEW.alerte_cyano_validee := false;
      NEW.alerte_cyano_validee_at := NULL;
    END IF;
    IF NEW.alerte_cyano IS DISTINCT FROM true THEN
      NEW.alerte_cyano_validee := false;
      NEW.alerte_cyano_validee_at := NULL;
    END IF;
    RETURN NEW;
  END IF;

  -- Alerte cyanobactéries (tout lieu, publié ou non).
  v_cyano_change :=
    (NEW.alerte_cyano, NEW.alerte_cyano_date, NEW.alerte_cyano_profile_id, NEW.alerte_cyano_lat,
     NEW.alerte_cyano_lng, NEW.alerte_cyano_statut, NEW.alerte_cyano_photo_url)
    IS DISTINCT FROM
    (OLD.alerte_cyano, OLD.alerte_cyano_date, OLD.alerte_cyano_profile_id, OLD.alerte_cyano_lat,
     OLD.alerte_cyano_lng, OLD.alerte_cyano_statut, OLD.alerte_cyano_photo_url);
  IF v_cyano_change THEN
    IF OLD.alerte_cyano = true AND OLD.alerte_cyano_validee THEN
      RAISE EXCEPTION 'Alerte vérifiée par l''équipe PetsMatch : elle seule peut la modifier ou la lever'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.alerte_cyano IS DISTINCT FROM true THEN
      -- Lever : l'auteur de l'alerte seulement.
      IF OLD.alerte_cyano = true AND OLD.alerte_cyano_uid IS DISTINCT FROM v_sub THEN
        RAISE EXCEPTION 'Seul l''auteur de l''alerte (ou l''équipe PetsMatch) peut la lever'
          USING ERRCODE = '42501';
      END IF;
      NEW.alerte_cyano_uid := NULL;
    ELSE
      -- Signaler / confirmer : l'auteur est toujours le compte connecté.
      NEW.alerte_cyano_uid := v_sub;
    END IF;
    NEW.alerte_cyano_validee := false;
    NEW.alerte_cyano_validee_at := NULL;
  ELSE
    NEW.alerte_cyano_uid := OLD.alerte_cyano_uid;
    NEW.alerte_cyano_validee := OLD.alerte_cyano_validee;
    NEW.alerte_cyano_validee_at := OLD.alerte_cyano_validee_at;
  END IF;

  -- Auteur d'un lieu non publié : tout, sauf se publier ou changer d'auteur ;
  -- la modification repasse par la modération.
  IF v_sub = OLD.submitted_by_uid AND OLD.statut <> 'valide' THEN
    NEW.submitted_by_uid := OLD.submitted_by_uid;
    NEW.statut := 'en_attente';
    RETURN NEW;
  END IF;
  -- Lieu publié (auteur compris) : seules les colonnes communautaires.
  IF (to_jsonb(NEW) - v_libres) IS DISTINCT FROM (to_jsonb(OLD) - v_libres) THEN
    RAISE EXCEPTION 'Un lieu publié ne peut être modifié que par l''équipe PetsMatch'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_natural_places_garde ON public.natural_places;
CREATE TRIGGER trg_natural_places_garde
  BEFORE UPDATE ON public.natural_places
  FOR EACH ROW EXECUTE FUNCTION public.pm_natural_places_garde();

COMMIT;

-- Vérification
SELECT nom, alerte_cyano_statut, alerte_cyano_uid, alerte_cyano_validee
  FROM public.natural_places WHERE alerte_cyano = true;
