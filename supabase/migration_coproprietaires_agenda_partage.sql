-- Co-propriété d'un animal (animaux_proprietes, foyers particuliers) :
--   1. l'agenda partagé — l'appli et le site chargent déjà les événements des
--      autres co-propriétaires liés à l'animal (RDV véto, rappels vaccin /
--      vermifuge / traitement…), mais la RLS agenda_events (pm_acces_compte)
--      les bloquait : rien n'apparaissait ;
--   2. les tâches de soin (prises de traitement, profil_source 'particulier')
--      d'un animal partagé : visibles et validables par chaque
--      co-propriétaire — une seule tâche, cochée pour tous ;
--   3. RDV pris par un co-propriétaire : les autres sont prévenus
--      (notification « coproprio_rdv », hors fan-out générique).
-- Périmètre : co-propriétaires actifs, profils particuliers (comme
-- fanout_notif_coproprietaires) — jamais l'agenda d'un élevage.

CREATE OR REPLACE FUNCTION public.pm_copro_partage(p_animal text, p_auteur text, p_uid text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT p_animal IS NOT NULL AND p_auteur IS NOT NULL AND p_uid IS NOT NULL
    AND p_auteur <> p_uid
    AND EXISTS (
      SELECT 1 FROM animaux_proprietes a JOIN user_profiles up ON up.id = a.profile_id_proprio
      WHERE a.animal_id = p_animal AND a.uid_proprio = p_auteur
        AND a.date_fin IS NULL AND a.statut = 'actif' AND up.profile_type = 'particulier')
    AND EXISTS (
      SELECT 1 FROM animaux_proprietes b JOIN user_profiles up ON up.id = b.profile_id_proprio
      WHERE b.animal_id = p_animal AND b.uid_proprio = p_uid
        AND b.date_fin IS NULL AND b.statut = 'actif' AND up.profile_type = 'particulier');
$$;

-- 1. Agenda : lecture des événements d'un animal partagé.
DROP POLICY IF EXISTS agenda_events_copro_select ON public.agenda_events;
CREATE POLICY agenda_events_copro_select ON public.agenda_events
  FOR SELECT USING (
    animal_id IS NOT NULL
    AND public.pm_copro_partage(animal_id, uid, (auth.jwt() ->> 'sub'))
  );

-- 2. Tâches de soin du particulier : lecture + validation.
DROP POLICY IF EXISTS taches_elevage_copro_select ON public.taches_elevage;
CREATE POLICY taches_elevage_copro_select ON public.taches_elevage
  FOR SELECT USING (
    profil_source = 'particulier' AND animal_id IS NOT NULL
    AND public.pm_copro_partage(animal_id::text, uid_eleveur, (auth.jwt() ->> 'sub'))
  );

DROP POLICY IF EXISTS taches_elevage_copro_update ON public.taches_elevage;
CREATE POLICY taches_elevage_copro_update ON public.taches_elevage
  FOR UPDATE USING (
    profil_source = 'particulier' AND animal_id IS NOT NULL
    AND public.pm_copro_partage(animal_id::text, uid_eleveur, (auth.jwt() ->> 'sub'))
  ) WITH CHECK (
    profil_source = 'particulier' AND animal_id IS NOT NULL
    AND public.pm_copro_partage(animal_id::text, uid_eleveur, (auth.jwt() ->> 'sub'))
  );

-- 3. RDV demandé par un co-propriétaire : les autres sont prévenus.
CREATE OR REPLACE FUNCTION public.pm_rdv_prevenir_coproprietaires()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_co RECORD;
  v_animal text;
  v_client text;
  v_pro text;
  v_quand text;
BEGIN
  IF NEW.animal_id IS NULL OR NEW.animal_id = '' OR NEW.client_uid IS NULL
     OR COALESCE(NEW.cree_par_pro, false) THEN
    RETURN NEW;
  END IF;
  -- Le demandeur doit lui-même être co-propriétaire actif (particulier).
  IF NOT EXISTS (
    SELECT 1 FROM animaux_proprietes ap JOIN user_profiles up ON up.id = ap.profile_id_proprio
    WHERE ap.animal_id = NEW.animal_id AND ap.uid_proprio = NEW.client_uid
      AND ap.date_fin IS NULL AND ap.statut = 'actif' AND up.profile_type = 'particulier'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT nom INTO v_animal FROM animaux WHERE id = NEW.animal_id;
  SELECT NULLIF(trim(nom), '') INTO v_client FROM user_profiles WHERE id::text = NEW.client_profile_id::text;
  SELECT NULLIF(trim(nom), '') INTO v_pro FROM user_profiles WHERE id::text = NEW.pro_profile_id::text;
  v_quand := to_char(NEW.date_heure AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY "à" HH24"h"MI');

  FOR v_co IN
    SELECT DISTINCT ap.uid_proprio, ap.profile_id_proprio
    FROM animaux_proprietes ap JOIN user_profiles up ON up.id = ap.profile_id_proprio
    WHERE ap.animal_id = NEW.animal_id AND ap.date_fin IS NULL AND ap.statut = 'actif'
      AND ap.uid_proprio <> NEW.client_uid AND up.profile_type = 'particulier'
  LOOP
    INSERT INTO notifications (uid, type, title, body, profile_type, profile_id, recipient_profile_id, data, read, created_at)
    VALUES (
      v_co.uid_proprio, 'coproprio_rdv',
      'Rendez-vous demandé pour ' || COALESCE(v_animal, 'votre animal'),
      COALESCE(v_client, 'Le co-propriétaire') || ' a demandé un rendez-vous'
        || COALESCE(' chez ' || v_pro, '') || ' le ' || v_quand || '.',
      'particulier', v_co.profile_id_proprio, v_co.profile_id_proprio,
      jsonb_build_object('rdv_id', NEW.id, 'animal_id', NEW.animal_id),
      false, now()
    );
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rdv_prevenir_coproprietaires ON public.rdv;
CREATE TRIGGER trg_rdv_prevenir_coproprietaires
  AFTER INSERT ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.pm_rdv_prevenir_coproprietaires();
