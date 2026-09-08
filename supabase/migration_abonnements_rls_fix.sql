-- ═══════════════════════════════════════════════════════════════════════════
-- Correctif : la RLS a été activée sur `abonnements` sans policy SELECT →
-- la clé anon (appli + site) ne lisait plus AUCUN abonnement → tous les
-- profils repassaient en « Découverte » (free).
--
-- Le projet est en Firebase Auth : `auth.uid()` est toujours NULL côté client,
-- donc on suit le pattern utilisé partout ailleurs — RLS activée + policy
-- SELECT permissive (`USING (true)`), les écritures restant réservées au
-- service_role (aucune policy INSERT/UPDATE/DELETE → bloquées pour anon).
-- Idempotent, à exécuter dans le SQL Editor Supabase.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.abonnements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "abonnements_read" ON public.abonnements;
CREATE POLICY "abonnements_read" ON public.abonnements FOR SELECT USING (true);

ALTER TABLE public.achats_ponctuels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "achats_ponctuels_read" ON public.achats_ponctuels;
CREATE POLICY "achats_ponctuels_read" ON public.achats_ponctuels FOR SELECT USING (true);

-- Vérif : doit renvoyer 9 (ou le nb réel) avec la clé anon, pas 0.
-- SELECT COUNT(*) FROM public.abonnements;
