-- Pension — rendez-vous d'arrivée / de départ (et d'essai) dans l'agenda du
-- client, avec rappel la veille et 30 min avant (15/11/2026).
--
--  • Les événements sont créés par /api/pension/sejour à l'acceptation du
--    séjour (service_role : la RLS refuse au pro d'écrire dans l'agenda du
--    client). Un événement par passage, pour tous les animaux de la demande.
--  • pension_entree_ids : lignes pension_entrees couvertes par l'événement.
--    pension_passage : 'arrivee' | 'depart' | 'essai'.
--  • Rappels envoyés par la Cloud Function sendAgendaRappels (rappels_auto).
--  • Trigger : séjour annulé → animal retiré de l'événement (supprimé s'il
--    n'en reste aucun) ; date / heure changée par la pension → événement
--    déplacé et rappels réarmés.

ALTER TABLE public.agenda_events
  ADD COLUMN IF NOT EXISTS pension_entree_ids   TEXT[],
  ADD COLUMN IF NOT EXISTS pension_passage      TEXT,
  ADD COLUMN IF NOT EXISTS rappels_auto         BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS rappel_veille_envoye BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS rappel_30min_envoye  BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS agenda_events_rappels_auto_idx
  ON public.agenda_events (date_debut) WHERE rappels_auto;
CREATE INDEX IF NOT EXISTS agenda_events_pension_entrees_idx
  ON public.agenda_events USING gin (pension_entree_ids);

CREATE OR REPLACE FUNCTION public.pension_agenda_client_sync()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Séjour annulé : l'animal sort de l'événement ; plus personne → supprimé.
  IF NEW.statut = 'annule' THEN
    IF OLD.statut IS DISTINCT FROM 'annule' THEN
      UPDATE agenda_events SET pension_entree_ids = array_remove(pension_entree_ids, NEW.id::text)
        WHERE pension_entree_ids @> ARRAY[NEW.id::text];
      DELETE FROM agenda_events
        WHERE pension_passage IS NOT NULL AND COALESCE(cardinality(pension_entree_ids), 0) = 0;
    END IF;
    RETURN NEW;
  END IF;

  -- Arrivée (ou essai) déplacée.
  IF (NEW.date_entree, NEW.heure_arrivee_prevue) IS DISTINCT FROM (OLD.date_entree, OLD.heure_arrivee_prevue)
     AND NEW.date_entree IS NOT NULL AND COALESCE(NEW.heure_arrivee_prevue, '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    UPDATE agenda_events
      SET date_debut = (NEW.date_entree + NEW.heure_arrivee_prevue::time) AT TIME ZONE 'Europe/Paris',
          rappel_veille_envoye = FALSE, rappel_30min_envoye = FALSE
      WHERE pension_entree_ids @> ARRAY[NEW.id::text] AND pension_passage IN ('arrivee', 'essai');
  END IF;

  -- Départ déplacé.
  IF (NEW.date_sortie_prevue, NEW.heure_depart_prevue) IS DISTINCT FROM (OLD.date_sortie_prevue, OLD.heure_depart_prevue)
     AND NEW.date_sortie_prevue IS NOT NULL AND COALESCE(NEW.heure_depart_prevue, '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    UPDATE agenda_events
      SET date_debut = (NEW.date_sortie_prevue + NEW.heure_depart_prevue::time) AT TIME ZONE 'Europe/Paris',
          rappel_veille_envoye = FALSE, rappel_30min_envoye = FALSE
      WHERE pension_entree_ids @> ARRAY[NEW.id::text] AND pension_passage = 'depart';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_pension_agenda_client_sync ON public.pension_entrees;
CREATE TRIGGER trg_pension_agenda_client_sync
  AFTER UPDATE OF statut, date_entree, date_sortie_prevue, heure_arrivee_prevue, heure_depart_prevue
  ON public.pension_entrees
  FOR EACH ROW EXECUTE FUNCTION public.pension_agenda_client_sync();
