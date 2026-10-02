-- ════════════════════════════════════════════════════════════════════════
-- Accès en écriture des pros de santé à un animal client.
--
-- Règle de l'appli ET du site (animal_fiche.dart _canWriteHealth,
-- mes-patients/[id] hasWriteAccess) : un pro de santé — vétérinaire,
-- santé (ostéo / kiné…), maréchal-ferrant — écrit dès que son accès est
-- ACTIF ; les autres pros (garde, éducation…) ont besoin d'une écriture
-- explicitement autorisée par le propriétaire ('active_write').
-- has_animal_access(…, true) exigeait 'active_write' pour TOUS : aucun pro
-- de santé ne pouvait enregistrer un suivi morpho (« new row violates
-- row-level security policy for table suivis_morpho »), ni écrire dans le
-- carnet de santé / suivi repro d'un client (can_access_animal_health /
-- _repro / _morpho s'appuient sur cette fonction).
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE OR REPLACE FUNCTION public.has_animal_access(p_animal_id text, p_uid text, p_require_write boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM animal_access aa
    JOIN user_profiles up ON up.id = aa.pro_profile_id
    WHERE aa.animal_id = p_animal_id
      AND up.uid = p_uid
      AND (
        aa.statut = 'active_write'
        OR (aa.statut = 'active'
            AND (NOT p_require_write
                 OR up.profile_type IN ('veterinaire', 'sante', 'marechal_ferrant')))
      )
  );
$function$;

COMMIT;
