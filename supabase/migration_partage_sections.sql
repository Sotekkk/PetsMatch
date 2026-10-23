-- ════════════════════════════════════════════════════════════════════════
-- Partage de la fiche d'un animal (lien + QR code, lecture seule) : le
-- propriétaire choisit les onglets visibles.
--   identite (toujours) · sante (vaccins, traitements, vermifuges,
--   antiparasitaires, visites, allergies, chirurgies) · poids ·
--   alimentation · documents · genealogie
-- Remplace, côté propriétaire, le lien « vétérinaire » (/sante/…) : un seul
-- lien, carnet de santé coché.
--
-- La base n'ouvre que les onglets cochés : chaque table de l'onglet a une
-- policy de lecture « via partage » (en-tête x-pm-token, lien actif et non
-- expiré, onglet présent dans partage_animal.sections).
-- Identité, documents et généalogie sont des colonnes de la fiche (déjà
-- lisible par le lien) : la page n'affiche que les onglets cochés.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.partage_animal
  ADD COLUMN IF NOT EXISTS sections text[] NOT NULL DEFAULT '{identite}';

CREATE OR REPLACE FUNCTION public.pm_partage_section(p_animal_id text, p_section text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.pm_token_requete() IS NOT NULL AND p_animal_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM partage_animal pa
     WHERE pa.animal_id::text = p_animal_id
       AND pa.token::text = public.pm_token_requete()
       AND pa.actif
       AND pa.expire_at > now()
       AND p_section = ANY (pa.sections)
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_partage_section(text, text) TO anon, authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations','traitements','visites','vermifuges','antiparasitaires','allergies','chirurgies'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select_via_partage', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated USING (public.pm_partage_section(animal_id::text, %L))',
                   t || '_select_via_partage', t, 'sante');
  END LOOP;
END $$;

DROP POLICY IF EXISTS poids_select_via_partage ON public.poids;
CREATE POLICY poids_select_via_partage ON public.poids
  FOR SELECT TO anon, authenticated USING (public.pm_partage_section(animal_id::text, 'poids'));

DROP POLICY IF EXISTS alimentations_select_via_partage ON public.alimentations;
CREATE POLICY alimentations_select_via_partage ON public.alimentations
  FOR SELECT TO anon, authenticated USING (public.pm_partage_section(animal_id::text, 'alimentation'));

COMMIT;
