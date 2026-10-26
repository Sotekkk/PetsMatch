-- ════════════════════════════════════════════════════════════════════════
-- RDV pris ou modifié par le professionnel → agenda du client (serveur).
--
-- Avant : l'appli et le site du pro écrivaient eux-mêmes l'événement dans
-- l'agenda du client (agenda_events, uid = client). La RLS
-- (agenda_events_related_insert / _update : pm_acces_compte) refuse cette
-- écriture pour un autre compte → un RDV créé par le vétérinaire pour un
-- client (« Nouveau RDV », planifié depuis la fiche patient) ou déplacé par
-- lui n'arrivait pas dans l'agenda du propriétaire. Le trigger
-- sync_rdv_agenda ne réagissait qu'à un CHANGEMENT de statut vers
-- « confirme » (pas à un RDV inséré directement confirmé, ni à un
-- changement d'heure).
--
-- Désormais : à l'insertion et à chaque changement de statut, d'heure, de
-- durée, de motif ou d'animal, l'événement du client est créé / mis à jour
-- côté serveur (SECURITY DEFINER), avec l'animal (→ visible des
-- co-propriétaires via agenda_events_copro_select) et le profil du client.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sync_rdv_agenda()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pro text;
  v_motif text;
  v_type text;
  v_titre text;
BEGIN
  IF NEW.client_uid IS NULL OR NEW.client_uid = '' THEN
    RETURN NEW;
  END IF;

  IF NEW.statut IN ('annule', 'refuse') THEN
    IF TG_OP = 'UPDATE' AND OLD.statut IS DISTINCT FROM NEW.statut THEN
      DELETE FROM agenda_events WHERE rdv_id = NEW.id;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.statut IS DISTINCT FROM 'confirme' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(trim(nom), ''), NULLIF(trim(nom_cabinet), '')) INTO v_pro
    FROM user_profiles WHERE id::text = NEW.pro_profile_id::text;
  IF v_pro IS NULL THEN
    SELECT COALESCE(NULLIF(name_elevage, ''), NULLIF(profession_pro, '')) INTO v_pro
      FROM users WHERE uid = NEW.pro_uid LIMIT 1;
  END IF;
  v_pro := COALESCE(v_pro, 'le professionnel');
  v_motif := NULLIF(trim(COALESCE(NEW.motif, '')), '');
  -- Miroir de _typeFromMotif (pro_agenda.dart).
  v_type := CASE
    WHEN lower(COALESCE(v_motif, '')) LIKE '%cours%' AND lower(v_motif) LIKE '%collectif%' THEN 'cours_collectif'
    WHEN lower(COALESCE(v_motif, '')) LIKE '%cours%' AND lower(v_motif) LIKE '%individuel%' THEN 'cours_individuel'
    WHEN lower(COALESCE(v_motif, '')) LIKE '%visite%' AND lower(v_motif) LIKE '%domicile%' THEN 'visite_domicile'
    WHEN lower(COALESCE(v_motif, '')) LIKE '%promenade%' THEN 'promenade'
    ELSE 'rdv' END;
  v_titre := CASE WHEN v_motif IS NOT NULL THEN v_motif || ' — ' || v_pro ELSE 'RDV avec ' || v_pro END;

  INSERT INTO agenda_events (uid, titre, type, date_debut, duree_minutes, animal_id, notes, rdv_id, pro_profile_id)
  VALUES (NEW.client_uid, v_titre, v_type, NEW.date_heure, NEW.duree_minutes,
          NULLIF(NEW.animal_id, ''), NEW.motif, NEW.id, NEW.client_profile_id::text)
  ON CONFLICT (rdv_id) WHERE rdv_id IS NOT NULL
  DO UPDATE SET titre = EXCLUDED.titre, type = EXCLUDED.type, date_debut = EXCLUDED.date_debut,
                duree_minutes = COALESCE(EXCLUDED.duree_minutes, agenda_events.duree_minutes),
                animal_id = COALESCE(EXCLUDED.animal_id, agenda_events.animal_id),
                notes = EXCLUDED.notes,
                pro_profile_id = COALESCE(EXCLUDED.pro_profile_id, agenda_events.pro_profile_id);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS rdv_agenda_sync ON public.rdv;
CREATE TRIGGER rdv_agenda_sync
  AFTER INSERT OR UPDATE OF statut, date_heure, duree_minutes, motif, animal_id ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.sync_rdv_agenda();
