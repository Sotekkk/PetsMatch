-- ══════════════════════════════════════════════════════════════════════════
-- Cession : identification obligatoire (27/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- L'écran de cession (site + appli) fait saisir l'identification manquante
-- avant de continuer. Contrôle aussi côté base, pour tout chemin :
--   • création d'une cession (table cessions) ;
--   • transfert de propriété (ceder_propriete_animal) — couvre les cessions
--     plus anciennes finalisées maintenant.
-- Exception : abandon par un PARTICULIER à une association / un refuge (qui
-- identifie l'animal à son arrivée).
-- Reprend ceder_propriete_animal de migration_cession_reprise_pro.sql, avec
-- le contrôle ajouté après la vérification des droits.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_cession_identification_ok(p_animal_id text, p_profile_acquereur uuid DEFAULT NULL)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    -- Identifié.
    EXISTS (SELECT 1 FROM animaux a WHERE a.id::text = p_animal_id AND nullif(trim(coalesce(a.identification, '')), '') IS NOT NULL)
    -- Ou abandon d'un particulier à une association.
    OR (
      p_profile_acquereur IS NOT NULL
      AND EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = p_profile_acquereur AND up.profile_type = 'association')
      AND NOT EXISTS (
        SELECT 1 FROM animaux_proprietes ap JOIN user_profiles p ON p.id::text = ap.profile_id_proprio::text
         WHERE ap.animal_id::text = p_animal_id AND ap.statut = 'actif' AND ap.date_fin IS NULL
           AND p.profile_type <> 'particulier')
    );
$function$;
GRANT EXECUTE ON FUNCTION public.pm_cession_identification_ok(text, uuid) TO anon, authenticated;

-- Création d'une cession.
CREATE OR REPLACE FUNCTION public.pm_cession_controle_identification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.animal_id IS NULL THEN RETURN NEW; END IF;
  -- Abandon par un particulier à une association / un refuge (aucun
  -- propriétaire actif autre qu'un particulier).
  IF NEW.qualite = 'refuge' AND NOT EXISTS (
       SELECT 1 FROM animaux_proprietes ap JOIN user_profiles p ON p.id::text = ap.profile_id_proprio::text
        WHERE ap.animal_id::text = NEW.animal_id::text AND ap.statut = 'actif' AND ap.date_fin IS NULL
          AND p.profile_type <> 'particulier') THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM animaux a WHERE a.id::text = NEW.animal_id::text
                  AND nullif(trim(coalesce(a.identification, '')), '') IS NOT NULL) THEN
    RAISE EXCEPTION 'Identification obligatoire : renseignez le n° d''identification de l''animal avant la cession.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_cession_controle_identification ON public.cessions;
CREATE TRIGGER trg_cession_controle_identification
  BEFORE INSERT ON public.cessions
  FOR EACH ROW EXECUTE FUNCTION public.pm_cession_controle_identification();

-- Transfert de propriété.
CREATE OR REPLACE FUNCTION public.ceder_propriete_animal(
  p_animal_id          TEXT,
  p_uid_acquereur      TEXT,
  p_profile_acquereur  UUID,
  p_date               DATE
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller  TEXT := auth.jwt() ->> 'sub';
  v_profile UUID := p_profile_acquereur;
  v_type    TEXT;
  v_date    DATE := COALESCE(p_date, CURRENT_DATE);
BEGIN
  IF v_caller IS NULL OR p_uid_acquereur IS NULL OR p_animal_id IS NULL THEN
    RAISE EXCEPTION 'ceder_propriete_animal: paramètres manquants';
  END IF;

  IF NOT (
    is_principal_owner_or_cogerant(p_animal_id, v_caller)
    OR (v_caller = p_uid_acquereur AND EXISTS (
          SELECT 1 FROM animaux a
           WHERE a.id = p_animal_id AND a.uid_acquereur = v_caller))
  ) THEN
    RAISE EXCEPTION 'ceder_propriete_animal: non autorisé' USING ERRCODE = '42501';
  END IF;

  -- Identification obligatoire (puce, tatouage, UELN, boucle, bague…) —
  -- sauf abandon par un particulier à une association (le refuge l'identifie).
  IF NOT public.pm_cession_identification_ok(p_animal_id, p_profile_acquereur) THEN
    RAISE EXCEPTION 'Identification obligatoire : renseignez le n° d''identification de l''animal avant la cession.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Le profil doit appartenir à l'acquéreur ; à défaut, son profil
  -- particulier (jamais un profil pro choisi au hasard).
  IF v_profile IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM user_profiles WHERE id = v_profile AND uid = p_uid_acquereur) THEN
    v_profile := NULL;
  END IF;
  IF v_profile IS NULL THEN
    SELECT id INTO v_profile FROM user_profiles
     WHERE uid = p_uid_acquereur AND profile_type = 'particulier'
     ORDER BY is_main DESC NULLS LAST LIMIT 1;
  END IF;
  SELECT profile_type INTO v_type FROM user_profiles WHERE id = v_profile;

  UPDATE animaux_proprietes
     SET date_fin = v_date
   WHERE animal_id = p_animal_id AND date_fin IS NULL
     AND statut = 'actif' AND uid_proprio <> p_uid_acquereur;

  DELETE FROM animaux_proprietes
   WHERE animal_id = p_animal_id AND statut = 'invite'
     AND uid_proprio <> p_uid_acquereur;

  INSERT INTO animaux_proprietes
    (animal_id, uid_proprio, profile_id_proprio, date_debut, date_fin,
     role_proprio, statut, transfert_principal_propose)
  VALUES
    (p_animal_id, p_uid_acquereur, v_profile, v_date, NULL,
     'principal', 'actif', false)
  ON CONFLICT (animal_id, uid_proprio) DO UPDATE
    SET profile_id_proprio = COALESCE(EXCLUDED.profile_id_proprio, animaux_proprietes.profile_id_proprio),
        date_debut  = EXCLUDED.date_debut,
        date_fin    = NULL,
        role_proprio = 'principal',
        statut      = 'actif',
        transfert_principal_propose = false;

  -- Reprise de la fiche par une association / un élevage.
  IF v_type IN ('association', 'eleveur') THEN
    UPDATE animaux
       SET uid_eleveur          = p_uid_acquereur,
           uid_proprietaire     = NULL,
           profile_id           = v_profile,
           is_association       = (v_type = 'association'),
           statut               = CASE WHEN v_type = 'association' THEN 'disponible' ELSE 'present' END,
           date_entree          = v_date,
           date_sortie          = NULL,
           fa_id                = NULL,
           uid_acquereur        = p_uid_acquereur,
           profile_id_acquereur = v_profile
     WHERE id = p_animal_id;
  ELSE
    UPDATE animaux
       SET profile_id_acquereur = COALESCE(v_profile, profile_id_acquereur)
     WHERE id = p_animal_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ceder_propriete_animal(TEXT, TEXT, UUID, DATE) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Vérification
SELECT tgname FROM pg_trigger WHERE tgname = 'trg_cession_controle_identification';

-- Retour arrière :
-- DROP TRIGGER IF EXISTS trg_cession_controle_identification ON public.cessions;
-- DROP FUNCTION IF EXISTS public.pm_cession_controle_identification();
-- puis réexécuter ceder_propriete_animal de migration_cession_reprise_pro.sql ;
-- DROP FUNCTION IF EXISTS public.pm_cession_identification_ok(text, uuid);
