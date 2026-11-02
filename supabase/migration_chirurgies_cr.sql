-- ════════════════════════════════════════════════════════════════════════
-- Comptes rendus préopératoire et opératoire — lot 3 des documents
-- vétérinaires. 02/11/2026.
--
--   • saisie structurée dans la fiche chirurgie existante : chirurgies.preop
--     et chirurgies.operatoire (jsonb : champs saisis + statut brouillon /
--     valide, valide_le, valide_par_uid, valide_par_profile_id, version) ;
--     PDF : preop_doc_url / operatoire_doc_url (bucket privé documents) ;
--   • clinique auteure : pro_uid / pro_profile_id ;
--   • seul un vétérinaire valide (pm_peut_prescrire sur un compte qui a un
--     profil vétérinaire) ; validateur et date posés par le serveur ;
--   • un document validé ne se modifie pas en silence : toute modification
--     (par un vétérinaire) archive la version précédente (contenu + PDF) dans
--     documents_historique et retire le PDF, à refaire ; version + 1 ;
--   • une fiche chirurgie avec un document validé ne se supprime pas
--     (sauf cascade : suppression de l'animal).
-- Les colonnes texte protocole_preop / protocole_postop restent (reprises
-- dans la saisie). Idempotent. Staging d'abord, puis prod AVANT le
-- déploiement ; déployer aussi la fonction lien-document (nouvelles colonnes).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.chirurgies
  ADD COLUMN IF NOT EXISTS preop                JSONB,
  ADD COLUMN IF NOT EXISTS operatoire           JSONB,
  ADD COLUMN IF NOT EXISTS preop_doc_url        TEXT,
  ADD COLUMN IF NOT EXISTS operatoire_doc_url   TEXT,
  ADD COLUMN IF NOT EXISTS pro_uid              TEXT,
  ADD COLUMN IF NOT EXISTS pro_profile_id       UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS documents_historique JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Le compte qui valide est un vétérinaire de la clinique auteure.
CREATE OR REPLACE FUNCTION public.pm_peut_valider_doc_veto(p_uid_compte text, p_profile_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_uid_compte IS NOT NULL
    AND EXISTS (SELECT 1 FROM user_profiles up WHERE up.uid = p_uid_compte AND up.profile_type = 'veterinaire'
                  AND (nullif(p_profile_id, '') IS NULL OR up.id::text = p_profile_id))
    AND public.pm_peut_prescrire(p_uid_compte, p_profile_id);
$$;
GRANT EXECUTE ON FUNCTION public.pm_peut_valider_doc_veto(text, text) TO anon, authenticated;

-- Contenu saisi d'un document (sans les champs de validation).
CREATE OR REPLACE FUNCTION public.pm_doc_contenu(d jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(d, '{}'::jsonb) - 'statut' - 'valide_le' - 'valide_par_uid' - 'valide_par_profile_id' - 'version';
$$;

CREATE OR REPLACE FUNCTION public.pm_chirurgie_controle()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub   text := auth.jwt() ->> 'sub';
  v_doc   text;
  v_old   jsonb;
  v_new   jsonb;
  v_url_o text;
  v_url_n text;
  v_old_v boolean;
  v_new_v boolean;
  v_vers  integer;
BEGIN
  IF v_sub IS NULL THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF pg_trigger_depth() <= 1 AND (OLD.preop ->> 'statut' = 'valide' OR OLD.operatoire ->> 'statut' = 'valide') THEN
      RAISE EXCEPTION 'Intervention avec un compte rendu validé : suppression impossible' USING ERRCODE = '42501';
    END IF;
    RETURN OLD;
  END IF;

  FOREACH v_doc IN ARRAY ARRAY['preop', 'operatoire'] LOOP
    IF v_doc = 'preop' THEN
      v_new := NEW.preop; v_url_n := NEW.preop_doc_url;
      v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.preop END;
      v_url_o := CASE WHEN TG_OP = 'UPDATE' THEN OLD.preop_doc_url END;
    ELSE
      v_new := NEW.operatoire; v_url_n := NEW.operatoire_doc_url;
      v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.operatoire END;
      v_url_o := CASE WHEN TG_OP = 'UPDATE' THEN OLD.operatoire_doc_url END;
    END IF;
    v_old_v := coalesce(v_old ->> 'statut', '') = 'valide';
    v_new_v := coalesce(v_new ->> 'statut', '') = 'valide';
    v_vers  := coalesce((v_old ->> 'version')::integer, 0);

    IF v_old_v AND v_new_v AND public.pm_doc_contenu(v_new) = public.pm_doc_contenu(v_old) THEN
      -- Document validé inchangé : validation conservée ; PDF déposé une seule fois.
      v_new := v_new || jsonb_build_object('valide_le', v_old -> 'valide_le', 'valide_par_uid', v_old -> 'valide_par_uid',
        'valide_par_profile_id', v_old -> 'valide_par_profile_id', 'version', v_old -> 'version');
      IF v_url_n IS DISTINCT FROM v_url_o AND coalesce(v_url_o, '') <> '' THEN
        RAISE EXCEPTION 'Compte rendu validé : PDF déjà déposé' USING ERRCODE = '42501';
      END IF;
    ELSIF v_old_v THEN
      -- Modification d'un document validé : vétérinaire seulement, ancienne version archivée.
      IF NEW.pro_uid IS DISTINCT FROM OLD.pro_uid
         OR NOT public.pm_peut_valider_doc_veto(NEW.pro_uid, coalesce(NEW.pro_profile_id::text, '')) THEN
        RAISE EXCEPTION 'Compte rendu validé : seul un vétérinaire de la clinique peut en faire une nouvelle version'
          USING ERRCODE = '42501';
      END IF;
      NEW.documents_historique := coalesce(NEW.documents_historique, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
        'document', v_doc, 'contenu', v_old, 'doc_url', v_url_o, 'archive_le', clock_timestamp(), 'archive_par_uid', v_sub));
      v_url_n := NULL;
      IF v_new_v THEN
        v_new := v_new || jsonb_build_object('valide_le', clock_timestamp(), 'valide_par_uid', v_sub, 'version', v_vers + 1);
      ELSE
        v_new := (coalesce(v_new, '{}'::jsonb) - 'valide_le' - 'valide_par_uid' - 'valide_par_profile_id')
          || jsonb_build_object('statut', 'brouillon', 'version', v_vers + 1);
      END IF;
    ELSIF v_new_v THEN
      -- Première validation.
      IF NOT public.pm_peut_valider_doc_veto(NEW.pro_uid, coalesce(NEW.pro_profile_id::text, '')) THEN
        RAISE EXCEPTION 'Seul un vétérinaire de la clinique valide un compte rendu' USING ERRCODE = '42501';
      END IF;
      v_new := v_new || jsonb_build_object('valide_le', clock_timestamp(), 'valide_par_uid', v_sub,
        'version', greatest(v_vers, 1));
      v_url_n := NULL;
    ELSIF v_new IS NOT NULL THEN
      -- Brouillon : jamais de validation posée à la main, pas de PDF.
      v_new := v_new - 'valide_le' - 'valide_par_uid' - 'valide_par_profile_id';
      IF v_new ->> 'statut' IS DISTINCT FROM 'brouillon' THEN v_new := v_new || '{"statut":"brouillon"}'::jsonb; END IF;
      v_url_n := NULL;
    END IF;

    IF v_doc = 'preop' THEN NEW.preop := v_new; NEW.preop_doc_url := v_url_n;
    ELSE NEW.operatoire := v_new; NEW.operatoire_doc_url := v_url_n; END IF;
  END LOOP;

  -- Historique : on ne fait qu'ajouter.
  IF TG_OP = 'UPDATE' AND NOT (coalesce(NEW.documents_historique, '[]'::jsonb) @> coalesce(OLD.documents_historique, '[]'::jsonb)) THEN
    RAISE EXCEPTION 'Historique des comptes rendus non modifiable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chirurgie_controle ON public.chirurgies;
CREATE TRIGGER trg_chirurgie_controle
  BEFORE INSERT OR UPDATE OR DELETE ON public.chirurgies
  FOR EACH ROW EXECUTE FUNCTION public.pm_chirurgie_controle();

NOTIFY pgrst, 'reload schema';

COMMIT;
