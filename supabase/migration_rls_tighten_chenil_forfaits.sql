-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 29/N : chenil_boxes, enclos_chenil, employe_conges,
--   forfaits_garde, forfaits_souscrits
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- chenil_boxes et enclos_chenil avaient déjà une policy « propriétaire »
-- mais écrite avec `auth.uid()` (helper Supabase natif, UUID) au lieu de
-- `auth.jwt() ->> 'sub'` — comme pour pension_entrees (vague 18/N), un
-- compte 100% Firebase n'y correspond jamais : ces policies n'ont jamais
-- réellement protégé ni laissé passer le bon utilisateur. Remplacées, et
-- cogérant actif ajouté (absent de la version d'origine).
--
-- employe_conges (congés) : USING(true) — accessible à l'employé concerné
-- et à l'employeur/cogérant (via la relation employes).
--
-- forfaits_garde : catalogue de prestations du pro, lecture publique
-- conservée (affiché sur la fiche publique), écriture verrouillée
-- pro/cogérant.
--
-- forfaits_souscrits : FOR ALL USING(true) — contient l'usage réel d'un
-- forfait par un client précis (séances consommées), pas public. Réservé
-- pro/cogérant + le client concerné en lecture.
--
-- ⚠️ À TESTER après exécution :
--   1. La gestion des box/enclos (association/élevage) fonctionne
--      normalement pour son propriétaire ET un cogérant actif.
--   2. Les congés d'un employé s'affichent pour lui-même ET pour
--      l'employeur/cogérant ; en déclarer un fonctionne.
--   3. Les forfaits de garde restent visibles sur la fiche publique du
--      pro ; les modifier fonctionne pour le pro/cogérant.
--   4. Un forfait souscrit (séances restantes) s'affiche pour le
--      pro/cogérant ET pour le client concerné.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── chenil_boxes ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Owner chenil_boxes" ON chenil_boxes;
CREATE POLICY "chenil_boxes_owner_or_cogerant" ON chenil_boxes
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = chenil_boxes.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = chenil_boxes.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── enclos_chenil ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Propriétaire enclos" ON enclos_chenil;
CREATE POLICY "enclos_chenil_owner_or_cogerant" ON enclos_chenil
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = enclos_chenil.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = enclos_chenil.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── employe_conges (rattaché via employe_id → employes) ───────────────────
DROP POLICY IF EXISTS "employe_conges_all" ON employe_conges;
CREATE POLICY "employe_conges_related" ON employe_conges
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.id = employe_conges.employe_id
        AND (
          e.uid_eleveur = (auth.jwt() ->> 'sub')
          OR e.uid_employe = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = e.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.id = employe_conges.employe_id
        AND (
          e.uid_eleveur = (auth.jwt() ->> 'sub')
          OR e.uid_employe = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = e.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- ── forfaits_garde (lecture publique conservée) ────────────────────────────
DROP POLICY IF EXISTS "Insert forfaits_garde" ON forfaits_garde;
DROP POLICY IF EXISTS "Update forfaits_garde" ON forfaits_garde;
DROP POLICY IF EXISTS "Delete forfaits_garde" ON forfaits_garde;

CREATE POLICY "forfaits_garde_write" ON forfaits_garde
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = forfaits_garde.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = forfaits_garde.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );
-- Note : "forfaits_garde_write" est FOR ALL, donc s'applique aussi au
-- SELECT — combinée en OR avec "Select forfaits_garde" (USING(true),
-- laissée en place), la lecture reste publique comme avant.

-- ── forfaits_souscrits (pro/cogérant + client concerné) ───────────────────
DROP POLICY IF EXISTS "forfaits_souscrits_all" ON forfaits_souscrits;

CREATE POLICY "forfaits_souscrits_select" ON forfaits_souscrits
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = client_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = forfaits_souscrits.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "forfaits_souscrits_insert" ON forfaits_souscrits
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = forfaits_souscrits.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "forfaits_souscrits_update" ON forfaits_souscrits
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = forfaits_souscrits.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = forfaits_souscrits.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "forfaits_souscrits_delete" ON forfaits_souscrits
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = forfaits_souscrits.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('chenil_boxes','enclos_chenil','employe_conges','forfaits_garde','forfaits_souscrits')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('chenil_boxes','enclos_chenil','employe_conges','forfaits_garde','forfaits_souscrits')
--     AND policyname NOT IN ('Select forfaits_garde')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "Owner chenil_boxes" ON chenil_boxes USING (association_uid = auth.uid()::text) WITH CHECK (association_uid = auth.uid()::text);
-- CREATE POLICY "Propriétaire enclos" ON enclos_chenil USING (uid_eleveur = auth.uid()::text) WITH CHECK (uid_eleveur = auth.uid()::text);
-- CREATE POLICY "employe_conges_all" ON employe_conges FOR ALL USING (true);
-- CREATE POLICY "Insert forfaits_garde" ON forfaits_garde FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);
-- CREATE POLICY "Update forfaits_garde" ON forfaits_garde FOR UPDATE USING (true);
-- CREATE POLICY "Delete forfaits_garde" ON forfaits_garde FOR DELETE USING (true);
-- CREATE POLICY "forfaits_souscrits_all" ON forfaits_souscrits FOR ALL USING (true) WITH CHECK (true);
