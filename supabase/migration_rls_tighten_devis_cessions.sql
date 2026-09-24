-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 43/N : devis, cessions
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Ces deux tables étaient explicitement différées depuis le début de ce
-- chantier RLS : leur lien /devis/[token] et /signer-cession/[token]
-- écrivaient directement en anonyme (clé anon) sans passer par une route
-- API — verrouiller l'écriture aurait cassé l'acceptation d'un devis ou la
-- signature d'une cession. Corrigé AVANT cette migration en déplaçant ces
-- deux écritures anonymes vers des routes API dédiées (clé service_role,
-- même principe que api/certificat/sign) :
--   - website/src/app/api/devis/respond/route.ts
--   - website/src/app/api/cessions/sign/route.ts
-- Les pages /devis/[token] et /signer-cession/[token] appellent maintenant
-- ces routes au lieu d'écrire directement dans Supabase. La RLS peut donc
-- être verrouillée à l'éleveur/pro sans casser ces flux : les routes API
-- passent par service_role, qui contourne la RLS de toute façon.
--
-- SELECT reste public sur les deux tables : la lecture initiale par token
-- (avant même de connaître le contenu) se fait toujours directement côté
-- client, comme album_partage/partage_tokens/factures.
--
-- cessions reste largement gérée côté app par l'éleveur authentifié
-- (créer/confirmer une cession, cession_sheet.dart, suivi_cessions_tab.dart)
-- — écriture réservée à uid_eleveur/cogérant, cohérent avec ce flux normal.
--
-- devis : écriture réservée au pro (pro_uid/cogérant) qui le crée/modifie
-- (animal_devis_page.dart, education_devis_page.dart).
--
-- ⚠️ À TESTER après exécution :
--   1. Un client (avec ou sans compte) peut toujours accepter/refuser un
--      devis depuis le lien /devis/[token].
--   2. Un acquéreur peut toujours signer une cession depuis le lien
--      /signer-cession/[token].
--   3. L'éleveur/pro peut toujours créer, modifier, consulter ses devis et
--      cessions depuis l'appli/le site.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── devis ───────────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE devis ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'devis'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.devis', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "devis_select" ON devis FOR SELECT USING (true);
CREATE POLICY "devis_write" ON devis
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = devis.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = devis.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );
-- Note : l'acceptation/refus anonyme par le client passe désormais par
-- api/devis/respond (service_role) — aucune policy anon nécessaire.

-- ── cessions ────────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE cessions ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cessions'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.cessions', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "cessions_select" ON cessions FOR SELECT USING (true);
CREATE POLICY "cessions_write" ON cessions
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = cessions.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = cessions.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );
-- Note : la signature anonyme de l'acquéreur passe désormais par
-- api/cessions/sign (service_role) — aucune policy anon nécessaire.

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('devis','cessions')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('devis','cessions')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE devis DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE cessions DISABLE ROW LEVEL SECURITY;
