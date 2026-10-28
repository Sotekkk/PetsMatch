-- ============================================================
-- PetsMatch — Notification « Nouvel avis » sur le BON profil du pro
-- (notifications.profile_id = avis_pro.pro_profile_id : elle n'apparaît plus
-- sur tous les profils du compte), avec de quoi ouvrir ses avis au clic
-- (data.pro_uid / data.pro_profile_id). Avis modifié par son auteur : le pro
-- est prévenu aussi. Pas d'émoticône dans le titre.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_notify_new_avis_pro()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.pro_uid IS NULL OR NEW.pro_uid = NEW.client_uid THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.note IS NOT DISTINCT FROM OLD.note
     AND NEW.commentaire IS NOT DISTINCT FROM OLD.commentaire THEN
    RETURN NEW;
  END IF;
  INSERT INTO notifications (uid, profile_id, type, title, body, data) VALUES (
    NEW.pro_uid, NEW.pro_profile_id, 'new_avis_pro',
    CASE WHEN TG_OP = 'UPDATE' THEN 'Avis modifié' ELSE 'Nouvel avis' END,
    CASE WHEN TG_OP = 'UPDATE' THEN 'Un client a modifié son avis : ' ELSE 'Vous avez reçu un nouvel avis : ' END
      || NEW.note || '/5.',
    jsonb_build_object('avis_id', NEW.id, 'type', 'new_avis_pro',
      'pro_uid', NEW.pro_uid, 'pro_profile_id', NEW.pro_profile_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_avis_pro ON avis_pro;
CREATE TRIGGER trg_notify_new_avis_pro
  AFTER INSERT OR UPDATE ON avis_pro
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_new_avis_pro();
