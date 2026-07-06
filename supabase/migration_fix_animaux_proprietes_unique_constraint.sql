-- ─────────────────────────────────────────────────────────────────────────────
-- Fix : animaux_proprietes n'a jamais eu de contrainte UNIQUE (animal_id, uid_proprio)
-- alors que le code (animal_fiche.dart) fait un upsert avec
-- onConflict: 'animal_id,uid_proprio'. Sans la contrainte, Postgres renvoie
-- l'erreur 42P10 à CHAQUE création d'animal, silencieusement avalée par le
-- try/catch côté app → aucune ligne animaux_proprietes n'était jamais créée.
--
-- mes_animaux.dart filtre les animaux visibles par profil via
-- animaux_proprietes.profile_id_proprio = activeProfileId (c'est la logique
-- multi-profil citée) : les animaux sans ligne animaux_proprietes, ou avec
-- profile_id_proprio manquant, sont invisibles pour tous les profils.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) Contrainte UNIQUE manquante, nécessaire pour que l'upsert applicatif fonctionne
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'animaux_proprietes_animal_uid_key'
  ) THEN
    ALTER TABLE public.animaux_proprietes
      ADD CONSTRAINT animaux_proprietes_animal_uid_key UNIQUE (animal_id, uid_proprio);
  END IF;
END $$;

-- 2) Backfill des animaux éleveur sans ligne animaux_proprietes (dont les
--    portées, qui n'ont jamais tenté l'insert). profile_id_proprio est résolu
--    via le profil éleveur PRINCIPAL (is_main=true) de l'uid_eleveur — pas
--    via animaux.profile_id, absent/non fiable (ex: portee_form_page.dart ne
--    le renseigne jamais).
INSERT INTO public.animaux_proprietes (animal_id, uid_proprio, profile_id_proprio, date_debut, date_fin)
SELECT
  a.id,
  a.uid_eleveur,
  up.id,
  COALESCE(a.date_entree::date, a.date_naissance::date, a.created_at::date, CURRENT_DATE),
  CASE
    WHEN a.statut IN ('sorti', 'en_attente_cession') AND a.date_sortie IS NOT NULL
      THEN a.date_sortie::date
    ELSE NULL
  END
FROM public.animaux a
JOIN public.user_profiles up
  ON up.uid = a.uid_eleveur
 AND up.profile_type = 'eleveur'
 AND up.is_main = true
WHERE a.uid_eleveur IS NOT NULL
  AND a.uid_eleveur != ''
  AND NOT EXISTS (
    SELECT 1 FROM public.animaux_proprietes ap
    WHERE ap.animal_id = a.id AND ap.uid_proprio = a.uid_eleveur
  )
ON CONFLICT (animal_id, uid_proprio) DO NOTHING;

-- Vérification : lister les animaux éleveur toujours orphelins après le backfill
-- (ex: uid_eleveur sans profil éleveur principal en base — cas à investiguer manuellement)
SELECT a.id, a.nom, a.uid_eleveur, a.created_at
FROM public.animaux a
WHERE a.uid_eleveur IS NOT NULL
  AND a.uid_eleveur != ''
  AND NOT EXISTS (
    SELECT 1 FROM public.animaux_proprietes ap
    WHERE ap.animal_id = a.id AND ap.uid_proprio = a.uid_eleveur
  );
