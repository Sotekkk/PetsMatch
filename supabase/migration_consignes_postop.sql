-- ════════════════════════════════════════════════════════════════════════
-- Consignes postopératoires pour le propriétaire — lot 4 des documents
-- vétérinaires. 02/11/2026.
--
--   • document distinct du compte rendu opératoire : chirurgies.consignes
--     (jsonb : sections [{titre, texte}] en texte simple — titres « ## »,
--     listes « - », gras « **…** » — + statut / validation / version, comme
--     preop et operatoire) et consignes_doc_url (PDF, bucket privé) ;
--   • même contrôle que les comptes rendus d'intervention : l'ASV prépare,
--     seul un vétérinaire de la clinique valide ; validé = figé, une nouvelle
--     version archive l'ancienne (documents_historique) ;
--   • consignes_modeles : modèles de la clinique (base rédactionnelle,
--     modifiable à chaque animal) ; lus et écrits par l'équipe de la clinique.
-- Prérequis : migration_chirurgies_cr.sql. Idempotent. Staging d'abord, puis
-- prod AVANT le déploiement ; redéployer lien-document (consignes_doc_url).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.chirurgies
  ADD COLUMN IF NOT EXISTS consignes          JSONB,
  ADD COLUMN IF NOT EXISTS consignes_doc_url  TEXT;

-- Contrôle des documents d'intervention : preop, operatoire et consignes.
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
    IF pg_trigger_depth() <= 1 AND (OLD.preop ->> 'statut' = 'valide' OR OLD.operatoire ->> 'statut' = 'valide'
                                    OR OLD.consignes ->> 'statut' = 'valide') THEN
      RAISE EXCEPTION 'Intervention avec un document validé : suppression impossible' USING ERRCODE = '42501';
    END IF;
    RETURN OLD;
  END IF;

  FOREACH v_doc IN ARRAY ARRAY['preop', 'operatoire', 'consignes'] LOOP
    IF v_doc = 'preop' THEN
      v_new := NEW.preop; v_url_n := NEW.preop_doc_url;
      v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.preop END;
      v_url_o := CASE WHEN TG_OP = 'UPDATE' THEN OLD.preop_doc_url END;
    ELSIF v_doc = 'operatoire' THEN
      v_new := NEW.operatoire; v_url_n := NEW.operatoire_doc_url;
      v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.operatoire END;
      v_url_o := CASE WHEN TG_OP = 'UPDATE' THEN OLD.operatoire_doc_url END;
    ELSE
      v_new := NEW.consignes; v_url_n := NEW.consignes_doc_url;
      v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.consignes END;
      v_url_o := CASE WHEN TG_OP = 'UPDATE' THEN OLD.consignes_doc_url END;
    END IF;
    v_old_v := coalesce(v_old ->> 'statut', '') = 'valide';
    v_new_v := coalesce(v_new ->> 'statut', '') = 'valide';
    v_vers  := coalesce((v_old ->> 'version')::integer, 0);

    IF v_old_v AND v_new_v AND public.pm_doc_contenu(v_new) = public.pm_doc_contenu(v_old) THEN
      v_new := v_new || jsonb_build_object('valide_le', v_old -> 'valide_le', 'valide_par_uid', v_old -> 'valide_par_uid',
        'valide_par_profile_id', v_old -> 'valide_par_profile_id', 'version', v_old -> 'version');
      IF v_url_n IS DISTINCT FROM v_url_o AND coalesce(v_url_o, '') <> '' THEN
        RAISE EXCEPTION 'Document validé : PDF déjà déposé' USING ERRCODE = '42501';
      END IF;
    ELSIF v_old_v THEN
      IF NEW.pro_uid IS DISTINCT FROM OLD.pro_uid
         OR NOT public.pm_peut_valider_doc_veto(NEW.pro_uid, coalesce(NEW.pro_profile_id::text, '')) THEN
        RAISE EXCEPTION 'Document validé : seul un vétérinaire de la clinique peut en faire une nouvelle version'
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
      IF NOT public.pm_peut_valider_doc_veto(NEW.pro_uid, coalesce(NEW.pro_profile_id::text, '')) THEN
        RAISE EXCEPTION 'Seul un vétérinaire de la clinique valide ce document' USING ERRCODE = '42501';
      END IF;
      v_new := v_new || jsonb_build_object('valide_le', clock_timestamp(), 'valide_par_uid', v_sub,
        'version', greatest(v_vers, 1));
      v_url_n := NULL;
    ELSIF v_new IS NOT NULL THEN
      v_new := v_new - 'valide_le' - 'valide_par_uid' - 'valide_par_profile_id';
      IF v_new ->> 'statut' IS DISTINCT FROM 'brouillon' THEN v_new := v_new || '{"statut":"brouillon"}'::jsonb; END IF;
      v_url_n := NULL;
    END IF;

    IF v_doc = 'preop' THEN NEW.preop := v_new; NEW.preop_doc_url := v_url_n;
    ELSIF v_doc = 'operatoire' THEN NEW.operatoire := v_new; NEW.operatoire_doc_url := v_url_n;
    ELSE NEW.consignes := v_new; NEW.consignes_doc_url := v_url_n; END IF;
  END LOOP;

  IF TG_OP = 'UPDATE' AND NOT (coalesce(NEW.documents_historique, '[]'::jsonb) @> coalesce(OLD.documents_historique, '[]'::jsonb)) THEN
    RAISE EXCEPTION 'Historique des documents non modifiable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

-- ── Modèles de consignes de la clinique ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.consignes_modeles (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  nom               TEXT NOT NULL,
  type_intervention TEXT,
  sections          JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS consignes_modeles_profil_idx ON public.consignes_modeles (pro_profile_id);
ALTER TABLE public.consignes_modeles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS consignes_modeles_select ON public.consignes_modeles;
CREATE POLICY consignes_modeles_select ON public.consignes_modeles FOR SELECT
  USING (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_patients', 'vet_cr_rediger', 'vet_cr_valider', 'vet_ordonnances']));
DROP POLICY IF EXISTS consignes_modeles_write ON public.consignes_modeles;
CREATE POLICY consignes_modeles_write ON public.consignes_modeles FOR ALL
  USING (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_cr_rediger', 'vet_cr_valider', 'vet_ordonnances']))
  WITH CHECK (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_cr_rediger', 'vet_cr_valider', 'vet_ordonnances']));

NOTIFY pgrst, 'reload schema';

COMMIT;
