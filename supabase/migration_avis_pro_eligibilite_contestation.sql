-- ══════════════════════════════════════════════════════════════════════════
-- Avis pro — éligibilité (interaction réelle requise) + contestation
-- ══════════════════════════════════════════════════════════════════════════
-- Remontée bêta : n'importe quel particulier connecté pouvait laisser un
-- avis sur n'importe quel pro, sans jamais avoir eu affaire à lui (aucun
-- RDV, aucune prestation). Restreint désormais aux clients ayant eu une
-- interaction réelle et documentée avec ce pro :
--   - un rendez-vous confirmé ou terminé (rdv.statut IN ('confirme','termine')), OU
--   - un compte-rendu/fiche de suivi rédigé par ce pro pour ce client
--     (comptes_rendus.owner_uid) — cas d'un client sans RDV pris dans
--     l'appli (RDV pris par téléphone, suivi historique, etc.).
-- Ajoute aussi la contestation d'avis par le pro (avis_pro_contests),
-- même modèle que petfriendly_review_contests (vague 37/N) — décision
-- admin traitée manuellement pour l'instant, pas de back-office dédié.
-- ══════════════════════════════════════════════════════════════════════════

-- ── Éligibilité : interaction réelle pro ↔ client ─────────────────────────
CREATE OR REPLACE FUNCTION public.can_review_pro(p_pro_uid TEXT, p_client_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM rdv
    WHERE rdv.pro_uid = p_pro_uid AND rdv.client_uid = p_client_uid
      AND rdv.statut IN ('confirme', 'termine')
  ) OR EXISTS (
    SELECT 1 FROM comptes_rendus
    WHERE comptes_rendus.pro_uid = p_pro_uid AND comptes_rendus.owner_uid = p_client_uid
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_review_pro(TEXT, TEXT) TO anon, authenticated;

DROP POLICY IF EXISTS "avis_pro_insert" ON avis_pro;
CREATE POLICY "avis_pro_insert" ON avis_pro
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = client_uid
    AND public.can_review_pro(pro_uid, client_uid)
  );

-- ── avis_pro_contests (contestation par le pro) ────────────────────────────
CREATE TABLE IF NOT EXISTS avis_pro_contests (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  avis_id        UUID REFERENCES avis_pro(id) ON DELETE CASCADE NOT NULL,
  pro_uid        TEXT NOT NULL,
  motif          TEXT NOT NULL,
  explication    TEXT,
  statut         TEXT DEFAULT 'en_attente', -- en_attente | acceptee | refusee
  decision_admin TEXT,
  decide_par     TEXT,
  decide_at      TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_avis_pro_contests_avis ON avis_pro_contests(avis_id);

ALTER TABLE avis_pro_contests ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'avis_pro_contests'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.avis_pro_contests', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "avis_pro_contests_select" ON avis_pro_contests
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
CREATE POLICY "avis_pro_contests_insert" ON avis_pro_contests
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    AND EXISTS (SELECT 1 FROM avis_pro a WHERE a.id = avis_id AND a.pro_uid = (auth.jwt() ->> 'sub'))
  );
CREATE POLICY "avis_pro_contests_update" ON avis_pro_contests
  FOR UPDATE USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('avis_pro','avis_pro_contests')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "avis_pro_insert" ON avis_pro;
-- CREATE POLICY "avis_pro_insert" ON avis_pro
--   FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = client_uid);
-- DROP TABLE IF EXISTS avis_pro_contests;
