-- Cession : transfert de propriété atomique (animaux_proprietes)
-- ============================================================================
-- Depuis migration_animaux_coproprietaires.sql, l'index unique
-- idx_ap_one_principal interdit deux principaux actifs pour un même animal.
-- Le client ouvrait la ligne de l'acquéreur (role_proprio par défaut =
-- 'principal') AVANT de clôturer celle du cédant (exigé par la policy
-- d'INSERT) → violation d'unicité avalée par un catch : la cession était
-- « confirmée » mais l'animal n'apparaissait jamais dans « Mes animaux » de
-- l'acquéreur. Dans l'autre ordre, c'est la policy d'INSERT qui refuse.
--
-- Cette fonction fait les deux d'un bloc (SECURITY DEFINER) :
--   1. clôt toute la copropriété courante (principal + secondaires) ;
--   2. supprime les invitations en attente ;
--   3. ouvre (ou rouvre) la ligne de l'acquéreur en PRINCIPAL actif.
-- Appelant autorisé : le propriétaire principal / un cogérant actif, ou
-- l'acquéreur désigné sur la fiche (animaux.uid_acquereur) — cas où c'est
-- sa signature du contrat qui finalise la cession.
-- ============================================================================

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
  v_caller TEXT := auth.jwt() ->> 'sub';
  v_profile UUID := p_profile_acquereur;
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

  -- Le profil doit appartenir à l'acquéreur ; à défaut, son profil
  -- particulier (jamais un profil pro par défaut).
  IF v_profile IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM user_profiles WHERE id = v_profile AND uid = p_uid_acquereur) THEN
    v_profile := NULL;
  END IF;
  IF v_profile IS NULL THEN
    SELECT id INTO v_profile FROM user_profiles
     WHERE uid = p_uid_acquereur AND profile_type = 'particulier'
     ORDER BY is_main DESC NULLS LAST LIMIT 1;
  END IF;

  UPDATE animaux_proprietes
     SET date_fin = COALESCE(p_date, CURRENT_DATE)
   WHERE animal_id = p_animal_id AND date_fin IS NULL
     AND statut = 'actif' AND uid_proprio <> p_uid_acquereur;

  DELETE FROM animaux_proprietes
   WHERE animal_id = p_animal_id AND statut = 'invite'
     AND uid_proprio <> p_uid_acquereur;

  INSERT INTO animaux_proprietes
    (animal_id, uid_proprio, profile_id_proprio, date_debut, date_fin,
     role_proprio, statut, transfert_principal_propose)
  VALUES
    (p_animal_id, p_uid_acquereur, v_profile, COALESCE(p_date, CURRENT_DATE), NULL,
     'principal', 'actif', false)
  ON CONFLICT (animal_id, uid_proprio) DO UPDATE
    SET profile_id_proprio = COALESCE(EXCLUDED.profile_id_proprio, animaux_proprietes.profile_id_proprio),
        date_debut  = EXCLUDED.date_debut,
        date_fin    = NULL,
        role_proprio = 'principal',
        statut      = 'actif',
        transfert_principal_propose = false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ceder_propriete_animal(TEXT, TEXT, UUID, DATE) TO anon, authenticated;
