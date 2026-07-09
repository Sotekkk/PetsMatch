-- Synchronise les colonnes synonymes issues des migrations incrémentales V1/V2
-- (acaced_numero/acaced, acaced_doc_url/diplome_url, phone/phone_number/telephone)
-- pour que l'app et le site web, qui ne lisent chacun qu'un sous-ensemble de ces
-- colonnes, voient toujours la même valeur peu importe quel client a écrit.

-- ============================================================
-- user_profiles : acaced_numero <-> acaced,
--                 acaced_doc_url <-> diplome_url,
--                 phone_number <-> phone <-> telephone (priorité phone_number)
-- ============================================================

CREATE OR REPLACE FUNCTION sync_user_profiles_synonym_columns()
RETURNS trigger AS $$
DECLARE
  v_phone text;
BEGIN
  -- N° ACACED
  IF NEW.acaced_numero IS DISTINCT FROM OLD.acaced_numero AND NULLIF(NEW.acaced_numero, '') IS NOT NULL THEN
    NEW.acaced := NEW.acaced_numero;
  ELSIF NEW.acaced IS DISTINCT FROM OLD.acaced AND NULLIF(NEW.acaced, '') IS NOT NULL THEN
    NEW.acaced_numero := NEW.acaced;
  END IF;

  -- Doc ACACED
  IF NEW.acaced_doc_url IS DISTINCT FROM OLD.acaced_doc_url AND NULLIF(NEW.acaced_doc_url, '') IS NOT NULL THEN
    NEW.diplome_url := NEW.acaced_doc_url;
  ELSIF NEW.diplome_url IS DISTINCT FROM OLD.diplome_url AND NULLIF(NEW.diplome_url, '') IS NOT NULL THEN
    NEW.acaced_doc_url := NEW.diplome_url;
  END IF;

  -- Téléphone : phone_number est prioritaire, "0000000000" traité comme vide
  IF NEW.phone_number IS DISTINCT FROM OLD.phone_number
     AND NULLIF(NEW.phone_number, '') IS NOT NULL
     AND NEW.phone_number <> '0000000000' THEN
    v_phone := NEW.phone_number;
  ELSIF NEW.phone IS DISTINCT FROM OLD.phone
        AND NULLIF(NEW.phone, '') IS NOT NULL
        AND NEW.phone <> '0000000000' THEN
    v_phone := NEW.phone;
  ELSIF NEW.telephone IS DISTINCT FROM OLD.telephone
        AND NULLIF(NEW.telephone, '') IS NOT NULL
        AND NEW.telephone <> '0000000000' THEN
    v_phone := NEW.telephone;
  END IF;

  IF v_phone IS NOT NULL THEN
    NEW.phone_number := v_phone;
    NEW.phone := v_phone;
    NEW.telephone := v_phone;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_user_profiles_synonyms ON user_profiles;
CREATE TRIGGER trg_sync_user_profiles_synonyms
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION sync_user_profiles_synonym_columns();

-- ============================================================
-- users : acaced_numero <-> acaced
-- ============================================================

CREATE OR REPLACE FUNCTION sync_users_synonym_columns()
RETURNS trigger AS $$
BEGIN
  IF NEW.acaced_numero IS DISTINCT FROM OLD.acaced_numero AND NULLIF(NEW.acaced_numero, '') IS NOT NULL THEN
    NEW.acaced := NEW.acaced_numero;
  ELSIF NEW.acaced IS DISTINCT FROM OLD.acaced AND NULLIF(NEW.acaced, '') IS NOT NULL THEN
    NEW.acaced_numero := NEW.acaced;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_users_synonyms ON users;
CREATE TRIGGER trg_sync_users_synonyms
  BEFORE INSERT OR UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION sync_users_synonym_columns();

-- ============================================================
-- Backfill ponctuel : réconcilie les lignes déjà divergentes
-- (le trigger ne joue que sur les écritures futures)
-- ============================================================

UPDATE user_profiles SET
  acaced_numero = COALESCE(NULLIF(acaced_numero, ''), acaced),
  acaced        = COALESCE(NULLIF(acaced, ''), acaced_numero)
WHERE acaced_numero IS DISTINCT FROM acaced;

UPDATE user_profiles SET
  acaced_doc_url = COALESCE(NULLIF(acaced_doc_url, ''), diplome_url),
  diplome_url    = COALESCE(NULLIF(diplome_url, ''), acaced_doc_url)
WHERE acaced_doc_url IS DISTINCT FROM diplome_url;

UPDATE user_profiles SET
  phone_number = COALESCE(NULLIF(NULLIF(phone_number, ''), '0000000000'), NULLIF(phone, '0000000000'), NULLIF(telephone, '0000000000')),
  phone        = COALESCE(NULLIF(NULLIF(phone_number, ''), '0000000000'), NULLIF(phone, '0000000000'), NULLIF(telephone, '0000000000')),
  telephone    = COALESCE(NULLIF(NULLIF(phone_number, ''), '0000000000'), NULLIF(phone, '0000000000'), NULLIF(telephone, '0000000000'))
WHERE COALESCE(NULLIF(phone_number, ''), '') IS DISTINCT FROM COALESCE(NULLIF(phone, ''), '')
   OR COALESCE(NULLIF(phone_number, ''), '') IS DISTINCT FROM COALESCE(NULLIF(telephone, ''), '');

UPDATE users SET
  acaced_numero = COALESCE(NULLIF(acaced_numero, ''), acaced),
  acaced        = COALESCE(NULLIF(acaced, ''), acaced_numero)
WHERE acaced_numero IS DISTINCT FROM acaced;
