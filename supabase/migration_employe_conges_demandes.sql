-- ══════════════════════════════════════════════════════════════════════════
-- Congés employé — passage d'un simple registre (rempli par l'employeur) à
-- un vrai workflow de demande/validation, généralisé à toutes les
-- catégories pro (pas seulement toilettage) + planning hebdo (horaires)
-- lui aussi généralisé.
-- ══════════════════════════════════════════════════════════════════════════
-- employe_conges existait déjà (migration_employes_toilettage.sql) avec
-- id/employe_id/date_debut/date_fin/motif/created_at — jamais de notion de
-- validation : un employeur ajoutait directement un congé "acquis". On
-- ajoute :
--   - statut ('approuve' par défaut = comportement existant inchangé pour
--     les lignes déjà en base et pour un ajout direct par l'employeur ;
--     'en_attente' = demande faite par l'employé, à valider ; 'refuse')
--   - demande_par_uid : qui a créé la ligne (employé ou employeur) — affiche
--     "Demandé par X" côté employeur, distingue une demande d'un congé
--     déjà posé directement.
--   - reponse_note : note optionnelle de l'employeur en cas de refus.
--
-- RLS : jusqu'ici USING(true) partout (jamais sécurisé). Modèle : employeur/
-- cogérant du profil concerné = accès complet (lecture + création directe +
-- validation) ; l'employé concerné = lecture de ses propres congés +
-- création d'une demande (toujours en 'en_attente', jamais auto-approuvée
-- — WITH CHECK dédié) sur SA PROPRE ligne employes.
--
-- ⚠️ À TESTER après exécution :
--   1. Les congés déjà existants (toilettage) restent visibles, statut
--      "Approuvé".
--   2. Un employeur (n'importe quelle catégorie) ajoute directement un
--      congé pour un employé → statut "Approuvé" immédiatement.
--   3. Un employé (Mes Employeurs) demande un congé → apparaît "En attente"
--      chez l'employeur, qui peut Approuver/Refuser.
--   4. L'employé voit le statut de sa propre demande évoluer.
--   5. Un employé ne peut ni voir ni modifier les congés d'un collègue.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE employe_conges
  ADD COLUMN IF NOT EXISTS statut          TEXT NOT NULL DEFAULT 'approuve'
    CHECK (statut IN ('en_attente', 'approuve', 'refuse')),
  ADD COLUMN IF NOT EXISTS demande_par_uid TEXT,
  ADD COLUMN IF NOT EXISTS reponse_note    TEXT;

-- Réutilisable par toute table rattachée à un employé via employe_id —
-- SECURITY DEFINER pour éviter une dépendance circulaire avec les policies
-- d'employes/elevage_cogerants elles-mêmes.
CREATE OR REPLACE FUNCTION public.can_access_employe_row(p_employe_id BIGINT, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employes e
    WHERE e.id = p_employe_id
      AND (
        e.uid_eleveur = p_uid
        OR e.uid_employe = p_uid
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = e.uid_eleveur
            AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
        )
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_access_employe_row(BIGINT, TEXT, BOOLEAN) TO anon, authenticated;

ALTER TABLE employe_conges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "employe_conges_all" ON employe_conges;

CREATE POLICY "employe_conges_select" ON employe_conges
  FOR SELECT USING (public.can_access_employe_row(employe_conges.employe_id, (auth.jwt() ->> 'sub')));

-- INSERT : l'employeur/cogérant peut créer directement un congé "approuvé"
-- (comportement historique) ; l'employé ne peut créer QUE sa propre demande,
-- toujours 'en_attente' (jamais auto-approuvée) — deux policies distinctes
-- plutôt qu'une seule pour verrouiller ce point précisément.
CREATE POLICY "employe_conges_insert_employeur" ON employe_conges
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.id = employe_conges.employe_id
        AND (
          e.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = e.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "employe_conges_insert_employe" ON employe_conges
  FOR INSERT WITH CHECK (
    statut = 'en_attente'
    AND EXISTS (
      SELECT 1 FROM employes e
      WHERE e.id = employe_conges.employe_id
        AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true
    )
  );

-- UPDATE : l'employeur/cogérant valide/refuse (change le statut, ajoute une
-- note) ; l'employé ne peut modifier/annuler QUE sa propre demande tant
-- qu'elle est encore en attente (pas après validation/refus).
CREATE POLICY "employe_conges_update_employeur" ON employe_conges
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.id = employe_conges.employe_id
        AND (
          e.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = e.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "employe_conges_update_employe" ON employe_conges
  FOR UPDATE USING (
    statut = 'en_attente'
    AND EXISTS (
      SELECT 1 FROM employes e
      WHERE e.id = employe_conges.employe_id
        AND e.uid_employe = (auth.jwt() ->> 'sub')
    )
  );

-- DELETE : employeur/cogérant uniquement (retirer un congé, y compris déjà
-- approuvé) — l'employé annule via UPDATE (statut) tant qu'en attente, pas
-- de suppression directe pour lui.
CREATE POLICY "employe_conges_delete" ON employe_conges
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.id = employe_conges.employe_id
        AND (
          e.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = e.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- Vérification
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'employe_conges' ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "employe_conges_select" ON employe_conges;
-- DROP POLICY IF EXISTS "employe_conges_insert_employeur" ON employe_conges;
-- DROP POLICY IF EXISTS "employe_conges_insert_employe" ON employe_conges;
-- DROP POLICY IF EXISTS "employe_conges_update_employeur" ON employe_conges;
-- DROP POLICY IF EXISTS "employe_conges_update_employe" ON employe_conges;
-- DROP POLICY IF EXISTS "employe_conges_delete" ON employe_conges;
-- CREATE POLICY "employe_conges_all" ON employe_conges FOR ALL USING (true);
