-- ─────────────────────────────────────────────────────────────────────────────
-- Table animaux_proprietes
-- Historique de propriété : qui possède (ou a possédé) chaque animal, et quand.
-- date_fin IS NULL  → propriétaire actuel
-- date_fin NOT NULL → ancien propriétaire
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.animaux_proprietes (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id   text        NOT NULL REFERENCES public.animaux(id) ON DELETE CASCADE,
  uid_proprio text        NOT NULL,           -- Firebase UID du propriétaire
  date_debut  date        NOT NULL,
  date_fin    date        DEFAULT NULL,       -- NULL = possède encore aujourd'hui
  created_at  timestamptz DEFAULT now()
);

-- Index performance
CREATE INDEX IF NOT EXISTS idx_ap_animal    ON public.animaux_proprietes(animal_id);
CREATE INDEX IF NOT EXISTS idx_ap_proprio   ON public.animaux_proprietes(uid_proprio);
CREATE INDEX IF NOT EXISTS idx_ap_current   ON public.animaux_proprietes(uid_proprio) WHERE date_fin IS NULL;
CREATE INDEX IF NOT EXISTS idx_ap_animal_dt ON public.animaux_proprietes(animal_id, date_debut);

-- ── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.animaux_proprietes ENABLE ROW LEVEL SECURITY;

-- Lecture : l'utilisateur voit les lignes qui le concernent (proprio ou éleveur d'origine)
CREATE POLICY "animaux_proprietes_select" ON public.animaux_proprietes
  FOR SELECT USING (
    uid_proprio = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.animaux a
      WHERE a.id = animaux_proprietes.animal_id
        AND a.uid_eleveur = auth.uid()::text
    )
  );

-- Écriture : seul l'éleveur d'origine (ou service role) peut insérer/modifier
CREATE POLICY "animaux_proprietes_insert" ON public.animaux_proprietes
  FOR INSERT WITH CHECK (
    uid_proprio = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.animaux a
      WHERE a.id = animaux_proprietes.animal_id
        AND a.uid_eleveur = auth.uid()::text
    )
  );

CREATE POLICY "animaux_proprietes_update" ON public.animaux_proprietes
  FOR UPDATE USING (
    uid_proprio = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.animaux a
      WHERE a.id = animaux_proprietes.animal_id
        AND a.uid_eleveur = auth.uid()::text
    )
  );

-- ── Peuplement initial depuis les données existantes ───────────────────────

-- 1) Pour chaque animal, l'éleveur d'origine est propriétaire depuis la date d'entrée
--    (ou date naissance, ou creation) jusqu'à date_sortie si l'animal est sorti
INSERT INTO public.animaux_proprietes (animal_id, uid_proprio, date_debut, date_fin)
SELECT
  a.id,
  a.uid_eleveur,
  COALESCE(
    a.date_entree::date,
    a.date_naissance::date,
    a.created_at::date,
    CURRENT_DATE
  ) AS date_debut,
  CASE
    WHEN a.statut IN ('sorti', 'en_attente_cession') AND a.date_sortie IS NOT NULL
      THEN a.date_sortie::date
    ELSE NULL
  END AS date_fin
FROM public.animaux a
WHERE a.uid_eleveur IS NOT NULL
  AND a.uid_eleveur != ''
  AND NOT EXISTS (
    SELECT 1 FROM public.animaux_proprietes ap
    WHERE ap.animal_id = a.id AND ap.uid_proprio = a.uid_eleveur
  )
ON CONFLICT DO NOTHING;

-- 2) Pour les animaux cédés avec un acquéreur identifié → nouveau propriétaire
INSERT INTO public.animaux_proprietes (animal_id, uid_proprio, date_debut, date_fin)
SELECT
  a.id,
  a.uid_acquereur,
  COALESCE(a.date_sortie::date, a.created_at::date, CURRENT_DATE) AS date_debut,
  NULL AS date_fin   -- propriétaire actuel
FROM public.animaux a
WHERE a.uid_acquereur IS NOT NULL
  AND a.uid_acquereur != ''
  AND a.statut IN ('sorti', 'en_attente_cession')
  AND NOT EXISTS (
    SELECT 1 FROM public.animaux_proprietes ap
    WHERE ap.animal_id = a.id AND ap.uid_proprio = a.uid_acquereur
  )
ON CONFLICT DO NOTHING;
