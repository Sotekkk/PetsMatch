-- ════════════════════════════════════════════════════════════════════════
-- Balades ludiques — XP, avis et compteurs qui échouaient en silence.
--
-- 1) joueurs_xp : clé primaire user_uid, mais l'appli et le site enregistrent
--    les XP PAR PROFIL (upsert onConflict profile_id) → erreur, aucun XP
--    jamais enregistré (table vide). Clé primaire → profile_id.
-- 2) balades_ludiques_avis : unicité (balade_id, user_uid) alors que l'appli
--    et le site font upsert onConflict (balade_id, profile_id) → erreur, aucun
--    avis enregistré (table vide). Unicité → (balade_id, profile_id).
-- 3) Compteurs nb_favoris / nb_avis / note_moyenne / nb_joueurs /
--    nb_completions : mis à jour par le JOUEUR sur balades_ludiques, que seul
--    le créateur peut modifier (RLS) → jamais à jour. Désormais tenus par des
--    triggers SECURITY DEFINER sur favoris / avis / progressions.
-- 4) Nouvel avis → notification au créateur du parcours (profil créateur).
-- 5) xp_recompense jamais renseignée à la création (toujours 0) → défaut
--    calculé : 10 XP par étape + bonus de difficulté (modéré +20, difficile
--    +50), à l'insertion des points et en rattrapage des parcours existants.
-- Tables joueurs_xp et balades_ludiques_avis vides au 05/10/2026 : aucune
-- donnée perdue par les changements de clés.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

-- ── 1) joueurs_xp : une ligne par profil ─────────────────────────────────
DELETE FROM joueurs_xp WHERE profile_id IS NULL;
ALTER TABLE joueurs_xp DROP CONSTRAINT IF EXISTS joueurs_xp_pkey;
ALTER TABLE joueurs_xp ALTER COLUMN profile_id SET NOT NULL;
ALTER TABLE joueurs_xp ADD CONSTRAINT joueurs_xp_pkey PRIMARY KEY (profile_id);

-- ── 2) Avis : un avis par profil et par parcours ─────────────────────────
ALTER TABLE balades_ludiques_avis DROP CONSTRAINT IF EXISTS balades_ludiques_avis_balade_id_user_uid_key;
ALTER TABLE balades_ludiques_avis
  ADD CONSTRAINT balades_ludiques_avis_balade_id_profile_id_key UNIQUE (balade_id, profile_id);

-- ── 3) Compteurs tenus par la base ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_balade_recompter(p_balade uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE balades_ludiques b SET
    nb_favoris     = (SELECT count(*) FROM balades_ludiques_favoris f WHERE f.balade_id = p_balade),
    nb_avis        = (SELECT count(*) FROM balades_ludiques_avis a WHERE a.balade_id = p_balade),
    note_moyenne   = (SELECT round(avg(a.note)::numeric, 1) FROM balades_ludiques_avis a WHERE a.balade_id = p_balade),
    nb_joueurs     = (SELECT count(*) FROM balades_ludiques_progressions p WHERE p.balade_id = p_balade),
    nb_completions = (SELECT count(*) FROM balades_ludiques_progressions p
                       WHERE p.balade_id = p_balade AND p.statut = 'termine')
  WHERE b.id = p_balade;
END $$;

CREATE OR REPLACE FUNCTION public.pm_balade_compteurs_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM pm_balade_recompter(COALESCE(NEW.balade_id, OLD.balade_id));
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_balade_compteurs_favoris ON balades_ludiques_favoris;
CREATE TRIGGER trg_balade_compteurs_favoris AFTER INSERT OR DELETE ON balades_ludiques_favoris
  FOR EACH ROW EXECUTE FUNCTION pm_balade_compteurs_trigger();
DROP TRIGGER IF EXISTS trg_balade_compteurs_avis ON balades_ludiques_avis;
CREATE TRIGGER trg_balade_compteurs_avis AFTER INSERT OR UPDATE OR DELETE ON balades_ludiques_avis
  FOR EACH ROW EXECUTE FUNCTION pm_balade_compteurs_trigger();
DROP TRIGGER IF EXISTS trg_balade_compteurs_progressions ON balades_ludiques_progressions;
CREATE TRIGGER trg_balade_compteurs_progressions AFTER INSERT OR UPDATE OF statut OR DELETE ON balades_ludiques_progressions
  FOR EACH ROW EXECUTE FUNCTION pm_balade_compteurs_trigger();

-- ── 4) Nouvel avis → notification au créateur ────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_balade_avis_notif()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b record;
BEGIN
  SELECT id, titre, createur_uid, createur_profile_id INTO b FROM balades_ludiques WHERE id = NEW.balade_id;
  IF b.createur_uid IS NULL OR b.createur_uid = NEW.user_uid THEN RETURN NEW; END IF;
  INSERT INTO notifications (uid, type, title, body, profile_id, data, read)
  VALUES (
    b.createur_uid, 'balade_ludique_avis',
    '⭐ Nouvel avis — ' || coalesce(b.titre, 'votre parcours'),
    NEW.note || '/5' || CASE WHEN coalesce(NEW.commentaire, '') <> ''
                             THEN ' — « ' || left(NEW.commentaire, 140) || ' »' ELSE '' END,
    b.createur_profile_id,
    jsonb_build_object('balade_id', b.id),
    false);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_balade_avis_notif ON balades_ludiques_avis;
CREATE TRIGGER trg_balade_avis_notif AFTER INSERT ON balades_ludiques_avis
  FOR EACH ROW EXECUTE FUNCTION pm_balade_avis_notif();

-- ── 5) XP de récompense par défaut ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_balade_xp_defaut(p_balade uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE balades_ludiques b SET xp_recompense =
    10 * (SELECT count(*) FROM balades_ludiques_points p WHERE p.balade_id = b.id)
    + CASE b.difficulte WHEN 'difficile' THEN 50 WHEN 'modere' THEN 20 ELSE 0 END
  WHERE b.id = p_balade AND coalesce(b.xp_recompense, 0) = 0;
END $$;

CREATE OR REPLACE FUNCTION public.pm_balade_xp_defaut_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM pm_balade_xp_defaut(NEW.balade_id);
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_balade_xp_defaut ON balades_ludiques_points;
CREATE TRIGGER trg_balade_xp_defaut AFTER INSERT ON balades_ludiques_points
  FOR EACH ROW EXECUTE FUNCTION pm_balade_xp_defaut_trigger();

-- ── Rattrapage des parcours existants ────────────────────────────────────
SELECT pm_balade_xp_defaut(id), pm_balade_recompter(id) FROM balades_ludiques;

SELECT titre, xp_recompense, nb_favoris, nb_joueurs, nb_completions, nb_avis FROM balades_ludiques;

COMMIT;
