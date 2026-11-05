-- Demande d'avis : seulement si le client n'a pas encore laissé d'avis (05/11/2026).
-- La règle est en base, pour tous les chemins (fin de RDV site / appli, animal
-- récupéré, livraison de photos, co-propriétaires) et toutes les versions de l'appli :
--   • avis déjà laissé à ce pro (même profil, ou ancien avis sans profil) : la
--     notification avis_demande n'est pas créée ;
--   • avis laissé : les demandes déjà reçues pour ce pro sont retirées ;
--   • nom affiché : celui du PROFIL du pro, pas celui du compte.
-- Un pro avec deux profils (vétérinaire, ostéo) reste noté profil par profil.
-- Demandes obsolètes existantes retirées, gardées dans sauv_rappels_sante_20261104.
-- Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_avis_demande_controle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pro TEXT := NEW.data ->> 'pro_uid';
  v_profil TEXT := NULLIF(NEW.data ->> 'pro_profile_id', '');
  v_nom TEXT;
BEGIN
  IF NEW.type IS DISTINCT FROM 'avis_demande' OR v_pro IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM avis_pro a WHERE a.pro_uid = v_pro AND a.client_uid = NEW.uid
             AND (v_profil IS NULL OR a.pro_profile_id IS NULL OR a.pro_profile_id::text = v_profil)) THEN
    RETURN NULL; -- avis déjà laissé : pas de demande
  END IF;
  IF v_profil IS NOT NULL THEN
    SELECT NULLIF(trim(COALESCE(nom, '')), '') INTO v_nom FROM user_profiles_complet WHERE id::text = v_profil LIMIT 1;
    IF v_nom IS NOT NULL THEN
      IF NULLIF(NEW.data ->> 'pro_nom', '') IS NOT NULL THEN
        NEW.body := replace(NEW.body, NEW.data ->> 'pro_nom', v_nom);
      END IF;
      NEW.data := NEW.data || jsonb_build_object('pro_nom', v_nom);
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_avis_demande_controle ON public.notifications;
CREATE TRIGGER trg_avis_demande_controle BEFORE INSERT ON public.notifications
  FOR EACH ROW WHEN (NEW.type = 'avis_demande') EXECUTE FUNCTION public.pm_avis_demande_controle();

-- Avis laissé : demandes reçues pour ce pro retirées.
CREATE OR REPLACE FUNCTION public.pm_avis_retire_demandes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM notifications n
   WHERE n.type = 'avis_demande' AND n.uid = NEW.client_uid AND n.data ->> 'pro_uid' = NEW.pro_uid
     AND (NEW.pro_profile_id IS NULL OR NULLIF(n.data ->> 'pro_profile_id', '') IS NULL
          OR n.data ->> 'pro_profile_id' = NEW.pro_profile_id::text);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW; -- ne jamais bloquer l'enregistrement d'un avis
END;
$function$;

DROP TRIGGER IF EXISTS trg_avis_retire_demandes ON public.avis_pro;
CREATE TRIGGER trg_avis_retire_demandes AFTER INSERT ON public.avis_pro
  FOR EACH ROW EXECUTE FUNCTION public.pm_avis_retire_demandes();

-- Demandes déjà reçues alors que l'avis a été laissé.
WITH suppr AS (
  DELETE FROM notifications n USING avis_pro a
   WHERE n.type = 'avis_demande' AND n.uid = a.client_uid AND n.data ->> 'pro_uid' = a.pro_uid
     AND (a.pro_profile_id IS NULL OR NULLIF(n.data ->> 'pro_profile_id', '') IS NULL
          OR n.data ->> 'pro_profile_id' = a.pro_profile_id::text)
  RETURNING n.*
)
INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne)
SELECT 'notifications_avis', to_jsonb(s) FROM (SELECT DISTINCT ON (id) * FROM suppr) s;

COMMIT;
