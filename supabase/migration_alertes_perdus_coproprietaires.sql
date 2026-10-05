-- Alertes « animal perdu » et co-propriétaires.
-- L'écriture était réservée à uid_proprietaire (celui qui a déclaré) : un
-- co-propriétaire ne pouvait ni marquer l'animal retrouvé, ni déclarer pour
-- le compte du propriétaire principal. Règle projet : une table liée à un
-- animal se résout via animal_id (animaux_proprietes), pas via un uid figé.
BEGIN;

DROP POLICY IF EXISTS alertes_perdus_write ON alertes_perdus;
CREATE POLICY alertes_perdus_write ON alertes_perdus FOR ALL
  USING (
    (auth.jwt() ->> 'sub') = uid_proprietaire
    OR EXISTS (SELECT 1 FROM animaux_proprietes ap
               WHERE ap.animal_id = alertes_perdus.animal_id
                 AND ap.uid_proprio = (auth.jwt() ->> 'sub')
                 AND ap.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_proprietaire
    OR EXISTS (SELECT 1 FROM animaux_proprietes ap
               WHERE ap.animal_id = alertes_perdus.animal_id
                 AND ap.uid_proprio = (auth.jwt() ->> 'sub')
                 AND ap.date_fin IS NULL)
  );

SELECT policyname, cmd FROM pg_policies WHERE tablename = 'alertes_perdus';

COMMIT;
