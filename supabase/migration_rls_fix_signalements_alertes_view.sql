-- ══════════════════════════════════════════════════════════════════════════
-- Admin — encart « alertes de signalements » vide (401 sur signalements_alertes)
-- ══════════════════════════════════════════════════════════════════════════
-- signalements_alertes est une VUE (comptage des signalements en attente par
-- élément, seuil 3 — migration_sig_signalements.sql). Une vue s'exécute par
-- défaut avec les droits de son propriétaire : elle contournait donc la RLS
-- de `signalements`. migration_rls_tighten_evenements_prestations.sql a
-- réglé ça en RETIRANT tout droit de lecture à anon/authenticated → l'admin
-- web (lecture directe depuis le navigateur) reçoit un 401 et l'encart des
-- alertes reste vide.
--
-- Correctif : la vue applique désormais les droits de CELUI QUI LIT
-- (security_invoker, Postgres 15+), donc la RLS de `signalements` (admin
-- via is_admin_uid + signaleur pour ses propres signalements) ; on peut
-- alors lui rendre le SELECT sans rien exposer.
--
-- ⚠️ À TESTER après exécution :
--   1. /admin (connecté en admin) : plus de 401 sur signalements_alertes.
--   2. Un compte non admin qui interroge la vue ne voit rien d'autre que
--      ses propres signalements agrégés (en pratique : rien, seuil de 3).
-- ══════════════════════════════════════════════════════════════════════════

ALTER VIEW public.signalements_alertes SET (security_invoker = true);
GRANT SELECT ON public.signalements_alertes TO authenticated;
-- Les jetons Firebase n'ont pas le rôle « authenticated » (pas de claim
-- role) : PostgREST les traite en « anon », l'identité passant par
-- auth.jwt() ->> 'sub' — comme pour toutes les autres tables. Sans ce
-- GRANT, l'admin reçoit toujours 401. Sans risque : via security_invoker,
-- la RLS de `signalements` s'applique (un anonyme obtient une liste vide).
GRANT SELECT ON public.signalements_alertes TO anon;

-- Vérification : doit afficher security_invoker=true
SELECT relname, reloptions FROM pg_class WHERE relname = 'signalements_alertes';

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════════
-- REVOKE SELECT ON public.signalements_alertes FROM authenticated, anon;
-- ALTER VIEW public.signalements_alertes SET (security_invoker = false);
