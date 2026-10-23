-- ════════════════════════════════════════════════════════════════════════
-- Forum : notifications de réponse et de mention, créées par la base (source
-- UNIQUE, appli + site — même principe que trg_notify_new_message).
--
--   • réponse (forum_reponses) → l'auteur du sujet et les personnes qui y ont
--     déjà répondu reçoivent « forum_reponse » (jamais l'auteur de la réponse) ;
--   • mention @[Nom](profileId) dans un sujet ou une réponse → la personne
--     citée reçoit « forum_mention » (et pas en plus « forum_reponse ») ;
--   • data = { sujetId, categorie } : un clic ouvre directement la discussion.
-- Les notifications insérées ici partent aussi en push (webhook notify_push).
-- Avant : seules les mentions écrites depuis l'appli notifiaient (côté
-- client) ; le site ne notifiait rien. L'appli ne crée plus ces notifications.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

-- Nom affiché d'un profil (pseudo Pets Social, prénom nom, ou nom pro).
CREATE OR REPLACE FUNCTION public.pm_forum_nom(p_uid text, p_profile uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT coalesce(nullif(trim(social_pseudo), ''),
                     nullif(trim(coalesce(firstname, '') || ' ' || coalesce(lastname, '')), ''),
                     nullif(trim(nom), ''))
       FROM user_profiles
      WHERE (p_profile IS NOT NULL AND id = p_profile)
         OR (p_profile IS NULL AND uid = p_uid AND is_main)
      LIMIT 1),
    'Quelqu''un');
$$;

-- Notifie les profils @mentionnés dans p_texte ; renvoie leurs uid.
CREATE OR REPLACE FUNCTION public.pm_forum_notifier_mentions(
  p_texte text, p_auteur_uid text, p_auteur_nom text, p_sujet_id uuid, p_categorie text, p_ou text)
RETURNS text[]
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  vus text[] := '{}';
BEGIN
  FOR r IN
    SELECT DISTINCT ON (p.uid) p.uid, p.id
      FROM regexp_matches(coalesce(p_texte, ''), '@\[[^\]]+\]\(([0-9a-fA-F-]{36})\)', 'g') AS m
      JOIN user_profiles p ON p.id = m[1]::uuid
     WHERE p.uid IS DISTINCT FROM p_auteur_uid
  LOOP
    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (r.uid, r.id::text, 'forum_mention', 'Vous avez été cité(e) sur le forum',
            p_auteur_nom || ' vous a cité(e) dans ' || p_ou,
            jsonb_build_object('sujetId', p_sujet_id, 'categorie', p_categorie), false);
    vus := vus || r.uid;
  END LOOP;
  RETURN vus;
END;
$$;

-- Nouveau sujet : mentions seulement.
CREATE OR REPLACE FUNCTION public.pm_forum_sujet_notifs()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.pm_forum_notifier_mentions(
    NEW.contenu, NEW.auteur_uid, public.pm_forum_nom(NEW.auteur_uid, NEW.auteur_profile_id),
    NEW.id, NEW.categorie_slug, 'le sujet « ' || left(NEW.titre, 80) || ' »');
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW; -- une notification ne doit jamais empêcher la publication
END;
$$;

DROP TRIGGER IF EXISTS trg_forum_sujet_notifs ON public.forum_sujets;
CREATE TRIGGER trg_forum_sujet_notifs
  AFTER INSERT ON public.forum_sujets
  FOR EACH ROW EXECUTE FUNCTION public.pm_forum_sujet_notifs();

-- Nouvelle réponse : mentions, puis auteur du sujet + participants.
CREATE OR REPLACE FUNCTION public.pm_forum_reponse_notifs()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s record;
  r record;
  nom text;
  cites text[];
BEGIN
  SELECT id, titre, categorie_slug, auteur_uid, auteur_profile_id INTO s
    FROM forum_sujets WHERE id = NEW.sujet_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  nom := public.pm_forum_nom(NEW.auteur_uid, NEW.auteur_profile_id);
  cites := public.pm_forum_notifier_mentions(
    NEW.contenu, NEW.auteur_uid, nom, s.id, s.categorie_slug,
    'une réponse au sujet « ' || left(s.titre, 80) || ' »');

  FOR r IN
    -- Auteur du sujet d'abord, puis chaque participant une seule fois
    -- (son profil le plus récent dans la discussion).
    SELECT DISTINCT ON (uid) uid, profile_id, est_auteur FROM (
      SELECT s.auteur_uid AS uid, s.auteur_profile_id AS profile_id, true AS est_auteur, now() AS quand
      UNION ALL
      SELECT fr.auteur_uid, fr.auteur_profile_id, false, fr.created_at
        FROM forum_reponses fr
       WHERE fr.sujet_id = s.id AND fr.id <> NEW.id
    ) t
    WHERE uid IS NOT NULL AND uid <> NEW.auteur_uid AND NOT (uid = ANY (cites))
    ORDER BY uid, est_auteur DESC, quand DESC
  LOOP
    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (r.uid, r.profile_id::text, 'forum_reponse', 'Nouvelle réponse sur le forum',
            nom || CASE WHEN r.est_auteur THEN ' a répondu à votre sujet « ' ELSE ' a répondu au sujet « ' END
                || left(s.titre, 80) || ' »',
            jsonb_build_object('sujetId', s.id, 'categorie', s.categorie_slug), false);
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_forum_reponse_notifs ON public.forum_reponses;
CREATE TRIGGER trg_forum_reponse_notifs
  AFTER INSERT ON public.forum_reponses
  FOR EACH ROW EXECUTE FUNCTION public.pm_forum_reponse_notifs();

COMMIT;
