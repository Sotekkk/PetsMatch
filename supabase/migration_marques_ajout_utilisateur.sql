-- ══════════════════════════════════════════════════════════════════════════
-- Alimentation — les utilisateurs peuvent ajouter leur marque (croquettes /
-- pâtée) quand elle manque au catalogue marques_aliments
-- ══════════════════════════════════════════════════════════════════════════
-- Retour testeuse (29/09/2026) : marque de croquettes introuvable, impossible
-- de renseigner l'alimentation. Le catalogue (553 aliments) n'était
-- modifiable que par l'admin (lecture publique seule).
--
-- - ajoute_par_uid : auteur (NULL = catalogue officiel, seedé par l'équipe).
-- - kcal_estime    : true si la densité n'a pas été saisie par l'utilisateur
--                    et a été estimée (moyennes du catalogue selon espèce /
--                    type / âge / formule stérilisé) — affiché « estimé »
--                    pour inviter à la corriger avec la valeur du paquet.
-- - formule_sterilise : gamme stérilisé / light (sert à l'estimation).
--
-- Visibilité : un aliment ajouté par un membre est visible de tous (il sert
-- aux suivants), marqué « ajouté par un membre ». Modification / suppression
-- par son auteur ou un admin (is_admin_uid). Le catalogue officiel
-- (ajoute_par_uid NULL) reste non modifiable par les membres.
--
-- ⚠️ À TESTER après exécution :
--   1. Ajouter une marque depuis la fiche alimentation (appli/site) → elle
--      apparaît dans la recherche et est sélectionnée.
--   2. Un autre compte la voit, mais ne peut ni la modifier ni la supprimer.
--   3. Une marque du catalogue officiel ne peut pas être modifiée par un membre.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE marques_aliments ADD COLUMN IF NOT EXISTS ajoute_par_uid TEXT;
ALTER TABLE marques_aliments ADD COLUMN IF NOT EXISTS kcal_estime BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE marques_aliments ADD COLUMN IF NOT EXISTS formule_sterilise BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_marques_ajoute_par ON marques_aliments(ajoute_par_uid);

-- Lecture publique inchangée (policy marques_aliments_select existante).
DROP POLICY IF EXISTS "marques_aliments_insert_membre" ON marques_aliments;
CREATE POLICY "marques_aliments_insert_membre" ON marques_aliments
  FOR INSERT WITH CHECK (
    ajoute_par_uid IS NOT NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub')
  );

DROP POLICY IF EXISTS "marques_aliments_update_auteur" ON marques_aliments;
CREATE POLICY "marques_aliments_update_auteur" ON marques_aliments
  FOR UPDATE USING (
    (ajoute_par_uid IS NOT NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub'))
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  ) WITH CHECK (
    (ajoute_par_uid IS NOT NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub'))
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

DROP POLICY IF EXISTS "marques_aliments_delete_auteur" ON marques_aliments;
CREATE POLICY "marques_aliments_delete_auteur" ON marques_aliments
  FOR DELETE USING (
    (ajoute_par_uid IS NOT NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub'))
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

-- Les jetons Firebase arrivent en rôle anon (identité via auth.jwt()->>'sub') :
-- les droits de table doivent couvrir anon ET authenticated ; la RLS ci-dessus
-- fait le vrai filtrage.
GRANT SELECT, INSERT, UPDATE, DELETE ON marques_aliments TO anon, authenticated;

-- Vérification
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'marques_aliments' ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "marques_aliments_insert_membre" ON marques_aliments;
-- DROP POLICY IF EXISTS "marques_aliments_update_auteur" ON marques_aliments;
-- DROP POLICY IF EXISTS "marques_aliments_delete_auteur" ON marques_aliments;
-- REVOKE INSERT, UPDATE, DELETE ON marques_aliments FROM anon, authenticated;
-- (colonnes conservées : sans effet si inutilisées)
