-- Cession à une ASSOCIATION ou un ÉLEVAGE : la fiche passe vraiment au nom
-- de l'acquéreur. À lancer après migration_cession_transfert_propriete.sql
-- (remplace la fonction ceder_propriete_animal).
-- ============================================================================
-- Avant : seule la ligne animaux_proprietes changeait de main ; la fiche
-- restait au nom du cédant (uid_eleveur) avec le statut « sorti ». L'asso /
-- l'élevage acquéreur voyait l'animal sans pouvoir le gérer (pas de
-- changement de statut, ni adoption, ni annonce, ni nouvelle cession).
--
-- Désormais, quand le profil acquéreur est 'association' ou 'eleveur', la
-- fiche est reprise : uid_eleveur / profile_id = acquéreur, statut
-- 'disponible' (asso) ou 'present' (élevage), date_entree = date de cession.
-- Un acquéreur PARTICULIER ne change rien à la fiche (statut 'sorti',
-- uid_eleveur = cédant) : le suivi de cession de l'éleveur (stérilisation,
-- anniversaires) repose dessus.
--
-- Les ANCIENS propriétaires (ligne animaux_proprietes clôturée) gardent la
-- lecture de la fiche : sans ça, l'animal repris disparaissait de
-- l'historique « Cédés » du cédant.
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

-- Lecture conservée pour les anciens propriétaires (historique « Cédés »).
DROP POLICY IF EXISTS animaux_select_anciens_proprietaires ON public.animaux;
CREATE POLICY animaux_select_anciens_proprietaires ON public.animaux
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM animaux_proprietes p
       WHERE p.animal_id = animaux.id
         AND p.uid_proprio = (auth.jwt() ->> 'sub')
         AND p.date_fin IS NOT NULL
    )
  );

-- ── Rattrapage : animaux déjà cédés à une asso / un élevage avant ce correctif
-- (propriétaire principal actif = profil pro, fiche encore au nom du cédant).
UPDATE animaux a
   SET uid_eleveur          = ap.uid_proprio,
       uid_proprietaire     = NULL,
       profile_id           = ap.profile_id_proprio,
       is_association       = (up.profile_type = 'association'),
       statut               = CASE WHEN up.profile_type = 'association' THEN 'disponible' ELSE 'present' END,
       date_entree          = COALESCE(ap.date_debut, CURRENT_DATE),
       date_sortie          = NULL,
       fa_id                = NULL,
       profile_id_acquereur = ap.profile_id_proprio
  FROM animaux_proprietes ap
  JOIN user_profiles up ON up.id = ap.profile_id_proprio
 WHERE ap.animal_id = a.id
   AND ap.date_fin IS NULL AND ap.statut = 'actif' AND ap.role_proprio = 'principal'
   AND up.profile_type IN ('association', 'eleveur')
   AND a.uid_acquereur = ap.uid_proprio
   AND a.uid_eleveur IS DISTINCT FROM ap.uid_proprio
   AND a.statut = 'sorti';
