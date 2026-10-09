-- ============================================================
-- PetsMatch — Saillies : seuls les reproducteurs actifs (contrôle serveur)
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query → Run.
-- Idempotent (CREATE OR REPLACE + DROP TRIGGER IF EXISTS) : relançable.
--
-- Règle (miroir de lib/utils/reproducteurs.dart et website/src/lib/reproducteurs.ts) :
-- un animal INTERNE (fiche présente dans `animaux`) ne peut figurer dans une
-- NOUVELLE saillie — comme animal de la fiche (animal_id) ou comme partenaire
-- (partenaire_animal_id) — que s'il est :
--   · coché « Reproducteur »           (animaux.reproducteur = true)
--   · ni retraité, ni stérilisé         (is_retraite / sterilise ≠ true)
--   · présent dans le cheptel           (statut hors sorti, décédé, cession…)
-- Un reproducteur EXTÉRIEUR n'a pas de partenaire_animal_id (nom + identification
-- seulement) : il n'est jamais bloqué.
-- Seul l'INSERT est contrôlé : modifier une saillie passée reste possible même
-- si le reproducteur a été retraité ou cédé depuis (historique conservé).
-- ============================================================

CREATE OR REPLACE FUNCTION public.saillie_reproducteur_eligible(p_animal_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT COALESCE(a.reproducteur, FALSE)
        AND NOT COALESCE(a.is_retraite, FALSE)
        AND NOT COALESCE(a.sterilise, FALSE)
        AND COALESCE(a.statut, 'present') NOT IN
            ('sorti', 'decede', 'en_attente_cession', 'cession_en_cours', 'adopte', 'transfere')
       FROM animaux a WHERE a.id = p_animal_id),
    TRUE)  -- fiche introuvable : pas un animal interne → pas de blocage
$$;

CREATE OR REPLACE FUNCTION public.check_saillie_reproducteurs()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.animal_id IS NOT NULL AND NOT public.saillie_reproducteur_eligible(NEW.animal_id) THEN
    RAISE EXCEPTION 'REPRO_NON_ELIGIBLE: l''animal % n''est pas un reproducteur actif', NEW.animal_id
      USING ERRCODE = 'P0001';
  END IF;
  IF NULLIF(NEW.partenaire_animal_id, '') IS NOT NULL
     AND NOT public.saillie_reproducteur_eligible(NEW.partenaire_animal_id) THEN
    RAISE EXCEPTION 'REPRO_NON_ELIGIBLE: le partenaire % n''est pas un reproducteur actif', NEW.partenaire_animal_id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_saillie_reproducteurs ON saillies;
CREATE TRIGGER trg_check_saillie_reproducteurs
  BEFORE INSERT ON saillies
  FOR EACH ROW EXECUTE FUNCTION public.check_saillie_reproducteurs();

-- ── Tests (à lancer manuellement, dans une transaction annulée) ─────────────
-- BEGIN;
--   -- jeux d'essai : un chiot, un cédé, un reproducteur actif, un retraité
--   INSERT INTO animaux (id, uid_eleveur, nom, sexe, statut, reproducteur, is_retraite)
--   SELECT 't_chiot',   uid, 'Chiot',    'male', 'present', FALSE, FALSE FROM users LIMIT 1;
--   INSERT INTO animaux (id, uid_eleveur, nom, sexe, statut, reproducteur, is_retraite)
--   SELECT 't_cede',    uid, 'Cédé',     'male', 'sorti',   TRUE,  FALSE FROM users LIMIT 1;
--   INSERT INTO animaux (id, uid_eleveur, nom, sexe, statut, reproducteur, is_retraite)
--   SELECT 't_actif',   uid, 'Actif',    'male', 'present', TRUE,  FALSE FROM users LIMIT 1;
--   INSERT INTO animaux (id, uid_eleveur, nom, sexe, statut, reproducteur, is_retraite)
--   SELECT 't_retraite',uid, 'Retraité', 'male', 'present', TRUE,  TRUE  FROM users LIMIT 1;
--   INSERT INTO animaux (id, uid_eleveur, nom, sexe, statut, reproducteur)
--   SELECT 't_femelle', uid, 'Femelle',  'femelle', 'present', TRUE FROM users LIMIT 1;
--   SELECT public.saillie_reproducteur_eligible('t_chiot');     -- false
--   SELECT public.saillie_reproducteur_eligible('t_cede');      -- false
--   SELECT public.saillie_reproducteur_eligible('t_actif');     -- true
--   SELECT public.saillie_reproducteur_eligible('t_retraite');  -- false
--   SELECT public.saillie_reproducteur_eligible('inconnu');     -- true (extérieur)
--   -- étalon extérieur (pas de partenaire_animal_id) : accepté
--   INSERT INTO saillies (id, animal_id, date, nom_partenaire) VALUES ('t_s1', 't_femelle', now(), 'Étalon ext.');
--   -- reproducteur actif : accepté
--   INSERT INTO saillies (id, animal_id, date, partenaire_animal_id) VALUES ('t_s2', 't_femelle', now(), 't_actif');
--   -- retraité : refusé (REPRO_NON_ELIGIBLE)
--   INSERT INTO saillies (id, animal_id, date, partenaire_animal_id) VALUES ('t_s3', 't_femelle', now(), 't_retraite');
-- ROLLBACK;
