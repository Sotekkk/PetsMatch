-- ══════════════════════════════════════════════════════════════════════════
-- Groupes — validation des publications + signalements reliés (comme Facebook)
-- ══════════════════════════════════════════════════════════════════════════
--   • groupes.validation_publications (par défaut NON, au choix de l'admin) :
--     les publications des membres attendent l'accord d'un admin / modérateur
--     avant d'être visibles. Celles de l'équipe paraissent directement.
--   • groupe_posts.statut : 'publie' | 'en_attente' (fixé par la base, pas par
--     l'appli). Une publication en attente n'est visible que par son auteur et
--     l'équipe du groupe.
--   • Notifications : publication en attente → équipe ; publiée / refusée →
--     auteur ; publication signalée → équipe (lien vers le groupe).
-- Pré-requis : migration_groupes_validation_membres.sql. Idempotent.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.groupes ADD COLUMN IF NOT EXISTS validation_publications BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.groupe_posts ADD COLUMN IF NOT EXISTS statut TEXT NOT NULL DEFAULT 'publie';
DO $$ BEGIN
  ALTER TABLE public.groupe_posts ADD CONSTRAINT groupe_posts_statut_check CHECK (statut IN ('publie', 'en_attente'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Équipe du groupe (admins, modérateurs, créateur) — destinataires des alertes.
CREATE OR REPLACE FUNCTION public.groupes_notifier_equipe(p_groupe UUID, p_sauf TEXT, p_type TEXT, p_titre TEXT, p_corps TEXT, p_data JSONB)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e RECORD;
BEGIN
  FOR e IN
    SELECT DISTINCT ON (user_uid) user_uid, profile_id FROM (
      SELECT user_uid, profile_id, 0 AS ordre FROM groupes_membres
       WHERE groupe_id = p_groupe AND statut = 'active' AND role IN ('admin', 'moderateur')
      UNION ALL
      SELECT createur_uid, createur_profile_id, 1 FROM groupes WHERE id = p_groupe AND createur_uid IS NOT NULL
    ) x
     WHERE user_uid IS DISTINCT FROM p_sauf
     ORDER BY user_uid, ordre
  LOOP
    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (e.user_uid, e.profile_id::text, p_type, p_titre, p_corps, p_data, false);
  END LOOP;
END $$;

-- Statut fixé par la base : en attente si le groupe valide les publications
-- et que l'auteur n'est pas de l'équipe ; seuls admins / modérateurs le changent.
CREATE OR REPLACE FUNCTION public.groupe_posts_statut()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE equipe BOOLEAN;
BEGIN
  equipe := COALESCE(auth.jwt() ->> 'sub', '') = ''
    OR public.is_admin_or_moderateur_of_groupe(COALESCE(NEW.groupe_id, OLD.groupe_id), auth.jwt() ->> 'sub');
  IF TG_OP = 'INSERT' THEN
    NEW.statut := CASE
      WHEN NOT equipe AND EXISTS (SELECT 1 FROM groupes g WHERE g.id = NEW.groupe_id AND g.validation_publications)
        THEN 'en_attente' ELSE 'publie' END;
  ELSIF NEW.statut IS DISTINCT FROM OLD.statut AND NOT equipe THEN
    NEW.statut := OLD.statut;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_groupe_posts_statut ON groupe_posts;
CREATE TRIGGER trg_groupe_posts_statut BEFORE INSERT OR UPDATE ON groupe_posts
  FOR EACH ROW EXECUTE FUNCTION public.groupe_posts_statut();

-- Lecture : publiées pour tous ; en attente pour l'auteur et l'équipe.
DROP POLICY IF EXISTS "groupe_posts_select" ON groupe_posts;
CREATE POLICY "groupe_posts_select" ON groupe_posts FOR SELECT USING (
  statut = 'publie'
  OR auteur_uid = (auth.jwt() ->> 'sub')
  OR public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
);

CREATE OR REPLACE FUNCTION public.groupe_posts_notifier()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE nom_groupe TEXT; auteur TEXT;
BEGIN
  SELECT nom INTO nom_groupe FROM groupes WHERE id = COALESCE(NEW.groupe_id, OLD.groupe_id);
  IF TG_OP = 'INSERT' AND NEW.statut = 'en_attente' THEN
    auteur := public.groupes_nom_membre(NEW.auteur_uid, NEW.auteur_profile_id);
    PERFORM public.groupes_notifier_equipe(NEW.groupe_id, NEW.auteur_uid, 'groupe_post_attente',
      'Publication à valider — ' || COALESCE(nom_groupe, 'groupe'),
      auteur || ' a publié : ' || LEFT(COALESCE(NULLIF(NEW.contenu, ''), 'une photo'), 80),
      jsonb_build_object('groupe_id', NEW.groupe_id, 'post_id', NEW.id));
  ELSIF TG_OP = 'UPDATE' AND OLD.statut = 'en_attente' AND NEW.statut = 'publie' THEN
    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (NEW.auteur_uid, NEW.auteur_profile_id::text, 'groupe_post_publie',
      'Publication acceptée', 'Votre publication est visible dans ' || COALESCE(nom_groupe, 'le groupe') || '.',
      jsonb_build_object('groupe_id', NEW.groupe_id, 'post_id', NEW.id), false);
  ELSIF TG_OP = 'DELETE' AND OLD.statut = 'en_attente'
        AND COALESCE(auth.jwt() ->> 'sub', '') <> OLD.auteur_uid THEN
    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (OLD.auteur_uid, OLD.auteur_profile_id::text, 'groupe_post_refuse',
      'Publication non retenue', 'Votre publication dans ' || COALESCE(nom_groupe, 'le groupe') || ' n''a pas été acceptée.',
      jsonb_build_object('groupe_id', OLD.groupe_id), false);
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
DROP TRIGGER IF EXISTS trg_groupe_posts_notifier ON groupe_posts;
CREATE TRIGGER trg_groupe_posts_notifier AFTER INSERT OR UPDATE OR DELETE ON groupe_posts
  FOR EACH ROW EXECUTE FUNCTION public.groupe_posts_notifier();

-- Publication signalée → équipe du groupe, avec le lien vers la publication.
CREATE OR REPLACE FUNCTION public.signalements_groupe_notifier()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE nom_groupe TEXT;
BEGIN
  IF NEW.target_type = 'groupe_post' AND NEW.groupe_id IS NOT NULL THEN
    SELECT nom INTO nom_groupe FROM groupes WHERE id = NEW.groupe_id;
    PERFORM public.groupes_notifier_equipe(NEW.groupe_id, NEW.reporter_uid, 'groupe_signalement',
      'Publication signalée — ' || COALESCE(nom_groupe, 'groupe'),
      'Motif : ' || COALESCE(NEW.raison, 'non précisé') || COALESCE(' — ' || NULLIF(NEW.description, ''), ''),
      jsonb_build_object('groupe_id', NEW.groupe_id, 'post_id', NEW.target_id, 'signalement_id', NEW.id));
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_signalements_groupe_notifier ON signalements;
CREATE TRIGGER trg_signalements_groupe_notifier AFTER INSERT ON signalements
  FOR EACH ROW EXECUTE FUNCTION public.signalements_groupe_notifier();

NOTIFY pgrst, 'reload schema';
