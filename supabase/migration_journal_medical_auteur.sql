-- Journal médical : bon profil d'auteur (03/11/2026).
--
-- Constat : depuis les ordonnances en brouillon (migration_ordonnances_v2.sql),
-- la création d'une ordonnance n'a pas encore de praticien_profile_id → le
-- journal affichait le nom du COMPTE (ex. « Angelique Begrand ») au lieu du
-- profil utilisé (ex. « Vétérinaire test AB ») ; la validation d'une
-- ordonnance apparaissait comme une simple modification ; les comptes rendus
-- d'intervention et consignes (chirurgies) n'avaient jamais de profil.
--
-- Correction :
--   • ordonnance : création → profil rédacteur ; brouillon → validée / signée
--     = action « validation », profil du validateur ;
--   • chirurgies : libellé du document concerné (CR préopératoire, CR
--     opératoire, consignes) et « validation » quand il est validé ;
--   • sans profil sur la ligne : titulaire du compte pro de la ligne → profil
--     pro de la ligne ; employé de la clinique → son profil d'employé ;
--   • réparation des lignes déjà journalisées (ordonnances, chirurgies).
-- Prérequis : migration_journal_medical.sql. Idempotent.

BEGIN;

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
  v_doc    text;
BEGIN
  IF r ->> 'animal_id' IS NULL THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' AND v_sub IS NULL THEN RETURN NULL; END IF;

  v_action := CASE TG_OP WHEN 'INSERT' THEN 'creation' WHEN 'DELETE' THEN 'suppression' ELSE 'modification' END;
  IF TG_TABLE_NAME = 'comptes_rendus' AND TG_OP = 'UPDATE'
     AND r ->> 'statut' = 'valide' AND o ->> 'statut' IS DISTINCT FROM 'valide' THEN
    v_action := 'validation';
  END IF;
  IF TG_TABLE_NAME = 'ordonnances' AND TG_OP = 'UPDATE'
     AND r ->> 'statut' IN ('validee', 'signee') AND o ->> 'statut' = 'brouillon' THEN
    v_action := 'validation';
  END IF;

  v_lib := left(coalesce(r ->> 'motif', r ->> 'vaccin', r ->> 'nom', r ->> 'produit', r ->> 'intitule',
                         r ->> 'titre', r ->> 'notes', ''), 200);

  -- Intervention : document concerné (CR pré / opératoire, consignes).
  IF TG_TABLE_NAME = 'chirurgies' AND TG_OP = 'UPDATE' THEN
    FOREACH v_doc IN ARRAY ARRAY['preop', 'operatoire', 'consignes'] LOOP
      IF (r -> v_doc) IS DISTINCT FROM (o -> v_doc) THEN
        v_lib := left(CASE v_doc WHEN 'preop' THEN 'Compte rendu préopératoire'
                                 WHEN 'operatoire' THEN 'Compte rendu opératoire'
                                 ELSE 'Consignes postopératoires' END
                      || coalesce(' — ' || nullif(r ->> 'intitule', ''), ''), 200);
        IF r -> v_doc ->> 'statut' = 'valide' AND (o -> v_doc ->> 'statut') IS DISTINCT FROM 'valide' THEN
          v_action := 'validation';
        END IF;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  v_profil := CASE
    WHEN TG_TABLE_NAME = 'comptes_rendus' AND v_action = 'validation' THEN r ->> 'valide_par_profile_id'
    WHEN TG_TABLE_NAME = 'comptes_rendus' AND v_action = 'creation' THEN r ->> 'redige_par_profile_id'
    WHEN TG_TABLE_NAME = 'ordonnances' AND v_action = 'validation'
      THEN coalesce(r ->> 'valide_par_profile_id', r ->> 'praticien_profile_id')
    WHEN TG_TABLE_NAME = 'ordonnances' AND v_action = 'creation'
      THEN coalesce(r ->> 'redige_par_profile_id', r ->> 'praticien_profile_id')
    WHEN TG_TABLE_NAME = 'ordonnances' THEN r ->> 'praticien_profile_id'
  END;
  -- Sans profil sur la ligne : titulaire du compte pro → profil pro de la
  -- ligne ; employé de la clinique → son profil d'employé.
  IF nullif(v_profil, '') IS NULL AND v_sub IS NOT NULL AND r ->> 'pro_uid' IS NOT NULL THEN
    IF v_sub = r ->> 'pro_uid' THEN
      v_profil := r ->> 'pro_profile_id';
    ELSE
      SELECT e.employe_profile_id::text INTO v_profil
        FROM employes e
       WHERE e.uid_employe = v_sub AND e.uid_eleveur = r ->> 'pro_uid' AND e.actif = true
         AND (r ->> 'pro_profile_id' IS NULL OR e.eleveur_profile_id::text = r ->> 'pro_profile_id')
       LIMIT 1;
    END IF;
  END IF;

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

-- ── Réparation des lignes déjà journalisées ──────────────────────────────
-- Validation d'une ordonnance journalisée comme « modification » : celle de
-- son validateur, au moment de la validation.
UPDATE public.journal_medical j
   SET action = 'validation'
  FROM public.ordonnances o
 WHERE j.table_source = 'ordonnances' AND j.ligne_id = o.id::text AND j.action = 'modification'
   AND o.valide_le IS NOT NULL AND j.auteur_uid = o.valide_par_uid
   AND abs(extract(epoch FROM (j.cree_le - o.valide_le))) < 5;

-- Ordonnances sans profil d'auteur.
UPDATE public.journal_medical j
   SET auteur_profile_id = CASE
         WHEN j.action = 'creation' THEN coalesce(o.redige_par_profile_id, o.praticien_profile_id,
           CASE WHEN j.auteur_uid = o.pro_uid THEN o.pro_profile_id END)
         ELSE coalesce(CASE WHEN j.auteur_uid = o.valide_par_uid THEN coalesce(o.valide_par_profile_id, o.praticien_profile_id) END,
           CASE WHEN j.auteur_uid = o.pro_uid THEN o.pro_profile_id END)
       END
  FROM public.ordonnances o
 WHERE j.table_source = 'ordonnances' AND j.ligne_id = o.id::text AND j.auteur_profile_id IS NULL;

-- Chirurgies (documents d'intervention) : titulaire → profil pro de la ligne.
UPDATE public.journal_medical j
   SET auteur_profile_id = c.pro_profile_id
  FROM public.chirurgies c
 WHERE j.table_source = 'chirurgies' AND j.ligne_id = c.id::text AND j.auteur_profile_id IS NULL
   AND c.pro_profile_id IS NOT NULL AND j.auteur_uid = c.pro_uid;

-- Employés de la clinique : leur profil d'employé.
UPDATE public.journal_medical j
   SET auteur_profile_id = e.employe_profile_id
  FROM public.employes e
 WHERE j.auteur_profile_id IS NULL AND j.table_source IN ('ordonnances', 'chirurgies', 'comptes_rendus')
   AND j.pro_uid IS NOT NULL AND e.uid_eleveur = j.pro_uid AND e.uid_employe = j.auteur_uid
   AND (j.pro_profile_id IS NULL OR e.eleveur_profile_id = j.pro_profile_id);

NOTIFY pgrst, 'reload schema';

COMMIT;
