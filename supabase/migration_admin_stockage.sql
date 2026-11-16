-- Admin — onglet « Stockage » (16/11/2026) : volume de la base et des
-- fichiers, détail des galeries photo, relevé quotidien pour la tendance.
--
-- Fonctions en lecture seule, SECURITY DEFINER, exécutables UNIQUEMENT par
-- service_role (route /api/admin/stockage, garde admin Firebase) et la Cloud
-- Function quotidienne sendStockageReleve. Jamais par anon / authenticated.

-- ── Relevés quotidiens (tendance) ──
CREATE TABLE IF NOT EXISTS public.stockage_releves (
  jour          DATE PRIMARY KEY,
  base_octets   BIGINT NOT NULL,
  buckets       JSONB NOT NULL DEFAULT '{}'::jsonb,   -- { bucket: { fichiers, octets } }
  galeries      JSONB NOT NULL DEFAULT '{}'::jsonb,   -- { albums, photos, apercus_octets, livraisons_octets }
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.stockage_releves ENABLE ROW LEVEL SECURITY;
-- Aucune policy : seul service_role (qui contourne la RLS) y accède.
REVOKE ALL ON public.stockage_releves FROM anon, authenticated;

-- ── Taille totale de la base ──
CREATE OR REPLACE FUNCTION public.admin_stockage_base()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT pg_database_size(current_database());
$$;

-- ── Plus grosses tables (données + index + TOAST) ──
CREATE OR REPLACE FUNCTION public.admin_stockage_tables(p_limite INT DEFAULT 25)
RETURNS TABLE (nom TEXT, octets BIGINT, lignes BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_catalog AS $$
  SELECT c.relname::text, pg_total_relation_size(c.oid), GREATEST(c.reltuples, 0)::bigint
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
  ORDER BY pg_total_relation_size(c.oid) DESC
  LIMIT LEAST(GREATEST(p_limite, 1), 100);
$$;

-- ── Fichiers par espace de stockage (bucket) ──
CREATE OR REPLACE FUNCTION public.admin_stockage_buckets()
RETURNS TABLE (bucket TEXT, fichiers BIGINT, octets BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, storage AS $$
  SELECT o.bucket_id::text, count(*)::bigint, COALESCE(sum((o.metadata->>'size')::bigint), 0)::bigint
  FROM storage.objects o
  GROUP BY o.bucket_id
  ORDER BY 3 DESC;
$$;

-- ── Galeries photo : une ligne par galerie ──
CREATE OR REPLACE FUNCTION public.admin_stockage_galeries()
RETURNS TABLE (
  album_id UUID, pro_uid TEXT, pro_profile_id UUID, titre TEXT, statut TEXT,
  created_at TIMESTAMPTZ, livree_le TIMESTAMPTZ, photos BIGINT, apercus_octets BIGINT,
  livraisons_octets BIGINT, livraison_expire_le TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, storage AS $$
  WITH apercus AS (
    SELECT split_part(o.name, '/', 1) AS aid, count(*)::bigint AS n, COALESCE(sum((o.metadata->>'size')::bigint), 0)::bigint AS octets
    FROM storage.objects o WHERE o.bucket_id = 'galeries' GROUP BY 1
  ), livs AS (
    SELECT l.album_id, COALESCE(sum(l.taille_octets), 0)::bigint AS octets, max(l.expire_le) AS expire_le
    FROM album_livraisons l GROUP BY 1
  )
  SELECT a.id, a.pro_uid, a.pro_profile_id, a.titre, a.statut, a.created_at, a.livree_le,
         COALESCE(ap.n, 0), COALESCE(ap.octets, 0), COALESCE(lv.octets, 0), lv.expire_le
  FROM albums_photo a
  LEFT JOIN apercus ap ON ap.aid = a.id::text
  LEFT JOIN livs lv ON lv.album_id = a.id
  ORDER BY COALESCE(ap.octets, 0) + COALESCE(lv.octets, 0) DESC;
$$;

-- ── Relevé du jour (idempotent) ──
CREATE OR REPLACE FUNCTION public.admin_stockage_releve()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, storage AS $$
DECLARE
  v_buckets JSONB;
  v_gal JSONB;
BEGIN
  SELECT COALESCE(jsonb_object_agg(b.bucket, jsonb_build_object('fichiers', b.fichiers, 'octets', b.octets)), '{}'::jsonb)
    INTO v_buckets FROM public.admin_stockage_buckets() b;
  SELECT jsonb_build_object(
           'albums', count(*), 'photos', COALESCE(sum(g.photos), 0),
           'apercus_octets', COALESCE(sum(g.apercus_octets), 0), 'livraisons_octets', COALESCE(sum(g.livraisons_octets), 0))
    INTO v_gal FROM public.admin_stockage_galeries() g;
  INSERT INTO public.stockage_releves (jour, base_octets, buckets, galeries)
  VALUES ((now() AT TIME ZONE 'Europe/Paris')::date, pg_database_size(current_database()), v_buckets, v_gal)
  ON CONFLICT (jour) DO UPDATE
    SET base_octets = EXCLUDED.base_octets, buckets = EXCLUDED.buckets, galeries = EXCLUDED.galeries, created_at = now();
END $$;

-- Exécution réservée à service_role.
REVOKE ALL ON FUNCTION public.admin_stockage_base() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_stockage_tables(INT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_stockage_buckets() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_stockage_galeries() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_stockage_releve() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_stockage_base() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_stockage_tables(INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_stockage_buckets() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_stockage_galeries() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_stockage_releve() TO service_role;
