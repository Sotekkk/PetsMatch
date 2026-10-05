-- Balades ludiques — rejouer un parcours.
-- Rejouer repasse la progression en « en_cours » (étape 1) en gardant
-- completed_at (1re réussite). nb_completions compte donc les joueurs ayant
-- terminé AU MOINS UNE FOIS (completed_at), et non l'état courant — sinon
-- rejouer faisait baisser le compteur. Trigger aussi sur completed_at.
BEGIN;

CREATE OR REPLACE FUNCTION public.pm_balade_recompter(p_balade uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE balades_ludiques b SET
    nb_favoris     = (SELECT count(*) FROM balades_ludiques_favoris f WHERE f.balade_id = p_balade),
    nb_avis        = (SELECT count(*) FROM balades_ludiques_avis a WHERE a.balade_id = p_balade),
    note_moyenne   = (SELECT round(avg(a.note)::numeric, 1) FROM balades_ludiques_avis a WHERE a.balade_id = p_balade),
    nb_joueurs     = (SELECT count(*) FROM balades_ludiques_progressions p WHERE p.balade_id = p_balade),
    nb_completions = (SELECT count(*) FROM balades_ludiques_progressions p
                       WHERE p.balade_id = p_balade AND p.completed_at IS NOT NULL)
  WHERE b.id = p_balade;
END $$;

DROP TRIGGER IF EXISTS trg_balade_compteurs_progressions ON balades_ludiques_progressions;
CREATE TRIGGER trg_balade_compteurs_progressions
  AFTER INSERT OR UPDATE OF statut, completed_at OR DELETE ON balades_ludiques_progressions
  FOR EACH ROW EXECUTE FUNCTION pm_balade_compteurs_trigger();

SELECT pm_balade_recompter(id) FROM balades_ludiques;

COMMIT;
