-- ════════════════════════════════════════════════════════════════════════
-- Forum : choisir ses notifications.
--
--   • preferences_notifications (une ligne par compte, absente = tout reçu) :
--       forum_reponses  — réponses aux sujets où l'on a écrit ;
--       forum_mentions  — quand quelqu'un vous cite (@Nom).
--     Réglage : Paramètres → Notifications (appli) / Mon profil → Notifications (site).
--   • forum_sujets_muets : « Ne plus être notifié(e) de ce sujet » (bouton
--     dans la discussion) — coupe les réponses de ce sujet, pas les citations.
--
-- Les triggers trg_forum_reponse_notifs / trg_forum_sujet_notifs
-- (migration_forum_notifications.sql) respectent ces choix : la notification
-- n'est pas créée, donc ni affichée dans l'appli ni envoyée en push.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS public.preferences_notifications (
  uid            text PRIMARY KEY,
  forum_reponses boolean NOT NULL DEFAULT true,
  forum_mentions boolean NOT NULL DEFAULT true,
  updated_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.preferences_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pref_notifs_own ON public.preferences_notifications;
CREATE POLICY pref_notifs_own ON public.preferences_notifications FOR ALL
  USING (uid = (auth.jwt() ->> 'sub'))
  WITH CHECK (uid = (auth.jwt() ->> 'sub'));

CREATE TABLE IF NOT EXISTS public.forum_sujets_muets (
  uid        text NOT NULL,
  sujet_id   uuid NOT NULL REFERENCES public.forum_sujets(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (uid, sujet_id)
);
ALTER TABLE public.forum_sujets_muets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS forum_muets_own ON public.forum_sujets_muets;
CREATE POLICY forum_muets_own ON public.forum_sujets_muets FOR ALL
  USING (uid = (auth.jwt() ->> 'sub'))
  WITH CHECK (uid = (auth.jwt() ->> 'sub'));

-- Le compte accepte-t-il ce type de notification du forum ?
CREATE OR REPLACE FUNCTION public.pm_forum_notif_voulue(p_uid text, p_type text, p_sujet_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE p_type
    WHEN 'forum_mention' THEN
      coalesce((SELECT forum_mentions FROM preferences_notifications WHERE uid = p_uid), true)
    ELSE
      coalesce((SELECT forum_reponses FROM preferences_notifications WHERE uid = p_uid), true)
      AND NOT EXISTS (SELECT 1 FROM forum_sujets_muets WHERE uid = p_uid AND sujet_id = p_sujet_id)
  END;
$$;

-- Mentions : la personne citée n'est notifiée que si elle l'accepte. Elle
-- compte quand même comme « citée » (pas de « forum_reponse » à la place).
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
    IF public.pm_forum_notif_voulue(r.uid, 'forum_mention', p_sujet_id) THEN
      INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
      VALUES (r.uid, r.id::text, 'forum_mention', 'Vous avez été cité(e) sur le forum',
              p_auteur_nom || ' vous a cité(e) dans ' || p_ou,
              jsonb_build_object('sujetId', p_sujet_id, 'categorie', p_categorie), false);
    END IF;
    vus := vus || r.uid;
  END LOOP;
  RETURN vus;
END;
$$;

-- Réponses : auteur du sujet + participants, sauf réglage contraire.
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
    CONTINUE WHEN NOT public.pm_forum_notif_voulue(r.uid, 'forum_reponse', s.id);
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

COMMIT;
