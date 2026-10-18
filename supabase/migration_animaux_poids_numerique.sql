-- animaux.poids : TEXTE → NOMBRE (kg).
-- Le poids était stocké en texte (« 11 », « 8,1 », « 12 kg », vide) : l'appli
-- le lisait comme un nombre et plantait (écran blanc à la prise de rendez-vous
-- toiletteur, grille de prix au poids). Les formulaires (appli + site)
-- envoient désormais un nombre ; les valeurs existantes sont converties
-- (virgule acceptée, « kg » retiré), les valeurs illisibles deviennent NULL.
--
-- Contrôle préalable (facultatif) — valeurs qui seront perdues :
--   SELECT id, nom, poids FROM animaux
--   WHERE coalesce(trim(poids), '') <> '' AND public.pm_poids_kg(poids) IS NULL;
-- Vues dépendantes (le changement de type échoue si une vue utilise la colonne) :
--   SELECT DISTINCT v.relname FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid
--   JOIN pg_class v ON v.oid = r.ev_class JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
--   WHERE d.refobjid = 'public.animaux'::regclass AND a.attname = 'poids';
-- Idempotent (ne fait rien si la colonne est déjà numérique).

CREATE OR REPLACE FUNCTION public.pm_poids_kg(v text) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN replace(regexp_replace(lower(trim(coalesce(v, ''))), '\s*kg$', ''), ',', '.') ~ '^[0-9]+(\.[0-9]+)?$'
    THEN replace(regexp_replace(lower(trim(v)), '\s*kg$', ''), ',', '.')::numeric
  END
$$;

DO $$
BEGIN
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'animaux' AND column_name = 'poids') IN ('text', 'character varying') THEN
    ALTER TABLE public.animaux ALTER COLUMN poids TYPE numeric USING public.pm_poids_kg(poids);
  END IF;
END $$;

-- Création d'un patient par la clinique : le poids saisi (texte) est converti.
CREATE OR REPLACE FUNCTION public.pm_creer_patient_clinique(
  p_clinique uuid, p_client_id uuid, p_client jsonb, p_animal jsonb)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid_clinique text;
  v_client uuid := p_client_id;
  v_animal text := gen_random_uuid()::text;
BEGIN
  IF NOT (public.pm_gere_clinique(p_clinique)
          OR public.pm_employe_profil(p_clinique, ARRAY['vet_patients', 'vet_agenda'])) THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  SELECT up.uid INTO v_uid_clinique FROM user_profiles up WHERE up.id = p_clinique;
  IF v_uid_clinique IS NULL THEN RAISE EXCEPTION 'Clinique introuvable'; END IF;
  IF coalesce(trim(p_animal ->> 'nom'), '') = '' THEN
    RAISE EXCEPTION 'Le nom de l''animal est obligatoire.' USING ERRCODE = 'P0001';
  END IF;

  IF v_client IS NULL THEN
    IF coalesce(trim(p_client ->> 'nom'), '') = '' THEN
      RAISE EXCEPTION 'Le nom du propriétaire est obligatoire.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO clients_clinique (clinique_profile_id, nom, prenom, telephone, email, adresse, code_postal, ville, notes)
    VALUES (p_clinique, trim(p_client ->> 'nom'), nullif(trim(p_client ->> 'prenom'), ''),
            nullif(trim(p_client ->> 'telephone'), ''), nullif(lower(trim(p_client ->> 'email')), ''),
            nullif(trim(p_client ->> 'adresse'), ''), nullif(trim(p_client ->> 'code_postal'), ''),
            nullif(trim(p_client ->> 'ville'), ''), nullif(trim(p_client ->> 'notes'), ''))
    RETURNING id INTO v_client;
  ELSIF NOT EXISTS (SELECT 1 FROM clients_clinique c WHERE c.id = v_client AND c.clinique_profile_id = p_clinique) THEN
    RAISE EXCEPTION 'Client inconnu pour cette clinique.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO animaux (id, uid_eleveur, profile_id, statut, client_clinique_id,
                       nom, espece, race, sexe, date_naissance, identification, poids, couleur)
  VALUES (v_animal, v_uid_clinique, p_clinique, 'patient_clinique', v_client,
          trim(p_animal ->> 'nom'), nullif(p_animal ->> 'espece', ''), nullif(trim(p_animal ->> 'race'), ''),
          nullif(p_animal ->> 'sexe', ''), nullif(p_animal ->> 'date_naissance', '')::date,
          nullif(trim(p_animal ->> 'identification'), ''), public.pm_poids_kg(p_animal ->> 'poids'),
          nullif(trim(p_animal ->> 'couleur'), ''));

  INSERT INTO animal_access (animal_id, pro_profile_id, granted_by_profile_id, permissions, statut, granted_at)
  VALUES (v_animal, p_clinique, p_clinique, ARRAY['read_basic', 'read_health', 'write_health'], 'active', now())
  ON CONFLICT (animal_id, pro_profile_id) DO UPDATE SET statut = 'active';

  RETURN v_animal;
END;
$$;
GRANT EXECUTE ON FUNCTION public.pm_creer_patient_clinique(uuid, uuid, jsonb, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
