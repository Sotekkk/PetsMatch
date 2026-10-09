-- Journal médical : traçabilité des actes et documents d'un animal
-- (qui a créé, modifié, validé ou supprimé, et quand). Clinique à plusieurs
-- vétérinaires / ASV : indispensable pour un dossier médical sérieux.
--
-- • Alimenté UNIQUEMENT par trigger (SECURITY DEFINER) : l'auteur vient du
--   jeton (auth.jwt() ->> 'sub'), jamais du client. Aucune écriture directe,
--   aucune modification / suppression possible (pas de policy d'écriture).
-- • Ne bloque jamais l'écriture métier : une erreur de journalisation est
--   ignorée (WARNING).
-- • Les mises à jour sans jeton (Cloud Functions : drapeaux de rappel) ne
--   sont pas journalisées ; les créations / suppressions le sont toujours.
-- • Complète les colonnes déjà horodatées côté serveur des comptes rendus
--   (redige_par_uid, valide_par_uid, valide_le — migration_clinique_equipe.sql).
--
-- À passer en staging d'abord, puis en prod.

BEGIN;

CREATE TABLE IF NOT EXISTS public.journal_medical (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  animal_id         text NOT NULL,
  table_source      text NOT NULL,
  ligne_id          text NOT NULL,
  action            text NOT NULL CHECK (action IN ('creation', 'modification', 'validation', 'suppression')),
  auteur_uid        text,
  auteur_profile_id uuid,
  pro_uid           text,
  pro_profile_id    uuid,
  libelle           text,
  cree_le           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS journal_medical_animal_idx ON public.journal_medical (animal_id, cree_le DESC);
CREATE INDEX IF NOT EXISTS journal_medical_ligne_idx ON public.journal_medical (table_source, ligne_id);

ALTER TABLE public.journal_medical ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.journal_medical FROM anon, authenticated;
GRANT SELECT ON public.journal_medical TO authenticated;

-- Lecture : l'auteur, l'équipe de la clinique qui détient le document,
-- ou toute personne ayant accès au dossier de l'animal (propriétaire,
-- co-propriétaires, pros avec accès accordé).
DROP POLICY IF EXISTS journal_medical_select ON public.journal_medical;
CREATE POLICY journal_medical_select ON public.journal_medical
  FOR SELECT USING (
    auteur_uid = (auth.jwt() ->> 'sub')
    OR (pro_uid IS NOT NULL AND public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
          ARRAY['vet_patients', 'vet_cr_rediger', 'vet_cr_valider', 'vet_ordonnances']))
    OR public.has_animal_access(animal_id, (auth.jwt() ->> 'sub'), false)
  );

CREATE OR REPLACE FUNCTION public.pm_journal_medical()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub    text := auth.jwt() ->> 'sub';
  r        jsonb := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  o        jsonb := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_action text;
  v_profil text;
  v_lib    text;
BEGIN
  IF r ->> 'animal_id' IS NULL THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' AND v_sub IS NULL THEN RETURN NULL; END IF;

  v_action := CASE TG_OP WHEN 'INSERT' THEN 'creation' WHEN 'DELETE' THEN 'suppression' ELSE 'modification' END;
  IF TG_TABLE_NAME = 'comptes_rendus' AND TG_OP = 'UPDATE'
     AND r ->> 'statut' = 'valide' AND o ->> 'statut' IS DISTINCT FROM 'valide' THEN
    v_action := 'validation';
  END IF;

  v_profil := CASE
    WHEN TG_TABLE_NAME = 'comptes_rendus' AND v_action = 'validation' THEN r ->> 'valide_par_profile_id'
    WHEN TG_TABLE_NAME = 'comptes_rendus' AND v_action = 'creation' THEN r ->> 'redige_par_profile_id'
    WHEN TG_TABLE_NAME = 'ordonnances' THEN r ->> 'praticien_profile_id'
  END;
  v_lib := left(coalesce(r ->> 'motif', r ->> 'vaccin', r ->> 'nom', r ->> 'produit', r ->> 'intitule',
                         r ->> 'titre', r ->> 'notes', ''), 200);

  BEGIN
    INSERT INTO public.journal_medical
      (animal_id, table_source, ligne_id, action, auteur_uid, auteur_profile_id, pro_uid, pro_profile_id, libelle)
    VALUES (r ->> 'animal_id', TG_TABLE_NAME, r ->> 'id', v_action, v_sub,
            NULLIF(v_profil, '')::uuid, r ->> 'pro_uid', NULLIF(r ->> 'pro_profile_id', '')::uuid, NULLIF(v_lib, ''));
    -- CR créé directement validé (vétérinaire) : trace aussi la validation.
    IF TG_TABLE_NAME = 'comptes_rendus' AND TG_OP = 'INSERT' AND r ->> 'statut' = 'valide' THEN
      INSERT INTO public.journal_medical
        (animal_id, table_source, ligne_id, action, auteur_uid, auteur_profile_id, pro_uid, pro_profile_id, libelle)
      VALUES (r ->> 'animal_id', TG_TABLE_NAME, r ->> 'id', 'validation', v_sub,
              NULLIF(r ->> 'valide_par_profile_id', '')::uuid, r ->> 'pro_uid',
              NULLIF(r ->> 'pro_profile_id', '')::uuid, NULLIF(v_lib, ''));
    END IF;
  EXCEPTION WHEN others THEN
    RAISE WARNING 'journal_medical : %', SQLERRM;
  END;
  RETURN NULL;
END;
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['comptes_rendus', 'ordonnances', 'vaccinations', 'traitements',
                           'vermifuges', 'antiparasitaires', 'chirurgies', 'allergies', 'radios', 'visites']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_journal_medical ON public.%I', t);
      EXECUTE format('CREATE TRIGGER trg_journal_medical AFTER INSERT OR UPDATE OR DELETE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.pm_journal_medical()', t);
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
