-- ══════════════════════════════════════════════════════════════════════════
-- Doublons de puce (fiches de test) — une puce différente pour chaque fiche
-- ══════════════════════════════════════════════════════════════════════════
-- À passer AVANT migration_puce_unique.sql (le trigger refuserait ensuite une
-- puce déjà prise). Fiches gardées telles quelles, seule la puce change ; la
-- plus ancienne de chaque groupe garde la sienne :
--   1234567890123 : test (1781281694059) garde ; Utha (1782115718419) → 1234567890124 ;
--                   testasso (1790969916463) → 1234567890125
--   1234567890    : test 1 (1789126768226) garde ; test2 (1789127576768) → 1234567891
-- Refusé si une des nouvelles puces est déjà utilisée. Rien n'est supprimé.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM animaux
     WHERE regexp_replace(coalesce(identification, ''), '[^0-9A-Za-z]', '', 'g') IN ('1234567890124', '1234567890125', '1234567891')
  ) THEN
    RAISE EXCEPTION 'Une des nouvelles puces est déjà utilisée : rien n''a été modifié.';
  END IF;
END $$;

UPDATE animaux SET identification = '1234567890124', updated_at = now()
 WHERE id = '1782115718419' AND identification = '1234567890123';
UPDATE animaux SET identification = '1234567890125', updated_at = now()
 WHERE id = '1790969916463' AND identification = '1234567890123';
UPDATE animaux SET identification = '1234567891', updated_at = now()
 WHERE id = '1789127576768' AND identification = '1234567890';

-- Vérification : plus aucun doublon
SELECT regexp_replace(identification, '[^0-9A-Za-z]', '', 'g') AS puce, count(*), string_agg(id || ' ' || coalesce(nom, ''), ' | ')
  FROM animaux
 WHERE length(regexp_replace(coalesce(identification, ''), '[^0-9A-Za-z]', '', 'g')) >= 6
 GROUP BY 1 HAVING count(*) > 1;

COMMIT;
