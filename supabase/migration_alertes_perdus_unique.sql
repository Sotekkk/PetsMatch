-- ════════════════════════════════════════════════════════════════════════
-- Animaux perdus en co-propriété : une seule alerte « perdu » ouverte par
-- animal. Quand un co-propriétaire déclare la perte, les autres sont
-- prévenus et voient la même alerte dans « Mes alertes » ; ils ne peuvent
-- plus la redéclarer (contrôle appli + site, et ce verrou en base contre
-- deux déclarations simultanées).
--
-- S'il reste des doublons, l'index n'est pas créé : la liste des animaux
-- concernés s'affiche (NOTICE) ; supprimer l'alerte en trop puis relancer.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  r record;
  doublons int := 0;
BEGIN
  FOR r IN
    SELECT animal_id, count(*) AS n, string_agg(id || ' (' || coalesce(nom_animal, '?') || ')', ', ' ORDER BY created_at) AS alertes
      FROM public.alertes_perdus
     WHERE statut = 'perdu' AND animal_id IS NOT NULL
     GROUP BY animal_id HAVING count(*) > 1
  LOOP
    doublons := doublons + 1;
    RAISE NOTICE 'Doublon animal % : % alertes ouvertes — %', r.animal_id, r.n, r.alertes;
  END LOOP;
  IF doublons > 0 THEN
    RAISE NOTICE 'Index non créé : % animal(aux) avec plusieurs alertes ouvertes.', doublons;
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS uq_alertes_perdus_animal_ouverte
      ON public.alertes_perdus (animal_id)
      WHERE statut = 'perdu' AND animal_id IS NOT NULL;
    RAISE NOTICE 'Verrou posé : une seule alerte ouverte par animal.';
  END IF;
END $$;
