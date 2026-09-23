-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 30/N : annonces_objets, stats d'annonces,
--   pro_animal_access
--   annonces_stats_daily, animaux_portee_stats, annonces_views_geo,
--   annonces_objets, pro_animal_access
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Les 3 tables de stats (annonces_stats_daily, animaux_portee_stats,
-- annonces_views_geo) sont incrémentées par N'IMPORTE QUEL VISITEUR
-- consultant une annonce (api/annonces/stats/route.ts), via 3 fonctions
-- RPC — mais ces fonctions n'étaient PAS SECURITY DEFINER : verrouiller
-- l'écriture directe aurait aussi cassé l'incrément via RPC (exécuté avec
-- les droits de l'appelant, donc soumis à la même RLS). Passées en
-- SECURITY DEFINER (même principe que increment_annonce_vues, vague
-- 10/N) pour dissocier « n'importe qui peut déclencher un incrément via
-- la fonction dédiée » de « seul le propriétaire peut écrire la table
-- directement ». SELECT reste public (simples compteurs agrégés, pas de
-- PII, et lu par la page publique de l'annonce).
--
-- annonces_objets (marketplace d'objets, distincte de `annonces` les
-- animaux) : USING(true) — écriture verrouillée au vendeur (uid).
--
-- pro_animal_access : table jamais utilisée dans le code actuel
-- (remplacée par `animal_access`, vague 6/N) mais toujours ouverte en
-- base — verrouillée par sécurité, même si sans effet pratique.
--
-- ⚠️ À TESTER après exécution :
--   1. Consulter une annonce animal (public, sans compte) incrémente
--      toujours ses statistiques de vues.
--   2. Le tableau de bord "Mes annonces" (vues/visiteurs/départements/
--      vues par chiot) s'affiche normalement pour l'éleveur.
--   3. Publier/modifier/supprimer une annonce d'objet fonctionne pour
--      son vendeur ; un autre utilisateur ne peut pas la modifier.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION increment_annonce_view(
  p_annonce_id  TEXT,
  p_departement TEXT DEFAULT 'inconnu',
  p_unique      BOOLEAN DEFAULT false
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO annonces_stats_daily (annonce_id, date, vues, visiteurs)
  VALUES (p_annonce_id, CURRENT_DATE, 1, CASE WHEN p_unique THEN 1 ELSE 0 END)
  ON CONFLICT (annonce_id, date) DO UPDATE
    SET vues      = annonces_stats_daily.vues + 1,
        visiteurs = annonces_stats_daily.visiteurs + CASE WHEN p_unique THEN 1 ELSE 0 END;

  IF p_departement IS NOT NULL AND p_departement != '' THEN
    INSERT INTO annonces_views_geo (annonce_id, departement, vues, updated_at)
    VALUES (p_annonce_id, p_departement, 1, NOW())
    ON CONFLICT (annonce_id, departement) DO UPDATE
      SET vues = annonces_views_geo.vues + 1, updated_at = NOW();
  END IF;

  UPDATE annonces SET vues = COALESCE(vues, 0) + 1 WHERE id = p_annonce_id;
END;
$$;
GRANT EXECUTE ON FUNCTION increment_annonce_view(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

CREATE OR REPLACE FUNCTION increment_portee_view(
  p_annonce_id TEXT,
  p_bebe_index INT
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO animaux_portee_stats (annonce_id, bebe_index, date, vues)
  VALUES (p_annonce_id, p_bebe_index, CURRENT_DATE, 1)
  ON CONFLICT (annonce_id, bebe_index, date) DO UPDATE
    SET vues = animaux_portee_stats.vues + 1;
END;
$$;
GRANT EXECUTE ON FUNCTION increment_portee_view(TEXT, INT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION increment_portee_favori(
  p_annonce_id TEXT,
  p_bebe_index INT,
  p_delta      INT DEFAULT 1
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO animaux_portee_stats (annonce_id, bebe_index, date, favoris)
  VALUES (p_annonce_id, p_bebe_index, CURRENT_DATE, GREATEST(p_delta, 0))
  ON CONFLICT (annonce_id, bebe_index, date) DO UPDATE
    SET favoris = GREATEST(animaux_portee_stats.favoris + p_delta, 0);
END;
$$;
GRANT EXECUTE ON FUNCTION increment_portee_favori(TEXT, INT, INT) TO anon, authenticated;

-- ── Tables de stats : SELECT public conservé, écriture directe verrouillée ─
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['annonces_stats_daily','animaux_portee_stats','annonces_views_geo']
  LOOP
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$ CREATE POLICY "%1$s_select" ON public.%1$I FOR SELECT USING (true) $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_write" ON public.%1$I
        FOR ALL USING (
          EXISTS (
            SELECT 1 FROM annonces a
            WHERE a.id = %1$I.annonce_id
              AND (
                a.uid_eleveur = (auth.jwt() ->> 'sub')
                OR EXISTS (
                  SELECT 1 FROM elevage_cogerants c
                  WHERE c.uid_gerant = a.uid_eleveur
                    AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
                )
              )
          )
        )
    $f$, t);
  END LOOP;
END $$;

-- ── annonces_objets (marketplace d'objets) ─────────────────────────────────
DROP POLICY IF EXISTS "annonces_objets_all" ON public.annonces_objets;
CREATE POLICY "annonces_objets_select" ON public.annonces_objets FOR SELECT USING (true);
CREATE POLICY "annonces_objets_write" ON public.annonces_objets
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- ── pro_animal_access (jamais utilisée, verrouillée par sécurité) ─────────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.pro_animal_access') IS NULL THEN RETURN; END IF;
  ALTER TABLE pro_animal_access ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'pro_animal_access'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.pro_animal_access', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "pro_animal_access_owner" ON pro_animal_access
      FOR ALL USING ((auth.jwt() ->> 'sub') = pro_uid)
      WITH CHECK ((auth.jwt() ->> 'sub') = pro_uid)
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('annonces_stats_daily','animaux_portee_stats','annonces_views_geo','annonces_objets','pro_animal_access')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('annonces_stats_daily','animaux_portee_stats','annonces_views_geo','annonces_objets','pro_animal_access')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY stats_daily_all  ON annonces_stats_daily  USING (true) WITH CHECK (true);
-- CREATE POLICY portee_stats_all ON animaux_portee_stats  USING (true) WITH CHECK (true);
-- CREATE POLICY views_geo_all    ON annonces_views_geo    USING (true) WITH CHECK (true);
-- CREATE POLICY "annonces_objets_all" ON annonces_objets FOR ALL USING (true) WITH CHECK (true);
-- ALTER TABLE pro_animal_access DISABLE ROW LEVEL SECURITY;
