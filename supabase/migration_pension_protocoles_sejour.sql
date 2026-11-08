-- ══════════════════════════════════════════════════════════════════════════
-- Pension : protocoles du séjour (08/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Un protocole de pension calé sur le séjour (reference_event = 'sejour')
-- s'applique AUTOMATIQUEMENT à l'enregistrement de l'arrivée :
--   plan_template_etapes.sejour_moment : 'chaque_jour' (de l'arrivée au
--     départ), 'arrivee' (jour de l'arrivée + jour_offset), 'depart' (jour du
--     départ − jour_offset).
--   plan_templates.pension_cible : ciblage
--     { "races": ["Berger australien", …], "logement_ids": [uuid…],
--       "logement_types": ["box","chatterie",…], "sejour": "tous"|"sejour"|"essai",
--       "nouveau": "tous"|"nouveau"|"habitue" }  (NULL = tous les pensionnaires)
--   Périmètre « locaux » : une tâche par logement occupé (nettoyage du box,
--   désinfection au départ…), sans doublon quand plusieurs animaux partagent
--   le logement.
--   plan_taches.pension_entree_id : séjour d'origine — tâches non faites
--   retirées si le séjour se termine plus tôt ou est annulé.
-- Facultatif : rien ne change pour les protocoles existants.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.plan_templates        ADD COLUMN IF NOT EXISTS pension_cible JSONB;
ALTER TABLE public.plan_template_etapes  ADD COLUMN IF NOT EXISTS sejour_moment TEXT;
ALTER TABLE public.plan_taches           ADD COLUMN IF NOT EXISTS pension_entree_id UUID
  REFERENCES public.pension_entrees(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_plan_taches_pension_entree ON public.plan_taches (pension_entree_id);

-- reference_event : ajout de 'sejour' (contrainte existante remplacée ;
-- NOT VALID pour ne pas bloquer sur d'anciennes valeurs).
DO $$
DECLARE c text;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.plan_templates'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%reference_event%'
  LOOP
    EXECUTE format('ALTER TABLE public.plan_templates DROP CONSTRAINT %I', c);
  END LOOP;
END $$;
ALTER TABLE public.plan_templates ADD CONSTRAINT plan_templates_reference_event_check
  CHECK (reference_event IN ('manuel','saillie','mise_bas','naissance','age_semaines','date_fixe','sejour')) NOT VALID;

COMMIT;
