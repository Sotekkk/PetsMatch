-- ════════════════════════════════════════════════════════════════════════
-- Retards en cascade + alerte automatique des clients (vétérinaire / clinique).
--
-- Décisions (08/10/2026) :
--   • Un RDV ne passe dans l'historique que lorsqu'il est marqué « terminé »
--     (rdv.termine_at = heure réelle de fin).
--   • Le retard s'enchaîne par praticien : un RDV terminé après l'heure
--     prévue (ou encore en cours) décale les suivants de la journée.
--   • Réglage du profil (user_profiles.retard_alerte_auto) : si activé, la
--     Cloud Function sendRetardsAutomatiques (toutes les 5 min) prévient le
--     client dès 30 min de retard estimé, puis à nouveau si le retard
--     augmente d'au moins 15 min (rdv.retard_notifie_min).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS retard_alerte_auto boolean NOT NULL DEFAULT false;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS termine_at timestamptz;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS retard_notifie_min integer;

-- Nouvelle colonne publique de user_profiles : vue masquée + droits.
SELECT public.pm_recreer_vues_perso();
SELECT public.pm_appliquer_droits_perso();
