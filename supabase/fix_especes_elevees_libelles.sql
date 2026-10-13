-- Répare user_profiles.especes_elevees enregistré en libellés (« Ajouter un
-- profil » avant correctif : ["Chien","Chat","NAC"]) vers la forme canonique
-- de l'inscription : [{"espece":"chien","races":[]}].
-- Symptôme : l'éleveur ne pouvait plus choisir d'espèce (ni de race) en
-- créant une annonce dans l'appli. Idempotent : les objets déjà au bon format
-- sont conservés tels quels.

-- 1) Aperçu des profils concernés
SELECT id, uid, profile_type, especes_elevees
FROM public.user_profiles
WHERE jsonb_typeof(especes_elevees) = 'array'
  AND EXISTS (SELECT 1 FROM jsonb_array_elements(especes_elevees) e WHERE jsonb_typeof(e) = 'string');

-- 2) Réparation
WITH alias(lib, val) AS (VALUES
  ('chien','chien'),('chiens','chien'),('chat','chat'),('chats','chat'),
  ('cheval','cheval'),('chevaux','cheval'),('equide','cheval'),('équidé','cheval'),
  ('lapin','lapin'),('lapins','lapin'),('oiseau','oiseau'),('oiseaux','oiseau'),
  ('ovin','ovin'),('caprin','caprin'),('porcin','porcin'),
  ('nac','nac'),('rongeur','nac'),('rongeurs','nac'),('reptile','nac'),('reptiles','nac'),
  ('autre','autre')
),
cible AS (
  SELECT p.id,
    COALESCE((
      SELECT jsonb_agg(x.obj ORDER BY x.ord)
      FROM (
        SELECT DISTINCT ON (COALESCE(a.val, e.v->>'espece'))
               COALESCE(a.val, e.v->>'espece') AS esp, e.ord,
               CASE WHEN jsonb_typeof(e.v) = 'object' THEN e.v
                    ELSE jsonb_build_object('espece', a.val, 'races', '[]'::jsonb) END AS obj
        FROM jsonb_array_elements(p.especes_elevees) WITH ORDINALITY e(v, ord)
        LEFT JOIN alias a ON jsonb_typeof(e.v) = 'string' AND a.lib = lower(trim(e.v #>> '{}'))
        WHERE jsonb_typeof(e.v) = 'object' OR a.val IS NOT NULL
        ORDER BY COALESCE(a.val, e.v->>'espece'), e.ord
      ) x
    ), '[]'::jsonb) AS nouv
  FROM public.user_profiles p
  WHERE jsonb_typeof(p.especes_elevees) = 'array'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(p.especes_elevees) e WHERE jsonb_typeof(e) = 'string')
)
UPDATE public.user_profiles u
SET especes_elevees = c.nouv
FROM cible c
WHERE u.id = c.id;
