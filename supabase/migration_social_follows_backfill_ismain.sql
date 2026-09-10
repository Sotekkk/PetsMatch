-- ═══════════════════════════════════════════════════════════════════════════
-- Pets Social — backfill des *_profile_id manquants (repli is_main)
-- ───────────────────────────────────────────────────────────────────────────
-- Le backfill précédent (migration_social_links.sql) ne remplissait les
-- follower_profile_id / following_profile_id / author_profile_id QUE depuis le
-- profil `particulier` de l'uid → NULL pour les comptes sans profil particulier
-- (pro-only). Résultat : follows/notifs de ces comptes retombaient sur un
-- scope uid = fuite entre profils.
--
-- Ici : profil "social" d'un uid = son profil particulier s'il en a un, SINON
-- son profil principal (is_main). Idempotent (ne touche que les NULL).
-- ═══════════════════════════════════════════════════════════════════════════

-- Un id de profil "social" par uid.
DROP VIEW IF EXISTS _social_pid;
CREATE TEMP VIEW _social_pid AS
SELECT DISTINCT ON (uid) uid, id
FROM public.user_profiles
ORDER BY uid, (profile_type = 'particulier') DESC, is_main DESC;

-- follows
UPDATE public.follows f SET follower_profile_id = sp.id
  FROM _social_pid sp
  WHERE f.follower_profile_id IS NULL AND f.follower_uid = sp.uid;

UPDATE public.follows f SET following_profile_id = sp.id
  FROM _social_pid sp
  WHERE f.following_profile_id IS NULL AND f.following_uid = sp.uid;

-- posts_socialmedia
UPDATE public.posts_socialmedia p SET author_profile_id = sp.id
  FROM _social_pid sp
  WHERE p.author_profile_id IS NULL AND p.uid = sp.uid;

-- post_comments
UPDATE public.post_comments c SET author_profile_id = sp.id
  FROM _social_pid sp
  WHERE c.author_profile_id IS NULL AND c.uid = sp.uid;

-- post_likes
UPDATE public.post_likes l SET author_profile_id = sp.id
  FROM _social_pid sp
  WHERE l.author_profile_id IS NULL AND l.uid = sp.uid;

-- post_favorites (si la table/colonne existe)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'post_favorites'
      AND column_name = 'author_profile_id'
  ) THEN
    UPDATE public.post_favorites fav SET author_profile_id = sp.id
      FROM _social_pid sp
      WHERE fav.author_profile_id IS NULL AND fav.uid = sp.uid;
  END IF;
END $$;

DROP VIEW IF EXISTS _social_pid;
