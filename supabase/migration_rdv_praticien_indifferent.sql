-- ════════════════════════════════════════════════════════════════════════
-- Clinique vétérinaire — RDV « Peu importe » et demandes de RDV à l'équipe.
-- (Suite de migration_clinique_rdv.sql.)
--
-- Décisions (08/10/2026) :
--   • « Peu importe » : la demande est posée PROVISOIREMENT sur le premier
--     praticien libre (instructeur_profile_id) — sur un créneau où deux
--     vétérinaires sont libres, il ne reste qu'une place tant que personne
--     n'a validé — et marquée praticien_indifferent : elle s'affiche dans
--     l'agenda de TOUS les praticiens. À la validation, celui qui accepte
--     (praticien, ASV ou gérant) choisit « Attribuer à » : un praticien la
--     prend pour lui, l'ASV l'attribue à un vétérinaire
--     (praticien_indifferent repasse à false).
--   • Nouvelle demande d'un client → notification aux praticiens concernés
--     (celui choisi, ou tous si « peu importe ») et aux employés autorisés
--     (droit vet_rdv_demandes, typiquement l'ASV). Le titulaire est déjà
--     notifié par l'appli / le site.
--
-- Multi-profil : scopé au profil clinique (employes.eleveur_profile_id).
-- La notification d'un employé porte SON profil (employe_profile_id).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS praticien_indifferent boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.pm_notifier_equipe_rdv()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nom  text;
  v_date text;
BEGIN
  IF NEW.statut IS DISTINCT FROM 'demande' OR coalesce(NEW.cree_par_pro, false)
     OR NEW.pro_profile_id IS NULL OR NEW.date_heure IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT coalesce(nullif(trim(up.nom), ''), 'la clinique') INTO v_nom
    FROM user_profiles up
   WHERE up.id::text = NEW.pro_profile_id AND up.profile_type = 'veterinaire';
  IF v_nom IS NULL THEN RETURN NEW; END IF;

  v_date := to_char(NEW.date_heure AT TIME ZONE 'Europe/Paris', 'DD/MM "à" HH24"h"MI');

  INSERT INTO notifications (uid, type, title, body, profile_id, data, read)
  SELECT DISTINCT ON (e.uid_employe)
         e.uid_employe, 'rdv_demande',
         'Nouvelle demande de RDV — ' || v_nom,
         coalesce(nullif(trim(NEW.motif), ''), 'RDV') || ' le ' || v_date
           || CASE WHEN NEW.praticien_indifferent THEN ' · vétérinaire au choix' ELSE '' END,
         e.employe_profile_id::text,
         jsonb_build_object('rdv_id', NEW.id, 'clinique_profile_id', NEW.pro_profile_id,
                            'clinique_uid', NEW.pro_uid),
         false
    FROM employes e
   WHERE e.eleveur_profile_id::text = NEW.pro_profile_id
     AND e.actif = true
     AND e.uid_employe IS NOT NULL
     AND e.uid_employe IS DISTINCT FROM NEW.pro_uid
     AND (
       (e.role_pro = 'veterinaire'
         AND (NEW.praticien_indifferent OR e.employe_profile_id = NEW.instructeur_profile_id))
       OR EXISTS (
         SELECT 1 FROM employe_permissions p
          WHERE p.eleveur_profile_id::text = e.eleveur_profile_id::text
            AND p.employe_profile_id::text = e.employe_profile_id::text
            AND p.permission = 'vet_rdv_demandes')
     );
  RETURN NEW;
EXCEPTION WHEN others THEN
  -- Une notification ratée ne doit jamais bloquer la réservation.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rdv_notifier_equipe ON public.rdv;
CREATE TRIGGER trg_rdv_notifier_equipe
  AFTER INSERT ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.pm_notifier_equipe_rdv();

COMMIT;
