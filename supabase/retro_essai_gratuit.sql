-- ════════════════════════════════════════════════════════════════════════
-- Essai gratuit 30 j RÉTROACTIF (optionnel, à décider au moment venu).
--
-- Le trigger grant_trial_on_new_pro_profile n'a jamais accordé d'essai en
-- prod (réparé par migration_rls_user_profiles.sql). Ce script accorde
-- l'essai aux profils pro créés AVANT la réparation qui ne l'ont pas eu,
-- à compter d'aujourd'hui (30 jours), une seule fois par compte et par type.
--
-- Aperçu (par défaut, ne modifie rien) :
--   psql "$PROD_DB_URL" -f supabase/retro_essai_gratuit.sql
-- Application :
--   psql "$PROD_DB_URL" -v appliquer=1 -f supabase/retro_essai_gratuit.sql
-- ════════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
\pset footer off

CREATE TEMP TABLE essai_retro AS
SELECT up.id AS profile_id, up.uid, up.profile_type, up.created_at::date AS cree_le,
       CASE up.profile_type
         WHEN 'eleveur' THEN 'premium' WHEN 'garde' THEN 'premium'
         WHEN 'pension' THEN 'premium' WHEN 'education' THEN 'premium'
         WHEN 'toilettage' THEN 'premium' WHEN 'sante' THEN 'pro'
         WHEN 'marechal_ferrant' THEN 'pro' WHEN 'veterinaire' THEN 'clinique'
         WHEN 'photographe' THEN 'essentiel'
       END AS plan_code
FROM public.user_profiles up
WHERE up.profile_type IN ('eleveur','garde','pension','education','toilettage',
                          'sante','marechal_ferrant','veterinaire','photographe')
  AND coalesce(up.plan_code, 'free') = 'free'
  AND NOT EXISTS (SELECT 1 FROM public.abonnements a
                  WHERE a.uid = up.uid AND a.profil_type = up.profile_type
                    AND (a.essai_gratuit OR a.statut = 'actif'));

\echo '== Profils pro qui recevraient l''essai de 30 jours'
SELECT profile_type, cree_le, plan_code, left(uid, 6) || '…' AS compte FROM essai_retro ORDER BY cree_le;

\if :{?appliquer}
BEGIN;
SELECT set_config('pm.systeme', 'on', true) \gset x_
INSERT INTO public.abonnements (uid, profile_id, profil_type, plan_code, periodicite, statut,
                                date_debut, date_fin, essai_gratuit, created_at, updated_at)
SELECT uid, profile_id, profile_type, plan_code, 'mensuel', 'actif',
       now(), now() + interval '30 days', true, now(), now()
FROM essai_retro;
UPDATE public.user_profiles up
   SET essai_gratuit_utilise = true, plan_code = e.plan_code, is_premium = true,
       plan_until = now() + interval '30 days'
  FROM essai_retro e WHERE up.id = e.profile_id;
COMMIT;
\echo 'Essai accordé.'
\else
\echo 'Aperçu seulement : relancer avec -v appliquer=1 pour accorder.'
\endif
