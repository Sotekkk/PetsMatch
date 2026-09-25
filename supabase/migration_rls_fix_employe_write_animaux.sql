-- ══════════════════════════════════════════════════════════════════════════
-- Accès employé à la fiche animal — gated par leur autorisation précise
-- ══════════════════════════════════════════════════════════════════════════
-- Un employé actif (table `employes`) pouvait déjà VOIR les animaux de son
-- employeur (policy SELECT), mais la policy UPDATE de `animaux` ne
-- l'incluait pas du tout : impossible de modifier la fiche (nom, race,
-- couleur, identification…), quelle que soit sa permission accordée
-- (`employe_permissions.permission = 'write_animaux'`). La policy INSERT
-- ne l'incluait pas non plus (impossible de créer un animal pour son
-- employeur).
--
-- Contrairement au reste du fichier (RLS volontairement grossière —
-- « une personne SANS AUCUNE relation légitime ne peut rien lire/écrire »,
-- le contrôle fin restant côté code appli), on vérifie ici la permission
-- PRÉCISE (write_animaux) directement en RLS — demande explicite : l'accès
-- en écriture à la fiche animal est sensible (identité, généalogie...),
-- pas seulement une question de « fait partie de l'élevage ».
--
-- ⚠️ À TESTER après exécution :
--   1. Un employé SANS la permission « Modifier les animaux » ne peut
--      toujours pas éditer la fiche (comportement inchangé).
--   2. Un employé AVEC la permission « Modifier les animaux » peut
--      maintenant éditer la fiche (nom, race, couleur, identité...) —
--      c'est le bug rapporté.
--   3. Le gérant, un cogérant actif, le propriétaire et un co-propriétaire
--      continuent de fonctionner normalement (policies inchangées pour eux).
-- ══════════════════════════════════════════════════════════════════════════

-- Réutilisable pour d'autres tables si le même trou se confirme ailleurs
-- (write_sante, write_repro...) — SECURITY DEFINER pour éviter toute
-- dépendance circulaire avec la policy employe_permissions elle-même.
CREATE OR REPLACE FUNCTION public.employe_has_permission(p_eleveur_uid TEXT, p_employe_uid TEXT, p_permission TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employes e
    JOIN employe_permissions ep
      ON ep.eleveur_profile_id = e.eleveur_profile_id
     AND ep.employe_profile_id = e.employe_profile_id
    WHERE e.uid_eleveur = p_eleveur_uid
      AND e.uid_employe = p_employe_uid
      AND e.actif = true
      AND ep.permission = p_permission
  );
$$;
GRANT EXECUTE ON FUNCTION public.employe_has_permission(TEXT, TEXT, TEXT) TO anon, authenticated;

-- ── animaux : INSERT + UPDATE ouverts à l'employé avec write_animaux ──────
DROP POLICY IF EXISTS "animaux_related_insert" ON animaux;
DROP POLICY IF EXISTS "animaux_related_update" ON animaux;

CREATE POLICY "animaux_related_insert" ON animaux
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_proprietaire
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.employe_has_permission(animaux.uid_eleveur, (auth.jwt() ->> 'sub'), 'write_animaux')
  );

CREATE POLICY "animaux_related_update" ON animaux
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_proprietaire
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.employe_has_permission(animaux.uid_eleveur, (auth.jwt() ->> 'sub'), 'write_animaux')
    OR EXISTS (
      SELECT 1 FROM animaux_proprietes p
      WHERE p.animal_id = animaux.id
        AND p.uid_proprio = (auth.jwt() ->> 'sub')
        AND p.date_fin IS NULL
    )
    OR public.has_animal_access(animaux.id, (auth.jwt() ->> 'sub'), true)
  );

-- Vérification
SELECT policyname, cmd, qual FROM pg_policies WHERE tablename = 'animaux' ORDER BY cmd;
