-- ════════════════════════════════════════════════════════════════════════
-- Demande d'accès d'un pro au dossier d'un animal (côté serveur).
--
-- Un pro SANS accès ne peut pas lire animaux_proprietes (RLS, à raison) :
-- la demande faite depuis l'appli échouait (« Propriétaire introuvable »,
-- ex. Luna, patient venu d'un RDV). Cette fonction :
--   • vérifie que p_pro_profile_id est un profil PRO de l'appelant ;
--   • retrouve le propriétaire principal actuel (sans l'exposer au pro) ;
--   • crée / relance la demande (animal_access 'pending') — sans jamais
--     rétrograder un accès déjà accordé ;
--   • notifie le propriétaire (vet_access_demande, réponse scopée au
--     profil demandeur) ; pas de nouvelle notification si une demande est
--     déjà en attente.
-- Retour : 'active' | 'active_write' | 'write_requested' (déjà accordé), 'pending' (déjà en
-- attente), 'envoyee' (demande créée).
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE OR REPLACE FUNCTION public.pm_demander_acces_animal(p_animal_id text, p_pro_profile_id uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_pro record;
  v_proprio record;
  v_animal_nom text;
  v_statut text;
  v_nom text;
BEGIN
  IF v_sub IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;

  SELECT id, nom, firstname, lastname, profile_type INTO v_pro
  FROM user_profiles WHERE id = p_pro_profile_id AND uid = v_sub;
  IF NOT FOUND OR v_pro.profile_type = 'particulier' THEN
    RAISE EXCEPTION 'Profil professionnel invalide' USING ERRCODE = '42501';
  END IF;

  SELECT uid_proprio, profile_id_proprio INTO v_proprio
  FROM animaux_proprietes
  WHERE animal_id = p_animal_id AND date_fin IS NULL AND coalesce(statut, 'actif') = 'actif'
  ORDER BY (role_proprio = 'principal') DESC NULLS LAST, date_debut DESC NULLS LAST
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Propriétaire introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF v_proprio.uid_proprio = v_sub THEN
    RETURN 'active'; -- le pro est lui-même propriétaire
  END IF;

  SELECT statut INTO v_statut FROM animal_access
  WHERE animal_id = p_animal_id AND pro_profile_id = p_pro_profile_id;
  IF v_statut IN ('active', 'active_write', 'write_requested', 'pending') THEN
    RETURN v_statut;
  END IF;

  INSERT INTO animal_access (animal_id, pro_profile_id, granted_by_profile_id, permissions, statut)
  VALUES (p_animal_id, p_pro_profile_id, v_proprio.profile_id_proprio,
          ARRAY['read_basic', 'read_health', 'write_health'], 'pending')
  ON CONFLICT (animal_id, pro_profile_id)
  DO UPDATE SET statut = 'pending', granted_by_profile_id = EXCLUDED.granted_by_profile_id;

  SELECT nom INTO v_animal_nom FROM animaux WHERE id = p_animal_id;
  v_nom := coalesce(nullif(trim(v_pro.nom), ''),
                    nullif(trim(coalesce(v_pro.firstname, '') || ' ' || coalesce(v_pro.lastname, '')), ''),
                    'Un professionnel');

  INSERT INTO notifications (uid, type, title, body, profile_id, data, read)
  VALUES (
    v_proprio.uid_proprio, 'vet_access_demande',
    'Demande d''accès — ' || v_nom,
    v_nom || ' demande l''accès au dossier de santé de ' || coalesce(v_animal_nom, 'votre animal') || '.',
    v_proprio.profile_id_proprio,
    jsonb_build_object('animal_id', p_animal_id, 'vet_id', v_sub, 'vet_nom', v_nom,
                       'is_clinic', nullif(trim(v_pro.nom), '') IS NOT NULL,
                       'animal_nom', coalesce(v_animal_nom, 'votre animal'),
                       'pro_profile_id', p_pro_profile_id),
    false);

  RETURN 'envoyee';
END;
$$;
REVOKE EXECUTE ON FUNCTION public.pm_demander_acces_animal(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pm_demander_acces_animal(text, uuid) TO anon, authenticated;

COMMIT;
